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
  const Pressable({super.key, required this.child, this.onTap, this.enfoncement = 0.97, this.semantique, this.haptique = true});

  final Widget child;
  final VoidCallback? onTap;
  final double enfoncement;
  final String? semantique;
  final bool haptique;

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
              opacity: actif ? (_survol && !_presse ? 0.92 : 1) : 0.45,
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
    final contenu = Row(
      mainAxisSize: large ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (chargement)
          const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white))
        else if (icone != null)
          Icon(icone, color: Colors.white, size: 21),
        if (chargement || icone != null) const SizedBox(width: 10),
        Flexible(
          child: Text(texte, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.titreCarte.copyWith(color: Colors.white)),
        ),
      ],
    );
    return Pressable(
      onTap: chargement ? null : onTap,
      semantique: texte,
      child: Container(
        height: hauteur,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: BoxDecoration(
          gradient: p.liquide,
          borderRadius: BorderRadius.circular(hauteur / 2.8),
          boxShadow: [
            BoxShadow(color: p.accent.withValues(alpha: p.sombre ? 0.35 : 0.28), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        // Un reflet en haut : la matière, sans effet gratuit.
        foregroundDecoration: BoxDecoration(
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
  const Carte({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap, this.couleur});

  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;
  final Color? couleur;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final boite = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: couleur ?? p.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: p.trait),
        boxShadow: p.sombre ? null : [BoxShadow(color: const Color(0xFF0B1220).withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: child,
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

/// Le fond de l'application : uni, avec une lueur d'accent très douce en
/// haut. Rien qui bouge.
class Fond extends StatelessWidget {
  const Fond({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.fond,
        gradient: RadialGradient(
          center: const Alignment(-0.6, -1.15),
          radius: 1.25,
          colors: [p.accent.withValues(alpha: p.sombre ? 0.16 : 0.09), p.fond.withValues(alpha: 0)],
        ),
      ),
      child: child,
    );
  }
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
            TweenAnimationBuilder<double>(
              tween: Tween(end: valeur.clamp(0, 1)),
              duration: duree(context, 420),
              curve: kSortie,
              builder: (context, v, _) => FractionallySizedBox(
                widthFactor: v,
                child: DecoratedBox(
                  decoration: BoxDecoration(gradient: couleur == null ? p.liquide : null, color: couleur),
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
