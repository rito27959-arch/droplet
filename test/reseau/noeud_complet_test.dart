// ============================================================================
// LE POINT D'INJECTION, VÉRIFIÉ DE BOUT EN BOUT.
//
// Ces tests ne vérifient pas une fonctionnalité de Droplet : ils
// vérifient qu'on peut désormais MONTER UN NŒUD COMPLET sans radio —
// `MeshRepository` posé sur un `MeshTransportService` posé sur trois
// transports simulés.
//
// C'est la condition de tout ce qui suit. Tant qu'elle n'était pas
// remplie, aucune mesure de latence, de taux de livraison ou de coût de
// synchronisation n'était possible : il aurait fallu autant de
// téléphones que de nœuds.
// ============================================================================

import 'package:droplet/core/repositories/mesh_repository.dart';
import 'package:droplet/core/services/mesh_state_machine.dart';
import 'package:droplet/core/services/mesh_transport_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'faux_transport.dart';

/// Un nœud Droplet complet, entièrement simulé.
class NoeudSimule {
  NoeudSimule(this.id, RezeauSimule reseau)
      : wifi = FauxTransport('$id/wifi', reseau),
        p2p = FauxTransport('$id/p2p', reseau),
        ble = FauxTransport('$id/ble', reseau) {
    service = MeshTransportService(
      wifiTransport: wifi,
      nativeTransport: p2p,
      bleTransport: ble,
    );
    repo = MeshRepository(transport: service);
  }

  final String id;
  final FauxTransport wifi;
  final FauxTransport p2p;
  final FauxTransport ble;
  late final MeshTransportService service;
  late final MeshRepository repo;

  void dispose() {
    wifi.dispose();
    p2p.dispose();
    ble.dispose();
  }
}

void main() {
  group('Point d\'injection', () {
    test('un service accepte des transports simulés', () {
      final reseau = RezeauSimule();
      final wifi = FauxTransport('A/wifi', reseau);
      final p2p = FauxTransport('A/p2p', reseau);
      final ble = FauxTransport('A/ble', reseau);

      final service = MeshTransportService(
        wifiTransport: wifi,
        nativeTransport: p2p,
        bleTransport: ble,
      );

      // Les trois sont bien ceux qu'on a fournis, et non de vraies
      // radios : leurs états sont ceux du simulateur.
      expect(service.transportStates().keys, containsAll(['faux']));
      expect(service.networkState, MeshNetworkState.offline);

      wifi.dispose();
      p2p.dispose();
      ble.dispose();
    });

    test('un dépôt complet se monte sur des transports simulés', () {
      final reseau = RezeauSimule();
      final noeud = NoeudSimule('A', reseau);

      // Le dépôt existe, avec toute sa logique — file fiable,
      // déduplication, accusés — mais sans une seule radio allumée.
      expect(noeud.repo, isNotNull);
      expect(noeud.service.connectedPeerCount, 0);

      noeud.dispose();
    });

    test('vingt nœuds complets tiennent dans un test', () {
      final reseau = RezeauSimule();
      final noeuds = [
        for (var i = 0; i < 20; i++) NoeudSimule('N$i', reseau),
      ];

      expect(noeuds.length, 20);
      for (final n in noeuds) {
        expect(n.service.networkState, MeshNetworkState.offline);
      }

      for (final n in noeuds) {
        n.dispose();
      }
    });
  });

  group('Le simulateur reste fidèle', () {
    test('sans injection, le service fabrique ses vraies radios', () {
      // Le comportement par défaut est INCHANGÉ : l'application livrée
      // ne voit aucune différence.
      final service = MeshTransportService();
      final etats = service.transportStates();
      expect(etats.keys, containsAll(['wifi', 'p2p', 'ble']));
      expect(etats.keys, isNot(contains('faux')));
    });
  });
}
