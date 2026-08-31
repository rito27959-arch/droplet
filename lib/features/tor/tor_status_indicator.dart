// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Indicateur d'état Tor dans l'interface.
// Affiche un petit bandeau sous la tab bar montrant l'état Tor.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/services/tor_service.dart';
import '../../core/providers/tor_providers.dart';

class TorStatusIndicator extends ConsumerStatefulWidget {
  const TorStatusIndicator({super.key});

  @override
  ConsumerState<TorStatusIndicator> createState() => _TorStatusIndicatorState();
}

class _TorStatusIndicatorState extends ConsumerState<TorStatusIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final torState = ref.watch(torStateProvider);

    return torState.when(
      data: (state) {
        if (state == TorServiceState.stopped) {
          return const SizedBox.shrink();
        }

        final (color, text, icon) = switch (state) {
          TorServiceState.connecting => (
              Colors.amber.shade700,
              'Connexion Tor…',
              Icons.sync,
            ),
          TorServiceState.connected => (
              Colors.green.shade600,
              'Tor actif',
              Icons.shield,
            ),
          TorServiceState.error => (
              Colors.red.shade600,
              'Erreur Tor',
              Icons.error_outline,
            ),
          TorServiceState.stopped => (
              Colors.grey.shade600,
              'Tor éteint',
              Icons.shield_outlined,
            ),
        };

        final opacity = state == TorServiceState.connecting
            ? (0.5 + _blinkController.value * 0.5)
            : 1.0;

        return Opacity(
          opacity: opacity,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              border: Border(
                bottom: BorderSide(color: color.withValues(alpha: 0.3)),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 14, color: color),
                const SizedBox(width: 6),
                Text(
                  text,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
