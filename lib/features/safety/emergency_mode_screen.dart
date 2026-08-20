import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/providers/mesh_provider.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_spinner.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';

class EmergencyModeScreen extends ConsumerStatefulWidget {
  const EmergencyModeScreen({super.key});

  @override
  ConsumerState<EmergencyModeScreen> createState() => _EmergencyModeScreenState();
}

class _EmergencyModeScreenState extends ConsumerState<EmergencyModeScreen> {
  bool _sosActive = false;
  bool _broadcasting = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OuroColors.background,
      body: Container(
        decoration: BoxDecoration(
          gradient: _sosActive
              ? LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    OuroColors.errorRed.withValues(alpha: 0.15),
                    OuroColors.background,
                    OuroColors.background,
                  ],
                )
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    // Un voile rouge très dilué en haut d'écran plutôt
                    // qu'un bleu nuit fixe : il porte le sens de l'écran, et
                    // il fonctionne aussi bien sur fond blanc que noir.
                    Color.alphaBlend(
                      OuroColors.systemRed.withValues(alpha: 0.10),
                      OuroColors.systemBackground,
                    ),
                    OuroColors.systemBackground,
                    OuroColors.systemBackground,
                  ],
                ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
                child: Row(
                  children: [
                    const OuroBackButton(),
                    Expanded(
                      child: Text('Mode urgence',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: OuroColors.textPrimary)),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              // Centre — gros bouton SOS
              Column(
                children: [
                  GestureDetector(
                    onTap: _toggleSos,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      curve: Curves.easeOutCubic,
                      width: _sosActive ? 180 : 160,
                      height: _sosActive ? 180 : 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: _sosActive
                              ? [OuroColors.errorRed, Color(0xFFFF1744)]
                              : [OuroColors.errorRed.withValues(alpha: 0.3), OuroColors.errorRed.withValues(alpha: 0.15)],
                        ),
                        boxShadow: _sosActive
                            ? [
                                BoxShadow(
                                  color: OuroColors.errorRed.withValues(alpha: 0.5),
                                  blurRadius: 40,
                                  spreadRadius: 8,
                                ),
                              ]
                            : [],
                        border: Border.all(
                          color: _sosActive ? OuroColors.errorRed : OuroColors.errorRed.withValues(alpha: 0.3),
                          width: 2,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _sosActive ? Icons.warning_rounded : Icons.sos_rounded,
                            color: Colors.white,
                            size: _sosActive ? 48 : 42,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _sosActive ? 'SOS ACTIF' : 'SOS',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: _sosActive ? 18 : 16,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ).animate(onPlay: (c) => _sosActive ? c.repeat(reverse: true) : null)
                      .scaleXY(begin: 1.0, end: 1.05, duration: 800.ms),
                  const SizedBox(height: 32),
                  Text(
                    _sosActive
                        ? 'Signal SOS actif —扩散到所有附近设备'
                        : 'Tirez pour envoyer un signal d\'urgence',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _sosActive ? OuroColors.errorRed : OuroColors.textSecondary,
                      fontSize: 15,
                      fontWeight: _sosActive ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Le signal est relayé de pair en pair\nsur tout le réseau mesh.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: OuroColors.textTertiary,
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              // Actions en bas
              Padding(
                padding: const EdgeInsets.fromLTRB(DesignTokens.screenMargin, 0, DesignTokens.screenMargin, DesignTokens.space8),
                child: Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: _broadcasting ? null : _broadcastCheckIn,
                        icon: _broadcasting
                            ? const SizedBox(width: 18, height: 18, child: OuroSpinner(color: Colors.white, radius: 9))
                            : const Icon(Icons.check_circle_rounded, size: 20),
                        label: Text(
                          _broadcasting ? 'Diffusion...' : 'Je suis en sécurité',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: OuroColors.successGreen,
                          side: BorderSide(color: OuroColors.successGreen, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.location_on_rounded, size: 20),
                        label: const Text(
                          'Partager ma position',
                          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: OuroColors.meshBlueBright,
                          side: BorderSide(color: OuroColors.meshBlueBright, width: 1.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
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
      ),
    );
  }

  void _toggleSos() {
    HapticFeedback.heavyImpact();
    setState(() => _sosActive = !_sosActive);
    if (_sosActive) {
      ref.read(toastProvider.notifier).show('Signal SOS activé', type: DropletToastType.warning);
    }
  }

  Future<void> _broadcastCheckIn() async {
    HapticFeedback.mediumImpact();
    setState(() => _broadcasting = true);
    try {
      await ref.read(meshRepositoryProvider).sendStatus('🟢 Je suis en sécurité');
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Statut de sécurité diffusé', type: DropletToastType.success);
    } catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Échec de la diffusion', type: DropletToastType.error);
    } finally {
      if (mounted) setState(() => _broadcasting = false);
    }
  }
}
