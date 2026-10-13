// ============================================================================
// LA MÉMOIRE DURABLE DE L'ANNUAIRE — Postgres.
// ----------------------------------------------------------------------------
// Deux tables, partagées avec la boîte aux lettres :
//
//   comptes  — identifiant ↔ clé publique, et « a déjà signé » (verrou).
//              C'est le cœur de la sécurité : le premier qui enregistre un
//              identifiant y attache sa clé ; ensuite, plus personne ne peut
//              la remplacer sans la signature du détenteur.
//   annuaire — pseudo, adresse, jeton push, dernière activité : ce que
//              l'annuaire servait avant depuis la mémoire, et qu'il perdait
//              à chaque redémarrage.
//
// L'annuaire garde toujours une copie en mémoire (pour chercher vite) :
// Postgres est la source de vérité, rechargée au démarrage.
// ============================================================================

import 'dart:io';

import 'package:postgres/postgres.dart';

class Persistance {
  Persistance._(this._db);

  final Pool _db;

  static Endpoint _endpoint(String url) {
    final u = Uri.parse(url);
    final infos = u.userInfo.split(':');
    return Endpoint(
      host: u.host,
      port: u.hasPort ? u.port : 5432,
      database: u.path.replaceFirst('/', ''),
      username: Uri.decodeComponent(infos.first),
      password: infos.length > 1 ? Uri.decodeComponent(infos.sublist(1).join(':')) : null,
    );
  }

  /// Null sans DATABASE_URL (en local) : l'annuaire tourne alors en mémoire.
  static Future<Persistance?> ouvrir() async {
    final url = Platform.environment['DATABASE_URL'];
    if (url == null || url.isEmpty) return null;
    final db = Pool.withEndpoints(
      [_endpoint(url)],
      settings: PoolSettings(maxConnectionCount: 10, sslMode: SslMode.disable),
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS comptes (
        peer_id TEXT PRIMARY KEY,
        cle TEXT NOT NULL,
        signe BOOLEAN NOT NULL DEFAULT false,
        cree TIMESTAMPTZ NOT NULL DEFAULT now(),
        vu TIMESTAMPTZ NOT NULL DEFAULT now()
      )''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS annuaire (
        peer_id TEXT PRIMARY KEY,
        pseudo TEXT NOT NULL,
        onion TEXT NOT NULL,
        cle TEXT NOT NULL,
        fcm TEXT,
        vu TIMESTAMPTZ NOT NULL DEFAULT now()
      )''');
    return Persistance._(db);
  }

  Future<List<ResultRow>> annuaire() =>
      _db.execute('SELECT peer_id, pseudo, onion, cle, fcm, vu FROM annuaire');

  Future<Map<String, ({String cle, bool signe})>> comptes() async {
    final r = await _db.execute('SELECT peer_id, cle, signe FROM comptes');
    return {for (final l in r) l[0] as String: (cle: l[1] as String, signe: l[2] as bool)};
  }

  Future<void> inscrire({
    required String peerId,
    required String pseudo,
    required String onion,
    required String cle,
    String? fcm,
  }) async {
    await _db.execute(
      Sql.named('''
        INSERT INTO annuaire (peer_id, pseudo, onion, cle, fcm, vu)
        VALUES (@id, @pseudo, @onion, @cle, @fcm, now())
        ON CONFLICT (peer_id) DO UPDATE SET
          pseudo = EXCLUDED.pseudo, onion = EXCLUDED.onion, cle = EXCLUDED.cle,
          fcm = COALESCE(EXCLUDED.fcm, annuaire.fcm), vu = now()'''),
      parameters: {'id': peerId, 'pseudo': pseudo, 'onion': onion, 'cle': cle, 'fcm': fcm},
    );
  }

  Future<void> lierCle(String peerId, String cle) => _db.execute(
        Sql.named('''
          INSERT INTO comptes (peer_id, cle) VALUES (@id, @cle)
          ON CONFLICT (peer_id) DO UPDATE SET cle = EXCLUDED.cle, vu = now()'''),
        parameters: {'id': peerId, 'cle': cle},
      );

  Future<void> marquerSigne(String peerId) => _db.execute(
        Sql.named('UPDATE comptes SET signe = true, vu = now() WHERE peer_id = @id'),
        parameters: {'id': peerId},
      );

  Future<void> desinscrire(String peerId) =>
      _db.execute(Sql.named('DELETE FROM annuaire WHERE peer_id = @id'), parameters: {'id': peerId});

  Future<void> vu(Iterable<String> ids) async {
    final liste = ids.toList();
    if (liste.isEmpty) return;
    await _db.execute(
      Sql.named('UPDATE annuaire SET vu = now() WHERE peer_id = ANY(@ids)'),
      parameters: {'ids': TypedValue(Type.textArray, liste)},
    );
  }

  Future<int> menage(Duration duree) async {
    final r = await _db.execute(
      Sql.named('DELETE FROM annuaire WHERE vu < @limite'),
      parameters: {'limite': DateTime.now().toUtc().subtract(duree)},
    );
    return r.affectedRows;
  }
}
