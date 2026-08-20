// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le petit bandeau d'information qui apparaît brièvement pour signaler
// quelque chose (« Message envoyé », « Échec de l'envoi »).
//
// CE QUI A CHANGÉ À LA REFONTE : il descend maintenant du HAUT de
// l'écran, dans une capsule translucide floutée — c'est la forme que
// prennent toutes les notifications système d'iOS (changement de sonnerie,
// AirPods connectés, copie effectuée). L'ancienne version tombait du haut
// avec un rebond élastique et une bordure colorée épaisse : deux marqueurs
// immédiats de design amateur.
//
// La couleur ne sert plus de fond : seule une petite icône est colorée.
// Le fond reste neutre quelle que soit la nature du message — un bandeau
// entièrement rouge pour une simple erreur d'envoi est disproportionné,
// et fatigue à force de se répéter.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/providers/mesh_provider.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/design_tokens.dart';

/// Affiche les notifications éphémères par-dessus toute l'app.
class ToastOverlay extends ConsumerWidget {
  const ToastOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final toast = ref.watch(toastProvider);
    return Stack(
      children: [
        child,
        Positioned(
          top: MediaQuery.paddingOf(context).top + DesignTokens.space2,
          left: 0,
          right: 0,
          child: Center(
            // AnimatedSwitcher enchaîne proprement deux notifications qui
            // se succèdent, au lieu de faire disparaître brutalement la
            // première.
            child: AnimatedSwitcher(
              duration: DesignTokens.durationFast,
              switchInCurve: DesignTokens.curveEnter,
              switchOutCurve: DesignTokens.curveExit,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, -0.4),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: toast == null
                  ? const SizedBox.shrink()
                  : _ToastCapsule(toast, key: ValueKey(toast.message)),
            ),
          ),
        ),
      ],
    );
  }
}

/// La capsule translucide elle-même.
class _ToastCapsule extends StatelessWidget {
  const _ToastCapsule(this.toast, {super.key});
  final DropletToast toast;

  /// Seule l'icône porte la couleur — jamais le fond.
  Color get _iconColor => switch (toast.type) {
        DropletToastType.success => OuroColors.systemGreen,
        DropletToastType.warning => OuroColors.systemOrange,
        DropletToastType.error => OuroColors.systemRed,
        DropletToastType.info => OuroColors.accent,
      };

  IconData get _icon => switch (toast.type) {
        DropletToastType.success => Icons.check_circle_rounded,
        DropletToastType.warning => Icons.warning_rounded,
        DropletToastType.error => Icons.error_rounded,
        DropletToastType.info => Icons.info_rounded,
      };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.screenMargin,
      ),
      child: OuroBlurSurface(
        material: OuroMaterial.thick,
        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space4,
          vertical: DesignTokens.space3,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icon, color: _iconColor, size: DesignTokens.iconMd),
            const SizedBox(width: DesignTokens.space2),
            Flexible(
              child: Text(
                toast.message,
                style: OuroTypography.subheadline.copyWith(
                  color: OuroColors.label,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
