// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// La bulle « … en train d'écrire » qui apparaît quand l'autre personne
// tape un message.
//
// CE QUI A CHANGÉ À LA REFONTE : c'est désormais la reproduction exacte
// de celle de Messages sur iOS — trois points GRIS dans une bulle grise,
// qui s'éclaircissent tour à tour en une vague lente. L'ancienne version
// utilisait trois gouttelettes en dégradé bleu qui SAUTAIENT avec un
// rebond élastique : trop voyant pour une information aussi mineure, et
// un rappel constant que quelqu'un tape, là où iOS reste discret.
//
// Le mouvement ici est volontairement lent (1,4 s par cycle) et ne
// déplace rien : seule l'opacité varie. Un élément qui bouge dans le
// champ de vision attire l'œil en permanence ; un élément qui respire se
// fait oublier.
// ============================================================================

import 'package:flutter/material.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/design_tokens.dart';

/// Indicateur de frappe façon Messages iOS : trois points gris qui
/// s'éclaircissent en vague dans une bulle.
class TypingIndicator extends StatefulWidget {
  const TypingIndicator({super.key});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.space4,
        vertical: DesignTokens.space3 + 2,
      ),
      decoration: BoxDecoration(
        color: OuroColors.bubbleIncoming,
        // Même forme qu'une bulle reçue : coin bas-gauche resserré, le
        // reste très arrondi. La cohérence de forme fait comprendre
        // immédiatement que c'est « un message en préparation ».
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(DesignTokens.radiusBubble),
          topRight: Radius.circular(DesignTokens.radiusBubble),
          bottomRight: Radius.circular(DesignTokens.radiusBubble),
          bottomLeft: Radius.circular(DesignTokens.space1),
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              // Chaque point est décalé d'un tiers de cycle : c'est ce
              // décalage qui crée la vague de gauche à droite.
              final phase = (_controller.value - i * 0.18) % 1.0;
              // La courbe monte puis redescend sur la première moitié du
              // cycle, et reste au repos sur la seconde — d'où la pause
              // entre deux vagues, exactement comme sur iOS.
              final wave = phase < 0.5
                  ? Curves.easeInOut.transform(phase * 2)
                  : Curves.easeInOut.transform((1 - phase) * 2);
              final opacity = 0.35 + wave.clamp(0.0, 1.0) * 0.55;

              return Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 5),
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: OuroColors.systemGray.withValues(alpha: opacity),
                  ),
                ),
              );
            }),
          );
        },
      ),
    );
  }
}
