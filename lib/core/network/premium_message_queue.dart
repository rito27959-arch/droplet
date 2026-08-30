import 'dart:async';
import 'dart:collection';
import 'dart:math';

/// MessageQueue v2 — file de messages prioritaire avec retry exponentiel,
/// dedup, et metrics en temps réel. Garantit la livraison même dans un
/// réseau instable (mesh).
///
/// Caractéristiques :
/// - 5 niveaux de priorité (critical > high > normal > low > background)
/// - Retry avec backoff exponentiel + jitter (100ms → 30s max)
/// - Dedup par message ID
/// - Métriques live : PDR, latence moyenne, queue depth
/// - Timeout par message (configurable)
/// - Callback de livraison/échec
class PremiumMessageQueue {
  PremiumMessageQueue({
    this.maxRetries = 5,
    this.defaultTimeout = const Duration(seconds: 30),
    this.onSend,
    this.onDelivered,
    this.onFailed,
    this.getCongestionWindow,
    this.debugLog,
  });

  final int maxRetries;
  final Duration defaultTimeout;
  final Future<bool> Function(SendTask task)? onSend;
  final void Function(String messageId)? onDelivered;
  final void Function(String messageId, String reason)? onFailed;

  /// Renvoie la fenêtre de congestion AIMD courante pour un peer donné.
  /// Si null, pas de contrôle de congestion (comportement précédent).
  final int Function(String peerId)? getCongestionWindow;

  /// Journal de diagnostic optionnel — la classe reste indépendante de
  /// Flutter (pas d'import `foundation.dart`), l'appelant branche donc
  /// `debugPrint` ou son propre système de log s'il en a besoin.
  final void Function(String message)? debugLog;

  // === QUEUE ===
  final SplayTreeSet<_QueueEntry> _pending = SplayTreeSet<_QueueEntry>();
  final Map<String, _QueueEntry> _pendingMap = {};
  final Set<String> _processing = {};
  final Set<String> _retryPending = {};
  final Set<String> _finished = {};
  final Map<String, _DeliveryRecord> _deliveryRecords = {};

  // === CONGESTION ===
  /// Nombre de messages en vol (non acquittés) par pair — pour le contrôle
  /// de congestion AIMD.
  final Map<String, int> _inflightPerPeer = {};

  // === TIMERS ===
  final Map<String, Timer> _retryTimers = {};
  Timer? _cleanupTimer;

  // === METRICS ===
  int totalSent = 0;
  int _totalDelivered = 0;
  int _totalFailed = 0;
  final List<double> _latencies = [];

  bool _running = false;

  // === LIFECYCLE ===

  void start() {
    _running = true;
    _cleanupTimer = Timer.periodic(const Duration(minutes: 1), (_) => _cleanup());
  }

  void stop() {
    _running = false;
    _cleanupTimer?.cancel();
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _pending.clear();
    _pendingMap.clear();
    _processing.clear();
    _retryPending.clear();
    _finished.clear();
    _deliveryRecords.clear();
  }

  // === ENQUEUE ===

  void enqueue({
    required String messageId,
    required String targetId,
    required List<int> payload,
    MessagePriority priority = MessagePriority.normal,
    Duration? timeout,
    Object? context,
  }) {
    if (!_running) return;
    if (_pendingMap.containsKey(messageId)) return; // dedup

    final entry = _QueueEntry(
      messageId: messageId,
      targetId: targetId,
      payload: payload,
      priority: priority,
      timeout: timeout ?? defaultTimeout,
      enqueuedAt: DateTime.now(),
      context: context,
    );

    _pending.add(entry);
    _pendingMap[messageId] = entry;
    _deliveryRecords[messageId] = _DeliveryRecord(messageId: messageId);

    // Essayer d'envoyer immédiatement si pas de congestion.
    _trySendNext();
  }

  // === PROCESSING ===

  void _trySendNext() {
    if (!_running) return;
    if (_processing.length >= 5) return; // max 5 en parallèle

    for (final entry in _pending) {
      if (!_processing.contains(entry.messageId) &&
          !_retryPending.contains(entry.messageId)) {

        // Contrôle de congestion AIMD : les messages normaux/low/background
        // respectent la fenêtre ; les critical/high passent toujours.
        final window = getCongestionWindow?.call(entry.targetId);
        if (window != null && entry.priority.value >= MessagePriority.normal.value) {
          final inFlight = _inflightPerPeer[entry.targetId] ?? 0;
          if (inFlight >= window) {
            debugLog?.call('[Queue] congestion: ${entry.targetId} '
                'inflight=$inFlight window=$window — '
                '${entry.priority.name} "${entry.messageId}" en attente');
            continue; // sauter ce message, essayer le suivant
          }
        }

        _processEntry(entry);
        break;
      }
    }
  }

  Future<void> _processEntry(_QueueEntry entry) async {
    _processing.add(entry.messageId);
    _retryPending.remove(entry.messageId);
    entry.lastAttemptAt = DateTime.now();
    entry.attempt++;
    totalSent++;
    _inflightPerPeer[entry.targetId] = (_inflightPerPeer[entry.targetId] ?? 0) + 1;

    final record = _deliveryRecords[entry.messageId];
    if (record != null) {
      record.attempts++;
    }

    try {
      // ⚠️ CORRECTIF — le timeout déclaré (`entry.timeout`, hérité de
      // `defaultTimeout`) était stocké mais jamais lu nulle part dans
      // cette classe : un `onSend` qui ne se termine jamais (écriture
      // GATT Bluetooth qui ne rend jamais la main, cas documenté dans
      // `ble_mesh_transport.dart`) laissait `entry.messageId` dans
      // `_processing` indéfiniment — un des cinq emplacements
      // concurrents disponibles restait bloqué pour toujours, avec
      // aucune retentative, aucun échec remonté. Seul un `.timeout()`
      // posé PAR L'APPELANT (`MeshRepository._enqueueReliable`)
      // rattrapait le cas — mais seulement pour les appels qui passent
      // par ce chemin précis, et seulement l'issue *logique* : le
      // `Future` sous-jacent, lui, continue de tourner dans le vide.
      // Le timeout est désormais appliqué ICI, dans la file elle-même,
      // pour que la garantie ne dépende plus de la discipline de
      // chaque appelant.
      final success = await (onSend?.call(SendTask(
                messageId: entry.messageId,
                targetId: entry.targetId,
                payload: entry.payload,
                priority: entry.priority,
                context: entry.context,
              )) ??
              Future.value(false))
          .timeout(
        entry.timeout,
        onTimeout: () {
          debugLog?.call(
              '[Queue] envoi de ${entry.messageId} suspendu au-delà de '
              '${entry.timeout.inSeconds}s — abandon de cette tentative');
          return false;
        },
      );

      if (success) {
        _onDelivered(entry);
      } else {
        _onAttemptFailed(entry, 'Send returned false');
      }
    } catch (e) {
      _onAttemptFailed(entry, e.toString());
    }
  }

  void _onDelivered(_QueueEntry entry) {
    if (!_finished.add(entry.messageId)) return;
    _processing.remove(entry.messageId);
    _retryPending.remove(entry.messageId);
    _pending.remove(entry);
    _pendingMap.remove(entry.messageId);
    _retryTimers.remove(entry.messageId)?.cancel();
    _inflightPerPeer[entry.targetId] = max(0, (_inflightPerPeer[entry.targetId] ?? 1) - 1);

    _totalDelivered++;
    final latency = DateTime.now().difference(entry.enqueuedAt).inMilliseconds.toDouble();
    _latencies.add(latency);
    if (_latencies.length > 1000) _latencies.removeAt(0);

    final record = _deliveryRecords[entry.messageId];
    if (record != null) {
      record.deliveredAt = DateTime.now();
      record.latencyMs = latency;
    }

    onDelivered?.call(entry.messageId);
    _trySendNext();
  }

  void _onAttemptFailed(_QueueEntry entry, String reason) {
    _processing.remove(entry.messageId);
    _inflightPerPeer[entry.targetId] = max(0, (_inflightPerPeer[entry.targetId] ?? 1) - 1);
    if (_finished.contains(entry.messageId)) return; // annulé pendant l'envoi

    final record = _deliveryRecords[entry.messageId];
    if (record != null) {
      record.errors.add(reason);
    }

    if (entry.attempt >= maxRetries) {
      _onFinalFailure(entry, reason);
    } else {
      _scheduleRetry(entry);
    }
    _trySendNext();
  }

  void _scheduleRetry(_QueueEntry entry) {
    final delay = entry.retryDelay;
    _retryPending.add(entry.messageId);
    _retryTimers[entry.messageId]?.cancel();
    _retryTimers[entry.messageId] = Timer(delay, () {
      if (_running && _pendingMap.containsKey(entry.messageId)) {
        _processEntry(entry);
      }
    });
  }

  void _onFinalFailure(_QueueEntry entry, String reason) {
    if (!_finished.add(entry.messageId)) return; // déjà terminé
    _pending.remove(entry);
    _pendingMap.remove(entry.messageId);
    _retryPending.remove(entry.messageId);
    _retryTimers.remove(entry.messageId)?.cancel();
    _totalFailed++;
    onFailed?.call(entry.messageId, reason);
    _trySendNext();
  }

  // === ACK ===

  void acknowledge(String messageId) {
    final entry = _pendingMap[messageId];
    if (entry != null) {
      _onDelivered(entry);
    }
  }

  // === CANCEL ===

  void cancel(String messageId) {
    _finished.add(messageId);
    _pendingMap.remove(messageId);
    _pending.removeWhere((e) => e.messageId == messageId);
    _retryPending.remove(messageId);
    _retryTimers.remove(messageId)?.cancel();
    _processing.remove(messageId);
  }

  // === METRICS ===

  QueueMetrics get metrics => QueueMetrics(
    pending: _pending.length,
    processing: _processing.length,
    totalSent: totalSent,
    totalDelivered: _totalDelivered,
    totalFailed: _totalFailed,
    avgLatencyMs: _latencies.isEmpty ? 0 : _latencies.reduce((a, b) => a + b) / _latencies.length,
    pdr: totalSent > 0 ? _totalDelivered / totalSent : 1.0,
  );

  // === CLEANUP ===

  void _cleanup() {
    final cutoff = DateTime.now().subtract(const Duration(hours: 1));
    final stale = _deliveryRecords.entries
        .where((e) => e.value.deliveredAt != null && e.value.deliveredAt!.isBefore(cutoff))
        .map((e) => e.key)
        .toList();
    for (final id in stale) {
      _deliveryRecords.remove(id);
    }
  }

  int get pendingCount => _pending.length;
  bool isPending(String messageId) => _pendingMap.containsKey(messageId);
}

// === MODELS ===

/// Tâche d'envoi passée à [PremiumMessageQueue.onSend] — contient tout le
/// contexte nécessaire pour transmettre réellement le paquet sur le réseau.
class SendTask {
  const SendTask({
    required this.messageId,
    required this.targetId,
    required this.payload,
    required this.priority,
    this.context,
  });

  final String messageId;
  final String targetId;
  final List<int> payload;
  final MessagePriority priority;

  /// Contexte optionnel attaché à l'envoi (ex. groupes d'intérêt pour le
  /// routage ciblé) — transmis tel quel de `enqueue` vers `onSend`.
  final Object? context;
}

class _QueueEntry implements Comparable<_QueueEntry> {
  _QueueEntry({
    required this.messageId,
    required this.targetId,
    required this.payload,
    required this.priority,
    required this.timeout,
    required this.enqueuedAt,
    this.context,
  });

  final String messageId;
  final String targetId;
  final List<int> payload;
  final MessagePriority priority;
  final Duration timeout;
  final DateTime enqueuedAt;
  final Object? context;
  int attempt = 0;
  DateTime? lastAttemptAt;

  Duration get retryDelay {
    final baseMs = min(pow(2, attempt).toInt() * 100, 30000);
    final jitter = Random().nextInt(max(1, baseMs ~/ 4));
    return Duration(milliseconds: baseMs + jitter);
  }

  @override
  int compareTo(_QueueEntry other) {
    // ⚠️ CORRECTIF — collision silencieuse dans `_pending`.
    //
    // `_pending` est un `SplayTreeSet`, dont l'appartenance ET l'ordre
    // reposent UNIQUEMENT sur `compareTo`. Tant que ce comparateur ne
    // portait que sur `(priority, enqueuedAt)`, deux messages DIFFÉRENTS
    // — deux `messageId` distincts — envoyés à la même priorité et
    // horodatés à la même microseconde (chose banale : `enqueue()` est
    // souvent appelé en boucle serrée, ex. l'envoi de 100 messages,
    // Test 5) comparaient égal à zéro. Or pour un `SplayTreeSet`, deux
    // éléments qui comparent égal sont LE MÊME ÉLÉMENT : `_pending.add()`
    // sur le second message ne l'ajoutait tout simplement pas.
    //
    // Le message restait pourtant dans `_pendingMap` (clé = messageId,
    // non affecté par ce bug), donnant l'illusion qu'il était bien en
    // file — `enqueue()` ne renvoie rien et ne lève rien. Mais
    // `_trySendNext()` ne parcourt QUE `_pending` pour choisir le
    // prochain message à envoyer : ce message-là n'y était jamais.
    // Résultat, silencieux et sans exception : un message sur N envoyés
    // en rafale ne partait jamais, ne réessayait jamais, et ne remontait
    // jamais en échec. C'est un des deux mécanismes derrière « messages
    // qui restent bloqués / jamais envoyés ».
    //
    // Le messageId, dernier critère, brise toute égalité : deux entrées
    // ne peuvent plus jamais comparer à zéro sauf à être RÉELLEMENT le
    // même message (déjà exclu en amont par le test `_pendingMap.
    // containsKey` dans `enqueue()`).
    final cmp = priority.value.compareTo(other.priority.value);
    if (cmp != 0) return cmp;
    final cmpTime = enqueuedAt.compareTo(other.enqueuedAt);
    if (cmpTime != 0) return cmpTime;
    return messageId.compareTo(other.messageId);
  }
}

class _DeliveryRecord {
  _DeliveryRecord({required this.messageId});

  final String messageId;
  int attempts = 0;
  DateTime? deliveredAt;
  double? latencyMs;
  final List<String> errors = [];
}

class QueueMetrics {
  const QueueMetrics({
    required this.pending,
    required this.processing,
    required this.totalSent,
    required this.totalDelivered,
    required this.totalFailed,
    required this.avgLatencyMs,
    required this.pdr,
  });

  final int pending;
  final int processing;
  final int totalSent;
  final int totalDelivered;
  final int totalFailed;
  final double avgLatencyMs;
  final double pdr; // Packet Delivery Ratio
}

enum MessagePriority {
  critical(0),
  high(1),
  normal(2),
  low(3),
  background(4);

  const MessagePriority(this.value);
  final int value;
}
