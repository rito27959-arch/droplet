// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'animation qui joue quand on ENVOIE une réaction depuis la barre de
// tapback — exactement comme Telegram : l'émojis éclate en particules
// depuis la bulle, un éclat bref et satisfaisant qui confirme le geste.
//
// Chaque type de réaction a sa propre personnalité visuelle :
//   ❤️  — particules en forme de cœurs (réutilise la forme Bézier)
//   👍  — pouce qui grandit puis éclate en cercles verts
//   👎  — pouce vers le bas qui pulse en rouge
//   😂  — larmes bleues qui jaillissent
//   ‼️  — points d'exclamation radiants
//   ❓  — points d'interrogation qui spiralent
//
// C'est un CustomPainter branché sur un contrôleur d'animation : zéro
// widget reconstruit pendant les 800 ms de l'animation, exactement comme
// `heart_burst_overlay.dart`.
// ============================================================================

import 'dart:math';
import 'package:flutter/material.dart';

/// Overlay de réaction ancré sur une bulle — joue un effet de particules
/// au point [origin] puis s'auto-détruit.
///
/// Quand [target] est fourni, l'emoji voyage d'abord de l'origine vers
/// la cible (effet de propagation), puis éclate en particules sur la
/// bulle réagie — comme si ton doigt créait un lien visuel entre les
/// deux bulles.
class ReactionEffectOverlay extends StatefulWidget {
  const ReactionEffectOverlay({
    super.key,
    required this.emoji,
    required this.origin,
    this.target,
    required this.onDone,
  });

  final String emoji;
  final Offset origin;

  /// Position de la bulle réagie — si fournie, l'emoji y voyage d'abord.
  final Offset? target;
  final VoidCallback onDone;

  /// Un seul effet à la fois.
  static OverlayEntry? _active;

  /// Affiche l'effet de réaction par-dessus le contexte racine.
  static void show(
    BuildContext context, {
    required String emoji,
    required Offset origin,
    Offset? target,
  }) {
    _active?.remove();
    _active = null;
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => ReactionEffectOverlay(
        emoji: emoji,
        origin: origin,
        target: target,
        onDone: () {
          if (identical(_active, entry)) _active = null;
          entry.remove();
        },
      ),
    );
    _active = entry;
    Overlay.of(context, rootOverlay: true).insert(entry);
  }

  @override
  State<ReactionEffectOverlay> createState() => _ReactionEffectOverlayState();
}

class _ReactionEffectOverlayState extends State<ReactionEffectOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final List<_Particle> _particles;
  final _rand = Random();

  /// Position courante de l'emoji pendant la phase de propagation.
  Offset? _travelPosition;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _particles = List.generate(_particleCount, (_) => _randomParticle());

    // Si une cible est fournie, on anime d'abord le voyage de l'emoji
    if (widget.target != null) {
      _startPropagation().then((_) {
        _ctrl.forward().whenComplete(widget.onDone);
      });
    } else {
      _ctrl.forward().whenComplete(widget.onDone);
    }
  }

  /// Phase 1 : l'emoji voyage de l'origine vers la cible (300 ms).
  Future<void> _startPropagation() async {
    final start = widget.origin;
    final end = widget.target!;
    final duration = const Duration(milliseconds: 300);
    final startTime = DateTime.now();

    while (true) {
      await Future.delayed(const Duration(milliseconds: 16));
      final elapsed = DateTime.now().difference(startTime);
      final t = (elapsed.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

      // Courbe ease-out pour un effet naturel
      final eased = 1 - (1 - t) * (1 - t);
      setState(() {
        _travelPosition = Offset(
          start.dx + (end.dx - start.dx) * eased,
          start.dy + (end.dy - start.dy) * eased,
        );
      });

      if (t >= 1.0) break;
    }

    // Petit flash à l'arrivée
    setState(() => _travelPosition = null);
  }

  int get _particleCount {
    switch (widget.emoji) {
      case '❤️':
        return 14;
      case '👍':
        return 12;
      case '👎':
        return 10;
      case '😂':
        return 16;
      case '‼️':
        return 10;
      case '❓':
        return 10;
      default:
        return 12;
    }
  }

  _Particle _randomParticle() {
    final angle = _rand.nextDouble() * 2 * pi;
    final speed = 60 + _rand.nextDouble() * 100;
    return _Particle(
      angle: angle,
      speed: speed,
      size: 6 + _rand.nextDouble() * 10,
      delay: _rand.nextDouble() * 0.15,
      rotation: (_rand.nextDouble() - 0.5) * 2,
    );
  }

  @override
  void dispose() {
    ReactionEffectOverlay._active = null;
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: RepaintBoundary(
        child: Stack(
          children: [
            CustomPaint(
              size: Size.infinite,
              painter: _ReactionPainter(
                animation: _ctrl,
                emoji: widget.emoji,
                // Pendant la propagation, les particules éclatent sur la cible
                origin: widget.target ?? widget.origin,
                particles: _particles,
              ),
            ),
            // L'emoji en transit pendant la propagation
            if (_travelPosition != null)
              Positioned(
                left: _travelPosition!.dx - 14,
                top: _travelPosition!.dy - 14,
                child: Text(
                  widget.emoji,
                  style: const TextStyle(fontSize: 28),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Particle {
  final double angle;
  final double speed;
  final double size;
  final double delay;
  final double rotation;
  const _Particle({
    required this.angle,
    required this.speed,
    required this.size,
    required this.delay,
    required this.rotation,
  });
}

class _ReactionPainter extends CustomPainter {
  _ReactionPainter({
    required this.animation,
    required this.emoji,
    required this.origin,
    required this.particles,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final String emoji;
  final Offset origin;
  final List<_Particle> particles;

  /// Le chemin d'un cœur dans un carré 1×1 (réutilisé de heart_burst_overlay).
  static final Path _heartPath = () {
    final p = Path()..moveTo(0.5, 0.97);
    p.cubicTo(-0.16, 0.55, 0.06, -0.05, 0.5, 0.28);
    p.cubicTo(0.94, -0.05, 1.16, 0.55, 0.5, 0.97);
    p.close();
    return p;
  }();

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value;

    // ── L'ÉMOJI CENTRAL : grandit, pulse, puis disparaît ──────────────
    //
    // Il apparaît instantanément, atteint son max à 30 %, puis fond
    // vers zéro. C'est le premier indice visuel que la réaction a été
    // prise en compte.
    final emojiScale = t < 0.3
        ? Curves.easeOut.transform(t / 0.3) * 1.4
        : 1.4 * (1 - Curves.easeIn.transform((t - 0.3) / 0.7));
    final emojiOpacity = t < 0.15
        ? t / 0.15
        : t > 0.5
            ? (1 - t) / 0.5
            : 1.0;

    if (emojiOpacity > 0.01) {
      final tp = TextPainter(
        text: TextSpan(
          text: emoji,
          style: TextStyle(fontSize: 32 * emojiScale),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(
        origin.dx - tp.width / 2,
        origin.dy - tp.height / 2,
      );
      tp.paint(canvas, Offset.zero);
      canvas.restore();
    }

    // ── LES PARTICULES ────────────────────────────────────────────────
    //
    // Chaque particule part du centre, s'écarte dans la direction de
    // son angle à vitesse constante (pas d'accélération gravitationnelle :
    // on veut un éclat, pas une pluie). La disparition est douce.
    final pinceau = Paint()..isAntiAlias = true;

    for (final p in particles) {
      final pt = ((t - p.delay) / (1 - p.delay)).clamp(0.0, 1.0);
      if (pt <= 0) continue;

      final curved = Curves.easeOut.transform(pt);
      final distance = p.speed * curved;
      final dx = origin.dx + cos(p.angle) * distance;
      final dy = origin.dy + sin(p.angle) * distance;

      // Opacité : pleine au milieu, fondu aux deux extrémités.
      final opacity = pt < 0.1
          ? pt / 0.1
          : pt > 0.6
              ? (1 - pt) / 0.4
              : 1.0;
      if (opacity <= 0.01) continue;

      final scale = 0.3 + Curves.easeOutCubic.transform(pt.clamp(0.0, 0.4) / 0.4) * 0.7;
      final cote = p.size * scale;
      final rot = p.rotation * pt;

      pinceau.color = _particleColor.withValues(alpha: opacity.clamp(0.0, 1.0));

      canvas.save();
      canvas.translate(dx, dy);
      canvas.rotate(rot);

      switch (emoji) {
        case '❤️':
          // Cœur vectoriel.
          canvas.translate(-cote / 2, -cote / 2);
          canvas.scale(cote);
          canvas.drawPath(_heartPath, pinceau);
          break;
        case '👍':
          // Cercle vert (sensation « ok »).
          canvas.drawCircle(Offset.zero, cote / 2, pinceau);
          break;
        case '👎':
          // Losange rouge (sensation « non »).
          final path = Path()
            ..moveTo(0, -cote / 2)
            ..lineTo(cote / 2, 0)
            ..lineTo(0, cote / 2)
            ..lineTo(-cote / 2, 0)
            ..close();
          canvas.drawPath(path, pinceau);
          break;
        case '😂':
          // Goutte bleue (larme).
          final path = Path()
            ..moveTo(0, -cote / 2)
            ..quadraticBezierTo(cote / 2, 0, 0, cote / 2)
            ..quadraticBezierTo(-cote / 2, 0, 0, -cote / 2);
          canvas.drawPath(path, pinceau);
          break;
        case '‼️':
          // Petit rectangle vertical (point d'exclamation).
          final rect = RRect.fromRectAndRadius(
            Rect.fromCenter(center: Offset.zero, width: cote * 0.35, height: cote),
            Radius.circular(cote * 0.15),
          );
          canvas.drawRRect(rect, pinceau);
          break;
        case '❓':
          // Point d'interrogation simplifié (arc + point).
          final path = Path()
            ..addOval(Rect.fromCircle(center: Offset(0, -cote * 0.15), radius: cote * 0.35));
          canvas.drawPath(path, pinceau);
          canvas.drawCircle(Offset(0, cote * 0.3), cote * 0.1, pinceau);
          break;
        default:
          canvas.drawCircle(Offset.zero, cote / 2, pinceau);
      }

      canvas.restore();
    }
  }

  Color get _particleColor {
    switch (emoji) {
      case '❤️':
        return const Color(0xFFFF2D55);
      case '👍':
        return const Color(0xFF34C759);
      case '👎':
        return const Color(0xFFFF3B30);
      case '😂':
        return const Color(0xFF5AC8FA);
      case '‼️':
        return const Color(0xFFFFCC00);
      case '❓':
        return const Color(0xFFAF52DE);
      default:
        return const Color(0xFF8E8E93);
    }
  }

  @override
  bool shouldRepaint(_ReactionPainter old) => false;
}
