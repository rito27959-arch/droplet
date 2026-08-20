// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'écran où l'on COMPOSE un statut. Il reprend la disposition des grandes
// messageries : un sélecteur de MODE en bas de l'écran — Vidéo, Photo,
// Message, Vocal — et un plein écran qui change complètement selon le
// mode choisi.
//
//   • MESSAGE : un aplat de couleur, le texte au centre, deux boutons en
//     haut à droite pour changer la police et la couleur.
//   • PHOTO / VIDÉO : la caméra en direct, la pellicule récente en bas,
//     un déclencheur, le retournement de caméra.
//   • VOCAL : un aplat de couleur, une bulle de voix au centre, une
//     bande de couleurs, et le micro en bas à droite.
//
// ── Ce qu'il fait au moment de publier ─────────────────────────────────
//
// Il envoie les choses dans un ordre précis, et cet ordre compte :
//
//   1. D'ABORD les fichiers lourds (la photo, la vidéo, le vocal, la
//      musique), par le canal de transfert de fichiers qui sait
//      découper, reprendre et relayer.
//   2. ENSUITE seulement l'annonce du statut, minuscule, qui dit « j'ai
//      publié quelque chose, et voici où trouver ce qui l'accompagne ».
//
// Si l'annonce partait en premier, elle arriverait chez des gens qui ne
// pourraient rien afficher pendant une minute. Dans cet ordre-là, les
// fichiers sont déjà en route quand l'annonce arrive.
//
// ── Pourquoi la musique est coupée à 30 secondes ───────────────────────
//
// Personne ne regarde un statut plus de quelques secondes, et le réseau
// de Droplet est lent par nature (Bluetooth, Wi-Fi direct). Envoyer une
// chanson entière de quatre minutes à tout le voisinage pour accompagner
// une photo serait un gâchis qui pénaliserait tous les messages en
// attente derrière.
// ============================================================================

import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:video_player/video_player.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../core/models/status_media.dart';
import '../../core/models/voice_note_meta.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/media_service.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_spinner.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_typography.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../core/services/storage_service.dart';

/// Ouvre le compositeur et publie le statut. Renvoie `true` si quelque
/// chose a effectivement été publié.
Future<bool> composeStatus(BuildContext context, WidgetRef ref) async {
  OuroHaptics.selection();
  final published = await Navigator.of(context).push<bool>(
    // Le compositeur est une PARENTHÈSE, pas une descente d'un cran :
    // il monte depuis le bas et se referme par sa croix — jamais par un
    // geste de bord, qu'on déclencherait sans le vouloir en cadrant.
    CupertinoPageRoute<bool>(
      fullscreenDialog: true,
      builder: (_) => const StatusComposerScreen(),
    ),
  );
  return published ?? false;
}

/// Les quatre modes du sélecteur du bas.
enum _Mode { video, photo, message, voice }

extension on _Mode {
  String get label => switch (this) {
        _Mode.video => 'Vidéo',
        _Mode.photo => 'Photo',
        _Mode.message => 'Message',
        _Mode.voice => 'Vocal',
      };
}

/// Les aplats proposés pour un statut Message ou Vocal.
///
/// Des teintes franches et saturées : sur un fond pâle, du texte blanc
/// devient illisible, et l'écran perd le caractère « affiche » qu'on
/// attend d'un statut.
const List<int> _backgrounds = [
  0xFF14B8C4, // turquoise
  0xFF4FB8F5, // ciel
  0xFF3B6EF5, // bleu
  0xFF7FBFA0, // sauge
  0xFF3FBF63, // vert
  0xFF8A9440, // olive
  0xFFD4B315, // moutarde
  0xFFE8A33D, // ambre
  0xFFD9534F, // rouge
  0xFF8E44D0, // violet
  0xFF2C3138, // ardoise
];

/// Les polices proposées pour un statut Message.
///
/// Le choix se fait sur la GRAISSE et l'ESPACEMENT plutôt que sur des
/// familles exotiques : Droplet n'embarque pas de polices
/// supplémentaires (chacune pèse plusieurs centaines de kilo-octets dans
/// l'app), et ces variations suffisent à donner un caractère différent à
/// chaque statut.
const List<TextStyle> _fonts = [
  TextStyle(fontWeight: FontWeight.w400),
  TextStyle(fontWeight: FontWeight.w700),
  TextStyle(fontWeight: FontWeight.w500, fontStyle: FontStyle.italic),
  TextStyle(fontWeight: FontWeight.w900),
  TextStyle(fontWeight: FontWeight.w700, letterSpacing: 3),
  TextStyle(fontWeight: FontWeight.w600, fontFamily: 'monospace'),
  TextStyle(fontWeight: FontWeight.w300, letterSpacing: 1.5),
];

class StatusComposerScreen extends ConsumerStatefulWidget {
  const StatusComposerScreen({super.key});

  @override
  ConsumerState<StatusComposerScreen> createState() =>
      _StatusComposerScreenState();
}

class _StatusComposerScreenState extends ConsumerState<StatusComposerScreen>
    with WidgetsBindingObserver {
  final _caption = TextEditingController();
  final _captionFocus = FocusNode();
  final _recorder = AudioRecorder();

  static const int _maxCaption = 700;

  _Mode _mode = _Mode.message;

  // ── Apparence d'un statut Message / Vocal ────────────────────────
  int _bgIndex = 7;
  int _fontIndex = 1;
  bool _showFonts = false;

  // ── Média choisi ou capturé ──────────────────────────────────────
  File? _mediaFile;
  String? _mediaMime;
  StatusMediaKind _mediaKind = StatusMediaKind.none;

  // ── Caméra ───────────────────────────────────────────────────────
  CameraController? _camera;
  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  bool _flashOn = false;
  bool _recordingVideo = false;

  /// Instant du début de la prise de vue.
  ///
  /// ⚠️ SERT À GARANTIR UNE DURÉE MINIMALE. L'encodeur d'Android a
  /// besoin d'un peu de temps avant de produire sa première image
  /// complète ; arrêté trop tôt, il rend un fichier VIDE et signale
  /// `ERROR_NO_VALID_DATA`. C'est très exactement ce qu'on voyait :
  /// un appui bref sur le déclencheur donnait « L'enregistrement n'a
  /// rien capturé ».
  DateTime? _videoStartedAt;
  static const Duration _minVideo = Duration(milliseconds: 1400);

  // ── Vocal ────────────────────────────────────────────────────────
  bool _recording = false;
  DateTime? _recordStartedAt;
  Duration _voiceDuration = Duration.zero;
  final List<double> _envelope = [];
  Timer? _ampTimer;
  Timer? _tickTimer;
  int _recSeconds = 0;

  // ── Musique ──────────────────────────────────────────────────────
  File? _musicFile;
  String? _musicTitle;

  bool _publishing = false;

  // ── Aperçu du média choisi ───────────────────────────────────────
  //
  // On ne publie pas à l'aveugle : une vidéo se regarde et un vocal
  // s'écoute AVANT de partir vers tout le voisinage. Une fois diffusé,
  // un statut ne se rattrape pas.
  VideoPlayerController? _preview;
  AudioPlayer? _voicePreview;
  bool _voicePlaying = false;
  bool _trimming = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _caption.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _caption.dispose();
    _captionFocus.dispose();
    _ampTimer?.cancel();
    _tickTimer?.cancel();
    _camera?.dispose();
    _preview?.dispose();
    _voicePreview?.dispose();
    // Filet de sécurité : quitter l'écran pendant un enregistrement ne
    // doit jamais laisser le micro ouvert derrière soi.
    _recorder.stop().whenComplete(_recorder.dispose);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // La caméra est une ressource que le système peut reprendre à tout
    // moment : on la relâche en partant en arrière-plan, et on la
    // reprend au retour. Sans cela, revenir dans l'app donne un aperçu
    // figé et noir.
    final cam = _camera;
    if (cam == null) return;
    if (state == AppLifecycleState.inactive) {
      _camera = null;
      cam.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _openCamera();
    }
  }

  bool get _isCameraMode => _mode == _Mode.photo || _mode == _Mode.video;
  Color get _bg => Color(_backgrounds[_bgIndex]);

  bool get _canPublish =>
      !_publishing &&
      switch (_mode) {
        _Mode.message => _caption.text.trim().isNotEmpty,
        _Mode.voice => _mediaFile != null && !_recording,
        _ => _mediaFile != null,
      };

  // ─────────────────────────────────────────────────────────────
  //  CHANGEMENT DE MODE
  // ─────────────────────────────────────────────────────────────

  Future<void> _setMode(_Mode mode) async {
    if (_mode == mode) return;
    OuroHaptics.selection();
    _captionFocus.unfocus();
    if (_recording) await _stopRecording();
    // Même raison que pour le changement d'objectif : quitter le mode
    // vidéo ferme la caméra, et une prise de vue interrompue ne laisse
    // qu'un fichier vide derrière elle.
    if (_recordingVideo) await _stopVideoRecording(keep: false);

    await _preview?.dispose();
    _preview = null;
    await _voicePreview?.stop();
    _voicePlaying = false;

    setState(() {
      _mode = mode;
      _showFonts = false;
      // Changer de mode remet le média à zéro : un vocal enregistré n'a
      // rien à faire dans un statut photo, et l'inverse non plus.
      if (mode != _Mode.voice) {
        _voiceDuration = Duration.zero;
        _envelope.clear();
      }
      _mediaFile = null;
      _mediaMime = null;
      _mediaKind = mode == _Mode.voice
          ? StatusMediaKind.voice
          : StatusMediaKind.none;
    });

    if (_isCameraMode) {
      await _openCamera();
    } else {
      final cam = _camera;
      _camera = null;
      await cam?.dispose();
      if (mounted) setState(() {});
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  CAMÉRA
  // ─────────────────────────────────────────────────────────────

  Future<void> _openCamera() async {
    try {
      if (_cameras.isEmpty) _cameras = await availableCameras();
      if (_cameras.isEmpty) return;

      final controller = CameraController(
        _cameras[_cameraIndex % _cameras.length],
        ResolutionPreset.high,
        enableAudio: true,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (e) {
      if (mounted) {
        _toast("Impossible d'ouvrir la caméra", DropletToastType.error);
      }
    }
  }

  Future<void> _flipCamera() async {
    if (_cameras.length < 2) return;
    // ⚠️ Changer d'objectif ferme la caméra et la rouvre. Le faire en
    // pleine prise de vue ABANDONNE l'enregistrement : le fichier reste
    // à zéro octet et devient « illisible » à la relecture. On termine
    // donc la vidéo en cours et on s'arrête là — l'aperçu qui s'affiche
    // aussitôt rend le changement d'objectif sans objet.
    if (_recordingVideo) {
      await _stopVideoRecording(keep: true);
      return;
    }
    OuroHaptics.selection();
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    final old = _camera;
    setState(() => _camera = null);
    await old?.dispose();
    await _openCamera();
  }

  Future<void> _toggleFlash() async {
    final cam = _camera;
    if (cam == null) return;
    OuroHaptics.selection();
    _flashOn = !_flashOn;
    try {
      await cam.setFlashMode(_flashOn ? FlashMode.torch : FlashMode.off);
    } catch (_) {}
    if (mounted) setState(() {});
  }

  Future<void> _shutter() async {
    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) return;

    if (_mode == _Mode.video) {
      if (_recordingVideo) {
        await _stopVideoRecording(keep: true);
      } else {
        // ⚠️ ON VÉRIFIE LA TEMPÉRATURE AVANT DE FILMER.
        //
        // Au-delà d'un certain échauffement, Android coupe les
        // encodeurs vidéo : l'aperçu reste vivant, le micro enregistre,
        // et le fichier ne contient QUE DU SON. Laisser filmer dans cet
        // état, c'est promettre une vidéo qu'on ne pourra pas rendre.
        if (await MediaService.isOverheating) {
          if (!mounted) return;
          _toast(
            'Téléphone en surchauffe — Android a coupé l\'encodeur vidéo. '
            'Débranchez-le et laissez-le refroidir quelques minutes.',
            DropletToastType.error,
          );
          return;
        }
        try {
          await cam.startVideoRecording();
        } catch (e) {
          // Micro refusé, mémoire pleine, caméra confisquée par une
          // autre application… Sans ce filet, l'exception remontait
          // jusqu'à la racine et l'écran restait figé sur un bouton
          // d'enregistrement qui n'enregistrait rien.
          debugPrint('[Statut] démarrage vidéo impossible: $e');
          if (mounted) {
            _toast("Impossible de démarrer l'enregistrement",
                DropletToastType.error);
          }
          return;
        }
        HapticFeedback.mediumImpact();
        setState(() {
          _recordingVideo = true;
          _recSeconds = 0;
          _videoStartedAt = DateTime.now();
        });
        _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted) return;
          setState(() => _recSeconds++);
          // L'enregistrement s'arrête de lui-même à la durée maximale
          // d'un statut : inutile de laisser filmer plus longtemps pour
          // couper ensuite. Le minuteur est annulé AVANT l'arrêt, sinon
          // la seconde suivante déclenche une deuxième coupure.
          if (_recSeconds >= _maxVideo.inSeconds) {
            _tickTimer?.cancel();
            unawaited(_stopVideoRecording(keep: true));
          }
        });
      }
      return;
    }

    try {
      final shot = await cam.takePicture();
      HapticFeedback.lightImpact();
      if (!mounted) return;
      setState(() {
        _mediaFile = File(shot.path);
        _mediaMime = 'image/jpeg';
        _mediaKind = StatusMediaKind.photo;
      });
    } catch (_) {
      if (mounted) _toast('Photo impossible', DropletToastType.error);
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  GALERIE ET MUSIQUE
  // ─────────────────────────────────────────────────────────────

  /// Au-delà, l'envoi prendrait plusieurs minutes en Bluetooth et
  /// bloquerait tout ce qui attend derrière dans la file.
  static const int _maxMediaBytes = 12 * 1024 * 1024;

  /// Durée maximale d'une vidéo de statut.
  ///
  /// Une vidéo plus longue est COUPÉE, pas refusée : refuser
  /// obligerait à ressortir de l'app pour la raccourcir ailleurs, alors
  /// que ce qu'on veut publier est presque toujours au début.
  static const Duration _maxVideo = Duration(seconds: 90);

  Future<void> _pickFromGallery() async {
    OuroHaptics.selection();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: _mode == _Mode.video ? FileType.video : FileType.image,
      );
      final picked = result?.files.single;
      final path = picked?.path;
      if (path == null) return;

      final file = File(path);
      if (await file.length() > _maxMediaBytes) {
        if (!mounted) return;
        _toast(
          'Fichier trop lourd — ${_maxMediaBytes ~/ (1024 * 1024)} Mo '
          'maximum pour traverser le réseau local.',
          DropletToastType.warning,
        );
        return;
      }

      if (!mounted) return;

      // ── ⚠️ C'EST LE FICHIER QUI DÉCIDE, PAS LE MODE ──────────────
      //
      // La version précédente déduisait la nature du média du mode
      // affiché : en mode « Photo », tout ce qui revenait du sélecteur
      // était étiqueté photo, sans jamais regarder ce que c'était.
      //
      // Or le sélecteur de fichiers d'Android ne garantit pas le filtre
      // demandé. Selon le constructeur et l'application de galerie
      // installée, `FileType.image` laisse passer des vidéos — et
      // « Documents » les laisse toutes passer. Une vidéo choisie là
      // repartait donc annoncée comme `image/jpeg`, publiée en statut
      // photo, et le lecteur d'images du destinataire ne pouvait rien en
      // faire : le statut s'affichait vide ou cassé, et le média
      // ressemblait à un fichier illisible.
      //
      // On regarde donc l'extension réelle. Une vidéo part vers la
      // préparation vidéo, quel que soit le mode dans lequel on se
      // trouvait — et si le type reste inconnu, on refuse au lieu de
      // deviner : publier un statut qui ne s'ouvrira chez personne est
      // pire que de dire non tout de suite.
      final nature = _natureDuFichier(picked!.name);
      if (nature == StatusMediaKind.video) {
        await _prepareVideo(file);
        return;
      }
      if (nature != StatusMediaKind.photo) {
        _toast(
          'Ce format n\'est pas pris en charge pour un statut.',
          DropletToastType.warning,
        );
        return;
      }
      setState(() {
        _mediaFile = file;
        _mediaKind = StatusMediaKind.photo;
        _mediaMime = _guessMime(picked.name);
      });
    } catch (_) {
      if (mounted) _toast('Impossible de lire ce fichier', DropletToastType.error);
    }
  }

  Future<void> _pickMusic() async {
    OuroHaptics.selection();
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.audio);
      final picked = result?.files.single;
      final path = picked?.path;
      if (path == null || !mounted) return;
      setState(() {
        _musicFile = File(path);
        _musicTitle = _prettyTrackTitle(picked!.name);
      });
    } catch (_) {
      if (mounted) _toast('Impossible de lire ce morceau', DropletToastType.error);
    }
  }

  /// Termine la prise de vue en cours.
  ///
  /// [keep] distingue les deux façons d'en sortir : le bouton d'arrêt,
  /// qui veut garder la vidéo, et un changement de mode ou d'objectif,
  /// qui ne fait qu'abandonner la prise. Dans les deux cas la caméra
  /// doit être arrêtée PROPREMENT — c'est ce qui manquait, et un
  /// enregistrement abandonné en route laissait un fichier de zéro
  /// octet que l'aperçu déclarait ensuite « illisible ».
  Future<void> _stopVideoRecording({required bool keep}) async {
    final cam = _camera;
    _tickTimer?.cancel();
    if (cam == null || !_recordingVideo) return;

    // ⚠️ ON LAISSE À L'ENCODEUR LE TEMPS DE PRODUIRE QUELQUE CHOSE.
    //
    // Un appui bref sur le déclencheur arrivait avant la première image
    // encodée : Android refermait le fichier vide en signalant
    // `ERROR_NO_VALID_DATA`. Plutôt que de refuser la prise, on attend
    // le peu qui manque — l'utilisateur obtient un clip très court,
    // ce qu'il demandait, au lieu d'un message d'erreur.
    final started = _videoStartedAt;
    if (started != null) {
      final elapsed = DateTime.now().difference(started);
      if (elapsed < _minVideo) await Future<void>.delayed(_minVideo - elapsed);
    }

    XFile? file;
    try {
      file = await cam.stopVideoRecording();
    } catch (e) {
      debugPrint('[Statut] arrêt vidéo impossible: $e');
    }
    _videoStartedAt = null;
    if (!mounted) return;
    setState(() => _recordingVideo = false);
    if (!keep || file == null) return;

    OuroHaptics.success();
    await _prepareVideo(File(file.path));
  }

  /// Prépare l'aperçu d'une vidéo, en la coupant si elle dépasse la
  /// durée autorisée.
  Future<void> _prepareVideo(File file) async {
    setState(() => _trimming = true);
    try {
      var path = file.path;

      // ⚠️ ON VÉRIFIE LE FICHIER AVANT DE LE DONNER AU LECTEUR.
      //
      // Une prise de vue interrompue, un import annulé à mi-course ou
      // un disque plein produisent un fichier vide. Le lecteur échoue
      // alors avec une erreur de décodage incompréhensible, alors que
      // la cause est simplement qu'il n'y a rien à lire.
      final length = await file.length();
      if (length < 1024) {
        debugPrint('[Statut] vidéo vide ($length octets): $path');
        // La surchauffe est la première cause : on la nomme plutôt que
        // de renvoyer l'utilisateur à un « réessayez » qui échouera
        // exactement de la même façon.
        final hot = await MediaService.isOverheating;
        if (mounted) {
          _toast(
            hot
                ? 'Téléphone en surchauffe — Android a coupé l\'encodeur '
                    'vidéo. Laissez-le refroidir quelques minutes.'
                : "L'enregistrement n'a rien capturé — réessayez.",
            DropletToastType.error,
          );
        }
        return;
      }

      final duration = await MediaService.videoDuration(path);
      if (duration == null) {
        debugPrint('[Statut] durée illisible, format non pris en charge: $path');
        if (mounted) {
          _toast(
            "Ce format vidéo n'est pas pris en charge.",
            DropletToastType.error,
          );
        }
        return;
      }
      if (duration > _maxVideo) {
        final trimmed = await MediaService.trimVideo(path, _maxVideo);
        if (trimmed != path) {
          path = trimmed;
          if (mounted) {
            _toast(
              'Vidéo raccourcie à 1 min 30 — seul le début est publié.',
              DropletToastType.info,
            );
          }
        }
      }

      // ⚠️ ON REND LA CAMÉRA AVANT D'OUVRIR LE LECTEUR.
      //
      // Un téléphone n'a qu'un nombre limité de codecs matériels. La
      // caméra en retient un pour encoder, le lecteur en veut un pour
      // décoder : les deux ensemble faisaient échouer le second avec un
      // « MediaCodecVideoRenderer error » — alors même que le format
      // était annoncé comme pris en charge. La caméra ne sert plus
      // pendant qu'on regarde le résultat ; on la rouvre si l'aperçu
      // échoue ou si l'utilisateur refait une prise.
      await _releaseCamera();

      await _preview?.dispose();
      _preview = null;
      final controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      await controller.setLooping(true);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _preview = controller;
        _mediaFile = File(path);
        _mediaKind = StatusMediaKind.video;
        // Le type vient du fichier RÉELLEMENT publié — celui qui sort de
        // la découpe, pas celui qui y est entré. Un `video/mp4` écrit en
        // dur annonçait un MP4 pour un .mov ou un .webm importé tel
        // quel, et le lecteur du destinataire refusait de l'ouvrir.
        _mediaMime = _guessMime(path);
      });
      unawaited(controller.play());
    } catch (e, stack) {
      // ⚠️ La cause est journalisée, pas seulement affichée. Un
      // « Vidéo illisible » sans trace ne dit rien : ni si c'est la
      // découpe, ni le décodage, ni un simple problème de droits sur le
      // fichier. Sans cette ligne, le défaut était indiagnosticable.
      debugPrint('[Statut] préparation vidéo échouée: $e\n$stack');
      if (mounted) _toast('Vidéo illisible', DropletToastType.error);
    } finally {
      if (mounted) setState(() => _trimming = false);
      // Aperçu raté : on ne laisse pas l'écran vide. La caméra revient,
      // prête pour une nouvelle prise.
      if (mounted && _mediaKind != StatusMediaKind.video && _isCameraMode) {
        unawaited(_openCamera());
      }
    }
  }

  /// Ferme la caméra et libère le codec matériel qu'elle occupe.
  Future<void> _releaseCamera() async {
    final cam = _camera;
    if (cam == null) return;
    _camera = null;
    if (mounted) setState(() {});
    try {
      await cam.dispose();
    } catch (_) {}
  }

  /// Écoute ou arrête l'aperçu du vocal enregistré.
  Future<void> _toggleVoicePreview() async {
    final file = _mediaFile;
    if (file == null || _recording) return;
    OuroHaptics.light();

    if (_voicePlaying) {
      await _voicePreview?.stop();
      if (mounted) setState(() => _voicePlaying = false);
      return;
    }

    _voicePreview ??= AudioPlayer();
    // L'abonnement est repris à chaque lecture, sur un lecteur unique :
    // pas d'empilement d'auditeurs d'une écoute à l'autre.
    _voicePreview!.onPlayerComplete.first.then((_) {
      if (mounted) setState(() => _voicePlaying = false);
    });
    try {
      await _voicePreview!.play(DeviceFileSource(file.path));
      if (mounted) setState(() => _voicePlaying = true);
    } catch (e) {
      debugPrint('[Statut] relecture impossible: $e');
      if (!mounted) return;
      setState(() => _voicePlaying = false);
      _toast('Enregistrement illisible', DropletToastType.error);
    }
  }

  /// Transforme un nom de fichier de musique en titre présentable.
  ///
  /// Un morceau récupéré sur le téléphone s'appelle rarement « Artiste -
  /// Titre ». Les téléchargeurs y accrochent un identifiant en tête, le
  /// code de la vidéo d'origine en queue, et des mentions publicitaires
  /// au milieu :
  ///
  ///   32ae17b2-967a-45da-8949-647499f80cb3-DADJU-Jaloux-Clip-Officiel_254EHfv9RvM.mp3
  ///                                    ↓
  ///   DADJU - Jaloux
  ///
  /// Affiché tel quel sous un statut, ce charabia ruine la vignette.
  static String _prettyTrackTitle(String fileName) {
    var name = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');

    // 1. L'identifiant unique que collent en tête les gestionnaires de
    //    téléchargement (format UUID).
    name = name.replaceFirst(
      RegExp(
        r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
        r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}[-_ ]*',
      ),
      '',
    );

    // 2. Le code de la vidéo d'origine, en queue : onze caractères sans
    //    espace, mêlant majuscules, minuscules ou chiffres. La
    //    condition est stricte à dessein — un vrai mot de onze lettres
    //    ne doit pas disparaître.
    name = name.replaceFirst(
      RegExp(r'[-_](?=[^-_ ]{11}$)(?=[^ ]*[A-Z])(?=[^ ]*[a-z0-9])[^ ]{11}$'),
      '',
    );

    // 3. Les mentions ajoutées par les plateformes.
    name = name.replaceAll(
      RegExp(
        r'[\(\[][^\)\]]*\b(official|officiel|lyrics?|paroles|audio|video|'
        r'vidéo|clip|music|hd|4k|hq|full)\b[^\)\]]*[\)\]]',
        caseSensitive: false,
      ),
      ' ',
    );
    //    Sans parenthèses, elles s'empilent en fin de nom
    //    (« …-Clip-Officiel ») : on les retire une par une, tant qu'il
    //    en reste.
    final trailingNoise = RegExp(
      r'[-_ ]+(official|officiel|lyrics?|paroles|audio|video|vidéo|clip|'
      r'music|hd|4k|hq)$',
      caseSensitive: false,
    );
    var previous = '';
    while (previous != name) {
      previous = name;
      name = name.replaceFirst(trailingNoise, '');
    }

    // 4. Ce qui reste : les séparateurs techniques redeviennent des
    //    espaces, et les tirets isolés des tirets de titre.
    name = name
        .replaceAll('_', ' ')
        .replaceAll(RegExp(r'\s*-\s*'), ' - ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^[\s\-]+|[\s\-]+$'), '')
        .trim();

    // Un nom entièrement rongé par le nettoyage vaut moins que le nom
    // d'origine : dans le doute, on garde ce que l'utilisateur voit
    // dans son explorateur de fichiers.
    if (name.length < 2) return fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
    return name;
  }

  static String _durationLabel(Duration d) {
    final sec = d.inSeconds;
    return '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}';
  }

  static String _extension(String name) =>
      name.contains('.') ? name.split('.').last.toLowerCase() : '';

  /// Ce qu'est RÉELLEMENT le fichier choisi, d'après son extension.
  ///
  /// Renvoie [StatusMediaKind.none] pour un format qu'on ne sait pas
  /// publier — ce qui vaut refus, et non « on tente quand même ».
  static StatusMediaKind _natureDuFichier(String name) {
    return switch (_extension(name)) {
      'jpg' || 'jpeg' || 'png' || 'webp' || 'heic' || 'gif' =>
        StatusMediaKind.photo,
      'mp4' || 'mov' || 'webm' || 'mkv' || '3gp' || 'm4v' =>
        StatusMediaKind.video,
      _ => StatusMediaKind.none,
    };
  }

  /// Le type MIME d'un fichier, d'après son extension.
  ///
  /// ⚠️ PLUS DE VALEUR PAR DÉFAUT INVENTÉE. L'ancienne version terminait
  /// par `_mode == _Mode.video ? 'video/mp4' : 'image/jpeg'` : une
  /// extension inconnue repartait donc étiquetée JPEG, et le
  /// destinataire recevait un fichier annoncé comme une image qui n'en
  /// était pas une. Un type honnête, même vague, vaut mieux qu'un type
  /// faux : `application/octet-stream` dit « je ne sais pas », et rien
  /// ne prétend savoir l'ouvrir.
  String _guessMime(String name) {
    return switch (_extension(name)) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'heic' => 'image/heic',
      'gif' => 'image/gif',
      'mp4' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'mkv' => 'video/x-matroska',
      '3gp' => 'video/3gpp',
      'm4v' => 'video/x-m4v',
      _ => 'application/octet-stream',
    };
  }

  // ─────────────────────────────────────────────────────────────
  //  VOCAL
  // ─────────────────────────────────────────────────────────────

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
    } else {
      await _startRecording();
    }
  }

  Future<void> _startRecording() async {
    if (!await _recorder.hasPermission()) {
      if (mounted) _toast('Permission micro refusée', DropletToastType.error);
      return;
    }
    try {
      final dir = await getApplicationDocumentsDirectory();
      final recDir = Directory('${dir.path}/recordings');
      if (!await recDir.exists()) await recDir.create(recursive: true);
      final path =
          '${recDir.path}/statut-${DateTime.now().millisecondsSinceEpoch}.m4a';

      await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      HapticFeedback.mediumImpact();

      _envelope.clear();
      _recordStartedAt = DateTime.now();
      setState(() {
        _recording = true;
        _mediaFile = File(path);
        _mediaMime = 'audio/m4a';
        _mediaKind = StatusMediaKind.voice;
        _recSeconds = 0;
      });

      // Le relevé du niveau sonore, pour dessiner la voix. Le micro
      // renvoie des DÉCIBELS (un nombre négatif) : la conversion vit
      // dans `VoiceNoteMeta.normalizeDb`.
      _ampTimer = Timer.periodic(const Duration(milliseconds: 80), (_) async {
        try {
          final amp = await _recorder.getAmplitude();
          if (!mounted) return;
          setState(() {
            if (_envelope.length < 8000) {
              _envelope.add(VoiceNoteMeta.normalizeDb(amp.current));
            }
          });
        } catch (_) {}
      });
      _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        setState(() => _recSeconds++);
        // Un statut vocal de plus de deux minutes n'a plus rien d'un
        // statut, et son fichier deviendrait trop lourd pour le réseau.
        if (_recSeconds >= 120) _stopRecording();
      });
    } catch (_) {
      if (mounted) {
        _toast("Impossible de démarrer l'enregistrement", DropletToastType.error);
      }
    }
  }

  Future<void> _stopRecording() async {
    if (!_recording) return;
    _ampTimer?.cancel();
    _tickTimer?.cancel();

    final started = _recordStartedAt;
    final duration =
        started == null ? Duration.zero : DateTime.now().difference(started);

    setState(() => _recording = false);
    _recordStartedAt = null;

    try {
      final path = await _recorder.stop();
      // Un appui involontaire produit un vocal d'un dixième de seconde,
      // qu'il vaut mieux jeter que publier.
      if (path == null || duration.inMilliseconds < 700) {
        if (path != null) {
          final f = File(path);
          if (await f.exists()) await f.delete();
        }
        if (mounted) setState(() => _mediaFile = null);
        return;
      }
      if (mounted) setState(() => _voiceDuration = duration);
    } catch (_) {}
  }

  // ─────────────────────────────────────────────────────────────
  //  PUBLICATION
  // ─────────────────────────────────────────────────────────────

  Future<void> _publish() async {
    if (!_canPublish) return;
    if (_recording) await _stopRecording();
    if (_recordingVideo) await _shutter();

    setState(() => _publishing = true);
    final repo = ref.read(meshRepositoryProvider);

    try {
      var media = StatusMedia(
        kind: _mediaKind,
        backgroundColor: (_mode == _Mode.message || _mode == _Mode.voice)
            ? _backgrounds[_bgIndex]
            : null,
      );

      // 1. Le média principal part en premier.
      final file = _mediaFile;
      if (file != null && await file.exists()) {
        final bytes = await file.readAsBytes();
        final name = file.path.split('/').last;
        final fileId = await repo.sendStatusFile(
          fileName: name,
          bytes: bytes,
          mimeType: _mediaMime ?? 'application/octet-stream',
        );
        media = media.copyWith(
          fileId: fileId,
          fileName: name,
          mimeType: _mediaMime,
          durationMs: _mediaKind == StatusMediaKind.voice
              ? _voiceDuration.inMilliseconds
              : null,
          waveform: _mediaKind == StatusMediaKind.voice
              ? VoiceNoteMeta.encodeFileName(
                  duration: _voiceDuration, samples: _envelope)
              : null,
        );
      }

      // 2. Puis la musique, si elle a été choisie.
      final music = _musicFile;
      if (music != null && await music.exists()) {
        final clipped = await _clipMusic(music);
        final name = music.path.split('/').last;
        final musicId = await repo.sendStatusFile(
          fileName: name,
          bytes: clipped,
          mimeType: 'audio/mpeg',
        );
        media = media.copyWith(
          musicFileId: musicId,
          musicFileName: name,
          musicTitle: _musicTitle,
        );
      }

      // 3. L'annonce en dernier : elle est minuscule et arrivera vite,
      //    pendant que les fichiers finissent leur route.
      await repo.sendStatus(_caption.text.trim(), media: media);

      if (!mounted) return;
      OuroHaptics.success();
      _toast('Statut publié', DropletToastType.success);
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _publishing = false);
      OuroHaptics.error();
      _toast('Échec de la publication', DropletToastType.error);
    }
  }

  /// Ne garde que le début de la chanson.
  ///
  /// Une vraie découpe audio demanderait de décoder puis réencoder le
  /// fichier. On se contente ici de tronquer les octets : sur un MP3, un
  /// fichier coupé net reste parfaitement lisible — le lecteur joue ce
  /// qu'il peut et s'arrête. C'est grossier, mais cela suffit pour un
  /// fond sonore de quelques secondes, et cela évite d'embarquer une
  /// bibliothèque de traitement audio entière.
  Future<Uint8List> _clipMusic(File file) async {
    final bytes = await file.readAsBytes();
    // ~40 ko par seconde à 320 kbit/s, le pire cas courant.
    const int limit = 30 * 40 * 1024;
    if (bytes.length <= limit) return bytes;
    return Uint8List.sublistView(bytes, 0, limit);
  }

  void _toast(String message, DropletToastType type) {
    ref.read(toastProvider.notifier).show(message, type: type);
  }

  // ─────────────────────────────────────────────────────────────
  //  AFFICHAGE
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final keyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

    return Scaffold(
      backgroundColor: _isCameraMode ? Colors.black : _bg,
      resizeToAvoidBottomInset: false,
      // Le compositeur est plein écran et toujours sombre : c'est une
      // toile, pas une page de réglages. Les icônes système doivent donc
      // rester claires même quand l'app est en mode clair.
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            Positioned.fill(child: _canvas()),
            Positioned(top: 0, left: 0, right: 0, child: SafeArea(child: _topBar())),
            Positioned(
              left: 0,
              right: 0,
              bottom: keyboardOpen
                  ? MediaQuery.viewInsetsOf(context).bottom
                  : 0,
              child: _bottomStack(keyboardOpen),
            ),
          ],
        ),
      ),
    );
  }

  // ── La toile ─────────────────────────────────────────────────────

  Widget _canvas() {
    if (_isCameraMode) return _cameraCanvas();
    if (_mode == _Mode.voice) return _voiceCanvas();
    return _messageCanvas();
  }

  Widget _messageCanvas() {
    return GestureDetector(
      // Taper n'importe où sur l'aplat donne le clavier : c'est une page
      // d'écriture, il n'y a rien d'autre à y faire.
      onTap: () => _captionFocus.requestFocus(),
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(28, 90, 28, 200),
          child: TextField(
            controller: _caption,
            focusNode: _captionFocus,
            maxLines: null,
            maxLength: _maxCaption,
            textAlign: TextAlign.center,
            textCapitalization: TextCapitalization.sentences,
            cursorColor: Colors.white,
            style: _fonts[_fontIndex].copyWith(
              color: Colors.white,
              // Le texte rétrécit à mesure qu'il s'allonge, comme dans
              // toutes les messageries : une phrase courte doit remplir
              // l'écran, un paragraphe doit rester lisible.
              fontSize: _caption.text.length > 120
                  ? 22
                  : _caption.text.length > 50
                      ? 28
                      : 34,
              height: 1.25,
            ),
            decoration: InputDecoration(
              counterText: '',
              // ⚠️ `filled: false` est indispensable : le thème de l'app
              // remplit TOUS les champs d'un gris de formulaire. Sur un
              // aplat de couleur, ce rectangle gris apparaissait au
              // milieu de l'écran comme une boîte posée là. Ici le champ
              // ne doit pas exister visuellement — il n'y a que du texte
              // sur de la couleur.
              filled: false,
              fillColor: Colors.transparent,
              isDense: true,
              contentPadding: EdgeInsets.zero,
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              hintText: 'Écrivez un statut',
              hintStyle: _fonts[_fontIndex].copyWith(
                color: Colors.white.withValues(alpha: 0.42),
                fontSize: 34,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _voiceCanvas() {
    final me = StorageService.currentUser?.pseudo ?? 'Moi';
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            // Un voile plus sombre que l'aplat : la bulle doit se
            // détacher sans introduire une seconde couleur.
            color: Colors.black.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              GestureDetector(
                // Une fois l'enregistrement terminé, cette pastille sert
                // à SE RÉÉCOUTER : on ne publie pas sa voix à tout le
                // voisinage sans l'avoir entendue une fois.
                onTap: (!_recording && _voiceDuration > Duration.zero)
                    ? _toggleVoicePreview
                    : null,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    PeerAvatar(pseudo: me, radius: 20),
                    Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: 0.35),
                      ),
                      child: Icon(
                        _recording
                            ? Icons.mic_rounded
                            : _voiceDuration > Duration.zero
                                ? (_voicePlaying
                                    ? Icons.pause_rounded
                                    : Icons.play_arrow_rounded)
                                : Icons.mic_rounded,
                        color: Colors.white,
                        size: 15,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 26,
                  child: _recording
                      ? _LiveDots(amplitudes: _envelope)
                      : _IdleDots(
                          filled: _voiceDuration > Duration.zero,
                        ),
                ),
              ),
              if (_recording || _voiceDuration > Duration.zero) ...[
                const SizedBox(width: 10),
                Text(
                  _recording
                      ? '${_recSeconds ~/ 60}:${(_recSeconds % 60).toString().padLeft(2, '0')}'
                      : '${_voiceDuration.inSeconds ~/ 60}:'
                          '${(_voiceDuration.inSeconds % 60).toString().padLeft(2, '0')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _cameraCanvas() {
    final captured = _mediaFile;
    if (captured != null && _mediaKind == StatusMediaKind.photo) {
      return Center(child: Image.file(captured, fit: BoxFit.contain));
    }
    if (captured != null && _mediaKind == StatusMediaKind.video) {
      // La vidéo se REGARDE avant d'être publiée, en boucle. Une simple
      // vignette immobile ne dirait pas si on a filmé le bon moment, ni
      // si la coupe à 1 min 30 tombe au bon endroit.
      final preview = _preview;
      if (_trimming || preview == null || !preview.value.isInitialized) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const OuroSpinner(color: Colors.white38, radius: 14),
              const SizedBox(height: 16),
              Text(
                _trimming ? 'Préparation de la vidéo…' : 'Chargement…',
                style: const TextStyle(color: Colors.white54, fontSize: 13),
              ),
            ],
          ),
        );
      }
      return Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: preview.value.aspectRatio,
              child: VideoPlayer(preview),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 12,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusFull),
                ),
                child: Text(
                  _durationLabel(preview.value.duration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final cam = _camera;
    if (cam == null || !cam.value.isInitialized) {
      return const Center(
        child: OuroSpinner(color: Colors.white38, radius: 14),
      );
    }

    // L'aperçu remplit l'écran sans se déformer : on le recadre plutôt
    // que de l'étirer, sinon les visages s'allongent.
    return Stack(
      fit: StackFit.expand,
      children: [
        FittedBox(
          fit: BoxFit.cover,
          child: SizedBox(
            width: cam.value.previewSize?.height ?? 1,
            height: cam.value.previewSize?.width ?? 1,
            child: CameraPreview(cam),
          ),
        ),
        if (_recordingVideo) IgnorePointer(child: _recordingOverlay()),
      ],
    );
  }

  /// Ce qui dit, sans ambiguïté possible, qu'on est en train de filmer.
  ///
  /// Il n'y avait AUCUN indice : le déclencheur changeait discrètement
  /// de forme, et rien d'autre. On ne savait pas si la prise avait
  /// démarré, ni depuis combien de temps, ni combien il restait. Les
  /// trois signaux que donnent toutes les grandes applications :
  ///
  ///   • un cadre rouge sur tout l'écran — visible du coin de l'œil ;
  ///   • une pastille « point clignotant + chronomètre » en haut ;
  ///   • une jauge du temps restant sur la limite de 1 min 30.
  ///
  /// Le clignotement suit le minuteur d'une seconde déjà en place :
  /// pas d'animation supplémentaire à entretenir.
  ///
  /// ⚠️ Le cadre n'a PAS d'ombre portée. Une `BoxShadow` sur une boîte
  /// qui occupe tout l'écran peint sa silhouette floutée derrière elle —
  /// et comme la boîte n'a pas de fond, le rouge se voyait au travers :
  /// l'aperçu entier virait au rose.
  Widget _recordingOverlay() {
    final remaining = _maxVideo.inSeconds - _recSeconds;
    final progress = (_recSeconds / _maxVideo.inSeconds).clamp(0.0, 1.0);

    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: OuroColors.systemRed, width: 3),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 62,
          left: 0,
          right: 0,
          child: Column(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 420),
                      opacity: _recSeconds.isEven ? 1 : 0.2,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                          color: OuroColors.systemRed,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_recSeconds ~/ 60}:'
                      '${(_recSeconds % 60).toString().padLeft(2, '0')}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
              // Les dix dernières secondes se comptent à rebours : c'est
              // le moment où l'on veut savoir qu'il faut conclure.
              if (remaining <= 10)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'Fin dans $remaining s',
                    style: TextStyle(
                      color: OuroColors.systemRed,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: MediaQuery.paddingOf(context).top,
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 2.5,
            backgroundColor: Colors.white.withValues(alpha: 0.12),
            valueColor: AlwaysStoppedAnimation(OuroColors.systemRed),
          ),
        ),
      ],
    );
  }

  // ── La barre du haut ─────────────────────────────────────────────

  Widget _topBar() {
    // Dès qu'on écrit ou qu'on a enregistré, le X laisse la place à un
    // bouton « Terminé » : à ce moment-là on ne veut plus abandonner,
    // on veut refermer le clavier et regarder son statut.
    final showDone = (_mode == _Mode.message && _captionFocus.hasFocus) ||
        (_mode == _Mode.voice && _voiceDuration > Duration.zero);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          if (showDone)
            GestureDetector(
              onTap: () {
                OuroHaptics.light();
                _captionFocus.unfocus();
                setState(() => _showFonts = false);
              },
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 22, vertical: 11),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Text('Terminé',
                    style: OuroTypography.headline
                        .copyWith(color: Colors.black)),
              ),
            )
          else
            _circle(
              Icons.close_rounded,
              () => Navigator.of(context).pop(false),
            ),
          const Spacer(),
          if (_mode == _Mode.message && !_showFonts)
            _circle(
              Icons.text_fields_rounded,
              () {
                OuroHaptics.selection();
                setState(() => _showFonts = true);
                _captionFocus.requestFocus();
              },
              label: 'Aa',
            ),
          if (_mode == _Mode.message) const SizedBox(width: 10),
          if (_mode == _Mode.message)
            _circle(Icons.palette_rounded, _cycleBackground),
          if (_isCameraMode && _mediaFile == null)
            _circle(
              _flashOn ? Icons.flash_on_rounded : Icons.flash_off_rounded,
              _toggleFlash,
            ),
          if (_isCameraMode && _mediaFile != null)
            _circle(Icons.refresh_rounded, () async {
              // La vidéo relâche son lecteur, et la caméra reprend la
              // place qu'il occupait — sans quoi l'écran resterait noir
              // après un « refaire » sur une vidéo.
              final preview = _preview;
              _preview = null;
              setState(() {
                _mediaFile = null;
                _mediaKind = StatusMediaKind.none;
              });
              await preview?.dispose();
              if (_camera == null && mounted) await _openCamera();
            }),
        ],
      ),
    );
  }

  void _cycleBackground() {
    OuroHaptics.selection();
    setState(() => _bgIndex = (_bgIndex + 1) % _backgrounds.length);
  }

  Widget _circle(IconData icon, VoidCallback onTap, {String? label}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.30),
        ),
        alignment: Alignment.center,
        child: label != null
            ? Text(label,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ))
            : Icon(icon, color: Colors.white, size: 21),
      ),
    );
  }

  // ── Le bas de l'écran ────────────────────────────────────────────

  Widget _bottomStack(bool keyboardOpen) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // La bande contextuelle : polices en mode Message, couleurs en
        // mode Vocal, pellicule en mode caméra.
        if (_mode == _Mode.message && _showFonts) _fontStrip(),
        if (_mode == _Mode.voice) _colorStrip(),
        if (_isCameraMode && _mediaFile == null) _cameraControls(),
        if (_musicTitle != null) _musicChip(),

        _modeSelector(keyboardOpen),
      ],
    );
  }

  Widget _fontStrip() {
    return SizedBox(
      height: 62,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _fonts.length,
        itemBuilder: (context, i) {
          final selected = i == _fontIndex;
          return GestureDetector(
            onTap: () {
              OuroHaptics.selection();
              setState(() => _fontIndex = i);
            },
            child: Container(
              width: 46,
              height: 46,
              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected
                    ? Colors.white
                    : Colors.black.withValues(alpha: 0.22),
              ),
              alignment: Alignment.center,
              child: Text(
                'Aa',
                style: _fonts[i].copyWith(
                  color: selected ? Colors.black : Colors.white,
                  fontSize: 16,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _colorStrip() {
    return SizedBox(
      height: 56,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _backgrounds.length,
        itemBuilder: (context, i) {
          final selected = i == _bgIndex;
          return GestureDetector(
            onTap: () {
              OuroHaptics.selection();
              setState(() => _bgIndex = i);
            },
            child: Container(
              width: 40,
              height: 40,
              margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Color(_backgrounds[i]),
                border: selected
                    ? Border.all(color: Colors.white, width: 2)
                    : null,
              ),
              child: selected
                  ? const Icon(Icons.check_rounded,
                      color: Colors.white, size: 20)
                  : null,
            ),
          );
        },
      ),
    );
  }

  Widget _cameraControls() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          // Pendant la prise, les deux actions latérales s'effacent :
          // elles interrompraient la vidéo, et rien ne doit détourner
          // du seul geste qui compte à cet instant — arrêter.
          AnimatedOpacity(
            duration: DesignTokens.durationFast,
            opacity: _recordingVideo ? 0.25 : 1,
            child: _circle(Icons.photo_library_rounded, _pickFromGallery),
          ),
          GestureDetector(
            onTap: _shutter,
            child: SizedBox(
              width: 74,
              height: 74,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // L'anneau blanc devient une jauge rouge qui se remplit
                  // jusqu'à la limite : le temps restant se lit sur le
                  // bouton lui-même, sans quitter le cadrage des yeux.
                  SizedBox(
                    width: 74,
                    height: 74,
                    child: _recordingVideo
                        ? CircularProgressIndicator(
                            value: (_recSeconds / _maxVideo.inSeconds)
                                .clamp(0.0, 1.0),
                            strokeWidth: 4,
                            backgroundColor:
                                Colors.white.withValues(alpha: 0.35),
                            valueColor:
                                AlwaysStoppedAnimation(OuroColors.systemRed),
                          )
                        : DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: Colors.white, width: 4),
                            ),
                          ),
                  ),
                  AnimatedContainer(
                    duration: DesignTokens.durationFast,
                    width: _recordingVideo ? 28 : 58,
                    height: _recordingVideo ? 28 : 58,
                    decoration: BoxDecoration(
                      color:
                          _recordingVideo ? OuroColors.systemRed : Colors.white,
                      borderRadius:
                          BorderRadius.circular(_recordingVideo ? 6 : 29),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedOpacity(
            duration: DesignTokens.durationFast,
            opacity: _recordingVideo ? 0.25 : 1,
            child: _circle(Icons.flip_camera_ios_rounded, _flipCamera),
          ),
        ],
      ),
    );
  }

  Widget _musicChip() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.34),
          borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
        ),
        child: Row(
          children: [
            const Icon(Icons.music_note_rounded, color: Colors.white, size: 17),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_musicTitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13)),
            ),
            const Text('30 s',
                style: TextStyle(color: Colors.white38, fontSize: 11)),
            GestureDetector(
              onTap: () => setState(() {
                _musicFile = null;
                _musicTitle = null;
              }),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.close_rounded, color: Colors.white54, size: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Le sélecteur de mode, plus les deux actions qui l'encadrent :
  /// la musique à gauche, et à droite le micro (en Vocal) ou le bouton
  /// de publication.
  Widget _modeSelector(bool keyboardOpen) {
    return Container(
      // Un voile sombre qui reprend la teinte du fond, exactement comme
      // dans les messageries : la bande se distingue de l'aplat sans
      // introduire une couleur de plus.
      color: Colors.black.withValues(alpha: 0.26),
      padding: EdgeInsets.only(
        left: 6,
        right: 6,
        top: 8,
        bottom: keyboardOpen ? 8 : MediaQuery.paddingOf(context).bottom + 8,
      ),
      child: Row(
        children: [
          // La musique n'a de sens que sur un statut qu'on regarde :
          // en mode caméra, l'aperçu occupe déjà l'écran et la place
          // manque pour les quatre modes.
          if (!keyboardOpen && !_isCameraMode)
            _circle(Icons.library_music_rounded, _pickMusic),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final mode in _Mode.values) _modeChip(mode),
                ],
              ),
            ),
          ),
          if (_mode == _Mode.voice && !_canPublish)
            _recordButton()
          else if (_canPublish)
            _publishButton()
          else
            const SizedBox(width: 44),
        ],
      ),
    );
  }

  Widget _modeChip(_Mode mode) {
    final selected = mode == _mode;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _setMode(mode),
      child: AnimatedContainer(
        duration: DesignTokens.durationFast,
        // Serré volontairement : les quatre modes DOIVENT tenir sans
        // défilement. Sur un écran de 411 points, « Vocal » se
        // retrouvait coupé au bord droit — et un mode qu'on ne voit pas
        // est un mode qui n'existe pas.
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        margin: const EdgeInsets.symmetric(horizontal: 1),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withValues(alpha: 0.22)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          mode.label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontSize: 15,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }

  Widget _recordButton() {
    return GestureDetector(
      onTap: _toggleRecording,
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _recording ? OuroColors.systemRed : Colors.white,
        ),
        child: Icon(
          _recording ? Icons.stop_rounded : Icons.mic_rounded,
          color: _recording ? Colors.white : Colors.black,
          size: 24,
        ),
      ),
    );
  }

  Widget _publishButton() {
    return GestureDetector(
      onTap: _publish,
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
          color: OuroColors.accent,
          borderRadius: BorderRadius.circular(24),
        ),
        alignment: Alignment.center,
        child: _publishing
            ? const SizedBox(
                width: 18,
                height: 18,
                child: OuroSpinner(color: Colors.white, radius: 9),
              )
            : const Icon(Icons.send_rounded, color: Colors.white, size: 21),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  LA VOIX DANS LA BULLE
// ─────────────────────────────────────────────────────────────

/// Les points immobiles d'une bulle vocale au repos.
class _IdleDots extends StatelessWidget {
  const _IdleDots({required this.filled});
  final bool filled;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _DotsPainter(
        amplitudes: const [],
        color: Colors.white.withValues(alpha: filled ? 0.85 : 0.45),
      ),
    );
  }
}

/// Les points qui réagissent à la voix pendant l'enregistrement.
class _LiveDots extends StatelessWidget {
  const _LiveDots({required this.amplitudes});
  final List<double> amplitudes;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.infinite,
      painter: _DotsPainter(amplitudes: amplitudes, color: Colors.white),
    );
  }
}

class _DotsPainter extends CustomPainter {
  _DotsPainter({required this.amplitudes, required this.color});

  final List<double> amplitudes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const spacing = 6.0;
    final count = (size.width / spacing).floor();
    if (count <= 0) return;

    final mid = size.height / 2;
    final visible = amplitudes.length > count
        ? amplitudes.sublist(amplitudes.length - count)
        : amplitudes;

    for (var i = 0; i < count; i++) {
      final x = i * spacing + spacing / 2;
      // Sans enregistrement, une simple rangée de points : c'est le
      // repos, il n'y a rien à représenter.
      final v = i < visible.length ? visible[i].clamp(0.0, 1.0) : 0.0;
      final h = 2.5 + v * (size.height - 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(x, mid), width: 2.5, height: h),
          const Radius.circular(1.5),
        ),
        Paint()..color = color,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DotsPainter old) =>
      old.amplitudes.length != amplitudes.length || old.color != color;
}
