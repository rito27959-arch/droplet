// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le tout premier écran, affiché une seconde et demie environ pendant que
// l'app se prépare, puis remplacé automatiquement par l'accueil (si une
// identité existe déjà) ou par l'écran de bienvenue.
//
// C'est ici que se joue l'ARRIVÉE DE L'ICÔNE : elle apparaît en
// grandissant légèrement, le nom monte sous elle, puis l'ensemble
// s'efface en s'agrandissant encore un peu — comme si on traversait
// l'icône pour entrer dans l'app. Le détail du mouvement, et les raisons
// de chaque réglage, sont dans `app_icon_intro.dart`.
//
// CE QUI A CHANGÉ : cet écran affichait auparavant un logo dessiné en
// code, animé en permanence (trois masses de liquide qui dérivaient et
// fusionnaient). C'était joli, mais ce logo n'était CELUI DE PERSONNE :
// il ne ressemblait pas à l'icône sur laquelle on venait d'appuyer. On
// passait donc d'une image à une autre sans lien visuel, ce qui est
// exactement ce qu'un écran de démarrage doit éviter.
// ============================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../shared/widgets/app_icon_intro.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  Timer? _leaveTimer;
  Timer? _goTimer;

  /// Vrai pendant les derniers instants : déclenche la sortie.
  bool _leaving = false;

  /// Durée d'affichage avant de commencer à s'effacer. L'animation
  /// d'entrée dure 1,1 s ; on laisse un court temps de pose pour que
  /// l'icône soit vue posée, et non seulement en mouvement.
  static const _hold = Duration(milliseconds: 1350);

  /// Durée du fondu de sortie — doit correspondre à celle réglée dans
  /// `AppIconIntro`, sinon on naviguerait avant la fin de l'effacement.
  static const _exit = Duration(milliseconds: 320);

  @override
  void initState() {
    super.initState();
    // `Timer` plutôt que `Future.delayed` : lui seul peut être annulé si
    // l'écran est quitté avant l'échéance, ce qui évite de laisser un
    // minuteur orphelin actif après la destruction du widget.
    _leaveTimer = Timer(_hold, () {
      if (mounted) setState(() => _leaving = true);
    });
    _goTimer = Timer(_hold + _exit, () {
      if (!mounted) return;
      context.go(StorageService.hasIdentity ? '/chats' : '/onboarding');
    });
  }

  @override
  void dispose() {
    _leaveTimer?.cancel();
    _goTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OuroColors.systemBackground,
      body: Center(
        child: AppIconIntro(
          size: 116,
          leaving: _leaving,
          label: 'Droplet',
          labelStyle: OuroTypography.largeTitle.copyWith(
            color: OuroColors.label,
          ),
          caption: 'Hors ligne. Sans opérateur.',
          captionStyle: OuroTypography.subheadline.copyWith(
            color: OuroColors.secondaryLabel,
          ),
        ),
      ),
    );
  }
}
