// ============================================================================
// CE QUE CE FICHIER VÉRIFIE
// ----------------------------------------------------------------------------
// QUE DROPLET EST UTILISABLE SANS VOIR L'ÉCRAN.
//
// C'est le seul lot de tests de ce projet qui vérifie quelque chose
// d'invisible : ce qu'un lecteur d'écran (VoiceOver sur iOS, TalkBack sur
// Android) ANNONCE. Rien de tout cela n'apparaît sur une capture, et
// `flutter analyze` n'en dit pas un mot — c'est précisément pour ça que
// l'application n'avait, jusqu'ici, pas un seul widget `Semantics`.
//
// ── Pourquoi ces trois propriétés, et pas d'autres ────────────────────
//
// Ce sont les trois qui font la différence entre « l'app parle » et
// « l'app est utilisable » :
//
//   1. Un bouton doit avoir un NOM. Une icône seule n'a aucun texte à
//      lire : sans libellé, le lecteur annonce « bouton », sans dire
//      lequel. Une barre d'outils devient une rangée d'inconnues.
//   2. Un onglet doit annoncer s'il est SÉLECTIONNÉ. La capsule bleue qui
//      le montre n'est d'aucun secours à qui ne la voit pas.
//   3. Une ligne de réglage doit se lire d'un SEUL tenant, sauf si elle
//      porte un interrupteur — auquel cas l'interrupteur doit rester
//      actionnable. C'est le piège classique : en regroupant tout pour
//      la lisibilité, on rend le réglage impossible à modifier.
// ============================================================================

import 'package:droplet/design_system/ouro_list.dart';
import 'package:droplet/design_system/ouro_pressable.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _banc(Widget enfant) => MaterialApp(
      home: Scaffold(body: Center(child: enfant)),
    );

void main() {
  group('Boutons', () {
    testWidgets('une icône seule annonce son nom', (tester) async {
      await tester.pumpWidget(_banc(
        OuroPressable(
          semantique: 'Appeler',
          onTap: () {},
          child: const Icon(Icons.phone),
        ),
      ));

      expect(
        tester.getSemantics(find.byType(OuroPressable)),
        matchesSemantics(
          label: 'Appeler',
          isButton: true,
          hasTapAction: true,
        ),
      );
    });

    testWidgets('sans libellé, le bouton reste activable', (tester) async {
      // Un bouton portant du texte n'a pas besoin de libellé : Flutter
      // lit son contenu. Ce qui compte, c'est qu'il soit ACTIONNABLE —
      // un `GestureDetector` nu ne l'est pas pour un lecteur d'écran.
      var touche = false;
      await tester.pumpWidget(_banc(
        OuroPressable(
          onTap: () => touche = true,
          child: const Text('Envoyer'),
        ),
      ));

      // ⚠️ On lit `getSemanticsData()` et non `node.label` : sur un nœud
      // FUSIONNÉ, l'étiquette des descendants n'est calculée qu'au moment
      // où l'on demande les données consolidées. `node.label` reste vide,
      // ce qui donne l'impression trompeuse que rien n'est annoncé.
      final donnees =
          tester.getSemantics(find.byType(OuroPressable)).getSemanticsData();
      // Le texte de l'enfant fait office de nom : pas besoin de libellé
      // explicite quand le bouton porte déjà des mots.
      expect(donnees.label, contains('Envoyer'));
      expect(donnees.flagsCollection.isButton, isTrue);

      // Et l'action doit RÉELLEMENT déclencher le bouton : un nœud qui
      // annonce une action sans la câbler serait pire que rien.
      final poignee = tester.ensureSemantics();
      await tester.tap(find.byType(OuroPressable));
      expect(touche, isTrue,
          reason: 'le lecteur d\'écran doit pouvoir déclencher le bouton');
      poignee.dispose();
    });
  });

  group('Lignes de réglage', () {
    testWidgets('se lisent d\'un seul tenant', (tester) async {
      await tester.pumpWidget(_banc(
        OuroListRow(
          title: 'Réseau mesh',
          subtitle: 'Pairs connectés et topologie',
          icon: Icons.wifi,
          onTap: () {},
        ),
      ));

      final noeud = tester.getSemantics(find.byType(OuroListRow));
      expect(noeud.label, 'Réseau mesh, Pairs connectés et topologie');
      expect(noeud.flagsCollection.isButton, isTrue);
    });

    testWidgets('la valeur affichée est annoncée elle aussi', (tester) async {
      await tester.pumpWidget(_banc(
        OuroListRow(
          title: 'Ma contribution',
          value: 'Relais',
          onTap: () {},
        ),
      ));

      expect(
        tester.getSemantics(find.byType(OuroListRow)).label,
        'Ma contribution, Relais',
      );
    });

    testWidgets('un interrupteur reste actionnable', (tester) async {
      // ⚠️ LA RÉGRESSION QUE CE TEST EMPÊCHE.
      //
      // Regrouper toute la ligne en un seul élément rend la lecture
      // agréable — mais masque l'interrupteur, qui devient impossible à
      // basculer sans voir l'écran. On aurait remplacé une gêne par une
      // exclusion.
      var actif = false;
      await tester.pumpWidget(_banc(
        OuroListRow(
          title: 'Relais en arrière-plan',
          onTap: () {},
          trailing: StatefulBuilder(
            builder: (context, setState) => Switch(
              value: actif,
              onChanged: (v) => setState(() => actif = v),
            ),
          ),
        ),
      ));

      expect(
        tester.getSemantics(find.byType(Switch)),
        matchesSemantics(
          isEnabled: true,
          hasEnabledState: true,
          hasToggledState: true,
          isFocusable: true,
          hasTapAction: true,
          hasFocusAction: true,
        ),
        reason: "l'interrupteur doit rester visible ET actionnable par le "
            "lecteur d'écran, même à l'intérieur d'une ligne regroupée",
      );
    });
  });
}
