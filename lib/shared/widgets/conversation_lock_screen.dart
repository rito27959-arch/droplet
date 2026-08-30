import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_typography.dart';

/// Écran de verrouillage pour une conversation protégée.
///
/// Affiché quand l'utilisateur tente d'ouvrir une conversation verrouillée.
/// Demande l'authentification biométrique (empreinte digitale / visage)
/// avant de laisser accès.
class ConversationLockScreen extends StatefulWidget {
  const ConversationLockScreen({
    super.key,
    required this.pseudo,
    required this.onUnlocked,
  });

  final String pseudo;
  final VoidCallback onUnlocked;

  @override
  State<ConversationLockScreen> createState() => _ConversationLockScreenState();
}

class _ConversationLockScreenState extends State<ConversationLockScreen>
    with SingleTickerProviderStateMixin {
  final _auth = LocalAuthentication();
  bool _authenticating = false;
  String? _error;
  late AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    // Tente l'auth automatiquement à l'ouverture.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  Future<void> _authenticate() async {
    if (_authenticating) return;
    setState(() {
      _authenticating = true;
      _error = null;
    });

    try {
      final available = await _auth.canCheckBiometrics;
      if (!available) {
        setState(() {
          _error = 'Aucune empreinte digitale configurée sur cet appareil';
          _authenticating = false;
        });
        return;
      }

      final didAuth = await _auth.authenticate(
        localizedReason: 'Déverrouiller la conversation avec ${widget.pseudo}',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true,
        ),
      );

      if (didAuth && mounted) {
        HapticFeedback.mediumImpact();
        widget.onUnlocked();
      } else if (mounted) {
        setState(() {
          _error = 'Authentification échouée';
          _authenticating = false;
        });
      }
    } on PlatformException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message ?? 'Erreur d\'authentification';
          _authenticating = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OuroColors.background,
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: OuroColors.glassBg,
                    boxShadow: [
                      BoxShadow(
                        color: OuroColors.accent.withValues(alpha: 0.2 + _pulse.value * 0.15),
                        blurRadius: 20 + _pulse.value * 10,
                        spreadRadius: _pulse.value * 3,
                      ),
                    ],
                  ),
                  child: Icon(
                    Icons.lock_rounded,
                    size: 36,
                    color: OuroColors.accent,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Conversation verrouillée',
                style: OuroTypography.title2.copyWith(color: OuroColors.label),
              ),
              const SizedBox(height: 8),
              Text(
                widget.pseudo,
                style: OuroTypography.body.copyWith(color: OuroColors.secondaryLabel),
              ),
              const SizedBox(height: 32),
              if (_authenticating)
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                )
              else ...[
                SizedBox(
                  width: 200,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: _authenticate,
                    icon: const Icon(Icons.fingerprint_rounded, size: 22),
                    label: const Text('Déverrouiller'),
                    style: FilledButton.styleFrom(
                      backgroundColor: OuroColors.accent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                      ),
                    ),
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _error!,
                    style: OuroTypography.footnote.copyWith(color: OuroColors.errorRed),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
