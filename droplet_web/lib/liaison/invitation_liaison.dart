// L'INVITATION À LIER CE NAVIGATEUR — ce que contient le code QR.
//
// Le navigateur fabrique ici SA PROPRE paire de clés X25519 : c'est le
// début de son identité d'appareil associé (voir l'étude « Droplet Web »).
// Le téléphone scanne le code, signe un certificat pour cette clé publique
// et le publie dans l'annuaire ; la clé privée, elle, ne quitte jamais le
// navigateur.
//
// Le code se renouvelle toutes les 60 secondes, avec une nouvelle paire et
// un nouveau canal : une photo du code prise par quelqu'un d'autre ne sert
// plus à rien une minute plus tard.
//
// ⚠️ Étape 2 du plan : la clé sera gardée, non exportable, dans le
// navigateur (WebCrypto + IndexedDB) quand « Rester connecté » est coché.
// Pour l'instant elle vit en mémoire, le temps de la page.
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:web/web.dart' as web;

class InvitationLiaison {
  InvitationLiaison._({
    required this.cles,
    required this.clePublique,
    required this.canal,
    required this.nomAppareil,
  });

  /// La paire de clés de ce navigateur.
  final SimpleKeyPair cles;

  /// La clé publique, en base64url sans remplissage.
  final String clePublique;

  /// L'identifiant du canal où le téléphone répondra (16 octets aléatoires).
  final String canal;

  /// Le nom que le téléphone affichera dans « Appareils liés ».
  final String nomAppareil;

  /// Ce que porte le code QR. Le préfixe `droplet_lien` permet au scanner
  /// de l'app de reconnaître une liaison, et pas un contact.
  String get contenuQr => jsonEncode({
        'type': 'droplet_lien',
        'v': 1,
        'canal': canal,
        'cle': clePublique,
        'nom': nomAppareil,
      });

  static Future<InvitationLiaison> nouvelle() async {
    final cles = await X25519().newKeyPair();
    final publique = await cles.extractPublicKey();
    final hasard = Random.secure();
    final canal = List<int>.generate(16, (_) => hasard.nextInt(256));
    return InvitationLiaison._(
      cles: cles,
      clePublique: _b64(publique.bytes),
      canal: _b64(canal),
      nomAppareil: nomDuNavigateur(),
    );
  }

  static String _b64(List<int> octets) =>
      base64Url.encode(octets).replaceAll('=', '');

  /// « Chrome · macOS », lu dans l'identité du navigateur. Approximatif par
  /// nature, mais c'est ce qui permet de reconnaître ses appareils.
  static String nomDuNavigateur() {
    final ua = web.window.navigator.userAgent;
    final navigateur = ua.contains('Edg/')
        ? 'Edge'
        : ua.contains('OPR/')
            ? 'Opera'
            : ua.contains('Firefox/')
                ? 'Firefox'
                : ua.contains('Chrome/')
                    ? 'Chrome'
                    : ua.contains('Safari/')
                        ? 'Safari'
                        : 'Navigateur';
    final systeme = ua.contains('Windows')
        ? 'Windows'
        : ua.contains('CrOS')
            ? 'ChromeOS'
            : ua.contains('Android')
                ? 'Android'
                : (ua.contains('iPhone') || ua.contains('iPad'))
                    ? 'iOS'
                    : ua.contains('Mac OS')
                        ? 'macOS'
                        : ua.contains('Linux')
                            ? 'Linux'
                            : '';
    return systeme.isEmpty ? navigateur : '$navigateur · $systeme';
  }
}
