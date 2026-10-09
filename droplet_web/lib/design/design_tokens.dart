// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Tous les petits nombres réutilisés dans l'app : espacements, arrondis,
// tailles d'icônes, durées et « personnalité » des animations.
//
// LE CHANGEMENT LE PLUS IMPORTANT DE LA REFONTE EST ICI, et il est
// invisible dans une capture d'écran — c'est le MOUVEMENT.
//
// Une app amateur fait rebondir ses éléments (`elasticOut`, `bounceOut`) :
// le bouton dépasse sa taille finale puis revient, comme un ressort de
// dessin animé. Ça paraît « vivant » au premier coup d'œil, et ça devient
// insupportable au bout de dix minutes d'usage — parce que ça retarde
// l'information que l'utilisateur attend, à chaque interaction, toute la
// journée.
//
// Apple ne fait JAMAIS ça dans son interface. Le mouvement iOS a trois
// règles :
//   1. Il DÉCÉLÈRE (rapide au départ, doux à l'arrivée) — jamais l'inverse.
//   2. Il ne dépasse jamais sa cible, sauf réponse directe à un geste.
//   3. Il est COURT : 200-350 ms. Au-delà, on attend l'interface.
//
// C'est ce qui donne cette impression que l'app « répond » au lieu de
// « jouer une animation ».
// ============================================================================

import 'package:flutter/material.dart';

class DesignTokens {
  DesignTokens._();

  // ══ ESPACEMENTS ══════════════════════════════════════════════════════
  // Grille de 4pt, comme iOS. La marge latérale standard d'un écran iOS
  // est de 16pt — c'est `screenMargin`, à utiliser partout pour que tous
  // les écrans s'alignent verticalement entre eux.

  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;
  static const double space10 = 40;
  static const double space12 = 48;
  static const double space16 = 64;

  /// Marge latérale standard d'un écran iOS.
  static const double screenMargin = 16;

  /// Décalage du contenu dans une cellule de liste (là où commence le
  /// texte après un avatar) — c'est aussi là que doivent démarrer les
  /// séparateurs, jamais au bord de l'écran.
  static const double listContentInset = 16;

  // ══ ARRONDIS ═════════════════════════════════════════════════════════
  // Valeurs iOS réelles. Apple reste sobre : au-delà de 20, un conteneur
  // commence à paraître enfantin.

  static const double radiusXs = 6;
  static const double radiusSm = 8;
  static const double radiusMd = 10;
  static const double radiusLg = 12;
  static const double radiusXl = 14;
  static const double radius2xl = 16;
  static const double radius3xl = 20;

  /// Arrondi d'un îlot de liste groupée (Réglages iOS).
  static const double radiusGroupedList = 10;

  /// Arrondi d'une feuille modale qui monte du bas.
  /// Le rayon du haut d'une feuille modale.
  ///
  /// ⚠️ 28 et non 12. Douze points, sur une feuille large de tout
  /// l'écran, se lisent comme un angle presque droit : la feuille
  /// ressemble à une dalle posée sur l'écran, pas à une carte qui monte
  /// depuis le bas. C'est le premier détail qui distingue une feuille
  /// « faite maison » d'une feuille système, avant même la couleur.
  static const double radiusSheet = 28;

  /// Arrondi d'une bulle de conversation.
  /// Le rayon exact d'une bulle iMessage : 19pt.
  ///
  /// iMessage utilise 19pt pour le corps de la bulle, avec un coin
  /// « queue » resserré à 6pt du côté de l'expéditeur pour former
  /// la pointe caractéristique.
  static const double radiusBubble = 19;

  /// Le coin « pointe » qui désigne le locuteur, en bas de la dernière
  /// bulle d'une série.
  ///
  /// 6pt comme iMessage : le coin le plus proche de l'expéditeur est
  /// « pincé » pour former la queue de la bulle, tandis que les trois
  /// autres coins restent à 19pt.
  static const double radiusBubbleTail = 6;

  /// Forme « gélule » — entièrement arrondie.
  static const double radiusFull = 999;

  // ══ ICÔNES ═══════════════════════════════════════════════════════════

  static const double iconXs = 12;
  static const double iconSm = 16;
  static const double iconMd = 20;
  static const double iconLg = 22;
  static const double iconXl = 28;
  static const double icon2xl = 32;
  static const double icon3xl = 40;
  static const double icon4xl = 48;

  /// Taille minimale d'une zone tactile — règle d'accessibilité Apple :
  /// jamais moins de 44×44 points, sinon la cible devient frustrante à
  /// atteindre au doigt.
  static const double minTouchTarget = 44;

  // ══ DURÉES ═══════════════════════════════════════════════════════════
  // Calées sur les durées système iOS.

  /// Retour instantané (changement d'état d'un bouton pressé).
  static const Duration durationInstant = Duration(milliseconds: 100);

  /// Micro-interaction (apparition d'une icône, bascule d'un interrupteur).
  static const Duration durationFast = Duration(milliseconds: 200);

  /// LA durée de référence — transitions d'écran iOS, apparition de
  /// contenu.
  static const Duration durationStandard = Duration(milliseconds: 350);

  /// Présentation d'une feuille modale.
  static const Duration durationSheet = Duration(milliseconds: 450);

  /// Mouvement ambiant lent (respiration d'un halo, onde d'appel).
  static const Duration durationAmbient = Duration(milliseconds: 2000);

  // ══ COURBES ══════════════════════════════════════════════════════════
  //
  // ⚠️ AUCUNE courbe de cette liste ne dépasse sa valeur finale. C'est
  // volontaire, et c'est la différence la plus nette avec l'ancien design.

  /// LA courbe par défaut d'iOS. Démarre vite, finit tout en douceur —
  /// c'est ce qui donne la sensation « l'interface répond immédiatement,
  /// puis se pose ».
  static const Curve curveStandard = Curves.fastEaseInToSlowEaseOut;

  /// Entrée d'un élément (apparition, glissement vers sa place).
  static const Curve curveEnter = Curves.easeOutCubic;

  /// Sortie d'un élément (disparition) — plus sec que l'entrée : ce qui
  /// part n'a pas besoin d'être admiré.
  static const Curve curveExit = Curves.easeInCubic;

  /// Mouvement piloté au doigt (glissement, défilement).
  static const Curve curveInteractive = Curves.easeOutQuart;

  /// Progression linéaire — barres de chargement uniquement.
  static const Curve curveLinear = Curves.linear;

  // ── Compatibilité avec l'ancien nommage ─────────────────────────────
  // Volontairement redirigées vers les courbes iOS : les anciens appels à
  // `curveSpring` et `curveBounce` (qui faisaient rebondir) produisent
  // désormais un mouvement sobre, sans avoir à modifier chaque écran.

  static const Curve curveDefault = curveStandard;
  static const Curve curveEmphasis = curveEnter;
  static const Curve curveSpring = curveEnter;
  static const Curve curveBounce = curveEnter;
  static const Curve curveFastOut = curveStandard;

  static const Duration durationNormal = durationStandard;
  static const Duration durationSlow = durationSheet;
  static const Duration durationXSlow = Duration(milliseconds: 600);
  static const Duration durationXXSlow = durationAmbient;
  static const Duration durationBeat = durationAmbient;

  // ══ RESSORTS ═════════════════════════════════════════════════════════
  // Pour les rares mouvements pilotés par un geste (fermer une feuille en
  // la faisant glisser). Réglés sur les valeurs SwiftUI d'Apple.

  /// Ressort « smooth » de SwiftUI — aucun dépassement.
  static SpringDescription get springSmooth => SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: 180,
        ratio: 1.0,
      );

  /// Ressort « snappy » de SwiftUI — très léger dépassement, réservé au
  /// retour d'un geste direct.
  static SpringDescription get springSnappy => SpringDescription.withDampingRatio(
        mass: 1,
        stiffness: 260,
        ratio: 0.86,
      );

  // ══ PADDINGS ═════════════════════════════════════════════════════════

  static const EdgeInsets paddingXs = EdgeInsets.all(4);
  static const EdgeInsets paddingSm = EdgeInsets.all(8);
  static const EdgeInsets paddingMd = EdgeInsets.all(16);
  static const EdgeInsets paddingLg = EdgeInsets.all(20);
  static const EdgeInsets paddingXl = EdgeInsets.all(24);

  static const EdgeInsets hPaddingSm = EdgeInsets.symmetric(horizontal: 8);
  static const EdgeInsets hPaddingMd = EdgeInsets.symmetric(horizontal: 16);
  static const EdgeInsets hPaddingLg = EdgeInsets.symmetric(horizontal: 20);

  static const EdgeInsets vPaddingSm = EdgeInsets.symmetric(vertical: 8);
  static const EdgeInsets vPaddingMd = EdgeInsets.symmetric(vertical: 16);
  static const EdgeInsets vPaddingLg = EdgeInsets.symmetric(vertical: 20);

  /// Marge horizontale d'écran, à utiliser par défaut.
  static const EdgeInsets screenPadding = EdgeInsets.symmetric(horizontal: 16);

  // ══ OMBRES ═══════════════════════════════════════════════════════════
  //
  // Sur fond noir OLED, une ombre portée est presque invisible : Apple
  // sépare ses surfaces par la LUMINOSITÉ (un gris plus clair au-dessus)
  // et non par l'ombre. Les ombres restantes sont donc extrêmement
  // discrètes, et réservées à ce qui flotte vraiment au-dessus du
  // contenu (feuille modale, bouton flottant).

  /// Élévation d'une carte — quasi nulle en mode sombre, par choix.
  static List<BoxShadow> get cardShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.20),
          blurRadius: 12,
          offset: const Offset(0, 2),
        ),
      ];

  /// Élévation d'un élément réellement flottant.
  static List<BoxShadow> get floatingShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.32),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];

  static List<BoxShadow> get cardShadowStrong => floatingShadow;

  /// ⚠️ Les halos lumineux colorés (« glow ») ont été retirés du design :
  /// c'est un effet de jeu vidéo, jamais utilisé par Apple, et le
  /// marqueur le plus reconnaissable d'une interface amateur. Cette
  /// fonction est conservée pour que l'existant compile, mais elle rend
  /// désormais une ombre neutre et sobre.
  static List<BoxShadow> glow(Color color, {double radius = 20, double spread = 2}) {
    return [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.24),
        blurRadius: radius * 0.8,
        offset: const Offset(0, 3),
      ),
    ];
  }

  // ══ ÉPAISSEUR DES TRAITS ═════════════════════════════════════════════

  /// Un séparateur iOS fait exactement 1 pixel physique — donc moins d'un
  /// point logique sur un écran haute densité. C'est cette finesse
  /// extrême qui rend les listes iOS si nettes.
  static double hairline(BuildContext context) =>
      1.0 / MediaQuery.devicePixelRatioOf(context);
}
