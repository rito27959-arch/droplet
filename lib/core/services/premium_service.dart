// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// CE QUI DÉCIDE SI UNE PERSONNE A DÉBLOQUÉ LE PACK OU DROPLET PRO.
//
// ── ⚠️ LE PROBLÈME, ET POURQUOI IL EST PARTICULIER ICI ────────────────
//
// Toutes les applications payantes du monde posent la même question à un
// serveur : « cette personne a-t-elle payé ? ». Droplet n'a AUCUN
// serveur — c'est son argument principal. Il doit donc en juger seul,
// hors ligne, sans jamais rien contacter, sur un téléphone dont
// l'utilisateur est le propriétaire complet.
//
// Trois façons de s'y prendre, et deux sont mauvaises :
//
//   ✗ UN BOOLÉEN « premium = true » quelque part. Le premier venu avec
//     un explorateur de fichiers racine le bascule. Pire : il se copie
//     d'un téléphone à l'autre avec une sauvegarde.
//
//   ✗ UN CODE SECRET partagé, caché dans l'application. Un APK
//     s'ouvre avec n'importe quel utilitaire, et les chaînes de
//     caractères s'y lisent en clair. Le premier acheteur publie le
//     code, et plus personne ne paie.
//
//   ✓ UNE SIGNATURE. Chaque licence est signée par une clé privée que
//     seul l'auteur détient. L'application n'embarque que la clé
//     PUBLIQUE, qui permet uniquement de VÉRIFIER — jamais de
//     fabriquer. Extraire cette clé de l'APK n'apporte rien du tout.
//
// ── ⚠️ LA LICENCE EST LIÉE À UN APPAREIL, ET C'EST L'ESSENTIEL ────────
//
// La signature porte sur l'identifiant de l'appareil. Une licence
// délivrée pour le téléphone d'Amina ne débloque rien sur celui de
// Michel. Le code peut donc circuler librement sur WhatsApp : il ne sert
// à personne d'autre. C'est la seule fraude qui compte vraiment à cette
// échelle, et elle est fermée.
//
// ── ⚠️ ON NE STOCKE PAS « DÉBLOQUÉ », ON STOCKE LA LICENCE ────────────
//
// C'est le détail qui fait tenir le reste. Ce qui est conservé est le
// CODE lui-même, et sa signature est revérifiée à chaque démarrage.
// Quelqu'un qui trafique le stockage n'obtient rien : sans signature
// valable, la licence est rejetée à la lecture suivante. Enregistrer un
// booléen « c'est bon » aurait rendu toute la cryptographie décorative.
//
// ── Ce que ça ne protège PAS ──────────────────────────────────────────
//
// Quelqu'un qui décompile l'application peut retirer cette vérification
// et se fabriquer une version débloquée. C'est vrai de TOUTE application
// hors ligne, sans exception, y compris des plus grandes. Le but est que
// l'effort dépasse largement 500 F — pas de rendre la chose impossible,
// ce qui serait un mensonge.
// ============================================================================

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Ce à quoi une personne a droit.
enum NiveauPremium {
  /// Rien de débloqué.
  aucun,

  /// Le pack : les icônes et les fonds premium.
  pack,

  /// Droplet Pro : le pack, plus le badge et ce qui viendra ensuite.
  pro;

  /// Pro contient le pack. L'inverse est faux.
  bool get donneAccesAuPack => this != NiveauPremium.aucun;
  bool get estPro => this == NiveauPremium.pro;
}

class PremiumService {
  PremiumService._();

  /// La clé PUBLIQUE de signature des licences.
  ///
  /// Elle ne permet que de vérifier. La clé privée correspondante vit
  /// hors du dépôt (`~/.droplet-keys/licence.key`) et ne doit jamais y
  /// entrer — voir `tool/licence.dart`.
  static const String _clePubliqueLivree =
      'Ua6tUtYLSFxEMbHHIrEXpRdBR8+AwzM11P+cN1u3QLo=';

  /// Remplace la clé publique — RÉSERVÉ AUX TESTS.
  ///
  /// ⚠️ Ce point d'entrée n'affaiblit rien, et il faut comprendre
  /// pourquoi avant de s'en inquiéter : il ne permet que de FOURNIR une
  /// clé de vérification. Pour s'en servir dans le but de contourner le
  /// paiement, il faudrait déjà pouvoir exécuter du code dans
  /// l'application — c'est-à-dire l'avoir modifiée, auquel cas on
  /// supprimerait simplement la vérification, ce qui est plus simple.
  ///
  /// Il existe parce que la vraie clé privée vit hors du dépôt : sans
  /// lui, aucun test ne pourrait fabriquer de licence valable, et toute
  /// la sécurité de ce fichier ne serait vérifiée par rien.
  @visibleForTesting
  static String? clePubliqueDeTest;

  static String get _clePublique => clePubliqueDeTest ?? _clePubliqueLivree;

  /// Le préfixe de format. Signé avec la charge utile, pour qu'une
  /// licence d'un futur format ne puisse pas être rejouée dans celui-ci.
  static const String _prefixe = 'DROP1';

  static const _coffre = FlutterSecureStorage();
  static const String _cle = 'licence_droplet';

  static final _algo = Ed25519();

  static NiveauPremium _niveau = NiveauPremium.aucun;

  /// Ce à quoi cet appareil a droit, ici et maintenant.
  static NiveauPremium get niveau => _niveau;

  /// L'identifiant à communiquer pour obtenir une licence.
  ///
  /// Seize caractères tirés de l'identité de l'appareil, présentés par
  /// groupes de quatre : c'est fait pour être dicté au téléphone ou
  /// recopié dans un message sans se tromper.
  static String codeAppareil(String identite) {
    final net = identite.replaceAll(RegExp(r'[^0-9a-fA-F]'), '').toLowerCase();
    final seize = net.length >= 16 ? net.substring(0, 16) : net.padRight(16, '0');
    return '${seize.substring(0, 4)}-${seize.substring(4, 8)}-'
        '${seize.substring(8, 12)}-${seize.substring(12, 16)}';
  }

  /// À appeler au démarrage : relit la licence enregistrée et la
  /// REVÉRIFIE. Voir la note en tête sur le stockage.
  static Future<void> charger(String identite) async {
    try {
      final code = await _coffre.read(key: _cle);
      if (code == null) return;
      final n = await verifier(code, identite);
      _niveau = n ?? NiveauPremium.aucun;
      if (n == null) {
        // Licence devenue invalide (identité réinitialisée, stockage
        // trafiqué) : on la retire plutôt que de la revérifier en vain à
        // chaque lancement.
        await _coffre.delete(key: _cle);
      }
    } catch (e) {
      debugPrint('[Premium] lecture impossible: $e');
      _niveau = NiveauPremium.aucun;
    }
  }

  /// Vérifie un code SANS l'enregistrer. Renvoie `null` s'il est invalide.
  ///
  /// Les trois raisons de rejet — format, appareil, signature — sont
  /// délibérément indistinguables de l'extérieur : `null` dans tous les
  /// cas. Dire « bonne signature mais mauvais appareil » renseignerait
  /// gratuitement quelqu'un qui cherche à contourner.
  static Future<NiveauPremium?> verifier(String code, String identite) async {
    try {
      final propre = code.trim().replaceAll(RegExp(r'\s+'), '');
      final parts = propre.split('.');
      if (parts.length != 3 || parts[0] != _prefixe) return null;

      final charge = jsonDecode(
        utf8.decode(base64Url.decode(base64.normalize(parts[1]))),
      ) as Map<String, dynamic>;

      // ⚠️ L'APPAREIL D'ABORD. Une licence signée pour quelqu'un d'autre
      // est parfaitement valable — elle ne vaut simplement pas ici.
      final attendu = codeAppareil(identite).replaceAll('-', '');
      if (charge['d'] != attendu) return null;

      final signature = Signature(
        base64Url.decode(base64.normalize(parts[2])),
        publicKey: SimplePublicKey(
          base64Decode(_clePublique),
          type: KeyPairType.ed25519,
        ),
      );
      final valide = await _algo.verify(
        utf8.encode('$_prefixe.${parts[1]}'),
        signature: signature,
      );
      if (!valide) return null;

      return switch (charge['k']) {
        'pack' => NiveauPremium.pack,
        'pro' => NiveauPremium.pro,
        _ => null,
      };
    } catch (e) {
      // Base64 tordu, JSON invalide, champ manquant : tout finit ici, et
      // tout vaut « non ».
      debugPrint('[Premium] licence rejetée: $e');
      return null;
    }
  }

  /// Vérifie puis ENREGISTRE. Renvoie le niveau obtenu, ou `null`.
  static Future<NiveauPremium?> appliquer(String code, String identite) async {
    final n = await verifier(code, identite);
    if (n == null) return null;
    // On garde le code, pas le verdict. Voir la note en tête.
    await _coffre.write(key: _cle, value: code.trim());
    _niveau = n;
    return n;
  }

  /// Retire la licence de cet appareil.
  static Future<void> oublier() async {
    await _coffre.delete(key: _cle);
    _niveau = NiveauPremium.aucun;
  }
}
