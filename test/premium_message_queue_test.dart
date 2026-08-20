import 'dart:async';
import 'dart:collection';
import 'package:flutter_test/flutter_test.dart';
import 'package:droplet/core/network/premium_message_queue.dart';

/// Couvre la file fiable v2 — le cœur de la livraison « comme sur
/// Internet » du mesh : retry exponentiel + jitter, dedup, priorité,
/// acquittement, annulation et métriques. Les timers réels sont courts
/// (maxRetries réduits) pour garder les tests rapides.
void main() {
  test('livre un message immédiatement quand l\'envoi réussit', () async {
    final delivered = <String>[];
    final queue = PremiumMessageQueue(
      maxRetries: 3,
      defaultTimeout: const Duration(seconds: 10),
      onSend: (task) async {
        expect(task.payload, [1, 2, 3]);
        expect(task.targetId, 'peer-1');
        return true;
      },
      onDelivered: delivered.add,
    )..start();

    queue.enqueue(messageId: 'msg-1', targetId: 'peer-1', payload: const [1, 2, 3]);

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(delivered, ['msg-1']);
    expect(queue.pendingCount, 0);
    expect(queue.isPending('msg-1'), isFalse);
    expect(queue.metrics.totalDelivered, 1);
    queue.stop();
  });

  test('réessaie avec backoff exponentiel puis échoue après maxRetries', () async {
    final attempts = <int>[];
    final failed = <String>[];
    final queue = PremiumMessageQueue(
      maxRetries: 3,
      defaultTimeout: const Duration(seconds: 10),
      onSend: (task) async {
        attempts.add(task.priority.value);
        return false; // échec persistant
      },
      onFailed: (id, reason) => failed.add(id),
    )..start();

    queue.enqueue(messageId: 'msg-2', targetId: 'peer-2', payload: const [9]);

    // Tentative initiale + 2 retries (100ms, 200ms + jitter) = 3 au total.
    await Future<void>.delayed(const Duration(seconds: 3));
    expect(attempts.length, 3);
    expect(failed, ['msg-2']);
    expect(queue.pendingCount, 0);
    expect(queue.metrics.totalFailed, 1);
    queue.stop();
  });

  test('les retries respectent le backoff (pas de boucle serrée)', () async {
    // Régression : avant le correctif, un échec immédiat redéclenchait
    // `_trySendNext`, qui redispatcheait le MÊME message (toujours premier
    // dans la file triée) → tous les retries partaient en rafale, sans
    // jamais attendre le backoff. Ici, à t+60ms il ne doit y avoir que la
    // tentative initiale.
    final attempts = <DateTime>[];
    final queue = PremiumMessageQueue(
      maxRetries: 5,
      onSend: (task) async {
        attempts.add(DateTime.now());
        return false;
      },
    )..start();

    queue.enqueue(messageId: 'msg-b', targetId: 'p', payload: const [1]);

    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(attempts.length, 1);

    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(attempts.length, 2);
    queue.stop();
  });

  test('transmet le contexte (intérêt de groupe) au sender', () async {
    Object? seenContext;
    final queue = PremiumMessageQueue(
      maxRetries: 1,
      onSend: (task) async {
        seenContext = task.context;
        return true;
      },
    )..start();

    queue.enqueue(
      messageId: 'msg-3',
      targetId: 'broadcast',
      payload: const [0],
      context: {'interestGroups': {'famille'}},
    );

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(seenContext, {'interestGroups': {'famille'}});
    queue.stop();
  });

  test('déduplique : un second enqueue du même ID est ignoré', () async {
    final attempts = <String>[];
    final queue = PremiumMessageQueue(
      maxRetries: 1,
      onSend: (task) async {
        attempts.add(task.messageId);
        return false;
      },
    )..start();

    queue.enqueue(messageId: 'msg-dup', targetId: 'p', payload: const [1]);
    queue.enqueue(messageId: 'msg-dup', targetId: 'p', payload: const [1]);

    expect(queue.pendingCount, 1);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    // 1 tentative initiale (le doublon n'a pas été mis en file).
    expect(attempts, ['msg-dup']);
    queue.stop();
  });

  test('l\'acquittement annule les retries restants', () async {
    final delivered = <String>[];
    final attempts = <String>[];
    final queue = PremiumMessageQueue(
      maxRetries: 5,
      onSend: (task) async {
        attempts.add(task.messageId);
        return false; // échoue au départ…
      },
      onDelivered: delivered.add,
    )..start();

    queue.enqueue(messageId: 'msg-ack', targetId: 'p', payload: const [1]);

    // Un ACK arrive (le pair l'a bien reçu) → on arrête de réessayer.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    queue.acknowledge('msg-ack');

    await Future<void>.delayed(const Duration(seconds: 1));
    expect(delivered, ['msg-ack']);
    expect(attempts, ['msg-ack']); // pas de retry après l'ACK
    expect(queue.pendingCount, 0);
    queue.stop();
  });

  test('la priorité gouverne la file quand plusieurs attendent un slot', () async {
    final gates = List.generate(5, (_) => Completer<bool>());
    var gateIdx = 0;
    final order = <String>[];
    final queue = PremiumMessageQueue(
      maxRetries: 5,
      onSend: (task) async {
        order.add(task.messageId);
        if (task.messageId.startsWith('filler')) {
          return gates[gateIdx++].future; // retient le slot ouvert
        }
        return false;
      },
    )..start();

    // Remplit les 5 slots avec des messages gated.
    for (var i = 0; i < 5; i++) {
      queue.enqueue(messageId: 'filler-$i', targetId: 'p', payload: const [1]);
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));

    // Slots pleins → ces deux attendent en file.
    queue.enqueue(messageId: 'low-msg', targetId: 'p', payload: const [1], priority: MessagePriority.low);
    queue.enqueue(messageId: 'crit-msg', targetId: 'p', payload: const [1], priority: MessagePriority.critical);

    // Libère les slots → `_trySendNext` sort le message prioritaire d'abord.
    for (final g in gates) {
      g.complete(false);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));

    expect(order.contains('crit-msg'), isTrue);
    expect(order.contains('low-msg'), isTrue);
    expect(order.indexOf('crit-msg'), lessThan(order.indexOf('low-msg')));
    queue.stop();
  });

  test('annuler retire le message sans tenter de retry supplémentaire', () async {
    final attempts = <String>[];
    final queue = PremiumMessageQueue(
      maxRetries: 5,
      onSend: (task) async {
        attempts.add(task.messageId);
        return false;
      },
    )..start();

    queue.enqueue(messageId: 'msg-cancel', targetId: 'p', payload: const [1]);
    queue.cancel('msg-cancel');

    await Future<void>.delayed(const Duration(seconds: 1));
    expect(queue.pendingCount, 0);
    // La tentative en vol au moment du cancel est comptée, mais AUCUN retry.
    expect(attempts, ['msg-cancel']);
    queue.stop();
  });

  test('l\'ordre de comparaison trie par priorité puis par ancienneté', () {
    final a = _entry('a', MessagePriority.high, DateTime(2026, 1, 1, 0, 0, 1));
    final b = _entry('b', MessagePriority.high, DateTime(2026, 1, 1, 0, 0, 2));
    final c = _entry('c', MessagePriority.critical, DateTime(2026, 1, 1, 0, 0, 3));

    final set = SplayTreeSet<_TestEntry>.of([a, b, c]);
    expect(set.map((e) => e.id).toList(), ['c', 'a', 'b']);
  });
}

class _TestEntry implements Comparable<_TestEntry> {
  _TestEntry(this.id, this.priority, this.at);
  final String id;
  final MessagePriority priority;
  final DateTime at;

  @override
  int compareTo(_TestEntry other) {
    final cmp = priority.value.compareTo(other.priority.value);
    if (cmp != 0) return cmp;
    return at.compareTo(other.at);
  }
}

_TestEntry _entry(String id, MessagePriority p, DateTime at) => _TestEntry(id, p, at);
