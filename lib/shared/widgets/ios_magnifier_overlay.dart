import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'native_magnifier_channel.dart';

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
    setState(() {});
  }

  void _onLongPressMoveUpdate(LongPressMoveUpdateDetails details) {
    if (!_active) return;
    if (_isIOS) {
      NativeMagnifierChannel.move(
        details.localPosition.dx,
        details.localPosition.dy,
      );
    }
    setState(() {});
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    _active = false;
    if (_isIOS) {
      NativeMagnifierChannel.hide();
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_isIOS) {
      return GestureDetector(
        onLongPressStart: _onLongPressStart,
        onLongPressMoveUpdate: _onLongPressMoveUpdate,
        onLongPressEnd: _onLongPressEnd,
        child: widget.child,
      );
    }

    if (!widget.activated) return widget.child;

    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressMoveUpdate: _onLongPressMoveUpdate,
      onLongPressEnd: _onLongPressEnd,
      child: widget.child,
    );
  }
}
