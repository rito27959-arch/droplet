import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart' show Ticker;

/// Overlay plein écran qui révèle le nouveau thème comme le fait Telegram.
///
/// ── LA TECHNIQUE DE TELEGRAM ─────────────────────────────────────────
///
/// Telegram ne repeint pas simplement l'écran dans le nouveau thème : il
/// capture d'abord l'écran ACTUEL (un instantané), change le thème
/// dessous, puis « perce » l'instantané par un trou circulaire qui
/// s'agrandit depuis le point de tap. Ce qu'on voit traverser le trou,
/// c'est le NOUVEAU thème déjà en place.
///
///  1. On capture l'écran courant en image (via un RepaintBoundary).
///  2. On change le thème — le vrai contenu reprend vie EN DESSOUS.
///  3. On pose l'instantané PAR-DESSUS, et on ouvre un cercle
///     (BlendMode.dstOut) qui grandit depuis le tap.
///  4. Quand le cercle couvre tout, on retire l'instantané.
///
/// Résultat : pendant la transition, l'ancien contenu reste visible et
/// se fait « ronger » par le nouveau thème — exactement l'effet
/// Telegram, sans écran blanc/noir vide.
///
/// ⚠️ LE SEUL DÉFI EST LE MOMENT DE LA CAPTURE. Le changement de thème
/// (via `ValueKey(brightness)` dans main.dart) reconstruit tout l'arbre
/// et invalide le contexte. La capture doit donc se faire AVANT
/// `set()`. C'est le rôle de [capture] : il prend l'image, puis on
/// change le thème, puis on appelle [showWithImage].
class ModeTransitionOverlay {
  static OverlayEntry? _entry;
  static Ticker? _ticker;
  static ui.Image? _snapshot;

  static GlobalKey? _repaintBoundaryKey;

  /// Le repaint boundary à capturer. Mis par la racine de l'app.
  static GlobalKey get repaintBoundaryKey =>
      _repaintBoundaryKey ??= GlobalKey();

  /// Capture l'écran courant en image.
  ///
  /// Appeler AVANT de changer le thème. Renvoie l'image, ou `null` si la
  /// capture a échoué (auquel cas on peut passer à un simple cercle
  /// plein en remplacement).
  static Future<ui.Image?> capture() async {
    final boundaryKey = _repaintBoundaryKey;
    if (boundaryKey == null) return null;
    final context = boundaryKey.currentContext;
    if (context == null) return null;

    final boundary =
        context.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) return null;

    // Forcer une frame pour s'assurer que la couche est peinte.
    // Timeout court : si la frame ne vient pas, on passe à un
    // cercle plein plutôt que de bloquer le changement de thème.
    try {
      await WidgetsBinding.instance.endOfFrame
          .timeout(const Duration(milliseconds: 500));
    } catch (_) {}

    try {
      final image = await boundary.toImage(pixelRatio: 1.0);
      return image;
    } catch (_) {
      return null;
    }
  }

  /// Lance l'animation Telegram depuis [tapPosition].
  ///
  /// ⚠️ IMPORTANT : appeler AVANT de modifier le thème avec [capture]
  /// pré-capturée via [showWithImage]. Si le thème change avant l'appel,
  /// le contexte peut être invalidé.
  static void show(BuildContext context, Offset tapPosition, {required bool toDark}) {
    dismiss();

    final overlay = Overlay.of(context);
    final screenSize = MediaQuery.of(context).size;
    _run(overlay, tapPosition, toDark: toDark, screenSize: screenSize);
  }

  /// Version « brute » utilisée quand le thème a déjà changé et le
  /// contexte est potentiellement invalidé. On passe l'overlay, la
  /// taille d'écran et l'image de l'écran précédent (pré-capturée).
  ///
  /// [previousImage] peut être `null` : dans ce cas on retombe sur un
  /// simple cercle plein (économie d'écran blanc/noir vide).
  static void showWithImage(
    OverlayState overlay,
    Offset tapPosition,
    ui.Image? previousImage, {
    required bool toDark,
    required Size screenSize,
  }) {
    dismiss();
    _run(overlay, tapPosition,
        toDark: toDark,
        screenSize: screenSize,
        previousImage: previousImage);
  }

  /// Alias rétro-compatible de [showWithImage] sans image.
  static void showRaw(
    OverlayState overlay,
    Offset tapPosition, {
    required bool toDark,
    required Size screenSize,
  }) {
    showWithImage(overlay, tapPosition, null,
        toDark: toDark, screenSize: screenSize);
  }

  static void _run(
    OverlayState overlay,
    Offset tapPosition, {
    required bool toDark,
    required Size screenSize,
    ui.Image? previousImage,
  }) {
    final maxRadius = math.sqrt(
      screenSize.width * screenSize.width +
      screenSize.height * screenSize.height,
    );

    final completer = _AnimationCompleter();
    _ticker = Ticker((elapsed) {
      final t = (elapsed.inMilliseconds / 650.0).clamp(0.0, 1.0);
      completer.update(t);
      if (t >= 1.0) {
        _ticker?.stop();
        dismiss();
      }
    });

    _entry = OverlayEntry(
      builder: (_) => _ModeTransitionWidget(
        completer: completer,
        center: tapPosition,
        maxRadius: maxRadius,
        previousImage: previousImage,
        screenSize: screenSize,
        toDark: toDark,
      ),
    );

    overlay.insert(_entry!);
    _ticker!.start();
  }

  /// Retire l'overlay immédiatement.
  static void dismiss() {
    _ticker?.stop();
    _ticker?.dispose();
    _ticker = null;
    _entry?.remove();
    _entry = null;
    _snapshot?.dispose();
    _snapshot = null;
  }
}

/// État partagé entre le ticker et le widget d'animation.
class _AnimationCompleter extends ChangeNotifier {
  double _value = 0.0;

  double get value => _value;

  void update(double t) {
    if (_value != t) {
      _value = t;
      notifyListeners();
    }
  }
}

class _ModeTransitionWidget extends StatelessWidget {
  const _ModeTransitionWidget({
    required this.completer,
    required this.center,
    required this.maxRadius,
    required this.previousImage,
    required this.screenSize,
    required this.toDark,
  });

  final _AnimationCompleter completer;
  final Offset center;
  final double maxRadius;
  final ui.Image? previousImage;
  final Size screenSize;
  final bool toDark;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: completer,
      builder: (context, _) {
        final t = completer.value;
        // Easing cubique : expansion rapide au début, freinage en fin —
        // le même que Telegram (CubicBezierInterpolator).
        final eased = 1 - math.pow(1 - t, 3).toDouble();
        final radius = maxRadius * eased;

        // Opacité : plein pendant l'expansion, léger fondu à la toute fin
        // pour fondre proprement avec le contenu désormais en place.
        final opacity = t < 0.92 ? 1.0 : ((1 - t) / 0.08).clamp(0.0, 1.0);

        return Positioned.fill(
          child: Opacity(
            opacity: opacity,
            child: CustomPaint(
              painter: _TelegramRevealPainter(
                center: center,
                radius: radius,
                previousImage: previousImage,
                screenSize: screenSize,
                toDark: toDark,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Peint l'ancien écran, percé d'un trou circulaire qui laisse voir le
/// nouveau thème. Technique Telegram : l'instantané est dessiné avec
/// `BlendMode.dstOut` sur le trou, de sorte que le cercle « enlève »
/// l'ancien contenu et révèle ce qui se trouve en dessous.
class _TelegramRevealPainter extends CustomPainter {
  _TelegramRevealPainter({
    required this.center,
    required this.radius,
    required this.previousImage,
    required this.screenSize,
    required this.toDark,
  });

  final Offset center;
  final double radius;
  final ui.Image? previousImage;
  final Size screenSize;
  final bool toDark;

  @override
  void paint(Canvas canvas, Size size) {
    // Fond : si on n'a pas d'instantané, on pose un cercle plein de la
    // couleur cible (l'ancien comportement) pour ne jamais laisser voir
    // un trou vide.
    final snapshot = previousImage;
    if (snapshot == null) {
      final color = toDark ? Colors.black : Colors.white;
      canvas.drawCircle(center, radius, Paint()..color = color);
      return;
    }

    // Règle de composition : on peint l'instantané de l'écran précédent
    // dans le calque, PUIS on « enlève » un cercle (dstOut) qui grandit.
    // Ce qui reste de l'instantané est l'anneau autour du cercle ; ce qui
    // transparaît au centre est le nouveau thème déjà dessiné en dessous.
    canvas.saveLayer(Offset.zero & size, Paint());

    canvas.drawImageRect(
      snapshot,
      Rect.fromLTWH(0, 0, snapshot.width.toDouble(), snapshot.height.toDouble()),
      Rect.fromLTWH(0, 0, screenSize.width, screenSize.height),
      Paint(),
    );

    // Le trou : dstOut = « garde ce qui n'est PAS traversé par ce cercle ».
    // Le bord est adouci par un léger flou pour éviter un liseré dur.
    final mask = Paint()
      ..blendMode = BlendMode.dstOut
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 0.5);

    canvas.drawCircle(center, radius, mask);

    canvas.restore();
  }

  @override
  bool shouldRepaint(_TelegramRevealPainter old) =>
      center != old.center ||
      radius != old.radius ||
      previousImage != old.previousImage ||
      screenSize != old.screenSize ||
      toDark != old.toDark;
}
