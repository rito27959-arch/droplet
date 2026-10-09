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

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'reglages_apparence.dart';

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

  // ⚠️ LES OPACITÉS NE SONT PLUS CELLES D'APPLE, ET C'EST VOULU.
  //
  // Apple descend à 30 % pour le tertiaire et 18 % pour le quaternaire.
  // Mesuré sur nos fonds, cela donnait 1,74:1 et 1,37:1 — très en dessous
  // du seuil WCAG de 4,5:1, c'est-à-dire illisible en plein soleil, la
  // situation exacte pour laquelle Droplet existe. Apple s'en sort parce
  // qu'iOS propose « Augmenter le contraste » dans ses réglages
  // d'accessibilité ; nous n'avons pas ce filet.
  //
  // Les trois valeurs ci-dessous sont les plus PETITES opacités qui
  // atteignent leur cible sur les deux fonds les plus difficiles de
  // chaque mode (blanc et F2F2F7 en clair, noir et 1C1C1E en sombre).
  // Elles gardent donc trois paliers distincts à l'œil, sans qu'aucun
  // texte porteur de sens ne tombe sous le seuil.

  /// Sous-titres, métadonnées. Cible 7:1 — 88 % en clair, 67 % en sombre.
  static Color get secondaryLabel =>
      _pick(const Color(0xE13C3C43), const Color(0xAAEBEBF5));

  /// Indications discrètes. Cible 4,5:1 — le plancher du texte lisible.
  static Color get tertiaryLabel =>
      _pick(const Color(0xB93C3C43), const Color(0x7FEBEBF5));

  /// ⚠️ 3:1 SEULEMENT — DÉCORATIF UNIQUEMENT.
  ///
  /// Le seul palier sous 4,5:1, et il y reste pour que la hiérarchie
  /// garde quatre marches. Réservé à ce qui ne porte AUCUNE information :
  /// un chevron, un séparateur dessiné, une icône redondante avec son
  /// libellé. Jamais un texte d'invite, jamais une valeur, jamais une
  /// date — pour cela, `tertiaryLabel`.
  static Color get quaternaryLabel =>
      _pick(const Color(0x903C3C43), const Color(0x61EBEBF5));

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

  /// La couleur d'accent CHOISIE dans les réglages (bleu iOS par défaut,
  /// voir `reglages_apparence.dart`).
  static Color get accent => ReglagesApparence.accent.pour(sombre: isDark);

  /// L'accent enfoncé : la même teinte, un cran plus sombre.
  static Color get accentPressed {
    final hsl = HSLColor.fromColor(accent);
    return hsl.withLightness((hsl.lightness - 0.09).clamp(0.0, 1.0)).toColor();
  }

  // ══ REMPLISSAGES PLEINS ══════════════════════════════════════════════
  // LE BLEU D'UN BOUTON N'EST PAS LE BLEU D'UN LIEN.
  //
  // Une teinte d'accent est calibrée pour être lisible SUR un fond clair
  // ou sombre — pas pour porter du texte blanc. Mesuré : blanc sur notre
  // vert donnait 2,22:1, sur la menthe 2,12:1, sur l'orange 2,20:1. Un
  // bouton plein avec son libellé à 2:1 disparaît au soleil.
  //
  // D'où ces deux fonctions, qui vont toujours ENSEMBLE : `surRemplissage`
  // donne le fond à peindre, `texteSurRemplissage` le texte à poser
  // dessus. L'une sans l'autre ne garantit rien.
  //
  // La règle tient en une phrase : on assombrit la teinte jusqu'à ce que
  // le BLANC atteigne 4,5:1 — sauf si elle est si claire que le NOIR y
  // lit déjà à 12:1, auquel cas on garde la teinte telle quelle et on
  // écrit en noir. C'est ce second cas qui sauve le jaune : l'assombrir
  // jusqu'au blanc lisible en ferait un olive, et le jaune cesserait
  // d'être un jaune. Apple fait exactement ce choix-là.
  //
  // Le seuil de 12:1 n'est pas arbitraire : mesuré sur nos onze teintes,
  // il isole le jaune seul. Vert, orange, menthe et cyan plafonnent entre
  // 9,5 et 10,6 avec du noir — assez pour se lire, pas assez pour qu'un
  // bouton noir-sur-couleur paraisse voulu au milieu d'une interface où
  // tous les autres sont blancs.

  /// Le contraste WCAG 2.1 entre deux couleurs opaques. Renvoie un nombre
  /// entre 1 (identiques) et 21 (noir sur blanc).
  static double contraste(Color a, Color b) {
    final la = _luminance(a);
    final lb = _luminance(b);
    final haut = math.max(la, lb);
    final bas = math.min(la, lb);
    return (haut + 0.05) / (bas + 0.05);
  }

  static double _luminance(Color c) {
    double canal(double v) =>
        v <= 0.04045 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * canal(c.r) + 0.7152 * canal(c.g) + 0.0722 * canal(c.b);
  }

  /// Le fond à peindre pour un bouton, une pastille ou une bulle pleins
  /// de [teinte] — poussé juste assez loin pour que son texte se lise.
  ///
  /// À utiliser TOUJOURS avec [texteSurRemplissage] sur la même teinte.
  ///
  /// [encre] force la couleur du texte au lieu de la déduire. C'est ce
  /// qui permet à un accent de garder la MÊME encre dans les deux modes :
  /// la menthe sombre (#63E6E2) est si claire que le noir y gagnerait,
  /// alors que la menthe claire appelle du blanc — sans ce paramètre, le
  /// même bouton passerait de blanc à noir en changeant de mode, ce qui
  /// se lit comme un bug et non comme une intention.
  static Color surRemplissage(Color teinte, {Color? encre}) {
    final e = encre ?? texteSurRemplissage(teinte);
    if (contraste(teinte, e) >= 4.5) return teinte;
    // Encre claire → on assombrit le fond ; encre sombre → on l'éclaircit.
    final versSombre = _luminance(e) > 0.5;
    var hsl = HSLColor.fromColor(teinte);
    // Pas de 0,005 : assez fin pour ne jamais aller trop loin, assez
    // grossier pour que la boucle reste courte (200 tours au pire).
    while (contraste(hsl.toColor(), e) < 4.5) {
      final l = versSombre ? hsl.lightness - 0.005 : hsl.lightness + 0.005;
      if (l <= 0 || l >= 1) break;
      hsl = hsl.withLightness(l);
    }
    return hsl.toColor();
  }

  /// Le texte à poser sur un remplissage plein de [teinte] : blanc dans
  /// la quasi-totalité des cas, noir sur les teintes trop claires.
  static Color texteSurRemplissage(Color teinte) =>
      contraste(teinte, const Color(0xFF000000)) >= 12
          ? const Color(0xFF000000)
          : const Color(0xFFFFFFFF);

  /// L'accent choisi, prêt à porter du texte. `accent` reste ce qu'on
  /// écrit SUR un fond ; `accentRempli` est ce qu'on peint DERRIÈRE.
  static Color get accentRempli =>
      surRemplissage(accent, encre: texteSurAccent);

  /// Le texte des boutons pleins en accent.
  ///
  /// ⚠️ DÉCIDÉ SUR LA VARIANTE CLAIRE, dans les deux modes. Le choix de
  /// l'encre appartient à l'accent, pas au mode d'affichage : un bouton
  /// « menthe » doit rester le même bouton la nuit.
  static Color get texteSurAccent => texteSurRemplissage(
        ReglagesApparence.accent.pour(sombre: false),
      );

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

  /// ⚠️ PAS `accent` BRUT. C'est le texte le plus lu de toute
  /// l'application : mesuré, du blanc sur l'accent vert donnait 2,22:1,
  /// sur la menthe 2,12:1 — une conversation illisible dehors. La bulle
  /// est donc peinte avec le remplissage, et son texte est
  /// `bubbleOutgoingText`, qui va avec.
  static Color get bubbleOutgoing => accentRempli;

  /// Le texte d'une bulle envoyée. Va TOUJOURS avec [bubbleOutgoing].
  static Color get bubbleOutgoingText => texteSurAccent;

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

  // ══ PRÉSENCE ════════════════════════════════════════════════════════
  //
  // ⚠️ TROIS COULEURS, ET PAS UNE DE PLUS. La fraîcheur d'un contact se
  // dit ici, pour toute l'application — en-tête de conversation, accueil,
  // liste des pairs. Voir `FraicheurPair` dans `etat_connexion.dart` pour
  // la règle qui les choisit, et pourquoi il a fallu la centraliser.
  //
  // Le vert ne signifie QUE « cette personne est là maintenant ». S'en
  // servir pour dire une route, un type de lien ou une ancienneté rend
  // l'indicateur incroyable, et un indicateur incroyable ne vaut rien.

  /// Joignable maintenant, et c'est prouvé.
  static Color get presenceMaintenant => systemGreen;

  /// Le lien se rétablit, ou Internet se fait attendre.
  static Color get presenceEnCours => systemOrange;

  /// Du passé : « vu il y a… », ou une route sans preuve de présence.
  static Color get presencePassee => tertiaryLabel;
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
