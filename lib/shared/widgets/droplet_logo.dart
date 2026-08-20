// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est ici qu'est DESSINÉ (avec du code, pas une image importée) le
// logo « goutte d'eau » de Droplet — cette forme n'est enregistrée nulle
// part comme fichier image, elle est calculée en direct par
// l'ordinateur à chaque fois qu'elle s'affiche, un peu comme si on
// donnait des instructions précises à un robot dessinateur (« trace une
// courbe ici, puis une autre là ») plutôt que de lui montrer une photo.
// L'avantage : le logo reste parfaitement net à n'importe quelle taille,
// et peut respirer doucement (pulsation) ou changer de dégradé
// facilement.
//
// Ce fichier contient aussi les « ondes » concentriques (comme les
// ronds qui s'élargissent quand on jette un caillou dans l'eau) utilisées
// pendant un appel entrant, pour donner une impression de vie autour du
// logo, un peu comme le halo qui pulse sur l'écran d'appel de
// FaceTime/WhatsApp.
// ============================================================================

import 'package:flutter/material.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/design_tokens.dart';

/// Logo "gouttelette d'eau" — teardrop avec dégradé, halo et pulsation douce.
class DropletLogo extends StatefulWidget {
  const DropletLogo({
    super.key,
    this.radius = 48,
    this.glow = true,
    this.animate = true,
    this.gradient,
  });

  final double radius;
  final bool glow;
  final bool animate;
  final Gradient? gradient;

  @override
  State<DropletLogo> createState() => _DropletLogoState();
}

class _DropletLogoState extends State<DropletLogo> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: DesignTokens.durationXXSlow * 2,
    )..repeat(reverse: true);
    _pulse = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = widget.animate ? 1.0 + (_pulse.value * 0.05) : 1.0;
    final glowOpacity = widget.animate ? 0.35 + (_pulse.value * 0.3) : 0.5;

    return SizedBox(
      width: widget.radius * 3,
      height: widget.radius * 3,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            if (widget.glow)
              Container(
                width: widget.radius * 3,
                height: widget.radius * 3,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      OuroColors.meshBlue.withValues(alpha: glowOpacity),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            Transform.scale(
              scale: scale,
              child: CustomPaint(
                size: Size(widget.radius * 3, widget.radius * 3),
                painter: _DropletPainter(
                  radius: widget.radius,
                  gradient: widget.gradient,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le vrai « robot dessinateur » : trace la forme de la goutte d'eau
/// point par point avec des courbes mathématiques, la remplit d'un
/// dégradé, puis ajoute un petit reflet blanc en haut à gauche pour lui
/// donner un aspect brillant, comme sur une vraie goutte de pluie.
class _DropletPainter extends CustomPainter {
  const _DropletPainter({required this.radius, this.gradient});

  final double radius;
  final Gradient? gradient;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = radius;

    final path = Path()
      ..moveTo(cx, cy - 1.55 * r)
      ..cubicTo(cx - 0.6 * r, cy - 0.95 * r, cx - r, cy - 0.6 * r, cx - r, cy - 0.1 * r)
      ..cubicTo(cx - r, cy + 0.55 * r, cx - 0.55 * r, cy + r, cx, cy + r)
      ..cubicTo(cx + 0.55 * r, cy + r, cx + r, cy + 0.55 * r, cx + r, cy - 0.1 * r)
      ..cubicTo(cx + r, cy - 0.6 * r, cx + 0.6 * r, cy - 0.95 * r, cx, cy - 1.55 * r)
      ..close();

    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: r * 1.6);
    final paint = Paint()
      ..shader = (gradient ?? OuroColors.brandGradient).createShader(rect);
    canvas.drawPath(path, paint);

    final highlight = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.45, -0.55),
        colors: [
          Colors.white.withValues(alpha: 0.35),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.save();
    canvas.clipPath(path);
    canvas.drawCircle(Offset(cx - r * 0.35, cy - r * 0.45), r * 0.7, highlight);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DropletPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.gradient != gradient;
}

/// Vagues concentriques (style appel iOS) émises par la gouttelette —
/// comme les ronds qui s'élargissent à la surface de l'eau après avoir
/// jeté un caillou, utilisées pour animer l'écran d'appel entrant.
class DropletRipples extends StatefulWidget {
  const DropletRipples({
    super.key,
    required this.active,
    this.color,
  });

  final bool active;
  final Color? color;

  @override
  State<DropletRipples> createState() => _DropletRipplesState();
}

class _DropletRipplesState extends State<DropletRipples>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant DropletRipples oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => CustomPaint(
        size: const Size(double.infinity, double.infinity),
        painter: _RipplePainter(t: widget.active ? _controller.value : 0, color: widget.color ?? OuroColors.accent),
      ),
    );
  }
}

/// Dessine 4 cercles décalés dans le temps, qui grandissent et
/// s'estompent en boucle — c'est ce qui crée l'illusion d'ondes qui se
/// propagent en continu plutôt qu'un seul cercle qui grossit une fois.
class _RipplePainter extends CustomPainter {
  _RipplePainter({required this.t, required this.color});
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (t <= 0) return;
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2 - 8;
    for (int i = 0; i < 4; i++) {
      final phase = ((t - i * 0.25) % 1.0 + 1.0) % 1.0;
      if (phase <= 0) continue;
      final progress = Curves.easeOut.transform(phase);
      final radius = progress * maxRadius;
      final alpha = (1.0 - progress).clamp(0.0, 1.0) * 0.35;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = color.withValues(alpha: alpha);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _RipplePainter oldDelegate) =>
      oldDelegate.t != t || oldDelegate.color != color;
}
