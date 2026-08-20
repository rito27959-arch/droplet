// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE VERRE LIQUIDE — le matériau d'iOS 26, celui que WhatsApp a adopté sur
// iPhone au printemps 2026.
//
// ── Ce que ça fait, et pourquoi ça ne ressemble à rien d'autre ────────
//
// Le flou classique (`BackdropFilter`, notre `glassmorphism.dart`) prend ce
// qu'il y a derrière et le rend illisible. C'est du verre dépoli : joli,
// mais mort. Il ne se passe rien quand le contenu défile dessous.
//
// Le verre liquide fait autre chose : il RÉFRACTE. Les pixels du dessous
// sont déviés comme à travers une vraie lentille, plus fort près des bords
// qu'au centre, avec un liseré lumineux là où la lumière rase la tranche.
// Résultat : un texte qui défile sous la capsule s'y déforme et s'y étire
// en passant. La barre cesse d'être un calque posé par-dessus l'écran, elle
// devient un objet physique posé SUR le contenu.
//
// ── Les deux règles que ce fichier fait respecter ─────────────────────
//
// 1. UNE SEULE COUCHE, UN SEUL ENDROIT. Chaque `LiquidGlassLayer` est un
//    passage de shader supplémentaire. Les auteurs du paquet le disent
//    eux-mêmes : « computationally intensive », et déconseillent de
//    l'ajouter aveuglément partout. Droplet ne l'emploie donc que sur la
//    capsule d'onglets — la seule pièce de châssis visible en permanence,
//    et celle sous laquelle il défile le plus de contenu.
//
// 2. IL S'EFFACE QUAND LE TÉLÉPHONE SOUFFRE. Le paquet expose un mode
//    `fake` qui retombe sur un simple flou, à disposition identique. On
//    bascule dessus dès qu'Android signale une surchauffe (voir
//    `thermal_provider.dart`), et on y revient tout seul une fois
//    l'appareil refroidi. Spectaculaire par défaut, sobre quand il le
//    faut — sans rien demander à l'utilisateur.
//
// ⚠️ EXIGE IMPELLER. C'est le moteur de rendu par défaut de Flutter sur
// Android depuis un moment, et Droplet ne vise qu'Android. Le mode `fake`
// sert malgré tout de filet : il n'utilise aucun shader.
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import '../core/providers/thermal_provider.dart';
import 'ouro_colors.dart';
import '../core/services/device_profile.dart';

/// Vrai quand il faut renoncer aux shaders — l'appareil chauffe.
/// Faut-il renoncer au shader et retomber sur un flou ordinaire ?
///
/// Deux raisons, et elles n'ont rien à voir l'une avec l'autre :
///
///   • **la surchauffe** — état passager. Le téléphone étouffe, on lui
///     retire la charge la plus lourde le temps qu'il respire.
///   • **la mémoire de l'appareil** — état permanent. Un shader s'exécute
///     à chaque image sur le processeur graphique, souvent partagé avec
///     la mémoire système sur les appareils d'entrée de gamme. Sur un
///     téléphone de 2 Go, c'est un luxe qu'on ne peut pas se payer, et
///     ça ne s'améliorera pas en attendant.
///
/// Le repli n'est pas une absence d'effet : `fake` donne un flou de fond
/// classique, qui reste correct. On perd la soudure des formes, pas la
/// transparence.
bool ouroGlassDegraded(WidgetRef ref) =>
    DeviceProfile.sansShader || ref.watch(deviceUnderThermalStressProvider);

/// La couche où le verre est effectivement rendu, avec son GROUPE DE
/// FUSION.
///
/// ── Le groupe de fusion, c'est toute l'affaire ────────────────────────
///
/// Deux formes de verre placées dans un même `LiquidGlassBlendGroup` ne
/// se contentent pas de se superposer : quand elles s'approchent, leurs
/// contours SE SOUDENT, comme deux gouttes de mercure qui se touchent, et
/// se déchirent en s'éloignant. C'est le principe des « métaballes », et
/// c'est exactement ce qui donne son nom au verre LIQUIDE.
///
/// Sans ce groupe, l'indicateur d'onglet serait une pastille qui glisse
/// devant une barre — deux objets distincts. Avec lui, la pastille naît
/// de la barre, s'en détache en s'étirant, et s'y refond à l'arrivée. Le
/// mouvement de la nouvelle barre de WhatsApp iOS tient entièrement là.
///
/// [blend] est grosso modo la distance, en pixels, à laquelle deux formes
/// commencent à se souder. 10 est le réglage de l'exemple officiel : plus
/// haut, l'indicateur reste collé à la barre sur tout son trajet et ne se
/// détache jamais ; plus bas, il s'en sépare trop tôt et on perd
/// l'impression de matière étirée.
class OuroGlassLayer extends ConsumerWidget {
  const OuroGlassLayer({super.key, required this.child, this.blend = 10});

  final Widget child;
  final double blend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LiquidGlassLayer(
      settings: _settings,
      // Le mode dégradé garde EXACTEMENT la même disposition : seule la
      // façon de peindre change. Sans cela, la barre changerait de
      // taille en cours d'utilisation, ce qui serait bien plus visible
      // que la perte de la réfraction.
      fake: ouroGlassDegraded(ref),
      child: LiquidGlassBlendGroup(blend: blend, child: child),
    );
  }

  /// Les réglages du matériau.
  ///
  /// Chaque valeur a été choisie pour un objet POSÉ SUR du contenu qui
  /// défile, pas pour une vitrine de démonstration :
  ///
  ///   • `thickness` 14 — assez pour qu'un texte se torde visiblement en
  ///     passant sous le bord, pas assez pour qu'on ne le reconnaisse
  ///     plus. Au-delà de ~25 l'effet devient une loupe et la barre
  ///     attire l'œil plus que le contenu.
  ///   • `blur` 6 — un voile léger EN PLUS de la réfraction : les icônes
  ///     doivent rester lisibles quelle que soit l'image en dessous.
  ///   • `lightAngle` — la lumière vient d'en haut à gauche, comme dans
  ///     tout le reste de l'app et comme sur iOS. ⚠️ Le paquet attend des
  ///     RADIANS, pas des degrés : passer « 285 » enroulerait l'angle
  ///     quarante-cinq fois sur lui-même.
  ///   • `chromaticAberration` 0,012 — la frange colorée sur la tranche,
  ///     comme au bord d'une vraie lentille. Discrète : au-delà, les
  ///     icônes se mettent à baver.
  ///   • `saturation` 1.08 — les couleurs qui traversent le verre sont
  ///     très légèrement ravivées. C'est un détail d'Apple qu'on ne
  ///     remarque jamais consciemment, et qui manque quand il n'est pas
  ///     là : sans lui, la matière paraît grise.
  static LiquidGlassSettings get settings => _settings;

  static LiquidGlassSettings get _settings => LiquidGlassSettings(
        thickness: 14,
        blur: 6,
        glassColor: OuroColors.isDark
            ? const Color(0x14FFFFFF)
            : const Color(0x1FFFFFFF),
        refractiveIndex: 1.42,
        lightAngle: 1.25 * math.pi,
        lightIntensity: OuroColors.isDark ? 1.15 : 0.85,
        ambientStrength: 0.45,
        chromaticAberration: 0.012,
        saturation: 1.08,
      );
}
