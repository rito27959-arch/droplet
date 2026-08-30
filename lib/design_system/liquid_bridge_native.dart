import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'ouro_colors.dart';

/// Vrai si l'appareil est iOS.
bool get isNativeGlassAvailable => defaultTargetPlatform == TargetPlatform.iOS;

// ============================================================================
// NAVIGATION BAR
// ============================================================================

class NativeGlassNavigationBar extends StatelessWidget {
  const NativeGlassNavigationBar({
    super.key,
    this.title,
    this.leading,
    this.trailing,
  });

  final String? title;
  final Widget? leading;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return CupertinoNavigationBar(
      leading: leading,
      middle: title != null ? Text(title!) : null,
      trailing: trailing,
      backgroundColor: Colors.transparent,
    );
  }
}

// ============================================================================
// ALERT DIALOG
// ============================================================================

Future<T?> showNativeGlassAlert<T>(
  BuildContext context, {
  required String title,
  String? message,
  List<NativeGlassAlertAction>? actions,
}) {
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
// TOGGLE (SWITCH)
// ============================================================================

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
    return Switch.adaptive(
      value: value,
      activeTrackColor: OuroColors.systemGreen,
      onChanged: onChanged,
    );
  }
}

// ============================================================================
// SLIDER
// ============================================================================

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
// SEGMENTED CONTROL
// ============================================================================

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
// CONTAINER
// ============================================================================

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
// ACTIVITY INDICATOR
// ============================================================================

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
    return CupertinoActivityIndicator(
      animating: animating,
      radius: size / 2,
    );
  }
}
