// ============================================================================
// SAUVEGARDES KUNFOX — la progression d'un élève, chiffrée, pour la
// retrouver sur un nouveau téléphone (« Se connecter avec Droplet »).
// ----------------------------------------------------------------------------
// Le serveur ne garde qu'un paquet opaque : Kunfox le chiffre sur le
// téléphone avec une clé dérivée du secret que Droplet lui a confié. Le
// serveur ne peut ni le lire ni savoir à quel compte Droplet il appartient.
//
// L'identifiant de la sauvegarde EST la preuve : 32 octets dérivés du même
// secret (base64url, 43 caractères). Qui ne connaît pas le secret ne peut
// ni deviner l'identifiant, ni lire, ni écraser la sauvegarde.
//
// Une version (nombre croissant, fixée par le téléphone) évite qu'un vieux
// téléphone écrase une progression plus récente.
// ============================================================================

import 'dart:convert';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

final _formeId = RegExp(r'^[A-Za-z0-9_-]{43}$');
const _tailleMax = 256 * 1024;

class SauvegardesKunfox {
  SauvegardesKunfox(this._db);
  final Pool _db;

  static Future<void> preparer(Pool db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kunfox_sauvegardes (
        id TEXT PRIMARY KEY,
        paquet TEXT NOT NULL,
        version BIGINT NOT NULL,
        maj TIMESTAMPTZ NOT NULL DEFAULT now()
      )''');
  }

  Response _json(Object o, {int statut = 200}) =>
      Response(statut, body: jsonEncode(o), headers: {'content-type': 'application/json'});

  Future<Response> lire(Request r, String id) async {
    if (!_formeId.hasMatch(id)) return _json({'error': 'identifiant invalide'}, statut: 400);
    final res = await _db.execute(
      Sql.named('SELECT paquet, version FROM kunfox_sauvegardes WHERE id = @id'),
      parameters: {'id': id},
    );
    if (res.isEmpty) return _json({'error': 'aucune sauvegarde'}, statut: 404);
    return _json({'paquet': res.first[0], 'version': res.first[1]});
  }

  Future<Response> ecrire(Request r, String id) async {
    if (!_formeId.hasMatch(id)) return _json({'error': 'identifiant invalide'}, statut: 400);
    final octets = await r.read().fold<List<int>>([], (a, b) => a..addAll(b));
    if (octets.length > _tailleMax) return _json({'error': 'trop grand'}, statut: 413);
    final Object? j;
    try {
      j = jsonDecode(utf8.decode(octets));
    } catch (_) {
      return _json({'error': 'corps illisible'}, statut: 400);
    }
    final paquet = j is Map ? j['paquet'] : null;
    final version = j is Map ? j['version'] : null;
    if (paquet is! String || version is! int || version < 0) {
      return _json({'error': 'paquet ou version manquant'}, statut: 400);
    }
    // N'écrit que si la version est plus récente que celle gardée.
    final res = await _db.execute(
      Sql.named('''
        INSERT INTO kunfox_sauvegardes (id, paquet, version) VALUES (@id, @paquet, @version)
        ON CONFLICT (id) DO UPDATE SET paquet = EXCLUDED.paquet, version = EXCLUDED.version, maj = now()
        WHERE kunfox_sauvegardes.version < EXCLUDED.version'''),
      parameters: {'id': id, 'paquet': paquet, 'version': version},
    );
    if (res.affectedRows == 0) return _json({'error': 'version plus ancienne que celle gardée'}, statut: 409);
    return _json({'ok': true});
  }

  /// Le ménage : une sauvegarde intouchée depuis plus de deux ans.
  Future<int> oublierVieilles() async {
    final r = await _db.execute("DELETE FROM kunfox_sauvegardes WHERE maj < now() - interval '730 days'");
    return r.affectedRows;
  }
}
