// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est le fichier qui fait vraiment PARLER deux téléphones en Bluetooth.
//
// Le Bluetooth basse consommation (BLE) fonctionne un peu comme un jeu de
// cache-cache avec des rôles bien précis :
//   - Le « central » est celui qui CHERCHE activement (il scanne autour de
//     lui, un peu comme quelqu'un qui balaie une pièce avec une lampe
//     torche pour repérer les autres).
//   - Le « périphérique » est celui qui SE MONTRE (il annonce en
//     permanence « je suis là ! », comme un phare).
//
// Le souci, c'est que Droplet doit fonctionner peu importe qui a lancé
// l'app en premier — donc CHAQUE téléphone joue LES DEUX RÔLES EN MÊME
// TEMPS : il cherche les autres (central) ET se fait trouver (périphérique)
// simultanément. C'est un peu comme si, à une fête, tout le monde à la
// fois cherchait ses amis ET portait un badge lumineux pour être repéré.
//
// Une fois deux téléphones connectés, ils échangent des petits paquets sur
// des « characteristics » (les boîtes aux lettres décrites dans
// `ble_mesh_protocol.dart`) — et comme le Bluetooth ne transporte que de
// tout petits messages à la fois, tout passe par le système de « chunks »
// (puzzle en morceaux) de ce même fichier protocole.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:bluetooth_low_energy/bluetooth_low_energy.dart';
import 'ble_mesh_protocol.dart';

/// Transport BLE peer-to-peer pour OURO PREP.
///
/// Chaque appareil joue **les deux rôles BLE simultanément** :
/// - **Central** : scanne et se connecte aux pairs qui annoncent le service
///   mesh (`kMeshServiceUuid`).
/// - **Périphérique** : annonce lui-même ce service via un serveur GATT
///   local, pour être découvrable par les autres appareils.
///
/// C'est indispensable : sans rôle périphérique, deux appareils qui ne font
/// que scanner ne se découvrent jamais (`universal_ble`, utilisé
/// précédemment, ne supportait que le rôle central).
///
/// ## Sens de communication
/// Un central ne peut qu'écrire sur une characteristic d'un périphérique ;
/// un périphérique ne peut que notifier les centraux abonnés — il ne peut
/// jamais écrire directement chez un central. D'où trois characteristics :
/// - `presence` (read + notify) : le périphérique annonce son identité.
/// - `inbox` (write) : le central envoie des données au périphérique.
/// - `downlink` (notify) : le périphérique envoie des données au central.
///
/// Comme chaque appareil est aussi périphérique, un pair qui se connecte à
/// nous en tant que central ne peut pas être lu directement — il s'annonce
/// via un message "hello" écrit sur `inbox` juste après connexion.
///
/// ## Limite plateforme connue
/// Sur iOS, en arrière-plan, le système retire les UUID de service de
/// l'annonce BLE (restriction Apple au niveau OS) : la découverte iOS↔iOS
/// n'est fiable qu'application au premier plan des deux côtés. Rien côté
/// app ne peut contourner ça.
class BleMeshTransport {
  /// Taille maximale d'un payload BLE (512 octets).
  /// Au-delà, le message est refusé : BLE ne porte que de la découverte,
  /// de la présence, et de petits messages de contrôle (poignée de main
  /// WebRTC, annonces mesh). Les fichiers et flux audio passent par le
  /// Wi‑Fi (localWifi ou nativeP2P).
  static const int _maxPayloadSize = 512;

  // Les deux « personnalités » du téléphone en Bluetooth : celle qui
  // cherche (central) et celle qui se montre (périphérique).
  //
  // ⚠️ `late` N'EST PAS UN DÉTAIL DE STYLE ICI.
  //
  // Ces deux objets prennent la main sur la radio Bluetooth du système
  // dès leur construction. Les créer en champ ordinaire les fabriquait
  // au moment où l'on construisait `MeshTransportService` — c'est-à-dire
  // AVANT même d'avoir décidé de démarrer le mesh, et sur toute
  // plateforme, y compris là où le Bluetooth n'existe pas (une machine
  // de test, un poste de développement). La construction échouait alors
  // sur un `UnimplementedError` qui n'avait rien à voir avec ce qu'on
  // voulait faire.
  //
  // En `late`, ils ne naissent qu'à la première utilisation réelle,
  // c'est-à-dire quand on allume vraiment le Bluetooth.
  late final CentralManager _central = CentralManager();
  late final PeripheralManager _peripheral = PeripheralManager();

  bool _isRunning = false;
  String _myId = '';
  String _myPseudo = '';

  final _peerEventsCtrl = StreamController<MeshPeerEvent>.broadcast();
  final _incomingDataCtrl = StreamController<MeshIncomingData>.broadcast();

  Stream<MeshPeerEvent> get peerEvents => _peerEventsCtrl.stream;
  Stream<MeshIncomingData> get incomingData => _incomingDataCtrl.stream;

  // -- Rôle central : nous sommes connectés à ces pairs en tant que central --
  final Map<String, _OutgoingLink> _outgoingLinks = {}; // peerId -> lien
  final Map<String, String> _peripheralKeyToPeerId = {}; // uuid périphérique -> peerId
  final Set<String> _pendingConnections = {}; // uuid périphérique en cours de connexion

  // -- Rôle périphérique : ces pairs sont connectés à nous en tant que central --
  final Map<String, _IncomingLink> _incomingLinks = {}; // peerId -> lien
  final Map<String, String> _centralUuidToPeerId = {}; // uuid central -> peerId

  final Map<String, ChunkAssembly> _assemblies = {};

  StreamSubscription<DiscoveredEventArgs>? _discoveredSub;
  StreamSubscription<PeripheralConnectionStateChangedEventArgs>? _centralLinkSub;
  StreamSubscription<GATTCharacteristicNotifiedEventArgs>? _notifiedSub;
  StreamSubscription<CentralConnectionStateChangedEventArgs>? _peripheralLinkSub;
  StreamSubscription<GATTCharacteristicReadRequestedEventArgs>? _readReqSub;
  StreamSubscription<GATTCharacteristicWriteRequestedEventArgs>? _writeReqSub;

  Timer? _presenceNotifyTimer;

  late GATTCharacteristic _presenceChar;
  late GATTCharacteristic _inboxChar;
  late GATTCharacteristic _downlinkChar;
  late GATTService _service;

  String get _platformName =>
      Platform.isAndroid ? 'android' : (Platform.isIOS ? 'ios' : 'unknown');

  /// Allume le Bluetooth mesh : demande les autorisations nécessaires,
  /// prépare les trois boîtes aux lettres (characteristics), puis lance en
  /// même temps la recherche des autres (central) ET l'annonce de sa
  /// propre présence (périphérique).
  Future<void> start(String myId, String myPseudo) async {
    if (_isRunning) return;
    _isRunning = true;
    _myId = myId;
    _myPseudo = myPseudo;
    try {
      await _start(myPseudo);
    } catch (e) {
      // ⚠️ REMETTRE LE DRAPEAU À ZÉRO EST INDISPENSABLE.
      //
      // `start()` sort par le haut dès qu'il dépasse le délai imparti
      // (huit secondes, imposées par `MeshTransportService`). Sans ce
      // `catch`, `_isRunning` restait à `true` alors que rien n'avait
      // démarré : ni la découverte, ni l'annonce de présence. Et comme
      // la première ligne de cette méthode sort immédiatement quand
      // `_isRunning` est vrai, PLUS AUCUNE tentative ultérieure ne
      // pouvait aboutir.
      //
      // Sur l'appareil de test, cela donnait :
      //
      //     [MeshService] BLE start error: TimeoutException after 8 s
      //     [MeshService] startMesh() completed, knownPeers=0
      //
      // …et le Bluetooth restait mort jusqu'au redémarrage de l'app.
      _isRunning = false;
      rethrow;
    }
  }

  Future<void> _start(String myPseudo) async {

    // authorize() n'est implémenté que sur Android (throw UnsupportedError ailleurs).
    if (Platform.isAndroid) {
      try {
        await _central.authorize();
        await _peripheral.authorize();
      } catch (e) { debugPrint('[BLE] authorize: $e'); }
    }

    _buildGattService();

    // On s'abonne à tous les événements possibles AVANT de vraiment
    // démarrer — comme brancher tous les fils avant d'appuyer sur
    // « marche », pour ne rater aucun événement dès le premier instant.
    _discoveredSub = _central.discovered.listen(_onDiscovered);
    _centralLinkSub = _central.connectionStateChanged.listen(_onCentralLinkStateChanged);
    _notifiedSub = _central.characteristicNotified.listen(_onCharacteristicNotified);

    _peripheralLinkSub = _peripheral.connectionStateChanged.listen(_onPeripheralLinkStateChanged);
    _readReqSub = _peripheral.characteristicReadRequested.listen(_onReadRequested);
    _writeReqSub = _peripheral.characteristicWriteRequested.listen(_onWriteRequested);

    await Future.wait([
      _waitPoweredOn(_central),
      _waitPoweredOn(_peripheral),
    ]);

    try {
      await _peripheral.removeAllServices();
      await _peripheral.addService(_service);
    } catch (e) { debugPrint('[BLE] addService: $e'); }

    // Démarre la recherche des autres, par cycles.
    await _demarrerCycleDeScan();

    // ...et en même temps, l'annonce de sa propre présence.
    try {
      await _peripheral.startAdvertising(Advertisement(
        name: myPseudo,
        serviceUUIDs: [UUID.fromString(kMeshServiceUuid)],
      ));
    } catch (e) { debugPrint('[BLE] startAdvertising: $e'); }

    // Toutes les 5 secondes, on redit « coucou, c'est toujours moi » aux
    // pairs déjà connectés à nous — comme agiter la main de temps en
    // temps pour montrer qu'on est toujours là.
    _presenceNotifyTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _pushPresenceToSubscribers();
    });
  }

  // ── Cycle de scan (« duty cycle ») ──────────────────────────────────
  //
  // ⚠️ POURQUOI ON NE SCANNE PAS EN CONTINU.
  //
  // Un scan BLE permanent est l'un des postes de consommation les plus
  // lourds d'un téléphone : la radio reste éveillée en permanence. Les
  // applications qui le font vident une batterie en quelques heures, et
  // Android finit par les brider de lui-même.
  //
  // On alterne donc : on cherche pendant `scanDuration`, puis on se tait
  // pendant `scanPause`. Ce n'est pas gênant pour les pairs DÉJÀ
  // connectés — leur lien GATT reste ouvert pendant la pause et les
  // messages continuent de passer. La pause ne retarde que la DÉCOUVERTE
  // d'un nouveau venu.
  //
  // Ces trois réglages existaient depuis toujours dans la configuration
  // (`bleScanDuration`, `bleScanPause`, `bleScanPauseLowBattery`) mais
  // n'étaient lus nulle part : le scan tournait sans interruption.

  Duration _scanDuration = const Duration(seconds: 10);
  Duration _scanPause = const Duration(seconds: 30);
  Timer? _scanCycleTimer;
  bool _scanEnCours = false;

  /// Règle le cycle de scan, à chaud.
  void setScanCycle({required Duration duree, required Duration pause}) {
    if (duree == _scanDuration && pause == _scanPause) return;
    _scanDuration = duree;
    _scanPause = pause;
    debugPrint('[BLE] cycle de scan: ${duree.inSeconds}s actif / '
        '${pause.inSeconds}s pause');
    if (_isRunning) unawaited(_demarrerCycleDeScan());
  }

  Future<void> _demarrerCycleDeScan() async {
    _scanCycleTimer?.cancel();
    await _scanner();
  }

  /// Une phase active, puis une pause, puis on recommence.
  Future<void> _scanner() async {
    if (!_isRunning) return;
    try {
      await _central
          .startDiscovery(serviceUUIDs: [UUID.fromString(kMeshServiceUuid)]);
      _scanEnCours = true;
    } catch (e) {
      debugPrint('[BLE] startDiscovery: $e');
    }

    _scanCycleTimer = Timer(_scanDuration, () async {
      if (!_isRunning) return;
      if (_scanEnCours) {
        try {
          await _central.stopDiscovery();
        } catch (e) {
          debugPrint('[BLE] stopDiscovery: $e');
        }
        _scanEnCours = false;
      }
      // ⚠️ L'ANNONCE DE NOTRE PRÉSENCE, ELLE, NE S'ARRÊTE JAMAIS.
      //
      // On cesse de CHERCHER, on ne cesse pas d'ÊTRE TROUVABLE. Couper
      // aussi l'advertising rendrait deux téléphones mutuellement
      // invisibles dès que leurs pauses se chevauchent — ils pourraient
      // rester côte à côte sans jamais se voir.
      _scanCycleTimer = Timer(_scanPause, () => unawaited(_scanner()));
    });
  }

  /// Attend que le Bluetooth soit vraiment allumé et prêt (« powered on »)
  /// avant de continuer — sans ça, toutes les commandes suivantes
  /// échoueraient silencieusement.
  Future<void> _waitPoweredOn(
    BluetoothLowEnergyManager manager, {
    Duration timeout = const Duration(seconds: 6),
  }) async {
    if (manager.state == BluetoothLowEnergyState.poweredOn) return;
    final completer = Completer<void>();
    late final StreamSubscription<BluetoothLowEnergyStateChangedEventArgs> sub;
    sub = manager.stateChanged.listen((e) {
      if (e.state == BluetoothLowEnergyState.poweredOn && !completer.isCompleted) {
        completer.complete();
      }
    });
    try {
      await completer.future.timeout(timeout, onTimeout: () {});
    } finally {
      await sub.cancel();
    }
  }

  /// Construit les trois boîtes aux lettres Bluetooth (les
  /// « characteristics ») décrites dans `ble_mesh_protocol.dart`, et les
  /// range dans un même « service » — l'ensemble que les autres
  /// téléphones verront quand ils nous découvriront.
  void _buildGattService() {
    _presenceChar = GATTCharacteristic.mutable(
      uuid: UUID.fromString(kPresenceCharUuid),
      properties: [
        GATTCharacteristicProperty.read,
        GATTCharacteristicProperty.notify,
      ],
      permissions: [GATTCharacteristicPermission.read],
      descriptors: [],
    );
    _inboxChar = GATTCharacteristic.mutable(
      uuid: UUID.fromString(kInboxCharUuid),
      properties: [
        GATTCharacteristicProperty.write,
        GATTCharacteristicProperty.writeWithoutResponse,
      ],
      permissions: [GATTCharacteristicPermission.write],
      descriptors: [],
    );
    _downlinkChar = GATTCharacteristic.mutable(
      uuid: UUID.fromString(kDownlinkCharUuid),
      properties: [GATTCharacteristicProperty.notify],
      permissions: [GATTCharacteristicPermission.read],
      descriptors: [],
    );
    _service = GATTService(
      uuid: UUID.fromString(kMeshServiceUuid),
      isPrimary: true,
      includedServices: const [],
      characteristics: [_presenceChar, _inboxChar, _downlinkChar],
    );
  }

  /// Éteint tout : arrête de chercher, arrête de s'annoncer, coupe toutes
  /// les connexions en cours, et range tous les petits carnets utilisés
  /// entre-temps.
  Future<void> stop() async {
    _isRunning = false;
    _presenceNotifyTimer?.cancel();

    await _discoveredSub?.cancel();
    await _centralLinkSub?.cancel();
    await _notifiedSub?.cancel();
    await _peripheralLinkSub?.cancel();
    await _readReqSub?.cancel();
    await _writeReqSub?.cancel();

    _scanCycleTimer?.cancel();
    _scanCycleTimer = null;
    _scanEnCours = false;
    try { await _central.stopDiscovery(); } catch (e) { debugPrint('[BLE] $e'); }
    try { await _peripheral.stopAdvertising(); } catch (e) { debugPrint('[BLE] $e'); }

    for (final link in _outgoingLinks.values) {
      try { await _central.disconnect(link.peripheral); } catch (e) { debugPrint('[BLE] $e'); }
    }
    for (final link in _incomingLinks.values) {
      try { await _peripheral.disconnect(link.central); } catch (e) { debugPrint('[BLE] $e'); }
    }
    try { await _peripheral.removeAllServices(); } catch (e) { debugPrint('[BLE] $e'); }

    _outgoingLinks.clear();
    _peripheralKeyToPeerId.clear();
    _pendingConnections.clear();
    _incomingLinks.clear();
    _centralUuidToPeerId.clear();
    _assemblies.clear();
  }

  // ── Rôle central : découverte et connexion ──────────────────────────────

  /// Un téléphone Droplet vient d'être repéré pendant le scan — on tente
  /// de s'y connecter, sauf si on est déjà en train de le faire ou déjà
  /// connecté.
  void _onDiscovered(DiscoveredEventArgs e) {
    if (!_isRunning) return;
    final hasOurService = e.advertisement.serviceUUIDs
        .any((u) => u.toString().toLowerCase() == kMeshServiceUuid.toLowerCase());
    if (!hasOurService) return;

    final key = e.peripheral.uuid.toString();
    if (_pendingConnections.contains(key)) return;
    if (_peripheralKeyToPeerId.containsKey(key)) return;

    _pendingConnections.add(key);
    unawaited(_connectAsCentral(e.peripheral));
  }

  /// Se connecte vraiment à un téléphone découvert, en tant que central :
  /// on ouvre la connexion, on va chercher ses trois boîtes aux lettres,
  /// on lit sa fiche de présence (qui il est), puis on s'abonne pour être
  /// prévenu de ses prochains messages.
  Future<void> _connectAsCentral(Peripheral peripheral) async {
    final key = peripheral.uuid.toString();
    try {
      await _central.connect(peripheral);

      final services = await _central.discoverGATT(peripheral);
      GATTService? svc;
      for (final s in services) {
        if (s.uuid.toString().toLowerCase() == kMeshServiceUuid.toLowerCase()) {
          svc = s;
          break;
        }
      }
      if (svc == null) {
        await _central.disconnect(peripheral);
        return;
      }

      GATTCharacteristic? presenceC, inboxC, downlinkC;
      for (final c in svc.characteristics) {
        final u = c.uuid.toString().toLowerCase();
        if (u == kPresenceCharUuid.toLowerCase()) {
          presenceC = c;
        } else if (u == kInboxCharUuid.toLowerCase()) {
          inboxC = c;
        } else if (u == kDownlinkCharUuid.toLowerCase()) {
          downlinkC = c;
        }
      }
      if (presenceC == null || inboxC == null || downlinkC == null) {
        await _central.disconnect(peripheral);
        return;
      }

      final presenceBytes = await _central.readCharacteristic(peripheral, presenceC);
      final info = _parsePresence(presenceBytes);
      if (info == null) {
        await _central.disconnect(peripheral);
        return;
      }

      try {
        await _central.setCharacteristicNotifyState(peripheral, presenceC, state: true);
        await _central.setCharacteristicNotifyState(peripheral, downlinkC, state: true);
      } catch (e) { debugPrint('[BLE] notify state: $e'); }

      _outgoingLinks[info.peerId] = _OutgoingLink(
        peripheral: peripheral,
        inboxChar: inboxC,
      );
      _peripheralKeyToPeerId[key] = info.peerId;

      // Le périphérique ne peut pas nous lire : on s'annonce nous-mêmes.
      await _sendHello(peripheral, inboxC);

      _peerEventsCtrl.add(MeshPeerEvent(
        peerId: info.peerId,
        pseudo: info.pseudo,
        hopCount: 0,
        isConnected: true,
        isGateway: info.isGateway,
        platform: info.platform,
      ));
    } catch (e) {
      debugPrint('[BLE] connect error: $e');
      try { await _central.disconnect(peripheral); } catch (_) {}
    } finally {
      _pendingConnections.remove(key);
    }
  }

  /// Envoie une petite carte de visite (« hello ») pour se présenter
  /// auprès du téléphone auquel on vient de se connecter — indispensable
  /// car, dans ce sens de connexion, LUI ne peut jamais nous demander qui
  /// on est directement.
  Future<void> _sendHello(Peripheral peripheral, GATTCharacteristic inboxChar) async {
    final helloJson = json.encode({
      'peerId': _myId,
      'pseudo': _myPseudo,
      'platform': _platformName,
    });
    final chunks = BleMeshProtocol.encodeMessage(
      messageId: BleMeshProtocol.generateMessageId(),
      hopCount: 0,
      type: kHelloType,
      payload: BleMeshProtocol.encodePayload(helloJson),
    );
    for (final chunk in chunks) {
      try {
        await _central.writeCharacteristic(
          peripheral,
          inboxChar,
          value: chunk,
          type: GATTCharacteristicWriteType.withoutResponse,
        );
      } catch (e) {
        debugPrint('[BLE] hello write: $e');
        break;
      }
    }
  }

  /// Un pair auquel on était connecté (en tant que central) vient de se
  /// déconnecter — on nettoie tout ce qu'on savait de lui.
  void _onCentralLinkStateChanged(PeripheralConnectionStateChangedEventArgs e) {
    if (e.state != ConnectionState.disconnected) return;
    final key = e.peripheral.uuid.toString();
    final peerId = _peripheralKeyToPeerId.remove(key);
    _outgoingLinks.remove(peerId);
    _pendingConnections.remove(key);
    if (peerId != null) {
      // ⚠️ PAS DE PSEUDO ICI, ET SURTOUT PAS L'IDENTIFIANT.
      //
      // Une déconnexion ne nous apprend rien sur le nom du pair. Cette
      // ligne passait `pseudo: peerId` faute de mieux — et cette
      // empreinte de clé publique finissait enregistrée comme nom dans
      // la fiche du pair, où plus rien ne pouvait la corriger (voir
      // `_vraiPseudo` dans `MeshTransportService`). La personne
      // s'affichait ensuite sous une suite de caractères hexadécimaux,
      // définitivement.
      //
      // On envoie donc une chaîne vide : « je ne sais pas », ce qui est
      // la vérité, et ce que la couche du dessus sait traiter.
      _peerEventsCtrl.add(MeshPeerEvent(peerId: peerId, pseudo: '', isConnected: false));
    }
  }

  /// Un pair connecté vient d'agiter son drapeau (notify) — on regarde sur
  /// quelle boîte aux lettres, pour savoir si c'est une mise à jour de sa
  /// fiche de présence ou un vrai message.
  void _onCharacteristicNotified(GATTCharacteristicNotifiedEventArgs e) {
    final peerId = _peripheralKeyToPeerId[e.peripheral.uuid.toString()];
    if (peerId == null) return;

    final charUuid = e.characteristic.uuid.toString().toLowerCase();
    if (charUuid == kPresenceCharUuid.toLowerCase()) {
      final info = _parsePresence(e.value);
      if (info != null) {
        _peerEventsCtrl.add(MeshPeerEvent(
          peerId: info.peerId,
          pseudo: info.pseudo,
          isConnected: true,
          isGateway: info.isGateway,
          platform: info.platform,
        ));
      }
      return;
    }
    if (charUuid == kDownlinkCharUuid.toLowerCase()) {
      _handleIncomingChunk(peerId, e.value);
    }
  }

  // ── Rôle périphérique : serveur GATT ────────────────────────────────────

  /// Un pair qui s'était connecté À NOUS (nous en tant que périphérique)
  /// vient de se déconnecter — même nettoyage que côté central, mais dans
  /// l'autre sens.
  void _onPeripheralLinkStateChanged(CentralConnectionStateChangedEventArgs e) {
    if (e.state != ConnectionState.disconnected) return;
    final key = e.central.uuid.toString();
    final peerId = _centralUuidToPeerId.remove(key);
    _incomingLinks.remove(peerId);
    if (peerId != null) {
      // ⚠️ PAS DE PSEUDO ICI, ET SURTOUT PAS L'IDENTIFIANT.
      //
      // Une déconnexion ne nous apprend rien sur le nom du pair. Cette
      // ligne passait `pseudo: peerId` faute de mieux — et cette
      // empreinte de clé publique finissait enregistrée comme nom dans
      // la fiche du pair, où plus rien ne pouvait la corriger (voir
      // `_vraiPseudo` dans `MeshTransportService`). La personne
      // s'affichait ensuite sous une suite de caractères hexadécimaux,
      // définitivement.
      //
      // On envoie donc une chaîne vide : « je ne sais pas », ce qui est
      // la vérité, et ce que la couche du dessus sait traiter.
      _peerEventsCtrl.add(MeshPeerEvent(peerId: peerId, pseudo: '', isConnected: false));
    }
  }

  /// Quelqu'un demande à lire notre fiche de présence — on lui répond avec
  /// nos informations (qui je suis).
  Future<void> _onReadRequested(GATTCharacteristicReadRequestedEventArgs e) async {
    if (e.characteristic.uuid.toString().toLowerCase() != kPresenceCharUuid.toLowerCase()) {
      return;
    }
    try {
      final bytes = _buildPresenceBytes();
      final offset = e.request.offset.clamp(0, bytes.length);
      await _peripheral.respondReadRequestWithValue(e.request, value: bytes.sublist(offset));
    } catch (err) { debugPrint('[BLE] respond read: $err'); }
  }

  /// Quelqu'un vient de nous écrire quelque chose dans notre boîte
  /// « inbox ». Si c'est une carte de visite (« hello »), on note qui
  /// c'est. Sinon, si on sait déjà qui écrit, on transmet le message reçu
  /// au reste de l'app.
  Future<void> _onWriteRequested(GATTCharacteristicWriteRequestedEventArgs e) async {
    if (e.characteristic.uuid.toString().toLowerCase() != kInboxCharUuid.toLowerCase()) {
      return;
    }

    final decoded = BleMeshProtocol.decodeChunk(e.request.value, _assemblies);

    try {
      await _peripheral.respondWriteRequest(e.request);
    } catch (err) { debugPrint('[BLE] respond write: $err'); }

    if (decoded == null) return;
    final central = e.central;
    final key = central.uuid.toString();

    if (decoded.type == kHelloType) {
      try {
        final helloJson = json.decode(BleMeshProtocol.decodePayload(decoded.payload))
            as Map<String, dynamic>;
        final peerId = helloJson['peerId'] as String?;
        if (peerId == null || peerId == _myId) return;
        final pseudo = helloJson['pseudo'] as String? ?? peerId;
        final platform = helloJson['platform'] as String? ?? 'unknown';

        _centralUuidToPeerId[key] = peerId;
        _incomingLinks[peerId] = _IncomingLink(central: central);

        _peerEventsCtrl.add(MeshPeerEvent(
          peerId: peerId,
          pseudo: pseudo,
          isConnected: true,
          platform: platform,
        ));
      } catch (err) { debugPrint('[BLE] hello parse: $err'); }
      return;
    }

    final peerId = _centralUuidToPeerId[key];
    if (peerId == null) return; // Pair pas encore identifié (hello pas reçu) : ignoré.
    _incomingDataCtrl.add(MeshIncomingData(
      messageId: decoded.messageId,
      peerId: peerId,
      data: decoded.payload,
    ));
  }

  /// Redit « coucou, toujours là » à tous les pairs connectés à nous en ce
  /// moment (envoi toutes les 5 secondes, voir `start()`).
  void _pushPresenceToSubscribers() {
    if (!_isRunning || _incomingLinks.isEmpty) return;
    final bytes = _buildPresenceBytes();
    for (final link in _incomingLinks.values) {
      _peripheral
          .notifyCharacteristic(link.central, _presenceChar, value: bytes)
          .catchError((e) => debugPrint('[BLE] notify presence: $e'));
    }
  }

  /// Fabrique la « carte de visite » qu'on montre aux autres : mon
  /// identifiant, mon pseudo, ma plateforme (Android/iOS).
  Uint8List _buildPresenceBytes() {
    final payload = json.encode({
      'peerId': _myId,
      'pseudo': _myPseudo,
      'platform': _platformName,
      // Le rôle gateway/super-peer n'est pas propagé à ce niveau — c'est
      // une limitation préexistante : MeshTransportService ne transmet pas
      // le rôle courant à BleMeshTransport.start(). Sans conséquence sur la
      // découverte/connectivité, seulement sur l'affichage du badge gateway.
      'isGateway': false,
    });
    return BleMeshProtocol.encodePayload(payload);
  }

  /// Relit une carte de visite reçue et la transforme en informations
  /// utilisables — ou `null` si elle est illisible ou si c'est... la
  /// nôtre (on s'ignore soi-même).
  _PeerInfo? _parsePresence(Uint8List bytes) {
    try {
      final map = json.decode(BleMeshProtocol.decodePayload(bytes)) as Map<String, dynamic>;
      final peerId = map['peerId'] as String?;
      if (peerId == null || peerId == _myId) return null;
      return _PeerInfo(
        peerId: peerId,
        pseudo: map['pseudo'] as String? ?? peerId,
        platform: map['platform'] as String? ?? 'unknown',
        isGateway: map['isGateway'] as bool? ?? false,
      );
    } catch (e) {
      debugPrint('[BLE] parse presence: $e');
      return null;
    }
  }

  void _handleIncomingChunk(String peerId, Uint8List chunk) {
    final decoded = BleMeshProtocol.decodeChunk(chunk, _assemblies);
    if (decoded == null) return;
    _incomingDataCtrl.add(MeshIncomingData(
      messageId: decoded.messageId,
      peerId: peerId,
      data: decoded.payload,
    ));
  }

  // ── Envoi (API publique utilisée par MeshTransportService) ──────────────

  /// Envoie des données à un pair précis — en choisissant automatiquement
  /// le bon sens (est-ce lui qui s'est connecté à moi, ou moi à lui ?).
  /// Envoie [data] à [peerId]. **Renvoie `false` si rien n'est parti.**
  ///
  /// ⚠️ CETTE VALEUR DE RETOUR EST LE CORRECTIF D'UN DÉFAUT GRAVE.
  ///
  /// Cette méthode ne rendait rien. Ses trois refus — contenu interdit,
  /// charge trop grosse, pair inconnu — se contentaient d'un
  /// `debugPrint` suivi d'un `return`. La couche du dessus n'avait donc
  /// AUCUN moyen de savoir qu'un message venait d'être jeté : elle le
  /// comptait comme livré, l'interface affichait deux coches, et le
  /// message n'avait jamais quitté l'appareil.
  ///
  /// Mesuré au banc d'essai (`test/two_peer_session_test.dart`) : sur un
  /// lot de 130 envois, la file en annonçait 130 livrés quand le pair
  /// n'en avait reçu que 110.
  Future<bool> sendToPeer(String peerId, Uint8List data, {int type = 0x00}) async {
    // ── Séparation stricte des rôles (A2.1) ──────────────────────────
    // BLE ne porte jamais de fichier ni de flux audio.
    if (type >= 0x20) {
      debugPrint('[BLE] Refusé : type contenu 0x${type.toRadixString(16)} '
          'sur BLE — nécessite Wi‑Fi');
      return false;
    }
    if (data.length > _maxPayloadSize) {
      debugPrint('[BLE] Refusé : payload ${data.length}o dépasse la '
          'limite BLE de $_maxPayloadSize o');
      return false;
    }

    // Si on s'est connecté À LUI (nous, central), on lui écrit directement.
    final out = _outgoingLinks[peerId];
    if (out != null) {
      return _sendChunks(data, type, (chunk) => _central.writeCharacteristic(
            out.peripheral,
            out.inboxChar,
            value: chunk,
            type: GATTCharacteristicWriteType.withoutResponse,
          ));
    }

    // Sinon, si c'est LUI qui s'est connecté à nous, on ne peut que lui
    // « agiter un drapeau » (notify) sur sa boîte downlink.
    final inc = _incomingLinks[peerId];
    if (inc != null) {
      return _sendChunks(data, type,
          (chunk) => _peripheral.notifyCharacteristic(inc.central, _downlinkChar, value: chunk));
    }

    debugPrint('[BLE] sendToPeer $peerId: pair inconnu');
    return false;
  }

  /// Découpe les données en petits morceaux (chunks) et les envoie un par
  /// un, dans l'ordre — s'arrête proprement au premier échec plutôt que
  /// de continuer à envoyer des morceaux dans le vide.
  /// Renvoie `true` seulement si TOUS les morceaux sont partis.
  ///
  /// Un message coupé en route est un message perdu : le destinataire ne
  /// pourra jamais le rassembler. Interrompre l'envoi au premier échec
  /// est la bonne décision, mais il faut le DIRE — sinon la couche du
  /// dessus croit avoir tout envoyé alors qu'il manque la moitié.
  Future<bool> _sendChunks(
    Uint8List data,
    int type,
    Future<void> Function(Uint8List chunk) send,
  ) async {
    final chunks = BleMeshProtocol.encodeMessage(
      messageId: BleMeshProtocol.generateMessageId(),
      hopCount: 0,
      type: type,
      payload: data,
    );
    for (final chunk in chunks) {
      try {
        await send(chunk);
      } catch (e) {
        debugPrint('[BLE] $e');
        return false;
      }
    }
    return true;
  }

  void dispose() {
    _presenceNotifyTimer?.cancel();
    _scanCycleTimer?.cancel();
    _discoveredSub?.cancel();
    _centralLinkSub?.cancel();
    _notifiedSub?.cancel();
    _peripheralLinkSub?.cancel();
    _readReqSub?.cancel();
    _writeReqSub?.cancel();
    _peerEventsCtrl.close();
    _incomingDataCtrl.close();
  }
}

/// Un pair auquel ON s'est connecté (nous en tant que central) — on garde
/// sa référence Bluetooth et sa boîte aux lettres « inbox » pour pouvoir
/// lui écrire.
class _OutgoingLink {
  final Peripheral peripheral;
  final GATTCharacteristic inboxChar;

  const _OutgoingLink({required this.peripheral, required this.inboxChar});
}

/// Un pair qui S'EST connecté à nous (nous en tant que périphérique) — on
/// garde juste sa référence Bluetooth pour pouvoir lui notifier des données.
class _IncomingLink {
  final Central central;

  const _IncomingLink({required this.central});
}

/// Les informations d'identité lues depuis la carte de visite (fiche de
/// présence) d'un pair.
class _PeerInfo {
  final String peerId;
  final String pseudo;
  final String platform;
  final bool isGateway;

  const _PeerInfo({
    required this.peerId,
    required this.pseudo,
    required this.platform,
    this.isGateway = false,
  });
}
