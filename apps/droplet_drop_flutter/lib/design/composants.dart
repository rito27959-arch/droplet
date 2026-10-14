// DROPLET LIQUID — les composants.
//
// Trois matériaux :
//   • SURFACE PLEINE — listes, réglages, informations : `Carte` ;
//   • GIVRE — barres flottantes et feuilles : `Givre` (flou mesuré, avec
//     un repli opaque quand l'utilisateur réduit la transparence) ;
//   • LIQUIDE — l'action principale et la progression : le dégradé de
//     l'accent, `BoutonLiquide`, `AnneauProgression`.
//
// Chaque élément touchable a ses états : normal, pressé (léger
// enfoncement), survolé (ordinateur), désactivé, chargement.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'couleurs.dart';
import 'typo.dart';

const Curve kSortie = Cubic(0.16, 1, 0.3, 1);
const Curve kRessort = Cubic(0.34, 1.36, 0.64, 1);

/// Vrai si l'utilisateur a demandé de réduire les animations.
bool reduireAnimations(BuildContext c) => MediaQuery.maybeDisableAnimationsOf(c) ?? false;

Duration duree(BuildContext c, int ms) => reduireAnimations(c) ? Duration.zero : Duration(milliseconds: ms);

/// Un élément pressable : enfoncement doux, survol, curseur, focus clavier.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.onTap, this.enfoncement = 0.97, this.semantique, this.haptique = true, this.attenuerInactif = true});

  final Widget child;
  final VoidCallback? onTap;
  final double enfoncement;
  final String? semantique;
  final bool haptique;

  /// Vrai : inactif, l'élément s'estompe. Faux : il dessine lui-même son
  /// état inactif (le bouton liquide devient gris, pas délavé).
  final bool attenuerInactif;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _presse = false;
  bool _survol = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final actif = widget.onTap != null;
    final p = context.p;
    return Semantics(
      button: true,
      enabled: actif,
      label: widget.semantique,
      child: FocusableActionDetector(
        enabled: actif,
        mouseCursor: actif ? SystemMouseCursors.click : MouseCursor.defer,
        onShowHoverHighlight: (v) => setState(() => _survol = v),
        onShowFocusHighlight: (v) => setState(() => _focus = v),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            widget.onTap?.call();
            return null;
          }),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: actif ? (_) => setState(() => _presse = true) : null,
          onTapCancel: () => setState(() => _presse = false),
          onTapUp: actif ? (_) => setState(() => _presse = false) : null,
          onTap: actif
              ? () {
                  if (widget.haptique) HapticFeedback.selectionClick();
                  widget.onTap!();
                }
              : null,
          child: AnimatedScale(
            scale: _presse ? widget.enfoncement : 1,
            duration: duree(context, _presse ? 90 : 260),
            curve: _presse ? Curves.easeOut : kRessort,
            child: AnimatedOpacity(
              opacity: actif ? (_survol && !_presse ? 0.92 : 1) : (widget.attenuerInactif ? 0.45 : 1),
              duration: duree(context, 150),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  border: _focus ? Border.all(color: p.accentTexte, width: 2) : null,
                ),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// L'action principale : le dégradé liquide de l'accent.
class BoutonLiquide extends StatelessWidget {
  const BoutonLiquide({super.key, required this.texte, this.icone, this.onTap, this.chargement = false, this.hauteur = 56, this.large = true});

  final String texte;
  final IconData? icone;
  final VoidCallback? onTap;
  final bool chargement;
  final double hauteur;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    // Inactif (rien à envoyer, personne de choisi) : une surface grise
    // nette, comme les boutons d'iOS — pas un dégradé délavé illisible.
    final inactif = onTap == null && !chargement;
    final encre = inactif ? p.texte3 : Colors.white;
    final contenu = Row(
      mainAxisSize: large ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (chargement)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
        else if (icone != null)
          Icon(icone, color: encre, size: 21),
        if (chargement || icone != null) const SizedBox(width: 10),
        Flexible(
          child: Text(texte, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.titreCarte.copyWith(color: encre)),
        ),
      ],
    );
    return Pressable(
      onTap: chargement ? null : onTap,
      semantique: texte,
      attenuerInactif: false,
      child: AnimatedContainer(
        duration: duree(context, 240),
        curve: kSortie,
        height: hauteur,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: inactif ? null : p.liquide,
          color: inactif ? p.surfaceHaute : null,
          borderRadius: BorderRadius.circular(hauteur / 2.8),
          boxShadow: inactif
              ? const []
              : [BoxShadow(color: p.accent.withValues(alpha: p.sombre ? 0.32 : 0.26), blurRadius: 22, spreadRadius: -4, offset: const Offset(0, 10))],
        ),
        // Un reflet en haut : la matière, sans effet gratuit.
        foregroundDecoration: inactif
            ? null
            : BoxDecoration(
                borderRadius: BorderRadius.circular(hauteur / 2.8),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.center,
                  colors: [Colors.white.withValues(alpha: 0.16), Colors.white.withValues(alpha: 0)],
                ),
              ),
        child: contenu,
      ),
    );
  }
}

/// L'action secondaire : surface pleine, bordure fine.
class BoutonSecondaire extends StatelessWidget {
  const BoutonSecondaire({super.key, required this.texte, this.icone, this.onTap, this.hauteur = 56, this.couleur, this.large = true});

  final String texte;
  final IconData? icone;
  final VoidCallback? onTap;
  final double hauteur;
  final Color? couleur;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final c = couleur ?? p.texte;
    return Pressable(
      onTap: onTap,
      semantique: texte,
      child: Container(
        height: hauteur,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(hauteur / 2.8),
          border: Border.all(color: p.trait),
        ),
        child: Row(
          mainAxisSize: large ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icone != null) ...[Icon(icone, color: couleur ?? p.accentTexte, size: 20), const SizedBox(width: 10)],
            Flexible(child: Text(texte, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.titreCarte.copyWith(color: c))),
          ],
        ),
      ),
    );
  }
}

/// Un petit bouton rond (icône seule), avec son nom pour les lecteurs
/// d'écran et l'infobulle de la souris.
class BoutonIcone extends StatelessWidget {
  const BoutonIcone({super.key, required this.icone, required this.nom, this.onTap, this.couleur, this.taille = 40});

  final IconData icone;
  final String nom;
  final VoidCallback? onTap;
  final Color? couleur;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Tooltip(
      message: nom,
      child: Pressable(
        onTap: onTap,
        semantique: nom,
        enfoncement: 0.9,
        child: Container(
          width: taille,
          height: taille,
          decoration: BoxDecoration(color: p.surfaceHaute, shape: BoxShape.circle),
          child: Icon(icone, size: taille * 0.5, color: couleur ?? p.texte),
        ),
      ),
    );
  }
}

/// La surface pleine.
class Carte extends StatelessWidget {
  const Carte({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap, this.couleur, this.selectionnee = false});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? couleur;

  /// Choisie (un destinataire) : liseré d'accent et fond teinté.
  final bool selectionnee;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final boite = AnimatedContainer(
      duration: duree(context, 220),
      curve: kSortie,
      padding: padding,
      decoration: BoxDecoration(
        color: selectionnee ? Color.alphaBlend(p.accent.withValues(alpha: p.sombre ? 0.12 : 0.07), p.surface) : (couleur ?? (p.sombre ? null : p.surface)),
        // La nuit : du verre fumé, un reflet à peine plus clair en haut —
        // les cartes du site posées sur le ciel.
        gradient: p.sombre && !selectionnee && couleur == null
            ? LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color.alphaBlend(Colors.white.withValues(alpha: 0.05), p.surface).withValues(alpha: 0.9), p.surface.withValues(alpha: 0.86)],
              )
            : null,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: selectionnee ? p.accent.withValues(alpha: 0.9) : p.trait, width: selectionnee ? 1.5 : 1),
        boxShadow: p.sombre ? null : [BoxShadow(color: const Color(0xFF0B1220).withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      // Une surface Material transparente : les ListTile posés dans une
      // carte y dessinent leur effet de toucher au lieu de le perdre dessous.
      child: Material(type: MaterialType.transparency, child: child),
    );
    return onTap == null ? boite : Pressable(onTap: onTap, enfoncement: 0.985, child: boite);
  }
}

/// Le givre : flou + voile. Repli opaque si la plateforme demande moins
/// de transparence (accessibilité) ou si le flou coûte trop.
class Givre extends StatelessWidget {
  const Givre({super.key, required this.child, this.rayon = 0});

  final Widget child;
  final double rayon;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final opaque = MediaQuery.maybeHighContrastOf(context) ?? false;
    final voile = DecoratedBox(
      decoration: BoxDecoration(
        color: opaque ? p.fondEleve : p.fondEleve.withValues(alpha: p.sombre ? 0.72 : 0.78),
        border: Border(top: BorderSide(color: p.trait)),
      ),
      child: child,
    );
    if (opaque) return voile;
    return ClipRRect(
      borderRadius: BorderRadius.circular(rayon),
      child: BackdropFilter(filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24), child: voile),
    );
  }
}

/// Le fond de l'application : le ciel du site. La nuit : un dégradé bleu
/// très profond, une lueur d'accent en haut, et des étoiles fixes (toujours
/// les mêmes, rien ne bouge). Le jour : le gris lumineux, et la même lueur,
/// plus douce.
class Fond extends StatelessWidget {
  const Fond({super.key, required this.child, this.lueur = const Alignment(0, -1.1)});

  final Widget child;
  final Alignment lueur;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.fond,
        gradient: p.sombre
            ? const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFF071029), Color(0xFF05070C)], stops: [0, .55])
            : null,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: lueur,
            radius: 1.1,
            colors: [p.accent.withValues(alpha: p.sombre ? 0.24 : 0.10), p.accent.withValues(alpha: 0)],
          ),
        ),
        child: p.sombre ? CustomPaint(painter: const _Etoiles(), child: child) : child,
      ),
    );
  }
}

/// Le champ d'étoiles du site : pseudo-aléatoire mais fixe (même graine),
/// plus dense en haut, et très discret.
class _Etoiles extends CustomPainter {
  const _Etoiles();

  @override
  void paint(Canvas canvas, Size size) {
    var graine = 7;
    double alea() {
      graine = (graine * 1103515245 + 12345) & 0x7fffffff;
      return graine / 0x7fffffff;
    }

    final n = (size.width * size.height / 9000).clamp(40, 220).round();
    final pinceau = Paint();
    for (var i = 0; i < n; i++) {
      final x = alea() * size.width;
      // Plus d'étoiles près du haut.
      final y = alea() * alea() * size.height;
      final r = 0.5 + alea() * 1.1;
      pinceau.color = Colors.white.withValues(alpha: 0.12 + alea() * 0.45 * (1 - y / size.height));
      canvas.drawCircle(Offset(x, y), r, pinceau);
    }
  }

  @override
  bool shouldRepaint(_Etoiles old) => false;
}

/// La progression : un anneau au dégradé liquide.
class AnneauProgression extends StatelessWidget {
  const AnneauProgression({super.key, required this.valeur, this.taille = 52, this.epaisseur = 5, this.couleur, this.centre});

  final double valeur;
  final double taille;
  final double epaisseur;
  final Color? couleur;
  final Widget? centre;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: valeur.clamp(0, 1)),
      duration: duree(context, 420),
      curve: kSortie,
      builder: (context, v, _) => SizedBox(
        width: taille,
        height: taille,
        child: CustomPaint(
          painter: _Anneau(v, epaisseur, p.surfaceHaute, couleur == null ? [p.accent, p.accent2] : [couleur!, couleur!]),
          child: Center(child: centre),
        ),
      ),
    );
  }
}

class _Anneau extends CustomPainter {
  _Anneau(this.v, this.e, this.piste, this.couleurs);

  final double v;
  final double e;
  final Color piste;
  final List<Color> couleurs;

  @override
  void paint(Canvas canvas, Size s) {
    final r = Rect.fromLTWH(e / 2, e / 2, s.width - e, s.height - e);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..color = piste
      ..style = PaintingStyle.stroke
      ..strokeWidth = e);
    if (v <= 0) return;
    canvas.drawArc(
      r,
      -math.pi / 2,
      math.pi * 2 * v,
      false,
      Paint()
        ..shader = SweepGradient(startAngle: -math.pi / 2, endAngle: math.pi * 1.5, colors: couleurs, transform: const GradientRotation(-math.pi / 2)).createShader(r)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = e,
    );
  }

  @override
  bool shouldRepaint(_Anneau o) => o.v != v || o.piste != piste || o.couleurs != couleurs;
}

/// Une barre de progression fine (listes).
class BarreProgression extends StatelessWidget {
  const BarreProgression({super.key, required this.valeur, this.couleur, this.hauteur = 6});

  final double valeur;
  final Color? couleur;
  final double hauteur;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ClipRRect(
      borderRadius: BorderRadius.circular(hauteur),
      child: SizedBox(
        height: hauteur,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: p.surfaceHaute)),
            // Positioned.fill + heightFactor 1 : la partie pleine prend
            // toute la hauteur de la barre (sans, elle mesurait 0 px et la
            // progression restait invisible).
            Positioned.fill(
              child: TweenAnimationBuilder<double>(
                tween: Tween(end: valeur.clamp(0, 1)),
                duration: duree(context, 420),
                curve: kSortie,
                builder: (context, v, _) => FractionallySizedBox(
                  alignment: AlignmentDirectional.centerStart,
                  widthFactor: v,
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: couleur == null ? p.liquide : null,
                      color: couleur,
                      borderRadius: BorderRadius.circular(hauteur),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// L'état vide : on dit ce qui se passe et quoi faire, sans dramatiser.
class EtatVide extends StatelessWidget {
  const EtatVide({super.key, required this.icone, required this.titre, this.texte, this.action});

  final IconData icone;
  final String titre;
  final String? texte;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: p.accent.withValues(alpha: p.sombre ? 0.14 : 0.1), shape: BoxShape.circle),
            child: Icon(icone, color: p.accentTexte, size: 28),
          ),
          const SizedBox(height: 14),
          Text(titre, textAlign: TextAlign.center, style: Typo.titreCarte.copyWith(color: p.texte)),
          if (texte != null) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(texte!, textAlign: TextAlign.center, style: Typo.secondaire.copyWith(color: p.texte2)),
            ),
          ],
          if (action != null) ...[const SizedBox(height: 18), action!],
        ],
      ),
    );
  }
}

/// Un titre de section (« APPAREILS À PROXIMITÉ »).
class TitreSection extends StatelessWidget {
  const TitreSection(this.texte, {super.key, this.fin});

  final String texte;
  final Widget? fin;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 26, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(texte.toUpperCase(), style: Typo.legende.copyWith(color: p.texte2, letterSpacing: 0.8)),
            ),
          ),
          ?fin,
        ],
      ),
    );
  }
}

/// Apparition douce (échelle + opacité), une seule fois.
class Apparition extends StatelessWidget {
  const Apparition({super.key, required this.child, this.delai = 0});

  final Widget child;
  final int delai;

  @override
  Widget build(BuildContext context) {
    if (reduireAnimations(context)) return child;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: 520 + delai),
      curve: Interval(delai / (520 + delai), 1, curve: kSortie),
      builder: (context, v, enfant) => Opacity(
        opacity: v,
        child: Transform.scale(scale: 0.94 + 0.06 * v, child: enfant),
      ),
      child: child,
    );
  }
}

/// La largeur de lecture : sur un grand écran, le contenu reste une
/// colonne confortable au centre.
class Colonne extends StatelessWidget {
  const Colonne({super.key, required this.child, this.max = 720});

  final Widget child;
  final double max;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: max), child: child),
      );
}


/// Le sélecteur segmenté d'iOS : une piste, et une pastille qui GLISSE
/// d'une option à l'autre (au lieu de cases qui s'allument). Les libellés
/// ne passent jamais à la ligne : ils rétrécissent s'il le faut.
class Segments<T> extends StatelessWidget {
  const Segments({super.key, required this.options, required this.valeur, required this.onChange});

  final List<(T, String, IconData?)> options;
  final T valeur;
  final ValueChanged<T> onChange;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final i = options.indexWhere((o) => o.$1 == valeur).clamp(0, options.length - 1);
    final n = options.length;
    return Semantics(
      container: true,
      child: Container(
        height: 40,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: p.surfaceHaute, borderRadius: BorderRadius.circular(12)),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: duree(context, 320),
              curve: kRessort,
              alignment: AlignmentDirectional(n == 1 ? 0 : -1 + 2 * i / (n - 1), 0).resolve(Directionality.of(context)),
              child: FractionallySizedBox(
                widthFactor: 1 / n,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: p.sombre ? const Color(0xFF3A4556) : Colors.white,
                    borderRadius: BorderRadius.circular(9),
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.sombre ? 0.3 : 0.1), blurRadius: 8, offset: const Offset(0, 2))],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                for (final (k, o) in options.indexed)
                  Expanded(
                    child: Semantics(
                      selected: k == i,
                      button: true,
                      label: o.$2,
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (k == i) return;
                          HapticFeedback.selectionClick();
                          onChange(o.$1);
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (o.$3 != null) ...[Icon(o.$3, size: 16, color: k == i ? p.texte : p.texte2), const SizedBox(width: 6)],
                                    Text(o.$2, maxLines: 1, style: Typo.secondaire.copyWith(color: k == i ? p.texte : p.texte2, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Une liste groupée à la manière des Réglages d'iOS : des lignes dans une
/// carte, séparées par un trait qui commence après l'icône.
class Groupe extends StatelessWidget {
  const Groupe({super.key, required this.lignes});

  final List<Widget> lignes;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Carte(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          for (final (i, l) in lignes.indexed) ...[
            if (i > 0) Padding(padding: const EdgeInsetsDirectional.only(start: 60), child: Divider(height: 1, thickness: 1, color: p.trait)),
            l,
          ],
        ],
      ),
    );
  }
}

/// Une ligne de réglage : la tuile colorée, le titre, la valeur, le chevron.
class Ligne extends StatelessWidget {
  const Ligne({super.key, required this.icone, required this.titre, this.valeur, this.sousTitre, this.teinte, this.onTap, this.fin});

  final IconData icone;
  final String titre;
  final String? valeur;
  final String? sousTitre;
  final Color? teinte;
  final VoidCallback? onTap;
  final Widget? fin;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final contenu = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(color: teinte ?? p.accent, borderRadius: BorderRadius.circular(8)),
            child: Icon(icone, size: 18, color: Colors.white),
          ),
          const SizedBox(width: 14),
          // Avec une valeur, c'est elle qui prend la place restante : elle
          // se cale à droite, contre le chevron, comme dans les Réglages.
          Flexible(
            flex: valeur == null ? 1 : 0,
            fit: valeur == null ? FlexFit.tight : FlexFit.loose,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre, style: Typo.corps.copyWith(color: p.texte)),
                if (sousTitre != null) Text(sousTitre!, maxLines: 2, overflow: TextOverflow.ellipsis, style: Typo.legende.copyWith(color: p.texte2)),
              ],
            ),
          ),
          if (valeur != null) ...[
            const SizedBox(width: 10),
            Expanded(child: Text(valeur!, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.end, style: Typo.corps.copyWith(color: p.texte2))),
          ],
          if (fin != null) ...[const SizedBox(width: 8), fin!],
          if (onTap != null && fin == null) ...[const SizedBox(width: 4), Icon(Icons.chevron_right_rounded, color: p.texte3)],
        ],
      ),
    );
    return onTap == null ? contenu : Pressable(onTap: onTap, enfoncement: 0.99, semantique: titre, child: contenu);
  }
}

/// Le radar : des ondes qui partent doucement d'un centre — on cherche les
/// appareils autour. Immobile si l'utilisateur réduit les animations.
class Radar extends StatefulWidget {
  const Radar({super.key, required this.child, this.taille = 180});

  final Widget child;
  final double taille;

  @override
  State<Radar> createState() => _RadarState();
}

class _RadarState extends State<Radar> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduireAnimations(context)) {
      _c.stop();
      _c.value = 0.5;
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return SizedBox(
      width: widget.taille,
      height: widget.taille,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _c,
            builder: (context, _) => CustomPaint(size: Size.square(widget.taille), painter: _Ondes(_c.value, p.accent)),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _Ondes extends CustomPainter {
  _Ondes(this.t, this.couleur);

  final double t;
  final Color couleur;

  @override
  void paint(Canvas canvas, Size s) {
    final c = s.center(Offset.zero);
    for (var k = 0; k < 3; k++) {
      final v = (t + k / 3) % 1;
      final r = s.width * (0.2 + 0.3 * Curves.easeOut.transform(v));
      canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = couleur.withValues(alpha: 0.28 * (1 - v))
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
  }

  @override
  bool shouldRepaint(_Ondes o) => o.t != t || o.couleur != couleur;
}

/// Une pastille qui respire : « en direct », « on cherche ».
class Pulsation extends StatefulWidget {
  const Pulsation({super.key, this.couleur, this.taille = 8});

  final Color? couleur;
  final double taille;

  @override
  State<Pulsation> createState() => _PulsationState();
}

class _PulsationState extends State<Pulsation> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduireAnimations(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final couleur = widget.couleur ?? context.p.succes;
    return SizedBox(
      width: widget.taille * 2.4,
      height: widget.taille * 2.4,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: widget.taille * (1 + 1.4 * _c.value),
              height: widget.taille * (1 + 1.4 * _c.value),
              decoration: BoxDecoration(shape: BoxShape.circle, color: couleur.withValues(alpha: 0.35 * (1 - _c.value))),
            ),
            Container(width: widget.taille, height: widget.taille, decoration: BoxDecoration(shape: BoxShape.circle, color: couleur)),
          ],
        ),
      ),
    );
  }
}

/// Une feuille de choix (langue…) : la liste, la coche sur l'option
/// courante, comme les listes de choix d'iOS.
Future<T?> choisirDansListe<T>(BuildContext context, {required String titre, required List<(T, String)> options, required T courant}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (c) {
      final p = c.p;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(c).height * 0.75, maxWidth: 560),
            child: Carte(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                    child: Text(titre, style: Typo.titreCarte.copyWith(color: p.texte)),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final o in options)
                          Pressable(
                            enfoncement: 0.99,
                            semantique: o.$2,
                            onTap: () => Navigator.pop(c, o.$1),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                              child: Row(
                                children: [
                                  Expanded(child: Text(o.$2, style: Typo.corps.copyWith(color: p.texte))),
                                  if (o.$1 == courant) Icon(Icons.check_rounded, color: p.accentTexte),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
