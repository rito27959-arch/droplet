import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:raw_magnifier_plus/raw_magnifier_plus.dart';

import 'native_magnifier_channel.dart';

/// Overlay de loupe iOS-style.
///
/// - **iOS** : utilise l'API native `UITextLoupeSession` via platform channel
///   pour la vraie loupe système d'Apple (10/10 fidélité).
/// - **Autres plateformes** : utilise `raw_magnifier_plus` (RawMagnifier natif)
///   avec forme `RoundedRectangleBorder`.
class IosMagnifierOverlay extends StatefulWidget {
  const IosMagnifierOverlay({
    super.key,
    required this.child,
    this.activated = true,
    this.lensRadius = 65,
    this.magnification = 2.0,
  });

  final Widget child;
  final bool activated;
  final double lensRadius;
  final double magnification;

  @override
  State<IosMagnifierOverlay> createState() => _IosMagnifierOverlayState();
}

class _IosMagnifierOverlayState extends State<IosMagnifierOverlay> {
  bool _active = false;

  bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  void _onLongPressStart(LongPressStartDetails details) {
    if (!widget.activated) return;
    _active = true;
    if (_isIOS) {
      NativeMagnifierChannel.show(
        details.localPosition.dx,
        details.localPosition.dy,
      );
    }
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_active) return;
    if (_isIOS) {
      NativeMagnifierChannel.move(
        details.localPosition.dx,
        details.localPosition.dy,
      );
    }
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _active = false;
    if (_isIOS) {
      NativeMagnifierChannel.hide();
    }
  }

  @override
  Widget build(BuildContext context) {
    // Sur iOS : GestureDetector pour les gestures + loupe native
    if (_isIOS) {
      return GestureDetector(
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMoveUpdate,
        onLongPressEnd: _onLongPressEnd,
        child: widget.child,
      );
    }

    // Sur les autres plateformes : DraggableLoupe avec RawMagnifier
    if (!widget.activated) return widget.child;

    return DraggableLoupe(
      showOnLongPress: true,
      loupeSize: Size(widget.lensRadius * 2, widget.lensRadius * 2),
      magnificationScale: widget.magnification,
      verticalOffset: widget.lensRadius + 20,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      shadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.25),
          blurRadius: 16,
          spreadRadius: 2,
        ),
      ],
      animationDuration: const Duration(milliseconds: 150),
      child: widget.child,
    );
  }
}
