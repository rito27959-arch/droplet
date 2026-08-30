// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'overlay Nexus — l'expérience visuelle complète qui recouvre tout
// l'écran pendant la connexion entre deux appareils.
//
// Composition en couches (de l'arrière vers l'avant) :
//
//   ┌─ 1. Fond noir avec assombrissement progressif ──────────────────────┐
//   │                                                                    │
//   │  ┌─ 2. Shader Nexus (toutes les phases) ─────────────────────────┐ │
//   │  │                                                               │ │
//   │  │  ┌─ 3. Particules ─────────────────────────────────────────┐  │ │
//   │  │  │                                                         │  │ │
//   │  │  │  ┌─ 4. Texte (Phase 5 : identité) ───────────────────┐ │  │ │
//   │  │  │  │                                                    │ │  │ │
//   │  │  │  └────────────────────────────────────────────────────┘ │  │ │
//   │  │  └─────────────────────────────────────────────────────────┘  │ │
//   │  └───────────────────────────────────────────────────────────────┘ │
//   └────────────────────────────────────────────────────────────────────┘
//
// L'overlay est un `OverlayEntry` qui se place au-dessus de tout.
// Il se construit automatiquement, joue l'animation, puis se détruit.
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_typography.dart';
import 'nexus_controller.dart';
import 'nexus_event.dart';
import 'nexus_particles.dart';
import 'nexus_shader.dart';

/// Affiche l'expérience Nexus en overlay plein écran.
///
/// Mode d'emploi :
///
/// ```dart
/// // Depuis n'importe quel State :
/// NexusOverlay.show(
///   context,
///   seed: nexusEvent.seed,
///   colorSignature: nexusEvent.colorSignature,
///   peerName: 'Alice',
///   onComplete: () => Navigator.of(context).pop(),
/// );
/// ```
class NexusOverlay {
  NexusOverlay._();

  /// Affiche l'overlay Nexus.
  ///
  /// L'overlay prend le contrôle total de l'écran pendant ~8 secondes,
  /// puis se referme tout seul et appelle [onComplete].
  static OverlayEntry show(
    BuildContext context, {
    required String seed,
    required int colorSignature,
    String peerName = '',
    VoidCallback? onComplete,
  }) {
    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _NexusOverlayWidget(
        seed: seed,
        colorSignature: colorSignature,
        peerName: peerName,
        onComplete: () {
          entry.remove();
          onComplete?.call();
        },
      ),
    );
    Overlay.of(context).insert(entry);
    return entry;
  }
}

// ── Widget interne ───────────────────────────────────────────────────────────

class _NexusOverlayWidget extends StatefulWidget {
  const _NexusOverlayWidget({
    required this.seed,
    required this.colorSignature,
    required this.peerName,
    this.onComplete,
  });

  final String seed;
  final int colorSignature;
  final String peerName;
  final VoidCallback? onComplete;

  @override
  State<_NexusOverlayWidget> createState() => _NexusOverlayWidgetState();
}

class _NexusOverlayWidgetState extends State<_NexusOverlayWidget>
    with SingleTickerProviderStateMixin {
  late final NexusController _controller;
  late final NexusParticles _particles;

  @override
  void initState() {
    super.initState();
    _particles = NexusParticles(seed: widget.seed);
    _controller = NexusController(
      seed: widget.seed,
      colorSignature: widget.colorSignature,
      peerName: widget.peerName,
    )..onComplete = () {
        widget.onComplete?.call();
      };
    _controller.start(this);
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
      builder: (context, _) {
        final state = _controller.state;
        return Material(
          type: MaterialType.transparency,
          child: _NexusContent(
            state: state,
            particles: _particles,
            onDismiss: () {
              _controller.dispose();
              widget.onComplete?.call();
            },
          ),
        );
      },
    );
  }
}

// ── Contenu principal ────────────────────────────────────────────────────────

class _NexusContent extends StatelessWidget {
  const _NexusContent({
    required this.state,
    required this.particles,
    required this.onDismiss,
  });

  final NexusControllerState state;
  final NexusParticles particles;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return SizedBox.expand(
      child: Stack(
        children: [
          // ── Couche 1 : Fond noir avec assombrissement progressif ──────
          _Background(
            phase: state.phase,
            phaseProgress: state.phaseProgress,
            colorSignature: state.colorSignature,
          ),

          // ── Couche 2 : Shader Nexus ──────────────────────────────────
          NexusShaderWidget(
            state: state.toShaderState(),
            active: state.isActive,
          ),

          // ── Couche 3 : Particules ────────────────────────────────────
          CustomPaint(
            painter: particles.painter(
              phase: state.phase,
              colorSignature: state.colorSignature,
              intensity: state.intensity,
            ),
            size: Size.infinite,
          ),

          // ── Couche 4 : Contenu centré (goutte Phase 5) ──────────────
          if (state.phase == NexusPhase.identity)
            _IdentityContent(
              state: state,
              screenHeight: screenHeight,
            ),

          // ── Fermeture tactile ────────────────────────────────────────
          if (state.phase == NexusPhase.identity ||
              state.phase == NexusPhase.complete)
            Positioned.fill(
              child: GestureDetector(
                onTap: onDismiss,
                behavior: HitTestBehavior.opaque,
                child: const SizedBox.expand(),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Fond ─────────────────────────────────────────────────────────────────────

class _Background extends StatelessWidget {
  const _Background({
    required this.phase,
    required this.phaseProgress,
    required this.colorSignature,
  });

  final NexusPhase phase;
  final double phaseProgress;
  final int colorSignature;

  @override
  Widget build(BuildContext context) {
    // Le fond passe de transparent (idle) à noir profond (awakening),
    // puis reste sombre pendant toute la séquence.
    final darkness = switch (phase) {
      NexusPhase.idle => 0.0,
      NexusPhase.awakening => phaseProgress * 0.85,
      _ => 0.85,
    };

    return Container(
      color: Colors.black.withValues(alpha: darkness),
    );
  }
}

// ── Contenu identité (Phase 5) ──────────────────────────────────────────────

class _IdentityContent extends StatelessWidget {
  const _IdentityContent({
    required this.state,
    required this.screenHeight,
  });

  final NexusControllerState state;
  final double screenHeight;

  @override
  Widget build(BuildContext context) {
    // Le texte apparaît progressivement dans la phase identity.
    final fadeIn = Curves.easeOut.transform(
      state.phaseProgress.clamp(0.0, 1.0),
    );
    final color = Color(state.colorSignature);

    return Positioned(
      top: screenHeight * 0.38,
      left: 0,
      right: 0,
      child: Opacity(
        opacity: fadeIn,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Réseau mesh dans la goutte ──────────────────────────────
            SizedBox(
              width: 120,
              height: 120,
              child: CustomPaint(
                painter: _MeshNetworkPainter(
                  color: color,
                  progress: state.phaseProgress,
                  seed: state.seed,
                ),
              ),
            ),

            SizedBox(height: DesignTokens.space6),

            // ── Texte « projeté dans la lumière » ──────────────────────
            Text(
              'Connexion établie',
              style: OuroTypography.headlineMedium.copyWith(
                color: Colors.white.withValues(alpha: fadeIn * 0.9),
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: DesignTokens.space3),

            Text(
              'Réseau privé actif',
              style: OuroTypography.bodyMedium.copyWith(
                color: color.withValues(alpha: fadeIn * 0.7),
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),

            SizedBox(height: DesignTokens.space2),

            Text(
              'Chiffrement E2EE',
              style: OuroTypography.labelSmall.copyWith(
                color: Colors.white.withValues(alpha: fadeIn * 0.5),
                letterSpacing: 2.0,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Painter du réseau mesh (Phase 5) ────────────────────────────────────────

class _MeshNetworkPainter extends CustomPainter {
  _MeshNetworkPainter({
    required this.color,
    required this.progress,
    required this.seed,
  });

  final Color color;
  final double progress;
  final String seed;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final rng = _seededRandom(seed);

    // 8 nœuds du réseau mesh, disposés en cercle
    const nodeCount = 8;
    final nodes = List<Offset>.generate(nodeCount, (i) {
      final angle = (i / nodeCount) * math.pi * 2 - math.pi / 2;
      final radius = size.width * 0.35 + rng.nextDouble() * 8;
      return Offset(
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
    });

    // Dessiner les connexions entre nœuds
    for (var i = 0; i < nodeCount; i++) {
      for (var j = i + 1; j < nodeCount; j++) {
        // Seulement certaines connexions (pas un graphe complet)
        if ((i + j) % 3 == 0) {
          // Animation progressive : la ligne apparaît quand le progress
          // la dépasse.
          final lineProgress = (progress * nodeCount - i * 0.5)
              .clamp(0.0, 1.0);
          if (lineProgress > 0) {
            final path = Path()
              ..moveTo(nodes[i].dx, nodes[i].dy)
              ..lineTo(nodes[j].dx, nodes[j].dy);
            canvas.drawPath(
              path,
              Paint()
                ..color = color.withValues(alpha: lineProgress * 0.25)
                ..strokeWidth = 0.8
                ..style = PaintingStyle.stroke,
            );
          }
        }
      }
    }

    // Dessiner les nœuds
    for (var i = 0; i < nodeCount; i++) {
      final nodeProgress = (progress * nodeCount - i * 0.3)
          .clamp(0.0, 1.0);
      if (nodeProgress <= 0) continue;

      final paint = Paint()
        ..color = color.withValues(alpha: nodeProgress * 0.8)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 2);

      canvas.drawCircle(nodes[i], 3.0 * nodeProgress, paint);

      // Halo
      canvas.drawCircle(
        nodes[i],
        8.0 * nodeProgress,
        Paint()
          ..color = color.withValues(alpha: nodeProgress * 0.2)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4),
      );
    }
  }

  static math.Random _seededRandom(String seed) {
    var hash = 0;
    for (var i = 0; i < seed.length; i++) {
      hash = ((hash << 5) - hash + seed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return math.Random(hash);
  }

  @override
  bool shouldRepaint(covariant _MeshNetworkPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color;
  }
}
