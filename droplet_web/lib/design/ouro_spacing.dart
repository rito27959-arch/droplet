// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Une version plus courte et plus ancienne de `design_tokens.dart` :
// juste les tailles d'espacement (xs = très petit, jusqu'à xxxl = très
// grand) et d'arrondi des coins. Certains écrans plus anciens de l'app
// utilisent encore ces noms-ci plutôt que ceux de `design_tokens.dart` —
// les deux fichiers existent en parallèle, mais racontent la même idée :
// des tailles standardisées à réutiliser partout, plutôt que d'inventer
// un nombre différent à chaque fois.
// ============================================================================

class OuroSpacing {
  OuroSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 16;
  static const double lg = 24;
  static const double xl = 32;
  static const double xxl = 48;
  static const double xxxl = 64;

  static const double radiusSm = 8;
  static const double radiusMd = 16;
  static const double radiusLg = 20;
  static const double radiusXl = 24;
  static const double radiusFull = 999;
}
