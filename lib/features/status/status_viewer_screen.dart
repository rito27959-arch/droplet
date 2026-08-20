// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'écran plein écran pour REGARDER les statuts de quelqu'un — comme les
// Stories d'Instagram ou les Statuts de WhatsApp : une barre de
// progression par statut en haut, avance automatique, tap à gauche pour
// revenir, tap à droite pour passer, glissement vers le bas pour fermer.
//
// Il affiche maintenant tout ce qu'un statut peut porter : du texte sur
// fond coloré, une photo, une vidéo, un message vocal, et la chanson qui
// l'accompagne éventuellement.
//
// ── Trois choses qui ne vont pas de soi ────────────────────────────────
//
// 1. LA DURÉE D'AFFICHAGE N'EST PAS FIXE. Cinq secondes pour du texte ou
//    une photo, mais la durée réelle pour une vidéo ou un vocal : couper
//    quelqu'un au milieu d'une phrase serait absurde.
//
// 2. LE MÉDIA PEUT NE PAS ÊTRE ENCORE ARRIVÉ. L'annonce d'un statut pèse
//    quelques centaines d'octets, une photo des centaines de milliers :
//    sur un réseau Bluetooth, la première arrive largement avant la
//    seconde. L'écran affiche donc un cadre en attente, et se remplit
//    dès que le fichier est là — la barre de progression, elle, reste en
//    pause tant qu'il n'y a rien à voir.
//
// 3. LES « J'AIME » ET COMMENTAIRES NE PARTENT QU'À L'AUTEUR. Sur un
//    maillage, un compteur public supposerait que tous les téléphones
//    tombent d'accord sur un même nombre, ce qui est impossible à
//    garantir quand chacun ne voit qu'une poignée de voisins. Une seule
//    personne tient donc le compte : celle que ça intéresse. C'est aussi
//    exactement ce que fait WhatsApp.
// ============================================================================

import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../core/models/mesh_message.dart';
import '../../core/models/status_media.dart';
import '../../core/models/voice_note_meta.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_spinner.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_typography.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../shared/widgets/story_progress_bar.dart';
import '../chat/voice_note.dart';
import '../../shared/widgets/scene_animee.dart';

class StatusViewerScreen extends ConsumerStatefulWidget {
  const StatusViewerScreen({super.key, required this.authorId});
  final String authorId;

  @override
  ConsumerState<StatusViewerScreen> createState() => _StatusViewerScreenState();
}

class _StatusViewerScreenState extends ConsumerState<StatusViewerScreen>
    with SingleTickerProviderStateMixin {
  /// Durée d'affichage d'un statut sans média — celle de toutes les
  /// applications de stories, et elle n'a pas été choisie au hasard :
  /// c'est à peu près le temps de lire une phrase courte.
  static const _textDuration = Duration(seconds: 5);
  static const _photoDuration = Duration(seconds: 6);

  late final List<MeshStatusRecord> _statuses;
  late final AnimationController _progress;
  int _index = 0;

  final Set<String> _seenSentFor = {};
  StreamSubscription<String>? _statusSeenSub;
  StreamSubscription<String>? _mediaSub;
  StreamSubscription<StatusFeedback>? _feedbackSub;
  int _revision = 0;

  /// Le lecteur du média principal (vocal) et celui de la musique
  /// d'accompagnement — deux lecteurs distincts, puisqu'ils peuvent
  /// jouer en même temps.
  AudioPlayer? _voicePlayer;
  AudioPlayer? _musicPlayer;
  VideoPlayerController? _video;

  StreamSubscription<Duration>? _voicePosSub;
  Duration? _voiceTotal;
  double _voiceProgress = 0;

  /// Vrai quand la progression est suspendue : le doigt est maintenu
  /// appuyé, une feuille est ouverte, ou le média n'est pas encore
  /// arrivé.
  bool _held = false;

  /// Le chemin local du média affiché, résolu UNE fois à la préparation.
  ///
  /// Il était auparavant redemandé depuis `build` via un `FutureBuilder`,
  /// donc relancé à chaque redessin — c'est-à-dire soixante fois par
  /// seconde pendant que la barre de progression avance. L'image
  /// clignotait à chaque nouvelle résolution, et le disque était
  /// interrogé pour rien.
  String? _mediaPath;

  /// Numéro de la préparation en cours.
  ///
  /// Enchaîner les taps lance plusieurs préparations à la fois, et
  /// chacune comporte des `await`. Sans ce compteur, une préparation
  /// ancienne pouvait reprendre la main APRÈS une plus récente et
  /// installer sa vidéo par-dessus : on se retrouvait avec le son d'un
  /// statut et l'image d'un autre.
  int _generation = 0;

  bool _liking = false;

  @override
  void initState() {
    super.initState();
    _statuses = StorageService.getActiveStatuses()
        .where((s) => s.authorId == widget.authorId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    _progress = AnimationController(vsync: this, duration: _textDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _advance();
      });

    final repo = ref.read(meshRepositoryProvider);

    _statusSeenSub = repo.statusSeenEvents.listen((statusId) {
      if (!mounted) return;
      if (_statuses.any((s) => s.id == statusId)) setState(() => _revision++);
    });
    _feedbackSub = repo.statusFeedbackEvents.listen((f) {
      if (!mounted) return;
      if (_statuses.any((s) => s.id == f.statusId)) setState(() => _revision++);
    });
    // Le média du statut affiché vient peut-être d'arriver : on relance
    // alors sa préparation, sans quoi l'écran resterait sur son cadre
    // d'attente jusqu'au statut suivant.
    _mediaSub = repo.statusMediaEvents.listen((fileId) {
      if (!mounted || _statuses.isEmpty) return;
      final media = StorageService.getStatusMedia(_statuses[_index].id);
      if (media.fileId == fileId || media.musicFileId == fileId) {
        _prepareCurrent();
      }
    });

    if (_statuses.isNotEmpty) {
      _prepareCurrent();
      _markSeenIfNeeded();
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _statusSeenSub?.cancel();
    _mediaSub?.cancel();
    _feedbackSub?.cancel();
    _teardownPlayers();
    super.dispose();
  }

  void _teardownPlayers() {
    _voicePosSub?.cancel();
    _voicePosSub = null;
    _voicePlayer?.dispose();
    _voicePlayer = null;
    _musicPlayer?.dispose();
    _musicPlayer = null;
    _video?.dispose();
    _video = null;
  }

  // ─────────────────────────────────────────────────────────────
  //  PRÉPARATION D'UN STATUT
  // ─────────────────────────────────────────────────────────────

  MeshStatusRecord get _current => _statuses[_index];
  StatusMedia get _media => StorageService.getStatusMedia(_current.id);

  /// Chemin local du fichier, ou `null` s'il n'est pas encore arrivé.
  Future<String?> _pathOf(String? fileId, String? fileName) {
    if (fileId == null || fileName == null) return Future.value(null);
    return StorageService.getSharedFilePath(fileId, fileName);
  }

  /// Met en place tout ce qu'il faut pour le statut courant : lecteurs,
  /// durée d'affichage, démarrage de la barre.
  Future<void> _prepareCurrent() async {
    final generation = ++_generation;
    _teardownPlayers();
    _voiceTotal = null;
    _voiceProgress = 0;
    _mediaPath = null;

    final status = _current;
    final media = StorageService.getStatusMedia(status.id);

    // La musique démarre en premier et tourne en boucle : elle
    // accompagne, elle ne rythme pas.
    if (media.hasMusic) {
      final path = await _pathOf(media.musicFileId, media.musicFileName);
      if (generation != _generation) return;
      if (path != null && mounted) {
        _musicPlayer = AudioPlayer();
        await _musicPlayer!.setReleaseMode(ReleaseMode.loop);
        await _musicPlayer!.setVolume(media.kind == StatusMediaKind.voice
            // Sous une voix, la musique doit rester très en retrait,
            // sinon on n'entend plus ce qui est dit.
            ? 0.18
            : 0.55);
        // ⚠️ Protégé : une musique de statut tronquée en cours de
        // transfert ferait autrement remonter une exception non
        // rattrapée jusqu'à la racine de l'application.
        unawaited(_musicPlayer!.play(DeviceFileSource(path)).catchError(
            (e) => debugPrint('[Statut] musique illisible: $e')));
      }
    }

    Duration segment = _textDuration;

    switch (media.kind) {
      case StatusMediaKind.none:
        segment = _textDuration;

      case StatusMediaKind.photo:
        final path = await _pathOf(media.fileId, media.fileName);
        if (generation != _generation) return;
        if (path == null) {
          _waitForMedia();
          return;
        }
        _mediaPath = path;
        segment = _photoDuration;

      case StatusMediaKind.video:
        final path = await _pathOf(media.fileId, media.fileName);
        if (generation != _generation) return;
        if (path == null) {
          _waitForMedia();
          return;
        }
        _mediaPath = path;
        final controller = VideoPlayerController.file(File(path));
        _video = controller;
        try {
          await controller.initialize();
          if (!mounted) return;
          // La préparation a été doublée pendant l'initialisation : ce
          // lecteur-ci n'a plus lieu d'être, et c'est le plus récent qui
          // a déjà pris sa place.
          if (generation != _generation) {
            await controller.dispose();
            return;
          }
          await controller.setLooping(false);
          // La vidéo porte son propre son : la musique s'efface devant.
          await _musicPlayer?.setVolume(0.12);
          unawaited(controller.play());
          segment = controller.value.duration;
        } catch (_) {
          segment = _photoDuration;
        }

      case StatusMediaKind.voice:
        final path = await _pathOf(media.fileId, media.fileName);
        if (generation != _generation) return;
        if (path == null) {
          _waitForMedia();
          return;
        }
        _mediaPath = path;
        final player = AudioPlayer();
        _voicePlayer = player;
        _voicePosSub = player.onPositionChanged.listen((pos) {
          final total = _voiceTotal;
          if (!mounted || total == null || total.inMilliseconds == 0) return;
          setState(() {
            _voiceProgress =
                (pos.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0);
          });
        });
        unawaited(player.play(DeviceFileSource(path)).catchError((e) {
          debugPrint('[Statut] vocal illisible: $e');
          // Le statut reste affiché, mais sans attendre une lecture qui
          // n'arrivera jamais : on laisse la barre repartir.
          if (mounted) _progress.forward();
        }));
        segment = media.durationMs != null
            ? Duration(milliseconds: media.durationMs!)
            : _textDuration;
        _voiceTotal = segment;
    }

    if (!mounted || generation != _generation) return;
    // Un garde-fou : une vidéo corrompue peut annoncer une durée nulle,
    // ce qui ferait défiler tous les statuts en un clin d'œil.
    if (segment.inMilliseconds < 800) segment = _textDuration;

    setState(() => _held = false);
    _progress
      ..duration = segment
      ..reset()
      ..forward();
  }

  /// Le fichier n'est pas encore arrivé : on suspend la progression et on
  /// attend le signal du dépôt (voir `statusMediaEvents`).
  void _waitForMedia() {
    if (!mounted) return;
    _progress.stop();
    setState(() => _held = true);
  }

  void _markSeenIfNeeded() {
    if (_statuses.isEmpty) return;
    final status = _current;
    final myId = ref.read(meshRepositoryProvider).myId;
    if (status.authorId == myId) return;
    if (!_seenSentFor.add(status.id)) return;
    unawaited(ref.read(meshRepositoryProvider).sendStatusSeen(
          authorId: status.authorId,
          statusId: status.id,
        ));
  }

  // ─────────────────────────────────────────────────────────────
  //  NAVIGATION
  // ─────────────────────────────────────────────────────────────

  void _advance() {
    if (_index >= _statuses.length - 1) {
      _close();
      return;
    }
    setState(() => _index++);
    _prepareCurrent();
    _markSeenIfNeeded();
  }

  void _rewind() {
    if (_index <= 0) {
      _prepareCurrent();
      return;
    }
    setState(() => _index--);
    _prepareCurrent();
    _markSeenIfNeeded();
  }

  /// Maintenir le doigt met tout en pause — le geste attendu de toutes
  /// les stories quand on veut prendre le temps de lire.
  void _hold(bool held) {
    if (_held == held) return;
    setState(() => _held = held);
    if (held) {
      _progress.stop();
      _video?.pause();
      _voicePlayer?.pause();
      _musicPlayer?.pause();
    } else {
      _progress.forward();
      _video?.play();
      _voicePlayer?.resume();
      _musicPlayer?.resume();
    }
  }

  void _close() {
    if (mounted) context.go('/chats');
  }

  /// Suspend l'écran le temps d'une feuille (spectateurs, commentaires),
  /// puis reprend là où on en était.
  Future<void> _pauseFor(Future<void> Function() action) async {
    _hold(true);
    await action();
    if (mounted) _hold(false);
  }

  // ─────────────────────────────────────────────────────────────
  //  RÉACTIONS
  // ─────────────────────────────────────────────────────────────

  bool get _iLiked {
    final myId = ref.read(meshRepositoryProvider).myId;
    return StorageService.getStatusFeedback(_current.id)
        .any((f) => f.isLike && f.authorId == myId);
  }

  Future<void> _toggleLike() async {
    if (_liking) return;
    setState(() => _liking = true);

    final repo = ref.read(meshRepositoryProvider);
    final status = _current;
    final liked = _iLiked;

    // On enregistre AUSSI chez soi, en plus d'envoyer à l'auteur : sans
    // cela, le cœur retomberait à sa position d'avant dès que l'écran se
    // redessine, puisque seul l'auteur conserve la trace du « j'aime ».
    if (liked) {
      await StorageService.removeStatusLike(status.id, repo.myId);
    } else {
      await StorageService.addStatusFeedback(StatusFeedback(
        statusId: status.id,
        authorId: repo.myId,
        authorPseudo: StorageService.currentUser?.pseudo ?? 'Moi',
        createdAt: DateTime.now(),
        emoji: '❤️',
      ));
      OuroHaptics.medium();
    }

    unawaited(repo.sendStatusFeedback(
      authorId: status.authorId,
      statusId: status.id,
      emoji: liked ? null : '❤️',
      remove: liked,
    ));

    if (mounted) setState(() => _liking = false);
  }

  Future<void> _sendComment(String text) async {
    if (text.trim().isEmpty) return;
    final repo = ref.read(meshRepositoryProvider);
    final status = _current;

    await StorageService.addStatusFeedback(StatusFeedback(
      statusId: status.id,
      authorId: repo.myId,
      authorPseudo: StorageService.currentUser?.pseudo ?? 'Moi',
      createdAt: DateTime.now(),
      text: text.trim(),
    ));
    unawaited(repo.sendStatusFeedback(
      authorId: status.authorId,
      statusId: status.id,
      text: text.trim(),
    ));

    if (!mounted) return;
    OuroHaptics.success();
    ref.read(toastProvider.notifier).show(
          'Réponse envoyée à ${status.authorPseudo}',
          type: DropletToastType.success,
        );
    setState(() => _revision++);
  }

  // ─────────────────────────────────────────────────────────────
  //  AFFICHAGE
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_statuses.isEmpty) {
      // Ce cas-ci n'est PAS la visionneuse : c'est un écran d'erreur
      // classique, il suit donc le mode clair/sombre comme le reste.
      return Scaffold(
        backgroundColor: OuroColors.systemBackground,
        body: EmptyState(
          emoji: Scenes.aucunStatut,
          icon: Icons.timer_off_rounded,
          title: 'Ce statut a expiré',
          action: TextButton(onPressed: _close, child: const Text('Fermer')),
        ),
      );
    }

    final status = _current;
    final media = _media;
    final mine = status.authorId == ref.watch(meshRepositoryProvider).myId;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: GestureDetector(
        onVerticalDragEnd: (d) {
          if ((d.primaryVelocity ?? 0) > 200) _close();
        },
        child: Scaffold(
          backgroundColor: media.backgroundColor != null
              ? Color(media.backgroundColor!)
              : OuroColors.callBackground,
          body: Stack(
            fit: StackFit.expand,
            children: [
              _canvas(status, media),

              // Zones de tap : tiers gauche = précédent, reste = suivant.
              // Le maintien met en pause, comme dans toutes les stories.
              Positioned.fill(
                top: 90,
                bottom: 110,
                child: Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _rewind,
                        onLongPressStart: (_) => _hold(true),
                        onLongPressEnd: (_) => _hold(false),
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _advance,
                        onLongPressStart: (_) => _hold(true),
                        onLongPressEnd: (_) => _hold(false),
                      ),
                    ),
                  ],
                ),
              ),

              SafeArea(child: _header(status, media)),

              SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: mine
                      ? _MyStatusFooter(
                          key: ValueKey('${status.id}-$_revision'),
                          status: status,
                          onTap: () => _pauseFor(() => _showFeedbackSheet(status)),
                        )
                      : _ReplyBar(
                          key: ValueKey('${status.id}-$_revision'),
                          liked: _iLiked,
                          onLike: _toggleLike,
                          onSend: _sendComment,
                          onFocus: _hold,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── La toile ─────────────────────────────────────────────────────

  Widget _canvas(MeshStatusRecord status, StatusMedia media) {
    final caption = status.content.trim();

    return switch (media.kind) {
      StatusMediaKind.none => _textCanvas(status),
      StatusMediaKind.photo => _fileCanvas(
          (path) => Center(
            child: Image.file(File(path), fit: BoxFit.contain),
          ),
          caption,
        ),
      StatusMediaKind.video => _fileCanvas(
          (_) {
            final v = _video;
            if (v == null || !v.value.isInitialized) return _loading();
            return Center(
              child: AspectRatio(
                aspectRatio: v.value.aspectRatio,
                child: VideoPlayer(v),
              ),
            );
          },
          caption,
        ),
      StatusMediaKind.voice => _voiceCanvas(status, media),
    };
  }

  Widget _textCanvas(MeshStatusRecord status) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Text(
          status.content,
          key: ValueKey(status.id),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            // Un texte court mérite d'occuper l'écran ; un texte long doit
            // rester lisible. La taille suit donc la longueur.
            fontSize: status.content.length > 80 ? 22 : 30,
            fontWeight: FontWeight.w600,
            height: 1.35,
          ),
        )
            .animate()
            .fadeIn(duration: DesignTokens.durationNormal)
            .scaleXY(begin: 0.94, curve: DesignTokens.curveEnter),
      ),
    );
  }

  /// Enveloppe commune aux médias qui viennent d'un fichier : elle gère
  /// le cas où celui-ci n'est pas encore arrivé, et pose la légende
  /// par-dessus.
  Widget _fileCanvas(
    Widget Function(String path) builder,
    String caption,
  ) {
    final path = _mediaPath;
    return Builder(
      builder: (context) {
        return Stack(
          fit: StackFit.expand,
          children: [
            if (path == null) _loading() else builder(path),
            if (caption.isNotEmpty)
              Positioned(
                left: 20,
                right: 20,
                bottom: 130,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    // Un voile sombre derrière la légende : sans lui, un
                    // texte blanc posé sur une photo claire disparaît.
                    color: Colors.black.withValues(alpha: 0.42),
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                  ),
                  child: Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.3,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _voiceCanvas(MeshStatusRecord status, StatusMedia media) {
    final meta = VoiceNoteMeta.tryParse(media.waveform);
    final caption = status.content.trim();

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            PeerAvatar(pseudo: status.authorPseudo, radius: 38),
            const SizedBox(height: 26),
            SizedBox(
              height: 56,
              child: VoiceWaveform(
                waveform: meta?.waveform ?? const [],
                progress: _voiceProgress,
                activeColor: Colors.white,
                inactiveColor: Colors.white.withValues(alpha: 0.28),
                height: 56,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              _fmtDuration(Duration(milliseconds: media.durationMs ?? 0)),
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (caption.isNotEmpty) ...[
              const SizedBox(height: 22),
              Text(
                caption,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: Colors.white, fontSize: 17, height: 1.35),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _loading() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 26,
            height: 26,
            child: OuroSpinner(color: Colors.white54, radius: 9),
          ),
          const SizedBox(height: 16),
          Text(
            'Réception en cours…',
            style: OuroTypography.footnote.copyWith(color: Colors.white54),
          ),
          const SizedBox(height: 4),
          Text(
            'Le fichier arrive par le réseau local',
            style: OuroTypography.caption1.copyWith(color: Colors.white30),
          ),
        ],
      ),
    );
  }

  // ── L'en-tête ────────────────────────────────────────────────────

  Widget _header(MeshStatusRecord status, StatusMedia media) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnimatedBuilder(
            animation: _progress,
            builder: (context, _) => StoryProgressBar(
              count: _statuses.length,
              currentIndex: _index,
              progress: _progress.value,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              PeerAvatar(pseudo: status.authorPseudo, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(status.authorPseudo,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w700)),
                    Text(_timeAgo(status.createdAt),
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              if (_held)
                const Padding(
                  padding: EdgeInsets.only(right: 6),
                  child: Icon(Icons.pause_rounded,
                      color: Colors.white54, size: 20),
                ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: _close,
              ),
            ],
          ),
          // La pastille de la musique, sous l'auteur : c'est là qu'on la
          // cherche, et elle dit à la fois qu'il y a du son et lequel.
          if (media.hasMusic) ...[
            const SizedBox(height: 8),
            _MusicChip(title: media.musicTitle ?? 'Musique'),
          ],
        ],
      ),
    );
  }

  Future<void> _showFeedbackSheet(MeshStatusRecord status) {
    HapticFeedback.selectionClick();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _FeedbackSheet(status: status),
    );
  }

  static String _fmtDuration(Duration d) {
    final sec = d.inSeconds.clamp(0, 3599);
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }

  static String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    return 'il y a ${diff.inHours} h';
  }
}

// ─────────────────────────────────────────────────────────────
//  LA PASTILLE DE MUSIQUE
// ─────────────────────────────────────────────────────────────

class _MusicChip extends StatelessWidget {
  const _MusicChip({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.34),
        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.music_note_rounded, color: Colors.white, size: 15)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .scaleXY(
                begin: 1,
                end: 1.18,
                duration: 620.ms,
                curve: Curves.easeInOut,
              ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 190),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  RÉPONDRE À UN STATUT
// ─────────────────────────────────────────────────────────────

/// La barre du bas sur le statut de quelqu'un d'autre : un cœur, et un
/// champ pour répondre.
class _ReplyBar extends StatefulWidget {
  const _ReplyBar({
    super.key,
    required this.liked,
    required this.onLike,
    required this.onSend,
    required this.onFocus,
  });

  final bool liked;
  final VoidCallback onLike;
  final Future<void> Function(String text) onSend;

  /// Prévient l'écran qu'on écrit : il met la progression en pause, sinon
  /// le statut défilerait pendant qu'on tape sa réponse.
  final void Function(bool) onFocus;

  @override
  State<_ReplyBar> createState() => _ReplyBarState();
}

class _ReplyBarState extends State<_ReplyBar> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => widget.onFocus(_focus.hasFocus));
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text;
    _controller.clear();
    _focus.unfocus();
    await widget.onSend(text);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 14,
        top: 8,
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focus,
              textCapitalization: TextCapitalization.sentences,
              minLines: 1,
              maxLines: 3,
              cursorColor: Colors.white,
              style: const TextStyle(color: Colors.white, fontSize: 15),
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Répondre…',
                hintStyle: const TextStyle(color: Colors.white54),
                filled: true,
                fillColor: Colors.black.withValues(alpha: 0.38),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: const BorderSide(color: Colors.white54),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Le bouton change de rôle selon qu'on a écrit ou non : envoyer
          // si oui, aimer si non. C'est le même emplacement, donc le même
          // geste, et jamais deux boutons qui se disputent la place.
          if (_hasText)
            _RoundAction(
              icon: Icons.arrow_upward_rounded,
              background: OuroColors.accent,
              onTap: _send,
            )
          else
            _RoundAction(
              icon: widget.liked
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              background: Colors.black.withValues(alpha: 0.38),
              foreground: widget.liked ? OuroColors.systemRed : Colors.white,
              onTap: widget.onLike,
            ),
        ],
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.background,
    required this.onTap,
    this.foreground = Colors.white,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(shape: BoxShape.circle, color: background),
        child: Icon(icon, color: foreground, size: 23),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  MES PROPRES STATUTS
// ─────────────────────────────────────────────────────────────

/// La barre du bas sur MON statut : combien de vues, combien de « j'aime »,
/// combien de réponses — un tap ouvre le détail.
class _MyStatusFooter extends StatelessWidget {
  const _MyStatusFooter({super.key, required this.status, required this.onTap});

  final MeshStatusRecord status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final viewers = StorageService.getStatusViewers(status.id).length;
    final feedback = StorageService.getStatusFeedback(status.id);
    final likes = feedback.where((f) => f.isLike).length;
    final comments = feedback.where((f) => !f.isLike).length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.42),
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          ),
          child: Row(
            children: [
              _stat(Icons.visibility_rounded, viewers, Colors.white),
              const SizedBox(width: 18),
              _stat(Icons.favorite_rounded, likes, OuroColors.systemRed),
              const SizedBox(width: 18),
              _stat(Icons.mode_comment_rounded, comments, Colors.white),
              const Spacer(),
              const Icon(Icons.keyboard_arrow_up_rounded,
                  color: Colors.white54, size: 20),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: DesignTokens.durationNormal);
  }

  Widget _stat(IconData icon, int value, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color, size: 17),
        const SizedBox(width: 6),
        Text('$value',
            style: const TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

/// La feuille qui remonte du bas et détaille qui a vu, qui a aimé et qui
/// a répondu à MON statut.
class _FeedbackSheet extends StatelessWidget {
  const _FeedbackSheet({required this.status});
  final MeshStatusRecord status;

  static String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    return 'il y a ${diff.inHours} h';
  }

  @override
  Widget build(BuildContext context) {
    final viewers = StorageService.getStatusViewers(status.id);
    final feedback = StorageService.getStatusFeedback(status.id);
    final likes = feedback.where((f) => f.isLike).toList();
    final comments = feedback.where((f) => !f.isLike).toList().reversed.toList();

    return FrostedSheet(
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Votre statut',
                  style: OuroTypography.title3
                      .copyWith(color: OuroColors.label)),
              const SizedBox(height: 4),
              Text(
                '${viewers.length} vue${viewers.length > 1 ? 's' : ''} · '
                '${likes.length} j\'aime · '
                '${comments.length} réponse${comments.length > 1 ? 's' : ''}',
                style: OuroTypography.footnote
                    .copyWith(color: OuroColors.secondaryLabel),
              ),
              const SizedBox(height: DesignTokens.space4),
              Flexible(
                child: (viewers.isEmpty && feedback.isEmpty)
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Text(
                            'Personne n\'a encore vu ce statut.\n'
                            'Il continuera de circuler tant que vous croiserez '
                            'des appareils.',
                            textAlign: TextAlign.center,
                            style: OuroTypography.footnote
                                .copyWith(color: OuroColors.tertiaryLabel),
                          ),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        children: [
                          if (comments.isNotEmpty) ...[
                            _sectionTitle('Réponses'),
                            for (final c in comments)
                              _row(
                                pseudo: c.authorPseudo,
                                subtitle: c.text ?? '',
                                trailing: _timeAgo(c.createdAt),
                              ),
                            const SizedBox(height: DesignTokens.space4),
                          ],
                          if (likes.isNotEmpty) ...[
                            _sectionTitle('J\'aime'),
                            for (final l in likes)
                              _row(
                                pseudo: l.authorPseudo,
                                subtitle: l.emoji ?? '❤️',
                                trailing: _timeAgo(l.createdAt),
                              ),
                            const SizedBox(height: DesignTokens.space4),
                          ],
                          if (viewers.isNotEmpty) ...[
                            _sectionTitle('Vu par'),
                            for (final v in viewers)
                              _row(
                                pseudo: v.viewerPseudo,
                                trailing: _timeAgo(v.viewedAt),
                              ),
                          ],
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label.toUpperCase(),
          style: OuroTypography.caption1.copyWith(
            color: OuroColors.secondaryLabel,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.5,
          ),
        ),
      );

  Widget _row({
    required String pseudo,
    String? subtitle,
    required String trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          PeerAvatar(pseudo: pseudo, radius: 17),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(pseudo,
                    style: OuroTypography.subheadline.copyWith(
                      color: OuroColors.label,
                      fontWeight: FontWeight.w600,
                    )),
                if (subtitle != null && subtitle.isNotEmpty)
                  Text(subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: OuroTypography.footnote
                          .copyWith(color: OuroColors.secondaryLabel)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(trailing,
              style: OuroTypography.caption1
                  .copyWith(color: OuroColors.tertiaryLabel)),
        ],
      ),
    );
  }
}
