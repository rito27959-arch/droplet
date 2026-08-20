// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est l'écran « Créer un groupe » — on tape un nom, on coche les
// personnes qu'on veut inviter (celles déjà connectées MAINTENANT, ou
// celles déjà rencontrées par le passé même si elles ne sont pas
// joignables tout de suite), et on tape sur « Créer le groupe ». Le
// bouton du bas change lui-même d'apparence selon l'étape : texte
// normal, roue de chargement pendant la création, puis une coche verte
// de confirmation juste avant d'ouvrir le nouveau groupe.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_spinner.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../shared/widgets/scene_animee.dart';
import '../../shared/widgets/empty_state.dart';

/// Écran de création d'un groupe : nom + sélection des membres parmi les
/// pairs connectés ou déjà rencontrés.
class GroupCreateScreen extends ConsumerStatefulWidget {
  const GroupCreateScreen({super.key});

  @override
  ConsumerState<GroupCreateScreen> createState() => _GroupCreateScreenState();
}

class _GroupCreateScreenState extends ConsumerState<GroupCreateScreen> {
  final _nameCtrl = TextEditingController();
  final Set<String> _selected = {};
  bool _busy = false;
  bool _created = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  /// Construit la liste des personnes qu'on peut inviter — d'abord tous
  /// les pairs actuellement connectés, puis complétée par ceux déjà
  /// rencontrés par le passé (mais pas doublonnée si quelqu'un est dans
  /// les deux listes).
  List<_Candidate> _candidates() {
    final connected = ref.watch(meshPeerListProvider);
    final byId = <String, _Candidate>{};
    for (final p in connected) {
      byId[p.peerId] = _Candidate(peerId: p.peerId, pseudo: p.pseudo, online: true);
    }
    for (final p in StorageService.getKnownPeers()) {
      byId.putIfAbsent(p.peerId, () => _Candidate(peerId: p.peerId, pseudo: p.pseudo, online: false));
    }
    final list = byId.values.toList()..sort((a, b) => a.pseudo.compareTo(b.pseudo));
    return list;
  }

  /// Vérifie qu'un nom et au moins un membre sont bien choisis, puis
  /// crée vraiment le groupe et navigue vers son écran de conversation.
  Future<void> _create() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      ref.read(toastProvider.notifier).show('Choisis un nom pour le groupe', type: DropletToastType.warning);
      return;
    }
    if (_selected.isEmpty) {
      ref.read(toastProvider.notifier).show('Sélectionne au moins un membre', type: DropletToastType.warning);
      return;
    }
    setState(() => _busy = true);
    try {
      final repo = ref.read(meshRepositoryProvider);
      final groupId = await repo.createGroup(name: name, memberIds: _selected);
      if (!mounted) return;
      setState(() => _created = true);
      await Future.delayed(DesignTokens.durationXSlow);
      if (!mounted) return;
      context.go('/group/$groupId');
    } catch (e) {
      if (!mounted) return;
      ref.read(toastProvider.notifier).show('Échec de la création du groupe', type: DropletToastType.error);
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final candidates = _candidates();

    return Scaffold(
      appBar: AppBar(
        leading: const OuroBackButton(),
        title: const Text('Nouveau groupe', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _nameCtrl,
              maxLength: 40,
              style: TextStyle(color: OuroColors.textPrimary, fontSize: 16),
              decoration: InputDecoration(
                labelText: 'Nom du groupe',
                counterText: '',
                hintText: 'ex. Équipe terrain',
                prefixIcon: Icon(Icons.groups_rounded, color: OuroColors.textTertiary),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Membres', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: OuroColors.textSecondary)),
                const Spacer(),
                Text('${_selected.length} sélectionné${_selected.length > 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 12, color: OuroColors.textTertiary)),
              ],
            ),
          ),
          Expanded(
            child: candidates.isEmpty
                ? const EmptyState(
                    emoji: Scenes.aucunGroupe,
                    icon: Icons.group_add_rounded,
                    title: 'Personne à portée',
                    subtitle: 'Rapproche-toi d\'un autre appareil Droplet : '
                        'les pairs apparaissent ici automatiquement.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    itemCount: candidates.length,
                    itemBuilder: (context, i) {
                      final c = candidates[i];
                      final checked = _selected.contains(c.peerId);
                      return _CandidateTile(
                        candidate: c,
                        checked: checked,
                        onChanged: () {
                          HapticFeedback.selectionClick();
                          setState(() {
                            checked ? _selected.remove(c.peerId) : _selected.add(c.peerId);
                          });
                        },
                      )
                          .animate()
                          .fadeIn(delay: (i * 35).ms, duration: DesignTokens.durationFast)
                          .slideX(begin: 0.06);
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: _busy ? null : _create,
                  style: FilledButton.styleFrom(
                    backgroundColor: _created ? OuroColors.successGreen : OuroColors.meshBlue,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
                  ),
                  child: AnimatedSwitcher(
                    duration: DesignTokens.durationFast,
                    child: _created
                        ? const Icon(Icons.check_rounded, key: ValueKey('done'), color: Colors.white)
                            .animate()
                            .scaleXY(begin: 0.3, curve: DesignTokens.curveBounce, duration: DesignTokens.durationSlow)
                        : _busy
                            ? const SizedBox(
                                key: ValueKey('busy'),
                                width: 22, height: 22,
                                child: OuroSpinner(color: Colors.white, radius: 9),
                              )
                            : const Text('Créer le groupe',
                                key: ValueKey('idle'),
                                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Une personne qu'on peut inviter dans le groupe.
class _Candidate {
  final String peerId;
  final String pseudo;
  final bool online;
  const _Candidate({required this.peerId, required this.pseudo, required this.online});
}

/// Tuile de sélection de membre, stylée cohérente avec le reste de l'app
/// (glass) — remplace le `CheckboxListTile` Material brut d'origine.
class _CandidateTile extends StatelessWidget {
  const _CandidateTile({required this.candidate, required this.checked, required this.onChanged});
  final _Candidate candidate;
  final bool checked;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onChanged,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: checked ? OuroColors.meshBlue.withValues(alpha: 0.12) : OuroColors.glassBg,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(color: checked ? OuroColors.meshBlue.withValues(alpha: 0.5) : OuroColors.glassBorder),
        ),
        child: Row(
          children: [
            PeerAvatar(pseudo: candidate.pseudo, radius: 20, online: candidate.online),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(candidate.pseudo, style: TextStyle(color: OuroColors.textPrimary, fontWeight: FontWeight.w600)),
                  Text(candidate.online ? 'Connecté' : 'Déjà rencontré',
                      style: TextStyle(
                          fontSize: 12, color: candidate.online ? OuroColors.successGreen : OuroColors.textTertiary)),
                ],
              ),
            ),
            AnimatedContainer(
              duration: DesignTokens.durationFast,
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: checked ? OuroColors.meshBlue : Colors.transparent,
                border: Border.all(color: checked ? OuroColors.meshBlue : OuroColors.glassBorderStrong, width: 1.5),
              ),
              child: checked
                  ? const Icon(Icons.check_rounded, size: 16, color: Colors.white)
                      .animate()
                      .scaleXY(begin: 0.4, curve: DesignTokens.curveBounce, duration: DesignTokens.durationNormal)
                  : null,
            ),
          ],
        ),
      ),
    );
  }
}
