// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LA BANDE DE PHOTOS RÉCENTES, sous les icônes du panneau « + ».
//
// C'est la trouvaille de la refonte de WhatsApp sur iOS en 2026 : au lieu
// d'ouvrir le sélecteur système par-dessus toute la conversation, on
// montre d'abord les derniers médias, en une rangée qu'on fait défiler du
// pouce. Neuf fois sur dix, la photo qu'on veut envoyer est là — elle
// vient d'être prise. On l'envoie sans jamais perdre la conversation de
// vue.
//
// Et si elle n'y est pas, « Tout voir » ouvre le sélecteur complet. C'est
// ce qu'on appelle une divulgation progressive : le cas fréquent est
// immédiat, le cas rare reste accessible.
//
// ── ⚠️ LES GARDE-FOUS MÉMOIRE NE SONT PAS NÉGOCIABLES ─────────────────
//
// Cette bande charge des images. Or Droplet a déjà été tué par un
// `OutOfMemoryError` en lisant un fichier (voir `_pickAndSendFile`), et
// l'écran de carte occupe à lui seul 300 Mo de mémoire graphique. Trois
// règles, donc :
//
//   1. On ne demande QUE des vignettes, en 200×200 — jamais l'image
//      d'origine. Une photo de téléphone fait douze millions de pixels ;
//      décodée, elle pèse 48 Mo. Une poignée d'entre elles suffirait à
//      faire tuer l'application.
//   2. On en charge DIX-HUIT, pas la photothèque. La bande sert à
//      retrouver ce qu'on vient de prendre, pas à parcourir dix ans
//      d'archives.
//   3. Les vignettes sont chargées PARESSEUSEMENT, une par case visible,
//      et jamais toutes d'un coup — la grille ne construit que ce qui
//      est à l'écran.
//
// ── Ce qui se passe si on refuse l'accès ──────────────────────────────
//
// La bande disparaît, purement et simplement. Pas de message d'erreur,
// pas de bandeau qui réclame une permission : les autres entrées du
// panneau continuent de fonctionner, et le sélecteur système demandera
// lui-même l'accès au moment voulu. Harceler quelqu'un qui vient de dire
// non est le meilleur moyen qu'il dise non pour toujours.
// ============================================================================

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_typography.dart';

/// Combien de médias récents on propose.
const int _kNombreRecents = 18;

/// La taille des vignettes demandées au système, en pixels.
const ThumbnailSize _kTailleVignette = ThumbnailSize.square(200);

/// La bande horizontale des derniers médias.
///
/// [onChoisi] reçoit le chemin du fichier choisi ; [onToutVoir] ouvre le
/// sélecteur complet.
class RecentMediaStrip extends StatefulWidget {
  const RecentMediaStrip({
    super.key,
    required this.onChoisi,
    required this.onToutVoir,
  });

  final void Function(AssetEntity asset) onChoisi;
  final VoidCallback onToutVoir;

  @override
  State<RecentMediaStrip> createState() => _RecentMediaStripState();
}

class _RecentMediaStripState extends State<RecentMediaStrip> {
  List<AssetEntity>? _recents;
  bool _refuse = false;

  /// Les vignettes déjà chargées, gardées par la BANDE et non par chaque
  /// case.
  ///
  /// ⚠️ MESURÉ SUR L'APPAREIL : sans ce cache, faire défiler la bande
  /// faisait passer l'application de 971 Mo à 1054 Mo. La raison tient
  /// au recyclage — une liste horizontale détruit les cases qui sortent
  /// de l'écran et en reconstruit de neuves quand on revient. Chaque
  /// aller-retour relançait donc une extraction de vignette côté
  /// système, avec l'allocation native qui va avec.
  ///
  /// Le cache est borné par construction : il ne peut pas dépasser le
  /// nombre de médias affichés, et disparaît avec le panneau.
  final Map<String, Uint8List> _vignettes = {};

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    try {
      // `requestPermissionExtend` gère à lui seul les trois réponses
      // possibles d'Android 14+ : tout, une sélection limitée, ou rien.
      final etat = await PhotoManager.requestPermissionExtend();
      if (!etat.hasAccess) {
        if (mounted) setState(() => _refuse = true);
        return;
      }

      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.common, // images ET vidéos
        onlyAll: true,
      );
      if (albums.isEmpty) {
        if (mounted) setState(() => _refuse = true);
        return;
      }

      final recents = await albums.first.getAssetListPaged(
        page: 0,
        size: _kNombreRecents,
      );
      if (mounted) setState(() => _recents = recents);
    } catch (e) {
      // Photothèque illisible, plateforme sans galerie : la bande
      // s'efface, le reste du panneau continue de marcher.
      debugPrint('[Récents] indisponible: $e');
      if (mounted) setState(() => _refuse = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_refuse) return const SizedBox.shrink();

    final recents = _recents;
    // Pendant le chargement, on réserve la hauteur au lieu de laisser le
    // panneau sauter quand les vignettes arrivent.
    if (recents == null) return const SizedBox(height: 236);
    if (recents.isEmpty) return const SizedBox.shrink();

    // ── UNE GRILLE, PLUS UNE BANDE ────────────────────────────────
    //
    // La première version était une rangée horizontale qu'on faisait
    // défiler du pouce. Les captures montrent autre chose : une GRILLE
    // de quatre colonnes, bord à bord, sur plusieurs lignes.
    //
    // La différence n'est pas cosmétique. Une bande horizontale montre
    // quatre photos et cache les autres derrière un geste que rien
    // n'annonce ; une grille en montre huit d'un coup et se parcourt du
    // même geste vertical que le reste du panneau. Sur une action dont
    // tout l'intérêt est de retrouver VITE une photo récente, voir le
    // double change la donne.
    //
    // Bord à bord et sans marge latérale, aussi comme sur les captures :
    // ces vignettes ne sont pas des cartes, elles forment une surface.
    return SizedBox(
      // Deux lignes visibles, la suite au défilement.
      height: 236,
      child: GridView.builder(
        padding: EdgeInsets.zero,
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 4,
          // Deux points d'écart : assez pour séparer, trop peu pour se
          // lire comme des éléments détachés.
          crossAxisSpacing: 2,
          mainAxisSpacing: 2,
          childAspectRatio: 1,
        ),
        // +1 : la dernière case est « Tout voir ».
        itemCount: recents.length + 1,
        itemBuilder: (context, i) {
          if (i == recents.length) {
            return _CaseToutVoir(onTap: widget.onToutVoir);
          }
          final asset = recents[i];
          return _Vignette(
            key: ValueKey(asset.id),
            asset: asset,
            cache: _vignettes,
            onTap: () => widget.onChoisi(asset),
          );
        },
      ),
    );
  }
}

/// Une case de la bande.
class _Vignette extends StatefulWidget {
  const _Vignette({
    super.key,
    required this.asset,
    required this.cache,
    required this.onTap,
  });

  final AssetEntity asset;
  final Map<String, Uint8List> cache;
  final VoidCallback onTap;

  @override
  State<_Vignette> createState() => _VignetteState();
}

class _VignetteState extends State<_Vignette> {
  Uint8List? _octets;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    // Déjà extraite une fois : on la réutilise telle quelle, sans
    // redemander quoi que ce soit au système.
    final connue = widget.cache[widget.asset.id];
    if (connue != null) {
      _octets = connue;
      return;
    }
    try {
      final data =
          await widget.asset.thumbnailDataWithSize(_kTailleVignette);
      if (data == null) return;
      widget.cache[widget.asset.id] = data;
      if (mounted) setState(() => _octets = data);
    } catch (_) {
      // Une vignette illisible laisse simplement une case grise.
    }
  }

  @override
  Widget build(BuildContext context) {
    final estVideo = widget.asset.type == AssetType.video;

    return Semantics(
      button: true,
      label: estVideo ? 'Vidéo récente' : 'Photo récente',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        onTap: () {
          OuroHaptics.light();
          widget.onTap();
        },
        // Plus de coins arrondis ni de dimensions propres : la vignette
        // remplit sa case de grille. Des vignettes arrondies séparées
        // par deux points donneraient une mosaïque de pastilles, là où
        // les captures montrent une surface continue.
        child: Container(
            color: OuroColors.systemGray5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_octets != null)
                  Image.memory(
                    _octets!,
                    fit: BoxFit.cover,
                    // ⚠️ Sans ces deux bornes, Flutter décode la vignette
                    // à la résolution de l'écran et la garde ainsi dans
                    // son cache — on annulerait tout le bénéfice d'avoir
                    // demandé une petite image.
                    cacheWidth: 200,
                    cacheHeight: 200,
                  ),
                // La durée d'une vidéo, en bas : c'est ce qui la distingue
                // d'une photo au premier coup d'œil.
                if (estVideo)
                  Align(
                    alignment: Alignment.bottomRight,
                    child: Container(
                      margin: const EdgeInsets.all(4),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _duree(widget.asset.duration),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ),
      ),
    );
  }

  static String _duree(int secondes) {
    final m = secondes ~/ 60;
    final s = (secondes % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

/// La dernière case : ouvrir le sélecteur complet.
class _CaseToutVoir extends StatelessWidget {
  const _CaseToutVoir({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Voir toutes les photos',
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        onTap: () {
          OuroHaptics.light();
          onTap();
        },
        child: Container(
          color: OuroColors.systemGray5.withValues(alpha: 0.7),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.photo_library_rounded,
                color: OuroColors.accent,
                size: 22,
              ),
              const SizedBox(height: 4),
              Text(
                'Tout voir',
                style: OuroTypography.caption2
                    .copyWith(color: OuroColors.secondaryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
