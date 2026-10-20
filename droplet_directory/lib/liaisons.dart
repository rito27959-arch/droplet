// ============================================================================
// LES LIAISONS — le rendez-vous entre le téléphone et Droplet Web.
// ----------------------------------------------------------------------------
// Droplet Web affiche un code QR qui porte un CANAL (16 octets aléatoires)
// et la clé publique du navigateur. Le téléphone le scanne, chiffre pour
// ce navigateur seul une enveloppe qui dit qui il est, et la dépose ici :
//
//   POST /liaison/<canal>   — le téléphone dépose l'enveloppe (chiffrée)
//   GET  /liaison/<canal>   — le navigateur la relève : 200 + enveloppe,
//                             ou 204 tant qu'elle n'est pas arrivée
//
// L'annuaire ne voit qu'un blob opaque : il ne sait ni qui se lie, ni à
// quoi. L'enveloppe est remise UNE fois puis effacée, et ne vit de toute
// façon que 5 minutes. Rien n'est écrit sur le disque.
//
// L'appareil lié reçoit ensuite sa propre file dans la boîte aux lettres :
//
//   POST   /appareils/<peerId>/<appareil>/cle   — le téléphone (signé)
//                                                 déclare la clé publique
//                                                 du navigateur ; celui-ci
//                                                 peut alors signer ses
//                                                 requêtes en son nom
//
// Et pour retirer un appareil :
//
//   DELETE /appareils/<peerId>/<appareil>       — le téléphone révoque
//   GET    /appareils/<peerId>/<appareil>/etat  — le navigateur vérifie
//                                                 qu'il est encore lié
//
// Les révocations, elles, sont gardées sur le volume : un navigateur
// éteint pendant des semaines doit apprendre à son retour qu'il a été
// déconnecté.
//
// Droplet Web vit sur un autre domaine (web.dropletmesh.app) : ces routes
// répondent aux requêtes croisées (CORS) pour cette origine.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';

class Liaisons {
  Liaisons(this._fichierRevocations) {
    try {
      if (_fichierRevocations.existsSync()) {
        final l = jsonDecode(_fichierRevocations.readAsStringSync()) as List;
        _revoques.addAll(l.cast<String>());
      }
    } catch (e) {
      print('[Liaisons] Révocations illisibles : $e');
    }
  }

  final File _fichierRevocations;
  final Map<String, ({String enveloppe, DateTime depot})> _enAttente = {};
  final Set<String> _revoques = {};

  static const _duree = Duration(minutes: 5);
  static const _tailleMax = 16 * 1024;
  static final _formeCanal = RegExp(r'^[A-Za-z0-9_-]{20,24}$');
  static final _formeId = RegExp(r'^[A-Za-z0-9_=-]{4,80}$');

  static const _origines = {
    'https://web.dropletmesh.app',
    'https://dropletmesh.app',
    'http://localhost:8080',
  };

  /// Les en-têtes CORS, pour Droplet Web seulement.
  static Map<String, String> enTetesCors(Request r) {
    final origine = r.headers['origin'];
    if (origine == null || !(_origines.contains(origine) || origine.endsWith('.vercel.app'))) {
      return const {};
    }
    return {
      'access-control-allow-origin': origine,
      'access-control-allow-methods': 'GET, POST, DELETE, OPTIONS',
      'access-control-allow-headers': 'content-type, x-droplet-id, x-droplet-ts, x-droplet-nonce, x-droplet-sig',
      'access-control-expose-headers': 'x-droplet-raison, x-droplet-heure',
      'access-control-max-age': '86400',
      'vary': 'origin',
    };
  }

  /// Le middleware : répond aux pré-vérifications OPTIONS et ajoute les
  /// en-têtes CORS aux réponses des routes de liaison.
  static Middleware cors() => (Handler suivant) => (Request r) async {
        final concerne = r.url.path.startsWith('liaison/') || r.url.path.startsWith('appareils/') || r.url.path == 'search';
        if (!concerne) return suivant(r);
        if (r.method == 'OPTIONS') return Response(204, headers: enTetesCors(r));
        final reponse = await suivant(r);
        return reponse.change(headers: enTetesCors(r));
      };

  void _menage() {
    final limite = DateTime.now().subtract(_duree);
    _enAttente.removeWhere((_, v) => v.depot.isBefore(limite));
  }

  Future<Response> deposer(Request r, String canal) async {
    if (!_formeCanal.hasMatch(canal)) return Response(400, body: 'canal invalide');
    final corps = await r.readAsString();
    if (corps.length > _tailleMax) return Response(413, body: 'enveloppe trop grande');
    try {
      final j = jsonDecode(corps);
      if (j is! Map || j['v'] != 1 || j['chiffre'] is! String || j['nonce'] is! String || j['cleTel'] is! String) {
        return Response(400, body: 'enveloppe invalide');
      }
    } catch (_) {
      return Response(400, body: 'enveloppe invalide');
    }
    _menage();
    if (_enAttente.length > 5000) return Response(503, body: 'trop de liaisons en cours');
    _enAttente[canal] = (enveloppe: corps, depot: DateTime.now());
    return Response(201, body: '{"ok":true}', headers: {'content-type': 'application/json'});
  }

  Response relever(Request r, String canal) {
    if (!_formeCanal.hasMatch(canal)) return Response(400, body: 'canal invalide');
    _menage();
    final e = _enAttente.remove(canal);
    if (e == null) return Response(204);
    return Response.ok(e.enveloppe, headers: {'content-type': 'application/json', 'cache-control': 'no-store'});
  }

  Response revoquer(Request r, String peerId, String appareil) {
    if (!_formeId.hasMatch(peerId) || !_formeId.hasMatch(appareil)) return Response(400);
    if (_revoques.add('$peerId/$appareil')) _enregistrer();
    return Response.ok('{"ok":true}', headers: {'content-type': 'application/json'});
  }

  bool estRevoque(String peerId, String appareil) => _revoques.contains('$peerId/$appareil');

  static bool formeValide(String id) => _formeId.hasMatch(id);

  Response etat(Request r, String peerId, String appareil) {
    if (!_formeId.hasMatch(peerId) || !_formeId.hasMatch(appareil)) return Response(400);
    final revoque = _revoques.contains('$peerId/$appareil');
    return Response.ok(
      jsonEncode({'lie': !revoque}),
      headers: {'content-type': 'application/json', 'cache-control': 'no-store'},
    );
  }

  void _enregistrer() {
    try {
      _fichierRevocations.writeAsStringSync(jsonEncode(_revoques.toList()));
    } catch (e) {
      print('[Liaisons] Écriture impossible : $e');
    }
  }
}
