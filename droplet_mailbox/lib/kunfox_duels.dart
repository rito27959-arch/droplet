// ============================================================================
// DUELS KUNFOX — défier un ami sur la même leçon.
// ----------------------------------------------------------------------------
// Celui qui lance le duel joue d'abord ; son téléphone envoie ici les
// questions exactes qu'il a eues et son parcours (juste/faux et temps de
// chaque réponse). Le serveur rend un code court à partager.
//
// Chaque ami qui ouvre le lien reçoit les mêmes questions et « court »
// contre le fantôme du créateur, puis dépose son propre résultat. Le
// créateur relit le duel pour voir qui l'a battu.
//
// Rien de personnel : un prénom choisi par l'élève, des scores, des
// questions de cours. Un duel est oublié au bout de 30 jours.
// ============================================================================

import 'dart:convert';
import 'dart:math';

import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';

const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'; // sans 0/O ni 1/I/L
final _formeCode = RegExp(r'^[A-HJ-NP-Z2-9]{8}$');
const _tailleMax = 48 * 1024;
const _adversairesMax = 50;

class DuelsKunfox {
  DuelsKunfox(this._db);
  final Pool _db;
  final _hasard = Random.secure();

  static Future<void> preparer(Pool db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS kunfox_duels (
        code TEXT PRIMARY KEY,
        duel TEXT NOT NULL,
        adversaires TEXT NOT NULL DEFAULT '[]',
        cree TIMESTAMPTZ NOT NULL DEFAULT now()
      )''');
  }

  Response _json(Object o, {int statut = 200}) =>
      Response(statut, body: jsonEncode(o), headers: {'content-type': 'application/json'});

  Future<Object?> _lireCorps(Request r) async {
    final octets = await r.read().fold<List<int>>([], (a, b) => a..addAll(b));
    if (octets.length > _tailleMax) throw const FormatException('trop grand');
    return jsonDecode(utf8.decode(octets));
  }

  static String? _nom(Object? n) {
    if (n is! String) return null;
    final t = n.trim();
    if (t.isEmpty || t.length > 24) return null;
    return t;
  }

  /// Le parcours d'un joueur : une case par question, [juste (0/1), ms].
  static Map<String, Object>? _joueur(Object? j, int nbQuestions) {
    if (j is! Map) return null;
    final nom = _nom(j['nom']);
    final traces = j['traces'];
    if (nom == null || traces is! List || traces.length != nbQuestions) return null;
    final propres = <List<int>>[];
    for (final t in traces) {
      if (t is! List || t.length != 2 || t[0] is! int || t[1] is! int) return null;
      final juste = t[0] as int, ms = t[1] as int;
      if ((juste != 0 && juste != 1) || ms < 0 || ms > 600000) return null;
      propres.add([juste, ms]);
    }
    final avatar = j['avatar'];
    return {
      'nom': nom,
      'traces': propres,
      'bonnes': propres.where((t) => t[0] == 1).length,
      'ms': propres.fold<int>(0, (a, t) => a + t[1]),
      if (avatar is int && avatar >= 0 && avatar < 16) 'avatar': avatar,
    };
  }

  /// POST /kunfox/duels — { lecon, titre, matiere, questions:[…], createur:{nom, traces} }
  Future<Response> creer(Request r) async {
    final Object? j;
    try {
      j = await _lireCorps(r);
    } on FormatException catch (e) {
      return _json({'error': e.message == 'trop grand' ? 'trop grand' : 'corps illisible'},
          statut: e.message == 'trop grand' ? 413 : 400);
    }
    if (j is! Map) return _json({'error': 'corps illisible'}, statut: 400);
    final lecon = j['lecon'], titre = j['titre'], matiere = j['matiere'], questions = j['questions'];
    if (lecon is! String || lecon.length > 80 || titre is! String || titre.length > 120) {
      return _json({'error': 'leçon manquante'}, statut: 400);
    }
    if (questions is! List || questions.isEmpty || questions.length > 12) {
      return _json({'error': 'questions manquantes'}, statut: 400);
    }
    for (final q in questions) {
      if (q is! Map ||
          q['question'] is! String ||
          q['options'] is! List ||
          (q['options'] as List).length < 2 ||
          (q['options'] as List).length > 6 ||
          q['bonne'] is! int) {
        return _json({'error': 'question mal formée'}, statut: 400);
      }
    }
    final createur = _joueur(j['createur'], questions.length);
    if (createur == null) return _json({'error': 'joueur mal formé'}, statut: 400);

    final duel = {
      'lecon': lecon,
      'titre': titre,
      if (matiere is String && matiere.length <= 60) 'matiere': matiere,
      'questions': questions,
      'createur': createur,
    };
    for (var essai = 0; essai < 5; essai++) {
      final code = List.generate(8, (_) => _alphabet[_hasard.nextInt(_alphabet.length)]).join();
      final res = await _db.execute(
        Sql.named('INSERT INTO kunfox_duels (code, duel) VALUES (@code, @duel) ON CONFLICT (code) DO NOTHING'),
        parameters: {'code': code, 'duel': jsonEncode(duel)},
      );
      if (res.affectedRows == 1) return _json({'code': code}, statut: 201);
    }
    return _json({'error': 'réessaie'}, statut: 503);
  }

  /// GET /kunfox/duels/<code>
  Future<Response> lire(Request r, String code) async {
    code = code.toUpperCase();
    if (!_formeCode.hasMatch(code)) return _json({'error': 'code invalide'}, statut: 400);
    final res = await _db.execute(
      Sql.named("SELECT duel, adversaires FROM kunfox_duels WHERE code = @c AND cree > now() - interval '30 days'"),
      parameters: {'c': code},
    );
    if (res.isEmpty) return _json({'error': 'duel introuvable'}, statut: 404);
    final duel = jsonDecode(res.first[0] as String) as Map<String, dynamic>;
    return _json({'code': code, ...duel, 'adversaires': jsonDecode(res.first[1] as String)});
  }

  /// POST /kunfox/duels/<code>/resultat — { nom, traces, avatar? }
  Future<Response> repondre(Request r, String code) async {
    code = code.toUpperCase();
    if (!_formeCode.hasMatch(code)) return _json({'error': 'code invalide'}, statut: 400);
    final Object? j;
    try {
      j = await _lireCorps(r);
    } on FormatException {
      return _json({'error': 'corps illisible'}, statut: 400);
    }
    return _db.runTx((tx) async {
      final res = await tx.execute(
        Sql.named(
            "SELECT duel, adversaires FROM kunfox_duels WHERE code = @c AND cree > now() - interval '30 days' FOR UPDATE"),
        parameters: {'c': code},
      );
      if (res.isEmpty) return _json({'error': 'duel introuvable'}, statut: 404);
      final duel = jsonDecode(res.first[0] as String) as Map<String, dynamic>;
      final adversaires = (jsonDecode(res.first[1] as String) as List).cast<Map<String, dynamic>>();
      final joueur = _joueur(j, (duel['questions'] as List).length);
      if (joueur == null) return _json({'error': 'joueur mal formé'}, statut: 400);
      if (adversaires.length >= _adversairesMax) return _json({'error': 'duel complet'}, statut: 409);
      adversaires.add({...joueur, 'quand': DateTime.now().toUtc().toIso8601String()});
      await tx.execute(
        Sql.named('UPDATE kunfox_duels SET adversaires = @a WHERE code = @c'),
        parameters: {'a': jsonEncode(adversaires), 'c': code},
      );
      return _json({'ok': true, 'rang': adversaires.length});
    });
  }

  Future<int> oublierVieux() async {
    final r = await _db.execute("DELETE FROM kunfox_duels WHERE cree < now() - interval '30 days'");
    return r.affectedRows;
  }
}
