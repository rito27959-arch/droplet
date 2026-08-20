// ============================================================================
// CE QUE CE TEST PROTÈGE
// ----------------------------------------------------------------------------
// LE PIRE DÉFAUT POSSIBLE DE TOUT CE SYSTÈME : « j'ai payé et ça ne
// marche pas ».
//
// Le format d'une licence est écrit à TROIS endroits qui ne partagent
// aucun code :
//
//   • `tool/licence.dart`            — la délivrance à la main
//   • `serveur/index.js`             — la délivrance automatique
//   • `lib/core/services/premium_service.dart` — la vérification
//
// Rien dans le compilateur ne les tient d'accord. Un champ renommé, un
// préfixe changé, un `=` de bourrage base64 oublié d'un côté et pas de
// l'autre, et l'application refuse des licences parfaitement payées.
// Le symptôme apparaît chez l'utilisateur, après le débit, et il n'y a
// pas pire moment pour découvrir une régression.
//
// Ce test signe une licence avec l'OUTIL RÉEL et la fait vérifier par le
// CODE RÉEL de l'application — clé publique livrée comprise, sans
// substitution. C'est le seul contrôle qui prouve que les deux moitiés
// se parlent.
//
// ⚠️ IL SE SAUTE TOUT SEUL SI LA CLÉ PRIVÉE EST ABSENTE. Elle vit dans
// `~/.droplet-keys/`, hors du dépôt : sur une machine d'intégration
// continue, ou chez quelqu'un qui vient de cloner le projet, il n'y a
// rien à signer. Échouer là-dessus ferait passer pour cassé un projet
// qui va très bien.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:droplet/core/services/premium_service.dart';

/// Une identité d'appareil dont le code abrégé vaut a1b2-c3d4-e5f6-0718.
const String _identite =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

File get _cle =>
    File('${Platform.environment['HOME']}/.droplet-keys/licence.key');

void main() {
  final cleDisponible = _cle.existsSync();

  test('une licence délivrée par tool/licence.dart est acceptée par '
      'l\'application', () async {
    final code = PremiumService.codeAppareil(_identite);
    expect(code, 'a1b2-c3d4-e5f6-0718',
        reason: 'le code d\'appareil sert d\'entrée à l\'outil : s\'il '
            'change, toutes les licences déjà délivrées deviennent '
            'caduques');

    final r = await Process.run(
      'dart',
      ['run', 'tool/licence.dart', 'signer', code, 'pro'],
      workingDirectory: Directory.current.path,
    );
    expect(r.exitCode, 0, reason: 'l\'outil a échoué : ${r.stderr}');

    // La licence est la seule ligne qui commence par le préfixe.
    final licence = const LineSplitter()
        .convert(r.stdout as String)
        .map((l) => l.trim())
        .firstWhere((l) => l.startsWith('DROP1.'), orElse: () => '');
    expect(licence, isNotEmpty,
        reason: 'aucune licence trouvée dans la sortie de l\'outil');

    // ⚠️ AUCUNE SUBSTITUTION DE CLÉ ICI : on vérifie contre la clé
    // publique réellement livrée dans l'application. C'est tout
    // l'intérêt — un test qui injecterait sa propre clé passerait même
    // si celle de l'app était fausse.
    expect(PremiumService.clePubliqueDeTest, isNull);

    expect(await PremiumService.verifier(licence, _identite),
        NiveauPremium.pro);

    // Et la propriété centrale tient aussi sur une licence réelle.
    const autre =
        'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100';
    expect(await PremiumService.verifier(licence, autre), isNull,
        reason: 'une licence réelle ne doit pas davantage voyager d\'un '
            'téléphone à l\'autre');
  },
      skip: cleDisponible
          ? false
          : 'clé privée absente (~/.droplet-keys/licence.key) — normal '
              'hors de la machine de publication',
      timeout: const Timeout(Duration(minutes: 2)));

  test('« repondre » extrait le code d\'un message et signe correctement',
      () async {
    // ⚠️ CE CHEMIN EST CELUI QU'ON EMPRUNTE TOUS LES JOURS.
    //
    // Tant que les licences sont délivrées à la main, `repondre` est la
    // commande réellement utilisée : on colle le message reçu, on
    // renvoie la réponse. Elle extrait le code au lieu de le faire
    // recopier — et c'est précisément la faute qu'elle évite qui
    // justifie ce test : un code de seize caractères hexadécimaux
    // retapé avec deux caractères intervertis produit une licence
    // parfaitement valable et parfaitement inutile, dont le symptôme
    // n'apparaît que chez quelqu'un qui vient de payer.
    final code = PremiumService.codeAppareil(_identite);
    final message = 'Bonjour, je viens de payer pour Droplet.\n\n'
        'Offre : Droplet Pro\n'
        'Montant : 1000 F\n'
        'Code appareil : $code\n\n'
        '(je joins la capture du paiement)';

    final proc = await Process.start(
      'dart',
      ['run', 'tool/licence.dart', 'repondre'],
      workingDirectory: Directory.current.path,
    );
    proc.stdin.write(message);
    await proc.stdin.close();
    final sortie = await proc.stdout.transform(utf8.decoder).join();
    expect(await proc.exitCode, 0);

    final licence = const LineSplitter()
        .convert(sortie)
        .map((l) => l.trim())
        .firstWhere((l) => l.startsWith('DROP1.'), orElse: () => '');
    expect(licence, isNotEmpty, reason: 'aucune licence dans la réponse');

    expect(PremiumService.clePubliqueDeTest, isNull);
    expect(await PremiumService.verifier(licence, _identite),
        NiveauPremium.pro,
        reason: 'l\'offre doit être déduite du message — « Droplet Pro » '
            'et 1000 F désignent tous deux Pro');
  },
      skip: cleDisponible
          ? false
          : 'clé privée absente — normal hors de la machine de publication',
      timeout: const Timeout(Duration(minutes: 2)));

  // ══════════════════════════════════════════════════════════════
  //  LE SERVEUR
  // ══════════════════════════════════════════════════════════════

  test('une licence signée par le code du Worker est acceptée par '
      'l\'application', () async {
    // ⚠️ C'EST LE CONTRÔLE LE PLUS UTILE DE TOUT LE PROJET DE PAIEMENT.
    //
    // Le Worker tourne en JavaScript sur Cloudflare, l'application en
    // Dart sur Android. Ils ne partagent AUCUNE ligne de code, et la
    // signature Ed25519 est l'endroit précis où deux plateformes peuvent
    // se croire d'accord sans l'être : nom d'algorithme, forme de la clé
    // importée, bourrage base64. Chacune de ces divergences produit une
    // licence d'apparence normale que l'application refuse — et le
    // symptôme apparaît chez quelqu'un qui vient de payer.
    //
    // On fait donc signer par le VRAI code du Worker (Node embarque la
    // même API WebCrypto que Cloudflare) et vérifier par le VRAI code de
    // l'application.
    final code = PremiumService.codeAppareil(_identite);
    final r = await Process.run(
      'node',
      ['serveur/verifier_signature.mjs', code, 'pack'],
      workingDirectory: Directory.current.path,
    );
    expect(r.exitCode, 0, reason: 'le Worker a échoué : ${r.stderr}');

    final licence = const LineSplitter()
        .convert(r.stdout as String)
        .map((l) => l.trim())
        .firstWhere((l) => l.startsWith('DROP1.'), orElse: () => '');
    expect(licence, isNotEmpty);

    expect(PremiumService.clePubliqueDeTest, isNull);
    expect(await PremiumService.verifier(licence, _identite),
        NiveauPremium.pack,
        reason: 'le Worker et l\'application doivent produire et lire le '
            'MÊME format — sinon on encaisse sans débloquer');
  },
      skip: cleDisponible
          ? false
          : 'secrets du Worker absents — normal hors de la machine de '
              'publication',
      timeout: const Timeout(Duration(minutes: 2)));
}
