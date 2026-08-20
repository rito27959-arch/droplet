// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Ce fichier reproduit l'échelle typographique EXACTE d'iOS — les mêmes
// tailles, les mêmes graisses, les mêmes hauteurs de ligne, et surtout le
// même « tracking » (l'espacement entre les lettres) qu'Apple utilise.
//
// LE DÉTAIL QUE 99 % DES APPS RATENT : Apple ne se contente pas de choisir
// des tailles de texte. À chaque taille correspond un tracking précis, et
// il est NÉGATIF sur les petites tailles (les lettres se resserrent) mais
// POSITIF sur les grandes (elles s'aèrent). C'est contre-intuitif, et
// c'est exactement ce qui fait qu'un texte « sent » l'iOS ou pas. Une app
// qui met le même espacement partout paraît toujours vaguement fausse
// sans qu'on sache dire pourquoi.
//
// Pour la police elle-même : SF Pro appartient à Apple et ne peut pas être
// embarquée dans l'app. Inter est son équivalent libre le plus proche —
// mêmes proportions, même clarté, dessinée pour les écrans. C'est ce
// qu'utilisent la plupart des apps réputées bien conçues sur Android.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Échelle typographique iOS (Dynamic Type, taille par défaut « Large »).
/// Valeurs officielles des Human Interface Guidelines d'Apple.
class OuroTypography {
  OuroTypography._();

  /// Construit un style à partir d'Inter, l'équivalent libre le plus
  /// proche de SF Pro.
  static TextStyle _font({
    required double size,
    required FontWeight weight,
    required double lineHeight,
    required double tracking,
    Color? color,
  }) {
    return GoogleFonts.inter(
      fontSize: size,
      fontWeight: weight,
      // Flutter attend un MULTIPLICATEUR de la taille, alors qu'Apple
      // publie une hauteur de ligne absolue en points — d'où la division.
      height: lineHeight / size,
      letterSpacing: tracking,
      color: color,
    );
  }

  // ══ GRANDS TITRES ════════════════════════════════════════════════════
  // Le titre qui occupe tout le haut d'un écran et se replie au scroll.

  /// Large Title — 34pt. Le grand titre en haut des écrans principaux.
  static TextStyle get largeTitle =>
      _font(size: 34, weight: FontWeight.w700, lineHeight: 41, tracking: 0.37);

  /// Title 1 — 28pt.
  static TextStyle get title1 =>
      _font(size: 28, weight: FontWeight.w700, lineHeight: 34, tracking: 0.36);

  /// Title 2 — 22pt.
  static TextStyle get title2 =>
      _font(size: 22, weight: FontWeight.w700, lineHeight: 28, tracking: 0.35);

  /// Title 3 — 20pt.
  static TextStyle get title3 =>
      _font(size: 20, weight: FontWeight.w600, lineHeight: 25, tracking: 0.38);

  // ══ CORPS DE TEXTE ═══════════════════════════════════════════════════
  // 17pt est LA taille de référence d'iOS — celle du texte d'un message,
  // d'une ligne de réglage, d'un bouton. Beaucoup d'apps descendent à 14
  // ou 15pt et paraissent aussitôt tassées et fatigantes à lire.

  /// Headline — 17pt semi-gras. Un titre de cellule, un nom de contact.
  static TextStyle get headline =>
      _font(size: 17, weight: FontWeight.w600, lineHeight: 22, tracking: -0.41);

  /// Body — 17pt. LE texte de référence : messages, contenu principal.
  static TextStyle get body =>
      _font(size: 17, weight: FontWeight.w400, lineHeight: 22, tracking: -0.41);

  /// Body semi-gras — pour mettre en avant sans changer de taille.
  static TextStyle get bodyEmphasized =>
      _font(size: 17, weight: FontWeight.w600, lineHeight: 22, tracking: -0.41);

  /// Callout — 16pt. Légèrement en retrait du corps principal.
  static TextStyle get callout =>
      _font(size: 16, weight: FontWeight.w400, lineHeight: 21, tracking: -0.32);

  /// Subheadline — 15pt. Sous-titres, aperçu du dernier message.
  static TextStyle get subheadline =>
      _font(size: 15, weight: FontWeight.w400, lineHeight: 20, tracking: -0.24);

  /// Footnote — 13pt. Notes de bas de section, explications.
  static TextStyle get footnote =>
      _font(size: 13, weight: FontWeight.w400, lineHeight: 18, tracking: -0.08);

  /// Caption 1 — 12pt. Horodatages, mentions discrètes.
  static TextStyle get caption1 =>
      _font(size: 12, weight: FontWeight.w400, lineHeight: 16, tracking: 0);

  /// Caption 2 — 11pt. Le plus petit texte lisible d'iOS.
  static TextStyle get caption2 =>
      _font(size: 11, weight: FontWeight.w400, lineHeight: 13, tracking: 0.06);

  // ══ SPÉCIALISÉS ══════════════════════════════════════════════════════

  /// En-tête de section d'une liste groupée — petites majuscules grises,
  /// exactement comme dans Réglages iOS.
  static TextStyle get sectionHeader =>
      _font(size: 13, weight: FontWeight.w400, lineHeight: 18, tracking: -0.08);

  /// Titre de barre de navigation (quand le grand titre est replié).
  static TextStyle get navTitle =>
      _font(size: 17, weight: FontWeight.w600, lineHeight: 22, tracking: -0.41);

  /// Chiffres tabulaires — pour les durées d'appel et compteurs, où les
  /// chiffres doivent avoir tous la même largeur (sinon « 1:11 » et
  /// « 0:00 » n'ont pas la même longueur et le texte tremble à chaque
  /// seconde qui passe).
  static TextStyle get monospacedDigits => GoogleFonts.inter(
    fontSize: 17,
    fontWeight: FontWeight.w400,
    letterSpacing: -0.41,
    fontFeatures: const [FontFeature.tabularFigures()],
  );

  // ══ COMPATIBILITÉ ════════════════════════════════════════════════════
  // Anciens noms Material, redirigés vers l'échelle iOS pour que tout
  // l'existant continue de compiler pendant la migration.

  static TextStyle get displayLarge => largeTitle;
  static TextStyle get displayMedium => title1;
  static TextStyle get displaySmall => title1;
  static TextStyle get headlineLarge => title2;
  static TextStyle get headlineMedium => title3;
  static TextStyle get headlineSmall => headline;
  static TextStyle get titleLarge => headline;
  static TextStyle get titleMedium => bodyEmphasized;
  static TextStyle get titleSmall => subheadline;
  static TextStyle get bodyLarge => body;
  static TextStyle get bodyMedium => callout;
  static TextStyle get bodySmall => subheadline;
  static TextStyle get labelLarge => bodyEmphasized;
  static TextStyle get labelMedium => footnote;
  static TextStyle get labelSmall => caption1;
  static TextStyle get caption => caption1;
  static TextStyle get captionMedium => caption1;
  static TextStyle get chatMessage => body;
  static TextStyle get chatTimestamp => caption2;
  static TextStyle get chatSender => footnote;
}
