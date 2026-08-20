// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'onglet ACTUS — la page officielle des statuts de Droplet.
//
// Un « statut », c'est un petit message qu'on publie non pas à quelqu'un
// en particulier, mais à TOUT le réseau autour de soi, et qui s'efface
// tout seul au bout de 24 heures. « Je suis au gymnase, il y a de l'eau
// potable », « le pont est coupé » : dans les situations où Droplet sert
// vraiment, c'est souvent l'information la plus utile de l'app.
//
// CE QUI A CHANGÉ : cet onglet s'appelait « Chaîne » et affichait de
// FAUSSES publications — de fausses vignettes vidéo, un faux « il y a
// 2h », de faux compteurs de « 24 j'aime », fabriqués à partir de la
// liste des pairs connectés. Rien de tout cela n'existait : c'était une
// maquette laissée dans l'app finie. Des chiffres inventés dans une app
// dont le but est de transmettre de l'information fiable en situation
// d'urgence, c'est le pire endroit possible pour du décor.
//
// La page montre désormais uniquement de vraies données : mon statut du
// moment (et qui l'a vu), et les statuts réellement reçus des autres par
// le mesh.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/mesh_message.dart';
import '../../core/models/status_media.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_list.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../status/status_composer.dart';
import '../../shared/widgets/scene_animee.dart';

class NewsScreen extends ConsumerStatefulWidget {
  const NewsScreen({super.key});

  @override
  ConsumerState<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends ConsumerState<NewsScreen> {
  @override
  Widget build(BuildContext context) {
    // On observe les pairs pour que la page se redessine quand le réseau
    // bouge : un nouveau pair rencontré, ce sont potentiellement de
    // nouveaux statuts qui arrivent dans la foulée.
    ref.watch(meshPeerListProvider);

    final myId = ref.watch(meshRepositoryProvider).myId;
    final active = StorageService.getActiveStatuses();

    // Un auteur = un seul statut affiché, le plus récent. Sans ce filtre,
    // quelqu'un qui publie trois fois dans la journée occuperait trois
    // lignes et repousserait tous les autres vers le bas.
    final latestByAuthor = <String, MeshStatusRecord>{};
    for (final s in active) {
      latestByAuthor.putIfAbsent(s.authorId, () => s);
    }

    final mine = latestByAuthor[myId];
    final others = latestByAuthor.values
        .where((s) => s.authorId != myId)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return OuroLargeTitleScaffold(
      title: 'Actus',
      subtitle: others.isEmpty
          ? 'Statuts du réseau · 24 h'
          : '${others.length} statut${others.length > 1 ? 's' : ''} '
              'du réseau',
      backgroundColor: OuroColors.systemGroupedBackground,
      actions: [
        OuroBarButton(
          icon: Icons.edit_square,
          tooltip: 'Publier un statut',
          onPressed: _composeStatus,
        ),
      ],
      // Tirer vers le bas relance une diffusion de mes annonces vers les
      // pairs actuellement à portée : c'est le geste « réessaie de me
      // faire entendre », utile quand on vient de croiser du monde.
      onRefresh: () async {
        await ref.read(meshRepositoryProvider).regossipAnnouncements();
        if (mounted) setState(() {});
      },
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.screenMargin,
            ),
            child: _MyStatusCard(
              status: mine,
              myId: myId,
              onCompose: _composeStatus,
            ),
          ),
        ),

        if (others.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: 60),
              child: EmptyState(
                emoji: Scenes.aucuneActualite,
                icon: Icons.podcasts_rounded,
                title: 'Aucune actu pour le moment',
                subtitle: 'Les statuts publiés par les personnes à portée '
                    'apparaîtront ici, sans passer par internet.',
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.screenMargin,
                DesignTokens.space5,
                DesignTokens.screenMargin,
                DesignTokens.space6,
              ),
              child: OuroListSection(
                header: 'Récents',
                footer: 'Un statut disparaît de lui-même 24 heures après '
                    'sa publication.',
                separatorInset: 68,
                children: [
                  for (final s in others)
                    _StatusRow(
                      status: s,
                      onTap: () {
                        OuroHaptics.selection();
                        context.go('/status/${s.authorId}');
                      },
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ── Publication ───────────────────────────────────────────────────

  Future<void> _composeStatus() async {
    // La feuille de saisie et la publication vivent dans
    // `status_composer.dart` : c'est exactement le même geste depuis le
    // menu « + » des Discussions, il ne doit donc exister qu'une seule
    // version de cet écran.
    final published = await composeStatus(context, ref);
    if (published && mounted) setState(() {});
  }
}

/// Ce qu'on écrit à la place de la légende quand un statut n'en a pas.
///
/// Un statut fait d'une seule photo n'a rien à afficher en texte : sans
/// ce repli, sa ligne apparaîtrait vide, comme si le statut était vide
/// lui aussi.
String _describeStatus(MeshStatusRecord status) {
  final caption = status.content.trim();
  if (caption.isNotEmpty) return caption;
  final media = StorageService.getStatusMedia(status.id);
  return switch (media.kind) {
    StatusMediaKind.photo => '📷 Photo',
    StatusMediaKind.video => '🎥 Vidéo',
    StatusMediaKind.voice => '🎤 Message vocal',
    StatusMediaKind.none => media.hasMusic ? '🎵 Musique' : 'Statut',
  };
}

/// La petite vignette carrée au bout d'une ligne, qui dit d'un coup
/// d'œil ce que contient le statut.
class _MediaBadge extends StatelessWidget {
  const _MediaBadge({required this.statusId});
  final String statusId;

  @override
  Widget build(BuildContext context) {
    final media = StorageService.getStatusMedia(statusId);
    if (media.kind == StatusMediaKind.none && !media.hasMusic) {
      return const SizedBox.shrink();
    }

    final (icon, color) = switch (media.kind) {
      StatusMediaKind.photo => (Icons.photo_rounded, OuroColors.systemGreen),
      StatusMediaKind.video => (Icons.videocam_rounded, OuroColors.systemIndigo),
      StatusMediaKind.voice => (Icons.mic_rounded, OuroColors.systemOrange),
      StatusMediaKind.none => (Icons.music_note_rounded, OuroColors.systemPink),
    };

    return Padding(
      padding: const EdgeInsets.only(left: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(icon, size: 14, color: color),
          ),
          // La note de musique s'ajoute au média principal quand les deux
          // sont présents : une photo AVEC une chanson n'est pas la même
          // chose qu'une photo silencieuse.
          if (media.hasMusic && media.kind != StatusMediaKind.none) ...[
            const SizedBox(width: 4),
            Icon(Icons.music_note_rounded,
                size: 13, color: OuroColors.tertiaryLabel),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  MON STATUT
// ─────────────────────────────────────────────────────────────

/// La carte du haut : ce que j'ai publié, ou l'invitation à publier.
///
/// Elle est plus grande que les lignes du dessous parce qu'elle répond à
/// deux questions différentes qu'on se pose en arrivant ici : « qu'est-ce
/// que j'ai dit ? » et surtout « est-ce que ça a été reçu ? ».
class _MyStatusCard extends StatelessWidget {
  const _MyStatusCard({
    required this.status,
    required this.myId,
    required this.onCompose,
  });

  final MeshStatusRecord? status;
  final String myId;
  final VoidCallback onCompose;

  @override
  Widget build(BuildContext context) {
    final published = status;
    final viewers = published == null
        ? const <StatusViewRecord>[]
        : StorageService.getStatusViewers(published.id);

    return GestureDetector(
      onTap: () {
        if (published == null) {
          onCompose();
        } else {
          OuroHaptics.selection();
          context.go('/status/$myId');
        }
      },
      child: Container(
        padding: const EdgeInsets.all(DesignTokens.space4),
        decoration: BoxDecoration(
          color: OuroColors.secondarySystemGroupedBackground,
          borderRadius: BorderRadius.circular(DesignTokens.radiusGroupedList),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusRing(
              published: published != null,
              child: const PeerAvatar(pseudo: 'Moi', radius: 24),
            ),
            const SizedBox(width: DesignTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mon statut',
                    style: OuroTypography.headline
                        .copyWith(color: OuroColors.label),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          published != null
                              ? _describeStatus(published)
                              : 'Appuyer pour publier sur le réseau',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: OuroTypography.subheadline.copyWith(
                            color: published != null
                                ? OuroColors.secondaryLabel
                                : OuroColors.tertiaryLabel,
                          ),
                        ),
                      ),
                      if (published != null) _MediaBadge(statusId: published.id),
                    ],
                  ),
                  if (published != null) ...[
                    const SizedBox(height: DesignTokens.space2),
                    Row(
                      children: [
                        Icon(
                          Icons.visibility_rounded,
                          size: 14,
                          color: viewers.isEmpty
                              ? OuroColors.tertiaryLabel
                              : OuroColors.accent,
                        ),
                        const SizedBox(width: 5),
                        Text(
                          // « Vu par personne » serait décourageant et
                          // surtout ambigu : hors ligne, personne vu ne
                          // veut pas dire message perdu, juste que
                          // l'accusé n'est pas encore revenu jusqu'ici.
                          viewers.isEmpty
                              ? 'Pas encore vu'
                              : 'Vu par ${viewers.length}',
                          style: OuroTypography.footnote.copyWith(
                            color: viewers.isEmpty
                                ? OuroColors.tertiaryLabel
                                : OuroColors.accent,
                          ),
                        ),
                        Text(
                          '  ·  ${_relative(published.createdAt)}',
                          style: OuroTypography.footnote
                              .copyWith(color: OuroColors.tertiaryLabel),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: DesignTokens.space2),
            Icon(
              published == null
                  ? Icons.add_circle_rounded
                  : Icons.chevron_right_rounded,
              color: published == null
                  ? OuroColors.accent
                  : OuroColors.tertiaryLabel,
              size: published == null ? 26 : 22,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  STATUT D'UN AUTRE
// ─────────────────────────────────────────────────────────────

class _StatusRow extends StatefulWidget {
  const _StatusRow({required this.status, required this.onTap});

  final MeshStatusRecord status;
  final VoidCallback onTap;

  @override
  State<_StatusRow> createState() => _StatusRowState();
}

class _StatusRowState extends State<_StatusRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final s = widget.status;

    return GestureDetector(
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: Container(
        // Assombrissement bref au doigt plutôt qu'une onde Material :
        // c'est le retour tactile des listes iOS.
        color: _pressed
            ? OuroColors.systemFill
            : OuroColors.secondarySystemGroupedBackground,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space4,
          vertical: DesignTokens.space3,
        ),
        child: Row(
          children: [
            _StatusRing(
              published: true,
              child: PeerAvatar(pseudo: s.authorPseudo, radius: 20),
            ),
            const SizedBox(width: DesignTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.authorPseudo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OuroTypography.body.copyWith(
                      color: OuroColors.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _describeStatus(s),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: OuroTypography.subheadline
                        .copyWith(color: OuroColors.secondaryLabel),
                  ),
                ],
              ),
            ),
            _MediaBadge(statusId: s.id),
            const SizedBox(width: DesignTokens.space2),
            Text(
              _relative(s.createdAt),
              style: OuroTypography.footnote
                  .copyWith(color: OuroColors.tertiaryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

/// L'anneau coloré autour de l'avatar qui signale « cette personne a
/// quelque chose à montrer » — la convention est comprise de tous depuis
/// les stories, inutile d'en inventer une autre.
class _StatusRing extends StatelessWidget {
  const _StatusRing({required this.published, required this.child});

  final bool published;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Pas d'anneau quand il n'y a rien à voir : un anneau permanent
        // ne voudrait plus rien dire.
        gradient: published
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [OuroColors.accent, OuroColors.systemIndigo],
              )
            : null,
        border: published
            ? null
            : Border.all(color: OuroColors.separator, width: 1.5),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          // Le liseré de fond qui détache l'anneau de l'avatar. Il prend
          // la couleur de la carte, pas un blanc ou un noir figé — sinon
          // il apparaîtrait comme un cerne dans l'autre mode.
          color: OuroColors.secondarySystemGroupedBackground,
        ),
        child: child,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────

/// « il y a 5 min », « il y a 3 h »… Au-delà de 24 h le statut a expiré,
/// donc aucun format en jours n'est nécessaire ici.
String _relative(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inMinutes < 1) return "à l'instant";
  if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
  return 'il y a ${diff.inHours} h';
}
