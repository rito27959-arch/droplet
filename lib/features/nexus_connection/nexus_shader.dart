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
  const NexusShaderState({
    required this.time,
    required this.phase,
    required this.phaseProgress,
    required this.overallProgress,
    required this.seed,
    required this.colorSignature,
    required this.intensity,
  });

  final double time;
  final NexusPhase phase;
  final double phaseProgress;
  final double overallProgress;
  final String seed;
  final int colorSignature;
  final double intensity;

  /// État « éteint » : le shader ne produit qu'un fond sombre.
  static const NexusShaderState idle = NexusShaderState(
    time: 0,
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
  }) : super(repaint: null);

  final ui.FragmentShader shader;
  final NexusShaderState state;

  @override
  void paint(Canvas canvas, Size size) {
    final program = NexusShaderLoader.program;
    if (program == null) return;

    final s = state;

    // ── Les uniformes doivent correspondre EXACTEMENT à l'ordre de
    // déclaration dans nexus.frag. C'est une liste positionnelle,
    // pas nommée : intervertir deux valeurs produit un résultat
    // visuellement absurde et très difficile à diagnostiquer.
    shader
      ..setFloat(0, size.width) // uSize.x
      ..setFloat(1, size.height) // uSize.y
      ..setFloat(2, s.time) // uTime
      ..setFloat(3, s.phase.index.toDouble()) // uPhase
      ..setFloat(4, s.phaseProgress) // uPhaseProgress
      ..setFloat(5, s.overallProgress) // uOverallProgress
      // uSeed (vec4) — décomposé en 4 floats
      ..setFloat(6, _seedVec4[0]) // uSeed.x
      ..setFloat(7, _seedVec4[1]) // uSeed.y
      ..setFloat(8, _seedVec4[2]) // uSeed.z
      ..setFloat(9, _seedVec4[3]) // uSeed.w
      // uColor (vec4) — décomposé en 4 floats
      ..setFloat(10, _colorVec4[0]) // uColor.x
      ..setFloat(11, _colorVec4[1]) // uColor.y
      ..setFloat(12, _colorVec4[2]) // uColor.z
      ..setFloat(13, _colorVec4[3]) // uColor.w
      ..setFloat(14, s.intensity) // uIntensity
      ..setFloat(15, WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio); // uDpr

    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Paint()..shader = shader,
    );
  }

  @override
  bool shouldRepaint(covariant NexusShaderPainter oldDelegate) {
    return true;
  }

  /// Convertit la seed hexadécimale en 4 floats pseudo-aléatoires.
  List<double> get _seedVec4 {
    final seed = state.seed;
    if (seed.length < 8) return [0.5, 0.5, 0.5, 0.5];
    return [
      int.parse(seed.substring(0, 2), radix: 16) / 255.0,
      int.parse(seed.substring(2, 4), radix: 16) / 255.0,
      int.parse(seed.substring(4, 6), radix: 16) / 255.0,
      int.parse(seed.substring(6, 8), radix: 16) / 255.0,
    ];
  }

  /// Convertit une couleur ARGB en 4 floats RGBA normalisés.
  List<double> get _colorVec4 {
    final c = state.colorSignature;
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
  });

  final NexusShaderState state;
  final bool active;

  @override
  State<NexusShaderWidget> createState() => _NexusShaderWidgetState();
}

class _NexusShaderWidgetState extends State<NexusShaderWidget>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;
  late final Ticker _ticker;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      _time = elapsed.inMilliseconds / 1000.0;
      setState(() {});
    });
    _initShader();
  }

  Future<void> _initShader() async {
    final program = await NexusShaderLoader.load();
    if (!mounted || program == null) return;
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
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (shader == null || !widget.active) {
      return const SizedBox.shrink();
    }

    // On override le temps du state avec notre ticker pour une
    // animation fluide et indépendante.
    final state = NexusShaderState(
      time: _time,
      phase: widget.state.phase,
      phaseProgress: widget.state.phaseProgress,
      overallProgress: widget.state.overallProgress,
      seed: widget.state.seed,
      colorSignature: widget.state.colorSignature,
      intensity: widget.state.intensity,
    );

    return RepaintBoundary(
      child: CustomPaint(
        painter: NexusShaderPainter(
          shader: shader,
          state: state,
        ),
        size: Size.infinite,
      ),
    );
  }
}


