// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE CONTRAT COMMUN À TOUS LES MOYENS DE TRANSPORT de Droplet.
//
// Droplet sait faire circuler ses messages par trois chemins physiques
// différents : le Wi-Fi du quartier, le Wi-Fi Direct d'appareil à
// appareil, et le Bluetooth. Ce sont trois technologies radio qui n'ont
// rien en commun — portée, débit, consommation, façon de découvrir les
// voisins, tout diffère.
//
// ── Le problème que ce fichier résout ─────────────────────────────────
//
// Jusqu'ici, ces trois transports avaient bien la MÊME FORME (démarrer,
// arrêter, envoyer, deux flux d'événements) — mais nulle part il n'était
// écrit qu'ils devaient l'avoir. La couche du dessus les connaissait
// donc chacun par son nom, et devait faire un aiguillage explicite :
//
//     case TransportKind.localWifi: return _wifiTransport.sendToPeer(…);
//     case TransportKind.ble:       return _bleTransport.sendToPeer(…);
//
// Trois conséquences concrètes :
//
//   1. AJOUTER UN QUATRIÈME TRANSPORT oblige à rouvrir les 1600 lignes
//      de logique d'aiguillage, alors que cette logique n'a rien à voir
//      avec la radio.
//   2. LES RÈGLES DE CHAQUE RADIO SE RETROUVENT RECOPIÉES en haut. Le
//      Bluetooth refuse les fichiers et les gros paquets ; cette règle
//      vivait à la fois dans le transport Bluetooth ET dans la couche
//      supérieure, avec le risque classique que les deux divergent.
//   3. ON NE PEUT PAS TESTER SANS RADIO. Impossible de simuler vingt
//      nœuds, 5 % de perte ou une déconnexion brutale : il aurait fallu
//      vingt téléphones. C'est la raison principale de ce fichier —
//      avec un contrat, un transport SIMULÉ devient possible, et avec
//      lui les mesures reproductibles.
//
// ── Ce que ce contrat ne contient PAS, volontairement ─────────────────
//
// Pas de `discoverPeers()`, `connect()` ni `disconnect()`. Ces trois-là
// semblent naturels sur le papier, mais AUCUN des transports de Droplet
// ne fonctionne comme ça : ils découvrent et se connectent tout seuls,
// en permanence, dès qu'ils tournent — c'est ce qu'exige un maillage où
// les gens marchent. Les inscrire au contrat obligerait à écrire trois
// méthodes vides, c'est-à-dire à mentir sur ce que le contrat garantit.
// Ce qu'ils font savoir, ils le font par `peerEvents`.
// ============================================================================

import 'dart:typed_data';

import 'ble_mesh_protocol.dart' show MeshPeerEvent, MeshIncomingData;

/// L'état d'un transport, du point de vue de la couche supérieure.
///
/// Volontairement plus grossier que l'état interne de chaque radio : la
/// couche du dessus n'a pas besoin de savoir qu'un scan BLE est en pause
/// entre deux cycles, elle a besoin de savoir si elle peut compter sur
/// ce chemin ou non.
enum TransportState {
  /// Éteint, ou jamais démarré.
  stopped,

  /// Démarré, mais le matériel ne répond pas : Wi-Fi coupé, Bluetooth
  /// désactivé, permission refusée. Aucun envoi ne peut aboutir.
  unavailable,

  /// Démarré et fonctionnel, mais sans aucun pair en vue.
  searching,

  /// Au moins un pair joignable.
  active,
}

/// Ce qu'un transport sait faire — et surtout, ce qu'il ne sait pas.
///
/// Ces limites vivent ICI, auprès du transport qui les connaît, et non
/// recopiées dans la couche d'aiguillage. C'est ce qui permet à celle-ci
/// de demander « peux-tu porter ceci ? » au lieu de savoir par cœur que
/// le Bluetooth refuse les fichiers.
class TransportCapabilities {
  const TransportCapabilities({
    required this.maxPayloadBytes,
    required this.maxContentType,
    required this.portePhotosEtFichiers,
    required this.porteVoixEnDirect,
    required this.coutEnergetique,
  });

  /// Taille maximale d'un paquet, en octets.
  final int maxPayloadBytes;

  /// Type de contenu le plus élevé accepté. Dans Droplet, les types à
  /// partir de 0x20 désignent les contenus lourds (fichiers, médias).
  final int maxContentType;

  final bool portePhotosEtFichiers;

  /// Le débit et la latence permettent-ils un appel vocal ?
  final bool porteVoixEnDirect;

  /// Coût en batterie, de 0 (négligeable) à 1 (très coûteux). Sert à
  /// départager deux chemins également valables.
  final double coutEnergetique;

  /// Ce transport peut-il porter ce paquet précis ?
  ///
  /// Une seule question posée au transport, plutôt que trois règles
  /// recopiées chez l'appelant.
  bool accepte({required int tailleOctets, required int type}) =>
      tailleOctets <= maxPayloadBytes && type <= maxContentType;
}

/// Compteurs d'un transport, pour l'observabilité et les mesures.
///
/// Volontairement simples et cumulatifs : c'est l'appelant qui calcule
/// des taux et des percentiles à partir de deux relevés. Un transport
/// n'a pas à savoir ce qu'est un P95.
class TransportMetrics {
  int pairsDecouverts = 0;
  int pairsConnectes = 0;
  int echecsConnexion = 0;
  int paquetsEnvoyes = 0;
  int paquetsRecus = 0;
  int echecsEnvoi = 0;
  int octetsEnvoyes = 0;
  int octetsRecus = 0;

  /// Nombre de fois où le transport est passé en `indisponible` —
  /// autrement dit, combien de fois la radio a lâché.
  int pertesDeLien = 0;

  Map<String, int> toJson() => {
        'pairsDecouverts': pairsDecouverts,
        'pairsConnectes': pairsConnectes,
        'echecsConnexion': echecsConnexion,
        'paquetsEnvoyes': paquetsEnvoyes,
        'paquetsRecus': paquetsRecus,
        'echecsEnvoi': echecsEnvoi,
        'octetsEnvoyes': octetsEnvoyes,
        'octetsRecus': octetsRecus,
        'pertesDeLien': pertesDeLien,
      };

  @override
  String toString() => toJson().toString();
}

/// Le contrat que remplit chaque moyen de transport.
///
/// `abstract interface class` : on ne peut pas en hériter pour récupérer
/// du code tout fait, seulement s'engager à en remplir la forme. C'est
/// exactement l'intention ici — les trois transports n'ont rigoureusement
/// aucun code à partager, seulement une forme commune.
abstract interface class MeshTransport {
  /// Nom court, pour les journaux et les métriques (« wifi », « ble »…).
  String get name;

  /// Vrai entre `start()` et `stop()`.
  bool get isRunning;

  TransportState get state;

  TransportCapabilities get capabilities;

  TransportMetrics get metrics;

  /// Les pairs qui apparaissent et disparaissent.
  Stream<MeshPeerEvent> get peerEvents;

  /// Les données reçues des pairs.
  Stream<MeshIncomingData> get incomingData;

  /// Allume la radio et commence à chercher. Doit être sans effet si le
  /// transport tourne déjà.
  Future<void> start(String myId, String myPseudo);

  /// Éteint tout proprement. Doit pouvoir être appelée même à l'arrêt.
  Future<void> stop();

  /// Envoie [data] à [peerId].
  ///
  /// Renvoie ce qui s'est RÉELLEMENT passé, jamais ce qu'on a tenté :
  /// `false` si le paquet n'est pas parti, pour que la couche supérieure
  /// puisse essayer un autre chemin plutôt que de croire le message
  /// délivré.
  ///
  /// [type] désigne la nature du contenu ; les transports qui n'en font
  /// rien l'ignorent, ceux qui ont des limites s'en servent pour refuser
  /// ce qu'ils ne peuvent pas porter.
  ///
  /// [priority] — si `critical` ou `high`, le message contourne la file
  /// séquentielle BLE pour minimiser la latence (appels, SOS, typing).
  Future<bool> sendToPeer(String peerId, Uint8List data,
      {int type, int priority});

  /// Libère les ressources définitivement.
  void dispose();
}
