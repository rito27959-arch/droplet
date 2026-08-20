// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'écran d'ACCUEIL — la liste des conversations, première chose que voit
// l'utilisateur. C'est l'écran qui donne son impression générale à toute
// l'app.
//
// CE QUI A CHANGÉ À LA REFONTE — l'ancienne version empilait, avant même
// d'atteindre la première conversation : un bandeau rouge « Mode
// urgence », une grande carte animée avec des points en orbite, une
// rangée de statuts, une rangée « À proximité », et seulement ensuite la
// liste. L'information principale (« à qui je parle ») était repoussée
// hors de l'écran par de la décoration.
//
// Le nouvel écran suit la règle d'iOS : LE CONTENU D'ABORD.
//   - Un grand titre « Discussions » qui se replie au défilement.
//   - Une barre de recherche, comme dans Messages.
//   - Les statuts sur une seule ligne compacte, seulement s'il y en a.
//   - Puis immédiatement les conversations, en pleine largeur.
//
// Le mode urgence et l'état du réseau ne sont pas supprimés : ils
// deviennent des éléments discrets de la barre de navigation, accessibles
// en un geste mais sans occuper le tiers de l'écran en permanence.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../shared/widgets/scene_animee.dart';
import '../status/status_composer.dart';

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  bool _meshStarted = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _ensureMesh();
    _searchCtrl.addListener(
      () => setState(() => _query = _searchCtrl.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// Démarre le réseau mesh une seule fois, dès l'affichage de l'écran.
  Future<void> _ensureMesh() async {
    if (_meshStarted) return;
    _meshStarted = true;
    final user = StorageService.currentUser;
    if (user == null) return;
    try {
      final repo = ref.read(meshRepositoryProvider);
      await repo.init(user.id, user.pseudo);
      ref.read(callProvider.notifier).init(repo.transport);
      ref.read(groupCallProvider.notifier).init(repo.transport, repo.myId);
    } catch (e) {
      debugPrint('[Chats] mesh init error: $e');
    }
  }

  Future<void> _onRefresh() async {
    // La découverte de pairs tourne déjà en continu en arrière-plan ; ce
    // geste sert de confirmation rassurante, comme dans Mail sur iOS.
    OuroHaptics.light();
    await Future.delayed(const Duration(milliseconds: 600));
  }

  Future<void> _archiveConversation(Conversation c) async {
    OuroHaptics.medium();
    await StorageService.setConversationArchived(c.key, true);
    if (!mounted) return;
    ref.read(archivedRevisionProvider.notifier).state++;
  }

  Future<void> _openArchived() async {
    OuroHaptics.selection();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _ArchivedSheet(),
    );
  }

  Future<void> _composeStatus() => composeStatus(context, ref);

  @override
  Widget build(BuildContext context) {
    ref.watch(archivedRevisionProvider);
    final all = ref.watch(conversationsProvider);
    final conversations = _query.isEmpty
        ? all
        : all
            .where((c) => c.pseudo.toLowerCase().contains(_query))
            .toList();
    final peers = ref.watch(meshPeerListProvider);
    final archivedCount = StorageService.getArchivedConversations().length;

    return OuroLargeTitleScaffold(
      title: 'Discussions',
      // Le sous-titre remplace à lui seul l'ancienne grande carte animée
      // du réseau : l'information utile (« combien de personnes sont
      // joignables ») en une ligne, au lieu d'un tiers d'écran.
      subtitle: peers.isEmpty
          ? 'Recherche de pairs…'
          : '${peers.length} pair${peers.length > 1 ? 's' : ''} à proximité',
      onRefresh: _onRefresh,
      leading: OuroBarButton(
        icon: Icons.settings_outlined,
        tooltip: 'Réglages',
        onPressed: () => context.push('/settings'),
      ),
      actions: [
        OuroBarButton(
          icon: Icons.wifi_tethering_rounded,
          tooltip: 'Réseau mesh',
          onPressed: () => context.push('/mesh-network'),
        ),
        OuroBarButton(
          icon: Icons.add_rounded,
          tooltip: 'Nouveau',
          onPressed: _showComposeMenu,
        ),
      ],
      slivers: [
        SliverToBoxAdapter(child: _SearchField(controller: _searchCtrl)),

        if (_query.isEmpty && archivedCount > 0)
          SliverToBoxAdapter(
            child: _ArchivedRow(count: archivedCount, onTap: _openArchived),
          ),

        if (conversations.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyChats(searching: _query.isNotEmpty),
          )
        else
          SliverList.builder(
            itemCount: conversations.length,
            itemBuilder: (context, i) => _ConversationRow(
              conversation: conversations[i],
              onArchive: () => _archiveConversation(conversations[i]),
            ),
          ),
      ],
    );
  }

  /// Menu d'action rapide, façon feuille iOS.
  void _showComposeMenu() {
    OuroHaptics.selection();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FrostedSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SheetAction(
              icon: Icons.group_add_rounded,
              label: 'Nouveau groupe',
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.go('/group/create');
              },
            ),
            Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
            _SheetAction(
              icon: Icons.auto_awesome_rounded,
              label: 'Nouveau statut',
              onTap: () {
                Navigator.of(sheetContext).pop();
                _composeStatus();
              },
            ),
            Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
            _SheetAction(
              icon: Icons.health_and_safety_rounded,
              label: 'Mode urgence',
              // Le seul élément coloré du menu : le rouge y garde son
              // sens d'alerte, justement parce qu'il est isolé.
              color: OuroColors.systemRed,
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/safety');
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  RECHERCHE
// ─────────────────────────────────────────────────────────────

/// Barre de recherche façon iOS : capsule grise, loupe à l'intérieur,
/// aucune bordure.
class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.screenMargin,
        DesignTokens.space1,
        DesignTokens.screenMargin,
        DesignTokens.space2,
      ),
      child: SizedBox(
        height: 36,
        child: TextField(
          controller: controller,
          style: OuroTypography.body.copyWith(color: OuroColors.label),
          cursorColor: OuroColors.accent,
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Rechercher',
            hintStyle: OuroTypography.body.copyWith(
              color: OuroColors.tertiaryLabel,
            ),
            prefixIcon: Icon(
              Icons.search_rounded,
              color: OuroColors.tertiaryLabel,
              size: DesignTokens.iconMd,
            ),
            prefixIconConstraints: const BoxConstraints(minWidth: 34),
            filled: true,
            fillColor: OuroColors.tertiarySystemFill,
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              borderSide: BorderSide.none,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  LIGNE DE CONVERSATION
// ─────────────────────────────────────────────────────────────

/// Une conversation dans la liste — mise en page identique à Messages sur
/// iOS : avatar, nom, aperçu sur deux lignes, heure et chevron à droite,
/// et un séparateur qui démarre après l'avatar.
class _ConversationRow extends StatefulWidget {
  const _ConversationRow({required this.conversation, required this.onArchive});

  final Conversation conversation;
  final VoidCallback onArchive;

  @override
  State<_ConversationRow> createState() => _ConversationRowState();
}

class _ConversationRowState extends State<_ConversationRow> {
  bool _pressed = false;

  static const double _avatarSize = 52;
  static const double _textInset =
      DesignTokens.screenMargin + _avatarSize + DesignTokens.space3;

  void _open() {
    final c = widget.conversation;
    OuroHaptics.selection();
    final route = c.isGroup
        ? '/group/${c.groupId}'
        : c.isBroadcast
            ? '/chat/broadcast'
            : '/chat/${c.peerId}';
    // `push` et non `go` : la liste des discussions reste DERRIÈRE la
    // conversation. C'est ce qui donne la parallaxe à l'ouverture et,
    // surtout, ce qui permet de revenir en tirant depuis le bord.
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final unread = c.unreadCount > 0;

    final row = Container(
      color: _pressed ? OuroColors.systemGray6 : Colors.transparent,
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.screenMargin,
        DesignTokens.space2,
        DesignTokens.screenMargin,
        DesignTokens.space2,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // La pastille de non-lu est à GAUCHE de l'avatar, comme dans
          // Messages — l'œil descend une seule colonne pour repérer d'un
          // coup ce qui n'a pas été lu.
          SizedBox(
            width: 10,
            child: unread
                ? Padding(
                    padding: const EdgeInsets.only(top: 20),
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: OuroColors.accent,
                      ),
                    ),
                  )
                : null,
          ),
          PeerAvatar(
            pseudo: c.pseudo,
            radius: _avatarSize / 2,
            online: c.isOnline,
          ),
          const SizedBox(width: DesignTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (c.isGroup) ...[
                      Icon(
                        Icons.group_rounded,
                        size: 14,
                        color: OuroColors.secondaryLabel,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        c.pseudo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OuroTypography.headline.copyWith(
                          color: OuroColors.label,
                        ),
                      ),
                    ),
                    const SizedBox(width: DesignTokens.space2),
                    Text(
                      formatMessageTime(c.lastTimestamp),
                      style: OuroTypography.footnote.copyWith(
                        color: OuroColors.secondaryLabel,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: OuroColors.quaternaryLabel,
                    ),
                  ],
                ),
                const SizedBox(height: 1),
                Text(
                  c.lastMessage,
                  // Deux lignes d'aperçu, comme Messages — une seule ligne
                  // rend la liste pauvre et donne peu de contexte.
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: OuroTypography.subheadline.copyWith(
                    color: OuroColors.secondaryLabel,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Dismissible(
      key: ValueKey('archive-${c.key}'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: 0.4},
      background: Container(
        color: OuroColors.systemGray,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: DesignTokens.space5),
        child: const Icon(
          Icons.archive_rounded,
          color: Colors.white,
          size: DesignTokens.iconXl,
        ),
      ),
      confirmDismiss: (_) async {
        // La ligne ne se retire pas d'elle-même : `onArchive` met à jour
        // le stockage, et c'est le filtre du provider qui la fait
        // disparaître au prochain rendu — pas de conflit entre la gestion
        // interne de Dismissible et le rebuild piloté par Riverpod.
        widget.onArchive();
        return false;
      },
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _pressed = true),
            onTapCancel: () => setState(() => _pressed = false),
            onTap: () {
              setState(() => _pressed = false);
              _open();
            },
            child: row,
          ),
          // Le séparateur démarre après l'avatar, jamais au bord — c'est
          // le détail iOS qui fait suivre la colonne de texte à l'œil.
          Padding(
            padding: EdgeInsets.only(left: _textInset),
            child: Divider(
              height: 0.5,
              thickness: 0.5,
              color: OuroColors.separator,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  STATUTS
// ─────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────
//  DIVERS
// ─────────────────────────────────────────────────────────────

/// Ligne d'accès aux conversations archivées, façon Messages iOS.
class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.screenMargin,
              vertical: DesignTokens.space3,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.archive_outlined,
                  size: DesignTokens.iconMd,
                  color: OuroColors.accent,
                ),
                const SizedBox(width: DesignTokens.space3),
                Expanded(
                  child: Text(
                    'Archivées',
                    style: OuroTypography.body.copyWith(
                      color: OuroColors.label,
                    ),
                  ),
                ),
                Text(
                  '$count',
                  style: OuroTypography.body.copyWith(
                    color: OuroColors.secondaryLabel,
                  ),
                ),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: OuroColors.quaternaryLabel,
                ),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.only(left: DesignTokens.screenMargin),
            child: Divider(
              height: 0.5,
              thickness: 0.5,
              color: OuroColors.separator,
            ),
          ),
        ],
      ),
    );
  }
}

/// Une action dans une feuille modale.
class _SheetAction extends StatelessWidget {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? OuroColors.label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 56,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(icon, color: c, size: DesignTokens.iconLg),
            const SizedBox(width: DesignTokens.space3),
            Text(label, style: OuroTypography.body.copyWith(color: c)),
          ],
        ),
      ),
    );
  }
}

/// État vide de la liste des conversations.
class _EmptyChats extends StatelessWidget {
  const _EmptyChats({required this.searching});
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space16),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Une scène animée plutôt qu'une icône figée. L'écran vide
              // est le moment où l'utilisateur se demande s'il a raté
              // quelque chose ; un mouvement doux répond que non.
              SceneAnimee(
                emoji: searching
                    ? Scenes.aucunResultat
                    : Scenes.aucuneConversation,
                iconeDeSecours: searching
                    ? Icons.search_off_rounded
                    : Icons.forum_outlined,
                taille: 92,
              ),
              const SizedBox(height: DesignTokens.space4),
              Text(
                searching ? 'Aucun résultat' : 'Aucune discussion',
                textAlign: TextAlign.center,
                style: OuroTypography.title3.copyWith(color: OuroColors.label),
              ),
              const SizedBox(height: DesignTokens.space2),
              Text(
                searching
                    ? 'Essayez un autre nom.'
                    : 'Approchez-vous d\'un appareil qui utilise Droplet : '
                        'il apparaîtra ici automatiquement.',
                textAlign: TextAlign.center,
                style: OuroTypography.subheadline.copyWith(
                  color: OuroColors.secondaryLabel,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Feuille listant les conversations archivées.
class _ArchivedSheet extends ConsumerWidget {
  const _ArchivedSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(archivedConversationsProvider);
    return FrostedSheet(
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Archivées',
              style: OuroTypography.title2.copyWith(color: OuroColors.label),
            ),
            const SizedBox(height: DesignTokens.space3),
            if (archived.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: DesignTokens.space5,
                ),
                child: Column(
                  children: [
                    SceneAnimee(
                      emoji: Scenes.aucunResultat,
                      iconeDeSecours: Icons.archive_outlined,
                      taille: 54,
                    ),
                    const SizedBox(height: DesignTokens.space2),
                    Text(
                      'Aucune conversation archivée',
                      style: OuroTypography.subheadline.copyWith(
                        color: OuroColors.secondaryLabel,
                      ),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.5,
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: archived.length,
                  itemBuilder: (context, i) {
                    final c = archived[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: DesignTokens.space2,
                      ),
                      child: Row(
                        children: [
                          PeerAvatar(pseudo: c.pseudo, radius: 20),
                          const SizedBox(width: DesignTokens.space3),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  c.pseudo,
                                  style: OuroTypography.body.copyWith(
                                    color: OuroColors.label,
                                  ),
                                ),
                                Text(
                                  c.lastMessage,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: OuroTypography.footnote.copyWith(
                                    color: OuroColors.secondaryLabel,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () async {
                              OuroHaptics.medium();
                              await StorageService.setConversationArchived(
                                c.key,
                                false,
                              );
                              ref
                                  .read(archivedRevisionProvider.notifier)
                                  .state++;
                            },
                            child: const Text('Désarchiver'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
