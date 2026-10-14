// DROPLET DROP — partagez librement.
//
// L'interface Flutter. Le moteur (transferts, chiffrement, découverte,
// historique) est en Rust : `rust/` et `../../crates/`.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app/etat_app.dart';
import 'app/natif.dart';
import 'app/theme.dart';
import 'app/textes.dart';
import 'design/couleurs.dart';
import 'ecrans/accueil.dart';
import 'ecrans/group_drop.dart';
import 'ecrans/offre.dart';
import 'src/rust/frb_generated.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RustLib.init();
  unawaited(EtatApp.i.demarrer());
  runApp(const DropletDrop());
}

final cleNavigation = GlobalKey<NavigatorState>();

class DropletDrop extends StatefulWidget {
  const DropletDrop({super.key});

  @override
  State<DropletDrop> createState() => _DropletDropState();
}

class _DropletDropState extends State<DropletDrop> with WidgetsBindingObserver {
  StreamSubscription<dynamic>? _offres;
  StreamSubscription<dynamic>? _finis;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    EtatApp.i.addListener(_rafraichir);
    // Une offre arrive, où qu'on soit dans l'app : la feuille s'ouvre.
    _offres = EtatApp.i.nouvellesOffres.stream.listen((o) {
      final c = cleNavigation.currentContext;
      if (c != null) montrerOffre(c, o);
    });
    // Un lien d'invitation Group Drop ouvert depuis une autre app : on
    // rejoint, sans passer par le site (donc sans Internet).
    Natif.ecouterLiens(_ouvrirLien);
    Natif.lienInitial().then((l) {
      if (l != null) _ouvrirLien(l);
    });
    // La fin d'un transfert se sent, discrètement.
    _finis = EtatApp.i.finis.stream.listen((t) {
      if (t.etat.name == 'termine') HapticFeedback.mediumImpact();
    });
  }

  void _rafraichir() => setState(() {});

  Future<void> _ouvrirLien(String lien) async {
    // Le moteur démarre peut-être encore (app lancée par le lien).
    for (var i = 0; i < 50 && !EtatApp.i.pret; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    await WidgetsBinding.instance.endOfFrame;
    final c = cleNavigation.currentContext;
    if (c != null && c.mounted && EtatApp.i.pret) await rejoindreAvecInvitation(c, lien);
  }

  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  void dispose() {
    _offres?.cancel();
    _finis?.cancel();
    EtatApp.i.removeListener(_rafraichir);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final e = EtatApp.i;
    final systemeSombre = WidgetsBinding.instance.platformDispatcher.platformBrightness == Brightness.dark;
    final sombre = switch (e.theme) { Theme3.clair => false, Theme3.sombre => true, Theme3.systeme => systemeSombre };
    final palette = Palette.de(sombre: sombre, accent: e.accent);
    return PorteePalette(
      palette: palette,
      child: MaterialApp(
        title: 'Droplet Drop',
        navigatorKey: cleNavigation,
        debugShowCheckedModeBanner: false,
        locale: localeCourante(),
        supportedLocales: [for (final l in langues.keys) Locale(l)],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        theme: themeDroplet(palette),
        builder: (context, enfant) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: sombre ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
          child: enfant!,
        ),
        home: const Accueil(),
      ),
    );
  }
}
