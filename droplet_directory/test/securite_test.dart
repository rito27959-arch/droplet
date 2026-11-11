// ============================================================================
// LES ESSAIS DE LA SÉCURITÉ DES SERVEURS (securite.dart).
// ----------------------------------------------------------------------------
// Ce fichier est le filet de sécurité de tout le reste : qui parle (requêtes
// signées), pas de rejeu, fenêtre de 5 minutes, limites de débit, adresse du
// client derrière le proxy, appels entre serveurs.
//
// Il signe ses requêtes EXACTEMENT comme l'app
// (lib/core/services/signature_serveur.dart) :
//   K   = HKDF-SHA256(X25519(appareil, serveur), sel « droplet-mesh »,
//                     info « droplet-auth-v1 »)
//   sig = base64url(HMAC-SHA256(K, MÉTHODE \n chemin \n heure \n nonce \n
//                               sha256-hex(corps)))
//
// Lancement (la CI le fait) : une clé de serveur D'ESSAI est donnée par
// l'environnement — jamais celle de la production.
//   CLE_SERVEUR=<32 octets en base64> CLE_INTERNE=<texte> dart test
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as c;
import 'package:cryptography/cryptography.dart';
import 'package:droplet_directory/securite.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

final _x25519 = X25519();

/// Un appareil d'essai : sa paire de clés et le secret partagé avec le serveur.
class Appareil {
  Appareil(this.id, this.cles, this.clePublique, this.secret);
  final String id;
  final SimpleKeyPair cles;
  final String clePublique;
  final List<int> secret;

  static Future<Appareil> creer(String id, SimplePublicKey serveur) async {
    final cles = await _x25519.newKeyPair();
    final pub = await cles.extractPublicKey();
    final partage = await _x25519.sharedSecretKey(keyPair: cles, remotePublicKey: serveur);
    final k = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
      secretKey: partage,
      info: utf8.encode('droplet-auth-v1'),
      nonce: utf8.encode('droplet-mesh'),
    );
    return Appareil(id, cles, base64.encode(pub.bytes), await k.extractBytes());
  }

  /// Une requête signée par cet appareil.
  Request requete(
    String methode,
    String chemin, {
    String corps = '',
    int? heure,
    String? nonce,
    String? idAnnonce,
    String? corpsSigne,
  }) {
    final ts = '${heure ?? DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000}';
    final n = nonce ?? base64Url.encode(List.generate(16, (i) => (DateTime.now().microsecondsSinceEpoch + i * 7919 + _compteur++) & 0xff)).replaceAll('=', '');
    final canon = '${methode.toUpperCase()}\n$chemin\n$ts\n$n\n${c.sha256.convert(utf8.encode(corpsSigne ?? corps))}';
    final sig = base64Url.encode(c.Hmac(c.sha256, secret).convert(utf8.encode(canon)).bytes).replaceAll('=', '');
    return Request(
      methode,
      Uri.parse('http://localhost$chemin'),
      headers: {
        'x-droplet-id': idAnnonce ?? id,
        'x-droplet-ts': ts,
        'x-droplet-nonce': n,
        'x-droplet-sig': sig,
      },
      body: corps,
    );
  }
}

var _compteur = 0;

void main() {
  late Securite securite;
  late SimplePublicKey cleServeur;
  late Appareil alice;
  late Appareil eve;

  setUpAll(() async {
    final graine = Platform.environment['CLE_SERVEUR'];
    if (graine == null || graine.isEmpty) {
      fail('CLE_SERVEUR (clé d\'essai) absente : lancer avec CLE_SERVEUR=<32 octets base64> dart test');
    }
    final paire = await _x25519.newKeyPairFromSeed(base64.decode(base64.normalize(graine)));
    cleServeur = await paire.extractPublicKey();
    securite = await Securite.depuisEnvironnement(silencieux: true);
    alice = await Appareil.creer('alice-0001', cleServeur);
    eve = await Appareil.creer('eve-0002', cleServeur);
  });

  Future<Verdict> verifier(Request r, String peerId, String corps, String? cle) =>
      securite.verifier(r, peerId, utf8.encode(corps), cle);

  group('Requêtes signées', () {
    test('une signature valide est acceptée', () async {
      final r = alice.requete('POST', '/register', corps: '{"a":1}');
      expect(await verifier(r, alice.id, '{"a":1}', alice.clePublique), Verdict.signe);
    });

    test('sans aucun en-tête : « absent » (ancienne app), pas « invalide »', () async {
      final r = Request('GET', Uri.parse('http://localhost/search'));
      expect(await verifier(r, alice.id, '', alice.clePublique), Verdict.absent);
    });

    test('la même signature rejouée est refusée', () async {
      final r = alice.requete('POST', '/presence', corps: '{}');
      expect(await verifier(r, alice.id, '{}', alice.clePublique), Verdict.signe);
      final rejeu = Request('POST', r.requestedUri, headers: r.headers, body: '{}');
      expect(await verifier(rejeu, alice.id, '{}', alice.clePublique), Verdict.invalide);
      expect(Securite.raisons[rejeu], 'rejeu');
    });

    test('une heure vieille de plus de 5 minutes est refusée', () async {
      final vieux = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 6 * 60;
      final r = alice.requete('POST', '/register', heure: vieux);
      expect(await verifier(r, alice.id, '', alice.clePublique), Verdict.invalide);
      expect(Securite.raisons[r], 'heure');
    });

    test('une heure en avance de plus de 5 minutes est refusée', () async {
      final futur = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + 6 * 60;
      final r = alice.requete('POST', '/register', heure: futur);
      expect(await verifier(r, alice.id, '', alice.clePublique), Verdict.invalide);
      expect(Securite.raisons[r], 'heure');
    });

    test('une heure décalée de 4 minutes passe encore', () async {
      final proche = DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 - 4 * 60;
      final r = alice.requete('POST', '/register', heure: proche);
      expect(await verifier(r, alice.id, '', alice.clePublique), Verdict.signe);
    });

    test('signer avec la clé d\'un autre est refusé', () async {
      // Ève signe au nom d'Alice avec SA clé à elle.
      final r = eve.requete('POST', '/register', idAnnonce: alice.id);
      expect(await verifier(r, alice.id, '', alice.clePublique), Verdict.invalide);
      expect(Securite.raisons[r], 'signature');
    });

    test('un corps modifié après signature est refusé', () async {
      final r = alice.requete('POST', '/register', corps: '{"pseudo":"Eve"}', corpsSigne: '{"pseudo":"Alice"}');
      expect(await verifier(r, alice.id, '{"pseudo":"Eve"}', alice.clePublique), Verdict.invalide);
      expect(Securite.raisons[r], 'signature');
    });

    test('un chemin différent de celui signé est refusé', () async {
      final r = alice.requete('DELETE', '/messages/alice-0001');
      final ailleurs = Request('DELETE', Uri.parse('http://localhost/messages/bob-0003'), headers: r.headers);
      expect(await verifier(ailleurs, alice.id, '', alice.clePublique), Verdict.invalide);
      expect(Securite.raisons[ailleurs], 'signature');
    });

    test('une méthode différente de celle signée est refusée', () async {
      final r = alice.requete('GET', '/messages/alice-0001');
      final autre = Request('DELETE', r.requestedUri, headers: r.headers);
      expect(await verifier(autre, alice.id, '', alice.clePublique), Verdict.invalide);
    });

    test('l\'identifiant annoncé doit être celui de la requête', () async {
      final r = alice.requete('POST', '/register');
      expect(await verifier(r, 'bob-0003', '', alice.clePublique), Verdict.invalide);
      expect(Securite.raisons[r], 'entetes');
    });

    test('aucune clé enregistrée : refus « inconnu »', () async {
      final r = alice.requete('POST', '/register');
      expect(await verifier(r, alice.id, '', null), Verdict.invalide);
      expect(Securite.raisons[r], 'inconnu');
    });

    test('un nonce trop court est refusé', () async {
      final r = alice.requete('POST', '/register', nonce: 'court');
      expect(await verifier(r, alice.id, '', alice.clePublique), Verdict.invalide);
      expect(Securite.raisons[r], 'entetes');
    });

    test('une clé publique illisible est refusée sans planter', () async {
      final r = alice.requete('POST', '/register');
      expect(await verifier(r, alice.id, '', 'pas-une-cle'), Verdict.invalide);
    });

    test('le registre partagé (base) refuse une signature déjà vue ailleurs', () async {
      // Une autre copie du service a déjà vu cette signature.
      securite.premiereFois = (_) async => false;
      addTearDown(() => securite.premiereFois = null);
      final r = alice.requete('POST', '/register');
      expect(await verifier(r, alice.id, '', alice.clePublique), Verdict.invalide);
      expect(Securite.raisons[r], 'rejeu');
    });

    test('base injoignable : la requête valide passe quand même', () async {
      securite.premiereFois = (_) async => throw StateError('base injoignable');
      addTearDown(() => securite.premiereFois = null);
      final r = alice.requete('POST', '/register');
      expect(await verifier(r, alice.id, '', alice.clePublique), Verdict.signe);
    });

    test('un refus donne sa raison et l\'heure du serveur au client', () async {
      final r = alice.requete('POST', '/register', heure: 1000);
      await verifier(r, alice.id, '', alice.clePublique);
      final entetes = Securite.entetesRefus(r);
      expect(entetes['x-droplet-raison'], 'heure');
      final heure = int.parse(entetes['x-droplet-heure']!);
      expect((heure - DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000).abs(), lessThan(5));
    });
  });

  group('Appels entre serveurs', () {
    test('la bonne clé interne est reconnue', () {
      final cle = Platform.environment['CLE_INTERNE'] ?? '';
      expect(cle, isNotEmpty, reason: 'CLE_INTERNE (d\'essai) absente');
      final r = Request('POST', Uri.parse('http://localhost/notify'), headers: {'x-cle-interne': cle});
      expect(securite.estInterne(r), isTrue);
    });

    test('une mauvaise clé, ou aucune, est refusée', () {
      final faux = Request('POST', Uri.parse('http://localhost/notify'), headers: {'x-cle-interne': 'fausse'});
      final rien = Request('POST', Uri.parse('http://localhost/notify'));
      expect(securite.estInterne(faux), isFalse);
      expect(securite.estInterne(rien), isFalse);
    });
  });

  group('Limites de débit', () {
    test('la capacité passe d\'un coup, la suivante est refusée', () {
      final d = Debit(capacite: 5, parMinute: 1);
      for (var i = 0; i < 5; i++) {
        expect(d.autoriser('ip'), isTrue, reason: 'requête $i');
      }
      expect(d.autoriser('ip'), isFalse);
    });

    test('chaque clé a son propre seau', () {
      final d = Debit(capacite: 1, parMinute: 1);
      expect(d.autoriser('a'), isTrue);
      expect(d.autoriser('a'), isFalse);
      expect(d.autoriser('b'), isTrue);
    });

    test('le seau se recharge avec le temps', () async {
      final d = Debit(capacite: 1, parMinute: 6000); // un jeton toutes les 10 ms
      expect(d.autoriser('ip'), isTrue);
      expect(d.autoriser('ip'), isFalse);
      await Future<void>.delayed(const Duration(milliseconds: 60));
      expect(d.autoriser('ip'), isTrue);
    });

    test('le middleware répond 429 au-delà de la limite, jamais sur /health', () async {
      final m = limiteParIp(Debit(capacite: 2, parMinute: 1));
      final h = m((r) => Response.ok('ok'));
      Request req(String chemin) => Request('GET', Uri.parse('http://localhost/$chemin'), headers: {'x-real-ip': '10.0.0.9'});
      expect((await h(req('search'))).statusCode, 200);
      expect((await h(req('search'))).statusCode, 200);
      expect((await h(req('search'))).statusCode, 429);
      expect((await h(req('health'))).statusCode, 200);
    });

    test('nos propres serveurs sont exemptés', () async {
      final m = limiteParIp(Debit(capacite: 1, parMinute: 1), exempter: (r) => r.headers['x-interne'] == '1');
      final h = m((r) => Response.ok('ok'));
      Request req() => Request('POST', Uri.parse('http://localhost/notify'), headers: {'x-real-ip': '10.0.0.7', 'x-interne': '1'});
      for (var i = 0; i < 5; i++) {
        expect((await h(req())).statusCode, 200);
      }
    });
  });

  group('Adresse du client derrière le proxy', () {
    test('X-Real-IP (écrit par Railway) passe avant tout', () {
      final r = Request('GET', Uri.parse('http://localhost/'), headers: {
        'x-real-ip': '203.0.113.5',
        'x-forwarded-for': '1.1.1.1, 198.51.100.7',
      });
      expect(adresseClient(r), '203.0.113.5');
    });

    test('dans X-Forwarded-For, la DERNIÈRE adresse (la première peut être inventée)', () {
      final r = Request('GET', Uri.parse('http://localhost/'), headers: {'x-forwarded-for': '1.1.1.1, 198.51.100.7'});
      expect(adresseClient(r), '198.51.100.7');
    });

    test('sans en-tête : « inconnu », sans planter', () {
      expect(adresseClient(Request('GET', Uri.parse('http://localhost/'))), 'inconnu');
    });
  });
}
