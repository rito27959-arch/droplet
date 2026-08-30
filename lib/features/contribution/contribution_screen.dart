import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/mesh_message.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/liquid_bridge.dart';

Color rankColor(ContributionRank rank) {
  return switch (rank) {
    ContributionRank.bronze => const Color(0xFFCD7F32),
    ContributionRank.argent => const Color(0xFFC0C0C0),
    ContributionRank.or => const Color(0xFFFFD700),
    ContributionRank.diamant => OuroColors.accentTeal,
  };
}

IconData rankIcon(ContributionRank rank) {
  return switch (rank) {
    ContributionRank.bronze => Icons.workspace_premium_outlined,
    ContributionRank.argent => Icons.workspace_premium_outlined,
    ContributionRank.or => Icons.workspace_premium_rounded,
    ContributionRank.diamant => Icons.diamond_rounded,
  };
}

/// Détail de la contribution au mesh : points gagnés en relayant des
/// messages pour les autres et en restant disponible comme relais
/// (gateway). Purement cosmétique — aucune fonctionnalité déblocable.
class ContributionScreen extends StatelessWidget {
  const ContributionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final points = StorageService.getContributionPoints();
    final rank = points.rank;
    final next = rank.next;
    final color = rankColor(rank);

    final progress = next == null
        ? 1.0
        : ((points.totalPoints - rank.minPoints) / (next.minPoints - rank.minPoints)).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: OuroColors.background,
      appBar: AppBar(
        backgroundColor: OuroColors.background,
        elevation: 0,
        leading: const OuroBackButton(fallback: '/settings'),
        title: Text('Ma contribution',
            style: TextStyle(color: OuroColors.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        children: [
          Center(
            child: Column(
              children: [
                LiquidGlassBox(
                  padding: EdgeInsets.zero,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withValues(alpha: 0.16),
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Icon(rankIcon(rank), color: color, size: 40),
                  ),
                )
                    .animate()
                    .fadeIn(duration: DesignTokens.durationSlow)
                    .scaleXY(begin: 0.5, curve: DesignTokens.curveBounce, duration: DesignTokens.durationSlow),
                const SizedBox(height: 14),
                Text(rank.label,
                        style: TextStyle(color: color, fontSize: 22, fontWeight: FontWeight.w800))
                    .animate()
                    .fadeIn(delay: 120.ms, duration: DesignTokens.durationNormal),
                const SizedBox(height: 4),
                Text('${points.totalPoints} points',
                        style: TextStyle(color: OuroColors.textSecondary, fontSize: 15))
                    .animate()
                    .fadeIn(delay: 180.ms, duration: DesignTokens.durationNormal),
              ],
            ),
          ),
          const SizedBox(height: 28),
          if (next != null) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: progress),
                duration: DesignTokens.durationXSlow,
                curve: DesignTokens.curveEmphasis,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 8,
                  backgroundColor: OuroColors.glassBg,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${next.minPoints - points.totalPoints} points avant le palier ${next.label}',
              style: TextStyle(color: OuroColors.textTertiary, fontSize: 12),
            ),
            const SizedBox(height: 24),
          ],
          _StatRow(
            icon: Icons.forward_to_inbox_rounded,
            label: 'Messages relayés pour d\'autres',
            value: '${points.relaysCount}',
            points: '+${points.relaysCount * 10} pts',
            delayMs: 0,
          ),
          const SizedBox(height: 10),
          _StatRow(
            icon: Icons.podcasts_rounded,
            label: 'Minutes en mode relais (gateway)',
            value: '${points.gatewayMinutes}',
            points: '+${points.gatewayMinutes * 2} pts',
            delayMs: 60,
          ),
          const SizedBox(height: 24),
          Text(
            'Chaque message que ton appareil relaie pour d\'autres, et chaque minute où '
            'il reste disponible comme relais, aide le réseau mesh à couvrir plus de '
            'monde, plus loin. Ce badge n\'a aucun effet sur l\'app — c\'est juste une '
            'reconnaissance de ta contribution.',
            style: TextStyle(color: OuroColors.textTertiary, fontSize: 12, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.icon, required this.label, required this.value, required this.points, this.delayMs = 0});
  final IconData icon;
  final String label;
  final String value;
  final String points;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return OuroCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(icon, color: OuroColors.meshBlueBright, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: TextStyle(color: OuroColors.textPrimary, fontSize: 13)),
          ),
          Text(value, style: TextStyle(color: OuroColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
          const SizedBox(width: 8),
          Text(points, style: TextStyle(color: OuroColors.textTertiary, fontSize: 11)),
        ],
      ),
    )
        .animate()
        .fadeIn(delay: (200 + delayMs).ms, duration: DesignTokens.durationNormal)
        .slideY(begin: 0.15, curve: DesignTokens.curveEmphasis);
  }
}
