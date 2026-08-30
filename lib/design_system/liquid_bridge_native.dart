// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le pont vers le VRAI Liquid Glass UIKit natif (iOS 26+).
//
// Sur iOS 26+, les composants UIKit reçoivent automatiquement le style
// Liquid Glass via UIGlassEffect. Ce fichier expose des wrappers qui
// utilisent les composants natifs quand disponibles, et retombent sur
// les implémentations Dart existantes (liquid_glass_ui_design) sur les
// anciennes plateformes.
//
// ── POURQUOI UN PONT SÉPARÉ ? ───────────────────────────────────────────
//
// 1. iOS 26+ n'est pas encore généralisé. La plupart des appareils
//    tournent encore sous iOS 17-18. Il faut un fallback gracieux.
// 2. Les composants natifs ont des API différentes (Platform Views).
//    Le pont cache cette complexité derrière une interface Flutter.
// 3. Les composants Dart restent nécessaires pour Android et web.
// ============================================================================

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:native_liquid_glass/native_liquid_glass.dart';

import 'ouro_colors.dart';

/// Vrai si l'appareil supporte le Liquid Glass natif (iOS 26+).
bool get isNativeGlassAvailable =>
    defaultTargetPlatform == TargetPlatform.iOS &&
    NativeLiquidGlassUtils.supportsLiquidGlass;

// ============================================================================
// NAVIGATION BAR — UINavigationBar native
// ============================================================================

/// Barre de navigation iOS avec Liquid Glass natif.
///
/// Sur iOS 26+ : `LiquidGlassNavigationBar` (UINavigationBar native).
/// Sur les autres : `CupertinoNavigationBar` classique.
class NativeGlassNavigationBar extends StatelessWidget {
  const NativeGlassNavigationBar({
    super.key,
    this.title,
    this.leading,
    this.trailing,
    this.leadingItems = const [],
    this.trailingItems = const [],
    this.onItemTapped,
  });

  final String? title;
  final Widget? leading;
  final Widget? trailing;
  final List<LiquidGlassNavBarItem> leadingItems;
  final List<LiquidGlassNavBarItem> trailingItems;
  final ValueChanged<String>? onItemTapped;

  @override
  Widget build(BuildContext context) {
    if (isNativeGlassAvailable) {
      return LiquidGlassNavigationBar(
        title: title ?? '',
        leadingItems: leadingItems,
        trailingItems: trailingItems,
        onItemTapped: onItemTapped ?? (_) {},
      );
    }

    return CupertinoNavigationBar(
      leading: leading,
      middle: title != null ? Text(title!) : null,
      trailing: trailing,
      backgroundColor: Colors.transparent,
    );
  }
}

// ============================================================================
// ALERT DIALOG — UIAlertController native
// ============================================================================

/// Alerte iOS avec Liquid Glass natif.
///
/// Sur iOS 26+ : `LiquidGlassAlert` (UIAlertController natif).
/// Sur les autres : `CupertinoAlertDialog` classique.
Future<T?> showNativeGlassAlert<T>(
  BuildContext context, {
  required String title,
  String? message,
  List<NativeGlassAlertAction>? actions,
}) {
  if (isNativeGlassAvailable) {
    return LiquidGlassAlert.show(
      context: context,
      title: title,
      message: message ?? '',
      actions: (actions ?? []).map((a) {
        return LiquidGlassAlertAction(
          id: a.id,
          title: a.label,
          isDestructive: a.destructive,
          isCancel: a.isCancel,
        );
      }).toList(),
    ).then((id) {
      if (id == null) return null;
      final match = actions?.where((a) => a.id == id);
      return match?.isNotEmpty == true ? match!.first.value as T : null;
    });
  }

  // Fallback : CupertinoAlertDialog
  return showCupertinoDialog<T>(
    context: context,
    builder: (ctx) => CupertinoTheme(
      data: CupertinoThemeData(brightness: OuroColors.brightness),
      child: CupertinoAlertDialog(
        title: Text(title),
        content: message != null ? Text(message) : null,
        actions: [
          if (actions != null)
            for (final a in actions)
              CupertinoDialogAction(
                isDefaultAction: a.isCancel,
                isDestructiveAction: a.destructive,
                onPressed: () => Navigator.of(ctx).pop(a.value),
                child: Text(a.label),
              ),
        ],
      ),
    ),
  );
}

/// Une action pour `showNativeGlassAlert`.
class NativeGlassAlertAction<T> {
  const NativeGlassAlertAction({
    required this.id,
    required this.label,
    this.value,
    this.destructive = false,
    this.isCancel = false,
  });

  final String id;
  final String label;
  final T? value;
  final bool destructive;
  final bool isCancel;
}

// ============================================================================
// TOGGLE (SWITCH) — UISwitch natif
// ============================================================================

/// Interrupteur iOS avec Liquid Glass natif.
///
/// Sur iOS 26+ : `LiquidGlassToggle` (UISwitch natif).
/// Sur les autres : `Switch.adaptive` classique.
class NativeGlassToggle extends StatelessWidget {
  const NativeGlassToggle({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    if (isNativeGlassAvailable) {
      return LiquidGlassToggle(
        value: value,
        onChanged: onChanged ?? (_) {},
      );
    }

    return Switch.adaptive(
      value: value,
      activeTrackColor: OuroColors.systemGreen,
      onChanged: onChanged,
    );
  }
}

// ============================================================================
// SLIDER — UISlider natif
// ============================================================================

/// Curseur iOS avec Liquid Glass natif.
///
/// Sur iOS 26+ : `LiquidGlassSlider` (UISlider natif).
/// Sur les autres : `CupertinoSlider` classique.
class NativeGlassSlider extends StatelessWidget {
  const NativeGlassSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.activeTrackColor,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final Color? activeTrackColor;

  @override
  Widget build(BuildContext context) {
    if (isNativeGlassAvailable) {
      return LiquidGlassSlider(
        value: value,
        min: min,
        max: max,
        onChanged: onChanged ?? (_) {},
      );
    }

    return CupertinoSlider(
      value: value,
      min: min,
      max: max,
      divisions: divisions,
      activeColor: activeTrackColor ?? OuroColors.accent,
      onChanged: onChanged,
    );
  }
}

// ============================================================================
// SEGMENTED CONTROL — UISegmentedControl natif
// ============================================================================

/// Sélecteur segmenté iOS avec Liquid Glass natif.
///
/// Sur iOS 26+ : `LiquidGlassSegmentedControl` (UISegmentedControl natif).
/// Sur les autres : `CupertinoSegmentedControl` classique.
class NativeGlassSegmentedControl<T> extends StatelessWidget {
  const NativeGlassSegmentedControl({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onValueChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onValueChanged;

  @override
  Widget build(BuildContext context) {
    if (isNativeGlassAvailable) {
      return LiquidGlassSegmentedControl(
        labels: labels,
        selectedIndex: selectedIndex,
        onValueChanged: onValueChanged,
      );
    }

    return CupertinoSegmentedControl(
      groupValue: selectedIndex,
      onValueChanged: (i) => onValueChanged(i),
      children: {
        for (int i = 0; i < labels.length; i++)
          i: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(labels[i], style: const TextStyle(fontSize: 13)),
          ),
      },
    );
  }
}

// ============================================================================
// CONTAINER — UIView natif avec Liquid Glass
// ============================================================================

/// Conteneur Liquid Glass natif.
///
/// Sur iOS 26+ : `LiquidGlassContainer` (UIView avec UIGlassEffect).
/// Sur les autres : un Container avec décoration glassmorphism Dart.
class NativeGlassContainer extends StatelessWidget {
  const NativeGlassContainer({
    super.key,
    required this.child,
    this.borderRadius,
    this.tint,
    this.width,
    this.height,
    this.padding,
  });

  final Widget child;
  final double? borderRadius;
  final Color? tint;
  final double? width;
  final double? height;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    if (isNativeGlassAvailable) {
      return LiquidGlassContainer(
        config: LiquidGlassConfig(
          effect: LiquidGlassEffect.regular,
          shape: borderRadius != null
              ? LiquidGlassEffectShape.rect
              : LiquidGlassEffectShape.capsule,
          tint: tint ?? OuroColors.accent.withValues(alpha: 0.14),
        ),
        width: width,
        height: height,
        child: padding != null ? Padding(padding: padding!, child: child) : child,
      );
    }

    // Fallback Dart : simple conteneur translucide
    return Container(
      width: width,
      height: height,
      padding: padding,
      decoration: BoxDecoration(
        color: (tint ?? OuroColors.accent).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(borderRadius ?? 16),
      ),
      child: child,
    );
  }
}

// ============================================================================
// ACTIVITY INDICATOR — UIActivityIndicatorView natif
// ============================================================================

/// Indicateur de chargement iOS avec Liquid Glass natif.
///
/// Sur iOS 26+ : `LiquidGlassActivityIndicator` (UIActivityIndicatorView).
/// Sur les autres : `CupertinoActivityIndicator` classique.
class NativeGlassActivityIndicator extends StatelessWidget {
  const NativeGlassActivityIndicator({
    super.key,
    this.animating = true,
    this.size = 28,
  });

  final bool animating;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (isNativeGlassAvailable) {
      return LiquidGlassActivityIndicator(
        animating: animating,
      );
    }

    return CupertinoActivityIndicator(
      animating: animating,
      radius: size / 2,
    );
  }
}
