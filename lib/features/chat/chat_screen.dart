// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est l'écran le plus GROS de toute l'app — celui d'une conversation
// ouverte, avec la liste des messages qui défile et la barre de saisie
// en bas. C'est gros parce qu'une conversation moderne fait BEAUCOUP de
// choses différentes : afficher les bulles de texte ET d'images ET de
// messages vocaux, gérer le clavier, les citations (« répondre à... »),
// les réactions emoji, les effets spéciaux, l'enregistrement vocal en
// maintenant le doigt appuyé, l'envoi de fichiers, le bouton « revenir
// en bas », et plus encore.
//
// Pour rester lisible malgré sa taille, ce fichier est découpé en
// beaucoup de petites classes, chacune responsable d'UN SEUL petit
// morceau visuel — un peu comme un plateau de tournage de film, où
// chaque équipe (éclairage, son, caméra) s'occupe d'une seule partie du
// travail plutôt qu'une seule personne qui ferait tout :
//
//   - `_ChatScreenState` : le grand chef d'orchestre de l'écran entier
//     (état de saisie, enregistrement vocal, défilement...).
//   - `_MessageBubble` / `_ImageBubble` : une seule bulle de message
//     (texte ou image) affichée dans la liste.
//   - `_InputBar` : toute la barre du bas — champ de texte, bouton
//     micro, bouton d'envoi.
//   - `_MicButton` / `_LiveWaveform` : le bouton micro et le petit
//     graphique qui bouge pendant qu'on enregistre sa voix.
//   - `_AnimatedSendButton` / `_EffectPicker` : le bouton d'envoi, et
//     le petit menu d'effets spéciaux (voir `message_effects.dart`).
//   - `_JumpButton` : le petit bouton flottant « nouveaux messages,
//     reviens en bas ».
//   - `_ImageViewerScreen` : l'écran plein écran pour zoomer une photo.
// ============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart' show CupertinoSearchTextField;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart'
    show SchedulerBinding, SchedulerPhase;
import 'package:motor/motor.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:video_player/video_player.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/mesh_message.dart';
import 'message_context_menu.dart';
import '../../core/providers/chat_background_provider.dart';
import 'animated_sticker.dart';
import 'package:photo_manager/photo_manager.dart';

import 'attach_sheet.dart';
import 'send_flight_animation.dart';
import 'network_sheet.dart';
import 'transmission_sheet.dart';
import 'telegram_gradient_background.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/nom_pair.dart';
import '../../core/services/notification_service.dart';
import '../../core/services/media_service.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_spinner.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/ouro_liquid.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_padlock.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_pressable.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../shared/widgets/typing_indicator.dart';
import '../../shared/widgets/heart_burst_overlay.dart';
import '../../shared/widgets/reaction_effect_overlay.dart';
import '../../shared/widgets/trash_toss_overlay.dart';
import '../../shared/widgets/message_effects.dart';
import '../../design_system/glassmorphism.dart';
import '../../shared/widgets/confetti_overlay.dart';
import '../../shared/widgets/liquid_long_press_effect.dart';
import '../../core/services/sound_service.dart';
import '../../shared/widgets/conversation_lock_screen.dart';
import '../../design_system/ouro_typography.dart';
import '../../core/models/voice_note_meta.dart';
import '../../core/services/mesh_transport_service.dart';
import 'location_message.dart';
import 'sticker_picker.dart';
import 'voice_note.dart';
import '../../shared/widgets/scene_animee.dart';
import '../../shared/widgets/ios_magnifier_overlay.dart';

/// L'écran de conversation lui-même — juste une coquille qui reçoit soit
/// un [peerId] (chat 1:1 ou diffusion), soit un [groupId] (chat de
/// groupe), et délègue tout le vrai travail à `_ChatScreenState`.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, this.peerId, this.groupId})
    : assert(peerId != null || groupId != null, 'peerId ou groupId requis');

  /// ID du pair destinataire, ou 'broadcast' pour le canal diffusion.
  /// Null si [groupId] est défini (chat de groupe).
  final String? peerId;

  /// ID du groupe de discussion, si ce chat est une conversation de groupe.
  final String? groupId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _inputCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool get _isGroup => widget.groupId != null;
  bool get _isBroadcast => !_isGroup && widget.peerId == 'broadcast';
  String? get _targetId => (_isBroadcast || _isGroup) ? null : widget.peerId;

  /// Conversation verrouillée — affiche l'écran biométrique.
  late bool _isLocked;

  // ── Recherche dans la conversation ───────────────────────────────
  //
  // ⚠️ ELLE NE FILTRE PAS LA LISTE, elle NAVIGUE DEDANS.
  //
  // Une recherche qui ne garde que les messages correspondants détruit
  // ce qu'on cherche vraiment : le CONTEXTE. Retrouver « rendez-vous »
  // n'a d'intérêt que si l'on voit la réponse juste en dessous. Ici la
  // conversation reste entière, les occurrences sont surlignées, et les
  // deux chevrons sautent de l'une à l'autre — de la plus récente vers
  // la plus ancienne, comme dans toutes les messageries.
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode();
  String _query = '';

  /// Identifiants des messages correspondants, du plus récent au plus
  /// ancien.
  List<String> _hits = const [];
  int _hitIndex = 0;

  /// Message vers lequel on vient de sauter — il clignote brièvement.
  ///
  /// Sans ce repère, arriver sur un message ancien laisse l'utilisateur
  /// devant un mur de texte sans savoir lequel il cherchait.
  String? _flashedId;
  Timer? _flashTimer;

  /// Les bulles actuellement construites, pour pouvoir en amener une à
  /// l'écran. Les autres n'existent pas encore : la liste ne fabrique
  /// que ce qui est visible.
  final Map<String, GlobalKey> _messageKeys = {};

  /// Le point de DÉPART du vol d'envoi : la boîte de texte de la barre
  /// de saisie.
  final GlobalKey _champSaisieKey = GlobalKey();

  /// La zone de la conversation, qui sert à calculer où la bulle se
  /// posera.
  final GlobalKey _zoneListeKey = GlobalKey();

  /// Combien de fois le fond en dégradé a déjà tourné.
  ///
  /// C'est le mécanisme exact de Telegram : le fond ne défile pas en
  /// boucle, il avance d'un cran à chaque message ENVOYÉ. Le lien entre
  /// le geste et le mouvement est ce qui rend l'effet vivant plutôt que
  /// décoratif.
  int _fondTick = 0;

  /// Le texte du message actuellement EN VOL, s'il y en a un.
  ///
  /// ⚠️ CE CHAMP EXISTE POUR RENDRE LA DERNIÈRE BULLE INVISIBLE, et
  /// c'est ce qui répare l'animation d'envoi.
  ///
  /// Le message est enregistré et affiché dans la liste bien avant que
  /// la copie volante ne l'ait rejoint. Sans ce masquage, on voyait donc
  /// la bulle d'arrivée DÉJÀ posée à sa place pendant que sa copie
  /// volait vers elle — deux exemplaires du même message à l'écran, ce
  /// que l'effet est précisément censé éviter.
  ///
  /// On masque donc la dernière bulle sortante tant que le vol dure, et
  /// `SendFlight` prévient (`onRevele`) quelques images avant la fin :
  /// la vraie bulle reparaît pendant que la copie s'efface par-dessus,
  /// donc le raccord se fait alors que les deux sont superposés.
  ///
  /// Le garde-fou compte : ce champ est remis à `null` à la fin du vol,
  /// à l'annulation, à la destruction de l'écran ET par une minuterie de
  /// sécurité. Une bulle définitivement invisible serait un bug bien
  /// pire que l'absence d'animation.
  String? _texteEnVol;
  Timer? _filetVol;

  bool _recording = false;
  bool _playingAudio = false;
  final _recorder = AudioRecorder();
  AudioPlayer? _player;
  String? _activeAudioFile;
  double _playbackProgress = 0;
  Duration? _playbackPosition;
  StreamSubscription<Duration>? _posSub;
  StreamSubscription<Duration>? _durSub;
  StreamSubscription<void>? _completeSub;
  Duration? _activeAudioDuration;

  /// Vitesse de lecture des messages vocaux (1×, 1,5× ou 2×). Conservée
  /// d'un message à l'autre : quelqu'un qui écoute vite veut écouter
  /// vite tout le temps, pas le redemander à chaque bulle.
  double _playbackSpeed = 1.0;

  /// Les vocaux déjà écoutés, pour la pastille « non lu ». En mémoire
  /// seulement : au prochain lancement, la pastille disparaît de toute
  /// façon puisque les messages sont alors tous anciens.
  final Set<String> _playedVoiceNotes = {};

  // ── Enregistrement en cours ──────────────────────────────────────
  //
  // La forme d'onde affichée en direct N'EST PLUS la même liste que
  // celle envoyée avec le message : la première est une fenêtre
  // glissante (les dernières secondes, qui défilent), la seconde est le
  // relevé COMPLET du début à la fin.

  /// Fenêtre glissante affichée pendant qu'on parle.
  final List<double> _amplitudes = [];

  /// Relevé complet, qui deviendra la forme d'onde du message.
  final List<double> _fullEnvelope = [];

  Timer? _ampTimer;

  /// Instant du début de l'enregistrement, pour en mesurer la durée
  /// réelle plutôt que de la deviner d'après le poids du fichier.
  DateTime? _recordStartedAt;

  /// Enregistrement « verrouillé » : on a fait glisser le micro vers le
  /// haut, on peut lâcher l'écran et continuer à parler les mains
  /// libres, comme sur WhatsApp.
  bool _recordingLocked = false;

  /// Le démarrage du micro EN COURS, s'il y en a un.
  ///
  /// ⚠️ Sans ce garde-fou, le micro pouvait rester allumé à l'insu de
  /// tout le monde. Allumer le micro n'est pas instantané (permission,
  /// arrêt d'un éventuel enregistrement précédent, ouverture du
  /// périphérique : facilement 300 ms). Or un geste rapide relâche le
  /// doigt AVANT la fin de cette séquence. `_stopRecording` trouvait
  /// alors `_recording == false`, en concluait qu'il n'y avait rien à
  /// arrêter et sortait aussitôt — pendant que le démarrage, lui, allait
  /// jusqu'au bout. Résultat : l'app affichait la barre de saisie au
  /// repos, et Android affichait sa pastille verte « micro actif ».
  ///
  /// Arrêt et annulation attendent donc désormais la fin du démarrage
  /// avant de décider qu'il n'y a rien à faire.
  Future<void>? _pendingStart;

  // Citation / swipe-to-reply
  MeshMessage? _replyTarget;

  // Scroll / jump-to-bottom
  bool _showJumpButton = false;
  int _unreadWhileScrolled = 0;
  DateTime? _lastReadAt;

  // Throttle du signal de frappe
  Timer? _typingTimer;
  DateTime _lastTypingSent = DateTime.fromMillisecondsSinceEpoch(0);

  // Souscription aux réactions partagées du pair
  StreamSubscription<({String messageId, String emoji})>? _reactionSub;

  // Souscription aux effets plein écran des messages reçus (les effets de
  // bulle, eux, se déclenchent naturellement via l'entrée en liste de la
  // nouvelle bulle — voir _MessageBubble.build).
  StreamSubscription<MeshMessage>? _effectSub;

  bool _loadingOlder = false;

  @override
  void initState() {
    super.initState();
    final key = _isGroup
        ? widget.groupId
        : (_isBroadcast ? 'broadcast' : widget.peerId);
    _isLocked = StorageService.getLockedConversations().contains(key);
    _scrollCtrl.addListener(_onScroll);
    NotificationService.openConversationId = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _isGroup
          ? widget.groupId!
          : (_isBroadcast ? 'broadcast' : widget.peerId!);
      ref.read(conversationReadsProvider.notifier).markRead(key);
      if (!_isGroup) {
        ref
            .read(meshMessagesProvider.notifier)
            .scheduleReadReceipts(_isBroadcast ? null : widget.peerId);
      }
    });
    // Réactions partagées : si le pair envoie une réaction, on joue l'overlay côté récepteur.
    _reactionSub = ref
        .read(meshMessagesProvider.notifier)
        .reactionEvents
        .listen((evt) {
          if (!mounted) return;
          HapticFeedback.mediumImpact();
          // Effet de particules ancé sur la bulle réagie.
          final origin = _centreDeLaBulle(evt.messageId);
          if (origin != null) {
            ReactionEffectOverlay.show(
              context,
              emoji: evt.emoji,
              origin: origin,
            );
          }
          // Pour ❤️ on joue en plus la salve de cœurs.
          if (evt.emoji == '❤️') {
            HeartBurstOverlay.show(context, origine: origin);
          }
        });
    // Effets plein écran reçus d'un pair — l'expéditeur les déclenche déjà
    // lui-même dans _send() ; ici on couvre le destinataire.
    final myId = ref.read(meshRepositoryProvider).myId;
    _effectSub = ref.read(meshRepositoryProvider).newMessageEvents.listen((
      msg,
    ) {
      if (!mounted) return;
      if (msg.senderId == myId ||
          msg.effect == null ||
          !kFullscreenEffects.contains(msg.effect)) {
        return;
      }
      final belongsHere = _isGroup
          ? msg.groupId == widget.groupId
          : (_isBroadcast
                ? msg.groupId == null && msg.targetId == null
                : msg.senderId == widget.peerId);
      if (belongsHere) MessageEffectOverlay.play(context, msg.effect!);
    });
  }

  // ─────────────────────────────────────────────────────────────
  //  RECHERCHE ET SAUT DANS L'HISTORIQUE
  // ─────────────────────────────────────────────────────────────

  void _openSearch() {
    OuroHaptics.light();
    setState(() => _searching = true);
    // Le clavier ne s'ouvre qu'après la construction de la barre : le
    // demander plus tôt viserait un champ qui n'existe pas encore.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    _searchCtrl.clear();
    setState(() {
      _searching = false;
      _query = '';
      _hits = const [];
      _hitIndex = 0;
    });
  }

  /// Le type du dernier message envoyé, pour le fond adaptatif.
  ///
  /// En mode adaptatif, le fond change légèrement selon le type du
  /// dernier message : texte, photo, ou vocal.
  String _lastMessageType(List<MeshMessage> messages, String myId) {
    final sent = messages.where((m) => m.senderId == myId).toList();
    if (sent.isEmpty) return 'text';
    final last = sent.last;
    if (last.type == 'file') {
      if (last.fileMimeType?.startsWith('image') ?? false) return 'photo';
      if (last.fileMimeType?.startsWith('audio') ?? false) return 'audio';
    }
    return 'text';
  }

  /// Recalcule les occurrences et saute d'emblée à la plus récente.
  void _runSearch(String raw, List<MeshMessage> messages) {
    final query = raw.trim().toLowerCase();
    if (query.isEmpty) {
      setState(() {
        _query = '';
        _hits = const [];
        _hitIndex = 0;
      });
      return;
    }

    // Les messages arrivent du plus ancien au plus récent ; on inverse
    // pour que le premier résultat proposé soit le plus récent — c'est
    // presque toujours celui qu'on cherche.
    final hits = <String>[];
    for (var i = messages.length - 1; i >= 0; i--) {
      final m = messages[i];
      // Un fichier n'a pas de texte : on cherche dans son nom.
      final haystack = (m.type == 'file' ? (m.fileName ?? '') : m.content)
          .toLowerCase();
      if (haystack.contains(query)) hits.add(m.id);
    }

    setState(() {
      _query = query;
      _hits = hits;
      _hitIndex = 0;
    });
    if (hits.isNotEmpty) _jumpToMessage(hits.first, messages);
  }

  void _gotoHit(int delta, List<MeshMessage> messages) {
    if (_hits.isEmpty) return;
    OuroHaptics.selection();
    setState(() {
      _hitIndex = (_hitIndex + delta) % _hits.length;
      if (_hitIndex < 0) _hitIndex += _hits.length;
    });
    _jumpToMessage(_hits[_hitIndex], messages);
  }

  /// Amène un message à l'écran et le fait clignoter.
  ///
  /// ⚠️ DEUX CAS, ET C'EST LE SECOND QUI EST DÉLICAT.
  ///
  /// Si la bulle est déjà construite (visible ou dans la zone de cache),
  /// `ensureVisible` l'amène proprement, avec une animation. Sinon elle
  /// n'existe tout simplement pas : une liste ne fabrique que ce qu'elle
  /// affiche. On saute alors À L'ESTIME, au prorata de la position du
  /// message dans l'historique, puis on affine une fois la bulle
  /// construite. L'estimation est grossière — les bulles n'ont pas
  /// toutes la même hauteur — mais elle amène assez près pour que la
  /// seconde passe termine le travail.
  void _jumpToMessage(String messageId, List<MeshMessage> messages) {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;

    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        duration: DesignTokens.durationNormal,
        curve: Curves.easeOutCubic,
        alignment: 0.35,
      );
      _flash(messageId);
      return;
    }

    final index = messages.indexWhere((m) => m.id == messageId);
    if (index < 0 || !_scrollCtrl.hasClients) return;
    final extent = _scrollCtrl.position.maxScrollExtent;
    final target = (extent * (index / messages.length)).clamp(0.0, extent);
    _scrollCtrl.jumpTo(target);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _messageKeys[messageId]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: DesignTokens.durationFast,
          curve: Curves.easeOutCubic,
          alignment: 0.35,
        );
      }
      _flash(messageId);
    });
  }

  void _flash(String messageId) {
    _flashTimer?.cancel();
    setState(() => _flashedId = messageId);
    _flashTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) setState(() => _flashedId = null);
    });
  }

  /// Surveille si on est en train de lire les messages tout en bas (le
  /// message le plus récent) ou remonté plus haut dans l'historique —
  /// c'est ce qui décide si le petit bouton flottant « nouveaux
  /// messages » doit apparaître.
  ///
  /// Suit aussi la vélocité du scroll pour l'effet « bulles qui
  /// respirent » — quand on scroll vite, les bulles se compressent
  /// légèrement (scale 0.97), et quand on s'arrête, elles reviennent
  /// à la normale avec un micro-spring.
  double _scrollVelocity = 0;
  double _lastScrollOffset = 0;
  DateTime _lastScrollTime = DateTime.now();

  void _onScroll() {
    final atBottom =
        _scrollCtrl.position.maxScrollExtent - _scrollCtrl.offset < 80;
    if (atBottom && _showJumpButton) {
      setState(() {
        _showJumpButton = false;
        _unreadWhileScrolled = 0;
      });
    } else if (!atBottom && !_showJumpButton) {
      setState(() => _showJumpButton = true);
    }
    // Tracker la vélocité via la différence de position entre deux ticks.
    final now = DateTime.now();
    final dt = now.difference(_lastScrollTime).inMilliseconds;
    final offset = _scrollCtrl.offset;
    if (dt > 0) {
      final speed = (offset - _lastScrollOffset).abs() / dt;
      final normalized = (speed * 16).clamp(0.0, 1.0); // ~1 frame at 60fps
      if ((normalized - _scrollVelocity).abs() > 0.05) {
        setState(() => _scrollVelocity = normalized);
      }
    }
    _lastScrollOffset = offset;
    _lastScrollTime = now;
  }

  @override
  void dispose() {
    final key = _isGroup
        ? widget.groupId
        : (_isBroadcast ? 'broadcast' : widget.peerId);
    if (NotificationService.openConversationId == key) {
      NotificationService.openConversationId = null;
    }
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _flashTimer?.cancel();
    _typingTimer?.cancel();
    _filetVol?.cancel();
    _ampTimer?.cancel();
    _posSub?.cancel();
    _durSub?.cancel();
    _completeSub?.cancel();
    _reactionSub?.cancel();
    _effectSub?.cancel();
    _player?.dispose();
    // Quitter la conversation pendant un enregistrement doit couper le
    // micro : le laisser ouvert en arrière-plan est autant un problème de
    // vie privée que de batterie.
    if (_recording) {
      unawaited(
        _recorder.stop().catchError((e) {
          debugPrint('[Chat] arrêt micro à la fermeture: $e');
          return null;
        }),
      );
    }
    _recorder.dispose();
    super.dispose();
  }

  /// Fait défiler la conversation jusqu'au tout dernier message — en
  /// glissant doucement (`animated: true`, par exemple après l'envoi
  /// d'un message) ou instantanément (à l'ouverture de l'écran).
  void _scrollToBottom({bool animated = true}) {
    if (!_scrollCtrl.hasClients) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollCtrl.hasClients) return;
      if (animated) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: 400.ms,
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);
      }
      setState(() => _showJumpButton = false);
    });
  }

  /// Prévient l'autre personne « je suis en train d'écrire » — mais pas
  /// à chaque lettre tapée, seulement toutes les 2 secondes maximum
  /// (pour ne pas spammer le réseau mesh à chaque frappe de clavier).
  void _sendTypingSignal() {
    if (_isBroadcast || _isGroup) return;
    final now = DateTime.now();
    if (now.difference(_lastTypingSent).inMilliseconds < 2000) return;
    _lastTypingSent = now;
    ref.read(meshRepositoryProvider).sendTyping(targetId: _targetId);
  }

  void _onTextChanged(String _) {
    if (_inputCtrl.text.trim().isEmpty) {
      _typingTimer?.cancel();
      return;
    }
    _sendTypingSignal();
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 4), _sendTypingSignal);
  }

  /// Envoie vraiment le message tapé dans le champ de texte — vide le
  /// champ, joue un éventuel effet spécial choisi (voir
  /// `message_effects.dart`), et fait défiler jusqu'en bas pour voir le
  /// nouveau message.
  /// Ouvre le panneau « + » et exécute le choix.
  ///
  /// ⚠️ Ce panneau REMPLACE trois boutons qui étaient alignés dans la
  /// barre de saisie. Ce n'est pas qu'une question d'encombrement : sur
  /// un petit écran, trois icônes plus le champ plus le micro laissaient
  /// une zone de frappe étroite, et chaque icône était une cible de
  /// moins de quarante-quatre points — sous le minimum tactile. Une
  /// seule cible large, et chaque action gagne un libellé lisible.
  Future<void> _openAttachSheet() async {
    final res = await pickAttachment(context);
    if (res == null || !mounted) return;

    // Une photo prise dans la bande des récents : elle part directement,
    // sans repasser par le sélecteur système. C'est tout l'intérêt de la
    // bande — deux gestes économisés sur l'action la plus fréquente.
    final asset = res.asset;
    if (asset != null) {
      await _envoyerAsset(asset);
      return;
    }

    switch (res.choix!) {
      case AttachChoice.media:
        await _pickAndSendFile(filtre: FileType.media);
      case AttachChoice.document:
        await _pickAndSendFile(filtre: FileType.any);
      case AttachChoice.sticker:
        await _sendSticker();
      case AttachChoice.position:
        await _shareLocation();
    }
  }

  /// Envoie un média choisi dans la bande des récents.
  ///
  /// ⚠️ On passe par `file`, PAS par `originBytes`. `originBytes` fait
  /// remonter la photo entière à travers le canal de méthodes Flutter,
  /// soit deux copies en mémoire du fichier complet — exactement ce qui
  /// tuait l'application sur les gros fichiers (voir `_pickAndSendFile`).
  /// On récupère donc le chemin, et on lit les octets nous-mêmes.
  Future<void> _envoyerAsset(AssetEntity asset) async {
    try {
      final fichier = await asset.file;
      if (fichier == null || !mounted) return;

      final taille = await fichier.length();
      if (taille > _maxFileSizeBytes) {
        ref.read(toastProvider.notifier).show(
              'Fichier trop volumineux (max 50 Mo)',
              type: DropletToastType.error,
            );
        return;
      }

      final nom = await asset.titleAsync;
      final me = StorageService.currentUser;
      await ref.read(meshMessagesProvider.notifier).sendFile(
            pseudo: me?.pseudo ?? 'Moi',
            fileName: nom.isNotEmpty ? nom : fichier.uri.pathSegments.last,
            bytes: await fichier.readAsBytes(),
            mimeType: asset.type == AssetType.video
                ? 'video/mp4'
                : 'image/jpeg',
            targetId: _targetId,
          );
      if (mounted) _scrollToBottom();
    } catch (e) {
      debugPrint('[Chat] envoi du média récent impossible: $e');
      if (mounted) {
        ref.read(toastProvider.notifier).show(
              'Impossible de lire ce média',
              type: DropletToastType.error,
            );
      }
    }
  }

  /// Ouvre le panneau de stickers et envoie celui qu'on choisit.
  ///
  /// Le sticker part comme un message texte ordinaire : c'est un ou
  /// deux emojis, quelques octets. Il traverse donc le mesh
  /// instantanément, là où une image de sticker demanderait un transfert
  /// de fichier complet — voir `sticker_picker.dart` pour le
  /// raisonnement.
  Future<void> _sendSticker() async {
    final sticker = await pickSticker(context);
    if (sticker == null || !mounted) return;
    _inputCtrl.text = sticker;
    await _send();
  }

  /// Partage sa position dans la conversation.
  ///
  /// Elle voyage comme un MESSAGE TEXTE ordinaire, avec un préfixe
  /// reconnaissable : `📍loc:latitude,longitude`. Ce choix n'est pas un
  /// raccourci — c'est ce qui rend le partage fiable.
  ///
  /// Une position pèse quarante octets. En passant par le canal des
  /// messages, elle profite de tout ce qui existe déjà : le chiffrement
  /// de bout en bout, la file d'attente qui réessaie, l'accusé de
  /// réception, et le relais par les téléphones intermédiaires. Un
  /// nouveau type de paquet aurait fallu redévelopper tout cela, et un
  /// téléphone équipé d'une version antérieure de Droplet n'aurait rien
  /// reçu du tout — alors qu'ici, il voit au pire une ligne de texte
  /// avec des coordonnées.
  Future<void> _shareLocation() async {
    OuroHaptics.selection();
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ref
            .read(toastProvider.notifier)
            .show(
              'Localisation refusée — activez-la dans les réglages du '
              'téléphone pour partager votre position.',
              type: DropletToastType.warning,
            );
        return;
      }

      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show('Relevé de la position…', type: DropletToastType.info);

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      _inputCtrl.text = LocationMessage.encode(
        position.latitude,
        position.longitude,
      );
      await _send();
    } catch (e) {
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show(
            'Position indisponible — réessayez à ciel ouvert.',
            type: DropletToastType.error,
          );
    }
  }

  /// Fait décoller la copie du message vers sa place dans la liste.
  ///
  /// Les messages très longs sont écartés : une bulle de dix lignes qui
  /// traverse l'écran attire l'œil sur elle plutôt que sur le geste, et
  /// la copie diffère alors trop de la vraie bulle pour que le raccord
  /// passe inaperçu.
  void _lancerVolDEnvoi(String texte) {
    if (texte.length > 220) return;
    // Un sticker ne vole pas : ce qui part sur le mesh est une
    // référence technique (`🎞tgs:lot/nom`), et la voir traverser
    // l'écran en toutes lettres serait exactement l'inverse de l'effet
    // recherché. Idem pour une position partagée.
    if (AnimatedStickerCatalog.estUneReference(texte)) return;
    if (LocationMessage.tryParse(texte) != null) return;

    // ⚠️ LES QUATRE VALEURS DE GÉOMÉTRIE CI-DESSOUS SONT DES COPIES
    // D'AILLEURS, ET ELLES DOIVENT LE RESTER.
    //
    //   • `paddingDepart` = le `contentPadding` du `TextField` (voir
    //     `_champ()`), pour que la copie décolle exactement là où était
    //     le texte ;
    //   • `paddingArrivee` et `rayonArrivee` = les marges et l'arrondi
    //     de la vraie bulle de texte ;
    //   • `largeurMaxBulle` = la contrainte de largeur des bulles.
    //
    // Elles sont passées plutôt que recopiées dans
    // `send_flight_animation.dart` pour une raison précise : une
    // constante recopiée dans deux fichiers finit toujours par diverger,
    // et ici la divergence ne se voit pas dans le code — elle se voit à
    // l'écran, sous forme d'un saut de la bulle au moment où elle se
    // pose.
    final lance = SendFlight.lancer(
      context: context,
      depuis: _champSaisieKey,
      zoneListe: _zoneListeKey,
      texte: texte,
      couleurBulle: OuroColors.accent,
      styleTexte: OuroTypography.body.copyWith(color: Colors.white),
      couleurTexteDepart: OuroColors.label,
      paddingDepart: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
      paddingArrivee: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
      rayonArrivee: const BorderRadius.only(
        topLeft: Radius.circular(DesignTokens.radiusBubble),
        topRight: Radius.circular(DesignTokens.radiusBubble),
        bottomLeft: Radius.circular(DesignTokens.radiusBubble),
        bottomRight: Radius.circular(DesignTokens.radiusBubbleTail),
      ),
      largeurMaxBulle: MediaQuery.sizeOf(context).width * 0.78,
      onRevele: _volTermine,
    );
    if (!lance) return;

    setState(() => _texteEnVol = texte);

    // Le filet de sécurité. `onRevele` est appelé à la fin du vol, à son
    // annulation et à la destruction de la copie — mais si quoi que ce
    // soit devait empêcher les trois, un message resterait invisible
    // pour toujours. Une seconde plus tard, on démasque quoi qu'il
    // arrive.
    _filetVol?.cancel();
    _filetVol = Timer(const Duration(seconds: 1), _volTermine);
  }

  /// Redonne sa visibilité à la bulle qui était en vol.
  ///
  /// ⚠️ APPELÉE DEPUIS TROIS ENDROITS AUX PHASES TRÈS DIFFÉRENTES : le
  /// listener d'animation du vol, le `dispose()` de la copie volante, et
  /// une minuterie. Le `dispose()` peut tomber en pleine construction
  /// d'image, moment où `setState` est interdit — d'où le report d'une
  /// image. Sans lui, changer de conversation pile pendant un vol
  /// déclencherait un « setState() called during build ».
  void _volTermine() {
    _filetVol?.cancel();
    _filetVol = null;
    if (_texteEnVol == null) return;
    if (!mounted) {
      _texteEnVol = null;
      return;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && _texteEnVol != null) {
          setState(() => _texteEnVol = null);
        }
      });
      return;
    }
    setState(() => _texteEnVol = null);
  }

  Future<void> _send([String? effect]) async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _typingTimer?.cancel();
    HapticFeedback.mediumImpact();
    SoundService.messageSent();

    // ⚠️ LE VOL PART AVANT LE VIDAGE DU CHAMP.
    //
    // `SendFlight` mesure la boîte de texte à l'instant où on l'appelle.
    // Une fois `clear()` passé, la barre de saisie s'est déjà rétractée à
    // sa hauteur d'une ligne : la copie décollerait alors du mauvais
    // endroit, et le raccord se verrait.
    _lancerVolDEnvoi(text);

    _inputCtrl.clear();
    final reply = _replyTarget;
    setState(() {
      _replyTarget = null;
      // Le fond avance d'un cran. Comme chez Telegram, c'est l'ENVOI qui
      // le fait bouger — pas la réception, pas le temps qui passe.
      _fondTick++;
    });
    final me = StorageService.currentUser;
    if (_isGroup) {
      await ref
          .read(meshMessagesProvider.notifier)
          .sendGroupMessage(
            me?.pseudo ?? 'Moi',
            text,
            groupId: widget.groupId!,
            replyToId: reply?.id,
            effect: effect,
          );
    } else {
      await ref
          .read(meshMessagesProvider.notifier)
          .sendMessage(
            me?.pseudo ?? 'Moi',
            text,
            targetId: _targetId,
            replyToId: reply?.id,
            effect: effect,
          );
    }
    if (!mounted) return;
    _scrollToBottom();
    if (effect != null) {
      // Effet explicitement choisi : prime sur la détection par mot-clé,
      // pour ne jamais empiler deux overlays plein écran sur un seul envoi.
      MessageEffectOverlay.play(context, effect);
    } else {
      _checkConfettiTrigger(text);
    }
  }

  /// Détecte les mots-clés de célébration et déclenche un overlay confetti.
  static final _confettiKeywords = RegExp(
    r'joyeux?\s*anniversaire|félicitations?|bravo|happy\s*birthday|toutes\s*mes\s*vœux',
    caseSensitive: false,
  );

  void _checkConfettiTrigger(String text) {
    if (_confettiKeywords.hasMatch(text)) {
      HapticFeedback.heavyImpact();
      ConfettiOverlay.show(context);
    }
  }

  /// Démarre l'enregistrement d'un message vocal — demande la
  /// permission d'utiliser le micro si nécessaire, puis commence à
  /// enregistrer dans un fichier temporaire.
  Future<void> _startRecording() async {
    // Garde contre un double déclenchement (ex. conflit de gestes tap/appui
    // long sur le bouton micro) : sans ça, un second appel à _recorder.start
    // pendant un enregistrement déjà en cours peut lever une exception
    // plateforme et laisser l'UI bloquée en état "recording".
    if (_recording || _pendingStart != null) return;
    final op = _doStartRecording();
    _pendingStart = op;
    try {
      await op;
    } finally {
      _pendingStart = null;
    }
  }

  Future<void> _doStartRecording() async {
    // Remis à zéro TOUT DE SUITE, et non dans le `setState` final : entre
    // les deux, l'utilisateur a le temps de faire glisser le micro vers
    // le haut pour verrouiller, et ce verrouillage serait alors effacé
    // par un démarrage qui se termine après lui.
    _recordingLocked = false;
    final ok = await _recorder.hasPermission();
    if (!ok) {
      ref
          .read(toastProvider.notifier)
          .show('Permission micro refusée', type: DropletToastType.error);
      return;
    }
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
      HapticFeedback.lightImpact();
      final dir = await getApplicationDocumentsDirectory();
      final recDir = Directory('${dir.path}/recordings');
      if (!await recDir.exists()) await recDir.create(recursive: true);
      final path =
          '${recDir.path}/${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      _recordStartedAt = DateTime.now();
      setState(() => _recording = true);
      _startAmpPolling();
    } catch (e) {
      debugPrint('[Chat] démarrage enregistrement: $e');
      ref
          .read(toastProvider.notifier)
          .show(
            "Impossible de démarrer l'enregistrement",
            type: DropletToastType.error,
          );
    }
  }

  /// Relève le niveau du micro à intervalle régulier, pour la forme
  /// d'onde affichée en direct ET pour celle qui partira avec le message.
  ///
  /// ⚠️ Le micro renvoie des DÉCIBELS (un nombre négatif), pas une valeur
  /// entre 0 et 1. L'ancien code appliquait directement un
  /// `clamp(0.0, 1.0)` dessus, ce qui écrasait tout à zéro : la forme
  /// d'onde restait plate et ne réagissait jamais à la voix. La
  /// conversion vit maintenant dans `VoiceNoteMeta.normalizeDb`.
  void _startAmpPolling() {
    _amplitudes.clear();
    _fullEnvelope.clear();
    _ampTimer?.cancel();
    // 80 ms plutôt que 140 : à 140 ms, un mot court passait entre deux
    // relevés et n'apparaissait pas du tout dans le dessin.
    _ampTimer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
      try {
        final amp = await _recorder.getAmplitude();
        final v = VoiceNoteMeta.normalizeDb(amp.current);
        if (!mounted) return;
        setState(() {
          // Relevé complet : sert à fabriquer la forme d'onde du message.
          // Borné pour qu'un enregistrement très long ne fasse pas
          // grossir la liste indéfiniment (10 min à 80 ms = 7500 points,
          // largement au-delà de ce qui est nécessaire).
          if (_fullEnvelope.length < 8000) _fullEnvelope.add(v);
          // Fenêtre glissante : ce qu'on voit défiler à l'écran.
          _amplitudes.add(v);
          if (_amplitudes.length > 44) _amplitudes.removeAt(0);
        });
      } catch (_) {}
    });
  }

  /// Arrête l'enregistrement en cours et envoie directement le message
  /// vocal obtenu — c'est ce qui se passe quand on relâche le doigt du
  /// bouton micro normalement (sans faire glisser vers l'annulation).
  Future<void> _stopRecording() async {
    // Un démarrage encore en vol : on le laisse aboutir, sinon on
    // conclurait à tort qu'il n'y a rien à arrêter (voir `_pendingStart`).
    final pending = _pendingStart;
    if (pending != null) await pending;
    if (!_recording) return;
    _ampTimer?.cancel();
    _ampTimer = null;

    // Durée MESURÉE, et non plus devinée à partir du poids du fichier :
    // un enregistrement fait dans le silence pèse beaucoup moins lourd
    // qu'un enregistrement fait dans le bruit, à durée identique.
    final startedAt = _recordStartedAt;
    final duration = startedAt == null
        ? Duration.zero
        : DateTime.now().difference(startedAt);
    final envelope = List<double>.from(_fullEnvelope);

    setState(() {
      _recording = false;
      _recordingLocked = false;
      _amplitudes.clear();
      _fullEnvelope.clear();
    });
    _recordStartedAt = null;

    // Un appui involontaire sur le micro produisait jusqu'ici un vocal
    // vide d'un dixième de seconde, envoyé pour de bon. En dessous d'une
    // demi-seconde il n'y a rien à écouter : on jette.
    if (duration.inMilliseconds < 500) {
      try {
        final path = await _recorder.stop();
        if (path != null) {
          final f = File(path);
          if (await f.exists()) await f.delete();
        }
      } catch (_) {}
      return;
    }

    try {
      final path = await _recorder.stop();
      if (path == null || !File(path).existsSync()) return;
      final bytes = await File(path).readAsBytes();
      final me = StorageService.currentUser;
      await ref
          .read(meshMessagesProvider.notifier)
          .sendFile(
            pseudo: me?.pseudo ?? 'Moi',
            // La durée et la forme d'onde voyagent DANS LE NOM DU FICHIER
            // (voir `voice_note.dart`) : c'est ce qui permet à l'autre
            // téléphone de les afficher sans rien changer au format des
            // paquets réseau.
            fileName: VoiceNoteMeta.encodeFileName(
              duration: duration,
              samples: envelope,
            ),
            bytes: Uint8List.fromList(bytes),
            mimeType: 'audio/m4a',
            targetId: _targetId,
            groupId: widget.groupId,
            replyToId: _replyTarget?.id,
          );
      if (mounted) setState(() => _replyTarget = null);
      _scrollToBottom();
    } catch (e) {
      debugPrint('[Chat] enregistrement: $e');
      ref
          .read(toastProvider.notifier)
          .show(
            'Envoi du message vocal impossible',
            type: DropletToastType.error,
          );
    }
  }

  /// Annule un enregistrement en cours (glissement vers l'annulation) : on
  /// arrête le recorder et on supprime le fichier temporaire, sans envoyer
  /// de message — pattern « glisser pour annuler » façon WhatsApp/Telegram.
  Future<void> _cancelRecording() async {
    final pending = _pendingStart;
    if (pending != null) await pending;
    if (!_recording) return;
    _ampTimer?.cancel();
    _ampTimer = null;
    setState(() {
      _recording = false;
      _recordingLocked = false;
      _amplitudes.clear();
      _fullEnvelope.clear();
    });
    _recordStartedAt = null;
    HapticFeedback.mediumImpact();
    try {
      final path = await _recorder.stop();
      if (path != null) {
        final f = File(path);
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      debugPrint('[Chat] annulation enregistrement: $e');
    }
  }

  static const Map<String, String> _mimeByExtension = {
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'mp3': 'audio/mpeg',
    'm4a': 'audio/m4a',
    'wav': 'audio/wav',
    'aac': 'audio/aac',
    'pdf': 'application/pdf',
  };

  String _guessMimeType(String fileName) {
    final ext = fileName.contains('.')
        ? fileName.split('.').last.toLowerCase()
        : '';
    return _mimeByExtension[ext] ?? 'application/octet-stream';
  }

  /// Au-delà, le crash observé sur appareil (OutOfMemoryError, tas ~256 Mo)
  /// devient probable : le fichier est lu en mémoire côté Dart puis
  /// ré-encodé tel quel dans les paquets mesh, sans transfert en flux.
  static const int _maxFileSizeBytes = 50 * 1024 * 1024;

  /// Ouvre le sélecteur de fichiers du téléphone (photos, documents...)
  /// et envoie le fichier choisi dans la conversation, en refusant les
  /// fichiers trop lourds (voir [_maxFileSizeBytes]).
  Future<void> _pickAndSendFile({FileType filtre = FileType.any}) async {
    try {
      // `withData: true` faisait lire le fichier ENTIER par le plugin natif
      // puis le repasser tel quel dans l'enveloppe du method channel Flutter
      // (StandardMessageCodec) — deux copies en mémoire du fichier complet,
      // ce qui provoquait un OutOfMemoryError natif (crash immédiat, tas
      // ~256 Mo) sur les fichiers volumineux. Ne récupérer que le chemin et
      // lire les octets nous-mêmes (comme pour la voix, cf. _stopRecording)
      // évite ce second passage par le method channel.
      final result = await FilePicker.platform.pickFiles(type: filtre);
      final picked = result?.files.single;
      if (picked == null || picked.path == null) return;
      if ((picked.size) > _maxFileSizeBytes) {
        ref
            .read(toastProvider.notifier)
            .show(
              'Fichier trop volumineux (max 50 Mo)',
              type: DropletToastType.error,
            );
        return;
      }
      final bytes = await File(picked.path!).readAsBytes();
      final me = StorageService.currentUser;
      await ref
          .read(meshMessagesProvider.notifier)
          .sendFile(
            pseudo: me?.pseudo ?? 'Moi',
            fileName: picked.name,
            bytes: bytes,
            mimeType: _guessMimeType(picked.name),
            targetId: _targetId,
            groupId: widget.groupId,
          );
      _scrollToBottom();
    } catch (e) {
      debugPrint('[Chat] sélection de fichier: $e');
      ref
          .read(toastProvider.notifier)
          .show('Envoi du fichier impossible', type: DropletToastType.error);
    }
  }

  /// Démarre ou arrête la lecture d'un message vocal reçu — un simple
  /// bouton « play/pause », avec une petite barre de progression qui
  /// avance pendant la lecture.
  Future<void> _toggleAudio(String fileId, String fileName) async {
    final path = await StorageService.getSharedFilePath(fileId, fileName);
    if (path == null) {
      ref
          .read(toastProvider.notifier)
          .show(
            'Audio pas encore reçu entièrement',
            type: DropletToastType.warning,
          );
      return;
    }
    if (_playingAudio && _activeAudioFile == fileId) {
      await _stopPlayback();
      return;
    }
    await _playAudioFile(fileId, path);
  }

  /// Lance la lecture d'un fichier audio déjà présent sur l'appareil.
  Future<void> _playAudioFile(String fileId, String path) async {
    _player ??= AudioPlayer();
    await _player!.stop();

    // ⚠️ Ces trois abonnements DOIVENT être annulés avant d'en créer de
    // nouveaux. `listen` ajoute un auditeur de plus à chaque lecture sans
    // jamais retirer le précédent : au bout de dix messages vocaux
    // écoutés, dix rappels se déclenchaient à chaque battement du
    // lecteur. L'oubli portait surtout sur `onPlayerComplete`, qui
    // n'était même pas stocké dans une variable.
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _completeSub?.cancel();

    _activeAudioFile = fileId;
    _activeAudioDuration = null;
    setState(() {
      _playingAudio = true;
      _playbackProgress = 0;
      _playbackPosition = Duration.zero;
      _playedVoiceNotes.add(fileId);
    });

    _durSub = _player!.onDurationChanged.listen((d) {
      _activeAudioDuration = d;
    });
    _posSub = _player!.onPositionChanged.listen((pos) {
      final total = _activeAudioDuration;
      if (!mounted || total == null || total.inMilliseconds == 0) return;
      setState(() {
        _playbackPosition = pos;
        _playbackProgress = (pos.inMilliseconds / total.inMilliseconds).clamp(
          0.0,
          1.0,
        );
      });
    });
    _completeSub = _player!.onPlayerComplete.listen((_) => _onPlaybackDone());

    try {
      await _player!.setPlaybackRate(_playbackSpeed);
      await _player!.play(DeviceFileSource(path));
    } catch (e) {
      // Fichier tronqué par un transfert interrompu, ou format que
      // l'appareil ne sait pas lire. On le dit, et on revient à l'état
      // d'arrêt — plutôt que de laisser l'exception faire tomber l'app.
      debugPrint('[Chat] lecture impossible: $e');
      await _stopPlayback();
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show(
            'Ce message vocal est illisible — il est peut-être arrivé '
            'incomplet.',
            type: DropletToastType.error,
          );
    }
  }

  Future<void> _stopPlayback() async {
    await _player?.stop();
    await _posSub?.cancel();
    await _durSub?.cancel();
    await _completeSub?.cancel();
    _posSub = null;
    _durSub = null;
    _completeSub = null;
    if (!mounted) return;
    setState(() {
      _playingAudio = false;
      _activeAudioFile = null;
      _playbackProgress = 0;
      _playbackPosition = null;
    });
  }

  /// Un vocal vient de se terminer : on enchaîne sur le suivant s'il y
  /// en a un juste après, non encore écouté.
  ///
  /// C'est le comportement de WhatsApp, et il change tout quand on
  /// reçoit plusieurs vocaux d'affilée : sans lui, il faut rappuyer sur
  /// chaque bulle, ce qui casse l'écoute exactement comme si on coupait
  /// la parole à quelqu'un.
  Future<void> _onPlaybackDone() async {
    final finished = _activeAudioFile;
    await _stopPlayback();
    if (finished == null || !mounted) return;

    final messages = _isGroup
        ? ref.read(groupMessagesProvider(widget.groupId!))
        : ref.read(
            conversationMessagesProvider(_isBroadcast ? null : widget.peerId),
          );

    final index = messages.indexWhere((m) => m.fileId == finished);
    if (index < 0) return;

    for (var i = index + 1; i < messages.length; i++) {
      final m = messages[i];
      final isVoice =
          m.type == 'file' &&
          (m.fileMimeType?.startsWith('audio') ?? false) &&
          VoiceNoteMeta.isVoiceNote(m.fileName);
      if (!isVoice) continue;
      // On n'enchaîne que sur les vocaux REÇUS et jamais écoutés :
      // rejouer ses propres messages, ou des messages déjà entendus,
      // n'a aucun sens.
      if (m.senderId == ref.read(meshRepositoryProvider).myId) return;
      if (_playedVoiceNotes.contains(m.fileId)) return;
      final path = await StorageService.getSharedFilePath(
        m.fileId ?? '',
        m.fileName ?? '',
      );
      if (path == null || !mounted) return;
      await _playAudioFile(m.fileId!, path);
      return;
    }
  }

  /// Déplace la lecture à [progress] (0..1) — glisser le doigt sur la
  /// forme d'onde. Sans ça, réécouter un mot manqué au milieu d'un vocal
  /// d'une minute obligeait à tout reprendre depuis le début.
  Future<void> _seekAudio(double progress) async {
    final total = _activeAudioDuration;
    if (_player == null || total == null) return;
    final target = Duration(
      milliseconds: (total.inMilliseconds * progress.clamp(0.0, 1.0)).round(),
    );
    await _player!.seek(target);
    if (!mounted) return;
    setState(() {
      _playbackPosition = target;
      _playbackProgress = progress.clamp(0.0, 1.0);
    });
  }

  /// Fait tourner la vitesse de lecture 1× → 1,5× → 2× → 1×.
  Future<void> _cycleSpeed() async {
    final next = switch (_playbackSpeed) {
      1.0 => 1.5,
      1.5 => 2.0,
      _ => 1.0,
    };
    setState(() => _playbackSpeed = next);
    await _player?.setPlaybackRate(next);
  }

  /// Répondre par la voix à un message précis : on vise ce message, et
  /// l'enregistrement démarre immédiatement, verrouillé (mains libres).
  ///
  /// C'est le raccourci du petit micro posé à côté d'un vocal reçu :
  /// écouter puis répondre en parlant, sans repasser par le champ de
  /// texte ni viser le bouton micro tout en bas de l'écran.
  Future<void> _replyWithVoice(MeshMessage target) async {
    if (_recording) return;
    setState(() => _replyTarget = target);
    if (_playingAudio) await _stopPlayback();
    await _startRecording();
    if (mounted && _recording) setState(() => _recordingLocked = true);
  }

  /// Ouvre la vue de fil de discussion pour un message donné.
  /// Si le message a déjà un threadId, on filtre par celui-ci.
  /// Sinon, on crée un thread avec le messageId comme threadId.
  void _openThread(MeshMessage parent) {
    final threadId = parent.threadId ?? parent.id;
    final messages = ref.read(conversationMessagesProvider(
      _isGroup ? widget.groupId : _targetId,
    ));
    final threadMessages = messages.where((m) =>
        m.threadId == threadId || m.id == threadId
    ).toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _ThreadSheet(
        parent: parent,
        threadId: threadId,
        messages: threadMessages,
        onReply: (text) {
          final me = StorageService.currentUser;
          if (_isGroup) {
            ref.read(meshMessagesProvider.notifier).sendGroupMessage(
              me?.pseudo ?? 'Moi',
              text,
              groupId: widget.groupId!,
              replyToId: parent.id,
              threadId: threadId,
            );
          } else {
            ref.read(meshMessagesProvider.notifier).sendMessage(
              me?.pseudo ?? 'Moi',
              text,
              targetId: _targetId,
              replyToId: parent.id,
              threadId: threadId,
            );
          }
        },
      ),
    );
  }

  /// Copie une pièce jointe reçue dans la galerie ou les
  /// téléchargements du téléphone.
  ///
  /// Les fichiers reçus par le mesh vivent dans le dossier PRIVÉ de
  /// Droplet : invisibles pour la galerie, et effacés si l'application
  /// est désinstallée. Les enregistrer, c'est les faire sortir de cet
  /// enclos pour de bon.
  Future<void> _saveToDevice(MeshMessage m) async {
    final path = await StorageService.getSharedFilePath(
      m.fileId ?? '',
      m.fileName ?? '',
    );
    if (path == null) {
      if (!mounted) return;
      ref
          .read(toastProvider.notifier)
          .show(
            "Fichier pas encore reçu en entier",
            type: DropletToastType.warning,
          );
      return;
    }

    final folder = await MediaService.saveToGallery(
      path: path,
      name: m.fileName ?? 'droplet',
      mimeType: m.fileMimeType ?? '',
    );

    if (!mounted) return;
    if (folder == null) {
      OuroHaptics.error();
      ref
          .read(toastProvider.notifier)
          .show('Enregistrement impossible', type: DropletToastType.error);
      return;
    }
    OuroHaptics.success();
    ref
        .read(toastProvider.notifier)
        .show('Enregistré dans $folder', type: DropletToastType.success);
  }

  /// Ouvre le menu contextuel ancré sur le message.
  ///
  /// Voir `message_context_menu.dart` : le fond se floute, le message
  /// choisi reste net et se soulève, les émojis se déploient au-dessus
  /// et les actions apparaissent en dessous — au lieu d'une feuille
  /// anonyme qui monte du bas de l'écran.
  void _openMessageActions(MeshMessage m) {
    final notifier = ref.read(meshMessagesProvider.notifier);
    final canSave =
        m.type == 'file' &&
        m.fileId != null &&
        !VoiceNoteMeta.isVoiceNote(m.fileName);

    unawaited(
      showMessageContextMenu(
        context: context,
        // La bulle réelle sert d'ancre : c'est elle qui donne au menu sa
        // position exacte à l'écran.
        anchorKey: _messageKeys.putIfAbsent(m.id, GlobalKey.new),
        preview: _previewOf(m),
        mine: m.senderId == ref.read(meshRepositoryProvider).myId,
        current: m.reactions,
        onReact: (emoji) {
          HapticFeedback.mediumImpact();
          notifier.toggleReaction(m.id, emoji);
          // Effet de particules ancré sur la bulle.
          final origin = _centreDeLaBulle(m.id);
          if (origin != null) {
            ReactionEffectOverlay.show(context, emoji: emoji, origin: origin);
          }
        },
        actions: [
          // ⚠️ « RÉESSAYER » PASSE EN PREMIER, ET SEULEMENT SI ÇA A
          // ÉCHOUÉ.
          //
          // Quand on ouvre le menu d'un message en échec, on ne cherche
          // qu'une chose : le renvoyer. Le placer sous « Répondre » et
          // « Copier » obligerait à lire une liste pour trouver la seule
          // action qui compte à ce moment-là.
          //
          // Il n'apparaît PAS sur les autres messages : proposer de
          // renvoyer quelque chose qui est déjà arrivé sèmerait le doute
          // sur ce qui a réellement été livré.
          if (m.status == MessageStatus.failed)
            MessageAction(
              icon: Icons.refresh_rounded,
              label: 'Réessayer',
              onTap: () {
                HapticFeedback.mediumImpact();
                notifier.renvoyer(m.id);
              },
            ),
          MessageAction(
            icon: Icons.reply_rounded,
            label: 'Répondre',
            onTap: () => setState(() => _replyTarget = m),
          ),
          MessageAction(
            icon: Icons.forum_rounded,
            label: 'Répondre dans le fil',
            onTap: () => _openThread(m),
          ),
          if (m.type != 'file')
            MessageAction(
              icon: Icons.copy_rounded,
              label: 'Copier',
              onTap: () {
                Clipboard.setData(ClipboardData(text: m.content));
                ref
                    .read(toastProvider.notifier)
                    .show('Message copié', type: DropletToastType.info);
              },
            ),
          // Modifier : uniquement sur mes messages texte, pas les fichiers.
          if (m.type != 'file' && m.senderId == ref.read(meshRepositoryProvider).myId)
            MessageAction(
              icon: Icons.edit_rounded,
              label: 'Modifier',
              onTap: () => _editMessage(m),
            ),
          // L'enregistrement n'est proposé que sur les messages qui
          // portent réellement un fichier — et pas sur les vocaux, dont le
          // nom encodé n'aurait aucun sens dans une galerie.
          if (canSave)
            MessageAction(
              icon: Icons.download_rounded,
              label: 'Enregistrer',
              onTap: () => _saveToDevice(m),
            ),
          MessageAction(
            icon: Icons.delete_outline_rounded,
            label: 'Supprimer',
            destructive: true,
            // La bulle part physiquement dans une corbeille au lieu de
            // s'évaporer entre deux images. La suppression réelle a lieu
            // au moment où elle y entre — voir `trash_toss_overlay.dart`
            // pour pourquoi ce n'est pas avant.
            onTap: () => unawaited(_supprimerAvecCorbeille(m)),
          ),
        ],
      ),
    );
  }

  /// Supprime [m] en montrant où il part.
  ///
  /// ⚠️ ON ATTEND QUE LE MENU AIT FINI DE SE REFERMER.
  ///
  /// `_ActionRow` fait `Navigator.pop()` puis appelle cette fonction. Le
  /// menu contextuel met 220 ms à se retirer (`reverseTransitionDuration`
  /// dans `message_context_menu.dart`), et pendant tout ce temps il
  /// affiche SA PROPRE copie de la bulle, qui revient se poser sur
  /// l'originale. Lancer le vol tout de suite ferait donc voler deux
  /// bulles identiques dans deux directions opposées.
  ///
  /// Les 40 ms de marge évitent de dépendre au dixième de milliseconde
  /// d'une durée définie dans un autre fichier.
  Future<void> _supprimerAvecCorbeille(MeshMessage m) async {
    final notifier = ref.read(meshMessagesProvider.notifier);

    await Future<void>.delayed(const Duration(milliseconds: 260));
    if (!mounted) return;

    final boite =
        _messageKeys[m.id]?.currentContext?.findRenderObject() as RenderBox?;
    // La bulle n'est plus à l'écran (défilement, message déjà parti) : on
    // supprime sans mise en scène. Une animation absente ne doit jamais
    // empêcher l'action qu'elle illustre.
    if (boite == null || !boite.hasSize || !boite.attached) {
      notifier.deleteMessage(m.id);
      return;
    }

    TrashTossOverlay.jouer(
      context,
      origine: boite.localToGlobal(Offset.zero) & boite.size,
      apercu: _previewOf(m),
      onAvalee: () => notifier.deleteMessage(m.id),
    );
  }

  /// Ouvre un dialogue pour modifier le contenu d'un message.
  void _editMessage(MeshMessage m) {
    final ctrl = TextEditingController(text: m.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Modifier le message'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: null,
          magnifierConfiguration: TextMagnifier.adaptiveMagnifierConfiguration,
          decoration: const InputDecoration.collapsed(hintText: 'Message'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Annuler'),
          ),
          TextButton(
            onPressed: () {
              final newContent = ctrl.text.trim();
              if (newContent.isNotEmpty && newContent != m.content) {
                ref.read(meshMessagesProvider.notifier).editMessage(m.id, newContent);
              }
              Navigator.of(ctx).pop();
            },
            child: const Text('Modifier'),
          ),
        ],
      ),
    );
  }

  /// Ce qu'on écrit sous le nom quand le pair n'est pas joignable.
  ///
  /// ⚠️ « HORS LIGNE » EST UN CONTRESENS DANS DROPLET, et c'est pour ça
  /// que cette méthode existe.
  ///
  /// Dans une messagerie ordinaire, « hors ligne » veut dire « rien ne
  /// partira ». Ici, c'est faux : le message est chiffré, mis en file, et
  /// repartira dès que la personne repassera à portée — ou sera relayé
  /// par un appareil intermédiaire. Annoncer une panne là où il n'y a
  /// qu'une attente pousse l'utilisateur à renoncer à écrire.
  ///
  /// On dit donc DEPUIS QUAND on ne l'a pas vue, ce qui est une
  /// information utile, plutôt qu'un verdict qui n'est pas le bon.
  ///
  /// ⚠️ « JAMAIS RENCONTRÉ » NE DOIT PAS S'AFFICHER SOUS UNE
  /// CONVERSATION QUI EXISTE.
  ///
  /// La version précédente ne regardait que la fiche du pair. Or cette
  /// fiche peut manquer — un identifiant qui a changé entre deux
  /// sessions, une table nettoyée, une conversation ouverte depuis un
  /// message reçu par relais. On affichait alors « Jamais rencontré »
  /// juste en dessous d'un fil de messages échangés le matin même : une
  /// affirmation que l'écran lui-même contredisait, ce qui apprend à
  /// l'utilisateur à ne plus croire ce qui est écrit là.
  ///
  /// Un message REÇU est une preuve de rencontre plus solide que la
  /// fiche, puisqu'il ne peut pas exister sans que l'appareil d'en face
  /// ait été joignable. On s'en sert donc de repli, et « jamais
  /// rencontré » n'est plus dit que lorsque c'est vrai : ni fiche, ni
  /// le moindre message reçu.
  ///
  /// ⚠️ REÇU, ET PAS « ÉCHANGÉ ». Un message envoyé ne prouve rien : il
  /// part en file d'attente et peut y rester des heures sans que
  /// personne ne soit passé à portée.
  static String _sousTitreHorsLigne(PeerRecord? fiche, DateTime? dernierRecu) {
    if (fiche == null && dernierRecu == null) return 'Jamais rencontré';
    final repere = fiche?.lastSeen ?? dernierRecu!;
    final ecart = DateTime.now().difference(repere);
    if (ecart.inMinutes < 1) return 'Vu à l\'instant';
    if (ecart.inMinutes < 60) return 'Vu il y a ${ecart.inMinutes} min';
    if (ecart.inHours < 24) return 'Vu il y a ${ecart.inHours} h';
    if (ecart.inDays == 1) return 'Vu hier';
    if (ecart.inDays < 7) return 'Vu il y a ${ecart.inDays} jours';
    return 'Hors de portée';
  }

  /// De quoi désigner un pair dont on n'a jamais appris le pseudonyme.
  ///
  /// Les huit premiers caractères de l'empreinte suffisent à distinguer
  /// deux contacts à l'œil, tiennent dans une barre de titre, et disent
  /// honnêtement qu'on ne connaît pas encore cette personne — là où
  /// l'empreinte entière ne disait rien du tout.
  // ⚠️ LA RÈGLE DE NOMMAGE VIT DANS `nom_pair.dart`, PAS ICI.
  //
  // Cet écran en portait sa propre copie. Le résolveur central en avait
  // une autre, légèrement différente — et c'est elle qui affichait des
  // empreintes brutes dans le journal d'appels pendant que la
  // conversation, elle, affichait proprement « Pair 3f7a1c92 ».
  //
  // Deux copies d'une même règle finissent toujours par diverger, et la
  // divergence se voit à l'écran : le même contact nommé de deux façons
  // selon l'endroit où on le regarde. Une application soignée ne fait
  // jamais ça.

  /// La copie de la bulle affichée dans le menu.
  ///
  /// ⚠️ ON NE DÉPLACE PAS L'ORIGINALE — elle vit dans la liste, qui
  /// continue d'exister derrière le flou. On en construit donc une
  /// seconde, posée exactement à sa place. L'illusion tient tant que les
  /// deux se ressemblent : mêmes réglages, mêmes couleurs, seuls les
  /// gestes et la lecture audio sont retirés (un menu n'est pas
  /// l'endroit où l'on démarre un vocal).
  Widget _previewOf(MeshMessage m) {
    final myId = ref.read(meshRepositoryProvider).myId;
    final isAudio =
        m.type == 'file' && (m.fileMimeType?.startsWith('audio') ?? false);
    final isImage =
        m.type == 'file' && (m.fileMimeType?.startsWith('image') ?? false);
    final isVideo =
        m.type == 'file' && (m.fileMimeType?.startsWith('video') ?? false);

    return _MessageBubble(
      message: m,
      mine: m.senderId == myId,
      isBroadcast: _isBroadcast,
      isGroup: _isGroup,
      isAudio: isAudio,
      isImage: isImage,
      isVideo: isVideo,
      playingAudio: false,
      voicePlayed: _playedVoiceNotes.contains(m.fileId),
      onPlayAudio: () {},
      onLongPress: () {},
    );
  }

  @override
  Widget build(BuildContext context) {
    final messages = _isGroup
        ? ref.watch(groupMessagesProvider(widget.groupId!))
        : ref.watch(
            conversationMessagesProvider(_isBroadcast ? null : widget.peerId),
          );
    final peers = ref.watch(meshPeerListProvider);
    final repo = ref.watch(meshRepositoryProvider);
    final myId = repo.myId;
    final typingPeers = ref.watch(typingPeersProvider);
    final group = _isGroup
        ? ref.watch(groupInfoProvider(widget.groupId!))
        : null;

    // Le nom affiché en tête de la conversation.
    //
    // ⚠️ L'IDENTIFIANT BRUT N'EST PAS UN NOM. C'est une empreinte de clé
    // publique — soixante-quatre caractères hexadécimaux. L'afficher,
    // c'est titrer une conversation « baee7a1f92f5e7d51b92… », ce qui ne
    // dit rien à personne.
    //
    // La version précédente ne cherchait le pseudonyme que dans la liste
    // des pairs CONNECTÉS À CET INSTANT. Or dans une app mesh, l'état
    // normal d'un contact est d'être hors de portée : on ouvre une
    // conversation pour relire, pour écrire un message qui partira plus
    // tard. L'identifiant brut n'apparaissait donc pas dans un cas rare —
    // il apparaissait dès qu'on s'éloignait de quelques mètres.
    //
    // On interroge donc d'abord la table des pairs déjà rencontrés, qui
    // survit aux déconnexions, et on ne retombe sur un identifiant
    // abrégé qu'en dernier recours — pour un pair dont on n'a
    // effectivement jamais appris le nom.
    //
    // ⚠️ La fiche du pair est lue UNE SEULE FOIS pour toute l'image.
    // `getPeerRecord` n'est pas une simple lecture de champ : il
    // redécode en JSON la table entière des pairs connus. L'appeler deux
    // fois par `build()` — ce que faisait la version précédente —
    // revenait à analyser tout l'annuaire deux fois par image pendant
    // qu'on tape ou qu'on fait défiler.
    final peerRecord = (!_isBroadcast && !_isGroup)
        ? StorageService.getPeerRecord(widget.peerId!)
        : null;

    // ⚠️ SEUL UN MESSAGE REÇU PROUVE QU'ON A VU LE PAIR.
    //
    // La version précédente prenait `messages.last` — le dernier message
    // de la conversation, quel qu'en soit l'auteur. Conséquence : venir
    // d'écrire suffisait à afficher « Vu à l'instant », alors que le
    // pair n'avait rien fait du tout. On datait notre propre activité en
    // la présentant comme la sienne.
    //
    // Un message ENVOYÉ ne prouve rien : il part en file d'attente, et
    // peut y rester des heures. Un message REÇU, lui, ne peut pas
    // exister sans que l'appareil d'en face ait été joignable.
    //
    // On remonte donc la liste à l'envers jusqu'au premier message qui
    // ne vient pas de nous. C'est un parcours, mais borné en pratique :
    // dans une conversation vivante, il s'arrête au bout de quelques
    // éléments.
    DateTime? dernierRecu;
    for (var i = messages.length - 1; i >= 0; i--) {
      if (messages[i].senderId != myId) {
        dernierRecu = messages[i].timestamp;
        break;
      }
    }

    String peerPseudo = _isGroup
        ? (group?.name ?? 'Groupe')
        : _isBroadcast
            ? 'Diffusion mesh'
            : nomDuPair(widget.peerId!, [peerRecord?.pseudo]);
    bool online = false;
    bool peerKeyKnown = false;
    // À quelle distance, en nombre d'appareils, se trouve ce pair.
    // 0 = liaison directe ; au-delà, on ne le joint qu'à travers d'autres.
    int sautsVersPair = 0;
    // Être « connecté » et être « appelable » sont deux choses
    // différentes : la voix ne passe qu'en liaison directe Wi-Fi, jamais
    // en Bluetooth (bien trop lent) ni à travers un relais. Le bouton
    // d'appel affichait pourtant l'état « connecté », et lancer l'appel
    // se soldait alors par un message d'erreur — autant le dire avant.
    bool callable = false;
    // Vrai quand le pair a perdu ses liens mais qu'on lui laisse encore
    // sa chance (voir `ConnectedPeer.reconnecting`). On ne l'annonce
    // SURTOUT PAS comme connecté : il est présent dans la liste, ce qui
    // permet aux messages d'attendre plutôt que d'échouer, mais rien ne
    // part pour l'instant. Afficher « Connecté » ici serait exactement
    // le genre de mensonge que cette application s'interdit ailleurs sur
    // les accusés de livraison.
    bool reconnecting = false;
    if (!_isBroadcast && !_isGroup) {
      for (final p in peers) {
        if (p.peerId == widget.peerId) {
          peerPseudo = p.pseudo;
          reconnecting = p.reconnecting;
          online = !p.reconnecting;
          sautsVersPair = p.hopCount;
          peerKeyKnown = p.publicKey != null;
          callable =
              p.hopCount == 0 &&
              (p.transports.contains(TransportKind.localWifi) ||
                  p.transports.contains(TransportKind.nativeP2P));
          break;
        }
      }
    }
    final peerVerified = peerRecord?.isVerifiedAndCurrent ?? false;
    final peerKeyChanged = peerRecord?.keyChangedSinceVerification ?? false;
    final groupMemberCount = group?.activeMembers.length ?? 0;

    final peerTyping =
        !_isBroadcast && !_isGroup && typingPeers.contains(widget.peerId);

    final fondCouleurs = ref.watch(chatBackgroundProvider) == 'adaptatif'
        ? TelegramGradientPalettes.pourContenu(
            _lastMessageType(messages, myId),
            sombre: Theme.of(context).brightness == Brightness.dark,
          )
        : TelegramGradientPalettes.pour(
            ref.watch(chatBackgroundProvider),
            sombre: Theme.of(context).brightness == Brightness.dark,
          );

    final items = _buildItems(messages);

    // Un annuaire des messages par identifiant, construit UNE fois par
    // image.
    //
    // ⚠️ C'est ce qui remplace un `messages.where(...)` qui était fait à
    // l'intérieur du constructeur de chaque bulle. Retrouver le message
    // cité coûtait donc un balayage de TOUTE la conversation, par bulle
    // citée et par image : dans un fil de mille messages où l'on se
    // répond souvent, cela faisait des dizaines de milliers de
    // comparaisons soixante fois par seconde — pendant le défilement,
    // c'est-à-dire au pire moment. Ici, une seule construction d'index,
    // puis des recherches instantanées.
    final parId = {for (final m in messages) m.id: m};

    // Les clés de repérage des bulles ne concernent que les messages
    // encore présents. Sans ce nettoyage, supprimer des messages laissait
    // leurs `GlobalKey` dans l'annuaire pour le reste de la session — et
    // une `GlobalKey` n'est pas gratuite : Flutter en tient un registre
    // global. Le seuil évite de reparcourir l'annuaire à chaque image.
    if (_messageKeys.length > parId.length * 2 + 50) {
      _messageKeys.removeWhere((id, _) => !parId.containsKey(id));
    }

    // Compte les messages non lus pendant qu'on est remonté dans
    // l'historique.
    _maybeCountUnread(messages, myId);

    // Conversation verrouillée — écran biométrique avant d'accéder au contenu.
    if (_isLocked) {
      final pseudo = _isGroup ? (group?.name ?? 'Groupe') : peerPseudo;
      return ConversationLockScreen(
        pseudo: pseudo,
        onUnlocked: () => setState(() => _isLocked = false),
      );
    }

    return Scaffold(
      // Transparent : c'est le dégradé animé posé en fond du `Stack`
      // ci-dessous qui donne sa couleur à l'écran.
      backgroundColor: Colors.transparent,
      // ⚠️ INDISPENSABLE DEPUIS QUE LA BARRE DE TITRE EST TRANSLUCIDE.
      //
      // Sans cela, le corps de l'écran commence SOUS la barre : la zone
      // de la barre n'a alors rien derrière elle, et le flou ne floute
      // que du vide — d'où la bande grise sale observée à l'écran, où le
      // sous-titre devenait presque illisible.
      //
      // En étendant le corps derrière la barre, c'est le fond de
      // discussion qui passe dessous, et le flou a enfin quelque chose à
      // travailler. C'est aussi ce que fait iOS 26 : le fond d'écran
      // d'une conversation remonte jusqu'en haut.
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        // Matériau flou sous la barre : le contenu de la conversation
        // défile DERRIÈRE elle et s'y estompe, au lieu de disparaître
        // sous un bandeau opaque. C'est ce détail qui donne aux barres
        // d'iOS leur impression de profondeur.
        // ── UNE BARRE QUI LAISSE PASSER LA CONVERSATION ─────────────
        //
        // Voile le plus léger disponible, et PLUS DE FILET DE SÉPARATION
        // en bas.
        //
        // C'est l'autre moitié du geste d'iOS 26 : la barre de titre
        // d'une conversation devient transparente, et le fond comme les
        // messages restent visibles en dessous. Le trait gris qui la
        // fermait la transformait en bandeau posé SUR l'écran ; sans
        // lui, elle appartient à l'écran.
        //
        // Le voile ne disparaît pas pour autant : c'est lui qui garantit
        // que le nom du contact reste lisible quand une photo sombre
        // passe dessous.
        flexibleSpace: const OuroBlurSurface(
          material: OuroMaterial.ultraThin,
          child: SizedBox.expand(),
        ),
        leadingWidth: 40,
        leading: _searching
            ? IconButton(
                tooltip: 'Fermer la recherche',
                icon: Icon(Icons.close_rounded, color: OuroColors.accent),
                onPressed: _closeSearch,
              )
            : const OuroBackButton(),
        titleSpacing: 0,
        centerTitle: false,
        title: _searching
            ? _searchField(messages)
            : GestureDetector(
                // Taper l'en-tête ouvre la fiche du contact ou du groupe —
                // convention universelle des messageries, et le seul endroit
                // où l'on pense à chercher les médias partagés.
                onTap: () {
                  if (_isGroup) {
                    context.push('/group/${widget.groupId}/info');
                  } else if (!_isBroadcast) {
                    context.push('/chat/${widget.peerId}/info');
                  }
                },
                behavior: HitTestBehavior.opaque,
                child: Row(
                  children: [
                    // Hero uniquement en 1:1 (seul cas où on peut naviguer vers un
                    // appel) — un tag basé sur peerId, jamais dupliqué ailleurs.
                    (_isGroup || _isBroadcast)
                        ? PeerAvatar(
                            pseudo: peerPseudo,
                            radius: 17,
                            online: online,
                            reconnecting: reconnecting,
                          )
                        : Hero(
                            tag: 'avatar-${widget.peerId}',
                            child: PeerAvatar(
                              pseudo: peerPseudo,
                              radius: 17,
                              online: online,
                              reconnecting: reconnecting,
                            ),
                          ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  peerPseudo,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: OuroTypography.headline.copyWith(
                                    color: OuroColors.label,
                                  ),
                                ),
                              ),
                              if (peerKeyKnown || _isGroup) ...[
                                const SizedBox(width: 5),
                                Icon(
                                  peerKeyChanged
                                      ? Icons.warning_amber_rounded
                                      : peerVerified
                                      ? Icons.verified_rounded
                                      : Icons.lock_rounded,
                                  size: 13,
                                  color: peerKeyChanged
                                      ? OuroColors.systemOrange
                                      : peerVerified
                                      ? OuroColors.systemGreen
                                      : OuroColors.tertiaryLabel,
                                ),
                              ],
                            ],
                          ),
                          // Toucher la ligne d'état ouvre le panneau
                          // réseau. Le geste est délibérément DISCRET :
                          // aucune icône ne l'annonce, parce que la
                          // majorité des gens n'a rien à y chercher —
                          // mais il est là pour qui se demande « par où
                          // ça passe ? ».
                          _TapCible(
                            marge: EdgeInsets.zero,
                            onTap: () => showNetworkSheet(context),
                            semantique: 'Réseau Droplet, voir les détails',
                            child: AnimatedSwitcher(
                            duration: 200.ms,
                            child: Text(
                              _isGroup
                                  ? '$groupMemberCount membre${groupMemberCount > 1 ? 's' : ''}'
                                  : peerTyping
                                  ? 'en train d\'écrire…'
                                  : _isBroadcast
                                  ? 'Canal diffusion'
                                  : online
                                  // ⚠️ « À PROXIMITÉ » NE VAUT QUE POUR
                                  // UNE LIAISON DIRECTE.
                                  //
                                  // Un pair joignable à travers deux
                                  // relais peut se trouver à des
                                  // centaines de mètres, dans un autre
                                  // bâtiment. L'annoncer « à proximité »
                                  // était faux, et fait prendre de
                                  // mauvaises décisions : on croit
                                  // pouvoir l'appeler, ou compter sur un
                                  // envoi instantané.
                                  //
                                  // Le dire est aussi ce qui rend le
                                  // maillage VISIBLE — c'est
                                  // exactement ce que Droplet a de
                                  // singulier.
                                  ? (sautsVersPair == 0
                                      ? 'À proximité'
                                      : 'Joignable via $sautsVersPair relais')
                                  : reconnecting
                                  ? 'Reconnexion…'
                                  : _sousTitreHorsLigne(
                                      peerRecord, dernierRecu),
                              key: ValueKey(
                                _isGroup
                                    ? 'group'
                                    : peerTyping
                                    ? 'typing'
                                    : 'status',
                              ),
                              style: OuroTypography.caption1.copyWith(
                                fontStyle: peerTyping
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                color: peerTyping
                                    ? OuroColors.accent
                                    : online
                                    ? OuroColors.systemGreen
                                    : reconnecting
                                    ? OuroColors.systemOrange
                                    : OuroColors.tertiaryLabel,
                              ),
                            ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        actions: _searching
            ? _searchActions(messages)
            : [
                IconButton(
                  tooltip: 'Rechercher dans la conversation',
                  icon: Icon(Icons.search_rounded, color: OuroColors.accent),
                  onPressed: _openSearch,
                ),
                // L'appel est l'action la plus utile depuis une conversation :
                // elle reste seule dans la barre. Les infos et les médias sont
                // atteignables en tapant l'en-tête, comme partout ailleurs.
                if (!_isGroup && !_isBroadcast)
                  IconButton(
                    tooltip: callable
                        ? 'Appel vocal'
                        : online
                        ? 'Appel impossible : liaison Bluetooth ou relayée'
                        : 'Hors de portée',
                    icon: Icon(
                      Icons.phone_rounded,
                      // Grisé plutôt qu'absent : un bouton qui disparaît puis
                      // réapparaît au gré de la portée réseau ferait sauter
                      // toute la barre à chaque changement.
                      color: callable
                          ? OuroColors.accent
                          : OuroColors.quaternaryLabel,
                    ),
                    onPressed: callable
                        ? () {
                            OuroHaptics.light();
                            context.go('/call/${widget.peerId}');
                          }
                        : online
                        // Joignable pour les messages mais pas pour la voix :
                        // on explique, au lieu de laisser un bouton mort.
                        ? () => ref
                              .read(toastProvider.notifier)
                              .show(
                                'Appel vocal impossible : ce pair est joignable '
                                'par relais ou en Bluetooth, trop lent pour la '
                                'voix. Rapprochez-vous pour passer en Wi-Fi.',
                                type: DropletToastType.warning,
                              )
                        : null,
                  ),
                if (_isGroup)
                  IconButton(
                    tooltip: 'Infos du groupe',
                    icon: Icon(
                      Icons.info_outline_rounded,
                      color: OuroColors.accent,
                    ),
                    onPressed: () =>
                        context.push('/group/${widget.groupId}/info'),
                  ),
                const SizedBox(width: 4),
              ],
      ),
      body: IosMagnifierOverlay(
        child: Stack(
        children: [
          // ── Le fond en dégradé animé, façon Telegram ────────────────
          //
          // Posé en TOUT PREMIER, donc derrière la conversation. Il
          // avance d'un cran à chaque message envoyé (`_fondTick`).
          // La palette suit la luminosité effective : un dégradé sombre
          // derrière le mode clair rendrait le texte illisible. `null`
          // veut dire que l'utilisateur a choisi « Aucun » — on retombe
          // alors sur le fond uni habituel, sans rien calculer.
          if (fondCouleurs != null)
            Positioned.fill(
              child: TelegramGradientBackground(
                tick: _fondTick,
                couleurs: fondCouleurs,
              ),
            )
          else
            Positioned.fill(
              child: ColoredBox(color: OuroColors.systemBackground),
            ),
          Column(
            children: [
              Expanded(
                // La clé sert à SendFlight : c'est dans ce rectangle
                // qu'est calculée la place où la bulle envoyée se pose.
                key: _zoneListeKey,
                child: messages.isEmpty && !peerTyping
                    ? _EmptyChat(
                        isBroadcast: _isBroadcast,
                        peerPseudo: peerPseudo,
                      )
                    : Stack(
                        children: [
                          NotificationListener<ScrollNotification>(
                            onNotification: (notification) {
                              if (notification is ScrollUpdateNotification &&
                                  notification.metrics.pixels <= 0 &&
                                  !_loadingOlder &&
                                  !_isBroadcast) {
                                setState(() => _loadingOlder = true);
                                Future.delayed(
                                    const Duration(seconds: 2),
                                    () {
                                  if (mounted) {
                                    setState(() => _loadingOlder = false);
                                  }
                                });
                              }
                              return false;
                            },
                            child: ListView.builder(
                            controller: _scrollCtrl,
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            // Le contenu DÉMARRE sous la barre, mais DÉFILE
                            // dessous : c'est la marge haute qui réserve la
                            // place, pas un bandeau opaque. Les messages
                            // s'estompent donc derrière le verre au lieu de
                            // se faire couper net.
                            padding: EdgeInsets.only(
                              left: 12,
                              right: 12,
                              top: MediaQuery.paddingOf(context).top +
                                  kToolbarHeight +
                                  8,
                              // ⚠️ PAS DE PADDING EN BAS.
                              //
                              // Le dernier message doit venir TOUCHER le
                              // gradient, pas s'arrêter au-dessus. C'est le
                              // gradient qui crée l'illusion que le message
                              // « sort » de derrière la barre de saisie.
                              bottom: 0,
                            ),
                            itemCount: items.length + (peerTyping ? 1 : 0) + 1,
                            itemBuilder: (context, i) {
                          if (i == 0) {
                              if (_loadingOlder) {
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 12),
                                child: Center(
                                  child: Text(
                                    'Charger les messages précédents…',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: OuroColors.textTertiary,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return const SizedBox.shrink();
                          }
                          if (peerTyping && i == items.length + 1) {
                            return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 4),
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: TypingIndicator(),
                                  ),
                                )
                                .animate()
                                .fadeIn(duration: 200.ms)
                                .slideX(begin: -0.05);
                          }
                          final item = items[i - 1];
                          if (item is _DaySeparator) {
                            return _daySeparator(item.label);
                          }
                          final m = item as MeshMessage;
                          final mine = m.senderId == myId;

                          // ── GROUPEMENT DES MESSAGES CONSÉCUTIFS ─────
                          //
                          // Trois messages d'affilée de la même personne
                          // ne sont pas trois événements séparés : c'est
                          // une seule prise de parole. Les espacer tous
                          // pareil donnait un fil haché, où l'œil devait
                          // relire l'auteur à chaque bulle.
                          //
                          // On les resserre donc, on n'écrit le nom de
                          // l'auteur qu'au DÉBUT d'une série, et seule la
                          // DERNIÈRE bulle porte le petit coin pointu qui
                          // désigne le locuteur. C'est ce que font iMessage
                          // et WhatsApp, et c'est ce qui donne au fil son
                          // rythme de conversation.
                          final suite = _memeAuteur(
                            i > 0 ? items[i - 1] : null,
                            m,
                            myId,
                          );
                          final finDeSerie = !_memeAuteur(
                            m,
                            i + 1 < items.length ? items[i + 1] : null,
                            myId,
                          );
                          final replied = m.replyToId == null
                              ? null
                              : parId[m.replyToId];
                          final isAudio =
                              m.type == 'file' &&
                              (m.fileMimeType?.startsWith('audio') ?? false);
                          final isActive =
                              _playingAudio && _activeAudioFile == m.fileId;
                          final bubble = _MessageBubble(
                            key: ValueKey(m.id),
                            message: m,
                            mine: mine,
                            suiteDuPrecedent: suite,
                            finDeSerie: finDeSerie,
                            isBroadcast: _isBroadcast,
                            isGroup: _isGroup,
                            isAudio: isAudio,
                            isImage:
                                m.type == 'file' &&
                                (m.fileMimeType?.startsWith('image') ?? false),
                            isVideo:
                                m.type == 'file' &&
                                (m.fileMimeType?.startsWith('video') ?? false),
                            playingAudio: isActive,
                            playbackProgress: isActive ? _playbackProgress : 0,
                            playbackPosition: isActive
                                ? _playbackPosition
                                : null,
                            playbackSpeed: _playbackSpeed,
                            voicePlayed: _playedVoiceNotes.contains(m.fileId),
                            repliedMessage: replied,
                            query: _query,
                            scrollVelocity: _scrollVelocity,
                            onOpenReplied: replied == null
                                ? null
                                : () => _jumpToMessage(replied.id, messages),
                            onPlayAudio: () =>
                                _toggleAudio(m.fileId ?? '', m.fileName ?? ''),
                            onSeekAudio: isActive ? _seekAudio : null,
                            onCycleSpeed: _cycleSpeed,
                            // Le micro de réponse rapide n'a de sens que
                            // sur un vocal REÇU : répondre à sa propre
                            // voix ne veut rien dire.
                            onVoiceReply:
                                (!mine &&
                                    isAudio &&
                                    VoiceNoteMeta.isVoiceNote(m.fileName))
                                ? () => _replyWithVoice(m)
                                : null,
                            onOpenLocation: () {
                              OuroHaptics.selection();
                              context.push('/map');
                            },
                            onLongPress: () => _openMessageActions(m),
                            // Fil de discussion : compter les réponses.
                            threadCount: messages.where((o) => o.replyToId == m.id).length,
                            onOpenThread: () => _openThread(m),
                            // Seulement quand il y a quelque chose à
                            // renvoyer : ailleurs, `null` retire la
                            // cible et l'heure retrouve son rôle
                            // habituel.
                            onRenvoyer: m.status == MessageStatus.failed
                                ? () {
                                    HapticFeedback.mediumImpact();
                                    ref
                                        .read(meshMessagesProvider.notifier)
                                        .renvoyer(m.id);
                                  }
                                : null,
                            onDoubleTap: () {
                              HapticFeedback.mediumImpact();
                              ref
                                  .read(meshMessagesProvider.notifier)
                                  .toggleReaction(m.id, '❤️');
                              // Effet de particules ancé sur la bulle.
                              final origin = _centreDeLaBulle(m.id);
                              if (origin != null) {
                                ReactionEffectOverlay.show(
                                  context,
                                  emoji: '❤️',
                                  origin: origin,
                                );
                              }
                            },
                          );
                          // ── LA BULLE EN VOL EST INVISIBLE ────
                          //
                          // Tant que la copie volante n'est pas arrivée,
                          // la vraie bulle ne doit pas être là : sinon
                          // on voit le message à deux endroits à la
                          // fois. Voir `_texteEnVol`.
                          //
                          // `Opacity` et non `Visibility` : la bulle
                          // doit garder sa PLACE (la liste ne doit pas
                          // se réorganiser au moment où elle reparaît),
                          // et surtout garder ses dimensions, puisque le
                          // vol atterrit dessus.
                          final enVol = mine &&
                              i == items.length - 1 &&
                              _texteEnVol != null &&
                              m.content == _texteEnVol;
                          final entree = _buildMessageEntry(m, bubble);
                          return enVol
                              ? Opacity(opacity: 0, child: entree)
                              : entree;
                        },
                      ),
                          ),
                          // ── LE GRADIENT DE FONDU (Telegram-style) ──────
                          //
                          // Un dégradé vertical posé AU-DESSUS de la liste,
                          // au bas de l'écran. Il va de transparent → couleur
                          // de fond en 60px. L'effet : les derniers messages
                          // semblent « sortir » de derrière la barre de saisie
                          // au lieu d'être coupés net par le bord du widget.
                          //
                          // C'est exactement ce que fait Telegram : la bulle
                          // la plus basse est à moitié estompée, et le texte
                          // paraît couler depuis la barre d'écriture.
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: 0,
                            height: 60,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      OuroColors.systemBackground,
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
              _InputBar(
                champKey: _champSaisieKey,
                controller: _inputCtrl,
                recording: _recording,
                recordingLocked: _recordingLocked,
                amplitudes: _recording
                    ? List.unmodifiable(_amplitudes)
                    : const <double>[],
                replyPreview: _replyTarget,
                onChanged: _onTextChanged,
                onSend: _send,
                onMicStart: _startRecording,
                onMicStop: _stopRecording,
                onMicCancel: _cancelRecording,
                onMicLock: () => setState(() => _recordingLocked = true),
                onAttach: _openAttachSheet,
                onSticker: _sendSticker,
                onAttachMedia: () => _pickAndSendFile(filtre: FileType.media),
                onCancelReply: () => setState(() => _replyTarget = null),
              ),
            ],
          ),
          // Bouton flottant "aller en bas"
          if (_showJumpButton)
            Positioned(
              right: 16,
              bottom: 96,
              child: _JumpButton(
                unread: _unreadWhileScrolled,
                onTap: () => _scrollToBottom(),
              ),
            ),
        ],
      ),
      ),
    );
  }

  /// Où se trouve la bulle d'un message, en coordonnées d'écran.
  ///
  /// On vise le HAUT de la bulle plutôt que son centre : les cœurs
  /// jaillissent alors du bord supérieur et montent, au lieu de traverser
  /// le texte du message auquel on vient de réagir.
  ///
  /// Renvoie `null` si la bulle n'est plus construite — la salve retombe
  /// alors sur son comportement plein écran, ce qui vaut mieux que pas
  /// de retour du tout.
  Offset? _centreDeLaBulle(String messageId) {
    final rendu = _messageKeys[messageId]?.currentContext?.findRenderObject();
    if (rendu is! RenderBox || !rendu.hasSize) return null;
    final origine = rendu.localToGlobal(Offset.zero);
    return Offset(origine.dx + rendu.size.width / 2, origine.dy + 8);
  }

  /// Ces deux éléments consécutifs sont-ils du même locuteur, assez
  /// rapprochés pour former une seule prise de parole ?
  ///
  /// Faux dès qu'un séparateur de date s'intercale, ou qu'il s'est écoulé
  /// plus de trois minutes : reprendre la parole après un silence, ce
  /// n'est plus la même intervention, et le fil doit le montrer.
  static bool _memeAuteur(Object? avant, Object? apres, String myId) {
    if (avant is! MeshMessage || apres is! MeshMessage) return false;
    if (avant.senderId != apres.senderId) return false;
    return apres.timestamp.difference(avant.timestamp).inMinutes.abs() < 3;
  }

  List<Object> _buildItems(List<MeshMessage> messages) {
    final items = <Object>[];
    DateTime? lastDay;
    for (final m in messages) {
      final day = DateTime(
        m.timestamp.year,
        m.timestamp.month,
        m.timestamp.day,
      );
      if (lastDay == null || day != lastDay) {
        items.add(_DaySeparator(_dayLabel(day)));
        lastDay = day;
      }
      items.add(m);
    }
    return items;
  }

  /// Le champ de recherche qui prend la place de l'en-tête.
  Widget _searchField(List<MeshMessage> messages) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: SizedBox(
        height: 36,
        child: CupertinoSearchTextField(
          controller: _searchCtrl,
          focusNode: _searchFocus,
          placeholder: 'Rechercher',
          style: OuroTypography.body.copyWith(color: OuroColors.label),
          placeholderStyle: OuroTypography.body.copyWith(
            color: OuroColors.tertiaryLabel,
          ),
          backgroundColor: OuroColors.tertiarySystemFill,
          itemColor: OuroColors.secondaryLabel,
          onChanged: (value) => _runSearch(value, messages),
          onSuffixTap: () {
            _searchCtrl.clear();
            _runSearch('', messages);
          },
        ),
      ),
    );
  }

  /// Le compteur « 2 sur 7 » et les deux chevrons de navigation.
  List<Widget> _searchActions(List<MeshMessage> messages) {
    final none = _query.isEmpty;
    final empty = !none && _hits.isEmpty;

    return [
      if (!none)
        Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Center(
            child: Text(
              empty ? 'Aucun' : '${_hitIndex + 1}/${_hits.length}',
              style: OuroTypography.footnote.copyWith(
                color: empty ? OuroColors.systemRed : OuroColors.secondaryLabel,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      // Le chevron BAS va vers les messages plus récents, le HAUT vers
      // les plus anciens : le sens du défilement, pas celui de la liste
      // des résultats. L'inverse désoriente immédiatement.
      IconButton(
        tooltip: 'Résultat plus ancien',
        visualDensity: VisualDensity.compact,
        icon: Icon(
          Icons.keyboard_arrow_up_rounded,
          color: _hits.isEmpty ? OuroColors.quaternaryLabel : OuroColors.accent,
        ),
        onPressed: _hits.isEmpty ? null : () => _gotoHit(1, messages),
      ),
      IconButton(
        tooltip: 'Résultat plus récent',
        visualDensity: VisualDensity.compact,
        icon: Icon(
          Icons.keyboard_arrow_down_rounded,
          color: _hits.isEmpty ? OuroColors.quaternaryLabel : OuroColors.accent,
        ),
        onPressed: _hits.isEmpty ? null : () => _gotoHit(-1, messages),
      ),
      const SizedBox(width: 4),
    ];
  }

  /// Enrobe une bulle de message pour permettre le glissement vers la
  /// droite qui prépare une réponse (« swipe to reply »), comme sur
  /// WhatsApp/Telegram.
  Widget _buildMessageEntry(MeshMessage m, Widget bubble) {
    // La clé permet de RAMENER cette bulle à l'écran plus tard — depuis
    // un résultat de recherche ou depuis une citation. Elle n'existe que
    // tant que la bulle est construite, ce dont `_jumpToMessage` tient
    // compte.
    final key = _messageKeys.putIfAbsent(m.id, GlobalKey.new);

    // Le clignotement d'arrivée : un halo qui s'allume puis s'éteint.
    // Sans lui, sauter à un message ancien dépose l'utilisateur devant
    // un mur de texte sans lui dire lequel il cherchait.
    final flashed = _flashedId == m.id;

    return KeyedSubtree(
      key: key,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: flashed
              ? OuroColors.accent.withValues(alpha: 0.14)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: _dismissibleEntry(m, bubble),
      ),
    );
  }

  /// Glisser une bulle vers la droite pour y répondre.
  ///
  /// ⚠️ CE N'EST PLUS UN `Dismissible`, ET C'EST TOUTE LA DIFFÉRENCE.
  ///
  /// `Dismissible` est fait pour SUPPRIMER : il emporte l'élément hors de
  /// l'écran, découvre un panneau coloré derrière, et ne se déclenche
  /// qu'au-delà d'un tiers de la largeur. Détourné en « répondre », il
  /// donnait un geste lourd — on tirait un bloc entier sur un tiers de
  /// l'écran pour citer un message.
  ///
  /// WhatsApp et Telegram font l'inverse : la bulle suit le doigt sur
  /// quelques dizaines de points, avec une résistance croissante, une
  /// flèche qui apparaît, une vibration au moment où le seuil est
  /// franchi — puis elle revient d'elle-même à sa place. Le message ne
  /// bouge jamais vraiment ; c'est un ACQUITTEMENT, pas un déplacement.
  ///
  /// Les trois détails qui font que ça marche :
  ///
  ///   • **l'élastique** — au-delà du seuil, le déplacement est divisé
  ///     par trois. Le doigt continue, la bulle non : c'est ce qui donne
  ///     la sensation de tirer contre quelque chose ;
  ///   • **la vibration AU SEUIL**, pas au relâchement. On sait que
  ///     c'est acquis avant même de lever le doigt ;
  ///   • **le retour par un ressort**, qui repart de la position ET de
  ///     la vitesse courantes — relâcher en plein mouvement ne produit
  ///     aucun à-coup.
  Widget _dismissibleEntry(MeshMessage m, Widget bubble) {
    return _GlisserPourRepondre(
      onRepondre: () => setState(() => _replyTarget = m),
      child: bubble,
    );
  }


  /// Pendant qu'on est remonté dans l'historique (pas tout en bas),
  /// compte combien de nouveaux messages sont arrivés depuis — c'est ce
  /// nombre qui s'affiche sur le petit bouton flottant « nouveaux
  /// messages ».
  void _maybeCountUnread(List<MeshMessage> messages, String myId) {
    if (!_showJumpButton) return;
    final now = DateTime.now();
    final readAt = _lastReadAt ?? now;
    _lastReadAt = readAt;
    final count = messages.where((m) {
      if (m.senderId == myId) return false;
      return m.timestamp.isAfter(readAt);
    }).length;
    if (count != _unreadWhileScrolled) {
      setState(() => _unreadWhileScrolled = count);
    }
  }

  Widget _daySeparator(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: OuroCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          borderRadius: DesignTokens.radiusFull,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: OuroColors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  String _dayLabel(DateTime day) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (day == today) return "Aujourd'hui";
    if (day == today.subtract(const Duration(days: 1))) return 'Hier';
    if (day.isAfter(today.subtract(const Duration(days: 7)))) {
      return const [
        'Lundi',
        'Mardi',
        'Mercredi',
        'Jeudi',
        'Vendredi',
        'Samedi',
        'Dimanche',
      ][day.weekday - 1];
    }
    return '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}/${day.year}';
  }
}

class _DaySeparator {
  const _DaySeparator(this.label);
  final String label;
}

/// Ce qui s'affiche quand la conversation n'a encore aucun message —
/// un avatar et un petit texte d'accueil (« Dites bonjour 👋 »).
class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.isBroadcast, required this.peerPseudo});
  final bool isBroadcast;
  final String peerPseudo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          PeerAvatar(pseudo: peerPseudo, radius: 34, online: !isBroadcast),
          const SizedBox(height: 12),
          // La petite main qui salue sous l'avatar : c'est le premier
          // écran d'une conversation neuve, le moment où l'on hésite à
          // écrire. Un mouvement y vaut mieux qu'un blanc.
          SceneAnimee(
            emoji: isBroadcast ? Scenes.diffusionVide : Scenes.conversationVide,
            iconeDeSecours:
                isBroadcast ? Icons.campaign_rounded : Icons.waving_hand_rounded,
            taille: 56,
          ),
          const SizedBox(height: 8),
          Text(
            isBroadcast ? 'Canal diffusion' : 'Dites bonjour 👋',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: OuroColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isBroadcast
                ? 'Les messages sans destinataire apparaissent ici.'
                : 'Vos échanges sont relayés pair à pair, sans Internet.',
            style: TextStyle(fontSize: 12, color: OuroColors.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// UNE bulle de message dans la conversation — texte, fichier ou
/// message vocal (mais pas image, voir `_ImageBubble` pour ça). Change
/// d'apparence selon qu'elle est « à moi » (alignée à droite, colorée)
/// ou « à l'autre » (alignée à gauche), et peut afficher une citation
/// (« en réponse à... »), un lecteur audio, ou l'effet spécial choisi.
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.mine,
    this.suiteDuPrecedent = false,
    this.finDeSerie = true,
    required this.isBroadcast,
    this.isGroup = false,
    required this.isAudio,
    this.isImage = false,
    this.isVideo = false,
    required this.playingAudio,
    this.playbackProgress = 0,
    this.playbackPosition,
    this.playbackSpeed = 1.0,
    this.voicePlayed = false,
    this.onRenvoyer,
    required this.onPlayAudio,
    this.onSeekAudio,
    this.onCycleSpeed,
    this.onVoiceReply,
    required this.onLongPress,
    this.onDoubleTap,
    this.onOpenLocation,
    this.repliedMessage,
    this.onOpenReplied,
    this.query = '',
    this.scrollVelocity = 0,
    this.threadCount = 0,
    this.onOpenThread,
  });

  final MeshMessage message;

  /// Renvoie un message dont l'envoi a échoué.
  ///
  /// ⚠️ UN SEUL APPUI, SUR L'INDICATEUR ROUGE LUI-MÊME.
  ///
  /// L'action existe aussi dans le menu d'appui long — mais un appui
  /// long est un geste qu'il faut connaître, et personne ne le cherche
  /// devant un message qui vient d'échouer. Toutes les grandes
  /// messageries font de l'indicateur d'échec un bouton : c'est
  /// exactement là que le doigt se pose déjà.
  final VoidCallback? onRenvoyer;

  /// Ramène à l'original quand on tape la citation.
  final VoidCallback? onOpenReplied;

  /// Le texte recherché, à surligner dans la bulle. Vide hors recherche.
  final String query;

  /// Vélocité du scroll (0.0 à 1.0) pour l'effet de respiration des bulles.
  final double scrollVelocity;

  /// Nombre de réponses dans le fil (0 = pas de fil actif).
  final int threadCount;

  /// Ouvre la vue du fil de discussion.
  final VoidCallback? onOpenThread;

  final bool mine;
  final bool isBroadcast;

  /// Conversation de groupe — comme en diffusion, il faut dire QUI parle.
  final bool isGroup;

  final bool isAudio;
  final bool isImage;
  final bool isVideo;
  final bool playingAudio;
  final double playbackProgress;
  final Duration? playbackPosition;
  final double playbackSpeed;

  /// Ce vocal a-t-il déjà été écouté ? Pilote la pastille bleue.
  final bool voicePlayed;

  final VoidCallback onPlayAudio;
  final ValueChanged<double>? onSeekAudio;
  final VoidCallback? onCycleSpeed;

  /// Répondre par un vocal — uniquement sur les messages vocaux reçus.
  final VoidCallback? onVoiceReply;

  final VoidCallback onLongPress;
  final VoidCallback? onDoubleTap;

  /// Ouvre la position partagée sur la grande carte.
  final VoidCallback? onOpenLocation;
  final MeshMessage? repliedMessage;

  /// Ce que le lecteur d'écran énonce pour cette bulle.
  ///
  /// ⚠️ C'EST LE POINT LE PLUS IMPORTANT DE TOUTE L'ACCESSIBILITÉ DE
  /// DROPLET, parce que c'est le contenu même de l'application.
  ///
  /// Sans lui, VoiceOver parcourait la bulle par fragments — le
  /// pseudonyme, puis le texte, puis l'heure, puis une icône de coche
  /// sans nom — et surtout il ne disait JAMAIS l'essentiel : de qui vient
  /// ce message. Sur un fil où l'on ne voit pas de quel côté sont les
  /// bulles, « moi » et « l'autre » deviennent indiscernables.
  ///
  /// L'ordre suit celui d'une lecture à voix haute : qui parle, ce qui
  /// est dit, quand, et où en est l'envoi.
  String _annonce() {
    final qui = mine ? 'Moi' : message.authorPseudo;

    final quoi = switch (message.type) {
      'file' when message.fileMimeType?.startsWith('image') ?? false =>
        'Photo',
      'file' when message.fileMimeType?.startsWith('video') ?? false =>
        'Vidéo',
      'file' when message.fileMimeType?.startsWith('audio') ?? false =>
        'Message vocal',
      'file' => 'Fichier ${message.fileName ?? ''}',
      _ when _isAnimatedSticker =>
        'Sticker ${AnimatedStickerCatalog.nomLisible(message.content)}',
      _ => message.content,
    };

    // L'état d'envoi n'est visible que sur MES messages, et n'est
    // annoncé que là — l'entendre sur un message reçu n'aurait aucun
    // sens.
    final etat = !mine
        ? null
        : switch (message.status) {
            MessageStatus.sending => 'envoi en cours',
            MessageStatus.pending => 'en attente',
            MessageStatus.failed => 'échec de l\'envoi',
            MessageStatus.sent => message.readAt != null
                ? 'lu'
                : message.deliveryCount > 0
                    ? 'remis'
                    : 'envoyé',
          };

    return [
      qui,
      quoi,
      _formatTime(message.timestamp),
      ?etat,
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final isFile = message.type == 'file';
    final align = mine ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    final bubble = Padding(
      // iMessage : 3pt quand la bulle prolonge la précédente, 9pt quand
      // elle ouvre une nouvelle prise de parole. C'est ce contraste
      // d'espacement — et lui seul — qui fait lire le fil par blocs.
      padding: EdgeInsets.only(
        top: suiteDuPrecedent ? 3 : 9,
        bottom: 1,
      ),
      child: Column(
        crossAxisAlignment: align,
        children: [
          // ⚠️ EN GROUPE AUSSI, PAS SEULEMENT EN DIFFUSION.
          //
          // Le nom n'apparaissait qu'au-dessus des messages de diffusion.
          // Dans un groupe, tous les messages reçus arrivaient donc
          // ANONYMES : impossible de savoir qui avait écrit quoi, alors
          // que c'est la première chose qu'on cherche à plusieurs.
          if (!mine && (isBroadcast || isGroup) && !suiteDuPrecedent)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (message.forwardedFrom != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 1),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.forward_rounded,
                            size: 12,
                            color: mine
                                ? Colors.white54
                                : OuroColors.textTertiary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            'Transféré',
                            style: TextStyle(
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                              color: mine
                                  ? Colors.white54
                                  : OuroColors.textTertiary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  Text(
                    message.authorPseudo,
                    style: TextStyle(
                      fontSize: 11,
                      color: _senderColor(message.senderId ?? message.authorPseudo),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          _BullePressable(
            onLongPress: onLongPress,
            onDoubleTap: onDoubleTap,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // ⚠️ L'ICÔNE DE STATUT NE VIT PLUS ICI.
                //
                // Elle était dessinée à GAUCHE de la bulle, en vert ou en
                // orange vif — et redessinée une seconde fois À
                // L'INTÉRIEUR, à côté de l'heure. Deux indicateurs pour
                // une seule information, dont un gros point coloré qui
                // attirait l'œil avant le texte du message lui-même.
                //
                // Il n'en reste qu'un, discret, collé à l'heure : le
                // statut est une information de service, il ne doit
                // jamais primer sur ce qui est écrit.
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.of(context).size.width * 0.78,
                  ),
                  child: Container(
                    // ── LES MÉDIAS N'ONT PLUS DE CADRE ──────────────
                    //
                    // Photos et vidéos étaient serties dans quatre points
                    // de couleur de bulle, tout autour. C'est le « cadre »
                    // que WhatsApp a supprimé dans sa refonte de 2026, et
                    // la raison est bonne : ce liseré n'apportait aucune
                    // information et découpait l'image d'un trait bleu ou
                    // gris qui la faisait paraître collée, pas envoyée.
                    //
                    // À zéro, l'image devient la bulle. Ce sont les coins
                    // arrondis du conteneur qui la rognent, donc elle
                    // garde exactement la même géométrie que les bulles
                    // de texte voisines.
                    padding: _sansBulle
                        ? const EdgeInsets.symmetric(horizontal: 2, vertical: 2)
                        : (isImage || isVideo)
                            ? EdgeInsets.zero
                            // ⚠️ MARGES ASYMÉTRIQUES, et c'est
                            // obligatoire depuis la pointe.
                            //
                            // La forme réserve sept points sur le côté
                            // de l'auteur pour laisser dépasser la
                            // pointe. Une marge identique des deux côtés
                            // laisserait donc le texte collé au bord du
                            // côté opposé et flottant du côté de la
                            // pointe — un déséquilibre qu'on ne sait pas
                            // nommer mais qu'on voit.
                            //
                            // Les valeurs sont aussi RESSERRÉES (11/7 au
                            // lieu de 14/10) : les bulles de WhatsApp
                            // sont nettement plus compactes que celles
                            // d'iMessage, et c'est ce qui permet d'en
                            // voir plus à l'écran sans rien tasser.
                            : EdgeInsets.symmetric(
                                horizontal: isAudio ? 6 : 13,
                                vertical: isAudio ? 6 : 7,
                              ),
                    // Le contenu est rogné par les coins de la bulle :
                    // sans cela, une image à ras bord dépasserait des
                    // arrondis.
                    clipBehavior: Clip.antiAlias,
                    // ── LA FORME WHATSAPP ───────────────────────────
                    //
                    // `ShapeDecoration` et non `BoxDecoration` : il
                    // fallait une forme LIBRE pour que la pointe puisse
                    // déborder du rectangle. Un `borderRadius` ne sait
                    // qu'arrondir des coins, il ne sait pas ajouter de
                    // matière.
                    //
                    // C'est aussi ce qui rogne le contenu : depuis que
                    // les images vont d'un bord à l'autre, elles suivent
                    // exactement ce tracé, pointe comprise.
                    decoration: ShapeDecoration(
                      // Couleurs de Messages, modulées par l'état réseau :
                      //   • Stable (lu/remis) = couleur vive, brillante
                      //   • En cours (sending/pending) = légèrement matte
                      //   • Échec = translucide, estompée
                      color: _sansBulle
                          ? Colors.transparent
                          : _bubbleColorForState(
                              mine: mine,
                              status: message.status,
                            ),
                      shape: _FormeBulle(
                        rayon: DesignTokens.radiusBubble,
                        rayonQueue: finDeSerie && !_sansBulle
                            ? DesignTokens.radiusBubbleTail
                            : DesignTokens.radiusBubble,
                        mine: mine,
                        // ⚠️ POINTE DÉSACTIVÉE.
                        //
                        // La petite pointe triangulaire est LA signature
                        // de WhatsApp — et vue sur les bulles bleues de
                        // Droplet, elle se lisait comme un emprunt plutôt
                        // que comme un détail de forme.
                        //
                        // Le locuteur reste marqué par le coin moins
                        // arrondi en bas (`radiusBubbleTail`), qui est la
                        // solution d'iMessage : plus discrète, et elle
                        // n'appartient à personne.
                        //
                        // La forme est conservée telle quelle : remettre
                        // la pointe ne demande que de repasser ce
                        // paramètre à `finDeSerie && !_sansBulle`.
                        pointe: false,
                      ),
                    ),
                    // ⚠️ POUR UN MESSAGE COURT, L'HEURE SE MET SUR LA
                    // MÊME LIGNE QUE LE TEXTE.
                    //
                    // Empilée systématiquement en dessous, elle donnait
                    // à un message de deux caractères une bulle presque
                    // aussi haute que large — l'heure y occupait plus de
                    // place que le mot. C'est la disposition qu'emploient
                    // toutes les messageries : le texte coule, et l'heure
                    // vient se loger dans l'espace qui reste à sa droite.
                    //
                    // Au-delà d'une vingtaine de caractères, ou dès qu'il
                    // y a autre chose que du texte (image, citation,
                    // réaction), on repasse à l'empilement : côte à côte,
                    // le texte serait comprimé par l'heure.
                    child: _heureSurLaMemeLigne
                        ? Row(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Flexible(child: _textBubble(isFile)),
                              const SizedBox(width: 6),
                              _TapCible(
                                marge: EdgeInsets.zero,
                                onTap: _actionSurLHeure(context),
                                semantique: _libelleDeLHeure,
                                child: Padding(
                                  padding: const EdgeInsets.only(bottom: 1),
                                  child: _timeAndStatus(),
                                ),
                              ),
                            ],
                          )
                        : Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (repliedMessage != null)
                          _quoteBlock(repliedMessage!),
                        if (isVideo)
                          _VideoBubble(
                            fileId: message.fileId ?? '',
                            fileName: message.fileName ?? '',
                          )
                        else if (isImage)
                          _ImageBubble(
                            fileId: message.fileId ?? '',
                            fileName: message.fileName ?? '',
                          )
                        else if (isAudio)
                          _audioBubble()
                        else if (message.effect == kEffectInvisibleInk)
                          _InvisibleInkReveal(child: _textBubble(isFile))
                        else
                          _textBubble(isFile),
                        if (message.reactions.isNotEmpty) _reactionChips(),
                        Padding(
                          // La bulle d'un média n'a plus de marge
                          // intérieure : sans ce rattrapage, l'heure se
                          // collerait au bord de l'image.
                          padding: (isImage || isVideo)
                              ? const EdgeInsets.fromLTRB(0, 4, 10, 6)
                              : EdgeInsets.zero,
                          child: _TapCible(
                            // Toucher l'heure ouvre le détail de la
                            // transmission — le geste est discret, et
                            // n'encombre pas la bulle d'un bouton de plus.
                            onTap: _actionSurLHeure(context),
                            semantique: _libelleDeLHeure,
                            child: _timeAndStatus(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // Entrée d'une bulle : un fondu court accompagné d'un très léger
    // glissement vers le haut, identique dans les deux sens.
    //
    // L'ancienne version faisait REBONDIR (`elasticOut`) chaque message
    // envoyé, en le faisant dépasser sa taille finale avant de revenir.
    // C'est l'animation la plus répétée de toute l'app — plusieurs
    // centaines de fois par jour pour quelqu'un qui écrit beaucoup — et
    // elle retardait à chaque fois l'affichage du message de près d'une
    // demi-seconde. Messages sur iOS se contente de faire apparaître la
    // bulle : elle est là, immédiatement.
    // La bulle devient UN élément pour le lecteur d'écran, avec ses deux
    // gestes nommés.
    //
    // ⚠️ `onLongPress` et `onDoubleTap` sont invisibles pour VoiceOver
    // tant qu'ils ne sont pas déclarés ici : un `GestureDetector` seul
    // n'est, pour lui, qu'un décor. Les déclarer les fait apparaître dans
    // le rotor d'actions, et l'utilisateur entend « Actions disponibles :
    // Options du message, J'adore » au lieu de n'avoir aucun moyen de
    // réagir à un message.
    final lisible = Semantics(
      container: true,
      label: _annonce(),
      excludeSemantics: true,
      onLongPress: onLongPress,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Options du message'): onLongPress,
        const CustomSemanticsAction(label: 'J\'adore'): ?onDoubleTap,
      },
      child: bubble,
    );

    var animated = lisible
        .animate()
        .fadeIn(
          duration: DesignTokens.durationFast,
          curve: DesignTokens.curveEnter,
        )
        .slideY(
          begin: 0.08,
          duration: DesignTokens.durationFast,
          curve: DesignTokens.curveEnter,
        );

    // Effet de respiration : quand on scroll vite, les bulles se
    // compressent légèrement (scale 0.97), et quand on s'arrête,
    // elles reviennent à la normale. L'effet est subtil — on ne veut
    // pas que l'utilisateur le remarque consciemment, juste qu'il
    // sente que la liste est « vivante ».
    if (scrollVelocity > 0.1) {
      final breathScale = 1.0 - (scrollVelocity * 0.03);
      animated = animated.scaleXY(
        begin: breathScale,
        end: 1.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    }

    // iMessage bubble send : spring(response: 0.35, damping: 0.75)
    // Scale 0.6→1.0 combined with slide up. Applied to outgoing messages.
    if (mine) {
      animated = animated
          .scaleXY(
            begin: 0.6,
            end: 1.0,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          );
    }

    // Effets de bulle façon iMessage — enchaînés après l'entrée normale via
    // `.then()`, ne rejouent jamais au re-render grâce au `ValueKey(m.id)`
    // stable posé sur cette bulle par l'appelant (même garantie que
    // l'animation d'entrée ci-dessus, déjà éprouvée).
    switch (message.effect) {
      case kEffectSlam:
        animated = animated
            .then(delay: 60.ms)
            .scaleXY(
              begin: 1,
              end: 1.3,
              duration: 140.ms,
              curve: Curves.easeOut,
            )
            .then()
            .scaleXY(
              begin: 1.3,
              end: 1,
              duration: 180.ms,
              curve: Curves.easeIn,
            );
      case kEffectLoud:
        animated = animated
            .then(delay: 60.ms)
            .scaleXY(
              begin: 1,
              end: 1.15,
              duration: 120.ms,
              curve: Curves.easeOut,
            )
            .then()
            .shake(hz: 6, duration: 380.ms, offset: const Offset(6, 0));
      case kEffectGentle:
        animated = animated
            .then(delay: 60.ms)
            .scaleXY(
              begin: 1,
              end: 0.8,
              duration: 220.ms,
              curve: Curves.easeInOut,
            )
            .then()
            .scaleXY(
              begin: 0.8,
              end: 1,
              duration: 280.ms,
              curve: Curves.easeOutCubic,
            );
    }
    return animated;
  }

  /// La couleur attribuée à un participant, dans un groupe.
  ///
  /// ── Pourquoi une couleur, et pourquoi celle-là ────────────────────
  ///
  /// Dans une conversation à plusieurs, on ne lit pas les noms : on les
  /// RECONNAÎT à leur couleur, du coin de l'œil, en parcourant le fil.
  /// C'est ce que font toutes les messageries de groupe, et c'est ce qui
  /// permet de suivre un échange à trois sans relire chaque en-tête.
  ///
  /// La couleur est TIRÉE DE L'IDENTIFIANT, pas d'un compteur : le même
  /// contact garde donc la sienne d'une session à l'autre, sur tous les
  /// appareils, sans que rien n'ait à être stocké ni synchronisé. Deux
  /// personnes peuvent tomber sur la même teinte — c'est sans gravité,
  /// le nom reste écrit à côté.
  ///
  /// Les huit teintes sont choisies pour rester lisibles sur les deux
  /// fonds, clair et sombre : ni pastel (invisible en clair), ni
  /// saturé-sombre (illisible en sombre).
  static const List<Color> _senderPalette = [
    Color(0xFF34AADC), // azur
    Color(0xFF30C07B), // menthe
    Color(0xFFFF9F0A), // ambre
    Color(0xFFFF6482), // corail
    Color(0xFFAF8CFF), // lavande
    Color(0xFF2ECAD5), // turquoise
    Color(0xFFFFB340), // miel
    Color(0xFF7D8CFF), // indigo
  ];

  static Color _senderColor(String id) {
    // Somme des unités de la chaîne : stable, sans dépendance, et bien
    // assez dispersée pour huit cases.
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x7FFFFFFF;
    }
    return _senderPalette[hash % _senderPalette.length];
  }

  Widget _quoteBlock(MeshMessage replied) {
    final snippet = replied.type == 'file'
        ? VoiceNoteMeta.describeAttachment(replied.fileName)
        : replied.content;
    final truncated = snippet.length > 80
        ? '${snippet.substring(0, 80)}…'
        : snippet;
    final accent = mine ? Colors.white : OuroColors.meshBlueBright;
    // ⚠️ LA CITATION EST UN LIEN, PAS UNE VIGNETTE.
    //
    // Une réponse n'a de sens qu'avec ce à quoi elle répond. Toutes les
    // messageries font remonter à l'original d'un appui sur le bloc
    // cité ; sans cela, il faut faire défiler à l'aveugle en espérant le
    // reconnaître.
    return GestureDetector(
      onTap: onOpenReplied == null
          ? null
          : () {
              OuroHaptics.light();
              onOpenReplied!();
            },
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: (mine ? Colors.white : OuroColors.meshBlue).withValues(
            alpha: 0.16,
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 3,
              height: 32,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    replied.senderId == message.senderId
                        ? replied.authorPseudo
                        : 'Vous',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    truncated,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: mine ? Colors.white70 : OuroColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// L'heure, et pour mes propres messages le statut, en pied de bulle.
  ///
  /// ⚠️ L'HEURE EST SECONDAIRE, ET DOIT LE RESTER. La version précédente
  /// écrivait « Lu 12:54 » en gras et en bleu vif dès que le message
  /// était lu : la mention pesait alors visuellement plus lourd que la
  /// phrase envoyée. Ici l'heure garde toujours le même poids ; c'est la
  /// petite icône à côté qui porte l'information de statut.
  /// Ce que fait un appui sur l'heure d'un message.
  ///
  /// Sur un message en échec : on le renvoie. Sur tous les autres : on
  /// ouvre le détail de la transmission. Le même endroit, deux actions —
  /// parce que sur un message échoué, personne ne cherche à lire par où
  /// il est passé : il n'est passé nulle part.
  VoidCallback _actionSurLHeure(BuildContext context) {
    final renvoi = onRenvoyer;
    if (message.status == MessageStatus.failed && renvoi != null) {
      return renvoi;
    }
    return () => showTransmissionSheet(context, message, mine: mine);
  }

  String get _libelleDeLHeure =>
      message.status == MessageStatus.failed && onRenvoyer != null
          ? 'Réessayer l\'envoi'
          : 'Détails de la transmission';

  Widget _timeAndStatus() {
    final read = message.readAt != null;
    final couleurStatut = _statusColor();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          _formatTime(message.timestamp),
          style: TextStyle(
            fontSize: 11,
            color: mine ? Colors.white70 : OuroColors.textTertiary,
          ),
        ),
        // Badge « modifié » — iMessage affiche « Edited » en gris à côté
        // de l'heure quand un message a été modifié.
        if (message.editedAt != null) ...[
          const SizedBox(width: 3),
          Text(
            'modifié',
            style: TextStyle(
              fontSize: 10,
              fontStyle: FontStyle.italic,
              color: mine
                  ? Colors.white.withValues(alpha: 0.5)
                  : OuroColors.textTertiary,
            ),
          ),
        ],
        // Icône d'auto-destruction — petit sablier à côté de l'heure.
        if (message.expiresInSeconds != null) ...[
          const SizedBox(width: 3),
          Icon(
            Icons.timer_off_rounded,
            size: 10,
            color: mine
                ? Colors.white.withValues(alpha: 0.5)
                : OuroColors.textTertiary,
          ),
        ],
        // Indicateur de fil — nombre de réponses dans le thread.
        if (threadCount > 0) ...[
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onOpenThread,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              decoration: BoxDecoration(
                color: (mine ? Colors.white : OuroColors.meshBlueBright)
                    .withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.forum_rounded,
                    size: 9,
                    color: mine
                        ? Colors.white.withValues(alpha: 0.7)
                        : OuroColors.meshBlueBright,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    '$threadCount',
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: mine
                          ? Colors.white.withValues(alpha: 0.7)
                          : OuroColors.meshBlueBright,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (mine) ...[
          const SizedBox(width: 4),
          // iMessage : "Delivered"/"Read" crossfade in 0.2s
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: couleurStatut),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOut,
            builder: (context, color, _) => Icon(
              _statusIconData(read),
              size: 13,
              color: color ?? couleurStatut,
            ),
          ),
        ],
      ],
    );
  }

  /// Le poids d'un fichier, écrit comme on le lit.
  ///
  /// Renvoie « Fichier » quand la taille est inconnue plutôt que « 0 o » :
  /// annoncer un fichier vide alors qu'on ne sait simplement pas
  /// tromperait sur ce qui va être transféré.
  static String _poidsLisible(int? octets) {
    if (octets == null || octets <= 0) return 'Fichier';
    if (octets < 1024) return '$octets o';
    if (octets < 1024 * 1024) {
      return '${(octets / 1024).toStringAsFixed(0)} Ko';
    }
    return '${(octets / (1024 * 1024)).toStringAsFixed(1)} Mo'
        .replaceAll('.', ',');
  }

  IconData _fileIconFor(String? mimeType) {
    if (mimeType == null) return Icons.attach_file_rounded;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf_rounded;
    if (mimeType.startsWith('audio')) return Icons.audiotrack_rounded;
    if (mimeType.startsWith('video')) return Icons.videocam_rounded;
    if (mimeType.contains('word') || mimeType.contains('document')) {
      return Icons.description_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  /// Vrai quand ce message est un sticker : uniquement des emojis, trois
  /// au maximum. Il s'affiche alors en grand et SANS bulle.
  bool get _isSticker =>
      message.type != 'file' && isStickerMessage(message.content);

  /// Ce message prolonge celui du dessus (même auteur, même moment).
  ///
  /// Il se colle alors au précédent et n'affiche plus le nom de son
  /// auteur : dans un groupe, le répéter à chaque bulle d'une même
  /// tirade rend le fil illisible.
  final bool suiteDuPrecedent;

  /// Ce message termine une série.
  ///
  /// Seule la dernière bulle d'une série porte le coin pointu qui
  /// désigne le locuteur — un empilement de bulles toutes pointues
  /// ressemble à une dentelure, pas à une conversation.
  final bool finDeSerie;

  /// Vrai quand ce message est une référence de sticker animé.
  bool get _isAnimatedSticker =>
      message.type != 'file' &&
      AnimatedStickerCatalog.estUneReference(message.content);

  /// Ce message est-il assez court pour loger l'heure à côté du texte ?
  ///
  /// Le seuil est volontairement bas. Le but n'est pas de gagner de la
  /// place à tout prix, mais d'éviter la bulle minuscule et disgracieuse
  /// des messages d'un ou deux mots. Dès qu'il y a une pièce jointe, une
  /// citation ou une réaction, l'empilement reste le bon choix : l'heure
  /// n'a plus d'espace libre où se glisser.
  bool get _heureSurLaMemeLigne =>
      message.type != 'file' &&
      !_sansBulle &&
      repliedMessage == null &&
      message.reactions.isEmpty &&
      message.effect != kEffectInvisibleInk &&
      message.content.length <= 22 &&
      !message.content.contains('\n');

  /// Les stickers — animés comme en emoji — sont posés à même la
  /// conversation, sans bulle autour. C'est ce qui les distingue d'un
  /// emoji tapé dans une phrase.
  bool get _sansBulle => _isSticker || _isAnimatedSticker;

  Widget _textBubble(bool isFile) {
    // Une position partagée devient une carte miniature. Sans ça, elle
    // s'afficherait telle qu'elle voyage — « 📍loc:3.848212,11.502341 » —
    // c'est-à-dire illisible.
    final location = LocationMessage.tryParse(message.content);
    if (location != null) {
      return LocationBubble(
        location: location,
        mine: mine,
        onOpen: onOpenLocation ?? () {},
      );
    }
    // Un sticker ANIMÉ : le message ne porte que sa référence, jamais
    // le fichier. L'animation est jouée depuis les assets locaux — et si
    // ce sticker manque sur cet appareil, `AnimatedStickerView` affiche
    // un repli lisible plutôt qu'un carré vide.
    if (_isAnimatedSticker) {
      // 104 et non 132 : à l'écran, un sticker de 132 points écrasait
      // complètement les bulles de texte voisines, au point de
      // déséquilibrer la lecture du fil. C'est la taille que retiennent
      // aussi WhatsApp et Telegram.
      return AnimatedStickerView(reference: message.content, taille: 104);
    }
    if (_isSticker) {
      return Text(
        message.content,
        style: TextStyle(
          fontSize: stickerFontSize(message.content),
          height: 1.0,
        ),
      );
    }
    // ── LINK PREVIEW ──────────────────────────────────────────────
    //
    // Quand le message contient une URL, on l'affiche dans une carte
    // stylisée plutôt qu'en texte brut. Sur un mesh sans internet, on
    // ne peut pas fetch le metadata — mais on peut au moins afficher
    // le domaine et un icône correspondant.
    final urlMatch = _extractUrl(message.content);
    if (urlMatch != null) {
      return _LinkPreviewCard(
        url: urlMatch,
        fullText: message.content,
        mine: mine,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (isFile) ...[
          // Une pastille carrée plutôt qu'une icône nue : elle donne au
          // fichier le poids d'une pièce jointe, là où la petite icône
          // grise se confondait avec la ponctuation du texte.
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: (mine ? Colors.white : OuroColors.accent)
                  .withValues(alpha: mine ? 0.20 : 0.14),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
              _fileIconFor(message.fileMimeType),
              color: mine ? Colors.white : OuroColors.accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 9),
        ],
        // Un fichier montre son nom ET son poids. « 2,4 Mo » répond à
        // la question qu'on se pose vraiment devant une pièce jointe sur
        // un réseau maillé : est-ce que ça va passer, et en combien de
        // temps.
        if (isFile)
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _highlighted(
                  message.content,
                  TextStyle(
                    color: mine ? Colors.white : OuroColors.textPrimary,
                    fontSize: 15,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _poidsLisible(message.fileSize),
                  style: TextStyle(
                    fontSize: 11,
                    color: mine ? Colors.white70 : OuroColors.textTertiary,
                  ),
                ),
              ],
            ),
          )
        else
        Flexible(
          child: _expandableTextContent(),
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  /// Contenu textuel du bulle : utilise `_ExpandableText` pour les
  /// messages longs (>100 caractères) et `_highlighted` pour la
  /// recherche active.
  Widget _expandableTextContent() {
    final style = TextStyle(
      color: mine ? Colors.white : OuroColors.textPrimary,
      fontSize: 15,
      height: 1.3,
    );

    // En recherche active, on garde le surlignage classique.
    if (query.isNotEmpty) {
      return _highlighted(message.content, style);
    }

    // Messages courts ou multimedia : pas de troncature.
    if (message.content.length <= _kExpandThreshold) {
      return _highlighted(message.content, style);
    }

    return _ExpandableText(
      text: message.content,
      style: style,
    );
  }

  /// Le texte du message, avec les occurrences recherchées surlignées.
  ///
  /// ⚠️ ON NE SURLIGNE QU'EN RECHERCHE ACTIVE. Hors recherche, [query]
  /// est vide et la méthode rend un `Text` ordinaire — pas de découpage
  /// de chaîne ni de `RichText` à construire pour chaque bulle de
  /// l'historique.
  ///
  /// La comparaison se fait en minuscules sur une copie, mais les
  /// morceaux affichés sont TAILLÉS DANS L'ORIGINAL : surligner
  /// « bonjour » ne doit pas transformer « Bonjour » en minuscules à
  /// l'écran.
  Widget _highlighted(String text, TextStyle style) {
    if (query.isEmpty) return Text(text, style: style);

    final lower = text.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;

    while (true) {
      final index = lower.indexOf(query, start);
      if (index < 0) break;
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: TextStyle(
            // Sur une bulle bleue, un surlignage bleu serait invisible :
            // on prend un fond jaune ambré et un texte noir, lisibles quel
            // que soit le côté de la conversation.
            backgroundColor: OuroColors.warningAmber.withValues(alpha: 0.55),
            color: Colors.black,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
      start = index + query.length;
    }

    if (spans.isEmpty) return Text(text, style: style);
    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start)));
    }
    return Text.rich(TextSpan(style: style, children: spans));
  }

  Widget _reactionChips() {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: message.reactions.map((r) {
        return Container(
          key: ValueKey('${message.id}-$r'),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: (mine ? Colors.white : OuroColors.meshBlue).withValues(
              alpha: 0.18,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(r, style: const TextStyle(fontSize: 11)),
        ).animate().scaleXY(
          begin: 0.4,
          end: 1,
          duration: DesignTokens.durationSlow,
          curve: DesignTokens.curveBounce,
        );
      }).toList(),
    );
  }

  Widget _audioBubble() {
    return VoiceNoteBubble(
      meta: VoiceNoteMeta.tryParse(message.fileName),
      fileSize: message.fileSize,
      mine: mine,
      playing: playingAudio,
      progress: playbackProgress,
      position: playbackPosition,
      speed: playbackSpeed,
      played: voicePlayed,
      onPlayPause: onPlayAudio,
      onSeek: onSeekAudio ?? (_) {},
      onCycleSpeed: onCycleSpeed ?? () {},
      onVoiceReply: onVoiceReply,
    );
  }

  String _formatTime(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  /// L'icône qui résume où en est ce message.
  ///
  /// ⚠️ CHAQUE ÉTAT CORRESPOND À UNE DONNÉE RÉELLE, aucun n'est décoratif :
  ///
  ///   • `sending` / `pending` — le message attend son tour dans la file.
  ///   • `sent` + `hopCount > 0` — il est parti, mais PAS en direct : il a
  ///     traversé au moins un appareil intermédiaire. C'est la
  ///     particularité de Droplet, et la seule application qui puisse
  ///     l'afficher honnêtement.
  ///   • `sent` seul — parti en liaison directe, sans accusé pour
  ///     l'instant.
  ///   • `deliveryCount > 0` — au moins un accusé de réception est
  ///     revenu.
  ///   • `readAt != null` — le destinataire a ouvert la conversation.
  ///   • `failed` — plus aucune route, après épuisement des tentatives.
  ///
  /// On n'invente donc pas d'état « en cours de relais » qu'aucune donnée
  /// ne viendrait soutenir.
  IconData _statusIconData(bool read) {
    return switch (message.status) {
      MessageStatus.sending || MessageStatus.pending =>
        Icons.schedule_rounded,
      MessageStatus.failed => Icons.error_outline_rounded,
      MessageStatus.sent when read || message.deliveryCount > 0 =>
        Icons.done_all_rounded,
      MessageStatus.sent => Icons.done_rounded,
    };
  }

  /// La couleur de fond de la bulle modulée par l'état du réseau.
  ///
  /// Quand le mesh est en transit (sending/pending), la bulle devient
  /// légèrement matte — l'utilisateur sent que le message est « en vol ».
  /// En cas d'échec, elle s'estompe pour signaler le problème sans cri.
  /// Quand le message est livré ou lu, la bulle est pleinement brillante.
  Color _bubbleColorForState({required bool mine, required MessageStatus status}) {
    final base = mine ? OuroColors.bubbleOutgoing : OuroColors.bubbleIncoming;
    return switch (status) {
      MessageStatus.sending || MessageStatus.pending =>
        base.withValues(alpha: 0.85), // matte — en transit
      MessageStatus.failed =>
        base.withValues(alpha: 0.55), // translucide — problème
      MessageStatus.sent => base, // plein — livré ou en attente d'ACK
    };
  }

  /// La couleur du statut.
  ///
  /// ⚠️ TOUT EST DISCRET SAUF DEUX CAS. L'ancienne version peignait
  /// l'attente en orange vif et l'envoi en vert vif : sur un fil de
  /// conversation, cela faisait une colonne de pastilles colorées qui
  /// captait le regard avant le texte. Or « envoyé » est l'état NORMAL
  /// de presque tous les messages — le signaler en couleur, c'est
  /// alerter en permanence sur ce qui va bien.
  ///
  /// Ne restent colorés que les deux états qui demandent vraiment
  /// quelque chose à l'utilisateur : l'échec (rouge, il faut agir) et la
  /// lecture (bleu Droplet, l'information qu'on attendait).
  Color _statusColor() {
    if (message.status == MessageStatus.failed) return OuroColors.errorRed;
    if (message.readAt != null) return OuroColors.meshBlueBright;
    return mine ? Colors.white70 : OuroColors.textTertiary;
  }
}

/// Extrait la première URL du texte. Retourne null si aucune URL n'est trouvée.
///
/// Sur un mesh sans internet, on ne peut pas fetch le metadata complet —
/// mais on peut détecter les URLs et afficher le domaine stylisé.
Uri? _extractUrl(String text) {
  final urlPattern = RegExp(
    r'https?://[^\s<>"{}|\\^`\[\]]+',
    caseSensitive: false,
  );
  final match = urlPattern.firstMatch(text);
  if (match != null) {
    return Uri.tryParse(match.group(0)!);
  }
  return null;
}

/// Carte de preview pour les URLs dans les messages.
///
/// Sur un mesh sans internet, on affiche le domaine et un icône
/// correspondant au type de contenu. C'est plus lisible qu'une URL brute.
class _LinkPreviewCard extends StatelessWidget {
  const _LinkPreviewCard({
    required this.url,
    required this.fullText,
    required this.mine,
  });

  final Uri url;
  final String fullText;
  final bool mine;

  IconData _iconForDomain(String host) {
    if (host.contains('youtube.com') || host.contains('youtu.be')) {
      return Icons.play_circle_fill;
    }
    if (host.contains('github.com')) {
      return Icons.code;
    }
    if (host.contains('twitter.com') || host.contains('x.com')) {
      return Icons.chat_bubble;
    }
    if (host.contains('instagram.com')) {
      return Icons.camera_alt;
    }
    if (host.contains('tiktok.com')) {
      return Icons.music_note;
    }
    if (host.contains('reddit.com')) {
      return Icons.forum;
    }
    return Icons.language;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final host = url.host;
    final icon = _iconForDomain(host);
    final hasTextBeforeUrl = fullText.trim() != url.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTextBeforeUrl) ...[
          SelectableText(
            fullText.replaceAll(url.toString(), '').trim(),
            style: TextStyle(
              color: theme.colorScheme.onSurface,
              fontSize: 15.5,
            ),
          ),
          const SizedBox(height: 4),
        ],
        Container(
          constraints: const BoxConstraints(maxWidth: 280),
          decoration: BoxDecoration(
            color: mine
                ? theme.colorScheme.primary.withValues(alpha: 0.08)
                : theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3),
            ),
          ),
          // ⚠️ C'ÉTAIT `Material` + `InkWell`, uniquement pour obtenir
          // l'onde d'Android. Dans une bulle de conversation — l'élément
          // le plus regardé de l'app — c'était la dernière onde Material
          // encore visible à l'écran.
          child: OuroPressable(
            onTap: () => _openUrl(context),
            child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        icon,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            host,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: theme.colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            url.path.isEmpty ? '/' : url.path,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.5),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.open_in_new,
                      size: 14,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  void _openUrl(BuildContext context) {
    // Sur un mesh, on ne peut pas ouvrir dans un browser — mais on peut
    // copier l'URL dans le presse-papier pour un usage ultérieur.
    // TODO: Utiliser url_launcher quand disponible.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('URL copiée : ${url.toString()}'),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

/// Vignette d'une VIDÉO partagée, avec lecture en plein écran au tap.
///
/// La vignette est la PREMIÈRE IMAGE de la vidéo, extraite à
/// l'affichage. C'est ce qui distingue une vidéo reçue d'un fichier
/// anonyme : on voit tout de suite de quoi il s'agit, sans avoir à
/// l'ouvrir.
class _VideoBubble extends StatefulWidget {
  const _VideoBubble({required this.fileId, required this.fileName});

  final String fileId;
  final String fileName;

  @override
  State<_VideoBubble> createState() => _VideoBubbleState();
}

class _VideoBubbleState extends State<_VideoBubble> {
  VideoPlayerController? _controller;
  String? _path;
  bool _missing = false;

  @override
  void initState() {
    super.initState();
    _prepare();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _prepare() async {
    final path = await StorageService.getSharedFilePath(
      widget.fileId,
      widget.fileName,
    );
    if (!mounted) return;
    if (path == null) {
      setState(() => _missing = true);
      return;
    }

    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _controller = controller;
        _path = path;
      });
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() => _missing = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    if (_missing) {
      return _frame(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.movie_outlined,
                color: OuroColors.tertiaryLabel,
                size: 34,
              ),
              const SizedBox(height: 8),
              Text(
                'Vidéo en cours de réception',
                style: OuroTypography.caption1.copyWith(
                  color: OuroColors.tertiaryLabel,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (controller == null || !controller.value.isInitialized) {
      return _frame(
        child: const Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: OuroSpinner(color: Colors.white54, radius: 9),
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        OuroHaptics.light();
        Navigator.of(context).push(
          PageRouteBuilder<void>(
            opaque: false,
            barrierColor: Colors.black,
            pageBuilder: (_, _, _) => _VideoViewerScreen(path: _path!),
          ),
        );
      },
      child: _frame(
        child: Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: controller.value.size.width,
                height: controller.value.size.height,
                child: VideoPlayer(controller),
              ),
            ),
            // Le bouton de lecture par-dessus : sans lui, une vignette
            // immobile ne se distingue pas d'une photo.
            Center(
              child: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.black.withValues(alpha: 0.5),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                  size: 30,
                ),
              ),
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  _fmt(controller.value.duration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _frame({required Widget child}) => ClipRRect(
    borderRadius: BorderRadius.circular(DesignTokens.radiusBubble),
    child: Container(
      width: 220,
      height: 148,
      color: Colors.black26,
      child: child,
    ),
  );

  static String _fmt(Duration d) {
    final sec = d.inSeconds;
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }
}

/// Le lecteur plein écran d'une vidéo reçue.
class _VideoViewerScreen extends StatefulWidget {
  const _VideoViewerScreen({required this.path});
  final String path;

  @override
  State<_VideoViewerScreen> createState() => _VideoViewerScreenState();
}

class _VideoViewerScreenState extends State<_VideoViewerScreen> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    _open();
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final controller = VideoPlayerController.file(File(widget.path));
    await controller.initialize();
    if (!mounted) {
      await controller.dispose();
      return;
    }
    setState(() => _controller = controller);
    await controller.play();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      // Un lecteur vidéo reste noir dans les deux modes, comme partout
      // ailleurs : c'est ce qui met l'image en valeur.
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: () {
          if (controller == null) return;
          setState(() {
            controller.value.isPlaying ? controller.pause() : controller.play();
          });
        },
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 200) Navigator.of(context).pop();
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (controller != null && controller.value.isInitialized)
              Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: VideoPlayer(controller),
                ),
              )
            else
              const Center(
                child: OuroSpinner(color: Colors.white38, radius: 14),
              ),

            if (controller != null && controller.value.isInitialized)
              Positioned(
                left: 16,
                right: 16,
                bottom: 40,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors: VideoProgressColors(
                    playedColor: OuroColors.accent,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),

            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
            ),

            if (controller != null &&
                controller.value.isInitialized &&
                !controller.value.isPlaying)
              Center(
                child: Container(
                  width: 68,
                  height: 68,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Vignette d'une image partagée, avec ouverture en plein écran au tap.
/// La vignette d'une image reçue ou envoyée.
///
/// ⚠️ TROIS DÉFAUTS SE CUMULAIENT ICI, et c'est ce qui faisait
/// « clignoter et sauter » toute la conversation pendant le défilement.
///
/// **1. Le chemin du fichier était recalculé à chaque construction.**
/// Le `FutureBuilder` recevait un `Future` fabriqué DANS `build()`. Or
/// une liste recycle ses éléments : chaque fois qu'une image
/// réapparaissait à l'écran, un nouveau `Future` démarrait,
/// `connectionState` repassait à « en cours », et l'image cédait la
/// place au chargeur — puis revenait. D'où le rechargement permanent.
///
/// **2. Le chargeur ne faisait pas la même taille que l'image.**
/// 220×160 pour l'un, 220×220 pour l'autre. Chaque bascule changeait la
/// hauteur de la bulle de soixante points, et poussait TOUS les messages
/// du dessous. C'est ce déplacement-là qu'on ressent comme un saut — y
/// compris sur les messages vocaux, qui n'y sont pour rien : ils sont
/// simplement bousculés par l'image du dessus.
///
/// **3. La photo était décodée en pleine résolution.**
/// `Image.file` sans `cacheWidth` décode l'image d'origine tout entière
/// avant de la réduire à 220 points. Une photo de téléphone occupe
/// alors une cinquantaine de méga-octets en mémoire — assez, à elle
/// seule, pour vider le cache d'images de l'application et forcer le
/// rechargement de toutes les autres.
class _ImageBubble extends StatefulWidget {
  const _ImageBubble({required this.fileId, required this.fileName});
  final String fileId;
  final String fileName;

  /// Le côté de la vignette. Une seule constante pour l'image ET le
  /// chargeur : c'est ce qui garantit qu'aucune bascule ne change la
  /// hauteur de la bulle.
  static const double cote = 220;

  /// Les chemins déjà résolus, partagés par toutes les vignettes.
  ///
  /// Un identifiant de fichier désigne toujours le même fichier : le
  /// chemin n'a donc besoin d'être cherché qu'une fois pour toute la
  /// session. C'est ce qui supprime le clignotement au recyclage — au
  /// retour à l'écran, le chemin est déjà connu et l'image s'affiche
  /// sans passer par le chargeur.
  static final Map<String, String?> _chemins = {};

  @override
  State<_ImageBubble> createState() => _ImageBubbleState();
}

class _ImageBubbleState extends State<_ImageBubble> {
  String? _chemin;
  bool _cherche = true;

  String get _cle => '${widget.fileId}-${widget.fileName}';

  @override
  void initState() {
    super.initState();
    _resoudre();
  }

  @override
  void didUpdateWidget(_ImageBubble old) {
    super.didUpdateWidget(old);
    // La liste a recyclé cette case pour un AUTRE message : il faut
    // rechercher, sinon on afficherait l'image du message précédent.
    if (old.fileId != widget.fileId || old.fileName != widget.fileName) {
      _resoudre();
    }
  }

  void _resoudre() {
    if (_ImageBubble._chemins.containsKey(_cle)) {
      _chemin = _ImageBubble._chemins[_cle];
      _cherche = false;
      return;
    }
    _cherche = true;
    StorageService.getSharedFilePath(widget.fileId, widget.fileName)
        .then((chemin) {
      _ImageBubble._chemins[_cle] = chemin;
      if (!mounted) return;
      setState(() {
        _chemin = chemin;
        _cherche = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final chemin = _chemin;
    if (chemin == null) return _placeholder(loading: _cherche);

    return ClipRRect(
      // MÊME rayon que la bulle : depuis que les médias vont d'un bord à
      // l'autre, deux arrondis différents laisseraient voir un croissant
      // de couleur dans chaque coin.
      borderRadius: BorderRadius.circular(DesignTokens.radiusBubble),
      child: GestureDetector(
        onTap: () => Navigator.of(context).push(
          PageRouteBuilder(
            opaque: false,
            barrierColor: Colors.black,
            pageBuilder: (context, animation, secondary) =>
                _ImageViewerScreen(path: chemin),
            transitionsBuilder: (context, animation, secondary, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        ),
        child: Image.file(
          File(chemin),
          width: _ImageBubble.cote,
          height: _ImageBubble.cote,
          fit: BoxFit.cover,
          // Décodage borné : on ne garde jamais en mémoire plus de pixels
          // qu'il n'en faut pour cette vignette. Le facteur 2 laisse de
          // la marge pour les écrans à forte densité sans jamais
          // approcher la taille d'origine.
          cacheWidth: (_ImageBubble.cote * 2).round(),
          // Évite le fondu à blanc entre deux images pendant le
          // défilement : la précédente reste affichée jusqu'à ce que la
          // suivante soit prête.
          gaplessPlayback: true,
          errorBuilder: (context, error, stackTrace) =>
              _placeholder(loading: false),
        ),
      ),
    );
  }

  Widget _placeholder({required bool loading}) {
    return Container(
      // MÊME taille que l'image. Voir le défaut n°2 ci-dessus.
      width: _ImageBubble.cote,
      height: _ImageBubble.cote,
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: loading
          ? const SizedBox(
              width: 22,
              height: 22,
              child: OuroSpinner(color: Colors.white70, radius: 9),
            )
          : const Icon(Icons.broken_image_rounded, color: Colors.white54),
    );
  }
}


/// Bulle affichant une vidéo dans une conversation.
/// Visionneuse plein écran : zoom (pincer) et fermeture par glissement
/// vertical, comme dans les messageries grand public.
class _ImageViewerScreen extends StatefulWidget {
  const _ImageViewerScreen({required this.path});
  final String path;

  @override
  State<_ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<_ImageViewerScreen> {
  double _dragOffset = 0;
  double _opacity = 1;

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _dragOffset += details.delta.dy;
      _opacity = (1 - (_dragOffset.abs() / 300)).clamp(0.3, 1.0);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    if (_dragOffset.abs() > 120) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _dragOffset = 0;
        _opacity = 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onVerticalDragUpdate: _onDragUpdate,
      onVerticalDragEnd: _onDragEnd,
      child: Scaffold(
        backgroundColor: Colors.black.withValues(alpha: _opacity),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        extendBodyBehindAppBar: true,
        body: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: Center(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.file(File(widget.path)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Dessine la petite « forme d'onde » figée (18 barres de hauteurs
/// différentes) qu'on voit sur un message vocal déjà envoyé — les
/// barres avant la position de lecture s'allument dans une couleur
/// différente au fur et à mesure que l'audio avance.
/// Le petit bouton flottant « ↓ 3 » qui apparaît quand on est remonté
/// dans l'historique et que de nouveaux messages arrivent en bas — un
/// tap ramène directement au dernier message.
class _JumpButton extends StatelessWidget {
  const _JumpButton({required this.unread, required this.onTap});
  final int unread;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
          onTap: onTap,
          child: OuroCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: OuroColors.textPrimary,
                ),
                // ⚠️ LE COMPTEUR NE S'AFFICHE QUE S'IL COMPTE QUELQUE
                // CHOSE.
                //
                // Le bouton écrivait « 0 » quand on remontait dans
                // l'historique sans qu'aucun message ne soit arrivé
                // depuis. Un badge qui annonce zéro est pire qu'un badge
                // absent : il attire l'œil pour dire qu'il n'y a rien à
                // voir, et donne l'impression d'un compteur cassé.
                if (unread > 0) ...[
                  const SizedBox(width: 4),
                  Text(
                    '$unread',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: OuroColors.textPrimary,
                    ),
                  ),
                ],
              ],
            ),
          ),
        )
        .animate()
        .scale(
          begin: const Offset(0.6, 0.6),
          curve: Curves.easeOutCubic,
          duration: 300.ms,
        )
        .fadeIn(duration: 200.ms);
  }
}

/// Toute la barre du bas de l'écran de conversation : champ de texte,
/// bouton pièce jointe, bouton micro (qui se transforme en petit
/// graphique d'enregistrement quand on le maintient appuyé), bouton
/// d'envoi, et l'éventuel aperçu « en réponse à... » juste au-dessus.
class _InputBar extends StatefulWidget {
  const _InputBar({
    required this.champKey,
    required this.controller,
    required this.recording,
    required this.recordingLocked,
    required this.amplitudes,
    required this.replyPreview,
    required this.onChanged,
    required this.onSend,
    required this.onMicStart,
    required this.onMicStop,
    required this.onMicCancel,
    required this.onMicLock,
    required this.onAttach,
    required this.onSticker,
    required this.onAttachMedia,
    required this.onCancelReply,
  });

  /// Où commence le vol d'envoi : la boîte de texte elle-même.
  final GlobalKey champKey;

  final TextEditingController controller;
  final bool recording;

  /// Enregistrement « mains libres » : le doigt a été relevé, mais le
  /// micro continue.
  final bool recordingLocked;

  final List<double> amplitudes;
  final MeshMessage? replyPreview;
  final ValueChanged<String> onChanged;
  final void Function([String? effect]) onSend;
  final Future<void> Function() onMicStart;
  final Future<void> Function() onMicStop;
  final Future<void> Function() onMicCancel;
  final VoidCallback onMicLock;
  final VoidCallback onAttach;

  /// Ouvre le panneau de stickers, depuis l'icône de gauche.
  final VoidCallback onSticker;

  /// Le raccourci de l'appui long : directement les photos et vidéos.
  final VoidCallback onAttachMedia;
  final VoidCallback onCancelReply;

  @override
  State<_InputBar> createState() => _InputBarState();
}

class _InputBarState extends State<_InputBar>
    with SingleTickerProviderStateMixin {
  Timer? _recTimer;
  int _recSeconds = 0;
  late final AnimationController _pulse;
  bool _hasText = false;
  double _micDragX = 0;
  double _micDragY = 0;
  bool _micWillCancel = false;

  /// Repère la rangée d'enregistrement à l'écran.
  ///
  /// Sert à savoir D'OÙ le micro doit s'envoler quand on jette la prise.
  /// Sans position réelle, l'animation partirait d'un coin arbitraire et
  /// on ne relierait pas ce qui vole à ce qu'on vient d'abandonner.
  final GlobalKey _recBarKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    widget.controller.addListener(_onController);
  }

  void _onController() {
    final hasText = widget.controller.text.trim().isNotEmpty;
    if (hasText != _hasText) setState(() => _hasText = hasText);
  }

  @override
  void dispose() {
    _pulse.dispose();
    _recTimer?.cancel();
    widget.controller.removeListener(_onController);
    super.dispose();
  }

  /// ⚠️ Le minuteur et la pulsation sont pilotés PAR L'ÉTAT, pas par le
  /// geste.
  ///
  /// Ils étaient auparavant démarrés dans `_startMic`, c'est-à-dire
  /// uniquement quand on appuyait sur le bouton micro. Or il existe un
  /// second chemin : le petit micro de réponse rapide posé à côté d'un
  /// vocal reçu, qui lance l'enregistrement directement depuis l'écran
  /// parent. Par ce chemin-là, le compteur restait figé sur « 0:00 »
  /// pendant tout l'enregistrement et la pastille rouge ne clignotait
  /// pas — on ne pouvait pas savoir si le micro écoutait vraiment.
  ///
  /// En réagissant ici au passage de `recording` à vrai, les deux
  /// chemins sont couverts, quel que soit celui qui déclenchera le
  /// prochain enregistrement.
  @override
  void didUpdateWidget(_InputBar old) {
    super.didUpdateWidget(old);
    if (widget.recording && !old.recording) {
      _beginRecordingVisuals();
    } else if (!widget.recording && old.recording) {
      _resetMicVisuals();
    }
  }

  void _beginRecordingVisuals() {
    _recSeconds = 0;
    _pulse.repeat(reverse: true);
    _recTimer?.cancel();
    _recTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _recSeconds++);
    });
  }

  Future<void> _startMic() => widget.onMicStart();

  Future<void> _stopMic() => widget.onMicStop();

  /// Jette l'enregistrement en cours — et montre où il part.
  ///
  /// ⚠️ ICI, L'ACTION PASSE AVANT L'ANIMATION. C'est l'inverse de la
  /// suppression d'un message.
  ///
  /// Pour un message, on retarde la suppression jusqu'à l'entrée dans la
  /// corbeille, pour que la liste ne se réorganise pas sous l'animation.
  /// Pour un enregistrement, ce serait une faute : le micro serait encore
  /// ouvert pendant les sept dixièmes de seconde du vol, alors que
  /// l'utilisateur vient de dire « non ». On coupe donc immédiatement, et
  /// ce qui vole n'est plus qu'un souvenir de ce qui a déjà été jeté.
  Future<void> _cancelMic() async {
    _jeterLEnregistrement();
    return widget.onMicCancel();
  }

  /// L'animation seule : le micro s'envole et tombe dans la corbeille.
  void _jeterLEnregistrement() {
    final boite =
        _recBarKey.currentContext?.findRenderObject() as RenderBox?;
    if (!mounted || boite == null || !boite.hasSize || !boite.attached) return;

    final barre = boite.localToGlobal(Offset.zero) & boite.size;

    // Le point de départ : la gauche de la barre, là où bat la pastille
    // rouge — c'est l'endroit que l'œil associe à « ça enregistre ».
    const cote = 44.0;
    final depart = Rect.fromCenter(
      center: Offset(barre.left + cote / 2, barre.center.dy),
      width: cote,
      height: cote,
    );

    TrashTossOverlay.jouer(
      context,
      origine: depart,
      apercu: const _MicJete(),
      // La corbeille se pose AU-DESSUS de la barre de saisie, pas au
      // centre de l'écran : sinon elle tomberait derrière la barre
      // elle-même, qui occupe déjà tout le bas.
      cible: Offset(barre.center.dx, barre.top - 58),
      // Rien à faire à l'arrivée : l'enregistrement est déjà annulé.
      onAvalee: () {},
    );
  }

  void _resetMicVisuals() {
    _pulse.stop();
    _pulse.value = 0;
    _recTimer?.cancel();
    // Simple affectation, sans `setState` : cette méthode n'est appelée
    // que depuis `didUpdateWidget`, où une reconstruction est déjà en
    // route de toute façon.
    _micDragX = 0;
    _micDragY = 0;
    _micWillCancel = false;
  }

  void _onMicDragUpdate(double dx, double dy, bool willCancel) {
    if (willCancel != _micWillCancel) HapticFeedback.selectionClick();
    setState(() {
      _micDragX = dx;
      _micDragY = dy;
      _micWillCancel = willCancel;
    });
  }

  void _onMicLock() {
    HapticFeedback.mediumImpact();
    widget.onMicLock();
    setState(() {
      _micDragX = 0;
      _micDragY = 0;
      _micWillCancel = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final rec = widget.recording;
    final locked = rec && widget.recordingLocked;
    final recLabel =
        '${_recSeconds ~/ 60}:${(_recSeconds % 60).toString().padLeft(2, '0')}';
    final reply = widget.replyPreview;

    // ── LA BARRE DE SAISIE FLOTTE ──────────────────────────────────
    //
    // Elle n'est plus une bande opaque collée au bas de l'écran, barrée
    // d'un filet gris. C'est une capsule translucide posée AU-DESSUS de
    // la conversation, à travers laquelle on continue de voir le fond et
    // les derniers messages défiler.
    //
    // C'est le changement signature d'iOS 26, repris par WhatsApp en
    // 2026 sous le nom de « floating chat bar ». L'intérêt n'est pas
    // décoratif : la bande opaque coupait l'écran en deux et donnait
    // l'impression que la conversation s'arrêtait là. La capsule, elle,
    // laisse la conversation aller jusqu'en bas — l'écran paraît plus
    // grand sans qu'on ait retiré quoi que ce soit.
    //
    // ⚠️ Le flou reste MODÉRÉ et un voile opaque subsiste derrière le
    // contenu. Une transparence totale rendrait le texte qu'on est en
    // train de taper illisible dès qu'une photo passe dessous — et le
    // champ de saisie est le seul endroit de l'écran où l'on ne peut pas
    // se permettre la moindre hésitation de lecture.
    return Padding(
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 6,
        bottom: MediaQuery.paddingOf(context).bottom + 8,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: BackdropFilter(
          // Le matériau partagé : la barre de saisie est du châssis, au
          // même titre que la barre d'onglets. Sur un fond de
          // conversation coloré, un flou sans saturation la faisait
          // paraître grise alors que tout le reste de l'écran vibrait.
          // 18 : la valeur réglée à la main pour cette barre, conservée.
          filter: OuroMaterialFilter.flou(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
            decoration: BoxDecoration(
              color: OuroColors.secondarySystemBackground
                  .withValues(alpha: 0.78),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(
                color: OuroColors.separator.withValues(alpha: 0.6),
                width: 0.5,
              ),
            ),
            child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (reply != null) _replyPreviewBar(reply),
          // Mains libres : la rangée change complètement de rôle — plus
          // rien à maintenir, on dispose d'une corbeille et d'un bouton
          // d'envoi, comme dans WhatsApp une fois le micro verrouillé.
          if (locked)
            _lockedRow(recLabel)
          else
            Row(
              children: [
                // ── LA PILULE, PUIS LE BOUTON ROND ───────────────
                //
                // Structure reprise de WhatsApp : TOUT ce qui touche à la
                // composition vit DANS une pilule blanche — sticker à
                // gauche, texte au milieu, trombone à droite — et le
                // bouton d'action principal est un CERCLE PLEIN posé à
                // côté, hors de la pilule.
                //
                // Ce n'est pas un choix esthétique. Le cercle plein est
                // la seule chose colorée de la barre : il devient le
                // point d'arrivée du regard, et le geste « j'envoie »
                // n'a plus qu'une cible possible. Fondu dans la pilule
                // comme avant, il se disputait l'attention avec le champ
                // de saisie.
                Expanded(
                  child: rec
                      ? _recordingRow(recLabel)
                      : OuroCard(
                          padding: const EdgeInsets.only(left: 6, right: 4),
                          child: Row(
                            children: [
                              // Sticker à GAUCHE, dans la pilule.
                              _IconePilule(
                                icone: Icons.emoji_emotions_outlined,
                                tooltip: 'Stickers',
                                onTap: widget.onSticker,
                              ),
                              Expanded(child: _textField()),
                              // Trombone à DROITE : il ouvre le panneau
                              // des pièces jointes.
                              _IconePilule(
                                icone: Icons.attach_file_rounded,
                                tooltip: 'Joindre',
                                onTap: widget.onAttach,
                              ),
                            ],
                          ),
                        ),
                ),
                const SizedBox(width: 8),
                // Le cadenas qui monte au-dessus du micro pendant qu'on
                // maintient : c'est l'indice qui rend le geste
                // découvrable. Sans lui, personne ne devine qu'on peut
                // glisser vers le haut.
                // ── MICRO **OU** ENVOYER, JAMAIS LES DEUX ────────
                //
                // Les deux boutons étaient affichés côte à côte en
                // permanence. C'est un contresens : on n'enregistre pas
                // un vocal et on n'envoie pas un texte en même temps, et
                // deux boutons voisins dont un seul est utile obligent à
                // choisir à chaque message.
                //
                // Le micro cède donc la place à l'avion dès le premier
                // caractère tapé, et la reprend dès que le champ se vide
                // — c'est ce que font WhatsApp, Telegram et iMessage.
                //
                // La bascule est un fondu croisé avec une légère mise à
                // l'échelle. Volontairement COURTE (160 ms) : cette
                // transition se joue à chaque premier caractère de chaque
                // message, des centaines de fois par jour. Tout ce qui
                // dépasse se transforme en attente.
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: (_hasText && !rec)
                      ? _BoutonRond(
                          key: const ValueKey('envoyer'),
                          child: _AnimatedSendButton(
                            active: true,
                            onSend: widget.onSend,
                          ),
                        )
                      : _MicButton(
                          key: const ValueKey('micro'),
                          recording: rec,
                          pulse: _pulse,
                          dragY: _micDragY,
                          onMicStart: _startMic,
                          onMicStop: _stopMic,
                          onMicCancel: _cancelMic,
                          onMicLock: _onMicLock,
                          onDragUpdate: _onMicDragUpdate,
                        ),
                ),
              ],
            ),
            ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _textField() {
    return KeyedSubtree(
      key: widget.champKey,
      child: _champ(),
    );
  }

  Widget _champ() {
    return TextField(
        autofocus: true,
      controller: widget.controller,
      minLines: 1,
      maxLines: 4,
      textCapitalization: TextCapitalization.sentences,
      onChanged: widget.onChanged,
      onSubmitted: (_) => widget.onSend(),
      cursorColor: OuroColors.accent,
      style: OuroTypography.body.copyWith(color: OuroColors.label),
      magnifierConfiguration: TextMagnifier.adaptiveMagnifierConfiguration,
      decoration: InputDecoration(
        hintText: 'Message',
        hintStyle: OuroTypography.body.copyWith(
          color: OuroColors.tertiaryLabel,
        ),
        // ⚠️ PLUS AUCUN FOND ICI.
        //
        // Le champ avait le sien, posé dans la capsule de la barre :
        // deux surfaces empilées, deux arrondis concentriques, une dalle
        // grise au milieu d'un élément censé être translucide.
        //
        // Désormais c'est la PILULE qui porte le fond, et le champ n'est
        // plus qu'un curseur et du texte posés dessus — comme chez
        // WhatsApp, où l'on ne distingue jamais le champ de son
        // conteneur.
        filled: false,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 6,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(20),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  /// Rangée affichée pendant qu'on MAINTIENT le micro : pastille rouge,
  /// minuteur, forme d'onde en direct, et l'indice « glisser pour
  /// annuler » qui bascule en « relâcher pour annuler » au-delà du seuil.
  Widget _recordingRow(String recLabel) {
    return AnimatedSwitcher(
      key: _recBarKey,
      duration: 150.ms,
      child: _micWillCancel
          ? Row(
              key: const ValueKey('cancel-hint'),
              children: [
                Icon(
                  Icons.delete_outline_rounded,
                  color: OuroColors.systemRed,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Relâchez pour annuler',
                  style: OuroTypography.subheadline.copyWith(
                    color: OuroColors.systemRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          : Row(
              key: const ValueKey('recording'),
              children: [
                AnimatedBuilder(
                  animation: _pulse,
                  builder: (context, _) => Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: OuroColors.systemRed.withValues(
                        alpha: 0.45 + _pulse.value * 0.55,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  recLabel,
                  style: OuroTypography.subheadline.copyWith(
                    color: OuroColors.label,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(child: _LiveWaveform(amplitudes: widget.amplitudes)),
                const SizedBox(width: 8),
                Icon(
                  Icons.chevron_left_rounded,
                  size: 16,
                  color: OuroColors.tertiaryLabel.withValues(
                    alpha: (_micDragX.abs() / 80).clamp(0.35, 1.0),
                  ),
                ),
                Text(
                  'Annuler',
                  style: OuroTypography.caption1.copyWith(
                    color: OuroColors.tertiaryLabel,
                  ),
                ),
              ],
            ),
    );
  }

  /// Rangée de l'enregistrement MAINS LIBRES : plus rien à maintenir.
  Widget _lockedRow(String recLabel) {
    return Row(
      key: _recBarKey,
      children: [
        IconButton(
          tooltip: "Supprimer l'enregistrement",
          icon: Icon(Icons.delete_outline_rounded, color: OuroColors.systemRed),
          onPressed: _cancelMic,
        ),
        AnimatedBuilder(
          animation: _pulse,
          builder: (context, _) => Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: OuroColors.systemRed.withValues(
                alpha: 0.45 + _pulse.value * 0.55,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          recLabel,
          style: OuroTypography.subheadline.copyWith(
            color: OuroColors.label,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: _LiveWaveform(amplitudes: widget.amplitudes)),
        const SizedBox(width: 8),
        _SendCircle(onTap: _stopMic),
      ],
    );
  }

  Widget _replyPreviewBar(MeshMessage m) {
    final snippet = m.type == 'file'
        ? VoiceNoteMeta.describeAttachment(m.fileName)
        : m.content;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, right: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: OuroColors.tertiarySystemFill,
          borderRadius: BorderRadius.circular(12),
          // Un filet vertical coloré du côté du texte, comme dans
          // Messages : plus discret qu'un contour complet, et il désigne
          // clairement ce à quoi on répond.
          border: Border(left: BorderSide(color: OuroColors.accent, width: 3)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Réponse à ${m.authorPseudo}',
                    style: OuroTypography.caption1.copyWith(
                      color: OuroColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    snippet,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OuroTypography.footnote.copyWith(
                      color: OuroColors.secondaryLabel,
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: widget.onCancelReply,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close_rounded,
                  color: OuroColors.tertiaryLabel,
                  size: 18,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Le petit graphique EN DIRECT qui bouge pendant qu'on enregistre sa
/// voix, en réaction au volume réellement capté par le micro.
///
/// Les nouvelles barres arrivent par la DROITE et poussent les
/// précédentes vers la gauche, comme un sismographe : c'est ce qui donne
/// la sensation que le temps défile, plutôt qu'un tas de barres qui
/// s'agitent sur place.
class _LiveWaveform extends StatelessWidget {
  const _LiveWaveform({required this.amplitudes});
  final List<double> amplitudes;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 28,
      // Pas d'`AnimatedSwitcher` ici : il était piloté par une clé qui
      // changeait à CHAQUE relevé (toutes les 80 ms), ce qui relançait un
      // fondu enchaîné complet dix fois par seconde — l'onde clignotait
      // au lieu de défiler.
      child: CustomPaint(
        painter: _LiveWaveformPainter(
          amplitudes: amplitudes,
          color: OuroColors.systemRed,
        ),
        size: Size.infinite,
      ),
    );
  }
}

class _LiveWaveformPainter extends CustomPainter {
  _LiveWaveformPainter({required this.amplitudes, required this.color});

  final List<double> amplitudes;
  final Color color;

  static const double _barWidth = 3;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0) return;
    final slot = _barWidth + _gap;
    final capacity = (size.width / slot).floor();
    if (capacity <= 0) return;

    // On ne garde que ce qui tient à l'écran, et on aligne à DROITE :
    // la barre la plus récente est toujours collée au bord droit, à
    // l'endroit exact où l'œil l'attend.
    final visible = amplitudes.length > capacity
        ? amplitudes.sublist(amplitudes.length - capacity)
        : amplitudes;

    final mid = size.height / 2;
    var x = size.width - _barWidth / 2;

    // ── DÉFORMATION DYNAMIQUE ─────────────────────────────────────
    //
    // La waveform résonne quand la voix est forte, et se rétracte
    // quand elle est douce. Le visualisateur devient un instrument :
    //   • Amplitude > 0.8 = barres très hautes, légère rotation
    //   • Amplitude > 0.5 = barres moyennes, pas de rotation
    //   • Amplitude < 0.3 = barres courtes, effet de rétraction
    for (var i = visible.length - 1; i >= 0; i--) {
      final v = visible[i].clamp(0.0, 1.0);

      // Hauteur de base avec déformation proportionnelle à l'amplitude
      final baseHeight = 3 + v * (size.height - 4);
      // Les barres hautes "résonnent" — leur hauteur oscille légèrement
      final resonance = v > 0.7 ? math.sin(i * 0.5) * 2 * v : 0.0;
      final h = (baseHeight + resonance).clamp(2.0, size.height);

      // Les barres les plus anciennes s'effacent progressivement vers la
      // gauche, ce qui évite un bord net et artificiel.
      final age = (visible.length - i) / capacity;
      final fade = (1.0 - age * 0.55).clamp(0.25, 1.0);

      // ── COULEUR DYNAMIQUE ─────────────────────────────────────
      //
      // Les barres fortes sont plus saturées, les faibles plus ternes.
      // C'est ce qui crée l'effet de "résonance visuelle".
      final saturation = 0.45 + v * 0.55;
      final barColor = Color.lerp(
        color.withValues(alpha: 0.3),
        color,
        saturation,
      )!;

      canvas.drawLine(
        Offset(x, mid - h / 2),
        Offset(x, mid + h / 2),
        Paint()
          ..color = barColor.withValues(alpha: fade)
          ..strokeWidth = _barWidth
          ..strokeCap = StrokeCap.round,
      );
      x -= slot;
      if (x < 0) break;
    }
  }

  @override
  bool shouldRepaint(_LiveWaveformPainter old) =>
      old.amplitudes.length != amplitudes.length || old.color != color;
}

/// Bouton micro « presser pour enregistrer » façon WhatsApp/Telegram/Signal.
///
/// Implémenté avec [Listener] (événements pointeur bruts) plutôt que
/// [GestureDetector.onTapDown]/[onLongPressStart] combinés : ces deux
/// reconnaisseurs partagés sur un même détecteur entraient en conflit dans
/// l'arène de gestes — `onTapDown` se déclenche de façon optimiste dès le
/// contact, PUIS `onLongPressStart` se déclenchait une seconde fois ~500ms
/// plus tard sur un appui maintenu (le cas normal pour un message vocal),
/// démarrant l'enregistrement deux fois et laissant l'UI dans un état
/// incohérent. [Listener] ne participe pas à l'arène de gestes : chaque
/// pointeur ne produit qu'un down/move/up, sans ambiguïté possible.
class _MicButton extends StatefulWidget {
  const _MicButton({
    super.key,
    required this.recording,
    required this.pulse,
    required this.dragY,
    required this.onMicStart,
    required this.onMicStop,
    required this.onMicCancel,
    required this.onMicLock,
    required this.onDragUpdate,
  });

  final bool recording;
  final Animation<double> pulse;

  /// De combien le doigt est remonté depuis le point d'appui (négatif).
  final double dragY;

  final Future<void> Function() onMicStart;
  final Future<void> Function() onMicStop;
  final Future<void> Function() onMicCancel;

  /// Le doigt est monté assez haut : on passe en mains libres.
  final VoidCallback onMicLock;

  final void Function(double dx, double dy, bool willCancel) onDragUpdate;

  @override
  State<_MicButton> createState() => _MicButtonState();
}

class _MicButtonState extends State<_MicButton> {
  /// Distance de glissement vers la gauche au-delà de laquelle on annule.
  static const double _cancelThreshold = 80;

  /// Distance de glissement vers le haut au-delà de laquelle on
  /// verrouille. Plus court que l'annulation : verrouiller est un geste
  /// qu'on veut trouver facilement, annuler un geste qu'on ne veut
  /// surtout pas déclencher par mégarde.
  static const double _lockThreshold = 56;

  Offset? _startPos;
  bool _willCancel = false;
  bool _locked = false;

  void _onPointerDown(PointerDownEvent e) {
    _startPos = e.position;
    _willCancel = false;
    _locked = false;
    widget.onMicStart();
  }

  void _onPointerMove(PointerMoveEvent e) {
    final start = _startPos;
    if (start == null || _locked) return;

    final dx = (e.position.dx - start.dx).clamp(-200.0, 0.0);
    final dy = (e.position.dy - start.dy).clamp(-200.0, 0.0);

    // Le geste dominant l'emporte : sans cet arbitrage, un glissement en
    // diagonale déclencherait les deux, et on ne saurait jamais si le
    // message part ou disparaît.
    if (-dy > _lockThreshold && -dy > -dx) {
      _locked = true;
      _startPos = null;
      widget.onMicLock();
      return;
    }

    final willCancel = dx < -_cancelThreshold && -dx > -dy;
    _willCancel = willCancel;
    widget.onDragUpdate(dx, dy, willCancel);
  }

  void _onPointerUp(PointerUpEvent e) => _release();

  void _onPointerCancel(PointerCancelEvent e) {
    if (_locked) return;
    widget.onMicCancel();
    _startPos = null;
    _willCancel = false;
  }

  void _release() {
    // Verrouillé : lever le doigt ne doit RIEN faire, c'est tout
    // l'intérêt du mode mains libres.
    if (_locked) return;
    if (_startPos == null) return;
    if (_willCancel) {
      widget.onMicCancel();
    } else {
      widget.onMicStop();
    }
    _startPos = null;
    _willCancel = false;
  }

  @override
  Widget build(BuildContext context) {
    final recording = widget.recording;
    // Progression du geste de verrouillage, 0..1 — pilote la remontée et
    // l'opacité du cadenas.
    final lockProgress = recording
        ? (-widget.dragY / _lockThreshold).clamp(0.0, 1.0)
        : 0.0;

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: SizedBox(
        width: 44,
        height: 44,
        // `clipBehavior: none` : le cadenas est dessiné AU-DESSUS du
        // bouton, donc hors de ses limites.
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (recording)
              Positioned(
                // ⚠️ LA CAPSULE DESCEND VERS LE BOUTON À MESURE QU'ON
                // MONTE.
                //
                // C'est contre-intuitif écrit comme ça, et c'est
                // pourtant exactement ce que fait WhatsApp : le doigt
                // monte, le cadenas VIENT À SA RENCONTRE. Les deux se
                // rejoignent au moment du verrouillage. L'ancienne
                // version faisait l'inverse — la capsule s'éloignait du
                // doigt (`46 + lockProgress * 18`), si bien qu'on
                // poursuivait une cible qui fuyait.
                bottom: 64 - lockProgress * 16,
                child: Opacity(
                  opacity: (0.35 + lockProgress * 0.65).clamp(0.0, 1.0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      // La capsule prend la couleur d'accent au moment où
                      // le seuil est franchi : le fond change en même
                      // temps que l'anse se ferme, pour que le seuil soit
                      // lisible même du coin de l'œil.
                      color: lockProgress >= 1
                          ? OuroColors.accent.withValues(alpha: 0.18)
                          : OuroColors.tertiarySystemBackground,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // L'ANSE SUIT LE DOIGT. Voir `ouro_padlock.dart`
                        // pour pourquoi ce n'est pas deux icônes.
                        OuroPadlock(
                          fermeture: lockProgress,
                          taille: 16,
                          couleur: lockProgress >= 1
                              ? OuroColors.accent
                              : OuroColors.secondaryLabel,
                        ),
                        const SizedBox(height: 2),
                        // Le chevron respire vers le haut tant qu'on n'a
                        // pas verrouillé, et s'efface une fois le seuil
                        // atteint : il n'a plus rien à demander.
                        // ⚠️ Son propre `AnimatedBuilder` : la pulsation
                        // n'appartient pas à cette partie de l'arbre, et
                        // sans abonnement explicite le chevron resterait
                        // figé à la valeur qu'avait la pulsation lors du
                        // dernier mouvement du doigt.
                        AnimatedBuilder(
                          animation: widget.pulse,
                          builder: (context, enfant) => Opacity(
                            opacity: 1 - lockProgress,
                            child: Transform.translate(
                              offset: Offset(0, -2 * widget.pulse.value),
                              child: enfant,
                            ),
                          ),
                          child: Icon(
                            Icons.keyboard_arrow_up_rounded,
                            size: 13,
                            color: OuroColors.tertiaryLabel,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            AnimatedBuilder(
              animation: widget.pulse,
              builder: (context, _) {
                final scale = recording ? 1.0 + widget.pulse.value * 0.14 : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: Container(
                    width: _BoutonRond.taille,
                    height: _BoutonRond.taille,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      // ⚠️ PLEIN, PLUS TRANSPARENT.
                      //
                      // Le micro n'était qu'une icône bleue posée sur la
                      // barre. Sur les captures de WhatsApp, c'est un
                      // DISQUE de couleur de marque — le seul élément vif
                      // de la rangée, et donc le seul point d'arrivée du
                      // regard. Une icône nue se confondait avec le
                      // trombone et le sticker, qui ne sont pourtant que
                      // des accessoires.
                      color: recording
                          ? OuroColors.systemRed
                          : OuroColors.accent,
                      boxShadow: recording
                          ? [
                              BoxShadow(
                                color: OuroColors.systemRed.withValues(
                                  alpha: 0.4 * widget.pulse.value,
                                ),
                                blurRadius: 16,
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: const Icon(
                      Icons.mic_rounded,
                      color: Colors.white,
                      size: 23,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Le bouton rond bleu qui envoie l'enregistrement mains libres.
class _SendCircle extends StatelessWidget {
  const _SendCircle({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: OuroColors.accent,
        ),
        child: const Icon(
          Icons.arrow_upward_rounded,
          color: Colors.white,
          size: 22,
        ),
      ),
    );
  }
}

/// Le bouton d'envoi (flèche/avion en papier) — un tap simple envoie
/// normalement, avec une petite onde qui éclate ; un appui long ouvre le
/// menu d'effets spéciaux ([_EffectPicker]) façon Telegram.
class _AnimatedSendButton extends StatefulWidget {
  const _AnimatedSendButton({
    required this.active,
    required this.onSend,
  });
  final bool active;
  final void Function([String? effect]) onSend;

  @override
  State<_AnimatedSendButton> createState() => _AnimatedSendButtonState();
}

class _AnimatedSendButtonState extends State<_AnimatedSendButton> {
  bool _pressed = false;

  void _handleTap([String? effect]) {
    if (!widget.active) return;
    OuroHaptics.light();
    widget.onSend(effect);
  }

  Future<void> _openEffectPicker() async {
    if (!widget.active) return;
    HapticFeedback.selectionClick();
    FocusScope.of(context).unfocus();
    final effect = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _EffectPicker(),
    );
    if (effect != null) _handleTap(effect);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: _openEffectPicker,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Center(
          child: LiquidSendButton(
            enabled: widget.active,
            onPressed: _handleTap,
            size: 22,
            color: OuroColors.accent,
          ),
        ),
      ),
    );
  }
}

/// Feuille de sélection d'un effet de message (appui long sur le bouton
/// d'envoi), façon Telegram — effets de bulle (rejoués une fois sur le
/// message lui-même) et effets plein écran (overlay chez l'expéditeur ET le
/// destinataire), voir `message_effects.dart`.
class _EffectPicker extends StatelessWidget {
  const _EffectPicker();

  static const _bubbleOptions = [
    (kEffectSlam, Icons.bolt_rounded, 'Boom'),
    (kEffectLoud, Icons.campaign_rounded, 'Fort'),
    (kEffectGentle, Icons.spa_rounded, 'Douceur'),
    (kEffectInvisibleInk, Icons.visibility_off_rounded, 'Encre invisible'),
  ];

  static const _fullscreenOptions = [
    (kEffectConfetti, Icons.celebration_rounded, 'Confettis'),
    (kEffectFireworks, Icons.auto_awesome_rounded, 'Feu d\'artifice'),
    (kEffectHearts, Icons.favorite_rounded, 'Cœurs'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: FrostedSheet(
        child: SafeArea(
          top: false,
          // Filet de sécurité sur petit écran / grande police système : le
          // contenu défile plutôt que de déborder silencieusement (un
          // `Column` figé ici avait déjà causé une feuille vide invisible
          // quand l'espace disponible se réduisait sous le clavier).
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Effet de message',
                  style: TextStyle(
                    color: OuroColors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Se joue une fois, chez toi et chez ton correspondant',
                  style: TextStyle(
                    color: OuroColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Sur la bulle',
                  style: TextStyle(
                    color: OuroColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _bubbleOptions
                      .map(
                        (o) => _EffectChip(
                          icon: o.$2,
                          label: o.$3,
                          onTap: () => Navigator.of(context).pop(o.$1),
                        ),
                      )
                      .toList(),
                ),
                const SizedBox(height: 18),
                Text(
                  'Plein écran',
                  style: TextStyle(
                    color: OuroColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _fullscreenOptions
                      .map(
                        (o) => _EffectChip(
                          icon: o.$2,
                          label: o.$3,
                          onTap: () => Navigator.of(context).pop(o.$1),
                        ),
                      )
                      .toList(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Une seule option cliquable dans le menu d'effets (icône + nom, comme
/// « ⚡ Boom » ou « 🎉 Confettis »).
class _EffectChip extends StatelessWidget {
  const _EffectChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: OuroCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        borderRadius: DesignTokens.radiusFull,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: OuroColors.meshBlueBright),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: OuroColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Effet de bulle « Encre invisible » (iMessage) : le contenu est masqué par
/// une surface bruitée jusqu'à ce qu'on tape dessus pour la révéler. Reste
/// révélé ensuite pour la durée de vie de la bulle (pas de re-masquage
/// automatique) — suffisant pour l'effet de surprise recherché.
class _InvisibleInkReveal extends StatefulWidget {
  const _InvisibleInkReveal({required this.child});
  final Widget child;

  @override
  State<_InvisibleInkReveal> createState() => _InvisibleInkRevealState();
}

class _InvisibleInkRevealState extends State<_InvisibleInkReveal> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _revealed
          ? null
          : () {
              HapticFeedback.mediumImpact();
              setState(() => _revealed = true);
            },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Opacity(opacity: _revealed ? 1 : 0, child: widget.child),
          if (!_revealed)
            AnimatedOpacity(
              opacity: _revealed ? 0 : 1,
              duration: DesignTokens.durationNormal,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: CustomPaint(
                  painter: _NoisePainter(),
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Text(
                      'Toucher pour révéler',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Dessine le petit fond « grésillement » (comme un vieux poste de
/// télé mal réglé) qui recouvre un message « encre invisible » avant
/// qu'on ne tape dessus pour le révéler.
class _NoisePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rnd = math.Random(42);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = OuroColors.textTertiary.withValues(alpha: 0.9),
    );
    final dot = Paint()..color = Colors.white.withValues(alpha: 0.25);
    for (int i = 0; i < 140; i++) {
      canvas.drawCircle(
        Offset(rnd.nextDouble() * size.width, rnd.nextDouble() * size.height),
        1.2,
        dot,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _NoisePainter oldDelegate) => false;
}

/// La bulle qui répond sous le doigt.
///
/// ⚠️ C'EST LE MANQUE LE PLUS COÛTEUX DE TOUT L'ÉCRAN, et le moins
/// visible à la lecture du code.
///
/// La bulle n'avait que `onLongPress` et `onDoubleTap`. Entre le moment
/// où le doigt se pose et celui où le menu s'ouvre — environ une
/// demi-seconde — il ne se passait STRICTEMENT RIEN. L'utilisateur
/// touche, l'écran reste figé, et il ne sait pas si son geste a été
/// pris. C'est ce silence-là qu'on ressent comme de la lenteur, bien
/// plus que la durée réelle d'une animation.
///
/// Telegram et iMessage répondent à l'instant du contact : la bulle
/// s'enfonce légèrement, et revient. Le geste est acquitté avant même
/// d'être terminé.
///
/// Le retour utilise un RESSORT et non une durée fixe. La différence
/// compte ici : un ressort repart de la valeur courante avec sa vitesse
/// courante. Relâcher pendant que la bulle s'enfonce la fait remonter
/// depuis où elle en est, sans à-coup — là où une courbe à durée fixe
/// redémarrerait du début et produirait un ressaut.
class _BullePressable extends StatefulWidget {
  const _BullePressable({
    required this.child,
    required this.onLongPress,
    this.onDoubleTap,
  });

  final Widget child;
  final VoidCallback onLongPress;
  final VoidCallback? onDoubleTap;

  @override
  State<_BullePressable> createState() => _BullePressableState();
}

class _BullePressableState extends State<_BullePressable> {
  bool _presse = false;

  void _set(bool v) {
    if (_presse != v && mounted) setState(() => _presse = v);
  }

  @override
  Widget build(BuildContext context) {
    return LiquidLongPressOverlay(
      onLongPress: widget.onLongPress,
      onDoubleTap: widget.onDoubleTap,
      child: GestureDetector(
        onLongPress: () {
          _set(false);
          widget.onLongPress();
        },
        onDoubleTap: widget.onDoubleTap,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onLongPressCancel: () => _set(false),
        onLongPressEnd: (_) => _set(false),
        child: _presse
            ? SingleMotionBuilder(
                motion: CupertinoMotion.snappy(),
                value: 0.965,
                from: 1.0,
                builder: (context, echelle, _) => Transform.scale(
                  scale: echelle,
                  alignment: Alignment.bottomCenter,
                  child: widget.child,
                ),
              )
            : widget.child,
      ),
    );
  }
}

/// Une petite zone touchable, annoncée correctement au lecteur d'écran.
///
/// ⚠️ La cible est ÉLARGIE au-delà de l'heure elle-même. Un texte de onze
/// points fait une hauteur de cible d'environ quinze : très en dessous
/// des quarante-quatre points recommandés. Sans cet élargissement, le
/// geste serait théoriquement disponible et pratiquement introuvable.
class _TapCible extends StatelessWidget {
  const _TapCible({
    required this.child,
    required this.onTap,
    required this.semantique,
    this.marge = const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
  });

  final Widget child;
  final VoidCallback onTap;
  final String semantique;

  /// La marge qui élargit la cible.
  ///
  /// ⚠️ ELLE DOIT ÊTRE NULLE DANS UNE BARRE DE TITRE. La hauteur d'une
  /// `AppBar` est fixe (56 points) ; les douze points ajoutés par la
  /// marge par défaut suffisaient à faire déborder la colonne
  /// nom + statut, qui venait alors se superposer à l'avatar et au
  /// bouton retour. Là où la rangée est déjà haute, la cible est de
  /// toute façon assez grande sans marge.
  final EdgeInsets marge;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semantique,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(padding: marge, child: child),
      ),
    );
  }
}

/// Le geste « glisser pour répondre », façon Telegram.
///
/// Voir la note détaillée sur `_dismissibleEntry` pour le pourquoi. Ici,
/// le comment.
class _GlisserPourRepondre extends StatefulWidget {
  const _GlisserPourRepondre({required this.child, required this.onRepondre});

  final Widget child;
  final VoidCallback onRepondre;

  @override
  State<_GlisserPourRepondre> createState() => _GlisserPourRepondreState();
}

class _GlisserPourRepondreState extends State<_GlisserPourRepondre> {
  /// Le déplacement courant de la bulle, en points.
  double _dx = 0;

  /// Vrai une fois le seuil franchi — sert à ne vibrer QU'UNE fois.
  bool _arme = false;

  /// La distance à parcourir pour déclencher la réponse.
  ///
  /// 56 points : assez pour qu'un défilement horizontal accidentel ne
  /// l'atteigne pas, assez peu pour rester un geste du pouce et non un
  /// mouvement du bras.
  static const double _seuil = 56;

  void _maj(DragUpdateDetails d) {
    var x = _dx + d.delta.dx;
    if (x < 0) x = 0; // jamais vers la gauche
    // Au-delà du seuil, la bulle résiste : le doigt avance trois fois
    // plus vite qu'elle.
    if (x > _seuil) x = _seuil + (x - _seuil) / 3;

    final atteint = x >= _seuil;
    if (atteint && !_arme) {
      _arme = true;
      OuroHaptics.light();
    } else if (!atteint && _arme) {
      _arme = false;
    }
    setState(() => _dx = x);
  }

  void _fin() {
    if (_arme) widget.onRepondre();
    _arme = false;
    setState(() => _dx = 0);
  }

  @override
  Widget build(BuildContext context) {
    // L'opacité de la flèche suit le geste : elle apparaît en même temps
    // qu'on tire, ce qui rend le geste découvrable sans l'expliquer.
    final avance = (_dx / _seuil).clamp(0.0, 1.0);

    return GestureDetector(
      // `horizontal` seulement : le défilement vertical de la
      // conversation doit continuer de passer.
      onHorizontalDragUpdate: _maj,
      onHorizontalDragEnd: (_) => _fin(),
      onHorizontalDragCancel: _fin,
      child: Stack(
        // ⚠️ `passthrough` EST INDISPENSABLE ICI, et son absence a mis
        // TOUS les messages à gauche — y compris les miens.
        //
        // Par défaut, un `Stack` donne à ses enfants non positionnés des
        // contraintes LÂCHES : la bulle se rétrécit alors à la largeur de
        // son texte, au lieu de recevoir toute la largeur de la
        // conversation. Or c'est précisément cette largeur pleine qui
        // permet au `crossAxisAlignment: end` de la colonne de pousser la
        // bulle vers la droite. Sans elle, il n'y a plus d'espace à
        // droite, et l'alignement n'a plus de sens : tout se tasse à
        // gauche, au coin haut-gauche imposé par le `Stack`.
        //
        // Le `Dismissible` qui occupait cette place auparavant
        // transmettait des contraintes serrées — d'où un défaut apparu
        // exactement au moment où on l'a remplacé.
        fit: StackFit.passthrough,
        children: [
          // La flèche, révélée derrière la bulle qui s'écarte.
          //
          // ⚠️ Elle n'est CONSTRUITE que pendant le geste. Auparavant
          // elle existait en permanence, à opacité nulle — et un
          // `Opacity` force un rendu hors-écran même quand il ne montre
          // rien. Sur cinquante messages, cela faisait cinquante couches
          // hors-écran par image pour dessiner cinquante flèches
          // invisibles.
          if (_dx > 0)
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 10),
                child: Opacity(
                  opacity: avance,
                  child: Transform.scale(
                    // Elle grandit jusqu'à sa taille pleine au seuil :
                    // le geste a un aboutissement visible.
                    scale: 0.6 + 0.4 * avance,
                    child: Icon(
                      Icons.reply_rounded,
                      size: 20,
                      color: OuroColors.accent,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // La bulle suit le doigt, et revient par un ressort.
          //
          // Même règle que pour l'état pressé : tant qu'on n'a rien
          // tiré, pas de contrôleur du tout. Voir la note dans
          // `_BullePressableState`.
          if (_dx == 0)
            widget.child
          else
            SingleMotionBuilder(
              motion: CupertinoMotion.snappy(),
              value: _dx,
              builder: (context, x, _) => Transform.translate(
                offset: Offset(x, 0),
                child: widget.child,
              ),
            ),
        ],
      ),
    );
  }
}

/// La forme d'une bulle façon WhatsApp : un rectangle arrondi, plus une
/// petite pointe triangulaire du côté de son auteur.
///
/// ⚠️ POURQUOI UNE FORME SUR MESURE PLUTÔT QU'UN COIN MOINS ARRONDI.
///
/// La version précédente marquait le locuteur en réduisant un seul
/// rayon : 22 partout, 8 sur le coin du bas. C'est le procédé
/// d'iMessage, et il fonctionne — mais il ne se voit qu'à condition de
/// comparer deux bulles côte à côte. WhatsApp, lui, fait DÉBORDER une
/// pointe hors du rectangle : la bulle désigne physiquement celui qui
/// parle, même isolée au milieu d'un écran.
///
/// C'est le marqueur le plus reconnaissable de leur conversation, et
/// c'est purement géométrique — il n'emporte aucune de leurs couleurs.
///
/// La pointe n'apparaît que sur la DERNIÈRE bulle d'une série : une
/// pile de bulles toutes pointues ressemble à une scie.

// ─────────────────────────────────────────────────────────────
//  TEXTE DÉROULABLE (WhatsApp-style)
// ─────────────────────────────────────────────────────────────

/// Seuil au-delà duquel un message est tronqué avec un bouton
/// « Voir plus ». 100 caractères correspond à environ 4 lignes
/// sur un écran de téléphone — assez pour le contexte, pas
/// assez pour devoir scroller.
const int _kExpandThreshold = 100;

/// Texte qui se déroule progressivement : tronqué à 100 caractères
/// avec un bouton « Voir plus », puis déroulé progressivement
/// (+100 caractères à chaque tap) jusqu'au texte complet, avec un
/// bouton « Replier » une fois entièrement étendu.
///
/// Reproduit exactement le comportement de WhatsApp pour les
/// messages longs.
class _ExpandableText extends StatefulWidget {
  const _ExpandableText({
    required this.text,
    required this.style,
  });

  final String text;
  final TextStyle style;

  @override
  State<_ExpandableText> createState() => _ExpandableTextState();
}

class _ExpandableTextState extends State<_ExpandableText>
    with SingleTickerProviderStateMixin {
  /// Nombre de caractères actuellement visibles.
  late int _maxLength;

  /// Le texte est-il entièrement déplié ?
  bool get _isExpanded => _maxLength >= widget.text.length;

  /// Le texte est-il long enough pour être tronqué ?
  bool get _isTruncatable => widget.text.length > _kExpandThreshold;

  @override
  void initState() {
    super.initState();
    _maxLength = _isTruncatable ? _kExpandThreshold : widget.text.length;
  }

  @override
  void didUpdateWidget(covariant _ExpandableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      _maxLength =
          _isTruncatable ? _kExpandThreshold : widget.text.length;
    }
  }

  void _toggleExpand() {
    setState(() {
      if (_isExpanded) {
        // Replier : revenir au seuil initial.
        _maxLength = _kExpandThreshold;
      } else {
        // Dérouler de 100 caractères de plus, ou tout afficher si proche.
        final next = _maxLength + _kExpandThreshold;
        _maxLength = next >= widget.text.length ? widget.text.length : next;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_isTruncatable) {
      // Message court : texte simple, pas de bouton.
      return Text(widget.text, style: widget.style);
    }

    final displayText = _isExpanded
        ? widget.text
        : '${widget.text.substring(0, _maxLength)}…';

    // Déterminer les couleurs des boutons depuis le style du texte.
    final isWhite = widget.style.color == Colors.white ||
        widget.style.color == Colors.white70;
    final buttonColor =
        isWhite ? Colors.white.withValues(alpha: 0.7) : OuroColors.accent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(displayText, style: widget.style),
        GestureDetector(
          onTap: _toggleExpand,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              _isExpanded
                  ? 'Replier'
                  : _maxLength >= widget.text.length
                      ? 'Replier'
                      : 'Voir plus',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: buttonColor,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FormeBulle extends ShapeBorder {
  const _FormeBulle({
    required this.rayon,
    required this.rayonQueue,
    required this.mine,
    required this.pointe,
  });

  final double rayon;

  /// Le rayon du coin bas, du côté de l'auteur.
  ///
  /// Plus petit que [rayon] sur la dernière bulle d'une série : c'est le
  /// marqueur de locuteur d'iMessage, discret et sans emprunt.
  final double rayonQueue;

  /// Le côté de l'auteur : droite pour mes messages.
  final bool mine;

  /// Ajoute une pointe triangulaire débordante, façon WhatsApp.
  ///
  /// Désactivée aujourd'hui — voir la note à l'appel. Le code reste en
  /// place : la remettre ne coûte qu'un booléen.
  final bool pointe;

  static const double _largeur = 7;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final corps = pointe
        ? Rect.fromLTRB(
            rect.left + (mine ? 0 : _largeur),
            rect.top,
            rect.right - (mine ? _largeur : 0),
            rect.bottom,
          )
        : rect;

    final chemin = Path()
      ..addRRect(RRect.fromRectAndCorners(
        corps,
        topLeft: Radius.circular(rayon),
        topRight: Radius.circular(rayon),
        bottomLeft: Radius.circular(mine ? rayon : rayonQueue),
        bottomRight: Radius.circular(mine ? rayonQueue : rayon),
      ));

    if (!pointe) return chemin;

    final baseY = rect.bottom - rayon * 0.55;
    final pointeY = rect.bottom;
    if (mine) {
      chemin
        ..moveTo(corps.right - 0.5, baseY)
        ..quadraticBezierTo(corps.right, pointeY, rect.right, pointeY)
        ..lineTo(corps.right - 1, pointeY)
        ..close();
    } else {
      chemin
        ..moveTo(corps.left + 0.5, baseY)
        ..quadraticBezierTo(corps.left, pointeY, rect.left, pointeY)
        ..lineTo(corps.left + 1, pointeY)
        ..close();
    }
    return chemin;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => _FormeBulle(
        rayon: rayon * t,
        rayonQueue: rayonQueue * t,
        mine: mine,
        pointe: pointe,
      );

  @override
  bool operator ==(Object other) =>
      other is _FormeBulle &&
      other.rayon == rayon &&
      other.rayonQueue == rayonQueue &&
      other.mine == mine &&
      other.pointe == pointe;

  @override
  int get hashCode => Object.hash(rayon, rayonQueue, mine, pointe);
}

/// Une icône discrète logée DANS la pilule de saisie.
///
/// Taille de cible portée à 40 points malgré une icône de 22 : dans une
/// barre où l'on vise vite et souvent, une cible à la taille exacte du
/// dessin se rate une fois sur trois.
class _IconePilule extends StatelessWidget {
  const _IconePilule({
    required this.icone,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icone;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tooltip,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          OuroHaptics.light();
          onTap();
        },
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icone,
            // Gris et non bleu : ce sont des accessoires. Le bleu est
            // réservé au bouton rond, qui porte l'action principale.
            color: OuroColors.secondaryLabel,
            size: 22,
          ),
        ),
      ),
    );
  }
}

/// Le disque plein qui porte l'action principale de la barre de saisie.
///
/// iMessage : 30pt circle, background #007AFF, icon arrow-up, 15pt.
/// Pressed: scale 0.92 + slight darken.
class _BoutonRond extends StatelessWidget {
  const _BoutonRond({super.key, required this.child});

  final Widget child;

  /// iMessage : 30pt circle for the send button.
  static const double taille = 30;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: OuroColors.accent,
      ),
      alignment: Alignment.center,
      child: child,
    );
  }
}

/// Feuille modale affichant les messages d'un fil de discussion.
class _ThreadSheet extends StatefulWidget {
  const _ThreadSheet({
    required this.parent,
    required this.threadId,
    required this.messages,
    required this.onReply,
  });

  final MeshMessage parent;
  final String threadId;
  final List<MeshMessage> messages;
  final ValueChanged<String> onReply;

  @override
  State<_ThreadSheet> createState() => _ThreadSheetState();
}

class _ThreadSheetState extends State<_ThreadSheet> {
  final _ctrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _ctrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _send() {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    widget.onReply(text);
    _ctrl.clear();
    HapticFeedback.lightImpact();
    // Scroll vers le bas après un court délai pour laisser le temps
    // au message d'apparaître.
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      builder: (ctx, scrollCtrl) => Container(
        decoration: BoxDecoration(
          color: OuroColors.systemGroupedBackground,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            // Handle
            Container(
              margin: const EdgeInsets.only(top: 8),
              width: 36,
              height: 5,
              decoration: BoxDecoration(
                color: OuroColors.separator,
                borderRadius: BorderRadius.circular(2.5),
              ),
            ),
            // Titre
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Fil de discussion',
                style: OuroTypography.headline.copyWith(
                  color: OuroColors.label,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
            // Messages du fil
            Expanded(
              child: ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: widget.messages.length,
                itemBuilder: (ctx, i) {
                  final m = widget.messages[i];
                  final isParent = m.id == widget.parent.id;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isParent
                          ? OuroColors.accent.withValues(alpha: 0.08)
                          : OuroColors.secondarySystemGroupedBackground,
                      borderRadius: BorderRadius.circular(12),
                      border: isParent
                          ? Border.all(
                              color: OuroColors.accent.withValues(alpha: 0.3),
                              width: 1,
                            )
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              m.authorPseudo,
                              style: OuroTypography.caption1.copyWith(
                                color: OuroColors.accent,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _formatTime(m.timestamp),
                              style: OuroTypography.caption2.copyWith(
                                color: OuroColors.tertiaryLabel,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          m.content,
                          style: OuroTypography.subheadline.copyWith(
                            color: OuroColors.label,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            // Champ de réponse
            Container(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                MediaQuery.of(context).padding.bottom + 8,
              ),
              decoration: BoxDecoration(
                color: OuroColors.systemGroupedBackground,
                border: Border(
                  top: BorderSide(
                    color: OuroColors.separator,
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _ctrl,
                      style: OuroTypography.body.copyWith(
                        color: OuroColors.label,
                      ),
                      cursorColor: OuroColors.accent,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Réponse…',
                        hintStyle: OuroTypography.body.copyWith(
                          color: OuroColors.tertiaryLabel,
                        ),
                        filled: true,
                        fillColor: OuroColors.tertiarySystemFill,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide.none,
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: OuroColors.accent,
                      ),
                      child: const Icon(
                        Icons.send_rounded,
                        color: Colors.white,
                        size: 17,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime t) {
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }
}

/// Le micro qu'on jette : ce qui vole vers la corbeille quand on
/// abandonne un enregistrement en cours.
///
/// ── Pourquoi un micro et pas la barre entière ─────────────────────────
///
/// La barre d'enregistrement fait toute la largeur de l'écran. Réduite à
/// un dixième de sa taille pendant le vol, elle ne serait plus qu'un
/// trait illisible. Ce qu'on jette, dans la tête de l'utilisateur, ce
/// n'est pas une barre : c'est SA VOIX. Le micro est le seul dessin qui
/// dise ça en douze pixels.
class _MicJete extends StatelessWidget {
  const _MicJete();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: OuroColors.systemRed,
        boxShadow: DesignTokens.cardShadow,
      ),
      child: const Icon(Icons.mic_rounded, color: Colors.white, size: 24),
    );
  }
}
