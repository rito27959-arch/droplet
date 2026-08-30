// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// La bulle « … en train d'écrire » qui apparaît quand l'autre personne
// tape un message.
//
// Reproduction EXACTE de l'indicateur iMessage :
//   - Trois cercles de 7pt dans une bulle grise entrante
//   - Chaque point SCALE de 0.6 à 1.0 avec un décalage de 0.2s
//   - Boucle de 1.4s, ease-in-out
//   - Couleur tertiaryLabel
// ============================================================================

import 'package:flutter/material.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/design_tokens.dart';

/// Indicateur de frappe iMessage exact : trois points gris qui
/// s'agrandissent en vague dans une bulle entrante.
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
    // iMessage : 1.4s loop
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
        horizontal: 12,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: OuroColors.bubbleIncoming,
        // Bulle iMessage entrante : coin bas-gauche pincé à 6pt
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(DesignTokens.radiusBubble),
          topRight: Radius.circular(DesignTokens.radiusBubble),
          bottomRight: Radius.circular(DesignTokens.radiusBubble),
          bottomLeft: Radius.circular(DesignTokens.radiusBubbleTail),
        ),
      ),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(3, (i) {
              // iMessage : 0.2s stagger entre chaque point
              final phase = (_controller.value - i * 0.18) % 1.0;
              // Scale de 0.6 à 1.0, ease-in-out
              final wave = phase < 0.5
                  ? Curves.easeInOut.transform(phase * 2)
                  : Curves.easeInOut.transform((1 - phase) * 2);
              final scale = 0.6 + wave.clamp(0.0, 1.0) * 0.4;

              return Padding(
                padding: EdgeInsets.only(left: i == 0 ? 0 : 4),
                child: Transform.scale(
                  scale: scale,
                  child: Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: OuroColors.tertiaryLabel,
                    ),
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
