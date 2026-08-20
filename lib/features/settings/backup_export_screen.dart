import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/backup_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_spinner.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/success_seal.dart';
import '../../shared/widgets/scene_animee.dart';

/// Export d'une sauvegarde chiffrée de l'identité (clé privée, contacts,
/// groupes, et optionnellement l'historique) — seul recours en cas de perte
/// d'appareil, l'app ne dépendant d'aucun compte ni serveur.
class BackupExportScreen extends ConsumerStatefulWidget {
  const BackupExportScreen({super.key});

  @override
  ConsumerState<BackupExportScreen> createState() => _BackupExportScreenState();
}

class _BackupExportScreenState extends ConsumerState<BackupExportScreen> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _includeMessages = true;
  bool _obscure = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _passwordCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  /// Force approximative du mot de passe, 0..1 — critères simples (longueur,
  /// variété de caractères) juste pour rassurer visuellement l'utilisateur
  /// sur la qualité de sa protection, pas une mesure d'entropie exacte.
  double _passwordStrength(String p) {
    if (p.isEmpty) return 0;
    var score = 0;
    if (p.length >= 8) score++;
    if (p.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(p) && RegExp(r'[a-z]').hasMatch(p)) score++;
    if (RegExp(r'[0-9]').hasMatch(p)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(p)) score++;
    return (score / 5).clamp(0.0, 1.0);
  }

  (Color, String) _strengthLabel(double s) {
    if (s <= 0) return (OuroColors.textTertiary, '');
    if (s < 0.4) return (OuroColors.errorRed, 'Faible');
    if (s < 0.8) return (OuroColors.warningAmber, 'Correct');
    return (OuroColors.successGreen, 'Solide');
  }

  Future<void> _export() async {
    final password = _passwordCtrl.text;
    if (password.length < 8) {
      ref.read(toastProvider.notifier).show(
            'Le mot de passe doit faire au moins 8 caractères',
            type: DropletToastType.warning,
          );
      return;
    }
    if (password != _confirmCtrl.text) {
      ref.read(toastProvider.notifier).show(
            'Les deux mots de passe ne correspondent pas',
            type: DropletToastType.warning,
          );
      return;
    }

    setState(() => _busy = true);
    try {
      final file = await BackupService.createBackup(
        password: password,
        includeMessages: _includeMessages,
      );
      if (!mounted) return;
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'Sauvegarde Droplet',
        text: 'Sauvegarde chiffrée de mon identité Droplet — à garder en lieu sûr.',
      );
      if (!mounted) return;
      _passwordCtrl.clear();
      _confirmCtrl.clear();
      // Moment sensible (identité chiffrée exportée) : un sceau plein écran
      // rassure davantage qu'un toast passager, cohérent avec le traitement
      // de la vérification de clé de sécurité.
      unawaited(SuccessSeal.show(context,
          icon: Icons.lock_rounded,
          emoji: Scenes.sauvegardeReussie,
          message: 'Sauvegarde créée'));
    } catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Échec de la sauvegarde', type: DropletToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OuroColors.background,
      appBar: AppBar(
        backgroundColor: OuroColors.background,
        elevation: 0,
        leading: const OuroBackButton(fallback: '/settings'),
        title: Text('Sauvegarder mon identité',
            style: TextStyle(color: OuroColors.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: OuroColors.warningAmber.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              border: Border.all(color: OuroColors.warningAmber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.warning_amber_rounded, color: OuroColors.warningAmber, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Quiconque possède ce fichier et le mot de passe peut se faire passer '
                    'pour toi. Garde-le en lieu sûr (jamais envoyé à personne d\'autre que '
                    'toi-même) et choisis un mot de passe que tu es seul à connaître.',
                    style: TextStyle(color: OuroColors.warningAmber, fontSize: 12, height: 1.4),
                  ),
                ),
              ],
            ),
          )
              .animate()
              .fadeIn(duration: DesignTokens.durationNormal)
              .slideY(begin: -0.1, curve: DesignTokens.curveEmphasis)
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .custom(
                duration: DesignTokens.durationBeat,
                builder: (context, value, child) => DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                    boxShadow: DesignTokens.glow(OuroColors.warningAmber, radius: 4 + value * 6, spread: 0),
                  ),
                  child: child,
                ),
              ),
          const SizedBox(height: 24),
          Text('Ce mot de passe protège ta sauvegarde. Il n\'est jamais enregistré : '
              'sans lui, le fichier est définitivement inutilisable.',
              style: TextStyle(color: OuroColors.textSecondary, fontSize: 13, height: 1.5)),
          const SizedBox(height: 16),
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscure,
            style: TextStyle(color: OuroColors.textPrimary),
            decoration: InputDecoration(
              labelText: 'Mot de passe',
              suffixIcon: IconButton(
                icon: Icon(_obscure ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                    color: OuroColors.textTertiary),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
          if (_passwordCtrl.text.isNotEmpty) ...[
            const SizedBox(height: 8),
            _PasswordStrengthMeter(
              strength: _passwordStrength(_passwordCtrl.text),
              label: _strengthLabel(_passwordStrength(_passwordCtrl.text)),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _confirmCtrl,
            obscureText: _obscure,
            style: TextStyle(color: OuroColors.textPrimary),
            decoration: const InputDecoration(labelText: 'Confirmer le mot de passe'),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _includeMessages,
            onChanged: (v) {
              HapticFeedback.selectionClick();
              setState(() => _includeMessages = v);
            },
            activeThumbColor: OuroColors.meshBlue,
            title: Text('Inclure l\'historique des messages',
                style: TextStyle(color: OuroColors.textPrimary, fontSize: 15)),
            subtitle: Text('Sinon, seuls l\'identité, les contacts et les groupes sont sauvegardés',
                style: TextStyle(color: OuroColors.textTertiary, fontSize: 12)),
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _busy ? null : _export,
              style: FilledButton.styleFrom(
                backgroundColor: OuroColors.meshBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
              ),
              child: AnimatedSwitcher(
                duration: DesignTokens.durationFast,
                child: _busy
                    ? const SizedBox(
                        key: ValueKey('busy'),
                        width: 22, height: 22,
                        child: OuroSpinner(color: Colors.white, radius: 9),
                      )
                    : const Text('Créer et partager la sauvegarde',
                        key: ValueKey('idle'),
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Indicateur de force du mot de passe, mis à jour en temps réel — rassure
/// sur la qualité de la protection d'une sauvegarde qui, contrairement à un
/// compte en ligne, n'a aucun mécanisme de récupération si le mot de passe
/// est trop faible et deviné/cassé plus tard.
class _PasswordStrengthMeter extends StatelessWidget {
  const _PasswordStrengthMeter({required this.strength, required this.label});
  final double strength;
  final (Color, String) label;

  @override
  Widget build(BuildContext context) {
    final (color, text) = label;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: strength),
              duration: DesignTokens.durationNormal,
              curve: DesignTokens.curveEmphasis,
              builder: (context, value, _) => LinearProgressIndicator(
                value: value,
                minHeight: 5,
                backgroundColor: OuroColors.glassBg,
                valueColor: AlwaysStoppedAnimation(color),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700)),
      ],
    ).animate().fadeIn(duration: DesignTokens.durationFast);
  }
}
