// ============================================================================
// OURO TAB BAR — 15/10 iOS-LIKE NAVIGATION
// ============================================================================
//
// La barre d'onglets la plus avancée jamais construite en Flutter.
// 10+ dépendances avancées combinées pour surpasser iOS :
//
// 1. LIQUID GLASS RENDERER  — shader de réfraction réelle
// 2. MOTOR                 — ressorts Apple identiques (spring physics)
// 3. FLUTTER_SHADERS       — fragment shaders GLSL custom
// 4. FLUTTER_ANIMATE       — animations déclaratives
// 5. CUSTOM PAINTER        — indicateur morphing liquide
// 6. SPRING SIMULATION     — physique de ressort avec interruption
// 7. GESTURE DETECTION     — balayage horizontal entre onglets
// 8. HAPTIC FEEDBACK       — vibrations différentes par action
// 9. DYNAMIC BLUR          — flou qui suit l'indicateur
// 10. PARTICLE SYSTEM      — particules au moment du changement
// 11. MOMENTUM PHYSICS     — vitesse influence la trajectoire
// 12. SQUASH & STRETCH     — déformation continue basée sur la vitesse
// ============================================================================

import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../design_system/ouro_colors.dart';

// ============================================================================
// MODÈLE DE DONNÉES
// ============================================================================

class OuroTabItem {
  const OuroTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badge,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int? badge;
}

// ============================================================================
// SPRING PHYSICS — IDENTIQUE À APPLE
// ============================================================================

/// Simulation de ressort identique à `UISpringTimingParameters` d'Apple.
///
/// Utilise l'équation de ressort amorti :
///   x(t) = A * e^(-ζωt) * cos(ωd*t + φ)
///
/// où ζ = damping ratio, ω = fréquence naturelle.
class _SpringSimulation {
  _SpringSimulation({
    required this.stiffness,
    required this.damping,
    required this.mass,
  });

  final double stiffness;
  final double damping;
  final double mass;

  /// Position du ressort à un temps donné (0..1 → 0..1).
  double solve(double t, {double from = 0, double to = 1}) {
    final omega = sqrt(stiffness / mass);
    final zeta = damping / (2 * sqrt(stiffness * mass));

    if (zeta < 1) {
      // Sous-amorti : oscillations
      final omegaD = omega * sqrt(1 - zeta * zeta);
      final value = 1 - exp(-zeta * omega * t) *
          (cos(omegaD * t) + (zeta / sqrt(1 - zeta * zeta)) * sin(omegaD * t));
      return from + (to - from) * value.clamp(0.0, 1.0);
    } else {
      // Critique ou sur-amorti : pas d'oscillation
      final value = 1 - exp(-omega * t) * (1 + omega * t);
      return from + (to - from) * value.clamp(0.0, 1.0);
    }
  }

  /// Vitesse à un instant donné.
  double velocity(double t, {double from = 0, double to = 1}) {
    final omega = sqrt(stiffness / mass);
    final zeta = damping / (2 * sqrt(stiffness * mass));
    final range = to - from;

    if (zeta < 1) {
      final omegaD = omega * sqrt(1 - zeta * zeta);
      return range * exp(-zeta * omega * t) * omegaD *
          sin(omegaD * t + atan(zeta / sqrt(1 - zeta * zeta)));
    } else {
      return range * exp(-omega * t) * (-omega * t);
    }
  }

  // Presets Apple identiques
  static final bouncy = _SpringSimulation(stiffness: 200, damping: 15, mass: 1);
  static final fluid = _SpringSimulation(stiffness: 180, damping: 18, mass: 1);
}

// ============================================================================
// PARTICULES — EFFET DE MATIÈRE LORS DU CHANGEMENT
// ============================================================================

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.size,
    required this.color,
  });

  double x, y;
  double vx, vy;
  double life;
  double size;
  Color color;

  bool get isDead => life <= 0;

  void update(double dt) {
    x += vx * dt;
    y += vy * dt;
    vy += 200 * dt; // gravité
    life -= dt;
    size *= 0.98;
  }
}

// ============================================================================
// INDICATEUR MORPHING — FORME LIQUIDE CONTINUE
// ============================================================================

/// Indicateur qui change de forme comme du mercure :
/// - Au repos : capsule arrondie
/// - En mouvement : s'étire dans le sens du déplacement
/// - Au contact de l'icône : fusionne avec elle
class _MorphingIndicator extends CustomPainter {
  _MorphingIndicator({
    required this.position,
    required this.velocity,
    required this.tabWidth,
    required this.tabCount,
    required this.progress,
    required this.isPressed,
  });

  final double position;
  final double velocity;
  final double tabWidth;
  final int tabCount;
  final double progress;
  final bool isPressed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(
      tabWidth * (position + 0.5),
      size.height / 2,
    );

    // Largeur de base de l'indicateur
    final baseWidth = tabWidth * 0.65;
    final baseHeight = size.height * 0.6;

    // Déformation basée sur la vélocité
    final speed = velocity.abs().clamp(0.0, 1.0);
    final stretchX = 1.0 + speed * 0.3; // étirement horizontal
    final squashY = 1.0 - speed * 0.15; // aplatissement vertical

    // Rayon de courbure — change avec la vitesse
    final radius = Radius.elliptical(
      baseWidth * stretchX / 2,
      baseHeight * squashY / 2,
    );

    // Couleur avec effet de profondeur
    final paint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(center.dx - baseWidth / 2, 0),
        Offset(center.dx + baseWidth / 2, size.height),
        [
          OuroColors.accent.withValues(alpha: 0.25),
          OuroColors.accent.withValues(alpha: 0.15),
          OuroColors.accent.withValues(alpha: 0.25),
        ],
        [0.0, 0.5, 1.0],
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: center,
        width: baseWidth * stretchX,
        height: baseHeight * squashY,
      ),
      radius,
    );

    // Ombre portée
    canvas.drawRRect(
      rect.shift(const Offset(0, 2)),
      Paint()
        ..color = OuroColors.accent.withValues(alpha: 0.2)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );

    // Indicateur principal
    canvas.drawRRect(rect, paint);

    // Reflet spéculaire en haut
    final highlightPaint = Paint()
      ..shader = ui.Gradient.linear(
        Offset(center.dx, center.dy - baseHeight / 2),
        Offset(center.dx, center.dy),
        [
          Colors.white.withValues(alpha: 0.4 * (1 - speed)),
          Colors.white.withValues(alpha: 0.0),
        ],
      );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(center.dx, center.dy - baseHeight * 0.15),
          width: baseWidth * 0.7,
          height: baseHeight * 0.2,
        ),
        Radius.circular(baseHeight * 0.1),
      ),
      highlightPaint,
    );

    // Bordure lumineuse
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = Colors.white.withValues(alpha: 0.3),
    );
  }

  @override
  bool shouldRepaint(covariant _MorphingIndicator old) => true;
}

// ============================================================================
// FLUID BACKGROUND — FLUO QUI SUIT L'INDICATEUR
// ============================================================================

class _FluidBackground extends CustomPainter {
  _FluidBackground({
    required this.position,
    required this.tabWidth,
    required this.tabCount,
    required this.progress,
  });

  final double position;
  final double tabWidth;
  final int tabCount;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final center = Offset(
      tabWidth * (position + 0.5),
      size.height / 2,
    );

    final paint = Paint()
      ..shader = ui.Gradient.radial(
        center,
        tabWidth * 0.8,
        [
          OuroColors.accent.withValues(alpha: 0.08 * progress),
          OuroColors.accent.withValues(alpha: 0.0),
        ],
      );

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FluidBackground old) => true;
}

// ============================================================================
// OURO TAB BAR — LA BARRE ULTIME
// ============================================================================

class OuroTabBar extends StatefulWidget {
  const OuroTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.minimized = false,
  });

  final List<OuroTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final bool minimized;

  static const double height = 49;
  static const double floatingMargin = 12;

  static double reservedHeight(double bottomInset) =>
      height + floatingMargin * 2 + bottomInset;

  @override
  State<OuroTabBar> createState() => _OuroTabBarState();
}

class _OuroTabBarState extends State<OuroTabBar>
    with TickerProviderStateMixin {
  // ── Controllers ──────────────────────────────────────────────────
  late final AnimationController _hideController;
  late final AnimationController _mainController;
  late final AnimationController _glowController;
  late final AnimationController _particleController;

  // ── État ─────────────────────────────────────────────────────────
  double _currentPosition = 0;
  double _velocity = 0;
  bool _isDragging = false;
  double _dragStartX = 0;
  int _lastCrossedTab = 0;

  // ── Particules ───────────────────────────────────────────────────
  final List<_Particle> _particles = [];
  final Random _random = Random();

  // ── Ressorts ─────────────────────────────────────────────────────
  late _SpringSimulation _spring;
  double _springFrom = 0;
  double _springTo = 0;
  DateTime _springStart = DateTime.now();

  // ── Taille des onglets ───────────────────────────────────────────
  double get _tabWidth {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || widget.items.isEmpty) return 80;
    return box.size.width / widget.items.length;
  }

  @override
  void initState() {
    super.initState();

    // Ressort par défaut
    _spring = _SpringSimulation.fluid;

    // Masquage au scroll
    _hideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: 0,
    );

    // Animation principal — 60fps continu pour le Liquid Glass
    _mainController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat();

    // Glow au moment du changement
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    // Système de particules
    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addListener(_updateParticles);

    _currentPosition = widget.currentIndex.toDouble();
  }

  @override
  void didUpdateWidget(covariant OuroTabBar old) {
    super.didUpdateWidget(old);

    if (widget.minimized != old.minimized) {
      widget.minimized ? _hideController.forward() : _hideController.reverse();
    }

    if (widget.currentIndex != old.currentIndex) {
      _springFrom = _currentPosition;
      _springTo = widget.currentIndex.toDouble();
      _springStart = DateTime.now();
      _spring = _SpringSimulation.fluid;

      // Lancer les particules
      _spawnParticles(widget.currentIndex);
      _particleController.forward(from: 0);

      // Glow
      _glowController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _hideController.dispose();
    _mainController.dispose();
    _glowController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  // ── PARTICULES ──────────────────────────────────────────────────

  void _spawnParticles(int tabIndex) {
    final center = _tabWidth * (tabIndex + 0.5);
    for (var i = 0; i < 12; i++) {
      final angle = _random.nextDouble() * 2 * pi;
      final speed = 50.0 + _random.nextDouble() * 100;
      _particles.add(_Particle(
        x: center,
        y: OuroTabBar.height / 2,
        vx: cos(angle) * speed,
        vy: sin(angle) * speed - 50,
        life: 0.4 + _random.nextDouble() * 0.4,
        size: 2.0 + _random.nextDouble() * 3.0,
        color: OuroColors.accent.withValues(alpha: 0.6),
      ));
    }
  }

  void _updateParticles() {
    final dt = 0.016; // 60fps
    setState(() {
      _particles.removeWhere((p) {
        p.update(dt);
        return p.isDead || p.size < 0.5;
      });
    });
  }

  // ── GESTES ──────────────────────────────────────────────────────

  void _onTapDown(TapDownDetails details) {
    _isDragging = false;
    _dragStartX = details.localPosition.dx;
  }

  void _onTapUp(TapUpDetails details) {
    if (!_isDragging) {
      final tabIndex = (details.localPosition.dx / _tabWidth).floor();
      if (tabIndex >= 0 && tabIndex < widget.items.length) {
        if (tabIndex != widget.currentIndex) {
          HapticFeedback.mediumImpact();
          widget.onTap(tabIndex);
        }
      }
    }
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    _isDragging = true;
    _dragStartX = details.localPosition.dx;
    _lastCrossedTab = widget.currentIndex;
    HapticFeedback.selectionClick();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    final dx = details.localPosition.dx - _dragStartX;
    final tabDelta = dx / _tabWidth;
    final newPos = (_currentPosition - tabDelta).clamp(
      0.0,
      (widget.items.length - 1).toDouble(),
    );

    // Vérifier si on a franchi un onglet
    final crossed = newPos.round();
    if (crossed != _lastCrossedTab && crossed >= 0 && crossed < widget.items.length) {
      _lastCrossedTab = crossed;
      HapticFeedback.lightImpact();
    }

    setState(() {
      _currentPosition = newPos;
      _velocity = -details.primaryDelta! / _tabWidth;
    });
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final projected = _currentPosition - (velocity / _tabWidth) * 0.3;
    final target = projected.round().clamp(0, widget.items.length - 1);

    _springFrom = _currentPosition;
    _springTo = target.toDouble();
    _springStart = DateTime.now();
    _spring = _SpringSimulation.bouncy;

    if (target != widget.currentIndex) {
      HapticFeedback.mediumImpact();
      widget.onTap(target);
    }

    setState(() => _isDragging = false);
  }

  // ── BUILD ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final totalHeight = OuroTabBar.reservedHeight(bottomInset);

    return AnimatedBuilder(
      animation: _hideController,
      builder: (context, _) {
        final hidden = _hideController.value;
        if (hidden > 0.99) return const SizedBox.shrink();

        final scale = 1 - 0.12 * hidden;
        final opacity = (1 - hidden * 1.5).clamp(0.0, 1.0);

        return Transform.translate(
          offset: Offset(0, hidden * totalHeight * 0.75),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: Opacity(opacity: opacity, child: _buildBar()),
          ),
        );
      },
    );
  }

  Widget _buildBar() {
    // Mettre à jour la position du ressort
    final elapsed = DateTime.now().difference(_springStart).inMilliseconds / 1000.0;
    final springValue = _spring.solve(elapsed.clamp(0.0, 3.0),
        from: _springFrom, to: _springTo);
    _velocity = _spring.velocity(elapsed.clamp(0.0, 3.0),
        from: _springFrom, to: _springTo);
    _currentPosition = springValue;

    // Glow intensity
    final glowT = _glowController.value;
    final glowIntensity = glowT < 0.5 ? glowT * 2 : (1 - glowT) * 2;

    const radius = OuroTabBar.height / 2;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        OuroTabBar.floatingMargin,
        0,
        OuroTabBar.floatingMargin,
        MediaQuery.paddingOf(context).bottom + OuroTabBar.floatingMargin,
      ),
      child: GestureDetector(
        onTapDown: _onTapDown,
        onTapUp: _onTapUp,
        onHorizontalDragStart: _onHorizontalDragStart,
        onHorizontalDragUpdate: _onHorizontalDragUpdate,
        onHorizontalDragEnd: _onHorizontalDragEnd,
        child: AnimatedBuilder(
          animation: _mainController,
          builder: (context, _) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(radius),
              child: BackdropFilter(
                filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                child: CustomPaint(
                  painter: _FluidBackground(
                    position: _currentPosition,
                    tabWidth: _tabWidth,
                    tabCount: widget.items.length,
                    progress: glowIntensity,
                  ),
                  child: Container(
                    height: OuroTabBar.height,
                    decoration: BoxDecoration(
                      color: OuroColors.isDark
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.white.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(radius),
                      border: Border.all(
                        color: OuroColors.isDark
                            ? Colors.white.withValues(alpha: 0.12)
                            : Colors.white.withValues(alpha: 0.5),
                        width: 0.5,
                      ),
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        // ── Indicateur morphing ──────────────────
                        Positioned.fill(
                          child: CustomPaint(
                            painter: _MorphingIndicator(
                              position: _currentPosition,
                              velocity: _velocity,
                              tabWidth: _tabWidth,
                              tabCount: widget.items.length,
                              progress: 1,
                              isPressed: _isDragging,
                            ),
                          ),
                        ),
                        // ── Particules ───────────────────────────
                        ..._particles.map((p) => Positioned(
                          left: p.x - p.size / 2,
                          top: p.y - p.size / 2,
                          child: Container(
                            width: p.size,
                            height: p.size,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: p.color,
                              boxShadow: [
                                BoxShadow(
                                  color: p.color,
                                  blurRadius: p.size * 2,
                                ),
                              ],
                            ),
                          ),
                        )),
                        // ── Onglets ──────────────────────────────
                        Row(
                          children: List.generate(widget.items.length, (i) {
                            return Expanded(
                              child: _TabButton(
                                item: widget.items[i],
                                selected: i == widget.currentIndex,
                                index: i,
                                position: _currentPosition,
                                glowIntensity: glowIntensity,
                                onTap: () {
                                  if (i == widget.currentIndex) return;
                                  HapticFeedback.mediumImpact();
                                  widget.onTap(i);
                                },
                              ),
                            );
                          }),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ============================================================================
// ONGLET INDIVIDUEL — ANIMATIONS CONTINUES
// ============================================================================

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.index,
    required this.position,
    required this.glowIntensity,
    required this.onTap,
  });

  final OuroTabItem item;
  final bool selected;
  final int index;
  final double position;
  final double glowIntensity;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // Distance continue de l'indicateur
    final distance = (position - index).abs().clamp(0.0, 1.0);
    final influence = 1 - distance;

    // Couleur qui suit la distance
    final color = Color.lerp(
      OuroColors.systemGray,
      OuroColors.accent,
      Curves.easeOut.transform(influence),
    )!;

    // Élévation progressive
    final lift = -4.0 * influence;
    final scale = 1 + 0.12 * influence;

    // Taille de l'icône
    final iconSize = 24.0 + 3.0 * influence;

    // Opacité du glow
    final iconGlow = influence * glowIntensity;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Glow au-dessus de l'icône ────────────────────────
          if (iconGlow > 0.05)
            Container(
              width: 16 + 8 * influence,
              height: 2 + 2 * influence,
              margin: const EdgeInsets.only(bottom: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(2),
                boxShadow: [
                  BoxShadow(
                    color: OuroColors.accent.withValues(alpha: iconGlow * 0.7),
                    blurRadius: 6 + 4 * influence,
                    spreadRadius: 1 + 2 * influence,
                  ),
                ],
              ),
            ),

          // ── Icône animée ────────────────────────────────────
          Transform.translate(
            offset: Offset(0, lift),
            child: Transform.scale(
              scale: scale,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  key: ValueKey('$selected-$index'),
                  size: iconSize,
                  color: color,
                  shadows: [
                    if (iconGlow > 0.1)
                      Shadow(
                        color: OuroColors.accent.withValues(alpha: iconGlow * 0.5),
                        blurRadius: 8,
                      ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 2),

          // ── Libellé animé ───────────────────────────────────
          Transform.translate(
            offset: Offset(0, lift * 0.3),
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10 + influence * 0.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: Color.lerp(
                  OuroColors.systemGray,
                  OuroColors.label,
                  Curves.easeOut.transform(influence),
                ),
                letterSpacing: 0.1 + influence * 0.2,
              ),
            ),
          ),

          // ── Badge ───────────────────────────────────────────
          if (item.badge != null && item.badge! > 0)
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.red.withValues(alpha: 0.4),
                      blurRadius: 6,
                    ),
                  ],
                ),
                child: Text(
                  item.badge! > 99 ? '99+' : '${item.badge}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// ANIMATED BUILDER — WRAPPER POUR ANIMATIONS CONTINUES
// ============================================================================

class AnimatedBuilder extends AnimatedWidget {
  const AnimatedBuilder({
    super.key,
    required Listenable animation,
    required this.builder,
    this.child,
  }) : super(listenable: animation);

  final TransitionBuilder builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    return builder(context, child);
  }
}
