// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Les LISTES GROUPÉES d'iOS — la structure visuelle qu'on voit dans
// Réglages, Contacts, ou l'écran d'infos d'une conversation : des îlots
// gris clair aux coins arrondis, posés sur le fond noir, séparés en
// sections coiffées d'un petit titre en gris.
//
// TROIS DÉTAILS FONT TOUTE LA DIFFÉRENCE, et ce sont ceux que les apps
// non natives ratent systématiquement :
//
//   1. LES SÉPARATEURS SONT DÉCALÉS. Le trait entre deux lignes ne part
//      PAS du bord de l'îlot : il démarre là où commence le TEXTE, après
//      l'avatar ou l'icône. L'œil suit ainsi la colonne de texte au lieu
//      d'être coupé horizontalement. C'est le détail iOS par excellence.
//
//   2. LE DERNIER ÉLÉMENT N'A PAS DE SÉPARATEUR. Un trait juste avant le
//      bord arrondi de l'îlot est la marque immédiate du travail bâclé.
//
//   3. LES COINS NE SONT ARRONDIS QU'AUX EXTRÉMITÉS. Le premier élément
//      arrondit ses coins du haut, le dernier ceux du bas, ceux du
//      milieu restent carrés — l'îlot forme un bloc continu, pas une
//      pile de cartes séparées.
//
// Ce fichier prend en charge ces trois règles automatiquement : il
// suffit de fournir les lignes, le reste est calculé.
// ============================================================================

import 'package:flutter/material.dart';
import 'ouro_colors.dart';
import 'ouro_typography.dart';
import 'ouro_haptics.dart';
import 'design_tokens.dart';

// ─────────────────────────────────────────────────────────────
//  SECTION
// ─────────────────────────────────────────────────────────────

/// Une section de liste groupée : un titre facultatif, un îlot de lignes,
/// et une note explicative facultative en dessous.
///
/// Gère automatiquement l'arrondi des extrémités et le décalage des
/// séparateurs décrits en tête de fichier.
class OuroListSection extends StatelessWidget {
  const OuroListSection({
    super.key,
    required this.children,
    this.header,
    this.footer,
    this.separatorInset = 60,
  });

  /// Les lignes de la section.
  final List<Widget> children;

  /// Petit titre gris au-dessus de l'îlot (« NOTIFICATIONS »).
  final String? header;

  /// Note explicative sous l'îlot, pour justifier un réglage sans
  /// alourdir la ligne elle-même.
  final String? footer;

  /// Décalage à gauche des séparateurs — doit correspondre à l'endroit où
  /// commence le texte des lignes. 60 convient à une ligne avec icône ;
  /// utiliser 16 pour une ligne de texte seul.
  final double separatorInset;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      // Règle n°2 : jamais de séparateur après le dernier élément.
      if (i < children.length - 1) {
        rows.add(Padding(
          padding: EdgeInsets.only(left: separatorInset),
          child: Divider(
            height: 0.5,
            thickness: 0.5,
            color: OuroColors.separator,
          ),
        ));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.screenMargin,
              DesignTokens.space5,
              DesignTokens.screenMargin,
              DesignTokens.space2,
            ),
            child: Text(
              header!.toUpperCase(),
              style: OuroTypography.sectionHeader.copyWith(
                color: OuroColors.secondaryLabel,
                letterSpacing: 0.5,
              ),
            ),
          ),
        // Règle n°3 : l'îlot arrondit ses extrémités, et son `clipBehavior`
        // fait que les lignes internes s'y conforment sans avoir à gérer
        // leurs coins une par une.
        Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: OuroColors.secondarySystemGroupedBackground,
            borderRadius: BorderRadius.circular(DesignTokens.radiusGroupedList),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: rows,
          ),
        ),
        if (footer != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.screenMargin,
              DesignTokens.space2,
              DesignTokens.screenMargin,
              0,
            ),
            child: Text(
              footer!,
              style: OuroTypography.footnote.copyWith(
                color: OuroColors.secondaryLabel,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  LIGNE
// ─────────────────────────────────────────────────────────────

/// Une ligne de liste groupée iOS : icône colorée facultative dans un
/// carré arrondi, titre, sous-titre, valeur à droite, chevron.
///
/// L'icône en pastille colorée est la signature visuelle de l'écran
/// Réglages d'iOS : elle donne un repère de couleur immédiat pour
/// retrouver une ligne sans lire son intitulé.
class OuroListRow extends StatefulWidget {
  const OuroListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.iconColor,
    this.leading,
    this.trailing,
    this.value,
    this.onTap,
    this.showChevron = true,
    this.isDestructive = false,
  });

  final String title;
  final String? subtitle;

  /// Icône affichée dans la pastille colorée à gauche.
  final IconData? icon;

  /// Couleur de la pastille (l'icône elle-même reste blanche).
  final Color? iconColor;

  /// Contenu de gauche personnalisé (un avatar par exemple) — prioritaire
  /// sur [icon].
  final Widget? leading;

  /// Contenu de droite personnalisé (un interrupteur par exemple).
  final Widget? trailing;

  /// Valeur affichée en gris à droite (« Activé », « 3 »).
  final String? value;

  final VoidCallback? onTap;

  /// Chevron « › » indiquant que la ligne mène ailleurs. Masqué
  /// automatiquement si la ligne n'est pas cliquable ou porte déjà un
  /// [trailing].
  final bool showChevron;

  /// Action destructive — affiche le titre en rouge (« Supprimer »,
  /// « Quitter le groupe »).
  final bool isDestructive;

  @override
  State<OuroListRow> createState() => _OuroListRowState();
}

class _OuroListRowState extends State<OuroListRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final interactive = widget.onTap != null;
    final titleColor =
        widget.isDestructive ? OuroColors.systemRed : OuroColors.label;

    final row = Container(
      // Retour tactile iOS : la ligne s'assombrit tant que le doigt est
      // posé, sans onde qui se propage.
      color: _pressed
          ? OuroColors.systemGray5
          : OuroColors.secondarySystemGroupedBackground,
      constraints: const BoxConstraints(minHeight: DesignTokens.minTouchTarget),
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.screenMargin,
        vertical: DesignTokens.space2 + 2,
      ),
      child: Row(
        children: [
          if (widget.leading != null) ...[
            widget.leading!,
            const SizedBox(width: DesignTokens.space3),
          ] else if (widget.icon != null) ...[
            _IconBadge(
              icon: widget.icon!,
              color: widget.iconColor ?? OuroColors.systemGray,
            ),
            const SizedBox(width: DesignTokens.space3),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: OuroTypography.body.copyWith(color: titleColor),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(
                    widget.subtitle!,
                    style: OuroTypography.footnote.copyWith(
                      color: OuroColors.secondaryLabel,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          if (widget.value != null) ...[
            const SizedBox(width: DesignTokens.space2),
            Text(
              widget.value!,
              style: OuroTypography.body.copyWith(
                color: OuroColors.secondaryLabel,
              ),
            ),
          ],
          if (widget.trailing != null) ...[
            const SizedBox(width: DesignTokens.space2),
            widget.trailing!,
          ] else if (interactive && widget.showChevron) ...[
            const SizedBox(width: DesignTokens.space1),
            Icon(
              Icons.chevron_right_rounded,
              size: DesignTokens.iconLg,
              // Le chevron iOS est gris, jamais coloré : il indique une
              // direction, pas une action.
              color: OuroColors.tertiaryLabel,
            ),
          ],
        ],
      ),
    );

    if (!interactive) return row;

    // ⚠️ `Semantics` regroupe la ligne en UN SEUL élément pour le
    // lecteur d'écran.
    //
    // Sans `container: true`, VoiceOver traverse la ligne morceau par
    // morceau : le titre, puis le sous-titre, puis la valeur, puis le
    // chevron — quatre arrêts pour une seule rangée, et l'utilisateur ne
    // sait jamais où finit un réglage et où commence le suivant. Avec,
    // il entend « Réseau mesh, Pairs connectés et topologie, bouton » et
    // passe au suivant d'un geste. C'est exactement ce que fait
    // l'application Réglages d'iOS.
    // ⚠️ On ne masque le contenu QUE s'il n'y a pas de widget à droite.
    //
    // Un `trailing` est souvent un INTERRUPTEUR — et un interrupteur est
    // un élément actionnable à part entière, avec son propre état
    // « activé / désactivé » que le lecteur d'écran doit annoncer et
    // pouvoir basculer. Le masquer au nom de la lisibilité rendrait le
    // réglage impossible à modifier sans voir l'écran : on aurait
    // remplacé une gêne par une exclusion.
    final resumable = widget.trailing == null;

    return Semantics(
      container: true,
      button: true,
      label: [
        widget.title,
        if (widget.subtitle != null) widget.subtitle!,
        if (widget.value != null) widget.value!,
      ].join(', '),
      excludeSemantics: resumable,
      onTap: () {
        OuroHaptics.selection();
        widget.onTap!();
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapCancel: () => setState(() => _pressed = false),
        onTap: () {
          setState(() => _pressed = false);
          OuroHaptics.selection();
          widget.onTap!();
        },
        child: row,
      ),
    );
  }
}

/// La pastille carrée arrondie qui contient l'icône d'une ligne de
/// réglage. Dimensions iOS : 29×29 points, icône de 18.
class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 29,
      height: 29,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 18, color: Colors.white),
    );
  }
}
