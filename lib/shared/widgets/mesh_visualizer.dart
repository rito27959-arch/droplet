// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est le joli petit dessin animé qu'on voit sur l'écran d'accueil ou
// l'écran « Réseau mesh » : une goutte d'eau au centre, avec des petits
// points qui tournent autour comme des planètes autour du soleil, reliés
// au centre par des traits lumineux. Chaque point représente un pair
// (un ami connecté), et le nombre de points s'ajuste selon le nombre
// réel de personnes connectées sur le mesh.
//
// C'est purement décoratif — ça ne fait tourner aucun vrai réseau, ça se
// contente de MONTRER de façon vivante et jolie que le réseau est actif,
// un peu comme l'animation d'un radar qui balaie l'écran dans un film,
// même si elle ne « détecte » rien elle-même : les vraies infos (combien
// de pairs, etc.) viennent d'ailleurs et sont juste transmises ici pour
// être affichées.
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../design_system/ouro_colors.dart';

/// Visualiseur mesh : gouttelette centrale + pairs en orbite reliés par des
/// liens lumineux, le tout animé en continu.
class MeshVisualizer extends StatefulWidget {
  const MeshVisualizer({
    super.key,
    this.peerCount = 0,
    this.height = 150,
  });

  final int peerCount;
  final double height;

  @override
  State<MeshVisualizer> createState() => _MeshVisualizerState();
}

class _MeshVisualizerState extends State<MeshVisualizer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _MeshVisualizerPainter(
            t: _controller.value,
            peerCount: widget.peerCount,
            active: widget.peerCount > 0,
          ),
        ),
      ),
    );
  }
}

/// Le « robot dessinateur » qui trace, image par image, les orbites, les
/// points-pairs qui tournent, les traits lumineux qui les relient au
/// centre, et la goutte d'eau centrale avec son onde de pulsation.
class _MeshVisualizerPainter extends CustomPainter {
  _MeshVisualizerPainter({
    required this.t,
    required this.peerCount,
    required this.active,
  });

  final double t;
  final int peerCount;
  final bool active;

  static const int _maxVisualPeers = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final orbitR = math.min(size.width, size.height) * 0.34;
    final count = peerCount == 0 ? 6 : peerCount.clamp(1, _maxVisualPeers);

    // Orbites
    for (final r in [orbitR * 0.55, orbitR * 0.8, orbitR]) {
      final orbitPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = OuroColors.meshBlue.withValues(alpha: 0.12);
      canvas.drawCircle(Offset(cx, cy), r, orbitPaint);
    }

    // Pairs en orbite
    final positions = <Offset>[];
    for (int i = 0; i < count; i++) {
      final angle = (i / count) * 2 * math.pi + t * 2 * math.pi;
      final radius = orbitR * (0.6 + 0.4 * math.sin(i * 1.7 + t * 0.5));
      final px = cx + math.cos(angle) * radius;
      final py = cy + math.sin(angle) * radius;

      // Lien vers le centre
      final link = Paint()
        ..strokeWidth = 1.2
        ..color = OuroColors.meshBlue.withValues(alpha: active ? 0.35 : 0.18);
      canvas.drawLine(Offset(cx, cy), Offset(px, py), link);

      positions.add(Offset(px, py));

      // Point pair
      final dot = Paint()
        ..color = active ? OuroColors.accentTeal : OuroColors.textTertiary.withValues(alpha: 0.6);
      canvas.drawCircle(Offset(px, py), 4, dot);
      final halo = Paint()
        ..color = (active ? OuroColors.accentTeal : OuroColors.textTertiary)
            .withValues(alpha: 0.15 + 0.1 * math.sin(t * 2 * math.pi + i));
      canvas.drawCircle(Offset(px, py), 9, halo);
    }

    // Lien pair-à-pair entre les deux premiers (décentralisé) — un petit
    // rappel visuel que le réseau n'est pas juste « en étoile » autour de
    // moi, mais que les pairs peuvent aussi se parler entre eux.
    if (positions.length >= 2) {
      final hop = Paint()
        ..strokeWidth = 1
        ..color = OuroColors.accentPurple.withValues(alpha: 0.25);
      canvas.drawLine(positions[0], positions[1], hop);
    }

    // Gouttelette centrale (teardrop)
    final r = 18.0;
    final droplet = Path()
      ..moveTo(cx, cy - 1.45 * r)
      ..cubicTo(cx - 0.55 * r, cy - 0.9 * r, cx - r, cy - 0.55 * r, cx - r, cy - 0.1 * r)
      ..cubicTo(cx - r, cy + 0.5 * r, cx - 0.5 * r, cy + r, cx, cy + r)
      ..cubicTo(cx + 0.5 * r, cy + r, cx + r, cy + 0.5 * r, cx + r, cy - 0.1 * r)
      ..cubicTo(cx + r, cy - 0.55 * r, cx + 0.55 * r, cy - 0.9 * r, cx, cy - 1.45 * r)
      ..close();
    canvas.drawPath(droplet, Paint()..shader = OuroColors.brandGradient.createShader(
      Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.6),
    ));

    // Onde de pulsation autour de la gouttelette — le même effet
    // « caillou dans l'eau » que dans droplet_logo.dart, mais un seul
    // cercle qui grandit en boucle au lieu de quatre.
    final pulsePhase = (t * 2) % 1.0;
    final pulseR = r + 6 + pulsePhase * 26;
    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = OuroColors.meshBlueBright.withValues(alpha: (1 - pulsePhase) * 0.5);
    canvas.drawCircle(Offset(cx, cy), pulseR, pulsePaint);
  }

  @override
  bool shouldRepaint(covariant _MeshVisualizerPainter oldDelegate) =>
      oldDelegate.t != t ||
      oldDelegate.peerCount != peerCount ||
      oldDelegate.active != active;
}
