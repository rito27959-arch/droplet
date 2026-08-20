// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Certains moments dans l'app méritent plus qu'un simple petit toast qui
// passe vite en bas de l'écran (comme quand on vérifie que le code de
// sécurité d'un contact correspond bien, ou qu'une sauvegarde chiffrée
// vient de réussir) — ce sont des instants de CONFIANCE importants, où
// on veut vraiment rassurer l'utilisateur. Ce fichier affiche alors un
// grand « sceau » rond avec une icône entourée d'une lueur, et un
// message, au centre de l'écran, comme un vrai tampon officiel qui
// vient confirmer que « oui, c'est bien vérifié/réussi ».
//
// Il disparaît automatiquement après un peu plus d'une seconde, ou si
// on tape à côté — pas besoin d'appuyer sur un bouton « OK ».
// ============================================================================

import 'dart:ui' as ui;
import 'package:animated_emoji/animated_emoji.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/design_tokens.dart';
import 'scene_animee.dart';

/// Sceau de confirmation plein écran pour les moments de confiance de l'app
/// (vérification de clé, sauvegarde chiffrée réussie…) — un simple toast ne
/// suffit pas à marquer l'importance de ces instants. S'auto-ferme après une
/// brève pause ; peut aussi être fermé en tapant à côté.
class SuccessSeal extends StatefulWidget {
  const SuccessSeal({
    super.key,
    required this.icon,
    required this.message,
    this.color,
    this.emoji,
  });

  final IconData icon;
  final String message;
  final Color? color;

  /// L'animation jouée dans le sceau, quand il y en a une.
  ///
  /// Facultative : [icon] reste le repli. Elle ne se répète PAS — un
  /// sceau de confirmation dure 1,2 seconde et disparaît ; une boucle
  /// n'aurait pas le temps de se voir, et donnerait surtout l'impression
  /// que quelque chose est encore en cours alors que c'est fini.
  final AnimatedEmojiData? emoji;

  /// Affiche le sceau par-dessus l'écran actuel, avec une petite
  /// vibration (haptique) au moment où il apparaît, pour renforcer la
  /// sensation « c'est confirmé ».
  static Future<void> show(
    BuildContext context, {
    required IconData icon,
    required String message,
    Color? color,
    AnimatedEmojiData? emoji,
  }) {
    HapticFeedback.mediumImpact();
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: message,
      barrierColor: Colors.transparent,
      transitionDuration: DesignTokens.durationNormal,
      pageBuilder: (context, animation, secondaryAnimation) =>
          SuccessSeal(
            icon: icon,
            message: message,
            color: color,
            emoji: emoji,
          ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 6 * animation.value, sigmaY: 6 * animation.value),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
    );
  }

  @override
  State<SuccessSeal> createState() => _SuccessSealState();
}

class _SuccessSealState extends State<SuccessSeal> {
  @override
  void initState() {
    super.initState();
    // Se referme tout seul après 1,2 seconde — assez de temps pour être
    // lu, pas assez pour devenir gênant.
    Future.delayed(const Duration(milliseconds: 1200), () {
      if (mounted) Navigator.of(context).pop();
    });
  }

  @override
  Widget build(BuildContext context) {
    // Résolue à l'affichage plutôt qu'en valeur par défaut du
    // constructeur : la couleur d'accent dépend désormais du mode
    // clair/sombre, elle ne peut donc plus être une constante figée à la
    // construction du widget.
    final seal = widget.color ?? OuroColors.systemGreen;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: seal.withValues(alpha: 0.16),
              border: Border.all(color: seal, width: 2),
              boxShadow: DesignTokens.glow(seal, radius: 32),
            ),
            child: Center(
              child: widget.emoji != null
                  ? SceneAnimee(
                      emoji: widget.emoji!,
                      iconeDeSecours: widget.icon,
                      taille: 68,
                      repete: false,
                    )
                  : Icon(widget.icon, color: seal, size: 60),
            ),
          )
              .animate()
              .fadeIn(duration: DesignTokens.durationFast)
              .scaleXY(begin: 0.4, curve: DesignTokens.curveBounce, duration: DesignTokens.durationSlow),
          const SizedBox(height: 18),
          Text(widget.message,
                  style: TextStyle(color: OuroColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w800))
              .animate()
              .fadeIn(delay: 150.ms, duration: DesignTokens.durationNormal),
        ],
      ),
    );
  }
}
