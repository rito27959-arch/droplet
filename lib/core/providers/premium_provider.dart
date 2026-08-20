// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'état « débloqué ou pas », rendu observable par les écrans.
//
// Il ne contient AUCUNE logique de vérification : tout se décide dans
// `PremiumService`, qui vérifie une signature. Ce fichier ne fait que
// transporter le verdict — et cette séparation compte, parce qu'une
// vérification éparpillée dans des providers finit toujours par avoir
// une branche qui dit « oui » un peu trop facilement.
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/premium_service.dart';
import '../services/storage_service.dart';

/// Le niveau débloqué sur cet appareil.
final premiumProvider =
    StateNotifierProvider<PremiumNotifier, NiveauPremium>((ref) {
  return PremiumNotifier();
});

class PremiumNotifier extends StateNotifier<NiveauPremium> {
  PremiumNotifier() : super(PremiumService.niveau);

  String get _identite => StorageService.currentUser?.id ?? '';

  /// Le code à communiquer pour obtenir une licence.
  String get codeAppareil => PremiumService.codeAppareil(_identite);

  /// Applique un code. Renvoie le niveau obtenu, ou `null` s'il est
  /// refusé.
  Future<NiveauPremium?> appliquer(String code) async {
    final n = await PremiumService.appliquer(code, _identite);
    if (n != null) state = n;
    return n;
  }

  /// Relit la licence enregistrée (au démarrage, ou après un changement
  /// d'identité).
  Future<void> recharger() async {
    await PremiumService.charger(_identite);
    state = PremiumService.niveau;
  }

  Future<void> oublier() async {
    await PremiumService.oublier();
    state = NiveauPremium.aucun;
  }
}

/// Raccourci : cet appareil a-t-il accès aux contenus du pack ?
final packDebloqueProvider = Provider<bool>((ref) {
  return ref.watch(premiumProvider).donneAccesAuPack;
});

/// Raccourci : cet appareil est-il en Droplet Pro ?
final estProProvider = Provider<bool>((ref) {
  return ref.watch(premiumProvider).estPro;
});
