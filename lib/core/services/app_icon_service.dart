// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE CHANGEMENT D'ICÔNE DE L'APPLICATION, côté Dart.
//
// ── Pourquoi ce n'est pas juste « remplacer une image » ────────────────
//
// Android fige l'icône d'une application dans son manifeste, lu une fois
// pour toutes à l'installation. Aucune API ne permet de la remplacer en
// cours de route.
//
// La seule méthode officielle — celle qu'emploient toutes les
// applications proposant des icônes alternatives — consiste à déclarer
// PLUSIEURS points d'entrée vers la même activité, chacun portant une
// icône différente, puis à n'en laisser qu'un seul activé. Le lanceur
// affiche l'icône du point d'entrée actif ; les autres n'existent pas
// pour lui.
//
// Le travail se fait donc côté natif (`MainActivity.kt`), et ce fichier
// n'est que la télécommande.
//
// ── ⚠️ Changer d'icône ferme l'application ─────────────────────────────
//
// Désactiver le point d'entrée par lequel l'app a été lancée revient à
// scier la branche sur laquelle on est assis : Android termine le
// processus. C'est le comportement normal, y compris chez les grandes
// applications — l'écran de choix prévient donc avant d'agir.
// ============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Une icône proposée à l'utilisateur.
class AppIconOption {
  const AppIconOption({
    required this.alias,
    required this.name,
    required this.asset,
    this.premium = false,
  });

  /// Le nom de l'alias côté Android (`Default`, `V1`… `V9`).
  final String alias;

  /// Ce qu'on affiche sous la vignette.
  final String name;

  /// L'image montrée dans la grille de choix.
  final String asset;

  /// Demande le pack pour être appliquée.
  ///
  /// ⚠️ LES TROIS PREMIÈRES RESTENT LIBRES, et ce n'est pas de la
  /// générosité mal placée. Une grille entièrement verrouillée se lit
  /// comme une publicité et se referme aussitôt ; trois icônes
  /// gratuites laissent découvrir que changer d'icône est possible —
  /// et c'est cette découverte, pas le cadenas, qui donne envie des
  /// dix autres.
  final bool premium;
}

class AppIconService {
  AppIconService._();

  static const MethodChannel _channel =
      MethodChannel('com.droplet.droplet/app_icon');

  /// Les treize icônes disponibles.
  ///
  /// Les noms décrivent l'ambiance plutôt que la couleur seule : sur une
  /// grille de vignettes, « Nuit » se retient mieux que « bleu foncé ».
  static const List<AppIconOption> options = [
    AppIconOption(
      alias: 'Default',
      name: 'Originale',
      asset: 'assets/icon/droplet_icon.png',
    ),
    AppIconOption(
      alias: 'V1',
      name: 'Azur',
      asset: 'assets/icon/variants/droplet_01.png',
    ),
    AppIconOption(
      alias: 'V2',
      name: 'Néon',
      asset: 'assets/icon/variants/droplet_02.png',
    ),
    AppIconOption(
      alias: 'V3',
      name: 'Papier',
      asset: 'assets/icon/variants/droplet_03.png',
      premium: true,
    ),
    AppIconOption(
      alias: 'V4',
      name: 'Lagon',
      asset: 'assets/icon/variants/droplet_04.png',
      premium: true,
    ),
    AppIconOption(
      alias: 'V5',
      name: 'Améthyste',
      asset: 'assets/icon/variants/droplet_05.png',
      premium: true,
    ),
    AppIconOption(
      alias: 'V6',
      name: 'Or',
      asset: 'assets/icon/variants/droplet_06.png',
      premium: true,
    ),
    AppIconOption(
      alias: 'V7',
      name: 'Marée',
      asset: 'assets/icon/variants/droplet_07.png',
      premium: true,
    ),
    AppIconOption(
      alias: 'V8',
      name: 'Aurore',
      asset: 'assets/icon/variants/droplet_08.png',
      premium: true,
    ),
    AppIconOption(
      alias: 'V9',
      name: 'Verre',
      asset: 'assets/icon/variants/droplet_09.png',
      premium: true,
    ),
    // Les trois dernières viennent des illustrations « premium ».
    // Elles pointent sur les vignettes NORMALISÉES et non sur les
    // JPEG d'origine : ceux-ci sont des images de présentation, avec
    // une marge autour de l'icône et des coins arrondis peints plutôt
    // que découpés (voir `tool/normalize_premium_icons.py`).
    AppIconOption(
      alias: 'V10',
      name: 'Constellation',
      asset: 'assets/icon/variants/droplet_10.png',
      premium: true,
    ),
    AppIconOption(
      alias: 'V11',
      name: 'Prisme',
      asset: 'assets/icon/variants/droplet_11.png',
      premium: true,
    ),
    AppIconOption(
      alias: 'V12',
      name: 'Émeraude',
      asset: 'assets/icon/variants/droplet_12.png',
      premium: true,
    ),
  ];

  /// Vrai si l'appareil sait changer d'icône.
  ///
  /// Réservé à Android : iOS a bien un mécanisme équivalent
  /// (`setAlternateIconName`), mais il exige de déclarer les icônes dans
  /// le projet Xcode, ce qui n'a pas de sens tant que Droplet n'est pas
  /// compilé pour iOS.
  static bool get isSupported => Platform.isAndroid;

  /// L'alias actuellement actif.
  static Future<String> current() async {
    if (!isSupported) return 'Default';
    try {
      final alias = await _channel.invokeMethod<String>('currentIcon');
      return alias ?? 'Default';
    } catch (e) {
      debugPrint("[Icône] lecture de l'icône actuelle: $e");
      return 'Default';
    }
  }

  /// Applique une icône. L'application se ferme aussitôt après.
  static Future<bool> apply(String alias) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('setIcon', {'alias': alias});
      return ok ?? false;
    } catch (e) {
      debugPrint('[Icône] changement impossible: $e');
      return false;
    }
  }
}
