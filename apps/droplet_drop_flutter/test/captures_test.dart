// Les captures des écrans (clair et sombre, téléphone et ordinateur), avec
// de vraies polices. Elles servent à relire l'interface sans appareil :
// la CI les publie. Les données affichées sont celles d'un état type.
//
//   flutter test --update-goldens test/captures_test.dart
import 'dart:io';

import 'package:droplet_drop/app/etat_app.dart';
import 'package:droplet_drop/app/modeles.dart';
import 'package:droplet_drop/design/couleurs.dart';
import 'package:droplet_drop/ecrans/accueil.dart';
import 'package:droplet_drop/ecrans/choisir.dart';
import 'package:droplet_drop/ecrans/group_drop.dart';
import 'package:droplet_drop/ecrans/offre.dart';
import 'package:droplet_drop/ecrans/recevoir.dart';
import 'package:droplet_drop/ecrans/reglages.dart';
import 'package:droplet_drop/ecrans/transfert.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _polices() async {
  // Roboto et les icônes Material sont dans le cache de Flutter.
  final racine = Platform.environment['FLUTTER_ROOT'] ?? '';
  final dossier = Directory('$racine/bin/cache/artifacts/material_fonts');
  if (!dossier.existsSync()) return;
  final roboto = FontLoader('Roboto');
  final icones = FontLoader('MaterialIcons');
  for (final f in dossier.listSync().whereType<File>()) {
    final nom = f.path.split('/').last.toLowerCase();
    final octets = f.readAsBytes().then((b) => b.buffer.asByteData());
    if (nom.startsWith('roboto-') && !nom.contains('italic') && !nom.contains('condensed')) roboto.addFont(octets);
    if (nom.startsWith('materialicons-regular')) icones.addFont(octets);
  }
  await roboto.load();
  await icones.load();
}

Pair _pair(String nom, String p, String fp) => Pair(nom: nom, plateforme: p, empreinte: fp, courte: '${fp.substring(0, 4)}-${fp.substring(4, 8)}'.toUpperCase());

String _fp(int i) => (List.filled(8, i.toRadixString(16).padLeft(2, '0')).join() * 4).substring(0, 64);

void _etatType() {
  final e = EtatApp.i;
  e
    ..pret = true
    ..nom = 'MacBook de Léa'
    ..empreinte = _fp(171)
    ..courte = 'ABAB-ABAB'
    ..port = 47321
    ..adresses = ['192.168.1.24']
    ..reception = '/Users/lea/Downloads/Droplet Drop';
  e.appareils
    ..clear()
    ..addAll({
      'a': AppareilVu(id: 'a', nom: 'iPhone de Karim', plateforme: 'ios', empreinte: _fp(12), adresses: const ['192.168.1.31:47321']),
      'b': AppareilVu(id: 'b', nom: 'PC de la salle 3', plateforme: 'windows', empreinte: _fp(45), adresses: const ['192.168.1.40:47321']),
      'c': AppareilVu(id: 'c', nom: 'Pixel 9 d’Amina', plateforme: 'android', empreinte: _fp(78), adresses: const ['192.168.1.52:47321']),
    });
  const fichiers = [Fichier('Projet final.mov', 2400000000), Fichier('Notes.pdf', 1800000)];
  Transfert t(String id, String g, Pair p, EtatTransfert etat, double avance, {int debit = 0, int? restant, String? erreur, int total = 2401800000, List<Fichier> f = fichiers}) => Transfert(
        id: id,
        groupe: g,
        envoi: true,
        pair: p,
        etat: etat,
        octets: (total * avance).round(),
        total: total,
        debit: debit,
        restant: restant,
        erreur: erreur,
        chemins: const [],
        fichiers: f,
      );
  e.transferts
    ..clear()
    ..addAll({
      't1': t('t1', 'g1', _pair('iPhone de Karim', 'ios', _fp(12)), EtatTransfert.transfert, 0.64, debit: 38500000, restant: 22),
      't2': t('t2', 'g1', _pair('PC de la salle 3', 'windows', _fp(45)), EtatTransfert.termine, 1),
      't3': t('t3', 'g1', _pair('Pixel 9 d’Amina', 'android', _fp(78)), EtatTransfert.interrompu, 0.31, erreur: 'connexion_interrompue'),
    });
  // Une distribution de 30 appareils.
  const zip = [Fichier('Android Studio.zip', 4200000000)];
  for (var i = 0; i < 30; i++) {
    final etat = i < 23 ? EtatTransfert.termine : (i < 27 ? EtatTransfert.transfert : (i < 29 ? EtatTransfert.enAttente : EtatTransfert.interrompu));
    final avance = etat == EtatTransfert.termine ? 1.0 : (etat == EtatTransfert.transfert ? 0.4 + i * 0.03 : (etat == EtatTransfert.interrompu ? 0.55 : 0.0));
    e.transferts['s$i'] = t('s$i', 's1', _pair('Poste ${(i + 1).toString().padLeft(2, '0')}', i.isEven ? 'windows' : 'linux', _fp(i + 1)), etat, avance,
        debit: etat == EtatTransfert.transfert ? 21000000 : 0, restant: etat == EtatTransfert.transfert ? 95 : null, total: 4200000000, f: zip);
  }
  e.mesSessions['s1'] = Session(id: 's1', invitation: 'dropletdrop://rejoindre#${'x' * 300}', expire: DateTime(2026, 10, 13, 18, 30), total: 4200000000, fichiers: zip);
  e.sessions['s1'] = const EtatSession(id: 's1', etat: 'en_cours', participants: 30, termines: 23);
}

Widget _app(Widget ecran, {required bool sombre}) => PorteePalette(
      palette: Palette.de(sombre: sombre, accent: Accent.bleu),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('fr'),
        supportedLocales: const [Locale('fr')],
        localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
        theme: ThemeData(
          brightness: sombre ? Brightness.dark : Brightness.light,
          fontFamily: 'Roboto',
          scaffoldBackgroundColor: Palette.de(sombre: sombre, accent: Accent.bleu).fond,
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF168BFF), brightness: sombre ? Brightness.dark : Brightness.light),
        ),
        home: ecran,
      ),
    );

const _tailles = {'mobile': Size(390, 844), 'bureau': Size(1280, 800)};

Future<void> _capture(WidgetTester tester, String nom, Widget ecran, {Future<void> Function(WidgetTester)? apres}) async {
  for (final sombre in [false, true]) {
    for (final t in _tailles.entries) {
      tester.view.physicalSize = t.value * 2;
      tester.view.devicePixelRatio = 2;
      EtatApp.i.langue = 'fr';
      await tester.pumpWidget(_app(ecran, sombre: sombre));
      await tester.pump(const Duration(milliseconds: 900));
      if (apres != null) await apres(tester);
      await expectLater(find.byType(MaterialApp), matchesGoldenFile('captures/$nom-${t.key}-${sombre ? 'sombre' : 'clair'}.png'));
    }
  }
  tester.view.resetPhysicalSize();
}

void main() {
  setUpAll(() async {
    await _polices();
    _etatType();
  });

  testWidgets('accueil', (tester) => _capture(tester, '1-accueil', const Accueil()));

  testWidgets('destinataires', (tester) => _capture(
        tester,
        '2-destinataires',
        const EcranDestinataires(choisis: [
          Choisi(chemin: '/a', nom: 'Projet final.mov', taille: 2400000000),
          Choisi(chemin: '/b', nom: 'Notes.pdf', taille: 1800000),
        ]),
      ));

  testWidgets('transfert', (tester) => _capture(tester, '3-transfert', const EcranTransfert(groupe: 'g1')));

  testWidgets('offre', (tester) => _capture(
        tester,
        '4-offre',
        Builder(builder: (c) => const Accueil()),
        apres: (tester) async {
          final c = tester.element(find.byType(Accueil));
          montrerOffre(
            c,
            Offre(id: 'o', de: _pair('iPhone de Karim', 'ios', _fp(12)), fichiers: const [Fichier('Vacances/IMG_2031.HEIC', 3400000), Fichier('Vacances/IMG_2032.HEIC', 3100000), Fichier('Vacances/vidéo.mov', 412000000)], total: 418500000),
          );
          await tester.pump(const Duration(milliseconds: 600));
        },
      ));

  testWidgets('distribution', (tester) => _capture(tester, '5-distribution', TableauSession(session: EtatApp.i.mesSessions['s1']!)));

  testWidgets('recevoir', (tester) => _capture(tester, '6-recevoir', const Recevoir()));

  testWidgets('reglages', (tester) async {
    EtatApp.i.pret = false; // pas de moteur dans les tests : réglages sans appel natif
    await _capture(tester, '7-reglages', const EcranReglages());
    EtatApp.i.pret = true;
  });
}
