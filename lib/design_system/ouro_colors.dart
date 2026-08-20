// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LA boîte de peinture de Droplet — les couleurs SYSTÈME exactes d'iOS,
// celles qu'Apple utilise dans Messages, Réglages et Téléphone, en
// version SOMBRE et CLAIRE.
//
// Pourquoi copier Apple plutôt qu'inventer ? Parce que ces couleurs ont
// été calibrées pendant des années pour rester lisibles dans les deux
// modes, se marier entre elles, et sembler « justes » à l'œil. Une app
// qui les respecte paraît immédiatement native ; une app qui invente ses
// propres gris paraît toujours légèrement fausse.
//
// LA RÈGLE : une SEULE couleur d'accent dans toute l'app (le bleu). Tout
// le reste est une nuance de gris. Les autres couleurs (rouge, vert,
// orange) ne servent QUE de signaux — jamais de décoration. C'est cette
// retenue qui fait le haut de gamme.
//
// ── COMMENT FONCTIONNE LE MODE CLAIR / SOMBRE ───────────────────────────
//
// Chaque couleur est un ACCESSEUR (et non une constante) qui renvoie la
// valeur claire ou sombre selon [brightness].
//
// Ce choix est délibéré : il permet aux 689 endroits de l'app qui écrivent
// `OuroColors.label` de basculer automatiquement, sans qu'aucun d'eux
// n'ait à savoir dans quel mode on se trouve. L'alternative — passer le
// contexte à chaque couleur — aurait imposé de réécrire tous les écrans.
//
// [brightness] est positionné par `DropletApp` AVANT que quoi que ce soit
// ne se dessine, donc tout widget lit forcément la bonne valeur.
// ============================================================================

import 'package:flutter/material.dart';

/// Couleurs système iOS, valeurs officielles Apple, en clair et en sombre.
class OuroColors {
  OuroColors._();

  // ══ MODE COURANT ═════════════════════════════════════════════════════

  static Brightness _brightness = Brightness.dark;

  /// Mode d'affichage actuellement appliqué à toute l'app.
  static Brightness get brightness => _brightness;

  /// Bascule toute la palette. Appelé par `DropletApp` à chaque
  /// construction, donc avant tout affichage.
  static void setBrightness(Brightness value) => _brightness = value;

  static bool get isDark => _brightness == Brightness.dark;

  /// Choisit entre la version claire et la version sombre.
  static Color _pick(Color light, Color dark) => isDark ? dark : light;

  // ══ FONDS ════════════════════════════════════════════════════════════
  // iOS empile les surfaces sur trois niveaux. En mode sombre, plus une
  // surface est « haute », plus elle est CLAIRE ; en mode clair, c'est
  // l'inverse — les surfaces hautes restent blanches et c'est le fond qui
  // s'assombrit légèrement. Ce n'est pas une symétrie mais bien deux
  // logiques distinctes, et c'est ce qui rend les deux modes crédibles.

  /// Le fond le plus profond. En sombre : noir pur, indispensable sur
  /// OLED (pixels éteints = contraste infini et batterie économisée).
  static Color get systemBackground =>
      _pick(const Color(0xFFFFFFFF), const Color(0xFF000000));

  /// Surface posée sur le fond (carte, cellule de liste).
  static Color get secondarySystemBackground =>
      _pick(const Color(0xFFF2F2F7), const Color(0xFF1C1C1E));

  /// Surface posée sur une surface (champ dans une carte).
  static Color get tertiarySystemBackground =>
      _pick(const Color(0xFFFFFFFF), const Color(0xFF2C2C2E));

  // ── Fonds « groupés » (écrans de type Réglages) ─────────────────────

  static Color get systemGroupedBackground =>
      _pick(const Color(0xFFF2F2F7), const Color(0xFF000000));
  static Color get secondarySystemGroupedBackground =>
      _pick(const Color(0xFFFFFFFF), const Color(0xFF1C1C1E));
  static Color get tertiarySystemGroupedBackground =>
      _pick(const Color(0xFFF2F2F7), const Color(0xFF2C2C2E));

  // ══ TEXTE ════════════════════════════════════════════════════════════
  // Quatre niveaux d'importance. Apple ne les fait pas varier en teinte
  // mais en OPACITÉ — c'est ce qui garde l'ensemble cohérent sur
  // n'importe quel fond.

  static Color get label =>
      _pick(const Color(0xFF000000), const Color(0xFFFFFFFF));

  /// Sous-titres, métadonnées (60 % d'opacité).
  static Color get secondaryLabel =>
      _pick(const Color(0x993C3C43), const Color(0x99EBEBF5));

  /// Indications discrètes (30 %).
  static Color get tertiaryLabel =>
      _pick(const Color(0x4D3C3C43), const Color(0x4DEBEBF5));

  /// Texte d'invite dans un champ vide (18 %).
  static Color get quaternaryLabel =>
      _pick(const Color(0x2E3C3C43), const Color(0x2EEBEBF5));

  // ══ SÉPARATEURS ══════════════════════════════════════════════════════

  static Color get separator =>
      _pick(const Color(0x4A3C3C43), const Color(0xA6545458));

  static Color get opaqueSeparator =>
      _pick(const Color(0xFFC6C6C8), const Color(0xFF38383A));

  // ══ REMPLISSAGES ═════════════════════════════════════════════════════

  static Color get systemFill =>
      _pick(const Color(0x33787880), const Color(0x5B787880));
  static Color get secondarySystemFill =>
      _pick(const Color(0x28787880), const Color(0x51787880));
  static Color get tertiarySystemFill =>
      _pick(const Color(0x1E767680), const Color(0x3D767680));
  static Color get quaternarySystemFill =>
      _pick(const Color(0x14747480), const Color(0x2D747480));

  // ══ TEINTE D'ACCENT ══════════════════════════════════════════════════
  // LA couleur de la marque. Une seule. Elle signale ce qui est
  // interactif — donc jamais décorative, sinon on ne sait plus ce qui
  // est cliquable.
  //
  // Le bleu clair d'iOS est légèrement plus soutenu que le sombre : sur
  // fond blanc, un bleu trop vif « vibre » et fatigue.

  static Color get accent =>
      _pick(const Color(0xFF007AFF), const Color(0xFF0A84FF));

  static Color get accentPressed =>
      _pick(const Color(0xFF0062CC), const Color(0xFF0770DB));

  // ══ COULEURS SÉMANTIQUES ═════════════════════════════════════════════
  // Uniquement pour porter un SENS. Jamais décoratives.

  static Color get systemGreen =>
      _pick(const Color(0xFF34C759), const Color(0xFF30D158));
  static Color get systemRed =>
      _pick(const Color(0xFFFF3B30), const Color(0xFFFF453A));
  static Color get systemOrange =>
      _pick(const Color(0xFFFF9500), const Color(0xFFFF9F0A));
  static Color get systemYellow =>
      _pick(const Color(0xFFFFCC00), const Color(0xFFFFD60A));
  static Color get systemIndigo =>
      _pick(const Color(0xFF5856D6), const Color(0xFF5E5CE6));
  static Color get systemPurple =>
      _pick(const Color(0xFFAF52DE), const Color(0xFFBF5AF2));
  static Color get systemPink =>
      _pick(const Color(0xFFFF2D55), const Color(0xFFFF375F));
  static Color get systemTeal =>
      _pick(const Color(0xFF30B0C7), const Color(0xFF40C8E0));
  static Color get systemBrown =>
      _pick(const Color(0xFFA2845E), const Color(0xFFAC8E68));

  // ══ GRIS SYSTÈME ═════════════════════════════════════════════════════
  // L'échelle s'INVERSE entre les deux modes : `systemGray6` est le plus
  // clair en mode clair et le plus sombre en mode sombre. C'est voulu —
  // ces noms désignent une distance au fond, pas une luminosité absolue.

  static Color get systemGray =>
      _pick(const Color(0xFF8E8E93), const Color(0xFF8E8E93));
  static Color get systemGray2 =>
      _pick(const Color(0xFFAEAEB2), const Color(0xFF636366));
  static Color get systemGray3 =>
      _pick(const Color(0xFFC7C7CC), const Color(0xFF48484A));
  static Color get systemGray4 =>
      _pick(const Color(0xFFD1D1D6), const Color(0xFF3A3A3C));
  static Color get systemGray5 =>
      _pick(const Color(0xFFE5E5EA), const Color(0xFF2C2C2E));
  static Color get systemGray6 =>
      _pick(const Color(0xFFF2F2F7), const Color(0xFF1C1C1E));

  // ══ BULLES DE CONVERSATION ═══════════════════════════════════════════
  // Contraste exact de Messages : accent plein pour mes messages, gris
  // neutre pour ceux reçus.

  static Color get bubbleOutgoing => accent;

  static Color get bubbleIncoming =>
      _pick(const Color(0xFFE9E9EB), const Color(0xFF26262A));

  /// Couleur du texte dans une bulle reçue — noir en clair, blanc en
  /// sombre. Sans cette distinction, le texte des messages reçus
  /// deviendrait blanc sur gris très clair, donc illisible.
  static Color get bubbleIncomingText => label;

  // ── Surfaces d'appel ────────────────────────────────────────────────
  //
  // L'écran d'appel reste SOMBRE en permanence, même quand toute l'app
  // est en mode clair. Ce n'est pas un oubli : c'est ce que font iOS,
  // WhatsApp et FaceTime, pour trois raisons qui se cumulent.
  //
  //  1. Un appel occupe l'écran entier, souvent longtemps, souvent
  //     collé au visage — un aplat blanc éclairerait la pièce.
  //  2. Les seules commandes qui comptent (raccrocher en rouge,
  //     décrocher en vert) ressortent bien plus nettement sur du noir.
  //  3. Un appel arrive par surprise, y compris la nuit : un écran qui
  //     passe au blanc d'un coup est une agression.
  //
  // Ces couleurs sont donc des constantes fixes, jamais passées par
  // `_pick`.

  /// Fond de l'écran d'appel — noir dans les deux modes.
  static const Color callBackground = Color(0xFF000000);

  /// Halo bleu nuit derrière l'avatar pendant la sonnerie.
  static const Color callGlow = Color(0xFF101A3A);

  /// Texte principal sur une surface d'appel.
  static const Color callLabel = Color(0xFFFFFFFF);

  /// Texte secondaire sur une surface d'appel (« Appel entrant… »).
  static const Color callSecondaryLabel = Color(0xB3FFFFFF);

  /// Fond des boutons ronds de l'écran d'appel au repos (micro,
  /// haut-parleur, caméra) — gris sombre fixe, comme le reste de l'écran.
  static const Color callControl = Color(0xFF2C2C2E);

  // ══ COMPATIBILITÉ ════════════════════════════════════════════════════
  // Anciens noms, redirigés vers les couleurs système. Ils permettent aux
  // écrans pas encore migrés de continuer à fonctionner, et de basculer
  // en mode clair automatiquement eux aussi.

  static Color get background => systemBackground;
  static Color get surface => secondarySystemBackground;
  static Color get surfaceElevated => tertiarySystemBackground;
  static Color get cardDark => secondarySystemBackground;
  static Color get cardHover => tertiarySystemBackground;

  static Color get meshBlue => accent;
  static Color get meshBlueBright => accent;
  static Color get meshBlueDark => accentPressed;
  static Color get ouroOrange => systemOrange;
  static Color get localGreen => systemGreen;
  static Color get accentPurple => systemIndigo;
  static Color get accentPink => systemPink;
  static Color get accentTeal => systemTeal;
  static Color get accentCyan => systemTeal;

  static Color get textPrimary => label;
  static Color get textSecondary => secondaryLabel;
  static Color get textTertiary => tertiaryLabel;
  static Color get textInverse => systemBackground;

  static Color get glassBg => quaternarySystemFill;
  static Color get glassBgStrong => tertiarySystemFill;
  static Color get glassBorder => separator;
  static Color get glassBorderStrong => opaqueSeparator;

  static Color get errorRed => systemRed;
  static Color get warningAmber => systemOrange;
  static Color get successGreen => systemGreen;
  static Color get infoBlue => accent;

  static Color get divider => separator;
  static Color get dividerStrong => opaqueSeparator;

  // ── Dégradés ────────────────────────────────────────────────────────
  //
  // Apple n'utilise quasiment jamais de dégradé dans son interface : c'est
  // le marqueur n°1 d'une app amateur. Ceux qui restent sont réduits à une
  // variation subtile de la MÊME couleur (jamais deux teintes opposées),
  // pour les rares surfaces qui en ont besoin.

  static LinearGradient get brandGradient => LinearGradient(
        colors: [accent, accentPressed],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get brandGradientVertical => LinearGradient(
        colors: [accent, accentPressed],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  static LinearGradient get energyGradient => LinearGradient(
        colors: [systemOrange, Color.lerp(systemOrange, Colors.black, 0.2)!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get successGradient => LinearGradient(
        colors: [systemGreen, Color.lerp(systemGreen, Colors.black, 0.2)!],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient get darkGradient => LinearGradient(
        colors: [systemBackground, systemBackground],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  static LinearGradient get meshGradient => brandGradient;

  static LinearGradient get surfaceGradient => LinearGradient(
        colors: [secondarySystemBackground, secondarySystemBackground],
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
      );

  /// Palette d'avatars — teintes système d'Apple, en aplat. Chaque
  /// personne reçoit toujours la même, dérivée de son pseudo (voir
  /// `peer_avatar.dart`).
  static List<Color> get avatarPalette => [
        accent,
        systemIndigo,
        systemPurple,
        systemPink,
        systemOrange,
        systemGreen,
        systemTeal,
        systemBrown,
      ];
}
