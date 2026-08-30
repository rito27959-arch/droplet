// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est l'écran plein écran d'un appel vocal 1:1 — le fameux « écran
// d'appel » qu'on connaît de WhatsApp/FaceTime : le nom du contact,
// l'avatar au centre entouré d'anneaux animés, la durée de l'appel qui
// défile, et en bas les gros boutons ronds (micro, haut-parleur, caméra,
// raccrocher). Beaucoup de petites animations séparées se combinent
// autour de l'avatar central pour donner l'impression que « quelque
// chose se passe » :
//
//   - `_OrbitRing` : pendant que ça sonne/se connecte, un anneau avec
//     une petite comète qui tourne autour, comme une orbite.
//   - `_PulseRing` : une fois connecté, des ondes qui s'élargissent en
//     boucle, comme des ronds dans l'eau.
//   - `_ConnectingDots` : les trois petits points qui rebondissent en
//     escalier pendant la connexion.
//   - `_RoundControl` : chacun des gros boutons ronds du bas.
//
// La vraie voix et la vraie connexion sont gérées ailleurs (voir
// `webrtc_call_service.dart` et `mesh_provider.dart`) — ce fichier ne
// s'occupe QUE de l'affichage.
// ============================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/mesh_message.dart';
import '../../core/providers/mesh_provider.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/droplet_logo.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../design_system/glassmorphism.dart';

class CallScreen extends ConsumerStatefulWidget {
  const CallScreen({super.key, required this.peerId});
  final String peerId;

  @override
  ConsumerState<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends ConsumerState<CallScreen>
    with SingleTickerProviderStateMixin {
  bool _started = false;
  bool _exiting = false;
  Timer? _timer;
  int _elapsed = 0;

  late final AnimationController _breath;

  @override
  void initState() {
    super.initState();
    _breath = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat(reverse: true);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startIfNeeded());
  }

  void _startIfNeeded() {
    if (_started) return;
    _started = true;
    final call = ref.read(callProvider);
    if (call.isCallActive && call.peerId == widget.peerId) {
      // Déjà actif (appel entrant accepté) : on ne relance pas.
      _startTimerIfConnected();
      return;
    }
    final pseudo = ref.read(peerPseudoProvider(widget.peerId));
    ref.read(callProvider.notifier).startCall(widget.peerId, pseudo);
  }

  void _startTimerIfConnected() {
    final call = ref.read(callProvider);
    if (call.connectionState == CallConnectionState.connected) {
      _timer?.cancel();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        setState(() => _elapsed++);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _breath.dispose();
    super.dispose();
  }

  String _formatElapsed(int s) {
    final m = s ~/ 60;
    final sec = s % 60;
    return '${m.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  String _statusText(CallState call) {
    switch (call.connectionState) {
      case CallConnectionState.connecting:
        return call.direction == CallDirection.outgoing
            ? 'Appel en cours…'
            : 'Appel entrant…';
      case CallConnectionState.connected:
        return _formatElapsed(_elapsed);
      case CallConnectionState.failed:
        return 'Appel impossible';
      case CallConnectionState.disconnected:
        return 'Appel terminé';
    }
  }

  Color _statusColor(CallState call) {
    switch (call.connectionState) {
      case CallConnectionState.connected:
        return OuroColors.successGreen;
      case CallConnectionState.failed:
        return OuroColors.errorRed;
      case CallConnectionState.disconnected:
        return OuroColors.callSecondaryLabel;
      default:
        return OuroColors.callSecondaryLabel;
    }
  }

  void _handleHangUp() {
    HapticFeedback.heavyImpact();
    setState(() => _exiting = true);
    ref.read(callProvider.notifier).hangUp();
    // Petit fondu de sortie plutôt qu'un context.go sec — cohérent avec les
    // transitions déjà soignées du reste de cet écran (_OrbitRing, _PulseRing).
    Future.delayed(const Duration(milliseconds: 220), () {
      if (mounted) context.go('/chats');
    });
  }

  @override
  Widget build(BuildContext context) {
    final call = ref.watch(callProvider);
    final pseudo = ref.watch(peerPseudoProvider(widget.peerId));
    final connecting =
        call.connectionState == CallConnectionState.connecting && call.isCallActive;
    final connected = call.connectionState == CallConnectionState.connected;

    if (connected && _timer == null) _startTimerIfConnected();
    if (!connected && _timer != null) {
      _timer?.cancel();
      _timer = null;
    }

    final audioBump = 1.0 + (call.audioLevel * 0.15).clamp(0.0, 0.2);

    return Scaffold(
      // Noir fixe, même en mode clair — voir `OuroColors.callBackground`.
      backgroundColor: OuroColors.callBackground,
      body: AnimatedOpacity(
        opacity: _exiting ? 0 : 1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: AnimatedScale(
        scale: _exiting ? 0.94 : 1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: Stack(
        fit: StackFit.expand,
        children: [
          // Fond noir uni. L'ancienne version posait un halo bleu radial
          // derrière l'appel : sur un écran qu'on regarde parfois plusieurs
          // minutes d'affilée, un fond coloré fatigue et écrase le contraste
          // du nom affiché. L'écran d'appel d'iOS est intégralement noir.
          const ColoredBox(color: OuroColors.callBackground),
          Positioned.fill(
            child: DropletRipples(active: connecting || connected),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 16),
                // Indication du chemin réseau, réduite à une seule ligne de
                // texte gris centrée. Les deux étiquettes colorées
                // précédentes se disputaient l'attention avec le nom de la
                // personne appelée, qui est la seule information importante
                // de cet écran.
                const _RouteLabel(),
                const Spacer(flex: 2),
                AnimatedBuilder(
                  animation: _breath,
                  builder: (context, _) {
                    final b = Curves.easeInOut.transform(_breath.value);
                    final s = audioBump * (1.0 + b * 0.07);
                    return Transform.scale(
                      scale: s,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (connecting)
                            _OrbitRing(size: 220)
                          else if (connected)
                            _PulseRing(size: 220),
                          if (connecting || connected)
                            const DropletLogo(radius: 78, glow: true, animate: true),
                          Hero(
                            tag: 'avatar-${widget.peerId}',
                            child: PeerAvatar(pseudo: pseudo, radius: 62, online: connecting || connected),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 32),
                Semantics(
                  label: 'Appel avec $pseudo',
                  child: Text(
                    pseudo,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: OuroColors.callLabel,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Semantics(
                    label: 'Statut de l\'appel: ${_statusText(call)}',
                    child: Row(
                      key: ValueKey(_statusText(call)),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (call.connectionState == CallConnectionState.failed) ...[
                          Icon(Icons.error_outline_rounded, size: 16, color: _statusColor(call)),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          _statusText(call),
                          style: TextStyle(
                            fontSize: 16,
                            color: _statusColor(call),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (connecting) ...[
                  const SizedBox(height: 14),
                  const _ConnectingDots(),
                ],
                const Spacer(flex: 2),
                OuroCard(
                  padding: EdgeInsets.zero,
                  child: _CallControls(
                    call: call,
                    onToggleMute: () => ref.read(callProvider.notifier).toggleMute(),
                    onToggleSpeaker: () => ref.read(callProvider.notifier).toggleSpeaker(),
                    onToggleVideo: () => ref.read(callProvider.notifier).toggleVideo(),
                    onHangUp: _handleHangUp,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ],
        ),
        ),
      ),
    );
  }
}

/// Une des petites étiquettes en haut à droite (« mesh », « BLE ») qui
/// indique par quel chemin l'appel passe.
/// Rappel discret que l'appel passe par le réseau mesh et non par un
/// opérateur — une seule ligne grise, centrée, sans encadré ni couleur.
class _RouteLabel extends StatelessWidget {
  const _RouteLabel();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.space2),
      child: Text(
        'Réseau mesh',
        style: OuroTypography.footnote.copyWith(
          color: OuroColors.callSecondaryLabel,
        ),
      ),
    );
  }
}

/// La rangée des 4 boutons ronds du bas : couper le micro, activer le
/// haut-parleur, activer la caméra, raccrocher.
class _CallControls extends StatelessWidget {
  const _CallControls({
    required this.call,
    required this.onToggleMute,
    required this.onToggleSpeaker,
    required this.onToggleVideo,
    required this.onHangUp,
  });

  final CallState call;
  final VoidCallback onToggleMute;
  final VoidCallback onToggleSpeaker;
  final VoidCallback onToggleVideo;
  final VoidCallback onHangUp;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundControl(
          icon: call.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
          color: call.isMuted ? OuroColors.ouroOrange : OuroColors.callControl,
          onTap: onToggleMute,
          semanticLabel: call.isMuted ? 'Activer le micro' : 'Couper le micro',
        ),
        _RoundControl(
          icon: call.isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          color: call.isSpeakerOn ? OuroColors.meshBlue : OuroColors.callControl,
          onTap: onToggleSpeaker,
          semanticLabel: call.isSpeakerOn ? 'Désactiver le haut-parleur' : 'Activer le haut-parleur',
        ),
        _RoundControl(
          icon: Icons.videocam_rounded,
          color: call.isVideoEnabled ? OuroColors.meshBlue : OuroColors.callControl,
          onTap: onToggleVideo,
          semanticLabel: call.isVideoEnabled ? 'Désactiver la caméra' : 'Activer la caméra',
        ),
        _RoundControl(
          icon: Icons.call_end_rounded,
          color: OuroColors.errorRed,
          onTap: onHangUp,
          semanticLabel: 'Raccrocher',
          // _handleHangUp déclenche déjà son propre haptique (heavyImpact,
          // plus marqué pour une action irréversible) — pas de doublon ici.
          haptic: false,
        ),
      ],
    );
  }
}

/// UN SEUL bouton rond de contrôle d'appel — change de couleur selon
/// qu'il est activé ou non, avec une petite rotation au moment du tap.
class _RoundControl extends StatefulWidget {
  const _RoundControl({
    required this.icon,
    required this.color,
    required this.onTap,
    this.haptic = true,
    this.semanticLabel,
  });

  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool haptic;
  final String? semanticLabel;

  @override
  State<_RoundControl> createState() => _RoundControlState();
}

class _RoundControlState extends State<_RoundControl> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // ⚠️ PAS DE RIPPLE ICI.
    //
    // Ce bouton passait par `Material` + `InkWell` pour obtenir l'onde
    // qui se propage au toucher. C'est LA signature d'Android, et elle
    // était posée sur l'écran d'appel — celui qu'on regarde le plus
    // longtemps sans rien faire d'autre.
    //
    // iOS ne propage rien : le bouton S'ENFONCE — il rapetisse d'un
    // cheveu et s'assombrit — puis revient. La réponse est immédiate et
    // part du doigt, au lieu de se répandre depuis lui.
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        setState(() => _pressed = false);
        if (widget.haptic) HapticFeedback.selectionClick();
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.92 : 1,
        duration: DesignTokens.durationFast,
        curve: DesignTokens.curveSpring,
        child: Semantics(
          button: true,
          label: widget.semanticLabel,
          child: AnimatedOpacity(
            opacity: _pressed ? 0.7 : 1,
            duration: DesignTokens.durationFast,
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.color,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Center(
                child: Icon(widget.icon, color: Colors.white, size: 26),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Anneau orbital en rotation avec satellites, affiché pendant la connexion.
class _OrbitRing extends StatefulWidget {
  const _OrbitRing({required this.size});
  final double size;

  @override
  State<_OrbitRing> createState() => _OrbitRingState();
}

class _OrbitRingState extends State<_OrbitRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _OrbitPainter(t: _controller.value),
        ),
      ),
    );
  }
}

class _OrbitPainter extends CustomPainter {
  _OrbitPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 14;

    // Cercle principal
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = OuroColors.meshBlue.withValues(alpha: 0.35);
    canvas.drawCircle(center, radius, ring);

    // Segment lumineux qui tourne (comète)
    final cometAngle = t * 2 * math.pi;
    final comet = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: cometAngle - 0.9,
        endAngle: cometAngle + 0.3,
        colors: [
          Colors.transparent,
          OuroColors.meshBlueBright.withValues(alpha: 0.9),
        ],
        transform: GradientRotation(cometAngle),
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, comet);

    // 3 satellites en orbite (espacement 120°)
    for (int i = 0; i < 3; i++) {
      final angle = cometAngle + i * (2 * math.pi / 3);
      final px = center.dx + math.cos(angle) * radius;
      final py = center.dy + math.sin(angle) * radius;
      final dot = Paint()..color = OuroColors.accentTeal;
      canvas.drawCircle(Offset(px, py), 4, dot);
      final halo = Paint()
        ..color = OuroColors.accentTeal.withValues(alpha: 0.35);
      canvas.drawCircle(Offset(px, py), 8, halo);
    }
  }

  @override
  bool shouldRepaint(covariant _OrbitPainter oldDelegate) => oldDelegate.t != t;
}

/// Anneau de pulsation douce quand l'appel est connecté.
class _PulseRing extends StatefulWidget {
  const _PulseRing({required this.size});
  final double size;

  @override
  State<_PulseRing> createState() => _PulseRingState();
}

class _PulseRingState extends State<_PulseRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) => CustomPaint(
          painter: _PulseRingPainter(t: _controller.value),
        ),
      ),
    );
  }
}

class _PulseRingPainter extends CustomPainter {
  _PulseRingPainter({required this.t});
  final double t;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    for (int i = 0; i < 3; i++) {
      final phase = ((t - i * 0.33) % 1.0 + 1.0) % 1.0;
      final radius = (size.width / 2 - 10) * Curves.easeOut.transform(phase);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = OuroColors.successGreen.withValues(alpha: (1 - phase) * 0.4);
      canvas.drawCircle(center, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _PulseRingPainter oldDelegate) => oldDelegate.t != t;
}

/// Trois points pulsants en escalier pendant la connexion.
class _ConnectingDots extends StatefulWidget {
  const _ConnectingDots();

  @override
  State<_ConnectingDots> createState() => _ConnectingDotsState();
}

class _ConnectingDotsState extends State<_ConnectingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final phase = ((_controller.value - i * 0.2) % 1.0 + 1.0) % 1.0;
            final p = Curves.easeOut.transform(phase < 0.5 ? phase : 1 - phase);
            final s = 0.6 + p * 0.8;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Transform.scale(
                scale: s,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: OuroColors.meshBlueBright.withValues(alpha: 0.4 + p * 0.6),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
