// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LES STICKERS ANIMÉS, au format `.tgs` de Telegram.
//
// ── Ce qu'est réellement un fichier .tgs ──────────────────────────────
//
// Rien d'exotique : c'est un JSON Bodymovin — le format qu'exporte After
// Effects via le greffon Lottie — COMPRESSÉ EN GZIP, avec un attribut
// supplémentaire `"tgs": 1`. Telegram impose en plus un cadre de
// 512×512, trois secondes au maximum, une boucle, et 60 images par
// seconde ; c'est ce qui leur permet de tenir sous les 30 ko là où un
// GIF équivalent en ferait mille.
//
// Telegram les affiche avec `rlottie`, une bibliothèque C++ de Samsung.
// Ici on utilise le paquet `lottie`, écrit en pur Dart, qui sait
// décompresser lui-même le gzip (`LottieComposition.decodeGZip`) — donc
// aucun code natif à embarquer, et ça marche sur toutes les plateformes.
//
// ── ⚠️ CE QUI CIRCULE SUR LE MESH : LE NOM, PAS LE FICHIER ────────────
//
// C'est LA décision de conception de ce fichier, et elle découle
// directement des contraintes de Droplet.
//
// Un sticker animé pèse ~30 ko. Envoyé comme un fichier, il devrait
// traverser le Bluetooth — où Droplet dispose de DIX-NEUF octets utiles
// par écriture. Trente kilo-octets, c'est plus de mille cinq cents
// écritures pour dire « 👍 », pendant lesquelles les vrais messages
// attendent derrière. Ce serait absurde.
//
// On envoie donc une RÉFÉRENCE : `🎞tgs:lot/nom`, quelques dizaines
// d'octets, exactement comme la position (`📍loc:` — voir
// `location_message.dart`). Chaque appareil affiche l'animation depuis
// SES PROPRES fichiers. C'est aussi ce que fait Telegram, qui n'envoie
// qu'un identifiant de document.
//
// Le corollaire est assumé : si le destinataire n'a pas ce sticker, il
// ne verra pas l'animation. On lui montre alors le nom du sticker dans
// une bulle ordinaire, plutôt qu'un carré vide — un message dégradé
// reste un message lisible.
//
// ── Le dossier est livré VIDE, et c'est volontaire ────────────────────
//
// Les stickers de Telegram sont leur propriété. Les embarquer dans une
// application destinée à être publiée serait une contrefaçon. Ce fichier
// fournit donc la mécanique ; les animations, c'est à vous de les
// déposer dans `assets/stickers/` (voir le LISEZ-MOI qui s'y trouve).
// Tant que le dossier est vide, l'onglet des stickers animés n'apparaît
// tout simplement pas.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lottie/lottie.dart';

/// Un sticker animé disponible sur cet appareil.
@immutable
class AnimatedSticker {
  const AnimatedSticker({
    required this.pack,
    required this.nom,
    required this.chemin,
    this.paquetDart,
  });

  /// Le paquet Dart qui contient l'asset, quand il ne vient pas de
  /// l'application elle-même.
  ///
  /// Les emojis animés de Noto sont livrés par `animated_emoji` ; leurs
  /// fichiers vivent donc dans CE paquet, pas dans `assets/` de Droplet.
  /// Flutter sait les charger, à condition qu'on lui dise d'où ils
  /// viennent — c'est le rôle de ce champ.
  final String? paquetDart;

  /// Le lot auquel il appartient — le nom du sous-dossier.
  final String pack;

  /// Son nom, sans extension.
  final String nom;

  /// Le chemin de l'asset, tel que Flutter le connaît.
  final String chemin;

  /// Vrai pour un `.tgs` (gzip), faux pour un `.json` Lottie ordinaire.
  bool get estCompresse => chemin.endsWith('.tgs');

  /// La référence qui circule sur le mesh.
  String get reference => '$kStickerPrefix$pack/$nom';

  @override
  bool operator ==(Object other) =>
      other is AnimatedSticker && other.chemin == chemin;

  @override
  int get hashCode => chemin.hashCode;
}

/// Le préfixe qui distingue un message-sticker d'un message ordinaire.
///
/// L'emoji de tête n'est pas décoratif : une version antérieure de
/// Droplet, qui ne connaît pas ce format, affichera simplement
/// `🎞tgs:fetes/confettis` — ce qui reste compréhensible. Un préfixe
/// purement technique aurait donné une ligne incompréhensible.
const String kStickerPrefix = '🎞tgs:';

/// Le catalogue des stickers présents sur l'appareil.
class AnimatedStickerCatalog {
  AnimatedStickerCatalog._();

  static List<AnimatedSticker> _tous = const [];
  static bool _charge = false;

  /// Le nom du lot d'emojis animés livré avec l'application.
  static const String lotNoto = 'noto';

  /// Les emojis animés retenus, parmi les 694 du paquet `animated_emoji`.
  ///
  /// ⚠️ Cette liste doit rester SYNCHRONISÉE avec les assets déclarés
  /// dans `pubspec.yaml`. Un nom présent ici mais pas là-bas donne une
  /// vignette qui ne charge jamais ; l'inverse alourdit l'APK pour rien.
  /// Le choix privilégie ce qui sert vraiment dans une conversation
  /// plutôt que l'exhaustivité — une grille de sept cents animations
  /// serait un dictionnaire, pas un choix.
  static const List<String> _noto = [
    'joy',
    'electricity',
    'heartEyes',
    'thumbsUp',
    'fire',
    'partyPopper',
    'beatingHeart',
    'brokenHeart',
    'cry',
    'loudlyCrying',
    'laughing',
    'grin',
    'wink',
    'blush',
    'cool',
    'clap',
    'foldedHands',
    'muscle',
    'rocket',
    'birthdayCake',
    'balloon',
    'glowingStar',
    'mindBlown',
    'thinkingFace',
    'sleep',
    'hotFace',
    'coldFace',
    'ghost',
    'alien',
    'dog',
    'wave',
    'checkMark',
    'crossMark',
    'warning',
    'exclamation',
    'salute',
    'starStruck',
    'relieved',
    'yawn',
    'shushingFace',
    'pleading',
    'kissingHeart',
    'melting',
    'skull',
    'eyes',
    'smile',
    'rainbow',
    'confettiBall',
    'handshake',
    'droplet',
    'luck',
  ];

  /// Tous les stickers trouvés, rangés par lot.
  static Map<String, List<AnimatedSticker>> get parLot {
    final map = <String, List<AnimatedSticker>>{};
    for (final s in _tous) {
      (map[s.pack] ??= []).add(s);
    }
    return map;
  }

  static bool get estVide => _tous.isEmpty;

  /// Découvre les stickers embarqués.
  ///
  /// ⚠️ On passe par l'INDEX DES ASSETS plutôt que par une liste écrite
  /// à la main. Flutter n'expose aucun moyen de lister un dossier
  /// d'assets à l'exécution : le paquet final ne contient pas de
  /// système de fichiers, seulement une table. `AssetManifest` est cette
  /// table. C'est ce qui permet de DÉPOSER un fichier `.tgs` dans
  /// `assets/stickers/` sans toucher une ligne de code.
  static Future<void> charger() async {
    if (_charge) return;
    _charge = true;
    try {
      final manifeste = await AssetManifest.loadFromAssetBundle(rootBundle);
      final trouves = <AnimatedSticker>[
        for (final nom in _noto)
          AnimatedSticker(
            pack: lotNoto,
            nom: nom,
            chemin: 'lottie/$nom.json',
            paquetDart: 'animated_emoji',
          ),
      ];
      for (final cle in manifeste.listAssets()) {
        if (!cle.startsWith('assets/stickers/')) continue;
        if (!cle.endsWith('.tgs') && !cle.endsWith('.json')) continue;

        final relatif = cle.substring('assets/stickers/'.length);
        final morceaux = relatif.split('/');
        // `fetes/confettis.tgs` → lot « fetes ». Un fichier posé à la
        // racine du dossier tombe dans un lot « Stickers » par défaut,
        // pour que ça marche aussi sans se soucier de l'arborescence.
        final pack = morceaux.length > 1 ? morceaux.first : 'stickers';
        final fichier = morceaux.last;
        final nom = fichier.substring(0, fichier.lastIndexOf('.'));
        trouves.add(
          AnimatedSticker(pack: pack, nom: nom, chemin: cle),
        );
      }
      trouves.sort((a, b) {
        final parLot = a.pack.compareTo(b.pack);
        return parLot != 0 ? parLot : a.nom.compareTo(b.nom);
      });
      _tous = trouves;
      debugPrint('[Stickers] ${_tous.length} sticker(s) animé(s) trouvé(s)');
    } catch (e) {
      // Aucun dossier, index illisible : on continue sans stickers
      // animés. Ce n'est pas une panne, c'est le cas par défaut.
      debugPrint('[Stickers] index des assets illisible: $e');
      // Le lot intégré ne dépend pas de l'index : il est connu à la
      // compilation. On le garde même si le balayage a échoué.
      _tous = [
        for (final nom in _noto)
          AnimatedSticker(
            pack: lotNoto,
            nom: nom,
            chemin: 'lottie/$nom.json',
            paquetDart: 'animated_emoji',
          ),
      ];
    }
  }

  /// Retrouve un sticker à partir d'une référence reçue.
  ///
  /// Renvoie `null` si ce pair possède une animation qu'on n'a pas —
  /// cas parfaitement normal, que l'affichage gère.
  static AnimatedSticker? resoudre(String reference) {
    final ref = reference.trim();
    if (!ref.startsWith(kStickerPrefix)) return null;
    final chemin = ref.substring(kStickerPrefix.length);
    final coupe = chemin.indexOf('/');
    if (coupe <= 0) return null;
    final pack = chemin.substring(0, coupe);
    final nom = chemin.substring(coupe + 1);
    for (final s in _tous) {
      if (s.pack == pack && s.nom == nom) return s;
    }
    return null;
  }

  /// Vrai si ce message est une référence de sticker animé, qu'on
  /// possède le fichier ou non.
  static bool estUneReference(String contenu) =>
      contenu.trim().startsWith(kStickerPrefix);

  /// Le nom lisible porté par une référence, pour le repli quand
  /// l'animation manque.
  static String nomLisible(String reference) {
    final ref = reference.trim();
    if (!ref.startsWith(kStickerPrefix)) return ref;
    return ref.substring(kStickerPrefix.length).replaceAll('/', ' · ');
  }
}

/// Affiche un sticker animé — ou un repli lisible s'il manque.
class AnimatedStickerView extends StatelessWidget {
  const AnimatedStickerView({
    super.key,
    required this.reference,
    this.taille = 128,
    this.boucle = true,
  });

  final String reference;
  final double taille;

  /// Dans une conversation, les stickers tournent en boucle comme chez
  /// Telegram. Dans la grille de choix, aussi — c'est ce qui permet de
  /// voir ce qu'on choisit.
  final bool boucle;

  @override
  Widget build(BuildContext context) {
    final sticker = AnimatedStickerCatalog.resoudre(reference);
    if (sticker == null) return _repli(context);

    return SizedBox(
      width: taille,
      height: taille,
      child: Lottie.asset(
        sticker.chemin,
        package: sticker.paquetDart,
        // ⚠️ C'est CETTE ligne qui permet de lire un `.tgs`. Sans elle,
        // le paquet essaie de lire du JSON brut et échoue sur des octets
        // compressés. Les `.json` Lottie ordinaires, eux, n'en veulent
        // pas — d'où le test.
        decoder: sticker.estCompresse ? LottieComposition.decodeGZip : null,
        repeat: boucle,
        width: taille,
        height: taille,
        fit: BoxFit.contain,
        // Un sticker qui ne se charge pas ne doit pas casser la
        // conversation autour de lui.
        errorBuilder: (context, error, stack) => _repli(context),
      ),
    );
  }

  /// Ce qu'on montre quand l'animation n'est pas là.
  ///
  /// Un carré vide laisserait croire à un bug. On affiche donc le nom du
  /// sticker et on dit pourquoi il ne s'anime pas — le destinataire
  /// comprend qu'il lui manque un fichier, pas que son app est cassée.
  Widget _repli(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      constraints: BoxConstraints(maxWidth: taille * 1.6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('🎞', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  AnimatedStickerCatalog.nomLisible(reference),
                  style: theme.textTheme.bodyMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            'Sticker absent de cet appareil',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
