// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le système de particules Nexus — des points lumineux qui vivent au-dessus
// du shader, ajoutant une couche de matière « poussière d'étoiles » qui
// donne de la profondeur à l'expérience.
//
// Les particules sont dessinées via `CustomPainter` (pas un shader) pour
// garder le GPU libre pour le shader principal. Elles suivent un mouvement
// de type fluid simulation simplifié (pas de vrai FBm, juste des sin/cos
// à fréquences décalées) pour rester légères.
//
// Deux types de particules coexistent :
//   1. Les POUSSIÈRES : minuscules, nombreuses, dérivent lentement.
//   2. Les ÉTINCELLES : plus grosses, plus rares, brillentbrief puis
//      s'éteignent — elles apparaissent surtout pendant les phases 3-5.
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'nexus_event.dart';

/// Une particule individuelle.
class _Particle {
  _Particle({
    required this.x,
    required this.y,
    required this.size,
    required this.speed,
    required this.phase,
    required this.isSpark,
    required this.lifetime,
  });

  double x, y;
  double size;
  double speed;
  double phase;
  bool isSpark;
  double lifetime; // durée de vie en secondes (-1 = infinie)

  /// Position actuelle calculée depuis le temps et les paramètres.
  Offset position(double time, Size screenSize) {
    final t = time * speed + phase;
    final dx = math.sin(t * 0.7) * 20 + math.cos(t * 0.3) * 10;
    final dy = math.cos(t * 0.5) * 15 + math.sin(t * 0.9) * 8;
    return Offset(
      (x * screenSize.width + dx) % screenSize.width,
      (y * screenSize.height + dy) % screenSize.height,
    );
  }

  /// Opacité de la particule (pulsa pour les étoiles, stable pour la
  /// poussière).
  double opacity(double time) {
    if (isSpark) {
      // Étincelle : apparition brève, fondu rapide
      final cycle = (time * speed + phase) % 3.0;
      return (cycle < 0.3) ? cycle / 0.3 : math.max(0.0, 1.0 - cycle / 2.7);
    }
    // Poussière : pulsation douce et lente
    return 0.3 + math.sin(time * 0.5 + phase) * 0.2;
  }
}

/// Système de particules pour l'expérience Nexus.
///
/// Peint par-dessus le shader pour ajouter de la matière lumineuse.
/// Les particules sont calculées une seule fois (constructeur) et
/// simplement déplacées par le painter — pas d'allocation en boucle.
class NexusParticles {
  NexusParticles({
    required String seed,
    int dustCount = 60,
    int sparkCount = 20,
  }) {
    final rng = _seededRandom(seed);
    _particles = [
      for (var i = 0; i < dustCount; i++)
        _Particle(
          x: rng.nextDouble(),
          y: rng.nextDouble(),
          size: 1.0 + rng.nextDouble() * 2.0,
          speed: 0.3 + rng.nextDouble() * 0.7,
          phase: rng.nextDouble() * math.pi * 2,
          isSpark: false,
          lifetime: -1,
        ),
      for (var i = 0; i < sparkCount; i++)
        _Particle(
          x: 0.2 + rng.nextDouble() * 0.6,
          y: 0.2 + rng.nextDouble() * 0.6,
          size: 2.0 + rng.nextDouble() * 3.0,
          speed: 0.8 + rng.nextDouble() * 1.2,
          phase: rng.nextDouble() * math.pi * 2,
          isSpark: true,
          lifetime: 2.0 + rng.nextDouble() * 2.0,
        ),
    ];
  }

  late final List<_Particle> _particles;

  static math.Random _seededRandom(String seed) {
    var hash = 0;
    for (var i = 0; i < seed.length; i++) {
      hash = ((hash << 5) - hash + seed.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return math.Random(hash);
  }

  /// Crée un painter qui dessine les particules.
  CustomPainter painter({
    required NexusPhase phase,
    required int colorSignature,
    required double intensity,
  }) {
    return _NexusParticlesPainter(
      particles: _particles,
      phase: phase,
      colorSignature: colorSignature,
      intensity: intensity,
    );
  }
}

/// CustomPainter qui dessine les particules Nexus.
class _NexusParticlesPainter extends CustomPainter {
  _NexusParticlesPainter({
    required this.particles,
    required this.phase,
    required this.colorSignature,
    required this.intensity,
  });

  final List<_Particle> particles;
  final NexusPhase phase;
  final int colorSignature;
  final double intensity;

  @override
  void paint(Canvas canvas, Size size) {
    if (intensity <= 0) return;

    final color = Color(colorSignature);
    final time = DateTime.now().millisecondsSinceEpoch / 1000.0;

    // Nombre de particules visibles selon la phase
    final visibility = _phaseVisibility();

    for (var i = 0; i < particles.length; i++) {
      if (i >= visibility) break;
      final p = particles[i];
      final pos = p.position(time, size);
      final opacity = p.opacity(time) * intensity;
      if (opacity <= 0.01) continue;

      final paint = Paint()
        ..color = color.withValues(alpha: opacity)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 0.8);

      // Le cœur de la particule est plus brillant
      canvas.drawCircle(pos, p.size, paint);

      // Halo plus large et plus doux
      canvas.drawCircle(
        pos,
        p.size * 2.5,
        Paint()
          ..color = color.withValues(alpha: opacity * 0.3)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 2),
      );
    }
  }

  /// Combien de particules sont visibles dans chaque phase.
  int _phaseVisibility() {
    switch (phase) {
      case NexusPhase.idle:
        return 0;
      case NexusPhase.awakening:
        return (particles.length * 0.3).round();
      case NexusPhase.dropletBirth:
        return (particles.length * 0.5).round();
      case NexusPhase.connectionWave:
        return (particles.length * 0.8).round();
      case NexusPhase.dualSync:
      case NexusPhase.identity:
        return particles.length;
      case NexusPhase.complete:
        return (particles.length * 0.2).round();
    }
  }

  @override
  bool shouldRepaint(covariant _NexusParticlesPainter oldDelegate) {
    return oldDelegate.intensity != intensity ||
        oldDelegate.phase != phase ||
        oldDelegate.colorSignature != colorSignature;
  }
}
