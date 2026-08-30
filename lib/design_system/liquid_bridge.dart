// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le pont entre le design system Ouro existant et les composants
// liquid_glass_ui_design. Fournit des wrappers et des raccourcis pour
// intégrer les composants Liquid dans l'app sans réécrire tous les écrans.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:liquid_glass_ui_design/liquid_glass_ui.dart';

import 'ouro_colors.dart';
import 'design_tokens.dart';

// ============================================================================
// FONCTIONS DE CONVERSION OURO → LIQUID
// ============================================================================

Color get liquidPrimary => OuroColors.accent;
Color get liquidAccent => OuroColors.accent;
Color get liquidBackground => OuroColors.isDark
    ? const Color(0x14FFFFFF)
    : const Color(0x1FFFFFFF);
Color get liquidSurface => OuroColors.isDark
    ? const Color(0x22FFFFFF)
    : const Color(0x22F9F9FB);
double get liquidBorderRadius => DesignTokens.radiusLg;
double get liquidBlur => 20.0;

LiquidTheme get liquidTheme => LiquidTheme(
      primaryColor: liquidPrimary.withValues(alpha: 0.5),
      accentColor: liquidAccent,
      blurStrength: liquidBlur,
      borderRadius: liquidBorderRadius,
      textStyle: TextStyle(
        color: OuroColors.label,
        fontWeight: FontWeight.w500,
        fontSize: 15,
      ),
    );

// ============================================================================
// COMPOSANTS WRAPPÉS
// ============================================================================

/// Carte Liquid Glass.
class LiquidGlassCard extends StatelessWidget {
  const LiquidGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    return LiquidCard(
      color: liquidSurface,
      borderRadius: borderRadius,
      padding: padding as EdgeInsets?,
      margin: margin as EdgeInsets?,
      child: child,
    );
  }
}

/// Bouton Liquid Glass.
class LiquidGlassButton extends StatelessWidget {
  const LiquidGlassButton({
    super.key,
    required this.onTap,
    required this.child,
    this.color,
  });

  final VoidCallback? onTap;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return LiquidButton(
      onTap: onTap,
      color: color ?? liquidPrimary,
      child: child,
    );
  }
}

/// Champ de recherche Liquid.
class LiquidGlassSearch extends StatelessWidget {
  const LiquidGlassSearch({
    super.key,
    this.controller,
    this.hint,
    this.onChanged,
  });

  final TextEditingController? controller;
  final String? hint;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return LiquidSearch(
      hintText: hint ?? 'Rechercher...',
      onChanged: onChanged,
      controller: controller,
    );
  }
}

/// Indicateur de chargement Liquid (point animé).
class LiquidGlassDot extends StatelessWidget {
  const LiquidGlassDot({super.key, this.size, this.color});

  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return LiquidIndicator(
      color: color ?? OuroColors.systemGray,
      size: size ?? 12.0,
    );
  }
}

/// Interrupteur Liquid — remplace Switch.adaptive.
class LiquidGlassSwitch extends StatelessWidget {
  const LiquidGlassSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return LiquidSwitch(
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Barre de progression Liquid.
class LiquidGlassProgress extends StatelessWidget {
  const LiquidGlassProgress({
    super.key,
    required this.value,
    this.color,
  });

  final double value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return LiquidProgress(
      value: value,
      color: color ?? liquidPrimary,
    );
  }
}

/// Élément de liste Liquid.
class LiquidGlassListTile extends StatelessWidget {
  const LiquidGlassListTile({
    super.key,
    this.leading,
    this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget? leading;
  final Widget? title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return LiquidListTile(
      leading: leading,
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// Badge Liquid — pour les compteurs de notifications.
class LiquidGlassBadge extends StatelessWidget {
  const LiquidGlassBadge({
    super.key,
    required this.child,
    this.count,
    this.visible = true,
  });

  final Widget child;
  final int? count;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    if (!visible || count == null || count == 0) return child;
    return LiquidBadge(
      text: count.toString(),
      child: child,
    );
  }
}

/// Conteneur Liquid Glass basique.
class LiquidGlassBox extends StatelessWidget {
  const LiquidGlassBox({
    super.key,
    required this.child,
    this.padding,
    this.margin,
    this.borderRadius,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? borderRadius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return LiquidContainer(
      borderRadius: borderRadius ?? liquidBorderRadius,
      padding: padding as EdgeInsets?,
      margin: margin as EdgeInsets?,
      color: color ?? liquidSurface,
      child: child,
    );
  }
}

/// Skeleton de chargement Liquid.
class LiquidGlassSkeleton extends StatelessWidget {
  const LiquidGlassSkeleton({
    super.key,
    this.width,
    this.height,
    this.borderRadius,
  });

  final double? width;
  final double? height;
  final double? borderRadius;

  @override
  Widget build(BuildContext context) {
    return LiquidSkeleton(
      width: width,
      height: height ?? 16,
      borderRadius: borderRadius,
    );
  }
}

/// Effet shimmer Liquid.
class LiquidGlassShimmer extends StatelessWidget {
  const LiquidGlassShimmer({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LiquidShimmer(
      child: child,
    );
  }
}

/// Chip/tag Liquid — remplace les Chip Material.
class LiquidGlassChip extends StatelessWidget {
  const LiquidGlassChip({
    super.key,
    required this.label,
    this.onTap,
    this.selected = false,
    this.color,
  });

  final String label;
  final VoidCallback? onTap;
  final bool selected;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return LiquidChip(
      label: label,
      selected: selected,
      onSelected: onTap != null ? (_) => onTap!() : null,
      color: color ?? (selected ? liquidPrimary : liquidSurface),
    );
  }
}

/// FAB Liquid Glass — remplace FloatingActionButton.
class LiquidGlassFAB extends StatelessWidget {
  const LiquidGlassFAB({
    super.key,
    required this.onTap,
    required this.icon,
  });

  final VoidCallback? onTap;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return LiquidFAB(
      onPressed: onTap,
      icon: Icon(icon, color: Colors.white),
    );
  }
}

/// Barre de navigation inférieure Liquid.
class LiquidGlassBottomNav extends StatelessWidget {
  const LiquidGlassBottomNav({
    super.key,
    required this.icons,
    required this.currentIndex,
    required this.onTap,
  });

  final List<IconData> icons;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return LiquidBottomNav(
      icons: icons,
      onItemSelected: onTap,
    );
  }
}

/// Séparateur Liquid.
class LiquidGlassDivider extends StatelessWidget {
  const LiquidGlassDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return LiquidDivider();
  }
}

/// Affiche une alerte Liquid Glass.
Future<T?> showLiquidAlert<T>(
  BuildContext context, {
  required String title,
  required String content,
  List<Widget>? actions,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => LiquidAlert(
      title: title,
      content: content,
      actions: actions ??
          [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
    ),
  );
}

/// Affiche un dialogue Liquid Glass.
Future<T?> showLiquidDialog<T>(
  BuildContext context, {
  required Widget content,
  List<Widget>? actions,
}) {
  return showDialog<T>(
    context: context,
    builder: (ctx) => LiquidDialog(
      content: content,
      actions: actions,
    ),
  );
}

/// Affiche un toast Liquid Glass.
void showLiquidToast(
  BuildContext context, {
  required String message,
}) {
  LiquidToast(message: message).show(context);
}

/// Affiche un snackbar Liquid Glass.
void showLiquidSnackbar(
  BuildContext context, {
  required String message,
}) {
  LiquidSnackbar(message: message).show(context);
}

/// Affiche un flushbar Liquid Glass.
void showLiquidFlushbar(
  BuildContext context, {
  required String message,
}) {
  LiquidFlushbar(message: message).show(context);
}

/// Progression de chargement Liquid pleine page.
class LiquidGlassFullLoader extends StatelessWidget {
  const LiquidGlassFullLoader({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LiquidLoader(
            color: OuroColors.systemGray,
          ),
          if (message != null) ...[
            const SizedBox(height: DesignTokens.space3),
            Text(
              message!,
              style: TextStyle(
                color: OuroColors.secondaryLabel,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
