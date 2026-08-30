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
import '../../design_system/glassmorphism.dart';
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
      body: RefreshIndicator(
        onRefresh: () async {
          await Future<void>.delayed(const Duration(milliseconds: 600));
        },
        color: OuroColors.meshBlueBright,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(DesignTokens.screenMargin, 8, DesignTokens.screenMargin, DesignTokens.space8),
          children: [
            // Résumé de santé du réseau
            if (peers.isNotEmpty) ...[
              OuroCard(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                margin: const EdgeInsets.only(bottom: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _HealthStat(label: 'Pairs', value: '${peers.length}', icon: Icons.devices_rounded),
                    _HealthStat(
                      label: 'Moy. sauts',
                      value: peers.isEmpty ? '—' : (peers.map((p) => p.hopCount).reduce((a, b) => a + b) / peers.length).toStringAsFixed(1),
                      icon: Icons.route_rounded,
                    ),
                    _HealthStat(
                      label: 'Signal',
                      value: peers.any((p) => p.hopCount <= 1) ? 'Fort' : 'Moyen',
                      icon: Icons.signal_cellular_alt_rounded,
                    ),
                  ],
                ),
              ),
            ],
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

  /// Force du signal basée sur le nombre de sauts.
  int get _signalBars {
    if (peer.hopCount <= 1) return 3;
    if (peer.hopCount <= 2) return 2;
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return OuroCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      margin: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        onTap: () => _showPeerDetails(context),
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
            // Indicateur de force du signal
            ...List.generate(3, (i) {
              final active = i < _signalBars;
              return Container(
                width: 3,
                height: 6 + i * 3,
                margin: const EdgeInsets.symmetric(horizontal: 1),
                decoration: BoxDecoration(
                  color: active ? OuroColors.successGreen : OuroColors.glassBorder,
                  borderRadius: BorderRadius.circular(1),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showPeerDetails(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _PeerDetailsSheet(peer: peer),
    );
  }
}

class _PeerDetailsSheet extends StatelessWidget {
  const _PeerDetailsSheet({required this.peer});
  final ConnectedPeer peer;

  String _transportsLabel() {
    final labels = <String>[];
    if (peer.transports.contains(TransportKind.ble)) labels.add('Bluetooth');
    if (peer.transports.contains(TransportKind.localWifi)) labels.add('Wi-Fi Local');
    if (peer.transports.contains(TransportKind.nativeP2P)) labels.add('P2P Natif');
    return labels.isEmpty ? '—' : labels.join(', ');
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: OuroColors.glassBg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: OuroColors.glassBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Row(
            children: [
              PeerAvatar(pseudo: peer.pseudo, radius: 28, online: true),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(peer.pseudo, style: TextStyle(color: OuroColors.textPrimary, fontSize: 18, fontWeight: FontWeight.w700)),
                    if (peer.isGateway)
                      Text('Passerelle active', style: TextStyle(color: OuroColors.meshBlueBright, fontSize: 12)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _DetailRow(icon: Icons.route_rounded, label: 'Chemin', value: '${peer.hopCount} saut${peer.hopCount > 1 ? 's' : ''}'),
          _DetailRow(icon: Icons.wifi_tethering_rounded, label: 'Transport', value: _transportsLabel()),
          _DetailRow(icon: Icons.battery_std_rounded, label: 'Batterie', value: '${(peer.batteryLevel * 100).round()}%'),
          _DetailRow(icon: Icons.speed_rounded, label: 'Score', value: '${peer.connectionScore}'),
          if (peer.reconnecting)
            _DetailRow(icon: Icons.sync_rounded, label: 'État', value: 'Reconnexion'),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: OuroColors.textTertiary),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(color: OuroColors.textSecondary, fontSize: 13)),
          const Spacer(),
          Text(value, style: TextStyle(color: OuroColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _HealthStat extends StatelessWidget {
  const _HealthStat({required this.label, required this.value, required this.icon});
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: OuroColors.meshBlueBright),
        const SizedBox(height: 4),
        Text(value, style: TextStyle(color: OuroColors.textPrimary, fontSize: 16, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(color: OuroColors.textTertiary, fontSize: 11)),
      ],
    );
  }
}
