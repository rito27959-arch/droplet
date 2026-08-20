// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LES DEUX MARQUES : « premium » sur ce qui est verrouillé, « Pro » sur
// la personne qui a souscrit.
//
// ── ⚠️ POURQUOI ELLES SONT AUSSI DISCRÈTES ────────────────────────────
//
// La pente naturelle d'un badge payant est de crier : couleur vive,
// majuscules, doré. C'est exactement ce qu'il ne faut pas ici, pour deux
// raisons différentes selon le badge.
//
// L'ÉTIQUETTE PREMIUM se pose sur une grille d'icônes ou de fonds que
// l'on parcourt à l'œil. Si elle attire plus que l'icône qu'elle
// désigne, elle empêche précisément ce qu'on cherche à provoquer :
// avoir envie de l'icône. Elle doit se lire au deuxième regard, pas au
// premier.
//
// LE BADGE PRO, lui, apparaît à côté du nom de quelqu'un, sur tous les
// écrans. Un badge tapageur porté en permanence devient une gêne pour
// celui qui le porte — et il l'a payé. Il doit se remarquer une fois,
// puis se faire oublier.
//
// Les deux sont donc en petites capitales espacées, dans un aplat très
// pâle de la couleur d'accent. C'est le traitement d'iOS pour ses
// propres marques : lisible, jamais bruyant.
// ============================================================================

import 'package:flutter/material.dart';

import '../../design_system/ouro_colors.dart';

/// L'étiquette posée sur un contenu verrouillé.
class EtiquettePremium extends StatelessWidget {
  const EtiquettePremium({super.key, this.compacte = false});

  /// Version réduite à une étoile, pour les vignettes trop petites pour
  /// accueillir un mot.
  final bool compacte;

  @override
  Widget build(BuildContext context) {
    if (compacte) {
      return Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: OuroColors.systemBackground.withValues(alpha: 0.82),
        ),
        child: Icon(Icons.auto_awesome_rounded,
            size: 10, color: OuroColors.accent),
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: OuroColors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'PREMIUM',
        style: TextStyle(
          fontSize: 8,
          height: 1.3,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
          color: OuroColors.accent,
        ),
      ),
    );
  }
}

/// Le badge porté par une personne abonnée à Droplet Pro.
class BadgePro extends StatelessWidget {
  const BadgePro({super.key, this.taille = 11});

  final double taille;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Droplet Pro',
      excludeSemantics: true,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: taille * 0.55,
          vertical: taille * 0.16,
        ),
        decoration: BoxDecoration(
          // Un dégradé très court, presque un aplat : il attrape la
          // lumière quand on incline le téléphone, sans jamais se
          // comporter comme un bouton.
          gradient: LinearGradient(
            colors: [
              OuroColors.accent,
              Color.lerp(OuroColors.accent, OuroColors.systemPurple, 0.45)!,
            ],
          ),
          borderRadius: BorderRadius.circular(taille * 0.42),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded,
                size: taille * 0.82, color: Colors.white),
            SizedBox(width: taille * 0.24),
            Text(
              'PRO',
              style: TextStyle(
                fontSize: taille * 0.76,
                height: 1.25,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le voile posé sur une vignette verrouillée.
///
/// ⚠️ IL ASSOMBRIT SANS CACHER. Un contenu payant qu'on ne voit pas ne
/// donne envie de rien : c'est la vue de l'icône qui déclenche l'achat,
/// pas le cadenas. On retire donc de la lumière, juste assez pour dire
/// « pas encore à vous », et pas un point de plus.
class VoileVerrouille extends StatelessWidget {
  const VoileVerrouille({super.key, required this.child, required this.verrouille});

  final Widget child;
  final bool verrouille;

  @override
  Widget build(BuildContext context) {
    if (!verrouille) return child;
    return Stack(
      children: [
        Opacity(opacity: 0.42, child: child),
        Positioned(
          right: 4,
          top: 4,
          child: const EtiquettePremium(compacte: true),
        ),
      ],
    );
  }
}
