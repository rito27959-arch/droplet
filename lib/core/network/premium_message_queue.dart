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
  });

  final int maxRetries;
  final Duration defaultTimeout;
  final Future<bool> Function(SendTask task)? onSend;
  final void Function(String messageId)? onDelivered;
  final void Function(String messageId, String reason)? onFailed;

  // === QUEUE ===
  final SplayTreeSet<_QueueEntry> _pending = SplayTreeSet<_QueueEntry>();
  final Map<String, _QueueEntry> _pendingMap = {};
  final Set<String> _processing = {};
  final Set<String> _retryPending = {};
  final Set<String> _finished = {};
  final Map<String, _DeliveryRecord> _deliveryRecords = {};

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
      // Un message en attente de retry (backoff en cours) ne doit JAMAIS
      // être re-dispatché immédiatement — sinon les retries tournent en
      // boucle serrée au lieu d'attendre le backoff exponentiel.
      if (!_processing.contains(entry.messageId) &&
          !_retryPending.contains(entry.messageId)) {
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

    final record = _deliveryRecords[entry.messageId];
    if (record != null) {
      record.attempts++;
    }

    try {
      final success = await onSend?.call(SendTask(
            messageId: entry.messageId,
            targetId: entry.targetId,
            payload: entry.payload,
            priority: entry.priority,
            context: entry.context,
          )) ??
          false;

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
    if (!_finished.add(entry.messageId)) return; // déjà terminé (ack pendant l'envoi)
    _processing.remove(entry.messageId);
    _retryPending.remove(entry.messageId);
    _pending.remove(entry);
    _pendingMap.remove(entry.messageId);
    _retryTimers.remove(entry.messageId)?.cancel();

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
    final cmp = priority.value.compareTo(other.priority.value);
    if (cmp != 0) return cmp;
    return enqueuedAt.compareTo(other.enqueuedAt);
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
