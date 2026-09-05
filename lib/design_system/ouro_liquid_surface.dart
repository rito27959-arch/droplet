// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE VERRE LIQUIDE, RENDU POSABLE SUR N'IMPORTE QUELLE SURFACE DE CHÂSSIS.
//
// `ouro_glass.dart` fournit la COUCHE et son groupe de fusion — ce dont a
// besoin la barre d'onglets, où deux formes doivent se souder. La plupart
// des surfaces n'ont pas ce besoin : une feuille modale, une alerte, une
// capsule de notification sont des objets isolés. Elles veulent seulement
// la MATIÈRE : la réfraction, le liseré de lumière sur la tranche, la
// frange colorée du bord.
//
// ── Où iOS 26 pose du Liquid Glass, exactement ────────────────────────
//
// Le matériau n'est pas appliqué au contenu, jamais. Il est réservé au
// CHÂSSIS — ce qui flotte au-dessus du contenu et n'appartient pas au
// document qu'on lit :
//
//   • la barre d'onglets                    → `ouro_tab_bar.dart`
//   • la barre de navigation, quand le contenu passe dessous
//   • les feuilles modales                  → `FrostedSheet`
//   • les alertes                           → `ouro_alert.dart`
//   • les capsules de notification système  → `toast_overlay.dart`
//   • les champs de recherche               → l'écran Discussions
//   • les menus contextuels
//
// Une bulle de conversation, une photo, une liste : jamais. Le verre
// posé sur du contenu rend le contenu illisible, et c'est la faute qui
// distingue une application « qui a mis du glassmorphism partout » d'une
// application qui emploie le matériau du système.
//
// ── ⚠️ CE QUE CHAQUE SURFACE COÛTE ────────────────────────────────────
//
// Une passe de shader par surface, sur le processeur graphique, à chaque
// image. C'est assumé et c'est demandé — mais c'est aussi la raison du
// repli automatique : `ouroGlassDegraded` bascule sur un flou ordinaire
// dès que l'appareil chauffe, et en permanence sur les téléphones de
// moins de 4 Go. La disposition ne change jamais : seule la façon de
// peindre change, et personne ne voit l'application « sauter » d'un
// aspect à l'autre.
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'ouro_colors.dart';
import 'ouro_glass.dart';

/// Une surface de châssis en verre liquide.
///
/// À poser sur ce qui FLOTTE au-dessus du contenu, jamais sur le contenu
/// lui-même. Se replie toute seule sur un flou ordinaire quand l'appareil
/// ne peut pas suivre.
class OuroLiquidSurface extends StatelessWidget {
  const OuroLiquidSurface({
    super.key,
    required this.child,
    required this.borderRadius,
    this.thickness = 12,
    this.blur = 10,
    this.teinte,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;

  /// Le rayon de la superellipse — la « squircle » d'Apple, pas un
  /// rectangle arrondi ordinaire.
  ///
  /// La différence se voit surtout dans les grands rayons : sur une
  /// feuille modale, un coin circulaire montre nettement l'endroit où
  /// l'arc rejoint la droite, là où la superellipse rend une courbure
  /// continue. C'est l'un des deux ou trois détails qui font qu'une
  /// forme « ressemble à iOS » sans qu'on sache dire pourquoi.
  final double borderRadius;

  /// L'épaisseur du verre — combien ce qui passe dessous se déforme.
  ///
  /// 12 pour du châssis posé sur du contenu qui défile. Au-delà de ~25,
  /// l'effet devient une loupe et la surface attire l'œil davantage que
  /// ce qu'elle contient.
  final double thickness;

  /// Le voile flou ajouté PAR-DESSUS la réfraction.
  ///
  /// Sans lui, un texte fin posé sur la surface devient illisible dès
  /// qu'une image contrastée passe dessous.
  final double blur;

  /// Teinte du verre. Par défaut, celle du système de design.
  final Color? teinte;

  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    // `Consumer` plutôt qu'un `ConsumerWidget` : cette surface doit
    // pouvoir se poser dans n'importe quel arbre, y compris sous une
    // route qui n'a pas de `WidgetRef` sous la main.
    return Consumer(
      builder: (context, ref, _) {
        final degrade = ouroGlassDegraded(ref);
        return LiquidGlass.withOwnLayer(
          fake: degrade,
          clipBehavior: clipBehavior,
          settings: LiquidGlassSettings(
            thickness: thickness,
            blur: blur,
            glassColor: teinte ??
                (OuroColors.isDark
                    ? const Color(0x14FFFFFF)
                    : const Color(0x1FFFFFFF)),
            refractiveIndex: 1.42,
            // La lumière vient d'en haut à gauche, dans toute
            // l'application comme dans tout iOS. ⚠️ En RADIANS.
            lightAngle: 1.25 * math.pi,
            lightIntensity: OuroColors.isDark ? 1.15 : 0.85,
            ambientStrength: 0.45,
            chromaticAberration: 0.012,
            saturation: 1.08,
          ),
          shape: LiquidRoundedSuperellipse(borderRadius: borderRadius),
          child: child,
        );
      },
    );
  }
}
