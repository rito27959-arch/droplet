import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../design_system/ouro_colors.dart';

/// Effet de verre liquide avancé déclenché lorsqu'on maintient
/// un doigt sur un élément (bulle de message, carte, etc.).
///
/// Crée une onde de distortion liquide qui émane du point de contact
/// et se propage en cercle concentrique, avec un effet de loupe de
/// verre qui révèle le contenu avec une réfraction réaliste.
///
/// Inspiré des transitions Material Design 3 et des effets
/// haptiques visuels d'iOS.
class LiquidLongPressOverlay extends StatefulWidget {
  const LiquidLongPressOverlay({
    super.key,
    required this.child,
    required this.onLongPress,
    this.onLongPressEnd,
    this.onDoubleTap,
    this.duration = const Duration(milliseconds: 800),
    this.maxRadius = 120,
  });

  final Widget child;
  final VoidCallback onLongPress;
  final VoidCallback? onLongPressEnd;
  final VoidCallback? onDoubleTap;
  final Duration duration;
  final double maxRadius;

  @override
  State<LiquidLongPressOverlay> createState() => _LiquidLongPressOverlayState();
}

class _LiquidLongPressOverlayState extends State<LiquidLongPressOverlay>
    with TickerProviderStateMixin {
  AnimationController? _rippleController;
  AnimationController? _glowController;
  Offset? _pressPoint;
  bool _active = false;

  void _startEffect(Offset point) {
    _pressPoint = point;
    _active = true;

    _rippleController?.dispose();
    _rippleController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _glowController?.dispose();
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _rippleController!.forward();
    _glowController!.forward();
  }

  void _endEffect() {
    _active = false;
    _glowController?.reverse();
    widget.onLongPressEnd?.call();
  }

  @override
  void dispose() {
    _rippleController?.dispose();
    _glowController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (details) {
        _startEffect(details.localPosition);
        widget.onLongPress();
      },
      onLongPressEnd: (_) => _endEffect(),
      onLongPressCancel: () => _endEffect(),
      onDoubleTap: widget.onDoubleTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          widget.child,
          if (_active && _pressPoint != null)
            Positioned(
              left: _pressPoint!.dx - widget.maxRadius,
              top: _pressPoint!.dy - widget.maxRadius,
              child: AnimatedBuilder(
                animation: Listenable.merge([
                  _rippleController!,
                  _glowController!,
                ]),
                builder: (context, _) {
                  return CustomPaint(
                    size: Size(widget.maxRadius * 2, widget.maxRadius * 2),
                    painter: _LiquidRipplePainter(
                      progress: _rippleController!.value,
                      glowOpacity: _glowController!.value,
                      center: Offset(widget.maxRadius, widget.maxRadius),
                      maxRadius: widget.maxRadius,
                      isDark: OuroColors.isDark,
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _LiquidRipplePainter extends CustomPainter {
  _LiquidRipplePainter({
    required this.progress,
    required this.glowOpacity,
    required this.center,
    required this.maxRadius,
    required this.isDark,
  });

  final double progress;
  final double glowOpacity;
  final Offset center;
  final double maxRadius;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final eased = _easeOutQuint(progress);
    final radius = maxRadius * eased;

    // 1. Halo lumineux central (glass refraction)
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          (isDark
                  ? OuroColors.accent.withValues(alpha: 0.25)
                  : OuroColors.accent.withValues(alpha: 0.15))
              .withValues(alpha: glowOpacity),
          Colors.transparent,
        ],
        stops: const [0.0, 0.6],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, glowPaint);

    // 2. Anneaux concentriques de distortion (vagues liquides)
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (var i = 0; i < 3; i++) {
      final ringProgress = (progress - i * 0.15).clamp(0.0, 1.0);
      if (ringProgress <= 0) continue;

      final ringRadius = radius * (0.4 + i * 0.25) * _easeOutQuint(ringProgress);
      final ringOpacity = (1 - ringProgress) * 0.35 * glowOpacity;

      ringPaint.color = (isDark ? Colors.white : OuroColors.accent)
          .withValues(alpha: ringOpacity);

      canvas.drawCircle(center, ringRadius, ringPaint);
    }

    // 3. Point central de lumineux (effet loupe)
    if (progress > 0.1 && progress < 0.9) {
      final dotPaint = Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.white.withValues(alpha: 0.4 * glowOpacity),
            Colors.white.withValues(alpha: 0.0),
          ],
        ).createShader(Rect.fromCircle(center: center, radius: 20));
      canvas.drawCircle(center, 20, dotPaint);
    }
  }

  double _easeOutQuint(double t) => 1 - math.pow(1 - t, 5).toDouble();

  @override
  bool shouldRepaint(_LiquidRipplePainter old) =>
      progress != old.progress || glowOpacity != old.glowOpacity;
}
