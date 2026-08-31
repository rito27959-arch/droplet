// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Transport Tor pour Droplet.
//
// Utilise le proxy SOCKS5 local (géré par TorService) pour connecter
// des pairs via le réseau Tor. Chaque appareil peut fonctionner comme
// un hidden service (.onion).
//
// Intègre aussi les clients directory et mailbox pour :
// - S'enregistrer dans l'annuaire .onion au démarrage
// - Chercher des contacts par pseudo
// - Stocker/récupérer des messages dans la mailbox .onion
//
// Ne remplace PAS les transports mesh — les complète pour contacts distants.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tor/socks_socket.dart';

import 'ble_mesh_protocol.dart';
import 'mesh_transport.dart';
import 'tor_service.dart';
import 'tor_http_client.dart';
import 'onion_service.dart';
import 'qr_code_exchange.dart';
import 'directory_client.dart';
import 'mailbox_client.dart';

/// Transport Tor pour Droplet.
class TorTransport implements MeshTransport {
  final TorService _torService;

  bool _isRunning = false;
  String _myId = '';
  String _myPseudo = '';
  OnionIdentity? _myIdentity;

  /// Pairs connectés : peerId → onion address.
  final Map<String, String> _peerOnionAddresses = {};

  final Map<String, _TorPeerConnection> _connections = {};

  /// Client directory .onion — pour chercher/être trouvé par pseudo.
  DirectoryClient? _directoryClient;

  /// Client mailbox .onion — pour stocker/récupérer des messages async.
  MailboxClient? _mailboxClient;

  /// URL du serveur directory (à configurer avant start).
  String? directoryUrl;

  /// URL du serveur mailbox (à configurer avant start).
  String? mailboxUrl;

  /// Contacts trouvés dans l'annuaire (cache mémoire).
  final List<DirectoryContact> _directoryCache = [];

  final _peerEventsCtrl = StreamController<MeshPeerEvent>.broadcast();
  final _incomingDataCtrl = StreamController<MeshIncomingData>.broadcast();
  final _metrics = TransportMetrics();

  @override
  String get name => 'tor';

  @override
  bool get isRunning => _isRunning;

  @override
  TransportState get state {
    if (!_isRunning) return TransportState.stopped;
    if (!_torService.isConnected) return TransportState.unavailable;
    if (_connections.isEmpty) return TransportState.searching;
    return TransportState.active;
  }

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        maxPayloadBytes: 65536,
        maxContentType: 0xFF,
        portePhotosEtFichiers: true,
        porteVoixEnDirect: false,
        coutEnergetique: 0.6,
      );

  @override
  TransportMetrics get metrics => _metrics;

  @override
  Stream<MeshPeerEvent> get peerEvents => _peerEventsCtrl.stream;

  @override
  Stream<MeshIncomingData> get incomingData => _incomingDataCtrl.stream;

  /// Contacts trouvés dans l'annuaire (dernière recherche).
  List<DirectoryContact> get directoryCache => List.unmodifiable(_directoryCache);

  /// Vrai si le client directory est initialisé et prêt.
  bool get isDirectoryReady => _directoryClient != null;

  /// Vrai si le client mailbox est initialisé et prêt.
  bool get isMailboxReady => _mailboxClient != null;

  TorTransport(this._torService);

  @override
  Future<void> start(String myId, String myPseudo) async {
    if (_isRunning) return;
    _myId = myId;
    _myPseudo = myPseudo;
    _isRunning = true;

    // Charger l'identité Tor.
    _myIdentity = _torService.identity;
    if (_myIdentity != null) {
      debugPrint('[TorTransport] Démarré — .onion: ${_myIdentity!.shortOnion}');
    } else {
      debugPrint('[TorTransport] Démarré — pas encore d\'identité .onion');
    }

    // Initialiser les clients HTTP via le proxy SOCKS5.
    _initHttpClients();

    // S'enregistrer dans l'annuaire si les URLs sont configurées.
    _registerInDirectory();
  }

  /// Initialise les clients HTTP directory et mailbox via le proxy SOCKS5.
  void _initHttpClients() {
    if (_torService.proxyPort <= 0) {
      debugPrint('[TorTransport] Tor non prêt, clients HTTP retardés');
      return;
    }

    final torHttpClient = TorHttpClient(
      host: InternetAddress.loopbackIPv4.address,
      port: _torService.proxyPort,
    );

    if (directoryUrl != null) {
      _directoryClient = DirectoryClient(
        serverUrl: directoryUrl!,
        httpClient: torHttpClient,
      );
      debugPrint('[TorTransport] Client directory initialisé');
    }

    if (mailboxUrl != null) {
      _mailboxClient = MailboxClient(
        serverUrl: mailboxUrl!,
        httpClient: torHttpClient,
      );
      debugPrint('[TorTransport] Client mailbox initialisé');
    }
  }

  /// S'enregistre dans l'annuaire .onion avec notre identité.
  Future<void> _registerInDirectory() async {
    if (_directoryClient == null || _myIdentity == null) return;

    final success = await _directoryClient!.register(
      peerId: _myId,
      pseudo: _myPseudo,
      onionAddress: _myIdentity!.onionAddress,
      publicKey: _myIdentity!.publicKeyBase64,
    );

    if (success) {
      debugPrint('[TorTransport] Enregistré dans l\'annuaire');
    } else {
      debugPrint('[TorTransport] Échec enregistrement annuaire');
    }
  }

  // ── Méthodes publiques pour l'intégration avec l'app ──────────────

  /// Cherche des contacts par pseudo dans l'annuaire .onion.
  Future<List<DirectoryContact>> searchDirectory(String query) async {
    if (_directoryClient == null) {
      debugPrint('[TorTransport] Client directory non disponible');
      return [];
    }

    final results = await _directoryClient!.search(query);
    _directoryCache.clear();
    _directoryCache.addAll(results);
    return results;
  }

  /// Dépose un message chiffré dans la mailbox d'un contact distant.
  Future<String?> storeMailboxMessage({
    required String toPeerId,
    required String encryptedPayload,
  }) async {
    if (_mailboxClient == null) {
      debugPrint('[TorTransport] Client mailbox non disponible');
      return null;
    }

    return _mailboxClient!.store(
      fromPeerId: _myId,
      toPeerId: toPeerId,
      encryptedPayload: encryptedPayload,
    );
  }

  /// Récupère tous les messages en attente dans notre mailbox.
  Future<List<MailboxMessage>> fetchMailboxMessages() async {
    if (_mailboxClient == null) {
      debugPrint('[TorTransport] Client mailbox non disponible');
      return [];
    }

    return _mailboxClient!.fetchAll(_myId);
  }

  /// Supprime un message après l'avoir traité.
  Future<bool> acknowledgeMailboxMessage(String messageId) async {
    if (_mailboxClient == null) return false;
    return _mailboxClient!.acknowledge(_myId, messageId);
  }

  @override
  Future<void> stop() async {
    if (!_isRunning) return;
    _isRunning = false;

    // Se désinscrire de l'annuaire.
    await _unregisterFromDirectory();

    for (final conn in _connections.values) {
      await conn.close();
    }
    _connections.clear();
    _peerOnionAddresses.clear();

    _directoryClient?.close();
    _directoryClient = null;
    _mailboxClient?.close();
    _mailboxClient = null;

    debugPrint('[TorTransport] Arrêté');
  }

  /// Se désinscrit de l'annuaire avant l'arrêt.
  Future<void> _unregisterFromDirectory() async {
    if (_directoryClient == null) return;
    try {
      await _directoryClient!.unregister(_myId);
      debugPrint('[TorTransport] Désinscrit de l\'annuaire');
    } catch (e) {
      debugPrint('[TorTransport] Erreur désinscription: $e');
    }
  }

  /// Enregistre un pair scopé via QR code.
  void registerQrPeer(QrPeerData peerData) {
    _peerOnionAddresses[peerData.peerId] = peerData.onionAddress;
    debugPrint('[TorTransport] Peer QR enregistré: ${peerData.pseudo} '
        '(${peerData.onionAddress.substring(0, 12)}…)');

    // Notifier la découverte.
    _metrics.pairsDecouverts++;
    _peerEventsCtrl.add(MeshPeerEvent(
      peerId: peerData.peerId,
      pseudo: peerData.pseudo,
      isConnected: false,
    ));
  }

  /// Connecte à un pair via son adresse onion.
  Future<bool> connectToPeer(String peerId, {int port = 8080}) async {
    if (!_isRunning || !_torService.isConnected) return false;
    if (_connections.containsKey(peerId)) return true;

    final onionAddress = _peerOnionAddresses[peerId];
    if (onionAddress == null) {
      debugPrint('[TorTransport] Pas d\'adresse onion pour $peerId');
      return false;
    }

    try {
      debugPrint('[TorTransport] Connexion à $peerId via $onionAddress:$port');

      final socks = await SOCKSSocket.create(
        proxyHost: InternetAddress.loopbackIPv4.address,
        proxyPort: _torService.proxyPort,
      );
      await socks.connect();
      await socks.connectTo(onionAddress, port);

      // Envoyer hello avec notre identité.
      final hello = jsonEncode({
        'type': 'hello',
        'id': _myId,
        'pseudo': _myPseudo,
        'onion': _myIdentity?.onionAddress,
      });
      socks.write(hello);

      // Créer la connexion persistante.
      _createPeerConnection(peerId, socks);

      _metrics.pairsConnectes++;

      _peerEventsCtrl.add(MeshPeerEvent(
        peerId: peerId,
        pseudo: '',
        isConnected: true,
      ));

      debugPrint('[TorTransport] Connecté à $peerId');
      return true;
    } catch (e) {
      debugPrint('[TorTransport] Échec connexion vers $peerId: $e');
      _metrics.echecsConnexion++;
      return false;
    }
  }

  @override
  Future<bool> sendToPeer(String peerId, Uint8List data,
      {int type = 0x01, int priority = 0}) async {
    final conn = _connections[peerId];
    if (conn == null) {
      _metrics.echecsEnvoi++;
      return false;
    }

    try {
      // Header DRLP + version + type
      final header = Uint8List.fromList([0x44, 0x52, 0x4C, 0x50, 1, type & 0xFF]);
      final lengthBytes = ByteData(4)..setUint32(0, data.length, Endian.big);

      conn.socks.write(header);
      conn.socks.write(lengthBytes.buffer.asUint8List());
      conn.socks.write(data);

      _metrics.paquetsEnvoyes++;
      _metrics.octetsEnvoyes += data.length;
      return true;
    } catch (e) {
      debugPrint('[TorTransport] Erreur envoi vers $peerId: $e');
      _metrics.echecsEnvoi++;
      return false;
    }
  }

  void _createPeerConnection(String peerId, SOCKSSocket socks) {
    final conn = _TorPeerConnection(peerId: peerId, socks: socks);
    _connections[peerId] = conn;

    socks.listen(
      (data) {
        _metrics.paquetsRecus++;
        _metrics.octetsRecus += data.length;
        _incomingDataCtrl.add(MeshIncomingData(
          messageId: '${peerId}_${DateTime.now().millisecondsSinceEpoch}',
          peerId: peerId,
          data: Uint8List.fromList(data),
        ));
      },
      onError: (e) {
        debugPrint('[TorTransport] Erreur socket $peerId: $e');
        _removePeer(peerId);
      },
      onDone: () {
        _removePeer(peerId);
      },
    );
  }

  void _removePeer(String peerId) {
    if (_connections.remove(peerId) != null) {
      _metrics.pairsConnectes--;
      _peerEventsCtrl.add(MeshPeerEvent(
        peerId: peerId,
        pseudo: '',
        isConnected: false,
      ));
    }
  }

  @override
  void dispose() {
    stop();
    _peerEventsCtrl.close();
    _incomingDataCtrl.close();
  }
}

class _TorPeerConnection {
  final String peerId;
  final SOCKSSocket socks;

  _TorPeerConnection({required this.peerId, required this.socks});

  Future<void> close() async {
    try {
      await socks.close();
    } catch (_) {}
  }
}
