// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LA FEUILLE QUI SERT À CHOISIR SA PHOTO DE PROFIL.
//
// Elle est ici, dans les widgets partagés, et pas dans l'écran d'accueil
// où elle est née — pour une raison qui n'a rien de cosmétique.
//
// ⚠️ UNE PHOTO QU'ON NE PEUT CHOISIR QU'À L'INSTALLATION EST UN PIÈGE.
//
// La première version vivait dans `onboarding_screen.dart`. Conséquence :
// on posait sa photo une fois, au tout premier lancement, et plus jamais.
// Se tromper de photo, ou simplement vouloir en changer six mois plus
// tard, aurait demandé de réinstaller l'application — c'est-à-dire de
// perdre son identité et toutes ses conversations, puisque Droplet n'a
// aucun serveur pour les restituer.
//
// La feuille est donc appelée depuis DEUX endroits : l'accueil, et les
// réglages. `choisirUnePhoto` est le seul point d'entrée des deux.
//
// Ce qu'elle renvoie est TOUJOURS une vignette carrée déjà réduite,
// jamais une photo d'origine — voir la note en tête d'`AvatarService`,
// qui explique pourquoi c'est non négociable sur un téléphone de 2 Go.
// ============================================================================

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../core/services/avatar_service.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';

/// Demande une photo de profil et renvoie la vignette choisie.
///
/// Renvoie `null` si l'utilisateur referme la feuille sans rien choisir.
/// L'appelant reste responsable de l'enregistrer (`AvatarService`) : la
/// feuille CHOISIT, elle ne décide pas.
Future<Uint8List?> choisirUnePhoto(BuildContext context) {
  return showModalBottomSheet<Uint8List>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => const _AvatarPickerSheet(),
  );
}

// ─────────────────────────────────────────────────────────────
//  LE CHOIX DE LA PHOTO
// ─────────────────────────────────────────────────────────────

/// La feuille qui propose les dernières photos du téléphone.
///
/// ⚠️ CE QU'ELLE RENVOIE EST DÉJÀ UNE VIGNETTE, jamais une photo
/// d'origine. Le rognage carré et la compression sont faits par
/// `AvatarService` — voir la note en tête de ce fichier-là, qui explique
/// pourquoi ce n'est pas négociable sur un téléphone de 2 Go.
///
/// ── Pourquoi la galerie récente plutôt qu'un sélecteur ────────────
///
/// Neuf fois sur dix, la photo qu'on veut mettre en profil est récente.
/// Ouvrir le sélecteur système par-dessus l'accueil ferait quitter la
/// page pour revenir avec un fichier ; une grille montre huit photos
/// d'un coup, et le choix se fait sans jamais sortir de l'écran. Le
/// bouton « Parcourir » reste là pour le cas rare.
class _AvatarPickerSheet extends StatefulWidget {
  const _AvatarPickerSheet();

  @override
  State<_AvatarPickerSheet> createState() => _AvatarPickerSheetState();
}

class _AvatarPickerSheetState extends State<_AvatarPickerSheet> {
  List<AssetEntity>? _recents;
  bool _occupe = false;

  /// Les vignettes déjà extraites, gardées par la FEUILLE.
  ///
  /// Une grille recycle ses cases : sans ce cache, faire défiler
  /// relancerait une extraction système à chaque aller-retour, avec
  /// l'allocation native qui va avec. Il est borné par construction —
  /// il ne peut pas dépasser le nombre de photos affichées, et disparaît
  /// avec la feuille.
  final Map<String, Uint8List> _vignettes = {};

  @override
  void initState() {
    super.initState();
    AvatarService.recents().then((r) {
      if (mounted) setState(() => _recents = r);
    });
  }

  Future<void> _choisirAsset(AssetEntity asset) async {
    setState(() => _occupe = true);
    final octets = await AvatarService.vignetteDe(asset);
    if (!mounted) return;
    if (octets == null) {
      setState(() => _occupe = false);
      return;
    }
    Navigator.of(context).pop(octets);
  }

  Future<void> _parcourir() async {
    setState(() => _occupe = true);
    try {
      final res = await FilePicker.platform.pickFiles(type: FileType.image);
      final chemin = res?.files.single.path;
      if (chemin == null) {
        if (mounted) setState(() => _occupe = false);
        return;
      }
      final octets = await AvatarService.reduireFichier(File(chemin));
      if (!mounted) return;
      if (octets == null) {
        setState(() => _occupe = false);
        return;
      }
      Navigator.of(context).pop(octets);
    } catch (e) {
      debugPrint('[Onboarding] photo illisible: $e');
      if (mounted) setState(() => _occupe = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recents = _recents;

    return FrostedSheet(
      material: OuroMaterial.thin,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Votre photo',
              style: OuroTypography.title3.copyWith(color: OuroColors.label),
            ),
            const SizedBox(height: DesignTokens.space4),

            if (recents == null)
              // On réserve la hauteur pendant le chargement : sans cela,
              // la feuille bondit quand les vignettes arrivent.
              const SizedBox(height: 240)
            else if (recents.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 28),
                child: Text(
                  'Aucune photo accessible sur cet appareil.',
                  style: OuroTypography.subheadline
                      .copyWith(color: OuroColors.secondaryLabel),
                ),
              )
            else
              SizedBox(
                height: 240,
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  gridDelegate:
                      const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 3,
                    mainAxisSpacing: 3,
                  ),
                  itemCount: recents.length,
                  itemBuilder: (context, i) => _TuilePhoto(
                    key: ValueKey(recents[i].id),
                    asset: recents[i],
                    cache: _vignettes,
                    onTap: _occupe ? null : () => _choisirAsset(recents[i]),
                  ),
                ),
              ),

            const SizedBox(height: DesignTokens.space4),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _occupe ? null : _parcourir,
                icon: Icon(Icons.folder_open_rounded,
                    size: 19, color: OuroColors.accent),
                label: Text(
                  'Parcourir les fichiers',
                  style: OuroTypography.body
                      .copyWith(color: OuroColors.accent),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Une case de la grille de choix.
///
/// Chargement dans `initState` et non dans `build` : une image demandée
/// depuis `build` serait redemandée à chaque reconstruction, ce qui fait
/// clignoter la grille et gonfle la mémoire — le défaut exact qu'on a dû
/// corriger dans la conversation.
class _TuilePhoto extends StatefulWidget {
  const _TuilePhoto({
    super.key,
    required this.asset,
    required this.cache,
    required this.onTap,
  });

  final AssetEntity asset;
  final Map<String, Uint8List> cache;
  final VoidCallback? onTap;

  @override
  State<_TuilePhoto> createState() => _TuilePhotoState();
}

class _TuilePhotoState extends State<_TuilePhoto> {
  Uint8List? _octets;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final connue = widget.cache[widget.asset.id];
    if (connue != null) {
      _octets = connue;
      return;
    }
    try {
      final data = await widget.asset
          .thumbnailDataWithSize(const ThumbnailSize.square(200));
      if (data == null) return;
      widget.cache[widget.asset.id] = data;
      if (mounted) setState(() => _octets = data);
    } catch (_) {
      // Une vignette illisible laisse une case grise, sans plus.
    }
  }

  @override
  Widget build(BuildContext context) {
    final octets = _octets;
    return Semantics(
      button: true,
      label: 'Photo récente',
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        onTap: widget.onTap,
        child: ColoredBox(
          color: OuroColors.systemGray5,
          child: octets == null
              ? const SizedBox.expand()
              : Image.memory(
                  octets,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                  cacheWidth: 200,
                  cacheHeight: 200,
                ),
        ),
      ),
    );
  }
}
