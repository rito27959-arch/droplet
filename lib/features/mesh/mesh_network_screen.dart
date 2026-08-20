// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est l'écran plein écran « Réseau mesh », qu'on ouvre en tapant sur
// la petite carte animée de l'écran d'accueil. En haut, un grand
// `MeshVisualizer` (voir `mesh_visualizer.dart`) plus gros que sur
// l'écran d'accueil, et en dessous, la VRAIE liste détaillée de chaque
// pair connecté : son pseudo, s'il joue le rôle de passerelle
// (« gateway »), par quel chemin il est joignable (Bluetooth, Wi-Fi,
// Nearby), et à combien de « sauts » il se trouve (0 = juste à côté,
// plus le nombre est grand, plus le message a dû passer par
// d'intermédiaires pour arriver jusqu'à lui).
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/mesh_transport_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/mesh_visualizer.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/scene_animee.dart';

/// Vue plein écran du réseau mesh — le visualiseur (orbites, ondes) qui
/// n'était jusqu'ici qu'un composant décoratif dans l'en-tête de
/// `chats_screen.dart` mérite sa propre page pour un app « digne des
/// grandes startups » : les pairs réellement connectés listés en dessous,
/// pas seulement des points abstraits.
class MeshNetworkScreen extends ConsumerWidget {
  const MeshNetworkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final peers = ref.watch(meshPeerListProvider);

    return Scaffold(
      backgroundColor: OuroColors.background,
      appBar: AppBar(
        backgroundColor: OuroColors.background,
        elevation: 0,
        leading: const OuroBackButton(),
        title: Text('Réseau mesh',
            style: TextStyle(color: OuroColors.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(DesignTokens.screenMargin, 8, DesignTokens.screenMargin, DesignTokens.space8),
        children: [
          MeshVisualizer(peerCount: peers.length, height: 280),
          const SizedBox(height: 8),
          Center(
            child: Text(
              peers.isEmpty
                  ? 'Recherche de pairs à portée…'
                  : '${peers.length} pair${peers.length > 1 ? 's' : ''} connecté${peers.length > 1 ? 's' : ''}',
              style: TextStyle(color: OuroColors.textTertiary, fontSize: 13),
            ),
          ),
          const SizedBox(height: 24),
          if (peers.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 24),
              child: EmptyState(
                emoji: Scenes.rechercheDePairs,
                icon: Icons.wifi_tethering_rounded,
                title: 'Aucun pair connecté pour le moment',
                subtitle: 'Rapproche-toi d\'un autre appareil avec Droplet installé — la découverte se fait automatiquement, sans configuration.',
              ),
            )
          else ...[
            Text('Pairs connectés',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: OuroColors.textSecondary, letterSpacing: 0.3)),
            const SizedBox(height: 10),
            ...peers.asMap().entries.map((entry) => _PeerRow(peer: entry.value)
                .animate()
                .fadeIn(delay: (entry.key * 50).ms, duration: DesignTokens.durationNormal)
                .slideY(begin: 0.15, curve: DesignTokens.curveEmphasis)),
          ],
        ],
      ),
    );
  }
}

/// Une ligne détaillée pour UN pair connecté — avatar, pseudo, badge
/// « passerelle » éventuel, et la petite ligne technique (chemins
/// utilisés + nombre de sauts).
class _PeerRow extends StatelessWidget {
  const _PeerRow({required this.peer});
  final ConnectedPeer peer;

  /// Fabrique le texte « BLE · Wi-Fi » à partir des chemins réellement
  /// utilisés pour joindre ce pair.
  String _transportsLabel() {
    final labels = <String>[];
    if (peer.transports.contains(TransportKind.ble)) labels.add('BLE');
    if (peer.transports.contains(TransportKind.localWifi)) labels.add('Wi-Fi');
    if (peer.transports.contains(TransportKind.nativeP2P)) labels.add('P2P');
    return labels.isEmpty ? '—' : labels.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: OuroColors.glassBg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(color: OuroColors.glassBorder),
      ),
      child: Row(
        children: [
          PeerAvatar(pseudo: peer.pseudo, radius: 20, online: true),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(peer.pseudo, style: TextStyle(color: OuroColors.textPrimary, fontWeight: FontWeight.w700)),
                    if (peer.isGateway) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.podcasts_rounded, size: 14, color: OuroColors.meshBlueBright),
                    ],
                  ],
                ),
                Text(
                  '${_transportsLabel()} · ${peer.hopCount} saut${peer.hopCount > 1 ? 's' : ''}',
                  style: TextStyle(color: OuroColors.textTertiary, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
