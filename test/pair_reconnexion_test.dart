// ============================================================================
// CE QUE CE FICHIER VÉRIFIE
// ----------------------------------------------------------------------------
// QU'UN PAIR NE DISPARAÎT PAS AU MOINDRE HOQUET DE LIAISON.
//
// C'est le comportement que l'utilisateur compare à WhatsApp : quand deux
// ou trois téléphones sont connectés, ils doivent le RESTER, et ne se
// perdre que si la distance devient trop grande.
//
// ── Le défaut que ces tests empêchent de revenir ──────────────────────
//
// L'ancienne logique retirait le pair de la liste À L'INSTANT où son
// dernier transport tombait. Or sur Android, une liaison Bluetooth se
// coupe et se rétablit sans arrêt, pour des raisons qui n'ont rien à voir
// avec la distance : le système ferme un GATT inactif, la radio part
// servir autre chose, le socket dort une seconde. Chacune de ces
// micro-coupures faisait disparaître le contact, repasser la conversation
// en « hors ligne », et échouer les messages en cours — deux téléphones
// posés côte à côte.
//
// La correction introduit un DÉLAI DE GRÂCE : le pair reste listé,
// marqué « reconnexion », et n'est déclaré perdu que si personne ne l'a
// revu au bout de `reconnectGrace`.
//
// ── Pourquoi le temps est injecté ─────────────────────────────────────
//
// `sweepPeers` accepte une date. Vérifier un délai de quarante-cinq
// secondes en attendant réellement quarante-cinq secondes rendrait la
// suite de tests inutilisable — on fait donc avancer l'horloge à la main.
// ============================================================================

import 'package:droplet/core/services/mesh_transport_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late MeshTransportService mesh;

  setUp(() {
    mesh = MeshTransportService();
    // Grâce courte pour que les calculs de dates restent lisibles ; la
    // logique testée est la même quelle que soit la valeur.
    mesh.config = const MeshScaleConfig(reconnectGrace: 45);
  });

  ConnectedPeer? trouver(String id) =>
      mesh.connectedPeers.where((p) => p.peerId == id).firstOrNull;

  group('Micro-coupure', () {
    test('le pair reste listé quand son dernier lien tombe', () {
      mesh.debugSignalerPair('alice',
          transport: TransportKind.ble, connecte: true);
      expect(trouver('alice'), isNotNull);

      // Le Bluetooth lâche.
      mesh.debugSignalerPair('alice',
          transport: TransportKind.ble, connecte: false);

      final alice = trouver('alice');
      expect(alice, isNotNull,
          reason: 'le pair ne doit PAS disparaître au premier hoquet');
      expect(alice!.reconnecting, isTrue);
      expect(alice.transports, isEmpty,
          reason: 'aucun chemin ne fonctionne, et il ne faut pas le cacher');
    });

    test('il redevient normal dès qu\'un transport le revoit', () {
      mesh.debugSignalerPair('alice',
          transport: TransportKind.ble, connecte: true);
      mesh.debugSignalerPair('alice',
          transport: TransportKind.ble, connecte: false);
      expect(trouver('alice')!.reconnecting, isTrue);

      // Deux secondes plus tard, le lien revient — le cas le plus
      // fréquent, et celui que l'utilisateur ne doit jamais voir.
      mesh.debugSignalerPair('alice',
          transport: TransportKind.ble, connecte: true);

      final alice = trouver('alice')!;
      expect(alice.reconnecting, isFalse);
      expect(alice.transports, contains(TransportKind.ble));
    });

    test('la grâce en cours n\'expire pas avant son terme', () {
      mesh.debugSignalerPair('alice',
          transport: TransportKind.ble, connecte: true);
      mesh.debugSignalerPair('alice',
          transport: TransportKind.ble, connecte: false);

      // 30 secondes après : on patiente encore (grâce = 45 s).
      mesh.sweepPeers(
          maintenant: DateTime.now().add(const Duration(seconds: 30)));
      expect(trouver('alice'), isNotNull);
    });
  });

  group('Éloignement réel', () {
    test('le pair est retiré une fois la grâce écoulée', () {
      mesh.debugSignalerPair('alice',
          transport: TransportKind.ble, connecte: true);
      mesh.debugSignalerPair('alice',
          transport: TransportKind.ble, connecte: false);

      // Une minute plus tard, toujours rien : cette fois la personne est
      // vraiment partie.
      mesh.sweepPeers(
          maintenant: DateTime.now().add(const Duration(seconds: 60)));
      expect(trouver('alice'), isNull);
    });
  });

  group('Cohérence balise / délai', () {
    test('ralentir les balises allonge le délai de grâce', () {
      // ⚠️ LE PIÈGE QUE CE TEST FERME.
      //
      // Espacer les balises pour économiser la batterie est une bonne
      // idée — mais si le délai avant de déclarer un pair perdu reste
      // fixe, on se met à supprimer des pairs parfaitement joignables
      // simplement parce qu'ils annoncent leur présence moins souvent.
      // C'est le bug de « déconnexion trop rapide », réintroduit par la
      // porte de derrière.
      //
      // Ici : application en arrière-plan et batterie à plat, la balise
      // passe de 5 à 20 secondes. La grâce doit suivre, pas rester à 45.
      mesh.config = const MeshScaleConfig(
        wifiBeaconIntervalSparse: 5,
        reconnectGrace: 45,
      );
      // Ces deux appels recalculent eux-mêmes la cadence.
      mesh.setForegroundState(false);
      mesh.updateBatteryLevel(0.1);

      mesh.debugSignalerPair('alice',
          transport: TransportKind.ble, connecte: true);
      mesh.debugSignalerPair('alice',
          transport: TransportKind.ble, connecte: false);

      // 5 × 4 = 20 s de balise → au moins 60 s de grâce (trois annonces).
      // À 50 secondes, le pair doit donc encore être là.
      mesh.sweepPeers(
          maintenant: DateTime.now().add(const Duration(seconds: 50)));
      expect(trouver('alice'), isNotNull,
          reason: 'la grâce doit suivre la cadence des balises');

      // Mais pas éternellement.
      mesh.sweepPeers(
          maintenant: DateTime.now().add(const Duration(seconds: 90)));
      expect(trouver('alice'), isNull);
    });
  });

  group('Plusieurs chemins', () {
    test('perdre le Bluetooth ne coupe rien si le Wi-Fi tient', () {
      // C'est tout l'intérêt d'avoir plusieurs transports : la panne de
      // l'un ne doit jamais se voir tant qu'un autre fonctionne.
      mesh.debugSignalerPair('bob',
          transport: TransportKind.ble, connecte: true);
      mesh.debugSignalerPair('bob',
          transport: TransportKind.localWifi, connecte: true);

      mesh.debugSignalerPair('bob',
          transport: TransportKind.ble, connecte: false);

      final bob = trouver('bob')!;
      expect(bob.reconnecting, isFalse,
          reason: 'le Wi-Fi tient : ce n\'est pas une reconnexion');
      expect(bob.transports, {TransportKind.localWifi});

      // Et rien ne doit l'évincer au balayage suivant.
      mesh.sweepPeers(
          maintenant: DateTime.now().add(const Duration(seconds: 20)));
      expect(trouver('bob'), isNotNull);
    });
  });
}
