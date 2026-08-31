// ============================================================================
// DROPLET DIRECTORY SERVER
// ============================================================================
// Serveur annuaire .onion pour Droplet.
//
// Les appareils s'enregistrent avec leur pseudo + adresse .onion.
// Les autres appareils peuvent chercher des contacts par nom.
//
// Endpoints :
//   POST /register   — Enregistrer/mettre à jour un appareil
//   DELETE /register — Se désinscrire
//   GET /search?q=   — Chercher un contact par pseudo
//   GET /health      — Health check
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:args/args.dart';

// ── Modèle de données ──────────────────────────────────────────────

class DirectoryEntry {
  DirectoryEntry({
    required this.peerId,
    required this.pseudo,
    required this.onionAddress,
    required this.publicKey,
    this.lastSeen,
  });

  final String peerId;
  final String pseudo;
  final String onionAddress;
  final String publicKey;
  DateTime? lastSeen;

  Map<String, dynamic> toJson() => {
        'peerId': peerId,
        'pseudo': pseudo,
        'onion': onionAddress,
        'publicKey': publicKey,
        'lastSeen': lastSeen?.toIso8601String(),
      };

  factory DirectoryEntry.fromJson(Map<String, dynamic> json) {
    return DirectoryEntry(
      peerId: json['peerId'] as String,
      pseudo: json['pseudo'] as String,
      onionAddress: json['onion'] as String,
      publicKey: json['publicKey'] as String,
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'] as String)
          : null,
    );
  }
}

// ── Base de données en mémoire ─────────────────────────────────────

class DirectoryDb {
  /// Entries par peerId.
  final Map<String, DirectoryEntry> _entries = {};

  /// TTL d'une entrée : 7 jours.
  static const _ttl = Duration(days: 7);

  void register(DirectoryEntry entry) {
    entry.lastSeen = DateTime.now();
    _entries[entry.peerId] = entry;
  }

  bool unregister(String peerId) {
    return _entries.remove(peerId) != null;
  }

  List<DirectoryEntry> search(String query) {
    final lower = query.toLowerCase();
    return _entries.values
        .where((e) => e.pseudo.toLowerCase().contains(lower))
        .toList();
  }

  /// Nettoie les entrées expirées.
  int sweep() {
    final now = DateTime.now();
    final before = _entries.length;
    _entries.removeWhere((_, e) =>
        e.lastSeen != null && now.difference(e.lastSeen!) > _ttl);
    return before - _entries.length;
  }

  int get count => _entries.length;
}

// ── Serveur ────────────────────────────────────────────────────────

final _db = DirectoryDb();
final _router = Router()
  ..post('/register', _handleRegister)
  ..delete('/register', _handleUnregister)
  ..get('/search', _handleSearch)
  ..get('/health', _handleHealth);

Future<Response> _handleRegister(Request request) async {
  try {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final peerId = json['peerId'] as String?;
    final pseudo = json['pseudo'] as String?;
    final onion = json['onion'] as String?;
    final publicKey = json['publicKey'] as String?;

    if (peerId == null || pseudo == null || onion == null || publicKey == null) {
      return Response(400,
          body: jsonEncode({'error': 'Champs manquants: peerId, pseudo, onion, publicKey'}));
    }

    if (!onion.endsWith('.onion')) {
      return Response(400, body: jsonEncode({'error': 'Adresse onion invalide'}));
    }

    _db.register(DirectoryEntry(
      peerId: peerId,
      pseudo: pseudo,
      onionAddress: onion,
      publicKey: publicKey,
    ));

    print('[Directory] Enregistré: $pseudo (${peerId.substring(0, 8)}…) — total: ${_db.count}');

    return Response.ok(jsonEncode({'ok': true, 'count': _db.count}),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response(500, body: jsonEncode({'error': e.toString()}));
  }
}

Future<Response> _handleUnregister(Request request) async {
  try {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final peerId = json['peerId'] as String?;

    if (peerId == null) {
      return Response(400, body: jsonEncode({'error': 'peerId manquant'}));
    }

    final removed = _db.unregister(peerId);
    return Response.ok(jsonEncode({'ok': true, 'removed': removed}),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response(500, body: jsonEncode({'error': e.toString()}));
  }
}

Future<Response> _handleSearch(Request request) async {
  final query = request.url.queryParameters['q'];
  if (query == null || query.isEmpty) {
    return Response(400, body: jsonEncode({'error': 'Paramètre q manquant'}));
  }

  final results = _db.search(query);
  return Response.ok(
    jsonEncode({'results': results.map((e) => e.toJson()).toList()}),
    headers: {'content-type': 'application/json'},
  );
}

Response _handleHealth(Request request) {
  return Response.ok(
    jsonEncode({
      'status': 'ok',
      'entries': _db.count,
      'uptime': DateTime.now().toIso8601String(),
    }),
    headers: {'content-type': 'application/json'},
  );
}

// ── Main ───────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', defaultsTo: '8080', help: 'Port d\'écoute')
    ..addOption('host', abbr: 'h', defaultsTo: '127.0.0.1', help: 'Adresse d\'écoute');

  final results = parser.parse(args);
  final port = int.parse(results['port'] as String);
  final host = results['host'] as String;

  // Nettoyage périodique des entrées expirées (toutes les heures).
  Timer.periodic(const Duration(hours: 1), (_) {
    final cleaned = _db.sweep();
    if (cleaned > 0) print('[Directory] Nettoyé $cleaned entrées expirées');
  });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addHandler(_router.call);

  final server = await io.serve(handler, host, port);
  print('[Directory] Serveur annuaire démarré sur http://${server.address.host}:${server.port}');
  print('[Directory] Endpoints:');
  print('  POST /register   — Enregistrer un appareil');
  print('  DELETE /register — Se désinscrire');
  print('  GET /search?q=   — Chercher un contact');
  print('  GET /health      — Health check');
}
