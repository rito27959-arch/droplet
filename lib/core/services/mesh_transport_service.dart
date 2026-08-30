// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est le CHEF D'ORCHESTRE de tout le réseau mesh. Il ne parle jamais
// directement Bluetooth, Wi-Fi ou Nearby lui-même — à la place, il dirige
// les TROIS musiciens (`BleMeshTransport`, `LocalWifiTransport`,
// `NativeP2PTransport`, chacun décrit dans son propre fichier) et
// harmonise tout ce qu'ils font :
//
//   - Il fusionne les trois listes de « qui est connecté » en UNE SEULE
//     liste de pairs (un même ami peut être joignable à la fois en
//     Bluetooth ET en Wi-Fi — le chef d'orchestre le sait et choisit le
//     meilleur chemin).
//   - Il surveille la SANTÉ de chaque chemin vers chaque pair : si un
//     chemin échoue plusieurs fois de suite, il arrête de l'utiliser
//     temporairement (comme éviter une route qu'on sait bouchée).
//   - Il adapte la fréquence de recherche selon la batterie et le nombre
//     de pairs autour (chercher moins souvent économise la pile).
//   - Il organise une petite hiérarchie : les « gateway » (passerelles) et
//     « super-peers » forment une colonne vertébrale plus stable du
//     réseau, pendant que les « leaf » (feuilles, les appareils normaux)
//     s'y raccrochent.
// ============================================================================

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'ble_mesh_protocol.dart';
import 'mesh_transport.dart';
import 'mesh_state_machine.dart';
import 'ble_mesh_transport.dart';
import 'local_wifi_transport.dart';
import 'native_p2p_transport.dart';
import '../network/network_manager.dart' as nm;
import '../protocol/droplet_mesh_protocol.dart';
import '../models/mesh_message.dart';
import 'storage_service.dart';

/// Type de transport utilisé pour joindre un pair — par quel « chemin » on
/// peut lui parler.
enum TransportKind { ble, localWifi, nativeP2P, both }

/// Rôle d'un pair dans le mesh hiérarchique.
enum PeerRole {
  /// Pair standard (feuille) — se connecte à des gateway
  leaf,

  /// Passerelle — relaie pour d'autres, peut être super-peer
  gateway,

  /// Super-peer — gateway élue, sert de backbone au mesh
  superPeer,
}

/// Information sur un pair connecté — sa fiche complète telle que le chef
/// d'orchestre la voit, tous transports confondus.
class ConnectedPeer {
  final String peerId;
  final String pseudo;
  final int hopCount;
  final bool isGateway;
  final Set<TransportKind> transports;
  final String platform;
  final PeerRole role;
  final Set<String> interestGroups;
  final double batteryLevel;
  final int connectionScore;

  /// Clé publique X25519 (base64) de ce pair, si déjà échangée.
  final String? publicKey;

  /// Vrai quand ce pair a perdu tous ses liens mais qu'on lui laisse
  /// encore sa chance.
  ///
  /// ⚠️ C'EST CE QUI DISTINGUE « la personne s'est éloignée » de « la
  /// liaison a hoqueté ».
  ///
  /// Sur Android, une connexion Bluetooth se coupe et se rétablit
  /// constamment, pour des raisons qui n'ont rien à voir avec la
  /// distance : le système coupe un GATT inactif, la radio est
  /// réquisitionnée par autre chose, le téléphone met le socket en
  /// veille une seconde. Traiter chacune de ces coupures comme un départ
  /// définitif, c'est ce qui faisait clignoter la liste des pairs et
  /// échouer des envois alors que les deux téléphones étaient posés
  /// côte à côte.
  ///
  /// Un pair dans cet état reste dans la liste, affiché « reconnexion »,
  /// et les messages qui lui sont destinés attendent dans la file au
  /// lieu d'échouer. Il n'est vraiment retiré que si le délai de grâce
  /// s'écoule sans qu'aucun transport ne l'ait revu.
  final bool reconnecting;

  const ConnectedPeer({
    required this.peerId,
    required this.pseudo,
    this.hopCount = 0,
    this.isGateway = false,
    this.transports = const {TransportKind.ble},
    this.platform = 'unknown',
    this.role = PeerRole.leaf,
    this.interestGroups = const {},
    this.batteryLevel = 1.0,
    this.connectionScore = 0,
    this.publicKey,
    this.reconnecting = false,
  });

  /// Fabrique une copie de cette fiche, en changeant seulement ce qu'on
  /// précise.
  ConnectedPeer copyWith({
    String? peerId,
    String? pseudo,
    int? hopCount,
    bool? isGateway,
    Set<TransportKind>? transports,
    String? platform,
    PeerRole? role,
    Set<String>? interestGroups,
    double? batteryLevel,
    int? connectionScore,
    String? publicKey,
    bool? reconnecting,
  }) {
    return ConnectedPeer(
      peerId: peerId ?? this.peerId,
      pseudo: pseudo ?? this.pseudo,
      hopCount: hopCount ?? this.hopCount,
      isGateway: isGateway ?? this.isGateway,
      transports: transports ?? this.transports,
      platform: platform ?? this.platform,
      role: role ?? this.role,
      interestGroups: interestGroups ?? this.interestGroups,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      connectionScore: connectionScore ?? this.connectionScore,
      publicKey: publicKey ?? this.publicKey,
      reconnecting: reconnecting ?? this.reconnecting,
    );
  }
}

/// Santé d'un transport pour un pair donné — un genre de carnet de notes
/// qui dit « est-ce que ce chemin marche bien avec cette personne ? ».
class TransportHealth {
  final int consecutiveFailures;
  final int totalSuccess;
  final DateTime? lastUsed;

  const TransportHealth({
    this.consecutiveFailures = 0,
    this.totalSuccess = 0,
    this.lastUsed,
  });

  TransportHealth copyWith({
    int? consecutiveFailures,
    int? totalSuccess,
    DateTime? lastUsed,
  }) {
    return TransportHealth(
      consecutiveFailures: consecutiveFailures ?? this.consecutiveFailures,
      totalSuccess: totalSuccess ?? this.totalSuccess,
      lastUsed: lastUsed ?? this.lastUsed,
    );
  }

  /// Un score de fiabilité entre 0 (jamais fiable) et 1 (toujours fiable).
  double get reliability {
    final total = consecutiveFailures + totalSuccess;
    if (total == 0) return 1.0;
    return totalSuccess / total;
  }
}

/// Statistiques globales de santé du mesh — un tableau de bord complet
/// pour l'écran « Réseau mesh » de l'app.
class MeshHealth {
  final int totalPeers;
  final int peersOnWifi;
  final int peersOnBle;
  final int peersOnNative;
  final int gatewayCount;
  final int superPeerCount;
  final double averageReliability;
  final int messagesSent;
  final int acksReceived;
  final int failedDeliveries;
  final Map<String, TransportHealth> bleHealth;
  final Map<String, TransportHealth> wifiHealth;
  final Map<String, TransportHealth> nativeHealth;

  const MeshHealth({
    this.totalPeers = 0,
    this.peersOnWifi = 0,
    this.peersOnBle = 0,
    this.peersOnNative = 0,
    this.gatewayCount = 0,
    this.superPeerCount = 0,
    this.averageReliability = 1.0,
    this.messagesSent = 0,
    this.acksReceived = 0,
    this.failedDeliveries = 0,
    this.bleHealth = const {},
    this.wifiHealth = const {},
    this.nativeHealth = const {},
  });
}

/// Configuration de scaling pour le mesh — tous les petits réglages
/// (limites, délais) qui permettent au réseau de bien fonctionner que ce
/// soit avec 2 amis autour ou une foule entière.
class MeshScaleConfig {
  /// Nombre max de connexions directes par appareil
  final int maxDirectConnections;

  /// Nombre max de connexions BLE
  final int maxBleConnections;

  /// Intervalle de beacon Wi-Fi (secondes) quand peu de pairs
  final int wifiBeaconIntervalSparse;

  /// Intervalle de beacon Wi-Fi (secondes) quand beaucoup de pairs
  final int wifiBeaconIntervalDense;

  /// Seuil de densité pour passer en mode dense
  final int densePeerThreshold;

  /// Durée de scan BLE active (secondes)
  final int bleScanDuration;

  /// Durée de pause BLE (secondes) — duty cycle
  final int bleScanPause;

  /// Durée de scan BLE quand batterie faible
  final int bleScanPauseLowBattery;

  /// Timeout de stale peer (secondes)
  final int peerTimeout;

  /// Délai de grâce avant de déclarer un pair réellement parti (secondes).
  ///
  /// ⚠️ CE RÉGLAGE DÉCIDE DE CE QUE L'UTILISATEUR PERÇOIT.
  ///
  /// Trop court, et la moindre coupure Bluetooth — il y en a plusieurs
  /// par minute sur certains téléphones — fait disparaître le contact de
  /// la liste alors qu'il est à un mètre. Trop long, et quelqu'un qui
  /// s'en va vraiment reste affiché comme joignable, ce qui est pire :
  /// on écrit à quelqu'un qui ne recevra rien.
  ///
  /// 45 secondes correspond à ce qu'on observe : les reprises réelles se
  /// font en 2 à 10 secondes, un éloignement définitif ne revient jamais.
  final int reconnectGrace;

  /// TTL par défaut des messages (secondes)
  final int defaultMessageTtl;

  /// Ports d'écoute Wi-Fi
  final int discoveryPort;
  final int dataPort;

  const MeshScaleConfig({
    this.maxDirectConnections = 50,
    this.maxBleConnections = 6,
    this.wifiBeaconIntervalSparse = 5,
    this.wifiBeaconIntervalDense = 30,
    this.densePeerThreshold = 20,
    this.bleScanDuration = 10,
    this.bleScanPause = 30,
    this.bleScanPauseLowBattery = 60,
    this.peerTimeout = 30,
    this.reconnectGrace = 45,
    this.defaultMessageTtl = 3600,
    this.discoveryPort = 42069,
    this.dataPort = 42070,
  });

  static const MeshScaleConfig defaultConfig = MeshScaleConfig();
}

/// Routeur de transport unifié scalable à 10M utilisateurs.
///
/// ## Hiérarchie
/// Les pairs sont organisés en feuilles (leaf), passerelles (gateway) et
/// super-peers. Chaque appareil connecte max [maxDirectConnections] pairs
/// simultanément. Les gateway forment un backbone, les feuilles se
/// connectent aux gateway les plus proches.
///
/// ## Groupes d'intérêt
/// Les messages sont taggés par série, matière, région. Seuls les pairs
/// abonnés à un groupe reçoivent les messages de ce groupe. Réduction
/// drastique du bruit à l'échelle.
///
/// ## Scanning adaptatif
/// BLE et Wi-Fi ajustent leur intervalle selon :
/// - La densité de pairs détectés
/// - Le niveau de batterie
/// - L'état foreground/background
/// - La présence d'alternatives Wi-Fi
class MeshTransportService {
  /// Les trois musiciens que ce chef d'orchestre dirige.
  ///
  /// ── POURQUOI ILS SONT INJECTABLES ────────────────────────────────
  ///
  /// Par défaut, ce sont les vraies radios. Mais le constructeur accepte
  /// de les remplacer, et c'est ce qui rend le maillage MESURABLE.
  ///
  /// Tant que ce service fabriquait lui-même ses trois transports, la
  /// seule façon de vérifier son comportement était de disposer de
  /// vrais téléphones : impossible de simuler vingt nœuds, 5 % de perte,
  /// ou une coupure au milieu d'une synchronisation. On ne pouvait donc
  /// affirmer aucune amélioration chiffrée — seulement constater que
  /// « ça a l'air de marcher ».
  ///
  /// Avec ce point d'injection, un `FauxTransport` prend leur place et
  /// le maillage complet tourne dans un test, en quelques
  /// millisecondes, de façon reproductible.
  MeshTransportService({
    MeshTransport? bleTransport,
    MeshTransport? wifiTransport,
    MeshTransport? nativeTransport,
  })  : _bleTransport = bleTransport ?? BleMeshTransport(),
        _wifiTransport = wifiTransport ?? LocalWifiTransport(),
        _nativeTransport = nativeTransport ?? NativeP2PTransport();

  final MeshTransport _bleTransport;
  final MeshTransport _wifiTransport;
  final MeshTransport _nativeTransport;

  /// Le « cerveau réseau » v2 : heartbeats, health checks, reconnexion et
  /// failover globaux. C'est lui qui détient le [DropletMeshProtocol]
  /// (routage adaptatif + congestion AIMD + dedup) ; le transport le nourrit
  /// en événements (connexions, santé des liens) et s'en sert pour choisir
  /// les chemins les plus sains.
  nm.NetworkManager? _networkManager;

  nm.NetworkManager get networkManager => _networkManager!;
  DropletMeshProtocol get protocol => _networkManager!.protocol;

  MeshScaleConfig _config = MeshScaleConfig.defaultConfig;

  MeshScaleConfig get config => _config;

  /// Changer la configuration remet aussi le délai de grâce à sa nouvelle
  /// valeur : sans cela, une config posée après coup (les tests, ou un
  /// réglage utilisateur) resterait sans effet jusqu'au prochain
  /// recalcul automatique, quinze secondes plus tard.
  set config(MeshScaleConfig value) {
    _config = value;
    _graceEffective = value.reconnectGrace;
  }

  bool _isRunning = false;
  String _myId = '';
  String _myPseudo = '';
  PeerRole _myRole = PeerRole.leaf;
  double _batteryLevel = 1.0;
  bool _isInForeground = true;

  /// Abonnements aux transports — annulés au stopMesh() pour éviter les fuites.
  final List<StreamSubscription<dynamic>> _transportSubs = [];

  /// Correspondance entre les IDs Nearby (MAC) et les IDs Droplet (crypto).
  /// NativeP2P utilise des IDs matériels, tandis que BLE/WiFi échangent
  /// les vrais IDs crypto. Cette table permet de faire le pont.
  final Map<String, String> _nearbyToDropletId = {};
  final Map<String, String> _dropletToNearbyId = {};

  final Map<String, ConnectedPeer> _peers = {};
  final Map<String, Map<TransportKind, TransportHealth>> _transportHealth = {};

  /// Dernière fois qu'un pair a donné signe de présence (beacon/scan/connexion
  /// sur N'IMPORTE QUEL transport) — distinct de [_transportHealth], qui ne
  /// suit que la fiabilité des envois actifs et reste vide tant qu'aucun
  /// message n'a été envoyé à ce pair précis. Utiliser _transportHealth pour
  /// décider qu'un pair est parti évinçait des pairs toujours bien présents
  /// simplement parce qu'on ne leur avait rien envoyé récemment.
  final Map<String, DateTime> _lastSeenAt = {};

  /// Jusqu'à quand on garde un pair sans lien avant de le déclarer parti.
  /// Voir `MeshScaleConfig.reconnectGrace`.
  final Map<String, DateTime> _graceUntil = {};

  /// Garde-fou anti-flood entrant : par pair, on compte les paquets dans
  /// une fenêtre glissante de 1 seconde. Un appareil qui dépasse le seuil
  /// (bug en boucle, relais détraqué, ou attaque) est écarté temporairement
  /// — sinon il saturerait la file de traitement et le CPU de CHAQUE voisin.
  final Map<String, _IngressWindow> _ingressWindows = {};
  static const int _ingressMaxPerSecond = 150;
  static const int _ingressWindowsCap = 512;
  DateTime _lastFloodLog = DateTime.fromMillisecondsSinceEpoch(0);

  /// Gateways connus dans le mesh (backbone)
  final Map<String, ConnectedPeer> _knownGateways = {};

  /// Table persistante des pairs connus (load au démarrage, save périodique)
  List<PeerRecord> _knownPeerRecords = [];

  /// Abonnements aux groupes d'intérêt
  final Set<String> _myInterestGroups = {};

  int _totalSent = 0;
  int _totalAcks = 0;
  int _totalFailed = 0;
  int _peersEverSeen = 0;

  final _peerEventsCtrl = StreamController<ConnectedPeer>.broadcast();
  final _incomingDataCtrl = StreamController<MeshIncomingData>.broadcast();
  final _healthCtrl = StreamController<MeshHealth>.broadcast();

  Stream<ConnectedPeer> get peerEvents => _peerEventsCtrl.stream;
  Stream<MeshIncomingData> get incomingData => _incomingDataCtrl.stream;
  Stream<MeshHealth> get healthEvents => _healthCtrl.stream;

  int get connectedPeerCount => _peers.length;

  /// Nombre de pairs réellement joignables MAINTENANT — exclut ceux « en
  /// grâce » ([ConnectedPeer.reconnecting]) dont le lien est tombé mais
  /// qu'on garde encore un instant dans l'espoir d'une reconnexion :
  /// aucun paquet ne peut passer par eux tant qu'ils sont dans cet état
  /// (même logique déjà appliquée manuellement dans `_annoncerRoutes`).
  int get activePeerCount =>
      _peers.values.where((p) => !p.reconnecting).length;

  // ── ÉTAT GLOBAL DU RÉSEAU ────────────────────────────────────────
  //
  // Un seul mot pour dire où en est l'appareil, recalculé à partir de
  // l'état des trois radios et du nombre de pairs. Voir
  // `mesh_state_machine.dart` pour la raison d'être de cette pièce : sans
  // elle, personne ne savait qu'il n'y avait plus de réseau, et la
  // balise Wi-Fi partait dans le vide toutes les trois secondes.
  final MeshStateMachine stateMachine = MeshStateMachine();

  MeshNetworkState get networkState => stateMachine.state;
  Stream<MeshStateTransition> get networkTransitions =>
      stateMachine.transitions;

  /// Recalcule l'état global. À appeler quand la situation change —
  /// jamais en boucle : la machine ne signale que les vraies
  /// transitions, mais l'appeler pour rien reste du travail inutile.
  void _refreshNetworkState({bool syncing = false}) {
    final etats = transportStates();

    // « Qualité insuffisante » = il ne reste que le Bluetooth. Les
    // messages texte passent, mais ni les fichiers ni la voix — c'est
    // exactement ce que `degraded` doit signifier à l'utilisateur.
    final bonChemin = etats.entries.any((e) =>
        e.key != 'ble' && e.value == TransportState.active);

    stateMachine.update(
      transports: etats,
      connectedPeers: _peers.length,
      syncing: syncing,
      qualityOk: bonChemin,
    );
  }
  List<ConnectedPeer> get connectedPeers => _peers.values.toList();
  List<ConnectedPeer> get knownGateways => _knownGateways.values.toList();
  int get peersEverSeen => _peersEverSeen;

  int get blePeerCount =>
      _peers.values.where((p) => p.transports.contains(TransportKind.ble)).length;
  int get wifiPeerCount =>
      _peers.values.where((p) => p.transports.contains(TransportKind.localWifi)).length;
  int get nativePeerCount =>
      _peers.values.where((p) => p.transports.contains(TransportKind.nativeP2P)).length;
  int get gatewayCount =>
      _peers.values.where((p) => p.isGateway).length;
  int get superPeerCount =>
      _peers.values.where((p) => p.role == PeerRole.superPeer).length;

  static const int maxFailuresBeforeExclude = 3;

  /// Intervalle de beacon Wi-Fi actuel (s'adapte à la densité)
  int _currentWifiBeaconInterval = 5;

  // ── Cycle de vie ─────────────────────────────────────────────────────────

  /// Demande explicitement les permissions Android nécessaires à la
  /// découverte de pairs (Bluetooth + Wi-Fi/localisation), au lieu de
  /// compter uniquement sur `NativeP2P` — son propre
  /// `android?.requestPermissions()` (nearby_service) reste bloqué
  /// indéfiniment sur cet appareil (jamais résolu, coupé après coup par le
  /// timeout de 8s dans `Future.wait` ci-dessous), ce qui fait que
  /// ACCESS_FINE_LOCATION/ACCESS_COARSE_LOCATION/NEARBY_WIFI_DEVICES ne sont
  /// jamais réellement demandées ni accordées — confirmé via
  /// `dumpsys package` (BLUETOOTH_* accordées, les trois autres non). Sans
  /// elles, la découverte Wi-Fi (mDNS/NsdManager, Wi-Fi Direct) échoue
  /// silencieusement même quand le Bluetooth fonctionne. Demandées ici, en
  /// amont et indépendamment, avant que quoi que ce soit n'en dépende.
  ///
  /// En clair : Android demande la permission avant de laisser l'app
  /// chercher des appareils autour d'elle (comme demander la permission à
  /// un parent avant de sortir jouer dehors) — cette fonction s'assure que
  /// la demande est bien posée, plutôt que de compter sur un système tiers
  /// qui, sur cet appareil, ne posait jamais vraiment la question.
  Future<void> _requestCorePermissions() async {
    if (!Platform.isAndroid) return;
    try {
      final statuses = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect,
        Permission.bluetoothAdvertise,
        Permission.locationWhenInUse,
        Permission.nearbyWifiDevices,
      ].request();
      debugPrint('[MeshService] permissions: '
          '${statuses.map((p, s) => MapEntry(p.toString(), s.toString()))}');
    } catch (e) {
      debugPrint('[MeshService] échec demande permissions: $e');
    }
  }

  /// Démarre le mesh avec les paramètres de scaling : demande les
  /// permissions, allume les trois transports EN MÊME TEMPS, puis lance
  /// toutes les tâches de fond (adaptation, nettoyage, sauvegarde).
  Future<void> startMesh(
    String myId,
    String myPseudo, {
    PeerRole role = PeerRole.leaf,
    Set<String>? interestGroups,
    MeshScaleConfig? config,
  }) async {
    if (_isRunning) return;
    _isRunning = true;
    _myId = myId;
    _myPseudo = myPseudo;
    _myRole = role;
    if (config != null) this.config = config;
    if (interestGroups != null) _myInterestGroups.addAll(interestGroups);

    debugPrint('[MeshService] startMesh() id=$myId role=$role groups=$interestGroups');

    // Cerveau réseau v2 : démarre les heartbeats (5s), health checks (30s)
    // et le pruning des routes (20s). Un seul appel est possible (le
    // NetworkManager n'est pas idempotent — re-initer doublerait les timers).
    _networkManager ??= nm.NetworkManager(
      myId: myId,
      onPeerUpdate: (event) => debugPrint('[MeshService] net event: $event'),
      onReconnectRequest: _onNetworkReconnectRequest,
    )..init();

    await _requestCorePermissions();

    // On s'abonne à ce que racontent les trois transports AVANT de les
    // démarrer, pour ne rater aucun de leurs premiers événements.
    _transportSubs.addAll([
      _bleTransport.peerEvents.listen(_onBlePeerEvent, onError: (e) => debugPrint('[MeshService] BLE peer event error: $e')),
      _bleTransport.incomingData.listen(_onIncomingData, onError: (e) => debugPrint('[MeshService] BLE incoming error: $e')),
      _wifiTransport.peerEvents.listen(_onWifiPeerEvent, onError: (e) => debugPrint('[MeshService] WiFi peer event error: $e')),
      _wifiTransport.incomingData.listen(_onIncomingData, onError: (e) => debugPrint('[MeshService] WiFi incoming error: $e')),
      _nativeTransport.peerEvents.listen(_onNativePeerEvent, onError: (e) => debugPrint('[MeshService] Native peer event error: $e')),
      _nativeTransport.incomingData.listen(_onIncomingData, onError: (e) => debugPrint('[MeshService] Native incoming error: $e')),
    ]);

    // Les trois transports démarrent EN MÊME TEMPS (pas l'un après
    // l'autre) pour gagner du temps — chacun a droit à 8 secondes max ;
    // si l'un est lent ou plante, ça n'empêche pas les deux autres de
    // fonctionner quand même.
    await Future.wait([
      _startTransport('BLE', () => _bleTransport.start(myId, myPseudo)),
      _startTransport('WiFi', () => _wifiTransport.start(myId, myPseudo)),
      _startTransport('NativeP2P', () => _nativeTransport.start(myId, myPseudo)),
    ]);

    _startAdaptiveBeaconing();
    _startStalePeerCleanup();
    _startContributionTracking();

    if (role == PeerRole.gateway || role == PeerRole.superPeer) {
      _announceGatewayPresence();
    }

    _loadKnownPeers();
    _startPeerPersistence();

    debugPrint('[MeshService] startMesh() completed, knownPeers=${_knownPeerRecords.length}');
  }

  /// Démarre un transport, et RÉESSAIE s'il échoue.
  ///
  /// ⚠️ La reprise n'est pas un luxe : sans elle, un transport qui rate
  /// son démarrage reste éteint jusqu'à la prochaine ouverture de l'app.
  ///
  /// C'est exactement ce qui se produisait avec le Bluetooth. Sur un
  /// téléphone réel, l'adaptateur met parfois plus de huit secondes à
  /// répondre — parce qu'il vient d'être rallumé, parce qu'une autre
  /// application l'occupe, ou simplement parce que le système est chargé
  /// au lancement. Le délai était dépassé, l'erreur consignée dans le
  /// journal, et plus personne n'y revenait :
  ///
  ///     [MeshService] BLE start error: TimeoutException after 8 s
  ///     [MeshService] startMesh() completed, knownPeers=0
  ///
  /// L'utilisateur se retrouvait avec une app qui ne voyait personne,
  /// sans aucune indication de la raison.
  ///
  /// Les tentatives s'espacent (4 s, 8 s, 16 s, 32 s) et s'arrêtent au
  /// bout de cinq essais : au-delà, ce n'est plus un contretemps mais un
  /// matériel indisponible ou une permission refusée — insister ne
  /// ferait que vider la batterie.
  Future<void> _startTransport(
    String name,
    Future<void> Function() start, {
    int attempt = 1,
  }) async {
    const maxAttempts = 5;
    try {
      await start().timeout(const Duration(seconds: 8));
      if (attempt > 1) {
        debugPrint('[MeshService] $name démarré à la tentative $attempt');
      }
    } catch (e) {
      debugPrint('[MeshService] $name start error (tentative $attempt): $e');
      if (attempt >= maxAttempts) {
        debugPrint('[MeshService] $name abandonné après $maxAttempts essais');
        return;
      }
      final delay = Duration(seconds: 2 << attempt);
      _restartTimers[name]?.cancel();
      _restartTimers[name] = Timer(delay, () {
        if (!_isRunning) return;
        unawaited(_startTransport(name, start, attempt: attempt + 1));
      });
    }
  }

  /// Les reprises programmées, pour pouvoir les annuler à l'arrêt.
  final Map<String, Timer> _restartTimers = {};

  /// Comptabilise les minutes passées en rôle relais (gateway/superPeer)
  /// pour l'économie de contribution — récompense les appareils qui restent
  /// disponibles pour relayer les autres, indépendamment de l'usage actif.
  Timer? _contributionTimer;

  void _startContributionTracking() {
    _contributionTimer?.cancel();
    _contributionTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (_myRole == PeerRole.gateway || _myRole == PeerRole.superPeer) {
        unawaited(StorageService.addGatewayMinutes(1));
      }
    });
  }

  /// Éteint tout, proprement : arrête toutes les tâches de fond, sauvegarde
  /// une dernière fois la liste des pairs connus, puis éteint les trois
  /// transports.
  Future<void> stopMesh() async {
    _isRunning = false;
    _adaptiveBeaconTimer?.cancel();
    _stalePeerTimer?.cancel();
    _gatewayAnnounceTimer?.cancel();
    _contributionTimer?.cancel();
    _peerPersistTimer?.cancel();
    // Les reprises de démarrage en attente : sans cette annulation, un
    // transport pourrait se rallumer plusieurs secondes APRÈS l'arrêt du
    // mesh, et se retrouver actif alors que tout le reste est éteint.
    for (final timer in _restartTimers.values) {
      timer.cancel();
    }
    _restartTimers.clear();
    stateMachine.markStopped();
    _networkManager?.dispose();
    _networkManager = null;
    for (final sub in _transportSubs) {
      sub.cancel();
    }
    _transportSubs.clear();
    _persistKnownPeers();
    await Future.wait([
      _bleTransport.stop(),
      _wifiTransport.stop(),
      _nativeTransport.stop(),
    ]);
    _peers.clear();
    _knownGateways.clear();
    _lastSeenAt.clear();
    _graceUntil.clear();
  }

  /// Met à jour le niveau de batterie (0.0 - 1.0).
  void updateBatteryLevel(double level) {
    _batteryLevel = level;
    _adjustScanRate();
  }

  /// Met à jour l'état foreground/background.
  void setForegroundState(bool isForeground) {
    _isInForeground = isForeground;
    _adjustScanRate();
  }

  /// Ajoute ou retire des groupes d'intérêt.
  void setInterestGroups(Set<String> groups) {
    _myInterestGroups.clear();
    _myInterestGroups.addAll(groups);
  }

  /// Met à jour la clé publique connue d'un pair (après échange de clés).
  ///
  /// Met aussi à jour la fiche PERSISTÉE : la clé est le « cadenas » du pair,
  /// elle doit survivre aux déconnexions/reconnexions ET aux redémarrages de
  /// l'app — sinon on retombe sur des messages illisibles à la reconnexion.
  void updatePeerPublicKey(String peerId, String publicKey) {
    final existing = _peers[peerId];
    if (existing != null) {
      _peers[peerId] = existing.copyWith(publicKey: publicKey);
    }
    final rec = StorageService.getPeerRecord(peerId);
    // Cet appel ne sert QU'À enregistrer une clé publique. Il ne connaît
    // pas le pseudo du pair et ne doit surtout pas en inventer un : voir
    // `_vraiPseudo`. On garde ce qui existe, sinon l'identifiant — que
    // l'affichage saura reconnaître comme « nom inconnu ».
    final nom = _vraiPseudo(rec?.pseudo, peerId) ??
        _vraiPseudo(existing?.pseudo, peerId) ??
        peerId;
    StorageService.upsertPeer(PeerRecord(
      peerId: peerId,
      pseudo: nom,
      role: rec?.role ?? 'leaf',
      transports: rec?.transports ?? const [],
      platform: rec?.platform ?? 'unknown',
      interestGroups: rec?.interestGroups ?? const [],
      reliability: rec?.reliability ?? 1.0,
      lastSeen: rec?.lastSeen ?? DateTime.now(),
      totalMessagesExchanged: rec?.totalMessagesExchanged ?? 0,
      publicKey: publicKey,
      verified: rec?.verified ?? false,
      verifiedPublicKey: rec?.verifiedPublicKey,
    ));
  }

  /// Définit le rôle de ce pair.
  void setRole(PeerRole role) {
    _myRole = role;
    if (_isRunning && (role == PeerRole.gateway || role == PeerRole.superPeer)) {
      _announceGatewayPresence();
    }
  }

  // ── Scanning adaptatif ──────────────────────────────────────────────────
  //
  // Chercher des appareils autour de soi consomme de la batterie — donc on
  // ne cherche pas toujours à la même vitesse : plus il y a de pairs
  // autour, ou plus la batterie est faible, plus on ralentit la cadence.

  Timer? _adaptiveBeaconTimer;
  Timer? _stalePeerTimer;
  Timer? _gatewayAnnounceTimer;

  void _startAdaptiveBeaconing() {
    _adaptiveBeaconTimer?.cancel();
    _adaptiveBeaconTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      _adjustScanRate();
    });
  }

  /// Recalcule à quelle vitesse on doit chercher/s'annoncer, selon le
  /// nombre de pairs autour, si l'app est au premier plan, et le niveau de
  /// batterie.
  void _adjustScanRate() {
    final peerCount = _peers.length;

    // Ajuster intervalle beacon Wi-Fi selon densité
    if (peerCount >= config.densePeerThreshold) {
      _currentWifiBeaconInterval = config.wifiBeaconIntervalDense;
    } else {
      _currentWifiBeaconInterval = config.wifiBeaconIntervalSparse;
    }

    // En background et batterie faible : réduire drastiquement
    if (!_isInForeground && _batteryLevel < 0.2) {
      _currentWifiBeaconInterval = _currentWifiBeaconInterval * 4;
    } else if (!_isInForeground) {
      _currentWifiBeaconInterval = _currentWifiBeaconInterval * 2;
    }

    // ⚠️ ET ON L'APPLIQUE VRAIMENT.
    //
    // Cette valeur était calculée toutes les quinze secondes depuis
    // toujours… puis simplement affichée dans le journal. Le transport
    // Wi-Fi gardait sa balise fixe de trois secondes, quelle que soit la
    // batterie et même application fermée. Toute l'adaptation décrite
    // par cette méthode était donc, en pratique, décorative.
    // Réglage propre au Wi-Fi local, protégé pour la même raison que les
    // deux autres : la notion de « balise » n'existe pas en Bluetooth.
    final wifi = _wifiTransport;
    if (wifi is LocalWifiTransport) {
      wifi.setBeaconInterval(Duration(seconds: _currentWifiBeaconInterval));
    }

    // Même chose côté Bluetooth : la durée de scan et la pause étaient
    // configurables depuis toujours et n'étaient lues nulle part — la
    // radio cherchait donc en continu, quelle que soit la batterie.
    //
    // La pause s'allonge quand la batterie faiblit. On ne touche PAS à la
    // durée de recherche elle-même : la raccourcir ferait manquer des
    // pairs, alors qu'espacer les recherches ne fait que retarder une
    // découverte.
    // ⚠️ Réglage PROPRE au Bluetooth : il ne figure pas au contrat
    // `MeshTransport`, et c'est voulu — le rythme d'un cycle de scan BLE
    // n'a aucun sens pour un socket TCP. On vérifie donc à qui on parle
    // avant de le demander, plutôt que d'imposer aux autres transports
    // une méthode qu'ils devraient laisser vide.
    final ble = _bleTransport;
    if (ble is BleMeshTransport) {
      ble.setScanCycle(
      duree: Duration(seconds: config.bleScanDuration),
      pause: Duration(
        seconds: _batteryLevel < 0.2
            ? config.bleScanPauseLowBattery
            : config.bleScanPause,
      ),
    );
    }

    // Le délai de grâce doit rester COHÉRENT avec la cadence des
    // balises. Sinon, ralentir les balises pour économiser la batterie
    // se paierait par des pairs déclarés perdus alors qu'ils sont là —
    // exactement le défaut qu'on vient de corriger, réintroduit par la
    // porte de derrière. On garde de quoi manquer trois annonces, avec un
    // plancher à la valeur configurée.
    final graceMini = _currentWifiBeaconInterval * 3;
    _graceEffective =
        graceMini > config.reconnectGrace ? graceMini : config.reconnectGrace;

    debugPrint('[MeshService] adapt beacon: ${_currentWifiBeaconInterval}s '
        'grâce=${_graceEffective}s peers=$peerCount '
        'bg=${!_isInForeground} bat=${(_batteryLevel * 100).round()}%');
  }

  /// Le délai de grâce réellement appliqué — voir `_adjustScanRate`.
  int _graceEffective = MeshScaleConfig.defaultConfig.reconnectGrace;

  /// Toutes les 10 secondes, vérifie si des pairs n'ont plus donné signe
  /// de vie depuis trop longtemps (`config.peerTimeout`) et les retire
  /// proprement de la liste.
  void _startStalePeerCleanup() {
    _stalePeerTimer?.cancel();
    _stalePeerTimer =
        Timer.periodic(const Duration(seconds: 10), (_) => sweepPeers());
  }

  /// Un passage de balai : retire les pairs dont la grâce est écoulée, et
  /// ceux qui n'ont plus donné signe de vie depuis `config.peerTimeout`.
  ///
  /// Extrait du minuteur pour être appelable directement par les tests :
  /// vérifier une logique de délai en attendant réellement quarante-cinq
  /// secondes rendrait la suite de tests inutilisable.
  @visibleForTesting
  void sweepPeers({DateTime? maintenant}) {
    {
      final now = maintenant ?? DateTime.now();
      _peers.removeWhere((id, peer) {
        // ── Fin du délai de grâce ────────────────────────────────────
        //
        // Le pair avait perdu tous ses liens et on lui laissait sa
        // chance (voir `_updatePeer`). Le temps est écoulé sans qu'aucun
        // transport ne l'ait revu : cette fois, il est vraiment parti —
        // c'est le cas de quelqu'un qui s'éloigne hors de portée.
        final grace = _graceUntil[id];
        if (grace != null) {
          if (now.isBefore(grace)) return false; // on patiente encore
          debugPrint('[MeshService] grâce écoulée, pair perdu: $id');
          _graceUntil.remove(id);
          _lastSeenAt.remove(id);
          _transportHealth.remove(id);
          _networkManager?.unregisterPeer(id);
          _peerEventsCtrl.add(peer.copyWith(transports: const {}));
          return true;
        }

        // On se base sur la dernière présence vue sur N'IMPORTE QUEL
        // transport (_lastSeenAt), pas sur _transportHealth (qui ne reflète
        // que les envois actifs et évinçait des pairs toujours connectés
        // simplement parce qu'aucun message ne leur avait été envoyé dans
        // la fenêtre de config.peerTimeout).
        final last = _lastSeenAt[id];
        if (last == null) return false;
        if (now.difference(last).inSeconds > config.peerTimeout) {
          debugPrint('[MeshService] stale peer removed: $id');
          _lastSeenAt.remove(id);
          _graceUntil.remove(id);
          _networkManager?.unregisterPeer(id);
          _peerEventsCtrl.add(peer.copyWith());
          return true;
        }
        return false;
      });
    }

    // Le dernier pair vient peut-être de disparaître : l'état passe
    // alors de « connecté » à « en recherche ».
    _refreshNetworkState();
  }

  /// Signale qu'un pair vient d'être vu / perdu sur un transport.
  ///
  /// Réservé aux tests : c'est le seul moyen d'exercer la logique de
  /// grâce sans allumer une vraie radio Bluetooth.
  @visibleForTesting
  void debugSignalerPair(
    String peerId, {
    required TransportKind transport,
    required bool connecte,
    String pseudo = 'Test',
  }) =>
      _updatePeer(peerId, pseudo, 0, false, transport, connecte);

  /// Toutes les minutes, si on joue le rôle de passerelle, on redit qu'on
  /// est là pour que le reste du réseau puisse s'appuyer sur nous.
  void _announceGatewayPresence() {
    _gatewayAnnounceTimer?.cancel();
    _gatewayAnnounceTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!_isRunning) return;
      debugPrint('[MeshService] gateway $_myId/$_myPseudo role=$_myRole presence announced');
      // Diffuser la présence gateway aux pairs connectés
      _peers.values.where((p) => p.isGateway).forEach((gw) {
        debugPrint('[MeshService] known gateway: ${gw.peerId}');
      });
    });
  }

  /// Recharge la liste des pairs déjà rencontrés par le passé, sauvegardée
  /// dans le classeur permanent (`storage_service.dart`).
  ///
  /// Restaure aussi `_lastSeenAt` pour que le mécanisme de « stale peer »
  /// fonctionne dès le démarrage : sans cette restauration, tous les pairs
  /// connus apparaissaient comme « jamais vus » et étaient immédiatement
  /// écartés par `sweepPeers`, même s'ils avaient été vus il y a une seconde
  /// au dernier arrêt de l'app.
  void _loadKnownPeers() {
    _knownPeerRecords = StorageService.getKnownPeers();
    for (final r in _knownPeerRecords) {
      _lastSeenAt[r.peerId] = r.lastSeen;
    }
    debugPrint('[MeshService] loaded ${_knownPeerRecords.length} known peers '
        '(${_lastSeenAt.length} avec lastSeen restauré)');
    for (final r in _knownPeerRecords.where((p) => p.role == 'gateway' || p.role == 'superPeer')) {
      debugPrint('[MeshService] known gateway: ${r.peerId} (${r.pseudo}) last seen: ${r.lastSeen}');
    }
  }

  Timer? _peerPersistTimer;

  /// Toutes les 30 secondes, sauvegarde la liste actuelle des pairs
  /// connus, pour ne pas tout perdre si l'app redémarre.
  void _startPeerPersistence() {
    _peerPersistTimer?.cancel();
    _peerPersistTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!_isRunning) return;
      _persistKnownPeers();
    });
  }

  void _persistKnownPeers() {
    // On part des records DÉJÀ ENREGISTRÉS pour préserver les champs
    // qui ne vivent que dans la table persistante (publicKey, verified,
    // verifiedPublicKey). Sans ça, chaque cycle de sauvegarde écrasait
    // la clé publique d'un pair par null — perdant le cadenas de
    // chiffrement et forçant un nouvel échange de clés à la prochaine
    // reconnexion.
    final existingMap = <String, PeerRecord>{
      for (final r in StorageService.getKnownPeers()) r.peerId: r,
    };

    final records = <PeerRecord>[];
    for (final peer in _peers.values) {
      final health = _transportHealth[peer.peerId];
      final reliability = health?.values.fold(0.0, (sum, h) => sum + h.reliability) ?? 1.0;
      final count = health?.values.fold(0, (sum, h) => sum + h.totalSuccess) ?? 0;
      final existing = existingMap[peer.peerId];
      records.add(PeerRecord(
        peerId: peer.peerId,
        pseudo: peer.pseudo,
        role: peer.role.name,
        transports: peer.transports.map((t) => t.name).toList(),
        platform: peer.platform,
        interestGroups: peer.interestGroups.toList(),
        reliability: reliability,
        lastSeen: DateTime.now(),
        totalMessagesExchanged: (existing?.totalMessagesExchanged ?? 0) + count,
        // ⚠️ C'est ICI que se jouait le bug des messages illisibles
        // après déconnexion : la clé publique n'était jamais conservée
        // car le record n'en tenait pas compte.
        publicKey: peer.publicKey ?? existing?.publicKey,
        verified: existing?.verified ?? false,
        verifiedPublicKey: existing?.verifiedPublicKey,
      ));
    }

    // Conserver les records de pairs qu'on ne voit plus mais qu'on a
    // déjà rencontrés — pour garder leur clé publique disponible si on
    // les recroise (reconnexion instantanée sans nouvel échange de clés).
    for (final entry in existingMap.entries) {
      if (!records.any((r) => r.peerId == entry.key)) {
        records.add(entry.value);
      }
    }

    _knownPeerRecords = records;
    StorageService.savePeers(records);
  }

  // ── Gestion des pairs ────────────────────────────────────────────────────
  //
  // C'est ici que le chef d'orchestre FUSIONNE ce que racontent
  // séparément le Bluetooth, le Wi-Fi et le Nearby, en une seule fiche par
  // personne — un même ami peut apparaître comme « joignable en
  // Bluetooth » ET « joignable en Wi-Fi » sur la même fiche.

  void _onBlePeerEvent(MeshPeerEvent event) {
    _mergeOrRegisterPeer(event.peerId, event.pseudo, event.hopCount,
        event.isGateway, TransportKind.ble, event.isConnected,
        platform: event.platform);
  }

  void _onWifiPeerEvent(MeshPeerEvent event) {
    _mergeOrRegisterPeer(event.peerId, event.pseudo, event.hopCount,
        event.isGateway, TransportKind.localWifi, event.isConnected);
  }

  // ⚠️ Correction importante (bug d'identité à l'échelle) : ces trois
  // gestionnaires d'événements essayaient auparavant de deviner que « deux
  // pairs avec le même pseudo affiché sont sûrement le même appareil vu
  // par deux transports différents », et fusionnaient alors leurs fiches.
  // C'était une béquille pour NativeP2P, qui ne parlait pas encore son vrai
  // identifiant Droplet à ce moment-là (voir `native_p2p_transport.dart`).
  // Problème : le pseudo est juste un nom choisi par l'utilisateur, JAMAIS
  // garanti unique — dès qu'un mesh compte beaucoup de monde (une salle de
  // classe, un événement, et a fortiori à l'échelle de millions
  // d'utilisateurs), deux personnes DIFFÉRENTES portant le même prénom
  // finissaient fusionnées en une seule fiche : mauvaise clé de
  // chiffrement, mauvais routage, appels dirigés vers la mauvaise
  // personne. Ça marchait « par chance » avec 2 utilisateurs de test aux
  // pseudos différents, mais cassait dès que le réseau grossissait. Les
  // trois transports (BLE, Wi-Fi local, Nearby) font maintenant chacun
  // une vraie poignée de main qui révèle le VRAI identifiant Droplet dès
  // la connexion — cette béquille par pseudo n'est plus nécessaire, et on
  // la retire pour ne plus jamais risquer de mélanger deux identités.

  void _onNativePeerEvent(MeshPeerEvent event) {
    _updatePeer(event.peerId, event.pseudo, event.hopCount, event.isGateway,
        TransportKind.nativeP2P, event.isConnected, platform: event.platform);
  }

  /// Applique l'événement de pair BLE/Wi-Fi tel quel — les deux transports
  /// annoncent déjà leur vrai identifiant Droplet via leur propre poignée
  /// de main, aucune réconciliation par pseudo n'est nécessaire.
  void _mergeOrRegisterPeer(
    String dropletId, String pseudo, int hopCount, bool isGateway,
    TransportKind transport, bool connected, {
    String platform = 'unknown',
  }) {
    _updatePeer(dropletId, pseudo, hopCount, isGateway, transport, connected,
        platform: platform);
  }

  /// Enregistre la correspondance entre un ID Nearby (MAC) et un ID Droplet
  /// (crypto). Migre le peer existant sous l'ID Nearby vers l'ID Droplet.
  void registerPeerIdMapping(String dropletId, String nearbyId) {
    if (dropletId == nearbyId) return;
    _nearbyToDropletId[nearbyId] = dropletId;
    _dropletToNearbyId[dropletId] = nearbyId;
    final nativePeer = _peers.remove(nearbyId);
    if (nativePeer != null) {
      final existing = _peers[dropletId];
      if (existing != null) {
        _peers[dropletId] = existing.copyWith(
          transports: {...existing.transports, ...nativePeer.transports},
        );
      } else {
        _peers[dropletId] = nativePeer.copyWith(peerId: dropletId);
      }
    }
  }

  /// Met à jour (ou crée, ou supprime) la fiche d'un pair suite à un
  /// événement venant de n'importe lequel des trois transports.
  void _updatePeer(
    String peerId, String pseudo, int hopCount, bool isGateway,
    TransportKind transport, bool connected, {
    String platform = 'unknown',
  }) {
    if (peerId == _myId) return;

    if (!connected) {
      // Ce chemin précis vers ce pair vient de tomber — mais s'il reste
      // joignable par un AUTRE chemin, on ne le supprime pas entièrement,
      // on retire juste ce chemin de sa liste.
      final existing = _peers[peerId];
      if (existing != null) {
        final updated = existing.copyWith(
          transports: Set.from(existing.transports)..remove(transport),
        );
        if (updated.transports.isEmpty) {
          // ⚠️ ON NE SUPPRIME PAS — on ouvre un DÉLAI DE GRÂCE.
          //
          // C'est ici que se jouait la « déconnexion trop rapide ». Le
          // dernier chemin qui tombe ne veut pas dire que la personne est
          // partie : sur Android, un lien Bluetooth se coupe pour un rien
          // et se rétablit dans la seconde. L'ancien code retirait le
          // pair immédiatement — la liste clignotait, la conversation
          // repassait « hors ligne », et les messages en cours
          // échouaient au lieu d'attendre.
          //
          // Le pair reste donc listé, marqué « reconnexion », pendant
          // `reconnectGrace`. C'est l'équivalent de ce que fait TCP pour
          // les applications qui passent par Internet : absorber les
          // micro-coupures pour que l'utilisateur ne les voie jamais.
          final enAttente = updated.copyWith(reconnecting: true);
          _peers[peerId] = enAttente;
          _graceUntil[peerId] =
              DateTime.now().add(Duration(seconds: _graceEffective));
          _peerEventsCtrl.add(enAttente);
        } else {
          _peers[peerId] = updated;
        }
      }
      return;
    }

    // Le pair vient de redonner signe de vie : la grâce est annulée, et
    // le drapeau « reconnexion » retombe. C'est le cas NORMAL après une
    // micro-coupure — et l'utilisateur n'aura rien vu du tout.
    _graceUntil.remove(peerId);
    _lastSeenAt[peerId] = DateTime.now();
    _peersEverSeen++;

    final existing = _peers[peerId];
    if (existing != null) {
      _peers[peerId] = existing.copyWith(
        transports: Set.from(existing.transports)..add(transport),
        hopCount: hopCount,
        isGateway: isGateway,
        platform: platform,
        role: isGateway ? PeerRole.gateway : PeerRole.leaf,
        connectionScore: existing.connectionScore + 1,
        reconnecting: false,
      );

      _persistPeerRecord(peerId, isGateway);
    } else {
      // Reconnexion : on recrée la fiche connectée. On récupère la clé
      // publique DÉJÀ CONNUE de la table persistante — sans ça, un pair
      // qui se reconnecte perdrait son « cadenas » et ne pourrait plus ni
      // recevoir nos messages (nous ne saurions plus chiffrer pour lui)
      // ni nous envoyer les siens (nous ne pourrions plus les déchiffrer).
      // On récupère aussi le score de connexion et le pseudo connu :
      // sans ça, le pair repartait à zéro à chaque reconnexion, perdant
      // sa place dans la file de routage et son identité affichée.
      final rec = StorageService.getPeerRecord(peerId);
      final nom = _vraiPseudo(rec?.pseudo, peerId) ??
          _vraiPseudo(pseudo, peerId) ??
          peerId;
      _peers[peerId] = ConnectedPeer(
        peerId: peerId,
        pseudo: nom,
        hopCount: hopCount,
        isGateway: isGateway,
        transports: {transport},
        platform: platform,
        role: isGateway ? PeerRole.gateway : PeerRole.leaf,
        publicKey: rec?.publicKey,
        connectionScore: rec?.totalMessagesExchanged ?? 0,
      );

      _persistPeerRecord(peerId, isGateway);
    }

    // Limiter le nombre de connexions directes : évincer le plus faible
    if (_peers.length > config.maxDirectConnections) {
      _evictWorstPeer();
    }

    if (isGateway) {
      _knownGateways[peerId] = _peers[peerId]!;
    }

    // Nourrir le cerveau réseau v2 : pair vivant + route directe connue.
    _networkManager?.registerPeer(peerId, batteryLevel: _batteryLevel);
    _networkManager?.protocol.updateRoutingTable(
      peerId, peerId, 1, _networkManager!.protocol.computeLinkMetric(peerId));

    _adjustScanRate();
    _peerEventsCtrl.add(_peers[peerId]!);
    _refreshNetworkState();
  }


  /// Le pseudo d'un pair, ou `null` si ce qu'on a n'en est pas un.
  ///
  /// ⚠️ UN IDENTIFIANT N'EST PAS UN NOM, ET LE CONFONDRE EMPOISONNE LA
  /// FICHE POUR TOUJOURS.
  ///
  /// Plusieurs chemins fabriquaient un pseudo à partir de l'identifiant
  /// faute de mieux : la déconnexion BLE émettait `pseudo: peerId`, et
  /// `updatePeerPublicKey` écrivait `rec?.pseudo ?? peerId`. La fiche
  /// persistée se retrouvait alors avec une empreinte de clé publique en
  /// guise de nom.
  ///
  /// Le piège se refermait ensuite : `_persistPeerRecord` gardait le
  /// pseudo DÉJÀ ENREGISTRÉ en priorité — ce qui est juste, pour ne pas
  /// perdre un nom connu au profit d'un événement pauvre. Sauf que le
  /// nom enregistré était l'empreinte : le vrai pseudo, arrivé ensuite,
  /// ne pouvait plus jamais l'écraser. La personne restait affichée sous
  /// une suite de caractères hexadécimaux, définitivement.
  ///
  /// On refuse donc à la source. Un pseudo égal à l'identifiant, ou
  /// vide, vaut « inconnu » — et l'affichage sait quoi faire d'un
  /// inconnu (voir `_identifiantAbrege`), là où il ne peut rien faire
  /// d'une empreinte déguisée en nom.
  static String? _vraiPseudo(String? pseudo, String peerId) {
    if (pseudo == null) return null;
    final net = pseudo.trim();
    if (net.isEmpty || net == peerId) return null;
    return net;
  }

  /// Persiste (ou crée) la fiche d'un pair en PRÉSERVANT les champs de
  /// confiance déjà connus — surtout `publicKey`, `verified`,
  /// `verifiedPublicKey` et le compteur d'échanges.
  ///
  /// C'était le bug des messages illisibles après déconnexion/reconnexion :
  /// la reconnexion réécrivait la fiche persistée SANS clé publique, donc
  /// la clé du pair disparaissait pour toujours (ni chiffrement pour lui,
  /// ni déchiffrement de ses messages) jusqu'au prochain échange de clés.
  void _persistPeerRecord(String peerId, bool isGateway) {
    final peer = _peers[peerId];
    if (peer == null) return;
    final rec = StorageService.getPeerRecord(peerId);
    // ⚠️ L'ORDRE EST : nom vivant, puis nom enregistré, puis
    // l'identifiant en dernier recours.
    //
    // La version précédente commençait par le nom ENREGISTRÉ. L'intention
    // était bonne — ne pas perdre un nom connu au profit d'un événement
    // qui n'en porte pas. Mais dès qu'une fiche avait été créée avec
    // l'identifiant en guise de nom, plus rien ne pouvait la corriger :
    // le vrai pseudo arrivait, et se faisait écarter par l'empreinte.
    //
    // `_vraiPseudo` écarte maintenant les faux noms des DEUX côtés, ce
    // qui rend l'ordre sûr : un nom vivant réel corrige la fiche, et une
    // absence de nom ne l'écrase jamais.
    final nom = _vraiPseudo(peer.pseudo, peerId) ??
        _vraiPseudo(rec?.pseudo, peerId) ??
        peerId;
    // On accumule les échanges de la session en cours avec ceux déjà
    // enregistrés — sinon le compteur était remis à zéro à chaque appel
    // de cette méthode (plusieurs fois par seconde par pair actif).
    final health = _transportHealth[peerId];
    final liveCount = health?.values.fold(0, (sum, h) => sum + h.totalSuccess) ?? 0;
    StorageService.upsertPeer(PeerRecord(
      peerId: peerId,
      pseudo: nom,
      role: isGateway ? 'gateway' : 'leaf',
      transports: peer.transports.map((t) => t.name).toList(),
      platform: peer.platform,
      interestGroups: rec?.interestGroups ?? peer.interestGroups.toList(),
      reliability: rec?.reliability ?? 1.0,
      lastSeen: DateTime.now(),
      totalMessagesExchanged: (rec?.totalMessagesExchanged ?? 0) + liveCount,
      publicKey: rec?.publicKey ?? peer.publicKey,
      verified: rec?.verified ?? false,
      verifiedPublicKey: rec?.verifiedPublicKey,
    ));
  }

  /// Quand il y a trop de pairs connectés à la fois (voir
  /// `maxDirectConnections`), on fait de la place en retirant celui qui a
  /// le moins bon « score de connexion » — jamais une passerelle, elles
  /// sont protégées car importantes pour tout le réseau.
  void _evictWorstPeer() {
    String? worstId;
    int worstScore = 999999;
    for (final entry in _peers.entries) {
      if (entry.value.role == PeerRole.gateway || entry.value.role == PeerRole.superPeer) continue;
      if (entry.value.connectionScore < worstScore) {
        worstScore = entry.value.connectionScore;
        worstId = entry.key;
      }
    }
    if (worstId != null) {
      debugPrint('[MeshService] evicting low-score peer $worstId (score=$worstScore)');
      _peers.remove(worstId);
      _lastSeenAt.remove(worstId);
      _graceUntil.remove(worstId);
      _transportHealth.remove(worstId);
    }
  }

  /// Filtrage des boucles de relais : le protocole v2 le fait avec un
  /// Bloom Filter de taille FIXE (50k items, mémoire constante) au lieu
  /// d'un Set qui grossirait sans fin. Un message déjà vu est écarté
  /// (probabilité de faux positif ≈ 0.1% — acceptable, l'app afficherait
  /// juste un vieux message une seconde fois).
  void _onIncomingData(MeshIncomingData data) {
    final proto = _networkManager?.protocol;
    if (proto != null) {
      if (proto.isDuplicate(data.messageId)) return;
      proto.markSeen(data.messageId);
    }

    // Anti-flood : à écarter APRÈS le dedup (une re-transmission du même
    // message ne compte pas), mais avant tout traitement coûteux.
    if (!_allowIngress(data.peerId)) return;

    // Traduire l'ID Nearby (MAC) en ID Droplet si possible.
    var peerId = data.peerId;
    final dropletId = _nearbyToDropletId[peerId];
    if (dropletId != null) peerId = dropletId;

    // Tout paquet reçu = le pair est vivant + un ACK (AIMD additive increase).
    _networkManager?.onHeartbeatAck(peerId, 0);
    _networkManager?.registerPeer(peerId);

    _incomingDataCtrl.add(MeshIncomingData(
      messageId: data.messageId,
      peerId: peerId,
      data: data.data,
    ));
  }

  /// Fenêtre glissante d'ingress : true si le pair n'a pas dépassé le seuil.
  bool _allowIngress(String peerId) {
    final now = DateTime.now();
    final window = _ingressWindows[peerId];
    if (window == null) {
      _ingressWindows[peerId] = _IngressWindow(now);
      return true;
    }
    if (now.difference(window.startedAt) >= const Duration(seconds: 1)) {
      window.startedAt = now;
      window.count = 0;
    }
    window.count++;
    if (window.count > _ingressMaxPerSecond) {
      if (now.difference(_lastFloodLog).inSeconds >= 5) {
        _lastFloodLog = now;
        debugPrint('[MeshService] anti-flood: $peerId dépasse $_ingressMaxPerSecond paquets/s, paquets ignorés');
      }
      return false;
    }
    // Borne mémoire du carnet de bord : si trop de pairs différents sont
    // passés, on oublie les plus anciens (fenêtres insérées en premier).
    if (_ingressWindows.length > _ingressWindowsCap) {
      final oldest = _ingressWindows.keys.first;
      _ingressWindows.remove(oldest);
    }
    return true;
  }

  bool hasWifiTransport(String peerId) {
    final peer = _peers[peerId];
    if (peer == null) return false;
    return peer.transports.contains(TransportKind.localWifi) ||
           peer.transports.contains(TransportKind.nativeP2P);
  }

  MeshTransport get nativeTransport => _nativeTransport;

  final Map<String, bool> _wifiNegotiations = {};

  /// Tente de faire passer un pair connu (déjà en Bluetooth) sur un chemin
  /// Wi-Fi plus rapide — utile avant de démarrer un appel ou un gros
  /// transfert de fichier.
  ///
  /// Réessaie avec backoff exponentiel (1s → 2s → 4s → 8s) jusqu'à
  /// [maxWifiAttempts] tentatives, au lieu du unique essai de 3s précédemment.
  static const int _maxWifiAttempts = 4;

  Future<bool> negotiateWifi(String peerId) async {
    final peer = _peers[peerId];
    if (peer == null) return false;
    if (hasWifiTransport(peerId)) return true;
    if (_wifiNegotiations.containsKey(peerId)) return false;
    _wifiNegotiations[peerId] = true;
    try {
      final natif = _nativeTransport;
      if (peer.platform == 'android' &&
          natif is NativeP2PTransport &&
          natif.isRunning) {
        natif.setStrategy(NearbyStrategy.pointToPoint);
      }

      // Backoff exponentiel : 1s → 2s → 4s → 8s
      for (int attempt = 0; attempt < _maxWifiAttempts; attempt++) {
        if (hasWifiTransport(peerId)) return true;
        final delay = Duration(seconds: 1 << attempt); // 1, 2, 4, 8
        await Future.delayed(delay);
      }
      return hasWifiTransport(peerId);
    } catch (_) {
      return false;
    } finally {
      _wifiNegotiations.remove(peerId);
    }
  }

  // ── Santé des transports ─────────────────────────────────────────────────
  //
  // Un peu comme un « disjoncteur » électrique : si un chemin échoue
  // plusieurs fois de suite pour joindre un pair précis, on arrête de
  // l'essayer temporairement plutôt que de continuer à s'y cogner.

  bool isTransportExcluded(String peerId, TransportKind kind) {
    final health = _transportHealth[peerId]?[kind];
    if (health == null) return false;
    return health.consecutiveFailures >= maxFailuresBeforeExclude;
  }

  void _recordSuccess(String peerId, TransportKind kind) {
    _transportHealth.putIfAbsent(peerId, () => {});
    final current = _transportHealth[peerId]![kind];
    _transportHealth[peerId]![kind] = TransportHealth(
      consecutiveFailures: 0,
      totalSuccess: (current?.totalSuccess ?? 0) + 1,
      lastUsed: DateTime.now(),
    );
    _networkManager?.recordTransportAck(_mapKind(kind));
    _updateProtocolLinkMetrics(peerId);
    _emitHealth();
  }

  void _recordFailure(String peerId, TransportKind kind) {
    _transportHealth.putIfAbsent(peerId, () => {});
    final current = _transportHealth[peerId]![kind];
    _transportHealth[peerId]![kind] = TransportHealth(
      consecutiveFailures: (current?.consecutiveFailures ?? 0) + 1,
      totalSuccess: current?.totalSuccess ?? 0,
      lastUsed: DateTime.now(),
    );
    _totalFailed++;
    _networkManager?.protocol.onPacketLost(peerId);
    _updateProtocolLinkMetrics(peerId);
    _emitHealth();
  }

  void incrementAck() {
    _totalAcks++;
    _emitHealth();
  }

  /// Appelé par le NetworkManager quand il veut relancer un scan de
  /// transports (backoff exponentiel déclenché après perte de tous les pairs).
  /// Redémarre BLE + Wi-Fi + NativeP2P en parallèle.
  void _onNetworkReconnectRequest() {
    debugPrint('[MeshService] NetworkManager demande reconnexion — restart transports');
    _startTransport('BLE', () => _bleTransport.start(_myId, _myPseudo));
    _startTransport('WiFi', () => _wifiTransport.start(_myId, _myPseudo));
    _startTransport('NativeP2P', () => _nativeTransport.start(_myId, _myPseudo));
  }

  /// Fabrique l'instantané complet de la santé du mesh, pour l'écran
  /// « Réseau mesh ».
  MeshHealth get health {
    final bleHealth = <String, TransportHealth>{};
    final wifiHealth = <String, TransportHealth>{};
    final nativeHealth = <String, TransportHealth>{};

    for (final entry in _transportHealth.entries) {
      for (final tEntry in entry.value.entries) {
        switch (tEntry.key) {
          case TransportKind.ble: bleHealth[entry.key] = tEntry.value;
          case TransportKind.localWifi: wifiHealth[entry.key] = tEntry.value;
          case TransportKind.nativeP2P: nativeHealth[entry.key] = tEntry.value;
          case TransportKind.both: break;
        }
      }
    }

    final allHealth = _transportHealth.values
        .expand((m) => m.values)
        .toList();
    final avgRel = allHealth.isEmpty
        ? 1.0
        : allHealth.fold(0.0, (s, h) => s + h.reliability) / allHealth.length;

    return MeshHealth(
      totalPeers: _peers.length,
      peersOnWifi: wifiPeerCount,
      peersOnBle: blePeerCount,
      peersOnNative: nativePeerCount,
      gatewayCount: gatewayCount,
      superPeerCount: superPeerCount,
      averageReliability: avgRel,
      messagesSent: _totalSent,
      acksReceived: _totalAcks,
      failedDeliveries: _totalFailed,
      bleHealth: bleHealth,
      wifiHealth: wifiHealth,
      nativeHealth: nativeHealth,
    );
  }

  void _emitHealth() {
    _healthCtrl.add(health);
  }

  void resetTransportHealth(String peerId) {
    _transportHealth.remove(peerId);
    _emitHealth();
  }

  void resetAllTransportHealth() {
    _transportHealth.clear();
    _emitHealth();
  }

  // ── Remise multi-voies avec routage par intérêt ─────────────────────────

  /// Passe d'un [TransportKind] local à celui du NetworkManager v2.
  static nm.TransportKind _mapKind(TransportKind k) {
    switch (k) {
      case TransportKind.ble:
        return nm.TransportKind.ble;
      case TransportKind.localWifi:
        return nm.TransportKind.localWifi;
      case TransportKind.nativeP2P:
        return nm.TransportKind.nativeP2p;
      case TransportKind.both:
        return nm.TransportKind.ble;
    }
  }

  /// Nourrit le protocole v2 (métriques de lien + table de routage) à partir
  /// de la santé connue des transports — c'est lui qui décidera des routes.
  void _updateProtocolLinkMetrics(String peerId) {
    final health = _transportHealth[peerId];
    final manager = _networkManager;
    if (health == null || manager == null) return;

    final totalSuccess = health.values.fold(0, (s, h) => s + h.totalSuccess);
    final totalFail = health.values.fold(0, (s, h) => s + h.consecutiveFailures);
    final total = totalSuccess + totalFail;
    final pdr = total > 0 ? (totalSuccess / total).clamp(0.0, 1.0) : 1.0;
    final rtt = manager.peerHealth[peerId]?.rttMs ?? 50.0;

    manager.protocol.updateLinkMetrics(peerId, LinkMetrics(
      latencyMs: rtt,
      packetDeliveryRatio: pdr,
      batteryLevel: _batteryLevel,
      bandwidthKbps: manager.peerHealth[peerId]?.estimatedBandwidth ?? 100,
    ));

    // Route directe vers ce pair, avec la métrique composite courante.
    manager.protocol.updateRoutingTable(
      peerId, peerId, 1, manager.protocol.computeLinkMetric(peerId));
  }

  /// Envoi ROUTÉ, pas floodé : si [peerId] est joignable directement on
  /// l'atteint en direct ; sinon on passe par le prochain saut connu de la
  /// table de routage (le relais fera suivre). Si la route principale
  /// échoue, essaie automatiquement les routes alternatives avant de
  /// retourner false — l'appelant retombe alors sur la diffusion.
  Future<bool> sendViaRoute(String peerId, Uint8List data,
      {int type = 0x00, int priority = 2}) async {
    // ⚠️ ON RENVOIE CE QUE `sendToPeer` A FAIT, plus « true » parce que le
    // pair nous est connu. C'était la ligne exacte du défaut : un pair
    // présent dans la table suffisait à déclarer le message livré, même
    // si aucun transport n'avait accepté la charge.
    if (_peers.containsKey(peerId)) {
      return sendToPeer(peerId, data, type: type, priority: priority);
    }
    final manager = _networkManager;
    if (manager != null) {
      // Essayer la route principale d'abord.
      final route = manager.protocol.getRoute(peerId);
      if (route != null &&
          route.nextHop.isNotEmpty &&
          route.nextHop != peerId &&
          _peers.containsKey(route.nextHop)) {
        debugPrint('[MeshService] routage $peerId via ${route.nextHop} (${route.hopCount} sauts)');
        final sent = await sendToPeer(route.nextHop, data, type: type, priority: priority);
        if (sent) return true;
        // Route principale échouée — essayer les alternatives.
        debugPrint('[MeshService] route principale vers $peerId échouée, basculement alternatif');
      }
      // Basculement sur les routes alternatives.
      final altRoute = manager.protocol.failoverRoute(peerId);
      if (altRoute != null &&
          altRoute.nextHop.isNotEmpty &&
          altRoute.nextHop != peerId &&
          _peers.containsKey(altRoute.nextHop)) {
        debugPrint('[MeshService] routage alternatif $peerId via ${altRoute.nextHop} (${altRoute.hopCount} sauts)');
        return sendToPeer(altRoute.nextHop, data, type: type, priority: priority);
      }
    }
    return false;
  }

  /// Pour un pair donné, dresse la liste des chemins qu'on peut essayer,
  /// dans l'ordre de préférence (Wi-Fi local d'abord, le plus rapide),
  /// puis retire ceux qu'on sait actuellement en panne (voir la section
  /// « Santé des transports » ci-dessus).
  List<TransportKind> _getCandidateTransports(ConnectedPeer peer, int type) {
    final ordered = <TransportKind>[];
    if (peer.transports.contains(TransportKind.localWifi)) {
      ordered.add(TransportKind.localWifi);
    }
    if (peer.transports.contains(TransportKind.nativeP2P)) {
      ordered.add(TransportKind.nativeP2P);
    }
    if (peer.transports.contains(TransportKind.ble) && type < 0x20) {
      ordered.add(TransportKind.ble);
    }
    ordered.removeWhere((k) => isTransportExcluded(peer.peerId, k));

    // Failover global : si un transport est dégradé dans l'ensemble du mesh
    // (faible healthScore agrégé), on le relègue en fin de liste — la priorité
    // devient : les transports sains d'abord, dans l'ordre WiFi→Native→BLE.
    if (_networkManager != null) {
      final scores = <TransportKind, double>{
        TransportKind.localWifi: _networkManager!.transportHealthScore(nm.TransportKind.localWifi),
        TransportKind.nativeP2P: _networkManager!.transportHealthScore(nm.TransportKind.nativeP2p),
        TransportKind.ble: _networkManager!.transportHealthScore(nm.TransportKind.ble),
      };
      ordered.sort((a, b) {
        final cmp = scores[b]!.compareTo(scores[a]!); // plus sain d'abord
        if (cmp != 0) return cmp;
        // Égalité → préférence d'origine (WiFi > Native > BLE).
        const rank = {
          TransportKind.localWifi: 0,
          TransportKind.nativeP2P: 1,
          TransportKind.ble: 2,
          TransportKind.both: 3,
        };
        return rank[a]!.compareTo(rank[b]!);
      });
    }
    return ordered;
  }

  /// Envoie vraiment les données via le chemin précis demandé — en
  /// redirigeant simplement vers le bon transport.
  /// Renvoie ce que le transport a RÉELLEMENT fait, pas ce qu'on a tenté.
  Future<bool> _sendVia(
      TransportKind kind, String peerId, Uint8List data, int type,
      {int priority = 2}) async {
    // Le transport à emprunter, et l'identifiant sous lequel IL connaît
    // ce pair — c'est la seule chose qui diffère encore d'un chemin à
    // l'autre. Wi-Fi Direct désigne les appareils par leur identifiant
    // Nearby (une MAC), pas par leur identité Droplet.
    final (MeshTransport? transport, String destinataire) = switch (kind) {
      TransportKind.localWifi => (_wifiTransport, peerId),
      TransportKind.nativeP2P => (
          _nativeTransport,
          _dropletToNearbyId[peerId] ?? peerId
        ),
      TransportKind.ble => (_bleTransport, peerId),
      TransportKind.both => (null, peerId),
    };
    if (transport == null) return false;

    // ── La règle de capacité, posée UNE seule fois ──────────────────
    //
    // Auparavant, seul le Bluetooth vérifiait lui-même qu'il pouvait
    // porter un paquet — et il le refusait APRÈS que la couche d'ici
    // l'ait choisi, ce qui gaspillait une tentative. Pire, la même règle
    // (« pas de fichiers en BLE ») se trouvait recopiée plus haut, avec
    // le risque que les deux copies divergent le jour où la limite
    // change. On demande désormais au transport ce qu'il sait porter,
    // avant de le solliciter.
    if (!transport.capabilities.accepte(
      tailleOctets: data.length,
      type: type,
    )) {
      debugPrint('[MeshService] ${transport.name} ne peut pas porter '
          '${data.length} o de type 0x${type.toRadixString(16)}');
      transport.metrics.echecsEnvoi++;
      return false;
    }

    final envoye = await transport.sendToPeer(destinataire, data, type: type, priority: priority);
    if (envoye) {
      transport.metrics.paquetsEnvoyes++;
      transport.metrics.octetsEnvoyes += data.length;
    } else {
      transport.metrics.echecsEnvoi++;
    }
    return envoye;
  }

  /// Les compteurs de chaque transport, pour l'observabilité.
  ///
  /// Deux relevés espacés suffisent à en déduire un débit, un taux
  /// d'échec ou un nombre de pertes de lien — c'est la matière première
  /// des mesures reproductibles, que rien n'exposait jusqu'ici.
  Map<String, Map<String, int>> transportMetrics() => {
        for (final t in <MeshTransport>[
          _wifiTransport,
          _nativeTransport,
          _bleTransport,
        ])
          t.name: t.metrics.toJson(),
      };

  /// L'état de chaque transport, tel que le voit la couche supérieure.
  Map<String, TransportState> transportStates() => {
        for (final t in <MeshTransport>[
          _wifiTransport,
          _nativeTransport,
          _bleTransport,
        ])
          t.name: t.state,
      };

  /// Route un message vers un pair spécifique avec priorisation
  /// des transports les plus économes en batterie.
  ///
  /// Essaie TOUS les chemins disponibles vers ce pair EN MÊME TEMPS
  /// (comme envoyer la même lettre par plusieurs facteurs différents) —
  /// dès que L'UN d'eux réussit, c'est suffisant. On considère l'envoi
  /// vraiment échoué seulement si TOUS les chemins ont échoué.
  /// Envoie [data] à [peerId] par le meilleur transport disponible.
  ///
  /// **Renvoie `true` seulement si un transport a réellement accepté la
  /// charge.**
  ///
  /// ⚠️ CETTE MÉTHODE NE RENDAIT RIEN, ET C'EST D'ICI QUE PARTAIT LE
  /// DÉFAUT LE PLUS GRAVE DU RÉSEAU.
  ///
  /// Elle levait une exception quand TOUS les transports échouaient, mais
  /// restait muette dans les deux cas les plus fréquents : pair inconnu,
  /// et aucun transport candidat. Surtout, un transport pouvait « réussir »
  /// en ayant jeté la charge — le Bluetooth écarte les fichiers et tout ce
  /// qui dépasse 512 octets. `_sendVia` ne levait rien, donc `.then()`
  /// s'exécutait, donc le succès était enregistré.
  ///
  /// Résultat mesuré au banc : la file annonçait 130 messages livrés sur
  /// 130 quand le destinataire n'en avait reçu que 110.
  ///
  /// On renvoie désormais un verdict, et on n'enregistre un succès de
  /// santé que si le transport a vraiment pris la charge — sans quoi le
  /// score de santé récompensait les transports qui jetaient le plus.
  Future<bool> sendToPeer(String peerId, Uint8List data,
      {int type = 0x00, int priority = 2}) async {
    final peer = _peers[peerId];
    if (peer == null) {
      debugPrint('[Mesh] sendToPeer $peerId: pair inconnu');
      return false;
    }

    final candidates = _getCandidateTransports(peer, type);
    if (candidates.isEmpty) {
      debugPrint('[Mesh] Aucun transport disponible pour $peerId');
      return false;
    }

    debugPrint('[Mesh] sendToPeer $peerId type=$type priority=$priority candidats=$candidates');
    _totalSent++;

    // ⚠️ LES TRANSPORTS SONT ESSAYÉS L'UN APRÈS L'AUTRE, plus tous en
    // même temps. La version précédente les lançait en parallèle et
    // gardait le premier qui rendait la main : cela envoyait le même
    // message deux ou trois fois quand plusieurs liens fonctionnaient,
    // et faisait payer au Bluetooth — le plus lent et le plus coûteux —
    // un trajet dont personne n'avait besoin. `_getCandidateTransports`
    // les a déjà triés du plus sain au moins sain : on s'arrête au
    // premier qui accepte.
    for (final kind in candidates) {
      bool ok;
      try {
        ok = await _sendVia(kind, peerId, data, type, priority: priority).timeout(
          const Duration(seconds: 10),
          onTimeout: () => false,
        );
      } catch (e) {
        debugPrint('[Mesh] $kind a échoué vers $peerId: $e');
        ok = false;
      }

      if (ok) {
        _recordSuccess(peerId, kind);
        return true;
      }
      _recordFailure(peerId, kind);
    }

    debugPrint('[Mesh] aucun transport n\'a pris la charge pour $peerId');
    return false;
  }

  /// Diffusion intelligente : ne diffuse qu'aux pairs qui correspondent
  /// aux groupes d'intérêt spécifiés (ou tous si non spécifié).
  ///
  /// C'est ce qu'on utilise pour envoyer un message de conversation
  /// (chiffré pour UNE personne précise) : on le transmet quand même à
  /// TOUS les pairs connectés, mais seule la bonne personne pourra le
  /// déchiffrer et l'afficher — les autres se contentent de le relayer
  /// plus loin dans le réseau.
  /// **Renvoie `true` si au moins un pair a réellement pris la charge.**
  Future<bool> broadcastToConnectedPeers(
    Uint8List data, {
    String? excludePeerId,
    Set<String>? interestGroups,
    int type = 0x00,
  }) async {
    Iterable<ConnectedPeer> targets = _peers.values;

    if (excludePeerId != null) {
      targets = targets.where((p) => p.peerId != excludePeerId);
    }

    // Routage par intérêt : ne diffuser qu'aux pairs abonnés
    if (interestGroups != null && interestGroups.isNotEmpty) {
      targets = targets.where((p) =>
        p.interestGroups.intersection(interestGroups).isNotEmpty ||
        p.role == PeerRole.gateway ||
        p.role == PeerRole.superPeer
      );
    }

    // Envoi « best effort » par pair : un seul pair en échec (transport
    // instable, ex. NativeP2P qui peut renvoyer BUSY) ne doit jamais faire
    // échouer tout le message alors que le ou les vrais destinataires
    // l'ont bien reçu par un autre chemin.
    final targetList = targets.toList();
    if (targetList.isEmpty) return false;

    // ⚠️ ON COMPTE LES SUCCÈS RÉELS, plus les absences d'exception.
    //
    // Auparavant seul un `throw` faisait grimper le compteur d'échecs.
    // Or `sendToPeer` ne levait rien quand le pair était inconnu ou
    // qu'aucun transport n'était disponible : ces envois-là passaient
    // pour des réussites, et la diffusion se déclarait accomplie sans
    // qu'un seul octet soit parti.
    final results = await Future.wait(
      targetList.map((peer) async {
        try {
          return await sendToPeer(peer.peerId, data, type: type);
        } catch (e) {
          debugPrint('[Mesh] échec diffusion vers ${peer.peerId}: $e');
          return false;
        }
      }),
    );

    final accepted = results.where((ok) => ok).length;
    if (accepted == 0) {
      debugPrint('[Mesh] diffusion : aucun des ${targetList.length} pairs '
          "n'a pris la charge");
    }
    return accepted > 0;
  }

  void dispose() {
    _adaptiveBeaconTimer?.cancel();
    _stalePeerTimer?.cancel();
    _gatewayAnnounceTimer?.cancel();
    _peerPersistTimer?.cancel();
    _networkManager?.dispose();
    stateMachine.dispose();
    _networkManager = null;
    _persistKnownPeers();
    _bleTransport.dispose();
    _wifiTransport.dispose();
    _nativeTransport.dispose();
    _peerEventsCtrl.close();
    _incomingDataCtrl.close();
    _healthCtrl.close();
  }
}

/// Compteur de paquets entrants sur une fenêtre de 1 seconde pour un pair.
class _IngressWindow {
  _IngressWindow(this.startedAt);

  DateTime startedAt;
  int count = 0;
}
