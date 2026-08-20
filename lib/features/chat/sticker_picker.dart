// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le PANNEAU DE STICKERS de la conversation : une grille de grandes
// vignettes, rangées par thème, plus la rangée des derniers utilisés.
//
// ── Pourquoi des stickers en emoji, et pas des images ? ────────────────
//
// C'est une décision de fond, pas un raccourci.
//
// Un vrai lot de stickers, c'est une centaine d'images de 50 à 150 ko.
// Embarquées dans l'app, elles feraient grossir le téléchargement de
// plusieurs méga-octets pour du décor. Et surtout : envoyées dans une
// conversation, CHAQUE sticker deviendrait un transfert de fichier
// complet à faire traverser le Bluetooth — plusieurs secondes pour
// dire « 👍 », sur un réseau où les vrais messages attendent derrière.
//
// Un sticker en emoji, lui, pèse quelques octets. Il part
// instantanément, s'affiche partout, et fonctionne même avec les
// versions antérieures de Droplet, qui le verront simplement comme un
// message texte.
//
// La différence avec un emoji tapé au clavier tient à l'AFFICHAGE : un
// message qui ne contient que des emojis (trois au maximum) est rendu
// en grand et SANS BULLE, exactement comme le fait WhatsApp. C'est ce
// qui lui donne son allure de sticker.
// ============================================================================

import 'package:flutter/material.dart';

import 'animated_sticker.dart';

import '../../core/services/storage_service.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_typography.dart';

/// Un lot de stickers.
class StickerPack {
  const StickerPack({
    required this.name,
    required this.icon,
    required this.stickers,
  });

  final String name;

  /// L'emoji qui représente le lot dans la barre d'onglets.
  final String icon;

  final List<String> stickers;
}

/// Le catalogue.
///
/// Volontairement resserré : une grille de mille emojis est un
/// dictionnaire, pas un choix. Chaque lot tient en deux ou trois écrans
/// et ne garde que ce qui sert vraiment dans une conversation.
const List<StickerPack> kStickerPacks = [
  StickerPack(
    name: 'Réactions',
    icon: '😀',
    stickers: [
      '😀', '😂', '🤣', '😊', '😍', '🥰', '😘', '😎',
      '🤩', '🥳', '😇', '🙃', '😉', '😌', '🤗', '🤔',
      '🤨', '😐', '😴', '🤯', '😱', '😭', '😢', '😤',
      '😡', '🥺', '😳', '🙄', '😬', '🤫', '🤐', '😷',
    ],
  ),
  StickerPack(
    name: 'Gestes',
    icon: '👍',
    stickers: [
      '👍', '👎', '👌', '✌️', '🤞', '🤟', '🤙', '👋',
      '🙌', '👏', '🙏', '💪', '🤝', '✊', '👊', '🫶',
      '☝️', '👉', '👈', '👆', '👇', '✋', '🖐️', '🫡',
    ],
  ),
  StickerPack(
    name: 'Cœurs',
    icon: '❤️',
    stickers: [
      '❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍',
      '💔', '❣️', '💕', '💞', '💓', '💗', '💖', '💘',
      '💝', '💟', '♥️', '💌', '🫂', '😻', '💐', '🌹',
    ],
  ),
  StickerPack(
    name: 'Sécurité',
    icon: '🆘',
    stickers: [
      '🆘', '⚠️', '🚨', '🔴', '🟢', '✅', '❌', '❗',
      '❓', '📍', '🧭', '🔦', '🔋', '📶', '🛜', '📡',
      '🏥', '🚑', '🚒', '🚓', '💊', '🩹', '💧', '🍞',
      '🏠', '⛺', '🔥', '🌧️', '⛈️', '🌊', '🌪️', '🕐',
    ],
  ),
  StickerPack(
    name: 'Animaux',
    icon: '🐶',
    stickers: [
      '🐶', '🐱', '🐭', '🐹', '🐰', '🦊', '🐻', '🐼',
      '🐨', '🐯', '🦁', '🐮', '🐷', '🐸', '🐵', '🐔',
      '🐧', '🐦', '🦆', '🦉', '🦅', '🐝', '🦋', '🐢',
    ],
  ),
  StickerPack(
    name: 'Fête',
    icon: '🎉',
    stickers: [
      '🎉', '🎊', '🥳', '🎂', '🍰', '🎁', '🎈', '🎀',
      '✨', '⭐', '🌟', '💫', '🔥', '💥', '🏆', '🥇',
      '🎵', '🎶', '🎤', '🥂', '🍻', '☕', '🍕', '🍫',
    ],
  ),
];

/// Vrai si ce texte doit s'afficher en GRAND et sans bulle.
///
/// La règle est celle de WhatsApp : uniquement des emojis, trois au
/// maximum. Au-delà, le message redevient une phrase, et une phrase se
/// lit dans une bulle.
bool isStickerMessage(String content) {
  final text = content.trim();
  if (text.isEmpty) return false;

  var glyphs = 0;
  for (final ch in text.characters) {
    // Les sélecteurs de variante et les jointures qui composent un
    // emoji (le ❤️ est un cœur SUIVI d'un sélecteur, 👨‍👩‍👧 est une
    // famille jointe) ne comptent pas comme des caractères de plus :
    // sans cette exception, un seul emoji composé serait pris pour
    // trois et perdrait son affichage en grand.
    if (ch == '\u{FE0F}' || ch == '\u{200D}') continue;

    final code = ch.runes.first;
    final isEmoji = code >= 0x1F000 ||
        (code >= 0x2190 && code <= 0x2BFF) ||
        (code >= 0x2600 && code <= 0x27BF) ||
        (code >= 0xFE00 && code <= 0xFE0F) ||
        (code >= 0x1F1E6 && code <= 0x1F1FF);
    if (!isEmoji) return false;

    glyphs++;
    if (glyphs > 3) return false;
  }
  return glyphs > 0;
}

/// Taille d'affichage d'un sticker, selon le nombre d'emojis.
double stickerFontSize(String content) {
  final count = content.trim().characters
      .where((c) => c != '\u{FE0F}' && c != '\u{200D}')
      .length;
  return switch (count) {
    1 => 62,
    2 => 48,
    _ => 38,
  };
}

/// Ouvre le panneau et renvoie le sticker choisi, ou `null`.
Future<String?> pickSticker(BuildContext context) {
  OuroHaptics.selection();
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const _StickerSheet(),
  );
}

class _StickerSheet extends StatefulWidget {
  const _StickerSheet();

  @override
  State<_StickerSheet> createState() => _StickerSheetState();
}

class _StickerSheetState extends State<_StickerSheet> {
  static const String _recentKey = 'recent_stickers';
  static const int _recentMax = 16;

  int _pack = 0;
  List<String> _recent = const [];

  @override
  void initState() {
    super.initState();
    _recent = _loadRecent();
  }

  List<String> _loadRecent() {
    final raw = StorageService.getString(_recentKey) ?? '';
    if (raw.isEmpty) return const [];
    return raw.split('').where((s) => s.isNotEmpty).toList();
  }

  Future<void> _remember(String sticker) async {
    final next = [sticker, ..._recent.where((s) => s != sticker)]
        .take(_recentMax)
        .toList();
    await StorageService.setString(_recentKey, next.join(''));
  }

  /// Transforme un nom de dossier en libellé d'onglet.
  ///
  /// Les dossiers d'assets se nomment sans accent ni majuscule
  /// (`fetes`, `humeurs`) parce que c'est ce qui traverse le mieux les
  /// systèmes de fichiers. L'utilisateur, lui, n'a pas à voir ça.
  static String _joliNomDeLot(String dossier) {
    if (dossier.isEmpty) return 'Stickers';
    final propre = dossier.replaceAll('_', ' ').replaceAll('-', ' ');
    return propre[0].toUpperCase() + propre.substring(1);
  }

  void _choose(String sticker) {
    OuroHaptics.light();
    _remember(sticker);
    Navigator.of(context).pop(sticker);
  }

  @override
  Widget build(BuildContext context) {
    // Les récents forment un lot supplémentaire, en tête — c'est là
    // qu'on trouve neuf fois sur dix ce qu'on cherche.
    // Les lots de stickers ANIMÉS, s'il y en a sur cet appareil.
    //
    // Ils n'ont rien de particulier du point de vue du panneau : un
    // sticker animé est, ici aussi, une simple chaîne — sa référence
    // (`🎞tgs:lot/nom`). C'est `_StickerTile` qui décide de dessiner un
    // emoji ou de jouer une animation. Tout le reste — les récents, le
    // choix, l'envoi — fonctionne sans une ligne de plus.
    final lotsAnimes = AnimatedStickerCatalog.parLot;

    final packs = <StickerPack>[
      if (_recent.isNotEmpty)
        StickerPack(name: 'Récents', icon: '🕐', stickers: _recent),
      for (final entree in lotsAnimes.entries)
        StickerPack(
          name: _joliNomDeLot(entree.key),
          icon: '🎞',
          stickers: [for (final s in entree.value) s.reference],
        ),
      ...kStickerPacks,
    ];
    final current = packs[_pack.clamp(0, packs.length - 1)];

    return FrostedSheet(
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.46,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(current.name,
                  style: OuroTypography.headline
                      .copyWith(color: OuroColors.label)),
              const SizedBox(height: DesignTokens.space3),
              Expanded(
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 68,
                    childAspectRatio: 1,
                  ),
                  itemCount: current.stickers.length,
                  itemBuilder: (context, i) {
                    final sticker = current.stickers[i];
                    return _StickerTile(
                      sticker: sticker,
                      onTap: () => _choose(sticker),
                    );
                  },
                ),
              ),
              const SizedBox(height: DesignTokens.space2),
              // La barre des lots, en bas : le pouce y est déjà.
              SizedBox(
                height: 46,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: packs.length,
                  itemBuilder: (context, i) {
                    final selected = i == _pack;
                    return GestureDetector(
                      onTap: () {
                        OuroHaptics.selection();
                        setState(() => _pack = i);
                      },
                      child: Container(
                        width: 44,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: selected
                              ? OuroColors.tertiarySystemFill
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        alignment: Alignment.center,
                        child: Text(packs[i].icon,
                            style: const TextStyle(fontSize: 22)),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StickerTile extends StatefulWidget {
  const _StickerTile({required this.sticker, required this.onTap});
  final String sticker;
  final VoidCallback onTap;

  @override
  State<_StickerTile> createState() => _StickerTileState();
}

class _StickerTileState extends State<_StickerTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.onTap,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.82 : 1,
        duration: const Duration(milliseconds: 110),
        curve: Curves.easeOut,
        // Une vignette porte soit un emoji, soit une animation. Rien
        // d'autre ne change : le reste du panneau ne sait pas — et n'a
        // pas besoin de savoir — de quel type il s'agit.
        child: Center(
          child: AnimatedStickerCatalog.estUneReference(widget.sticker)
              ? AnimatedStickerView(reference: widget.sticker, taille: 56)
              : Text(widget.sticker, style: const TextStyle(fontSize: 34)),
        ),
      ),
    );
  }
}
