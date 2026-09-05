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
import 'package:liquid_glass_ui_design/liquid_glass_ui.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/crash_journal.dart';
import '../../core/services/media_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../shared/widgets/bulle_guide.dart';
import '../settings/journal_sheet.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/ouro_pressable.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../shared/widgets/scene_animee.dart';
import '../status/status_composer.dart';
import '../../shared/widgets/ios_magnifier_overlay.dart';

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  bool _meshStarted = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// Un rapport d'erreur attend d'être envoyé.
  bool _rapportEnAttente = false;

  // Les points désignés par la visite guidée. Ce sont les trois choses
  // qu'on ne devine pas : que « zéro pair » n'est pas une panne, que le
  // réseau se regarde, et que la conversation commence par un geste.
  final _cleReseau = GlobalKey();
  final _clePlus = GlobalKey();
  final _cleReglages = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ensureMesh();
    _chercherUnRapport();
    // Après la première image : les boutons doivent exister pour qu'on
    // puisse les désigner.
    WidgetsBinding.instance.addPostFrameCallback((_) => _visiteGuidee());
    _searchCtrl.addListener(
      () => setState(() => _query = _searchCtrl.text.trim().toLowerCase()),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// La visite guidée du premier lancement.
  ///
  /// ⚠️ TROIS ÉTAPES, PAS DIX. Ce ne sont pas les fonctions de
  /// l'application qu'on explique — on les découvre très bien seul.
  /// Ce sont les trois comportements que Droplet ne PARTAGE PAS avec
  /// les messageries habituelles, et que l'on prend pour des pannes
  /// faute d'un mot d'explication :
  ///
  ///   • « zéro pair à proximité » est l'état normal, pas une erreur ;
  ///   • un message peut mettre des heures sans être perdu ;
  ///   • le réseau se regarde, et c'est là qu'on comprend pourquoi.
  ///
  /// Tout le reste — les statuts, les appels, la carte — ressemble
  /// assez à ce que les gens connaissent pour se passer de tutoriel.
  void _visiteGuidee() {
    if (!mounted) return;
    Guide.lancer(
      context,
      nom: 'accueil',
      etapes: [
        EtapeGuide(
          cible: _cleReseau,
          titre: 'Personne à proximité ? C\'est normal',
          texte: 'Droplet ne passe par aucun serveur : il parle aux '
              'téléphones à portée. Ici vous voyez qui est joignable, et '
              'par quelle radio. Zéro pair ne veut pas dire que ça ne '
              'marche pas — juste que personne n\'est encore là.',
        ),
        EtapeGuide(
          cible: _clePlus,
          titre: 'Écrivez même sans personne',
          texte: 'Un message écrit maintenant attend sur votre téléphone '
              'et repart dès qu\'un appareil passe à portée — dans la '
              'rue, dans un taxi. Il n\'est pas perdu, il patiente.',
        ),
        EtapeGuide(
          cible: _cleReglages,
          titre: 'Sauvegardez votre identité',
          texte: 'Sans serveur, personne ne peut vous rendre votre compte. '
              'Exportez votre identité depuis les réglages : sans cette '
              'sauvegarde, un téléphone perdu emporte tout.',
        ),
      ],
    );
  }

  /// Regarde si l'application s'est fermée anormalement depuis la
  /// dernière fois qu'on a regardé.
  ///
  /// ⚠️ ON DEMANDE, ON N'ENVOIE PAS. Le journal ne contient aucun
  /// message ni contact — mais c'est un fichier technique, et
  /// l'expédier sans le dire serait exactement ce que Droplet reproche
  /// aux autres applications. C'est l'utilisateur qui décide, à chaque
  /// fois.
  Future<void> _chercherUnRapport() async {
    final oui = await CrashJournal.aDuNouveau();
    if (mounted && oui) setState(() => _rapportEnAttente = true);
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

  Future<void> _pinConversation(Conversation c) async {
    OuroHaptics.medium();
    await StorageService.setConversationPinned(c.key, !c.isPinned);
    if (!mounted) return;
    ref.read(pinMuteRevisionProvider.notifier).state++;
  }

  Future<void> _muteConversation(Conversation c) async {
    OuroHaptics.medium();
    await StorageService.setConversationMuted(c.key, !c.isMuted);
    if (!mounted) return;
    ref.read(pinMuteRevisionProvider.notifier).state++;
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
    ref.watch(pinMuteRevisionProvider);
    final all = ref.watch(conversationsProvider);
    final conversations = _query.isEmpty
        ? all
        : all
            .where((c) => c.pseudo.toLowerCase().contains(_query))
            .toList();
    final peers = ref.watch(meshPeerListProvider);
    final archivedCount = StorageService.getArchivedConversations().length;

    // ── LE WIDGET D'ÉCRAN D'ACCUEIL ──────────────────────────────
    //
    // ⚠️ MIS À JOUR DEPUIS ICI, ET APRÈS L'IMAGE.
    //
    // C'est le seul écran qui connaît à la fois le nombre de messages
    // non lus et le nombre de pairs — les deux chiffres du widget. Les
    // recalculer ailleurs aurait donné deux comptes qui divergent, et un
    // widget qui contredit l'application est pire qu'un widget absent.
    //
    // `addPostFrameCallback` parce qu'un appel de canal natif pendant
    // `build` déclenche une reconstruction en pleine construction. Et
    // `unawaited` parce que l'affichage ne doit jamais attendre le
    // lanceur d'Android.
    final nonLus = all.fold<int>(0, (t, c) => t + c.unreadCount);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(MediaService.majWidget(
        nonLus: nonLus,
        pairs: peers.length,
      ));
    });

    return IosMagnifierOverlay(
      child: OuroLargeTitleScaffold(
      title: 'Discussions',
      // Le sous-titre remplace à lui seul l'ancienne grande carte animée
      // du réseau : l'information utile (« combien de personnes sont
      // joignables ») en une ligne, au lieu d'un tiers d'écran.
      subtitle: peers.isEmpty
          ? 'Recherche de pairs…'
          : '${peers.length} pair${peers.length > 1 ? 's' : ''} à proximité',
      onRefresh: _onRefresh,
      floatingNotification: _MeshNotificationBanner(
        conversations: all,
      ),
      leading: KeyedSubtree(
        key: _cleReglages,
        child: OuroBarButton(
          icon: Icons.settings_outlined,
          tooltip: 'Réglages',
          onPressed: () => context.push('/settings'),
        ),
      ),
      actions: [
        KeyedSubtree(
          key: _cleReseau,
          child: OuroBarButton(
            icon: Icons.wifi_tethering_rounded,
            tooltip: 'Réseau mesh',
            onPressed: () => context.push('/mesh-network'),
          ),
        ),
        KeyedSubtree(
          key: _clePlus,
          child: OuroBarButton(
            icon: Icons.add_rounded,
            tooltip: 'Nouveau',
            onPressed: _showComposeMenu,
          ),
        ),
      ],
      slivers: [
        if (_rapportEnAttente)
          SliverToBoxAdapter(
            child: _BandeauRapport(
              onEnvoyer: () async {
                await afficherJournal(context);
                await CrashJournal.marquerVu();
                if (mounted) setState(() => _rapportEnAttente = false);
              },
              onIgnorer: () async {
                await CrashJournal.marquerVu();
                if (mounted) setState(() => _rapportEnAttente = false);
              },
            ),
          ),
        SliverToBoxAdapter(child: _SearchField(controller: _searchCtrl)),

        if (_query.isEmpty && archivedCount > 0)
          SliverToBoxAdapter(
            child: _ArchivedRow(count: archivedCount, onTap: _openArchived),
          ),

        if (conversations.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _EmptyChats(
                key: ValueKey(_query.isEmpty ? 'empty' : 'search_$_query'),
                searching: _query.isNotEmpty,
              ),
            ),
          )
        else ...[
          // ── Épinglées ─────────────────────────────────────────────
          if (_query.isEmpty && conversations.any((c) => c.isPinned)) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(
                  DesignTokens.screenMargin,
                  DesignTokens.space3,
                  DesignTokens.screenMargin,
                  DesignTokens.space1,
                ),
                child: Text(
                  'ÉPINGLÉES',
                  style: OuroTypography.caption1.copyWith(
                    color: OuroColors.secondaryLabel,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
            SliverList.builder(
              key: ValueKey('pinned_${conversations.length}'),
              itemCount: conversations.where((c) => c.isPinned).length,
              itemBuilder: (context, i) {
                final pinned = conversations.where((c) => c.isPinned).toList();
                return _ConversationRow(
                  key: ValueKey(pinned[i].key),
                  conversation: pinned[i],
                  onArchive: () => _archiveConversation(pinned[i]),
                  onPin: () => _pinConversation(pinned[i]),
                  onMute: () => _muteConversation(pinned[i]),
                );
              },
            ),
          ],
          // ── Autres ────────────────────────────────────────────────
          if (_query.isEmpty && conversations.any((c) => !c.isPinned))
            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  DesignTokens.screenMargin,
                  conversations.any((c) => c.isPinned) ? DesignTokens.space3 : DesignTokens.space1,
                  DesignTokens.screenMargin,
                  DesignTokens.space1,
                ),
                child: Text(
                  'DISCUSSIONS',
                  style: OuroTypography.caption1.copyWith(
                    color: OuroColors.secondaryLabel,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
          SliverList.builder(
            key: ValueKey('list_${_query}_${conversations.length}'),
            itemCount: _query.isEmpty
                ? conversations.where((c) => !c.isPinned).length
                : conversations.length,
            itemBuilder: (context, i) {
              final list = _query.isEmpty
                  ? conversations.where((c) => !c.isPinned).toList()
                  : conversations;
              return _ConversationRow(
                key: ValueKey(list[i].key),
                conversation: list[i],
                onArchive: () => _archiveConversation(list[i]),
                onPin: () => _pinConversation(list[i]),
                onMute: () => _muteConversation(list[i]),
              );
            },
          ),
        ],
      ],
      ),
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
/// Le bandeau qui signale un rapport d'erreur non envoyé.
///
/// ── ⚠️ POURQUOI IL EXISTE, ET POURQUOI IL EST DISCRET ─────────────
///
/// Droplet n'a aucun serveur : quand l'application se ferme toute seule
/// chez quelqu'un, la seule trace au monde est un fichier sur son
/// téléphone. S'il ne l'envoie pas, le défaut n'existe pour personne —
/// et il ne sera jamais corrigé.
///
/// Or ce journal vivait au fond des réglages, sans que rien ne signale
/// jamais son contenu. Un testeur qui plante rouvre l'application et
/// continue : aller voir demande de se souvenir qu'un journal existe, à
/// un moment où l'on pensait à autre chose. Les rapports ne remontaient
/// donc pas, par oubli et non par mauvaise volonté.
///
/// Il est ambre et non rouge : il ne s'est rien passé de grave pour
/// l'utilisateur — ses messages sont intacts, rien n'est perdu. Le
/// rouge dirait « danger » là où il n'y a qu'une demande de service.
///
/// Et il porte un « Plus tard » qui le fait taire DÉFINITIVEMENT pour
/// ces lignes-là. Un bandeau qu'on ne peut pas congédier devient un
/// harcèlement, et la première chose qu'on apprend à faire d'un
/// harcèlement est de ne plus le lire.
class _BandeauRapport extends StatelessWidget {
  const _BandeauRapport({required this.onEnvoyer, required this.onIgnorer});

  final VoidCallback onEnvoyer;
  final VoidCallback onIgnorer;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.screenMargin,
        DesignTokens.space2,
        DesignTokens.screenMargin,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(DesignTokens.space4),
        decoration: BoxDecoration(
          color: OuroColors.systemOrange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(
            color: OuroColors.systemOrange.withValues(alpha: 0.32),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded,
                    size: 19, color: OuroColors.systemOrange),
                const SizedBox(width: DesignTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Droplet s\'est fermé de façon inattendue',
                        style: OuroTypography.headline
                            .copyWith(color: OuroColors.label),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Droplet n\'a aucun serveur : sans votre envoi, ce '
                        'défaut n\'existe pour personne. Le rapport ne '
                        'contient ni messages, ni contacts, ni clés.',
                        style: OuroTypography.footnote.copyWith(
                          color: OuroColors.secondaryLabel,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.space3),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: onEnvoyer,
                    style: FilledButton.styleFrom(
                      backgroundColor: OuroColors.systemOrange,
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusMd),
                      ),
                    ),
                    child: Text(
                      'Envoyer le rapport',
                      style: OuroTypography.subheadline.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: DesignTokens.space3),
                TextButton(
                  onPressed: onIgnorer,
                  child: Text(
                    'Plus tard',
                    style: OuroTypography.subheadline
                        .copyWith(color: OuroColors.secondaryLabel),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

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
        child: OuroCard(
          padding: EdgeInsets.zero,
          borderRadius: DesignTokens.radiusMd,
          child: TextField(
            controller: controller,
            style: OuroTypography.body.copyWith(color: OuroColors.label),
            cursorColor: OuroColors.accent,
            magnifierConfiguration: TextMagnifier.adaptiveMagnifierConfiguration,
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
              fillColor: Colors.transparent,
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
  const _ConversationRow({
    super.key,
    required this.conversation,
    required this.onArchive,
    required this.onPin,
    required this.onMute,
  });

  final Conversation conversation;
  final VoidCallback onArchive;
  final VoidCallback onPin;
  final VoidCallback onMute;

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
                    child: LiquidBadge(
                      text: c.unreadCount > 9 ? '9+' : '${c.unreadCount}',
                      color: OuroColors.accent,
                      child: const SizedBox.shrink(),
                    ),
                  )
                : null,
          ),
          Hero(
            tag: 'avatar-${c.peerId}',
            child: PeerAvatar(
              pseudo: c.pseudo,
              radius: _avatarSize / 2,
              online: c.isOnline,
            ),
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
                          color: c.isMuted
                              ? OuroColors.tertiaryLabel
                              : OuroColors.label,
                        ),
                      ),
                    ),
                    // Icône d'épingle pour les conversations épinglées.
                    if (c.isPinned) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.push_pin_rounded,
                        size: 12,
                        color: OuroColors.secondaryLabel,
                      ),
                    ],
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
                Row(
                  children: [
                    // Icône de mode silencieux.
                    if (c.isMuted) ...[
                      Icon(
                        Icons.volume_off_rounded,
                        size: 14,
                        color: OuroColors.tertiaryLabel,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        c.lastMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: OuroTypography.subheadline.copyWith(
                          color: OuroColors.secondaryLabel,
                        ),
                      ),
                    ),
                  ],
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
            onLongPress: () => _showContextMenu(),
            child: row,
          ),
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

  void _showContextMenu() {
    OuroHaptics.medium();
    final c = widget.conversation;
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FrostedSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // En-tête : nom de la conversation
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.space4,
                vertical: DesignTokens.space3,
              ),
              child: Row(
                children: [
                  PeerAvatar(
                    pseudo: c.pseudo,
                    radius: 20,
                    online: c.isOnline,
                  ),
                  const SizedBox(width: DesignTokens.space3),
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
                ],
              ),
            ),
            Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
            _SheetAction(
              icon: c.isPinned
                  ? Icons.push_pin_rounded
                  : Icons.push_pin_outlined,
              label: c.isPinned ? 'Désépingler' : 'Épingler en haut',
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onPin();
              },
            ),
            Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
            _SheetAction(
              icon: c.isMuted
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
              label: c.isMuted ? 'Activer les notifications' : 'Couper le son',
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onMute();
              },
            ),
            Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
            _SheetAction(
              icon: Icons.archive_rounded,
              label: 'Archiver',
              onTap: () {
                Navigator.of(sheetContext).pop();
                widget.onArchive();
              },
            ),
          ],
        ),
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
  const _EmptyChats({super.key, required this.searching});
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
                      // Enfoncement iOS plutôt que l'onde de Material —
                      // c'est la même liste de conversations que dans
                      // l'écran principal, elle doit répondre pareil.
                      child: OuroPressable(
                        onTap: () {
                          Navigator.of(context).pop();
                          if (c.peerId != null) {
                            context.push('/chat/${c.peerId}');
                          } else if (c.groupId != null) {
                            context.push('/group/${c.groupId}');
                          }
                        },
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

/// ─────────────────────────────────────────────────────────────
///  NOTIFICATION MESH FLOTTANTE
/// ─────────────────────────────────────────────────────────────
///
/// Bulle flottante en haut de l'écran d'accueil qui montre le dernier
/// message reçu du mesh, avec un mini avatar et un preview. Pas de push
/// notification classique — c'est un élément in-app qui apparaît quand
/// un message arrive pendant qu'on est sur l'écran d'accueil.
///
/// L'animation est un slide-in par le haut avec un léger bounce, puis
/// un slide-out après 4 secondes ou au tap.
class _MeshNotificationBanner extends StatefulWidget {
  const _MeshNotificationBanner({required this.conversations});

  final List<Conversation> conversations;

  @override
  State<_MeshNotificationBanner> createState() =>
      _MeshNotificationBannerState();
}

class _MeshNotificationBannerState extends State<_MeshNotificationBanner>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<Offset>? _slideAnim;
  Conversation? _lastUnread;
  bool _dismissed = false;

  @override
  void didUpdateWidget(_MeshNotificationBanner old) {
    super.didUpdateWidget(old);
    _checkForNewMessage();
  }

  void _checkForNewMessage() {
    if (_dismissed) return;
    // Trouver la conversation avec le dernier message non lu
    final unread = widget.conversations
        .where((c) => c.unreadCount > 0)
        .toList()
      ..sort((a, b) => b.lastTimestamp.compareTo(a.lastTimestamp));

    if (unread.isEmpty) {
      if (_ctrl?.isAnimating == true) _dismiss();
      return;
    }

    final latest = unread.first;
    // Si c'est un nouveau message non lu qu'on n'affichait pas
    if (_lastUnread?.key != latest.key) {
      _lastUnread = latest;
      _show(latest);
    }
  }

  void _show(Conversation conv) {
    _dismissed = false;
    _ctrl?.dispose();
    _ctrl = AnimationController(
      vsync: this,
      // 350 ms : la durée de référence des transitions iOS. Les 500 ms
      // d'origine servaient à laisser le rebond se terminer ; sans rebond,
      // elles ne font plus qu'attendre.
      duration: DesignTokens.durationStandard,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _ctrl!,
      // ⚠️ C'ÉTAIT `Curves.elasticOut`. Une bannière de message non lu qui
      // rebondit en descendant du haut est exactement ce que
      // `design_tokens.dart` interdit : elle dépasse sa position finale,
      // revient, et retarde de plusieurs dixièmes de seconde la lecture du
      // message — à chaque message, toute la journée. iOS ne fait jamais
      // rebondir une notification.
      curve: DesignTokens.curveEnter,
    ));
    _ctrl!.forward();
    // Auto-masquer après 4 secondes
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && !_dismissed) _dismiss();
    });
  }

  void _dismiss() {
    _dismissed = true;
    _ctrl?.reverse().then((_) {
      if (mounted) setState(() => _lastUnread = null);
    });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conv = _lastUnread;
    if (conv == null || _ctrl == null || _slideAnim == null) {
      return const SizedBox.shrink();
    }

    return SlideTransition(
      position: _slideAnim!,
      child: GestureDetector(
        onTap: () {
          _dismiss();
          // TODO: naviguer vers la conversation
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: OuroColors.systemBackground.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              PeerAvatar(pseudo: conv.pseudo, radius: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      conv.pseudo,
                      style: OuroTypography.subheadline.copyWith(
                        color: OuroColors.label,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      conv.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OuroTypography.footnote.copyWith(
                        color: OuroColors.secondaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: OuroColors.meshBlueBright,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${conv.unreadCount}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
