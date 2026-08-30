// ============================================================================
// Ces tests vérifient LE CONTRAT, pas une implémentation particulière.
//
// Ils tournent sur le transport simulé, mais chaque assertion porte sur
// une promesse que les trois transports réels s'engagent désormais à
// tenir. Le jour où un quatrième transport apparaît, il suffit de le
// faire passer par la même série pour savoir s'il est utilisable.
// ============================================================================

import 'dart:typed_data';

import 'package:droplet/core/services/mesh_transport.dart';
import 'package:flutter_test/flutter_test.dart';

import 'faux_transport.dart';

Uint8List paquet(String texte) =>
    Uint8List.fromList(texte.codeUnits);

void main() {
  group('Contrat MeshTransport — cycle de vie', () {
    test('un transport à l\'arrêt refuse d\'envoyer', () async {
      final reseau = RezeauSimule();
      final a = FauxTransport('A', reseau);
      final b = FauxTransport('B', reseau);
      reseau.relier('A', 'B');

      // Pas de `start()` : l'envoi ne doit pas prétendre avoir réussi.
      expect(await a.sendToPeer('B', paquet('salut')), isFalse);
      expect(b.recus, isEmpty);

      a.dispose();
      b.dispose();
    });

    test('l\'état suit le cycle arrêté → recherche → actif', () async {
      final reseau = RezeauSimule();
      final a = FauxTransport('A', reseau);
      final b = FauxTransport('B', reseau);

      expect(a.state, TransportState.stopped);

      await a.start('A', 'A');
      expect(a.state, TransportState.searching);

      reseau.relier('A', 'B');
      expect(a.state, TransportState.active);

      reseau.separer('A', 'B');
      expect(a.state, TransportState.searching);

      await a.stop();
      expect(a.state, TransportState.stopped);

      a.dispose();
      b.dispose();
    });

    test('stop() est appelable même à l\'arrêt', () async {
      final reseau = RezeauSimule();
      final a = FauxTransport('A', reseau);
      await a.stop();
      await a.stop();
      expect(a.state, TransportState.stopped);
      a.dispose();
    });
  });

  group('Contrat MeshTransport — capacités', () {
    test('un paquet trop gros est refusé AVANT d\'être envoyé', () async {
      final reseau = RezeauSimule();
      final a = FauxTransport('A', reseau);
      final b = FauxTransport('B', reseau);
      await a.start('A', 'A');
      await b.start('B', 'B');
      reseau.relier('A', 'B');

      final trop = Uint8List(a.capabilities.maxPayloadBytes + 1);
      expect(await a.sendToPeer('B', trop), isFalse);
      // Rien ne doit être parti sur le réseau : le refus est local.
      expect(reseau.paquetsTransmis, 0);
      expect(a.metrics.echecsEnvoi, 1);

      a.dispose();
      b.dispose();
    });

    test('les capacités décrivent ce que le transport porte vraiment', () {
      const bluetooth = TransportCapabilities(
        maxPayloadBytes: 512,
        maxContentType: 0x1F,
        portePhotosEtFichiers: false,
        porteVoixEnDirect: false,
        coutEnergetique: 0.1,
      );

      // Un message texte court : passe.
      expect(bluetooth.accepte(tailleOctets: 100, type: 0x01), isTrue);
      // Un fichier : refusé par son TYPE, même s'il tenait en taille.
      expect(bluetooth.accepte(tailleOctets: 100, type: 0x20), isFalse);
      // Un texte trop long : refusé par sa TAILLE.
      expect(bluetooth.accepte(tailleOctets: 5000, type: 0x01), isFalse);
    });
  });

  group('Contrat MeshTransport — livraison', () {
    test('un pair hors de portée n\'est pas joignable', () async {
      final reseau = RezeauSimule();
      final a = FauxTransport('A', reseau);
      final b = FauxTransport('B', reseau);
      await a.start('A', 'A');
      await b.start('B', 'B');
      // Aucun `relier` : ils ne se voient pas.

      expect(await a.sendToPeer('B', paquet('perdu')), isFalse);
      expect(b.recus, isEmpty);

      a.dispose();
      b.dispose();
    });

    test('sans perte, tout arrive', () async {
      final reseau = RezeauSimule();
      final a = FauxTransport('A', reseau);
      final b = FauxTransport('B', reseau);
      await a.start('A', 'A');
      await b.start('B', 'B');
      reseau.relier('A', 'B');

      for (var i = 0; i < 100; i++) {
        await a.sendToPeer('B', paquet('m$i'));
      }

      expect(b.recus.length, 100);
      expect(reseau.paquetsPerdus, 0);

      a.dispose();
      b.dispose();
    });

    test('avec 20 % de perte, il en manque — et le compteur le dit',
        () async {
      final reseau = RezeauSimule(tauxDePerte: 0.20, graine: 7);
      final a = FauxTransport('A', reseau);
      final b = FauxTransport('B', reseau);
      await a.start('A', 'A');
      await b.start('B', 'B');
      reseau.relier('A', 'B');

      for (var i = 0; i < 500; i++) {
        await a.sendToPeer('B', paquet('m$i'));
      }

      // La graine est fixe : le résultat est reproductible d'une
      // exécution à l'autre. On vérifie l'ordre de grandeur, pas une
      // valeur exacte, qui dépendrait du générateur.
      expect(b.recus.length, lessThan(500));
      expect(reseau.paquetsPerdus, greaterThan(50));
      expect(b.recus.length + reseau.paquetsPerdus, 500);

      a.dispose();
      b.dispose();
    });

    test('la duplication produit bien des doublons à dédupliquer',
        () async {
      final reseau = RezeauSimule(tauxDeDuplication: 1.0);
      final a = FauxTransport('A', reseau);
      final b = FauxTransport('B', reseau);
      await a.start('A', 'A');
      await b.start('B', 'B');
      reseau.relier('A', 'B');

      await a.sendToPeer('B', paquet('unique'));

      // Chaque paquet arrive deux fois : c'est exactement la situation
      // que la déduplication du dépôt doit absorber.
      expect(b.recus.length, 2);

      a.dispose();
      b.dispose();
    });
  });

  group('Laboratoire — plusieurs nœuds', () {
    test('vingt nœuds reliés deux à deux se voient tous', () async {
      final reseau = RezeauSimule();
      final noeuds = <FauxTransport>[];
      for (var i = 0; i < 20; i++) {
        final n = FauxTransport('N$i', reseau);
        await n.start('N$i', 'N$i');
        noeuds.add(n);
      }
      reseau.relierTous();

      for (final n in noeuds) {
        // Chacun voit les dix-neuf autres.
        expect(n.metrics.pairsConnectes, 19);
        expect(n.state, TransportState.active);
      }

      for (final n in noeuds) {
        n.dispose();
      }
    });

    test('un nœud qui part est signalé aux autres', () async {
      final reseau = RezeauSimule();
      final a = FauxTransport('A', reseau);
      final b = FauxTransport('B', reseau);
      await a.start('A', 'A');
      await b.start('B', 'B');
      reseau.relier('A', 'B');

      final vus = <bool>[];
      a.peerEvents.listen((e) => vus.add(e.isConnected));

      reseau.separer('A', 'B');
      await Future<void>.delayed(Duration.zero);

      expect(vus, contains(false));
      expect(a.metrics.pairsConnectes, 0);

      a.dispose();
      b.dispose();
    });
  });
}
