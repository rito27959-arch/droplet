// ============================================================================
// LA SÉCURITÉ DES SERVEURS DROPLET — partagée par l'annuaire et la boîte aux
// lettres (le même fichier dans chaque service).
// ----------------------------------------------------------------------------
// ── 1. QUI PARLE ? Les requêtes signées ─────────────────────────────
//
// Chaque appareil Droplet a une paire de clés X25519 (son identité). Le
// serveur a la sienne (CLE_SERVEUR). Les deux calculent le même secret :
//
//     K = HKDF-SHA256( X25519(clé privée appareil, clé publique serveur),
//                      sel « droplet-mesh », info « droplet-auth-v1 » )
//
// et l'appareil signe chaque requête avec trois en-têtes :
//
//     X-Droplet-Id     son identifiant
//     X-Droplet-Ts     l'heure (secondes Unix)
//     X-Droplet-Nonce  16 octets aléatoires (base64url), neufs à chaque fois
//     X-Droplet-Sig    base64url( HMAC-SHA256(K, MÉTHODE \n chemin \n heure \n
//                                             nonce \n sha256-hex(corps)) )
//
// Le serveur ne voit jamais la clé privée de personne ; il prouve juste que
// la requête vient du détenteur de la clé publique ENREGISTRÉE pour cet
// identifiant. Une signature vieille de plus de 5 minutes, ou déjà vue,
// est refusée (pas de rejeu).
//
// ── 2. LA TRANSITION, sans casser les apps déjà installées ─────────
//
// Les versions de l'app d'avant cette mise à jour ne signent rien. Règle :
//
//   • un identifiant qui n'a JAMAIS signé reste accepté sans signature
//     (c'est le comportement d'avant) ;
//   • dès sa première requête signée valide, il est VERROUILLÉ : toute
//     requête non signée à son nom est refusée pour toujours.
//
// Chaque utilisateur est donc protégé dès qu'il installe la mise à jour, et
// personne n'est coupé en attendant. Le jour où toutes les apps signent,
// EXIGER_SIGNATURE=1 refuse tout ce qui ne l'est pas.
//
// ── 3. LES APPELS ENTRE SERVEURS ───────────────────────────────────
//
// /notify (réveiller un téléphone) n'est appelé que par nos serveurs, avec
// l'en-tête X-Cle-Interne (variable CLE_INTERNE). Personne d'autre ne peut
// envoyer une notification à quelqu'un.
// ============================================================================

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as c;
import 'package:cryptography/cryptography.dart';
import 'package:shelf/shelf.dart';

enum Verdict {
  /// Signature présente et valide.
  signe,

  /// Pas de signature (ancienne version de l'app).
  absent,

  /// Signature présente mais fausse, périmée ou rejouée.
  invalide,
}

class Securite {
  Securite._(this._cleServeur, this.cleInterne, this.exigerSignature);

  final SimpleKeyPair? _cleServeur;
  final String cleInterne;
  final bool exigerSignature;

  static const _fenetre = Duration(minutes: 5);
  final _x25519 = X25519();
  final _cache = LinkedHashMap<String, List<int>>();
  final _vues = <String, DateTime>{};

  /// Lit CLE_SERVEUR (graine X25519 en base64), CLE_INTERNE et
  /// EXIGER_SIGNATURE dans l'environnement.
  static Future<Securite> depuisEnvironnement() async {
    final graine = Platform.environment['CLE_SERVEUR'];
    SimpleKeyPair? cle;
    if (graine != null && graine.isNotEmpty) {
      cle = await X25519().newKeyPairFromSeed(base64.decode(base64.normalize(graine)));
      final pub = await cle.extractPublicKey();
      print('[Sécurité] Clé publique du serveur : ${base64.encode(pub.bytes)}');
    } else {
      print('[Sécurité] ⚠️ CLE_SERVEUR absente : les signatures ne peuvent pas être vérifiées');
    }
    final interne = Platform.environment['CLE_INTERNE'] ?? '';
    if (interne.isEmpty) print('[Sécurité] ⚠️ CLE_INTERNE absente : /notify refusera tout');
    return Securite._(cle, interne, Platform.environment['EXIGER_SIGNATURE'] == '1');
  }

  /// La requête vient-elle bien de [peerId] ? [clePublique] est sa clé
  /// enregistrée (base64), ou null si on ne la connaît pas.
  Future<Verdict> verifier(Request r, String peerId, List<int> corps, String? clePublique) async {
    final id = r.headers['x-droplet-id'];
    final ts = r.headers['x-droplet-ts'];
    final sig = r.headers['x-droplet-sig'];
    final nonce = r.headers['x-droplet-nonce'];
    if (id == null && ts == null && sig == null) return Verdict.absent;
    if (id != peerId || ts == null || sig == null || nonce == null || nonce.length < 16 || nonce.length > 64) {
      return Verdict.invalide;
    }
    if (_cleServeur == null || clePublique == null) return Verdict.invalide;

    final secondes = int.tryParse(ts);
    if (secondes == null) return Verdict.invalide;
    final quand = DateTime.fromMillisecondsSinceEpoch(secondes * 1000, isUtc: true);
    if (DateTime.now().toUtc().difference(quand).abs() > _fenetre) return Verdict.invalide;

    final k = await _secret(peerId, clePublique);
    if (k == null) return Verdict.invalide;
    final canon = '${r.method.toUpperCase()}\n${r.requestedUri.path}\n$ts\n$nonce\n${c.sha256.convert(corps)}';
    final attendu = base64Url.encode(c.Hmac(c.sha256, k).convert(utf8.encode(canon)).bytes).replaceAll('=', '');
    if (!_egal(attendu, sig.replaceAll('=', ''))) return Verdict.invalide;

    // Pas de rejeu : chaque signature ne sert qu'une fois.
    _oublierVieilles();
    if (_vues.containsKey(sig)) return Verdict.invalide;
    _vues[sig] = DateTime.now();
    return Verdict.signe;
  }

  Future<List<int>?> _secret(String peerId, String clePublique) async {
    final cleCache = '$peerId|$clePublique';
    final deja = _cache.remove(cleCache);
    if (deja != null) {
      _cache[cleCache] = deja;
      return deja;
    }
    try {
      final pub = base64.decode(base64.normalize(clePublique.replaceAll('-', '+').replaceAll('_', '/')));
      if (pub.length != 32) return null;
      final partage = await _x25519.sharedSecretKey(
        keyPair: _cleServeur!,
        remotePublicKey: SimplePublicKey(pub, type: KeyPairType.x25519),
      );
      final k = await Hkdf(hmac: Hmac.sha256(), outputLength: 32).deriveKey(
        secretKey: partage,
        info: utf8.encode('droplet-auth-v1'),
        nonce: utf8.encode('droplet-mesh'),
      );
      final octets = await k.extractBytes();
      _cache[cleCache] = octets;
      if (_cache.length > 50000) _cache.remove(_cache.keys.first);
      return octets;
    } catch (_) {
      return null;
    }
  }

  void _oublierVieilles() {
    if (_vues.length < 2000) return;
    final limite = DateTime.now().subtract(_fenetre * 2);
    _vues.removeWhere((_, t) => t.isBefore(limite));
  }

  /// L'appel vient-il d'un de nos serveurs ?
  bool estInterne(Request r) {
    final cle = r.headers['x-cle-interne'];
    return cleInterne.isNotEmpty && cle != null && _egal(cle, cleInterne);
  }

  static bool _egal(String a, String b) {
    if (a.length != b.length) return false;
    var d = 0;
    for (var i = 0; i < a.length; i++) {
      d |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return d == 0;
  }
}

// ── Les limites de débit ──────────────────────────────────────────────

/// Un seau à jetons par clé (adresse IP, identifiant…) : [capacite]
/// requêtes d'un coup, puis [parMinute] en régime continu. C'est ce qui
/// empêche un seul client de saturer le serveur ou d'inonder quelqu'un.
class Debit {
  Debit({required this.capacite, required this.parMinute});

  final int capacite;
  final int parMinute;
  final _seaux = <String, (double, DateTime)>{};

  bool autoriser(String cle) {
    final maintenant = DateTime.now();
    final (jetons, depuis) = _seaux[cle] ?? (capacite.toDouble(), maintenant);
    final recharges = maintenant.difference(depuis).inMilliseconds * parMinute / 60000;
    final dispo = (jetons + recharges).clamp(0, capacite).toDouble();
    if (dispo < 1) {
      _seaux[cle] = (dispo, maintenant);
      return false;
    }
    _seaux[cle] = (dispo - 1, maintenant);
    if (_seaux.length > 200000) _menage(maintenant);
    return true;
  }

  void _menage(DateTime maintenant) {
    _seaux.removeWhere((_, v) => maintenant.difference(v.$2) > const Duration(minutes: 10));
  }
}

/// L'adresse du client, derrière le proxy de Railway. Railway écrit
/// lui-même X-Real-IP ; dans X-Forwarded-For, c'est la DERNIÈRE adresse
/// qu'il ajoute — la première peut être inventée par le client.
String adresseClient(Request r) {
  final reelle = r.headers['x-real-ip'];
  if (reelle != null && reelle.isNotEmpty) return reelle.trim();
  final fwd = r.headers['x-forwarded-for'];
  if (fwd != null && fwd.isNotEmpty) return fwd.split(',').last.trim();
  final info = r.context['shelf.io.connection_info'];
  return info is HttpConnectionInfo ? info.remoteAddress.address : 'inconnu';
}

/// Middleware : limite globale par adresse IP.
Middleware limiteParIp(Debit debit) => (Handler suivant) => (Request r) {
      if (r.url.path == 'health') return suivant(r);
      if (!debit.autoriser(adresseClient(r))) {
        return Response(429, body: '{"error":"trop de requêtes"}', headers: {
          'content-type': 'application/json',
          'retry-after': '10',
        });
      }
      return suivant(r);
    };

/// Un journal sobre, fait pour tenir la charge : jamais de contenu, jamais
/// une ligne par requête (à 100 000 appareils, ce serait des millions de
/// lignes par heure). Les erreurs serveur et les requêtes très lentes sont
/// écrites tout de suite ; le reste est résumé une fois par minute.
Middleware journalSobre(String nom) {
  final bilan = <int, int>{};
  var lentes = 0;
  Timer.periodic(const Duration(minutes: 1), (_) {
    if (bilan.isEmpty) return;
    final total = bilan.values.fold(0, (a, b) => a + b);
    final detail = (bilan.keys.toList()..sort()).map((c) => '$c×${bilan[c]}').join(' ');
    print('[$nom] dernière minute : $total requêtes ($detail)${lentes > 0 ? ' · $lentes lentes' : ''}');
    bilan.clear();
    lentes = 0;
  });
  return (Handler suivant) => (Request r) async {
        final debut = DateTime.now();
        final rep = await suivant(r);
        final ms = DateTime.now().difference(debut).inMilliseconds;
        bilan[rep.statusCode] = (bilan[rep.statusCode] ?? 0) + 1;
        // Une attente longue dure 20 s par nature : elle n'est pas « lente ».
        final attente = r.url.queryParameters.containsKey('attendre');
        if (!attente && ms > 2000) lentes++;
        if (rep.statusCode >= 500 || (!attente && ms > 5000)) {
          final chemin = r.url.path.length > 24 ? '${r.url.path.substring(0, 24)}…' : r.url.path;
          print('[$nom] ${r.method} /$chemin → ${rep.statusCode} ($ms ms)');
        }
        return rep;
      };
}

Response json(Object corps, {int statut = 200, Map<String, String>? enTetes}) => Response(
      statut,
      body: jsonEncode(corps),
      headers: {'content-type': 'application/json', ...?enTetes},
    );
