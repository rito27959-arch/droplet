// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Ce fichier fait le lien entre le « cerveau » du mesh
// (`mesh_repository.dart`, qui gère le vrai réseau) et tout ce que
// l'utilisateur VOIT à l'écran (la liste des conversations, les bulles
// de messages, l'écran d'appel...). C'est ce qu'on appelle des
// « providers Riverpod » — des petites boîtes qui contiennent un
// morceau d'état de l'app (par exemple « la liste des messages » ou
// « est-ce qu'un appel est en cours ? ») et qui préviennent
// AUTOMATIQUEMENT tous les écrans concernés dès que ce morceau change.
//
// Analogie : imagine un tableau d'affichage électronique dans une gare.
// Le repository, c'est le train qui arrive avec de nouvelles infos ; ce
// fichier, c'est le tableau d'affichage qui se met à jour tout seul dès
// que le train est là — et chaque écran de l'app (la liste des
// conversations, la bulle d'un message, l'icône « en train d'écrire »)
// regarde ce tableau au lieu d'aller lui-même demander au train.
//
// Le fichier est organisé en grandes sections, séparées par des
// commentaires en bandeau (════) : le petit système de « toast »
// (messages qui apparaissent brièvement en bas de l'écran), les
// messages/fichiers envoyés, les appels individuels, les appels de
// groupe, la liste des pairs connectés, et la construction de la liste
// des conversations affichées à l'écran d'accueil.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/mesh_message.dart';
import '../models/voice_note_meta.dart';
import '../../features/chat/location_message.dart';
import '../services/nom_pair.dart';
import '../services/storage_service.dart';
import '../services/mesh_transport_service.dart';
import '../services/ble_mesh_protocol.dart';
import '../services/call_signaling_service.dart';
import '../services/webrtc_call_service.dart';
import '../services/call_ringer_service.dart';
import '../services/group_webrtc_call_service.dart';
import '../services/notification_service.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../repositories/mesh_repository.dart';
import '../../features/chat/animated_sticker.dart';

/// Description lisible d'un contenu de message pour les previews.
///
/// Les stickers animés ne doivent PAS afficher leur référence technique
/// (🎞tgs:fetes/confettis) dans la liste des conversations — on affiche
/// un label lisible à la place.
String _describeForPreview(MeshMessage last) {
  if (last.type == 'file') return VoiceNoteMeta.describeAttachment(last.fileName);
  if (AnimatedStickerCatalog.estUneReference(last.content)) {
    return '🎞 ${AnimatedStickerCatalog.nomLisible(last.content)}';
  }
  return LocationMessage.describe(last.content);
}

// ── Toast minimal (remplace mesh_toast de l'app éducative) ─────────────────
//
// Un « toast », c'est ce petit message qui apparaît brièvement en bas de
// l'écran (« Message envoyé », « Erreur »...) puis disparaît tout seul
// après 3 secondes — comme une petite pastille de pain qui saute hors du
// grille-pain puis qu'on range.

enum DropletToastType { info, success, warning, error }

class DropletToast {
  final String message;
  final DropletToastType type;
  const DropletToast(this.message, {this.type = DropletToastType.info});
}

final toastProvider = StateNotifierProvider<ToastNotifier, DropletToast?>((ref) {
  return ToastNotifier();
});

class ToastNotifier extends StateNotifier<DropletToast?> {
  ToastNotifier() : super(null);
  Timer? _timer;

  void show(String msg, {DropletToastType type = DropletToastType.info}) {
    _timer?.cancel();
    state = DropletToast(msg, type: type);
    _timer = Timer(const Duration(seconds: 3), () => state = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

// ── Providers mesh ─────────────────────────────────────────────────────────

/// La seule instance du repository mesh pour toute l'app — tout le monde
/// (liste de conversations, écran de chat, écran d'appel...) regarde
/// vers CE MÊME repository, jamais une copie.
final meshRepositoryProvider = Provider<MeshRepository>((ref) {
  final repo = MeshRepository();
  ref.onDispose(() => repo.dispose());
  return repo;
});

final meshMessagesProvider =
    StateNotifierProvider<MeshNotifier, List<MeshMessage>>((ref) {
  final repo = ref.watch(meshRepositoryProvider);
  void showToast(String msg, {DropletToastType type = DropletToastType.info}) {
    ref.read(toastProvider.notifier).show(msg, type: type);
  }
  return MeshNotifier(repo, showToast);
});

final meshStatsProvider = Provider<MeshStats>((ref) {
  final peers = ref.watch(meshPeerListProvider);
  return _buildRealStats(peers: peers);
});

/// Calcule les statistiques affichées sur l'écran de contribution
/// (combien de données distribuées, combien de fichiers relayés, etc.).
MeshStats _buildRealStats({List<ConnectedPeer> peers = const []}) {
  final messages = StorageService.getMessages();
  final relayedFiles = messages.where((m) => m.type == 'file').length;
  final totalMessages = messages.length;
  final estimatedGb = totalMessages * 0.001;
  final uniqueAuthors = messages.map((m) => m.authorPseudo).toSet().length;
  final bleCount = peers.where((p) => p.transports.contains(TransportKind.ble)).length;
  final wifiCount = peers.where((p) => p.transports.contains(TransportKind.localWifi)).length;
  final nativeCount = peers.where((p) => p.transports.contains(TransportKind.nativeP2P)).length;

  return MeshStats(
    distributedGb: double.parse(estimatedGb.toStringAsFixed(2)),
    relayedFiles: relayedFiles,
    helpedPeers: uniqueAuthors,
    totalPeers: peers.length,
    blePeers: bleCount,
    wifiPeers: wifiCount,
    nativePeers: nativeCount,
  );
}

/// Santé en temps réel du mesh (multi‑transport, fiabilité, ACK).
final meshHealthProvider = StreamProvider<MeshHealth>((ref) {
  final repo = ref.watch(meshRepositoryProvider);
  return repo.transport.healthEvents;
});

/// ACK d'un message spécifique.
final messageAckProvider = Provider.family<int, String>((ref, messageId) {
  final repo = ref.watch(meshRepositoryProvider);
  return repo.getAckCount(messageId);
});

/// Le gardien de TOUS les messages affichés dans l'app : envoie les
/// nouveaux messages/fichiers, suit leur statut (en cours, envoyé,
/// échoué), gère la « boîte d'attente » (outbox) pour les messages
/// tapés quand personne n'est connecté, et écoute tout ce qui arrive du
/// repository pour mettre à jour l'écran automatiquement.
class MeshNotifier extends StateNotifier<List<MeshMessage>> {
  final MeshRepository _repo;
  final void Function(String, {DropletToastType type}) _showToast;
  StreamSubscription<void>? _peerSub;
  StreamSubscription<String>? _ackSub;
  StreamSubscription<String>? _readSub;
  StreamSubscription<({String messageId, String emoji})>? _reactionSub;
  StreamSubscription<MeshMessage>? _newMessageSub;
  StreamSubscription<String>? _repairedSub;
  Timer? _readDelayTimer;

  /// Événements de réaction entrants (pour déclencher l'overlay côté UI).
  final _reactionEventCtrl = StreamController<({String messageId, String emoji})>.broadcast();
  Stream<({String messageId, String emoji})> get reactionEvents => _reactionEventCtrl.stream;

  /// Messages en attente d'envoi (0 pair connecté au moment du tap).
  final List<_OutboxEntry> _outbox = [];

  /// Génération de l'outbox — incémentée à chaque ajout. Permet de
  /// détecter si de nouveaux messages sont arrivés pendant qu'on vidait
  /// la file, et de relancer un flush si nécessaire.
  int _outboxGeneration = 0;

  /// Ajoute une entrée à l'outbox et incrémente la génération.
  void _addToOutbox(_OutboxEntry entry) {
    _outbox.add(entry);
    _outboxGeneration++;
  }

  MeshNotifier(this._repo, this._showToast) : super(StorageService.getMessages()) {
    _peerSub = _repo.peerEvents?.listen((_) => _flushOutbox());
    _ackSub = _repo.ackEvents.listen((messageId) {
      // Haptique de livraison : vibrer légèrement quand un message arrive
      // à destination. iMessage ne fait rien — on fait mieux.
      HapticFeedback.lightImpact();
      state = state.map((m) {
        if (m.id != messageId) return m;
        return m.copyWith(deliveryCount: _repo.getAckCount(messageId));
      }).toList();
    });
    _readSub = _repo.readEvents.listen((messageId) {
      HapticFeedback.mediumImpact();
      final now = DateTime.now();
      state = state.map((m) {
        if (m.id != messageId || m.readAt != null) return m;
        return m.copyWith(readAt: now);
      }).toList();
      unawaited(StorageService.updateMessageReadAt(messageId, now));
      // Messages éphémères : marquer la première lecture et démarrer le
      // timer de disparition.
      final msg = state.where((m) => m.id == messageId).firstOrNull;
      if (msg != null) _markFirstRead(msg);
    });
    _reactionSub = _repo.reactionEvents.listen((evt) {
      _reactionEventCtrl.add(evt);
    });
    _newMessageSub = _repo.newMessageEvents.listen((msg) {
      if (state.any((m) => m.id == msg.id)) return;
      state = [...state, msg];
    });

    // Un message reçu avant la clé de son auteur s'affiche « illisible » ;
    // dès que la clé arrive, le dépôt le répare et prévient ici, pour que
    // la bulle déjà à l'écran se remplace toute seule par le vrai texte.
    _repairedSub = _repo.repairedMessageEvents.listen((messageId) {
      final repaired = StorageService.getMessages()
          .where((m) => m.id == messageId)
          .firstOrNull;
      if (repaired == null) return;
      state = [
        for (final m in state) m.id == messageId ? repaired : m,
      ];
    });

    _loadOutbox();
    _startEphemeralChecker();
  }

  /// Charge la file d'attente persistée au démarrage — les messages
  /// qu'on n'avait pas réussi à envoyer avant la dernière fermeture de
  /// l'app, pour réessayer.
  void _loadOutbox() {
    final stored = StorageService.getOutbox();
    for (final entry in stored) {
      final kind = entry['kind'] as String?;
      if (kind == 'text') {
        _addToOutbox(_OutboxEntry(
          messageId: entry['id'] as String,
          kind: _OutboxKind.text,
          targetId: entry['targetId'] as String?,
          groupId: entry['groupId'] as String?,
        ));
      } else if (kind == 'file') {
        _addToOutbox(_OutboxEntry(
          messageId: entry['id'] as String,
          kind: _OutboxKind.file,
          targetId: entry['targetId'] as String?,
          groupId: entry['groupId'] as String?,
        ));
      }
    }
    if (_outbox.isNotEmpty) {
      debugPrint('[MeshNotifier] ${_outbox.length} messages en attente chargés');
      if (_repo.transport.connectedPeerCount > 0) _flushOutbox();
    }
  }

  // ── UNDO SEND ───────────────────────────────────────────────────
  //
  // iMessage permet d'annuler l'envoi dans les 2 premières secondes.
  // On fait pareil : le message reste dans un état « annulable » pendant
  // 2 secondes après l'envoi. Passé ce délai, il est trop tard.

  /// IDs des messages récemment envoyés et encore annulables.
  final Set<String> _undoableMessages = {};

  /// Vérifie si un message peut encore être annulé.
  bool canUndoSend(String messageId) => _undoableMessages.contains(messageId);

  /// Annule l'envoi d'un message : le supprime de l'état et de la base.
  /// Renvoie `true` si l'annulation a réussi.
  bool undoSend(String messageId) {
    if (!_undoableMessages.remove(messageId)) return false;
    state = state.where((m) => m.id != messageId).toList();
    unawaited(StorageService.deleteMessage(messageId));
    return true;
  }

  /// Enregistre un message comme annulable pendant 2 secondes.
  void _registerUndoable(String messageId) {
    _undoableMessages.add(messageId);
    Timer(const Duration(seconds: 2), () {
      _undoableMessages.remove(messageId);
    });
  }

  // ── MESSAGES ÉPHÉMÈRES ────────────────────────────────────────
  //
  // Quand un message a un `expiresInSeconds` défini et que le
  // destinataire le lit pour la première fois, un timer démarre.
  // Le message est supprimé quand le timer atteint la durée définie.
  // Un timer périodique vérifie les messages expirés toutes les 5 secondes.

  Timer? _ephemeralCheckTimer;

  /// Démarre le vérificateur périodique des messages éphémères.
  void _startEphemeralChecker() {
    _ephemeralCheckTimer?.cancel();
    _ephemeralCheckTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _purgeExpiredMessages(),
    );
  }

  /// Marque un message comme « première lecture » et planifie sa suppression.
  void _markFirstRead(MeshMessage message) {
    if (message.expiresInSeconds == null || message.firstReadAt != null) return;
    if (message.senderId == _repo.myId) return;
    final now = DateTime.now();
    state = state.map((m) {
      if (m.id != message.id) return m;
      return m.copyWith(firstReadAt: now);
    }).toList();
    unawaited(StorageService.updateMessageFirstReadAt(message.id, now));
  }

  /// Supprime tous les messages éphémères dont le délai est écoulé.
  void _purgeExpiredMessages() {
    final now = DateTime.now();
    final toDelete = <String>[];
    for (final m in state) {
      if (m.expiresInSeconds == null || m.firstReadAt == null) continue;
      final elapsed = now.difference(m.firstReadAt!).inSeconds;
      if (elapsed >= m.expiresInSeconds!) {
        toDelete.add(m.id);
      }
    }
    if (toDelete.isEmpty) return;
    state = state.where((m) => !toDelete.contains(m.id)).toList();
    for (final id in toDelete) {
      unawaited(StorageService.deleteMessage(id));
    }
  }

  // ── MESSAGE EDITING ─────────────────────────────────────────────
  //
  // iMessage permet de modifier un message après envoi. On fait pareil :
  // seul l'expéditeur peut modifier, et le badge « modifié » apparaît
  // dans la bulle.

  /// Modifie le contenu d'un message. Seul l'auteur peut le faire.
  /// Le badge « modifié » est affiché dans la bulle.
  void editMessage(String messageId, String newContent) {
    state = state.map((m) {
      if (m.id != messageId) return m;
      if (m.senderId != _repo.myId) return m;
      return m.copyWith(
        content: newContent,
        editedAt: DateTime.now(),
      );
    }).toList();
    // Persister en base.
    final msg = state.where((m) => m.id == messageId).firstOrNull;
    if (msg != null) {
      unawaited(StorageService.saveMessage(msg));
    }
  }

  /// Envoie un message texte (1:1 ou diffusion). Le message apparaît
  /// TOUT DE SUITE à l'écran avec un statut « en cours d'envoi », même
  /// avant que l'envoi réel ne soit confirmé — l'utilisateur n'attend
  /// jamais devant un écran vide.
  Future<void> sendMessage(String pseudo, String content,
      {String type = 'text', String? imageUrl, String? audioUrl, String? replyToId, String? targetId, String? effect, String? threadId}) async {
    // Messages éphémères : si la conversation a un timer, l'appliquer.
    final ephemeralTimer = targetId != null
        ? StorageService.getEphemeralTimer(targetId)
        : 0;
    final msg = MeshMessage(
      id: BleMeshProtocol.generateMessageId(),
      authorPseudo: pseudo,
      content: content,
      type: type,
      timestamp: DateTime.now(),
      senderId: _repo.myId,
      targetId: targetId,
      imageUrl: imageUrl,
      audioUrl: audioUrl,
      hopCount: MeshRepository.kDefaultHopCount,
      replyToId: replyToId,
      status: MessageStatus.sending,
      effect: effect,
      expiresInSeconds: ephemeralTimer > 0 ? ephemeralTimer : null,
      threadId: threadId,
    );

    await StorageService.saveMessage(msg);
    state = [...state, msg];

    if (_repo.transport.connectedPeerCount > 0) {
      try {
        await _repo.sendMessage(
          authorPseudo: pseudo,
          content: content,
          type: type,
          imageUrl: imageUrl,
          audioUrl: audioUrl,
          replyToId: replyToId,
          messageId: msg.id,
          targetId: targetId,
          effect: effect,
        );
        _setStatus(msg.id, MessageStatus.sent);
        _registerUndoable(msg.id);
      } catch (_) {
        _setStatus(msg.id, MessageStatus.failed);
        _showToast('Échec de l\'envoi du message', type: DropletToastType.error);
        final conv = targetId ?? 'broadcast';
        unawaited(NotificationService.showSendFailed(
          conversationId: conv,
          routePath: '/chat/$conv',
        ));
      }
    } else {
      _setStatus(msg.id, MessageStatus.pending);
      _addToOutbox(_OutboxEntry(messageId: msg.id, kind: _OutboxKind.text, targetId: targetId));
      unawaited(StorageService.saveOutbox({
        'id': msg.id, 'kind': 'text', 'targetId': targetId,
      }));
    }
  }

  /// Envoie un message dans un groupe (chiffré avec ma sender-key).
  Future<void> sendGroupMessage(String pseudo, String content, {
    required String groupId,
    String? replyToId,
    String? effect,
    String? threadId,
  }) async {
    final msg = MeshMessage(
      id: BleMeshProtocol.generateMessageId(),
      authorPseudo: pseudo,
      content: content,
      type: 'text',
      timestamp: DateTime.now(),
      senderId: _repo.myId,
      groupId: groupId,
      hopCount: MeshRepository.kDefaultHopCount,
      replyToId: replyToId,
      status: MessageStatus.sending,
      effect: effect,
      threadId: threadId,
    );

    await StorageService.saveMessage(msg);
    state = [...state, msg];

    if (_repo.transport.connectedPeerCount > 0) {
      try {
        await _repo.sendGroupMessage(
          groupId: groupId,
          content: content,
          replyToId: replyToId,
          messageId: msg.id,
          effect: effect,
        );
        _setStatus(msg.id, MessageStatus.sent);
      } catch (_) {
        _setStatus(msg.id, MessageStatus.failed);
        _showToast('Échec de l\'envoi du message', type: DropletToastType.error);
        unawaited(NotificationService.showSendFailed(
          conversationId: groupId,
          routePath: '/group/$groupId',
        ));
      }
    } else {
      _setStatus(msg.id, MessageStatus.pending);
      _addToOutbox(_OutboxEntry(messageId: msg.id, kind: _OutboxKind.text, groupId: groupId));
      unawaited(StorageService.saveOutbox({
        'id': msg.id, 'kind': 'text', 'groupId': groupId,
      }));
    }
  }

  /// Envoie un fichier (photo, document, message vocal) — même logique
  /// « apparaît tout de suite, statut mis à jour ensuite » que
  /// [sendMessage].
  Future<void> sendFile({
    required String pseudo,
    required String fileName,
    required Uint8List bytes,
    String mimeType = '',
    String? targetId,
    String? groupId,
    String? replyToId,
  }) async {
    final fileId = const Uuid().v4();
    final int hopCount = MeshRepository.kDefaultHopCount;

    final msg = MeshMessage(
      id: fileId,
      authorPseudo: pseudo,
      content: fileName,
      type: 'file',
      timestamp: DateTime.now(),
      senderId: _repo.myId,
      targetId: targetId,
      groupId: groupId,
      fileId: fileId,
      fileName: fileName,
      fileSize: bytes.length,
      fileMimeType: mimeType,
      replyToId: replyToId,
      hopCount: hopCount,
      status: MessageStatus.sending,
    );

    await StorageService.saveMessage(msg);
    state = [...state, msg];
    await StorageService.saveSharedFile(fileId: fileId, fileName: fileName, bytes: bytes);

    if (_repo.transport.connectedPeerCount > 0) {
      try {
        await _repo.sendFile(
          fileName: fileName,
          bytes: bytes,
          mimeType: mimeType,
          targetId: targetId,
          groupId: groupId,
          fileId: fileId,
          replyToId: replyToId,
        );
        _setStatus(msg.id, MessageStatus.sent);
      } catch (_) {
        _setStatus(msg.id, MessageStatus.failed);
        _showToast('Échec de l\'envoi du fichier', type: DropletToastType.error);
        final conv = groupId ?? targetId ?? 'broadcast';
        unawaited(NotificationService.showSendFailed(
          conversationId: conv,
          routePath: groupId != null ? '/group/$conv' : '/chat/$conv',
        ));
      }
    } else {
      _setStatus(msg.id, MessageStatus.pending);
      _addToOutbox(_OutboxEntry(messageId: fileId, kind: _OutboxKind.file, targetId: targetId, groupId: groupId));
      unawaited(StorageService.saveOutbox({
        'id': fileId, 'kind': 'file', 'targetId': targetId, 'groupId': groupId,
      }));
    }
  }

  /// Supprime un message localement (DB + état) — n'affecte que cet
  /// appareil, ne rappelle pas le message chez les destinataires.
  void deleteMessage(String messageId) {
    state = state.where((msg) => msg.id != messageId).toList();
    unawaited(StorageService.deleteMessage(messageId));
  }

  void toggleReaction(String messageId, String reaction) {
    state = state.map((msg) {
      if (msg.id != messageId) return msg;
      final reactions = List<String>.from(msg.reactions);
      if (reactions.contains(reaction)) {
        reactions.remove(reaction);
      } else {
        reactions.add(reaction);
      }
      // Persister en base.
      unawaited(StorageService.updateMessageReactions(messageId, reactions));
      // Diffuser au pair via le mesh.
      final peerId = msg.groupId ?? msg.targetId ?? msg.senderId;
      if (peerId != null && peerId != _repo.myId) {
        unawaited(_repo.sendReaction(
          targetId: peerId,
          messageId: messageId,
          emoji: reaction,
        ));
      }
      return msg.copyWith(reactions: reactions);
    }).toList();
  }

  /// Marque localement comme lu tous les messages entrants d'une conversation
  /// et diffuse les accusés de lecture à leurs émetteurs respectifs.
  Future<void> sendReadReceipts(String? peerId) async {
    final now = DateTime.now();
    var changed = false;
    final pending = <({String senderId, String messageId})>[];
    final updated = state.map((m) {
      if (m.groupId != null) return m;
      final other = m.senderId == _repo.myId ? m.targetId : m.senderId;
      final inConv = peerId == null ? m.targetId == null : other == peerId;
      if (!inConv || m.senderId == _repo.myId || m.readAt != null) return m;
      changed = true;
      final sender = m.senderId;
      if (sender != null) pending.add((senderId: sender, messageId: m.id));
      return m.copyWith(readAt: now);
    }).toList();
    if (changed) {
      state = updated;
      for (final m in updated) {
        if (m.readAt == now && m.senderId != _repo.myId) {
          unawaited(StorageService.updateMessageReadAt(m.id, now));
        }
      }
      for (final p in pending) {
        unawaited(_repo.sendRead(
          originalSenderId: p.senderId,
          messageId: p.messageId,
        ));
      }
    }
  }

  /// Dès qu'un pair se reconnecte, tente d'envoyer tout ce qui attendait
  /// dans la « boîte d'attente ».
  ///
  /// Utilise un compteur de génération pour détecter si de nouveaux
  /// messages sont arrivés pendant le vidage. Si c'est le cas, un
  /// deuxième flush est programmé automatiquement — on ne perd jamais
  /// un message ajouté entre le `clear()` et la fin des envois.
  void _flushOutbox() {
    if (_outbox.isEmpty) return;
    if (_repo.transport.connectedPeerCount == 0) return;

    final gen = _outboxGeneration;
    final toFlush = List<_OutboxEntry>.from(_outbox);
    _outbox.clear();

    _showToast('${toFlush.length} message${toFlush.length > 1 ? 's' : ''} en attente envoyé${toFlush.length > 1 ? 's' : ''}', type: DropletToastType.success);

    for (final entry in toFlush) {
      _setStatus(entry.messageId, MessageStatus.sending);
      _doSendOutboxEntry(entry);
    }

    // Si de nouveaux messages ont été ajoutés pendant l'envoi, relancer.
    if (_outboxGeneration != gen && _outbox.isNotEmpty) {
      scheduleMicrotask(_flushOutbox);
    }
  }

  /// Renvoie un message dont l'envoi avait échoué.
  ///
  /// ── ⚠️ POURQUOI CETTE ACTION MANQUAIT, ET POURQUOI ELLE COMPTE ───
  ///
  /// Un message en échec affichait une icône rouge, et rien d'autre. La
  /// seule issue était de le retaper — sur un vocal ou une photo, cela
  /// voulait dire recommencer entièrement.
  ///
  /// Or l'échec ici n'est pas ce qu'il est ailleurs. Sans pair à
  /// portée, un message part en ATTENTE et se renvoie tout seul : c'est
  /// le fonctionnement normal. `failed` ne survient que lorsque l'envoi
  /// a réellement échoué malgré des appareils présents — une liaison
  /// coupée en plein transfert, un pair évincé au mauvais moment.
  /// Autrement dit : toujours une erreur passagère, toujours de celles
  /// qui réussissent au second essai.
  ///
  /// ⚠️ ON RÉUTILISE `_doSendOutboxEntry`, on ne réécrit pas l'envoi.
  /// Une seconde implémentation aurait fini par diverger de celle de la
  /// file d'attente — et un message renvoyé serait parti avec un
  /// chiffrement ou une cible légèrement différents.
  Future<void> renvoyer(String messageId) async {
    final msg = state.where((m) => m.id == messageId).firstOrNull;
    if (msg == null) return;

    final entree = _OutboxEntry(
      messageId: msg.id,
      kind: msg.type == 'file' ? _OutboxKind.file : _OutboxKind.text,
      targetId: msg.targetId,
      groupId: msg.groupId,
    );

    _setStatus(msg.id, MessageStatus.sending);

    if (_repo.transport.connectedPeerCount == 0) {
      // Plus personne à portée : on ne réessaie pas dans le vide, on
      // remet en attente. Le message repartira de lui-même à la
      // prochaine rencontre, exactement comme les autres.
      _setStatus(msg.id, MessageStatus.pending);
      _addToOutbox(entree);
      unawaited(StorageService.saveOutbox({
        'id': msg.id,
        'kind': entree.kind == _OutboxKind.file ? 'file' : 'text',
        'targetId': msg.targetId,
        'groupId': msg.groupId,
      }));
      _showToast(
        'Aucun pair à portée — le message repartira tout seul',
        type: DropletToastType.info,
      );
      return;
    }

    await _doSendOutboxEntry(entree);
  }

  Future<void> _doSendOutboxEntry(_OutboxEntry entry) async {
    try {
      final msg = state.where((m) => m.id == entry.messageId).firstOrNull;
      if (msg == null) {
        StorageService.clearOutboxEntry(entry.messageId);
        return;
      }

      if (entry.kind == _OutboxKind.text) {
        if (entry.groupId != null) {
          await _repo.sendGroupMessage(
            groupId: entry.groupId!,
            content: msg.content,
            replyToId: msg.replyToId,
            messageId: msg.id,
          );
        } else {
          await _repo.sendMessage(
            authorPseudo: msg.authorPseudo,
            content: msg.content,
            type: msg.type,
            imageUrl: msg.imageUrl,
            audioUrl: msg.audioUrl,
            replyToId: msg.replyToId,
            messageId: msg.id,
            targetId: entry.targetId,
          );
        }
      } else if (entry.kind == _OutboxKind.file) {
        final path = await StorageService.getSharedFilePath(msg.fileId ?? '', msg.fileName ?? '');
        if (path == null) throw StateError('Fichier introuvable localement');
        final bytes = await File(path).readAsBytes();
        await _repo.sendFile(
          fileName: msg.fileName ?? '',
          bytes: bytes,
          mimeType: msg.fileMimeType ?? '',
          targetId: entry.targetId,
          groupId: entry.groupId,
          fileId: msg.fileId,
          // Repris du message conservé : un vocal envoyé hors ligne en
          // réponse à un autre doit rester rattaché à sa question quand
          // il repart, plusieurs heures plus tard.
          replyToId: msg.replyToId,
        );
      }
      _setStatus(entry.messageId, MessageStatus.sent);
      StorageService.clearOutboxEntry(entry.messageId);
    } catch (_) {
      _setStatus(entry.messageId, MessageStatus.failed);
      _showToast('Échec d\'envoi d\'un message en attente', type: DropletToastType.error);
    }
  }

  void _setStatus(String messageId, MessageStatus status) {
    state = state.map((m) {
      if (m.id != messageId) return m;
      return m.copyWith(status: status);
    }).toList();
    StorageService.updateMessageStatus(messageId, status);
  }

  /// Planifie l'envoi des accusés de lecture après 1s (annulé si de nouveaux
  /// messages arrivent pendant ce délai). Évite de marquer lu trop tôt quand
  /// l'utilisateur ouvre brièvement une conversation.
  void scheduleReadReceipts(String? peerId) {
    _readDelayTimer?.cancel();
    _readDelayTimer = Timer(const Duration(seconds: 1), () {
      unawaited(sendReadReceipts(peerId));
    });
  }

  @override
  void dispose() {
    _peerSub?.cancel();
    _ackSub?.cancel();
    _readSub?.cancel();
    _reactionSub?.cancel();
    _newMessageSub?.cancel();
    _repairedSub?.cancel();
    _readDelayTimer?.cancel();
    _reactionEventCtrl.close();
    super.dispose();
  }
}

enum _OutboxKind { text, file }

/// Un message « en attente d'envoi » — mis de côté le temps qu'un pair
/// se reconnecte.
class _OutboxEntry {
  final String messageId;
  final _OutboxKind kind;
  final String? targetId;
  final String? groupId;
  const _OutboxEntry({
    required this.messageId,
    required this.kind,
    this.targetId,
    this.groupId,
  });
}

// ── Appels WebRTC (voix sur mesh) ─────────────────────────────────────────
//
// Ce notifier fait le lien entre l'écran d'appel (`call_screen.dart`) et
// les deux services techniques `CallSignalingService` (les « papiers
// d'entente ») et `WebRtcCallService` (le vrai son) — il traduit leurs
// événements internes en un état simple que l'écran peut afficher
// directement (« en train de sonner », « connecté », « raccroché »...).

final callProvider = StateNotifierProvider<CallNotifier, CallState>((ref) {
  return CallNotifier();
});

class CallNotifier extends StateNotifier<CallState> {
  CallSignalingService? _signaling;
  WebRtcCallService? _webrtc;
  StreamSubscription<CallEvent>? _eventSub;
  StreamSubscription<SignalingMessage>? _incomingCallSub;

  String? _pendingOfferSdp;

  // ── Journal d'appels ────────────────────────────────────────────────
  // De quoi transformer l'appel en cours en une ligne d'historique au
  // moment où il se termine. Ces champs sont volontairement en dehors de
  // `CallState` : ils ne concernent que la comptabilité, l'écran d'appel
  // n'a rien à en faire.

  /// Début de la sonnerie de l'appel en cours.
  DateTime? _callStartedAt;

  /// Moment où l'autre a décroché — reste nul pour un appel jamais
  /// abouti, ce qui est précisément ce qui distingue un appel manqué.
  DateTime? _callConnectedAt;

  /// Copiés au démarrage : à la fin de l'appel, `state` a déjà été remis
  /// à zéro par endroits, et on veut malgré tout savoir qui on appelait.
  String? _callPeerId;
  String? _callPeerPseudo;

  CallNotifier() : super(const CallState());

  bool _initialized = false;

  /// Branche ce notifier sur le vrai transport mesh — appelé une fois au
  /// démarrage de l'app, dès qu'une identité existe.
  void init(MeshTransportService transport) {
    if (_initialized) return;
    _initialized = true;
    _signaling = CallSignalingService(transport);
    _signaling!.startListening();
    _webrtc = WebRtcCallService(_signaling!);
    _incomingCallSub = _signaling!.incomingMessages.listen(_onIncomingCall);
  }

  void _onIncomingCall(SignalingMessage msg) {
    // Ce callback est un `onData` de Stream.listen, actif en permanence dès
    // le lancement de l'app (init() est appelé à l'onboarding). Une
    // exception synchrone ici (cast raté sur des données malformées venant
    // d'un pair) ne serait rattrapée par personne et ferait planter l'app à
    // chaque réception d'un message de signalisation — d'où le try/catch.
    try {
      debugPrint('[CallNotifier] _onIncomingCall type=0x${msg.type.toRadixString(16)} peer=${msg.peerId} sdpPresent=${msg.data.containsKey('sdp')}');
      // Une offre porteuse d'une liste de participants est une invitation à
      // un appel de groupe — gérée séparément par GroupCallNotifier, jamais
      // comme un appel 1:1 entrant.
      if (msg.data['participants'] != null) return;
      if (msg.type == kCallOffer) {
        final sdp = msg.data['sdp'] as String?;
        if (sdp == null) return;
        _pendingOfferSdp = sdp;
        _beginCallLog(msg.peerId, null, CallDirection.incoming);
        state = state.copyWith(
          isCallActive: true,
          peerId: msg.peerId,
          direction: CallDirection.incoming,
          connectionState: CallConnectionState.connecting,
        );
        CallRingerService.startIncoming();
      }
    } catch (e) {
      debugPrint('[CallNotifier] message de signalisation invalide ignoré: $e');
    }
  }

  /// Démarre un appel SORTANT vers [peerId] — fait sonner la tonalité de
  /// rappel et lance la négociation WebRTC.
  Future<void> startCall(String peerId, String peerPseudo) async {
    if (_signaling == null || _webrtc == null) return;

    _beginCallLog(peerId, peerPseudo, CallDirection.outgoing);
    state = state.copyWith(
      isCallActive: true,
      peerId: peerId,
      peerPseudo: peerPseudo,
      direction: CallDirection.outgoing,
      connectionState: CallConnectionState.connecting,
    );
    CallRingerService.startOutgoing();

    try {
      _eventSub?.cancel();
      _eventSub = _webrtc!.events.listen(_onWebrtcEvent);
      await _webrtc!.startCall(peerId);
    } catch (e) {
      CallRingerService.stop();
      _finishCallLog(CallOutcome.failed);
      state = state.copyWith(
        isCallActive: false,
        connectionState: CallConnectionState.failed,
      );
    }
  }

  /// Décroche l'appel ENTRANT en cours de sonnerie.
  Future<void> answerCall() async {
    if (_signaling == null || _webrtc == null) return;
    final peerId = state.peerId;
    final sdp = _pendingOfferSdp;
    if (peerId == null || sdp == null) return;

    CallRingerService.stop();
    state = state.copyWith(
      isCallActive: true,
      connectionState: CallConnectionState.connecting,
    );

    try {
      _eventSub?.cancel();
      _eventSub = _webrtc!.events.listen(_onWebrtcEvent);
      await _webrtc!.answerCall(peerId, sdp);
    } catch (e) {
      _finishCallLog(CallOutcome.failed);
      state = state.copyWith(
        isCallActive: false,
        connectionState: CallConnectionState.failed,
      );
    }
  }

  RTCVideoRenderer? get remoteRenderer => _webrtc?.remoteRenderer;
  RTCVideoRenderer? get localRenderer => _webrtc?.localRenderer;

  /// Traduit chaque événement technique de WebRTC en un changement
  /// d'état compréhensible pour l'écran d'appel.
  void _onWebrtcEvent(CallEvent event) {
    if (event is CallConnecting) {
      state = state.copyWith(connectionState: CallConnectionState.connecting);
    } else if (event is CallConnected) {
      CallRingerService.stop();
      _callConnectedAt ??= DateTime.now();
      state = state.copyWith(connectionState: CallConnectionState.connected);
    } else if (event is CallFailed) {
      CallRingerService.stop();
      _finishCallLog(CallOutcome.failed);
      state = state.copyWith(
        isCallActive: false,
        connectionState: CallConnectionState.failed,
      );
    } else if (event is CallDisconnected) {
      CallRingerService.stop();
      _finishCallLog(null);
      state = state.copyWith(
        isCallActive: false,
        connectionState: CallConnectionState.disconnected,
      );
    } else if (event is CallRemoteHangUp) {
      CallRingerService.stop();
      _finishCallLog(null);
      state = state.copyWith(
        isCallActive: false,
        connectionState: CallConnectionState.disconnected,
      );
    } else if (event is CallStatsUpdated) {
      state = state.copyWith(
        latencyMs: event.latencyMs > 0 ? event.latencyMs : state.latencyMs,
        bitrateKbps: event.bitrateKbps > 0 ? event.bitrateKbps : state.bitrateKbps,
        audioLevel: event.audioLevel,
      );
    } else if (event is VideoAdded) {
      state = state.copyWith(
        isRemoteVideoActive: true,
        isVideoEnabled: true,
      );
    } else if (event is VideoRemoved) {
      state = state.copyWith(isRemoteVideoActive: false);
    }
  }

  void toggleMute() {
    if (_webrtc == null) return;
    final wasMuted = state.isMuted;
    _webrtc!.toggleMute();
    state = state.copyWith(isMuted: !wasMuted);
  }

  void toggleSpeaker() {
    if (_webrtc == null) return;
    _webrtc!.toggleSpeaker();
    state = state.copyWith(isSpeakerOn: !state.isSpeakerOn);
  }

  void toggleVideo() {
    if (_webrtc == null) return;
    _webrtc!.toggleVideo();
    state = state.copyWith(isVideoEnabled: !state.isVideoEnabled);
  }

  void hangUp() {
    CallRingerService.stop();
    _finishCallLog(null);
    if (_webrtc != null) {
      // Fire-and-forget assumé : l'UI raccroche immédiatement (navigation
      // vers /chats juste après) sans attendre la fermeture propre de la
      // connexion WebRTC ; un échec ne doit jamais remonter après coup.
      unawaited(_webrtc!.hangUp().catchError((e) => debugPrint('[Call] échec hangUp: $e')));
    }
    _eventSub?.cancel();
    state = const CallState();
  }

  // ── Journalisation ──────────────────────────────────────────────────

  /// Note le début d'un appel. Rien n'est écrit sur le disque à ce
  /// stade : on ne sait pas encore comment il va se terminer, et un appel
  /// en cours n'a pas sa place dans un historique.
  void _beginCallLog(String peerId, String? pseudo, CallDirection direction) {
    _callStartedAt = DateTime.now();
    _callConnectedAt = null;
    _callPeerId = peerId;
    _callPeerPseudo = pseudo;
    _callDirection = direction;
  }

  CallDirection _callDirection = CallDirection.outgoing;

  /// Écrit l'appel qui vient de se terminer dans le journal.
  ///
  /// [forcedOutcome] sert aux échecs explicites ; sinon le résultat se
  /// déduit tout seul : si l'appel a été décroché à un moment, c'est un
  /// appel abouti, sinon c'est un appel manqué.
  ///
  /// Écriture asynchrone non attendue : raccrocher doit être instantané,
  /// et un échec d'écriture du journal ne doit jamais empêcher de
  /// raccrocher.
  void _finishCallLog(CallOutcome? forcedOutcome) {
    final startedAt = _callStartedAt;
    final peerId = _callPeerId;
    // Appelé deux fois de suite (raccrochage local puis événement
    // « déconnecté » de WebRTC) : le premier appel remet ces champs à
    // zéro, le second n'a donc plus rien à écrire. Sans cette garde, un
    // seul appel apparaîtrait deux fois dans l'historique.
    if (startedAt == null || peerId == null) return;
    _callStartedAt = null;
    _callPeerId = null;

    final connectedAt = _callConnectedAt;
    final outcome = forcedOutcome ??
        (connectedAt != null ? CallOutcome.answered : CallOutcome.missed);

    final entry = CallLogEntry(
      id: '${startedAt.microsecondsSinceEpoch}-$peerId',
      peerId: peerId,
      // Pour un appel entrant, personne ne nous a donné de pseudo : on le
      // retrouve dans la fiche du pair, sinon dans l'état de l'appel.
      // « Inconnu » ne distinguait rien : deux appels manqués de deux
      // personnes différentes s'affichaient à l'identique, et on ne
      // pouvait pas savoir qui rappeler. Un identifiant abrégé, lui,
      // reste stable d'un appel à l'autre — on reconnaît « Pair
      // 3f7a1c92 » même sans savoir qui c'est.
      peerPseudo: nomDuPair(peerId, [
        _callPeerPseudo,
        StorageService.getPeerRecord(peerId)?.pseudo,
        state.peerPseudo,
      ]),
      direction: _callDirection,
      outcome: outcome,
      startedAt: startedAt,
      duration: connectedAt != null
          ? DateTime.now().difference(connectedAt)
          : Duration.zero,
    );

    unawaited(StorageService.addCallLog(entry)
        .catchError((e) => debugPrint('[Call] échec journal: $e')));
  }

  bool canCallPeer(String peerId) {
    return _signaling?.canCallPeer(peerId) ?? false;
  }

  @override
  void dispose() {
    CallRingerService.stop();
    _eventSub?.cancel();
    _incomingCallSub?.cancel();
    _webrtc?.dispose();
    _signaling?.dispose();
    super.dispose();
  }
}

// ── Appels de groupe (voix, maillage complet) ──────────────────────────────
//
// Service et état entièrement séparés de CallNotifier/WebRtcCallService
// (appels 1:1) — aucune donnée partagée, pour ne jamais risquer de
// régression sur le chemin d'appel 1:1 déjà en production.

final groupCallProvider = StateNotifierProvider<GroupCallNotifier, GroupCallState>((ref) {
  return GroupCallNotifier();
});

class GroupCallNotifier extends StateNotifier<GroupCallState> {
  CallSignalingService? _signaling;
  GroupWebrtcCallService? _webrtc;
  StreamSubscription<GroupCallEvent>? _eventSub;
  StreamSubscription<SignalingMessage>? _incomingSub;
  String _myId = '';
  bool _initialized = false;

  GroupCallNotifier() : super(const GroupCallState());

  /// Invitation à un appel de groupe reçue, en attente d'acceptation/refus.
  ({String fromPeerId, String sdp, List<String> participants})? pendingInvite;

  void init(MeshTransportService transport, String myId) {
    _myId = myId;
    if (_initialized) return;
    _initialized = true;
    _signaling = CallSignalingService(transport);
    _signaling!.startListening();
    _webrtc = GroupWebrtcCallService(_signaling!);
    _incomingSub = _signaling!.incomingMessages.listen(_onIncomingOffer);
  }

  void _onIncomingOffer(SignalingMessage msg) {
    // Même raison qu'au-dessus : listener permanent sans protection en
    // amont. `.cast<String>()` est paresseux — une exception ne surviendrait
    // qu'au moment d'itérer la liste (ex. dans acceptInvite), potentiellement
    // hors de tout try/catch ; on matérialise donc la liste ici, sous try.
    try {
      if (msg.type != kCallOffer) return;
      final rawParticipants = msg.data['participants'] as List?;
      if (rawParticipants == null) return; // offre 1:1 classique, pas pour nous
      final participants = rawParticipants.map((e) => e as String).toList();
      if (state.isActive || pendingInvite != null) return; // déjà occupé
      final sdp = msg.data['sdp'] as String?;
      if (sdp == null) return;
      pendingInvite = (fromPeerId: msg.peerId, sdp: sdp, participants: participants);
      CallRingerService.startIncoming();
      // Ré-émet l'état courant pour notifier les auditeurs Riverpod qu'une
      // invitation est disponible (pendingInvite n'est pas dans CallState).
      state = state.copyWith();
    } catch (e) {
      debugPrint('[GroupCallNotifier] message de signalisation invalide ignoré: $e');
    }
  }

  Future<void> startGroupCall({
    required String groupId,
    required String groupName,
    required List<String> memberPeerIds,
    required String Function(String peerId) pseudoFor,
  }) async {
    if (_webrtc == null) return;
    state = GroupCallState(
      isActive: true,
      groupId: groupId,
      groupName: groupName,
      participants: memberPeerIds.map((id) => GroupCallParticipant(peerId: id, pseudo: pseudoFor(id))).toList(),
    );
    CallRingerService.startOutgoing();
    _eventSub?.cancel();
    _eventSub = _webrtc!.events.listen(_onEvent);
    try {
      await _webrtc!.startGroupCall(myId: _myId, memberPeerIds: memberPeerIds);
    } catch (e) {
      debugPrint('[GroupCall] échec démarrage: $e');
      CallRingerService.stop();
      state = const GroupCallState();
    }
  }

  Future<void> acceptInvite({required String Function(String peerId) pseudoFor}) async {
    final invite = pendingInvite;
    if (invite == null || _webrtc == null) return;
    pendingInvite = null;
    CallRingerService.stop();

    final otherIds = invite.participants.where((id) => id != _myId).toSet()..add(invite.fromPeerId);
    state = GroupCallState(
      isActive: true,
      participants: otherIds.map((id) => GroupCallParticipant(peerId: id, pseudo: pseudoFor(id))).toList(),
    );
    _eventSub?.cancel();
    _eventSub = _webrtc!.events.listen(_onEvent);
    try {
      await _webrtc!.joinGroupCall(
        myId: _myId,
        fromPeerId: invite.fromPeerId,
        offerSdp: invite.sdp,
        allParticipants: invite.participants,
      );
    } catch (e) {
      debugPrint('[GroupCall] échec adhésion: $e');
      state = const GroupCallState();
    }
  }

  void declineInvite() {
    final invite = pendingInvite;
    pendingInvite = null;
    CallRingerService.stop();
    if (invite != null) {
      unawaited(_signaling?.sendHangUp(invite.fromPeerId));
    }
    state = state.copyWith();
  }

  void _onEvent(GroupCallEvent event) {
    List<GroupCallParticipant> updateState(GroupCallParticipantState newState) {
      return state.participants
          .map((p) => p.peerId == event.peerId ? p.copyWith(state: newState) : p)
          .toList();
    }

    if (event is GroupCallParticipantConnecting) {
      state = state.copyWith(participants: updateState(GroupCallParticipantState.connecting));
    } else if (event is GroupCallParticipantConnected) {
      CallRingerService.stop();
      state = state.copyWith(participants: updateState(GroupCallParticipantState.connected));
    } else if (event is GroupCallParticipantFailed) {
      state = state.copyWith(participants: updateState(GroupCallParticipantState.failed));
    } else if (event is GroupCallParticipantDisconnected) {
      final remaining = state.participants.where((p) => p.peerId != event.peerId).toList();
      if (remaining.isEmpty) {
        hangUp();
      } else {
        state = state.copyWith(participants: remaining);
      }
    }
  }

  void toggleMute() {
    _webrtc?.toggleMute();
    state = state.copyWith(isMuted: !state.isMuted);
  }

  Future<void> toggleSpeaker() async {
    await _webrtc?.toggleSpeaker();
    state = state.copyWith(isSpeakerOn: !state.isSpeakerOn);
  }

  Future<void> removeParticipant(String peerId) async {
    await _webrtc?.removeParticipant(peerId);
  }

  void hangUp() {
    CallRingerService.stop();
    if (_webrtc != null) {
      unawaited(_webrtc!.hangUpAll().catchError((e) => debugPrint('[GroupCall] échec hangUp: $e')));
    }
    _eventSub?.cancel();
    state = const GroupCallState();
  }

  @override
  void dispose() {
    CallRingerService.stop();
    _eventSub?.cancel();
    _incomingSub?.cancel();
    _webrtc?.dispose();
    _signaling?.dispose();
    super.dispose();
  }
}

// ── Pairs connectés ────────────────────────────────────────────────────────

/// La liste, toujours à jour, des appareils actuellement joignables sur
/// le mesh — utilisée pour afficher les petits points « en ligne » et
/// pour savoir qui on peut appeler.
final meshPeerListProvider = StateNotifierProvider<MeshPeerListNotifier, List<ConnectedPeer>>((ref) {
  final repo = ref.watch(meshRepositoryProvider);
  return MeshPeerListNotifier(repo);
});

class MeshPeerListNotifier extends StateNotifier<List<ConnectedPeer>> {
  final MeshRepository _repo;
  StreamSubscription<ConnectedPeer>? _sub;

  MeshPeerListNotifier(this._repo) : super(_repo.peerList) {
    _sub = _repo.peerEvents?.listen((_) {
      state = _repo.peerList;
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

final connectedPeerCountProvider = Provider<int>((ref) {
  return ref.watch(meshPeerListProvider).length;
});

// ── Conversations 1:1 / groupe / diffusion (WhatsApp-like) ────────────────

enum ConversationKind { direct, group, broadcast }

/// Une ligne de la liste des conversations (écran d'accueil) — un
/// résumé : avec qui (ou quel groupe), le dernier message, quand, et
/// combien de messages non lus.
class Conversation {
  final String? peerId;
  final String? groupId;
  final ConversationKind kind;
  final String pseudo;
  final String lastMessage;
  final DateTime lastTimestamp;
  final int unreadCount;
  final String? avatarUrl;
  final bool isOnline;
  final bool isPinned;
  final bool isMuted;

  const Conversation({
    required this.peerId,
    this.groupId,
    required this.kind,
    required this.pseudo,
    required this.lastMessage,
    required this.lastTimestamp,
    required this.unreadCount,
    this.avatarUrl,
    this.isOnline = false,
    this.isPinned = false,
    this.isMuted = false,
  });

  bool get isBroadcast => kind == ConversationKind.broadcast;
  bool get isGroup => kind == ConversationKind.group;

  /// Clé de conversation stable, utilisée pour le watermark de lecture et
  /// le routage vers l'écran de chat.
  String get key => groupId ?? peerId ?? 'broadcast';
}

/// Horodatages de dernière lecture par conversation (watermark).
///
/// Persisté dans les settings pour rester cohérent entre redémarrages.
final conversationReadsProvider = StateNotifierProvider<ConversationReadsNotifier, Map<String, DateTime>>((ref) {
  return ConversationReadsNotifier();
});

class ConversationReadsNotifier extends StateNotifier<Map<String, DateTime>> {
  ConversationReadsNotifier() : super(_load());

  static Map<String, DateTime> _load() {
    final raw = StorageService.getString('conversation_reads');
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = json.decode(raw) as Map<String, dynamic>;
      return map.map((k, v) => MapEntry(
        k,
        DateTime.fromMillisecondsSinceEpoch((v as num).toInt()),
      ));
    } catch (_) {
      return {};
    }
  }

  void markRead(String peerId) {
    final now = DateTime.now();
    state = {...state, peerId: now};
    StorageService.setString(
      'conversation_reads',
      json.encode(state.map((k, v) => MapEntry(k, v.millisecondsSinceEpoch))),
    );
  }

  @override
  void dispose() {
    StorageService.setString(
      'conversation_reads',
      json.encode(state.map((k, v) => MapEntry(k, v.millisecondsSinceEpoch))),
    );
    super.dispose();
  }
}

/// Construit la liste des conversations à partir des messages stockés.
///
/// Trois catégories, mutuellement exclusives par message :
/// - `groupId` défini → conversation de groupe.
/// - `groupId` nul et `targetId`/`senderId` définit un correspondant →
///   conversation 1:1 (`senderId` message reçu, `targetId` message envoyé).
/// - ni l'un ni l'autre → diffusion mesh totale ("Diffusion mesh").
/// Compteur bumpé manuellement à l'archivage/désarchivage d'une conversation
/// — `StorageService.getArchivedConversations()` est un cache synchrone, pas
/// un state Riverpod, donc rien ne force [conversationsProvider] à se
/// recalculer sans ce signal explicite (même pattern que
/// `_groupsRevisionProvider` un peu plus bas).
final archivedRevisionProvider = StateProvider<int>((ref) => 0);

/// Signal de relecture quand une conversation est épinglée/désépinglée ou
/// mise en mode silencieux — même pattern que [archivedRevisionProvider].
final pinMuteRevisionProvider = StateProvider<int>((ref) => 0);

/// LE calcul principal derrière l'écran d'accueil : prend TOUS les
/// messages stockés et les range en « paquets » par correspondant ou par
/// groupe pour en faire une conversation, comme trier un tas de lettres
/// reçues et envoyées en une pile par destinataire.
final conversationsProvider = Provider<List<Conversation>>((ref) {
  ref.watch(archivedRevisionProvider);
  ref.watch(pinMuteRevisionProvider);
  final messages = ref.watch(meshMessagesProvider);
  final peers = ref.watch(meshPeerListProvider);
  final reads = ref.watch(conversationReadsProvider);
  final repo = ref.watch(meshRepositoryProvider);
  final myId = repo.myId;
  final archived = StorageService.getArchivedConversations();
  final pinned = StorageService.getPinnedConversations();
  final muted = StorageService.getMutedConversations();
  NotificationService.setArchivedConversations(archived);

  final byPeer = <String, List<MeshMessage>>{};
  final byGroup = <String, List<MeshMessage>>{};
  final broadcast = <MeshMessage>[];

  for (final m in messages) {
    if (m.groupId != null) {
      byGroup.putIfAbsent(m.groupId!, () => []).add(m);
      continue;
    }
    final peerId = m.senderId == myId ? m.targetId : m.senderId;
    if (peerId == null) {
      broadcast.add(m);
    } else {
      byPeer.putIfAbsent(peerId, () => []).add(m);
    }
  }

  final conversations = <Conversation>[];

  for (final entry in byPeer.entries) {
    final list = entry.value
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final last = list.first;
    final lastRead = reads[entry.key];
    final unread = list.where((m) {
      final isMine = m.senderId == myId;
      if (isMine) return false;
      return lastRead == null || m.timestamp.isAfter(lastRead);
    }).length;
    ConnectedPeer? peer;
    try {
      peer = peers.firstWhere((p) => p.peerId == entry.key);
    } catch (_) {}
    conversations.add(Conversation(
      peerId: entry.key,
      kind: ConversationKind.direct,
      // `last.authorPseudo` est l'auteur du DERNIER message du fil — si
      // c'est moi qui ai parlé en dernier, ce serait mon propre pseudo, pas
      // celui du correspondant. On résout explicitement le pseudo du pair
      // (`entry.key`), jamais celui du dernier message.
      //
      // Dernier repli : un message reçu de ce pair AVANT que son pseudo ne
      // soit connu (poignée de main pas encore faite, ou relais multi-hop)
      // est persisté avec `authorPseudo == senderId` — l'ID brut. Prendre le
      // premier message venu risquerait de retomber sur cet ID brut même si
      // un message *plus tardif* a bien le vrai pseudo. On cherche donc le
      // premier message dont l'auteur est réellement résolu.
      pseudo: peer?.pseudo ??
          StorageService.getPeerRecord(entry.key)?.pseudo ??
          list
              .where((m) => m.senderId == entry.key && m.authorPseudo != entry.key)
              .map((m) => m.authorPseudo)
              .firstOrNull ??
          entry.key,
      lastMessage: _describeForPreview(last),
      lastTimestamp: last.timestamp,
      unreadCount: unread,
      isOnline: peer != null,
      isPinned: pinned.contains(entry.key),
      isMuted: muted.contains(entry.key),
    ));
  }

  for (final entry in byGroup.entries) {
    final list = entry.value
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final last = list.first;
    final lastRead = reads[entry.key];
    final unread = list.where((m) {
      final isMine = m.senderId == myId;
      if (isMine) return false;
      return lastRead == null || m.timestamp.isAfter(lastRead);
    }).length;
    final group = StorageService.getGroup(entry.key);
    if (group == null || !group.isActiveMember(myId)) continue;
    conversations.add(Conversation(
      peerId: null,
      groupId: entry.key,
      kind: ConversationKind.group,
      pseudo: group.name,
      avatarUrl: group.avatarUrl,
      lastMessage: _describeForPreview(last),
      lastTimestamp: last.timestamp,
      unreadCount: unread,
      isPinned: pinned.contains(entry.key),
      isMuted: muted.contains(entry.key),
    ));
  }

  if (broadcast.isNotEmpty) {
    broadcast.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final last = broadcast.first;
    conversations.add(Conversation(
      peerId: null,
      kind: ConversationKind.broadcast,
      pseudo: 'Diffusion mesh',
      lastMessage: _describeForPreview(last),
      lastTimestamp: last.timestamp,
      unreadCount: 0,
    ));
  }

  conversations.removeWhere((c) => archived.contains(c.key));
  // Épinglés d'abord, puis par date décroissante.
  conversations.sort((a, b) {
    if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
    return b.lastTimestamp.compareTo(a.lastTimestamp);
  });
  return conversations;
});

/// Conversations archivées (mêmes calculs que [conversationsProvider], non
/// filtrées) — pour la feuille de désarchivage de `chats_screen.dart`.
final archivedConversationsProvider = Provider<List<Conversation>>((ref) {
  ref.watch(archivedRevisionProvider);
  final messages = ref.watch(meshMessagesProvider);
  final peers = ref.watch(meshPeerListProvider);
  final myId = ref.watch(meshRepositoryProvider).myId;
  final archived = StorageService.getArchivedConversations();
  if (archived.isEmpty) return const [];

  final byPeer = <String, List<MeshMessage>>{};
  final byGroup = <String, List<MeshMessage>>{};
  for (final m in messages) {
    if (m.groupId != null) {
      byGroup.putIfAbsent(m.groupId!, () => []).add(m);
      continue;
    }
    final peerId = m.senderId == myId ? m.targetId : m.senderId;
    if (peerId != null) byPeer.putIfAbsent(peerId, () => []).add(m);
  }

  final result = <Conversation>[];
  for (final entry in byPeer.entries) {
    if (!archived.contains(entry.key)) continue;
    final list = entry.value..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final last = list.first;
    ConnectedPeer? peer;
    try {
      peer = peers.firstWhere((p) => p.peerId == entry.key);
    } catch (_) {}
    result.add(Conversation(
      peerId: entry.key,
      kind: ConversationKind.direct,
      pseudo: peer?.pseudo ?? StorageService.getPeerRecord(entry.key)?.pseudo ?? entry.key,
      lastMessage: _describeForPreview(last),
      lastTimestamp: last.timestamp,
      unreadCount: 0,
      isOnline: peer != null,
    ));
  }
  for (final entry in byGroup.entries) {
    if (!archived.contains(entry.key)) continue;
    final group = StorageService.getGroup(entry.key);
    if (group == null) continue;
    final list = entry.value..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    final last = list.first;
    result.add(Conversation(
      peerId: null,
      groupId: entry.key,
      kind: ConversationKind.group,
      pseudo: group.name,
      lastMessage: _describeForPreview(last),
      lastTimestamp: last.timestamp,
      unreadCount: 0,
    ));
  }
  result.sort((a, b) => b.lastTimestamp.compareTo(a.lastTimestamp));
  return result;
});

/// Messages d'une conversation donnée (triés du plus ancien au plus récent).
final conversationMessagesProvider = Provider.family<List<MeshMessage>, String?>((ref, peerId) {
  final messages = ref.watch(meshMessagesProvider);
  final repo = ref.watch(meshRepositoryProvider);
  final myId = repo.myId;

  final filtered = messages.where((m) {
    if (m.groupId != null) return false;
    if (peerId == null) {
      // Canal diffusion : aucun ciblage.
      return m.targetId == null;
    }
    final other = m.senderId == myId ? m.targetId : m.senderId;
    return other == peerId;
  }).toList();
  filtered.sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return filtered;
});

/// Messages d'un groupe donné (triés du plus ancien au plus récent).
final groupMessagesProvider = Provider.family<List<MeshMessage>, String>((ref, groupId) {
  final messages = ref.watch(meshMessagesProvider);
  final filtered = messages.where((m) => m.groupId == groupId).toList()
    ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
  return filtered;
});

/// Groupe donné, réactif aux changements locaux (création/ajout/retrait).
final groupInfoProvider = Provider.family<GroupInfo?, String>((ref, groupId) {
  ref.watch(_groupsRevisionProvider);
  return StorageService.getGroup(groupId);
});

/// Groupes dont je suis membre actif, triés par nom.
final myGroupsProvider = Provider<List<GroupInfo>>((ref) {
  ref.watch(_groupsRevisionProvider);
  final myId = ref.watch(meshRepositoryProvider).myId;
  final groups = StorageService.getGroups().where((g) => g.isActiveMember(myId)).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  return groups;
});

/// Compteur incrémenté à chaque `groupsChangedEvents` — sert uniquement à
/// invalider [groupInfoProvider]/[myGroupsProvider] (les groupes sont lus
/// depuis le cache synchrone de `StorageService`, pas depuis le state).
final _groupsRevisionProvider = StateNotifierProvider<_GroupsRevisionNotifier, int>((ref) {
  final repo = ref.watch(meshRepositoryProvider);
  return _GroupsRevisionNotifier(repo);
});

class _GroupsRevisionNotifier extends StateNotifier<int> {
  final MeshRepository _repo;
  StreamSubscription<String>? _sub;

  _GroupsRevisionNotifier(this._repo) : super(0) {
    _sub = _repo.groupsChangedEvents.listen((_) => state++);
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }
}

/// Pseudo d'un pair donné (depuis la liste connectée ou l'historique).
final peerPseudoProvider = Provider.family<String, String>((ref, peerId) {
  // ⚠️ CE PROVIDER NE RENVOIE PLUS JAMAIS L'IDENTIFIANT BRUT.
  //
  // Il terminait par `return resolved ?? peerId` : une empreinte de
  // soixante-quatre caractères hexadécimaux, affichée à la place d'un
  // nom dans le journal d'appels, la liste des pairs et les groupes.
  // C'est ce que voyait tout utilisateur ayant reçu un message par
  // relais d'un appareil jamais croisé — un cas fréquent, pas marginal.
  //
  // Et la fiche enregistrée n'était pas contrôlée : d'anciennes
  // versions y écrivaient l'identifiant en guise de pseudonyme, si bien
  // qu'un `known != null` renvoyait joyeusement l'empreinte.
  //
  // `nomDuPair` applique la même règle qu'ailleurs : un vrai nom, ou
  // « Pair 3f7a1c92 ». Voir `nom_pair.dart`.
  final vivant = ref
      .watch(meshPeerListProvider)
      .where((p) => p.peerId == peerId)
      .map((p) => p.pseudo)
      .firstOrNull;

  // Un message reçu porte le nom de son auteur — sauf s'il est arrivé
  // avant que le pseudonyme ne soit connu, auquel cas il porte
  // l'identifiant. `nomDuPair` écarte ce cas de lui-même.
  final parMessage = ref
      .watch(meshMessagesProvider)
      .where((m) => m.senderId == peerId)
      .map((m) => m.authorPseudo)
      .firstOrNull;

  return nomDuPair(peerId, [
    vivant,
    StorageService.getPeerRecord(peerId)?.pseudo,
    parMessage,
  ]);
});

// ── Indicateur de frappe ──────────────────────────────────────────────────

/// IDs des pairs qui tapent actuellement (auto-nettoyé après 3 s) — le
/// petit « ... » animé qu'on voit apparaître pendant que l'autre écrit.
final typingPeersProvider = StateNotifierProvider<TypingNotifier, Set<String>>((ref) {
  final repo = ref.watch(meshRepositoryProvider);
  return TypingNotifier(repo.typingEvents);
});

class TypingNotifier extends StateNotifier<Set<String>> {
  TypingNotifier(Stream<String> events) : super(<String>{}) {
    _sub = events.listen(_onTyping);
  }

  StreamSubscription<String>? _sub;
  final Map<String, Timer> _timers = {};

  void _onTyping(String peerId) {
    _timers[peerId]?.cancel();
    state = {...state, peerId};
    _timers[peerId] = Timer(const Duration(seconds: 3), () {
      state = {...state}..remove(peerId);
      _timers.remove(peerId);
    });
  }

  @override
  void dispose() {
    for (final t in _timers.values) {
      t.cancel();
    }
    _sub?.cancel();
    super.dispose();
  }
}
