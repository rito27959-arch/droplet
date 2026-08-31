// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Providers Riverpod pour le service Tor.
//
// Fournit un accès global à l'état de Tor et au service lui-même pour
// que les widgets puissent lire/écouter l'état sans couplage direct.
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/tor_service.dart';

/// Instance globale du service Tor.
///
/// Créé au démarrage de l'app, partagé entre tous les widgets.
final torServiceProvider = Provider<TorService>((ref) {
  final service = TorService();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Stream de l'état Tor — pour les widgets qui veulent rebuild.
final torStateProvider = StreamProvider<TorServiceState>((ref) {
  final service = ref.watch(torServiceProvider);
  return service.stateStream;
});

/// Vrai si Tor est actuellement connecté.
final torConnectedProvider = Provider<bool>((ref) {
  final state = ref.watch(torStateProvider);
  return state.valueOrNull == TorServiceState.connected;
});
