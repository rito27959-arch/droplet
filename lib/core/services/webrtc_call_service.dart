// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est ici que se passe le VRAI appel — le son (et l'image, si vidéo) qui
// voyage en direct entre les deux téléphones. `call_signaling_service.dart`
// s'occupait juste des « papiers d'entente » avant l'appel ; celui-ci
// s'occupe de faire vraiment circuler la voix, en utilisant une technologie
// qui s'appelle WebRTC (la même que Google Meet, Discord, etc. utilisent).
//
// Analogie : imagine que deux personnes veulent se parler avec deux
// gobelets reliés par une ficelle. Avant de tendre la ficelle, il faut
// savoir où est l'autre personne exactement (c'est la signalisation,
// gérée ailleurs). Ce fichier, lui, tend la ficelle, fait passer le son
// dedans, et la coupe proprement à la fin de l'appel.
//
// Notes importantes qui restent vraies dans ce fichier :
//   - Il n'y a AUCUN serveur central qui relaie le son — l'appel reste
//     toujours direct entre les deux téléphones (esprit « sans serveur »
//     de Droplet).
//   - Un service « STUN » public (juste une boussole, pas un relais) est
//     utilisé pour aider les deux téléphones à se trouver, même sur le
//     même Wi-Fi — sans ça, certains réseaux bloquent la découverte
//     directe.
// ============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_signaling_service.dart';

/// Les différents événements qu'un appel peut vivre — un peu comme les
/// étapes d'un appel téléphonique classique : ça sonne, ça décroche, ça
/// coupe, etc.
sealed class CallEvent {
  const CallEvent();
}
class CallConnecting extends CallEvent {
  const CallConnecting();
}
class CallConnected extends CallEvent {
  const CallConnected();
}
class CallFailed extends CallEvent {
  final String reason;
  const CallFailed(this.reason);
}
class CallDisconnected extends CallEvent {
  const CallDisconnected();
}
class CallRemoteHangUp extends CallEvent {
  const CallRemoteHangUp();
}
/// Petites statistiques en direct de la qualité de l'appel (latence,
/// débit, volume) — pour éventuellement afficher un petit indicateur de
/// qualité de connexion à l'écran.
class CallStatsUpdated extends CallEvent {
  final int latencyMs;
  final int bitrateKbps;
  final double audioLevel;
  const CallStatsUpdated({
    required this.latencyMs,
    required this.bitrateKbps,
    required this.audioLevel,
  });
}

class VideoAdded extends CallEvent {
  const VideoAdded();
}
class VideoRemoved extends CallEvent {
  const VideoRemoved();
}

/// Service d'appel vocal P2P basé sur WebRTC avec support vidéo.
///
/// ## Principe
/// - Utilise `webrtc_interface` via `dart_webrtc` pour créer une
///   `RTCPeerConnection`.
/// - Pas de serveur TURN (aucun relais média — l'appel reste direct entre
///   les deux appareils, cohérent avec l'esprit "pas de serveur central").
///   Un serveur STUN public est en revanche nécessaire même sur le même
///   réseau Wi-Fi : Android/iOS masquent par défaut les candidats ICE
///   "host" derrière un nom mDNS `.local`, dont la résolution échoue sur de
///   nombreux réseaux réels (isolation clients, mDNS bloqué par le routeur,
///   etc.) — sans STUN pour obtenir un candidat "srflx", l'appel échoue même
///   entre deux appareils physiquement sur le même Wi-Fi.
/// - Audio + Vidéo (toggleable).
/// - La signalisation (échange SDP + ICE) passe par `CallSignalingService`.
class WebRtcCallService {
  final CallSignalingService _signaling;
  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription? _signalingSubscription;

  final _eventCtrl = StreamController<CallEvent>.broadcast();
  Stream<CallEvent> get events => _eventCtrl.stream;

  Timer? _statsTimer;
  String? _currentPeerId;

  // Les "renderers" sont les petits écrans internes de WebRTC qui savent
  // afficher le flux vidéo local (ma propre caméra) et distant (l'autre
  // personne) — comme deux cadres photo qui se mettent à jour en direct.
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCVideoRenderer get localRenderer => _localRenderer;
  RTCVideoRenderer get remoteRenderer => _remoteRenderer;

  WebRtcCallService(this._signaling) {
    _initRenderers();
  }

  Future<void> _initRenderers() async {
    await _localRenderer.initialize();
    await _remoteRenderer.initialize();
  }

  /// Démarrer un appel sortant : je crée ma « proposition » (l'offre
  /// SDP, la carte d'identité technique de mon flux audio/vidéo), je
  /// l'envoie à l'autre, et je me mets à l'écoute de sa réponse.
  Future<void> startCall(String peerId) async {
    _currentPeerId = peerId;
    _eventCtrl.add(const CallConnecting());

    await _initPeerConnection();
    await _startLocalMedia();

    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    await _signaling.sendOffer(peerId, offer.sdp!);

    _signalingSubscription = _signaling.incomingMessages.listen(
      (msg) => _handleSignalingMessage(peerId, msg),
    );

    _startStatsTimer();
  }

  /// Répondre à un appel entrant : je reçois la proposition de l'autre,
  /// je prépare la mienne en retour, et je réponds.
  Future<void> answerCall(String peerId, String offerSdp) async {
    _currentPeerId = peerId;
    _eventCtrl.add(const CallConnecting());

    await _initPeerConnection();
    await _startLocalMedia();

    final offer = RTCSessionDescription(offerSdp, 'offer');
    await _pc!.setRemoteDescription(offer);

    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    await _signaling.sendAnswer(peerId, answer.sdp!);

    _signalingSubscription = _signaling.incomingMessages.listen(
      (msg) => _handleSignalingMessage(peerId, msg),
    );

    _startStatsTimer();
  }

  /// Serveurs ICE — STUN publics + TURN de secours pour les NAT symétriques.
  /// Les serveurs TURN ne sont utilisés qu'en dernier recours quand la
  /// connexion directe P2P échoue (NAT symétrique des deux côtés).
  /// FreeSTUN/CoTURN publics — à remplacer par des instances privées
  /// en production pour la fiabilité et la performance.
  static const _iceServers = [
    // STUN — découverte d'adresse publique
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {'urls': 'stun:stun.freevoip.com:3478'},
    // TURN — relais media pour NAT symétrique
    {
      'urls': [
        'turn:openrelay.metered.ca:80',
        'turn:openrelay.metered.ca:443',
        'turn:openrelay.metered.ca:443?transport=tcp',
      ],
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
    {
      'urls': [
        'turn:relay1.expressturn.com:3478',
      ],
      'username': 'eframe',
      'credential': 'eframe',
    },
  ];

  /// Prépare une nouvelle connexion WebRTC vide, prête à accueillir
  /// l'audio/vidéo et à écouter ce qui se passe (nouvelle route trouvée,
  /// connexion établie, flux vidéo reçu, etc.).
  Future<void> _initPeerConnection() async {
    // Filet de sécurité : si un appel précédent a échoué avant d'atteindre
    // hangUp() proprement (ex. exception non rattrapée pendant la
    // négociation ICE), _pc/_localStream restent ouverts et gardent le
    // micro/la caméra capturés — un appel suivant échouerait alors
    // systématiquement sur getUserMedia. On nettoie avant de recréer.
    if (_pc != null) {
      try {
        if (_localStream != null) {
          for (final track in _localStream!.getTracks()) {
            await track.stop();
          }
          _localStream = null;
        }
        await _pc!.close();
      } catch (e) {
        debugPrint('[WebRTC] nettoyage connexion précédente: $e');
      }
      _pc = null;
    }

    _pc = await createPeerConnection({
      'iceServers': _iceServers,
    });

    // Chaque fois que WebRTC trouve un nouveau chemin réseau possible
    // (un « candidat ICE »), on le transmet immédiatement à l'autre
    // téléphone via la signalisation.
    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      if (_currentPeerId == null) return;
      final c = candidate.candidate;
      if (c == null || c.isEmpty) return;
      // `sendIceCandidate` lève si le pair perd son lien Wi-Fi direct
      // pendant la négociation ICE (fenêtre d'instabilité fréquente en
      // pratique) — ne doit jamais faire planter l'app pour un seul
      // candidat perdu, les autres candidats ICE suffisent souvent.
      unawaited(_signaling.sendIceCandidate(
        _currentPeerId!,
        c,
        candidate.sdpMid ?? '',
        candidate.sdpMLineIndex ?? 0,
      ).catchError((e) => debugPrint('[WebRTC] échec envoi candidat ICE: $e')));
    };

    // Suit l'état de la connexion réseau elle-même (pas l'appel côté
    // utilisateur) : connectée, échouée, coupée...
    _pc!.onIceConnectionState = (RTCIceConnectionState state) {
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _eventCtrl.add(const CallConnected());
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _eventCtrl.add(const CallFailed('Échec de la connexion ICE'));
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
          _eventCtrl.add(const CallDisconnected());
          break;
        default:
          break;
      }
    };

    // Quand l'autre personne active sa caméra en cours d'appel, son flux
    // vidéo arrive ici et on le branche sur l'écran distant.
    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.track.kind == 'video') {
        _remoteStream = event.streams.first;
        _remoteRenderer.srcObject = _remoteStream;
        _eventCtrl.add(const VideoAdded());
      }
    };
  }

  /// Allume le micro (et la caméra si demandé) et branche ce flux sur la
  /// connexion WebRTC, prêt à être envoyé à l'autre personne.
  Future<void> _startLocalMedia({bool withVideo = false}) async {
    final mediaConstraints = <String, dynamic>{
      'audio': <String, dynamic>{
        'echo_cancellation': true,
        'noise_suppression': true,
        'auto_gain_control': true,
      },
      'video': withVideo,
    };

    _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
    _localRenderer.srcObject = _localStream;

    for (final track in _localStream!.getAudioTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }
    if (withVideo) {
      for (final track in _localStream!.getVideoTracks()) {
        await _pc!.addTrack(track, _localStream!);
      }
    }
  }

  /// Reçoit un message de signalisation (réponse, candidat ICE, ou
  /// raccrochage) et l'aiguille vers le bon traitement — ignore tout
  /// message qui ne vient pas de la personne avec qui on est en appel.
  void _handleSignalingMessage(String expectedPeerId, SignalingMessage msg) {
    if (msg.peerId != expectedPeerId) return;

    switch (msg.type) {
      case kCallAnswer:
        _handleAnswer(msg.data);
        break;
      case kCallIceCandidate:
        _handleIceCandidate(msg.data);
        break;
      case kCallHangUp:
        _eventCtrl.add(const CallRemoteHangUp());
        break;
    }
  }

  Future<void> _handleAnswer(Map<String, dynamic> data) async {
    try {
      final sdp = data['sdp'] as String;
      final answer = RTCSessionDescription(sdp, 'answer');
      await _pc!.setRemoteDescription(answer);
    } catch (e) {
      _eventCtrl.add(CallFailed('Erreur réponse SDP: $e'));
    }
  }

  Future<void> _handleIceCandidate(Map<String, dynamic> data) async {
    try {
      final c = data['candidate'] as String?;
      if (c == null || c.isEmpty) return;
      final candidate = RTCIceCandidate(
        c,
        data['sdpMid'] as String?,
        data['sdpMLineIndex'] as int?,
      );
      await _pc!.addCandidate(candidate);
    } catch (e) { debugPrint('[WebRTC] $e'); }
  }

  /// Toutes les 5 secondes pendant l'appel, on demande à WebRTC ses
  /// statistiques internes (retard, débit, volume) pour pouvoir afficher
  /// un petit indicateur de qualité de connexion.
  void _startStatsTimer() {
    _statsTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_pc == null) return;
      try {
        final stats = await _pc!.getStats();
        int latencyMs = 0;
        int bitrateKbps = 0;
        double audioLevel = 0.0;

        for (final report in stats) {
          if (report.type == 'candidate-pair' &&
              report.values['state'] == 'succeeded') {
            final rtt = report.values['currentRoundTripTime'];
            if (rtt is num) {
              latencyMs = (rtt * 1000).round();
            }
          }
          if (report.type == 'inbound-rtp' &&
              report.values['kind'] == 'audio') {
            final br = report.values['bytesReceived'];
            if (br is num) {
              bitrateKbps = br ~/ 1000;
            }
            final al = report.values['audioLevel'];
            if (al is num) {
              audioLevel = al.toDouble();
            }
          }
        }

        _eventCtrl.add(CallStatsUpdated(
          latencyMs: latencyMs,
          bitrateKbps: bitrateKbps,
          audioLevel: audioLevel,
        ));
      } catch (e) { debugPrint('[WebRTC] $e'); }
    });
  }

  /// Couper/rétablir le micro.
  void toggleMute() {
    if (_localStream == null) return;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !track.enabled;
    }
  }

  bool _speakerOn = false;
  bool _videoEnabled = false;

  /// Bascule entre le haut-parleur et l'écouteur (comme mettre l'appel
  /// en mode « mains libres » ou non).
  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    await Helper.setSpeakerphoneOn(_speakerOn);
  }

  /// Active ou coupe la caméra en cours d'appel — si c'est la toute
  /// première fois qu'on l'allume, on doit d'abord demander l'accès à la
  /// caméra puis brancher ce nouveau flux vidéo sur l'appel en cours.
  Future<void> toggleVideo() async {
    _videoEnabled = !_videoEnabled;
    if (_localStream == null) return;

    final videoTracks = _localStream!.getVideoTracks();
    if (_videoEnabled) {
      if (videoTracks.isEmpty) {
        try {
          final stream = await navigator.mediaDevices.getUserMedia({
            'audio': false,
            'video': {
              'facingMode': 'user',
              'width': 640,
              'height': 480,
            },
          });
          for (final track in stream.getVideoTracks()) {
            await _pc!.addTrack(track, stream);
            _localStream!.addTrack(track);
          }
        } catch (e) {
          _videoEnabled = false;
          return;
        }
      } else {
        for (final track in videoTracks) {
          track.enabled = true;
        }
      }
      _eventCtrl.add(const VideoAdded());
    } else {
      for (final track in videoTracks) {
        track.enabled = false;
      }
      _eventCtrl.add(const VideoRemoved());
    }
  }

  /// Raccrocher : prévenir l'autre, éteindre micro/caméra, fermer la
  /// connexion WebRTC, et remettre les écrans à zéro.
  Future<void> hangUp() async {
    _statsTimer?.cancel();
    _signalingSubscription?.cancel();

    try {
      await _signaling.sendHangUp(_currentPeerId ?? '');
    } catch (e) { debugPrint('[WebRTC] $e'); }

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      _localStream = null;
    }

    _localRenderer.srcObject = null;
    _remoteRenderer.srcObject = null;
    _videoEnabled = false;

    if (_pc != null) {
      await _pc!.close();
      _pc = null;
    }

    _currentPeerId = null;
    _eventCtrl.add(const CallDisconnected());
  }

  void dispose() {
    _statsTimer?.cancel();
    _signalingSubscription?.cancel();
    _localRenderer.dispose();
    _remoteRenderer.dispose();
    _eventCtrl.close();
  }
}
