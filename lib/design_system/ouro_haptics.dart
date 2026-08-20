// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le vocabulaire des VIBRATIONS de l'app — remplaçant intégral des sons
// d'interface, qui ont tous été supprimés lors de la refonte.
//
// POURQUOI SUPPRIMER LES SONS ? Parce qu'un son d'interface est joué à
// chaque interaction, toute la journée, souvent en public. Les apps
// perçues comme les plus haut de gamme (Linear, Things, Arc, et iOS
// lui-même) n'en émettent quasiment aucun : elles répondent par une
// VIBRATION, que l'utilisateur est le seul à percevoir. Le son est
// réservé à ce qui doit attirer l'attention à distance de l'écran — chez
// nous, uniquement la sonnerie d'appel entrant.
//
// LA RÈGLE D'OR : l'intensité doit correspondre à l'importance. Une
// vibration forte sur une action anodine est aussi désagréable qu'un son.
// D'où ces cinq niveaux nommés par INTENTION plutôt que par force — on
// écrit `OuroHaptics.selection()`, jamais `vibrerFort()`.
// ============================================================================

import 'package:flutter/services.dart';

/// Retours haptiques de Droplet, calés sur le vocabulaire d'iOS.
class OuroHaptics {
  OuroHaptics._();

  /// Vibration la plus légère — on parcourt des éléments : changement
  /// d'onglet, sélection dans une liste, curseur qui passe un cran.
  /// C'est de loin la plus utilisée.
  static void selection() => HapticFeedback.selectionClick();

  /// Impact léger — une action mineure a abouti : message envoyé,
  /// bascule d'un interrupteur, ouverture d'un panneau.
  static void light() => HapticFeedback.lightImpact();

  /// Impact moyen — une action significative a abouti : conversation
  /// archivée, groupe créé, appel décroché.
  static void medium() => HapticFeedback.mediumImpact();

  /// Impact fort — action lourde ou irréversible : raccrocher,
  /// supprimer, quitter un groupe. À utiliser avec parcimonie : trop
  /// fréquent, il perd tout son sens d'avertissement.
  static void heavy() => HapticFeedback.heavyImpact();

  /// Confirmation d'un moment important : identité vérifiée, sauvegarde
  /// réussie. Un impact moyen unique, net.
  static void success() => HapticFeedback.mediumImpact();

  /// Signalement d'un échec : envoi impossible, mauvais code de
  /// sécurité. Deux impacts rapprochés — le motif « quelque chose ne va
  /// pas », universellement compris sans avoir à regarder l'écran.
  static Future<void> error() async {
    await HapticFeedback.heavyImpact();
    await Future.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.heavyImpact();
  }

  /// Avertissement (non bloquant) — un impact moyen puis un léger.
  static Future<void> warning() async {
    await HapticFeedback.mediumImpact();
    await Future.delayed(const Duration(milliseconds: 90));
    await HapticFeedback.lightImpact();
  }
}
