// LE THÈME — partagé par l'application et par les captures de test, pour
// que ce qu'on relit soit exactement ce qu'on livre.
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

import '../design/couleurs.dart';

/// `police` : seulement pour les captures (Roboto chargée à la main) ; dans
/// l'application, la police du système.
ThemeData themeDroplet(Palette palette, {String? police}) {
  return ThemeData(
    fontFamily: police,
    brightness: palette.sombre ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: palette.fond,
    colorScheme: ColorScheme.fromSeed(seedColor: palette.accent, brightness: palette.sombre ? Brightness.dark : Brightness.light),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    pageTransitionsTheme: PageTransitionsTheme(builders: {
      TargetPlatform.android: CupertinoPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
    }),
    textSelectionTheme: TextSelectionThemeData(cursorColor: palette.accent, selectionColor: palette.accent.withValues(alpha: 0.3), selectionHandleColor: palette.accent),
    // Les éléments du système, habillés Droplet Liquid : rien ne doit
    // trahir le « Material par défaut ».
    appBarTheme: AppBarTheme(
      backgroundColor: palette.fond,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.macOS,
      iconTheme: IconThemeData(color: palette.accentTexte),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: palette.sombre ? const Color(0xFF2A3445) : const Color(0xFF1C2333),
      contentTextStyle: TextStyle(fontFamily: police, color: Colors.white, fontSize: 15, fontWeight: FontWeight.w500),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: palette.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      titleTextStyle: TextStyle(fontFamily: police, color: palette.texte, fontSize: 20, fontWeight: FontWeight.w600, letterSpacing: -0.3),
      contentTextStyle: TextStyle(fontFamily: police, color: palette.texte2, fontSize: 15, height: 1.4),
    ),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: Colors.transparent, elevation: 0, modalElevation: 0),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: palette.accentTexte, textStyle: TextStyle(fontFamily: police, fontSize: 16, fontWeight: FontWeight.w600)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: palette.surfaceHaute,
      hintStyle: TextStyle(color: palette.texte3),
      helperStyle: TextStyle(color: palette.texte2),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: palette.accent, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? palette.succes : palette.surfaceHaute),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    dividerTheme: DividerThemeData(color: palette.trait, thickness: 1, space: 1),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: palette.sombre ? const Color(0xFF2A3445) : const Color(0xFF1C2333), borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(fontFamily: police, color: Colors.white, fontSize: 13),
      waitDuration: const Duration(milliseconds: 500),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(palette.texte3.withValues(alpha: 0.5)),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
  );
}
