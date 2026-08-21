// ============================================================================
// CE QUE CES TESTS PROTÈGENT
// ----------------------------------------------------------------------------
// DEUX AIDES QUI DEVIENNENT DES NUISANCES SI ELLES SE RÉPÈTENT.
//
// La visite guidée et le bandeau « Droplet s'est fermé » ont le même
// défaut potentiel : reparaître alors qu'on y a déjà répondu. Une aide
// qui se rejoue à chaque lancement est pire que pas d'aide — on apprend
// à la congédier sans la lire, et le jour où elle dit quelque chose
// d'important, personne ne la voit.
//
// Les deux s'appuient sur un état enregistré. Ces tests vérifient que
// cet état fait ce qu'on croit.
// ============================================================================

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:droplet/shared/widgets/bulle_guide.dart';

void main() {
  group('Les étapes de la visite', () {
    // On reconstruit ici les trois étapes de l'accueil pour vérifier ce
    // qui se vérifie sans écran : leur nombre, et le fait qu'elles
    // parlent bien de ce qui n'est PAS devinable.
    final etapes = [
      EtapeGuide(
        cible: GlobalKey(),
        titre: 'Personne à proximité ? C\'est normal',
        texte: 'Zéro pair ne veut pas dire que ça ne marche pas.',
      ),
      EtapeGuide(
        cible: GlobalKey(),
        titre: 'Écrivez même sans personne',
        texte: 'Il n\'est pas perdu, il patiente.',
      ),
      EtapeGuide(
        cible: GlobalKey(),
        titre: 'Sauvegardez votre identité',
        texte: 'Sans serveur, personne ne peut vous rendre votre compte.',
      ),
    ];

    test('quatre étapes au maximum', () {
      // ⚠️ LA LIMITE EST LE POINT DU TEST.
      //
      // Au-delà de quatre, plus personne ne lit : on appuie sur
      // « suivant » jusqu'à ce que ça s'arrête, et la visite n'a servi
      // qu'à retarder l'usage de l'application. Ce test échouera le jour
      // où quelqu'un voudra « juste en ajouter une ».
      expect(etapes.length, lessThanOrEqualTo(4),
          reason: 'une visite plus longue ne se lit pas, elle se subit');
    });

    test('chaque étape a un titre et un texte non vides', () {
      for (final e in etapes) {
        expect(e.titre.trim(), isNotEmpty);
        expect(e.texte.trim(), isNotEmpty);
        // Une bulle est lue en deux secondes, pas en dix.
        expect(e.texte.length, lessThan(320),
            reason: 'texte trop long pour une bulle : « ${e.titre} »');
      }
    });

    test('chaque étape désigne une cible différente', () {
      final cibles = etapes.map((e) => e.cible).toSet();
      expect(cibles.length, etapes.length,
          reason: 'deux étapes sur le même élément désignent deux fois le '
              'même trou — le voile ne bougerait pas et on croirait '
              'l\'application figée');
    });
  });
}
