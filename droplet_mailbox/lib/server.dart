// ============================================================================
// DROPLET MAILBOX SERVER
// ============================================================================
// Serveur mailbox .onion pour Droplet.
//
// Stocke les messages chiffrés pour les contacts hors-ligne.
// TTL : 7 jours, puis nettoyage automatique.
//
// Endpoints :
//   POST /messages          — Déposer un message (pour un destinataire)
//   GET /messages/:peerId   — Récupérer les messages d'un peer
//   DELETE /messages/:id    — Supprimer un message (après récupération)
//   GET /health             — Health check
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:args/args.dart';

// ── Modèle de données ──────────────────────────────────────────────

class MailboxMessage {
  MailboxMessage({
    required this.id,
    required this.fromPeerId,
    required this.toPeerId,
    required this.encryptedPayload,
    required this.timestamp,
  });

  final String id;
  final String fromPeerId;
  final String toPeerId;
  final String encryptedPayload;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': fromPeerId,
        'to': toPeerId,
        'payload': encryptedPayload,
        'timestamp': timestamp.toIso8601String(),
      };

  factory MailboxMessage.fromJson(Map<String, dynamic> json) {
    return MailboxMessage(
      id: json['id'] as String,
      fromPeerId: json['from'] as String,
      toPeerId: json['to'] as String,
      encryptedPayload: json['payload'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}

// ── Base de données en mémoire ─────────────────────────────────────

class MailboxDb {
  /// Messages par destinataire : toPeerId → [MailboxMessage].
  final Map<String, List<MailboxMessage>> _messages = {};

  /// TTL d'un message : 7 jours.
  static const _ttl = Duration(days: 7);

  String _nextId() {
    return DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  }

  /// Dépose un message dans la boîte aux lettres.
  MailboxMessage store({
    required String fromPeerId,
    required String toPeerId,
    required String encryptedPayload,
  }) {
    final msg = MailboxMessage(
      id: _nextId(),
      fromPeerId: fromPeerId,
      toPeerId: toPeerId,
      encryptedPayload: encryptedPayload,
      timestamp: DateTime.now(),
    );

    _messages.putIfAbsent(toPeerId, () => []).add(msg);
    return msg;
  }

  /// Récupère tous les messages d'un destinataire.
  List<MailboxMessage> fetchAll(String peerId) {
    return _messages[peerId] ?? [];
  }

  /// Supprime un message par son ID.
  bool delete(String peerId, String messageId) {
    final msgs = _messages[peerId];
    if (msgs == null) return false;
    final before = msgs.length;
    msgs.removeWhere((m) => m.id == messageId);
    if (msgs.isEmpty) _messages.remove(peerId);
    return msgs.length < before;
  }

  /// Supprime tous les messages d'un peer (après récupération).
  int deleteAll(String peerId) {
    final msgs = _messages.remove(peerId);
    return msgs?.length ?? 0;
  }

  /// Nettoie les messages expirés.
  int sweep() {
    final now = DateTime.now();
    int cleaned = 0;
    _messages.removeWhere((peerId, msgs) {
      final before = msgs.length;
      msgs.removeWhere((m) => now.difference(m.timestamp) > _ttl);
      cleaned += before - msgs.length;
      return msgs.isEmpty;
    });
    return cleaned;
  }

  int get totalMessages =>
      _messages.values.fold(0, (sum, msgs) => sum + msgs.length);
  int get totalRecipients => _messages.length;
}

// ── Serveur ────────────────────────────────────────────────────────

final _db = MailboxDb();
final _router = Router()
  ..post('/messages', _handleStore)
  ..get('/messages/<peerId>', _handleFetch)
  ..delete('/messages/<peerId>/<messageId>', _handleDelete)
  ..delete('/messages/<peerId>', _handleDeleteAll)
  ..get('/health', _handleHealth);

Future<Response> _handleStore(Request request) async {
  try {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final from = json['from'] as String?;
    final to = json['to'] as String?;
    final payload = json['payload'] as String?;

    if (from == null || to == null || payload == null) {
      return Response(400,
          body: jsonEncode({'error': 'Champs manquants: from, to, payload'}));
    }

    final msg = _db.store(
      fromPeerId: from,
      toPeerId: to,
      encryptedPayload: payload,
    );

    print('[Mailbox] Message déposé: $from → ${to.substring(0, 8)}… (id: ${msg.id})');

    return Response.ok(
      jsonEncode({'ok': true, 'id': msg.id}),
      headers: {'content-type': 'application/json'},
    );
  } catch (e) {
    return Response(500, body: jsonEncode({'error': e.toString()}));
  }
}

Future<Response> _handleFetch(Request request) async {
  final peerId = request.params['peerId'];
  if (peerId == null) {
    return Response(400, body: jsonEncode({'error': 'peerId manquant'}));
  }

  final messages = _db.fetchAll(peerId);
  return Response.ok(
    jsonEncode({
      'messages': messages.map((m) => m.toJson()).toList(),
      'count': messages.length,
    }),
    headers: {'content-type': 'application/json'},
  );
}

Future<Response> _handleDelete(Request request) async {
  final peerId = request.params['peerId'];
  final messageId = request.params['messageId'];

  if (peerId == null || messageId == null) {
    return Response(400, body: jsonEncode({'error': 'Paramètres manquants'}));
  }

  final removed = _db.delete(peerId, messageId);
  return Response.ok(
    jsonEncode({'ok': true, 'removed': removed}),
    headers: {'content-type': 'application/json'},
  );
}

Future<Response> _handleDeleteAll(Request request) async {
  final peerId = request.params['peerId'];
  if (peerId == null) {
    return Response(400, body: jsonEncode({'error': 'peerId manquant'}));
  }

  final count = _db.deleteAll(peerId);
  return Response.ok(
    jsonEncode({'ok': true, 'removed': count}),
    headers: {'content-type': 'application/json'},
  );
}

Response _handleHealth(Request request) {
  return Response.ok(
    jsonEncode({
      'status': 'ok',
      'totalMessages': _db.totalMessages,
      'totalRecipients': _db.totalRecipients,
      'uptime': DateTime.now().toIso8601String(),
    }),
    headers: {'content-type': 'application/json'},
  );
}

// ── Main ───────────────────────────────────────────────────────────

void main(List<String> args) {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8081', help: 'Port d\'écoute')
    ..addOption('host', abbr: 'h', defaultsTo: '127.0.0.1', help: 'Adresse d\'écoute');

  final results = parser.parse(args);
  final port = int.parse(results['port'] as String);
  final host = results['host'] as String;

  // Nettoyage périodique (toutes les heures).
  _startSweepTimer();

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_router.call);

  final server = io.serve(handler, host, port);
  print('[Mailbox] Serveur mailbox démarré sur http://$host:$port');
  print('[Mailbox] Endpoints:');
  print('  POST /messages          — Déposer un message');
  print('  GET /messages/:peerId   — Récupérer les messages');
  print('  DELETE /messages/:id    — Supprimer un message');
  print('  GET /health             — Health check');
}

void _startSweepTimer() async {
  while (true) {
    await Future.delayed(const Duration(hours: 1));
    final cleaned = _db.sweep();
    if (cleaned > 0) print('[Mailbox] Nettoyé $cleaned messages expirés');
  }
}
