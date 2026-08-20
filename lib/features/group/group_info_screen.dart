// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est l'écran « Infos du groupe » — celui qu'on ouvre en tapant sur le
// nom d'un groupe. On y voit son nom (modifiable), la liste de tous ses
// membres avec une étoile « Administrateur » pour ceux qui gèrent le
// groupe, et selon qu'on est soi-même administrateur ou pas, la
// possibilité d'ajouter/retirer des membres. Il y a aussi un bouton pour
// démarrer un appel de groupe, et un bouton rouge tout en bas pour
// quitter le groupe.
//
// Toutes les actions ici (renommer, ajouter, retirer, quitter) sont de
// vraies fonctions de `mesh_repository.dart` — voir ce fichier pour
// comprendre comment un simple changement local se propage ensuite aux
// autres membres via le réseau mesh.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/mesh_message.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_alert.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/ouro_list.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/peer_avatar.dart';

/// Page « Infos du groupe » : membres, administration, renommage.
class GroupInfoScreen extends ConsumerWidget {
  const GroupInfoScreen({super.key, required this.groupId});

  final String groupId;

  /// Ouvre une petite fenêtre pour taper un nouveau nom de groupe.
  Future<void> _rename(BuildContext context, WidgetRef ref, String currentName) async {
    final name = await ouroPrompt(
      context,
      title: 'Renommer le groupe',
      initialValue: currentName,
      placeholder: 'Nom du groupe',
      maxLength: 40,
    );
    if (name == null || name.isEmpty || name == currentName) return;
    try {
      await ref.read(meshRepositoryProvider).renameGroup(groupId: groupId, name: name);
    } catch (e) {
      if (!context.mounted) return;
      ref.read(toastProvider.notifier).show('Échec du renommage', type: DropletToastType.error);
    }
  }

  /// Propose la liste des pairs pas encore membres (connectés ou déjà
  /// rencontrés), et ajoute celui choisi au groupe (réservé aux
  /// administrateurs).
  Future<void> _addMember(BuildContext context, WidgetRef ref, GroupInfo group) async {
    final peers = ref.read(meshPeerListProvider);
    final known = StorageService.getKnownPeers();
    final memberIds = group.activeMembers.map((m) => m.peerId).toSet();
    final byId = <String, String>{}; // peerId -> pseudo
    for (final p in peers) {
      if (!memberIds.contains(p.peerId)) byId[p.peerId] = p.pseudo;
    }
    for (final p in known) {
      if (!memberIds.contains(p.peerId)) byId.putIfAbsent(p.peerId, () => p.pseudo);
    }

    if (byId.isEmpty) {
      ref.read(toastProvider.notifier).show('Aucun pair disponible à ajouter', type: DropletToastType.warning);
      return;
    }

    // ⚠️ La seule feuille de l'app restée en Material : coins carrés,
    // fond opaque, pas de poignée. Toutes les autres sont des
    // `FrostedSheet` — coins largement arrondis, matériau translucide et
    // la petite barre grise de 36×5 qu'iOS pose en haut de ses feuilles
    // pour dire « ça se tire ».
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => FrostedSheet(
        padding: const EdgeInsets.fromLTRB(
          DesignTokens.screenMargin,
          0,
          DesignTokens.screenMargin,
          DesignTokens.space5,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: DesignTokens.space2),
              child: Text(
                'AJOUTER UN MEMBRE',
                style: OuroTypography.sectionHeader.copyWith(
                  color: OuroColors.secondaryLabel,
                  letterSpacing: 0.5,
                ),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: byId.entries
                    .map((e) => OuroListRow(
                          leading: PeerAvatar(pseudo: e.value, radius: 16),
                          title: e.value,
                          onTap: () => context.pop(e.key),
                        ))
                    .toList(),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    HapticFeedback.mediumImpact();
    try {
      await ref.read(meshRepositoryProvider).addGroupMember(groupId: groupId, peerId: selected);
    } catch (e) {
      if (!context.mounted) return;
      ref.read(toastProvider.notifier).show('Échec de l\'ajout du membre', type: DropletToastType.error);
    }
  }

  /// Demande confirmation puis retire un membre du groupe (réservé aux
  /// administrateurs) — il ne pourra plus lire les futurs messages.
  Future<void> _removeMember(BuildContext context, WidgetRef ref, String peerId) async {
    final confirmed = await ouroConfirm(
      context,
      title: 'Retirer ce membre ?',
      message: 'Il ne pourra plus lire les messages envoyés après son retrait.',
      confirmLabel: 'Retirer',
      destructive: true,
    );
    if (confirmed != true) return;
    HapticFeedback.mediumImpact();
    try {
      await ref.read(meshRepositoryProvider).removeGroupMember(groupId: groupId, peerId: peerId);
    } catch (e) {
      if (!context.mounted) return;
      ref.read(toastProvider.notifier).show('Échec du retrait du membre', type: DropletToastType.error);
    }
  }

  /// Demande confirmation puis me fait quitter le groupe moi-même.
  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    final confirmed = await ouroConfirm(
      context,
      title: 'Quitter le groupe ?',
      message: 'Vous ne recevrez plus les messages envoyés après votre départ.',
      confirmLabel: 'Quitter',
      destructive: true,
    );
    if (confirmed != true) return;
    HapticFeedback.heavyImpact();
    await ref.read(meshRepositoryProvider).leaveGroup(groupId);
    if (!context.mounted) return;
    context.go('/chats');
  }

  /// Démarre un appel de groupe avec les membres actuellement joignables
  /// en Wi-Fi local (max 3 autres personnes, voir la limite de
  /// `group_webrtc_call_service.dart`).
  Future<void> _startGroupCall(
    BuildContext context,
    WidgetRef ref,
    GroupInfo group,
    String myId,
    String Function(String peerId) pseudoFor,
  ) async {
    final callNotifier = ref.read(callProvider.notifier);
    final reachable = group.activeMembers
        .map((m) => m.peerId)
        .where((id) => id != myId && callNotifier.canCallPeer(id))
        .toList();

    if (reachable.isEmpty) {
      ref.read(toastProvider.notifier).show(
            'Aucun membre joignable en Wi-Fi local pour le moment',
            type: DropletToastType.warning,
          );
      return;
    }
    if (reachable.length + 1 > 4) {
      ref.read(toastProvider.notifier).show(
            'Maximum 4 participants par appel de groupe — seuls les 3 premiers joignables seront appelés',
            type: DropletToastType.warning,
          );
    }
    final members = reachable.take(3).toList();

    await ref.read(groupCallProvider.notifier).startGroupCall(
          groupId: group.id,
          groupName: group.name,
          memberPeerIds: members,
          pseudoFor: pseudoFor,
        );
    if (!context.mounted) return;
    context.go('/group-call');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupInfoProvider(groupId));
    final myId = ref.watch(meshRepositoryProvider).myId;
    final peers = ref.watch(meshPeerListProvider);

    if (group == null) {
      return Scaffold(
        backgroundColor: OuroColors.background,
        body: Center(child: Text('Groupe introuvable', style: TextStyle(color: OuroColors.textTertiary))),
      );
    }

    final isAdmin = group.isAdmin(myId);
    final members = group.activeMembers
      ..sort((a, b) => a.role == b.role ? a.peerId.compareTo(b.peerId) : (a.role == 'admin' ? -1 : 1));

    String pseudoFor(String peerId) {
      for (final p in peers) {
        if (p.peerId == peerId) return p.pseudo;
      }
      for (final p in StorageService.getKnownPeers()) {
        if (p.peerId == peerId) return p.pseudo;
      }
      return peerId == myId ? 'Moi' : peerId;
    }

    bool onlineFor(String peerId) => peers.any((p) => p.peerId == peerId);

    return Scaffold(
      backgroundColor: OuroColors.background,
      appBar: AppBar(
        backgroundColor: OuroColors.background,
        elevation: 0,
        title: Text('Infos du groupe',
            style: TextStyle(color: OuroColors.textPrimary, fontWeight: FontWeight.w700)),
        leading: OuroBackButton(fallback: '/group/$groupId'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(DesignTokens.screenMargin, 8, DesignTokens.screenMargin, DesignTokens.space8),
        children: [
          Center(
            child: Column(
              children: [
                PeerAvatar(pseudo: group.name, radius: 38),
                const SizedBox(height: 14),
                GestureDetector(
                  onTap: () => _rename(context, ref, group.name),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(group.name,
                          style: TextStyle(color: OuroColors.textPrimary, fontSize: 17, fontWeight: FontWeight.w700)),
                      SizedBox(width: 6),
                      Icon(Icons.edit_rounded, size: 14, color: OuroColors.textTertiary),
                    ],
                  ),
                ),
                SizedBox(height: 4),
                Text('${members.length} membre${members.length > 1 ? 's' : ''}',
                    style: TextStyle(color: OuroColors.textTertiary, fontSize: 13)),
                SizedBox(height: 8),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.lock_rounded, size: 14, color: OuroColors.successGreen),
                    SizedBox(width: 6),
                    Text('Messages de groupe chiffrés', style: TextStyle(fontSize: 12, color: OuroColors.successGreen)),
                  ],
                ),
                const SizedBox(height: 16),
                OutlinedButton.icon(
                  onPressed: () => _startGroupCall(context, ref, group, myId, pseudoFor),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: OuroColors.meshBlue,
                    side: BorderSide(color: OuroColors.meshBlue),
                  ),
                  icon: const Icon(Icons.call_rounded),
                  label: const Text('Appel de groupe'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Text('Membres', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: OuroColors.textSecondary)),
              const Spacer(),
              if (isAdmin)
                TextButton.icon(
                  onPressed: () => _addMember(context, ref, group),
                  icon: Icon(Icons.person_add_alt_1_rounded, size: 18, color: OuroColors.meshBlueBright),
                  label: Text('Ajouter', style: TextStyle(color: OuroColors.meshBlueBright)),
                ),
            ],
          ),
          ...members.asMap().entries.map((entry) {
            final i = entry.key;
            final m = entry.value;
            final pseudo = pseudoFor(m.peerId);
            return Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              decoration: BoxDecoration(
                color: OuroColors.glassBg,
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                border: Border.all(color: OuroColors.glassBorder),
              ),
              child: ListTile(
                leading: PeerAvatar(pseudo: pseudo, radius: 20, online: onlineFor(m.peerId)),
                title: Text(m.peerId == myId ? '$pseudo (moi)' : pseudo,
                    style: TextStyle(color: OuroColors.textPrimary, fontWeight: FontWeight.w600)),
                subtitle: m.isAdmin
                    ? Text('Administrateur', style: TextStyle(fontSize: 12, color: OuroColors.meshBlueBright))
                    : null,
                trailing: isAdmin && m.peerId != myId
                    ? IconButton(
                        icon: Icon(Icons.remove_circle_outline_rounded, color: OuroColors.errorRed),
                        onPressed: () => _removeMember(context, ref, m.peerId),
                      )
                    : null,
              ),
            )
                .animate()
                .fadeIn(delay: (i * 40).ms, duration: DesignTokens.durationFast)
                .slideX(begin: 0.06);
          }),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _leave(context, ref),
              style: OutlinedButton.styleFrom(
                foregroundColor: OuroColors.errorRed,
                side: BorderSide(color: OuroColors.errorRed),
              ),
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Quitter le groupe'),
            ),
          ),
        ],
      ),
    );
  }
}
