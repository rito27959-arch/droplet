// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est la petite rangée de barres fines tout en haut de l'écran quand
// on regarde des statuts, exactement comme sur Instagram Stories ou les
// statuts WhatsApp. Chaque barre représente UN statut : entièrement
// remplie s'il a déjà été regardé, en train de se remplir petit à petit
// pour celui qu'on regarde en ce moment, et encore vide pour ceux qu'on
// n'a pas encore vus — comme une jauge de progression, mais découpée en
// plusieurs petits segments au lieu d'une seule grande barre.
// ============================================================================

import 'package:flutter/material.dart';

/// Barres de progression segmentées façon Stories (Instagram/WhatsApp
/// Status) : un segment par élément, rempli entièrement pour les éléments
/// déjà vus, partiellement pour l'élément courant selon [progress], vide
/// pour les suivants.
class StoryProgressBar extends StatelessWidget {
  const StoryProgressBar({
    super.key,
    required this.count,
    required this.currentIndex,
    required this.progress,
    this.activeColor = Colors.white,
    this.trackColor = Colors.white24,
  });

  final int count;
  final int currentIndex;
  /// Avancement du segment courant, 0..1.
  final double progress;
  final Color activeColor;
  final Color trackColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: List.generate(count, (i) {
        // Pour chaque segment : 100% rempli si c'est un statut déjà vu,
        // le pourcentage exact d'avancement si c'est celui en cours,
        // 0% (vide) pour tous les suivants.
        final double value = i < currentIndex ? 1.0 : (i == currentIndex ? progress.clamp(0.0, 1.0) : 0.0);
        return Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            height: 3,
            decoration: BoxDecoration(
              color: trackColor,
              borderRadius: BorderRadius.circular(2),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: value,
              child: Container(
                decoration: BoxDecoration(
                  color: activeColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}
