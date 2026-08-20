// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LES TROIS GRANDES ANIMATIONS DES ÉCRANS DE BIENVENUE.
//
// Elles vivent à part de `onboarding_screen.dart` pour une raison
// simple : elles sont d'un tout autre ordre de grandeur que les deux
// petits croquis qui y sont restés (le relais, la carte). Les garder
// dans le même fichier l'aurait poussé au-delà de mille huit cents
// lignes, dont l'essentiel n'aurait plus rien eu à voir avec le
// déroulé des pages.
//
// ── ⚠️ CE QUI DISTINGUE UNE ANIMATION UTILE D'UNE DÉCORATION ─────────
//
// Les trois animations d'ici racontent chacune UNE chose que le texte à
// côté ne peut pas montrer :
//
//   • [StatusRingsDiagram] — qu'un statut se REGARDE puis s'éteint. Le
//     cercle coloré qui devient gris est la seule manière de faire
//     comprendre en une seconde ce que « déjà vu » veut dire.
//
//   • [AvatarRing] — que le rond vide ATTEND quelque chose. Un anneau
//     qui tourne lentement se lit comme une invitation ; un rond gris
//     immobile se lit comme une case à cocher.
//
//   • [NetworkGrowthDiagram] — l'effet de réseau lui-même, qui est
//     rigoureusement impossible à faire passer par une phrase. Voir sa
//     note : c'est la plus importante des trois, et de loin.
//
// Aucune ne comporte de flou ni de calque hors-écran : elles tournent
// sur des téléphones de 2 Go, et jusqu'à trois à la fois puisqu'un
// `PageView` construit les pages voisines.
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';

// ═══════════════════════════════════════════════════════════════════
//  1. LES ANNEAUX DE STATUT
// ═══════════════════════════════════════════════════════════════════

/// Trois statuts qui se publient, se regardent, puis s'éteignent.
///
/// L'anneau segmenté est la convention universelle du « statut non
/// vu » — on la retrouve à l'identique dans WhatsApp, Instagram et
/// Telegram. Chaque segment est une publication ; les intervalles disent
/// combien il y en a avant même d'avoir ouvert quoi que ce soit.
///
/// L'animation suit le cycle complet, dans l'ordre : l'anneau se TRACE
/// (le statut arrive), puis il PÂLIT (on l'a regardé). Ce deuxième temps
/// est celui que personne n'anime jamais, et c'est pourtant celui qui
/// explique à quoi sert la couleur.
class StatusRingsDiagram extends StatefulWidget {
  const StatusRingsDiagram({super.key});

  @override
  State<StatusRingsDiagram> createState() => _StatusRingsDiagramState();
}

class _StatusRingsDiagramState extends State<StatusRingsDiagram>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 140,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _StatusRingsPainter(
            t: _c.value,
            accent: OuroColors.accent,
            vert: OuroColors.systemGreen,
            violet: OuroColors.systemPurple,
            eteint: OuroColors.quaternaryLabel,
            surface: OuroColors.secondarySystemBackground,
          ),
        ),
      ),
    );
  }
}

class _StatusRingsPainter extends CustomPainter {
  _StatusRingsPainter({
    required this.t,
    required this.accent,
    required this.vert,
    required this.violet,
    required this.eteint,
    required this.surface,
  });

  final double t;
  final Color accent;
  final Color vert;
  final Color violet;
  final Color eteint;
  final Color surface;

  /// Combien de publications compte chaque personne — donc combien de
  /// segments compte son anneau.
  static const List<int> _segments = [3, 1, 2];

  /// Le moment où chaque anneau commence à se tracer.
  static const List<double> _debuts = [0.04, 0.20, 0.36];

  /// Le moment où chaque anneau s'éteint (« vu »).
  static const List<double> _vus = [0.62, 0.72, 0.82];

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final rayons = [30.0, 38.0, 30.0];
    final couleurs = [violet, accent, vert];
    final xs = [
      size.width * 0.22,
      size.width * 0.50,
      size.width * 0.78,
    ];

    for (var i = 0; i < 3; i++) {
      final r = rayons[i];
      final centre = Offset(xs[i], y);

      // ── Le disque : une personne, suggérée et non dessinée ──
      //
      // Une silhouette réaliste ferait porter l'attention sur QUI, alors
      // que la page parle de QUOI. Un aplat et une initiale abstraite
      // suffisent à dire « quelqu'un ».
      canvas.drawCircle(centre, r - 6, Paint()..color = surface);
      canvas.drawCircle(
        centre,
        r - 6,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = eteint.withValues(alpha: 0.5),
      );

      // ── L'anneau segmenté ──
      final trace = _avancement(_debuts[i], 0.13);
      if (trace <= 0) continue;

      // Après son heure, l'anneau passe au gris : c'est « déjà vu ».
      final extinction = _avancement(_vus[i], 0.10);
      final couleur = Color.lerp(couleurs[i], eteint, extinction)!;
      final epaisseur = 3.4 - 1.6 * extinction;

      final n = _segments[i];
      // L'intervalle entre segments : plus il y a de publications, plus
      // il faut le resserrer, sinon les traits deviennent des points.
      final ecart = n == 1 ? 0.0 : (n > 2 ? 0.10 : 0.14);
      final part = (2 * math.pi - ecart * n) / n;

      final pinceau = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = epaisseur
        ..strokeCap = StrokeCap.round
        ..color = couleur;

      for (var s = 0; s < n; s++) {
        // On part du haut, dans le sens des aiguilles : le sens de
        // lecture d'un compteur.
        final depart = -math.pi / 2 + s * (part + ecart);
        canvas.drawArc(
          Rect.fromCircle(center: centre, radius: r),
          depart,
          part * trace,
          false,
          pinceau,
        );
      }

      // ── L'éclat au moment où l'anneau se referme ──
      //
      // Un halo bref, qui n'existe QUE pendant la demi-seconde qui suit
      // la fermeture de l'anneau. C'est ce qui fait qu'un statut
      // « arrive » au lieu d'apparaître.
      if (trace >= 1 && extinction == 0) {
        final depuis = _depuis(_debuts[i] + 0.13, 0.14);
        if (depuis > 0 && depuis < 1) {
          canvas.drawCircle(
            centre,
            r + 5 * depuis,
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2 * (1 - depuis)
              ..color = couleurs[i].withValues(alpha: (1 - depuis) * 0.6),
          );
        }
      }
    }
  }

  /// Où en est une étape qui commence à [debut] et dure [duree].
  double _avancement(double debut, double duree) {
    if (t < debut) return 0;
    return Curves.easeOutCubic.transform(((t - debut) / duree).clamp(0.0, 1.0));
  }

  /// Combien de temps s'est écoulé depuis [instant], rapporté à [duree].
  double _depuis(double instant, double duree) => (t - instant) / duree;

  @override
  bool shouldRepaint(covariant _StatusRingsPainter old) => old.t != t;
}

// ═══════════════════════════════════════════════════════════════════
//  2. L'ANNEAU DE LA PHOTO DE PROFIL
// ═══════════════════════════════════════════════════════════════════

/// Le grand rond de la page « photo », avec son anneau vivant.
///
/// ⚠️ L'ANNEAU CHANGE DE NATURE SELON L'ÉTAT, et c'est tout l'intérêt.
///
///   • VIDE, il tourne lentement, en pointillés, dans la couleur
///     d'accent. Un anneau qui tourne se lit comme une attente — donc
///     comme une invitation à toucher. Un rond gris immobile se lit
///     comme un champ désactivé, et personne n'appuie dessus.
///
///   • REMPLI, il s'arrête net et devient un liseré plein. Le mouvement
///     cesse parce que l'attente a cessé : c'est la récompense du geste,
///     et elle est plus claire qu'une coche.
///
/// Le passage de l'un à l'autre est un ressort, pas un fondu : on vient
/// de POSER quelque chose, et une chose posée rebondit.
class AvatarRing extends StatefulWidget {
  const AvatarRing({
    super.key,
    required this.rempli,
    required this.rayon,
    required this.child,
    this.onTap,
  });

  /// Vrai dès qu'une photo a été choisie.
  final bool rempli;
  final double rayon;
  final Widget child;
  final VoidCallback? onTap;

  @override
  State<AvatarRing> createState() => _AvatarRingState();
}

class _AvatarRingState extends State<AvatarRing>
    with TickerProviderStateMixin {
  /// La rotation continue de l'anneau vide.
  late final AnimationController _rotation;

  /// Le ressort qui accueille la photo.
  late final AnimationController _pose;

  @override
  void initState() {
    super.initState();
    _rotation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 6000),
    );
    _pose = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
      value: widget.rempli ? 1 : 0,
    );
    if (!widget.rempli) _rotation.repeat();
  }

  @override
  void didUpdateWidget(AvatarRing old) {
    super.didUpdateWidget(old);
    if (widget.rempli == old.rempli) return;
    if (widget.rempli) {
      // ⚠️ On ARRÊTE la rotation. Laisser tourner un anneau sous une
      // photo posée donnerait un objet qui continue de charger alors
      // que tout est fini — le contraire de ce qu'on veut dire.
      _rotation.stop();
      _pose.forward(from: 0);
    } else {
      _pose.reverse();
      _rotation.repeat();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    _pose.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cote = widget.rayon * 2 + 26;

    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: cote,
        height: cote,
        child: AnimatedBuilder(
          animation: Listenable.merge([_rotation, _pose]),
          builder: (context, enfant) {
            final pose = Curves.elasticOut.transform(
              _pose.value.clamp(0.0, 1.0),
            );
            return CustomPaint(
              painter: _AvatarRingPainter(
                rotation: _rotation.value,
                pose: _pose.value,
                accent: OuroColors.accent,
                creux: OuroColors.tertiarySystemFill,
              ),
              child: Center(
                child: Transform.scale(
                  // Le contenu ne dépasse jamais : le ressort porte
                  // seulement les six derniers pour cent de l'échelle.
                  scale: widget.rempli ? 0.94 + 0.06 * pose : 1.0,
                  child: ClipOval(
                    child: SizedBox(
                      width: widget.rayon * 2,
                      height: widget.rayon * 2,
                      child: enfant,
                    ),
                  ),
                ),
              ),
            );
          },
          child: widget.child,
        ),
      ),
    );
  }
}

class _AvatarRingPainter extends CustomPainter {
  _AvatarRingPainter({
    required this.rotation,
    required this.pose,
    required this.accent,
    required this.creux,
  });

  final double rotation;
  final double pose;
  final Color accent;
  final Color creux;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final rayon = size.width / 2 - 5;

    // ── L'anneau plein, qui n'apparaît qu'une fois la photo posée ──
    if (pose > 0) {
      canvas.drawCircle(
        centre,
        rayon,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..color = accent.withValues(alpha: pose),
      );
    }

    // ── L'anneau en pointillés, qui tourne tant qu'on attend ──
    if (pose >= 1) return;

    const nombre = 26;
    final pinceau = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..color = accent.withValues(alpha: (1 - pose) * 0.55);

    final part = 2 * math.pi / nombre;
    for (var i = 0; i < nombre; i++) {
      final depart = rotation * 2 * math.pi + i * part;
      canvas.drawArc(
        Rect.fromCircle(center: centre, radius: rayon),
        depart,
        // Un tiret court, deux tiers de vide : assez pour lire un
        // pointillé, pas assez pour lire un cercle.
        part * 0.34,
        false,
        pinceau,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AvatarRingPainter old) =>
      old.rotation != rotation || old.pose != pose;
}

// ═══════════════════════════════════════════════════════════════════
//  3. LA CROISSANCE DU RÉSEAU
// ═══════════════════════════════════════════════════════════════════

/// Le réseau qui grandit, et le moment où deux groupes se rejoignent.
///
/// ⚠️ C'EST L'ANIMATION LA PLUS IMPORTANTE DE L'APPLICATION, et elle
/// mérite qu'on explique pourquoi.
///
/// Droplet a un défaut qu'aucune autre messagerie n'a : **seul, il ne
/// sert à rien**. On l'installe, on ouvre, et il n'y a personne. Ce
/// n'est pas une panne, c'est la nature même d'un réseau maillé — et
/// c'est la raison numéro un pour laquelle quelqu'un désinstalle
/// l'application dans les deux minutes.
///
/// Aucune phrase ne répare ça. « Plus il y a d'utilisateurs, mieux ça
/// marche » est vrai, et parfaitement inopérant : c'est une abstraction,
/// et on la lit sans la ressentir.
///
/// Cette animation la MONTRE, en trois temps :
///
///   1. un point, seul, qui n'atteint personne ;
///   2. quelques voisins : un petit groupe se forme, le compteur monte
///      à quatre — puis un second groupe apparaît à droite, en gris,
///      HORS D'ATTEINTE. Le compteur ne bouge pas. C'est le moment
///      important : on voit des gens qu'on ne peut pas joindre ;
///   3. **une seule personne** apparaît entre les deux — et le compteur
///      saute de quatre à dix d'un coup.
///
/// Ce saut est l'effet de réseau. Il ne se raconte pas, il se regarde.
/// Et il rend la demande de la page — « invitez trois personnes » —
/// évidente au lieu d'insistante.
///
/// Le graphe est ÉCRIT À LA MAIN, pas tiré au sort : les positions et
/// les liaisons sont fixes. Un tirage aléatoire redonnerait un résultat
/// différent à chaque ouverture, et une fois sur trois le pont ne
/// changerait pas grand-chose — l'animation raterait alors précisément
/// ce qu'elle vient dire.
class NetworkGrowthDiagram extends StatefulWidget {
  const NetworkGrowthDiagram({super.key});

  @override
  State<NetworkGrowthDiagram> createState() => _NetworkGrowthDiagramState();
}

class _NetworkGrowthDiagramState extends State<NetworkGrowthDiagram>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 8200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 190,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final t = _c.value;
          final atteints = MeshGrowthModel.atteignables(t);
          return Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: _NetworkPainter(
                    t: t,
                    accent: OuroColors.accent,
                    eteint: OuroColors.quaternaryLabel,
                    fond: OuroColors.systemBackground,
                  ),
                ),
              ),
              // Le compteur, en Flutter et non peint sur la toile : un
              // texte peint à la main ignorerait la taille de police
              // choisie dans les réglages d'accessibilité.
              Positioned(
                left: 0,
                top: 0,
                child: _Compteur(nombre: atteints),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Le petit compteur « N personnes joignables ».
class _Compteur extends StatelessWidget {
  const _Compteur({required this.nombre});

  final int nombre;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Le chiffre change par un GLISSEMENT vertical, comme un
        // compteur mécanique. Un simple remplacement de texte passerait
        // inaperçu — or c'est le chiffre qui porte toute la
        // démonstration.
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 260),
          transitionBuilder: (enfant, anim) => ClipRect(
            child: SlideTransition(
              position: Tween(
                begin: const Offset(0, 0.6),
                end: Offset.zero,
              ).animate(anim),
              child: FadeTransition(opacity: anim, child: enfant),
            ),
          ),
          child: Text(
            '$nombre',
            key: ValueKey(nombre),
            style: OuroTypography.title1.copyWith(
              color: OuroColors.accent,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
        const SizedBox(width: 6),
        Padding(
          padding: const EdgeInsets.only(bottom: 3),
          child: Text(
            nombre > 1 ? 'personnes joignables' : 'personne joignable',
            style: OuroTypography.subheadline
                .copyWith(color: OuroColors.secondaryLabel),
          ),
        ),
      ],
    );
  }
}

/// Le graphe et son déroulé dans le temps.
///
/// Séparé du peintre parce que le compteur en a besoin aussi : c'est le
/// MÊME calcul d'atteignabilité qui colore les points et qui donne le
/// chiffre. Deux calculs séparés finiraient par se contredire, et un
/// chiffre qui ne correspond pas au dessin ruinerait la démonstration.
class MeshGrowthModel {
  MeshGrowthModel._();

  /// Les positions, en coordonnées normalisées (0 → 1).
  static const List<Offset> noeuds = [
    Offset(0.13, 0.58), // 0 — moi
    Offset(0.27, 0.33), // 1
    Offset(0.28, 0.80), // 2
    Offset(0.41, 0.57), // 3
    Offset(0.67, 0.27), // 4
    Offset(0.79, 0.51), // 5
    Offset(0.68, 0.78), // 6
    Offset(0.90, 0.74), // 7
    Offset(0.88, 0.30), // 8
    Offset(0.54, 0.44), // 9 — LE PONT
  ];

  /// Qui est à portée de qui.
  static const List<List<int>> liens = [
    [0, 1], [0, 2], [1, 3], [2, 3], // le groupe de gauche
    [4, 5], [4, 8], [5, 8], [5, 6], [6, 7], [5, 7], // celui de droite
    [3, 9], [9, 4], [9, 5], // le pont, qui n'arrive qu'à la fin
  ];

  /// Quand chaque point apparaît, en fraction du cycle.
  ///
  /// Le groupe de droite arrive AVANT le pont, et c'est délibéré : il
  /// faut voir des gens hors d'atteinte pour comprendre ce que le pont
  /// change.
  static const List<double> apparitions = [
    0.02, 0.09, 0.15, 0.21, // gauche
    0.33, 0.39, 0.45, 0.51, 0.57, // droite, encore inaccessible
    0.70, // le pont
  ];

  /// Combien de temps dure l'apparition d'un point.
  static const double dureeApparition = 0.05;

  /// La fin du cycle, où tout s'efface avant de recommencer.
  static const double debutSortie = 0.93;

  /// Un point est-il là, et à quel point ?
  static double presence(double t, int i) {
    if (t < apparitions[i]) return 0;
    final apparu = ((t - apparitions[i]) / dureeApparition).clamp(0.0, 1.0);
    if (t < debutSortie) return Curves.easeOutBack.transform(apparu);
    // La sortie : tout s'efface ensemble, sinon le redémarrage donne
    // l'impression d'un bug plutôt que d'une boucle.
    final sortie = ((t - debutSortie) / (1 - debutSortie)).clamp(0.0, 1.0);
    return 1 - sortie;
  }

  /// L'ensemble des points joignables depuis le point 0.
  ///
  /// Un parcours en largeur, refait à chaque image. Dix points et
  /// quatorze liaisons : le coût est négligeable, et c'est la seule
  /// façon d'être certain que le chiffre affiché correspond exactement
  /// à ce qui est dessiné.
  static Set<int> ensembleAtteignable(double t) {
    final presents = <int>{
      for (var i = 0; i < noeuds.length; i++)
        if (t >= apparitions[i]) i,
    };
    if (!presents.contains(0)) return const {};

    final atteints = <int>{0};
    final aVisiter = <int>[0];
    while (aVisiter.isNotEmpty) {
      final n = aVisiter.removeLast();
      for (final lien in liens) {
        final autre = lien[0] == n ? lien[1] : (lien[1] == n ? lien[0] : -1);
        if (autre < 0) continue;
        if (!presents.contains(autre) || atteints.contains(autre)) continue;
        atteints.add(autre);
        aVisiter.add(autre);
      }
    }
    return atteints;
  }

  static int atteignables(double t) => ensembleAtteignable(t).length;
}

class _NetworkPainter extends CustomPainter {
  _NetworkPainter({
    required this.t,
    required this.accent,
    required this.eteint,
    required this.fond,
  });

  final double t;
  final Color accent;
  final Color eteint;
  final Color fond;

  @override
  void paint(Canvas canvas, Size size) {
    // Le dessin occupe le bas de la zone : le compteur tient le haut.
    final zone = Rect.fromLTWH(0, 44, size.width, size.height - 44);
    Offset place(int i) => Offset(
          zone.left + MeshGrowthModel.noeuds[i].dx * zone.width,
          zone.top + MeshGrowthModel.noeuds[i].dy * zone.height,
        );

    final atteints = MeshGrowthModel.ensembleAtteignable(t);

    // ── LES LIAISONS ──
    //
    // Dessinées AVANT les points, pour qu'elles passent dessous. Une
    // liaison qui traverse un point donnerait un croquis de câblage, pas
    // un réseau.
    for (final lien in MeshGrowthModel.liens) {
      final a = MeshGrowthModel.presence(t, lien[0]);
      final b = MeshGrowthModel.presence(t, lien[1]);
      if (a <= 0 || b <= 0) continue;

      // La liaison se TRACE depuis le point le plus ancien vers le plus
      // récent : c'est le nouvel arrivant qui se raccorde, pas la
      // liaison qui tombe du ciel.
      final vieux = MeshGrowthModel.apparitions[lien[0]] <=
              MeshGrowthModel.apparitions[lien[1]]
          ? lien[0]
          : lien[1];
      final neuf = vieux == lien[0] ? lien[1] : lien[0];
      // ⚠️ BORNÉ À 1. `presence` s'appuie sur `easeOutBack`, qui dépasse
      // sa cible avant d'y revenir — c'est ce qui donne le petit rebond
      // des points. Reporté tel quel sur une interpolation de position,
      // ce dépassement ferait sortir le trait au-delà du point qu'il
      // relie, et on verrait des liaisons qui débordent.
      final avance = math.min(a, b).clamp(0.0, 1.0);

      final actif = atteints.contains(lien[0]) && atteints.contains(lien[1]);
      final couleur = actif
          ? accent.withValues(alpha: 0.42 * avance)
          : eteint.withValues(alpha: 0.34 * avance);

      canvas.drawLine(
        place(vieux),
        Offset.lerp(place(vieux), place(neuf), avance)!,
        Paint()
          ..color = couleur
          ..strokeWidth = actif ? 1.8 : 1.2
          ..strokeCap = StrokeCap.round,
      );
    }

    // ── L'ONDE QUI PARCOURT LE RÉSEAU UNE FOIS LE PONT POSÉ ──
    //
    // Elle ne se déclenche qu'après la jonction, et une seule fois. Elle
    // dit ce que le compteur vient d'annoncer : ces gens-là sont
    // vraiment joignables, un message peut aller jusqu'à eux.
    const debutOnde = 0.78;
    if (t > debutOnde && t < MeshGrowthModel.debutSortie) {
      final onde = (t - debutOnde) / (MeshGrowthModel.debutSortie - debutOnde);
      for (final lien in MeshGrowthModel.liens) {
        if (!atteints.contains(lien[0]) || !atteints.contains(lien[1])) {
          continue;
        }
        final p = Offset.lerp(
          place(lien[0]),
          place(lien[1]),
          Curves.easeInOut.transform(onde),
        )!;
        canvas.drawCircle(
          p,
          2.6,
          Paint()..color = accent.withValues(alpha: (1 - onde) * 0.85),
        );
      }
    }

    // ── LES POINTS ──
    for (var i = 0; i < MeshGrowthModel.noeuds.length; i++) {
      final presence = MeshGrowthModel.presence(t, i);
      if (presence <= 0) continue;

      final centre = place(i);
      final joignable = atteints.contains(i);
      final moi = i == 0;
      final rayon = (moi ? 8.5 : 6.0) * presence.clamp(0.0, 1.2);

      if (joignable) {
        // Le halo, en cercle translucide et non en flou : un
        // `MaskFilter` coûte un calque hors-écran par point, et il y en
        // a dix.
        canvas.drawCircle(
          centre,
          rayon * 2.5,
          Paint()..color = accent.withValues(alpha: 0.13 * presence),
        );
        canvas.drawCircle(
          centre,
          rayon,
          Paint()..color = accent.withValues(alpha: presence.clamp(0.0, 1.0)),
        );
      } else {
        // Hors d'atteinte : un cercle CREUX. La différence entre plein
        // et creux se voit d'un coup d'œil, là où deux teintes de gris
        // demanderaient de comparer.
        canvas.drawCircle(centre, rayon, Paint()..color = fond);
        canvas.drawCircle(
          centre,
          rayon,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = eteint.withValues(alpha: presence.clamp(0.0, 1.0)),
        );
      }

      // Le point de départ porte un anneau : c'est vous, et il faut
      // pouvoir vous retrouver dans le graphe à tout instant.
      if (moi) {
        canvas.drawCircle(
          centre,
          rayon + 5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = accent.withValues(alpha: 0.55 * presence),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _NetworkPainter old) => old.t != t;
}
