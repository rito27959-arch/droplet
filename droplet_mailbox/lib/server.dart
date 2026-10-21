// ============================================================================
// LA BOÎTE AUX LETTRES DROPLET
// ============================================================================
// Garde les messages chiffrés pour les destinataires hors ligne, jusqu'à ce
// qu'ils les relèvent. Le serveur ne peut lire aucun message : il ne voit
// qu'un expéditeur, un destinataire et un blob chiffré.
//
// Endpoints (les mêmes qu'avant : les apps déjà installées marchent) :
//   POST   /messages                  — déposer {from, to, payload}
//   GET    /messages/<peerId>         — relever ses messages
//          ?attendre=25                 attente longue : la réponse part dès
//                                       qu'un message arrive (25 s au plus)
//   DELETE /messages/<peerId>/<id>    — accuser réception d'un message
//   DELETE /messages/<peerId>         — tout effacer
//   GET    /health                    — état du service et de la base
//
// ── Ce qui a changé ─────────────────────────────────────────────────
//
//   • DURABLE. Les messages vivent dans Postgres, plus en mémoire : un
//     redémarrage ou un redéploiement n'en perd plus aucun.
//   • À PLUSIEURS. Le service ne garde plus rien pour lui : on peut en
//     lancer plusieurs copies derrière Railway. Les attentes longues sont
//     réveillées entre copies par LISTEN/NOTIFY de Postgres.
//   • SÉCURISÉ. Relever ou effacer les messages de quelqu'un exige sa
//     signature dès qu'il a la version qui signe (voir securite.dart) ;
//     déposer au nom de quelqu'un aussi.
//   • LIMITÉ. Par adresse IP, par expéditeur et par destinataire : un
//     client fou ou malveillant ne sature ni le serveur ni la boîte d'un
//     autre. Taille d'un message et d'une boîte bornées.
//   • SUR TOUS LES CŒURS. Dart n'utilise qu'un cœur par isolat : le service
//     lance une copie de lui-même par cœur (variable COPIES, 8 au plus),
//     toutes sur le même port. Mesuré : une copie sature vers 10 000
//     appareils en attente longue ; huit en tiennent bien davantage.
//   • ÉCONOME. L'attente longue remplace l'interrogation toutes les 30 s :
//     une requête qui attend ne coûte presque rien, et le message arrive
//     tout de suite au lieu d'attendre le tour suivant.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';

import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';

import 'securite.dart';

const _tailleMaxMessage = 2 * 1024 * 1024;
const _maxParBoite = 5000;
const _duree = Duration(days: 30);
final _formeId = RegExp(r'^[A-Za-z0-9_-]{4,128}$');

late final Pool _db;
late final Securite _securite;
final _hasard = Random.secure();
final _http = http.Client();
final _annuaire = Platform.environment['DIRECTORY_URL'] ?? 'https://droplet-directory-production.up.railway.app';

/// Le nombre de copies (isolats) du service, une par cœur.
final int _copies = () {
  final demande = int.tryParse(Platform.environment['COPIES'] ?? '');
  return (demande ?? Platform.numberOfProcessors).clamp(1, 8);
}();

/// Chaque copie tient ses propres compteurs : on partage les limites entre
/// elles pour que le total reste celui voulu.
Debit _limite(int capacite, int parMinute) =>
    Debit(capacite: max(2, capacite ~/ _copies), parMinute: max(2, parMinute ~/ _copies));

final _depotsParExpediteur = _limite(60, 120);
final _depotsParDestinataire = _limite(200, 300);

/// Les relèves en attente sur cette copie du service, par destinataire.
final _attentes = <String, List<Completer<void>>>{};

// ── Base ──────────────────────────────────────────────────────────────

Endpoint _endpoint() {
  final u = Uri.parse(Platform.environment['DATABASE_URL']!);
  final infos = u.userInfo.split(':');
  return Endpoint(
    host: u.host,
    port: u.hasPort ? u.port : 5432,
    database: u.path.replaceFirst('/', ''),
    username: Uri.decodeComponent(infos.first),
    password: infos.length > 1 ? Uri.decodeComponent(infos.sublist(1).join(':')) : null,
  );
}

/// Ouvre les connexions de CETTE copie. Postgres accepte 100 connexions :
/// les copies d'un service se partagent CONNEXIONS_BASE (80 par défaut), il
/// en reste pour l'annuaire. Avec plusieurs répliques Railway, baisser ce
/// nombre (ex. 40 pour deux répliques).
Future<void> _ouvrirBase() async {
  final budget = int.tryParse(Platform.environment['CONNEXIONS_BASE'] ?? '') ?? 80;
  final reglages = PoolSettings(maxConnectionCount: max(4, budget ~/ _copies), sslMode: SslMode.disable);
  _db = Pool.withEndpoints([_endpoint()], settings: reglages);
  _securite.premiereFois = registreSignatures(_db);
  // Les dépôts faits sur une AUTRE copie du service réveillent nos attentes.
  final ecoute = await Connection.open(_endpoint(), settings: ConnectionSettings(sslMode: SslMode.disable));
  ecoute.channels['boite'].listen(_reveiller);
}

/// Crée les tables, une seule fois, avant de lancer les copies.
Future<void> _preparerBase() async {
  await preparerRegistreSignatures(_db);
  await _db.execute('''
    CREATE TABLE IF NOT EXISTS messages (
      id TEXT PRIMARY KEY,
      destinataire TEXT NOT NULL,
      expediteur TEXT NOT NULL,
      payload TEXT NOT NULL,
      cree TIMESTAMPTZ NOT NULL DEFAULT now()
    )''');
  await _db.execute('CREATE INDEX IF NOT EXISTS messages_destinataire ON messages (destinataire, cree)');
  await _db.execute('CREATE INDEX IF NOT EXISTS messages_cree ON messages (cree)');
  // La table des comptes est tenue par l'annuaire ; la boîte la lit pour
  // vérifier les signatures. On la crée si l'annuaire ne l'a pas encore fait.
  await _db.execute('''
    CREATE TABLE IF NOT EXISTS comptes (
      peer_id TEXT PRIMARY KEY,
      cle TEXT NOT NULL,
      signe BOOLEAN NOT NULL DEFAULT false,
      cree TIMESTAMPTZ NOT NULL DEFAULT now(),
      vu TIMESTAMPTZ NOT NULL DEFAULT now()
    )''');
}

Future<({String? cle, bool signe})> _compte(String peerId) async {
  final r = await _db.execute(Sql.named('SELECT cle, signe FROM comptes WHERE peer_id = @id'), parameters: {'id': peerId});
  if (r.isEmpty) return (cle: null, signe: false);
  return (cle: r.first[0] as String, signe: r.first[1] as bool);
}

/// Contrôle d'identité commun : rend une réponse d'erreur, ou null si la
/// requête peut passer.
Future<Response?> _controler(Request r, String peerId, List<int> corps) async {
  final compte = await _compte(peerId);
  final verdict = await _securite.verifier(r, peerId, corps, compte.cle);
  switch (verdict) {
    case Verdict.signe:
      if (!compte.signe) {
        await _db.execute(Sql.named('UPDATE comptes SET signe = true WHERE peer_id = @id'), parameters: {'id': peerId});
      }
      return null;
    case Verdict.invalide:
      return json({'error': 'signature invalide', 'raison': Securite.raisons[r]}, statut: 401, enTetes: Securite.entetesRefus(r));
    case Verdict.absent:
      if (compte.signe || _securite.exigerSignature) {
        return json({'error': 'signature requise', 'raison': 'requise'}, statut: 401, enTetes: Securite.entetesRefus(r));
      }
      return null;
  }
}

String _nouvelId() => List.generate(16, (_) => _hasard.nextInt(256).toRadixString(16).padLeft(2, '0')).join();

// ── Attente longue ────────────────────────────────────────────────────

void _reveiller(String destinataire) {
  final liste = _attentes.remove(destinataire);
  if (liste == null) return;
  for (final c in liste) {
    if (!c.isCompleted) c.complete();
  }
}

Future<void> _attendre(String peerId, Duration duree) {
  final c = Completer<void>();
  (_attentes[peerId] ??= []).add(c);
  return c.future.timeout(duree, onTimeout: () {
    _attentes[peerId]?.remove(c);
    if (_attentes[peerId]?.isEmpty ?? false) _attentes.remove(peerId);
  });
}

// ── Routes ────────────────────────────────────────────────────────────

Future<Response> _deposer(Request r) async {
  final octets = await r.read().fold<List<int>>([], (a, b) => a..addAll(b));
  if (octets.length > _tailleMaxMessage) return json({'error': 'message trop grand'}, statut: 413);
  final Map<String, dynamic> j;
  try {
    j = jsonDecode(utf8.decode(octets)) as Map<String, dynamic>;
  } catch (_) {
    return json({'error': 'corps illisible'}, statut: 400);
  }
  final de = j['from'], a = j['to'], payload = j['payload'];
  if (de is! String || a is! String || payload is! String || !_formeId.hasMatch(de) || !_formeId.hasMatch(a)) {
    return json({'error': 'Champs manquants: from, to, payload'}, statut: 400);
  }
  final refus = await _controler(r, de, octets);
  if (refus != null) return refus;
  if (!_depotsParExpediteur.autoriser(de) || !_depotsParDestinataire.autoriser(a)) {
    return json({'error': 'trop de messages, réessayez dans un instant'}, statut: 429, enTetes: {'retry-after': '20'});
  }

  final plein = await _db.execute(Sql.named('SELECT count(*) FROM messages WHERE destinataire = @a'), parameters: {'a': a});
  if ((plein.first[0] as int) >= _maxParBoite) return json({'error': 'boîte du destinataire pleine'}, statut: 507);

  final id = _nouvelId();
  await _db.execute(
    Sql.named('INSERT INTO messages (id, destinataire, expediteur, payload) VALUES (@id, @a, @de, @p)'),
    parameters: {'id': id, 'a': a, 'de': de, 'p': payload},
  );
  // Réveille les attentes, ici et sur les autres copies.
  _reveiller(a);
  unawaited(() async {
    try {
      await _db.execute(Sql.named("SELECT pg_notify('boite', @a)"), parameters: {'a': a});
    } catch (_) {}
  }());
  if (_meriteUnReveil(de, a, payload)) _notifier(de, a);
  return json({'ok': true, 'id': id});
}

/// Les derniers réveils « paquet » par expéditeur→destinataire.
final _derniersReveils = <String, DateTime>{};

/// Ce dépôt mérite-t-il « Nouveau message » sur le téléphone ?
///
/// ⚠️ AVANT, CHAQUE DÉPÔT RÉVEILLAIT. Or la boîte transporte bien plus que
/// des messages : les accusés « distribué / lu », les échanges avec Droplet
/// Web, chaque morceau d'une photo, et les paquets techniques (statuts,
/// synchro de groupe, demandes de photo de profil…). Le destinataire
/// recevait « Nouveau message de papa » toutes les deux minutes, ouvrait
/// l'app, et n'y trouvait rien. On lit l'enveloppe — en clair par
/// construction, le contenu, lui, reste chiffré :
///   • `rc` (accusé), `w`/`l` (Droplet Web) : jamais ;
///   • `f: 2` (morceau de fichier) : seulement le premier ;
///   • `pk` (paquet) : si l'app le marque `nt: 1` (message de groupe) ; une
///     app plus ancienne ne marque rien → au plus un réveil par quart d'heure.
bool _meriteUnReveil(String de, String a, String payload) {
  Object? e;
  try {
    e = jsonDecode(payload);
  } catch (_) {
    return true;
  }
  if (e is! Map) return true;
  if (e['rc'] == 1 || e['w'] == 1 || e['l'] == 1) return false;
  if (e['f'] == 2) return (e['i'] ?? 0) == 0;
  if (e['pk'] == 1) {
    if (e['nt'] == 1) return true;
    if (e['nt'] == 0) return false;
    final cle = '$de>$a';
    final avant = _derniersReveils[cle];
    final maintenant = DateTime.now();
    if (avant != null && maintenant.difference(avant) < const Duration(minutes: 15)) return false;
    _derniersReveils[cle] = maintenant;
    if (_derniersReveils.length > 20000) _derniersReveils.clear();
    return true;
  }
  return true;
}

/// Réveille le destinataire par notification push (via l'annuaire, seul
/// à connaître Firebase). Jamais attendu : un push raté n'empêche pas le
/// dépôt, le message attend sagement dans la boîte.
void _notifier(String de, String a) {
  unawaited(() async {
    try {
      await _http
          .post(
            Uri.parse('$_annuaire/notify'),
            headers: {'content-type': 'application/json', 'x-cle-interne': _securite.cleInterne},
            body: jsonEncode({
              'peerId': a,
              'title': 'Droplet',
              'body': 'Nouveau message',
              'data': {'type': 'mailbox', 'from': de},
            }),
          )
          .timeout(const Duration(seconds: 10));
    } catch (_) {}
  }());
}

Future<Response> _relever(Request r, String peerId) async {
  if (!_formeId.hasMatch(peerId)) return json({'error': 'identifiant invalide'}, statut: 400);
  final refus = await _controler(r, peerId, const []);
  if (refus != null) return refus;

  Future<Result> lire() => _db.execute(
        Sql.named('SELECT id, expediteur, payload, cree FROM messages WHERE destinataire = @p ORDER BY cree LIMIT 500'),
        parameters: {'p': peerId},
      );

  var lignes = await lire();
  final attente = int.tryParse(r.url.queryParameters['attendre'] ?? '') ?? 0;
  if (lignes.isEmpty && attente > 0) {
    await _attendre(peerId, Duration(seconds: attente.clamp(1, 25)));
    lignes = await lire();
  }
  final messages = [
    for (final l in lignes)
      {
        'id': l[0],
        'from': l[1],
        'to': peerId,
        'payload': l[2],
        'timestamp': (l[3] as DateTime).toUtc().toIso8601String(),
      },
  ];
  return json({'messages': messages, 'count': messages.length});
}

Future<Response> _accuser(Request r, String peerId, String id) async {
  if (!_formeId.hasMatch(peerId)) return json({'error': 'identifiant invalide'}, statut: 400);
  final refus = await _controler(r, peerId, const []);
  if (refus != null) return refus;
  final res = await _db.execute(
    Sql.named('DELETE FROM messages WHERE destinataire = @p AND id = @id'),
    parameters: {'p': peerId, 'id': id},
  );
  return json({'ok': true, 'removed': res.affectedRows > 0});
}

Future<Response> _toutEffacer(Request r, String peerId) async {
  if (!_formeId.hasMatch(peerId)) return json({'error': 'identifiant invalide'}, statut: 400);
  final refus = await _controler(r, peerId, const []);
  if (refus != null) return refus;
  final res = await _db.execute(Sql.named('DELETE FROM messages WHERE destinataire = @p'), parameters: {'p': peerId});
  return json({'ok': true, 'removed': res.affectedRows});
}

Future<Response> _sante(Request r) async {
  try {
    final n = await _db.execute('SELECT count(*), count(DISTINCT destinataire) FROM messages');
    return json({
      'status': 'ok',
      'totalMessages': n.first[0],
      'totalRecipients': n.first[1],
      'attentes': _attentes.values.fold<int>(0, (s, l) => s + l.length),
    });
  } catch (e) {
    return json({'status': 'base injoignable'}, statut: 503);
  }
}

final _routes = Router()
  ..post('/messages', _deposer)
  ..get('/messages/<peerId>', _relever)
  ..delete('/messages/<peerId>/<id>', _accuser)
  ..delete('/messages/<peerId>', _toutEffacer)
  ..get('/health', _sante);

Future<void> main() async {
  _securite = await Securite.depuisEnvironnement();
  await _ouvrirBase();
  await _preparerBase();

  Timer.periodic(const Duration(minutes: 5), (_) => oublierVieillesSignatures(_db).catchError((_) {}));

  // Le ménage : les messages jamais relevés au bout de 30 jours.
  Timer.periodic(const Duration(hours: 1), (_) async {
    try {
      final r = await _db.execute(
        Sql.named('DELETE FROM messages WHERE cree < @limite'),
        parameters: {'limite': DateTime.now().toUtc().subtract(_duree)},
      );
      if (r.affectedRows > 0) print('[Boîte] ${r.affectedRows} messages expirés effacés');
    } catch (e) {
      print('[Boîte] Ménage impossible : $e');
    }
  });

  for (var i = 1; i < _copies; i++) {
    await Isolate.spawn(_copie, i, debugName: 'boite-$i');
  }
  await _servir(0);
  print('[Boîte] Prête — $_copies copie(s), stockage Postgres');
}

/// Une copie supplémentaire : ses propres connexions, le même port.
Future<void> _copie(int numero) async {
  _securite = await Securite.depuisEnvironnement(silencieux: true);
  await _ouvrirBase();
  await _servir(numero);
}

Future<void> _servir(int numero) async {
  final handler = const Pipeline()
      .addMiddleware(_cors())
      .addMiddleware(journalSobre(numero == 0 ? 'Boîte' : 'Boîte $numero'))
      .addMiddleware(limiteParIp(_limite(120, 600)))
      .addHandler(_routes.call);

  final port = int.parse(Platform.environment['PORT'] ?? '8081');
  final serveur = await io.serve(handler, InternetAddress.anyIPv4, port, shared: true);
  serveur.autoCompress = true;
  serveur.idleTimeout = const Duration(seconds: 40);
}

/// Droplet Web relève sa file depuis le navigateur (web.dropletmesh.app) :
/// la boîte répond aux requêtes croisées pour les origines de Droplet
/// seulement, en-têtes de signature compris.
Middleware _cors() {
  const origines = {'https://web.dropletmesh.app', 'https://dropletmesh.app', 'http://localhost:8080'};
  Map<String, String> entetes(Request r) {
    final o = r.headers['origin'];
    if (o == null || !(origines.contains(o) || o.endsWith('.vercel.app'))) return const {};
    return {
      'access-control-allow-origin': o,
      'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
      'access-control-allow-headers': 'content-type, x-droplet-id, x-droplet-ts, x-droplet-nonce, x-droplet-sig',
      'access-control-expose-headers': 'x-droplet-raison, x-droplet-heure',
      'access-control-max-age': '86400',
      'vary': 'origin',
    };
  }

  return (Handler suivant) => (Request r) async {
        if (r.method == 'OPTIONS') return Response(204, headers: entetes(r));
        final reponse = await suivant(r);
        return reponse.change(headers: entetes(r));
      };
}
