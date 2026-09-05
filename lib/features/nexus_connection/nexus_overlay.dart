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

import '../../core/services/device_profile.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_typography.dart';
import 'nexus_controller.dart';
import 'nexus_event.dart';
import 'nexus_particles.dart';
import 'nexus_shader.dart';

/// Ce qu'il faut savoir pour jouer une séquence Nexus.
@immutable
class NexusRequest {
  const NexusRequest({
    required this.seed,
    required this.colorSignature,
    this.peerName = '',
  });

  final String seed;
  final int colorSignature;
  final String peerName;
}

/// La scène Nexus : on y dépose une demande, [NexusHost] la joue.
///
/// ── POURQUOI PAS UN `OverlayEntry` ────────────────────────────────────
///
/// C'était la première des deux causes de la panne. L'ancienne version
/// faisait `Overlay.of(context).insert(entry)` depuis `NotificationBridge`
/// — un widget placé dans le `builder` de `MaterialApp.router`, donc
/// AU-DESSUS du `Navigator`. Or c'est le `Navigator` qui fournit l'unique
/// `Overlay` de l'application : en remontant l'arbre depuis ce point, il
/// n'y en a aucun. `Overlay.of` lève alors une exception, à l'intérieur
/// d'un écouteur de flux — c'est-à-dire loin de tout écran, sans rien
/// afficher nulle part. L'animation ne se lançait jamais, et le drapeau
/// « Nexus en cours » restait bloqué douze secondes.
///
/// Le reste de l'app (appel entrant, appel de groupe, notifications) ne
/// passe déjà PAS par `Overlay` : ce sont des couches de `Stack` posées
/// dans ce même `builder`. Nexus fait désormais comme eux — c'est plus
/// simple, et cela ne peut plus dépendre d'un ancêtre qui n'existe pas.
class NexusStage {
  NexusStage._();

  static final ValueNotifier<NexusRequest?> _current =
      ValueNotifier<NexusRequest?>(null);

  /// La séquence en cours, ou `null`. Observée par [NexusHost].
  static ValueListenable<NexusRequest?> get current => _current;

  /// Lance une séquence. Sans effet si une autre est déjà à l'écran.
  static void play(NexusRequest request) {
    if (_current.value != null) return;
    _current.value = request;
  }

  /// Retire la séquence de l'écran.
  static void clear() => _current.value = null;
}

/// La couche qui affiche la séquence Nexus par-dessus toute l'app.
///
/// À placer dans le `builder` de `MaterialApp`, comme les autres couches
/// plein écran de Droplet.
class NexusHost extends StatelessWidget {
  const NexusHost({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NexusRequest?>(
      valueListenable: NexusStage.current,
      // ⚠️ TOUTE L'APPLICATION EST CE `child`. Le passer ici plutôt que de
      // le lire dans le `builder` évite de reconstruire l'arbre entier au
      // début et à la fin de chaque séquence — c'est-à-dire précisément
      // aux deux instants où l'on demande déjà beaucoup au téléphone.
      child: child,
      builder: (context, request, child) {
        return Stack(
          children: [
            child!,
            if (request != null)
              Positioned.fill(
                child: _NexusOverlayWidget(
                  // La clé garantit qu'une NOUVELLE rencontre repart d'un
                  // état neuf plutôt que de reprendre l'animation
                  // précédente au milieu.
                  key: ValueKey(request.seed),
                  seed: request.seed,
                  colorSignature: request.colorSignature,
                  peerName: request.peerName,
                  onComplete: NexusStage.clear,
                ),
              ),
          ],
        );
      },
    );
  }
}

// ── Widget interne ───────────────────────────────────────────────────────────

class _NexusOverlayWidget extends StatefulWidget {
  const _NexusOverlayWidget({
    super.key,
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
    )..onComplete = _terminer;
    _controller.start(this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Déjà terminée ? Évite qu'un tap et la fin naturelle ne se marchent
  /// dessus.
  bool _termine = false;

  /// Le shader a-t-il renoncé sur cet appareil ?
  bool _sansShader = DeviceProfile.sansShader;

  /// Écourte la séquence — l'utilisateur a tapé pour la passer.
  ///
  /// ⚠️ `stop()` et NON `dispose()` — c'est `dispose()` du `State` qui
  /// détruit le contrôleur, une seule fois. Voir `NexusController.stop`.
  void _terminer() {
    if (_termine) return;
    _termine = true;
    _controller.stop();
    widget.onComplete?.call();
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
            sansShader: _sansShader,
            onShaderIndisponible: () {
              // Le shader a échoué à la compilation sur un appareil qui
              // était pourtant censé le supporter. Sans lui, l'écran n'a
              // plus de source de lumière : on assombrit alors beaucoup
              // moins, sinon il ne reste qu'un rectangle noir pendant huit
              // secondes — le symptôme même qu'on vient de corriger.
              if (mounted && !_sansShader) {
                setState(() => _sansShader = true);
              }
            },
            onDismiss: _terminer,
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
    required this.sansShader,
    required this.onShaderIndisponible,
    required this.onDismiss,
  });

  final NexusControllerState state;
  final NexusParticles particles;
  final bool sansShader;
  final VoidCallback onShaderIndisponible;
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
            sansShader: sansShader,
          ),

          // ── Couche 2 : Shader Nexus ──────────────────────────────────
          //
          // Sauté entièrement sur les appareils modestes : un shader plein
          // écran y coûte plus cher que tout le reste de l'app réuni. Les
          // particules et le texte suffisent à raconter la même chose —
          // c'est le même arbitrage que le verre liquide de la barre
          // d'onglets (`ouro_glass.dart`), et il se prend au même endroit :
          // dans le code, pas dans un réglage à la charge de l'utilisateur.
          if (!DeviceProfile.sansShader)
            NexusShaderWidget(
              state: state.toShaderState(),
              // `isVisible` et non `isActive` : la couche reste montée
              // pendant la dissolution, sinon l'image la plus lumineuse
              // disparaît d'un coup au lieu de s'éteindre.
              active: state.isVisible,
              onUnavailable: onShaderIndisponible,
            ),

          // ── Couche 3 : Particules ────────────────────────────────────
          CustomPaint(
            painter: particles.painter(
              phase: state.phase,
              colorSignature: state.colorSignature,
              intensity: state.intensity,
              time: state.elapsedSeconds,
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
    required this.sansShader,
  });

  final NexusPhase phase;
  final double phaseProgress;
  final int colorSignature;

  /// Sans shader, l'écran n'a plus de source de lumière : on assombrit
  /// moins, pour que les particules restent lisibles au lieu de se perdre
  /// dans du noir.
  final bool sansShader;

  @override
  Widget build(BuildContext context) {
    final maxDarkness = sansShader ? 0.55 : 0.85;
    // Le fond passe de transparent (idle) à noir profond (awakening),
    // puis reste sombre pendant toute la séquence.
    final darkness = switch (phase) {
      NexusPhase.idle => 0.0,
      NexusPhase.awakening => phaseProgress * maxDarkness,
      // La dissolution rend l'app à l'utilisateur progressivement. Sans
      // cette ligne, l'assombrissement restait au maximum jusqu'à la
      // dernière image, puis l'écran réapparaissait d'un coup.
      NexusPhase.complete => maxDarkness * (1.0 - phaseProgress),
      _ => maxDarkness,
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
