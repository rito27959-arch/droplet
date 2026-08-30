// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE PANNEAU QUI S'OUVRE QUAND ON APPUIE SUR « + » dans la barre de
// saisie.
//
// ── Pourquoi il existe : trois boutons devenus un ─────────────────────
//
// La barre de saisie portait TROIS boutons alignés avant le champ de
// texte : joindre un fichier, stickers, partager sa position. Trois
// icônes bleues côte à côte, qui grignotaient la largeur du champ et
// obligeaient à viser une cible de plus en plus étroite sur un petit
// écran — alors que ce sont des actions occasionnelles, pas celles qu'on
// fait à chaque message.
//
// Toutes les messageries modernes ont convergé vers la même réponse : un
// seul bouton « + », qui ouvre une feuille. Le champ de texte récupère
// la place, et chaque action gagne un vrai libellé au lieu d'une icône
// qu'il fallait deviner.
//
// ── ⚠️ CE PANNEAU NE PROPOSE QUE CE QUI EXISTE VRAIMENT ───────────────
//
// C'est une règle, pas une limitation subie. Il serait facile d'aligner
// ici « Appareil photo », « Contact », « Sondage » pour faire riche —
// et de livrer une interface qui promet ce que l'application ne sait pas
// faire. Chaque entrée ci-dessous correspond à un chemin de code
// réellement implémenté et testé.
//
// « Photo ou vidéo » et « Document » passent par le MÊME sélecteur
// (`file_picker`), avec un filtre différent. Ce n'est pas un doublon
// déguisé : viser une photo dans une liste qui contient aussi les PDF et
// les archives est pénible, et le filtre est ce qui rend l'action
// rapide.
// ============================================================================

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'recent_media_strip.dart';

import '../../design_system/design_tokens.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_typography.dart';

/// Ce que l'utilisateur a choisi dans le panneau.
enum AttachChoice {
  /// Une photo ou une vidéo de la galerie.
  media,

  /// N'importe quel fichier.
  document,

  /// Sa position actuelle.
  position,

  /// Un sticker animé ou un emoji.
  sticker,
}

/// Le filtre à passer à `file_picker` pour ce choix.
///
/// Renvoie `null` quand le choix n'ouvre pas de sélecteur de fichier.
FileType? fileTypePour(AttachChoice choix) => switch (choix) {
      AttachChoice.media => FileType.media,
      AttachChoice.document => FileType.any,
      _ => null,
    };

/// Ce que le panneau a rapporté.
///
/// Soit une entrée de la liste, soit — et c'est le cas le plus fréquent —
/// un média déjà choisi dans la bande des récents, qu'il n'y a plus qu'à
/// envoyer.
class AttachResult {
  const AttachResult.choix(this.choix) : asset = null;
  const AttachResult.media(this.asset) : choix = null;

  final AttachChoice? choix;
  final AssetEntity? asset;
}

/// Ouvre le panneau et renvoie ce qui a été choisi, ou `null`.
Future<AttachResult?> pickAttachment(BuildContext context) {
  OuroHaptics.selection();
  return showModalBottomSheet<AttachResult>(
    context: context,
    backgroundColor: Colors.transparent,
    // ── ⚠️ LE VOILE DERRIÈRE LA FEUILLE ────────────────────────────
    //
    // Flutter assombrit par défaut tout ce qui se trouve derrière une
    // feuille modale, à 54 % de noir. Sur une feuille OPAQUE, cela ne se
    // voit pas. Sur une feuille en verre, c'est fatal : le verre ne
    // transmet plus que du gris, et le panneau ressemble à du carton
    // quelle que soit la finesse du matériau qu'on lui donne.
    //
    // À 18 %, la conversation reste nettement visible derrière, le verre
    // prend enfin la couleur de ce qu'il recouvre — et l'assombrissement
    // suffit encore à désigner la feuille comme l'élément actif.
    barrierColor: Colors.black.withValues(alpha: 0.18),
    // Le panneau doit pouvoir descendre sous la barre système sans que
    // ses coins arrondis soient rognés.
    isScrollControlled: true,
    builder: (context) => const _AttachSheet(),
  );
}

class _AttachSheet extends StatelessWidget {
  const _AttachSheet();

  @override
  Widget build(BuildContext context) {
    return FrostedSheet(
      // ⚠️ `thin` ET NON `regular`. Ce panneau ne porte que quatre
      // grandes cibles et des photos : rien qui demande un fond opaque
      // pour rester lisible. Avec le voile épais par défaut (80 %
      // d'opacité), il ressemblait à une dalle grise posée sur l'écran.
      // Allégé, la conversation transparaît réellement au travers — et
      // c'est cette transparence, plus que la couleur, qui distingue le
      // verre du carton.
      material: OuroMaterial.thin,
      // Les marges latérales sont reprises ici pour que la bande de
      // photos puisse, elle, déborder jusqu'aux bords.
      // La `SafeArea` du contenu réserve déjà la place de la barre
      // système : ajouter une marge basse par-dessus creusait un vide
      // sous les photos.
      padding: EdgeInsets.zero,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── LES ACTIONS D'ABORD, EN RANGÉE ──────────────────────
            //
            // ⚠️ CE N'ÉTAIT PAS L'ORDRE DE LA PREMIÈRE VERSION, et
            // l'inversion est délibérée.
            //
            // La bande de photos était en haut, les actions en dessous,
            // en liste verticale à deux lignes. Deux défauts :
            //
            //   • la liste ressemblait à un écran de RÉGLAGES — icône en
            //     pastille, titre, sous-titre explicatif — alors qu'un
            //     panneau d'action se parcourt d'un coup d'œil, pas en
            //     lisant ;
            //   • le panneau montait très haut pour quatre choix, et
            //     recouvrait la conversation qu'on est justement censé
            //     ne pas perdre de vue.
            //
            // La rangée horizontale règle les deux : les quatre actions
            // tiennent sur une ligne, le panneau descend, et la
            // conversation reste visible derrière. C'est la disposition
            // du panneau de partage d'iOS, et celle qu'a retenue
            // WhatsApp en 2026.
            const SizedBox(height: DesignTokens.space3),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.screenMargin,
              ),
              child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _ActionCarte(
                  choix: AttachChoice.media,
                  icone: Icons.photo_library_rounded,
                  couleur: OuroColors.systemPurple,
                  libelle: 'Galerie',
                ),
                _ActionCarte(
                  choix: AttachChoice.document,
                  icone: Icons.description_rounded,
                  couleur: OuroColors.accent,
                  libelle: 'Document',
                ),
                _ActionCarte(
                  choix: AttachChoice.sticker,
                  icone: Icons.emoji_emotions_rounded,
                  couleur: OuroColors.systemOrange,
                  libelle: 'Sticker',
                ),
                _ActionCarte(
                  choix: AttachChoice.position,
                  icone: Icons.near_me_rounded,
                  couleur: OuroColors.systemGreen,
                  libelle: 'Position',
                ),
              ],
              ),
            ),
            const SizedBox(height: DesignTokens.space5),

            // ── PUIS LES RÉCENTS ────────────────────────────────────
            //
            // Sous les actions, comme chez WhatsApp. La bande s'efface
            // d'elle-même si l'accès à la photothèque est refusé.
            RecentMediaStrip(
              onChoisi: (asset) =>
                  Navigator.of(context).pop(AttachResult.media(asset)),
              onToutVoir: () => Navigator.of(context)
                  .pop(const AttachResult.choix(AttachChoice.media)),
            ),
            const SizedBox(height: DesignTokens.space2),
          ],
        ),
      ),
    );
  }
}

/// Une action du panneau : une pastille ronde et un mot dessous.
///
/// Le libellé tient en UN mot. « Photo ou vidéo · Depuis la galerie »
/// disait la même chose en six, et transformait un choix instantané en
/// lecture. Sous une icône explicite, un mot suffit à lever le doute.
class _ActionCarte extends StatefulWidget {
  const _ActionCarte({
    required this.choix,
    required this.icone,
    required this.couleur,
    required this.libelle,
  });

  final AttachChoice choix;
  final IconData icone;
  final Color couleur;
  final String libelle;

  @override
  State<_ActionCarte> createState() => _ActionCarteState();
}

class _ActionCarteState extends State<_ActionCarte> {
  bool _presse = false;

  void _set(bool v) {
    if (_presse != v && mounted) setState(() => _presse = v);
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: widget.libelle,
      excludeSemantics: true,
      onTap: () =>
          Navigator.of(context).pop(AttachResult.choix(widget.choix)),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: () {
          OuroHaptics.light();
          Navigator.of(context).pop(AttachResult.choix(widget.choix));
        },
        // Le retour tactile d'iOS : la cible s'enfonce légèrement sous le
        // doigt, sans onde qui se propage.
        child: AnimatedScale(
          scale: _presse ? 0.92 : 1,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: SizedBox(
            width: 76,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── UNE CARTE, PAS UNE PASTILLE ───────────────────
                //
                // Sur les captures, chaque action est une petite carte
                // BLANCHE à coins arrondis, large et basse, avec l'icône
                // colorée posée dedans. La pastille ronde teintée que
                // j'avais faite venait des Réglages d'iOS, pas d'un
                // panneau de partage : elle enfermait l'icône dans un
                // cercle de sa propre couleur, ce qui délavait les deux.
                //
                // La carte blanche laisse la couleur à la seule icône —
                // c'est elle qu'on reconnaît de loin, pas son fond.
                OuroCard(
                  padding: const EdgeInsets.all(8),
                  child: SizedBox(
                    width: 60,
                    height: 42,
                    child: Icon(widget.icone, color: widget.couleur, size: 26),
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  widget.libelle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  // Libellé FONCÉ, pas gris : sur les captures il a le
                  // même poids que le texte de l'app. En gris, il se
                  // lisait comme une légende secondaire alors que c'est
                  // le nom de l'action.
                  style: OuroTypography.footnote
                      .copyWith(color: OuroColors.label),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
