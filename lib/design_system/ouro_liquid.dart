// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Les effets LIQUIDES de l'app — la matière qui fusionne, s'étire et se
// sépare, comme les gouttes de mercure des interfaces d'Apple (la
// Dynamic Island qui s'étire, les bulles du Control Center, le « Liquid
// Glass » d'iOS 26).
//
// DEUX TECHNIQUES COMPLÉMENTAIRES SONT UTILISÉES ICI :
//
// ┌─ 1. LA FUSION DE GOUTTES (« metaball ») ─────────────────────────┐
// │ C'est un tour de passe-passe en deux étapes, sans aucun shader : │
// │                                                                   │
// │   a) On FLOUTE fortement plusieurs formes. Leurs bords nets       │
// │      deviennent des halos diffus qui se chevauchent.              │
// │   b) On applique une MATRICE DE COULEUR qui pousse brutalement    │
// │      le contraste du canal de transparence : tout ce qui est      │
// │      au-dessus d'un seuil devient parfaitement opaque, tout ce    │
// │      qui est en dessous disparaît.                                │
// │                                                                   │
// │ Résultat : là où deux halos flous se chevauchaient, leurs         │
// │ transparences s'additionnent, passent le seuil, et les deux       │
// │ formes se retrouvent RELIÉES par un pont de matière — exactement  │
// │ comme deux gouttes d'eau qui fusionnent quand on les rapproche.   │
// │ Aucun calcul de physique n'est fait : c'est une illusion pure,    │
// │ et c'est la technique utilisée par toutes les interfaces qui      │
// │ font cet effet.                                                   │
// └───────────────────────────────────────────────────────────────────┘
//
// ┌─ 2. LA RÉFRACTION (shader GLSL) ─────────────────────────────────┐
// │ Pour déformer une image comme à travers de l'eau en mouvement,   │
// │ la fusion de gouttes ne suffit pas : il faut déplacer chaque      │
// │ pixel individuellement. C'est le rôle du programme GPU dans       │
// │ `shaders/liquid.frag` — voir ce fichier pour le détail.           │
// └───────────────────────────────────────────────────────────────────┘
//
// Le shader étant chargé de façon asynchrone (il est compilé par le
// téléphone au premier usage), tous les widgets de ce fichier
// fonctionnent SANS lui : ils affichent simplement leur contenu normal
// tant qu'il n'est pas prêt, et l'effet apparaît une fois disponible.
// Jamais d'écran vide ni de plantage si le GPU ne le supporte pas.
// ============================================================================

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
// Fournit `AnimatedSampler`, qui capture un widget sous forme de texture
// pour l'alimenter à un shader. Écrit et maintenu par l'équipe Flutter —
// préférable à une implémentation maison, car capturer une couche de
// rendu à chaque image sans fuite mémoire est particulièrement délicat.
import 'package:flutter_shaders/flutter_shaders.dart';

// ─────────────────────────────────────────────────────────────
//  CHARGEMENT DU SHADER
// ─────────────────────────────────────────────────────────────

/// Charge et conserve le programme GPU, pour ne le compiler qu'une seule
/// fois pour toute la durée de vie de l'app.
class LiquidShader {
  LiquidShader._();

  static ui.FragmentProgram? _program;
  static Future<ui.FragmentProgram?>? _loading;

  /// Vrai une fois le shader compilé et prêt à l'emploi.
  static bool get isReady => _program != null;

  /// Le programme compilé, ou null s'il n'est pas encore prêt.
  static ui.FragmentProgram? get program => _program;

  /// Compile le shader. À appeler une fois au démarrage de l'app ; les
  /// appels suivants réutilisent le résultat.
  ///
  /// N'échoue jamais bruyamment : si le GPU ou la plateforme ne supporte
  /// pas les shaders, l'app continue normalement, simplement sans l'effet
  /// de réfraction.
  static Future<ui.FragmentProgram?> load() {
    if (_program != null) return Future.value(_program);
    return _loading ??= _loadOnce();
  }

  static Future<ui.FragmentProgram?> _loadOnce() async {
    try {
      final program =
          await ui.FragmentProgram.fromAsset('shaders/liquid.frag');
      _program = program;
      return program;
    } catch (e) {
      debugPrint('[Liquid] shader indisponible, effet désactivé: $e');
      return null;
    }
  }
}

// ─────────────────────────────────────────────────────────────
//  FUSION DE GOUTTES (metaball)
// ─────────────────────────────────────────────────────────────

/// Enveloppe un ensemble de formes pour qu'elles FUSIONNENT entre elles
/// quand elles se rapprochent, comme des gouttes de liquide.
///
/// Voir l'explication détaillée en tête de fichier. En pratique : posez
/// plusieurs cercles opaques en enfants, rapprochez-les, et ils se
/// relieront tout seuls par un pont de matière.
///
/// ⚠️ Les enfants doivent être OPAQUES et de couleur unie pour que le
/// seuillage fonctionne — un contenu déjà semi-transparent ou dégradé
/// donnera un résultat imprévisible.
class LiquidMetaball extends StatelessWidget {
  const LiquidMetaball({
    super.key,
    required this.child,
    this.blur = 12,
    this.threshold = 28,
  });

  final Widget child;

  /// Force du flou. Plus il est élevé, plus les formes fusionnent de
  /// loin — mais plus leurs contours deviennent mous.
  final double blur;

  /// Raideur du seuil de transparence. Plus c'est élevé, plus le bord du
  /// liquide est net. En dessous de ~15, l'effet redevient un simple flou.
  final double threshold;

  @override
  Widget build(BuildContext context) {
    // L'ordre est capital : `ColorFiltered` est le PARENT, donc il
    // s'applique APRÈS le flou de `ImageFiltered`. Inversés, on
    // seuillerait des formes encore nettes — et rien ne fusionnerait.
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(_alphaContrastMatrix(threshold)),
      child: ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: child,
      ),
    );
  }

  /// Matrice qui laisse les couleurs intactes mais amplifie brutalement
  /// le canal de transparence.
  ///
  /// Une matrice de couleur transforme chaque pixel ainsi :
  ///   nouvelle_valeur = a·R + b·V + c·B + d·A + e
  /// Les trois premières lignes (rouge, vert, bleu) sont l'identité : on
  /// ne touche pas aux couleurs. Seule la quatrième ligne agit, en
  /// multipliant la transparence par [k] puis en retranchant une
  /// constante — ce qui transforme le dégradé du flou en une bascule
  /// nette entre « transparent » et « opaque ».
  static List<double> _alphaContrastMatrix(double k) {
    // Le décalage vise un seuil autour de 47 % de transparence : un peu
    // avant la moitié, pour que les ponts de matière se forment dès que
    // deux formes commencent à se toucher, et pas seulement quand elles
    // se recouvrent largement.
    final offset = -k * 255 * 0.47;
    return <double>[
      1, 0, 0, 0, 0, // rouge inchangé
      0, 1, 0, 0, 0, // vert inchangé
      0, 0, 1, 0, 0, // bleu inchangé
      0, 0, 0, k, offset, // transparence : contraste poussé à fond
    ];
  }
}

/// Une goutte animée, à placer dans un [LiquidMetaball].
///
/// Elle dérive lentement autour de sa position d'origine, sur une
/// trajectoire qui ne se répète jamais exactement — deux gouttes avec des
/// [seed] différentes ne seront jamais synchronisées, ce qui évite
/// l'aspect mécanique d'un mouvement en boucle.
class LiquidBlob extends StatefulWidget {
  const LiquidBlob({
    super.key,
    required this.size,
    required this.color,
    this.seed = 0,
    this.drift = 10,
    this.speed = 1,
  });

  final double size;
  final Color color;

  /// Change la trajectoire — donnez une valeur différente à chaque goutte.
  final int seed;

  /// Amplitude du déplacement, en pixels.
  final double drift;

  /// Vitesse de dérive (1 = référence).
  final double speed;

  @override
  State<LiquidBlob> createState() => _LiquidBlobState();
}

class _LiquidBlobState extends State<LiquidBlob>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      // Cycle volontairement long : une dérive lente se remarque à peine
      // consciemment, mais rend la surface « vivante ».
      duration: Duration(milliseconds: (9000 / widget.speed).round()),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value * 2 * math.pi;
        // Deux fréquences non multiples l'une de l'autre (1 et 1,3) :
        // leur combinaison ne revient au même point qu'au bout de très
        // longtemps, d'où une trajectoire jamais répétitive.
        final phase = widget.seed * 1.7;
        final dx = math.sin(t + phase) * widget.drift;
        final dy = math.cos(t * 1.3 + phase) * widget.drift;
        return Transform.translate(offset: Offset(dx, dy), child: child);
      },
      child: Container(
        width: widget.size,
        height: widget.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  RÉFRACTION (shader)
// ─────────────────────────────────────────────────────────────

/// Applique la déformation liquide du shader GLSL à son contenu.
///
/// Utilisé pour les transitions : quand [progress] passe de 0 à 1, une
/// onde traverse le contenu de haut en bas en le déformant sur son
/// passage.
///
/// Si le shader n'est pas disponible, affiche simplement le contenu tel
/// quel — l'app reste parfaitement utilisable.
class LiquidRefraction extends StatefulWidget {
  const LiquidRefraction({
    super.key,
    required this.child,
    required this.progress,
    this.strength = 1.0,
    this.enabled = true,
  });

  final Widget child;

  /// Position de l'onde, de 0 (avant l'écran) à 1 (après l'écran).
  final double progress;

  /// Intensité de la déformation. 0 la désactive complètement.
  final double strength;

  final bool enabled;

  @override
  State<LiquidRefraction> createState() => _LiquidRefractionState();
}

class _LiquidRefractionState extends State<LiquidRefraction>
    with SingleTickerProviderStateMixin {
  ui.FragmentShader? _shader;

  /// Horloge qui alimente l'ondulation du shader. Elle tourne en
  /// permanence pendant l'effet pour que l'onde vive même si `progress`
  /// est momentanément figé.
  late final Ticker _ticker;
  double _time = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((elapsed) {
      if (!mounted) return;
      setState(() => _time = elapsed.inMilliseconds / 1000.0);
    });
    _initShader();
  }

  Future<void> _initShader() async {
    final program = await LiquidShader.load();
    if (!mounted || program == null) return;
    setState(() => _shader = program.fragmentShader());
    if (widget.enabled) _ticker.start();
  }

  @override
  void didUpdateWidget(covariant LiquidRefraction oldWidget) {
    super.didUpdateWidget(oldWidget);
    // L'horloge ne tourne que quand l'effet est actif : un ticker qui
    // continue en arrière-plan redessinerait l'écran 60 fois par seconde
    // pour rien, et viderait la batterie.
    if (widget.enabled && !_ticker.isActive && _shader != null) {
      _ticker.start();
    } else if (!widget.enabled && _ticker.isActive) {
      _ticker.stop();
    }
  }

  @override
  void dispose() {
    _ticker.dispose();
    _shader?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (shader == null || !widget.enabled || widget.strength <= 0) {
      return widget.child;
    }

    return AnimatedSampler(
      (image, size, canvas) {
        // L'ordre des uniformes doit correspondre EXACTEMENT à celui de
        // leur déclaration dans `liquid.frag` — c'est une liste
        // positionnelle, pas nommée : intervertir deux valeurs donnerait
        // un résultat visuellement absurde et très difficile à diagnostiquer.
        shader
          ..setFloat(0, size.width) // uSize.x
          ..setFloat(1, size.height) // uSize.y
          ..setFloat(2, _time) // uTime
          ..setFloat(3, widget.progress) // uProgress
          ..setFloat(4, widget.strength) // uStrength
          ..setImageSampler(0, image); // uTexture

        canvas.drawRect(
          Rect.fromLTWH(0, 0, size.width, size.height),
          Paint()..shader = shader,
        );
      },
      child: widget.child,
    );
  }
}

// La capture du contenu en texture (`AnimatedSampler`) est fournie par le
// paquet `flutter_shaders` importé en tête de fichier.

// ─────────────────────────────────────────────────────────────
//  TRANSITION DE PAGE LIQUIDE
// ─────────────────────────────────────────────────────────────

/// Transition d'écran où une onde liquide traverse la page en la
/// déformant, pendant que le contenu apparaît.
///
/// À brancher sur le `transitionsBuilder` d'une route. L'onde balaie
/// l'écran de haut en bas, et son intensité retombe à zéro aux deux
/// extrémités : au repos, aucune déformation ne subsiste — un écran figé
/// et déformé serait immédiatement perçu comme un bug d'affichage.
class LiquidPageTransition extends StatelessWidget {
  const LiquidPageTransition({
    super.key,
    required this.animation,
    required this.child,
  });

  final Animation<double> animation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        // L'intensité suit une cloche : nulle au départ, maximale à
        // mi-parcours, nulle à l'arrivée.
        final strength = (1 - (t * 2 - 1).abs()).clamp(0.0, 1.0);
        return LiquidRefraction(
          progress: t,
          strength: strength,
          // On coupe complètement l'effet aux extrémités, pour que le
          // shader (et son horloge) cesse de tourner une fois la
          // transition finie.
          enabled: strength > 0.01,
          child: Opacity(
            opacity: Curves.easeOut.transform(t.clamp(0.0, 1.0)),
            child: child,
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  BOUTON D'ENVOI LIQUIDE
// ─────────────────────────────────────────────────────────────

/// Bouton rond d'où se DÉTACHE une goutte de liquide au moment de
/// l'envoi — la goutte s'étire hors du bouton, se sépare, puis file vers
/// le haut avant de s'effacer.
///
/// C'est le geste que l'effet de fusion rend possible : la goutte reste
/// reliée au bouton par un pont de matière qui s'amincit, puis casse.
/// Sans le filtre de fusion, on verrait juste un cercle qui s'éloigne
/// d'un autre cercle.
class LiquidSendButton extends StatefulWidget {
  const LiquidSendButton({
    super.key,
    required this.onPressed,
    required this.enabled,
    this.size = 34,
    this.color = const Color(0xFF0A84FF),
    this.icon = Icons.arrow_upward_rounded,
  });

  final VoidCallback onPressed;

  /// Quand faux, le bouton est grisé et ne réagit pas.
  final bool enabled;

  final double size;
  final Color color;
  final IconData icon;

  @override
  State<LiquidSendButton> createState() => _LiquidSendButtonState();
}

class _LiquidSendButtonState extends State<LiquidSendButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _fire() {
    if (!widget.enabled) return;
    // L'action part IMMÉDIATEMENT : l'animation accompagne l'envoi, elle
    // ne le retarde pas. Faire attendre la fin d'une animation avant
    // d'agir est la faute la plus courante — et la plus vite agaçante.
    widget.onPressed();
    _controller.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final activeColor =
        widget.enabled ? widget.color : widget.color.withValues(alpha: 0.3);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.enabled ? (_) => setState(() => _pressed = true) : null,
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        setState(() => _pressed = false);
        _fire();
      },
      child: AnimatedScale(
        // Léger enfoncement sous le doigt — le retour tactile d'iOS.
        scale: _pressed ? 0.88 : 1.0,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: SizedBox(
          // La zone dessinée dépasse largement le bouton vers le haut,
          // pour laisser la place à la goutte qui s'en échappe.
          width: widget.size,
          height: widget.size * 2.4,
          // NOTE : la zone est plus haute que le bouton, et celui-ci est
          // ancré en bas. Centrée dans une rangée, elle plaçait donc le
          // cercle NETTEMENT sous l'axe des autres commandes. C'est
          // l'appelant qui rattrape, en alignant cette zone par le bas
          // (voir la barre de saisie).
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              return LiquidMetaball(
                blur: 6,
                threshold: 40,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // La goutte qui s'échappe : elle monte, rétrécit,
                    // puis disparaît. Elle n'existe que pendant
                    // l'animation.
                    if (t > 0 && t < 1) _escapingDrop(t, activeColor),
                    // Le bouton lui-même, ancré en bas.
                    Positioned(
                      left: 0,
                      bottom: 0,
                      child: Container(
                        width: widget.size,
                        height: widget.size,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: activeColor,
                        ),
                        // ⚠️ SANS FLÈCHE, CE BOUTON EST UNE PASTILLE
                        // MUETTE.
                        //
                        // Il n'y avait ici qu'un cercle de couleur. La
                        // métaphore de la goutte qui se détache est jolie
                        // — mais elle ne se joue qu'APRÈS l'envoi. Avant
                        // le tap, l'utilisateur voit un rond bleu sans
                        // savoir ce qu'il fait, à l'endroit précis où
                        // toutes les autres messageries mettent une
                        // flèche.
                        //
                        // La flèche est dessinée DANS le cercle, donc
                        // elle participe au fondu métaballe comme le
                        // reste : elle ne se décolle pas du bouton
                        // pendant l'animation.
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.arrow_upward_rounded,
                          color: Colors.white,
                          size: widget.size * 0.58,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// La goutte qui se détache et s'envole.
  Widget _escapingDrop(double t, Color color) {
    final eased = Curves.easeOutCubic.transform(t);
    // Elle part du centre du bouton et monte d'une hauteur et demie.
    final travel = widget.size * 1.5 * eased;
    // Et rétrécit en chemin : une goutte qui se détache s'amincit, elle
    // ne garde pas son volume.
    final dropSize = widget.size * (0.62 - eased * 0.42);
    if (dropSize <= 0) return const SizedBox.shrink();

    return Positioned(
      left: (widget.size - dropSize) / 2,
      bottom: widget.size * 0.5 + travel,
      child: Opacity(
        // Elle s'efface sur la fin, une fois le pont de matière rompu.
        opacity: (1 - t).clamp(0.0, 1.0),
        child: Container(
          width: dropSize,
          height: dropSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  LOGO LIQUIDE
// ─────────────────────────────────────────────────────────────

/// Le logo de Droplet en version liquide : plusieurs gouttes qui dérivent
/// et fusionnent lentement, formant une masse en mouvement perpétuel.
///
/// Réservé aux écrans où il est le sujet principal (démarrage, accueil
/// vide) : c'est un mouvement continu, donc à proscrire à côté de contenu
/// à lire.
class LiquidLogo extends StatelessWidget {
  const LiquidLogo({
    super.key,
    this.size = 96,
    this.color = const Color(0xFF0A84FF),
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    // Trois gouttes suffisent : au-delà, la masse devient informe et on
    // ne distingue plus les fusions individuelles.
    final blobSize = size * 0.52;
    return SizedBox(
      width: size,
      height: size,
      child: LiquidMetaball(
        blur: size * 0.09,
        threshold: 30,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: size * 0.10,
              top: size * 0.20,
              child: LiquidBlob(
                size: blobSize,
                color: color,
                seed: 0,
                drift: size * 0.07,
              ),
            ),
            Positioned(
              right: size * 0.10,
              top: size * 0.16,
              child: LiquidBlob(
                size: blobSize * 0.85,
                color: color,
                seed: 1,
                drift: size * 0.08,
                speed: 0.85,
              ),
            ),
            Positioned(
              left: size * 0.26,
              bottom: size * 0.12,
              child: LiquidBlob(
                size: blobSize * 0.92,
                color: color,
                seed: 2,
                drift: size * 0.06,
                speed: 1.15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
