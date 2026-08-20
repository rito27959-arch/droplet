// ============================================================================
// CE QUE CE FICHIER VÉRIFIE
// ----------------------------------------------------------------------------
// QUE LA TABLE DE ROUTAGE APPREND VRAIMENT LES CHEMINS À PLUSIEURS SAUTS.
//
// ── Le défaut que ces tests empêchent de revenir ──────────────────────
//
// La table n'était alimentée qu'avec des voisins DIRECTS :
//
//     updateRoutingTable(pair, pair, 1, métrique)
//
// Personne n'apprenait jamais qu'un appareil hors de portée était
// joignable À TRAVERS un autre. `sendViaRoute` ne trouvait donc rien pour
// un destinataire lointain, et l'appelant retombait sur la diffusion : le
// message partait vers TOUS les voisins jusqu'à épuisement du compteur de
// sauts.
//
// Ça fonctionnait — mais tout le calcul de métrique et le Bellman-Ford de
// `getRoute` restaient inertes, faute d'entrée à plus d'un saut à
// comparer.
// ============================================================================

import 'package:droplet/core/protocol/droplet_mesh_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DropletMeshProtocol p;

  setUp(() => p = DropletMeshProtocol(myId: 'moi'));

  test('une route à deux sauts est apprise et retrouvée', () {
    // B est mon voisin direct.
    p.updateRoutingTable('B', 'B', 1, 10);
    // B annonce qu'il joint C en un saut → C est à deux sauts, via B.
    p.updateRoutingTable('C', 'B', 2, 20);

    final route = p.getRoute('C');
    expect(route, isNotNull, reason: 'C doit être joignable via B');
    expect(route!.nextHop, 'B');
    expect(route.hopCount, 2);
  });

  test('le chemin le moins coûteux gagne', () {
    // Deux voisins annoncent tous deux savoir joindre D.
    p.updateRoutingTable('D', 'B', 2, 40); // lien médiocre
    p.updateRoutingTable('D', 'E', 2, 12); // bon lien

    expect(p.getRoute('D')!.nextHop, 'E',
        reason: 'à distance égale, c\'est la métrique qui tranche');
  });

  test('une route pire ne remplace pas une bonne', () {
    p.updateRoutingTable('F', 'E', 2, 12);
    p.updateRoutingTable('F', 'B', 2, 90);

    expect(p.getRoute('F')!.nextHop, 'E');
  });

  test('un voisin direct reste préféré à un détour', () {
    // ⚠️ Le cas qui compte le plus : une annonce ne doit jamais faire
    // passer par un relais quelqu'un qu'on a sous la main.
    p.updateRoutingTable('G', 'G', 1, 30);
    p.updateRoutingTable('G', 'B', 2, 5); // métrique très basse, mais 2 sauts

    final route = p.getRoute('G')!;
    expect(route.nextHop, 'G');
    expect(route.hopCount, 1);
  });

  test('les routes se réannoncent : la copie ne casse pas l\'itération', () {
    p.updateRoutingTable('B', 'B', 1, 10);
    p.updateRoutingTable('C', 'B', 2, 20);

    final copie = p.snapshotRoutes();
    // Modifier la table pendant qu'on tient la copie ne doit rien casser.
    p.updateRoutingTable('D', 'B', 2, 25);

    expect(copie.length, 2);
    expect(p.snapshotRoutes().length, 3);
  });
}
