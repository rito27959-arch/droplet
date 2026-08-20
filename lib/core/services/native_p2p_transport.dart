// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est le troisième et dernier chemin de communication de Droplet (après
// le Bluetooth et le Wi-Fi local) : la technologie « Nearby Connections »
// (Wi-Fi Direct sur Android, Multipeer Connectivity sur iPhone), fournie
// directement par le système du téléphone. Elle permet à deux téléphones
// de se connecter DIRECTEMENT l'un à l'autre, sans routeur Wi-Fi entre les
// deux, et avec un débit plus rapide que le Bluetooth — pratique pour les
// appels et les gros fichiers.
//
// Correctif important (bug d'identité + de données binaires corrigé) :
// contrairement à ce que ce fichier faisait avant, il fait maintenant une
// vraie « poignée de main » (handshake) juste après la connexion — un
// petit message « bonjour, je m'appelle... » qui donne notre VRAI
// identifiant Droplet (le même que celui utilisé par le Bluetooth et le
// Wi-Fi local) au lieu de se contenter de l'identifiant technique fourni
// par le système (`device.info.id`, souvent une adresse Bluetooth brute
// comme « a2:8c:fd:86:bc:b8 »). Sans cette poignée de main, l'appareil en
// face ne pouvait jamais faire le lien entre « ce voisin Nearby juste à
// côté » et « cette personne dans mon carnet de contacts » — ce qui
// cassait la résolution de la clé de chiffrement (messages illisibles) et
// la vérification de qui est joignable pour un appel.
//
// Second correctif : tout ce qui transite par ce transport passe
// maintenant par un petit « emballage » en base64 avant l'envoi. Avant,
// les paquets mesh (souvent des octets binaires bruts — photos, messages
// vocaux, contenu chiffré) étaient envoyés tels quels via une API de
// « message texte », qui suppose du texte lisible (UTF-8) — dès qu'un
// paquet contenait un octet qui ne correspond à aucune lettre valide (très
// fréquent avec des données binaires), l'envoi échouait silencieusement.
// Le base64 transforme n'importe quelle suite d'octets en texte toujours
// valide, comme mettre un colis fragile dans une boîte standard avant de
// l'envoyer par la poste.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:nearby_service/nearby_service.dart';
import 'ble_mesh_protocol.dart';

/// Stratégie de topologie Nearby Connections — comment se comporter face à
/// plusieurs appareils repérés en même temps.
enum NearbyStrategy {
  /// Diffusion mesh à plusieurs pairs (M:N, débit plus faible).
  /// Utilisé pour la propagation de contenu en essaim.
  ///
  /// Comme une conversation de groupe : on parle à plusieurs personnes à
  /// la fois, donc chacun reçoit un peu moins de débit.
  cluster,

  /// Lien direct entre deux appareils (débit maximal).
  /// Utilisé pour les appels et transferts ciblés.
  ///
  /// Comme un appel téléphonique en tête-à-tête : toute la ligne est
  /// réservée à une seule personne, donc la qualité est meilleure.
  pointToPoint,
}

/// Transport P2P natif same-OS pour OURO PREP.
///
/// Encapsule `nearby_service` (Wi‑Fi Direct Android / Multipeer Connectivity
/// iOS) derrière la même interface que les autres transports.
///
/// ## Stratégie (A2.2)
/// - `cluster` (P2P_CLUSTER) pour la diffusion mesh à plusieurs pairs
/// - `pointToPoint` (P2P_POINT_TO_POINT) pour appels et transferts ciblés
///
/// ## Séparation des rôles
/// - Découverte BLE → négociation Wi-Fi → Nearby Connections pour le contenu
/// - BLE ne porte jamais de fichier ni flux audio
///
/// ## Identité (voir le bandeau en tête de fichier)
/// Chaque pair passe par deux états : « vu par le système » (identifié par
/// son `nearbyId` technique, dans [_connectedPeers]) puis, une fois la
/// poignée de main reçue, « identifié dans le mesh » (son vrai
/// [_NativePeer.realPeerId] Droplet, indexé aussi dans
/// [_peerIdToNearbyId]). Aucun événement `MeshPeerEvent` n'est émis avant
/// ce second état — le reste de l'app ne doit jamais voir un pair sous son
/// identifiant technique brut.
class NativeP2PTransport {
  bool _isRunning = false;
  bool get isRunning => _isRunning;
  String _myId = '';
  String _myPseudo = '';

  /// Stratégie active : cluster (défaut) ou pointToPoint.
  NearbyStrategy _strategy = NearbyStrategy.cluster;

  final _peerEventsCtrl = StreamController<MeshPeerEvent>.broadcast();
  final _incomingDataCtrl = StreamController<MeshIncomingData>.broadcast();

  Stream<MeshPeerEvent> get peerEvents => _peerEventsCtrl.stream;
  Stream<MeshIncomingData> get incomingData => _incomingDataCtrl.stream;

  NearbyService? _service;
  final Map<String, _NativePeer> _connectedPeers = {};

  /// Retrouve rapidement le `nearbyId` technique à partir du vrai
  /// identifiant Droplet — nécessaire car [sendToPeer] reçoit toujours le
  /// vrai identifiant (comme les deux autres transports), mais l'API
  /// `nearby_service` a besoin du `nearbyId` pour router l'envoi.
  final Map<String, String> _peerIdToNearbyId = {};

  StreamSubscription<List<NearbyDevice>>? _peersSub;
  bool _hasPtpPeer = false;

  // ── Régulation des tentatives de connexion ───────────────────────
  //
  // ⚠️ SANS CE QUI SUIT, LE TRANSPORT SE BLOQUE LUI-MÊME.
  //
  // Le flux `getPeersStream()` réémet la liste des appareils visibles
  // CHAQUE SECONDE. La version précédente relançait une connexion pour
  // chaque appareil pas encore connecté à chacune de ces émissions.
  //
  // Or la couche native ne sait traiter qu'UNE opération de connexion à
  // la fois : la deuxième est refusée avec `BUSY`. Le refus était avalé
  // en silence, l'appareil restait donc « pas encore connecté », et une
  // nouvelle tentative repartait la seconde suivante. Sur un vrai
  // téléphone, cela donnait, indéfiniment :
  //
  //     [NativeP2P] peers updated: 2 devices
  //     [NearbyService]: Got error from native platform with status=BUSY
  //     [NativeP2P] peers updated: 2 devices
  //     [NearbyService]: Got error from native platform with status=BUSY
  //     ... une fois par seconde, pour toujours
  //
  // La connexion ne pouvait JAMAIS aboutir, puisque chaque tentative
  // occupait la pile native que la suivante trouvait occupée. Le
  // Wi-Fi Direct ne fonctionnait donc pas du tout, tout en consommant
  // du processeur et de la batterie en permanence.
  //
  // Trois garde-fous, qui se complètent :

  /// 1. UNE SEULE tentative à la fois, toutes cibles confondues.
  bool _connecting = false;

  /// 2. Un délai d'attente par appareil, doublé à chaque échec.
  final Map<String, DateTime> _retryAfter = {};
  final Map<String, int> _failures = {};

  /// Premier délai après un échec, puis 4 s, 8 s, 16 s… jusqu'au
  /// plafond. Le plafond compte autant que le doublement : un appareil
  /// hors de portée ne doit pas être réessayé toutes les secondes, mais
  /// il doit continuer d'être réessayé — quelqu'un peut se rapprocher.
  static const Duration _retryBase = Duration(seconds: 2);
  static const Duration _retryMax = Duration(minutes: 2);

  /// Définit la stratégie de topologie.
  ///
  /// - `cluster` (défaut) — accepte plusieurs pairs. Adapté à la
  ///   diffusion mesh M:N et au relais de contenu (débit plus faible).
  /// - `pointToPoint` — une seule connexion à la fois. Débit maximal
  ///   pour les appels et transferts ciblés.
  void setStrategy(NearbyStrategy strategy) {
    _strategy = strategy;
    if (strategy == NearbyStrategy.pointToPoint) {
      // En mode pointToPoint, on se déconnecte des pairs existants
      // sauf un (géré par l'appelant qui choisit la cible).
      _hasPtpPeer = false;
    }
  }

  /// Allume ce transport : demande les autorisations nécessaires, prépare
  /// le service natif du téléphone, puis lance la recherche des appareils
  /// autour de soi.
  Future<void> start(String myId, String myPseudo) async {
    if (_isRunning) return;
    _isRunning = true;
    _myId = myId;
    _myPseudo = myPseudo;

    debugPrint('[NativeP2P] start() called with id=$myId pseudo=$myPseudo');

    try {
      _service = NearbyService.getInstance();
      debugPrint('[NativeP2P] service instance created');

      if (Platform.isAndroid) {
        debugPrint('[NativeP2P] requesting permissions...');
        final ok = await _service!.android?.requestPermissions() ?? true;
        debugPrint('[NativeP2P] permissions result: $ok');
        if (!ok) {
          debugPrint('[NativeP2P] permissions denied');
          _isRunning = false;
          return;
        }
      }

      debugPrint('[NativeP2P] initializing...');
      final initialized = await _service!.initialize(
        data: NearbyInitializeData(darwinDeviceName: myPseudo),
      );
      debugPrint('[NativeP2P] initialize result: $initialized');
      if (!initialized) {
        _isRunning = false;
        return;
      }

      debugPrint('[NativeP2P] discovering...');
      final discovered = await _service!.discover();
      debugPrint('[NativeP2P] discover result: $discovered');
      if (!discovered) {
        _isRunning = false;
        return;
      }

      // Sur iOS/macOS (Multipeer Connectivity), `discover()` ne démarre
      // qu'UN SEUL rôle à la fois — "browser" (parcourt) ou "advertiser"
      // (s'annonce) — selon `isBrowserValue` (vrai par défaut). Un browser
      // ne voit jamais un autre browser : sans démarrer aussi l'annonce,
      // deux appareils iOS ne se découvrent jamais l'un l'autre. Android
      // n'a pas ce problème (WifiP2pManager fait une découverte symétrique
      // nativement), donc ce bloc ne s'applique qu'à Darwin.
      //
      // `startBrowsing()`/`startAdvertising()` pilotent deux objets natifs
      // indépendants (MCNearbyServiceBrowser / MCNearbyServiceAdvertiser) :
      // en démarrer un second n'arrête pas le premier, donc ce bascule
      // temporaire permet de faire tourner les deux en même temps.
      //
      // ⚠️ Limite non résolue (nécessite un vrai appareil Apple pour
      // vérifier) : `connectById()` envoie une invitation si
      // `isBrowserValue` est vrai au moment de l'appel, ou accepte une
      // invitation reçue s'il est faux. En laissant `isBrowserValue` à
      // `true` après ce bloc, ce transport peut découvrir et être
      // découvert des deux côtés, mais n'accepte pas explicitement les
      // invitations reçues pendant qu'il annonce — à valider/corriger
      // sur device réel iOS.
      final darwin = _service!.darwin;
      if (darwin != null) {
        darwin.setIsBrowser(value: false);
        final advertising = await _service!.discover();
        debugPrint('[NativeP2P] advertising result: $advertising');
        darwin.setIsBrowser(value: true);
      }

      _peersSub?.cancel();
      _peersSub = _service!.getPeersStream().listen((peers) {
        debugPrint('[NativeP2P] peers updated: ${peers.length} devices');
        _onPeersUpdated(peers);
      });

      debugPrint('[NativeP2P] start() completed successfully');
    } catch (e, s) {
      debugPrint('[NativeP2P] start() error: $e\n$s');
      _isRunning = false;
    }
  }

  Future<void> stop() async {
    _isRunning = false;
    _peersSub?.cancel();

    if (_service != null) {
      try {
        for (final peer in _connectedPeers.values) {
          await _service!.disconnectById(peer.nearbyId);
        }
      } catch (e) { debugPrint('[NativeP2P] $e'); }
      await _service!.endCommunicationChannel();
      await _service!.stopDiscovery();

      // Symétrique du bascule dans start() : arrêter aussi l'annonce sur
      // Darwin, sinon MCNearbyServiceAdvertiser continue de tourner après
      // stop().
      final darwin = _service!.darwin;
      if (darwin != null) {
        try {
          darwin.setIsBrowser(value: false);
          await _service!.stopDiscovery();
        } catch (e) { debugPrint('[NativeP2P] $e'); }
        darwin.setIsBrowser(value: true);
      }
    }

    _connectedPeers.clear();
    _peerIdToNearbyId.clear();
    _retryAfter.clear();
    _failures.clear();
    _connecting = false;
  }

  /// Retourne la plateforme actuelle sous forme de chaîne.
  static String get currentPlatform {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    return 'unknown';
  }

  /// La liste des appareils visibles vient de changer — on compare avec
  /// ce qu'on savait avant : ceux qui ont disparu (on prévient le reste de
  /// l'app), et ceux qui sont nouveaux (on tente de s'y connecter).
  void _onPeersUpdated(List<NearbyDevice> peers) {
    if (!_isRunning) return;

    final currentNearbyIds = peers.map(_extractNearbyId).toSet();

    // Pairs disparus — on ne prévient le reste de l'app QUE si la poignée
    // de main avait déjà abouti (sinon aucun `MeshPeerEvent` de connexion
    // n'a jamais été émis pour ce pair, donc rien à annuler).
    final lostNearbyIds = _connectedPeers.keys
        .where((nearbyId) => !currentNearbyIds.contains(nearbyId))
        .toList();
    for (final nearbyId in lostNearbyIds) {
      final info = _connectedPeers.remove(nearbyId);
      final realId = info?.realPeerId;
      if (info != null && realId != null) {
        _peerIdToNearbyId.remove(realId);
        _peerEventsCtrl.add(MeshPeerEvent(
          peerId: realId,
          pseudo: info.pseudo,
          isConnected: false,
          platform: currentPlatform,
        ));
      }
    }

    // Nouveaux pairs.
    //
    // 3. On ne lance qu'UNE tentative par passage, et seulement si
    // aucune autre n'est en cours — voir le grand commentaire sur
    // `_connecting`.
    if (_connecting) return;

    final connectedNearbyIds = _connectedPeers.keys.toSet();
    final now = DateTime.now();

    for (final device in peers) {
      final nearbyId = _extractNearbyId(device);
      if (nearbyId == _myId) continue;
      if (connectedNearbyIds.contains(nearbyId)) continue;

      final waitUntil = _retryAfter[nearbyId];
      if (waitUntil != null && now.isBefore(waitUntil)) continue;

      _connectToDevice(nearbyId, device);
      // Une seule par tour : la couche native ne sait pas en traiter
      // deux, et la seconde ne ferait que provoquer le `BUSY` qu'on
      // cherche précisément à éviter.
      return;
    }
  }

  /// Note un échec et repousse la prochaine tentative pour cet appareil.
  void _noteFailure(String nearbyId) {
    final count = (_failures[nearbyId] ?? 0) + 1;
    _failures[nearbyId] = count;
    final delay = Duration(
      milliseconds: (_retryBase.inMilliseconds * (1 << (count - 1)))
          .clamp(_retryBase.inMilliseconds, _retryMax.inMilliseconds),
    );
    _retryAfter[nearbyId] = DateTime.now().add(delay);
    debugPrint('[NativeP2P] $nearbyId injoignable ($count) — '
        'nouvelle tentative dans ${delay.inSeconds} s');
  }

  /// Une connexion a abouti : on repart de zéro pour cet appareil.
  void _noteSuccess(String nearbyId) {
    _failures.remove(nearbyId);
    _retryAfter.remove(nearbyId);
  }

  /// L'identifiant technique fourni par le système (souvent une adresse
  /// Bluetooth) — sert uniquement à router les appels bas niveau vers
  /// `nearby_service` ; jamais exposé au reste de l'app (voir la poignée
  /// de main dans [_onHandshake], qui fournit le vrai identifiant Droplet).
  String _extractNearbyId(NearbyDevice device) => device.info.id;

  /// Tente de se connecter vraiment à un appareil repéré, puis lui envoie
  /// notre poignée de main dès que le canal de communication est prêt —
  /// le pair n'est annoncé au reste de l'app (`MeshPeerEvent`) que
  /// lorsque SA poignée de main à lui arrive en retour (voir
  /// [_onHandshake]).
  Future<void> _connectToDevice(String nearbyId, NearbyDevice device) async {
    // ── Application de la stratégie de topologie (A2.2) ───────────
    if (_strategy == NearbyStrategy.pointToPoint && _hasPtpPeer) {
      debugPrint('[NativeP2P] Point‑to‑point actif, connexion '
          'refusée pour $nearbyId');
      return;
    }

    _connecting = true;
    try {
      final connected = await _service!.connectById(nearbyId);
      if (!connected) {
        _noteFailure(nearbyId);
        return;
      }

      // Démarrer le canal de communication pour ce pair
      final channelData = NearbyCommunicationChannelData(
        nearbyId,
        messagesListener: NearbyServiceMessagesListener(
          onData: (received) {
            _onMessageReceived(nearbyId, received);
          },
        ),
      );
      await _service!.startCommunicationChannel(channelData);

      _connectedPeers[nearbyId] = _NativePeer(
        nearbyId: nearbyId,
        pseudo: _extractPseudo(device),
      );

      if (_strategy == NearbyStrategy.pointToPoint) {
        _hasPtpPeer = true;
      }

      _noteSuccess(nearbyId);

      // On se présente au pair avec notre VRAI identifiant Droplet — tant
      // que sa réponse n'est pas arrivée, ce pair reste invisible pour le
      // reste de l'app (pas de `MeshPeerEvent`).
      unawaited(_sendHandshake(nearbyId));
    } catch (e) {
      debugPrint('[NativeP2P] connexion à $nearbyId: $e');
      _noteFailure(nearbyId);
    } finally {
      // ⚠️ Dans un `finally` : si le drapeau restait levé après une
      // exception, plus AUCUNE connexion ne serait jamais tentée, et le
      // transport tomberait définitivement muet.
      _connecting = false;
    }
  }

  String _extractPseudo(NearbyDevice device) =>
      device.info.displayName;

  /// Envoie un petit message JSON emballé — `{'k': 'hs', ...}` pour la
  /// poignée de main, `{'k': 'd', 'b': ...}` pour de vraies données mesh
  /// (voir [sendToPeer]). Tout passe par l'API « message texte » de
  /// `nearby_service`, qui exige du texte UTF-8 valide — un JSON encodé
  /// est toujours valide, contrairement aux octets binaires bruts qu'on
  /// pourrait vouloir y glisser directement.
  Future<void> _sendEnvelope(String nearbyId, Map<String, dynamic> envelope) async {
    final peer = _connectedPeers[nearbyId];
    if (_service == null || peer == null) return;
    try {
      final msg = OutgoingNearbyMessage<NearbyMessageTextRequest>(
        content: NearbyMessageTextRequest.create(
          value: json.encode(envelope),
        ),
        receiver: NearbyDeviceInfo(
          id: peer.nearbyId,
          displayName: peer.pseudo,
        ),
      );
      await _service!.send(msg);
    } catch (e) { debugPrint('[NativeP2P] $e'); }
  }

  /// Envoie notre « carte de visite » Droplet (identifiant + pseudo) à ce
  /// pair — la vraie poignée de main qui manquait avant, cause du
  /// problème d'identité/chiffrement pour ce transport.
  Future<void> _sendHandshake(String nearbyId) {
    return _sendEnvelope(nearbyId, {'k': 'hs', 'id': _myId, 'p': _myPseudo});
  }

  /// Un message vient d'arriver par ce transport (via [_service]'s canal
  /// de communication, identifié par le `nearbyId` de son expéditeur) —
  /// on désemballe l'enveloppe JSON pour savoir si c'est une poignée de
  /// main ou de vraies données mesh, et on traite chaque cas séparément.
  void _onMessageReceived(String nearbyId, ReceivedNearbyMessage<NearbyMessageContent> message) {
    final content = message.content;
    if (content is! NearbyMessageTextRequest) return;

    Map<String, dynamic> envelope;
    try {
      envelope = json.decode(content.value) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[NativeP2P] enveloppe invalide reçue de $nearbyId: $e');
      return;
    }

    switch (envelope['k'] as String?) {
      case 'hs':
        _onHandshake(nearbyId, envelope);
      case 'd':
        _onDataEnvelope(nearbyId, envelope);
      default:
        debugPrint('[NativeP2P] enveloppe de type inconnu ignorée: ${envelope['k']}');
    }
  }

  /// Reçoit la « carte de visite » Droplet d'un pair déjà connecté au
  /// niveau système : enregistre son vrai identifiant, et — seulement la
  /// toute première fois — prévient le reste de l'app qu'un nouveau pair
  /// est joignable (avec son VRAI identifiant, jamais le `nearbyId`
  /// technique).
  void _onHandshake(String nearbyId, Map<String, dynamic> envelope) {
    final realId = envelope['id'] as String?;
    if (realId == null || realId == _myId) return;
    final peer = _connectedPeers[nearbyId];
    if (peer == null) return;

    final pseudo = envelope['p'] as String? ?? peer.pseudo;
    final isFirstHandshake = peer.realPeerId == null;
    peer.realPeerId = realId;
    peer.pseudo = pseudo;
    _peerIdToNearbyId[realId] = nearbyId;

    debugPrint('[NativeP2P] poignée de main reçue: $nearbyId → $realId ($pseudo)');

    if (isFirstHandshake) {
      _peerEventsCtrl.add(MeshPeerEvent(
        peerId: realId,
        pseudo: pseudo,
        isConnected: true,
        platform: currentPlatform,
      ));
    }
  }

  /// Reçoit un paquet mesh emballé en base64 : le déballe, puis le
  /// transmet au reste de l'app sous le VRAI identifiant Droplet de son
  /// expéditeur (résolu via la poignée de main) — jamais sous le
  /// `nearbyId` technique.
  void _onDataEnvelope(String nearbyId, Map<String, dynamic> envelope) {
    final realId = _connectedPeers[nearbyId]?.realPeerId;
    if (realId == null) {
      // Donnée arrivée avant que la poignée de main n'ait abouti — ne
      // devrait pas arriver en pratique (la poignée de main part en
      // premier), mais on l'ignore proprement plutôt que de risquer de
      // relayer un message sous une fausse identité.
      debugPrint('[NativeP2P] donnée reçue de $nearbyId avant poignée de main, ignorée');
      return;
    }
    final b64 = envelope['b'] as String?;
    if (b64 == null) return;
    Uint8List data;
    try {
      data = base64Decode(b64);
    } catch (e) {
      debugPrint('[NativeP2P] données base64 invalides de $realId: $e');
      return;
    }

    _incomingDataCtrl.add(MeshIncomingData(
      messageId: BleMeshProtocol.generateMessageId(),
      peerId: realId,
      data: data,
    ));
  }

  /// Envoie un paquet mesh à [peerId] — le VRAI identifiant Droplet, comme
  /// pour les deux autres transports (jamais le `nearbyId` technique).
  /// Envoie [data] à [peerId]. Renvoie `false` si rien n'est parti.
  ///
  /// Le cas « identifiant Nearby inconnu » est fréquent : un pair peut
  /// être connu du mesh par un autre transport sans avoir jamais achevé
  /// sa poignée de main Nearby. Le taire revenait à jeter le message.
  Future<bool> sendToPeer(String peerId, Uint8List data) async {
    final nearbyId = _peerIdToNearbyId[peerId];
    if (nearbyId == null) {
      debugPrint('[NativeP2P] $peerId sans identifiant Nearby connu');
      return false;
    }
    try {
      await _sendEnvelope(nearbyId, {'k': 'd', 'b': base64Encode(data)});
      return true;
    } catch (e) {
      debugPrint('[NativeP2P] envoi vers $peerId impossible: $e');
      return false;
    }
  }

  void dispose() {
    _peersSub?.cancel();
    _peerEventsCtrl.close();
    _incomingDataCtrl.close();
  }
}

/// Un pair connecté via ce transport : son identifiant technique
/// (`nearbyId`, pour parler à l'API du système), et — une fois la
/// poignée de main reçue — son vrai identifiant Droplet ([realPeerId]) et
/// son pseudo tel qu'il se présente lui-même (qui remplace le nom
/// deviné par le système dès que la poignée de main arrive).
class _NativePeer {
  final String nearbyId;
  String pseudo;
  String? realPeerId;

  _NativePeer({
    required this.nearbyId,
    required this.pseudo,
  });
}
