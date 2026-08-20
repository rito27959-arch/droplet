// ============================================================================
// CE QUE CES TESTS PROTÈGENT
// ----------------------------------------------------------------------------
// L'animation d'envoi (`SendFlight`) a une particularité qui la rend
// dangereuse : elle demande à l'écran de discussion de RENDRE UNE BULLE
// INVISIBLE pendant qu'elle vole, et c'est elle qui doit dire quand la
// remontrer.
//
// Si ce signal ne part jamais — vol interrompu, écran détruit en cours de
// route, `Overlay` absent — le message reste invisible pour toujours.
// L'utilisateur voit alors son message disparaître à l'envoi, dans une
// application dont le seul travail est de ne pas perdre de messages.
//
// Ces tests vérifient donc, dans l'ordre d'importance :
//
//   1. que le vol ANNONCE son échec quand il ne peut pas partir (sinon
//      l'écran masque une bulle que rien ne viendra démasquer) ;
//   2. que la révélation a bien lieu AVANT la fin, pour que la vraie
//      bulle soit déjà là quand la copie s'efface ;
//   3. qu'elle a lieu MÊME si le vol est détruit en plein milieu ;
//   4. que la copie se retire d'elle-même à l'arrivée.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:droplet/features/chat/send_flight_animation.dart';

/// Les paramètres de géométrie, identiques d'un test à l'autre : ce
/// n'est pas eux qu'on teste ici.
bool _lancer(
  BuildContext context, {
  required GlobalKey depuis,
  required GlobalKey zone,
  VoidCallback? onRevele,
  String texte = 'Bonjour',
}) {
  return SendFlight.lancer(
    context: context,
    depuis: depuis,
    zoneListe: zone,
    texte: texte,
    couleurBulle: const Color(0xFF007AFF),
    styleTexte: const TextStyle(color: Colors.white, fontSize: 16),
    couleurTexteDepart: const Color(0xFF000000),
    paddingDepart: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
    paddingArrivee: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
    rayonArrivee: BorderRadius.circular(22),
    largeurMaxBulle: 300,
    onRevele: onRevele,
  );
}

/// Une page minimale avec les deux repères que le vol doit mesurer.
class _Banc extends StatelessWidget {
  const _Banc({
    required this.champ,
    required this.zone,
    required this.onPret,
  });

  final GlobalKey champ;
  final GlobalKey zone;
  final void Function(BuildContext) onPret;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Column(
          children: [
            Expanded(child: SizedBox(key: zone, width: 400)),
            SizedBox(key: champ, height: 44, width: 300),
            Builder(
              builder: (inner) {
                return TextButton(
                  onPressed: () => onPret(inner),
                  child: const Text('envoyer'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

void main() {
  testWidgets('un vol qui ne peut pas être mesuré renvoie false',
      (tester) async {
    // Les deux clés ne sont attachées à rien : aucun rectangle à mesurer.
    // C'est exactement le cas où l'écran NE DOIT PAS masquer sa bulle.
    late bool resultat;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            resultat = _lancer(
              context,
              depuis: GlobalKey(),
              zone: GlobalKey(),
            );
            return const SizedBox();
          },
        ),
      ),
    );
    expect(resultat, isFalse);
  });

  testWidgets('un vol mesurable décolle et pose une copie du texte',
      (tester) async {
    final champ = GlobalKey();
    final zone = GlobalKey();
    bool? lance;

    await tester.pumpWidget(_Banc(
      champ: champ,
      zone: zone,
      onPret: (context) =>
          lance = _lancer(context, depuis: champ, zone: zone),
    ));
    await tester.tap(find.text('envoyer'));
    await tester.pump();

    expect(lance, isTrue);
    // La copie volante porte le texte du message.
    expect(find.text('Bonjour'), findsOneWidget);
  });

  testWidgets('la vraie bulle est révélée AVANT la fin du vol',
      (tester) async {
    final champ = GlobalKey();
    final zone = GlobalKey();
    Duration? quand;
    final depart = Stopwatch();

    await tester.pumpWidget(_Banc(
      champ: champ,
      zone: zone,
      onPret: (context) {
        depart.start();
        _lancer(
          context,
          depuis: champ,
          zone: zone,
          onRevele: () => quand = depart.elapsed,
        );
      },
    ));
    await tester.tap(find.text('envoyer'));

    // Un peu avant le seuil de révélation : rien ne doit encore être
    // annoncé, sinon la vraie bulle apparaîtrait à côté de la copie
    // encore en pleine course.
    await tester.pump();
    await tester.pump(SendFlight.duree * 0.7);
    expect(quand, isNull,
        reason: 'révéler trop tôt fait voir le message à deux endroits');

    // Après le seuil, mais avant la fin.
    await tester.pump(SendFlight.duree * 0.2);
    expect(quand, isNotNull,
        reason: 'révéler trop tard fait clignoter un vide à l\'arrivée');

    await tester.pumpAndSettle();
  });

  testWidgets('la copie se retire d\'elle-même une fois posée',
      (tester) async {
    final champ = GlobalKey();
    final zone = GlobalKey();

    await tester.pumpWidget(_Banc(
      champ: champ,
      zone: zone,
      onPret: (context) => _lancer(context, depuis: champ, zone: zone),
    ));
    await tester.tap(find.text('envoyer'));
    await tester.pump();
    expect(find.text('Bonjour'), findsOneWidget);

    await tester.pumpAndSettle();
    // Plus aucune copie : l'`OverlayEntry` s'est retirée seule. Sans
    // cela, chaque message enverrait une bulle fantôme de plus se
    // superposer à la conversation, définitivement.
    expect(find.text('Bonjour'), findsNothing);
  });

  testWidgets('un vol interrompu révèle quand même la bulle',
      (tester) async {
    final champ = GlobalKey();
    final zone = GlobalKey();
    var revele = false;

    await tester.pumpWidget(_Banc(
      champ: champ,
      zone: zone,
      onPret: (context) => _lancer(
        context,
        depuis: champ,
        zone: zone,
        onRevele: () => revele = true,
      ),
    ));
    await tester.tap(find.text('envoyer'));
    await tester.pump();
    expect(revele, isFalse);

    // On quitte l'écran en plein vol — le cas où un message resterait
    // invisible pour toujours si la copie ne prévenait pas en partant.
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pump();

    expect(revele, isTrue,
        reason: 'une bulle masquée doit TOUJOURS finir par reparaître');
  });
}
