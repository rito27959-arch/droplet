import 'package:flutter/services.dart';

/// Service de sons et vibrations pour l'app.
///
/// Utilise principalement les vibrations natives d'iOS/Android.
/// Quand des fichiers audio seront ajoutés, c'est un drop-in replacement.
class SoundService {
  static bool enabled = true;

  static void messageSent() {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }

  static void messageReceived() {
    if (!enabled) return;
    HapticFeedback.mediumImpact();
  }

  static void error() {
    if (!enabled) return;
    HapticFeedback.heavyImpact();
  }

  static void success() {
    if (!enabled) return;
    HapticFeedback.selectionClick();
  }

  static void buttonTap() {
    if (!enabled) return;
    HapticFeedback.lightImpact();
  }
}
