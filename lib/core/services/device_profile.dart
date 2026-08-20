// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE PROFIL DE L'APPAREIL : est-on sur un téléphone qui peut se permettre
// les effets coûteux, ou sur une machine modeste qu'il faut ménager ?
//
// ── Pourquoi ce fichier existe ────────────────────────────────────────
//
// Droplet vise des gens qui n'ont pas de réseau — pas des gens qui ont
// des téléphones neufs. Les deux populations ne se recouvrent pas. Or,
// mesuré sur un Pixel 6 Pro, l'application occupe environ 865 Mo, dont
// 310 Mo de mémoire graphique rien que pour l'écran de carte.
//
// Sur un appareil de 12 Go, personne ne le remarque. Sur un appareil de
// 2 Go — celui de l'utilisateur type — Android tue l'application, sans
// message et sans écran d'erreur. C'est le même symptôme que celui
// rapporté au début : « l'app se ferme quand j'ouvre la carte ».
//
// ── ⚠️ ON DÉCIDE UNE FOIS, PAS EN CONTINU ─────────────────────────────
//
// La capacité totale de l'appareil est une propriété STABLE. La mémoire
// libre, elle, varie à la seconde selon ce que fait le reste du système.
// Se baser sur la seconde donnerait une interface qui change d'apparence
// sans raison visible — les effets qui apparaissent et disparaissent au
// gré des autres applications. On lit donc la capacité une fois au
// démarrage, et on s'y tient pour la session.
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ce que l'appareil peut se permettre.
enum DeviceTier {
  /// 2 Go ou moins, ou marqué « low RAM » par Android. Aucun effet
  /// coûteux : ni shader de verre, ni dégradé calculé, et une réserve
  /// d'images réduite.
  modeste,

  /// Entre 2 et 4 Go. Les effets légers passent, les shaders non.
  moyen,

  /// Plus de 4 Go. Tout est permis.
  confortable,
}

/// Le profil de cet appareil, lu une fois au démarrage.
class DeviceProfile {
  DeviceProfile._();

  static const MethodChannel _channel =
      MethodChannel('com.droplet.droplet/media');

  static DeviceTier _tier = DeviceTier.confortable;
  static int _ramMb = 0;

  /// La catégorie de l'appareil. Vaut `confortable` tant que
  /// [detecter] n'a pas été appelé — on ne bride jamais par défaut.
  static DeviceTier get tier => _tier;

  /// La mémoire vive totale en mégaoctets, 0 si inconnue.
  static int get ramMb => _ramMb;

  /// Vrai quand il faut renoncer aux effets coûteux.
  static bool get menager => _tier == DeviceTier.modeste;

  /// Vrai quand les shaders sont hors de portée (verre liquide).
  ///
  /// Le seuil est plus haut que pour le reste : un shader s'exécute à
  /// chaque image sur le processeur graphique, souvent partagé avec la
  /// mémoire système sur les appareils d'entrée de gamme. C'est l'effet
  /// dont le coût grimpe le plus vite quand la machine faiblit.
  static bool get sansShader => _tier != DeviceTier.confortable;

  /// La taille de la réserve d'images décodées, en octets.
  ///
  /// ⚠️ Le défaut de Flutter est 100 Mo, pensé pour un écran de bureau.
  /// Sur un téléphone de 2 Go, une réserve de cette taille suffit à
  /// elle seule à faire tuer l'application.
  static int get budgetImages => switch (_tier) {
        DeviceTier.modeste => 16 << 20,
        DeviceTier.moyen => 32 << 20,
        DeviceTier.confortable => 48 << 20,
      };

  /// Combien d'images décodées on garde au maximum.
  static int get nombreImages => switch (_tier) {
        DeviceTier.modeste => 60,
        DeviceTier.moyen => 140,
        DeviceTier.confortable => 250,
      };

  /// Interroge le système. À appeler une fois, au démarrage.
  static Future<void> detecter() async {
    if (!(defaultTargetPlatform == TargetPlatform.android)) return;
    try {
      final mb = await _channel.invokeMethod<int>('deviceMemoryMb');
      _ramMb = mb ?? 0;
      // Zéro veut dire « je n'ai pas pu savoir ». On traite alors
      // l'appareil comme modeste : une interface sobre sur un téléphone
      // puissant se remarque à peine, l'inverse le fait planter.
      _tier = _ramMb == 0
          ? DeviceTier.modeste
          : _ramMb <= 2200
              ? DeviceTier.modeste
              : _ramMb <= 4200
                  ? DeviceTier.moyen
                  : DeviceTier.confortable;
      debugPrint('[Appareil] $_ramMb Mo de RAM → ${_tier.name}');
    } catch (e) {
      debugPrint('[Appareil] mémoire indisponible: $e');
      _tier = DeviceTier.modeste;
    }
  }
}
