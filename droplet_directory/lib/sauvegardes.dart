// ============================================================================
// SAUVEGARDES CHIFFRÉES — stockées sur le volume, jamais lisibles ici.
// ----------------------------------------------------------------------------
// L'application chiffre la sauvegarde sur le téléphone (mot de passe choisi
// par l'utilisateur, PBKDF2 300 000 tours puis AES-GCM) avant de l'envoyer.
// Ce serveur ne reçoit que :
//   • un IDENTIFIANT opaque (64 caractères hexadécimaux), dérivé sur le
//     téléphone du pseudo et du mot de passe — il ne révèle ni l'un ni
//     l'autre ;
//   • un JETON d'accès, dérivé de la même façon avec un autre sel. Le premier
//     dépôt le fixe ; tout dépôt, lecture ou suppression ultérieur doit le
//     présenter. Le jeton ne permet PAS de déchiffrer (clé différente) ;
//   • l'enveloppe chiffrée elle-même.
//
// ⚠️ LES ÉCHECS SONT LIMITÉS : 10 par identifiant et par heure. Sans ce frein,
// quelqu'un qui connaîtrait un identifiant pourrait essayer des jetons en
// rafale.
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:shelf/shelf.dart';

class StockSauvegardes {
  StockSauvegardes(this.dossier);

  final Directory dossier;

  /// Taille maximale d'une sauvegarde (texte des discussions, sans médias).
  static const int tailleMax = 25 * 1024 * 1024;

  static const int echecsMax = 10;

  static final RegExp _idValide = RegExp(r'^[0-9a-f]{64}$');

  final Map<String, List<DateTime>> _echecs = {};

  static const _json = {'content-type': 'application/json'};

  File _fichierSauvegarde(String id) => File('${dossier.path}/$id.sauvegarde');
  File _fichierJeton(String id) => File('${dossier.path}/$id.jeton');

  static Response _erreur(int code, String message) =>
      Response(code, body: jsonEncode({'error': message}), headers: _json);

  /// Comparaison à temps constant : ne laisse pas deviner le jeton octet par
  /// octet en mesurant le temps de réponse.
  static bool _egaux(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  bool _bloque(String id) {
    final maintenant = DateTime.now();
    final liste = _echecs[id];
    if (liste == null) return false;
    liste.removeWhere((t) => maintenant.difference(t) > const Duration(hours: 1));
    return liste.length >= echecsMax;
  }

  void _noterEchec(String id) => (_echecs[id] ??= []).add(DateTime.now());

  /// Contrôles communs : identifiant bien formé, jeton présent, pas bloqué.
  Response? _refus(Request request, String id) {
    if (!_idValide.hasMatch(id)) return _erreur(400, 'Identifiant invalide');
    final jeton = request.headers['x-jeton-sauvegarde'] ?? '';
    if (jeton.length < 32) return _erreur(401, 'Jeton manquant');
    if (_bloque(id)) return _erreur(429, 'Trop d\'essais, réessayez plus tard');
    return null;
  }

  /// `true` si le jeton présenté est celui de la sauvegarde (ou s'il n'y en a
  /// pas encore et que [creation] est permise).
  bool _jetonAccepte(Request request, String id, {required bool creation}) {
    final jeton = request.headers['x-jeton-sauvegarde'] ?? '';
    final fichier = _fichierJeton(id);
    if (!fichier.existsSync()) return creation;
    return _egaux(fichier.readAsStringSync(), jeton);
  }

  Future<Response> deposer(Request request, String id) async {
    final refus = _refus(request, id);
    if (refus != null) return refus;
    if (!_jetonAccepte(request, id, creation: true)) {
      _noterEchec(id);
      return _erreur(409, 'Identifiant déjà utilisé');
    }
    final annonce = request.contentLength;
    if (annonce != null && annonce > tailleMax) return _erreur(413, 'Sauvegarde trop volumineuse');

    final corps = BytesBuilder(copy: false);
    await for (final morceau in request.read()) {
      corps.add(morceau);
      if (corps.length > tailleMax) return _erreur(413, 'Sauvegarde trop volumineuse');
    }
    final octets = corps.takeBytes();

    // Ce stockage n'accepte que des enveloppes de sauvegarde Droplet : il ne
    // doit pas servir d'hébergement de fichiers quelconques.
    try {
      final enveloppe = jsonDecode(utf8.decode(octets)) as Map<String, dynamic>;
      if (enveloppe['ciphertext'] is! String || enveloppe['nonce'] is! String || enveloppe['kdf'] is! Map) {
        return _erreur(400, 'Enveloppe de sauvegarde invalide');
      }
    } catch (_) {
      return _erreur(400, 'Enveloppe de sauvegarde invalide');
    }

    await dossier.create(recursive: true);
    // Écriture dans un fichier temporaire puis renommage : une coupure pendant
    // l'envoi ne remplace jamais une bonne sauvegarde par une moitié.
    final temporaire = File('${_fichierSauvegarde(id).path}.tmp');
    await temporaire.writeAsBytes(octets, flush: true);
    await temporaire.rename(_fichierSauvegarde(id).path);
    final jeton = _fichierJeton(id);
    if (!jeton.existsSync()) {
      await jeton.writeAsString(request.headers['x-jeton-sauvegarde']!, flush: true);
    }
    print('[Sauvegardes] Dépôt ${id.substring(0, 8)}… (${octets.length} octets)');
    return Response.ok(jsonEncode({'ok': true, 'taille': octets.length}), headers: _json);
  }

  Future<Response> lire(Request request, String id) async {
    final refus = _refus(request, id);
    if (refus != null) return refus;
    // Même réponse pour « inexistante » et « mauvais jeton » : le serveur ne
    // confirme pas l'existence d'une sauvegarde à qui n'a pas le bon jeton.
    if (!_fichierSauvegarde(id).existsSync() || !_jetonAccepte(request, id, creation: false)) {
      _noterEchec(id);
      return _erreur(404, 'Aucune sauvegarde');
    }
    return Response.ok(
      _fichierSauvegarde(id).openRead(),
      headers: {'content-type': 'application/json'},
    );
  }

  Future<Response> supprimer(Request request, String id) async {
    final refus = _refus(request, id);
    if (refus != null) return refus;
    if (!_fichierSauvegarde(id).existsSync() || !_jetonAccepte(request, id, creation: false)) {
      _noterEchec(id);
      return _erreur(404, 'Aucune sauvegarde');
    }
    await _fichierSauvegarde(id).delete();
    if (_fichierJeton(id).existsSync()) await _fichierJeton(id).delete();
    return Response.ok(jsonEncode({'ok': true}), headers: _json);
  }
}
