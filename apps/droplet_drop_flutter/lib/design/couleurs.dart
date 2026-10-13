// DROPLET LIQUID — les couleurs.
//
// Deux thèmes travaillés chacun pour lui-même (le clair n'est pas le sombre
// inversé) et une couleur d'accent au choix. Toutes les nuances d'état
// (succès, attention, erreur) gardent un contraste AA sur leur fond.
import 'package:flutter/material.dart';

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
        Accent.bleu => (const Color(0xFF168BFF), const Color(0xFF34D8FF), const Color(0xFF4DA8FF), const Color(0xFF0864CC)),
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
        fond: const Color(0xFF080C16),
        fondEleve: const Color(0xFF0E1420),
        surface: const Color(0xFF141B28),
        surfaceHaute: const Color(0xFF202A39),
        trait: const Color(0x14FFFFFF),
        texte: const Color(0xFFF7F9FC),
        texte2: const Color(0xFFA5B0C1),
        texte3: const Color(0xFF6E7A8E),
        accent: a,
        accent2: a2,
        accentTexte: texteSombre,
        succes: const Color(0xFF34D27B),
        attention: const Color(0xFFFFB340),
        erreur: const Color(0xFFFF5D55),
      );
    }
    return Palette(
      sombre: false,
      fond: const Color(0xFFF3F6FA),
      fondEleve: const Color(0xFFFAFBFD),
      surface: const Color(0xFFFFFFFF),
      surfaceHaute: const Color(0xFFEDF1F7),
      trait: const Color(0x140B1220),
      texte: const Color(0xFF0B1220),
      texte2: const Color(0xFF55607A),
      texte3: const Color(0xFF8A94A8),
      accent: a,
      accent2: a2,
      accentTexte: texteClair,
      succes: const Color(0xFF138A4D),
      attention: const Color(0xFFB25E00),
      erreur: const Color(0xFFD12B21),
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
