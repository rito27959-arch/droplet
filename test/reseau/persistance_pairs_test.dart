// ============================================================================
// LA PERSISTANCE DES PAIRS : le bug de la course perdue.
//
// `upsertPeer` lit la liste complète des pairs, la modifie, puis la
// réécrit en entier. Il est appelé sans être attendu, depuis trois
// endroits, à chaque fois qu'un appareil est aperçu.
//
// Deux appels qui se chevauchent lisaient donc la MÊME liste de départ,
// et le second écrasait le premier. Un pair sur deux disparaissait — non
// pas à cause du réseau, mais parce que sa fiche n'était jamais écrite.
// ============================================================================

import 'package:droplet/core/models/mesh_message.dart';
import 'package:droplet/core/services/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

PeerRecord pair(String id) => PeerRecord(
      peerId: id,
      pseudo: 'pseudo-$id',
      lastSeen: DateTime.now(),
    );

void main() {
  setUp(() async {
    await StorageService.savePeers([]);
  });

  test('deux écritures simultanées ne se perdent pas', () async {
    // Le cas d'origine : deux appareils découverts dans la même
    // milliseconde, chacun déclenchant son `upsertPeer`.
    await Future.wait([
      StorageService.upsertPeer(pair('alice')),
      StorageService.upsertPeer(pair('bob')),
    ]);

    final ids = StorageService.getKnownPeers().map((p) => p.peerId).toSet();
    expect(ids, {'alice', 'bob'});
  });

  test('vingt écritures simultanées : aucune perdue', () async {
    // Le cas d'une salle bondée, où le mesh découvre une grappe entière
    // d'un coup.
    await Future.wait([
      for (var i = 0; i < 20; i++) StorageService.upsertPeer(pair('n$i')),
    ]);

    expect(StorageService.getKnownPeers().length, 20);
  });

  test('réécrire le même pair le met à jour sans le dupliquer', () async {
    await StorageService.upsertPeer(pair('alice'));
    await StorageService.upsertPeer(PeerRecord(
      peerId: 'alice',
      pseudo: 'Alice renommée',
      lastSeen: DateTime.now(),
    ));

    final pairs = StorageService.getKnownPeers();
    expect(pairs.length, 1);
    expect(pairs.single.pseudo, 'Alice renommée');
  });

  test('les écritures gardent leur ordre', () async {
    // La dernière écriture doit gagner, y compris sous concurrence :
    // c'est elle qui porte le pseudo le plus récent.
    final futures = <Future<void>>[];
    for (var i = 0; i < 10; i++) {
      futures.add(StorageService.upsertPeer(PeerRecord(
        peerId: 'alice',
        pseudo: 'version-$i',
        lastSeen: DateTime.now(),
      )));
    }
    await Future.wait(futures);

    final pairs = StorageService.getKnownPeers();
    expect(pairs.length, 1);
    expect(pairs.single.pseudo, 'version-9');
  });
}
