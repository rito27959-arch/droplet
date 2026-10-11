// ============================================================================
// LES PAQUETS DE CLÉS SIGNAL — pour ouvrir une session avec quelqu'un absent.
// ----------------------------------------------------------------------------
// Le protocole Signal ne chiffre pas avec une clé fixe par personne : chaque
// conversation part d'un échange de clés, puis les clés changent à CHAQUE
// message. Voler une clé aujourd'hui ne permet de relire ni les messages
// d'hier ni ceux de demain.
//
// Pour écrire à quelqu'un qui n'est pas connecté, il faut pourtant démarrer
// cet échange sans lui. Chaque téléphone dépose donc ici un « paquet » :
//   • sa clé d'identité Signal (publique) ;
//   • une pré-clé SIGNÉE par cette identité (renouvelée régulièrement) ;
//   • une réserve de pré-clés À USAGE UNIQUE : chacune n'est remise qu'à UN
//     seul demandeur, puis effacée.
//
// Rien de secret : que des clés publiques. Le serveur ne peut lire aucun
// message. Ce qu'il doit empêcher, c'est qu'on publie un FAUX paquet au nom
// de quelqu'un :
//   • chaque publication est signée par la clé d'identité du paquet ;
//   • la première identité publiée pour un identifiant est RETENUE : une
//     publication avec une autre identité est refusée (409) ;
//   • une publication plus ancienne que la dernière est refusée (rejeu), et
//     l'horloge du téléphone doit être à moins de dix minutes de la nôtre.
//
// Comme Signal, une substitution par le serveur lui-même reste détectable par
// la comparaison du code de sécurité entre les deux personnes.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:libsignal_protocol_dart/libsignal_protocol_dart.dart';
import 'package:shelf/shelf.dart';

class StockClesSignal {
  StockClesSignal(this.dossier, {DateTime Function()? horloge})
      : _horloge = horloge ?? DateTime.now;

  final Directory dossier;
  final DateTime Function() _horloge;

  /// Réserve maximale de pré-clés à usage unique par personne.
  static const int maxPreCles = 200;

  /// Pré-clés acceptées en une publication.
  static const int maxParEnvoi = 100;

  /// Écart d'horloge toléré entre le téléphone et le serveur.
  static const Duration derive = Duration(minutes: 10);

  /// Paquets remis par minute pour une même personne : freine qui voudrait
  /// vider sa réserve de pré-clés à usage unique.
  static const int lecturesParMinute = 20;

  static final RegExp _idValide = RegExp(r'^[A-Za-z0-9_-]{8,128}$');
  static const _json = {'content-type': 'application/json'};

  final Map<String, List<DateTime>> _lectures = {};
  final Map<String, Future<void>> _verrous = {};

  File _fichier(String id) => File('${dossier.path}/$id.json');

  static Response _erreur(int code, String message) =>
      Response(code, body: jsonEncode({'error': message}), headers: _json);

  static Uint8List? _b64(Object? valeur) {
    if (valeur is! String) return null;
    try {
      return base64Decode(valeur);
    } catch (_) {
      return null;
    }
  }

  static ECPublicKey? _cle(Uint8List? octets) {
    if (octets == null || octets.length != 33) return null;
    try {
      return Curve.decodePoint(octets, 0);
    } catch (_) {
      return null;
    }
  }

  /// Une seule opération à la fois par personne : deux demandes simultanées
  /// ne doivent jamais recevoir la même pré-clé à usage unique.
  Future<T> _exclusif<T>(String id, Future<T> Function() operation) {
    final precedente = _verrous[id] ?? Future<void>.value();
    final resultat = precedente.then((_) => operation());
    final fin = resultat.then<void>((_) {}, onError: (_) {});
    _verrous[id] = fin;
    unawaited(fin.then((_) {
      if (identical(_verrous[id], fin)) _verrous.remove(id);
    }));
    return resultat;
  }

  Future<Map<String, dynamic>?> _lire(String id) async {
    final fichier = _fichier(id);
    if (!await fichier.exists()) return null;
    try {
      return jsonDecode(await fichier.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  Future<void> _ecrire(String id, Map<String, dynamic> donnees) async {
    final temporaire = File('${_fichier(id).path}.tmp');
    await temporaire.writeAsString(jsonEncode(donnees), flush: true);
    await temporaire.rename(_fichier(id).path);
  }

  bool _tropDeLectures(String id) {
    final maintenant = _horloge();
    final liste = _lectures[id] ??= [];
    liste.removeWhere((t) => maintenant.difference(t) > const Duration(minutes: 1));
    if (liste.length >= lecturesParMinute) return true;
    liste.add(maintenant);
    return false;
  }

  /// PUT /cles/<id> — publie (ou complète) le paquet de clés d'une personne.
  ///
  /// Corps : `{"contenu": "<JSON en texte>", "signature": "<base64>"}`, la
  /// signature portant sur les octets exacts de `contenu`.
  Future<Response> publier(Request request, String id) async {
    if (!_idValide.hasMatch(id)) return _erreur(400, 'Identifiant invalide');
    final Map<String, dynamic> enveloppe;
    try {
      enveloppe = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      return _erreur(400, 'JSON invalide');
    }
    final texte = enveloppe['contenu'];
    final signature = _b64(enveloppe['signature']);
    if (texte is! String || texte.length > 64 * 1024 || signature == null) {
      return _erreur(400, 'Enveloppe invalide');
    }
    final Map<String, dynamic> contenu;
    try {
      contenu = jsonDecode(texte) as Map<String, dynamic>;
    } catch (_) {
      return _erreur(400, 'Contenu invalide');
    }
    if (contenu['peerId'] != id) return _erreur(400, 'Identifiant différent');
    final horodatage = contenu['horodatage'];
    if (horodatage is! int) return _erreur(400, 'Horodatage manquant');
    final ecart = _horloge()
        .difference(DateTime.fromMillisecondsSinceEpoch(horodatage))
        .abs();
    if (ecart > derive) return _erreur(400, 'Horloge du téléphone trop décalée');

    final identite = _cle(_b64(contenu['identityKey']));
    final registrationId = contenu['registrationId'];
    final signee = contenu['signedPreKey'];
    if (identite == null || registrationId is! int || signee is! Map) {
      return _erreur(400, 'Clés manquantes ou invalides');
    }

    bool verifie(Uint8List message, Uint8List sig) {
      try {
        return Curve.verifySignature(identite, message, sig);
      } catch (_) {
        return false;
      }
    }

    if (!verifie(Uint8List.fromList(utf8.encode(texte)), signature)) {
      return _erreur(401, 'Signature invalide');
    }

    final signeeOctets = _b64(signee['publicKey']);
    final signeeSignature = _b64(signee['signature']);
    final signeeId = signee['id'];
    if (_cle(signeeOctets) == null || signeeSignature == null || signeeId is! int) {
      return _erreur(400, 'Pré-clé signée invalide');
    }
    if (!verifie(signeeOctets!, signeeSignature)) {
      return _erreur(401, 'Pré-clé non signée par l\'identité');
    }

    final nouvelles = contenu['preKeys'] ?? const [];
    if (nouvelles is! List || nouvelles.length > maxParEnvoi) {
      return _erreur(400, 'Pré-clés invalides');
    }
    final validees = <Map<String, dynamic>>[];
    for (final p in nouvelles) {
      if (p is! Map || p['id'] is! int || _cle(_b64(p['publicKey'])) == null) {
        return _erreur(400, 'Pré-clé invalide');
      }
      validees.add({'id': p['id'], 'publicKey': p['publicKey']});
    }

    return _exclusif(id, () async {
      final existant = await _lire(id);
      if (existant != null) {
        if (existant['identityKey'] != contenu['identityKey']) {
          return _erreur(409, 'Une autre identité est déjà publiée pour cet identifiant');
        }
        final precedent = existant['horodatage'];
        if (precedent is int && horodatage <= precedent) {
          return _erreur(409, 'Publication plus ancienne que la dernière');
        }
      }
      final nouveauxIds = {for (final p in validees) p['id']};
      final reserve = <Map<String, dynamic>>[
        for (final p in (existant?['preKeys'] as List?) ?? const [])
          if (p is Map && !nouveauxIds.contains(p['id'])) Map<String, dynamic>.from(p),
        ...validees,
      ];
      if (reserve.length > maxPreCles) {
        reserve.removeRange(0, reserve.length - maxPreCles);
      }
      await _ecrire(id, {
        'identityKey': contenu['identityKey'],
        'registrationId': registrationId,
        'signedPreKey': {
          'id': signeeId,
          'publicKey': signee['publicKey'],
          'signature': signee['signature'],
        },
        'preKeys': reserve,
        'horodatage': horodatage,
      });
      return Response.ok(jsonEncode({'ok': true, 'restantes': reserve.length}),
          headers: _json);
    });
  }

  /// GET /cles/<id> — remet un paquet, avec UNE pré-clé à usage unique
  /// retirée de la réserve (ou sans, si elle est vide : la session s'ouvre
  /// alors sur la seule pré-clé signée, comme le permet Signal).
  Future<Response> recuperer(Request request, String id) async {
    if (!_idValide.hasMatch(id)) return _erreur(400, 'Identifiant invalide');
    if (_tropDeLectures(id)) return _erreur(429, 'Trop de demandes, réessayez plus tard');
    return _exclusif(id, () async {
      final donnees = await _lire(id);
      if (donnees == null) return _erreur(404, 'Aucune clé publiée');
      final reserve = List<Object?>.from((donnees['preKeys'] as List?) ?? const []);
      Object? unique;
      if (reserve.isNotEmpty) {
        unique = reserve.removeAt(0);
        donnees['preKeys'] = reserve;
        await _ecrire(id, donnees);
      }
      return Response.ok(
        jsonEncode({
          'identityKey': donnees['identityKey'],
          'registrationId': donnees['registrationId'],
          'deviceId': 1,
          'signedPreKey': donnees['signedPreKey'],
          'preKey': ?unique,
          'restantes': reserve.length,
        }),
        headers: _json,
      );
    });
  }

  /// GET /cles/<id>/etat — combien de pré-clés restent (rien de secret) :
  /// le téléphone en republie quand la réserve baisse.
  Future<Response> etat(Request request, String id) async {
    if (!_idValide.hasMatch(id)) return _erreur(400, 'Identifiant invalide');
    final donnees = await _lire(id);
    if (donnees == null) return _erreur(404, 'Aucune clé publiée');
    return Response.ok(
      jsonEncode({
        'restantes': ((donnees['preKeys'] as List?) ?? const []).length,
        'signedPreKeyId': (donnees['signedPreKey'] as Map?)?['id'],
        'identityKey': donnees['identityKey'],
      }),
      headers: _json,
    );
  }
}
