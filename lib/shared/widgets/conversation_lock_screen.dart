import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_padlock.dart';
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

class _ConversationLockScreenState extends State<ConversationLockScreen> {
  final _auth = LocalAuthentication();
  bool _authenticating = false;
  String? _error;

  // ⚠️ Le contrôleur de pulsation a disparu avec le halo qu'il animait.
  // Un `AnimationController` qui tourne en boucle est un `Ticker` qui
  // réveille l'application soixante fois par seconde, en permanence :
  // ici, sur un écran qui attend une empreinte digitale et ne bouge
  // pas. Le cadenas, lui, joue une seule fois à l'ouverture.

  @override
  void initState() {
    super.initState();
    // Tente l'auth automatiquement à l'ouverture.
    WidgetsBinding.instance.addPostFrameCallback((_) => _authenticate());
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
              // ── LE CADENAS, VRAIMENT FERMÉ ─────────────────────────
              //
              // Deux changements par rapport à la version précédente.
              //
              // Le halo bleu pulsant a disparu : c'est l'effet que
              // `design_tokens.dart` bannit, et il servait ici à faire
              // « respirer » une icône figée faute de mieux.
              //
              // Et l'icône `Icons.lock_rounded` est devenue le cadenas
              // articulé de l'application (`ouro_padlock.dart`). Il
              // arrive OUVERT, et se ferme en un demi-tour de seconde à
              // l'ouverture de l'écran. Voir un cadenas se fermer devant
              // soi dit « cette conversation vient d'être mise sous
              // clé » ; une icône de cadenas déjà fermée ne dit que
              // « verrouillé », ce que le titre écrit déjà juste en
              // dessous.
              //
              // C'est le même objet que sur le bouton micro, dans la
              // barre d'état Tor et sur l'écran Tor : une seule chose à
              // apprendre pour toute l'application.
              TweenAnimationBuilder<double>(
                tween: Tween<double>(begin: 0, end: 1),
                duration: DesignTokens.durationSheet,
                curve: DesignTokens.curveStandard,
                builder: (context, fermeture, _) => Container(
                  width: 80,
                  height: 80,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: OuroColors.glassBg,
                  ),
                  child: OuroPadlock(
                    fermeture: fermeture,
                    couleur: OuroColors.accent,
                    taille: 36,
                    epaisseur: 3.5,
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
