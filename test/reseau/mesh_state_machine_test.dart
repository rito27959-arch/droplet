// ============================================================================
// La machine d'état se teste ENTIÈREMENT sans radio, sans téléphone et
// sans réseau — c'est tout l'intérêt d'avoir fait de l'état une fonction
// de ses entrées plutôt qu'un empilement de drapeaux posés de partout.
//
// On peut donc vérifier ici des situations qu'on ne saurait pas
// provoquer sur un vrai appareil : couper les trois radios à la
// milliseconde près, ou faire revenir le Wi-Fi pile au bon moment.
// ============================================================================

import 'package:droplet/core/services/mesh_state_machine.dart';
import 'package:droplet/core/services/mesh_transport.dart';
import 'package:flutter_test/flutter_test.dart';

/// Les trois transports dans un état donné, pour alléger les tests.
Map<String, TransportState> radios({
  TransportState wifi = TransportState.stopped,
  TransportState p2p = TransportState.stopped,
  TransportState ble = TransportState.stopped,
}) =>
    {'wifi': wifi, 'p2p': p2p, 'ble': ble};

void main() {
  group('Calcul de l\'état', () {
    test('sans aucun transport, on est hors ligne', () {
      final m = MeshStateMachine();
      m.update(transports: const {}, connectedPeers: 0);
      expect(m.state, MeshNetworkState.offline);
      m.dispose();
    });

    test('tous les transports arrêtés : hors ligne', () {
      final m = MeshStateMachine();
      m.update(transports: radios(), connectedPeers: 0);
      expect(m.state, MeshNetworkState.offline);
      m.dispose();
    });

    test('démarrés mais aucune radio disponible : réseau perdu', () {
      // C'EST LE CAS QUI PRODUISAIT LE FLOT D'EXCEPTIONS : le mesh
      // tourne, la balise part, mais il n'y a pas d'interface.
      final m = MeshStateMachine();
      m.update(
        transports: radios(
          wifi: TransportState.unavailable,
          p2p: TransportState.unavailable,
          ble: TransportState.unavailable,
        ),
        connectedPeers: 0,
      );
      expect(m.state, MeshNetworkState.networkLost);
      expect(m.canSend, isFalse, reason: 'rien ne doit être tenté');
      m.dispose();
    });

    test('une seule radio suffit à sortir de la coupure', () {
      final m = MeshStateMachine();
      m.update(
        transports: radios(
          wifi: TransportState.unavailable,
          p2p: TransportState.unavailable,
          ble: TransportState.searching,
        ),
        connectedPeers: 0,
      );
      expect(m.state, MeshNetworkState.discovering);
      m.dispose();
    });

    test('des pairs vus mais aucune liaison montée : connexion en cours', () {
      final m = MeshStateMachine();
      m.update(
        transports: radios(wifi: TransportState.searching),
        connectedPeers: 2,
      );
      expect(m.state, MeshNetworkState.connecting);
      m.dispose();
    });

    test('une liaison active et des pairs : connecté', () {
      final m = MeshStateMachine();
      m.update(
        transports: radios(wifi: TransportState.active),
        connectedPeers: 3,
      );
      expect(m.state, MeshNetworkState.connected);
      expect(m.canSend, isTrue);
      m.dispose();
    });

    test('mauvaise qualité de lien : dégradé', () {
      final m = MeshStateMachine();
      m.update(
        transports: radios(ble: TransportState.active),
        connectedPeers: 1,
        qualityOk: false,
      );
      expect(m.state, MeshNetworkState.degraded);
      // Dégradé reste envoyable : le texte passe, c'est l'essentiel.
      expect(m.canSend, isTrue);
      m.dispose();
    });

    test('échange en cours : synchronisation', () {
      final m = MeshStateMachine();
      m.update(
        transports: radios(wifi: TransportState.active),
        connectedPeers: 1,
        syncing: true,
      );
      expect(m.state, MeshNetworkState.syncing);
      m.dispose();
    });
  });

  group('Transitions', () {
    test('un état recalculé à l\'identique ne produit AUCUNE transition', () {
      // C'est la promesse qui rend le journal lisible : sans elle, on
      // retrouverait une ligne toutes les trois secondes.
      final vues = <MeshStateTransition>[];
      final m = MeshStateMachine(onTransition: vues.add);

      for (var i = 0; i < 100; i++) {
        m.update(
          transports: radios(wifi: TransportState.unavailable),
          connectedPeers: 0,
        );
      }

      expect(vues.length, 1, reason: 'une seule entrée en réseau perdu');
      expect(m.networkLossCount, 1);
      m.dispose();
    });

    test('le cycle coupure → retour → reconnexion est signalé', () {
      final vues = <MeshStateTransition>[];
      final m = MeshStateMachine(onTransition: vues.add);

      m.update(
        transports: radios(wifi: TransportState.active),
        connectedPeers: 1,
      );
      expect(m.state, MeshNetworkState.connected);

      // Le Wi-Fi tombe.
      m.update(
        transports: radios(wifi: TransportState.unavailable),
        connectedPeers: 0,
      );
      expect(m.state, MeshNetworkState.networkLost);

      // La radio revient, mais personne en vue : on RÉCUPÈRE, on n'est
      // pas simplement « en recherche ». La nuance compte : elle dit
      // qu'il faudra resynchroniser.
      m.update(
        transports: radios(wifi: TransportState.searching),
        connectedPeers: 0,
      );
      expect(m.state, MeshNetworkState.recovering);
      expect(m.needsResync, isTrue);

      // Un pair est retrouvé : la reprise est acquise.
      m.update(
        transports: radios(wifi: TransportState.active),
        connectedPeers: 1,
      );
      expect(m.state, MeshNetworkState.connected);
      expect(m.needsResync, isFalse);

      expect(vues.map((t) => t.to).toList(), [
        MeshNetworkState.connected,
        MeshNetworkState.networkLost,
        MeshNetworkState.recovering,
        MeshNetworkState.connected,
      ]);
      m.dispose();
    });

    test('dégradation et amélioration sont distinguées', () {
      final vues = <MeshStateTransition>[];
      final m = MeshStateMachine(onTransition: vues.add);

      m.update(
        transports: radios(wifi: TransportState.active),
        connectedPeers: 1,
      );
      m.update(
        transports: radios(wifi: TransportState.unavailable),
        connectedPeers: 0,
      );

      expect(vues.last.isDegradation, isTrue);
      expect(vues.last.isImprovement, isFalse);
      m.dispose();
    });

    test('les coupures successives sont comptées', () {
      final m = MeshStateMachine();
      for (var i = 0; i < 3; i++) {
        m.update(
          transports: radios(wifi: TransportState.active),
          connectedPeers: 1,
        );
        m.update(
          transports: radios(wifi: TransportState.unavailable),
          connectedPeers: 0,
        );
      }
      expect(m.networkLossCount, 3);
      m.dispose();
    });

    test('l\'historique est borné', () {
      final m = MeshStateMachine();
      for (var i = 0; i < 200; i++) {
        m.update(
          transports: radios(wifi: TransportState.active),
          connectedPeers: 1,
        );
        m.update(
          transports: radios(wifi: TransportState.unavailable),
          connectedPeers: 0,
        );
      }
      expect(m.recentTransitions.length, lessThanOrEqualTo(50));
      m.dispose();
    });

    test('markStopped ramène hors ligne', () {
      final m = MeshStateMachine();
      m.update(
        transports: radios(wifi: TransportState.active),
        connectedPeers: 2,
      );
      m.markStopped();
      expect(m.state, MeshNetworkState.offline);
      expect(m.canSend, isFalse);
      m.dispose();
    });
  });

  group('canSend', () {
    test('ne tente rien tant qu\'aucun pair n\'est joignable', () {
      expect(MeshNetworkState.offline.canSend, isFalse);
      expect(MeshNetworkState.networkLost.canSend, isFalse);
      expect(MeshNetworkState.recovering.canSend, isFalse);
      expect(MeshNetworkState.discovering.canSend, isFalse);

      expect(MeshNetworkState.connecting.canSend, isTrue);
      expect(MeshNetworkState.degraded.canSend, isTrue);
      expect(MeshNetworkState.connected.canSend, isTrue);
      expect(MeshNetworkState.syncing.canSend, isTrue);
    });
  });
}
