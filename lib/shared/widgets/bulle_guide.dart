// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LES PETITES BULLES QUI EXPLIQUENT L'APPLICATION, une fois, à
// l'arrivée.
//
// ── ⚠️ POURQUOI DROPLET EN A PLUS BESOIN QU'UNE AUTRE APPLICATION ─────
//
// Une messagerie ordinaire n'a rien à expliquer : on ouvre, on écrit,
// ça part. Tout le monde a déjà vu WhatsApp.
//
// Droplet ressemble à WhatsApp et ne se comporte pas comme lui. « Zéro
// pair à proximité » n'est pas une panne. Un message qui met deux heures
// n'est pas une erreur. Une conversation avec quelqu'un qu'on n'a jamais
// vu apparaître dans la liste est normale. Sans un mot d'explication,
// chacun de ces comportements se lit comme un défaut — et une
// application qu'on croit cassée se désinstalle.
//
// ── ⚠️ LES TROIS RÈGLES QUI ÉVITENT QUE ÇA DEVIENNE INSUPPORTABLE ─────
//
// Les visites guidées ont mauvaise réputation, et c'est mérité. Trois
// contraintes, tenues sans exception :
//
//   1. UNE SEULE FOIS. Une étape vue ne revient jamais, même après une
//      mise à jour. Ce qui est enregistré est le nom de l'étape, pas un
//      compteur — ajouter une bulle plus tard n'en fait pas réapparaître
//      d'anciennes.
//   2. INTERROMPABLE À TOUT MOMENT. « Passer » saute la visite entière,
//      pas seulement l'étape courante. Quelqu'un qui a compris doit
//      pouvoir sortir en un geste, sans chercher.
//   3. QUATRE ÉTAPES AU MAXIMUM. Au-delà, plus personne ne lit — on
//      appuie sur « suivant » jusqu'à ce que ça s'arrête, et la visite
//      n'a servi qu'à retarder l'usage.
//
// ── Comment c'est dessiné ─────────────────────────────────────────────
//
// Un voile sombre percé d'un trou autour de l'élément désigné : c'est
// le trou, et non une flèche, qui dit de quoi on parle. La bulle se
// place au-dessus ou en dessous selon la place disponible, et sa pointe
// vise le centre du trou.
// ============================================================================

import 'package:flutter/material.dart';

import '../../core/services/storage_service.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_typography.dart';

/// Une étape de la visite : ce qu'on désigne, et ce qu'on en dit.
class EtapeGuide {
  const EtapeGuide({
    required this.cible,
    required this.titre,
    required this.texte,
  });

  /// L'élément désigné. Si sa clé n'est pas montée au moment venu,
  /// l'étape est SAUTÉE plutôt que d'afficher une bulle qui montre le
  /// vide.
  final GlobalKey cible;

  final String titre;
  final String texte;
}

class Guide {
  Guide._();

  /// Lance une visite, si elle n'a jamais été vue.
  ///
  /// [nom] identifie la visite dans le stockage. Renvoie sans rien faire
  /// si elle a déjà eu lieu.
  static Future<void> lancer(
    BuildContext context, {
    required String nom,
    required List<EtapeGuide> etapes,
  }) async {
    if (dejaVue(nom)) return;
    if (etapes.isEmpty || !context.mounted) return;

    // ⚠️ ON MARQUE AVANT D'AFFICHER, PAS APRÈS.
    //
    // Si l'application se ferme pendant la visite — ou si l'utilisateur
    // la quitte par un retour système — marquer à la fin ne se ferait
    // jamais, et la visite recommencerait à chaque lancement. Une aide
    // qui se rejoue en boucle est pire que pas d'aide du tout.
    // ⚠️ L'`Overlay` est saisi AVANT l'écriture, pas après.
    //
    // `marquerVue` est asynchrone : entre son début et sa fin, l'écran
    // a pu être quitté. Reprendre le `context` de l'autre côté d'une
    // attente est précisément ce que l'analyseur interdit, et à raison
    // — on poserait une visite guidée sur un écran qui n'existe plus.
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return;

    await marquerVue(nom);

    late OverlayEntry entree;
    entree = OverlayEntry(
      builder: (_) => _VisiteGuidee(
        etapes: etapes,
        onFini: () => entree.remove(),
      ),
    );
    overlay.insert(entree);
  }

  static String _cle(String nom) => 'guide_$nom';

  static bool dejaVue(String nom) =>
      StorageService.getString(_cle(nom)) == '1';

  static Future<void> marquerVue(String nom) =>
      StorageService.setString(_cle(nom), '1');

  /// Remet toutes les visites à zéro — utile depuis les réglages.
  static Future<void> toutRejouer(List<String> noms) async {
    for (final n in noms) {
      await StorageService.setString(_cle(n), '');
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  L'AFFICHAGE
// ─────────────────────────────────────────────────────────────

class _VisiteGuidee extends StatefulWidget {
  const _VisiteGuidee({required this.etapes, required this.onFini});

  final List<EtapeGuide> etapes;
  final VoidCallback onFini;

  @override
  State<_VisiteGuidee> createState() => _VisiteGuideeState();
}

class _VisiteGuideeState extends State<_VisiteGuidee>
    with SingleTickerProviderStateMixin {
  int _index = 0;
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    )..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Le rectangle de l'élément désigné, ou `null` s'il a disparu.
  Rect? _zone(EtapeGuide e) {
    final rendu = e.cible.currentContext?.findRenderObject();
    if (rendu is! RenderBox || !rendu.hasSize) return null;
    return rendu.localToGlobal(Offset.zero) & rendu.size;
  }

  void _suivant() {
    OuroHaptics.light();
    // On saute les étapes dont la cible a disparu entre-temps.
    var i = _index + 1;
    while (i < widget.etapes.length && _zone(widget.etapes[i]) == null) {
      i++;
    }
    if (i >= widget.etapes.length) {
      widget.onFini();
      return;
    }
    setState(() => _index = i);
    _c.forward(from: 0);
  }

  void _passer() {
    OuroHaptics.light();
    widget.onFini();
  }

  @override
  Widget build(BuildContext context) {
    final etape = widget.etapes[_index];
    final zone = _zone(etape);
    if (zone == null) {
      // La cible a disparu : on ne montre pas une bulle dans le vide.
      WidgetsBinding.instance.addPostFrameCallback((_) => _suivant());
      return const SizedBox.shrink();
    }

    final ecran = MediaQuery.sizeOf(context);
    final marges = MediaQuery.paddingOf(context);
    // Le trou déborde un peu de la cible : collé au pixel, il donne
    // l'impression d'un défaut d'alignement plutôt que d'une mise en
    // lumière.
    final trou = zone.inflate(8);
    // Sous la cible s'il y a la place, au-dessus sinon.
    final dessous = trou.bottom + 190 < ecran.height - marges.bottom;

    return Material(
      type: MaterialType.transparency,
      child: Stack(
        children: [
          // Le voile percé. Il intercepte tous les appuis : pendant la
          // visite, l'écran du dessous ne doit pas réagir — appuyer sur
          // un bouton qu'on vient d'expliquer emmènerait ailleurs, en
          // plein milieu de l'explication.
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _suivant,
              child: AnimatedBuilder(
                animation: _c,
                builder: (context, _) => CustomPaint(
                  painter: _VoilePainter(
                    trou: trou,
                    avance: Curves.easeOutCubic.transform(_c.value),
                  ),
                ),
              ),
            ),
          ),

          // La bulle.
          Positioned(
            left: DesignTokens.screenMargin,
            right: DesignTokens.screenMargin,
            top: dessous ? trou.bottom + 14 : null,
            bottom: dessous ? null : ecran.height - trou.top + 14,
            child: _Bulle(
              animation: _c,
              etape: etape,
              pointeVers: trou.center.dx,
              pointeEnHaut: dessous,
              rang: _index + 1,
              total: widget.etapes.length,
              dernier: _index == widget.etapes.length - 1,
              onSuivant: _suivant,
              onPasser: _passer,
            ),
          ),
        ],
      ),
    );
  }
}

/// Le voile sombre, percé autour de la cible.
class _VoilePainter extends CustomPainter {
  _VoilePainter({required this.trou, required this.avance});

  final Rect trou;
  final double avance;

  @override
  void paint(Canvas canvas, Size size) {
    final r = RRect.fromRectAndRadius(trou, const Radius.circular(14));
    final chemin = Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addRRect(r),
    );
    canvas.drawPath(
      chemin,
      Paint()..color = Colors.black.withValues(alpha: 0.68 * avance),
    );
    // Un liseré clair sur le bord du trou : sur un fond sombre, sans
    // lui, la découpe ne se voit pas.
    canvas.drawRRect(
      r,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = Colors.white.withValues(alpha: 0.34 * avance),
    );
  }

  @override
  bool shouldRepaint(covariant _VoilePainter old) =>
      old.trou != trou || old.avance != avance;
}

class _Bulle extends StatelessWidget {
  const _Bulle({
    required this.animation,
    required this.etape,
    required this.pointeVers,
    required this.pointeEnHaut,
    required this.rang,
    required this.total,
    required this.dernier,
    required this.onSuivant,
    required this.onPasser,
  });

  final Animation<double> animation;
  final EtapeGuide etape;
  final double pointeVers;
  final bool pointeEnHaut;
  final int rang;
  final int total;
  final bool dernier;
  final VoidCallback onSuivant;
  final VoidCallback onPasser;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, enfant) {
        final t = Curves.easeOutBack.transform(animation.value.clamp(0.0, 1.0));
        return Opacity(
          opacity: animation.value.clamp(0.0, 1.0),
          child: Transform.translate(
            // Elle vient DU CÔTÉ de la cible : le mouvement relie la
            // bulle à ce qu'elle désigne, mieux qu'une flèche.
            offset: Offset(0, (pointeEnHaut ? -16 : 16) * (1 - t)),
            child: Transform.scale(
              scale: 0.94 + 0.06 * t,
              alignment: pointeEnHaut ? Alignment.topCenter : Alignment.bottomCenter,
              child: enfant,
            ),
          ),
        );
      },
      child: Semantics(
        liveRegion: true,
        label: '${etape.titre}. ${etape.texte}. Étape $rang sur $total.',
        excludeSemantics: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (pointeEnHaut) _Pointe(vers: pointeVers, versLeHaut: true),
            Container(
              padding: const EdgeInsets.all(DesignTokens.space4),
              decoration: BoxDecoration(
                color: OuroColors.accent,
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    etape.titre,
                    style: OuroTypography.headline.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    etape.texte,
                    style: OuroTypography.subheadline.copyWith(
                      color: Colors.white.withValues(alpha: 0.92),
                      height: 1.42,
                    ),
                  ),
                  const SizedBox(height: DesignTokens.space4),
                  Row(
                    children: [
                      // Les points de progression : savoir combien il en
                      // reste est ce qui décide de continuer ou de
                      // passer. Sans eux, on suppose toujours le pire.
                      for (var i = 0; i < total; i++)
                        Container(
                          width: i == rang - 1 ? 16 : 6,
                          height: 6,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: Colors.white
                                .withValues(alpha: i == rang - 1 ? 1 : 0.42),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      const Spacer(),
                      if (!dernier)
                        TextButton(
                          onPressed: onPasser,
                          child: Text(
                            'Passer',
                            style: OuroTypography.subheadline.copyWith(
                              color: Colors.white.withValues(alpha: 0.78),
                            ),
                          ),
                        ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: onSuivant,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 18, vertical: 9),
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(DesignTokens.radiusMd),
                          ),
                        ),
                        child: Text(
                          dernier ? 'Compris' : 'Suivant',
                          style: OuroTypography.subheadline.copyWith(
                            color: OuroColors.accent,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (!pointeEnHaut) _Pointe(vers: pointeVers, versLeHaut: false),
          ],
        ),
      ),
    );
  }
}

/// La pointe de la bulle, alignée sur le centre de la cible.
class _Pointe extends StatelessWidget {
  const _Pointe({required this.vers, required this.versLeHaut});

  final double vers;
  final bool versLeHaut;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 9,
      child: CustomPaint(
        painter: _PointePainter(
          // La pointe est repositionnée dans le repère de la bulle, qui
          // commence à la marge de l'écran.
          x: vers - DesignTokens.screenMargin,
          versLeHaut: versLeHaut,
          couleur: OuroColors.accent,
        ),
      ),
    );
  }
}

class _PointePainter extends CustomPainter {
  _PointePainter({
    required this.x,
    required this.versLeHaut,
    required this.couleur,
  });

  final double x;
  final bool versLeHaut;
  final Color couleur;

  @override
  void paint(Canvas canvas, Size size) {
    // Bornée pour ne jamais sortir de la bulle : une pointe qui dépasse
    // du coin arrondi se lit comme un défaut d'affichage.
    final cx = x.clamp(20.0, size.width - 20);
    final p = Path();
    if (versLeHaut) {
      p.moveTo(cx, 0);
      p.lineTo(cx - 9, size.height);
      p.lineTo(cx + 9, size.height);
    } else {
      p.moveTo(cx, size.height);
      p.lineTo(cx - 9, 0);
      p.lineTo(cx + 9, 0);
    }
    p.close();
    canvas.drawPath(p, Paint()..color = couleur);
  }

  @override
  bool shouldRepaint(covariant _PointePainter old) =>
      old.x != x || old.versLeHaut != versLeHaut || old.couleur != couleur;
}
