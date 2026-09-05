// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Providers Riverpod pour le service Tor.
//
// Fournit un accès global à l'état de Tor et au service lui-même pour
// que les widgets puissent lire/écouter l'état sans couplage direct.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/storage_service.dart';
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

// ── Le réglage « Tor activé » ────────────────────────────────────────────────
//
// ⚠️ CE QUI MANQUAIT : PERSONNE NE DEMANDAIT À TOR DE DÉMARRER.
//
// Tout existait — le service, le transport, l'identité .onion, le client
// HTTP, l'annuaire, trois écrans — et rien ne les reliait à
// l'application : aucune route vers les réglages Tor, aucun appel à
// `start()` au lancement, et le choix de l'utilisateur n'était nulle part
// enregistré. Activer Tor dans l'écran de réglages marchait le temps de
// la session, puis tout retombait au lancement suivant, sans message.
//
// Ce notifier est le chaînon manquant : il retient le choix, et le
// rejoue au démarrage.

const String _cleTorActif = 'tor_actif';

/// L'utilisateur veut-il faire passer Droplet par Tor ?
final torActifProvider =
    StateNotifierProvider<TorActifNotifier, bool>((ref) {
  return TorActifNotifier(ref.watch(torServiceProvider));
});

class TorActifNotifier extends StateNotifier<bool> {
  TorActifNotifier(this._service) : super(_lire());

  final TorService _service;

  static bool _lire() => StorageService.getString(_cleTorActif) == 'oui';

  /// Rallume Tor au lancement si l'utilisateur l'avait laissé allumé.
  ///
  /// À appeler une fois l'application démarrée. Volontairement séparé du
  /// constructeur : lancer un circuit Tor pendant la construction d'un
  /// provider bloquerait la première image sur dix à trente secondes de
  /// négociation réseau.
  Future<void> restaurer() async {
    if (!state) return;
    await _service.start();
  }

  Future<void> definir(bool actif) async {
    state = actif;
    await StorageService.setString(_cleTorActif, actif ? 'oui' : 'non');
    if (actif) {
      await _service.start();
    } else {
      await _service.stop();
    }
  }
}

/// Démarre Tor au lancement s'il était activé.
///
/// Se contente d'observer : aucun écran n'a besoin de savoir que ceci
/// existe.
final torDemarrageProvider = Provider<void>((ref) {
  final notifier = ref.read(torActifProvider.notifier);
  // Après la première image, jamais pendant.
  unawaited(Future<void>.microtask(() async {
    try {
      await notifier.restaurer();
    } catch (e) {
      debugPrint('[Tor] restauration impossible: $e');
    }
  }));
});
