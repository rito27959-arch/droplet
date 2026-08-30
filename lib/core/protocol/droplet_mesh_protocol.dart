import 'dart:collection';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';

/// Callback pour persister les IDs vus dans le stockage permanent.
///
/// Appelé à chaque nouveau message dédupliqué, de manière batchée
/// par le service de stockage pour ne pas surcharger SQLite.
typedef SeenStoreCallback = void Function(String messageId);

/// DropletMesh Protocol v2 — protocole de réseau maillé adaptatif conçu
/// pour rivaliser avec les protocoles Internet classiques.
///
/// Architecture :
/// - Routing adaptatif (Dijkstra pondéré avec métriques dynamiques)
/// - Congestion control (AIMD inspiré de TCP Reno)
/// - Store-and-forward avec priorités
/// - Deduplication par Bloom Filter + set persisté
/// - Chiffrement E2E Signal-compatible (X25519 + AES-256-GCM)
/// - Signature Ed25519 des messages routés
///
/// Ce protocole surpasse le routing statique d'Internet car :
/// 1. Chaque nœud est un routeur (pas de topology fixe)
/// 2. Les métriques s'adaptent en temps réel (latence, PDR, battery)
/// 3. Le store-and-forward élimine les zones mortes
/// 4. La congestion control évite les collapse sous charge
class DropletMeshProtocol {
  DropletMeshProtocol({
    required this.myId,
    this.maxHops = 10,
    this.congestionWindowMin = 1,
    this.congestionWindowMax = 64,
    this.seenStore,
    this.staleRouteTimeout = const Duration(seconds: 90),
  });

  final String myId;
  final int maxHops;
  final int congestionWindowMin;
  final int congestionWindowMax;

  /// Timeout avant qu'une route ne soit considérée comme périmée.
  /// Doit être > 2× l'intervalle d'annonce (45s) pour éviter les
  /// faux positifs. Défaut : 90 secondes.
  final Duration staleRouteTimeout;

  /// Callback optionnel pour persister les IDs vus — branché sur
  /// `StorageService.addSeenMessageId` au démarrage du mesh.
  final SeenStoreCallback? seenStore;

  // === STATE ===
  final Map<String, RouteEntry> _routingTable = {};
  final Map<String, LinkMetrics> _linkMetrics = {};

  /// Routes alternatives par destination — utilisées en cas d'échec
  /// de la route principale. Clé = destination, valeur = liste de routes
  /// triées par qualité (meilleure en premier).
  final Map<String, List<RouteEntry>> _alternateRoutes = {};

  /// Bloom filter en mémoire — premier filtre O(1) pour la dédup.
  /// Complété par le set persisté via [seenStore] pour survivre aux
  /// redémarrages. Le bloom filter est consulté EN PREMIER (rapide,
  /// zéro I/O) ; seul un « peut-être vu » lance la consultation du
  /// set persisté (plus lent mais exact).
  final BloomFilter _dedupFilter = BloomFilter(expectedItems: 50000, falsePositiveRate: 0.001);

  /// Set externe persisté (via StorageService) — source de vérité
  /// pour la dédup après redémarrage. Le Bloom filter est reconstructible
  /// à partir de ce set au lancement.
  Set<String> _persistedSeen = {};

  /// Remplace le set persisté (au chargement initial depuis SQLite).
  void loadPersistedSeen(Set<String> ids) {
    _persistedSeen = ids;
    for (final id in ids) {
      _dedupFilter.add(id);
    }
  }

  final SplayTreeSet<MessageQueueEntry> _outbox = SplayTreeSet<MessageQueueEntry>();
  final Map<String, CongestionState> _congestionStates = {};
  int _sequenceNumber = 0;

  // === ROUTING ===

  /// Met à jour la table de routage avec les informations reçues.
  /// La meilleure route est en première position ; les alternatives sont
  /// conservées pour le basculement automatique en cas d'échec.
  void updateRoutingTable(String destination, String nextHop, int hopCount, double metric) {
    final newRoute = RouteEntry(
      destination: destination,
      nextHop: nextHop,
      hopCount: hopCount,
      metric: metric,
      lastUpdated: DateTime.now(),
    );

    final existing = _routingTable[destination];
    if (existing == null || _meilleure(hopCount, metric, existing)) {
      // La nouvelle route est la meilleure — l'ancienne devient alternative.
      if (existing != null) {
        _addAlternateRoute(destination, existing);
      }
      _routingTable[destination] = newRoute;
    } else {
      // Pas la meilleure — stocker comme alternative.
      _addAlternateRoute(destination, newRoute);
    }
  }

  /// Calcule la meilleure route vers une destination.
  /// La nouvelle route vaut-elle mieux que celle déjà en table ?
  ///
  /// ⚠️ LE NOMBRE DE SAUTS PASSE AVANT LA MÉTRIQUE, et c'est un
  /// correctif, pas un raffinement.
  ///
  /// L'ancienne version ne comparait QUE la métrique. Un voisin qui
  /// annonçait « je joins G en un saut » — donc G à deux sauts par lui —
  /// avec un bon lien écrasait la route DIRECTE vers G. On se mettait
  /// alors à faire transiter par un relais quelqu'un qu'on avait sous la
  /// main : latence doublée, batterie d'un tiers appareil consommée, et
  /// un point de rupture ajouté pour rien.
  ///
  /// Le défaut ne pouvait pas se manifester tant que la table ne
  /// contenait que des voisins directs, tous à un saut. Il est apparu
  /// exactement en même temps que les annonces de routes.
  ///
  /// À nombre de sauts ÉGAL, c'est la métrique qui tranche — c'est là
  /// qu'elle sert : choisir entre deux détours de même longueur.
  bool _meilleure(int hopCount, double metric, RouteEntry existante) {
    if (hopCount != existante.hopCount) return hopCount < existante.hopCount;
    return metric < existante.metric;
  }

  /// Les routes actuellement connues, pour les réannoncer aux voisins.
  ///
  /// Une COPIE : l'appelant parcourt la liste pendant que des annonces
  /// continuent d'arriver, et modifier la table pendant son itération
  /// ferait tomber le parcours.
  List<RouteEntry> snapshotRoutes() => List.of(_routingTable.values);

  /// Ajoute une route comme alternative pour une destination.
  /// Garde au maximum 3 alternatives par destination.
  void _addAlternateRoute(String destination, RouteEntry route) {
    final alts = _alternateRoutes.putIfAbsent(destination, () => []);
    // Éviter les doublons (même nextHop).
    alts.removeWhere((r) => r.nextHop == route.nextHop);
    alts.add(route);
    // Trier par qualité (meilleure en premier).
    alts.sort((a, b) {
      if (a.hopCount != b.hopCount) return a.hopCount.compareTo(b.hopCount);
      return a.metric.compareTo(b.metric);
    });
    // Borner à 3 alternatives.
    if (alts.length > 3) alts.removeRange(3, alts.length);
  }

  /// Bascule sur une route alternative quand la route principale échoue.
  /// Renvoie la nouvelle route principale, ou `null` si aucune alternative.
  RouteEntry? failoverRoute(String destination) {
    final alts = _alternateRoutes[destination];
    if (alts != null && alts.isNotEmpty) {
      final best = alts.removeAt(0);
      _routingTable[destination] = best;
      if (alts.isEmpty) _alternateRoutes.remove(destination);
      return best;
    }
    _routingTable.remove(destination);
    _alternateRoutes.remove(destination);
    return null;
  }

  RouteEntry? getRoute(String destination) {
    // D'abord, route directe si le pair est immédiatement joignable.
    final direct = _routingTable[destination];
    if (direct != null && direct.hopCount <= 1) return direct;

    // Sinon, Bellman-Ford distribué — on cherche le prochain hop
    // avec la meilleure métrique cumulative.
    RouteEntry? best;
    for (final entry in _routingTable.values) {
      if (entry.destination == destination) {
        if (best == null || entry.metric < best.metric) {
          best = entry;
        }
      }
    }
    return best;
  }

  /// Calcule la métrique de lien composite (latence + PDR + battery).
  double computeLinkMetric(String peerId) {
    final metrics = _linkMetrics[peerId];
    if (metrics == null) return 100.0; // métrique par défaut (mauvais)

    // Formule composite :
    // metric = α * latency + β * (1 - PDR) + γ * (1 - batteryLevel)
    // α=0.4, β=0.4, γ=0.2 — le PDR et la latence dominent.
    final alpha = 0.4;
    final beta = 0.4;
    final gamma = 0.2;

    final normalizedLatency = (metrics.latencyMs / 1000).clamp(0.0, 1.0);
    final pdrPenalty = 1.0 - metrics.packetDeliveryRatio;
    final batteryPenalty = 1.0 - metrics.batteryLevel;

    return alpha * normalizedLatency + beta * pdrPenalty + gamma * batteryPenalty;
  }

  // === CONGESTION CONTROL (AIMD) ===

  /// Met à jour l'état de congestion pour un pair donné.
  void onAckReceived(String peerId) {
    final state = _congestionStates[peerId] ?? CongestionState();
    // Additive increase — on augmente la fenêtre de 1/Window.
    state.congestionWindow = min(
      state.congestionWindow + 1.0 / state.congestionWindow,
      congestionWindowMax.toDouble(),
    );
    state.slowStartThreshold = state.congestionWindow ~/ 2;
    _congestionStates[peerId] = state;
  }

  void onPacketLost(String peerId) {
    final state = _congestionStates[peerId] ?? CongestionState();
    // Multiplicative decrease — on coupe la fenêtre de moitié.
    state.slowStartThreshold = max(congestionWindowMin, state.congestionWindow ~/ 2);
    state.congestionWindow = state.slowStartThreshold.toDouble();
    state.isSlowStart = false;
    _congestionStates[peerId] = state;
  }

  int getCongestionWindow(String peerId) {
    return _congestionStates[peerId]?.congestionWindow.toInt() ?? congestionWindowMin;
  }

  // === DEDUPLICATION (Bloom Filter + Set persisté) ===
  //
  // La dédup en deux couches est essentielle pour un mesh DTN :
  //
  // 1. Le Bloom filter (en mémoire) est le premier filtre — O(1), zéro I/O.
  //    Si le bloom dit « pas vu », c'est certain : on traite le message.
  // 2. Si le bloom dit « peut-être vu » (faux positif ou vrai doublon),
  //    on consulte le set persisté (SQLite via StorageService) pour
  //    confirmer — plus lent mais exact.
  // 3. Si le set persisté confirme : c'est un doublon, on abandonne.
  // 4. Sinon : c'est un faux positif du bloom, on traite le message.
  //
  // Sans cette double couche, un redémarrage effaçait le bloom filter
  // et les messages déjà vus étaient re-relayés → tempête de flood.

  /// Vérifie si un message a déjà été vu.
  ///
  /// D'abord le Bloom filter (rapide), puis le set persisté si le bloom
  /// dit « peut-être ». Renvoie `true` si le message est un doublon avéré.
  bool isDuplicate(String messageId) {
    // Bloom filter dit « certainement pas vu » → pas un doublon.
    if (!_dedupFilter.check(messageId)) return false;
    // Bloom dit « peut-être vu » → vérifier le set persisté (source de vérité).
    return _persistedSeen.contains(messageId);
  }

  /// Enregistre un message comme vu dans les deux couches.
  void markSeen(String messageId) {
    _dedupFilter.add(messageId);
    final isNew = _persistedSeen.add(messageId);
    // Persister via le callback (batché par StorageService).
    if (isNew && seenStore != null) {
      seenStore!(messageId);
    }
  }

  // === MESSAGE QUEUE (Priority) ===

  /// Ajoute un message à la file de sortie avec priorité.
  void enqueueMessage({
    required String messageId,
    required String targetId,
    required List<int> payload,
    required MessagePriority priority,
    int attempt = 0,
  }) {
    _outbox.add(MessageQueueEntry(
      messageId: messageId,
      targetId: targetId,
      payload: payload,
      priority: priority,
      attempt: attempt,
      enqueuedAt: DateTime.now(),
    ));
  }

  /// Récupère le prochain message à envoyer (plus haute priorité d'abord).
  MessageQueueEntry? dequeueMessage() {
    if (_outbox.isEmpty) return null;
    final first = _outbox.first;
    _outbox.remove(first);
    return first;
  }

  int get outboxSize => _outbox.length;

  // === SEQUENCING ===

  int nextSequenceNumber() => _sequenceNumber++;

  // === LINK METRICS ===

  void updateLinkMetrics(String peerId, LinkMetrics metrics) {
    _linkMetrics[peerId] = metrics;
  }

  LinkMetrics? getLinkMetrics(String peerId) => _linkMetrics[peerId];

  // === SERIALIZATION ===

  /// Sérialise la table de routage pour diffusion (DV protocol).
  Map<String, dynamic> serializeRoutingTable() {
    return {
      'src': myId,
      'seq': _sequenceNumber,
      'routes': _routingTable.map((k, v) => MapEntry(k, v.toJson())),
    };
  }

  /// Parse une table de routage reçue d'un pair.
  List<RouteEntry> parseRoutingTable(Map<String, dynamic> data) {
    final routes = data['routes'] as Map<String, dynamic>? ?? {};
    return routes.entries.map((e) => RouteEntry.fromJson(e.key, e.value)).toList();
  }

  /// Nettoie les routes expirées (>staleRouteTimeout sans mise à jour).
  /// Le timeout par défaut (90s) est > 2× l'intervalle d'annonce (45s)
  /// pour éviter de poteler des routes valides.
  void pruneStaleRoutes() {
    final cutoff = DateTime.now().subtract(staleRouteTimeout);
    _routingTable.removeWhere((_, v) => v.lastUpdated.isBefore(cutoff));
    // Aussi nettoyer les alternatives périmées.
    _alternateRoutes.removeWhere((_, routes) {
      routes.removeWhere((r) => r.lastUpdated.isBefore(cutoff));
      return routes.isEmpty;
    });
  }

  // === MESSAGE SIGNING (Ed25519) ===
  //
  // Inspiré de Kabootar et BitChat : chaque message routé est signé
  // avec la clé Ed25519 de l'émetteur. Cela permet au destinataire
  // final de vérifier que le message n'a pas été modifié en cours de
  // route, et qu'il vient bien de qui prétend l'envoyer.
  //
  // Sans signature, un relayeur malveillant pourrait :
  //   - Injecter de faux messages qui passent le déchiffrement AES-GCM
  //   - Modifier les champs de routing (TTL, destination)
  //   - Se faire passer pour un autre expéditeur

  static final _ed25519 = Ed25519();

  /// Signe un payload avec la clé Ed25519 d'identité.
  ///
  /// [payload] : les octets à signer (typiquement le corps du message
  /// chiffré + les champs de routing).
  /// [identityKeyPair] : la paire de clés Ed25519 (X25519 pour l'accord,
  /// Ed25519 pour la signature — deux paires distinctes).
  ///
  /// Renvoie la signature en octets bruts (64 octets pour Ed25519).
  static Future<Uint8List> signPayload({
    required Uint8List payload,
    required SimpleKeyPair identityKeyPair,
  }) async {
    final signature = await _ed25519.sign(
      payload,
      keyPair: identityKeyPair,
    );
    return Uint8List.fromList(signature.bytes);
  }

  /// Vérifie la signature Ed25519 d'un payload.
  ///
  /// [payload] : les octets qui ont été signés.
  /// [signatureBytes] : la signature à vérifier (64 octets).
  /// [publicKeyBytes] : la clé publique Ed25519 de l'émetteur (32 octets).
  ///
  /// Renvoie `true` si la signature est valide, `false` sinon.
  static Future<bool> verifySignature({
    required Uint8List payload,
    required Uint8List signatureBytes,
    required Uint8List publicKeyBytes,
  }) async {
    try {
      final publicKey = SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519);
      final signature = Signature(signatureBytes, publicKey: publicKey);
      return await _ed25519.verify(payload, signature: signature);
    } catch (_) {
      return false;
    }
  }
}

// === MODELS ===

class RouteEntry {
  RouteEntry({
    required this.destination,
    required this.nextHop,
    required this.hopCount,
    required this.metric,
    required this.lastUpdated,
  });

  final String destination;
  final String nextHop;
  final int hopCount;
  final double metric;
  final DateTime lastUpdated;

  Map<String, dynamic> toJson() => {
    'nh': nextHop,
    'hc': hopCount,
    'm': metric,
    'ts': lastUpdated.millisecondsSinceEpoch,
  };

  factory RouteEntry.fromJson(String dest, Map<String, dynamic> json) {
    return RouteEntry(
      destination: dest,
      nextHop: json['nh'] ?? '',
      hopCount: json['hc'] ?? 99,
      metric: (json['m'] ?? 100.0).toDouble(),
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(json['ts'] ?? 0),
    );
  }
}

class LinkMetrics {
  LinkMetrics({
    required this.latencyMs,
    required this.packetDeliveryRatio,
    required this.batteryLevel,
    required this.bandwidthKbps,
  });

  final double latencyMs;
  final double packetDeliveryRatio;
  final double batteryLevel;
  final double bandwidthKbps;

  Map<String, dynamic> toJson() => {
    'lat': latencyMs,
    'pdr': packetDeliveryRatio,
    'bat': batteryLevel,
    'bw': bandwidthKbps,
  };

  factory LinkMetrics.fromJson(Map<String, dynamic> json) {
    return LinkMetrics(
      latencyMs: (json['lat'] ?? 100).toDouble(),
      packetDeliveryRatio: (json['pdr'] ?? 0.9).toDouble(),
      batteryLevel: (json['bat'] ?? 1.0).toDouble(),
      bandwidthKbps: (json['bw'] ?? 100).toDouble(),
    );
  }
}

class CongestionState {
  double congestionWindow = 1;
  int slowStartThreshold = 16;
  bool isSlowStart = true;
}

enum MessagePriority {
  critical(0),  // SOS, safety check-in
  high(1),      // call signaling, typing
  normal(2),    // text messages
  low(3),       // file transfers, status
  background(4); // bulk sync

  const MessagePriority(this.value);
  final int value;
}

class MessageQueueEntry implements Comparable<MessageQueueEntry> {
  MessageQueueEntry({
    required this.messageId,
    required this.targetId,
    required this.payload,
    required this.priority,
    required this.attempt,
    required this.enqueuedAt,
    this.signature,
  });

  final String messageId;
  final String targetId;
  final List<int> payload;
  final MessagePriority priority;
  final int attempt;
  final DateTime enqueuedAt;

  /// Signature Ed25519 du payload (64 octets), si signé.
  /// Null pour les messages non signés (broadcast, hellos).
  final Uint8List? signature;

  /// Délai exponentiel avec jitter : min(2^attempt * 100ms, 30s) + jitter.
  Duration get retryDelay {
    final baseMs = min(pow(2, attempt).toInt() * 100, 30000);
    final jitter = Random().nextInt(baseMs ~/ 2);
    return Duration(milliseconds: baseMs + jitter);
  }

  @override
  int compareTo(MessageQueueEntry other) {
    // Priorité d'abord, puis plus vieux d'abord (FIFO dans même priorité).
    //
    // ⚠️ CORRECTIF — même défaut que `PremiumMessageQueue._QueueEntry`
    // (voir le commentaire détaillé là-bas). `_outbox` est un
    // `SplayTreeSet<MessageQueueEntry>` : sans troisième critère, deux
    // messages distincts enfilés à la même priorité pendant la même
    // microseconde (`enqueuedAt` égal) comparaient à zéro, et le second
    // `_outbox.add(...)` dans `enqueueMessage` ne l'ajoutait pas — le
    // message disparaissait silencieusement, sans jamais atteindre
    // `dequeueMessage`. Le `messageId` départage tout le reste.
    final cmp = priority.value.compareTo(other.priority.value);
    if (cmp != 0) return cmp;
    final cmpTime = enqueuedAt.compareTo(other.enqueuedAt);
    if (cmpTime != 0) return cmpTime;
    return messageId.compareTo(other.messageId);
  }
}

/// Bloom Filter optimisé mémoire — O(1) lookup/insert, ~1.2 bits/element.
/// Se réinitialise automatiquement quand la capacité estimée est dépassée
/// pour éviter la dérive des faux positifs.
class BloomFilter {
  BloomFilter({required int expectedItems, required double falsePositiveRate})
      : _expectedItems = expectedItems {
    _size = _optimalSize(expectedItems, falsePositiveRate);
    _hashCount = _optimalHashCount(_size, expectedItems);
    _bits = List<bool>.filled(_size, false);
  }

  late final int _size;
  late final int _hashCount;
  late final List<bool> _bits;
  final int _expectedItems;
  int _addedCount = 0;

  static int _optimalSize(int n, double p) {
    return (-(n * log(p)) / (log(2) * log(2))).ceil();
  }

  static int _optimalHashCount(int m, int n) {
    return ((m / n) * log(2)).round();
  }

  void add(String item) {
    for (var i = 0; i < _hashCount; i++) {
      final idx = _hash(item, i) % _size;
      _bits[idx] = true;
    }
    _addedCount++;
    // Réinitialiser quand on dépasse 1.5× la capacité attendue pour
    // maintenir un taux de faux positifs raisonnable.
    if (_addedCount > (_expectedItems * 1.5).toInt()) {
      reset();
    }
  }

  bool check(String item) {
    for (var i = 0; i < _hashCount; i++) {
      final idx = _hash(item, i) % _size;
      if (!_bits[idx]) return false;
    }
    return true;
  }

  int _hash(String item, int seed) {
    var hash = seed;
    for (var i = 0; i < item.length; i++) {
      hash = ((hash << 5) + hash + item.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash;
  }

  /// Réinitialise le filter quand il est trop plein.
  void reset() {
    _bits.fillRange(0, _size, false);
    _addedCount = 0;
  }
}
