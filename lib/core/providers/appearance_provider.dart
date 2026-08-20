// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le réglage d'APPARENCE de l'app : sombre, clair, ou « comme le
// téléphone ».
//
// LE MODE SOMBRE RESTE LE DÉFAUT. Ce n'est pas un détail : Droplet est
// une app de terrain, souvent utilisée de nuit, en extérieur ou en
// situation d'urgence, et sur un écran OLED les pixels noirs sont
// littéralement éteints — moins de batterie consommée, et aucun
// éblouissement dans le noir. Le mode clair est là pour ceux qui en ont
// besoin (plein soleil, préférence personnelle, confort de lecture), pas
// comme réglage recommandé.
//
// Le choix est conservé d'un lancement à l'autre dans le petit magasin
// clé/valeur de `storage_service.dart`.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage_service.dart';

/// Les trois choix possibles d'apparence.
enum AppearanceMode {
  /// Suit le réglage du téléphone.
  system,

  /// Toujours clair.
  light,

  /// Toujours sombre — le défaut de Droplet.
  dark;

  /// Libellé affiché dans les réglages.
  String get label => switch (this) {
        AppearanceMode.system => 'Automatique',
        AppearanceMode.light => 'Clair',
        AppearanceMode.dark => 'Sombre',
      };

  /// La luminosité effective de ce mode.
  ///
  /// Le mode « Automatique » a besoin de connaître le réglage du
  /// téléphone, d'où le paramètre — c'est aussi la raison pour laquelle
  /// on ne passe pas par le `ThemeMode` de Flutter : l'app doit
  /// connaître la luminosité RETENUE avant de construire quoi que ce
  /// soit, puisque `OuroColors` s'appuie dessus (voir `main.dart`).
  Brightness resolve(Brightness systemBrightness) => switch (this) {
        AppearanceMode.system => systemBrightness,
        AppearanceMode.light => Brightness.light,
        AppearanceMode.dark => Brightness.dark,
      };
}

const String _appearanceKey = 'appearance_mode';

/// Le mode d'apparence choisi, persisté entre deux lancements.
final appearanceProvider =
    StateNotifierProvider<AppearanceNotifier, AppearanceMode>((ref) {
  return AppearanceNotifier();
});

class AppearanceNotifier extends StateNotifier<AppearanceMode> {
  AppearanceNotifier() : super(_load());

  static AppearanceMode _load() {
    final raw = StorageService.getString(_appearanceKey);
    return AppearanceMode.values.firstWhere(
      (m) => m.name == raw,
      // Sombre par défaut, y compris au tout premier lancement et si la
      // valeur enregistrée est corrompue ou provient d'une version
      // antérieure de l'app.
      orElse: () => AppearanceMode.dark,
    );
  }

  Future<void> set(AppearanceMode mode) async {
    state = mode;
    await StorageService.setString(_appearanceKey, mode.name);
  }
}
