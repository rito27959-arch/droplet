// ============================================================================
// OURO TAB BAR — 10/10 LIQUID GLASS iOS
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:motor/motor.dart';

import 'ouro_colors.dart';
import 'ouro_glass.dart';

// ============================================================================
// JELLY TRANSFORM — SQUASH & STRETCH
// ============================================================================

Matrix4 _buildJellyTransform(double velocity) {
  final speed = velocity.abs().clamp(0.0, 1.0);
  if (speed == 0) return Matrix4.identity();
  final distortion = speed * 0.8;
  final squashX = 1.0 - distortion * 0.5;
  final stretchY = 1.0 + distortion * 0.3;
  return Matrix4.identity()..scaleByDouble(squashX, stretchY, 1, 1);
}

// ============================================================================
// PARTICULES
// ============================================================================

class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.vx,
    required this.vy,
    required this.life,
    required this.size,
  });

  double x, y, vx, vy, life, size;

  bool get isDead => life <= 0;

  void update(double dt) {
    x += vx * dt;
    y += vy * dt;
    vy += 300 * dt;
    life -= dt;
    size *= 0.97;
  }
}

// ============================================================================
// INDICATEUR MORPHING
// ============================================================================

class _MorphingIndicator extends StatelessWidget {
  const _MorphingIndicator({
    required this.child,
    required this.alignment,
    required this.velocity,
    required this.thickness,
    required this.tabCount,
  });

  final Widget child;
  final Alignment alignment;
  final double velocity;
  final double thickness;
  final int tabCount;

  @override
  Widget build(BuildContext context) {
    final rect = RelativeRect.lerp(
      RelativeRect.fill,
      const RelativeRect.fromLTRB(-14, -14, -14, -14),
      thickness,
    )!;

    return Positioned.fill(
      left: 4,
      right: 4,
      top: 4,
      bottom: 4,
      child: FractionallySizedBox(
        widthFactor: 1 / tabCount,
        alignment: alignment,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRelativeRect(
              rect: rect,
              child: SingleMotionBuilder(
                motion: Motion.bouncySpring(
                  duration: const Duration(milliseconds: 600),
                ),
                value: velocity,
                builder: (context, v, child) => Transform(
                  alignment: Alignment.center,
                  transform: _buildJellyTransform(v),
                  child: child,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// OURO TAB BAR
// ============================================================================

class OuroTabItem {
  const OuroTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
}

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
    with SingleTickerProviderStateMixin {
  late final AnimationController _hideController;
  late final AnimationController _glowController;
  late final AnimationController _particleController;

  double _xAlign = 0;
  bool _isDown = false;
  bool _isDragging = false;
  int _lastCrossedTab = 0;

  final List<_Particle> _particles = [];
  final math.Random _random = math.Random();

  double get _tabWidth {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || widget.items.isEmpty) return 80;
    return box.size.width / widget.items.length;
  }

  double _computeXAlignment(int index) {
    if (widget.items.length < 2) return 0;
    return (index / (widget.items.length - 1)).clamp(0.0, 1.0) * 2 - 1;
  }

  @override
  void initState() {
    super.initState();
    _xAlign = _computeXAlignment(widget.currentIndex);

    _hideController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: 0,
    );

    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );

    _particleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..addListener(_updateParticles);
  }

  @override
  void didUpdateWidget(covariant OuroTabBar old) {
    super.didUpdateWidget(old);

    if (widget.minimized != old.minimized) {
      widget.minimized ? _hideController.forward() : _hideController.reverse();
    }

    if (widget.currentIndex != old.currentIndex) {
      _xAlign = _computeXAlignment(widget.currentIndex);
      _spawnParticles(widget.currentIndex);
      _particleController.forward(from: 0);
      _glowController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _hideController.dispose();
    _glowController.dispose();
    _particleController.dispose();
    super.dispose();
  }

  void _spawnParticles(int tabIndex) {
    final center = _tabWidth * (tabIndex + 0.5);
    for (var i = 0; i < 14; i++) {
      final angle = _random.nextDouble() * 2 * math.pi;
      final speed = 60.0 + _random.nextDouble() * 120;
      _particles.add(_Particle(
        x: center,
        y: OuroTabBar.height / 2,
        vx: math.cos(angle) * speed,
        vy: math.sin(angle) * speed - 60,
        life: 0.3 + _random.nextDouble() * 0.5,
        size: 2.0 + _random.nextDouble() * 3.5,
      ));
    }
  }

  void _updateParticles() {
    const dt = 0.016;
    setState(() {
      _particles.removeWhere((p) {
        p.update(dt);
        return p.isDead || p.size < 0.5;
      });
    });
  }

  double _applyRubberBand(double value) {
    const resistance = 0.4;
    const maxOverdrag = 0.3;
    if (value < 0) {
      return -(value.abs() * resistance).clamp(0.0, maxOverdrag);
    }
    if (value > 1) {
      return 1 + ((value - 1) * resistance).clamp(0.0, maxOverdrag);
    }
    return value;
  }

  double _alignmentFromGlobal(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width == 0) return _xAlign;
    final local = box.globalToLocal(globalPosition);
    final indicatorWidth = 1.0 / widget.items.length;
    final draggableRange = 1.0 - indicatorWidth;
    final padding = indicatorWidth / 2;
    final raw = (local.dx / box.size.width).clamp(0.0, 1.0);
    final normalized = (raw - padding) / draggableRange;
    return (_applyRubberBand(normalized) * 2) - 1;
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final x = _alignmentFromGlobal(d.globalPosition);
    final currentTab = ((x + 1) / 2 * (widget.items.length - 1)).round();
    if (currentTab != _lastCrossedTab &&
        currentTab >= 0 &&
        currentTab < widget.items.length) {
      _lastCrossedTab = currentTab;
      HapticFeedback.selectionClick();
    }
    setState(() {
      _isDragging = true;
      _xAlign = x;
    });
  }

  void _onDragEnd(DragEndDetails d) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 1;
    final currentRelative = (_xAlign + 1) / 2;
    final indicatorWidth = 1.0 / widget.items.length;
    final draggableRange = 1.0 - indicatorWidth;
    final velocityX =
        (d.velocity.pixelsPerSecond.dx / width) / draggableRange;

    int targetTab;
    if (currentRelative < 0) {
      targetTab = 0;
    } else if (currentRelative > 1) {
      targetTab = widget.items.length - 1;
    } else {
      const velocityThreshold = 0.5;
      if (velocityX.abs() > velocityThreshold) {
        final projected =
            (currentRelative + velocityX * 0.3).clamp(0.0, 1.0);
        targetTab =
            (projected / indicatorWidth).round().clamp(0, widget.items.length - 1);
      } else {
        targetTab =
            (currentRelative / indicatorWidth).round().clamp(0, widget.items.length - 1);
      }
    }

    setState(() {
      _isDragging = false;
      _isDown = false;
      _xAlign = _computeXAlignment(targetTab);
    });

    if (targetTab != widget.currentIndex) {
      HapticFeedback.mediumImpact();
      widget.onTap(targetTab);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final totalHeight = OuroTabBar.reservedHeight(bottomInset);
    final targetAlignment = _computeXAlignment(widget.currentIndex);

    return SingleMotionBuilder(
      motion: widget.minimized
          ? const CupertinoMotion.smooth()
          : const CupertinoMotion.snappy(),
      value: widget.minimized ? 1.0 : 0.0,
      builder: (context, hidden, _) {
        if (hidden < 0.001) return _bar(bottomInset, targetAlignment);

        final scale = 1 - 0.12 * hidden;
        return Transform.translate(
          offset: Offset(0, hidden * totalHeight * 0.75),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: Opacity(
              opacity: (1 - hidden * 1.5).clamp(0.0, 1.0),
              child: _bar(bottomInset, targetAlignment),
            ),
          ),
        );
      },
    );
  }

  Widget _bar(double bottomInset, double targetAlignment) {
    const radius = OuroTabBar.height / 2;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        OuroTabBar.floatingMargin,
        0,
        OuroTabBar.floatingMargin,
        bottomInset + OuroTabBar.floatingMargin,
      ),
      child: GestureDetector(
        onTapDown: (d) {
          setState(() {
            _isDown = true;
            _xAlign = _alignmentFromGlobal(d.globalPosition);
          });
        },
        onHorizontalDragStart: (d) {
          _isDragging = true;
          _lastCrossedTab = widget.currentIndex;
          HapticFeedback.selectionClick();
        },
        onHorizontalDragUpdate: _onDragUpdate,
        onHorizontalDragEnd: _onDragEnd,
        onHorizontalDragCancel: () => setState(() {
          _isDragging = false;
          _isDown = false;
          _xAlign = targetAlignment;
        }),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Ombre
            Positioned.fill(
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                            alpha: OuroColors.isDark ? 0.42 : 0.13),
                        blurRadius: 22,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // Verre liquide
            OuroGlassLayer(
              child: _GlassIndicator(
                tabIndex: widget.currentIndex,
                tabCount: widget.items.length,
                onTabChanged: widget.onTap,
                isDragging: _isDragging,
                isDown: _isDown,
                xAlign: _xAlign,
                tabWidth: _tabWidth,
                particles: _particles,
                child: SizedBox(
                  height: OuroTabBar.height,
                  child: Row(
                    children: List.generate(widget.items.length, (i) {
                      final influence = (1 - (_xAlign - _computeXAlignment(i)).abs())
                          .clamp(0.0, 1.0);
                      return Expanded(
                        child: _TabButton(
                          item: widget.items[i],
                          selected: i == widget.currentIndex,
                          influence: influence,
                          onTap: () {
                            if (i == widget.currentIndex) return;
                            HapticFeedback.mediumImpact();
                            widget.onTap(i);
                          },
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// L'INDICATEUR DE VERRE LIQUIDE
// ============================================================================

class _GlassIndicator extends ConsumerStatefulWidget {
  const _GlassIndicator({
    required this.child,
    required this.tabIndex,
    required this.tabCount,
    required this.onTabChanged,
    required this.isDragging,
    required this.isDown,
    required this.xAlign,
    required this.tabWidth,
    required this.particles,
  });

  final Widget child;
  final int tabIndex;
  final int tabCount;
  final ValueChanged<int> onTabChanged;
  final bool isDragging;
  final bool isDown;
  final double xAlign;
  final double tabWidth;
  final List<_Particle> particles;

  @override
  ConsumerState<_GlassIndicator> createState() => _GlassIndicatorState();
}

class _GlassIndicatorState extends ConsumerState<_GlassIndicator> {
  double _computeXAlignment(int index) {
    if (widget.tabCount < 2) return 0;
    return (index / (widget.tabCount - 1)).clamp(0.0, 1.0) * 2 - 1;
  }

  @override
  Widget build(BuildContext context) {
    final targetAlignment = _computeXAlignment(widget.tabIndex);
    final degraded = ouroGlassDegraded(ref);

    return VelocityMotionBuilder(
      converter: const SingleMotionConverter(),
      value: widget.xAlign,
      motion: widget.isDragging
          ? const Motion.interactiveSpring(snapToEnd: true)
          : const Motion.bouncySpring(snapToEnd: true),
      builder: (context, x, velocity, _) {
        final alignment = Alignment(x, 0);
        final bar = LiquidGlass.grouped(
          clipBehavior: Clip.none,
          shape: const LiquidRoundedSuperellipse(borderRadius: 24),
          child: widget.child,
        );

        final wantsGlass =
            !degraded && (widget.isDown || (x - targetAlignment).abs() > 0.30);

        return SingleMotionBuilder(
          motion: const Motion.snappySpring(
            snapToEnd: true,
            duration: Duration(milliseconds: 300),
          ),
          value: wantsGlass ? 1.0 : 0.0,
          builder: (context, thickness, _) {
            return Stack(
              clipBehavior: Clip.none,
              children: [
                // Aplat de repos
                if (thickness < 1)
                  _MorphingIndicator(
                    alignment: alignment,
                    velocity: velocity,
                    thickness: thickness,
                    tabCount: widget.tabCount,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: thickness <= 0.2 ? 1 : 0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: OuroColors.accent.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(64),
                        ),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                // Contenu
                bar,
                // Vrai verre liquide
                if (thickness > 0)
                  _MorphingIndicator(
                    alignment: alignment,
                    velocity: velocity,
                    thickness: thickness,
                    tabCount: widget.tabCount,
                    child: LiquidGlass.withOwnLayer(
                      fake: degraded,
                      settings: LiquidGlassSettings(
                        visibility: thickness,
                        glassColor: OuroColors.accent.withValues(alpha: 0.14),
                        saturation: 1.5,
                        refractiveIndex: 1.15,
                        thickness: 20,
                        lightIntensity: 2,
                        chromaticAberration: 0.5,
                        blur: 0,
                      ),
                      shape: const LiquidRoundedSuperellipse(borderRadius: 64),
                      child: GlassGlow(child: const SizedBox.expand()),
                    ),
                  ),
              ],
            );
          },
          child: bar,
        );
      },
      child: widget.child,
    );
  }
}

// ============================================================================
// ONGLET
// ============================================================================

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.influence,
    required this.onTap,
  });

  final OuroTabItem item;
  final bool selected;
  final double influence;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color.lerp(
      OuroColors.systemGray,
      OuroColors.accent,
      Curves.easeOut.transform(influence),
    )!;

    final lift = -3.0 * influence;
    final scale = 1 + 0.10 * influence;

    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
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
                    key: ValueKey('$selected-${item.label}'),
                    size: 25,
                    color: color,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: Color.lerp(
                  OuroColors.systemGray,
                  OuroColors.label,
                  Curves.easeOut.transform(influence),
                ),
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
