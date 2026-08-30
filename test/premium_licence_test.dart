// ============================================================================
// CE QUE CES TESTS PROTÈGENT
// ----------------------------------------------------------------------------
// Le système de licences est la seule chose qui sépare « a payé » de
// « n'a pas payé », et il n'a AUCUN serveur pour l'aider. Tout repose
// donc sur une signature — et une signature mal vérifiée est pire que
// pas de signature du tout, parce qu'elle donne l'illusion d'une
// protection.
//
// Ces tests vérifient les propriétés dans leur ordre d'importance :
//
//   1. une licence valable débloque bien ce pour quoi elle a été émise ;
//   2. **la même licence ne débloque RIEN sur un autre appareil** —
//      c'est la propriété qui rend le partage de code inutile, et donc
//      la seule qui compte vraiment à cette échelle ;
//   3. toute retouche de la charge utile invalide la licence, y compris
//      celle qui consisterait à changer « pack » en « pro » ;
//   4. une licence signée avec une AUTRE clé privée est rejetée — c'est
//      ce qui empêche quelqu'un de fabriquer les siennes ;
//   5. n'importe quoi en entrée est rejeté proprement, sans exception.
// ============================================================================

import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:droplet/core/services/premium_service.dart';

const String _prefixe = 'DROP1';

/// Une identité d'appareil plausible : Droplet utilise des empreintes
/// hexadécimales.
const String identiteAmina =
    'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';
const String identiteMichel =
    'ffeeddccbbaa99887766554433221100ffeeddccbbaa99887766554433221100';

/// Fabrique une licence exactement comme le fait `tool/licence.dart`.
Future<String> emettre({
  required SimpleKeyPair paire,
  required String identite,
  required String genre,
  Map<String, dynamic>? chargeForcee,
}) async {
  final appareil = PremiumService.codeAppareil(identite).replaceAll('-', '');
  final charge = jsonEncode(chargeForcee ??
      {
        'd': appareil,
        'k': genre,
        't': DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000,
      });
  final chargeB64 = base64Url.encode(utf8.encode(charge)).replaceAll('=', '');
  final signature = await Ed25519()
      .sign(utf8.encode('$_prefixe.$chargeB64'), keyPair: paire);
  final sigB64 = base64Url.encode(signature.bytes).replaceAll('=', '');
  return '$_prefixe.$chargeB64.$sigB64';
}

void main() {
  late SimpleKeyPair paire;
  late SimpleKeyPair autrePaire;

  setUp(() async {
    paire = await Ed25519().newKeyPair();
    autrePaire = await Ed25519().newKeyPair();
    PremiumService.clePubliqueDeTest =
        base64Encode((await paire.extractPublicKey()).bytes);
  });

  tearDown(() => PremiumService.clePubliqueDeTest = null);

  test('le code d\'appareil est stable et lisible', () {
    final a = PremiumService.codeAppareil(identiteAmina);
    expect(a, PremiumService.codeAppareil(identiteAmina),
        reason: 'un code qui change rendrait toute licence caduque');
    expect(a.replaceAll('-', '').length, 16);
    expect(a.split('-').length, 4,
        reason: 'les groupes de quatre servent à le dicter sans erreur');
  });

  test('une licence « pack » valable débloque le pack', () async {
    final code = await emettre(
        paire: paire, identite: identiteAmina, genre: 'pack');
    expect(await PremiumService.verifier(code, identiteAmina),
        NiveauPremium.pack);
  });

  test('une licence « pro » valable débloque Pro', () async {
    final code =
        await emettre(paire: paire, identite: identiteAmina, genre: 'pro');
    final n = await PremiumService.verifier(code, identiteAmina);
    expect(n, NiveauPremium.pro);
    expect(n!.estPro, isTrue);
    expect(n.donneAccesAuPack, isTrue,
        reason: 'Pro contient le pack, sinon l\'offre la plus chère '
            'donnerait moins que l\'autre');
  });

  test('LA PROPRIÉTÉ CENTRALE : la licence d\'Amina ne vaut rien '
      'chez Michel', () async {
    final code = await emettre(
        paire: paire, identite: identiteAmina, genre: 'pro');

    expect(await PremiumService.verifier(code, identiteAmina),
        NiveauPremium.pro);
    expect(await PremiumService.verifier(code, identiteMichel), isNull,
        reason: 'sans cela, un seul achat circulerait sur WhatsApp et '
            'débloquerait toute la ville');
  });

  test('on ne peut pas transformer un pack en Pro', () async {
    final code = await emettre(
        paire: paire, identite: identiteAmina, genre: 'pack');
    final parts = code.split('.');

    // On réécrit la charge utile en « pro », en gardant la signature.
    final charge = jsonDecode(
        utf8.decode(base64Url.decode(base64.normalize(parts[1]))))
      as Map<String, dynamic>;
    charge['k'] = 'pro';
    final falsifiee = base64Url
        .encode(utf8.encode(jsonEncode(charge)))
        .replaceAll('=', '');

    expect(
      await PremiumService.verifier(
          '${parts[0]}.$falsifiee.${parts[2]}', identiteAmina),
      isNull,
      reason: 'la signature couvre la charge : la retoucher la casse',
    );
  });

  test('une licence signée avec une autre clé est rejetée', () async {
    // Le cas de quelqu'un qui a compris le format et fabrique les
    // siennes — sans la clé privée, ça ne mène nulle part.
    final code = await emettre(
        paire: autrePaire, identite: identiteAmina, genre: 'pro');
    expect(await PremiumService.verifier(code, identiteAmina), isNull);
  });

  test('une signature retouchée est rejetée', () async {
    final code = await emettre(
        paire: paire, identite: identiteAmina, genre: 'pack');
    final parts = code.split('.');
    final sig = parts[2];
    // On change un seul caractère de la signature.
    final abime = '${sig.substring(0, sig.length - 1)}'
        '${sig.endsWith('A') ? 'B' : 'A'}';
    expect(
      await PremiumService.verifier(
          '${parts[0]}.${parts[1]}.$abime', identiteAmina),
      isNull,
    );
  });

  test('un genre inconnu ne débloque rien', () async {
    final code = await emettre(
      paire: paire,
      identite: identiteAmina,
      genre: 'peu importe',
      chargeForcee: {
        'd': PremiumService.codeAppareil(identiteAmina).replaceAll('-', ''),
        'k': 'illimite',
        't': 0,
      },
    );
    expect(await PremiumService.verifier(code, identiteAmina), isNull,
        reason: 'un genre non prévu doit valoir « rien », jamais « tout »');
  });

  test('n\'importe quoi en entrée est rejeté sans lever d\'exception',
      () async {
    for (final absurde in <String>[
      '',
      '   ',
      'DROP1',
      'DROP1.a.b',
      'DROP2.aaaa.bbbb',
      'pas du tout une licence',
      'DROP1..',
      'DROP1.!!!.???',
    ]) {
      expect(await PremiumService.verifier(absurde, identiteAmina), isNull,
          reason: 'entrée refusée attendue pour « $absurde »');
    }
  });

  test('les espaces autour du code sont tolérés', () async {
    // Un code collé depuis WhatsApp traîne souvent un saut de ligne.
    final code = await emettre(
        paire: paire, identite: identiteAmina, genre: 'pack');
    expect(await PremiumService.verifier('  $code\n', identiteAmina),
        NiveauPremium.pack);
  });

  test('une licence collée avec le texte WhatsApp est acceptée', () async {
    // Le cas réel : quelqu'un colle la réponse entière, pas juste la
    // ligne DROP1.x.y — il y a des tirets, des mots, des points.
    final code = await emettre(
        paire: paire, identite: identiteAmina, genre: 'pro');
    final texte = 'Merci ! Voici votre licence pour Droplet Pro.\n\n'
        '$code\n\n'
        'Dans Droplet : Réglages → Droplet Pro → collez-la '
        'dans « J\'ai reçu ma licence ».';
    expect(await PremiumService.verifier(texte, identiteAmina),
        NiveauPremium.pro);
  });

  test('la première licence dans un texte est extraite', () async {
    // Un texte avec du bruit avant et après.
    final code = await emettre(
        paire: paire, identite: identiteAmina, genre: 'pack');
    final texte = '---\n Merci !\nVoici votre licence :\n\n'
        '$code\n\n'
        'Elle ne fonctionne que sur votre téléphone.\n---';
    expect(await PremiumService.verifier(texte, identiteAmina),
        NiveauPremium.pack);
  });
}
