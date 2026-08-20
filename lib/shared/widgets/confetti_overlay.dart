// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Quand quelqu'un écrit « Joyeux anniversaire » ou « Félicitations »
// dans un message, ce fichier fait pleuvoir des confettis colorés sur
// TOUT l'écran, comme une petite fête surprise. C'est une animation
// entièrement fabriquée à la main (pas une vidéo ni une image), avec
// une quarantaine de petites formes (ronds et rectangles colorés) qui
// s'envolent, tournent sur elles-mêmes, puis s'estompent — chacune
// avec sa propre trajectoire légèrement différente, pour que ça ne
// ressemble pas à un motif répété mais à un vrai jet de confettis.
//
// Une fois l'animation terminée (2,4 secondes), elle se retire toute
// seule de l'écran — personne n'a besoin de la fermer à la main.
//
// POURQUOI C'EST DESSINÉ À LA MAIN (CustomPainter) ET PAS EN WIDGETS ?
// ----------------------------------------------------------------------------
// Voir la note détaillée en tête de `heart_burst_overlay.dart` : chaque
// confetti était auparavant un empilement `Positioned` + `Transform` +
// `Opacity` + `Container`, et un `Opacity` coûte un rendu hors-écran
// complet. Quarante-cinq rendus hors-écran par image, soixante fois par
// seconde, c'est ce qui faisait ramer l'animation. Ici les 45 confettis
// sont dessinés dans un seul canevas, et le peintre est branché sur le
// contrôleur d'animation — aucun widget n'est reconstruit pendant les
// 2,4 secondes.
// ============================================================================

import 'dart:math';
import 'package:flutter/material.dart';

/// Overlay plein écran de confettis colorés déclenché sur mots-clés
/// (Joyeux anniversaire, Félicitations, bravo, etc.). S'auto-détruit après
/// l'animation.
class ConfettiOverlay extends StatefulWidget {
  const ConfettiOverlay({super.key, required this.onDone});
  final VoidCallback onDone;

  /// La salve actuellement à l'écran, s'il y en a une — un message
  /// contenant trois fois « bravo » ne doit pas lancer trois pluies de
  /// confettis simultanées.
  static OverlayEntry? _active;

  /// Fait apparaître les confettis par-dessus tout le reste de l'écran
  /// (même par-dessus la barre de navigation), et se retire lui-même une
  /// fois fini.
  static void show(BuildContext context) {
    if (_active != null) return;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => ConfettiOverlay(onDone: () {
        if (identical(_active, entry)) _active = null;
        entry.remove();
      }),
    );
    _active = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  /// Relâche le garde-fou — voir la note détaillée sur l'équivalent
  /// dans `heart_burst_overlay.dart` : sans elle, un overlay détruit
  /// avant la fin de son animation verrouille l'effet pour de bon.
  static void _liberer() => _active = null;

  @override
  State<ConfettiOverlay> createState() => _ConfettiOverlayState();
}

class _ConfettiOverlayState extends State<ConfettiOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Confetti> _particles;
  final _rand = Random();

  static const _palette = [
    Color(0xFFFF3B30), // rouge
    Color(0xFFFF9500), // orange
    Color(0xFFFFCC00), // jaune
    Color(0xFF34C759), // vert
    Color(0xFF007AFF), // bleu
    Color(0xFFAF52DE), // violet
    Color(0xFFFF2D55), // rose
    Color(0xFF5AC8FA), // cyan
  ];

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    _particles = List.generate(45, (_) => _randomParticle());
    _ctrl.forward().whenComplete(() => widget.onDone());
  }

  /// Fabrique un confetti avec des propriétés tirées au hasard : sa
  /// position de départ, son déplacement latéral, sa taille, son petit
  /// délai avant de partir, sa vitesse de rotation, sa couleur, et si
  /// c'est un rond ou un petit rectangle.
  _Confetti _randomParticle() => _Confetti(
        x: _rand.nextDouble(),
        drift: (_rand.nextDouble() - 0.5) * 180,
        size: 6 + _rand.nextDouble() * 10,
        delay: _rand.nextDouble() * 0.5,
        rotation: (_rand.nextDouble() - 0.5) * 4,
        color: _palette[_rand.nextInt(_palette.length)],
        isCircle: _rand.nextBool(),
      );

  @override
  void dispose() {
    ConfettiOverlay._liberer();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // `IgnorePointer` : les confettis ne bloquent jamais les taps de
    // l'utilisateur sur ce qu'il y a en dessous — on peut continuer à
    // utiliser l'app normalement pendant qu'ils tombent.
    // `RepaintBoundary` : leur redessin n'entraîne pas celui de l'écran
    // qui se trouve derrière.
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _ConfettiPainter(_ctrl, _particles),
        ),
      ),
    );
  }
}

/// Dessine les 45 confettis en une seule passe de canevas.
class _ConfettiPainter extends CustomPainter {
  /// `super(repaint: animation)` : le peintre s'abonne directement au
  /// contrôleur, donc Flutter redessine sans jamais rappeler `build()`.
  _ConfettiPainter(this.animation, this.particles) : super(repaint: animation);

  final Animation<double> animation;
  final List<_Confetti> particles;

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;
    final pinceau = Paint()..isAntiAlias = true;

    for (final p in particles) {
      final ht = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (ht <= 0) continue;

      final curved = Curves.easeOut.transform(ht);
      final x = p.x * size.width + p.drift * curved;
      final y = size.height * 0.15 - curved * size.height * 0.8;

      final opacity = ht < 0.15
          ? ht / 0.15
          : ht > 0.75
              ? (1 - ht) / 0.25
              : 1.0;
      if (opacity <= 0.01) continue;

      // Le confetti grandit jusqu'à sa taille finale puis s'y tient. Une
      // version précédente utilisait un ressort (`elasticOut`) qui le
      // faisait osciller autour de sa taille : un vrai bout de papier qui
      // tombe ne pulse pas.
      final scale =
          Curves.easeOutCubic.transform(ht.clamp(0.0, 0.5) * 2) * 1.1;
      final rot = p.rotation * (1 - ht * 0.6);
      final l = p.size * scale;

      pinceau.color = p.color.withValues(alpha: opacity.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(x, y);
      if (rot != 0) canvas.rotate(rot);
      if (p.isCircle) {
        canvas.drawCircle(Offset.zero, l / 2, pinceau);
      } else {
        // Un rectangle allongé aux coins arrondis : un ruban de papier.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: l, height: l * 0.4),
            const Radius.circular(2),
          ),
          pinceau,
        );
      }
      canvas.restore();
    }
  }

  // Le peintre ne change jamais d'état : c'est `repaint` qui déclenche
  // le redessin, pas un remplacement de peintre.
  @override
  bool shouldRepaint(_ConfettiPainter old) => false;
}

/// La fiche d'identité d'UN SEUL petit confetti — d'où il part, où il
/// dérive, sa taille, sa couleur, sa forme.
class _Confetti {
  final double x;
  final double drift;
  final double size;
  final double delay;
  final double rotation;
  final Color color;
  final bool isCircle;
  const _Confetti({
    required this.x,
    required this.drift,
    required this.size,
    required this.delay,
    required this.rotation,
    required this.color,
    required this.isCircle,
  });
}
