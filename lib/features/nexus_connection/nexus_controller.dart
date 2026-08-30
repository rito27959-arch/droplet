// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le chef d'orchestre de l'expérience Nexus. Ce contrôleur :
//
//   1. Avance automatiquement d'une phase à la suivante.
//   2. Calcule le timing de chaque phase (progression 0→1).
//   3. Déclenche les retours haptiques au bon moment.
//   4. Produit l'état shader (`NexusShaderState`) à chaque image.
//   5. Notifie les écrans quand l'expérience commence/évolue/finit.
//
// Il ne dessine RIEN. Il ne fait que CALCULER et PUBILER l'état.
// C'est la séparation MVC : ce fichier est le M, le V est
// `NexusOverlay`.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'nexus_event.dart';
import 'nexus_haptic.dart';
import 'nexus_shader.dart';

/// Durées de chaque phase en millisecondes.
///
/// Ces valeurs sont le rythme de la séquence. Elles ont été calibrées
/// pour que chaque phase ait le temps de « respirer » sans jamais
/// devenir longue. L'expérience totale dure environ 8 secondes.
class NexusDurations {
  NexusDurations._();

  /// Phase 1 — Éveil : le fond s'assombrit, les particules apparaissent.
  static const Duration awakening = Duration(milliseconds: 1800);

  /// Phase 2 — Naissance : la goutte naît au centre.
  static const Duration dropletBirth = Duration(milliseconds: 2200);

  /// Phase 3 — Connexion : l'onde traverse l'écran.
  static const Duration connectionWave = Duration(milliseconds: 2000);

  /// Phase 4 — Sync : les deux écrans se synchronisent.
  static const Duration dualSync = Duration(milliseconds: 1500);

  /// Phase 5 — Identité : le réseau mesh et les informations.
  static const Duration identity = Duration(milliseconds: 1800);

  /// Phase 6 — Dissolution : l'overlay se referme.
  static const Duration complete = Duration(milliseconds: 600);

  /// Durée totale de l'expérience.
  static Duration get total => awakening +
      dropletBirth +
      connectionWave +
      dualSync +
      identity +
      complete;
}

/// État lu par les écrans pour construire l'UI.
@immutable
class NexusControllerState {
  const NexusControllerState({
    required this.phase,
    required this.phaseProgress,
    required this.overallProgress,
    required this.intensity,
    required this.seed,
    required this.colorSignature,
    required this.peerName,
  });

  /// Phase actuelle.
  final NexusPhase phase;

  /// Progression dans la phase (0→1).
  final double phaseProgress;

  /// Progression globale de l'expérience (0→1).
  final double overallProgress;

  /// Intensité du shader (0→1).
  final double intensity;

  /// Seed partagée (identique sur les deux appareils).
  final String seed;

  /// Couleur signature (ARGB, identique sur les deux appareils).
  final int colorSignature;

  /// Nom du pair distant (pour l'affichage Phase 5).
  final String peerName;

  /// L'expérience est-elle en cours (phases 1-5) ?
  bool get isActive =>
      phase.index >= NexusPhase.awakening.index &&
      phase.index <= NexusPhase.identity.index;

  /// L'expérience est-elle terminée ?
  bool get isComplete => phase == NexusPhase.complete;

  /// Crée un état shader correspondant.
  NexusShaderState toShaderState() => NexusShaderState(
        time: 0, // le shader a son propre ticker
        phase: phase,
        phaseProgress: phaseProgress,
        overallProgress: overallProgress,
        seed: seed,
        colorSignature: colorSignature,
        intensity: intensity,
      );
}

/// Contrôleur de la séquence Nexus.
///
/// À créer une fois par session de connexion, puis appeler [start]
/// quand l'animation doit commencer. Le contrôleur avance seul
/// d'une phase à la suivante.
class NexusController extends ChangeNotifier {
  NexusController({
    required this.seed,
    required this.colorSignature,
    this.peerName = '',
    this.intensityMultiplier = 1.0,
  }) : _state = NexusControllerState(
          phase: NexusPhase.idle,
          phaseProgress: 0,
          overallProgress: 0,
          intensity: 0,
          seed: seed,
          colorSignature: colorSignature,
          peerName: peerName,
        );

  final String seed;
  final int colorSignature;
  final String peerName;
  final double intensityMultiplier;

  NexusControllerState _state;
  NexusControllerState get state => _state;

  Timer? _phaseTimer;
  Ticker? _ticker;

  /// Notifié quand l'expérience est terminée et l'overlay doit se fermer.
  VoidCallback? onComplete;

  /// Notifié à chaque changement d'état significatif.
  void Function(NexusControllerState)? onStateChanged;

  // ── Lancement ──────────────────────────────────────────────────────────────

  /// Démarre l'expérience Nexus.
  ///
  /// [tickerProvider] est nécessaire pour créer le ticker interne.
  /// Doit être appelé depuis un State avec SingleTickerProviderStateMixin.
  void start(TickerProvider tickerProvider) {
    debugPrint('[NexusController] Démarrage');
    _ticker = tickerProvider.createTicker(_onTick);
    _ticker!.start();
    _startPhase(NexusPhase.awakening);
  }

  // ── Avancement par phase ──────────────────────────────────────────────────

  void _startPhase(NexusPhase phase) {
    final duration = _durationFor(phase);
    _updateState(phase, 0.0);

    // Haptique au début de la phase
    NexusHaptics.forPhase(phase, intensity: intensityMultiplier);

    _phaseTimer?.cancel();
    if (duration == Duration.zero) {
      // Phase terminale : passer directement à complete
      _finish();
      return;
    }

    _phaseTimer = Timer(duration, () {
      final next = _nextPhase(phase);
      if (next != null) {
        _startPhase(next);
      } else {
        _finish();
      }
    });
  }

  NexusPhase? _nextPhase(NexusPhase current) {
    switch (current) {
      case NexusPhase.idle:
        return NexusPhase.awakening;
      case NexusPhase.awakening:
        return NexusPhase.dropletBirth;
      case NexusPhase.dropletBirth:
        return NexusPhase.connectionWave;
      case NexusPhase.connectionWave:
        return NexusPhase.dualSync;
      case NexusPhase.dualSync:
        return NexusPhase.identity;
      case NexusPhase.identity:
        return NexusPhase.complete;
      case NexusPhase.complete:
        return null;
    }
  }

  Duration _durationFor(NexusPhase phase) {
    switch (phase) {
      case NexusPhase.idle:
        return Duration.zero;
      case NexusPhase.awakening:
        return NexusDurations.awakening;
      case NexusPhase.dropletBirth:
        return NexusDurations.dropletBirth;
      case NexusPhase.connectionWave:
        return NexusDurations.connectionWave;
      case NexusPhase.dualSync:
        return NexusDurations.dualSync;
      case NexusPhase.identity:
        return NexusDurations.identity;
      case NexusPhase.complete:
        return NexusDurations.complete;
    }
  }

  // ── Mise à jour à chaque frame ────────────────────────────────────────────

  void _onTick(Duration elapsed) {
    if (_state.phase == NexusPhase.idle ||
        _state.phase == NexusPhase.complete) {
      return;
    }

    // Calculer la progression dans la phase courante
    final phaseDuration = _durationFor(_state.phase).inMilliseconds;
    if (phaseDuration == 0) return;

    // Le temps passé dans la phase actuelle est calculé depuis
    // le timer, mais on utilise le tick du ticker pour le shader.
    final elapsedMs = elapsed.inMilliseconds;
    final totalBeforePhase = _totalMsBefore(_state.phase);
    final phaseElapsed = (elapsedMs - totalBeforePhase).clamp(0, phaseDuration);
    final phaseProgress = phaseElapsed / phaseDuration;

    // Intensité : monte pendant awakening, reste à 1, puis redescend
    // pendant complete.
    double intensity;
    if (_state.phase == NexusPhase.awakening) {
      intensity = phaseProgress * intensityMultiplier;
    } else if (_state.phase == NexusPhase.complete) {
      intensity = (1.0 - phaseProgress) * intensityMultiplier;
    } else {
      intensity = intensityMultiplier;
    }

    // Progression globale
    final totalMs = NexusDurations.total.inMilliseconds;
    final overall = (elapsedMs / totalMs).clamp(0.0, 1.0);

    _updateState(_state.phase, phaseProgress,
        intensity: intensity, overallProgress: overall);
  }

  int _totalMsBefore(NexusPhase phase) {
    var total = 0;
    for (final p in NexusPhase.values) {
      if (p == phase) break;
      total += _durationFor(p).inMilliseconds;
    }
    return total;
  }

  void _updateState(
    NexusPhase phase,
    double phaseProgress, {
    double? intensity,
    double? overallProgress,
  }) {
    final newState = NexusControllerState(
      phase: phase,
      phaseProgress: phaseProgress,
      overallProgress: overallProgress ?? _state.overallProgress,
      intensity: intensity ?? _state.intensity,
      seed: seed,
      colorSignature: colorSignature,
      peerName: peerName,
    );
    _state = newState;
    onStateChanged?.call(newState);
    notifyListeners();
  }

  // ── Fin ───────────────────────────────────────────────────────────────────

  void _finish() {
    debugPrint('[NexusController] Terminé');
    _ticker?.stop();
    _phaseTimer?.cancel();
    _updateState(NexusPhase.complete, 1.0, intensity: 0, overallProgress: 1.0);
    onComplete?.call();
  }

  @override
  void dispose() {
    _phaseTimer?.cancel();
    _ticker?.dispose();
    super.dispose();
  }
}
