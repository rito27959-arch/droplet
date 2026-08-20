// ============================================================================
// CE QUE CES TESTS PROTÈGENT
// ----------------------------------------------------------------------------
// LA CHAÎNE USSD QUI DÉCLENCHE UN TRANSFERT D'ARGENT.
//
// C'est le seul endroit de Droplet où une erreur de caractère fait
// partir de l'argent au mauvais endroit, définitivement. Pas d'écran
// cassé, pas de message d'erreur : le transfert réussit, simplement pas
// vers le bon compte.
//
// Trois choses sont figées ici :
//
//   1. le numéro composé est CELUI DE LA CONSTANTE, jamais une copie —
//      c'est ce qui garantit qu'un changement de numéro Mobile Money ne
//      laisse pas une chaîne pointant vers l'ancien ;
//   2. le montant composé correspond à l'offre — 500 pour le pack,
//      1000 pour Pro, jamais l'inverse ;
//   3. Orange n'a PAS de chaîne : aucune n'a été vérifiée sur une vraie
//      ligne, et en deviner une reviendrait à parier avec l'argent de
//      quelqu'un d'autre.
// ============================================================================

import 'package:flutter_test/flutter_test.dart';

import 'package:droplet/features/premium/premium_screen.dart';

Operateur get mtn => kOperateurs.firstWhere((o) => o.nom.contains('MTN'));
Operateur get orange => kOperateurs.firstWhere((o) => o.nom.contains('Orange'));

void main() {
  group('Le raccourci MTN', () {
    test('compose le numéro de la constante, pas une copie', () {
      final compose = mtn.codePour(kPrixPack);

      expect(compose, contains(mtn.numeroBrut),
          reason: 'le numéro composé doit venir de kNumeroMtn');
      expect(compose, contains('678963221'),
          reason: 'si ce numéro change, ce test doit être mis à jour '
              'DÉLIBÉRÉMENT — c\'est là tout son intérêt');
      expect(compose, isNot(contains('{numero}')),
          reason: 'le marqueur doit être remplacé, pas composé tel quel');
    });

    test('compose le bon montant selon l\'offre', () {
      expect(mtn.codePour(kPrixPack), '*126*1*1*678963221*500#');
      expect(mtn.codePour(kPrixPro), '*126*1*1*678963221*1000#');
    });

    test('ne laisse aucun marqueur non remplacé', () {
      for (final montant in [kPrixPack, kPrixPro]) {
        final compose = mtn.codePour(montant);
        expect(compose, isNot(contains('{')),
            reason: 'un marqueur oublié serait composé littéralement et '
                'le menu répondrait par une erreur incompréhensible');
        expect(compose, matches(RegExp(r'^\*[0-9*]+#$')),
            reason: 'une chaîne USSD ne contient que des chiffres, des '
                'étoiles, et se termine par un dièse');
      }
    });

    test('annonce que tout est prérempli', () {
      expect(mtn.toutEstRempli, isTrue,
          reason: 'l\'écran dit « il ne reste que votre code secret » — '
              'ce doit être vrai');
    });
  });

  group('Orange', () {
    test('ouvre le menu, sans chaîne devinée', () {
      // ⚠️ CE TEST DOIT ÉCHOUER LE JOUR OÙ QUELQU'UN AJOUTE UNE CHAÎNE
      // ORANGE SANS L'AVOIR ESSAYÉE.
      //
      // L'ordre des menus Mobile Money n'est documenté nulle part. Une
      // chaîne écrite « par analogie » avec celle de MTN a toutes les
      // chances de tomber sur une autre entrée — dans un menu qui
      // déplace de l'argent.
      expect(orange.raccourci, isEmpty,
          reason: 'aucune chaîne Orange n\'a été vérifiée sur une vraie '
              'ligne. Si vous en ajoutez une, essayez-la d\'abord avec '
              'votre propre argent, puis mettez ce test à jour.');
      expect(orange.codePour(kPrixPack), '#150#');
      expect(orange.toutEstRempli, isFalse,
          reason: 'l\'écran doit dire qu\'il faut saisir le numéro et le '
              'montant');
    });
  });

  group('Les deux opérateurs', () {
    test('portent des numéros différents et non vides', () {
      expect(mtn.numeroBrut, isNotEmpty);
      expect(orange.numeroBrut, isNotEmpty);
      expect(mtn.numeroBrut, isNot(orange.numeroBrut));
      for (final o in kOperateurs) {
        expect(o.numeroBrut.length, 9,
            reason: 'un numéro camerounais fait neuf chiffres — '
                '« ${o.nom} » en a ${o.numeroBrut.length}');
        expect(o.numeroBrut, startsWith('6'));
      }
    });

    test('les prix restent ceux annoncés', () {
      // Le site, l'écran et les chaînes USSD répètent ces deux nombres.
      expect(kPrixPack, 500);
      expect(kPrixPro, 1000);
    });
  });
}
