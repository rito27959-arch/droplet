import 'package:droplet_id/droplet_id.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('le bouton affiche le texte et répond au toucher', (t) async {
    var touche = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: DropletIdBouton(langue: 'fr', onPressed: () => touche++)))));
    expect(find.text('Continuer avec Droplet ID'), findsOneWidget);
    await t.tap(find.byType(DropletIdBouton));
    expect(touche, 1);
  });

  testWidgets('en anglais, et pas de toucher pendant le chargement', (t) async {
    var touche = 0;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: DropletIdBouton(langue: 'en', chargement: true, onPressed: () => touche++))));
    expect(find.text('Continue with Droplet ID'), findsOneWidget);
    await t.tap(find.byType(DropletIdBouton));
    expect(touche, 0);
  });

  test('openid est toujours demandé', () {
    final did = DropletId(clientId: 'x', redirectUri: 'cm.x:/r', portees: const ['profile']);
    expect(did.portees, ['openid', 'profile']);
  });
}
