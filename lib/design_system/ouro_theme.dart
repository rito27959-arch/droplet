// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le « livre de règles » d'apparence appliqué automatiquement à TOUTE
// l'app : chaque bouton, chaque champ de texte, chaque barre de titre y
// puise son style sans qu'on ait à le redire écran par écran.
//
// Deux décisions structurantes de la refonte sont posées ici :
//
//   1. LES TRANSITIONS D'ÉCRAN sont celles d'iOS sur les DEUX plateformes.
//      L'écran entrant glisse depuis la droite pendant que le précédent
//      recule légèrement — et surtout, on peut revenir en arrière en
//      faisant glisser depuis le bord gauche. C'est le geste le plus
//      utilisé d'iOS, et son absence est immédiatement ressentie comme
//      « cette app n'est pas finie ».
//
//   2. LES EFFETS D'ONDE MATERIAL SONT SUPPRIMÉS. Sur Android, toucher un
//      bouton propage un cercle d'encre depuis le doigt. iOS ne fait
//      jamais ça : l'élément touché s'assombrit ou change d'opacité,
//      instantanément. Garder l'onde Material dans une app qui vise le
//      rendu iOS est la fausse note la plus repérable de toutes.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'ouro_colors.dart';
import 'ouro_typography.dart';
import 'design_tokens.dart';

class OuroTheme {
  OuroTheme._();

  /// Le thème sombre — celui par défaut de Droplet.
  static ThemeData get dark => _build(Brightness.dark);

  /// Le thème clair, proposé en option dans les réglages.
  static ThemeData get light => _build(Brightness.light);

  /// Le thème correspondant au mode donné.
  ///
  /// L'app en fournit UN SEUL à `MaterialApp`, celui du mode retenu, au
  /// lieu de lui passer `theme` + `darkTheme` + `themeMode`. La raison
  /// tient à la façon dont les couleurs sont lues ici : `OuroColors`
  /// expose des accesseurs globaux qui répondent selon un mode courant,
  /// et non des constantes par thème. Construire les deux thèmes en même
  /// temps produirait donc deux thèmes IDENTIQUES — ceux du mode courant
  /// — dont un porterait à tort l'étiquette de l'autre.
  static ThemeData of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;

  /// Construit le thème pour un mode donné.
  ///
  /// Un SEUL constructeur pour les deux modes, et non deux thèmes écrits
  /// séparément : toutes les couleurs viennent de `OuroColors`, qui sait
  /// déjà se placer dans le bon mode. Dupliquer le thème garantirait
  /// qu'un réglage finisse par diverger entre clair et sombre au premier
  /// oubli.
  /// Rend la barre d'état et la barre de navigation système
  /// transparentes, avec des icônes lisibles dans le mode donné.
  ///
  /// ⚠️ CET APPEL NE DOIT PAS VIVRE DANS [_build]. Flutter évalue
  /// `theme:` ET `darkTheme:` à chaque construction de `MaterialApp`,
  /// quel que soit le mode réellement affiché : le thème construit en
  /// dernier écraserait donc toujours le réglage de l'autre, et le mode
  /// clair hériterait d'icônes système blanches — invisibles sur fond
  /// blanc. Il est appelé une seule fois, depuis la racine de l'app, avec
  /// le mode effectivement retenu.
  static void applySystemOverlay(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      scaffoldBackgroundColor: OuroColors.systemBackground,

      colorScheme: ColorScheme(
        brightness: brightness,
        primary: OuroColors.accent,
        onPrimary: Colors.white,
        secondary: OuroColors.accent,
        onSecondary: Colors.white,
        surface: OuroColors.secondarySystemBackground,
        onSurface: OuroColors.label,
        surfaceContainerHighest: OuroColors.tertiarySystemBackground,
        error: OuroColors.systemRed,
        onError: Colors.white,
        outline: OuroColors.separator,
        outlineVariant: OuroColors.opaqueSeparator,
      ),

      textTheme: TextTheme(
        displayLarge: OuroTypography.largeTitle,
        displayMedium: OuroTypography.title1,
        displaySmall: OuroTypography.title1,
        headlineLarge: OuroTypography.title2,
        headlineMedium: OuroTypography.title3,
        headlineSmall: OuroTypography.headline,
        titleLarge: OuroTypography.headline,
        titleMedium: OuroTypography.bodyEmphasized,
        titleSmall: OuroTypography.subheadline,
        bodyLarge: OuroTypography.body,
        bodyMedium: OuroTypography.callout,
        bodySmall: OuroTypography.subheadline,
        labelLarge: OuroTypography.bodyEmphasized,
        labelMedium: OuroTypography.footnote,
        labelSmall: OuroTypography.caption1,
      ).apply(
        bodyColor: OuroColors.label,
        displayColor: OuroColors.label,
      ),

      // ── Barre de navigation ────────────────────────────────────────
      // Transparente et sans ombre : sur iOS, la barre laisse voir le
      // contenu qui défile derrière, floutée par le matériau posé
      // séparément (voir `OuroBlurSurface`).
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true, // iOS centre TOUJOURS le titre de barre.
        titleTextStyle: OuroTypography.navTitle.copyWith(
          color: OuroColors.label,
        ),
        iconTheme: IconThemeData(
          color: OuroColors.accent,
          size: DesignTokens.iconLg,
        ),
        actionsIconTheme: IconThemeData(
          color: OuroColors.accent,
          size: DesignTokens.iconLg,
        ),
        // Icônes de la barre système claires sur fond sombre, sombres
        // sur fond clair — sans cette inversion, l'heure et la batterie
        // deviennent blanches sur blanc en mode clair.
        systemOverlayStyle:
            isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),

      // ── Effets tactiles ────────────────────────────────────────────
      // La suppression de l'onde Material, mentionnée en tête de fichier.
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: OuroColors.quaternarySystemFill,
      hoverColor: Colors.transparent,

      cardTheme: CardThemeData(
        color: OuroColors.secondarySystemGroupedBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusGroupedList),
        ),
      ),

      // ── Champs de saisie ───────────────────────────────────────────
      // Style iOS : fond gris uni, AUCUNE bordure. Le contour dessiné
      // autour des champs est une convention Material ; iOS s'appuie
      // uniquement sur le contraste du fond.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: OuroColors.tertiarySystemBackground,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          borderSide: BorderSide.none,
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          borderSide: BorderSide(color: OuroColors.systemRed, width: 1),
        ),
        hintStyle: OuroTypography.body.copyWith(
          color: OuroColors.tertiaryLabel,
        ),
        labelStyle: OuroTypography.body.copyWith(
          color: OuroColors.secondaryLabel,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space3,
          vertical: DesignTokens.space3,
        ),
      ),

      // ── Boutons pleins ─────────────────────────────────────────────
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return OuroColors.accent.withValues(alpha: 0.35);
            }
            if (states.contains(WidgetState.pressed)) {
              return OuroColors.accentPressed;
            }
            return OuroColors.accent;
          }),
          foregroundColor: const WidgetStatePropertyAll(Colors.white),
          textStyle: WidgetStatePropertyAll(OuroTypography.bodyEmphasized),
          minimumSize: const WidgetStatePropertyAll(
            Size.fromHeight(DesignTokens.minTouchTarget + 6),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            ),
          ),
          elevation: const WidgetStatePropertyAll(0),
          splashFactory: NoSplash.splashFactory,
        ),
      ),

      // ── Boutons texte ──────────────────────────────────────────────
      // Sur iOS, un bouton secondaire est du TEXTE bleu, sans fond ni
      // contour. C'est aussi le style des actions de barre de navigation.
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return OuroColors.tertiaryLabel;
            }
            return OuroColors.accent;
          }),
          textStyle: WidgetStatePropertyAll(OuroTypography.body),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: DesignTokens.space3),
          ),
        ),
      ),

      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(OuroColors.accent),
          textStyle: WidgetStatePropertyAll(OuroTypography.body),
          side: WidgetStatePropertyAll(
            BorderSide(color: OuroColors.separator, width: 1),
          ),
          minimumSize: const WidgetStatePropertyAll(
            Size.fromHeight(DesignTokens.minTouchTarget),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            ),
          ),
          splashFactory: NoSplash.splashFactory,
        ),
      ),

      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(OuroColors.accent),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          splashFactory: NoSplash.splashFactory,
        ),
      ),

      // ── Interrupteurs ──────────────────────────────────────────────
      // Vert système iOS quand actif — pas le bleu d'accent : c'est le
      // seul endroit où iOS s'autorise une autre couleur, et l'écart est
      // devenu un repère universel.
      switchTheme: SwitchThemeData(
        thumbColor: const WidgetStatePropertyAll(Colors.white),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return OuroColors.systemGreen;
          }
          return OuroColors.systemGray5;
        }),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
        trackOutlineWidth: const WidgetStatePropertyAll(0),
      ),

      chipTheme: ChipThemeData(
        backgroundColor: OuroColors.tertiarySystemBackground,
        selectedColor: OuroColors.accent,
        labelStyle: OuroTypography.subheadline.copyWith(
          color: OuroColors.label,
        ),
        side: BorderSide.none,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space3,
          vertical: DesignTokens.space1,
        ),
      ),

      dividerTheme: DividerThemeData(
        color: OuroColors.separator,
        thickness: 0.5,
        space: 0.5,
      ),

      // ── Boîtes de dialogue ─────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: OuroColors.tertiarySystemBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        ),
        titleTextStyle: OuroTypography.headline.copyWith(
          color: OuroColors.label,
        ),
        contentTextStyle: OuroTypography.footnote.copyWith(
          color: OuroColors.label,
        ),
      ),

      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),

      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: Colors.transparent,
        elevation: 0,
        selectedItemColor: OuroColors.accent,
        unselectedItemColor: OuroColors.systemGray,
      ),

      // ── Transitions d'écran ────────────────────────────────────────
      // Le glissement iOS sur les deux plateformes, avec le geste de
      // retour depuis le bord gauche (voir en-tête de fichier).
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.android: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        },
      ),

      // Indicateur de chargement circulaire fin, façon iOS.
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: OuroColors.systemGray,
        linearTrackColor: OuroColors.systemGray5,
        circularTrackColor: Colors.transparent,
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: OuroColors.tertiarySystemBackground,
        contentTextStyle: OuroTypography.subheadline.copyWith(
          color: OuroColors.label,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
      ),

      listTileTheme: ListTileThemeData(
        iconColor: OuroColors.systemGray,
        textColor: OuroColors.label,
        tileColor: Colors.transparent,
      ),

      // Curseur de saisie et sélection de texte aux couleurs iOS.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: OuroColors.accent,
        selectionColor: OuroColors.accent.withValues(alpha: 0.3),
        selectionHandleColor: OuroColors.accent,
      ),
    );
  }
}
