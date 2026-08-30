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
import 'dart:math' show Random;
import 'package:flutter/foundation.dart';
import 'package:nsd/nsd.dart' as nsd;
import 'ble_mesh_protocol.dart';
import 'mesh_transport.dart';

/// Transport Wi-Fi local pour OURO PREP.
///
/// ## Découverte
/// - **mDNS** (via `nsd`) — enregistre un service `_ouroprep._tcp`
/// - **UDP broadcast** (fallback) — envoie des beacons toutes les 3s sur
///   `OURO_DISCOVERY_PORT` et écoute les beacons entrants
///
/// ## Communication
/// Sockets TCP bruts (`dart:io`) avec framing `[longueur 4 bytes][payload]`.
class LocalWifiTransport implements MeshTransport {
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


  // ── Contrat MeshTransport ────────────────────────────────────────
  //
  // Ce transport remplissait déjà cette forme ; ces quelques membres ne
  // font que l'écrire noir sur blanc, plus l'état et les capacités que
  // la couche supérieure devinait jusqu'ici.

  @override
  String get name => 'wifi';

  @override
  bool get isRunning => _isRunning;

  @override
  TransportState get state {
    if (!_isRunning) return TransportState.stopped;
    // `_subnetBroadcast == null` est l'exacte définition de « pas
    // d'interface réseau utilisable » posée par `_resolveBroadcastAddress`.
    if (_subnetBroadcast == null) return TransportState.unavailable;
    return _connectedPeers.isEmpty
        ? TransportState.searching
        : TransportState.active;
  }

  @override
  final TransportMetrics metrics = TransportMetrics();

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        // Le Wi-Fi local passe par TCP : la taille est bornée par la
        // mémoire, pas par la radio. 50 Mo est la limite déjà appliquée
        // aux pièces jointes en amont.
        maxPayloadBytes: 50 * 1024 * 1024,
        maxContentType: 0xFF,
        portePhotosEtFichiers: true,
        porteVoixEnDirect: true,
        coutEnergetique: 0.35,
      );

  @override
  Stream<MeshPeerEvent> get peerEvents => _peerEventsCtrl.stream;
  @override
  Stream<MeshIncomingData> get incomingData => _incomingDataCtrl.stream;

  ServerSocket? _serverSocket;
  RawDatagramSocket? _udpSocket;
  nsd.Discovery? _discovery;

  final Map<String, _TcpPeerInfo> _connectedPeers = {};

  // ══ ARBITRAGE DES CONNEXIONS SIMULTANÉES ═══════════════════════════
  //
  // Deux appareils qui se découvrent en même temps s'appellent en même
  // temps : il existe alors DEUX tuyaux entre eux, et il faut en fermer
  // un.
  //
  // ⚠️ LA VERSION PRÉCÉDENTE GARDAIT « LA PLUS RÉCENTE », ET C'EST CE
  // QUI RENDAIT LE RÉSEAU INSTABLE. « La plus récente » était jugée
  // localement, donc chacun désignait celle de l'autre : A fermait
  // A→B pendant que B fermait B→A. Les DEUX tuyaux tombaient, la balise
  // suivante relançait tout trois secondes plus tard, et le cycle
  // recommençait sans fin — d'où les `Software caused connection abort`
  // à répétition.
  //
  // La règle est désormais la même des deux côtés, et porte sur une
  // donnée que les deux connaissent : le nonce annoncé par chacun dans
  // sa carte de visite.
  //
  //     gagne la connexion ouverte par celui dont le nonce est le plus
  //     grand
  //
  // A et B appliquent la même comparaison sur les mêmes deux valeurs :
  // ils arrivent forcément à la même conclusion, et un seul des deux
  // ferme. Le nonce est tiré une fois au démarrage ; en cas d'égalité
  // (improbable sur huit octets), l'identifiant du pair départage, ce
  // qui garde la règle totale.
  late String _myNonce;

  /// Qui, de moi ou du pair, l'emporte ?
  ///
  /// Fonction pure : c'est ce qui permet de vérifier la symétrie de la
  /// règle dans un test, sans ouvrir la moindre connexion.
  @visibleForTesting
  static bool monNonceLEmporte(
      String monNonce, String nonceDuPair, String monId, String sonId) {
    final cmp = monNonce.compareTo(nonceDuPair);
    if (cmp != 0) return cmp > 0;
    return monId.compareTo(sonId) > 0;
  }
  final Map<String, DateTime> _lastBeaconSeen = {};
  Timer? _beaconTimer;
  Timer? _cleanupTimer;
  Timer? _discoveryTimer;

  /// Allume tout : ouvre une porte d'entrée pour les connexions (le
  /// serveur TCP), commence à écouter les cris « coucou » des autres
  /// (UDP), et s'annonce sur le réseau via mDNS.
  @override
  Future<void> start(String myId, String myPseudo) async {
    if (_isRunning) return;
    _isRunning = true;
    _myId = myId;
    _myPseudo = myPseudo;

    // Huit octets aléatoires, tirés une fois par session : c'est
    // l'arbitre des connexions simultanées.
    final alea = Random.secure();
    _myNonce = List.generate(8, (_) => alea.nextInt(256))
        .map((o) => o.toRadixString(16).padLeft(2, '0'))
        .join();

    await _startServer();
    await _resolveBroadcastAddress();
    await _startUdpDiscovery();
    await _startMdnsDiscovery();

    _cleanupTimer = Timer.periodic(const Duration(seconds: 5), (_) => _cleanupStalePeers());
    _beaconTimer = Timer.periodic(_beaconInterval, (_) => _sendBeacon());

    debugPrint('[LocalWifi] started on port $_listenPort id=$myId');
  }

  @override
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
    _echecsConsecutifs.clear();
    _pasAvant.clear();

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
    final info =
        _TcpPeerInfo(address: remoteAddr, socket: socket, sortante: false);
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
      _udpSocket!.listen(
        _onUdpEvent,
        // ⚠️ CE GESTIONNAIRE D'ERREUR N'EST PAS FACULTATIF.
        //
        // Un socket UDP est un flux : quand l'envoi d'un paquet échoue,
        // dart:io ne lève PAS l'exception à l'endroit de l'appel — il la
        // dépose dans ce flux, plus tard. Le `try/catch` qui entoure
        // `send()` dans `_sendBeacon` ne peut donc rien attraper : au
        // moment où l'erreur arrive, l'appel est terminé depuis
        // longtemps. Sans `onError` ici, elle remonte jusqu'au sommet et
        // s'affiche comme un plantage :
        //
        //   SocketException: Send failed
        //   (OS Error: Network is unreachable, errno = 101)
        //
        // Or ce n'est pas un plantage, c'est la situation NORMALE de
        // Droplet : le Wi-Fi est coupé, l'avion est activé, ou l'on
        // change de réseau — et la balise « coucou, je suis là » part
        // toutes les trois secondes quoi qu'il arrive. On note donc
        // l'incident et on continue : le Bluetooth prend le relais, et
        // le Wi-Fi repartira dès qu'un réseau reviendra.
        onError: (Object e) =>
            debugPrint('[LocalWifi] socket UDP indisponible: $e'),
        // Le flux qui se ferme n'est pas davantage une anomalie : Android
        // referme le socket de lui-même quand l'interface réseau
        // disparaît.
        cancelOnError: false,
      );
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

    // ⚠️ PAS DE REPLI SUR 255.255.255.255 ICI, ET C'EST TOUT LE CORRECTIF.
    //
    // L'ancienne version, faute d'avoir trouvé une interface, se rabattait
    // sur la diffusion générale. Or si aucune interface n'a d'adresse
    // privée, c'est précisément qu'il N'Y A PAS DE RÉSEAU : le noyau n'a
    // alors aucune route vers cette adresse et rejette chaque envoi avec
    // `ENETUNREACH`. La balise partant toutes les trois secondes, l'app
    // fabriquait une exception toutes les trois secondes, indéfiniment.
    //
    // `null` signifie donc « transport Wi-Fi hors service » — un ÉTAT, et
    // non une erreur à répéter. `_sendBeacon` s'abstient tant qu'il vaut
    // `null`, et retente une résolution de temps en temps pour détecter le
    // retour du réseau.
    _subnetBroadcast = null;
  }

  /// Envoie le petit cri « coucou, je suis là » à tout le réseau — répété
  /// toutes les 3 secondes tant que l'app tourne.
  /// Vrai quand on a renoncé à émettre faute de réseau utilisable.
  bool _reseauIndisponible = false;

  /// Nombre de cycles écoulés depuis la dernière tentative de
  /// re-résolution, quand le réseau est absent.
  int _cyclesDepuisTentative = 0;

  void _sendBeacon() {
    if (!_isRunning || _udpSocket == null) return;

    // ── Aucune interface utilisable : on se tait ────────────────────
    //
    // Émettre dans le vide ne sert à rien, réveille le processeur pour
    // rien, et produisait le flot d'exceptions `Network is unreachable`.
    // On re-teste malgré tout périodiquement, sinon le Wi-Fi pourrait
    // revenir sans que Droplet s'en aperçoive jamais.
    if (_subnetBroadcast == null) {
      if (!_reseauIndisponible) {
        _reseauIndisponible = true;
        debugPrint('[LocalWifi] aucune interface locale — balise suspendue');
      }
      // Une tentative toutes les ~10 périodes (30 s au rythme normal) :
      // assez souvent pour ne pas rater le retour du réseau, assez rare
      // pour ne rien coûter en veille.
      if (++_cyclesDepuisTentative >= 10) {
        _cyclesDepuisTentative = 0;
        unawaited(_resolveBroadcastAddress());
      }
      return;
    }

    if (_reseauIndisponible) {
      _reseauIndisponible = false;
      _cyclesDepuisTentative = 0;
      debugPrint('[LocalWifi] interface retrouvée — balise reprise');
    }

    try {
      final payload = utf8.encode(json.encode({
        'peerId': _myId,
        'pseudo': _myPseudo,
        'port': _listenPort,
      }));
      // Deux destinations, et chacune tentée SÉPARÉMENT.
      //
      // La diffusion de sous-réseau (192.168.1.255) est celle qui marche
      // partout ; la diffusion générale (255.255.255.255) rattrape les
      // configurations Android où la première ne porte pas. Mais cette
      // seconde est souvent non routable et échoue seule — les traiter
      // en bloc ferait déclarer le réseau perdu alors que la première
      // vient de passer.
      //
      // ⚠️ Jamais 0.0.0.0 en destination : cette adresse ne désigne
      // aucune machine, elle ne sert qu'à se mettre à l'écoute.
      var reussi = 0;
      for (final target in [
        _subnetBroadcast!,
        InternetAddress('255.255.255.255'),
      ]) {
        try {
          _udpSocket!.send(payload, target, _discoveryPort);
          reussi++;
        } catch (_) {
          // Silence volontaire : l'échec d'UNE destination est banal.
        }
      }

      // Aucune n'est passée : l'interface a disparu. On repasse à l'état
      // « pas de réseau », ce qui suspend la balise jusqu'à son retour.
      if (reussi == 0) {
        debugPrint('[LocalWifi] plus aucune destination joignable');
        _subnetBroadcast = null;
        return;
      }

      _beaconCount++;
      if (_beaconCount % 10 == 0) {
        debugPrint('[LocalWifi] beacon #$_beaconCount sent');
      }
    } catch (e) {
      // L'interface a disparu entre-temps. On repasse à l'état « pas de
      // réseau » plutôt que de réessayer en boucle avec une adresse qui
      // ne mène nulle part.
      debugPrint('[LocalWifi] balise impossible, réseau perdu: $e');
      _subnetBroadcast = null;
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
  // ══ RECUL ENTRE DEUX TENTATIVES ════════════════════════════════════
  //
  // `_connectToPeer` est rappelé à CHAQUE balise reçue, soit toutes les
  // trois secondes. Sans recul, un pair injoignable — pare-feu, adresse
  // périmée, appareil en veille — était rappelé indéfiniment toutes les
  // trois secondes, avec cinq secondes d'attente à chaque fois. C'est
  // une tempête de connexions qui ne sert à rien et vide la batterie.
  //
  // L'attente double à chaque échec, jusqu'à cinq minutes, et repart de
  // zéro dès qu'une connexion aboutit. Une part d'aléatoire s'y ajoute :
  // sans elle, vingt appareils ayant échoué en même temps réessaieraient
  // tous à la même seconde, indéfiniment.
  static const Duration _reculInitial = Duration(seconds: 3);
  static const Duration _reculMax = Duration(minutes: 5);

  final Map<String, int> _echecsConsecutifs = {};
  final Map<String, DateTime> _pasAvant = {};
  final Random _aleaRecul = Random();

  void _noterEchec(String peerId) {
    final echecs = (_echecsConsecutifs[peerId] ?? 0) + 1;
    _echecsConsecutifs[peerId] = echecs;

    var attente = _reculInitial * (1 << (echecs - 1).clamp(0, 10));
    if (attente > _reculMax) attente = _reculMax;
    // Jusqu'à 30 % de dispersion, pour désynchroniser les appareils.
    final gigue = Duration(
        milliseconds: _aleaRecul.nextInt(attente.inMilliseconds ~/ 3 + 1));

    _pasAvant[peerId] = DateTime.now().add(attente + gigue);
    debugPrint('[LocalWifi] $peerId injoignable ($echecs) — '
        'nouvelle tentative dans ${(attente + gigue).inSeconds}s');
  }

  void _noterSucces(String peerId) {
    _echecsConsecutifs.remove(peerId);
    _pasAvant.remove(peerId);
  }

  Future<void> _connectToPeer(
    String peerId, String pseudo, InternetAddress address, int port,
  ) async {
    if (_connectedPeers.values.any((p) => p.peerId == peerId)) return;

    final pasAvant = _pasAvant[peerId];
    if (pasAvant != null && DateTime.now().isBefore(pasAvant)) return;

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
        sortante: true,
        peerId: peerId,
        pseudo: pseudo,
      );
      _connectedPeers[remoteAddr] = info;

      final handshake = json.encode(
          {'peerId': _myId, 'pseudo': _myPseudo, 'nonce': _myNonce});
      _sendRaw(socket, Uint8List.fromList(utf8.encode(handshake)));

      _peerEventsCtrl.add(MeshPeerEvent(
        peerId: peerId,
        pseudo: pseudo,
        hopCount: 0,
        isConnected: true,
      ));

      debugPrint('[LocalWifi] connected to $peerId');
      _noterSucces(peerId);

      _receiveLoop(socket, info);
    } catch (e) {
      debugPrint('[LocalWifi] connect to $peerId failed: $e');
      _noterEchec(peerId);
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

          if (!info.poigneeRecue) {
            // Premier message d'une connexion : c'est TOUJOURS la carte
            // de visite, entrante comme sortante. L'ancien test portait
            // sur `peerId == null`, ce qui excluait les connexions
            // sortantes — leur carte de visite était alors traitée comme
            // un message du mesh.
            info.poigneeRecue = true;
            try {
              final handshake = json.decode(utf8.decode(payload))
                  as Map<String, dynamic>;
              info.peerId = (handshake['peerId'] as String?) ?? info.peerId;
              info.pseudo = (handshake['pseudo'] as String?) ?? info.pseudo;
              info.nonceDuPair = handshake['nonce'] as String?;
              if (info.peerId != null) {
                // Deux connexions simultanées vers le même pair peuvent
                // coexister (découverte mDNS + UDP en parallèle, ou
                // reconnexion avant expiration de l'ancien socket) —
                // `sendToPeer` choisirait alors arbitrairement entre les
                // deux, y compris un socket déjà fermé côté distant. On ne
                // garde que la connexion la plus récente par pair.
                final doublons = _connectedPeers.entries
                    .where((e) =>
                        e.value.peerId == info.peerId &&
                        e.value.socket != socket)
                    .toList();

                for (final e in doublons) {
                  final autre = e.value;

                  // Laquelle des deux garder ? La règle porte sur les
                  // nonces, que les deux appareils connaissent, et non
                  // sur l'ordre d'arrivée, que chacun voit différemment.
                  final nonceDuPair =
                      info.nonceDuPair ?? autre.nonceDuPair ?? '';
                  final jeGagne = monNonceLEmporte(
                    _myNonce,
                    nonceDuPair,
                    _myId,
                    info.peerId!,
                  );

                  // Si je gagne, c'est MA connexion sortante qui
                  // survit ; sinon c'est la sienne, que je vois comme
                  // entrante. On ferme l'autre — et le pair, appliquant
                  // la même règle aux mêmes valeurs, ferme exactement
                  // celle que je garde ouverte.
                  final aFermer = jeGagne
                      ? (info.sortante ? autre : info)
                      : (info.sortante ? info : autre);
                  final aGarder = identical(aFermer, info) ? autre : info;

                  aFermer.superseded = true;
                  _connectedPeers.removeWhere((_, v) => identical(v, aFermer));
                  aFermer.socket.destroy();

                  debugPrint('[LocalWifi] double connexion vers '
                      '${info.peerId} — on garde la '
                      '${aGarder.sortante ? "sortante" : "entrante"}');
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
    _guardSocket(socket);
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
  @override
  Future<bool> sendToPeer(String peerId, Uint8List data,
      {int type = 0x00, int priority = 2}) async {
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
    // ⚠️ `add` sur un socket déjà mort ne lève pas toujours ici : selon
    // le moment, l'échec est signalé PLUS TARD, par le `Future` que le
    // socket expose sous le nom `done`. C'est ce qui produisait, sans
    // que rien ne le rattrape :
    //
    //   SocketException: Software caused connection abort (errno = 103)
    //
    // Situation on ne peut plus banale ici : le pair s'éloigne, le
    // groupe Wi-Fi Direct se dissout, l'autre téléphone se met en
    // veille. Le `try` couvre l'échec immédiat ; `_guardSocket` couvre
    // l'échec différé.
    try {
      socket.add(Uint8List.fromList([...lengthBytes, ...data]));
    } catch (e) {
      debugPrint('[LocalWifi] écriture impossible sur le socket: $e');
    }
  }

  /// Neutralise les erreurs différées d'un socket TCP.
  ///
  /// Un socket expose un `Future done` qui se termine en ERREUR quand la
  /// liaison casse pendant une écriture. Personne ne l'attendant, cette
  /// erreur remontait jusqu'au sommet de l'app et s'affichait comme un
  /// plantage — alors que la déconnexion est déjà traitée proprement par
  /// `onDone`/`onError` de la lecture, qui préviennent le reste de l'app.
  /// On se contente donc de la noter.
  void _guardSocket(Socket socket) {
    unawaited(socket.done.catchError((Object e) {
      debugPrint('[LocalWifi] liaison interrompue: $e');
      return socket;
    }));
  }

  @override
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

  /// Vrai si c'est NOUS qui avons composé le numéro.
  ///
  /// Indispensable pour départager deux connexions simultanées : la
  /// règle d'arbitrage désigne un GAGNANT par son initiateur, et il faut
  /// donc savoir de quel côté on se trouve.
  final bool sortante;

  /// Le nonce annoncé par le pair dans sa carte de visite.
  String? nonceDuPair;

  /// Vrai une fois la carte de visite reçue.
  ///
  /// Remplace l'ancien test « `peerId == null` », qui ne fonctionnait que
  /// sur les connexions ENTRANTES : sur une connexion sortante, le
  /// `peerId` était déjà renseigné, si bien que la carte de visite du
  /// pair était prise pour un message ordinaire et injectée telle quelle
  /// dans le mesh — du JSON dont le premier octet, `{`, était lu comme
  /// un compteur de sauts.
  bool poigneeRecue = false;

  /// Vrai si ce socket a été remplacé par une connexion plus récente vers
  /// le même pair — sa fermeture ne doit alors pas émettre un faux
  /// événement de déconnexion (le pair reste joignable via l'autre socket).
  bool superseded = false;

  _TcpPeerInfo({
    required this.address,
    required this.socket,
    required this.sortante,
    this.peerId,
    this.pseudo,
  });
}
