// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Si `mesh_transport_service.dart` est le chef d'orchestre qui fait
// VOYAGER les paquets de données entre les téléphones (par Bluetooth,
// Wi-Fi, ou Nearby), CE fichier est le CERVEAU qui décide QUOI mettre
// dans ces paquets et QUOI FAIRE de ce qu'on reçoit. C'est ici que
// vivent toutes les vraies fonctionnalités de Droplet : envoyer un
// message, publier un statut, créer un groupe, envoyer un fichier,
// signaler qu'on est en sécurité en cas de catastrophe, etc.
//
// Quelques idées importantes à comprendre pour tout le fichier :
//
//   - « Relayer un message » : comme dans le jeu du téléphone arabe (ou
//     une chaîne de personnes qui se passent un seau d'eau), un message
//     ne va pas directement de A à B s'ils ne sont pas côte à côte — il
//     passe de téléphone en téléphone jusqu'à atteindre sa destination
//     (ou jusqu'à épuiser son « nombre de sauts » autorisés, pour ne pas
//     tourner en rond éternellement).
//   - « Message dirigé » (chat privé) : même si un message chiffré pour
//     UNE personne passe par plusieurs autres téléphones en chemin (comme
//     une lettre scellée qui transite par plusieurs bureaux de poste),
//     seul le vrai destinataire peut l'ouvrir et le lire — les autres se
//     contentent de la faire suivre sans pouvoir l'ouvrir.
//   - « Diffusion » (broadcast) : à l'inverse, certaines choses (un
//     statut, un message d'urgence) sont volontairement publiques et
//     doivent atteindre TOUT LE MONDE sur le réseau.
//   - « Sender-key » de groupe : chaque membre d'un groupe a sa propre
//     « chaîne » de clés secrètes qui avance à chaque message envoyé
//     (comme un cadenas à combinaison qui change de code après chaque
//     utilisation) — cela permet à tous les autres membres de suivre et
//     déchiffrer, tout en gardant les anciens messages illisibles pour
//     quelqu'un qui rejoindrait le groupe plus tard.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import '../models/mesh_message.dart';
import '../models/status_media.dart';
import '../sync/sync_negotiation.dart';
import '../network/premium_message_queue.dart';
import '../services/crypto_service.dart';
import '../services/media_service.dart';
import '../services/storage_service.dart';
import '../services/mesh_transport_service.dart';
import '../services/ble_mesh_protocol.dart';
import '../services/call_signaling_service.dart';
import '../../features/nexus_connection/nexus_event.dart';

/// Un message en attente de relais — mis de côté quand on n'a
/// temporairement aucun pair connecté à qui le transmettre.
class _PendingRelay {
  final String id;
  final Uint8List payload;
  _PendingRelay(this.id, this.payload);
}

/// Repository mesh pour Droplet (messagerie + appels 1:1 hors ligne).
///
/// ## Chat dirigé (WhatsApp-like)
/// Chaque message peut cibler un pair précis via [targetId] (wire `t`).
/// - [targetId] null → diffusion mesh (tout le monde)
/// - [targetId] défini → seul le destinataire affiche le message, les autres
///   pairs se contentent de le relayer (store-and-forward) jusqu'à épuisement
///   du TTL (hopCount).
///
/// ## Batterie
/// - ACK batching (regroupe les ACK)
/// - Pas de relay BLE si batterie < 15%
/// - Flush d'outbox différé en background
class MeshRepository {
  /// Par défaut, le vrai service de transport — mais il peut être
  /// remplacé, et c'est ce qui permet de faire tourner un NŒUD COMPLET
  /// de Droplet dans un test : la même logique de messages, d'accusés,
  /// de déduplication et de relais, mais posée sur des transports
  /// simulés au lieu de vraies radios.
  ///
  /// Sans ce point d'injection, mesurer un taux de livraison ou une
  /// latence à vingt nœuds supposait vingt téléphones.
  MeshRepository({MeshTransportService? transport})
      : _transport = transport ?? MeshTransportService();

  final MeshTransportService _transport;
  bool _initialized = false;

  // ── File fiable (retry + backoff exponentiel) ─────────────────────────────
  //
  // Chaque envoi important (message, fichier, statut, check-in sécurité,
  // contrôle de groupe) passe par cette file : en cas d'échec transitoire
  // (transport instable, pair qui bouge), le message est RÉESSAYÉ avec un
  // backoff exponentiel + jitter au lieu d'être perdu — c'est ce qui rend
  // la messagerie fiable « comme sur Internet » même sur un mesh physique
  // capricieux (BLE/Wi-Fi/Nearby). Quand aucun pair n'est joignable, le
  // message reste dans la file (store-and-forward) jusqu'à ce qu'un chemin
  // s'ouvre, jusqu'à épuisement du budget de tentatives.
  PremiumMessageQueue? _queue;
  final Map<String, Completer<void>> _sendOutcomes = {};

  PremiumMessageQueue get _reliableQueue => _queue ??= (PremiumMessageQueue(
        maxRetries: 6,
        defaultTimeout: const Duration(seconds: 30),
        onSend: _reliableOnSend,
        onDelivered: (messageId) => _completeSend(messageId, success: true),
        onFailed: (messageId, reason) => _completeSend(messageId, success: false, reason: reason),
        getCongestionWindow: (peerId) => _transport.protocol.getCongestionWindow(peerId),
        debugLog: debugPrint,
      )..start());

  /// Transmet réellement un paquet sur le mesh. « Succès » = le paquet a
  /// été accepté par AU MOINS un pair connecté (il est sur le fil — les
  /// relais le feront suivre vers la destination). S'il n'y a aucun pair
  /// joignable, retourne false → la file réessaiera plus tard.
  ///
  /// Routage adaptatif : un message dirigé (targetId ≠ broadcast) passe
  /// d'abord par un envoi CIBLÉ (direct ou via le prochain saut connu du
  /// protocole v2) au lieu de la diffusion massive ; on ne retombe sur le
  /// flooding classique que si aucune route n'existe (découverte).
  Future<bool> _reliableOnSend(SendTask task) async {
    final interestGroups = task.context is Set<String>
        ? (task.context as Set<String>).cast<String>()
        : null;

    final payload = Uint8List.fromList(task.payload);
    final type = payload.length > 1 ? payload[1] : 0x00;
    final activePeers = _transport.activePeerCount;

    debugPrint('[MeshRepo] _reliableOnSend msg=${task.messageId} '
        'target=${task.targetId} type=0x${type.toRadixString(16)} '
        'size=${payload.length}o activePeers=$activePeers '
        'groups=$interestGroups');

    if (task.targetId != 'broadcast') {
      try {
        final routed = await _transport.sendViaRoute(
          task.targetId, payload, type: type, priority: task.priority.value);
        if (routed) {
          debugPrint('[MeshRepo] routage OK vers ${task.targetId}');
          return true;
        }
      } catch (e) {
        debugPrint('[MeshRepo] routage vers ${task.targetId} échoué: $e');
      }
    }

    try {
      final result = await _transport.broadcastToConnectedPeers(
        payload,
        interestGroups: interestGroups,
        type: type,
      );
      debugPrint('[MeshRepo] diffusion ${result ? "OK" : "ÉCHEC"} '
          'msg=${task.messageId}');
      return result;
    } catch (e) {
      debugPrint('[MeshRepo] diffusion exception: $e');
      return false;
    }
  }

  /// Enfile [data] dans la file fiable et attend son issue : le Future se
  /// résout quand le message est sur le fil, ou lève une exception après
  /// épuisement des tentatives (ou timeout). Retourne l'ID utilisé.
  Future<String> _enqueueReliable({
    required String messageId,
    required String targetId,
    required Uint8List data,
    MessagePriority priority = MessagePriority.normal,
    Set<String>? interestGroups,
    Duration? timeout,
  }) async {
    final completer = Completer<void>();
    _sendOutcomes[messageId] = completer;
    _reliableQueue.enqueue(
      messageId: messageId,
      targetId: targetId,
      payload: data,
      priority: priority,
      context: interestGroups,
    );
    try {
      // ⚠️ LE TIMEOUT DOIT COUVRIR LE BUDGET COMPLET DES RETRIES.
      //
      // La file fait 6 tentatives avec backoff exponentiel (100ms → 3.2s)
      // et un timeout de 30s par tentative. Le timeout total est donc
      // d'environ 6 × 30s + backoff ≈ 186s. Si le timeout ici est
      // inférieur, le Completer se résout avant que la file ait fini
      // ses retries, et le message est marqué « échoué » alors qu'un
      // envoi ultérieur pourrait réussir.
      await completer.future.timeout(
          timeout ?? const Duration(seconds: 180));
    } on TimeoutException {
      _completeSend(messageId);
      _reliableQueue.cancel(messageId);
      throw StateError('Délai dépassé pour l\'envoi du message $messageId');
    }
    return messageId;
  }

  void _completeSend(String messageId, {bool success = true, String? reason}) {
    final completer = _sendOutcomes.remove(messageId);
    if (completer == null || completer.isCompleted) {
      if (completer == null) {
        debugPrint('[MeshRepo] _completeSend $messageId: deja retire (null)');
      }
      return;
    }
    if (success) {
      debugPrint('[MeshRepo] _completeSend $messageId: SUCCES');
      completer.complete();
    } else {
      debugPrint('[MeshRepo] _completeSend $messageId: ECHEC ($reason)');
      completer.completeError(
        StateError(reason ?? 'Échec de l\'envoi du message $messageId'),
      );
    }
  }

  Set<String> _seenMessageIds = {};
  final Map<String, DateTime> _appMessageIds = {};
  final Map<String, int> _ackCounts = {};
  static const Duration _seenIdMaxAge = Duration(days: 7);

  String _myId = '';
  String _myPseudo = '';
  String? _myPublicKey;

  /// Émet l'ID d'un pair dont la clé publique vient d'être établie
  /// (échange de clés terminé — le chiffrement de bout en bout est
  /// désormais possible avec ce pair).
  final _peerKeyReadyCtrl = StreamController<String>.broadcast();
  Stream<String> get peerKeyReadyEvents => _peerKeyReadyCtrl.stream;

  /// Émet l'ID d'un groupe dont l'état local (métadonnées, membres) vient
  /// de changer — création, ajout/retrait de membre, renommage, synchro
  /// reçue d'un autre membre.
  final _groupsChangedCtrl = StreamController<String>.broadcast();
  Stream<String> get groupsChangedEvents => _groupsChangedCtrl.stream;

  /// Émet les événements Nexus reçus d'un pair distant.
  final _nexusEventCtrl = StreamController<NexusEvent>.broadcast();
  Stream<NexusEvent> get nexusEvents => _nexusEventCtrl.stream;

  /// Émet les modifications de message reçues d'un pair distant.
  /// Payload: (messageId, newContent).
  final _editCtrl = StreamController<({String messageId, String newContent})>.broadcast();
  Stream<({String messageId, String newContent})> get editEvents => _editCtrl.stream;

  /// Émet chaque message affichable déchiffré et persisté (1:1, diffusion,
  /// groupe, fichier) — source unique pour l'UI (`MeshNotifier`), qui ne
  /// décode plus le flux brut elle-même. Évite qu'un déchiffrement ou un
  /// ratchet (groupe) ne s'exécute deux fois indépendamment.
  final _newMessageCtrl = StreamController<MeshMessage>.broadcast();
  Stream<MeshMessage> get newMessageEvents => _newMessageCtrl.stream;

  Stream<ConnectedPeer>? get peerEvents => _transport.peerEvents;
  Stream<MeshIncomingData>? get incomingData => _transport.incomingData;

  /// Émet la première fois qu'un pair se connecte dans cette session.
  ///
  /// Utilisé par le Nexus pour déclencher l'animation de connexion.
  /// Les pairs déjà connus avant le lancement de l'app ne déclenchent
  /// rien — on ne veut pas revoir l'animation à chaque redémarrage.
  final _firstPeerCtrl = StreamController<ConnectedPeer>.broadcast();
  Stream<ConnectedPeer> get firstPeerConnection => _firstPeerCtrl.stream;
  final Set<String> _connectedThisSession = {};

  /// Pair premier né de la session, en attente que le dashboard s'abonne.
  /// Le broadcast stream perd les événements émis avant le premier
  /// auditeur — si le mesh trouve un pair pendant que le dashboard
  /// n'a pas encore initialisé son écoute, `_firstPeerCtrl.add()` tombe
  /// dans le vide. On le sauvegarde ici pour le rejouer dès l'abonnement.
  ConnectedPeer? _pendingFirstPeer;
  MeshTransportService get transport => _transport;

  /// Récupère et consomme le premier pair connecté s'il a été détecté
  /// avant l'abonnement du dashboard au stream broadcast.
  /// Retourne null s'il n'y en a pas (le dashboard s'est abonné à temps).
  ConnectedPeer? consumePendingFirstPeer() {
    final p = _pendingFirstPeer;
    _pendingFirstPeer = null;
    return p;
  }

  String get myId => _myId;
  String get myPseudo => _myPseudo;

  int get connectedPeers => _transport.connectedPeerCount;
  int get blePeerCount => _transport.blePeerCount;
  int get wifiPeerCount => _transport.wifiPeerCount;
  List<ConnectedPeer> get peerList => _transport.connectedPeers;
  int get peersEverSeen => _transport.peersEverSeen;

  int getAckCount(String messageId) => _ackCounts[messageId] ?? 0;

  final _ackCtrl = StreamController<String>.broadcast();
  Stream<String> get ackEvents => _ackCtrl.stream;

  /// Signaux de frappe reçus (émet l'ID du pair qui tape).
  final _typingCtrl = StreamController<String>.broadcast();
  Stream<String> get typingEvents => _typingCtrl.stream;

  /// Accusés de lecture reçus (émet l'ID du message lu).
  final _readCtrl = StreamController<String>.broadcast();
  Stream<String> get readEvents => _readCtrl.stream;

  /// Réactions reçues (émet (messageId, emoji)).
  final _reactionCtrl = StreamController<({String messageId, String emoji})>.broadcast();
  Stream<({String messageId, String emoji})> get reactionEvents => _reactionCtrl.stream;

  /// Check-in "je suis en sécurité" reçus (mode urgence/catastrophe).
  final _safetyCheckinCtrl = StreamController<SafetyCheckinRecord>.broadcast();
  Stream<SafetyCheckinRecord> get safetyCheckinEvents => _safetyCheckinCtrl.stream;

  /// Statuts éphémères reçus.
  final _statusCtrl = StreamController<MeshStatusRecord>.broadcast();
  Stream<MeshStatusRecord> get statusEvents => _statusCtrl.stream;

  /// Accusé de vue reçu pour un de MES statuts (émet le statusId concerné).
  final _statusSeenCtrl = StreamController<String>.broadcast();
  Stream<String> get statusSeenEvents => _statusSeenCtrl.stream;

  /// Un média de statut vient d'arriver en entier (émet son fileId).
  ///
  /// L'annonce d'un statut et son média voyagent séparément, et la
  /// première arrive presque toujours en premier — elle ne pèse que
  /// quelques centaines d'octets là où une photo en pèse des centaines
  /// de milliers. La visionneuse affiche donc d'abord un cadre vide, et
  /// c'est ce signal qui lui dit que l'image est enfin là.
  final _statusMediaCtrl = StreamController<String>.broadcast();
  Stream<String> get statusMediaEvents => _statusMediaCtrl.stream;

  /// « J'aime » ou commentaire reçu sur l'un de MES statuts.
  final _statusFeedbackCtrl = StreamController<StatusFeedback>.broadcast();
  Stream<StatusFeedback> get statusFeedbackEvents => _statusFeedbackCtrl.stream;

  /// ⚠️ AJOUTÉ — filet de sécurité pour les diffusions qui échouent
  /// définitivement.
  ///
  /// `sendStatus` et `sendSafetyCheckin` passent par `_enqueueReliable`,
  /// qui — après épuisement de son budget de tentatives (six essais sur
  /// ~180 s) — se termine par une `Future` en erreur (`StateError`), pas
  /// par un simple retour `false`. Contrairement à `sendMessage`/`sendFile`
  /// (gérés côté `mesh_provider.dart` avec un `try/catch` qui marque le
  /// message `failed` et prévient l'utilisateur), ces deux fonctions
  /// n'attrapaient rien : une diffusion de statut, ou pire, un CHECK-IN
  /// DE SÉCURITÉ qui échoue à joindre le moindre pair pendant trois
  /// minutes, levait une exception que rien, dans ce paquet, ne
  /// garantissait de rattraper.
  ///
  /// Ce flux est un filet de sécurité additif : il ne remplace pas la
  /// gestion d'erreur que l'écran appelant peut déjà faire (l'exception
  /// continue d'être relancée, `await` la verra toujours) — il donne en
  /// PLUS un point d'écoute fiable, au niveau du dépôt, pour qu'une
  /// notification de secours (`NotificationService.showSendFailed`, déjà
  /// prévue pour ce cas précis) puisse être déclenchée même si l'écran
  /// d'origine ne s'attendait pas à cet échec.
  final _criticalSendFailureCtrl = StreamController<({String kind, String messageId, String reason})>.broadcast();
  Stream<({String kind, String messageId, String reason})> get criticalSendFailureEvents =>
      _criticalSendFailureCtrl.stream;

  /// Purge les IDs de messages vus depuis trop longtemps.
  Timer? _pruneTimer;

  /// Le minuteur des annonces de routes — voir `_annoncerRoutes`.
  Timer? _routeTimer;

  /// Toutes les 6 heures, on fait le ménage dans la mémoire des messages
  /// « déjà vus » — sinon cette liste grossirait indéfiniment et
  /// ralentirait l'app avec le temps (voir [_pruneSeenIds]).
  void _startPruneTimer() {
    _pruneTimer?.cancel();
    _pruneTimer = Timer.periodic(const Duration(hours: 6), (_) {
      _pruneSeenIds();
      unawaited(StorageService.pruneExpiredStatuses());
    });

    // ⚠️ LA CADENCE EST UN COMPROMIS, PAS UN CHIFFRE ROND.
    //
    // Trop rapide, on réveille toutes les radios à portée pour répéter
    // des informations qui n'ont pas bougé — sur une app dont l'autonomie
    // est un argument, c'est inacceptable. Trop lente, une route apprise
    // reste périmée après le départ d'un relais, et des messages partent
    // vers un chemin qui n'existe plus.
    //
    // Quarante-cinq secondes : de l'ordre du délai de grâce accordé à un
    // pair qui disparaît, pour que les deux notions vieillissent au même
    // rythme.
    _routeTimer?.cancel();
    _routeTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      unawaited(_annoncerRoutes().catchError(
          (e) => debugPrint('[MeshRepo] annonce de routes: $e')));
    });
  }

  Future<void> _pruneSeenIds() async {
    await StorageService.pruneSeenMessageIds(maxAge: _seenIdMaxAge);
    _seenMessageIds = StorageService.getSeenMessageIds();

    final cutoff = DateTime.now().subtract(_seenIdMaxAge);
    _appMessageIds.removeWhere((_, seenAt) => seenAt.isBefore(cutoff));

    debugPrint('[MeshRepo] purge IDs vus: ${_seenMessageIds.length} restants, ${_appMessageIds.length} app-ids');
  }

  /// Démarre tout le système : prépare mon identité, allume le transport
  /// mesh (Bluetooth/Wi-Fi/Nearby), et se met à l'écoute de tout ce qui
  /// arrive.
  Future<void> init(String myId, String myPseudo, {
    Set<String>? interestGroups,
  }) async {
    // `_initialized` doit être posé de façon SYNCHRONE avant le premier
    // `await` : sinon, deux appels rapprochés à init() (ex. MeshBootstrap
    // au démarrage + un flux de restauration de sauvegarde juste après)
    // passent tous les deux le test `if (_initialized) return;` avant que
    // le premier ait eu la main pour le positionner, et démarrent chacun
    // leur propre transport mesh en parallèle — doubles binds de socket,
    // doubles abonnements à incomingData/peerEvents (chaque message reçu
    // alors traité deux fois), état corrompu. Observé et reproduit : deux
    // lignes "[MeshRepo] init() id=..." consécutives dès le lancement.
    if (_initialized) return;
    _initialized = true;
    _myId = myId;
    _myPseudo = myPseudo;
    _myPublicKey = await CryptoService.ensureIdentityKeyPair();

    debugPrint('[MeshRepo] init() id=$myId pseudo=$myPseudo groups=$interestGroups');

    _seenMessageIds = StorageService.getSeenMessageIds();
    // Les messages reçus lors d'une session précédente dont on n'avait
    // pas encore la clé. Rechargés AVANT de démarrer le mesh : le
    // premier « hello » venu peut alors les réparer immédiatement.
    _loadPendingDecryptions();

    // Configurer les serveurs Tor (directory + mailbox) AVANT startMesh.
    _transport.configureTorServers(
      directoryUrl: 'http://127.0.0.1:8080',
      mailboxUrl: 'http://127.0.0.1:8081',
    );

    await _transport.startMesh(
      myId,
      myPseudo,
      interestGroups: interestGroups,
    );

    _transport.incomingData.listen((data) {
      _handleIncomingMessage(data).catchError((e) {
        debugPrint('[MeshRepo] erreur traitement message entrant: $e');
      });
    });

    _transport.peerEvents.listen((peer) {
      try {
        // Adapter le nombre de sauts à la densité du mesh.
        MeshRepository.updateAdaptiveHopCount(_transport.connectedPeerCount);
        if (_transport.connectedPeerCount > 0) flushPendingRelays();
        // Première connexion dans cette session → signal Nexus.
        if (_connectedThisSession.add(peer.peerId)) {
          _firstPeerCtrl.add(peer);
          _pendingFirstPeer = peer;
        }
        if (peer.publicKey == null) {
          // Fire-and-forget : un pair qui se déconnecte pendant l'envoi ne
          // doit jamais faire remonter une exception non rattrapée.
          //
          // Hello en DIFFUSION (pas de targetId) : un pair découvert par
          // NativeP2P est identifié par son ID transport (ex. adresse MAC),
          // pas par son ID Droplet. Un hello ciblé sur cet ID transport
          // serait ignoré par le destinataire (targetId ≠ son ID Droplet) —
          // l'échange de clés ne se ferait JAMAIS, et le premier message
          // chiffré échouerait. Diffusé, tout voisin direct le traite.
          unawaited(sendHello()
              .catchError((e) => debugPrint('[MeshRepo] échec hello (diffusion): $e')));
          // Un pair fraîchement rencontré n'a jamais vu mon statut ou mon
          // dernier check-in de sécurité si je les ai diffusés alors que
          // j'étais seul (0 pair connecté) — `sendStatus`/`sendSafetyCheckin`
          // n'envoient qu'une seule fois, sans réessai. On les regossipe donc
          // à chaque nouvelle rencontre plutôt que de les considérer perdus.
          unawaited(_gossipAnnouncementsOnNewPeer()
            .catchError((e) => debugPrint('[MeshRepo] échec regossip vers ${peer.peerId}: $e')));
          // Un nouveau voisin ne sait rien de ce que je sais joindre.
          unawaited(_annoncerRoutes().catchError(
              (e) => debugPrint('[MeshRepo] échec annonce de routes: $e')));
        }
      } catch (e) {
        debugPrint('[MeshRepo] erreur traitement événement pair: $e');
      }
    });

    _loadPendingRelays();
    _startPruneTimer();

    debugPrint('[MeshRepo] init() completed, peers=${_transport.connectedPeerCount}');
  }

  Future<void> dispose() async {
    _pruneTimer?.cancel();
    _routeTimer?.cancel();
    _routeTimer = null;
    // Les accusés en attente sont abandonnés avec leurs minuteurs : sans
    // cela, un minuteur survivait à l'arrêt du mesh et tentait un envoi
    // sur un transport déjà refermé.
    for (final t in _ackBatchTimers.values) {
      t.cancel();
    }
    _ackBatchTimers.clear();
    _ackBatches.clear();
    _queue?.stop();
    _queue = null;
    _sendOutcomes.clear();
    await _transport.stopMesh();
    _initialized = false;
  }

  // ── Accusés de réception (ACK) groupés ──────────────────────────────────
  //
  // Plutôt que de renvoyer un petit accusé « bien reçu » immédiatement
  // pour chaque message (ce qui userait la batterie pour rien si
  // plusieurs messages arrivent d'affilée), on les regroupe pendant 2
  // secondes et on envoie un seul paquet qui dit « j'ai bien reçu ces 5
  // messages-là » — comme accuser réception d'un paquet de lettres d'un
  // coup plutôt qu'une par une.

  /// ⚠️ UN LOT PAR EXPÉDITEUR, PAS UN LOT GLOBAL.
  ///
  /// La version précédente gardait UNE seule liste et UN seul minuteur,
  /// avec le destinataire capturé au moment où le minuteur démarrait.
  /// Conséquence, dès que deux personnes écrivaient dans la même fenêtre
  /// de deux secondes — ce qui est le cas ordinaire dans un groupe :
  ///
  ///   • tous les accusés partaient vers le PREMIER expéditeur, y compris
  ///     ceux qui concernaient les messages du second ;
  ///   • le second n'en recevait aucun : ses messages restaient
  ///     éternellement affichés « envoyé » alors qu'ils étaient bien
  ///     arrivés ;
  ///   • le premier recevait des accusés portant des identifiants de
  ///     messages qu'il n'avait jamais envoyés.
  ///
  /// Autrement dit, l'application affichait des états de livraison faux
  /// dans les deux sens. Chaque expéditeur a donc désormais son propre
  /// lot et son propre minuteur.
  final Map<String, List<String>> _ackBatches = {};
  final Map<String, Timer> _ackBatchTimers = {};

  void _sendAck(String targetPeerId, String originalMessageId) {
    (_ackBatches[targetPeerId] ??= []).add(originalMessageId);
    _ackBatchTimers[targetPeerId] ??= Timer(
      const Duration(milliseconds: 200),
      () => _flushAckBatch(targetPeerId),
    );
  }

  void _flushAckBatch(String targetPeerId) {
    final lot = _ackBatches.remove(targetPeerId);
    _ackBatchTimers.remove(targetPeerId)?.cancel();
    if (lot == null || lot.isEmpty) return;
    final batchPayload = utf8.encode(lot.join(','));
    final packet = Uint8List(2 + batchPayload.length);
    packet[0] = 0;
    packet[1] = kAckType;
    packet.setRange(2, packet.length, batchPayload);
    // Fire-and-forget : le pair a pu se déconnecter entre l'ACK et ce flush
    // 2s plus tard — un échec de tous les transports ne doit jamais
    // remonter comme exception non rattrapée dans ce callback de Timer.
    unawaited(() async {
      try {
        final ok = await _transport.sendToPeer(targetPeerId, packet);
        if (!ok) {
          debugPrint('[MeshRepo] lot d\'ACK non parti vers $targetPeerId');
        }
      } catch (e) {
        debugPrint('[MeshRepo] échec envoi ACK batch à $targetPeerId: $e');
      }
    }());
  }

  // ── Messages entrants ────────────────────────────────────────────────────

  /// Résout la clé publique connue d'un pair (connecté ou persistée). Si
  /// elle est absente, relance une annonce de clé et attend brièvement
  /// [timeout] qu'elle arrive avant d'abandonner.
  Future<String?> _resolvePeerPublicKey(String peerId, {Duration timeout = const Duration(milliseconds: 500)}) async {
    String? key = _peerPublicKeyFromCaches(peerId);
    if (key != null) return key;

    unawaited(sendHello(targetId: peerId)
        .catchError((e) => debugPrint('[MeshRepo] échec hello vers $peerId: $e')));

    final completer = Completer<void>();
    final sub = peerKeyReadyEvents.listen((readyId) {
      if (readyId == peerId && !completer.isCompleted) completer.complete();
    });
    final timer = Timer(timeout, () {
      if (!completer.isCompleted) completer.complete();
    });
    await completer.future;
    timer.cancel();
    await sub.cancel();

    return _peerPublicKeyFromCaches(peerId);
  }

  /// Déchiffre `content` si `encrypted` est vrai (voir enveloppe wire `e`/`n`),
  /// en utilisant la clé publique connue de [senderId]. Retourne un message
  /// de substitution si le déchiffrement échoue (clé inconnue, tag invalide).
  /// Exposé publiquement car `MeshNotifier` (état UI en mémoire) et
  /// `MeshRepository` (persistance) décodent chacun l'enveloppe reçue.
  Future<String> resolveIncomingContent({
    required String? senderId,
    required String content,
    required bool encrypted,
    required String? nonce,
  }) async {
    if (!encrypted || senderId == null || nonce == null) return content;

    var peerPublicKey = _peerPublicKeyFromCaches(senderId);

    // ⚠️ Le repli qui manquait, et qui explique le fameux « message
    // illisible ».
    //
    // Le chemin d'ENVOI, lui, savait déjà réclamer la clé publique du
    // pair et l'attendre (`_resolvePeerPublicKey` envoie un « hello » et
    // patiente deux secondes). Le chemin de RÉCEPTION, non : il se
    // contentait de regarder dans son cache et, si la clé n'y était pas
    // encore, déclarait le message définitivement illisible.
    //
    // Or c'est un cas parfaitement ordinaire : un message relayé par un
    // tiers arrive souvent AVANT qu'on ait échangé quoi que ce soit avec
    // son auteur, qu'on n'a peut-être même jamais croisé directement.
    // Le texte de substitution était alors ENREGISTRÉ à la place du vrai
    // message — donc perdu pour de bon, même une fois la clé reçue une
    // seconde plus tard.
    peerPublicKey ??= await _resolvePeerPublicKey(senderId);

    final sharedKey =
        await CryptoService.sharedKeyWithPeer(senderId, peerPublicKey);
    final decrypted = sharedKey != null
        ? await CryptoService.decrypt(sharedKey, content, nonce)
        : null;
    if (decrypted != null) return decrypted;

    // Toujours rien : on garde le message chiffré de côté et on
    // réessaiera dès que la clé de cet auteur arrivera (voir
    // `_retryPendingDecryptions`). Le message reste affiché comme
    // illisible en attendant, mais il n'est plus perdu.
    _pendingDecryptions.add((
      senderId: senderId,
      cipherText: content,
      nonce: nonce,
    ));
    if (_pendingDecryptions.length > 200) _pendingDecryptions.removeAt(0);
    unawaited(_savePendingDecryptions());

    return kUnreadableMessage;
  }

  /// Le texte affiché à la place d'un message qu'on n'arrive pas encore à
  /// déchiffrer. Exposé pour que la reprise puisse le reconnaître.
  static const String kUnreadableMessage =
      '🔒 Message illisible (clé de chiffrement manquante)';

  /// Messages reçus chiffrés dont la clé n'était pas encore connue.
  final List<({String senderId, String cipherText, String nonce})>
      _pendingDecryptions = [];

  /// Où cette liste survit à la fermeture de l'application.
  static const String _pendingDecryptionsKey = 'pending_decryptions';

  /// ⚠️ POURQUOI CETTE LISTE DOIT SURVIVRE À UN REDÉMARRAGE.
  ///
  /// Le texte de substitution (« 🔒 Message illisible ») est ce qui est
  /// ENREGISTRÉ à la place du message, en attendant la clé. Le vrai
  /// contenu, lui, n'existe plus que sous forme chiffrée, ici, en
  /// mémoire vive.
  ///
  /// Tant que l'app restait ouverte, la reprise fonctionnait. Mais si
  /// elle se fermait avant que la clé n'arrive — ce qui, dans une app
  /// mesh, est le cas le plus fréquent : on reçoit un message relayé par
  /// un tiers, on range son téléphone, et on ne croise l'auteur que le
  /// lendemain — le chiffré disparaissait avec le processus. Le message
  /// restait alors barré d'un cadenas POUR TOUJOURS, alors que tout ce
  /// qui manquait était une clé qui finissait par arriver.
  ///
  /// Ce n'était donc pas un affichage désagréable : c'était une PERTE DE
  /// DONNÉES définitive, et silencieuse.
  ///
  /// Conserver ces octets sur le disque n'affaiblit rien : ils sont déjà
  /// chiffrés, et sans la clé du pair ils ne disent rien de plus à qui
  /// lirait le stockage qu'ils n'en disaient sur le réseau.
  Future<void> _savePendingDecryptions() async {
    try {
      await StorageService.setString(
        _pendingDecryptionsKey,
        jsonEncode([
          for (final p in _pendingDecryptions)
            {'s': p.senderId, 'c': p.cipherText, 'n': p.nonce}
        ]),
      );
    } catch (e) {
      debugPrint('[MeshRepo] sauvegarde des messages en attente échouée: $e');
    }
  }

  /// Relit la liste au démarrage.
  void _loadPendingDecryptions() {
    try {
      final brut = StorageService.getString(_pendingDecryptionsKey);
      if (brut == null || brut.isEmpty) return;
      for (final e in jsonDecode(brut) as List) {
        final m = e as Map<String, dynamic>;
        final s = m['s'], c = m['c'], n = m['n'];
        if (s is! String || c is! String || n is! String) continue;
        _pendingDecryptions.add((senderId: s, cipherText: c, nonce: n));
      }
      debugPrint('[MeshRepo] ${_pendingDecryptions.length} message(s) en '
          'attente de clé rechargé(s)');
    } catch (e) {
      debugPrint('[MeshRepo] relecture des messages en attente échouée: $e');
    }
  }

  /// Rejoue le déchiffrement des messages mis de côté, maintenant que la
  /// clé publique de [peerId] est connue.
  ///
  /// Appelé à chaque « hello » reçu. Sans cette reprise, un message
  /// arrivé une seconde trop tôt resterait barré d'un cadenas pour
  /// toujours, alors que tout ce qu'il manquait était une clé qui est
  /// arrivée juste après.
  Future<void> _retryPendingDecryptions(String peerId) async {
    if (_pendingDecryptions.isEmpty) return;
    final mine =
        _pendingDecryptions.where((p) => p.senderId == peerId).toList();
    if (mine.isEmpty) return;
    _pendingDecryptions.removeWhere((p) => p.senderId == peerId);

    final peerPublicKey = _peerPublicKeyFromCaches(peerId);
    final sharedKey =
        await CryptoService.sharedKeyWithPeer(peerId, peerPublicKey);
    if (sharedKey == null) {
      // La clé n'est toujours pas exploitable : on remet les chiffrés en
      // attente plutôt que de les jeter. Les avoir retirés de la liste
      // avant d'essayer évite qu'un second « hello » arrivé pendant le
      // déchiffrement ne traite les mêmes messages en double ; encore
      // faut-il les rendre si l'essai n'aboutit pas.
      _pendingDecryptions.addAll(mine);
      return;
    }

    for (final entry in mine) {
      final clear = await CryptoService.decrypt(
          sharedKey, entry.cipherText, entry.nonce);
      if (clear == null) continue;
      // On retrouve le message à réparer par son texte de substitution et
      // son auteur : l'identifiant applicatif n'est pas conservé ici, et
      // deux messages illisibles du même auteur se valent de toute façon
      // — le premier réparé prend la première place libre.
      final broken = StorageService.getMessages()
          .where((m) => m.senderId == peerId && m.content == kUnreadableMessage)
          .firstOrNull;
      if (broken == null) continue;
      await StorageService.saveMessage(broken.copyWith(content: clear));
      _repairedMessagesCtrl.add(broken.id);
    }
    // La liste sur le disque doit refléter ce qui vient d'être réparé,
    // sans quoi les mêmes chiffrés reviendraient au prochain démarrage.
    await _savePendingDecryptions();
  }

  /// Prévient l'interface qu'un message illisible vient d'être réparé.
  final _repairedMessagesCtrl = StreamController<String>.broadcast();
  Stream<String> get repairedMessageEvents => _repairedMessagesCtrl.stream;

  /// Chiffre [plaintext] pour [targetId] avec la clé partagée dérivée de sa
  /// clé publique X25519 (attend brièvement l'échange de clés si besoin).
  /// Lève une exception si la clé publique reste introuvable — pas de repli
  /// silencieux en clair pour un contenu destiné à un pair précis.
  Future<(String content, String? nonce, bool encrypted)> _encryptForPeer(
    String targetId,
    String plaintext,
  ) async {
    final peerPublicKey = await _resolvePeerPublicKey(targetId);
    final sharedKey = await CryptoService.sharedKeyWithPeer(targetId, peerPublicKey);
    if (sharedKey == null) {
      throw StateError(
        'Clé publique de $targetId inconnue — chiffrement impossible pour le moment',
      );
    }
    final (cipherText, nonce) = await CryptoService.encrypt(sharedKey, plaintext);
    return (cipherText, nonce, true);
  }

  String? _peerPublicKeyFromCaches(String peerId) {
    for (final peer in _transport.connectedPeers) {
      if (peer.peerId == peerId && peer.publicKey != null) return peer.publicKey;
    }
    for (final peer in StorageService.getKnownPeers()) {
      if (peer.peerId == peerId && peer.publicKey != null) return peer.publicKey;
    }
    return null;
  }

  /// LE cœur du fichier : chaque fois qu'un paquet de données arrive de
  /// n'importe quel transport (Bluetooth/Wi-Fi/Nearby), il passe par ici.
  /// Cette fonction regarde ce que c'est (un message ? un accusé de
  /// réception ? un fichier ? un signal de frappe ? un statut ?) et
  /// l'aiguille vers le bon traitement — comme un employé de tri postal
  /// qui ouvre chaque enveloppe pour voir dans quel casier la ranger.
  Future<void> _handleIncomingMessage(MeshIncomingData data) async {
    if (_seenMessageIds.contains(data.messageId)) return;
    _seenMessageIds.add(data.messageId);
    StorageService.addSeenMessageId(data.messageId);

    if (data.data.length < 2) return;
    final int hopCount = data.data[0];
    final int msgType = data.data[1];

    if (msgType == kAckType) {
      _handleAck(data);
      return;
    }

    if (msgType == kRouteAnnounceType) {
      _recevoirRoutes(data);
      return;
    }

    // ── Synchronisation différentielle des statuts ──────────────────
    //
    // Ces deux échanges ne sont JAMAIS relayés : ils ne concernent que
    // les deux appareils qui viennent de se rencontrer. Une offre
    // relayée à travers le mesh proposerait à des inconnus des statuts
    // qu'on ne leur enverra pas, et déclencherait une avalanche de
    // demandes sans destinataire.
    if (msgType == kSyncOfferType) {
      unawaited(_handleSyncOffer(data).catchError(
          (e) => debugPrint('[MeshRepo] offre de synchro: $e')));
      return;
    }
    if (msgType == kSyncRequestType) {
      unawaited(_handleSyncRequest(data).catchError(
          (e) => debugPrint('[MeshRepo] demande de synchro: $e')));
      return;
    }

    if (msgType == kNexusEventType) {
      try {
        final json = jsonDecode(utf8.decode(data.data.sublist(2)))
            as Map<String, dynamic>;
        final event = NexusEvent.fromJson(json);
        _nexusEventCtrl.add(event);
        debugPrint('[MeshRepo] Nexus reçu: seed=${event.seed.substring(0, 8)}...');
      } catch (e) {
        debugPrint('[MeshRepo] erreur parsing Nexus: $e');
      }
      return;
    }

    if (msgType >= kCallOffer && msgType <= kCallHangUp) return;

    if (msgType == kFileTransferType) {
      await _handleFileTransfer(data, hopCount);
      return;
    }

    if (msgType != kTextMessageType) return;
    if (data.data.length < 3) return;
    final Uint8List contentBytes = data.data.sublist(2);

    try {
      final raw = utf8.decode(contentBytes);
      String content;
      String? replyToId;
      String? senderId;
      String? appMsgId;
      String? targetId;
      String? groupId;
      String? kind;
      int? groupCounter;
      String? nonce;
      String? effect;
      // Le trajet signé par les relais successifs (champ `p`).
      List<String>? chemin;
      try {
        final parsed = json.decode(raw) as Map<String, dynamic>;
        chemin = (parsed['p'] as List?)?.cast<String>();
        content = parsed['c'] as String? ?? raw;
        replyToId = parsed['r'] as String?;
        senderId = parsed['s'] as String?;
        appMsgId = parsed['m'] as String?;
        targetId = parsed['t'] as String?;
        groupId = parsed['g'] as String?;
        kind = parsed['k'] as String?;
        groupCounter = parsed['ctr'] as int?;
        nonce = parsed['n'] as String?;
        effect = parsed['ef'] as String?;

        // Les messages de groupe sont déchiffrés via leur sender-key
        // (voir _handleGroupContent), pas via le secret partagé 1:1.
        if (groupId == null) {
          content = await resolveIncomingContent(
            senderId: senderId,
            content: content,
            encrypted: parsed['e'] as bool? ?? false,
            nonce: nonce,
          );
        }
      } catch (_) {
        content = raw;
      }

      if (groupId != null && kind == null) {
        await _handleGroupContent(
          data: data,
          hopCount: hopCount,
          groupId: groupId,
          senderId: senderId,
          appMsgId: appMsgId,
          cipherText: content,
          nonce: nonce,
          counter: groupCounter,
          replyToId: replyToId,
          effect: effect,
        );
        return;
      }

      if (kind == 'group_sync' || kind == 'group_sender_key') {
        if (senderId != null && senderId != _myId && targetId == _myId) {
          final payload = jsonDecode(content) as Map<String, dynamic>;
          if (kind == 'group_sync') {
            await _applyGroupSync(senderId, payload);
          } else {
            await _applyIncomingSenderKey(payload);
          }
        }
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: targetId);
        return;
      }

      // Signal de frappe : on ne stocke rien, on le relaie pour le multi-hop
      // et on prévient l'UI (jamais nos propres signaux).
      if (kind == 'typing') {
        if (senderId != _myId && (targetId == null || targetId == _myId)) {
          _typingCtrl.add(senderId ?? data.peerId);
        }
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: targetId);
        return;
      }

      // Échange de clés : `c` porte la clé publique X25519 de l'émetteur.
      // Toujours traité si on est concerné (broadcast ou ciblé), puis relayé
      // pour atteindre l'émetteur si nous ne sommes pas voisins directs.
      if (kind == 'hello') {
        if (senderId != null && senderId != _myId &&
            (targetId == null || targetId == _myId)) {
          _handleHello(senderId, content,
              viaPeerId: data.peerId, hopCount: hopCount);
        }
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: targetId);
        return;
      }

      // Accusé de lecture : `c` porte l'ID du message lu. On prévient l'UI
      // (jamais pour nos propres messages) puis on relaie pour le multi-hop.
      if (kind == 'read') {
        final readMsgId = content;
        if (senderId != _myId && readMsgId.isNotEmpty &&
            (targetId == null || targetId == _myId)) {
          _readCtrl.add(readMsgId);
        }
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: targetId);
        return;
      }

      // Réaction emoji : `c` porte l'ID du message, `m` l'emoji.
      if (kind == 'reaction') {
        final reactMsgId = content;
        final emoji = appMsgId ?? ''; // 'm' est déjà parsé dans appMsgId
        if (senderId != _myId && reactMsgId.isNotEmpty && emoji.isNotEmpty &&
            (targetId == null || targetId == _myId)) {
          _reactionCtrl.add((messageId: reactMsgId, emoji: emoji));
        }
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: targetId);
        return;
      }

      // Modification de message : `m` porte l'ID du message, `c` le
      // nouveau contenu. Relayé pour le multi-hop.
      if (kind == 'edit') {
        final editMsgId = appMsgId ?? '';
        if (senderId != null && editMsgId.isNotEmpty &&
            (targetId == null || targetId == _myId)) {
          String newContent = content;
          // Les messages de groupe sont chiffrés avec la sender-key du groupe.
          if (groupId != null && nonce != null && groupCounter != null) {
            final group = StorageService.getGroup(groupId);
            if (group != null && group.isActiveMember(_myId)) {
              newContent = await _decryptGroupContent(
                  groupId, senderId, content, nonce, groupCounter);
            }
          }
          _editCtrl.add((messageId: editMsgId, newContent: newContent));
          debugPrint('[MeshRepo] édit reçu: $editMsgId');
        }
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: targetId);
        return;
      }

      // Accusé de vue d'un statut : `c` porte {statusId, ts}, ciblé vers
      // l'auteur du statut (comme une réaction), jamais diffusé largement.
      if (kind == 'status_feedback') {
        if (senderId != null && senderId != _myId && targetId == _myId) {
          _handleStatusFeedback(senderId, content);
        }
        _relayOrDefer(data.messageId, data.data, hopCount,
            excludePeerId: data.peerId, targetId: targetId);
        return;
      }

      if (kind == 'status_seen') {
        if (senderId != null && senderId != _myId &&
            (targetId == null || targetId == _myId)) {
          _handleStatusSeen(senderId, content);
        }
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: targetId);
        return;
      }

      // Check-in de sécurité : statut public, diffusé à tout le mesh.
      if (kind == 'safety_checkin') {
        if (senderId != null && senderId != _myId) {
          _handleSafetyCheckin(senderId, content);
        }
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: targetId);
        return;
      }

      // Statut éphémère : public, diffusé à tout le mesh.
      if (kind == 'status') {
        if (senderId != null && senderId != _myId) {
          _handleStatus(senderId, content, appMsgId);
        }
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: targetId);
        return;
      }

      if (appMsgId != null) {
        if (_appMessageIds.containsKey(appMsgId)) return;
        _appMessageIds[appMsgId] = DateTime.now();
      }

      if (senderId == _myId) return;

      // Chat dirigé : si ce message ne m'est pas destiné, on ne fait que le
      // relayer (store-and-forward) sans l'afficher.
      if (targetId != null && targetId != _myId) {
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: targetId);
        return;
      }

      String authorPseudo = data.peerId;
      if (senderId != null) {
        try {
          final peer = _transport.connectedPeers.firstWhere(
            (p) => p.peerId == senderId,
          );
          authorPseudo = peer.pseudo;
        } catch (_) {
          authorPseudo = senderId;
        }
      } else {
        try {
          final peer = _transport.connectedPeers.firstWhere(
            (p) => p.peerId == data.peerId,
          );
          authorPseudo = peer.pseudo;
        } catch (_) {}
      }

      final msg = MeshMessage(
        id: appMsgId ?? data.messageId,
        authorPseudo: authorPseudo,
        content: content,
        type: 'mesh',
        timestamp: DateTime.now(),
        senderId: senderId,
        targetId: targetId,
        hopCount: hopCount,
        replyToId: replyToId,
        effect: effect,
        routeInfo: (chemin == null || chemin.isEmpty)
            ? null
            : chemin.join(' → '),
      );
      StorageService.saveMessage(msg);
      _newMessageCtrl.add(msg);

      if (senderId != null && senderId != _myId) {
        _sendAck(senderId, appMsgId ?? data.messageId);
      }
    } catch (e) { debugPrint('[MeshRepo] $e'); }

    // Relais final : on arrive ici pour un message de diffusion (targetId
    // null) ou qui m'était adressé (targetId == _myId). Dans les deux cas
    // le routage ciblé n'a pas de sens (la cible est moi-même), donc on
    // relaie en diffusion pour la propagation.
    _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId);
  }

  void _handleAck(MeshIncomingData data) {
    try {
      final ackPayload = utf8.decode(data.data.sublist(2));
      final ids = ackPayload.split(',');
      for (final ackedMsgId in ids) {
        final current = _ackCounts[ackedMsgId] ?? 0;
        _ackCounts[ackedMsgId] = current + 1;
        _transport.incrementAck();
        _ackCtrl.add(ackedMsgId);
        // Un message encore en attente de retry est confirmé reçu → arrête
        // de réessayer (le pair l'a bien eu).
        _reliableQueue.acknowledge(ackedMsgId);
      }
      debugPrint('[MeshRepo] ACK batch reçu: ${ids.length} messages');
    } catch (e) {
      debugPrint('[MeshRepo] Erreur traitement ACK: $e');
    }
  }

  // ── ANNONCE DE ROUTES (multi-saut) ──────────────────────────────────
  //
  // ⚠️ CE QUI MANQUAIT POUR QUE LE MULTI-SAUT SOIT AUTRE CHOSE QU'UNE
  // INONDATION.
  //
  // La table de routage n'était alimentée qu'avec des voisins DIRECTS
  // (`updateRoutingTable(p, p, 1, …)`). Personne n'apprenait jamais qu'un
  // pair hors de portée était joignable À TRAVERS un autre. Résultat :
  // `sendViaRoute` ne trouvait rien pour un destinataire lointain, et
  // l'appelant retombait sur la diffusion — le message partait vers TOUS
  // les voisins, à charge pour eux de le refaire suivre jusqu'à
  // épuisement du compteur de sauts.
  //
  // Ça fonctionnait, mais tout le calcul de métrique composite et le
  // Bellman-Ford de `getRoute` étaient inertes : ils ne pouvaient trouver
  // que des entrées à un saut.
  //
  // Ici, chaque appareil dit périodiquement à ses voisins CE QU'IL SAIT
  // JOINDRE. Le voisin en déduit « pour atteindre C, passe par B, deux
  // sauts » — et le message ne suit plus qu'un chemin.

  /// Combien de destinations au maximum dans une annonce.
  ///
  /// ⚠️ Ce plafond n'est pas cosmétique : une annonce voyage aussi par
  /// Bluetooth, où Droplet dispose de dix-neuf octets utiles par écriture
  /// et refuse tout paquet au-delà de 512. Douze destinations tiennent
  /// largement dedans ; une table entière, non.
  static const int _maxRoutesAnnoncees = 12;

  /// Dit aux voisins ce que je sais joindre.
  Future<void> _annoncerRoutes() async {
    if (!_initialized) return;
    final protocole = _transport.networkManager.protocol;

    // Ce que j'annonce : mes voisins directs (un saut) et les routes que
    // j'ai moi-même apprises. On n'annonce PAS le destinataire à
    // lui-même, ni moi — chacun sait déjà comment s'atteindre.
    final destinations = <String, int>{};
    for (final p in _transport.connectedPeers) {
      if (p.reconnecting) continue; // rien ne passe par un lien tombé
      destinations[p.peerId] = 1;
    }
    for (final entree in protocole.snapshotRoutes()) {
      final actuel = destinations[entree.destination];
      if (actuel == null || entree.hopCount < actuel) {
        destinations[entree.destination] = entree.hopCount;
      }
    }
    destinations.remove(_myId);
    if (destinations.isEmpty) return;

    // Les plus proches d'abord : si le plafond tronque, on garde les
    // routes les plus utiles.
    final triees = destinations.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    final charge = jsonEncode({
      's': _myId,
      'r': [
        for (final e in triees.take(_maxRoutesAnnoncees))
          {'d': e.key, 'h': e.value},
      ],
    });

    final octets = utf8.encode(charge);
    final paquet = Uint8List(2 + octets.length);
    paquet[0] = 1; // ⚠️ TTL À UN : une annonce ne se relaie JAMAIS.
    // Chaque appareil réannonce ce qu'il a appris, à sa propre cadence.
    // Laisser une annonce se propager telle quelle ferait circuler des
    // distances fausses — le compteur de sauts serait celui de
    // l'émetteur d'origine, pas celui du relais.
    paquet[1] = kRouteAnnounceType;
    paquet.setRange(2, paquet.length, octets);

    await _transport.broadcastToConnectedPeers(paquet);
  }

  /// Apprend les routes annoncées par un voisin.
  void _recevoirRoutes(MeshIncomingData data) {
    try {
      final json = jsonDecode(utf8.decode(data.data.sublist(2)));
      if (json is! Map) return;
      final voisin = json['s'] as String?;
      final routes = json['r'];
      if (voisin == null || voisin == _myId || routes is! List) return;

      final protocole = _transport.networkManager.protocol;
      final metriqueVoisin = protocole.computeLinkMetric(voisin);

      for (final entree in routes) {
        if (entree is! Map) continue;
        final dest = entree['d'] as String?;
        final sauts = entree['h'];
        if (dest == null || sauts is! int) continue;
        // Une route vers moi-même n'a aucun sens, et une route vers le
        // voisin lui-même est déjà connue en direct.
        if (dest == _myId || dest == voisin) continue;
        // Au-delà du TTL, le message n'arriverait pas de toute façon :
        // annoncer une telle route ne ferait qu'encombrer la table.
        if (sauts + 1 >= kDefaultHopCount) continue;

        // La métrique s'ADDITIONNE le long du chemin : passer par un
        // voisin médiocre pour atteindre quelqu'un de proche peut coûter
        // plus cher qu'un détour par un bon lien.
        protocole.updateRoutingTable(
          dest,
          voisin,
          sauts + 1,
          metriqueVoisin * (sauts + 1),
        );
      }
    } catch (e) {
      debugPrint('[MeshRepo] annonce de routes illisible: $e');
    }
  }

  /// Ajoute mon empreinte au chemin porté par l'enveloppe.
  ///
  /// Renvoie le paquet inchangé si l'enveloppe n'est pas du JSON — un
  /// transfert de fichier, par exemple, dont l'en-tête n'est pas un
  /// objet : le relais doit continuer de fonctionner, quitte à ne pas
  /// enregistrer le chemin.
  Uint8List _signerLePassage(Uint8List paquet) {
    try {
      final enveloppe = jsonDecode(utf8.decode(paquet.sublist(2)));
      if (enveloppe is! Map<String, dynamic>) return paquet;

      final chemin = (enveloppe['p'] as List?)?.cast<String>() ?? <String>[];
      final moi = _myId.length > 8 ? _myId.substring(0, 8) : _myId;
      // Un message peut repasser par ici quand plusieurs chemins se
      // rejoignent : on ne se compte pas deux fois.
      if (chemin.contains(moi)) return paquet;
      // Borné par le TTL de toute façon ; la garde évite qu'une
      // enveloppe forgée fasse enfler le paquet.
      if (chemin.length >= kDefaultHopCount) return paquet;
      enveloppe['p'] = [...chemin, moi];

      final octets = utf8.encode(jsonEncode(enveloppe));
      final neuf = Uint8List(2 + octets.length);
      neuf[0] = paquet[0];
      neuf[1] = paquet[1];
      neuf.setRange(2, neuf.length, octets);
      return neuf;
    } catch (_) {
      return paquet;
    }
  }

  List<MeshMessage> getMessages() => StorageService.getMessages();

  final List<_PendingRelay> _pendingRelays = [];
  static const int _pendingRelaysCap = 256;

  /// Génération des relais en attente — incémentée à chaque ajout.
  int _pendingRelayGeneration = 0;

  /// Rate-limit des réponses hello : un carnet par émetteur (borné) pour
  /// éviter de répondre sans arrêt, + un plafond global de réponses par
  /// fenêtre. Sans cela, une découverte de masse (ou un appareil en boucle)
  /// déclencherait une rafale de hello broadcast de notre part.
  final Map<String, DateTime> _helloReplyCooldown = {};
  static const Duration _helloReplyPerSenderGap = Duration(seconds: 30);
  int _helloRepliesInWindow = 0;
  DateTime _helloReplyWindowStart = DateTime.fromMillisecondsSinceEpoch(0);
  static const int _helloRepliesMaxPerWindow = 8;
  static const Duration _helloReplyWindow = Duration(seconds: 5);

  /// Nombre de sauts par défaut dans un paquet. Le premier octet de
  /// chaque message porte ce compteur, décrémenté à chaque relais. À
  /// zéro, le message est jeté — c'est le garde-fou contre les
  /// boucles infinies.
  ///
  /// ⚠️ ADAPTATIF : la valeur est calculée dynamiquement selon la
  /// densité du mesh (nombre de pairs connectés). Plus le réseau est
  /// dense, plus on autorise de sauts pour atteindre des pairs éloignés.
  static int get kDefaultHopCount => _adaptiveHopCount;
  static int _adaptiveHopCount = 5;

  /// Met à jour le nombre de sauts adaptatif selon la densité du mesh.
  static void updateAdaptiveHopCount(int connectedPeerCount) {
    if (connectedPeerCount <= 2) {
      _adaptiveHopCount = 3;
    } else if (connectedPeerCount <= 5) {
      _adaptiveHopCount = 5;
    } else {
      _adaptiveHopCount = 7;
    }
  }

  /// Envoie un message texte — soit ciblé vers une personne précise
  /// ([targetId], chiffré), soit diffusé à tout le mesh en clair si
  /// aucune cible n'est donnée.
  Future<void> sendMessage({
    required String authorPseudo,
    required String content,
    String type = 'text',
    String? imageUrl,
    String? audioUrl,
    String? replyToId,
    String? messageId,
    String? targetId,
    Set<String>? interestGroups,
    String? effect,
  }) async {
    final (wireContent, nonce, encrypted) = targetId != null
        ? await _encryptForPeer(targetId, content)
        : (content, null, false);

    final jsonMap = <String, dynamic>{
      'c': wireContent,
      's': _myId,
    };
    if (encrypted) {
      jsonMap['e'] = true;
      jsonMap['n'] = nonce;
    }
    if (replyToId != null) jsonMap['r'] = replyToId;
    if (messageId != null) jsonMap['m'] = messageId;
    if (targetId != null) jsonMap['t'] = targetId;
    if (effect != null) jsonMap['ef'] = effect;
    final payloadBytes = utf8.encode(json.encode(jsonMap));
    final data = Uint8List(2 + payloadBytes.length);
    data[0] = kDefaultHopCount;
    data[1] = kTextMessageType;
    data.setRange(2, data.length, payloadBytes);
    await _enqueueReliable(
      messageId: messageId ?? 'm-${DateTime.now().microsecondsSinceEpoch}',
      targetId: targetId ?? 'broadcast',
      data: data,
      priority: targetId != null ? MessagePriority.high : MessagePriority.normal,
      interestGroups: interestGroups,
    );
  }

  /// Annonce ma clé publique X25519 à [targetId] (ou à tout le voisinage
  /// direct si null), pour permettre au destinataire de dériver le secret
  /// partagé du chiffrement de bout en bout.
  ///
  /// ⚠️ ENVOI DIRECT : le hello contourne la file fiable (`_enqueueReliable`)
  /// pour minimiser la latence d'échange de clés. La clé est le verrou du
  /// chiffrement — chaque milliseconde de retard est un message en attente
  /// de déchiffrement. On envoie via `broadcastToConnectedPeers` (ou
  /// `sendViaRoute` si ciblé) sans retry ni backoff : si ça rate, le
  /// prochain `_resolvePeerPublicKey` relancera un hello.
  Future<void> sendHello({String? targetId}) async {
    final publicKey = _myPublicKey;
    if (publicKey == null) return;
    final jsonMap = <String, dynamic>{
      'c': publicKey,
      's': _myId,
      'k': 'hello',
    };
    if (targetId != null) jsonMap['t'] = targetId;
    final payloadBytes = utf8.encode(json.encode(jsonMap));
    final data = Uint8List(2 + payloadBytes.length);
    data[0] = kDefaultHopCount;
    data[1] = kTextMessageType;
    data.setRange(2, data.length, payloadBytes);

    try {
      if (targetId != null) {
        final ok = await _transport.sendViaRoute(targetId, data, type: kTextMessageType, priority: 0);
        if (!ok) {
          // Fallback : diffusion si le routage direct échoue
          await _transport.broadcastToConnectedPeers(data, type: kTextMessageType);
        }
      } else {
        await _transport.broadcastToConnectedPeers(data, type: kTextMessageType);
      }
    } catch (e) {
      debugPrint('[MeshRepo] échec hello direct: $e');
    }
  }

  /// Enregistre la clé publique X25519 d'un pair et fait le nécessaire pour
  /// que l'identité de ce pair soit cohérente sur tout le système :
  ///
  /// 1. **Apprentissage du mapping ID transport → ID Droplet** : un hello
  ///    DIRECT (aucun relais, `hopCount == kDefaultHopCount`) reçu d'un pair
  ///    encore identifié par son ID transport (ex. adresse MAC NativeP2P)
  ///    révèle la correspondance entre cet ID et son vrai ID Droplet
  ///    (`senderId`). On l'enregistre pour que `sendToPeer`, `canCallPeer`
  ///    et le routage fonctionnent avec l'ID Droplet — sinon les messages
  ///    et les appels vers un pair « MAC-identifié » échouent silencieusement.
  ///    (Restreint au trafic direct : un hello RELAYÉ porterait l'ID du
  ///    voisin immédiat, pas celui de l'émetteur original — mauvais mapping.)
  /// 2. **Réponse de clé** : si la clé de ce pair nous était inconnue, on lui
  ///    renvoie la nôtre — l'échange de clés devient BIDIRECTIONNEL même
  ///    quand la découverte n'a eu lieu que d'un seul côté. Sans cela,
  ///    `_resolvePeerPublicKey` attendrait 2 s et échouerait (premier
  ///    message chiffré perdu).
  void _handleHello(String senderId, String publicKeyB64,
      {String? viaPeerId, int hopCount = 0}) {
    CryptoService.invalidateSharedKey(senderId);

    final wasUnknown = _peerPublicKeyFromCaches(senderId) == null;

    _transport.updatePeerPublicKey(senderId, publicKeyB64);

    if (viaPeerId != null &&
        viaPeerId != senderId &&
        hopCount == kDefaultHopCount) {
      _transport.registerPeerIdMapping(senderId, viaPeerId);
    }

    final existing = StorageService.getKnownPeers().where((p) => p.peerId == senderId);
    final record = existing.isNotEmpty
        ? existing.first.copyWith(publicKey: publicKeyB64)
        : PeerRecord(peerId: senderId, pseudo: senderId, lastSeen: DateTime.now(), publicKey: publicKeyB64);
    StorageService.upsertPeer(record);

    _peerKeyReadyCtrl.add(senderId);
    debugPrint('[MeshRepo] clé publique reçue de $senderId');

    // La clé vient d'arriver : on rejoue le déchiffrement des messages de
    // ce pair reçus trop tôt, plutôt que de les laisser barrés d'un
    // cadenas pour toujours.
    unawaited(_retryPendingDecryptions(senderId).catchError(
        (e) => debugPrint('[MeshRepo] reprise déchiffrement: $e')));

    // Première rencontre → répondre avec notre clé pour compléter l'échange.
    if (wasUnknown && _allowHelloReply(senderId)) {
      unawaited(sendHello()
          .catchError((e) => debugPrint('[MeshRepo] échec réponse hello à $senderId: $e')));
    }
  }

  /// Peut-on répondre à ce hello ? Deux conditions : on n'a pas déjà répondu
  /// à CE pair dans les 30 dernières secondes (carnet borné), et on n'a pas
  /// dépassé le plafond global de réponses (8 par 5 s) — sinon une rafale
  /// de découverte déclencherait une rafale de broadcast chez nous.
  bool _allowHelloReply(String senderId) {
    final now = DateTime.now();

    // Plafond global (fenêtre glissante).
    if (now.difference(_helloReplyWindowStart) >= _helloReplyWindow) {
      _helloReplyWindowStart = now;
      _helloRepliesInWindow = 0;
    }
    if (_helloRepliesInWindow >= _helloRepliesMaxPerWindow) {
      return false;
    }

    // Carnet par émetteur, borné (oubli des plus anciens).
    if (_helloReplyCooldown.length > 512) {
      _helloReplyCooldown.remove(_helloReplyCooldown.keys.first);
    }
    final last = _helloReplyCooldown[senderId];
    if (last != null && now.difference(last) < _helloReplyPerSenderGap) {
      return false;
    }

    _helloReplyCooldown[senderId] = now;
    _helloRepliesInWindow++;
    return true;
  }

  /// Envoie une opération de contrôle de groupe (manifeste, sender-key) à
  /// [targetPeerId], toujours chiffrée en 1:1 comme un message dirigé
  /// classique — ce canal transporte potentiellement du matériel secret
  /// (clé de groupe).
  Future<void> _sendEncryptedControl(String targetPeerId, String kind, Map<String, dynamic> payload) async {
    final (wireContent, nonce, encrypted) = await _encryptForPeer(targetPeerId, json.encode(payload));
    final jsonMap = <String, dynamic>{
      'c': wireContent,
      's': _myId,
      'k': kind,
      't': targetPeerId,
    };
    if (encrypted) {
      jsonMap['e'] = true;
      jsonMap['n'] = nonce;
    }
    final payloadBytes = utf8.encode(json.encode(jsonMap));
    final data = Uint8List(2 + payloadBytes.length);
    data[0] = kDefaultHopCount;
    data[1] = kTextMessageType;
    data.setRange(2, data.length, payloadBytes);
    await _enqueueReliable(
      messageId: 'ctrl-$kind-${DateTime.now().microsecondsSinceEpoch}',
      targetId: targetPeerId,
      data: data,
      priority: MessagePriority.critical,
    );
  }

  /// Diffuse un signal de frappe léger (ne persiste pas) — le petit
  /// « ... en train d'écrire » qu'on voit apparaître chez l'autre.
  Future<void> sendTyping({String? targetId}) async {
    final jsonMap = <String, dynamic>{
      'c': '',
      's': _myId,
      'k': 'typing',
    };
    if (targetId != null) jsonMap['t'] = targetId;
    final payloadBytes = utf8.encode(json.encode(jsonMap));
    final data = Uint8List(2 + payloadBytes.length);
    data[0] = kDefaultHopCount;
    data[1] = kTextMessageType;
    data.setRange(2, data.length, payloadBytes);
    await _transport.broadcastToConnectedPeers(data);
  }

  /// Diffuse un accusé de lecture pour [messageId] vers son émetteur
  /// [originalSenderId] (ne persiste pas, relayé pour le multi-hop).
  Future<void> sendRead({
    required String originalSenderId,
    required String messageId,
  }) async {
    final jsonMap = <String, dynamic>{
      'c': messageId,
      's': _myId,
      'k': 'read',
      't': originalSenderId,
    };
    final payloadBytes = utf8.encode(json.encode(jsonMap));
    final data = Uint8List(2 + payloadBytes.length);
    data[0] = kDefaultHopCount;
    data[1] = kTextMessageType;
    data.setRange(2, data.length, payloadBytes);
    await _transport.broadcastToConnectedPeers(data);
  }

  /// Diffuse une réaction emoji vers [targetId]. Le champ `c` porte l'ID du
  /// message réagi, `m` l'emoji. Jamais persisté, relayé pour le multi-hop.
  Future<void> sendReaction({
    required String targetId,
    required String messageId,
    required String emoji,
  }) async {
    final jsonMap = <String, dynamic>{
      'c': messageId,
      's': _myId,
      'm': emoji,
      'k': 'reaction',
      't': targetId,
    };
    final payloadBytes = utf8.encode(json.encode(jsonMap));
    final data = Uint8List(2 + payloadBytes.length);
    data[0] = kDefaultHopCount;
    data[1] = kTextMessageType;
    data.setRange(2, data.length, payloadBytes);
    await _transport.broadcastToConnectedPeers(data);
  }

  /// Diffuse une modification de message vers tous les pairs connectés.
  /// Le champ `c` porte le nouveau contenu, `m` l'ID du message modifié.
  /// Relayé pour le multi-hop comme un message normal.
  Future<void> sendEditMessage({
    required String messageId,
    required String newContent,
    String? targetId,
  }) async {
    final (wireContent, nonce, encrypted) = targetId != null
        ? await _encryptForPeer(targetId, newContent)
        : (newContent, null, false);
    final jsonMap = <String, dynamic>{
      'c': wireContent,
      's': _myId,
      'm': messageId,
      'k': 'edit',
    };
    if (encrypted) {
      jsonMap['e'] = true;
      jsonMap['n'] = nonce;
    }
    if (targetId != null) jsonMap['t'] = targetId;
    final payloadBytes = utf8.encode(json.encode(jsonMap));
    final data = Uint8List(2 + payloadBytes.length);
    data[0] = kDefaultHopCount;
    data[1] = kTextMessageType;
    data.setRange(2, data.length, payloadBytes);
    await _transport.broadcastToConnectedPeers(data);
  }

  /// Diffuse une modification de message de groupe. Le contenu est chiffré
  /// avec la sender-key du groupe, comme un message de groupe ordinaire.
  Future<void> sendGroupEditMessage({
    required String groupId,
    required String messageId,
    required String newContent,
  }) async {
    final (messageKey, newCounter) = await _advanceMySenderKey(groupId);
    final (cipherText, nonce) = await CryptoService.encrypt(messageKey, newContent);
    final jsonMap = <String, dynamic>{
      'c': cipherText,
      's': _myId,
      'g': groupId,
      'm': messageId,
      'k': 'edit',
      'n': nonce,
      'ctr': newCounter,
      'e': true,
    };
    final payloadBytes = utf8.encode(json.encode(jsonMap));
    final data = Uint8List(2 + payloadBytes.length);
    data[0] = kDefaultHopCount;
    data[1] = kTextMessageType;
    data.setRange(2, data.length, payloadBytes);
    await _transport.broadcastToConnectedPeers(data);
  }

  /// Diffuse un check-in "je suis en sécurité" à tout le mesh (mode
  /// urgence/catastrophe) — statut public par nature, comme la diffusion
  /// mesh totale existante. [lat]/[lon] sont arrondis à 2 décimales
  /// (~1 km) avant envoi si fournis : jamais la position exacte.
  /// Mon dernier check-in envoyé — reconservé pour le regossiper aux pairs
  /// rencontrés après coup (voir `_gossipAnnouncementsOnNewPeer`), puisque
  /// l'envoi initial ne touche que les pairs connectés à cet instant précis.
  ({DateTime ts, double? lat, double? lon})? _myLastCheckin;
  static const Duration _checkinGossipWindow = Duration(hours: 24);

  Future<void> sendSafetyCheckin({double? lat, double? lon}) async {
    final now = DateTime.now();
    _myLastCheckin = (ts: now, lat: lat, lon: lon);
    final payload = <String, dynamic>{
      'status': 'safe',
      'ts': now.toIso8601String(),
      if (lat != null) 'lat': (lat * 100).round() / 100,
      if (lon != null) 'lon': (lon * 100).round() / 100,
    };
    final jsonMap = <String, dynamic>{
      'c': json.encode(payload),
      's': _myId,
      'k': 'safety_checkin',
    };
    final payloadBytes = utf8.encode(json.encode(jsonMap));
    final data = Uint8List(2 + payloadBytes.length);
    data[0] = kDefaultHopCount;
    data[1] = kTextMessageType;
    data.setRange(2, data.length, payloadBytes);
    final checkinId = 'checkin-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await _enqueueReliable(
        messageId: checkinId,
        targetId: 'broadcast',
        data: data,
        priority: MessagePriority.critical,
      );
    } catch (e) {
      // C'est ici, précisément, que le silence serait le plus dangereux :
      // un check-in « je suis en sécurité » qui échoue sans que personne
      // ne le sache est pire que l'absence de fonctionnalité elle-même.
      _criticalSendFailureCtrl.add((kind: 'safety_checkin', messageId: checkinId, reason: e.toString()));
      rethrow;
    }
  }

  /// Rediffuse manuellement mes annonces (statut, check-in) aux pairs
  /// actuellement à portée.
  ///
  /// Déclenché par le geste « tirer pour rafraîchir » de l'onglet Actus :
  /// le regossip automatique ne se produit qu'à la rencontre d'un
  /// NOUVEAU pair, alors qu'on veut aussi pouvoir insister volontairement
  /// vers ceux déjà connectés (typiquement quand on doute que le message
  /// soit bien passé).
  Future<void> regossipAnnouncements() => _gossipAnnouncementsOnNewPeer();

  /// Envoie un événement Nexus à un pair pour synchroniser l'animation
  /// de connexion. Le payload est en clair (non chiffré) : il ne contient
  /// qu'une seed aléatoire et une couleur, aucun secret.
  Future<void> sendNexusEvent(String targetPeerId, NexusEvent event) async {
    final jsonPayload = utf8.encode(json.encode(event.toJson()));
    final data = Uint8List(2 + jsonPayload.length);
    data[0] = kDefaultHopCount;
    data[1] = kNexusEventType;
    data.setRange(2, data.length, jsonPayload);
    try {
      await _transport.sendToPeer(targetPeerId, data);
    } catch (e) {
      debugPrint('[MeshRepo] échec envoi Nexus vers $targetPeerId: $e');
    }
  }

  /// Regossipe mon statut actif et mon dernier check-in de sécurité à
  /// chaque nouvelle rencontre de pair — `sendStatus`/`sendSafetyCheckin`
  /// ne diffusent qu'une fois, aux pairs connectés à l'instant T ; sans ce
  /// regossip, publier en étant seul (0 pair) perdait silencieusement
  /// l'annonce pour de bon.
  Future<void> _gossipAnnouncementsOnNewPeer() async {
    // ── Les statuts : on PROPOSE, on ne rediffuse plus ──────────────
    //
    // L'ancienne version renvoyait MON statut, et lui seul, à chaque
    // rencontre. Deux défauts, dont le second est le plus grave :
    //
    //   1. Elle le renvoyait même à quelqu'un qui l'avait déjà.
    //   2. Elle ne transmettait JAMAIS les statuts des autres. Un statut
    //      n'atteignait donc que les gens que son auteur croisait en
    //      personne — alors qu'il est censé circuler « sur tout le
    //      mesh ». Le relais de proche en proche, qui est la raison
    //      d'être de Droplet, ne s'appliquait pas aux statuts.
    //
    // On propose désormais TOUT ce qu'on connaît, le sien et celui des
    // autres, sous forme d'identifiants. Le pair réclame ce qui lui
    // manque, et rien d'autre. Les statuts se propagent enfin de proche
    // en proche, et le coût reste proportionnel à ce qui manque
    // vraiment, non à ce qu'on possède.
    await _envoyerOffreDeSynchro();

    // ── Le check-in de sécurité : rediffusé tel quel ────────────────
    //
    // Volontairement laissé à l'identique. Il n'a pas d'identifiant
    // stable et n'est pas conservé dans un magasin qu'on puisse
    // comparer : il n'y a donc rien à négocier. Il est minuscule, borné
    // à une fenêtre de temps courte, et c'est le message le plus
    // critique de l'app — le rediffuser sans condition est ici la
    // bonne décision, pas une négligence.
    final checkin = _myLastCheckin;
    if (checkin != null && DateTime.now().difference(checkin.ts) < _checkinGossipWindow) {
      final payload = <String, dynamic>{
        'status': 'safe',
        'ts': checkin.ts.toIso8601String(),
        if (checkin.lat != null) 'lat': checkin.lat,
        if (checkin.lon != null) 'lon': checkin.lon,
      };
      final jsonMap = <String, dynamic>{'c': json.encode(payload), 's': _myId, 'k': 'safety_checkin'};
      final payloadBytes = utf8.encode(json.encode(jsonMap));
      final data = Uint8List(2 + payloadBytes.length);
      data[0] = kDefaultHopCount;
      data[1] = kTextMessageType;
      data.setRange(2, data.length, payloadBytes);
      await _transport.broadcastToConnectedPeers(data);
    }
  }

  // ═══════════════════════════════════════════════════════════════════
  //  SYNCHRONISATION DIFFÉRENTIELLE DES STATUTS
  // ═══════════════════════════════════════════════════════════════════
  //
  // Trois temps : j'offre, on me demande, j'envoie. La logique de
  // décision elle-même est ailleurs, dans `sync_negotiation.dart`, sous
  // forme de fonctions pures — ce qui permet de la mesurer sans réseau.

  /// Compteurs, pour rendre le gain MESURABLE et non seulement affirmé.
  int syncOffersSent = 0;
  int syncOfferBytes = 0;
  int syncRequestsReceived = 0;
  int syncStatusesSent = 0;

  /// Les identifiants des statuts encore valides que je connais.
  List<String> _mesStatutsConnus() =>
      StorageService.getActiveStatuses().map((s) => s.id).toList();

  Future<void> _envoyerOffreDeSynchro() async {
    final connus = _mesStatutsConnus();
    if (connus.isEmpty) return;

    final offre = SyncNegotiation.preparerOffre(mesMessages: connus);
    if (offre.messageIds.isEmpty) return;

    final corps = offre.encode();
    final data = Uint8List(2 + corps.length);
    data[0] = kDefaultHopCount;
    data[1] = kSyncOfferType;
    data.setRange(2, data.length, corps);

    syncOffersSent++;
    syncOfferBytes += data.length;
    await _transport.broadcastToConnectedPeers(data);
  }

  /// On me propose des statuts : je réclame ceux qui me manquent.
  Future<void> _handleSyncOffer(MeshIncomingData data) async {
    try {
      if (data.data.length < 2) return;
      final offre = SyncOffer.decode(
          Uint8List.sublistView(data.data, 2));
      final miens = _mesStatutsConnus().toSet();

      final demande = SyncNegotiation.repondreAOffre(
        offre: offre,
        mesMessages: miens,
      );
      // Rien ne manque : on ne répond RIEN. C'est le cas le plus
      // fréquent entre deux appareils qui se recroisent, et c'est là que
      // se joue l'essentiel de l'économie.
      if (demande.messageIds.isEmpty) return;

      final corps = demande.encode();
      final paquet = Uint8List(2 + corps.length);
      paquet[0] = kDefaultHopCount;
      paquet[1] = kSyncRequestType;
      paquet.setRange(2, paquet.length, corps);

      await _transport.sendToPeer(data.peerId, paquet);
    } catch (e) {
      debugPrint('[MeshRepo] offre de synchro illisible: $e');
    }
  }

  /// On me réclame des statuts : je les renvoie, et eux seuls.
  ///
  /// La réponse emprunte le format d'annonce ORDINAIRE (`k: 'status'`) :
  /// le destinataire n'a donc aucun code de réception nouveau à
  /// exécuter, c'est `_handleStatus` qui les range comme d'habitude.
  Future<void> _handleSyncRequest(MeshIncomingData data) async {
    try {
      if (data.data.length < 2) return;
      final demande = SyncRequest.decode(
          Uint8List.sublistView(data.data, 2));

      final parId = {
        for (final s in StorageService.getActiveStatuses()) s.id: s,
      };
      final aEnvoyer = SyncNegotiation.messagesAEnvoyer(
        demande: demande,
        mesMessages: parId.keys.toSet(),
      );

      syncRequestsReceived++;
      for (final id in aEnvoyer) {
        final statut = parId[id];
        if (statut == null) continue;

        final payload = <String, dynamic>{
          'id': statut.id,
          'content': statut.content,
          'createdAt': statut.createdAt.toIso8601String(),
          'expiresAt': statut.expiresAt.toIso8601String(),
          // Le média suit le statut : sans lui, le destinataire
          // recevrait une photo sans savoir qu'il y en a une.
          if (!StorageService.getStatusMedia(statut.id).isPlainText)
            'media': StorageService.getStatusMedia(statut.id).toJson(),
        };
        // ⚠️ `s` porte l'AUTEUR du statut, pas moi. C'est ce qui permet
        // au relais de fonctionner : je transmets le statut de quelqu'un
        // d'autre sans m'en attribuer la paternité.
        final jsonMap = <String, dynamic>{
          'c': json.encode(payload),
          's': statut.authorId,
          'k': 'status',
          'm': statut.id,
        };
        final bytes = utf8.encode(json.encode(jsonMap));
        final paquet = Uint8List(2 + bytes.length);
        paquet[0] = kDefaultHopCount;
        paquet[1] = kTextMessageType;
        paquet.setRange(2, paquet.length, bytes);

        syncStatusesSent++;
        await _transport.sendToPeer(data.peerId, paquet);
      }
    } catch (e) {
      debugPrint('[MeshRepo] demande de synchro illisible: $e');
    }
  }


  void _handleSafetyCheckin(String senderId, String content) {
    try {
      final payload = json.decode(content) as Map<String, dynamic>;
      String authorPseudo = senderId;
      try {
        authorPseudo = _transport.connectedPeers.firstWhere((p) => p.peerId == senderId).pseudo;
      } catch (_) {
        try {
          authorPseudo = StorageService.getKnownPeers().firstWhere((p) => p.peerId == senderId).pseudo;
        } catch (_) {}
      }
      final checkin = SafetyCheckinRecord(
        peerId: senderId,
        pseudo: authorPseudo,
        timestamp: DateTime.tryParse(payload['ts'] as String? ?? '') ?? DateTime.now(),
        lat: (payload['lat'] as num?)?.toDouble(),
        lon: (payload['lon'] as num?)?.toDouble(),
      );
      unawaited(StorageService.saveSafetyCheckin(checkin));
      _safetyCheckinCtrl.add(checkin);
    } catch (e) {
      debugPrint('[MeshRepo] check-in de sécurité invalide: $e');
    }
  }

  static const Duration _statusLifetime = Duration(hours: 24);

  /// Diffuse un statut éphémère à tout le mesh — public par nature,
  /// comme les statuts WhatsApp vus par tous les contacts.
  ///
  /// [media] peut porter une photo, une vidéo, un message vocal et une
  /// musique d'accompagnement. Les FICHIERS doivent avoir été envoyés
  /// AVANT l'appel (voir [sendStatusFile]) : cette annonce ne transporte
  /// que la légende et les identifiants qui pointent vers eux.
  Future<void> sendStatus(
    String content, {
    StatusMedia media = StatusMedia.empty,
  }) async {
    final now = DateTime.now();
    final status = MeshStatusRecord(
      id: StorageService.generateId(),
      authorId: _myId,
      authorPseudo: _myPseudo,
      content: content,
      createdAt: now,
      expiresAt: now.add(_statusLifetime),
    );
    await StorageService.saveStatus(status);
    await StorageService.saveStatusMedia(status.id, media);

    final payload = <String, dynamic>{
      'id': status.id,
      'content': content,
      'createdAt': status.createdAt.toIso8601String(),
      'expiresAt': status.expiresAt.toIso8601String(),
      // Absent quand le statut est en texte seul : inutile d'alourdir
      // l'annonce d'un objet vide, et les versions antérieures de
      // Droplet ignorent simplement cette clé qu'elles ne connaissent
      // pas.
      if (!media.isPlainText) 'media': media.toJson(),
    };
    final jsonMap = <String, dynamic>{
      'c': json.encode(payload),
      's': _myId,
      'k': 'status',
    };
    final payloadBytes = utf8.encode(json.encode(jsonMap));
    final data = Uint8List(2 + payloadBytes.length);
    data[0] = kDefaultHopCount;
    data[1] = kTextMessageType;
    data.setRange(2, data.length, payloadBytes);
    try {
      await _enqueueReliable(
        messageId: 'status-${status.id}',
        targetId: 'broadcast',
        data: data,
        priority: MessagePriority.normal,
      );
    } catch (e) {
      _criticalSendFailureCtrl.add((kind: 'status', messageId: status.id, reason: e.toString()));
      rethrow;
    }
  }

  /// Diffuse un fichier destiné à un statut (photo, vidéo, vocal,
  /// musique) et renvoie son identifiant.
  ///
  /// En clair, et c'est volontaire : un statut est PUBLIC par définition,
  /// destiné à quiconque passe à portée. Le chiffrer supposerait de
  /// connaître à l'avance la liste de ses destinataires — or on ne la
  /// connaît pas, c'est justement tout l'intérêt.
  ///
  /// ⚠️ Les images >10 Mo sont automatiquement compressées (JPEG, qualité
  /// 85, max 2048px) avant envoi — sur un mesh, la bande passante est
  /// comptée et une photo de 10 Mo prendrait des minutes à traverser.
  Future<String> sendStatusFile({
    required String fileName,
    required Uint8List bytes,
    required String mimeType,
  }) async {
    // Compression automatique des images volumineuses.
    final compressed = await MediaService.compressIfNeeded(
      bytes: bytes,
      fileName: fileName,
      mimeType: mimeType,
    );

    final fileId = StorageService.generateId();
    await StorageService.saveSharedFile(
        fileId: fileId, fileName: compressed.name, bytes: compressed.bytes);
    await sendFile(
      fileName: compressed.name,
      bytes: compressed.bytes,
      mimeType: compressed.name.endsWith('.jpg') || compressed.name.endsWith('.jpeg')
          ? 'image/jpeg'
          : mimeType,
      fileId: fileId,
      forStatus: true,
    );
    return fileId;
  }

  /// Envoie un « j'aime » ou un commentaire à l'auteur d'un statut.
  ///
  /// Ciblé sur le seul auteur, jamais diffusé — voir [StatusFeedback]
  /// pour la raison, qui tient autant à la discrétion qu'à ce qu'un
  /// compteur public serait impossible à tenir juste sur un maillage.
  Future<void> sendStatusFeedback({
    required String authorId,
    required String statusId,
    String? emoji,
    String? text,
    bool remove = false,
  }) async {
    if (authorId == _myId) return;
    final payload = <String, dynamic>{
      'statusId': statusId,
      'ts': DateTime.now().toIso8601String(),
      'emoji': ?emoji,
      'text': ?text,
      if (remove) 'remove': true,
    };
    final jsonMap = <String, dynamic>{
      'c': json.encode(payload),
      's': _myId,
      'k': 'status_feedback',
      't': authorId,
    };
    final payloadBytes = utf8.encode(json.encode(jsonMap));
    final data = Uint8List(2 + payloadBytes.length);
    data[0] = kDefaultHopCount;
    data[1] = kTextMessageType;
    data.setRange(2, data.length, payloadBytes);
    // Passe par la file fiable, contrairement aux accusés de vue : un
    // commentaire qu'on prend la peine d'écrire doit finir par arriver,
    // même si son destinataire est momentanément hors de portée.
    await _enqueueReliable(
      messageId: 'feedback-$statusId-${DateTime.now().microsecondsSinceEpoch}',
      targetId: authorId,
      data: data,
      priority: MessagePriority.normal,
    );
  }

  void _handleStatusFeedback(String senderId, String content) {
    try {
      final payload = json.decode(content) as Map<String, dynamic>;
      final statusId = payload['statusId'] as String?;
      if (statusId == null) return;

      String pseudo = senderId;
      try {
        pseudo = _transport.connectedPeers
            .firstWhere((p) => p.peerId == senderId)
            .pseudo;
      } catch (_) {
        try {
          pseudo = StorageService.getKnownPeers()
              .firstWhere((p) => p.peerId == senderId)
              .pseudo;
        } catch (_) {}
      }

      if (payload['remove'] == true) {
        unawaited(StorageService.removeStatusLike(statusId, senderId));
        return;
      }

      final feedback = StatusFeedback(
        statusId: statusId,
        authorId: senderId,
        authorPseudo: pseudo,
        createdAt:
            DateTime.tryParse(payload['ts'] as String? ?? '') ?? DateTime.now(),
        emoji: payload['emoji'] as String?,
        text: payload['text'] as String?,
      );
      unawaited(StorageService.addStatusFeedback(feedback));
      _statusFeedbackCtrl.add(feedback);
    } catch (e) {
      debugPrint('[MeshRepo] retour de statut invalide: $e');
    }
  }

  void _handleStatus(String senderId, String content, String? appMsgId) {
    if (appMsgId != null) {
      if (_appMessageIds.containsKey(appMsgId)) return;
      _appMessageIds[appMsgId] = DateTime.now();
    }
    try {
      final payload = json.decode(content) as Map<String, dynamic>;
      final expiresAt = DateTime.tryParse(payload['expiresAt'] as String? ?? '');
      if (expiresAt == null || DateTime.now().isAfter(expiresAt)) return;

      String authorPseudo = senderId;
      try {
        authorPseudo = _transport.connectedPeers.firstWhere((p) => p.peerId == senderId).pseudo;
      } catch (_) {
        try {
          authorPseudo = StorageService.getKnownPeers().firstWhere((p) => p.peerId == senderId).pseudo;
        } catch (_) {}
      }

      final status = MeshStatusRecord(
        id: payload['id'] as String? ?? appMsgId ?? StorageService.generateId(),
        authorId: senderId,
        authorPseudo: authorPseudo,
        content: payload['content'] as String? ?? '',
        createdAt: DateTime.tryParse(payload['createdAt'] as String? ?? '') ?? DateTime.now(),
        expiresAt: expiresAt,
      );
      unawaited(StorageService.saveStatus(status));

      final rawMedia = payload['media'];
      if (rawMedia is Map<String, dynamic>) {
        unawaited(StorageService.saveStatusMedia(
            status.id, StatusMedia.fromJson(rawMedia)));
      }
      _statusCtrl.add(status);
    } catch (e) {
      debugPrint('[MeshRepo] statut invalide: $e');
    }
  }

  /// Signale à l'auteur [authorId] que j'ai vu son statut [statusId] —
  /// ciblé (comme une réaction), jamais diffusé largement. C'est ce qui
  /// permet d'afficher plus tard « Vu par Untel, Unetelle » sous son
  /// propre statut.
  Future<void> sendStatusSeen({required String authorId, required String statusId}) async {
    if (authorId == _myId) return;
    final payload = <String, dynamic>{
      'statusId': statusId,
      'ts': DateTime.now().toIso8601String(),
    };
    final jsonMap = <String, dynamic>{
      'c': json.encode(payload),
      's': _myId,
      'k': 'status_seen',
      't': authorId,
    };
    final payloadBytes = utf8.encode(json.encode(jsonMap));
    final data = Uint8List(2 + payloadBytes.length);
    data[0] = kDefaultHopCount;
    data[1] = kTextMessageType;
    data.setRange(2, data.length, payloadBytes);
    await _transport.broadcastToConnectedPeers(data);
  }

  void _handleStatusSeen(String senderId, String content) {
    try {
      final payload = json.decode(content) as Map<String, dynamic>;
      final statusId = payload['statusId'] as String?;
      if (statusId == null) return;
      String viewerPseudo = senderId;
      try {
        viewerPseudo = _transport.connectedPeers.firstWhere((p) => p.peerId == senderId).pseudo;
      } catch (_) {
        try {
          viewerPseudo = StorageService.getKnownPeers().firstWhere((p) => p.peerId == senderId).pseudo;
        } catch (_) {}
      }
      unawaited(StorageService.recordStatusView(
        statusId: statusId,
        viewerId: senderId,
        viewerPseudo: viewerPseudo,
        ts: DateTime.tryParse(payload['ts'] as String? ?? '') ?? DateTime.now(),
      ));
      _statusSeenCtrl.add(statusId);
    } catch (e) {
      debugPrint('[MeshRepo] accusé de vue de statut invalide: $e');
    }
  }

  // ── Relais (faire suivre un message qui ne m'était pas destiné) ────────
  //
  // Comme dans le jeu du téléphone arabe : chaque message porte un
  // « nombre de sauts » restants, qui diminue à chaque fois qu'il passe
  // par un téléphone. Ça l'empêche de tourner en rond éternellement sur
  // le réseau.

  /// Décide s'il faut relayer TOUT DE SUITE (des pairs sont connectés) ou
  /// mettre de côté pour plus tard (aucun pair connecté pour le moment).
  ///
  /// [targetId] : la destination logique du paquet (un pair, un groupe, ou
  /// null pour une diffusion publique). Elle permet au relais de choisir un
  /// chemin INTELLIGENT (next-hop connu de la table de routage) au lieu de
  /// noyer tout le voisinage.
  void _relayOrDefer(String messageId, Uint8List fullPayload, int remainingHops,
      {String? excludePeerId, String? targetId}) {
    if (remainingHops <= 1) {
      debugPrint('[MeshRepo] relais fini msg=$messageId (hops=$remainingHops)');
      return;
    }
    if (_transport.activePeerCount == 0) {
      _addPendingRelay(messageId, fullPayload);
      debugPrint('[MeshRepo] relais différé msg=$messageId (aucun pair actif)');
      return;
    }
    _relayNow(messageId, fullPayload, remainingHops,
        excludePeerId: excludePeerId, targetId: targetId);
  }

  /// Met un relais en attente (aucun pair connecté) avec une borne haute :
  /// si plus de [_pendingRelaysCap] messages attendent, on jette les plus
  /// vieux en priorité — stocker 10 000 relais en RAM + disque en attendant
  /// une reconnexion qui n'arrive peut-être pas ne servirait à rien.
  void _addPendingRelay(String messageId, Uint8List payload) {
    if (_pendingRelays.length >= _pendingRelaysCap) {
      _pendingRelays.removeAt(0);
    }
    _pendingRelays.add(_PendingRelay(messageId, Uint8List.fromList(payload)));
    _pendingRelayGeneration++;
    StorageService.savePendingRelay(messageId, payload);
  }

  /// Transmet réellement un relais au prochain saut.
  ///
  /// Routage adaptatif (protocole v2) : si le paquet est dirigé vers une
  /// destination précise et que la table de routage connaît un prochain
  /// saut (route directe ou multi-hop), on envoie UNIQUEMENT à ce pair —
  /// qui fera suivre. On ne retombe sur la diffusion au voisinage que si
  /// on ne sait pas encore où aller (découverte) ou si la route est
  /// introuvable.
  void _relayNow(String messageId, Uint8List fullPayload, int remainingHops,
      {String? excludePeerId, String? targetId}) {
    final nextHops = remainingHops - 1;
    var relayData = Uint8List.fromList(fullPayload);
    relayData[0] = nextHops;

    // ── ON SIGNE SON PASSAGE ──────────────────────────────────────
    //
    // Chaque relais ajoute son empreinte au champ `p` de l'enveloppe. Le
    // destinataire reçoit donc le trajet complet, et peut enfin
    // l'afficher — c'est ce qui manquait pour que `routeInfo` cesse
    // d'être une colonne vide.
    //
    // ⚠️ HUIT CARACTÈRES, PAS L'IDENTIFIANT ENTIER. Une empreinte
    // complète fait soixante-quatre caractères ; cinq relais en
    // ajouteraient plus de trois cents à un paquet qui doit tenir sous
    // les 512 octets du Bluetooth. Huit suffisent à distinguer deux
    // appareils à l'œil, et c'est déjà la forme abrégée qu'affiche
    // l'interface.
    relayData = _signerLePassage(relayData);

    // `broadcastToConnectedPeers` utilise Future.wait : un seul pair dont le
    // transport échoue pendant la diffusion suffit à rejeter le Future
    // entier. Fire-and-forget assumé (le relais est best-effort), donc
    // jamais laissé remonter comme exception non rattrapée.
    Future<void> relay = _relayToNextHop(
      messageId, relayData, targetId, excludePeerId);
    unawaited(relay
        .then((_) => StorageService.incrementRelayCount())
        .catchError((e) => debugPrint('[MeshRepo] échec relais msg=$messageId: $e')));
    _relayCounter++;
    debugPrint('[MeshRepo] relais #$_relayCounter msg=$messageId hops=$remainingHops→$nextHops peers=${_transport.connectedPeerCount} target=$targetId');
  }

  /// Choisit le prochain saut : route connue si [targetId] est précis, sinon
  /// diffusion au voisinage.
  Future<void> _relayToNextHop(
      String messageId, Uint8List relayData, String? targetId, String? excludePeerId) {
    if (targetId != null && targetId != 'broadcast') {
      try {
        return _transport
            .sendViaRoute(targetId, relayData)
            .then((routed) {
          if (routed) return Future<void>.value();
          // Route inconnue → on ne peut pas cibler, on diffuse.
          return _transport.broadcastToConnectedPeers(relayData,
              excludePeerId: excludePeerId);
        });
      } catch (e) {
        debugPrint('[MeshRepo] route vers $targetId impossible: $e — diffusion');
      }
    }
    return _transport.broadcastToConnectedPeers(relayData,
        excludePeerId: excludePeerId);
  }

  int _relayCounter = 0;

  /// Dès qu'un pair se reconnecte, on essaie d'envoyer tous les messages
  /// qu'on gardait de côté faute de destinataire disponible — comme
  /// vider la boîte aux lettres d'attente dès que quelqu'un repasse.
  ///
  /// Utilise un compteur de génération pour détecter si de nouveaux
  /// relais sont arrivés pendant le vidage. Si c'est le cas, un
  /// deuxième flush est programmé — on ne perd jamais un relais ajouté
  /// entre le `clear()` et la fin des envois.
  void flushPendingRelays() {
    if (_pendingRelays.isEmpty) return;
    final gen = _pendingRelayGeneration;
    final toForward = List<_PendingRelay>.from(_pendingRelays);
    _pendingRelays.clear();
    StorageService.clearPendingRelays();
    debugPrint('[MeshRepo] flush ${toForward.length} relais en attente');
    for (final pending in toForward) {
      final hops = pending.payload.isNotEmpty ? pending.payload[0] : 0;
      if (hops > 1) _relayNow(pending.id, pending.payload, hops);
    }
    // Si de nouveaux relais ont été ajoutés pendant l'envoi, relancer.
    if (_pendingRelayGeneration != gen && _pendingRelays.isNotEmpty) {
      scheduleMicrotask(flushPendingRelays);
    }
  }

  void _loadPendingRelays() {
    try {
      final stored = StorageService.getPendingRelays();
      for (final entry in stored) {
        final id = entry['id'] as String;
        final b64 = entry['payload'] as String;
        final payload = base64Decode(b64);
        _addPendingRelay(id, Uint8List.fromList(payload));
      }
      if (_pendingRelays.isNotEmpty) {
        debugPrint('[MeshRepo] ${_pendingRelays.length} relais chargés du stockage');
      }
    } catch (e) {
      debugPrint('[MeshRepo] erreur chargement relais: $e');
    }
  }

  List<MeshMessage> getMessagesByType(String type) {
    return StorageService.getMessages()
        .where((m) => m.type == type)
        .toList();
  }

  List<MeshMessage> getMessagesByAuthor(String pseudo) {
    return StorageService.getMessages()
        .where((m) => m.authorPseudo == pseudo)
        .toList();
  }

  int getMessageCount() => StorageService.getMessages().length;

  /// Fabrique les statistiques affichées sur l'écran « Réseau mesh »
  /// (nombre de pairs, fiabilité moyenne, fichiers relayés, etc.).
  MeshStats getStats() {
    final health = _transport.health;
    return MeshStats(
      distributedGb: StorageService.getMessageCount() * 0.001,
      relayedFiles: StorageService.getMessages().where((m) => m.type == 'file').length,
      helpedPeers: _transport.connectedPeerCount,
      totalPeers: _transport.connectedPeerCount,
      blePeers: _transport.blePeerCount,
      wifiPeers: _transport.wifiPeerCount,
      nativePeers: _transport.nativePeerCount,
      averageReliability: health.averageReliability,
      messagesSent: health.messagesSent,
      acksReceived: health.acksReceived,
    );
  }

  void setGatewayMode(bool enabled) {
    _transport.setRole(enabled ? PeerRole.gateway : PeerRole.leaf);
  }

  // ── Groupes de discussion (sender-keys façon Signal/WhatsApp) ───────────
  //
  // Pas de serveur de groupe : chaque mutation (création, ajout, retrait,
  // renommage) est appliquée localement puis diffusée en manifeste complet
  // ("group_sync") à chaque membre concerné, toujours via le canal 1:1 déjà
  // chiffré. La convergence entre appareils se fait par LWW sur le
  // timestamp le plus récent (ajout ou retrait) par membre — voir
  // [_applyGroupSync]. Les messages de groupe eux-mêmes sont chiffrés avec
  // la sender-key de leur auteur (ratchet HMAC, [CryptoService.ratchetForward]).
  //
  // Pour un enfant de 8 ans : imagine un club secret. Il n'y a pas de
  // chef unique qui note tout dans un grand cahier central — à la place,
  // chaque membre écrit lui-même les changements (« Untel a rejoint »,
  // « Unetelle est partie ») sur son PROPRE petit carnet, et le montre
  // aux autres. Si deux membres ont des versions différentes, celle avec
  // la date la plus récente gagne. Et chaque membre a son propre
  // « cadenas à combinaison qui change » (sa sender-key) pour signer ses
  // messages dans le club — s'il est exclu, on change tous les cadenas
  // pour qu'il ne puisse plus rien lire de nouveau.

  /// Crée un groupe et m'en nomme administrateur. Diffuse le manifeste et
  /// distribue ma sender-key à chaque membre initial.
  Future<String> createGroup({required String name, required Set<String> memberIds}) async {
    final groupId = StorageService.generateId();
    final now = DateTime.now();
    await StorageService.upsertGroup(id: groupId, name: name, createdBy: _myId, createdAt: now, updatedAt: now);
    await StorageService.upsertGroupMember(groupId: groupId, peerId: _myId, role: 'admin', addedAt: now, addedBy: _myId);
    for (final peerId in memberIds.where((id) => id != _myId)) {
      await StorageService.upsertGroupMember(groupId: groupId, peerId: peerId, role: 'member', addedAt: now, addedBy: _myId);
    }
    await _bootstrapMySenderKey(groupId);
    await _syncGroupToMembers(groupId);
    _groupsChangedCtrl.add(groupId);
    return groupId;
  }

  /// Ajoute [peerId] au groupe (réservé aux administrateurs).
  Future<void> addGroupMember({required String groupId, required String peerId}) async {
    final group = StorageService.getGroup(groupId);
    if (group == null || !group.isAdmin(_myId)) {
      throw StateError('Seul un administrateur peut ajouter un membre à ce groupe');
    }
    final now = DateTime.now();
    await StorageService.upsertGroupMember(groupId: groupId, peerId: peerId, role: 'member', addedAt: now, addedBy: _myId);
    await StorageService.upsertGroup(
      id: group.id, name: group.name, avatarUrl: group.avatarUrl,
      createdBy: group.createdBy, createdAt: group.createdAt, updatedAt: now,
    );
    await _syncGroupToMembers(groupId);
    _groupsChangedCtrl.add(groupId);
  }

  /// Retire [peerId] du groupe (réservé aux administrateurs). Ma sender-key
  /// est régénérée et redistribuée aux membres restants : le membre exclu
  /// ne pourra plus déchiffrer les messages futurs.
  Future<void> removeGroupMember({required String groupId, required String peerId}) async {
    final group = StorageService.getGroup(groupId);
    if (group == null || !group.isAdmin(_myId)) {
      throw StateError('Seul un administrateur peut retirer un membre de ce groupe');
    }
    await _markMemberRemoved(group, peerId);
    await StorageService.deleteGroupSenderKey(groupId, peerId);
    await _bootstrapMySenderKey(groupId); // rotation + redistribution aux membres restants
    await _syncGroupToMembers(groupId); // informe les membres restants du retrait
    _groupsChangedCtrl.add(groupId);
  }

  /// Quitte le groupe. Les membres restants apprendront mon départ via la
  /// prochaine synchro et feront tourner leur propre sender-key.
  Future<void> leaveGroup(String groupId) async {
    final group = StorageService.getGroup(groupId);
    if (group == null) return;
    await _markMemberRemoved(group, _myId);
    await StorageService.deleteGroupSenderKey(groupId, _myId);
    await _syncGroupToMembers(groupId);
    _groupsChangedCtrl.add(groupId);
  }

  Future<void> _markMemberRemoved(GroupInfo group, String peerId) async {
    final now = DateTime.now();
    final existing = group.members.where((m) => m.peerId == peerId);
    await StorageService.upsertGroupMember(
      groupId: group.id,
      peerId: peerId,
      role: existing.isNotEmpty ? existing.first.role : 'member',
      addedAt: existing.isNotEmpty ? existing.first.addedAt : now,
      removedAt: now,
      addedBy: existing.isNotEmpty ? existing.first.addedBy : _myId,
    );
    await StorageService.upsertGroup(
      id: group.id, name: group.name, avatarUrl: group.avatarUrl,
      createdBy: group.createdBy, createdAt: group.createdAt, updatedAt: now,
    );
  }

  /// Renomme le groupe (n'importe quel membre actif peut le faire, comme
  /// dans la plupart des messageries grand public).
  Future<void> renameGroup({required String groupId, required String name}) async {
    final group = StorageService.getGroup(groupId);
    if (group == null || !group.isActiveMember(_myId)) {
      throw StateError('Groupe introuvable ou vous n\'en êtes plus membre');
    }
    await StorageService.upsertGroup(
      id: group.id, name: name, avatarUrl: group.avatarUrl,
      createdBy: group.createdBy, createdAt: group.createdAt, updatedAt: DateTime.now(),
    );
    await _syncGroupToMembers(groupId);
    _groupsChangedCtrl.add(groupId);
  }

  /// Génère une nouvelle sender-key pour ce groupe et la distribue à tous
  /// les membres actifs (hors moi-même). Utilisé à la fois pour le
  /// bootstrap initial (création/adhésion) et la rotation (retrait d'un
  /// membre) — les deux cas veulent une chaîne fraîche redistribuée aux
  /// membres actuellement actifs.
  Future<void> _bootstrapMySenderKey(String groupId) async {
    final chainKey = await CryptoService.generateChainKey();
    await StorageService.upsertGroupSenderKey(
      groupId: groupId, ownerPeerId: _myId, chainKey: chainKey, counter: 0, isMine: true,
    );
    final group = StorageService.getGroup(groupId);
    if (group == null) return;
    final targets = group.activeMembers.map((m) => m.peerId).where((id) => id != _myId);
    for (final peerId in targets) {
      unawaited(_sendEncryptedControl(peerId, 'group_sender_key', {
        'groupId': groupId,
        'ownerPeerId': _myId,
        'chainKey': chainKey,
        'counter': 0,
      }).catchError((e) => debugPrint('[MeshRepo] échec distribution sender-key à $peerId: $e')));
    }
  }

  /// Diffuse le manifeste complet du groupe (métadonnées + tous les membres,
  /// y compris retirés — nécessaire pour propager les tombstones) à
  /// [onlyTo], ou à tous les membres actifs par défaut.
  Future<void> _syncGroupToMembers(String groupId, {Iterable<String>? onlyTo}) async {
    final group = StorageService.getGroup(groupId);
    if (group == null) return;
    final payload = {
      'id': group.id,
      'name': group.name,
      'avatarUrl': group.avatarUrl,
      'createdBy': group.createdBy,
      'createdAt': group.createdAt.toIso8601String(),
      'updatedAt': group.updatedAt.toIso8601String(),
      'members': group.members.map((m) => {
        'peerId': m.peerId,
        'role': m.role,
        'addedAt': m.addedAt.toIso8601String(),
        'removedAt': m.removedAt?.toIso8601String(),
        'addedBy': m.addedBy,
      }).toList(),
    };
    final targets = (onlyTo ?? group.activeMembers.map((m) => m.peerId)).where((id) => id != _myId);
    for (final peerId in targets) {
      unawaited(_sendEncryptedControl(peerId, 'group_sync', payload)
          .catchError((e) => debugPrint('[MeshRepo] échec synchro groupe vers $peerId: $e')));
    }
  }

  /// Applique un manifeste de groupe reçu : convergence par LWW (le
  /// timestamp le plus récent, ajout ou retrait, l'emporte par membre).
  /// Réagit aux transitions d'appartenance : bootstrap de ma sender-key si
  /// je viens de devenir membre actif, rotation + nettoyage si un membre
  /// vient d'être retiré.
  Future<void> _applyGroupSync(String senderId, Map<String, dynamic> payload) async {
    final groupId = payload['id'] as String;
    final name = payload['name'] as String;
    final avatarUrl = payload['avatarUrl'] as String?;
    final createdBy = payload['createdBy'] as String;
    final createdAt = DateTime.parse(payload['createdAt'] as String);
    final updatedAt = DateTime.parse(payload['updatedAt'] as String);
    final incomingMembers = (payload['members'] as List).cast<Map<String, dynamic>>();

    final existingGroup = StorageService.getGroup(groupId);
    final previouslyActive = existingGroup?.activeMembers.map((m) => m.peerId).toSet() ?? <String>{};

    if (existingGroup == null || updatedAt.isAfter(existingGroup.updatedAt)) {
      await StorageService.upsertGroup(
        id: groupId, name: name, avatarUrl: avatarUrl,
        createdBy: createdBy, createdAt: createdAt, updatedAt: updatedAt,
      );
    }

    for (final m in incomingMembers) {
      final peerId = m['peerId'] as String;
      final role = m['role'] as String;
      final addedAt = DateTime.parse(m['addedAt'] as String);
      final removedAtRaw = m['removedAt'] as String?;
      final removedAt = removedAtRaw != null ? DateTime.parse(removedAtRaw) : null;
      final addedBy = m['addedBy'] as String;
      final incomingEventTime = removedAt ?? addedAt;

      GroupMemberRecord? local;
      for (final lm in StorageService.getGroupMembers(groupId)) {
        if (lm.peerId == peerId) { local = lm; break; }
      }
      final localEventTime = local == null ? null : (local.removedAt ?? local.addedAt);
      if (local == null || localEventTime == null || incomingEventTime.isAfter(localEventTime)) {
        await StorageService.upsertGroupMember(
          groupId: groupId, peerId: peerId, role: role,
          addedAt: addedAt, removedAt: removedAt, addedBy: addedBy,
        );
      }
    }

    final updatedGroup = StorageService.getGroup(groupId);
    if (updatedGroup == null) return;
    final nowActive = updatedGroup.activeMembers.map((m) => m.peerId).toSet();
    final isActiveNow = nowActive.contains(_myId);
    final wasActiveMember = previouslyActive.contains(_myId);

    if (isActiveNow && !wasActiveMember) {
      // Je viens de rejoindre (ou de recevoir le manifeste initial) : je ne
      // peux pas lire l'historique, mais je génère et distribue ma propre
      // sender-key pour les messages à venir.
      await _bootstrapMySenderKey(groupId);
    } else if (isActiveNow) {
      // Membres tout juste ajoutés par ce manifeste : je leur pousse ma
      // sender-key courante pour qu'ils puissent me déchiffrer.
      final newlyAdded = nowActive.difference(previouslyActive)..remove(_myId);
      for (final peerId in newlyAdded) {
        final mine = await StorageService.getGroupSenderKey(groupId, _myId);
        if (mine == null) continue;
        unawaited(_sendEncryptedControl(peerId, 'group_sender_key', {
          'groupId': groupId,
          'ownerPeerId': _myId,
          'chainKey': mine.chainKey,
          'counter': mine.counter,
        }).catchError((e) => debugPrint('[MeshRepo] échec envoi sender-key à $peerId: $e')));
      }
    }

    final justRemoved = previouslyActive.difference(nowActive);
    for (final peerId in justRemoved) {
      await StorageService.deleteGroupSenderKey(groupId, peerId);
    }
    if (isActiveNow && justRemoved.isNotEmpty) {
      await _bootstrapMySenderKey(groupId);
    }
  }

  /// Enregistre une sender-key reçue d'un autre membre (ou confirmation de
  /// la mienne, sans effet notable dans ce cas).
  Future<void> _applyIncomingSenderKey(Map<String, dynamic> payload) async {
    final groupId = payload['groupId'] as String;
    final ownerPeerId = payload['ownerPeerId'] as String;
    final chainKey = payload['chainKey'] as String;
    final counter = payload['counter'] as int;
    await StorageService.upsertGroupSenderKey(
      groupId: groupId, ownerPeerId: ownerPeerId, chainKey: chainKey, counter: counter,
      isMine: ownerPeerId == _myId,
    );
    debugPrint('[MeshRepo] sender-key reçue pour groupe $groupId de $ownerPeerId');
  }

  /// Avance ma sender-key d'un cran pour ce groupe et persiste le nouvel
  /// état. Un seul compteur de ratchet partagé pour tous les types de
  /// message (texte, fichier) que j'envoie dans ce groupe.
  Future<(SecretKey messageKey, int counter)> _advanceMySenderKey(String groupId) async {
    final keyState = await StorageService.getGroupSenderKey(groupId, _myId);
    if (keyState == null) {
      throw StateError('Aucune clé d\'envoi pour ce groupe — rejoignez-le avant d\'envoyer un message');
    }
    final (messageKey, nextChainKeyB64) = await CryptoService.ratchetForward(keyState.chainKey);
    final newCounter = keyState.counter + 1;
    await StorageService.upsertGroupSenderKey(
      groupId: groupId, ownerPeerId: _myId, chainKey: nextChainKeyB64, counter: newCounter, isMine: true,
    );
    return (messageKey, newCounter);
  }

  /// Envoie un message de groupe, chiffré avec ma sender-key courante
  /// (ratchet HMAC — un cran par message).
  Future<void> sendGroupMessage({
    required String groupId,
    required String content,
    String? replyToId,
    String? messageId,
    String? effect,
  }) async {
    final (messageKey, newCounter) = await _advanceMySenderKey(groupId);
    final (cipherText, nonce) = await CryptoService.encrypt(messageKey, content);
    final jsonMap = <String, dynamic>{
      'c': cipherText,
      's': _myId,
      'g': groupId,
      'n': nonce,
      'ctr': newCounter,
      'e': true,
    };
    if (replyToId != null) jsonMap['r'] = replyToId;
    if (messageId != null) jsonMap['m'] = messageId;
    if (effect != null) jsonMap['ef'] = effect;
    final payloadBytes = utf8.encode(json.encode(jsonMap));
    final data = Uint8List(2 + payloadBytes.length);
    data[0] = kDefaultHopCount;
    data[1] = kTextMessageType;
    data.setRange(2, data.length, payloadBytes);
    await _enqueueReliable(
      messageId: messageId ?? 'g-${DateTime.now().microsecondsSinceEpoch}',
      targetId: groupId,
      data: data,
      priority: MessagePriority.high,
    );
  }

  Future<void> _handleGroupContent({
    required MeshIncomingData data,
    required int hopCount,
    required String groupId,
    required String? senderId,
    required String? appMsgId,
    required String cipherText,
    required String? nonce,
    required int? counter,
    required String? replyToId,
    String? effect,
  }) async {
    if (senderId == null || nonce == null || counter == null) {
      _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: groupId);
      return;
    }
    if (appMsgId != null) {
      if (_appMessageIds.containsKey(appMsgId)) {
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: groupId);
        return;
      }
      _appMessageIds[appMsgId] = DateTime.now();
    }
    if (senderId == _myId) return;

    final group = StorageService.getGroup(groupId);
    if (group != null && group.isActiveMember(_myId)) {
      final content = await _decryptGroupContent(groupId, senderId, cipherText, nonce, counter);

      String authorPseudo = senderId;
      try {
        authorPseudo = _transport.connectedPeers.firstWhere((p) => p.peerId == senderId).pseudo;
      } catch (_) {
        try {
          authorPseudo = StorageService.getKnownPeers().firstWhere((p) => p.peerId == senderId).pseudo;
        } catch (_) {}
      }

      final msg = MeshMessage(
        id: appMsgId ?? data.messageId,
        authorPseudo: authorPseudo,
        content: content,
        type: 'mesh',
        timestamp: DateTime.now(),
        senderId: senderId,
        groupId: groupId,
        hopCount: hopCount,
        replyToId: replyToId,
        effect: effect,
      );
      StorageService.saveMessage(msg);
      _newMessageCtrl.add(msg);
    }

    _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: groupId);
  }

  /// Résout la clé de message pour déchiffrer un message de groupe : avance
  /// le ratchet de [senderId] jusqu'au [counter] reçu, avec tolérance au
  /// désordre (multi-hop) via un cache de clés "sautées"
  /// ([CryptoService.fastForward]). Retourne null si la clé de l'expéditeur
  /// est inconnue ou si le compteur ne peut être résolu.
  Future<SecretKey?> _resolveGroupMessageKey(String groupId, String senderId, int counter) async {
    final keyState = await StorageService.getGroupSenderKey(groupId, senderId);
    if (keyState == null) return null;

    if (counter == keyState.counter + 1) {
      final (msgKey, nextChain) = await CryptoService.ratchetForward(keyState.chainKey);
      await StorageService.upsertGroupSenderKey(
        groupId: groupId, ownerPeerId: senderId, chainKey: nextChain, counter: counter, isMine: false,
      );
      return msgKey;
    } else if (counter > keyState.counter + 1) {
      try {
        final result = await CryptoService.fastForward(keyState.chainKey, keyState.counter, counter);
        for (final entry in result.skipped.entries) {
          await StorageService.saveSkippedGroupKey(groupId, senderId, entry.key, entry.value);
        }
        await StorageService.upsertGroupSenderKey(
          groupId: groupId, ownerPeerId: senderId, chainKey: result.nextChainKeyB64, counter: counter, isMine: false,
        );
        return result.messageKey;
      } catch (e) {
        debugPrint('[MeshRepo] rattrapage ratchet groupe échoué: $e');
        return null;
      }
    } else {
      final skippedB64 = await StorageService.takeSkippedGroupKey(groupId, senderId, counter);
      return skippedB64 != null ? CryptoService.secretKeyFromBase64(skippedB64) : null;
    }
  }

  /// Déchiffre le contenu texte d'un message de groupe.
  Future<String> _decryptGroupContent(
    String groupId,
    String senderId,
    String cipherText,
    String nonce,
    int counter,
  ) async {
    final messageKey = await _resolveGroupMessageKey(groupId, senderId, counter);
    if (messageKey == null) {
      return '🔒 Message de groupe illisible (clé de l\'expéditeur manquante ou compteur dépassé)';
    }
    final decrypted = await CryptoService.decrypt(messageKey, cipherText, nonce);
    return decrypted ?? '🔒 Message de groupe illisible (échec du déchiffrement)';
  }

  // ── Transfert de fichiers (chiffré, 1:1 ou groupe) ──────────────────────
  //
  // Paquet : [hopCount][type][metaLen u16][meta JSON clair][nonceLen u8]
  // [nonce][cipher ou octets bruts]. `meta` ne porte que ce qui est
  // nécessaire au routage (identifiants, compteur de ratchet) ; le nom de
  // fichier, le type MIME et les octets sont chiffrés ensemble en un seul
  // bloc. Diffusion mesh totale (ni `t` ni `g`) : reste en clair, même
  // politique que le texte.

  static const int _kFileNonceMax = 32;

  Future<(Uint8List cipher, Uint8List nonce)> _encryptBytesForPeer(String targetId, Uint8List plaintext) async {
    final peerPublicKey = await _resolvePeerPublicKey(targetId);
    final sharedKey = await CryptoService.sharedKeyWithPeer(targetId, peerPublicKey);
    if (sharedKey == null) {
      throw StateError('Clé publique de $targetId inconnue — chiffrement impossible pour le moment');
    }
    return CryptoService.encryptBytes(sharedKey, plaintext);
  }

  /// Envoie un fichier (photo, document, message vocal) — chiffré pour un
  /// destinataire 1:1 ([targetId]) ou un groupe ([groupId], via ma
  /// sender-key courante). Ni l'un ni l'autre : diffusion mesh en clair.
  Future<void> sendFile({
    required String fileName,
    required Uint8List bytes,
    String mimeType = '',
    String? targetId,
    String? groupId,
    String? fileId,
    String? replyToId,
    bool forStatus = false,
  }) async {
    final id = fileId ?? StorageService.generateId();
    final nameBytes = Uint8List.fromList(utf8.encode(fileName));
    final mimeBytes = Uint8List.fromList(utf8.encode(mimeType));
    final plain = (BytesBuilder()
          ..addByte((nameBytes.length >> 8) & 0xFF)
          ..addByte(nameBytes.length & 0xFF)
          ..add(nameBytes)
          ..addByte(mimeBytes.length & 0xFF)
          ..add(mimeBytes)
          ..add(bytes))
        .toBytes();

    Uint8List payload;
    Uint8List nonce;
    int? counter;
    final encrypted = targetId != null || groupId != null;

    if (groupId != null) {
      final (messageKey, newCounter) = await _advanceMySenderKey(groupId);
      counter = newCounter;
      (payload, nonce) = await CryptoService.encryptBytes(messageKey, plain);
    } else if (targetId != null) {
      (payload, nonce) = await _encryptBytesForPeer(targetId, plain);
    } else {
      payload = plain;
      nonce = Uint8List(0);
    }

    final meta = <String, dynamic>{'fileId': id, 's': _myId, 'sz': bytes.length};
    if (targetId != null) meta['t'] = targetId;
    if (groupId != null) {
      meta['g'] = groupId;
      meta['ctr'] = counter;
    }
    if (encrypted) meta['e'] = true;
    // `r` = le message auquel celui-ci répond. Indispensable pour
    // répondre à un vocal par un vocal : sans ce champ, le destinataire
    // recevrait la réponse détachée de la question.
    if (replyToId != null) meta['r'] = replyToId;
    // `st` = ce fichier accompagne un statut, il ne doit PAS apparaître
    // comme une pièce jointe dans une conversation. Sans ce marqueur, la
    // photo d'un statut atterrirait aussi dans le fil « Diffusion »,
    // affichée deux fois et sortie de son contexte.
    if (forStatus) meta['st'] = true;

    final metaBytes = Uint8List.fromList(utf8.encode(json.encode(meta)));
    final packet = (BytesBuilder()
          ..addByte(kDefaultHopCount)
          ..addByte(kFileTransferType)
          ..addByte((metaBytes.length >> 8) & 0xFF)
          ..addByte(metaBytes.length & 0xFF)
          ..add(metaBytes)
          ..addByte(nonce.length)
          ..add(nonce)
          ..add(payload))
        .toBytes();

    await _enqueueReliable(
      messageId: 'file-$id',
      targetId: targetId ?? groupId ?? 'broadcast',
      data: packet,
      priority: MessagePriority.high,
    );
  }

  /// Reçoit un fichier : découpe le paquet (métadonnées, nonce, contenu),
  /// vérifie s'il m'est destiné, le déchiffre selon le contexte (1:1,
  /// groupe, ou en clair), et le range dans le stockage local si tout se
  /// passe bien.
  Future<void> _handleFileTransfer(MeshIncomingData data, int hopCount) async {
    try {
      final bytes = data.data;
      if (bytes.length < 5) return;
      final metaLen = (bytes[2] << 8) | bytes[3];
      if (bytes.length < 5 + metaLen) return;
      final meta = json.decode(utf8.decode(bytes.sublist(4, 4 + metaLen))) as Map<String, dynamic>;

      int offset = 4 + metaLen;
      final nonceLen = bytes[offset];
      offset += 1;
      if (nonceLen > _kFileNonceMax || bytes.length < offset + nonceLen) return;
      final nonce = bytes.sublist(offset, offset + nonceLen);
      offset += nonceLen;
      final payload = bytes.sublist(offset);

      final fileId = meta['fileId'] as String;
      final senderId = meta['s'] as String?;
      final targetId = meta['t'] as String?;
      final groupId = meta['g'] as String?;
      final counter = meta['ctr'] as int?;
      final encrypted = meta['e'] as bool? ?? false;
      final replyToId = meta['r'] as String?;
      final forStatus = meta['st'] as bool? ?? false;

      // Chat dirigé : si ce fichier ne m'est pas destiné, on ne fait que le
      // relayer (store-and-forward) sans le traiter.
      if (groupId == null && targetId != null && targetId != _myId) {
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: targetId);
        return;
      }

      if (_appMessageIds.containsKey(fileId)) {
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: groupId ?? targetId);
        return;
      }
      _appMessageIds[fileId] = DateTime.now();

      if (senderId == _myId) {
        _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: targetId);
        return;
      }

      Uint8List? plainBytes;
      if (!encrypted) {
        plainBytes = payload;
      } else if (groupId != null) {
        final group = StorageService.getGroup(groupId);
        if (group != null && group.isActiveMember(_myId) && senderId != null && counter != null) {
          final key = await _resolveGroupMessageKey(groupId, senderId, counter);
          if (key != null) plainBytes = await CryptoService.decryptBytes(key, payload, nonce);
        }
      } else if (senderId != null) {
        final peerPublicKey = _peerPublicKeyFromCaches(senderId);
        final sharedKey = await CryptoService.sharedKeyWithPeer(senderId, peerPublicKey);
        if (sharedKey != null) plainBytes = await CryptoService.decryptBytes(sharedKey, payload, nonce);
      }

      if (plainBytes != null && plainBytes.length >= 3) {
        final nameLen = (plainBytes[0] << 8) | plainBytes[1];
        if (plainBytes.length >= 2 + nameLen + 1) {
          final fileName = utf8.decode(plainBytes.sublist(2, 2 + nameLen));
          final mimeLen = plainBytes[2 + nameLen];
          final mimeStart = 2 + nameLen + 1;
          if (plainBytes.length >= mimeStart + mimeLen) {
            final mimeType = utf8.decode(plainBytes.sublist(mimeStart, mimeStart + mimeLen));
            final fileBytes = plainBytes.sublist(mimeStart + mimeLen);

            await StorageService.saveSharedFile(fileId: fileId, fileName: fileName, bytes: fileBytes);

            // Média d'un statut : on le range et on s'arrête là. C'est
            // l'annonce du statut, arrivée séparément, qui saura qu'il
            // existe et où le trouver.
            if (forStatus) {
              debugPrint('[MeshRepo] Média de statut reçu: $fileName '
                  '(${fileBytes.length} octets)');
              _statusMediaCtrl.add(fileId);
              _relayOrDefer(data.messageId, data.data, hopCount,
                  excludePeerId: data.peerId, targetId: null);
              return;
            }

            String authorPseudo = senderId ?? data.peerId;
            try {
              authorPseudo = _transport.connectedPeers.firstWhere((p) => p.peerId == (senderId ?? data.peerId)).pseudo;
            } catch (_) {
              try {
                authorPseudo = StorageService.getKnownPeers().firstWhere((p) => p.peerId == (senderId ?? data.peerId)).pseudo;
              } catch (_) {}
            }

            final msg = MeshMessage(
              id: fileId,
              authorPseudo: authorPseudo,
              content: fileName,
              type: 'file',
              timestamp: DateTime.now(),
              senderId: senderId ?? data.peerId,
              targetId: targetId,
              groupId: groupId,
              fileId: fileId,
              fileName: fileName,
              fileSize: fileBytes.length,
              fileMimeType: mimeType,
              replyToId: replyToId,
              hopCount: hopCount,
            );
            StorageService.saveMessage(msg);
            _newMessageCtrl.add(msg);
            debugPrint('[MeshRepo] Fichier reçu: $fileName (${fileBytes.length} octets)');
          }
        }
      }

      _relayOrDefer(data.messageId, data.data, hopCount, excludePeerId: data.peerId, targetId: groupId ?? targetId);
    } catch (e) {
      debugPrint('[MeshRepo] Erreur réception fichier: $e');
    }
  }
}
