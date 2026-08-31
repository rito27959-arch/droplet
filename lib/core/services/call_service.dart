// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Service d'appels audio/vidéo pour Droplet.
//
// Intègre le SignalingClient (WebSocket → Railway) avec flutter_webrtc
// pour gérer les appels peer-to-peer via WebRTC.
//
// ── Comment ça marche ? ─────────────────────────────────────────────
//
// 1. L'appelant ouvre une salle sur DropletServer (WebSocket).
// 2. Le destinataire rejoint la même salle.
// 3. L'appelant crée une offre SDP et l'envoie via le signaling.
// 4. Le destinataire répond avec une réponse SDP.
// 5. Les candidats ICE sont échangés.
// 6. Une connexion WebRTC directe est établie (audio + vidéo).
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'signaling_client.dart';

/// État d'un appel.
enum CallState {
  idle,
  calling,
  ringing,
  connected,
  disconnected,
}

/// Service d'appels WebRTC pour Droplet.
class CallService {
  CallService({required this.signalingClient});

  final SignalingClient signalingClient;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  CallState _state = CallState.idle;
  String? _currentRoomId;
  String? _remotePeerId;

  final _stateCtrl = StreamController<CallState>.broadcast();
  final _remoteStreamCtrl = StreamController<MediaStream>.broadcast();

  CallState get state => _state;
  Stream<CallState> get stateStream => _stateCtrl.stream;
  Stream<MediaStream> get remoteStreamEvents => _remoteStreamCtrl.stream;
  MediaStream? get localStream => _localStream;
  MediaStream? get currentRemoteStream => _remoteStream;
  bool get isInCall => _state == CallState.connected;
  bool get isIdle => _state == CallState.idle;

  /// Initialise le service et écoute les événements de signaling.
  void init() {
    signalingClient.events.listen(_onSignalingEvent);
  }

  /// Lance un appel vers un peer.
  ///
  /// 1. Rejoint une salle unique (room ID basée sur les deux peer IDs).
  /// 2. Crée le peer connection WebRTC.
  /// 3. Ajoute le stream local (caméra + micro).
  /// 4. Crée et envoie une offre SDP.
  Future<void> startCall(String myPeerId, String remotePeerId) async {
    if (_state != CallState.idle) {
      debugPrint('[CallService] Déjà en appel');
      return;
    }

    _remotePeerId = remotePeerId;
    _setState(CallState.calling);

    // Créer un ID de salle unique (ordre alphabetique pour cohérence).
    final peers = [myPeerId, remotePeerId]..sort();
    _currentRoomId = 'call_${peers[0]}_${peers[1]}';

    // Rejoindre la salle de signaling.
    await signalingClient.joinRoom(_currentRoomId!, myPeerId);

    // Créer le peer connection.
    await _createPeerConnection();

    // Ajouter le stream local.
    await _addLocalStream();

    // Créer l'offre SDP.
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });

    await _peerConnection!.setLocalDescription(offer);

    // Envoyer l'offre via signaling.
    signalingClient.sendOffer(remotePeerId, offer.sdp ?? '');
    debugPrint('[CallService] Offre envoyée vers $remotePeerId');
  }

  /// Répond à un appel entrant.
  Future<void> answerCall(String myPeerId, String remotePeerId) async {
    if (_state != CallState.ringing) {
      debugPrint('[CallService] Pas d\'appel en attente');
      return;
    }

    _remotePeerId = remotePeerId;
    _setState(CallState.connected);

    // Le peer connection est déjà créé dans _handleOffer.
    // Créer et envoyer la réponse SDP.
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);

    signalingClient.sendAnswer(remotePeerId, answer.sdp ?? '');
    debugPrint('[CallService] Réponse envoyée vers $remotePeerId');
  }

  /// Met fin à l'appel en cours.
  Future<void> endCall() async {
    debugPrint('[CallService] Fin d\'appel');

    // Fermer le peer connection.
    await _peerConnection?.close();
    _peerConnection = null;

    // Fermer les streams.
    await _localStream?.dispose();
    _localStream = null;
    _remoteStream = null;

    // Quitter la salle de signaling.
    signalingClient.leaveRoom();

    _currentRoomId = null;
    _remotePeerId = null;
    _setState(CallState.idle);
  }

  /// Active/désactive le micro.
  Future<void> toggleMicrophone() async {
    if (_localStream == null) return;
    final audioTrack = _localStream!.getAudioTracks().firstOrNull;
    if (audioTrack != null) {
      audioTrack.enabled = !audioTrack.enabled;
      debugPrint('[CallService] Micro ${audioTrack.enabled ? "activé" : "désactivé"}');
    }
  }

  /// Active/désactive la caméra.
  Future<void> toggleCamera() async {
    if (_localStream == null) return;
    final videoTrack = _localStream!.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      videoTrack.enabled = !videoTrack.enabled;
      debugPrint('[CallService] Caméra ${videoTrack.enabled ? "activée" : "désactivée"}');
    }
  }

  /// Bascule entre caméra avant et arrière.
  Future<void> switchCamera() async {
    if (_localStream == null) return;
    final videoTrack = _localStream!.getVideoTracks().firstOrNull;
    if (videoTrack != null) {
      await Helper.switchCamera(videoTrack);
      debugPrint('[CallService] Caméra basculée');
    }
  }

  // ── Méthodes privées ──────────────────────────────────────────────

  Future<void> _createPeerConnection() async {
    final config = {
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        {'urls': 'stun:stun1.l.google.com:19302'},
      ],
      'sdpSemantics': 'plan-b',
    };

    _peerConnection = await createPeerConnection(config);

    _peerConnection!.onIceCandidate = (candidate) {
      if (_remotePeerId != null) {
        signalingClient.sendIceCandidate(
          _remotePeerId!,
          candidate.candidate ?? '',
        );
      }
    };

    _peerConnection!.onAddStream = (stream) {
      _remoteStream = stream;
      _remoteStreamCtrl.add(stream);
      debugPrint('[CallService] Stream distant reçu');
    };

    _peerConnection!.onIceConnectionState = (state) {
      debugPrint('[CallService] ICE state: $state');
      if (state == RTCIceConnectionState.RTCIceConnectionStateFailed ||
          state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        endCall();
      }
    };

    debugPrint('[CallService] Peer connection créée');
  }

  Future<void> _addLocalStream() async {
    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 640},
        'height': {'ideal': 480},
      },
    });

    _localStream = stream;
    await _peerConnection!.addStream(stream);
    debugPrint('[CallService] Stream local ajouté');
  }

  void _onSignalingEvent(SignalingEvent event) {
    switch (event) {
      case PeerJoinedEvent(:final peerId):
        debugPrint('[CallService] Peer rejoint la salle: $peerId');
        _remotePeerId = peerId;
        _setState(CallState.ringing);

      case PeerLeftEvent(:final peerId):
        debugPrint('[CallService] Peer quitté: $peerId');
        if (peerId == _remotePeerId) {
          endCall();
        }

      case OfferEvent(:final fromPeerId, :final sdp):
        debugPrint('[CallService] Offre reçue de $fromPeerId');
        _handleOffer(fromPeerId, sdp);

      case AnswerEvent(:final fromPeerId, :final sdp):
        debugPrint('[CallService] Réponse reçue de $fromPeerId');
        _handleAnswer(fromPeerId, sdp);

      case IceCandidateEvent(:final fromPeerId, :final candidate):
        _handleIceCandidate(fromPeerId, candidate);
    }
  }

  Future<void> _handleOffer(String fromPeerId, String sdp) async {
    _remotePeerId = fromPeerId;
    _setState(CallState.ringing);

    await _createPeerConnection();
    await _addLocalStream();

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(sdp, 'offer'),
    );
  }

  Future<void> _handleAnswer(String fromPeerId, String sdp) async {
    await _peerConnection?.setRemoteDescription(
      RTCSessionDescription(sdp, 'answer'),
    );
    _setState(CallState.connected);
    debugPrint('[CallService] Appel connecté avec $fromPeerId');
  }

  Future<void> _handleIceCandidate(String fromPeerId, String candidate) async {
    if (candidate.isEmpty) return;
    await _peerConnection?.addCandidate(
      RTCIceCandidate(candidate, null, null),
    );
  }

  void _setState(CallState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateCtrl.add(newState);
  }

  void dispose() {
    endCall();
    _stateCtrl.close();
    _remoteStreamCtrl.close();
  }
}
