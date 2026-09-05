// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Les « matériaux » d'iOS — ces surfaces translucides et floues qu'on voit
// derrière la barre de navigation, la barre d'onglets ou une feuille
// modale, et qui laissent deviner le contenu qui défile dessous.
//
// LA DIFFÉRENCE AVEC L'ANCIENNE VERSION : avant, ce fichier fabriquait des
// panneaux de verre décoratifs, posés un peu partout parce que « ça fait
// joli ». Chez Apple, le flou n'est jamais décoratif — il a une seule
// fonction : signaler qu'une surface FLOTTE au-dessus du contenu, et que
// du contenu passe derrière elle. Un flou posé sur un fond fixe ne floute
// rien du tout : il coûte cher en performance et n'apporte rien.
//
// Donc ici : quatre épaisseurs de matériau (comme Apple : ultraThin, thin,
// regular, thick), à utiliser UNIQUEMENT sur les barres et les feuilles.
// Pour le reste, on empile des gris opaques — c'est plus net, plus rapide,
// et c'est ce que fait iOS.
// ============================================================================

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'ouro_colors.dart';
import 'design_tokens.dart';
import 'ouro_liquid_surface.dart';
import 'ouro_pressable.dart';

/// Les quatre épaisseurs de matériau translucide d'iOS.
enum OuroMaterial {
  /// Le plus transparent — laisse presque tout voir (barres fines).
  ultraThin,

  /// Transparent — barre de navigation, barre d'onglets.
  thin,

  /// Standard — feuilles modales, menus contextuels.
  regular,

  /// Le plus opaque — quand le contenu dessous doit vraiment disparaître.
  thick,
}

extension _MaterialSpec on OuroMaterial {
  /// Intensité du flou, en points.
  double get blur => switch (this) {
        OuroMaterial.ultraThin => 20,
        OuroMaterial.thin => 30,
        OuroMaterial.regular => 40,
        OuroMaterial.thick => 50,
      };

  /// Voile posé par-dessus le flou, qui garantit que le texte reste
  /// lisible quel que soit ce qui défile derrière.
  ///
  /// Le voile s'inverse avec le mode : sombre par-dessus le contenu en
  /// mode sombre, clair en mode clair. Un voile sombre gardé en mode
  /// clair transformerait chaque barre en bandeau gris sale, et surtout
  /// le texte noir posé dessus deviendrait illisible — c'est l'erreur
  /// classique des apps qui « ajoutent » un mode clair après coup.
  Color get tint => OuroColors.isDark
      ? switch (this) {
          OuroMaterial.ultraThin => const Color(0x1F1C1C1E),
          OuroMaterial.thin => const Color(0x661C1C1E),
          OuroMaterial.regular => const Color(0xB31C1C1E),
          OuroMaterial.thick => const Color(0xE01C1C1E),
        }
      : switch (this) {
          // Un peu plus opaques que leurs équivalents sombres : sur fond
          // clair, l'œil distingue beaucoup mieux ce qui bouge derrière
          // un voile blanc, et le contenu défilant deviendrait vite
          // distrayant à opacité égale.
          OuroMaterial.ultraThin => const Color(0x4DFFFFFF),
          OuroMaterial.thin => const Color(0x8CF9F9FB),
          OuroMaterial.regular => const Color(0xCCF9F9FB),
          OuroMaterial.thick => const Color(0xEDFBFBFD),
        };
}

// ─────────────────────────────────────────────────────────────
//  SURFACE TRANSLUCIDE
// ─────────────────────────────────────────────────────────────

/// Une surface floue façon iOS. À réserver aux éléments qui flottent
/// réellement au-dessus de contenu défilant (barres, feuilles).
class OuroBlurSurface extends StatelessWidget {
  const OuroBlurSurface({
    super.key,
    required this.child,
    this.material = OuroMaterial.thin,
    this.borderRadius,
    this.padding,
  });

  final Widget child;
  final OuroMaterial material;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.zero;
    return ClipRRect(
      borderRadius: radius,
      child: BackdropFilter(
        filter: OuroMaterialFilter.pour(material),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: material.tint,
            borderRadius: radius,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Le FILTRE du matériau : flou **et** saturation.
///
/// ── Le détail qui sépare le verre du calque flouté ────────────────────
///
/// Un `BackdropFilter` qui ne fait que flouter donne du plastique dépoli.
/// Le matériau d'Apple fait deux choses : il floute, et il RAVIVE
/// légèrement les couleurs qui le traversent. C'est ce qui explique
/// qu'une photo colorée reste vivante derrière une barre iOS, là où le
/// même flou seul la rend grise et morte.
///
/// Personne ne remarque cette saturation consciemment ; tout le monde
/// remarque son absence — sous la forme d'un « ça fait fade ».
///
/// Le fichier `ouro_glass.dart` applique déjà exactement ce principe au
/// verre liquide de la barre d'onglets (`saturation: 1.08`). Ici, on le
/// donne à TOUT le reste du châssis — feuilles modales, alertes,
/// bandeaux — sans ajouter la moindre passe de shader : une matrice de
/// couleur est composée avec le flou en une seule opération, au même
/// coût qu'avant.
class OuroMaterialFilter {
  OuroMaterialFilter._();

  /// À quel point les couleurs sont ravivées en traversant le verre.
  ///
  /// 1,0 = aucune correction. Au-delà de ~1,15 la teinte se met à
  /// « baver » sur les bords des objets flous et l'effet se voit — ce
  /// qui est précisément ce qu'on ne veut pas.
  static const double saturation = 1.08;

  static ui.ImageFilter pour(OuroMaterial material) => flou(material.blur);

  /// Même matériau, mais pour les rares surfaces dont le flou a été
  /// réglé à la main et ne doit pas changer.
  ///
  /// ⚠️ NE PAS LES BASCULER SUR UN `OuroMaterial` « PARCE QUE C'EST PLUS
  /// PROPRE ». La barre de saisie est floutée à 18 ; le matériau
  /// `regular` l'est à 40. Substituer l'un à l'autre au nom de
  /// l'uniformité changerait franchement l'aspect d'un élément qu'on a
  /// sous les yeux toute la journée — ce qui n'était pas la question.
  static ui.ImageFilter flou(double sigma) {
    return ui.ImageFilter.compose(
      outer: ui.ColorFilter.matrix(_matriceSaturation(saturation)),
      inner: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    );
  }

  /// La matrice de saturation, exposée pour les rares surfaces qui font
  /// varier leur intensité au fil d'une animation (le fond du menu
  /// contextuel, qui se floute progressivement à l'ouverture).
  static List<double> matricePour(double s) => _matriceSaturation(s);

  /// La matrice de saturation standard, construite autour des poids de
  /// luminance perçue (Rec. 709). Les mêmes coefficients que ceux
  /// qu'emploient CoreImage et le shader de `liquid.frag`.
  static List<double> _matriceSaturation(double s) {
    const lr = 0.2126;
    const lg = 0.7152;
    const lb = 0.0722;
    final ir = (1 - s) * lr;
    final ig = (1 - s) * lg;
    final ib = (1 - s) * lb;
    return <double>[
      ir + s, ig, ib, 0, 0,
      ir, ig + s, ib, 0, 0,
      ir, ig, ib + s, 0, 0,
      0, 0, 0, 1, 0,
    ];
  }
}

// ─────────────────────────────────────────────────────────────
//  FEUILLE MODALE
// ─────────────────────────────────────────────────────────────

/// Feuille qui monte du bas de l'écran, façon iOS : coins arrondis en
/// haut, petite poignée grise centrée, matériau translucide.
///
/// La poignée n'est pas décorative — c'est l'indice visuel universel
/// d'iOS qui dit « on peut faire glisser ce panneau vers le bas pour le
/// fermer ». Sans elle, l'utilisateur cherche un bouton « Fermer ».
class FrostedSheet extends StatelessWidget {
  const FrostedSheet({
    super.key,
    required this.child,
    this.topRadius = DesignTokens.radiusSheet,
    this.padding,
    this.showGrabber = true,
    this.material = OuroMaterial.regular,
  });

  final Widget child;
  final double topRadius;
  final EdgeInsetsGeometry? padding;
  final bool showGrabber;

  /// L'épaisseur du verre.
  ///
  /// `regular` par défaut — assez opaque pour qu'un texte dense reste
  /// lisible par-dessus n'importe quoi. Une feuille qui ne porte que de
  /// grandes cibles et des images peut se permettre `thin`, et devient
  /// alors franchement translucide : c'est ce qui donne l'impression de
  /// verre plutôt que de carton.
  final OuroMaterial material;

  @override
  Widget build(BuildContext context) {
    // ── VERRE LIQUIDE, PAS SEULEMENT VERRE DÉPOLI ────────────────────
    //
    // iOS 26 pose du Liquid Glass sur ses feuilles modales : le contenu
    // qui passe derrière ne se contente pas d'être flouté, il est
    // RÉFRACTÉ — dévié comme à travers une lentille, plus fort près du
    // bord, avec un liseré lumineux sur la tranche.
    //
    // La feuille est le meilleur endroit de l'application pour ça :
    // elle est grande, elle monte devant du contenu qui reste visible en
    // dessous, et on la regarde longtemps. C'est aussi une surface
    // TEMPORAIRE — le coût de la passe de shader n'est payé que le temps
    // où elle est à l'écran, contrairement à la barre d'onglets.
    //
    // `OuroLiquidSurface` retombe toute seule sur le flou d'origine
    // quand l'appareil chauffe ou n'a pas la mémoire pour un shader.
    return OuroLiquidSurface(
      borderRadius: topRadius,
      // Une feuille porte du texte dense : il lui faut plus de voile
      // qu'à une capsule, sinon une photo qui défile derrière rend les
      // libellés illisibles.
      blur: 14,
      thickness: 11,
      child: _corps(context),
    );
  }

  Widget _corps(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(topRadius)),
      child: BackdropFilter(
        // Le voile de secours SOUS le verre liquide : il garantit la
        // lisibilité du texte quel que soit le fond, et c'est lui seul
        // qui reste en mode dégradé.
        filter: OuroMaterialFilter.pour(material),
        child: Container(
          decoration: BoxDecoration(
            color: material.tint,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(topRadius)),
            // ── LE LISERÉ DE BORD ────────────────────────────────────
            //
            // Un trait blanc d'un demi-point sur le pourtour haut. C'est
            // le détail le plus discret de la feuille, et celui qui fait
            // le plus de différence : il attrape la lumière comme le
            // ferait la tranche d'une vraie plaque de verre, et détache
            // la feuille du contenu sombre qu'elle recouvre.
            //
            // Sans lui, la feuille et le fond se touchent sans transition
            // et l'ensemble paraît plat — c'est exactement ce qui
            // manquait pour que le panneau ait l'air « posé sur » plutôt
            // que « découpé dans ».
            border: Border(
              top: BorderSide(
                color: Colors.white.withValues(
                  alpha: OuroColors.isDark ? 0.14 : 0.55,
                ),
                width: 0.5,
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showGrabber) const _SheetGrabber(),
              Padding(
                padding: padding ??
                    const EdgeInsets.fromLTRB(
                      DesignTokens.screenMargin,
                      0,
                      DesignTokens.screenMargin,
                      DesignTokens.space5,
                    ),
                child: child,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La petite poignée grise en haut d'une feuille modale. Dimensions
/// exactes d'iOS : 36×5 points.
class _SheetGrabber extends StatelessWidget {
  const _SheetGrabber();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 5, bottom: DesignTokens.space3),
      child: Container(
        width: 36,
        height: 5,
        decoration: BoxDecoration(
          color: OuroColors.systemGray2,
          borderRadius: BorderRadius.circular(2.5),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  CARTE OPAQUE
// ─────────────────────────────────────────────────────────────

/// Carte de contenu — OPAQUE, pas floue.
///
/// C'est le remplaçant direct de l'ancien `GlassContainer`. iOS empile
/// ses surfaces par la luminosité (chaque niveau est un gris légèrement
/// plus clair), pas par la transparence : c'est plus net à l'œil et
/// nettement moins coûteux à afficher, car le téléphone n'a pas à
/// recalculer un flou à chaque image.
class OuroCard extends StatelessWidget {
  const OuroCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius = DesignTokens.radiusGroupedList,
    this.color,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? OuroColors.secondarySystemGroupedBackground,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: child,
    );

    if (onTap == null) return card;

    // Enfoncement iOS plutôt que l'onde de Material — voir
    // `ouro_pressable.dart`.
    return OuroPressable(onTap: onTap, child: card);
  }
}

/// Ancien nom de [OuroCard], conservé pour que les écrans pas encore
/// migrés continuent de compiler. Rend désormais une carte opaque : le
/// flou décoratif a été retiré partout où il ne floutait rien.
class GlassContainer extends StatelessWidget {
  const GlassContainer({
    super.key,
    required this.child,
    this.width,
    this.height,
    this.padding,
    this.margin,
    this.borderRadius = DesignTokens.radiusGroupedList,
    this.blur = 0,
    this.opacity = 0,
    this.border,
    this.boxShadow,
    this.gradient,
  });

  final Widget child;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final double blur;
  final double opacity;
  final Border? border;
  final List<BoxShadow>? boxShadow;
  final Gradient? gradient;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null
            ? OuroColors.secondarySystemGroupedBackground
            : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(borderRadius),
        border: border,
      ),
      child: child,
    );
  }
}

/// Ancien conteneur à halo lumineux. Le halo coloré a été retiré du
/// design (effet de jeu vidéo, jamais utilisé par Apple) — ce widget se
/// contente désormais de laisser passer son contenu.
class GlowContainer extends StatelessWidget {
  const GlowContainer({
    super.key,
    required this.child,
    this.glowColor,
    this.radius = 20,
    this.opacity = 0.3,
    this.borderRadius = DesignTokens.radiusGroupedList,
  });

  final Widget child;
  final Color? glowColor;
  final double radius;
  final double opacity;
  final double borderRadius;

  @override
  Widget build(BuildContext context) => child;
}

// ─────────────────────────────────────────────────────────────
//  DÉGRADÉ DE LISIBILITÉ
// ─────────────────────────────────────────────────────────────

/// Fond dégradé posé sous du texte affiché par-dessus une image, pour
/// garantir sa lisibilité. Seul usage légitime d'un dégradé dans une
/// interface iOS.
class GradientOverlay extends StatelessWidget {
  const GradientOverlay({
    super.key,
    required this.child,
    this.colors,
    this.begin = Alignment.topCenter,
    this.end = Alignment.bottomCenter,
  });

  final Widget child;
  final List<Color>? colors;
  final AlignmentGeometry begin;
  final AlignmentGeometry end;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: begin,
                  end: end,
                  colors: colors ??
                      [
                        Colors.transparent,
                        OuroColors.systemBackground.withValues(alpha: 0.7),
                        OuroColors.systemBackground,
                      ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Ancien fond animé à halo mouvant. Retiré du design : un arrière-plan
/// qui bouge en permanence attire l'œil en continu et fatigue à l'usage —
/// iOS garde ses fonds parfaitement immobiles. Le widget rend désormais
/// un fond noir uni.
class AnimatedGradientBackground extends StatelessWidget {
  const AnimatedGradientBackground({
    super.key,
    required this.child,
    this.colors,
    this.duration = const Duration(seconds: 6),
  });

  final Widget child;
  final List<Color>? colors;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: OuroColors.systemBackground,
      child: child,
    );
  }
}
