// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Client WebSocket pour le signaling WebRTC.
//
// Se connecte au DropletServer (Railway) pour relayer les offres SDP,
// réponses et candidats ICE pendant les appels audio/vidéo.
// ============================================================================

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

/// Événement de signaling reçu du serveur.
sealed class SignalingEvent {
  const SignalingEvent();
}

class PeerJoinedEvent extends SignalingEvent {
  const PeerJoinedEvent(this.peerId);
  final String peerId;
}

class PeerLeftEvent extends SignalingEvent {
  const PeerLeftEvent(this.peerId);
  final String peerId;
}

class OfferEvent extends SignalingEvent {
  const OfferEvent(this.fromPeerId, this.sdp);
  final String fromPeerId;
  final String sdp;
}

class AnswerEvent extends SignalingEvent {
  const AnswerEvent(this.fromPeerId, this.sdp);
  final String fromPeerId;
  final String sdp;
}

class IceCandidateEvent extends SignalingEvent {
  const IceCandidateEvent(this.fromPeerId, this.candidate);
  final String fromPeerId;
  final String candidate;
}

/// Client de signaling WebRTC.
class SignalingClient {
  SignalingClient({required this.serverUrl});

  final String serverUrl;
  WebSocketChannel? _channel;
  String? _roomId;
  String? _peerId;

  final _eventCtrl = StreamController<SignalingEvent>.broadcast();
  Stream<SignalingEvent> get events => _eventCtrl.stream;

  bool get isConnected => _channel != null;

  /// Rejoint une salle de signaling.
  Future<void> joinRoom(String roomId, String peerId) async {
    _roomId = roomId;
    _peerId = peerId;

    try {
      _channel = WebSocketChannel.connect(
        Uri.parse('$serverUrl/ws/$roomId'),
      );

      _channel!.stream.listen(
        (data) {
          try {
            final msg = jsonDecode(data as String) as Map<String, dynamic>;
            _handleMessage(msg);
          } catch (e) {
            debugPrint('[Signaling] Erreur parsing: $e');
          }
        },
        onDone: () {
          debugPrint('[Signaling] Connexion fermée');
          _channel = null;
        },
        onError: (e) {
          debugPrint('[Signaling] Erreur: $e');
          _channel = null;
        },
      );

      // Envoyer le join.
      _send({'type': 'join', 'peerId': peerId});
      debugPrint('[Signaling] Rejoint la salle $roomId');
    } catch (e) {
      debugPrint('[Signaling] Erreur connexion: $e');
    }
  }

  /// Quitte la salle.
  void leaveRoom() {
    _send({'type': 'leave'});
    _channel?.sink.close();
    _channel = null;
    _roomId = null;
    _peerId = null;
  }

  /// Envoie une offre SDP à un peer.
  void sendOffer(String toPeerId, String sdp) {
    _send({
      'type': 'offer',
      'from': _peerId,
      'to': toPeerId,
      'sdp': sdp,
    });
  }

  /// Envoie une réponse SDP à un peer.
  void sendAnswer(String toPeerId, String sdp) {
    _send({
      'type': 'answer',
      'from': _peerId,
      'to': toPeerId,
      'sdp': sdp,
    });
  }

  /// Envoie un candidat ICE à un peer.
  void sendIceCandidate(String toPeerId, String candidate) {
    _send({
      'type': 'ice-candidate',
      'from': _peerId,
      'to': toPeerId,
      'candidate': candidate,
    });
  }

  void _send(Map<String, dynamic> msg) {
    _channel?.sink.add(jsonEncode(msg));
  }

  void _handleMessage(Map<String, dynamic> msg) {
    final type = msg['type'] as String?;

    switch (type) {
      case 'joined':
        final peers = msg['peers'] as List<dynamic>? ?? [];
        for (final p in peers) {
          _eventCtrl.add(PeerJoinedEvent(p as String));
        }

      case 'offer':
        _eventCtrl.add(OfferEvent(
          msg['from'] as String,
          msg['sdp'] as String,
        ));

      case 'answer':
        _eventCtrl.add(AnswerEvent(
          msg['from'] as String,
          msg['sdp'] as String,
        ));

      case 'ice-candidate':
        _eventCtrl.add(IceCandidateEvent(
          msg['from'] as String,
          msg['candidate'] as String,
        ));

      case 'peer-left':
        _eventCtrl.add(PeerLeftEvent(msg['peerId'] as String));
    }
  }

  void dispose() {
    leaveRoom();
    _eventCtrl.close();
  }
}
