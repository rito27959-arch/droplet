// ============================================================================
// LES NOTIFICATIONS DE DROPLET WEB, ONGLET FERMÉ (Web Push).
// ----------------------------------------------------------------------------
// Un navigateur lié s'abonne auprès de son service de notifications (celui
// de Chrome, Firefox, Edge ou Safari) et nous confie l'adresse obtenue.
// Quand un dépôt qui mérite « Nouveau message » arrive dans sa boîte, on
// frappe à cette adresse : le navigateur réveille le service worker de
// Droplet Web (`sw.js`), qui affiche la notification.
//
// ⚠️ UNE NOTIFICATION VIDE, PAR CHOIX. On n'envoie AUCUN contenu : ni
// l'expéditeur, ni le texte, ni même un identifiant. Le service de
// notifications du navigateur (Google, Mozilla, Apple, Microsoft) ne voit
// passer qu'un « réveille-toi ». C'est le service worker qui écrit
// « Nouveau message ». Pas de contenu = pas de chiffrement à faire, et rien
// à lire pour un intermédiaire.
//
// L'authentification auprès des services (VAPID, RFC 8292) : un jeton JWT
// signé en ES256 avec une clé P-256 propre à la boîte. Elle est créée au
// premier démarrage et rangée dans Postgres (table `reglages_boite`), pour
// que toutes les copies du service et tous les redéploiements utilisent la
// même — sinon chaque abonnement existant serait invalidé.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pointycastle/export.dart';
import 'package:postgres/postgres.dart';

/// Les services de notifications acceptés. Une adresse d'abonnement
/// ailleurs est refusée : la boîte ne doit jamais devenir un outil pour
/// faire des requêtes vers n'importe quel serveur.
bool adressePushAcceptable(String endpoint) {
  final u = Uri.tryParse(endpoint);
  if (u == null || u.scheme != 'https' || endpoint.length > 1024) return false;
  final h = u.host;
  return h == 'fcm.googleapis.com' ||
      h == 'android.googleapis.com' ||
      h == 'updates.push.services.mozilla.com' ||
      h.endsWith('.push.services.mozilla.com') ||
      h.endsWith('.notify.windows.com') ||
      h == 'web.push.apple.com' ||
      h.endsWith('.push.apple.com');
}

class PushWeb {
  PushWeb(this._db);

  PushWeb._essai(this._db, BigInt d) {
    _d = d;
    _cle = _b64url((_courbe.G * d)!.getEncoded(false));
  }

  final Pool _db;
  BigInt? _d;
  String? _cle;
  Future<bool>? _chargement;

  final _client = http.Client();
  final _derniers = <String, DateTime>{};

  static final _courbe = ECDomainParameters('secp256r1');

  /// Prépare les tables et la clé — appelé UNE fois, par la copie
  /// principale, au démarrage. Une erreur ici n'arrête rien : la boîte
  /// fonctionne sans notifications web, et [_charger] réessaiera.
  ///
  /// ⚠️ LES COPIES NE TOUCHENT PAS À LA BASE AU DÉMARRAGE. Pendant un
  /// redéploiement, l'ancienne et la nouvelle version tiennent chacune leurs
  /// connexions, et Postgres peut refuser les suivantes (« too many
  /// clients ») : une copie qui interrogeait la base dès son démarrage
  /// mourait. La clé est donc lue à la première notification, avec reprise.
  static Future<void> preparer(Pool db) async {
    try {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS reglages_boite (
          cle TEXT PRIMARY KEY,
          valeur TEXT NOT NULL
        )''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS push_web (
          appareil TEXT PRIMARY KEY,
          endpoint TEXT NOT NULL,
          cree TIMESTAMPTZ NOT NULL DEFAULT now()
        )''');
      // Créée une seule fois, même si deux versions démarrent ensemble.
      await db.execute(
        Sql.named("INSERT INTO reglages_boite (cle, valeur) VALUES ('vapid', @v) ON CONFLICT (cle) DO NOTHING"),
        parameters: {'v': _hex(_nouvelleCle())},
      );
    } catch (e) {
      print('[Boîte] notifications web : préparation reportée ($e)');
    }
  }

  /// Lit la clé (une fois réussie, plus jamais).
  Future<bool> _charger() {
    if (_d != null) return Future.value(true);
    return _chargement ??= () async {
      try {
        final r = await _db.execute("SELECT valeur FROM reglages_boite WHERE cle = 'vapid'");
        if (r.isEmpty) return false;
        final d = BigInt.parse(r.first[0] as String, radix: 16);
        _d = d;
        _cle = _b64url((_courbe.G * d)!.getEncoded(false));
        return true;
      } catch (_) {
        return false;
      } finally {
        _chargement = null;
      }
    }();
  }

  /// La clé publique VAPID (65 octets, non compressée), en base64url sans
  /// remplissage : ce que le navigateur passe à `pushManager.subscribe`.
  /// `null` si la base est momentanément injoignable.
  Future<String?> clePublique() async => await _charger() ? _cle : null;

  /// Pour la vérification automatique (`tool/essai_vapid.dart`) : une clé
  /// neuve, sa clé publique et un jeton signé, sans base de données.
  static (String, String) essai() {
    final d = _nouvelleCle();
    final p = PushWeb._essai(_SansBase.instance, d);
    return (p._cle!, p._jeton('https://fcm.googleapis.com/fcm/send/essai'));
  }

  static BigInt _nouvelleCle() {
    final gen = ECKeyGenerator()..init(ParametersWithRandom(ECKeyGeneratorParameters(_courbe), _aleatoire()));
    return (gen.generateKeyPair().privateKey as ECPrivateKey).d!;
  }

  static SecureRandom _aleatoire() {
    final s = Random.secure();
    return FortunaRandom()..seed(KeyParameter(Uint8List.fromList(List.generate(32, (_) => s.nextInt(256)))));
  }

  Future<void> abonner(String appareil, String endpoint) => _db.execute(
        Sql.named('''
          INSERT INTO push_web (appareil, endpoint) VALUES (@a, @e)
          ON CONFLICT (appareil) DO UPDATE SET endpoint = @e, cree = now()'''),
        parameters: {'a': appareil, 'e': endpoint},
      );

  Future<void> desabonner(String appareil) =>
      _db.execute(Sql.named('DELETE FROM push_web WHERE appareil = @a'), parameters: {'a': appareil});

  /// Ce dépôt doit-il réveiller un navigateur ? Seulement un vrai message :
  ///   • une copie déposée par un contact pour ce navigateur (`md`), une
  ///     fois par fichier (premier morceau seulement) ;
  ///   • un lot du téléphone (`w`) que le téléphone a marqué `nt: 1` (il
  ///     contient un message reçu). Les accusés, la frappe, les photos et
  ///     les synchros ne réveillent jamais.
  static bool merite(String payload) {
    Object? e;
    try {
      e = jsonDecode(payload);
    } catch (_) {
      return false;
    }
    if (e is! Map) return false;
    if (e['rc'] == 1) return false;
    if (e['md'] == 1) return e['f'] != 2 || (e['i'] ?? 0) == 0;
    if (e['w'] == 1) return e['nt'] == 1;
    return false;
  }

  /// Réveille [appareil] s'il est abonné. Jamais attendu par le dépôt ; au
  /// plus un réveil toutes les 5 s par appareil (le `Topic` regroupe de
  /// toute façon les réveils en attente chez le service).
  void reveiller(String appareil) {
    final maintenant = DateTime.now();
    final avant = _derniers[appareil];
    if (avant != null && maintenant.difference(avant) < const Duration(seconds: 5)) return;
    _derniers[appareil] = maintenant;
    if (_derniers.length > 20000) _derniers.clear();
    unawaited(() async {
      try {
        if (!await _charger()) return;
        final r = await _db.execute(Sql.named('SELECT endpoint FROM push_web WHERE appareil = @a'), parameters: {'a': appareil});
        if (r.isEmpty) return;
        final endpoint = r.first[0] as String;
        if (!adressePushAcceptable(endpoint)) return;
        final rep = await _client
            .post(
              Uri.parse(endpoint),
              headers: {
                'ttl': '86400',
                'urgency': 'high',
                'topic': 'droplet',
                'authorization': 'vapid t=${_jeton(endpoint)}, k=$_cle',
                'content-length': '0',
              },
            )
            .timeout(const Duration(seconds: 10));
        // 404 / 410 : l'abonnement n'existe plus (navigateur désinstallé,
        // permission retirée). On l'oublie.
        if (rep.statusCode == 404 || rep.statusCode == 410) await desabonner(appareil);
      } catch (_) {}
    }());
  }

  /// Le jeton VAPID : un JWT ES256 pour l'origine du service, valable 12 h.
  String _jeton(String endpoint) {
    final u = Uri.parse(endpoint);
    final entete = _b64url(utf8.encode(jsonEncode({'typ': 'JWT', 'alg': 'ES256'})));
    final corps = _b64url(utf8.encode(jsonEncode({
      'aud': '${u.scheme}://${u.host}',
      'exp': DateTime.now().add(const Duration(hours: 12)).millisecondsSinceEpoch ~/ 1000,
      'sub': 'https://dropletmesh.app',
    })));
    final signe = '$entete.$corps';
    final signataire = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
      ..init(true, PrivateKeyParameter<ECPrivateKey>(ECPrivateKey(_d!, _courbe)));
    final s = signataire.generateSignature(Uint8List.fromList(utf8.encode(signe))) as ECSignature;
    return '$signe.${_b64url([..._octets32(s.r), ..._octets32(s.s)])}';
  }

  static List<int> _octets32(BigInt n) {
    final hex = n.toRadixString(16).padLeft(64, '0');
    return [for (var i = 0; i < 64; i += 2) int.parse(hex.substring(i, i + 2), radix: 16)];
  }

  static String _hex(BigInt n) => n.toRadixString(16).padLeft(64, '0');

  static String _b64url(List<int> o) => base64Url.encode(o).replaceAll('=', '');
}

/// Une base absente, pour [PushWeb.essai] seulement.
class _SansBase implements Pool {
  _SansBase._();
  static final instance = _SansBase._();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError('pas de base dans l’essai');
}
