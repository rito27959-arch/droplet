// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le pont Dart ↔ GLSL pour le shader Nexus. Ce fichier :
//
//   1. Charge et compile le shader GPU une seule fois au démarrage.
//   2. Fournit `NexusShaderPainter`, un `CustomPainter` qui dessine le
//      résultat du shader sur n'importe quelle zone de l'écran.
//   3. Gère les uniformes : chaque pixel reçoit le temps, la phase,
//      la seed, la couleur, etc.
//
// Le shader tourne UNIQUEMENT sur le GPU — le Dart ne fait que lui
// fournit les paramètres et le canvas. C'est ce qui permet les 60 FPS
// même sur des effets visuels complexes.
// ============================================================================

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'nexus_event.dart';

// ── Chargement du shader ─────────────────────────────────────────────────────
// Exactement le même pattern que `LiquidShader` dans `ouro_liquid.dart` :
// compilation asynchrone, null-safe, un seul essai.

/// Charge et conserve le programme GPU Nexus.
class NexusShaderLoader {
  NexusShaderLoader._();

  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loading;

  static bool get isReady => _program != null;
  static ui.FragmentProgram? get program => _program;

  static Future<ui.FragmentProgram?> load() {
    if (_program != null) return Future.value(_program);
    return _loading ??= _loadOnce();
  }

  static Future<ui.FragmentProgram?> _loadOnce() async {
    try {
      final program =
          await ui.FragmentProgram.fromAsset('shaders/nexus.frag');
      _program = program;
      debugPrint('[NexusShader] compilé avec succès');
      return program;
    } catch (e) {
      debugPrint('[NexusShader] indisponible: $e');
      return null;
    }
  }
}

// ── État public de l'animation ───────────────────────────────────────────────
// Toutes les données que le shader doit recevoir, regroupées en un seul
// objet pour éviter de passer 10 paramètres isolés.

/// État complet de l'animation Nexus, passé au shader à chaque image.
class NexusShaderState {
  /// ⚠️ PAS DE CHAMP `time` ICI, VOLONTAIREMENT.
  ///
  /// Il en existait un, toujours mis à zéro par le contrôleur, et le
  /// widget le remplaçait ensuite par la valeur de son propre ticker. Deux
  /// sources pour la même grandeur, dont une morte : la première chose
  /// qu'on soupçonne quand l'animation paraît figée, et la dernière où se
  /// trouve le vrai problème. Le temps vient désormais d'un seul endroit,
  /// le ticker de [NexusShaderWidget].
  const NexusShaderState({
    required this.phase,
    required this.phaseProgress,
    required this.overallProgress,
    required this.seed,
    required this.colorSignature,
    required this.intensity,
  });

  final NexusPhase phase;
  final double phaseProgress;
  final double overallProgress;
  final String seed;
  final int colorSignature;
  final double intensity;

  /// État « éteint » : le shader ne produit qu'un fond sombre.
  static const NexusShaderState idle = NexusShaderState(
    phase: NexusPhase.idle,
    phaseProgress: 0,
    overallProgress: 0,
    seed: '',
    colorSignature: 0xFF0A84FF,
    intensity: 0,
  );
}

// ── Painter ──────────────────────────────────────────────────────────────────

/// CustomPainter qui dessine le résultat du shader Nexus.
///
/// Utilisé comme `foregroundPainter` par-dessus le contenu de l'app,
/// ou comme `painter` dans un `Stack` avec un fond noir.
class NexusShaderPainter extends CustomPainter {
  NexusShaderPainter({
    required this.shader,
    required this.state,
    required this.time,
    required Listenable repaint,
  })  : _seed = _seedToVec4(state.seed),
        _color = _colorToVec4(state.colorSignature),
        super(repaint: repaint);

  final ui.FragmentShader shader;
  final NexusShaderState state;

  /// Le temps de l'animation, lu à CHAQUE peinture.
  ///
  /// ⚠️ Il ne vient pas de [state]. Le painter est repeint par son
  /// `repaint` Listenable sans que le widget soit reconstruit : s'il
  /// lisait le temps dans l'objet d'état figé à la construction, il
  /// repeindrait indéfiniment la même image et l'animation serait
  /// parfaitement immobile.
  final ValueListenable<double> time;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    final s = state;

    // ── Les uniformes doivent correspondre EXACTEMENT à l'ordre de
    // déclaration dans nexus.frag. C'est une liste positionnelle,
    // pas nommée : intervertir deux valeurs produit un résultat
    // visuellement absurde et très difficile à diagnostiquer.
    shader
      ..setFloat(0, size.width) // uSize.x
      ..setFloat(1, size.height) // uSize.y
      ..setFloat(2, time.value) // uTime
      ..setFloat(3, s.phase.index.toDouble()) // uPhase
      ..setFloat(4, s.phaseProgress) // uPhaseProgress
      ..setFloat(5, s.overallProgress) // uOverallProgress
      // uSeed (vec4) — décomposé en 4 floats
      ..setFloat(6, _seed[0]) // uSeed.x
      ..setFloat(7, _seed[1]) // uSeed.y
      ..setFloat(8, _seed[2]) // uSeed.z
      ..setFloat(9, _seed[3]) // uSeed.w
      // uColor (vec4) — décomposé en 4 floats
      ..setFloat(10, _color[0]) // uColor.x
      ..setFloat(11, _color[1]) // uColor.y
      ..setFloat(12, _color[2]) // uColor.z
      ..setFloat(13, _color[3]) // uColor.w
      ..setFloat(14, s.intensity); // uIntensity
    // ⚠️ PAS DE 16ᵉ UNIFORME. `uDpr` a été retiré du shader (il servait à
    // une normalisation fautive des coordonnées, voir `nexus.frag`). La
    // liste est POSITIONNELLE : écrire un index que le shader ne déclare
    // pas lève une exception à la première image.

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant NexusShaderPainter oldDelegate) {
    return oldDelegate.state != state || oldDelegate.shader != shader;
  }

  /// La seed et la couleur, converties UNE FOIS à la construction.
  ///
  /// ⚠️ C'étaient des `get` qui reconstruisaient leur liste à chaque
  /// lecture — et chacune était lue quatre fois par image. Cela faisait
  /// huit listes allouées et seize analyses hexadécimales par image, pour
  /// des valeurs qui ne changent JAMAIS pendant une séquence.
  final List<double> _seed;
  final List<double> _color;

  /// Convertit la seed hexadécimale en 4 floats pseudo-aléatoires.
  ///
  /// ⚠️ `tryParse`, PAS `parse`. Cette chaîne peut venir du réseau : c'est
  /// le pair d'en face qui l'envoie dans son `NexusEvent`. Un appareil
  /// buggé — ou malveillant — qui émet autre chose que de l'hexadécimal
  /// faisait lever une exception DANS LA BOUCLE DE PEINTURE, soit soixante
  /// fois par seconde, sur un écran devenu rouge. Une animation
  /// décorative ne doit jamais pouvoir faire tomber l'application.
  static List<double> _seedToVec4(String seed) {
    if (seed.length < 8) return const [0.5, 0.5, 0.5, 0.5];
    double octet(int index) {
      final valeur = int.tryParse(seed.substring(index, index + 2), radix: 16);
      return (valeur ?? 128) / 255.0;
    }

    return [octet(0), octet(2), octet(4), octet(6)];
  }

  /// Convertit une couleur ARGB en 4 floats RGBA normalisés.
  static List<double> _colorToVec4(int c) {
    return [
      ((c >> 16) & 0xFF) / 255.0,
      ((c >> 8) & 0xFF) / 255.0,
      (c & 0xFF) / 255.0,
      ((c >> 24) & 0xFF) / 255.0,
    ];
  }
}

// ── Widget ───────────────────────────────────────────────────────────────────

/// Widget qui dessine le shader Nexus en continu.
///
/// Crée son propre ticker pour alimenter le shader à chaque image.
/// Le shader ne tourne que tant que [active] est vrai.
class NexusShaderWidget extends StatefulWidget {
  const NexusShaderWidget({
    super.key,
    required this.state,
    this.active = true,
    this.onUnavailable,
  });

  final NexusShaderState state;
  final bool active;

  /// Appelé si le shader ne peut pas être compilé sur cet appareil.
  ///
  /// Sans ce signal, l'échec est SILENCIEUX : le widget rend une boîte
  /// vide, l'overlay reste noir pendant huit secondes, et rien nulle part
  /// ne dit pourquoi. C'est ce qui rendait la panne si difficile à
  /// diagnostiquer.
  final VoidCallback? onUnavailable;

  @override
  State<NexusShaderWidget> createState() => _NexusShaderWidgetState();
}

class _NexusShaderWidgetState extends State<NexusShaderWidget>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  late final Ticker _ticker;

  /// Le temps, publié comme `Listenable` plutôt que par `setState`.
  ///
  /// ⚠️ C'EST LA DIFFÉRENCE ENTRE 60 IMAGES PAR SECONDE ET UNE ANIMATION
  /// QUI RAME. La version précédente appelait `setState` à chaque image :
  /// Flutter reconstruisait alors tout le sous-arbre, comparait les
  /// widgets, recréait le painter — soixante fois par seconde, pour ne
  /// changer qu'un seul nombre. Un `ValueNotifier` passé en `repaint` au
  /// `CustomPainter` saute entièrement les phases de construction et de
  /// disposition : Flutter ne refait que la PEINTURE, ce qui est
  /// exactement ce dont on a besoin.
  final ValueNotifier<double> _time = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      _time.value = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
    });
    _initShader();
  }

  Future<void> _initShader() async {
    final program = await NexusShaderLoader.load();
    if (!mounted) return;
    if (program == null) {
      // Shader indisponible (compilation refusée, appareil sans Impeller).
      // On le signale à l'écran parent pour qu'il puisse jouer la version
      // sans shader plutôt que d'attendre une image qui ne viendra pas.
      widget.onUnavailable?.call();
      return;
    }
    setState(() => _shader = program.fragmentShader());
    if (widget.active) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant NexusShaderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_ticker.isActive && _shader != null) {
      _ticker.start();
    } else if (!widget.active && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _time.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (shader == null || !widget.active) {
      return const SizedBox.shrink();
    }

    return RepaintBoundary(
      child: CustomPaint(
        painter: NexusShaderPainter(
          shader: shader,
          state: widget.state,
          time: _time,
          repaint: _time,
        ),
        size: Size.infinite,
      ),
    );
  }
}


