// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est le chemin de communication le plus RAPIDE de l'app : le Wi-Fi
// local, utilisé quand deux téléphones sont connectés au MÊME réseau
// Wi-Fi (ou point d'accès mobile) — pas besoin d'Internet, juste d'être
// sur le même réseau local.
//
// Il y a DEUX façons de se DÉCOUVRIR (trouver les autres téléphones) :
//   1. Le « mDNS » — un peu comme crier son nom dans une salle en
//      attendant que quelqu'un réponde « présent ! ». C'est la méthode
//      principale, la plus propre.
//   2. Les « beacons UDP » — un plan B plus simple : toutes les 3
//      secondes, on envoie un petit message à TOUT LE MONDE sur le réseau
//      (« diffusion » = broadcast) pour dire « coucou, je suis là ».
//
// Une fois deux téléphones repérés, ils ouvrent une VRAIE connexion directe
// (une « socket TCP », comme un tuyau permanent entre les deux), et
// s'échangent d'abord une « poignée de main » (handshake) pour se dire
// qui ils sont, avant de pouvoir vraiment discuter.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'ble_mesh_protocol.dart';

/// Transport Wi-Fi local pour OURO PREP.
///
/// ## Découverte
/// - **mDNS** (via `nsd`) — enregistre un service `_ouroprep._tcp`
/// - **UDP broadcast** (fallback) — envoie des beacons toutes les 3s sur
///   `OURO_DISCOVERY_PORT` et écoute les beacons entrants
///
/// ## Communication
/// Sockets TCP bruts (`dart:io`) avec framing `[longueur 4 bytes][payload]`.
class LocalWifiTransport {
  static const int _discoveryPort = 42069;

  /// L'intervalle par défaut entre deux balises « coucou ».
  static const Duration _beaconIntervalDefaut = Duration(seconds: 3);

  /// L'intervalle RÉELLEMENT appliqué, ajusté par `MeshTransportService`
  /// selon le nombre de pairs, la batterie et l'état de l'application.
  ///
  /// ⚠️ Il était auparavant figé à 3 secondes, et toute l'adaptation
  /// calculée plus haut (`_currentWifiBeaconInterval`) finissait dans un
  /// simple `debugPrint` sans jamais atteindre la radio. Résultat : une
  /// balise toutes les trois secondes en permanence, y compris app en
  /// arrière-plan et batterie à 5 %.
  Duration _beaconInterval = _beaconIntervalDefaut;

  /// Au bout de combien de temps sans balise on oublie un pair.
  ///
  /// ⚠️ CE DÉLAI SUIT L'INTERVALLE, IL N'EST PAS FIXE — et c'est
  /// indispensable. Un délai constant de 15 secondes avec une balise
  /// toutes les 30 secondes (cas d'un réseau dense) supprimerait
  /// systématiquement des pairs parfaitement joignables, à chaque
  /// passage de balai. On garde donc toujours la place pour CINQ balises
  /// manquées : en dessous, on confond une perte de paquet avec un
  /// départ.
  Duration get _peerTimeout => _beaconInterval * 5;

  /// Change la cadence des balises, à chaud.
  ///
  /// Le minuteur est reprogrammé immédiatement : attendre le prochain
  /// déclenchement retarderait l'ajustement d'autant, ce qui n'a aucun
  /// sens quand on vient justement de constater une batterie faible.
  void setBeaconInterval(Duration interval) {
    if (interval == _beaconInterval) return;
    _beaconInterval = interval;
    if (!_isRunning) return;
    _beaconTimer?.cancel();
    _beaconTimer = Timer.periodic(_beaconInterval, (_) => _sendBeacon());
    debugPrint('[LocalWifi] balise réglée à ${interval.inSeconds}s '
        '(oubli après ${_peerTimeout.inSeconds}s)');
  }

  bool _isRunning = false;
  String _myId = '';
  String _myPseudo = '';
  int _listenPort = 0;
  int _beaconCount = 0;

  final _peerEventsCtrl = StreamController<MeshPeerEvent>.broadcast();
  final _incomingDataCtrl = StreamController<MeshIncomingData>.broadcast();

  Stream<MeshPeerEvent> get peerEvents => _peerEventsCtrl.stream;
  Stream<MeshIncomingData> get incomingData => _incomingDataCtrl.stream;

  ServerSocket? _serverSocket;
  RawDatagramSocket? _udpSocket;
  nsd.Discovery? _discovery;

  final Map<String, _TcpPeerInfo> _connectedPeers = {};
  final Map<String, DateTime> _lastBeaconSeen = {};
  Timer? _beaconTimer;
  Timer? _cleanupTimer;
  Timer? _discoveryTimer;

  /// Allume tout : ouvre une porte d'entrée pour les connexions (le
  /// serveur TCP), commence à écouter les cris « coucou » des autres
  /// (UDP), et s'annonce sur le réseau via mDNS.
  Future<void> start(String myId, String myPseudo) async {
    if (_isRunning) return;
    _isRunning = true;
    _myId = myId;
    _myPseudo = myPseudo;

    await _startServer();
    await _resolveBroadcastAddress();
    await _startUdpDiscovery();
    await _startMdnsDiscovery();

    _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (_) => _cleanupStalePeers());
    _beaconTimer = Timer.periodic(_beaconInterval, (_) => _sendBeacon());

    debugPrint('[LocalWifi] started on port $_listenPort id=$myId');
  }

  Future<void> stop() async {
    _isRunning = false;
    _beaconTimer?.cancel();
    _cleanupTimer?.cancel();
    _discoveryTimer?.cancel();

    if (_discovery != null) {
      await nsd.stopDiscovery(_discovery!);
    }

    _udpSocket?.close();
    _udpSocket = null;
    _connectingPeerIds.clear();

    if (_serverSocket != null) {
      for (final peer in _connectedPeers.values) {
        try { peer.socket.close(); } catch (e) { debugPrint('[WiFi] $e'); }
      }
      _connectedPeers.clear();
      _lastBeaconSeen.clear();
      await _serverSocket!.close();
      _serverSocket = null;
    }
  }

  // ── TCP Server ──────────────────────────────────────────────────────
  //
  // Le « serveur TCP » est notre porte d'entrée : on ouvre un port et on
  // attend que d'autres téléphones viennent frapper — comme une porte
  // d'appartement toujours prête à s'ouvrir.

  Future<void> _startServer() async {
    for (int attempt = 0; attempt < 10; attempt++) {
      try {
        _serverSocket = await ServerSocket.bind(
          InternetAddress.anyIPv4,
          0,
          shared: true,
        );
        _listenPort = _serverSocket!.port;
        _serverSocket!.listen(_onIncomingConnection, onError: (e) {
          debugPrint('[LocalWifi] server error: $e');
        });
        break;
      } catch (e) {
        debugPrint('[LocalWifi] server bind attempt $attempt failed: $e');
        await Future.delayed(const Duration(milliseconds: 100));
      }
    }

    if (_serverSocket == null) {
      throw Exception('Impossible d\'ouvrir un port d\'écoute TCP');
    }
  }

  /// Quelqu'un vient de frapper à notre porte (nouvelle connexion) — on
  /// note son arrivée et on commence à écouter ce qu'il a à dire.
  void _onIncomingConnection(Socket socket) {
    final remoteAddr = '${socket.remoteAddress.address}:${socket.remotePort}';
    final info = _TcpPeerInfo(address: remoteAddr, socket: socket);
    _connectedPeers[remoteAddr] = info;
    _receiveLoop(socket, info);
  }

  // ── UDP Broadcast Discovery ─────────────────────────────────────────
  //
  // Le plan B de découverte : au lieu de chuchoter à une adresse précise,
  // on CRIE un petit message à TOUT le réseau en même temps, et on écoute
  // si quelqu'un d'autre crie la même chose.

  Future<void> _startUdpDiscovery() async {
    try {
      _udpSocket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        _discoveryPort,
        reuseAddress: true,
      );
      _udpSocket!.broadcastEnabled = true;
      _udpSocket!.listen(_onUdpEvent);
      debugPrint('[LocalWifi] UDP listener on port $_discoveryPort');
    } catch (e) {
      debugPrint('[LocalWifi] UDP bind failed: $e');
    }
  }

  InternetAddress? _subnetBroadcast;

  /// Devine l'adresse spéciale « tout le monde sur ce réseau » (l'adresse
  /// de diffusion), à partir de notre propre adresse Wi-Fi.
  Future<void> _resolveBroadcastAddress() async {
    try {
      final interfaces = await NetworkInterface.list();
      for (final iface in interfaces) {
        final hasPrivateIp = iface.addresses.any((a) =>
            a.address.startsWith('192.168.') ||
            a.address.startsWith('10.') ||
            a.address.startsWith('172.'));
        if (!hasPrivateIp) { continue; }
        for (final addr in iface.addresses) {
          if (addr.type == InternetAddressType.IPv4) {
            final parts = addr.address.split('.');
            final broadcast = '${parts[0]}.${parts[1]}.${parts[2]}.255';
            _subnetBroadcast = InternetAddress(broadcast);
            debugPrint('[LocalWifi] resolved broadcast: $broadcast');
            return;
          }
        }
      }
    } catch (e) { debugPrint('[WiFi] $e'); }
    _subnetBroadcast = InternetAddress('255.255.255.255');
  }

  /// Envoie le petit cri « coucou, je suis là » à tout le réseau — répété
  /// toutes les 3 secondes tant que l'app tourne.
  void _sendBeacon() {
    if (!_isRunning || _udpSocket == null) return;
    try {
      final payload = utf8.encode(json.encode({
        'peerId': _myId,
        'pseudo': _myPseudo,
        'port': _listenPort,
      }));
      final targets = [
        InternetAddress('255.255.255.255'),
        ?_subnetBroadcast,
      ];
      for (final target in targets) {
        _udpSocket!.send(payload, target, _discoveryPort);
      }
      _beaconCount++;
      if (_beaconCount % 10 == 0) {
        debugPrint('[LocalWifi] beacon #$_beaconCount sent');
      }
    } catch (e) {
      debugPrint('[LocalWifi] beacon send error: $e');
    }
  }

  /// Quelqu'un d'autre vient de crier son « coucou » — si on ne le connaît
  /// pas encore, on tente de se connecter directement à lui.
  void _onUdpEvent(RawSocketEvent event) {
    if (!_isRunning || _udpSocket == null) return;
    if (event != RawSocketEvent.read) return;

    final datagram = _udpSocket!.receive();
    if (datagram == null) return;

    try {
      final msg = json.decode(utf8.decode(datagram.data)) as Map<String, dynamic>;
      final peerId = msg['peerId'] as String?;
      if (peerId == null || peerId == _myId) return;

      final pseudo = msg['pseudo'] as String? ?? peerId;
      final port = msg['port'] as int? ?? 0;

      _lastBeaconSeen[peerId] = DateTime.now();

      if (_connectedPeers.values.any((p) => p.peerId == peerId)) return;
      if (port == 0) return;

      _connectToPeer(peerId, pseudo, datagram.address, port);
    } catch (e) {
      debugPrint('[LocalWifi] UDP parse error: $e');
    }
  }

  /// Purge uniquement le bookkeeping de découverte (`_lastBeaconSeen`) des
  /// pairs dont on n'a plus entendu le beacon UDP récemment — ne ferme
  /// JAMAIS une connexion TCP déjà établie sur cette seule base.
  ///
  /// Avant ce correctif, une connexion TCP saine était coupée de force dès
  /// que 15s s'écoulaient sans beacon UDP frais pour ce pair — hors la
  /// diffusion/multicast UDP est peu fiable sur beaucoup de routeurs Wi-Fi
  /// réels (isolation clients, filtrage IGMP), contrairement à un simple
  /// point d'accès mobile. Résultat observé et reproduit : un pair réel se
  /// connectait puis se déconnectait quasi immédiatement, rendant les
  /// connexions non persistantes et les envois systématiquement en échec.
  /// La vraie source de vérité pour "ce pair est-il toujours là" est le
  /// socket TCP lui-même (`onDone`/`onError`, voir `_onPeerDisconnected`) —
  /// les beacons ne servent qu'à la DÉCOUVERTE de nouveaux pairs, pas au
  /// maintien en vie d'une connexion déjà établie.
  ///
  /// En mots simples : ce n'est pas parce qu'on n'entend plus quelqu'un
  /// CRIER (le beacon) qu'il est parti — s'il est toujours en ligne avec
  /// nous au téléphone (la connexion TCP), c'est ÇA la vraie preuve qu'il
  /// est encore là.
  void _cleanupStalePeers() {
    final now = DateTime.now();
    final stale = _lastBeaconSeen.entries
        .where((e) => now.difference(e.value) > _peerTimeout)
        .map((e) => e.key)
        .toList();

    for (final peerId in stale) {
      if (_connectedPeers.values.any((p) => p.peerId == peerId)) continue;
      _lastBeaconSeen.remove(peerId);
    }
  }

  // ── mDNS Discovery (secondary) ──────────────────────────────────────
  //
  // mDNS (« multicast DNS ») est la méthode de découverte PRINCIPALE :
  // notre téléphone s'inscrit dans un genre d'« annuaire local » du
  // réseau Wi-Fi (comme se présenter à l'accueil d'un immeuble), et
  // écoute en même temps qui d'autre s'y est inscrit.

  Future<void> _startMdnsDiscovery() async {
    try {
      final service = nsd.Service(
        name: _myId,
        type: '_ouroprep._tcp',
        port: _listenPort,
        txt: {
          'pseudo': Uint8List.fromList(utf8.encode(_myPseudo)),
          // Les noms de service mDNS sont limités à 63 octets (une seule
          // étiquette DNS) : notre ID (64 caractères hex) y est
          // silencieusement tronqué par l'OS. Le TXT record n'a pas cette
          // limite — c'est la seule source fiable pour l'identité du pair
          // (voir _onServiceEvent, qui ne fait plus confiance à
          // service.name pour filtrer notre propre annonce).
          'id': Uint8List.fromList(utf8.encode(_myId)),
        },
      );
      await nsd.register(service).timeout(const Duration(seconds: 4));
      debugPrint('[LocalWifi] mDNS registered');
    } catch (e) {
      debugPrint('[LocalWifi] mDNS register failed: $e');
    }

    try {
      _discovery = await nsd.startDiscovery(
        '_ouroprep._tcp',
        autoResolve: true,
      ).timeout(const Duration(seconds: 4));
      _discovery!.addServiceListener(_onServiceEvent);
      debugPrint('[LocalWifi] mDNS discovery started');
    } catch (e) {
      debugPrint('[LocalWifi] mDNS discovery failed: $e');
    }
  }

  /// ID réel du pair annoncé par ce service — lu depuis le TXT record, pas
  /// depuis `service.name` (silencieusement tronqué à 63 octets par le
  /// mDNS sous-jacent, ce qui empêchait le filtre anti-auto-connexion
  /// ci-dessous de jamais matcher et menait à une connexion à soi-même).
  /// Repli sur `service.name` si un pair distant tourne encore une
  /// ancienne version de l'app sans ce TXT record.
  String _peerIdOf(nsd.Service service) {
    final idBytes = service.txt?['id'];
    if (idBytes != null) {
      try {
        return utf8.decode(idBytes);
      } catch (_) {}
    }
    return service.name ?? '';
  }

  /// Un événement d'annuaire mDNS vient d'arriver : quelqu'un est apparu,
  /// ou a disparu.
  void _onServiceEvent(nsd.Service service, nsd.ServiceStatus status) {
    if (!_isRunning) return;
    if (_peerIdOf(service) == _myId) return;
    if (status == nsd.ServiceStatus.found) {
      _onServiceFound(service);
    } else {
      _onServiceLost(service);
    }
  }

  /// Nouveau téléphone Droplet repéré dans l'annuaire — on tente de s'y
  /// connecter directement.
  void _onServiceFound(nsd.Service service) {
    final peerId = _peerIdOf(service);
    if (peerId.isEmpty) return;
    if (_connectedPeers.values.any((p) => p.peerId == peerId)) return;

    final pseudoBytes = service.txt?['pseudo'];
    final pseudo = pseudoBytes != null ? utf8.decode(pseudoBytes) : peerId;

    final address = service.addresses?.isNotEmpty == true
        ? service.addresses!.first
        : InternetAddress.loopbackIPv4;

    _connectToPeer(peerId, pseudo, address, service.port ?? 0);
  }

  /// Un téléphone a disparu de l'annuaire mDNS — on ferme sa connexion et
  /// on prévient le reste de l'app.
  void _onServiceLost(nsd.Service service) {
    final peerId = _peerIdOf(service);
    final existing = _connectedPeers.values.where(
      (p) => p.peerId == peerId,
    );
    if (existing.isEmpty) return;
    final peer = existing.first;

    _peerEventsCtrl.add(MeshPeerEvent(
      peerId: peerId,
      pseudo: peer.pseudo ?? peerId,
      isConnected: false,
    ));
    _connectedPeers.removeWhere((k, v) => v.peerId == peerId);
    try { peer.socket.close(); } catch (e) { debugPrint('[WiFi] $e'); }
  }

  // ── TCP Connection ──────────────────────────────────────────────────

  /// Pairs vers qui une connexion TCP est déjà en train de s'établir —
  /// évite de composer le numéro deux fois de suite avant même d'avoir
  /// décroché.
  final Set<String> _connectingPeerIds = {};

  /// Se connecte vraiment à un pair repéré (peu importe qu'on l'ait trouvé
  /// via mDNS ou UDP) : ouvre le tuyau TCP, envoie sa carte de visite
  /// (handshake) pour se présenter, puis commence à écouter ce qu'il
  /// répond.
  Future<void> _connectToPeer(
    String peerId, String pseudo, InternetAddress address, int port,
  ) async {
    if (_connectedPeers.values.any((p) => p.peerId == peerId)) return;

    // Un même pair peut être annoncé plusieurs fois quasi simultanément
    // (un beacon UDP est envoyé à la fois vers 255.255.255.255 ET vers
    // l'adresse de diffusion du sous-réseau — les deux arrivent souvent
    // en double), et mDNS peut le redécouvrir juste après. Sans ce
    // verrou, ces événements en rafale déclenchaient chacun leur propre
    // `Socket.connect` avant que le premier n'ait eu le temps de
    // s'enregistrer dans `_connectedPeers` — deux tuyaux TCP ouverts en
    // parallèle vers la même personne pour rien, du gaspillage de
    // batterie/sockets à l'échelle d'un mesh très dense.
    if (!_connectingPeerIds.add(peerId)) return;

    try {
      debugPrint('[LocalWifi] connecting to $peerId at $address:$port');
      final socket = await Socket.connect(
        address,
        port,
        timeout: const Duration(seconds: 5),
      );

      final remoteAddr = '${socket.remoteAddress.address}:${socket.remotePort}';
      final info = _TcpPeerInfo(
        address: remoteAddr,
        socket: socket,
        peerId: peerId,
        pseudo: pseudo,
      );
      _connectedPeers[remoteAddr] = info;

      final handshake = json.encode({'peerId': _myId, 'pseudo': _myPseudo});
      _sendRaw(socket, Uint8List.fromList(utf8.encode(handshake)));

      _peerEventsCtrl.add(MeshPeerEvent(
        peerId: peerId,
        pseudo: pseudo,
        hopCount: 0,
        isConnected: true,
      ));

      debugPrint('[LocalWifi] connected to $peerId');

      _receiveLoop(socket, info);
    } catch (e) {
      debugPrint('[LocalWifi] connect to $peerId failed: $e');
    } finally {
      _connectingPeerIds.remove(peerId);
    }
  }

  // ── Receive Loop ────────────────────────────────────────────────────

  /// Écoute en permanence ce qui arrive sur le tuyau TCP, et reforme les
  /// messages complets à partir des octets bruts reçus (chaque message est
  /// précédé de sa longueur, pour savoir où il s'arrête).
  void _receiveLoop(Socket socket, _TcpPeerInfo info) {
    final buffer = <int>[];
    bool readingLength = true;
    int expectedLength = 0;

    socket.listen(
      (Uint8List data) {
        // Filet de sécurité : si `dispose()` a déjà fermé les contrôleurs
        // (par exemple pendant qu'on éteint l'app) mais qu'un paquet était
        // déjà en vol sur ce socket, on ne doit surtout pas planter en
        // essayant d'écrire dans un flux fermé — on abandonne juste
        // proprement ce socket devenu inutile.
        if (_incomingDataCtrl.isClosed || _peerEventsCtrl.isClosed) {
          socket.destroy();
          return;
        }
        buffer.addAll(data);

        while (true) {
          if (readingLength) {
            if (buffer.length < 4) break;
            expectedLength = (buffer[0] << 24) |
                (buffer[1] << 16) |
                (buffer[2] << 8) |
                buffer[3];
            buffer.removeRange(0, 4);
            readingLength = false;
          }

          if (buffer.length < expectedLength) break;

          final payload = Uint8List.fromList(buffer.sublist(0, expectedLength));
          buffer.removeRange(0, expectedLength);
          readingLength = true;

          if (info.peerId == null) {
            // Premier message reçu sur cette connexion : ce DOIT être la
            // carte de visite (handshake) — on ne sait pas encore qui
            // est ce pair.
            try {
              final handshake = json.decode(utf8.decode(payload))
                  as Map<String, dynamic>;
              info.peerId = handshake['peerId'] as String?;
              info.pseudo = handshake['pseudo'] as String?;
              if (info.peerId != null) {
                // Deux connexions simultanées vers le même pair peuvent
                // coexister (découverte mDNS + UDP en parallèle, ou
                // reconnexion avant expiration de l'ancien socket) —
                // `sendToPeer` choisirait alors arbitrairement entre les
                // deux, y compris un socket déjà fermé côté distant. On ne
                // garde que la connexion la plus récente par pair.
                final duplicates = _connectedPeers.entries
                    .where((e) => e.value.peerId == info.peerId && e.value.socket != socket)
                    .map((e) => e.key)
                    .toList();
                for (final key in duplicates) {
                  final stale = _connectedPeers.remove(key);
                  if (stale != null) {
                    stale.superseded = true;
                    stale.socket.destroy();
                  }
                }
                _lastBeaconSeen[info.peerId!] = DateTime.now();
                _peerEventsCtrl.add(MeshPeerEvent(
                  peerId: info.peerId!,
                  pseudo: info.pseudo ?? info.peerId!,
                  hopCount: 0,
                  isConnected: true,
                ));
              }
              debugPrint('[LocalWifi] handshake from ${info.peerId}');
            } catch (e) { debugPrint('[WiFi] $e'); }
          } else {
            // On sait déjà qui c'est : c'est un vrai message du mesh, on
            // le transmet au reste de l'app.
            debugPrint('[LocalWifi] ← ${info.peerId} payload=${payload.length}o');
            _incomingDataCtrl.add(MeshIncomingData(
              messageId: BleMeshProtocol.generateMessageId(),
              peerId: info.peerId ?? 'unknown',
              data: payload,
            ));
          }
        }
      },
      onDone: () {
        _onPeerDisconnected(socket, info);
      },
      onError: (e) {
        debugPrint('[LocalWifi] socket error: $e');
        _onPeerDisconnected(socket, info);
      },
    );
  }

  void _onPeerDisconnected(Socket socket, _TcpPeerInfo info) {
    if (info.superseded) {
      // Fermeture volontaire d'un doublon — le pair reste connecté via
      // l'autre socket, pas de faux événement de déconnexion.
      return;
    }
    if (info.peerId != null) {
      _peerEventsCtrl.add(MeshPeerEvent(
        peerId: info.peerId!,
        pseudo: info.pseudo ?? info.peerId!,
        isConnected: false,
      ));
    }
    _connectedPeers.removeWhere((k, v) => v.socket == socket);
  }

  // ── Send ────────────────────────────────────────────────────────────

  /// Envoie des données à un pair déjà connecté par ce chemin.
  /// Envoie [data] à [peerId]. Renvoie `false` si rien n'est parti.
  Future<bool> sendToPeer(String peerId, Uint8List data) async {
    final peer = _connectedPeers.values.where(
      (p) => p.peerId == peerId,
    );
    if (peer.isEmpty) {
      debugPrint('[LocalWifi] aucune connexion active pour $peerId');
      return false;
    }
    // Avaler l'erreur ici rendrait un échec d'écriture (socket déjà fermé
    // côté distant) invisible pour le suivi de santé des transports
    // (`MeshTransportService`), qui continuerait à croire ce transport
    // fiable et n'essaierait jamais un repli — d'où des messages qui
    // disparaissent silencieusement sans jamais remonter d'erreur ni de
    // relais alternatif.
    try {
      _sendRaw(peer.first.socket, data);
      return true;
    } catch (e) {
      debugPrint('[LocalWifi] écriture impossible vers $peerId: $e');
      return false;
    }
  }

  /// Colle une étiquette « voici combien d'octets vont suivre » devant les
  /// données, puis envoie le tout — pour que le destinataire sache
  /// exactement où s'arrête chaque message dans le flux continu du tuyau
  /// TCP.
  void _sendRaw(Socket socket, Uint8List data) {
    final lengthBytes = Uint8List.fromList([
      (data.length >> 24) & 0xFF,
      (data.length >> 16) & 0xFF,
      (data.length >> 8) & 0xFF,
      data.length & 0xFF,
    ]);
    socket.add(Uint8List.fromList([...lengthBytes, ...data]));
  }

  void dispose() {
    _beaconTimer?.cancel();
    _cleanupTimer?.cancel();
    _discoveryTimer?.cancel();
    _peerEventsCtrl.close();
    _incomingDataCtrl.close();
  }
}

/// Tout ce qu'on sait sur une connexion TCP en cours avec un pair — son
/// adresse, le tuyau (socket) lui-même, et son identité une fois la
/// poignée de main reçue.
class _TcpPeerInfo {
  final String address;
  final Socket socket;
  String? peerId;
  String? pseudo;

  /// Vrai si ce socket a été remplacé par une connexion plus récente vers
  /// le même pair — sa fermeture ne doit alors pas émettre un faux
  /// événement de déconnexion (le pair reste joignable via l'autre socket).
  bool superseded = false;

  _TcpPeerInfo({
    required this.address,
    required this.socket,
    this.peerId,
    this.pseudo,
  });
}
