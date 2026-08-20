// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LA BARRE D'ONGLETS DU BAS, reproduite aux spécifications exactes d'Apple,
// avec l'indicateur LIQUIDE qui s'étire entre les onglets comme une goutte
// de mercure (le style « Liquid Glass » des dernières versions d'iOS).
//
// ── CE QUI FAIT UNE VRAIE BARRE D'ONGLETS iOS ───────────────────────────
//
// L'ancienne barre était une barre Material : une pastille colorée qui
// enveloppait l'onglet actif, avec le libellé À CÔTÉ de l'icône, et les
// onglets espacés irrégulièrement. Rien de tout cela n'existe sur iOS.
// Les règles réelles d'Apple :
//
//   1. HAUTEUR DE 49 POINTS, invariable, plus la zone de sécurité du bas.
//   2. LIBELLÉ SOUS L'ICÔNE, jamais à côté — et toujours affiché, pour
//      tous les onglets, pas seulement l'actif.
//   3. LARGEURS ÉGALES : chaque onglet occupe exactement 1/N de la barre,
//      quel que soit la longueur de son libellé.
//   4. AUCUN FOND derrière l'onglet actif dans le style classique : c'est
//      la COULEUR qui distingue l'actif (bleu) de l'inactif (gris).
//   5. ICÔNE PLEINE quand actif, CONTOUR quand inactif.
//   6. MATÉRIAU TRANSLUCIDE : le contenu défile derrière en étant flouté,
//      avec un trait d'un pixel en haut.
//
// ── L'INDICATEUR LIQUIDE ────────────────────────────────────────────────
//
// Par-dessus ces règles, on ajoute la signature visuelle d'Apple la plus
// récente : une capsule de verre qui se DÉPLACE d'un onglet à l'autre en
// se déformant comme du liquide.
//
// LE TRUC POUR QUE ÇA RESSEMBLE À DU MERCURE : on ne déplace pas une seule
// forme. On en met DEUX — l'une part vite vers la destination, l'autre
// traîne derrière. Pendant le trajet, elles se séparent ; le filtre de
// fusion (voir `ouro_liquid.dart`) les relie alors par un pont de matière
// qui s'étire. À l'arrivée, elles se rejoignent et le pont disparaît.
//
// C'est exactement le comportement d'une goutte de liquide qu'on fait
// glisser : elle s'allonge en accélérant, puis se recompose en s'arrêtant.
// Une forme unique qui se déplace, même avec une belle courbe, n'aura
// jamais cet aspect — il lui manque l'étirement.
// ============================================================================


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:motor/motor.dart';
import 'ouro_colors.dart';
import 'ouro_typography.dart';
import 'ouro_haptics.dart';
import 'ouro_glass.dart';
import 'design_tokens.dart';

/// Un onglet de la barre.
class OuroTabItem {
  const OuroTabItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });

  /// Icône en contour, affichée quand l'onglet n'est pas sélectionné.
  final IconData icon;

  /// Icône pleine, affichée quand l'onglet est sélectionné.
  final IconData activeIcon;

  final String label;
}

/// Barre d'onglets iOS avec indicateur liquide.
class OuroTabBar extends StatefulWidget {
  const OuroTabBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.minimized = false,
  });

  final List<OuroTabItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  /// La barre s'efface-t-elle pour laisser la place au contenu ?
  ///
  /// ── Le geste d'iOS 26, celui qu'a repris WhatsApp ─────────────────
  ///
  /// Quand on descend dans une liste, la barre d'onglets S'ESCAMOTE vers
  /// le bas ; au premier mouvement vers le haut, elle revient. Apple
  /// l'expose sous le nom `tabBarMinimizeBehavior(.onScrollDown)`, et
  /// c'est le principe « le contenu d'abord » de Liquid Glass : le
  /// châssis ne réclame de la place que lorsqu'on le cherche.
  ///
  /// Le mouvement est porté par un RESSORT, pas par une courbe : si l'on
  /// change de sens de défilement en plein trajet, la barre garde sa
  /// vitesse et rattrape la nouvelle position sans repartir de zéro.
  /// C'est précisément ce qui distingue une animation iOS d'une
  /// animation « qui joue ».
  final bool minimized;

  /// Hauteur du contenu, hors zone de sécurité — la valeur exacte d'iOS.
  static const double height = 49;

  /// Marge autour de la barre flottante.
  ///
  /// ── Pourquoi la barre ne touche plus le bord ──────────────────────
  ///
  /// C'est le changement le plus visible d'iOS 26, et celui que WhatsApp
  /// a repris : la barre d'onglets n'est plus un bandeau soudé au bas de
  /// l'écran, c'est une CAPSULE QUI FLOTTE au-dessus du contenu. On voit
  /// la liste passer derrière elle et de chaque côté, ce qui donne la
  /// profondeur — et supprime le trait de séparation, qui n'a plus de
  /// sens dès lors que rien n'est collé à rien.
  static const double floatingMargin = 12;

  /// Place à réserver en bas des écrans pour que le contenu ne finisse
  /// jamais sous la capsule.
  static double reservedHeight(double bottomInset) =>
      height + floatingMargin * 2 + bottomInset;

  @override
  State<OuroTabBar> createState() => _OuroTabBarState();
}

class _OuroTabBarState extends State<OuroTabBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// Position de départ et d'arrivée du déplacement en cours, en index
  /// d'onglet (des valeurs continues, pas entières, pendant le trajet).
  late double _from;
  late double _to;

  @override
  void initState() {
    super.initState();
    _from = widget.currentIndex.toDouble();
    _to = widget.currentIndex.toDouble();
    _controller = AnimationController(
      vsync: this,
      // 420 ms : assez lent pour qu'on VOIE l'étirement du liquide, assez
      // rapide pour ne jamais donner l'impression d'attendre. En dessous
      // de ~300 ms, la déformation passe inaperçue et l'effet ne sert à
      // rien ; au-delà de ~500 ms, la navigation devient pénible.
      duration: const Duration(milliseconds: 420),
      value: 1,
    );
  }

  @override
  void didUpdateWidget(covariant OuroTabBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentIndex != oldWidget.currentIndex) {
      // Le nouveau trajet démarre là où le précédent en était — si on
      // change d'onglet en plein mouvement, la goutte repart de sa
      // position réelle au lieu de sauter.
      _from = _currentPosition;
      _to = widget.currentIndex.toDouble();
      _controller.forward(from: 0);
    }
  }

  /// Position actuelle de la goutte, interpolée entre départ et arrivée.
  double get _currentPosition => _from + (_to - _from) * _controller.value;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final totalHeight = OuroTabBar.reservedHeight(bottomInset);

    // ⚠️ DEUX RESSORTS DIFFÉRENTS, ET C'EST VOULU.
    //
    // Ranger la barre et la faire revenir ne sont pas deux versions du
    // même geste. On la range parce qu'elle gêne : elle doit s'écarter
    // sans se faire remarquer — `smooth`, sans rebond. On la rappelle
    // parce qu'on en a besoin : elle doit ARRIVER, et un léger
    // dépassement la rend franche — `snappy`.
    //
    // Un seul ressort pour les deux sens donne soit un rangement qui
    // rebondit bêtement, soit un retour mou. C'est exactement le genre
    // d'asymétrie qu'iOS applique partout sans le dire.
    return SingleMotionBuilder(
      motion: widget.minimized
          ? const CupertinoMotion.smooth()
          : const CupertinoMotion.snappy(),
      value: widget.minimized ? 1.0 : 0.0,
      builder: (context, hidden, _) {
        if (hidden < 0.001) return _bar(bottomInset);

        // La capsule ne fait pas que descendre : elle SE RÉTRACTE. Elle
        // se resserre vers son centre en s'enfonçant, comme un objet
        // qu'on range dans une fente. Une simple translation donnerait
        // l'impression qu'elle tombe.
        final scale = 1 - 0.12 * hidden;

        return Transform.translate(
          offset: Offset(0, hidden * totalHeight * 0.75),
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.bottomCenter,
            child: Opacity(
              // L'opacité décroît PLUS VITE que la translation : la
              // barre a déjà disparu quand elle sort du cadre, plutôt
              // que de sembler glisser sous le bord de l'écran.
              opacity: (1 - hidden * 1.5).clamp(0.0, 1.0),
              child: _bar(bottomInset),
            ),
          ),
        );
      },
    );
  }

  Widget _bar(double bottomInset) {
    const radius = OuroTabBar.height / 2;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        OuroTabBar.floatingMargin,
        0,
        OuroTabBar.floatingMargin,
        bottomInset + OuroTabBar.floatingMargin,
      ),
      child: Stack(
        children: [
          // ⚠️ L'OMBRE EST PEINTE À PART, SOUS UNE FORME INVISIBLE.
          //
          // Une ombre projetée directement derrière une surface
          // translucide se verrait au travers et salirait la matière. Ici
          // elle vit dans sa propre couche, sous le verre : elle détache
          // la capsule du contenu sans jamais le traverser.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black
                          .withValues(alpha: OuroColors.isDark ? 0.42 : 0.13),
                      blurRadius: 22,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // La couche de verre, et son groupe de fusion : c'est lui qui
          // permet à l'indicateur de se souder à la barre. Voir
          // `ouro_glass.dart`.
          OuroGlassLayer(
            child: _GlassIndicator(
              tabIndex: widget.currentIndex,
              tabCount: widget.items.length,
              onTabChanged: widget.onTap,
              builder: (position) => LiquidGlass.grouped(
                // ⚠️ `Clip.none` : la capsule ne doit PAS rogner ce qui
                // dépasse d'elle, sinon l'indicateur serait coupé net à
                // l'instant où il s'en détache — précisément le moment
                // qu'on veut montrer.
                clipBehavior: Clip.none,
                shape: const LiquidRoundedSuperellipse(borderRadius: radius),
                child: SizedBox(
                  height: OuroTabBar.height,
                  child: Row(
                    children: List.generate(widget.items.length, (i) {
                      // L'icône réagit à la DISTANCE de la goutte : elle
                      // se soulève, grossit et se colore à mesure que
                      // celle-ci approche, retombe quand elle s'éloigne.
                      // C'est ce qui fait croire à une matière qui
                      // POUSSE l'icône devant elle.
                      final influence =
                          (1 - (position - i).abs()).clamp(0.0, 1.0);
                      return Expanded(
                        child: _TabButton(
                          item: widget.items[i],
                          selected: i == widget.currentIndex,
                          influence: influence,
                          onTap: () {
                            if (i == widget.currentIndex) return;
                            OuroHaptics.selection();
                            widget.onTap(i);
                          },
                        ),
                      );
                    }),
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

// ─────────────────────────────────────────────────────────────
//  L'INDICATEUR — LA GOUTTE QUI SE DÉTACHE ET SE REFOND
// ─────────────────────────────────────────────────────────────

/// L'indicateur d'onglet actif, et le geste de balayage qui va avec.
///
/// ── Comment le mouvement est construit ────────────────────────────────
///
/// Trois choses se superposent, et c'est leur combinaison qui donne
/// l'impression de matière :
///
/// 1. **UN RESSORT, PAS UNE COURBE.** La position suit un ressort
///    d'Apple : `interactive` tant que le doigt est posé (il colle au
///    doigt sans rebondir), `bouncy` au lâcher (il dépasse légèrement la
///    cible et revient). Un ressort peut être interrompu en plein vol
///    sans repartir de zéro — c'est la base de la fluidité iOS.
///
/// 2. **LA MATIÈRE N'APPARAÎT QU'EN MOUVEMENT.** Au repos, l'indicateur
///    n'est qu'un aplat translucide très discret. Dès qu'il se déplace
///    d'un tiers de case, il devient du VRAI verre — réfraction, reflet,
///    frange colorée — puis redevient plat en arrivant. C'est ce que fait
///    iOS 26 : la matière se révèle pendant la transition et se range
///    ensuite. Cela évite aussi de payer un shader en permanence pour
///    quelque chose d'immobile.
///
/// 3. **LA DÉFORMATION SUIT LA VITESSE.** Plus il va vite, plus il
///    s'étire dans le sens du trajet et s'aplatit dans l'autre — le
///    « squash and stretch » de l'animation traditionnelle. Sans lui, une
///    forme qui se déplace vite paraît rigide.
///
/// Et comme il vit dans le même groupe de fusion que la capsule, tout ce
/// mouvement se joue en restant SOUDÉ à elle : il en sort en s'étirant,
/// et s'y refond à l'arrivée.
class _GlassIndicator extends ConsumerStatefulWidget {
  const _GlassIndicator({
    required this.builder,
    required this.tabIndex,
    required this.tabCount,
    required this.onTabChanged,
  });

  /// ⚠️ UN CONSTRUCTEUR, PAS UN ENFANT FIGÉ.
  ///
  /// Les icônes doivent réagir au PASSAGE de la goutte, pas à un état
  /// « sélectionné / pas sélectionné ». Il faut donc leur transmettre sa
  /// position continue à chaque image — d'où ce rappel, qui reçoit la
  /// position en index d'onglet (2,4 = entre le troisième et le
  /// quatrième). Reconstruire quatre boutons par image ne coûte rien ;
  /// laisser les icônes figées pendant qu'une matière glisse dessous
  /// casse toute l'illusion.
  final Widget Function(double position) builder;
  final int tabIndex;
  final int tabCount;
  final ValueChanged<int> onTabChanged;

  @override
  ConsumerState<_GlassIndicator> createState() => _GlassIndicatorState();
}

class _GlassIndicatorState extends ConsumerState<_GlassIndicator> {
  bool _pressed = false;
  bool _dragging = false;

  /// Position horizontale, de -1 (premier onglet) à +1 (dernier).
  late double _x = _alignmentFor(widget.tabIndex);

  /// Dernier onglet survolé pendant un balayage — sert à ne déclencher
  /// la vibration qu'au FRANCHISSEMENT, pas à chaque image.
  late int _lastCrossed = widget.tabIndex;

  double _alignmentFor(int index) {
    if (widget.tabCount < 2) return 0;
    return (index / (widget.tabCount - 1)).clamp(0.0, 1.0) * 2 - 1;
  }

  @override
  void didUpdateWidget(covariant _GlassIndicator old) {
    super.didUpdateWidget(old);
    if (old.tabIndex != widget.tabIndex || old.tabCount != widget.tabCount) {
      setState(() {
        _x = _alignmentFor(widget.tabIndex);
        _lastCrossed = widget.tabIndex;
      });
    }
  }

  /// Convertit la position du doigt en alignement -1..1, avec la
  /// résistance élastique des bords d'iOS.
  double _alignmentFromGlobal(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.width == 0) return _x;
    final local = box.globalToLocal(globalPosition);

    // L'indicateur a sa propre largeur : son CENTRE ne peut pas atteindre
    // les extrémités de la barre. On retire donc une demi-case de chaque
    // côté avant de convertir.
    final width = 1 / widget.tabCount;
    final range = 1 - width;
    if (range <= 0) return 0;
    final raw = (local.dx / box.size.width).clamp(0.0, 1.0);
    final normalized = (raw - width / 2) / range;
    return _rubberBand(normalized) * 2 - 1;
  }

  /// Au-delà des bords, le doigt n'entraîne plus l'indicateur qu'à 40 % —
  /// la même résistance élastique que celle d'une liste iOS tirée trop
  /// loin. Sans elle, on pourrait pousser l'indicateur hors de la barre.
  double _rubberBand(double value) {
    const resistance = 0.4;
    const maxOverdrag = 0.3;
    if (value < 0) return -(-value * resistance).clamp(0.0, maxOverdrag);
    if (value > 1) return 1 + ((value - 1) * resistance).clamp(0.0, maxOverdrag);
    return value;
  }

  void _onDragDown(DragDownDetails d) {
    setState(() {
      _pressed = true;
      _x = _alignmentFromGlobal(d.globalPosition);
    });
  }

  void _onDragUpdate(DragUpdateDetails d) {
    final x = _alignmentFromGlobal(d.globalPosition);
    // Une vibration à chaque case franchie, comme sous un sélecteur iOS :
    // on sent les crans sans avoir à regarder.
    final over = _nearestTab((x + 1) / 2);
    if (over != _lastCrossed) {
      _lastCrossed = over;
      OuroHaptics.selection();
    }
    setState(() {
      _dragging = true;
      _x = x;
    });
  }

  int _nearestTab(double relative) =>
      (relative * (widget.tabCount - 1)).round().clamp(0, widget.tabCount - 1);

  void _onDragEnd(DragEndDetails d) {
    final box = context.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 1;
    final relative = (_x + 1) / 2;

    // La vitesse au lâcher PROJETTE la trajectoire : un geste rapide
    // emporte l'indicateur plus loin que là où le doigt s'est levé.
    // C'est ce qui distingue un balayage d'un simple glissement.
    final velocity = d.velocity.pixelsPerSecond.dx / width;
    final projected = (relative + velocity * 0.25).clamp(0.0, 1.0);
    final target = _nearestTab(projected);

    setState(() {
      _dragging = false;
      _pressed = false;
      _x = _alignmentFor(target);
    });
    if (target != widget.tabIndex) widget.onTabChanged(target);
  }

  @override
  Widget build(BuildContext context) {
    final settled = _alignmentFor(widget.tabIndex);
    final degraded = ouroGlassDegraded(ref);

    return GestureDetector(
      onHorizontalDragDown: _onDragDown,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: () => setState(() {
        _dragging = false;
        _pressed = false;
        _x = settled;
      }),
      child: VelocityMotionBuilder(
        converter: const SingleMotionConverter(),
        value: _x,
        motion: _dragging
            ? const Motion.interactiveSpring(snapToEnd: true)
            : const Motion.bouncySpring(snapToEnd: true),
        builder: (context, x, velocity, _) {
          final alignment = Alignment(x, 0);
          // De -1..1 vers un index d'onglet continu.
          final position = (x + 1) / 2 * (widget.tabCount - 1);
          final bar = widget.builder(position);

          // « Épaisseur » : 0 = aplat discret au repos, 1 = verre en
          // mouvement. Le seuil de 0,3 case évite que la matière
          // n'apparaisse pour un simple tressaillement.
          final wantsGlass =
              !degraded && (_pressed || (x - settled).abs() > 0.30);

          return SingleMotionBuilder(
            motion: const Motion.snappySpring(
              snapToEnd: true,
              duration: Duration(milliseconds: 300),
            ),
            value: wantsGlass ? 1.0 : 0.0,
            builder: (context, thickness, _) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // L'aplat de repos : il s'efface dès que la matière
                  // prend le relais, pour ne pas se voir au travers.
                  if (thickness < 1)
                    _IndicatorSlot(
                      alignment: alignment,
                      velocity: velocity,
                      thickness: thickness,
                      tabCount: widget.tabCount,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: thickness <= 0.2 ? 1 : 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: OuroColors.accent.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(64),
                          ),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                  bar,
                  if (thickness > 0)
                    _IndicatorSlot(
                      alignment: alignment,
                      velocity: velocity,
                      thickness: thickness,
                      tabCount: widget.tabCount,
                      child: LiquidGlass.withOwnLayer(
                        fake: degraded,
                        settings: LiquidGlassSettings(
                          // `visibility` fait NAÎTRE la matière au lieu
                          // de la faire apparaître d'un coup : le verre
                          // se densifie à mesure que l'indicateur prend
                          // de la vitesse.
                          visibility: thickness,
                          glassColor:
                              OuroColors.accent.withValues(alpha: 0.14),
                          saturation: 1.5,
                          refractiveIndex: 1.15,
                          thickness: 20,
                          lightIntensity: 2,
                          chromaticAberration: 0.5,
                          blur: 0,
                        ),
                        shape:
                            const LiquidRoundedSuperellipse(borderRadius: 64),
                        child: GlassGlow(child: const SizedBox.expand()),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// Place l'indicateur sur la bonne case, et le déforme selon sa vitesse.
class _IndicatorSlot extends StatelessWidget {
  const _IndicatorSlot({
    required this.alignment,
    required this.velocity,
    required this.thickness,
    required this.tabCount,
    required this.child,
  });

  final Alignment alignment;
  final double velocity;
  final double thickness;
  final int tabCount;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    // En prenant de l'épaisseur, la goutte DÉBORDE de sa case : c'est ce
    // débordement qui la fait mordre sur la capsule et déclenche la
    // soudure du groupe de fusion.
    final rect = RelativeRect.lerp(
      RelativeRect.fill,
      const RelativeRect.fromLTRB(-10, -10, -10, -10),
      thickness,
    )!;

    return Positioned.fill(
      left: 4,
      right: 4,
      top: 4,
      bottom: 4,
      child: FractionallySizedBox(
        widthFactor: 1 / tabCount,
        alignment: alignment,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fromRelativeRect(
              rect: rect,
              child: SingleMotionBuilder(
                motion: const Motion.bouncySpring(
                  duration: Duration(milliseconds: 600),
                ),
                value: velocity,
                builder: (context, v, child) => Transform(
                  alignment: Alignment.center,
                  transform: _jelly(v),
                  child: child,
                ),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Écrasement dans le sens du déplacement, étirement perpendiculaire —
  /// le « squash and stretch » des animateurs. C'est ce qui fait qu'une
  /// forme rapide paraît molle plutôt que rigide.
  static Matrix4 _jelly(double velocity) {
    const maxDistortion = 0.8;
    const scale = 10.0;
    final speed = velocity.abs();
    if (speed == 0) return Matrix4.identity();
    final factor = (speed / scale).clamp(0.0, 1.0) * maxDistortion;
    final squashX = 1 - factor * 0.5;
    final stretchY = 1 + factor * 0.3;
    return Matrix4.identity()..scaleByDouble(squashX, stretchY, 1, 1);
  }
}

class _TabButton extends StatelessWidget {
  const _TabButton({
    required this.item,
    required this.selected,
    required this.onTap,
    this.influence = 0,
  });

  final OuroTabItem item;
  final bool selected;
  final VoidCallback onTap;

  /// Proximité de la goutte de liquide, de 0 (loin) à 1 (juste dessous).
  /// C'est une valeur CONTINUE, pas un booléen : c'est elle qui permet à
  /// l'icône d'accompagner le passage du liquide au lieu de basculer d'un
  /// état à l'autre.
  final double influence;

  @override
  Widget build(BuildContext context) {
    // La couleur suit la POSITION DU LIQUIDE, pas l'état sélectionné :
    // l'icône vire au bleu au fur et à mesure que la goutte arrive, au
    // lieu de basculer d'un coup. Un changement de couleur instantané
    // pendant qu'une matière glisse lentement dessous casse l'illusion.
    final color = Color.lerp(
      OuroColors.systemGray,
      OuroColors.accent,
      Curves.easeOut.transform(influence),
    )!;

    // L'icône se soulève et grossit sous la poussée du liquide.
    final lift = -3.0 * influence;
    final scale = 1 + 0.10 * influence;

    // ⚠️ L'onglet DOIT annoncer son état sélectionné, pas seulement son
    // nom. Sans `selected`, un lecteur d'écran énonce cinq onglets
    // identiques et l'utilisateur ne sait pas où il se trouve dans
    // l'application — la capsule bleue qui le lui dirait ne lui est
    // d'aucun secours. Avec, VoiceOver dit « Discussions, sélectionné,
    // onglet ».
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
          Transform.translate(
            offset: Offset(0, lift),
            child: Transform.scale(
              scale: scale,
              // Le passage contour → plein se fait en fondu croisé : un
              // changement d'icône instantané « clignote » désagréablement.
              child: AnimatedSwitcher(
                duration: DesignTokens.durationFast,
                transitionBuilder: (child, animation) =>
                    FadeTransition(opacity: animation, child: child),
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  key: ValueKey(selected),
                  // 25 points : la taille des symboles de barre d'onglets iOS.
                  size: 25,
                  color: color,
                ),
              ),
            ),
          ),
          const SizedBox(height: 2),
          // Le libellé est TOUJOURS visible, y compris pour les onglets
          // inactifs — c'est la règle iOS. Une barre où le libellé
          // n'apparaît que sur l'onglet actif oblige à deviner les autres.
          //
          // Il passe au BLANC quand il est actif, jamais au bleu : la
          // capsule liquide est bleue, et du texte bleu par-dessus
          // devenait franchement illisible. L'icône, elle, se détache
          // très bien en bleu car ses traits sont épais.
          Text(
            item.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OuroTypography.caption2.copyWith(
              fontSize: 10,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: Color.lerp(
                OuroColors.systemGray,
                OuroColors.label,
                Curves.easeOut.transform(influence),
              ),
              letterSpacing: 0.1,
            ),
          ),
          ],
        ),
      ),
    );
  }
}
