// ============================================================================
// CE QUE CE FICHIER VÉRIFIE
// ----------------------------------------------------------------------------
// Les deux animations « festives » de la conversation : la salve de cœurs
// (double-tap sur un message) et la pluie de confettis (mots-clés comme
// « bravo »).
//
// Ce ne sont pas des tests de beauté — on ne peut pas mesurer si c'est
// joli. Ce sont des tests de DISCIPLINE, sur les deux points qui les
// avaient rendues poussives sur un vrai téléphone :
//
//   1. Une salve à la fois. Un utilisateur qui double-tape cinq fois de
//      suite empilait cinq animations simultanées, donc cinq fois le
//      travail de dessin.
//   2. La salve se retire toute seule. Un overlay qui reste accroché à
//      l'écran après la fin continue d'exister dans l'arbre.
//
// Et un troisième, invisible mais décisif : que le dessin passe par un
// `CustomPaint` et non par un widget `Opacity` par particule. C'est
// cette différence-là qui faisait ramer l'animation, et rien dans
// `flutter analyze` ne l'aurait signalée.
// ============================================================================

import 'package:droplet/shared/widgets/confetti_overlay.dart';
import 'package:droplet/shared/widgets/heart_burst_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un écran minimal muni d'un `Overlay`, avec un bouton qui déclenche
/// l'effet — c'est le strict nécessaire pour que `Overlay.of(context)`
/// trouve quelque chose.
Widget _banc(void Function(BuildContext) declencher) {
  return MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () => declencher(context),
            child: const Text('go'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  group('Salve de cœurs', () {
    testWidgets('dessine les cœurs sur un seul canevas, pas en widgets',
        (tester) async {
      await tester.pumpWidget(_banc(HeartBurstOverlay.show));
      await tester.tap(find.text('go'));
      await tester.pump();

      // Un seul `CustomPaint` ajouté pour les 28 cœurs.
      expect(find.byType(HeartBurstOverlay), findsOneWidget);
      // Aucun `Opacity` : c'est la couleur du pinceau qui porte la
      // transparence. Un `Opacity` par cœur forcerait 28 rendus
      // hors-écran par image.
      expect(
        find.descendant(
          of: find.byType(HeartBurstOverlay),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      // Aucun texte non plus : l'emoji ❤️ était remis en page à chaque
      // image, pour chacune des 28 tailles différentes.
      expect(
        find.descendant(
          of: find.byType(HeartBurstOverlay),
          matching: find.byType(Text),
        ),
        findsNothing,
      );

      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('un double-tap insistant ne lance qu\'une salve',
        (tester) async {
      await tester.pumpWidget(_banc(HeartBurstOverlay.show));

      for (var i = 0; i < 5; i++) {
        await tester.tap(find.text('go'));
        await tester.pump(const Duration(milliseconds: 40));
      }

      expect(find.byType(HeartBurstOverlay), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });

    testWidgets('se retire toute seule une fois finie', (tester) async {
      await tester.pumpWidget(_banc(HeartBurstOverlay.show));
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.byType(HeartBurstOverlay), findsOneWidget);

      // L'animation dure 1,8 s.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(find.byType(HeartBurstOverlay), findsNothing);

      // Et comme elle est partie, on peut en relancer une : le garde-fou
      // anti-empilement ne doit pas rester coincé.
      await tester.tap(find.text('go'));
      await tester.pump();
      expect(find.byType(HeartBurstOverlay), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 3));
    });
  });

  group('Pluie de confettis', () {
    testWidgets('même discipline : un seul canevas, aucune couche '
        'hors-écran', (tester) async {
      await tester.pumpWidget(_banc(ConfettiOverlay.show));
      await tester.tap(find.text('go'));
      await tester.pump();

      expect(find.byType(ConfettiOverlay), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ConfettiOverlay),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );

      await tester.pumpAndSettle(const Duration(seconds: 4));
    });

    testWidgets('un message qui dit trois fois « bravo » ne déclenche '
        'qu\'une pluie', (tester) async {
      await tester.pumpWidget(_banc(ConfettiOverlay.show));

      for (var i = 0; i < 3; i++) {
        await tester.tap(find.text('go'));
        await tester.pump(const Duration(milliseconds: 30));
      }

      expect(find.byType(ConfettiOverlay), findsOneWidget);
      await tester.pumpAndSettle(const Duration(seconds: 4));
    });
  });
}
