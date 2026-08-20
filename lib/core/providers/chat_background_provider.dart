// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le choix du FOND DE DISCUSSION — le dégradé animé qui tourne d'un cran
// à chaque message envoyé (voir `telegram_gradient_background.dart`).
//
// Comme chez Telegram, ce n'est pas imposé : c'est un réglage. Et il
// comporte une option « Aucun », qui n'est pas là par politesse.
//
// ⚠️ POURQUOI L'OPTION « AUCUN » EST OBLIGATOIRE ICI.
//
// Le dégradé est calculé pixel par pixel, puis étiré. C'est peu coûteux,
// mais ce n'est pas gratuit — et Droplet tourne sur des téléphones
// modestes, parfois déjà en surchauffe (l'app a un détecteur d'état
// thermique pour cette raison précise). Un utilisateur qui préfère
// économiser sa batterie, ou qui trouve simplement que le mouvement le
// distrait, doit pouvoir l'éteindre. Un effet décoratif qu'on ne peut
// pas couper est un défaut, pas une fonctionnalité.
// ============================================================================

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/device_profile.dart';
import '../services/storage_service.dart';

const String _fondKey = 'chat_background';

/// La valeur enregistrée quand l'utilisateur ne veut aucun dégradé.
const String kFondAucun = 'aucun';

/// Le fond de discussion choisi : une clé de palette, ou [kFondAucun].
final chatBackgroundProvider =
    StateNotifierProvider<ChatBackgroundNotifier, String>((ref) {
  return ChatBackgroundNotifier();
});

class ChatBackgroundNotifier extends StateNotifier<String> {
  ChatBackgroundNotifier() : super(_load());

  static String _load() {
    final choisi = StorageService.getString(_fondKey);
    // ⚠️ SUR UN APPAREIL MODESTE, LE DÉFAUT EST « AUCUN ».
    //
    // Le dégradé recalcule une image à chaque message envoyé, et occupe
    // une surface plein écran de plus. Ce n'est pas énorme — mais sur un
    // téléphone de 2 Go, l'addition de « pas énorme » est exactement ce
    // qui fait tuer l'application.
    //
    // On ne le RETIRE pas : quelqu'un qui l'a explicitement choisi le
    // garde. On se contente de ne pas l'imposer à qui n'a rien demandé.
    if (choisi != null) return choisi;
    return DeviceProfile.menager ? kFondAucun : 'mesh';
  }

  Future<void> set(String cle) async {
    state = cle;
    await StorageService.setString(_fondKey, cle);
  }
}
