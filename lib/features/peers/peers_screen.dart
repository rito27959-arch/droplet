// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'onglet PAIRS — qui est là, autour de moi, en ce moment.
//
// « Un pair », c'est simplement un autre téléphone qui fait tourner
// Droplet et que le mien arrive à joindre : soit directement, soit en
// passant par d'autres téléphones qui font le relais. C'est l'écran le
// plus proche du cœur de l'app : sans pair, rien ne circule.
//
// CE QUI A CHANGÉ : la version précédente présentait les pairs en
// vignettes carrées dans une grille à trois colonnes, toutes marquées
// « En ligne » en vert. C'était joli et ça ne disait rien : ni par quel
// moyen on est relié (Bluetooth ? Wi-Fi ?), ni à quelle distance en
// nombre de relais, ni qui aide les autres à communiquer. Or c'est
// exactement ce qu'on vient chercher ici quand un message ne part pas.
//
// La liste montre désormais ces informations, écran par écran identique
// au reste de l'app, en mode clair comme en mode sombre.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:liquid_glass_ui_design/liquid_glass_ui.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/mesh_transport_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_list.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/mesh_visualizer.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../shared/widgets/scene_animee.dart';

class PeersScreen extends ConsumerStatefulWidget {
  const PeersScreen({super.key});

  @override
  ConsumerState<PeersScreen> createState() => _PeersScreenState();
}

class _PeersScreenState extends ConsumerState<PeersScreen> {
  @override
  Widget build(BuildContext context) {
    final peers = ref.watch(meshPeerListProvider);

    // Les personnes joignables directement d'abord, les autres ensuite :
    // en pratique on cherche presque toujours quelqu'un de proche.
    final sorted = [...peers]..sort((a, b) {
        final byHop = a.hopCount.compareTo(b.hopCount);
        return byHop != 0 ? byHop : a.pseudo.compareTo(b.pseudo);
      });
    final direct = sorted.where((p) => p.hopCount == 0).toList();
    final relayed = sorted.where((p) => p.hopCount > 0).toList();

    return OuroLargeTitleScaffold(
      title: 'Pairs',
      subtitle: peers.isEmpty
          ? 'Recherche en cours…'
          : '${peers.length} appareil${peers.length > 1 ? 's' : ''} '
              'à portée',
      backgroundColor: OuroColors.systemGroupedBackground,
      actions: [
        OuroBarButton(
          icon: Icons.hub_rounded,
          tooltip: 'Carte du réseau',
          onPressed: () {
            OuroHaptics.selection();
            context.push('/mesh-network');
          },
        ),
      ],
      slivers: [
        // Le petit schéma animé du maillage — présent uniquement quand il
        // y a réellement quelque chose à représenter.
        if (peers.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.screenMargin,
                0,
                DesignTokens.screenMargin,
                DesignTokens.space5,
              ),
              child: Container(
                decoration: BoxDecoration(
                  color: OuroColors.secondarySystemGroupedBackground,
                  borderRadius:
                      BorderRadius.circular(DesignTokens.radiusGroupedList),
                ),
                clipBehavior: Clip.antiAlias,
                child: MeshVisualizer(peerCount: peers.length, height: 110),
              ),
            ),
          ),

        if (peers.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: 60),
              child: EmptyState(
                emoji: Scenes.aucunPair,
                icon: Icons.wifi_tethering_rounded,
                title: 'Personne à portée',
                subtitle: 'Droplet cherche en permanence les appareils '
                    'proches. Rapprochez-vous de quelqu\'un qui a l\'app '
                    'pour établir la première liaison.',
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.screenMargin,
                0,
                DesignTokens.screenMargin,
                DesignTokens.space6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (direct.isNotEmpty)
                    OuroListSection(
                      header: 'À portée directe',
                      footer: relayed.isEmpty
                          ? 'Ces appareils sont joignables sans passer par '
                              'personne d\'autre.'
                          : null,
                      separatorInset: 68,
                      children: [
                        for (final p in direct) _PeerRow(peer: p),
                      ],
                    ),
                  if (direct.isNotEmpty && relayed.isNotEmpty)
                    const SizedBox(height: DesignTokens.space5),
                  if (relayed.isNotEmpty)
                    OuroListSection(
                      header: 'Par relais',
                      footer: 'Ces appareils sont hors de portée directe : '
                          'les messages leur parviennent en passant par '
                          'd\'autres téléphones.',
                      separatorInset: 68,
                      children: [
                        for (final p in relayed) _PeerRow(peer: p),
                      ],
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  UNE LIGNE DE PAIR
// ─────────────────────────────────────────────────────────────

class _PeerRow extends StatefulWidget {
  const _PeerRow({required this.peer});

  final ConnectedPeer peer;

  @override
  State<_PeerRow> createState() => _PeerRowState();
}

class _PeerRowState extends State<_PeerRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.peer;

    return GestureDetector(
      onTap: () {
        OuroHaptics.selection();
        context.push('/chat/${p.peerId}');
      },
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: Container(
        color: _pressed
            ? OuroColors.systemFill
            : OuroColors.secondarySystemGroupedBackground,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space4,
          vertical: DesignTokens.space3,
        ),
        child: Row(
          children: [
            PeerAvatar(pseudo: p.pseudo, radius: 20, online: true),
            const SizedBox(width: DesignTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          p.pseudo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OuroTypography.body.copyWith(
                            color: OuroColors.label,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      // Une passerelle relaie pour les autres : c'est
                      // grâce à elle que le réseau s'étend au-delà de la
                      // portée d'un seul appareil.
                      if (p.isGateway) ...[
                        const SizedBox(width: 6),
                        LiquidChip(
                          label: 'Relais',
                          color: OuroColors.systemTeal,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _describe(p),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OuroTypography.footnote
                        .copyWith(color: OuroColors.secondaryLabel),
                  ),
                ],
              ),
            ),
            const SizedBox(width: DesignTokens.space2),
            // Appel direct depuis la liste — 44 points de côté, comme
            // toutes les cibles tactiles de l'app.
            //
            // La voix ne passe qu'en liaison Wi-Fi directe : en Bluetooth
            // ou à travers un relais, le débit ne suit pas. Le bouton est
            // donc grisé dans ces cas, au lieu de lancer un appel qui
            // échouerait aussitôt.
            Builder(builder: (context) {
              final callable = p.hopCount == 0 &&
                  (p.transports.contains(TransportKind.localWifi) ||
                      p.transports.contains(TransportKind.nativeP2P));
              return Tooltip(
                message: callable
                    ? 'Appeler'
                    : 'Trop lent pour la voix — rapprochez-vous',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: callable
                      ? () {
                          OuroHaptics.light();
                          context.go('/call/${p.peerId}');
                        }
                      : null,
                  child: SizedBox(
                    width: 44,
                    height: 44,
                    child: Icon(
                      Icons.phone_rounded,
                      size: 20,
                      color: callable
                          ? OuroColors.accent
                          : OuroColors.quaternaryLabel,
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  /// Décrit en une ligne comment on est relié à ce pair — la seule
  /// information vraiment utile quand un message refuse de partir.
  String _describe(ConnectedPeer p) {
    final moyens = <String>[];
    if (p.transports.contains(TransportKind.localWifi)) moyens.add('Wi-Fi');
    if (p.transports.contains(TransportKind.nativeP2P)) moyens.add('Wi-Fi Direct');
    if (p.transports.contains(TransportKind.ble)) moyens.add('Bluetooth');
    final via = moyens.isEmpty ? 'Liaison inconnue' : moyens.join(' · ');

    if (p.hopCount == 0) return '$via · direct';
    return '$via · ${p.hopCount} relais';
  }
}
