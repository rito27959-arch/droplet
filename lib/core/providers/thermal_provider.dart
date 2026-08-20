// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LA SURVEILLANCE DE LA TEMPÉRATURE DU TÉLÉPHONE, pour que l'application
// sache quand se faire discrète.
//
// ── Pourquoi une app de messagerie s'en préoccupe ─────────────────────
//
// Parce qu'elle n'est pas seule sur l'appareil, et que Droplet en demande
// déjà beaucoup : Bluetooth et Wi-Fi qui balaient en permanence, chiffrement
// de chaque message, relais des messages des autres. Ajouter par-dessus un
// shader qui recalcule la réfraction de tout ce qui passe sous la barre
// d'onglets, à chaque image, c'est tenable sur un appareil frais — et c'est
// exactement ce qu'il ne faut pas faire sur un appareil déjà au bord de la
// coupure.
//
// Android publie ce niveau de 0 (rien) à 6 (arrêt imminent). À partir de
// 3, il commence lui-même à débrancher des choses — on a vu l'encodeur
// vidéo disparaître à 4, sans un mot, pendant un enregistrement.
//
// Le principe retenu : SPECTACULAIRE PAR DÉFAUT, SOBRE QUAND IL LE FAUT.
// L'effet coûteux s'efface tout seul, et revient tout seul. L'utilisateur
// n'a rien à comprendre ni à régler.
// ============================================================================

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/media_service.dart';

/// Vrai quand le téléphone est trop sollicité pour les effets coûteux.
final deviceUnderThermalStressProvider =
    StateNotifierProvider<ThermalWatcher, bool>((ref) => ThermalWatcher());

class ThermalWatcher extends StateNotifier<bool> with WidgetsBindingObserver {
  ThermalWatcher() : super(false) {
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _timer = Timer.periodic(_interval, (_) => _refresh());
  }

  Timer? _timer;

  /// ⚠️ 45 SECONDES, PAS DAVANTAGE, ET PAS MOINS.
  ///
  /// Un téléphone ne passe pas de tiède à brûlant en trois secondes :
  /// interroger plus souvent ne changerait rien à ce qu'on apprend, et
  /// réveillerait le processeur pour rien — ce qui, pour une surveillance
  /// de la chauffe, serait plutôt comique. Beaucoup plus rarement, en
  /// revanche, et l'effet resterait allumé plusieurs minutes après que
  /// l'appareil a commencé à souffrir.
  static const Duration _interval = Duration(seconds: 45);

  Future<void> _refresh() async {
    final stressed = await MediaService.isOverheating;
    if (mounted && stressed != state) state = stressed;
  }

  @override
  // ⚠️ Le paramètre s'appelle `state` par contrainte de la classe mère,
  // et masque donc le `state` du `StateNotifier` (le booléen de chauffe)
  // dans cette méthode. On ne touche pas au second ici : `_refresh` s'en
  // charge, hors de portée de ce masquage.
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Au retour dans l'app, on relit tout de suite : l'appareil a pu
    // chauffer ailleurs pendant qu'on n'y était pas, et c'est justement
    // le moment où l'on va redessiner tout l'écran.
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
