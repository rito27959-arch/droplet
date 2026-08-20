// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est la version « appel à plusieurs » du fichier `webrtc_call_service.dart`
// — pour parler à 2, 3 ou 4 personnes en même temps, toujours SANS aucun
// serveur central.
//
// Le problème : sans serveur, il n'y a personne au milieu pour mélanger
// les voix de tout le monde et les redistribuer. La seule solution
// possible est que CHAQUE téléphone se connecte directement à TOUS les
// autres — comme si, dans un groupe de 4 amis qui veulent discuter sans
// passer par un haut-parleur central, chacun tendait une ficelle
// téléphonique séparée vers chacun des trois autres. Avec 4 personnes, ça
// fait 6 ficelles en tout. C'est pour ça qu'on plafonne à 4 participants
// maximum ([maxParticipants]) : avec plus de monde, le nombre de ficelles
// exploserait et ça deviendrait ingérable pour les téléphones.
//
// Pour éviter que deux personnes envoient chacune une « invitation » à
// l'autre en même temps (et se marchent dessus), une règle simple et sans
// discussion est utilisée : entre deux personnes, celle dont l'identifiant
// est alphabétiquement le plus petit est toujours celle qui envoie
// l'invitation en premier, l'autre attend et répond. Comme ça, tout le
// monde suit la même règle sans avoir besoin de se concerter.
//
// Ce fichier est volontairement complètement séparé de
// `webrtc_call_service.dart` (l'appel à deux) — aucun code ni donnée
// partagés, pour ne jamais risquer de casser les appels normaux en
// modifiant les appels de groupe.
// ============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'call_signaling_service.dart';

/// Un événement d'appel de groupe, toujours accompagné du participant
/// concerné (contrairement à l'appel 1:1, ici il faut savoir DE QUI on
/// parle).
sealed class GroupCallEvent {
  final String peerId;
  const GroupCallEvent(this.peerId);
}
class GroupCallParticipantConnecting extends GroupCallEvent {
  const GroupCallParticipantConnecting(super.peerId);
}
class GroupCallParticipantConnected extends GroupCallEvent {
  const GroupCallParticipantConnected(super.peerId);
}
class GroupCallParticipantFailed extends GroupCallEvent {
  const GroupCallParticipantFailed(super.peerId);
}
class GroupCallParticipantDisconnected extends GroupCallEvent {
  const GroupCallParticipantDisconnected(super.peerId);
}

/// Service d'appel de groupe P2P, **voix uniquement**, sans serveur.
///
/// ## Principe
/// Service entièrement séparé de [WebRtcCallService] (appels 1:1) — aucune
/// donnée ni code partagé, pour ne jamais risquer de régression sur le
/// chemin d'appel 1:1 déjà en production. Sans SFU/serveur de relais média,
/// la seule option décentralisée est un **maillage complet** : chaque
/// participant établit une connexion `RTCPeerConnection` directe avec
/// chaque autre participant. Ça ne passe pas à l'échelle — plafonné à
/// [maxParticipants].
///
/// ## Chorégraphie de connexion (sans coordinateur central)
/// - L'initiateur envoie une offre à chaque membre, avec la liste complète
///   des participants dans le payload (`participants`).
/// - Chaque membre qui reçoit cette offre répond à l'initiateur, PUIS
///   établit lui-même une connexion vers chaque autre membre de la liste
///   selon une règle déterministe : celui dont l'identifiant est
///   lexicographiquement le plus petit initie l'offre, l'autre attend et
///   répond. Ça garantit exactement une offre par paire, sans message de
///   coordination supplémentaire.
///
/// Audio uniquement : aucun rendu vidéo nécessaire, la lecture audio de
/// plusieurs flux distants se mélange nativement dès que les pistes sont
/// ajoutées à leurs `RTCPeerConnection` respectives.
class GroupWebrtcCallService {
  final CallSignalingService _signaling;

  /// Une connexion WebRTC séparée par participant — c'est littéralement
  /// « une ficelle par ami ».
  final Map<String, RTCPeerConnection> _peerConnections = {};
  MediaStream? _localStream;
  StreamSubscription<SignalingMessage>? _signalingSubscription;
  Set<String> _expectedPeerIds = {};

  final _eventCtrl = StreamController<GroupCallEvent>.broadcast();
  Stream<GroupCallEvent> get events => _eventCtrl.stream;

  /// Voir la note de portée du plan : sans serveur, le maillage complet ne
  /// passe pas à l'échelle au-delà de quelques participants.
  static const int maxParticipants = 4;

  static const _iceServers = [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {
      'urls': [
        'turn:openrelay.metered.ca:80',
        'turn:openrelay.metered.ca:443',
      ],
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ];

  GroupWebrtcCallService(this._signaling);

  /// Démarre un appel de groupe en tant qu'initiateur (« c'est moi qui
  /// invite tout le monde ») : on prépare mon micro, puis on tente de se
  /// connecter à chaque membre en même temps.
  Future<void> startGroupCall({required String myId, required List<String> memberPeerIds}) async {
    if (memberPeerIds.isEmpty) {
      throw ArgumentError('Aucun membre à appeler');
    }
    if (memberPeerIds.length + 1 > maxParticipants) {
      throw StateError('Maximum $maxParticipants participants par appel de groupe');
    }
    _expectedPeerIds = memberPeerIds.toSet();
    await _ensureLocalMedia();
    _signalingSubscription ??= _signaling.incomingMessages.listen(_handleSignalingMessage);

    for (final peerId in memberPeerIds) {
      unawaited(_connectToPeer(peerId, isInitiator: true, allParticipants: memberPeerIds)
          .catchError((e) => debugPrint('[GroupCall] échec connexion vers $peerId: $e')));
    }
  }

  /// Rejoint un appel de groupe suite à une invitation reçue (une offre
  /// qui contient la liste de tous les participants) : je réponds à celui
  /// qui m'a invité, puis, selon la règle du « plus petit identifiant
  /// invite en premier », je me connecte moi-même aux autres membres si
  /// c'est à moi d'initier.
  Future<void> joinGroupCall({
    required String myId,
    required String fromPeerId,
    required String offerSdp,
    required List<String> allParticipants,
  }) async {
    _expectedPeerIds = allParticipants.where((id) => id != myId).toSet();
    await _ensureLocalMedia();
    _signalingSubscription ??= _signaling.incomingMessages.listen(_handleSignalingMessage);

    await _connectToPeer(fromPeerId, isInitiator: false, remoteOfferSdp: offerSdp);

    for (final peerId in _expectedPeerIds) {
      if (peerId == fromPeerId) continue;
      if (myId.compareTo(peerId) < 0) {
        unawaited(_connectToPeer(peerId, isInitiator: true)
            .catchError((e) => debugPrint('[GroupCall] échec connexion vers $peerId: $e')));
      }
      // Sinon : on attend que ce pair nous envoie son offre (règle
      // symétrique de son côté).
    }
  }

  /// Allume le micro une seule fois (si déjà fait pour un participant, on
  /// réutilise le même flux audio pour tous les autres).
  Future<void> _ensureLocalMedia() async {
    if (_localStream != null) return;
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echo_cancellation': true,
        'noise_suppression': true,
        'auto_gain_control': true,
      },
      'video': false,
    });
  }

  /// Établit UNE connexion WebRTC vers UN participant précis — que ce
  /// soit en envoyant l'invitation (initiateur) ou en y répondant.
  Future<void> _connectToPeer(
    String peerId, {
    required bool isInitiator,
    String? remoteOfferSdp,
    List<String>? allParticipants,
  }) async {
    if (_peerConnections.containsKey(peerId)) return;
    _eventCtrl.add(GroupCallParticipantConnecting(peerId));

    final pc = await createPeerConnection({'iceServers': _iceServers});
    _peerConnections[peerId] = pc;

    pc.onIceCandidate = (RTCIceCandidate candidate) {
      final c = candidate.candidate;
      if (c == null || c.isEmpty) return;
      unawaited(_signaling.sendIceCandidate(peerId, c, candidate.sdpMid ?? '', candidate.sdpMLineIndex ?? 0)
          .catchError((e) => debugPrint('[GroupCall] échec envoi candidat ICE ($peerId): $e')));
    };

    pc.onIceConnectionState = (RTCIceConnectionState state) {
      switch (state) {
        case RTCIceConnectionState.RTCIceConnectionStateConnected:
        case RTCIceConnectionState.RTCIceConnectionStateCompleted:
          _eventCtrl.add(GroupCallParticipantConnected(peerId));
          break;
        case RTCIceConnectionState.RTCIceConnectionStateFailed:
          _eventCtrl.add(GroupCallParticipantFailed(peerId));
          break;
        case RTCIceConnectionState.RTCIceConnectionStateDisconnected:
        case RTCIceConnectionState.RTCIceConnectionStateClosed:
          _eventCtrl.add(GroupCallParticipantDisconnected(peerId));
          break;
        default:
          break;
      }
    };

    for (final track in _localStream!.getAudioTracks()) {
      await pc.addTrack(track, _localStream!);
    }

    if (isInitiator) {
      final offer = await pc.createOffer();
      await pc.setLocalDescription(offer);
      await _signaling.sendOffer(peerId, offer.sdp!, participants: allParticipants ?? _expectedPeerIds.toList());
    } else {
      final offer = RTCSessionDescription(remoteOfferSdp!, 'offer');
      await pc.setRemoteDescription(offer);
      final answer = await pc.createAnswer();
      await pc.setLocalDescription(answer);
      await _signaling.sendAnswer(peerId, answer.sdp!);
    }
  }

  /// Reçoit un message de signalisation venant de N'IMPORTE LEQUEL des
  /// participants attendus, et l'aiguille vers le bon traitement.
  void _handleSignalingMessage(SignalingMessage msg) {
    // Listener synchrone actif dès qu'un appel de groupe démarre : un cast
    // raté sur des données malformées venant d'un pair (autre version de
    // l'app, message tronqué) doit être avalé ici, pas remonter comme
    // exception non rattrapée du Stream.
    try {
      if (!_expectedPeerIds.contains(msg.peerId)) return;
      switch (msg.type) {
        case kCallOffer:
          final sdp = msg.data['sdp'] as String?;
          if (sdp != null && !_peerConnections.containsKey(msg.peerId)) {
            unawaited(_connectToPeer(msg.peerId, isInitiator: false, remoteOfferSdp: sdp)
                .catchError((e) => debugPrint('[GroupCall] échec réponse à ${msg.peerId}: $e')));
          }
          break;
        case kCallAnswer:
          unawaited(_handleAnswer(msg.peerId, msg.data));
          break;
        case kCallIceCandidate:
          unawaited(_handleIceCandidate(msg.peerId, msg.data));
          break;
        case kCallHangUp:
          unawaited(_removeParticipant(msg.peerId, notifyEvent: true));
          break;
      }
    } catch (e) {
      debugPrint('[GroupCall] message de signalisation invalide ignoré (${msg.peerId}): $e');
    }
  }

  Future<void> _handleAnswer(String peerId, Map<String, dynamic> data) async {
    final pc = _peerConnections[peerId];
    if (pc == null) return;
    try {
      final sdp = data['sdp'] as String;
      await pc.setRemoteDescription(RTCSessionDescription(sdp, 'answer'));
    } catch (e) {
      debugPrint('[GroupCall] erreur réponse SDP ($peerId): $e');
    }
  }

  Future<void> _handleIceCandidate(String peerId, Map<String, dynamic> data) async {
    final pc = _peerConnections[peerId];
    if (pc == null) return;
    try {
      final c = data['candidate'] as String?;
      if (c == null || c.isEmpty) return;
      await pc.addCandidate(RTCIceCandidate(c, data['sdpMid'] as String?, data['sdpMLineIndex'] as int?));
    } catch (e) {
      debugPrint('[GroupCall] erreur candidat ICE ($peerId): $e');
    }
  }

  /// Coupe/rétablit mon micro pour TOUT le monde en même temps (une
  /// seule piste audio, partagée par toutes les connexions).
  void toggleMute() {
    if (_localStream == null) return;
    for (final track in _localStream!.getAudioTracks()) {
      track.enabled = !track.enabled;
    }
  }

  bool _speakerOn = false;
  Future<void> toggleSpeaker() async {
    _speakerOn = !_speakerOn;
    await Helper.setSpeakerphoneOn(_speakerOn);
  }

  /// Retire un participant de l'appel (moi qui l'exclus, ou lui qui part).
  Future<void> removeParticipant(String peerId) async {
    try {
      await _signaling.sendHangUp(peerId);
    } catch (e) {
      debugPrint('[GroupCall] échec hangup vers $peerId: $e');
    }
    await _removeParticipant(peerId, notifyEvent: true);
  }

  Future<void> _removeParticipant(String peerId, {required bool notifyEvent}) async {
    final pc = _peerConnections.remove(peerId);
    _expectedPeerIds.remove(peerId);
    if (pc != null) {
      try {
        await pc.close();
      } catch (e) {
        debugPrint('[GroupCall] erreur fermeture connexion $peerId: $e');
      }
    }
    if (notifyEvent) _eventCtrl.add(GroupCallParticipantDisconnected(peerId));
  }

  /// Raccroche pour tout le monde d'un coup et libère micro + connexions.
  Future<void> hangUpAll() async {
    await _signalingSubscription?.cancel();
    _signalingSubscription = null;

    for (final peerId in _peerConnections.keys.toList()) {
      try {
        await _signaling.sendHangUp(peerId);
      } catch (e) {
        debugPrint('[GroupCall] échec hangup vers $peerId: $e');
      }
      final pc = _peerConnections.remove(peerId);
      try {
        await pc?.close();
      } catch (e) {
        debugPrint('[GroupCall] erreur fermeture connexion $peerId: $e');
      }
    }

    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await track.stop();
      }
      _localStream = null;
    }
    _expectedPeerIds.clear();
  }

  void dispose() {
    unawaited(_signalingSubscription?.cancel());
    _eventCtrl.close();
  }
}
