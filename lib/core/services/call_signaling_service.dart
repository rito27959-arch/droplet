// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Avant qu'un appel puisse commencer, les deux téléphones doivent se
// mettre d'accord sur PLEIN de petits détails techniques : comment se
// parler, quelle route réseau prendre, etc. C'est exactement ce que fait
// ce fichier — il n'envoie JAMAIS le son de l'appel lui-même (ça, c'est
// le travail de `webrtc_call_service.dart`), il envoie seulement les
// « papiers d'entente » nécessaires AVANT que le son puisse circuler :
//
//   - « Je voudrais t'appeler, voici mes infos techniques » (l'offre)
//   - « D'accord, voici les miennes » (la réponse)
//   - « Essaie cette route réseau précise » (les candidats ICE, plusieurs
//     petits essais de chemins possibles)
//   - « Je raccroche » (fin d'appel)
//
// Comme un facteur qui livre des lettres d'accord entre deux personnes
// avant qu'elles ne puissent enfin se téléphoner. Ces messages passent
// par le même chef d'orchestre mesh (`MeshTransportService`) que les
// messages normaux, mais avec des types spéciaux (0x10 à 0x13) pour que
// le reste de l'app sache que ce sont des messages d'appel et pas des
// messages de discussion.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'mesh_transport_service.dart';
import 'ble_mesh_protocol.dart';

/// Les quatre types de messages de signalisation d'appel — des codes
/// spéciaux ajoutés au protocole mesh (le Bluetooth utilise déjà des
/// codes en dessous de 0x10 pour les messages normaux).
const int kCallOffer = 0x10;
const int kCallAnswer = 0x11;
const int kCallIceCandidate = 0x12;
const int kCallHangUp = 0x13;

/// Erreur levée quand un appel n'est vraiment pas possible (par exemple,
/// la personne n'est joignable qu'en Bluetooth, trop lent pour la voix).
class CallTransportException implements Exception {
  final String message;
  CallTransportException(this.message);
  @override
  String toString() => 'CallTransportException: $message';
}

/// Un message de signalisation une fois décodé et prêt à être compris —
/// « quel type de message, de qui, avec quelles infos ».
class SignalingMessage {
  final int type;
  final String peerId;
  final Map<String, dynamic> data;

  const SignalingMessage({
    required this.type,
    required this.peerId,
    required this.data,
  });
}

/// Service de signalisation d'appel via le transport mesh.
///
/// Envoie et reçoit des messages CALL_OFFER, CALL_ANSWER, CALL_ICE_CANDIDATE
/// et CALL_HANGUP en réutilisant le `MeshTransportService`.
///
/// Les appels ne sont autorisés que si le pair cible est joignable
/// via TransportKind.localWifi (le BLE seul n'a pas le débit suffisant
/// pour l'audio temps réel).
class CallSignalingService {
  final MeshTransportService _transport;
  final _incomingCtrl = StreamController<SignalingMessage>.broadcast();
  StreamSubscription? _subscription;

  Stream<SignalingMessage> get incomingMessages => _incomingCtrl.stream;

  CallSignalingService(this._transport);

  /// Se met à l'écoute des messages de signalisation qui arrivent —
  /// comme décrocher un téléphone pour être prêt à entendre.
  void startListening() {
    _subscription?.cancel();
    _subscription = _transport.incomingData.listen(_onIncomingData);
  }

  void stopListening() {
    _subscription?.cancel();
  }

  /// Regarde chaque paquet de données brutes qui arrive du mesh : est-ce
  /// que ça ressemble à un message d'appel (type entre 0x10 et 0x13) ? Si
  /// oui, on le décode et on le republie proprement sur [incomingMessages].
  void _onIncomingData(MeshIncomingData data) {
    if (data.data.length < 2) return;
    // Format: [hopCount][type 0x10-0x13][json]
    final type = data.data[1];
    debugPrint('[Signaling] reçu type=0x${type.toRadixString(16)} peer=${data.peerId} len=${data.data.length}');
    if (type < kCallOffer || type > kCallHangUp) return;

    if (data.data.length < 3) return;
    try {
      final payload = utf8.decode(data.data.sublist(2));
      final json = jsonDecode(payload) as Map<String, dynamic>;
      debugPrint('[Signaling] routé vers incomingMessages');
      _incomingCtrl.add(SignalingMessage(
        type: type,
        peerId: data.peerId,
        data: json,
      ));
    } catch (e) { debugPrint('[Signaling] erreur décodage: $e'); }
  }

  /// Coupe court avec une erreur claire si le pair visé n'est PAS
  /// joignable en Wi-Fi direct — appelé avant chaque envoi de
  /// signalisation d'appel.
  void _requireDirectWifi(String peerId) {
    if (!canCallPeer(peerId)) {
      final peer = _transport.connectedPeers
          .where((p) => p.peerId == peerId);
      final platformInfo = peer.isNotEmpty
          ? ' (${peer.first.platform})'
          : '';
      throw CallTransportException(
        'Appel possible uniquement sur Wi‑Fi local ou Direct '
        '(0 saut). Le pair $peerId$platformInfo n\'est pas '
        'joignable.',
      );
    }
  }

  /// Est-ce qu'on peut appeler cette personne ? Il faut qu'elle soit
  /// directement à côté (0 « saut », pas relayée par quelqu'un d'autre) ET
  /// joignable en Wi-Fi (local ou Direct) — le Bluetooth seul est bien
  /// trop lent pour transporter de la voix en direct, un peu comme
  /// essayer de discuter par messages écrits pendant un appel vocal : ça
  /// ne suit pas.
  bool canCallPeer(String peerId) {
    final peers = _transport.connectedPeers.where((p) => p.peerId == peerId);
    if (peers.isEmpty) return false;
    final peer = peers.first;
    if (peer.hopCount != 0) return false;
    return peer.transports.contains(TransportKind.localWifi) ||
        peer.transports.contains(TransportKind.nativeP2P);
  }

  /// Fabrique le petit paquet à envoyer : un octet « nombre de sauts »
  /// (toujours 0, un appel n'est jamais relayé de proche en proche), un
  /// octet « type de message », puis les données en JSON.
  Uint8List _buildMessage(int type, Map<String, dynamic> data) {
    // Format : [hopCount=0][type][json] — hopCount=0 car appels jamais relayés
    final payload = utf8.encode(jsonEncode(data));
    return Uint8List.fromList([0, type, ...payload]);
  }

  /// Envoyer une offre d'appel (SDP offer). [participants], si fourni,
  /// transforme l'offre en invitation à un appel de groupe (liste complète
  /// des membres, pour que chaque destinataire puisse établir un maillage
  /// complet avec les autres) — absent pour un appel 1:1 classique.
  Future<void> sendOffer(String peerId, String sdp, {List<String>? participants}) async {
    _requireDirectWifi(peerId);
    await _transport.sendToPeer(
      peerId,
      _buildMessage(kCallOffer, {
        'sdp': sdp,
        'participants': ?participants,
      }),
      priority: 1, // high — signaling d'appel
    );
  }

  /// Répondre à une offre (SDP answer) — « d'accord, voici mes infos à
  /// moi aussi ».
  Future<void> sendAnswer(String peerId, String sdp) async {
    _requireDirectWifi(peerId);
    await _transport.sendToPeer(
      peerId,
      _buildMessage(kCallAnswer, {'sdp': sdp}),
      priority: 1, // high
    );
  }

  /// Envoyer un candidat ICE — un essai de chemin réseau précis à tenter,
  /// parmi plusieurs, pour que les deux téléphones trouvent la meilleure
  /// route pour se parler.
  Future<void> sendIceCandidate(
    String peerId,
    String candidate,
    String sdpMid,
    int sdpMLineIndex,
  ) async {
    _requireDirectWifi(peerId);
    await _transport.sendToPeer(
      peerId,
      _buildMessage(kCallIceCandidate, {
        'candidate': candidate,
        'sdpMid': sdpMid,
        'sdpMLineIndex': sdpMLineIndex,
      }),
      priority: 1, // high
    );
  }

  /// Envoyer une demande de raccrochage — on essaie poliment de prévenir
  /// l'autre, mais si ça échoue (l'autre est déjà parti, par exemple), on
  /// ne bloque pas l'app pour autant, on note juste l'erreur.
  Future<void> sendHangUp(String peerId) async {
    try {
      await _transport.sendToPeer(
        peerId,
        _buildMessage(kCallHangUp, {}),
        priority: 1, // high
      );
    } catch (e) { debugPrint('[Signaling] $e'); }
  }

  void dispose() {
    stopListening();
    _incomingCtrl.close();
  }
}
