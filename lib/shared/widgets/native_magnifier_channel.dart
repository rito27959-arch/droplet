import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Canal de communication avec la loupe native iOS (UITextLoupeSession).
///
/// Sur iOS, utilise l'API native Apple pour afficher la vraie loupe système.
/// Sur les autres plateformes, fait rien (null-safe).
class NativeMagnifierChannel {
  NativeMagnifierChannel._();

  static const _channel = MethodChannel('droplet/native_magnifier');

  static bool get _isIOS => defaultTargetPlatform == TargetPlatform.iOS;

  /// Affiche la loupe native à la position donnée (coordonnées locales).
  static Future<void> show(double x, double y) async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod('show', {'x': x, 'y': y});
    } on PlatformException catch (e) {
      debugPrint('NativeMagnifier.show error: $e');
    }
  }

  /// Déplace la loupe native vers une nouvelle position.
  static Future<void> move(double x, double y) async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod('move', {'x': x, 'y': y});
    } on PlatformException catch (e) {
      debugPrint('NativeMagnifier.move error: $e');
    }
  }

  /// Masque et détruit la loupe native.
  static Future<void> hide() async {
    if (!_isIOS) return;
    try {
      await _channel.invokeMethod('hide');
    } on PlatformException catch (e) {
      debugPrint('NativeMagnifier.hide error: $e');
    }
  }
}
