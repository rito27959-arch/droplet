// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Comme iMessage (qui fait « trembler » un message envoyé avec force,
// ou le rend invisible jusqu'à ce qu'on le frotte du doigt) ou Telegram
// (qui peut faire pleuvoir des confettis en plein écran), Droplet permet
// d'attacher un petit « effet spécial » à un message qu'on envoie. Ce
// fichier définit la LISTE de tous ces effets possibles, et sait
// comment les JOUER quand un message qui en porte un s'affiche.
//
// Deux familles d'effets :
//   - Les effets « plein écran » (confettis, cœurs, feu d'artifice) qui
//     recouvrent tout l'écran un court instant.
//   - Les effets « sur la bulle » (le message tremble fort, s'agrandit,
//     apparaît en douceur, ou reste caché jusqu'à ce qu'on le touche) —
//     ceux-là sont gérés directement dans `chat_screen.dart`, ce fichier
//     se contente de définir leurs noms.
//
// Le feu d'artifice est le seul effet vraiment nouveau ici — les
// confettis et les cœurs réutilisent les mêmes animations déjà écrites
// dans `confetti_overlay.dart` et `heart_burst_overlay.dart`, pour ne
// pas refaire deux fois le même travail.
// ============================================================================

import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../design_system/ouro_colors.dart';
import 'confetti_overlay.dart';
import 'heart_burst_overlay.dart';

/// Clés d'effets de message façon Telegram (plein écran)/iMessage (bulle).
/// Transportées par [MeshMessage.effect] — voir ce champ pour le contexte.
const kEffectSlam = 'slam';
const kEffectLoud = 'loud';
const kEffectGentle = 'gentle';
const kEffectInvisibleInk = 'invisible_ink';
const kEffectConfetti = 'confetti';
const kEffectFireworks = 'fireworks';
const kEffectHearts = 'hearts';

/// Effets qui se jouent en overlay plein écran (vs. sur la bulle elle-même).
const kFullscreenEffects = {kEffectConfetti, kEffectFireworks, kEffectHearts};

/// Effets qui se jouent directement sur la bulle de message.
const kBubbleEffects = {kEffectSlam, kEffectLoud, kEffectGentle, kEffectInvisibleInk};

/// Déclenche un effet plein écran choisi explicitement par l'expéditeur, via
/// un [OverlayEntry] auto-supprimé — pas une route/dialog, pour ne jamais
/// interrompre la saisie en cours dans `chat_screen.dart`.
///
/// Confettis et cœurs réutilisent les overlays déjà existants et éprouvés
/// ([ConfettiOverlay] — déclenchement par mots-clés, [HeartBurstOverlay] —
/// réaction ❤️ partagée) plutôt que de dupliquer un second système de
/// particules pour les mêmes effets visuels. Seul le feu d'artifice est
/// réellement nouveau.
class MessageEffectOverlay {
  MessageEffectOverlay._();

  /// Fait apparaître l'effet demandé par-dessus tout l'écran.
  static void play(BuildContext context, String effect) {
    switch (effect) {
      case kEffectConfetti:
        ConfettiOverlay.show(context);
      case kEffectHearts:
        HeartBurstOverlay.show(context);
      case kEffectFireworks:
        final overlayState = Overlay.of(context, rootOverlay: true);
        late OverlayEntry entry;
        entry = OverlayEntry(
          builder: (context) => _FireworksPlayer(onDone: () => entry.remove()),
        );
        overlayState.insert(entry);
    }
  }
}

/// Joue l'animation de feu d'artifice : plusieurs « bouquets »
/// d'étincelles qui explosent à des endroits différents de l'écran,
/// comme un vrai feu d'artifice vu de loin dans le ciel.
class _FireworksPlayer extends StatefulWidget {
  const _FireworksPlayer({required this.onDone});
  final VoidCallback onDone;

  @override
  State<_FireworksPlayer> createState() => _FireworksPlayerState();
}

class _FireworksPlayerState extends State<_FireworksPlayer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<_Spark> _sparks;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    _sparks = _generateSparks();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: 1800))
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed && !_done) {
          _done = true;
          widget.onDone();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Choisit 3 points d'explosion au hasard sur l'écran, et pour chacun,
  /// génère 22 petites étincelles qui partiront dans toutes les
  /// directions autour de ce point — comme un vrai bouquet de feu
  /// d'artifice qui éclate.
  List<_Spark> _generateSparks() {
    final rnd = math.Random();
    final colors = [
      OuroColors.ouroOrange, OuroColors.warningAmber, OuroColors.errorRed,
      OuroColors.accentPink, OuroColors.meshBlueBright,
    ];
    final bursts = List.generate(3, (_) => Offset(0.2 + rnd.nextDouble() * 0.6, 0.2 + rnd.nextDouble() * 0.35));
    final sparks = <_Spark>[];
    for (final center in bursts) {
      final burstColor = colors[rnd.nextInt(colors.length)];
      for (int i = 0; i < 22; i++) {
        final angle = (i / 22) * 2 * math.pi + rnd.nextDouble() * 0.2;
        final speed = 0.18 + rnd.nextDouble() * 0.14;
        sparks.add(_Spark(
          start: center,
          velocity: Offset(math.cos(angle) * speed, math.sin(angle) * speed),
          color: burstColor,
          size: 3 + rnd.nextDouble() * 2.5,
        ));
      }
    }
    return sparks;
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          size: MediaQuery.of(context).size,
          painter: _SparkFieldPainter(sparks: _sparks, t: _controller.value),
        ),
      ),
    );
  }
}

/// La fiche d'identité d'UNE SEULE étincelle : d'où elle part, dans
/// quelle direction et à quelle vitesse elle file, sa couleur, sa taille.
class _Spark {
  const _Spark({required this.start, required this.velocity, required this.color, required this.size});

  /// Position de départ, en fraction de l'écran (0..1).
  final Offset start;
  /// Vitesse initiale, en fraction d'écran par seconde de vie (0..1 de [t]).
  final Offset velocity;
  final Color color;
  final double size;
}

/// Dessine toutes les étincelles à chaque image : elles filent en ligne
/// droite mais retombent petit à petit à cause d'une fausse gravité
/// (comme un vrai feu d'artifice qui retombe), et s'estompent
/// progressivement sur le dernier tiers de leur courte vie.
class _SparkFieldPainter extends CustomPainter {
  _SparkFieldPainter({required this.sparks, required this.t});
  final List<_Spark> sparks;
  final double t;

  static const _gravity = 0.25;

  @override
  void paint(Canvas canvas, Size size) {
    // Un seul pinceau réutilisé pour les 66 étincelles : en fabriquer un
    // par étincelle et par image, c'était quatre mille objets jetables
    // par seconde à ramasser pour rien.
    final paint = Paint()..isAntiAlias = true;
    for (final s in sparks) {
      // Fondu en sortie sur le dernier tiers de la vie de l'étincelle.
      final opacity = t < 0.7 ? 1.0 : (1 - (t - 0.7) / 0.3).clamp(0.0, 1.0);
      if (opacity <= 0) continue;

      final dx = s.start.dx + s.velocity.dx * t;
      final dy = s.start.dy + s.velocity.dy * t + 0.5 * _gravity * t * t;
      final center = Offset(dx * size.width, dy * size.height);

      paint.color = s.color.withValues(alpha: opacity);
      canvas.drawCircle(center, s.size * (1 - t * 0.3).clamp(0.3, 1.0), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkFieldPainter oldDelegate) => oldDelegate.t != t;
}
