// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est le cousin de `confetti_overlay.dart`, mais avec des petits
// cœurs ❤️ au lieu de confettis — exactement l'animation qu'on voit sur
// Messenger quand on double-tape sur un message pour dire « j'adore ».
// Une trentaine de cœurs s'envolent depuis le bas de l'écran vers le
// haut, chacun avec sa propre taille, sa propre trajectoire et son
// propre petit délai de départ, sur fond légèrement assombri qui
// s'éclaircit vite. Une fois l'animation finie (moins de 2 secondes),
// elle disparaît toute seule.
//
// POURQUOI C'EST DESSINÉ À LA MAIN (CustomPainter) ET PAS EN WIDGETS ?
// ----------------------------------------------------------------------------
// La première version empilait, pour CHAQUE cœur, un `Positioned` + un
// `Transform.rotate` + un `Transform.scale` + un `Opacity` + un `Text`
// contenant l'emoji. Ça donnait ~140 widgets reconstruits 60 fois par
// seconde, et surtout 28 `Opacity` — or un `Opacity` force le moteur de
// rendu à dessiner son contenu dans une image hors-écran séparée avant
// de la recomposer (un « saveLayer »). 28 allers-retours hors-écran par
// image, plus la remise en page de 28 emojis, c'est ce qui rendait
// l'animation poussive sur un téléphone déjà chargé.
//
// Ici tout est dessiné dans UN SEUL canevas : le cœur est une forme
// vectorielle (deux courbes de Bézier), la transparence est portée par
// la couleur du pinceau (donc gratuite), et le peintre est branché
// directement sur le contrôleur d'animation via `super(repaint:)` — ce
// qui veut dire que Flutter ne reconstruit AUCUN widget pendant les 1,8
// seconde : il se contente de redessiner. C'est le même mécanisme que
// celui utilisé par les vraies apps pour les animations de particules.
// ============================================================================

import 'dart:math';
import 'package:flutter/material.dart';

/// Overlay plein écran de cœurs flottants ( Messenger-style ) déclenché
/// par un double-tap sur ❤️. S'auto-détruit après l'animation.
class HeartBurstOverlay extends StatefulWidget {
  const HeartBurstOverlay({super.key, required this.onDone, this.origine});
  final VoidCallback onDone;

  /// D'où part la salve, en coordonnées d'écran. `null` = depuis le bas.
  final Offset? origine;

  /// L'entrée actuellement affichée, s'il y en a une.
  ///
  /// Sans ce garde-fou, un utilisateur qui double-tape cinq fois de
  /// suite empile cinq animations simultanées — cinq fois le travail de
  /// dessin, pour un résultat visuel qui n'est pas cinq fois plus joli.
  static OverlayEntry? _active;

  /// Affiche l'overlay par-dessus le Stack racine de [context].
  ///
  /// [origine] est le point d'où part la salve, en coordonnées d'écran.
  /// Quand il est fourni, les cœurs JAILLISSENT de ce point ; sinon ils
  /// montent depuis le bas de l'écran comme avant.
  ///
  /// ⚠️ CE PARAMÈTRE EST LE CŒUR DE L'EFFET, pas une option de confort.
  ///
  /// Une salve qui monte du bas de l'écran est un décor : elle se joue à
  /// côté du geste. Une salve qui part de la bulle qu'on vient de
  /// toucher est une RÉPONSE : l'utilisateur voit sa propre action
  /// produire quelque chose, à l'endroit exact où il l'a faite. C'est ce
  /// lien entre le point de contact et le point d'origine de l'animation
  /// qui distingue une application qui réagit d'une application qui
  /// s'anime.
  static void show(BuildContext context, {Offset? origine}) {
    if (_active != null) return; // une salve à la fois
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => HeartBurstOverlay(
        origine: origine,
        onDone: () {
          if (identical(_active, entry)) _active = null;
          entry.remove();
        },
      ),
    );
    _active = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  /// Relâche le garde-fou.
  ///
  /// ⚠️ Indispensable en plus du chemin normal (fin d'animation →
  /// `onDone` → retrait). Si l'overlay disparaît AUTREMENT — parce que
  /// l'`Overlay` qui le porte est détruit — l'animation ne se termine
  /// jamais, `onDone` n'est jamais appelé, et le verrou resterait posé
  /// pour le reste de la session : plus un seul cœur au double-tap,
  /// sans que rien ne signale pourquoi.
  static void _liberer() => _active = null;

  @override
  State<HeartBurstOverlay> createState() => _HeartBurstOverlayState();
}

class _HeartBurstOverlayState extends State<HeartBurstOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Heart> _hearts;
  final _rand = Random();

  /// Les teintes des cœurs. Trois rouges légèrement différents valent
  /// mieux qu'un seul : l'œil lit un essaim, pas un motif répété.
  static const _teintes = [
    Color(0xFFFF375F),
    Color(0xFFFF2D55),
    Color(0xFFFF5E7A),
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      // Une réaction est un accusé de réception : elle doit être vue et
      // oubliée. 1,8 seconde, c'est le temps d'une pluie décorative ;
      // pour un geste qu'on répète, c'est une éternité.
      duration: Duration(
        milliseconds: widget.origine != null ? 900 : 1800,
      ),
    );
    // Moins de cœurs pour une réaction ancrée : ils partent tous du même
    // point, donc vingt-huit se chevauchent en une masse illisible.
    _hearts = List.generate(widget.origine != null ? 16 : 28, (_) => _randomHeart());
    _ctrl.forward().whenComplete(widget.onDone);
  }

  /// Fabrique un cœur avec des propriétés tirées au hasard : sa position
  /// de départ, sa dérive latérale, sa taille, son petit délai avant de
  /// partir, sa légère rotation.
  _Heart _randomHeart() {
    final ancre = widget.origine != null;
    return _Heart(
      x: _rand.nextDouble(),
      // Ancrée, la salve s'ouvre en éventail : la dérive latérale est
      // beaucoup plus large, et symétrique autour du point touché.
      // Non ancrée, on garde la dérive douce d'une montée depuis le bas.
      drift: (_rand.nextDouble() - 0.5) * (ancre ? 340 : 120),
      size: (ancre ? 18 : 24) + _rand.nextDouble() * (ancre ? 26 : 36),
      // Les départs sont BEAUCOUP plus resserrés quand c'est une
      // réaction : un jaillissement est un événement bref, pas une pluie
      // qui s'installe. Étaler les délais donnerait un goutte-à-goutte.
      delay: _rand.nextDouble() * (ancre ? 0.14 : 0.4),
      rotation: (_rand.nextDouble() - 0.5) * 0.6,
      couleur: _teintes[_rand.nextInt(_teintes.length)],
    );
  }

  @override
  void dispose() {
    HeartBurstOverlay._liberer();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // `IgnorePointer` : les cœurs ne bloquent jamais les taps de
    // l'utilisateur sur ce qu'il y a en dessous.
    // `RepaintBoundary` : le redessin des cœurs n'oblige pas la
    // conversation qui est derrière à se redessiner elle aussi.
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _HeartPainter(_ctrl, _hearts, widget.origine),
        ),
      ),
    );
  }
}

/// Dessine les 28 cœurs — et le voile sombre — en une seule passe.
class _HeartPainter extends CustomPainter {
  /// `super(repaint: animation)` : le peintre s'abonne lui-même au
  /// contrôleur. Flutter redessine quand la valeur change, sans jamais
  /// repasser par `build()`.
  _HeartPainter(this.animation, this.hearts, this.origine)
      : super(repaint: animation);

  final Animation<double> animation;
  final List<_Heart> hearts;

  /// Le point d'où jaillit la salve, ou `null` pour une montée du bas.
  final Offset? origine;

  /// Le tracé d'un cœur dans un carré de 1×1, construit une fois pour
  /// toutes. On le met à l'échelle avec le canevas plutôt que d'en
  /// refabriquer un par cœur et par image.
  static final Path _forme = _construireCoeur();

  static Path _construireCoeur() {
    final p = Path()..moveTo(0.5, 0.97);
    // Lobe gauche puis lobe droit, en miroir.
    p.cubicTo(-0.16, 0.55, 0.06, -0.05, 0.5, 0.28);
    p.cubicTo(0.94, -0.05, 1.16, 0.55, 0.5, 0.97);
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;

    // Voile sombre, qui s'efface vite. L'opacité est portée par la
    // couleur : pas de `saveLayer`, donc pas de rendu hors-écran.
    // ⚠️ PAS DE VOILE SOMBRE POUR UNE RÉACTION ANCRÉE.
    //
    // Assombrir tout l'écran transforme un accusé de réception en
    // événement : on suspend la lecture pour dire « j'aime ». Le voile
    // n'a de sens que pour la pluie plein écran, qui est, elle, une
    // célébration.
    final voile =
        origine != null ? 0.0 : (1 - t).clamp(0.0, 1.0) * 0.15;
    if (voile > 0.002) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()..color = Colors.black.withValues(alpha: voile),
      );
    }

    final pinceau = Paint()..isAntiAlias = true;

    for (final h in hearts) {
      final ht = ((t - h.delay) / (1 - h.delay)).clamp(0.0, 1.0);
      if (ht <= 0) continue;

      final curved = Curves.easeOut.transform(ht);

      final double x;
      final double y;
      final depart = origine;
      if (depart != null) {
        // ── JAILLISSEMENT DEPUIS LA BULLE ────────────────────────────
        //
        // Tous les cœurs partent du MÊME point, s'écartent en éventail
        // (`drift`) et montent. La montée est courte — un cinquième de
        // l'écran — parce qu'une réaction doit rester AU NIVEAU du
        // message : la voir traverser tout l'écran ferait perdre de vue
        // ce à quoi on a réagi.
        //
        // La retombée légère en fin de course (le terme au carré) évite
        // que les cœurs s'arrêtent net en haut de leur trajectoire, ce
        // qui trahit immédiatement une animation calculée.
        final monte = curved * (size.height * 0.20);
        final retombee = 26 * curved * curved;
        x = depart.dx + h.drift * curved;
        y = depart.dy - monte + retombee;
      } else {
        x = h.x * size.width + h.drift * curved;
        y = size.height - curved * (size.height * 0.65);
      }

      // Apparition franche, disparition douce en fin de course.
      // Ancrée, la salve apparaît QUASI INSTANTANÉMENT et s'efface tôt :
      // le geste est acquitté dès le premier dixième de seconde, et
      // l'écran est rendu à la conversation avant qu'on ait le temps de
      // s'impatienter.
      final opacity = origine != null
          ? (ht < 0.08
              ? ht / 0.08
              : ht > 0.5
                  ? (1 - ht) / 0.5
                  : 1.0)
          : (ht < 0.2
              ? ht / 0.2
              : ht > 0.7
                  ? (1 - ht) / 0.3
                  : 1.0);
      if (opacity <= 0.01) continue;

      // Croissance franche jusqu'à la taille finale, sans oscillation
      // autour (un `elasticOut` faisait « respirer » chaque cœur pendant
      // sa montée).
      final scale =
          0.5 + Curves.easeOutCubic.transform(ht.clamp(0.0, 0.6) / 0.6) * 0.5;
      final cote = h.size * scale;
      final rot = h.rotation * (1 - ht);

      pinceau.color = h.couleur.withValues(alpha: opacity.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(x, y);
      if (rot != 0) canvas.rotate(rot);
      canvas.translate(-cote / 2, -cote / 2);
      canvas.scale(cote);
      canvas.drawPath(_forme, pinceau);
      canvas.restore();
    }
  }

  // Le peintre se redessine parce que `repaint` le lui demande, jamais
  // parce qu'on l'a remplacé — la liste de cœurs ne change pas en cours
  // de route.
  @override
  bool shouldRepaint(_HeartPainter old) => false;
}

/// La fiche d'identité d'UN SEUL cœur — d'où il part, où il dérive, sa
/// taille, sa rotation, sa teinte.
class _Heart {
  final double x;
  final double drift;
  final double size;
  final double delay;
  final double rotation;
  final Color couleur;
  const _Heart({
    required this.x,
    required this.drift,
    required this.size,
    required this.delay,
    required this.rotation,
    required this.couleur,
  });
}
