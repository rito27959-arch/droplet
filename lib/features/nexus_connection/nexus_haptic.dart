// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// La chorégraphie haptique de l'expérience Nexus.
//
// Chaque phase visuelle a son propre retour tactile, calé sur les
// durées d'animation. Les vibrations ne sont JAMAIS synchronisées par
// une horloge partagée (impossible) — elles sont déclenchées localement
// à chaque phase, ce qui donne une sensation identique sur les deux
// appareils même si leur timing est décalé de quelques millisecondes.
//
// Le vocabulaire suit la même logique que `OuroHaptics` : on nomme
// par INTENTION, pas par force.
// ============================================================================

import 'package:flutter/services.dart';

import 'nexus_event.dart';

/// Choregraphie haptique pour l'expérience Nexus.
class NexusHaptics {
  NexusHaptics._();

  /// Phase 1 — Éveil : un battement léger, comme un cœur qui s'éveille.
  ///
  /// Double impact léger espacé de 80 ms : le premier « startled », le
  /// second « confirme ». Ça crée la sensation d'un battement cardiaque.
  static Future<void> awakening() async {
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 80));
    await HapticFeedback.lightImpact();
  }

  /// Phase 2 — Naissance de la goutte : un impact moyen unique, net
  /// comme l'apparition d'une surface de tension.
  static void dropletBirth() => HapticFeedback.mediumImpact();

  /// Phase 3 — Connexion : une vibration longue et ascendante.
  ///
  /// Trois impacts de force croissante, espacés de 60 ms — comme une
  /// vague qui monte. Pas de heavy (trop brutal pour un moment beau).
  static Future<void> connectionWave() async {
    await HapticFeedback.lightImpact();
    await Future.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 60));
    await HapticFeedback.mediumImpact();
  }

  /// Phase 4 — Synchronisation : un impact unique, le plus intense
  /// de la séquence. C'est le « moment » — la confirmation que les
  /// deux appareils sont liés.
  static void dualSync() => HapticFeedback.heavyImpact();

  /// Phase 5 — Identité : un battement doux de résolution, comme un
  /// exhalé après la montée.
  static void identity() => HapticFeedback.selectionClick();

  /// Retour haptique adapté au contexte.
  ///
  /// [phase] : la phase Nexus à signaler.
  /// [intensity] : facteur d'intensité (0 à 1), pour adaptation batterie.
  static Future<void> forPhase(NexusPhase phase, {double intensity = 1.0}) async {
    if (intensity <= 0) return;
    switch (phase) {
      case NexusPhase.awakening:
        await awakening();
      case NexusPhase.dropletBirth:
        dropletBirth();
      case NexusPhase.connectionWave:
        await connectionWave();
      case NexusPhase.dualSync:
        dualSync();
      case NexusPhase.identity:
        identity();
      case NexusPhase.idle:
      case NexusPhase.complete:
        break;
    }
  }
}
