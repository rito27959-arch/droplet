import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:droplet/main.dart';

void main() {
  testWidgets('Droplet app builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: DropletApp()),
    );
    await tester.pump();
    expect(find.byType(DropletApp), findsOneWidget);
    // Laisse l'écran de démarrage s'afficher puis céder la place à
    // l'onboarding (1,35 s de pose + 0,32 s de fondu de sortie).
    await tester.pump(const Duration(milliseconds: 2500));

    // L'onboarding vient d'apparaître, et ses lignes de fonctionnalité
    // entrent l'une APRÈS l'autre — le dernier départ est décalé d'une
    // demi-seconde. On laisse cette séquence se terminer : démonter au
    // milieu laisserait un minuteur d'animation en vol, ce que le
    // moteur de test signale comme une fuite.
    await tester.pump(const Duration(milliseconds: 1500));

    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 100));
  });
}
