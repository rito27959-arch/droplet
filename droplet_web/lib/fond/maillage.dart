// LE FOND — le maillage de Droplet, très lentement vivant.
//
// Des téléphones vus de très haut (des points) qui dérivent à peine, et les
// liens qui se tissent entre ceux qui sont assez proches. Discret par
// principe : il donne le sujet sans jamais voler l'attention au code QR.
//
// Chaque point suit une petite orbite calculée à partir de l'horloge, pas
// une simulation : rien ne s'accumule, rien ne dérive avec le temps, et le
// même instant donne toujours la même image.
//
// « Réduire les animations » (système) → le maillage est figé.
import 'dart:math';

import 'package:flutter/widgets.dart';

class FondMaillage extends StatefulWidget {
  const FondMaillage({super.key, required this.couleurPoint, required this.couleurAccent});

  final Color couleurPoint;
  final Color couleurAccent;

  @override
  State<FondMaillage> createState() => _FondMaillageState();
}

class _FondMaillageState extends State<FondMaillage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _temps = AnimationController(
    vsync: this,
    duration: const Duration(minutes: 4),
  );

  // Des graines fixes : le même maillage à chaque ouverture.
  static final List<_Noeud> _noeuds = () {
    final r = Random(7);
    return List.generate(46, (_) {
      return _Noeud(
        x: r.nextDouble(),
        y: r.nextDouble(),
        rayon: 14 + r.nextDouble() * 26,
        phase: r.nextDouble() * pi * 2,
        vitesse: 0.6 + r.nextDouble() * 0.8,
        allume: r.nextDouble() < 0.08,
      );
    });
  }();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.of(context).disableAnimations) {
      _temps.stop();
    } else if (!_temps.isAnimating) {
      _temps.repeat();
    }
  }

  @override
  void dispose() {
    _temps.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _temps,
        builder: (context, _) => CustomPaint(
          size: Size.infinite,
          painter: _PeintreMaillage(
            t: _temps.value * pi * 2,
            noeuds: _noeuds,
            point: widget.couleurPoint,
            accent: widget.couleurAccent,
          ),
        ),
      ),
    );
  }
}

class _Noeud {
  const _Noeud({
    required this.x,
    required this.y,
    required this.rayon,
    required this.phase,
    required this.vitesse,
    required this.allume,
  });

  final double x, y, rayon, phase, vitesse;

  /// Quelques téléphones « actifs », dans la couleur d'accent.
  final bool allume;
}

class _PeintreMaillage extends CustomPainter {
  _PeintreMaillage({
    required this.t,
    required this.noeuds,
    required this.point,
    required this.accent,
  });

  final double t;
  final List<_Noeud> noeuds;
  final Color point;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final positions = [
      for (final n in noeuds)
        Offset(
          n.x * size.width + cos(t * n.vitesse + n.phase) * n.rayon,
          n.y * size.height + sin(t * n.vitesse * 0.8 + n.phase) * n.rayon,
        ),
    ];
    final portee = min(size.width, size.height) * 0.2;
    final lien = Paint()..strokeWidth = 1;
    for (var i = 0; i < positions.length; i++) {
      for (var j = i + 1; j < positions.length; j++) {
        final d = (positions[i] - positions[j]).distance;
        if (d < portee) {
          lien.color = point.withValues(alpha: (1 - d / portee) * 0.14);
          canvas.drawLine(positions[i], positions[j], lien);
        }
      }
    }
    final rond = Paint();
    for (var i = 0; i < positions.length; i++) {
      final n = noeuds[i];
      if (n.allume) {
        // Le halo d'un téléphone actif respire lentement.
        final souffle = 0.5 + 0.5 * sin(t * 3 + n.phase);
        rond.color = accent.withValues(alpha: 0.10 + 0.12 * souffle);
        canvas.drawCircle(positions[i], 9 + 5 * souffle, rond);
        rond.color = accent.withValues(alpha: 0.85);
        canvas.drawCircle(positions[i], 2.6, rond);
      } else {
        rond.color = point.withValues(alpha: 0.32);
        canvas.drawCircle(positions[i], 2, rond);
      }
    }
  }

  @override
  bool shouldRepaint(_PeintreMaillage ancien) =>
      ancien.t != t || ancien.point != point || ancien.accent != accent;
}
