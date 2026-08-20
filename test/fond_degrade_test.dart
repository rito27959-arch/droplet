// ============================================================================
// CE QUE CE FICHIER VÉRIFIE
// ----------------------------------------------------------------------------
// Le fond de discussion animé, repris de l'algorithme de Telegram.
//
// On ne teste pas si c'est joli — ça ne se mesure pas. On teste les trois
// propriétés dont dépend l'effet :
//
//   1. Le fond BOUGE quand on envoie un message, et seulement à ce
//      moment-là. C'est tout le principe : le mouvement répond au geste.
//   2. Chaque palette existe en clair ET en sombre. Une palette sombre
//      affichée derrière du texte foncé rendrait la conversation
//      illisible — c'est le risque numéro un de cet effet.
//   3. L'option « Aucun » est reconnue comme telle et ne renvoie aucune
//      palette : rien ne doit être calculé quand l'utilisateur a coupé
//      l'effet.
// ============================================================================

import 'package:droplet/core/providers/chat_background_provider.dart';
import 'package:droplet/features/chat/telegram_gradient_background.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Palettes', () {
    test('chaque palette sombre a son équivalent clair', () {
      for (final cle in TelegramGradientPalettes.etiquettes.keys) {
        expect(TelegramGradientPalettes.pour(cle, sombre: true), isNotNull,
            reason: 'palette sombre manquante pour « $cle »');
        expect(TelegramGradientPalettes.pour(cle, sombre: false), isNotNull,
            reason: 'palette claire manquante pour « $cle »');
      }
    });

    test('toutes les palettes ont bien quatre couleurs', () {
      // Quatre centres de couleur pour huit positions : chaque centre
      // avance de deux crans. Un nombre différent casserait la
      // répartition régulière dans l'anneau.
      for (final cle in TelegramGradientPalettes.etiquettes.keys) {
        for (final sombre in [true, false]) {
          expect(TelegramGradientPalettes.pour(cle, sombre: sombre)!.length, 4,
              reason: '« $cle » (sombre: $sombre)');
        }
      }
    });

    test('les palettes claires sont réellement claires', () {
      // Le vrai risque de cet effet : un fond trop foncé derrière le
      // texte du mode clair. On exige une luminance élevée.
      for (final cle in TelegramGradientPalettes.etiquettes.keys) {
        for (final c in TelegramGradientPalettes.pour(cle, sombre: false)!) {
          expect(c.computeLuminance(), greaterThan(0.5),
              reason: '« $cle » contient une couleur trop foncée : $c');
        }
      }
      // Et symétriquement pour le mode sombre.
      for (final cle in TelegramGradientPalettes.etiquettes.keys) {
        for (final c in TelegramGradientPalettes.pour(cle, sombre: true)!) {
          expect(c.computeLuminance(), lessThan(0.2),
              reason: '« $cle » contient une couleur trop claire : $c');
        }
      }
    });

    test('« Aucun » ne correspond à aucune palette', () {
      expect(TelegramGradientPalettes.pour(kFondAucun, sombre: true), isNull);
      expect(TelegramGradientPalettes.pour(kFondAucun, sombre: false), isNull);
      // Une valeur écrite par une version antérieure de l'app ne doit pas
      // non plus faire tomber l'écran.
      expect(TelegramGradientPalettes.pour('inconnue', sombre: true), isNull);
    });
  });

  group('Rotation du fond', () {
    testWidgets('le dégradé se redessine quand le compteur avance',
        (tester) async {
      var tick = 0;
      late StateSetter regler;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              regler = setState;
              return TelegramGradientBackground(
                tick: tick,
                couleurs: TelegramGradientPalettes.mesh,
              );
            },
          ),
        ),
      );
      // ⚠️ PLUSIEURS IMAGES, PAS UNE SEULE.
      //
      // Le dégradé est calculé puis remis au moteur graphique par
      // `decodeImageFromPixels`, dont le rappel est asynchrone et ne suit
      // PAS l'horloge simulée des tests. Une seule image pompée laissait
      // parfois ce rappel en vol : il déclenchait un `setState` juste
      // après l'assertion, et le test échouait une fois sur plusieurs
      // sans que rien n'ait changé dans le code. Un test instable est
      // pire qu'un test absent — on finit par ignorer ses échecs.
      await tester.pumpAndSettle();

      final etat = tester.state<State>(
        find.byType(TelegramGradientBackground),
      );

      // Au repos, aucune animation en cours.
      expect(tester.hasRunningAnimations, isFalse);

      // Un message envoyé → le compteur avance → le fond se met en
      // mouvement.
      regler(() => tick = 1);
      await tester.pump();
      expect(tester.hasRunningAnimations, isTrue,
          reason: 'le fond doit bouger quand un message part');

      // Et il s'arrête tout seul.
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
      expect(etat.mounted, isTrue);
    });

    testWidgets('un fond au repos ne consomme rien', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: TelegramGradientBackground(
            tick: 3,
            couleurs: TelegramGradientPalettes.foret,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Reconstruire avec le MÊME compteur ne doit rien relancer : le
      // fond ne bouge qu'à l'envoi d'un message, pas à chaque `build()`
      // de l'écran de discussion (qui a lieu à chaque frappe au clavier).
      await tester.pumpWidget(
        const MaterialApp(
          home: TelegramGradientBackground(
            tick: 3,
            couleurs: TelegramGradientPalettes.foret,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.hasRunningAnimations, isFalse);
    });
  });
}
