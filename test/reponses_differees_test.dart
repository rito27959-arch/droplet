// ============================================================================
// CE QUE CES TESTS PROTÈGENT
// ----------------------------------------------------------------------------
// QU'UN MESSAGE TAPÉ DANS UNE NOTIFICATION NE DISPARAISSE JAMAIS.
//
// Quand on répond depuis une notification alors que l'application est
// fermée, Android réveille un isolate minuscule : ni maillage, ni
// providers. La réponse ne peut qu'être écrite sur le disque, puis
// rejouée au démarrage suivant.
//
// Tout repose donc sur ce fichier d'attente. S'il se vide au mauvais
// moment, le message est perdu — et personne ne le saura, pas même son
// auteur, qui croira l'avoir envoyé. Pour une application dont
// l'argument central est de ne pas perdre de messages, c'est le pire
// défaut possible.
// ============================================================================

import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:droplet/core/services/reponses_differees.dart';

late Directory _faux;

/// Le fichier d'attente, dans le dossier simulé.
File get fichier => File('${_faux.path}/reponses_differees.json');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    _faux = await Directory.systemTemp.createTemp('droplet_reponses');
    // `path_provider` n'existe pas dans un test : on répond à sa place.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => _faux.path,
    );
    ReponsesDifferees.onRejouer = null;
  });

  tearDown(() async {
    ReponsesDifferees.onRejouer = null;
    if (_faux.existsSync()) _faux.deleteSync(recursive: true);
  });

  test('une réponse écrite est retrouvée', () async {
    await ReponsesDifferees.ajouter('/chat/abc', 'Bonjour');
    expect(fichier.existsSync(), isTrue);

    final liste = jsonDecode(fichier.readAsStringSync()) as List;
    expect(liste.length, 1);
    expect(liste.first['r'], '/chat/abc');
    expect(liste.first['t'], 'Bonjour');
  });

  test('SANS RAPPEL BRANCHÉ, RIEN N\'EST PERDU', () async {
    // ⚠️ Le cas du démarrage : `rejouer` peut être appelé avant que
    // l'application ne sache quoi faire des réponses. Elle doit alors
    // les LAISSER, pas les consommer dans le vide.
    await ReponsesDifferees.ajouter('/chat/abc', 'Bonjour');
    await ReponsesDifferees.rejouer();

    expect(fichier.existsSync(), isTrue,
        reason: 'sans destinataire, la réponse doit rester sur le disque');
  });

  test('rejouée puis effacée', () async {
    await ReponsesDifferees.ajouter('/chat/abc', 'Un');
    await ReponsesDifferees.ajouter('/group/xyz', 'Deux');

    final vues = <String>[];
    ReponsesDifferees.onRejouer = (r) async => vues.add('${r.route}|${r.texte}');
    await ReponsesDifferees.rejouer();

    expect(vues, ['/chat/abc|Un', '/group/xyz|Deux'],
        reason: 'l\'ordre d\'écriture doit être conservé : deux réponses '
            'à la même conversation arrivent comme elles ont été tapées');
    expect(fichier.existsSync(), isFalse,
        reason: 'tout est passé, le fichier disparaît');
  });

  test('UN ÉCHEC NE FAIT PERDRE QUE CE QUI EST PASSÉ', () async {
    // ⚠️ LE TEST LE PLUS IMPORTANT.
    //
    // Si l'envoi échoue au milieu, vider le fichier ferait disparaître
    // les messages restants sans que personne ne le sache.
    await ReponsesDifferees.ajouter('/chat/a', 'Un');
    await ReponsesDifferees.ajouter('/chat/b', 'Deux');
    await ReponsesDifferees.ajouter('/chat/c', 'Trois');

    var n = 0;
    ReponsesDifferees.onRejouer = (r) async {
      n++;
      if (n == 2) throw StateError('réseau coupé');
    };
    await ReponsesDifferees.rejouer();

    expect(fichier.existsSync(), isTrue);
    final reste = jsonDecode(fichier.readAsStringSync()) as List;
    expect(reste.length, 2,
        reason: 'la première est passée ; les deux autres attendent');
    expect(reste.first['t'], 'Deux',
        reason: 'celle qui a échoué doit être retentée en premier');
  });

  test('un fichier illisible ne bloque pas le démarrage', () async {
    fichier.writeAsStringSync('ceci n\'est pas du JSON {{{');
    ReponsesDifferees.onRejouer = (_) async {};
    // Ne doit lever aucune exception : une application qui refuse de
    // démarrer à cause d'un fichier annexe corrompu est inutilisable.
    await ReponsesDifferees.rejouer();
  });

  test('la file est bornée', () async {
    for (var i = 0; i < 60; i++) {
      await ReponsesDifferees.ajouter('/chat/a', 'msg $i');
    }
    final liste = jsonDecode(fichier.readAsStringSync()) as List;
    expect(liste.length, lessThanOrEqualTo(50),
        reason: 'sans borne, une notification restée affichée des '
            'semaines enverrait des centaines de messages d\'un coup au '
            'redémarrage');
  });
}
