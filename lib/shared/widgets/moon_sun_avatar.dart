import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../design_system/ouro_colors.dart';

/// Avatar animé du profil utilisateur qui change avec le thème :
/// - Mode sombre : croissant de lune avec étoiles scintillantes
/// - Mode clair : soleil animé avec rayons rotatifs
///
/// Remplace le `PeerAvatar` standard pour l'utilisateur courant dans
/// les endroits clés (paramètres, profil).
class MoonSunAvatar extends StatefulWidget {
  const MoonSunAvatar({
    super.key,
    required this.pseudo,
    this.radius = 30,
    this.imagePath,
  });

  final String pseudo;
  final double radius;
  final String? imagePath;

  @override
  State<MoonSunAvatar> createState() => _MoonSunAvatarState();
}

class _MoonSunAvatarState extends State<MoonSunAvatar>
    with TickerProviderStateMixin {
  late final AnimationController _moonController;
  late final AnimationController _sunController;

  @override
  void initState() {
    super.initState();
    _moonController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _sunController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    )..repeat();
  }

  @override
  void dispose() {
    _moonController.dispose();
    _sunController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = OuroColors.isDark;

    return SizedBox(
      width: widget.radius * 2,
      height: widget.radius * 2,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        child: isDark
            ? _MoonAvatar(
                key: const ValueKey('moon'),
                radius: widget.radius,
                controller: _moonController,
              )
            : _SunAvatar(
                key: const ValueKey('sun'),
                radius: widget.radius,
                controller: _sunController,
              ),
      ),
    );
  }
}

/// Croissant de lune avec étoiles scintillantes sur fond sombre.
class _MoonAvatar extends StatelessWidget {
  const _MoonAvatar({
    required this.radius,
    required this.controller,
    super.key,
  });

  final double radius;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              center: const Alignment(-0.3, -0.3),
              colors: [
                const Color(0xFF1A1A2E),
                const Color(0xFF0F0F23),
                const Color(0xFF050510),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6B7FD7).withValues(alpha: 0.15),
                blurRadius: radius * 0.4,
                spreadRadius: radius * 0.05,
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Croissant de lune
              _buildMoon(),
              // Étoiles scintillantes
              ..._buildStars(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMoon() {
    final moonSize = radius * 1.1;
    final offset = radius * 0.35;
    return Stack(
      alignment: Alignment.center,
      children: [
        // Lune pleine (cercle principal)
        Container(
          width: moonSize,
          height: moonSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const RadialGradient(
              center: Alignment(-0.2, -0.2),
              colors: [
                Color(0xFFF5F5DC),
                Color(0xFFE8E8C8),
                Color(0xFFD4D4A8),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFF5F5DC).withValues(alpha: 0.3),
                blurRadius: moonSize * 0.25,
                spreadRadius: moonSize * 0.05,
              ),
            ],
          ),
        ),
        // Ombre du croissant (cercle sombre qui cache une partie)
        Transform.translate(
          offset: Offset(offset, -offset * 0.6),
          child: Container(
            width: moonSize * 0.78,
            height: moonSize * 0.78,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0F0F23),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildStars() {
    // Positions fixes pour 5 étoiles, avec des tailles et phases aléatoires
    final stars = <(double x, double y, double size, double phase)>[
      (0.72, 0.18, 2.5, 0.0),
      (0.82, 0.45, 1.8, 0.3),
      (0.65, 0.72, 2.2, 0.6),
      (0.15, 0.78, 1.5, 0.8),
      (0.28, 0.12, 2.0, 0.5),
    ];

    return stars.map((s) {
      final twinkle = (math.sin((controller.value * 2 * math.pi) + s.$4 * 2 * math.pi) + 1) / 2;
      final opacity = 0.3 + twinkle * 0.7;
      return Positioned(
        left: radius * 2 * s.$1 - s.$3 / 2,
        top: radius * 2 * s.$2 - s.$3 / 2,
        child: Container(
          width: s.$3,
          height: s.$3,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: opacity),
            boxShadow: [
              BoxShadow(
                color: Colors.white.withValues(alpha: opacity * 0.5),
                blurRadius: s.$3 * 1.5,
              ),
            ],
          ),
        ),
      );
    }).toList();
  }
}

/// Soleil animé avec rayons rotatifs sur fond clair.
class _SunAvatar extends StatelessWidget {
  const _SunAvatar({
    required this.radius,
    required this.controller,
    super.key,
  });

  final double radius;
  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Container(
          width: radius * 2,
          height: radius * 2,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                const Color(0xFFFFF8E1),
                const Color(0xFFFFECB3),
                const Color(0xFFFFE082),
              ],
              stops: const [0.3, 0.7, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFFB300).withValues(alpha: 0.2),
                blurRadius: radius * 0.5,
                spreadRadius: radius * 0.1,
              ),
            ],
          ),
          child: CustomPaint(
            painter: _SunPainter(
              rotation: controller.value * 2 * math.pi,
              radius: radius,
            ),
            child: Center(
              child: Container(
                width: radius * 0.8,
                height: radius * 0.8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const RadialGradient(
                    colors: [
                      Color(0xFFFFD54F),
                      Color(0xFFFFCA28),
                      Color(0xFFFFB300),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFFFB300).withValues(alpha: 0.4),
                      blurRadius: radius * 0.3,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SunPainter extends CustomPainter {
  _SunPainter({required this.rotation, required this.radius});
  final double rotation;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    // 8 rayons rotatifs
    for (var i = 0; i < 8; i++) {
      final angle = rotation + (i * math.pi / 4);
      final innerR = radius * 0.55;
      final outerR = radius * 0.85;
      final start = Offset(
        center.dx + math.cos(angle) * innerR,
        center.dy + math.sin(angle) * innerR,
      );
      final end = Offset(
        center.dx + math.cos(angle) * outerR,
        center.dy + math.sin(angle) * outerR,
      );
      paint.color = const Color(0xFFFFB300).withValues(alpha: 0.5);
      canvas.drawLine(start, end, paint);
    }
  }

  @override
  bool shouldRepaint(_SunPainter old) => rotation != old.rotation;
}
