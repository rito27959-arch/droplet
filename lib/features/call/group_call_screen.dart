// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est l'écran d'un appel de GROUPE (voix uniquement, jusqu'à 4
// personnes — voir `group_webrtc_call_service.dart` pour comprendre
// pourquoi il y a une limite). Au lieu d'un seul gros avatar au centre
// comme dans l'appel 1:1, on a ici une petite grille de cartes, une par
// participant, chacune avec son propre halo qui pulse pendant qu'elle
// est connectée — pour montrer d'un coup d'œil qui parle réellement et
// qui est encore en train de se connecter.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/mesh_message.dart';
import '../../core/providers/mesh_provider.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_pressable.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/scene_animee.dart';

/// Écran d'appel de groupe — voix uniquement, grille de participants.
/// Expérimental : maillage WebRTC complet sans serveur, plafonné à
/// [GroupCallState] (voir `group_webrtc_call_service.dart` pour le détail).
class GroupCallScreen extends ConsumerWidget {
  const GroupCallScreen({super.key});

  Color _stateColor(GroupCallParticipantState state) {
    return switch (state) {
      GroupCallParticipantState.connecting => OuroColors.warningAmber,
      GroupCallParticipantState.connected => OuroColors.successGreen,
      GroupCallParticipantState.failed => OuroColors.errorRed,
      GroupCallParticipantState.disconnected => OuroColors.callSecondaryLabel,
    };
  }

  String _stateLabel(GroupCallParticipantState state) {
    return switch (state) {
      GroupCallParticipantState.connecting => 'Connexion…',
      GroupCallParticipantState.connected => 'En ligne',
      GroupCallParticipantState.failed => 'Échec',
      GroupCallParticipantState.disconnected => 'Déconnecté',
    };
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final call = ref.watch(groupCallProvider);

    return Scaffold(
      // Noir fixe, même en mode clair — voir `OuroColors.callBackground`.
      backgroundColor: OuroColors.callBackground,
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 16),
            Text(call.groupName ?? 'Appel de groupe',
                style: TextStyle(color: OuroColors.callLabel, fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('${call.participants.length} participant${call.participants.length > 1 ? 's' : ''} · voix uniquement',
                style: TextStyle(color: OuroColors.callSecondaryLabel, fontSize: 12)),
            Expanded(
              child: call.participants.isEmpty
                  ? EmptyState(
                      emoji: Scenes.appelManque,
                      icon: Icons.call_end_rounded,
                      title: 'Appel terminé',
                      iconColor: OuroColors.callSecondaryLabel,
                    )
                  : GridView.builder(
                      padding: const EdgeInsets.all(20),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        mainAxisSpacing: 16,
                        crossAxisSpacing: 16,
                        childAspectRatio: 1,
                      ),
                      itemCount: call.participants.length,
                      itemBuilder: (context, i) {
                        final p = call.participants[i];
                        final color = _stateColor(p.state);
                        final active = p.state == GroupCallParticipantState.connecting ||
                            p.state == GroupCallParticipantState.connected;
                        final card = Container(
                          decoration: BoxDecoration(
                            color: OuroColors.callControl,
                            borderRadius: BorderRadius.circular(DesignTokens.radius2xl),
                            border: Border.all(color: color.withValues(alpha: 0.4)),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _ParticipantAvatar(pseudo: p.pseudo, color: color, active: active),
                              const SizedBox(height: 12),
                              Text(p.pseudo,
                                  maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: OuroColors.callLabel, fontWeight: FontWeight.w700)),
                              const SizedBox(height: 4),
                              Text(_stateLabel(p.state), style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        );
                        return card
                            .animate()
                            .fadeIn(delay: (i * 60).ms, duration: DesignTokens.durationSlow)
                            .scaleXY(begin: 0.8, curve: DesignTokens.curveSpring, duration: DesignTokens.durationSlow);
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: 32, top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundControl(
                    icon: call.isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    color: call.isMuted ? OuroColors.ouroOrange : OuroColors.callControl,
                    onTap: () => ref.read(groupCallProvider.notifier).toggleMute(),
                  ),
                  _RoundControl(
                    icon: call.isSpeakerOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                    color: call.isSpeakerOn ? OuroColors.meshBlue : OuroColors.callControl,
                    onTap: () => ref.read(groupCallProvider.notifier).toggleSpeaker(),
                  ),
                  _RoundControl(
                    icon: Icons.call_end_rounded,
                    color: OuroColors.errorRed,
                    haptic: false,
                    onTap: () {
                      HapticFeedback.heavyImpact();
                      ref.read(groupCallProvider.notifier).hangUp();
                      context.go('/chats');
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Un bouton rond de contrôle (micro, haut-parleur, raccrocher) —
/// version simplifiée de celui de `call_screen.dart`, sans l'animation
/// de rotation au tap.
class _RoundControl extends StatelessWidget {
  const _RoundControl({required this.icon, required this.color, required this.onTap, this.haptic = true});
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool haptic;

  @override
  Widget build(BuildContext context) {
    // Même enfoncement que l'appel 1:1, et pour la même raison : l'onde
    // de Material n'a rien à faire sur un écran d'appel.
    return OuroPressable(
      scale: 0.92,
      opacity: 0.7,
      onTap: () {
        if (haptic) HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 62,
        height: 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color,
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Center(child: Icon(icon, color: Colors.white, size: 26)),
      ),
    );
  }
}

/// Avatar de participant avec halo pulsé pendant la connexion/l'appel —
/// miroir du `_PulseRing` de l'appel 1:1 (`call_screen.dart`), pour donner à
/// la grille de groupe le même niveau de vie que l'appel individuel.
class _ParticipantAvatar extends StatefulWidget {
  const _ParticipantAvatar({required this.pseudo, required this.color, required this.active});
  final String pseudo;
  final Color color;
  final bool active;

  @override
  State<_ParticipantAvatar> createState() => _ParticipantAvatarState();
}

class _ParticipantAvatarState extends State<_ParticipantAvatar> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        if (!widget.active) return child!;
        return DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: DesignTokens.glow(widget.color, radius: 8 + _pulse.value * 10, spread: 1),
          ),
          child: child,
        );
      },
      child: PeerAvatar(pseudo: widget.pseudo, radius: 36, online: widget.active),
    );
  }
}
