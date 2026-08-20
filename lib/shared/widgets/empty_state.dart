// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Ce qui s'affiche quand un écran n'a rien à montrer (aucune
// conversation, aucun statut, aucun résultat de recherche).
//
// CE QUI A CHANGÉ À LA REFONTE : c'est maintenant l'état vide d'iOS —
// une icône grise fine, un titre, un texte d'explication, centrés et
// SOBRES. L'ancienne version affichait l'icône dans un cercle coloré qui
// grossissait avec un rebond élastique, puis faisait glisser chaque
// ligne de texte l'une après l'autre.
//
// Pourquoi c'était un problème : un écran vide n'est pas un événement à
// célébrer, c'est une information neutre. Une animation d'entrée
// élaborée pour dire « il n'y a rien ici » attire l'attention sur
// l'absence, et se rejoue à chaque fois qu'on revient sur l'écran. iOS
// affiche ses états vides sans aucune animation d'entrée.
// ============================================================================

import 'package:animated_emoji/animated_emoji.dart';
import 'package:flutter/material.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/design_tokens.dart';
import 'scene_animee.dart';

/// État vide façon iOS : icône grise fine, titre, explication.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconColor,
    this.action,
    this.emoji,
  });

  /// L'animation à jouer à la place de l'icône, quand il y en a une.
  ///
  /// ⚠️ Facultative, et c'est délibéré. [icon] reste OBLIGATOIRE et sert
  /// de repli : si l'animation ne se charge pas — asset non déclaré,
  /// fichier abîmé, mémoire insuffisante — l'écran retombe exactement
  /// sur ce qu'il affichait avant. Un état vide qui deviendrait un état
  /// CASSÉ serait un très mauvais échange.
  ///
  /// Les valeurs à passer sont dans `Scenes` (`scene_animee.dart`), qui
  /// tient la liste de toutes les scènes de l'application au même
  /// endroit — sans quoi chaque écran choisirait la sienne dans son coin
  /// et l'ensemble n'aurait plus aucune cohérence.
  final AnimatedEmojiData? emoji;

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Conservé pour compatibilité — l'icône d'un état vide reste grise
  /// dans le nouveau design, quelle que soit la valeur passée.
  final Color? iconColor;

  /// Bouton d'action facultatif (« Créer un groupe »).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null)
              SceneAnimee(
                emoji: emoji!,
                iconeDeSecours: icon,
                taille: 88,
              )
            else
              Icon(
                icon,
                // Grande et grise : présente sans être un point focal.
                size: 52,
                color: OuroColors.systemGray3,
              ),
            const SizedBox(height: DesignTokens.space4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: OuroTypography.title3.copyWith(color: OuroColors.label),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: DesignTokens.space2),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: OuroTypography.subheadline.copyWith(
                  color: OuroColors.secondaryLabel,
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: DesignTokens.space5),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
