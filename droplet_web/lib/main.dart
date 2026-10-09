// DROPLET WEB — vos discussions Droplet dans le navigateur.
//
// Étape actuelle du plan (voir l'étude « Droplet Web — étude de
// faisabilité ») : les fondations. La liaison par code QR s'affiche, avec
// les clés propres à ce navigateur ; la suite (certificat signé par le
// téléphone, file dans la boîte aux lettres, discussions) arrive avec les
// serveurs consolidés.
//
// Lancer : flutter run -d chrome
// Construire : flutter build web --release   (sortie dans build/web)
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'design/ouro_colors.dart';
import 'design/ouro_typography.dart';
import 'app/coquille.dart';
import 'design/reglages_apparence.dart';
import 'liaison/ecran_liaison.dart';
import 'textes.dart';

void main() {
  // Le rose de la goutte : la couleur de Droplet tant que le téléphone n'a
  // pas transmis l'accent choisi dans ses réglages.
  ReglagesApparence.accent = ReglagesApparence.accentParCle('rose');
  runApp(const DropletWeb());
}

class DropletWeb extends StatefulWidget {
  const DropletWeb({super.key});

  @override
  State<DropletWeb> createState() => _DropletWebState();
}

class _DropletWebState extends State<DropletWeb> with WidgetsBindingObserver {
  final Textes _textes = Textes.duNavigateur();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Le système passe en sombre (ou en clair) : toute la palette suit.
  @override
  void didChangePlatformBrightness() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final luminosite =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    OuroColors.setBrightness(luminosite);

    return MaterialApp(
      title: 'Droplet Web',
      debugShowCheckedModeBanner: false,
      locale: Locale(_textes.code),
      supportedLocales: const [
        Locale('fr'), Locale('en'), Locale('de'), Locale('es'), Locale('it'),
        Locale('pt'), Locale('ru'), Locale('zh'), Locale('ar'), Locale('hi'),
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      theme: ThemeData(
        brightness: luminosite,
        fontFamily: OuroTypography.fontFamily,
        scaffoldBackgroundColor: OuroColors.systemGroupedBackground,
        colorScheme: ColorScheme.fromSeed(
          seedColor: OuroColors.accent,
          brightness: luminosite,
        ),
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      ),
      // `?apercu` : l'interface avec des discussions d'exemple, pour la voir
      // avant que la liaison fonctionne. Sinon, l'écran de liaison.
      home: Uri.base.queryParameters.containsKey('apercu')
          ? Coquille(textes: _textes, apercu: true)
          : EcranLiaison(textes: _textes),
    );
  }
}
