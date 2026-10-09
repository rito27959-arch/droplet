// ============================================================================
// LES RÉGLAGES D'APPARENCE — ce que Telegram laisse régler, Droplet aussi.
// ----------------------------------------------------------------------------
// Repris de l'écran « Apparence » de Telegram Android (`ThemeActivity`) :
//
//   • la TAILLE DU TEXTE des messages, de 12 à 30 points ;
//   • l'ARRONDI DES BULLES, de 0 (carré) à 20 points ;
//   • la COULEUR D'ACCENT, qui colore mes bulles, les boutons, les liens ;
//   • l'affichage de la LISTE DES DISCUSSIONS, sur deux ou trois lignes.
//
// Comme `OuroColors`, ces valeurs sont lues en statique par les écrans.
// `DropletApp` les pose à chaque construction, avant tout affichage (voir
// `personnalisation_provider.dart`).
// ============================================================================

import 'package:flutter/material.dart';

/// Une couleur d'accent, en version claire et sombre.
class Accent {
  const Accent(this.cle, this.clair, this.sombre);

  final String cle;
  final Color clair;
  final Color sombre;

  Color pour({required bool sombre}) => sombre ? this.sombre : clair;
}

class ReglagesApparence {
  ReglagesApparence._();

  // ── Bornes et valeurs par défaut ────────────────────────────────────
  static const double tailleTexteMin = 12;
  static const double tailleTexteMax = 30;
  static const double tailleTexteDefaut = 15;

  static const double rayonMin = 0;
  static const double rayonMax = 20;
  static const double rayonDefaut = 19;

  /// Les accents proposés : le bleu iOS d'abord, puis le cercle chromatique.
  /// Les versions sombres sont celles d'iOS (légèrement plus lumineuses).
  static const List<Accent> accents = [
    Accent('bleu', Color(0xFF007AFF), Color(0xFF0A84FF)),
    Accent('indigo', Color(0xFF5856D6), Color(0xFF5E5CE6)),
    Accent('violet', Color(0xFFAF52DE), Color(0xFFBF5AF2)),
    Accent('rose', Color(0xFFFF2D55), Color(0xFFFF375F)),
    Accent('rouge', Color(0xFFFF3B30), Color(0xFFFF453A)),
    Accent('orange', Color(0xFFFF9500), Color(0xFFFF9F0A)),
    Accent('vert', Color(0xFF34C759), Color(0xFF30D158)),
    Accent('menthe', Color(0xFF00C7BE), Color(0xFF63E6E2)),
    Accent('cyan', Color(0xFF32ADE6), Color(0xFF64D2FF)),
    Accent('graphite', Color(0xFF8E8E93), Color(0xFF98989D)),
  ];

  // ── L'état courant ──────────────────────────────────────────────────
  static double tailleTexte = tailleTexteDefaut;
  static double rayonBulles = rayonDefaut;
  static Accent accent = accents.first;
  static int lignesListe = 3;

  /// Le jeu de motifs du fond des discussions (index de `PackMotifs`).
  static int packMotifs = 0;

  /// La hauteur de ligne du texte des bulles, pour la taille courante.
  static const double interligne = 1.3;

  /// Le rayon du coin « de l'auteur » : jamais plus rond que le reste.
  static double get rayonQueue => rayonBulles < 6 ? rayonBulles : 6;

  static Accent accentParCle(String? cle) =>
      accents.firstWhere((a) => a.cle == cle, orElse: () => accents.first);
}
