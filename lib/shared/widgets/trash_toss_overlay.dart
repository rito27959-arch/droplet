// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LA SUPPRESSION D'UN MESSAGE, RENDUE VISIBLE. La bulle se soulève, part
// en cloche, rétrécit, et tombe dans une corbeille dont le couvercle
// s'ouvre pour la laisser entrer puis se referme.
//
// ── Pourquoi une animation pour une suppression ───────────────────────
//
// Ce n'est pas de la décoration. Supprimer est la seule action
// irréversible du menu contextuel, et jusqu'ici elle était la plus
// discrète de toutes : la bulle disparaissait entre deux images, sans que
// rien ne dise si c'était bien CELLE-LÀ qui était partie. L'animation
// répond à trois questions qu'on se pose toujours après un geste
// destructeur : qu'est-ce qui est parti (on suit l'objet des yeux), où
// c'est parti (dans la corbeille), et est-ce que c'est vraiment fait (le
// couvercle se referme).
//
// C'est aussi le principe qu'Apple applique partout où l'on supprime :
// l'objet ne s'évapore pas, il VA quelque part.
//
// ── Les règles de mouvement respectées ici ────────────────────────────
//
//   • Aucune courbe ne dépasse sa cible (voir `design_tokens.dart`). Le
//     seul rebond de toute la séquence est celui du couvercle, produit
//     par une VRAIE simulation de ressort — la façon dont iOS anime une
//     charnière — et non par une courbe `elasticOut`.
//   • L'objet accélère en tombant (`easeInCubic` sur le dernier tiers du
//     vol) : sans cela, la trajectoire paraît flotter au lieu de tomber.
//   • Deux retours haptiques seulement : léger au décollage, moyen au
//     claquement du couvercle. Un par événement physique visible.
//   • `MediaQuery.disableAnimations` est respecté : la suppression est
//     alors immédiate, sans rien afficher.
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_haptics.dart';

/// Envoie [apercu] dans une corbeille, depuis [origine].
class TrashTossOverlay extends StatefulWidget {
  const TrashTossOverlay({
    super.key,
    required this.origine,
    required this.apercu,
    required this.onAvalee,
    required this.onFini,
    this.cible,
  });

  /// Où poser la corbeille, en coordonnées écran.
  ///
  /// Par défaut, au-dessus de la zone sûre du bas. À préciser quand
  /// l'endroit par défaut est déjà occupé — la barre de saisie, par
  /// exemple, quand on jette un enregistrement en cours.
  final Offset? cible;

  /// La place exacte de la bulle à l'écran, au moment du geste.
  final Rect origine;

  /// Une COPIE de la bulle. On ne déplace jamais l'originale : elle vit
  /// dans la liste, qui la reconstruit à chaque image.
  final Widget apercu;

  /// Appelé à l'instant précis où la bulle disparaît dans la corbeille.
  ///
  /// ⚠️ C'EST LÀ QUE LA VRAIE SUPPRESSION DOIT SE FAIRE, pas avant. Si on
  /// supprime au moment du tap, la liste se réorganise sous l'animation :
  /// les messages du dessous remontent d'un cran pendant que la copie
  /// vole, et l'œil voit deux mouvements contradictoires.
  final VoidCallback onAvalee;

  /// Appelé quand tout est fini et que l'overlay peut être retiré.
  final VoidCallback onFini;

  /// Un seul envoi à la fois — deux corbeilles à l'écran n'auraient
  /// aucun sens.
  static OverlayEntry? _actif;

  /// Joue l'animation, ou supprime immédiatement si l'appareil demande
  /// à ce qu'on n'anime pas.
  ///
  /// [origine] et [apercu] viennent du même endroit que pour le menu
  /// contextuel : la clé de la bulle réelle et sa copie.
  static void jouer(
    BuildContext context, {
    required Rect origine,
    required Widget apercu,
    required VoidCallback onAvalee,
    Offset? cible,
  }) {
    // Réglage d'accessibilité « Réduire les animations ». Quelqu'un qui
    // l'active a souvent une raison médicale de le faire : on ne lui
    // impose pas une trajectoire, on supprime, point.
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      onAvalee();
      return;
    }

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      // Pas d'overlay accessible : la suppression doit quand même avoir
      // lieu. Une animation qui échoue ne doit jamais emporter l'action
      // qu'elle illustre.
      onAvalee();
      return;
    }

    _actif?.remove();
    _actif = null;

    late OverlayEntry entree;
    entree = OverlayEntry(
      builder: (_) => TrashTossOverlay(
        origine: origine,
        apercu: apercu,
        cible: cible,
        onAvalee: onAvalee,
        onFini: () {
          if (identical(_actif, entree)) _actif = null;
          entree.remove();
        },
      ),
    );
    _actif = entree;
    overlay.insert(entree);
  }

  @override
  State<TrashTossOverlay> createState() => _TrashTossOverlayState();
}

class _TrashTossOverlayState extends State<TrashTossOverlay>
    with TickerProviderStateMixin {
  /// L'horloge principale : décollage, vol, sortie.
  late final AnimationController _vol;

  /// Le couvercle a son propre contrôleur, parce qu'il ne suit pas une
  /// courbe mais un RESSORT : il s'ouvre en douceur et se referme en
  /// claquant, avec l'oscillation d'une vraie charnière.
  late final AnimationController _couvercle;

  bool _avalee = false;
  bool _ouvertureLancee = false;

  // ── Découpage temporel ────────────────────────────────────────────────
  // Une seule constante par étape, pour qu'on puisse régler le rythme
  // sans chercher des nombres au milieu du code.

  static const Duration _duree = Duration(milliseconds: 900);

  /// Fin du décollage : la bulle se soulève avant de partir.
  static const double _tDecollage = 0.12;

  /// Fin du vol : la bulle est entrée dans la corbeille.
  ///
  /// ⚠️ Il reste volontairement 28 % de la séquence APRÈS ce point. C'est
  /// le temps qu'il faut pour voir le couvercle claquer. Faire arriver la
  /// bulle à 90 % économiserait deux dixièmes de seconde et supprimerait
  /// la seule image qui dit « c'est fait ».
  static const double _tArrivee = 0.72;

  /// La corbeille est en place.
  static const double _tCorbeillePosee = 0.18;

  /// La corbeille commence à s'effacer.
  static const double _tCorbeilleSort = 0.90;

  @override
  void initState() {
    super.initState();
    _couvercle = AnimationController.unbounded(vsync: this, value: 0);
    _vol = AnimationController(vsync: this, duration: _duree)
      ..addListener(_surImage)
      ..addStatusListener((statut) {
        if (statut == AnimationStatus.completed) widget.onFini();
      });

    OuroHaptics.light();
    _vol.forward();
  }

  void _surImage() {
    final t = _vol.value;

    // Le couvercle s'ouvre quand la bulle est à mi-parcours : trop tôt,
    // la corbeille attend bouche ouverte et l'effet tombe à plat ; trop
    // tard, la bulle traverse un couvercle fermé.
    if (!_ouvertureLancee && t >= 0.42) {
      _ouvertureLancee = true;
      _couvercle.animateTo(
        1,
        duration: const Duration(milliseconds: 220),
        curve: DesignTokens.curveEnter,
      );
    }

    // L'instant du claquement : la bulle vient de disparaître dedans.
    if (!_avalee && t >= _tArrivee) {
      _avalee = true;
      widget.onAvalee();
      OuroHaptics.medium();
      // ⚠️ RESSORT, PAS COURBE. Un couvercle qui se referme dépasse
      // légèrement puis revient : c'est une charnière, pas une
      // interpolation. `springSnappy` est précisément le réglage
      // d'Apple pour ce genre de mouvement — et c'est le seul
      // dépassement autorisé par `design_tokens.dart`, parce qu'il est
      // la conséquence physique d'un choc, pas un ornement.
      _couvercle.animateWith(
        SpringSimulation(DesignTokens.springSnappy, _couvercle.value, 0, 4.5),
      );
    }
  }

  @override
  void dispose() {
    _vol.dispose();
    _couvercle.dispose();
    super.dispose();
  }

  /// La trajectoire : une courbe de Bézier quadratique dont le point de
  /// contrôle est placé AU-DESSUS des deux extrémités.
  ///
  /// C'est ce qui produit le « s'envole puis retombe » : une ligne droite
  /// entre la bulle et la corbeille donnerait un glissement, pas un
  /// lancer. La hauteur de la cloche est proportionnelle à la distance,
  /// pour qu'un message proche de la corbeille ne fasse pas un looping.
  Offset _positionSur(Offset depart, Offset arrivee, double p) {
    final distance = (arrivee - depart).distance;
    final hauteur = math.min(160.0, 60 + distance * 0.28);
    final controle = Offset(
      (depart.dx + arrivee.dx) / 2,
      math.min(depart.dy, arrivee.dy) - hauteur,
    );
    final u = 1 - p;
    return depart * (u * u) + controle * (2 * u * p) + arrivee * (p * p);
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ `AnimatedBuilder` SUR LES DEUX CONTRÔLEURS.
    //
    // Le couvercle a sa propre horloge (un ressort), qui continue de
    // tourner après la fin du vol. N'écouter que le vol figerait la
    // charnière au milieu de son claquement — et l'écouter par
    // `setState` reconstruirait tout l'arbre soixante fois par seconde
    // pour ne bouger que deux nombres.
    return AnimatedBuilder(
      animation: Listenable.merge([_vol, _couvercle]),
      builder: (context, _) => _construire(context),
    );
  }

  Widget _construire(BuildContext context) {
    final ecran = MediaQuery.sizeOf(context);
    final basSur = MediaQuery.paddingOf(context).bottom;
    final t = _vol.value;

    // La corbeille se pose au-dessus de la zone sûre, centrée.
    const tailleCorbeille = 72.0;
    final centreCorbeille = widget.cible ??
        Offset(
          ecran.width / 2,
          ecran.height - basSur - 96,
        );
    // La bouche est au niveau du couvercle, pas au centre du dessin.
    final bouche = centreCorbeille.translate(0, -tailleCorbeille * 0.34);

    // ── Le vol ────────────────────────────────────────────────────────
    final pVol = ((t - _tDecollage) / (_tArrivee - _tDecollage)).clamp(0.0, 1.0);
    // Deux courbes enchaînées : on part vite (le lancer), on ralentit au
    // sommet, puis la chute accélère. Une seule courbe ne peut pas rendre
    // ces deux régimes.
    final pTrajet = pVol < 0.55
        ? DesignTokens.curveEnter.transform(pVol / 0.55) * 0.55
        : 0.55 + Curves.easeInCubic.transform((pVol - 0.55) / 0.45) * 0.45;

    final depart = widget.origine.center;
    final position = _positionSur(depart, bouche, pTrajet);

    // ── Décollage : la bulle se soulève d'un cheveu ───────────────────
    // Huit points, pas davantage. C'est le geste de « prendre » l'objet
    // avant de le lancer : sans lui, la bulle part sans qu'on ait vu
    // qu'elle avait été saisie.
    final pDecollage = (t / _tDecollage).clamp(0.0, 1.0);
    final souleve = DesignTokens.curveEnter.transform(pDecollage);
    final leve = -8.0 * souleve * (1 - pVol);

    // ── Échelle : 1 → 1,045 au décollage, puis fonte jusqu'à 0,10 ─────
    final echelle = t < _tDecollage
        ? 1 + 0.045 * souleve
        : 1.045 - 0.945 * DesignTokens.curveEnter.transform(pVol);

    // ── Rotation : l'objet bascule dans le sens du lancer ─────────────
    final sens = bouche.dx >= depart.dx ? 1.0 : -1.0;
    final rotation = 0.26 * sens * pVol * pVol;

    // La bulle s'efface sur les tout derniers pour cent : elle est
    // désormais DANS la corbeille, on ne doit plus la voir dépasser.
    final opaciteBulle = pVol < 0.90 ? 1.0 : (1 - (pVol - 0.90) / 0.10).clamp(0.0, 1.0);

    // ── La corbeille : entre par le bas, sort en fondu ────────────────
    final pEntree = (t / _tCorbeillePosee).clamp(0.0, 1.0);
    final entree = DesignTokens.curveEnter.transform(pEntree);
    final pSortie = ((t - _tCorbeilleSort) / (1 - _tCorbeilleSort)).clamp(0.0, 1.0);
    final opaciteCorbeille = entree * (1 - DesignTokens.curveExit.transform(pSortie));

    return IgnorePointer(
      child: Stack(
        children: [
          // ── La corbeille ──────────────────────────────────────────
          Positioned(
            left: centreCorbeille.dx - tailleCorbeille / 2,
            top: centreCorbeille.dy - tailleCorbeille / 2 + (1 - entree) * 18,
            width: tailleCorbeille,
            height: tailleCorbeille,
            child: Opacity(
              opacity: opaciteCorbeille,
              child: CustomPaint(
                painter: _CorbeillePainter(
                  ouverture: _couvercle.value.clamp(-0.2, 1.2),
                  corps: OuroColors.systemGray,
                  accent: OuroColors.systemRed,
                ),
              ),
            ),
          ),

          // ── La bulle en vol ───────────────────────────────────────
          Positioned(
            left: position.dx - widget.origine.width / 2,
            top: position.dy - widget.origine.height / 2 + leve,
            width: widget.origine.width,
            height: widget.origine.height,
            child: Opacity(
              opacity: opaciteBulle,
              child: Transform.rotate(
                angle: rotation,
                child: Transform.scale(
                  scale: echelle,
                  // ⚠️ `OverflowBox` et non `SizedBox` seul : la copie de
                  // la bulle peut demander un peu plus de hauteur que le
                  // rectangle mesuré (une réaction, un accusé de
                  // lecture). Sans lui, Flutter peint la bande jaune de
                  // débordement en plein milieu de l'animation.
                  child: OverflowBox(
                    maxWidth: widget.origine.width,
                    maxHeight: double.infinity,
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: widget.origine.width,
                      child: widget.apercu,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Le dessin de la corbeille ────────────────────────────────────────────────

/// La corbeille, dessinée plutôt qu'importée.
///
/// ── Pourquoi pas une icône du système ─────────────────────────────────
///
/// Parce que le couvercle doit s'ouvrir. Une icône est une image d'un
/// seul tenant : pour articuler une charnière, il faut que le couvercle
/// soit un objet séparé, avec son propre pivot. C'est aussi ce qui permet
/// de rester net à n'importe quelle taille d'écran, sans embarquer
/// d'image.
class _CorbeillePainter extends CustomPainter {
  _CorbeillePainter({
    required this.ouverture,
    required this.corps,
    required this.accent,
  });

  /// 0 = fermé, 1 = grand ouvert. Peut dépasser légèrement pendant le
  /// rebond du ressort — d'où le `clamp` à l'appel.
  final double ouverture;
  final Color corps;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final l = size.width;
    final h = size.height;

    // ── Le seau : un trapèze aux angles adoucis ──────────────────────
    final hautSeau = h * 0.30;
    final largeurHaut = l * 0.62;
    final largeurBas = l * 0.48;
    final seau = Path()
      ..moveTo((l - largeurHaut) / 2, hautSeau)
      ..lineTo((l + largeurHaut) / 2, hautSeau)
      ..lineTo((l + largeurBas) / 2, h * 0.92)
      ..quadraticBezierTo(
          (l + largeurBas) / 2 - 2, h * 0.97, (l + largeurBas) / 2 - 8, h * 0.97)
      ..lineTo((l - largeurBas) / 2 + 8, h * 0.97)
      ..quadraticBezierTo(
          (l - largeurBas) / 2 + 2, h * 0.97, (l - largeurBas) / 2, h * 0.92)
      ..close();

    canvas.drawPath(seau, Paint()..color = corps.withValues(alpha: 0.92));

    // Les trois rainures verticales — c'est le détail qui fait lire
    // « corbeille » plutôt que « seau ».
    final rainure = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    for (var i = -1; i <= 1; i++) {
      final x = l / 2 + i * (largeurBas * 0.28);
      canvas.drawLine(
        Offset(x, hautSeau + h * 0.10),
        Offset(x, h * 0.82),
        rainure,
      );
    }

    // ── Le couvercle, pivoté autour de sa charnière arrière-gauche ───
    canvas.save();
    final pivot = Offset((l - largeurHaut) / 2 - 2, hautSeau - h * 0.045);
    canvas.translate(pivot.dx, pivot.dy);
    // Le signe négatif ouvre vers l'arrière-gauche, comme une poubelle à
    // pédale qu'on regarde de face.
    canvas.rotate(-ouverture * 0.85);
    canvas.translate(-pivot.dx, -pivot.dy);

    final couvercle = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        (l - largeurHaut * 1.12) / 2,
        hautSeau - h * 0.09,
        largeurHaut * 1.12,
        h * 0.09,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(couvercle, Paint()..color = accent);

    // La poignée : un petit pont au-dessus du couvercle.
    final poignee = Path()
      ..moveTo(l / 2 - largeurHaut * 0.16, hautSeau - h * 0.09)
      ..lineTo(l / 2 - largeurHaut * 0.12, hautSeau - h * 0.155)
      ..lineTo(l / 2 + largeurHaut * 0.12, hautSeau - h * 0.155)
      ..lineTo(l / 2 + largeurHaut * 0.16, hautSeau - h * 0.09);
    canvas.drawPath(
      poignee,
      Paint()
        ..color = accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _CorbeillePainter old) =>
      old.ouverture != ouverture || old.corps != corps || old.accent != accent;
}
