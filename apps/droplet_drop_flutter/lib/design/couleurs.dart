// DROPLET LIQUID — les couleurs.
//
// Les neutres et les états viennent de Droplet Design (droplet_design.dart,
// commun à toute la famille) : la nuit de la couche « scène » en sombre, les
// gris d'Apple en clair. Seul l'accent est propre à Drop : son bleu liquide.
//
// Deux thèmes travaillés chacun pour lui-même (le clair n'est pas le sombre
// inversé) et une couleur d'accent au choix. Toutes les nuances d'état
// (succès, attention, erreur) gardent un contraste AA sur leur fond.
import 'package:flutter/material.dart';

import 'droplet_design.dart';

enum Accent { bleu, cyan, indigo, violet, vert }

class Palette {
  const Palette({
    required this.sombre,
    required this.fond,
    required this.fondEleve,
    required this.surface,
    required this.surfaceHaute,
    required this.trait,
    required this.texte,
    required this.texte2,
    required this.texte3,
    required this.accent,
    required this.accent2,
    required this.accentTexte,
    required this.succes,
    required this.attention,
    required this.erreur,
  });

  final bool sombre;

  /// Le fond de l'application.
  final Color fond;

  /// Les panneaux posés sur le fond (barres, colonnes).
  final Color fondEleve;

  /// Les cartes : listes, réglages, informations importantes.
  final Color surface;

  /// Une carte sur une carte (champ, pastille).
  final Color surfaceHaute;
  final Color trait;
  final Color texte;
  final Color texte2;
  final Color texte3;

  /// L'accent et son second ton : le dégradé « liquide » des actions.
  final Color accent;
  final Color accent2;

  /// L'accent lisible en texte sur le fond (contraste AA).
  final Color accentTexte;
  final Color succes;
  final Color attention;
  final Color erreur;

  LinearGradient get liquide => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [accent, accent2],
      );

  static (Color, Color, Color, Color) _accent(Accent a, bool sombre) => switch (a) {
        // (accent, second ton, accent texte sombre, accent texte clair)
        Accent.bleu => (DDMarque.drop, DDMarque.drop2, const Color(0xFF4DA8FF), const Color(0xFF0864CC)),
        Accent.cyan => (const Color(0xFF12B8E0), const Color(0xFF5CF0D4), const Color(0xFF34D8FF), const Color(0xFF007A99)),
        Accent.indigo => (const Color(0xFF4855E8), const Color(0xFF168BFF), const Color(0xFF8C95FF), const Color(0xFF3540C9)),
        Accent.violet => (const Color(0xFF8B5CF6), const Color(0xFFD06BFF), const Color(0xFFB79CFF), const Color(0xFF6D3FD9)),
        Accent.vert => (const Color(0xFF16B46C), const Color(0xFF7BE0A0), const Color(0xFF4FD893), const Color(0xFF0B7E49)),
      };

  factory Palette.de({required bool sombre, required Accent accent}) {
    final (a, a2, texteSombre, texteClair) = _accent(accent, sombre);
    if (sombre) {
      return Palette(
        sombre: true,
        // La nuit du site (drop.dropletmesh.app) : un noir bleuté profond,
        // des cartes de verre fumé à peine plus claires.
        fond: DDScene.nuit,
        fondEleve: DDScene.nuitEleve,
        surface: DDScene.verre,
        surfaceHaute: DDScene.verreHaut,
        trait: DDScene.trait,
        texte: DDScene.texte,
        texte2: DDScene.texte2,
        texte3: DDScene.texte3,
        accent: a,
        accent2: a2,
        accentTexte: texteSombre,
        succes: DDEtatsSombre.succes,
        attention: DDEtatsSombre.attention,
        erreur: DDEtatsSombre.erreur,
      );
    }
    return Palette(
      sombre: false,
      fond: DDClair.fondGroupe,
      fondEleve: const Color(0xFFFBFBFD),
      surface: DDClair.surface,
      surfaceHaute: DDClair.surfaceHaute,
      trait: DDClair.trait,
      texte: DDClair.texte,
      texte2: DDClair.texte2,
      texte3: DDClair.texte3,
      accent: a,
      accent2: a2,
      accentTexte: texteClair,
      succes: DDEtatsClair.succes,
      attention: DDEtatsClair.attention,
      erreur: DDEtatsClair.erreur,
    );
  }
}

/// La palette courante, accessible partout : `context.p`.
class PorteePalette extends InheritedWidget {
  const PorteePalette({super.key, required this.palette, required super.child});

  final Palette palette;

  @override
  bool updateShouldNotify(PorteePalette old) => old.palette != palette;
}

extension PaletteContexte on BuildContext {
  Palette get p => dependOnInheritedWidgetOfExactType<PorteePalette>()!.palette;
}
