// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'ANIMATION D'ENVOI DE TELEGRAM : au moment où l'on appuie sur envoyer,
// le texte ne disparaît pas de la barre de saisie pour réapparaître
// ailleurs. Il DÉCOLLE — il prend la forme d'une bulle en chemin, et il
// file en arc de cercle jusqu'à sa place en bas de la conversation.
//
// ── Pourquoi ça change tout ───────────────────────────────────────────
//
// Dans presque toutes les messageries, envoyer un message est une
// COUPURE : le champ se vide d'un coup, et une bulle apparaît d'un coup
// plus bas. Rien ne relie les deux. L'utilisateur doit refaire le lien
// dans sa tête — « c'est bien mon message, celui-là ».
//
// Telegram supprime cette coupure. L'objet à l'écran est le même du
// début à la fin, il ne fait que se déplacer. C'est le principe de
// continuité qu'Apple applique à ses transitions, appliqué ici au geste
// le plus répété de toute l'application.
//
// ── ⚠️ Pourquoi ce n'est PAS un `Hero` ────────────────────────────────
//
// Le mécanisme intégré de Flutter pour ce genre d'effet (`Hero`) ne
// fonctionne qu'entre deux ROUTES — deux pages différentes. Ici, tout se
// passe sur le même écran : la barre de saisie et la liste sont
// simultanément à l'écran, et la bulle d'arrivée n'existe même pas
// encore au moment du décollage (le message n'a pas fini d'être
// enregistré).
//
// On fait donc voler une COPIE, posée dans l'`Overlay` par-dessus tout
// le reste, entre deux rectangles mesurés à la volée.
//
// ── ⚠️ LES TROIS DÉFAUTS QUI ONT ÉTÉ CORRIGÉS, ET POURQUOI ───────────
//
// La première version faisait bien voler quelque chose, mais elle ratait
// l'effet. Trois raisons, toutes visibles à l'œil nu sur l'appareil :
//
//   1. **LA DOUBLE BULLE.** Le vrai message était inséré dans la liste
//      immédiatement, donc pendant toute la durée du vol on voyait la
//      bulle d'arrivée DÉJÀ POSÉE à sa place, pendant qu'une copie
//      volait vers elle. Or c'est exactement ce que l'effet est censé
//      cacher. La copie ne « devenait » rien : elle rejoignait un
//      doublon. Corrigé par [onRevele] : la conversation garde sa
//      dernière bulle invisible jusqu'aux dernières images du vol, et
//      la copie s'efface par-dessus elle. Le raccord ne se voit pas
//      parce qu'au moment où il se produit, les deux objets sont
//      superposés.
//
//   2. **LE PAVÉ BLEU AU DÉCOLLAGE.** La copie naissait déjà en bulle —
//      fond accent plein, texte blanc — à l'emplacement du champ de
//      saisie. Le premier tiers de l'animation était donc un rectangle
//      bleu qui recouvrait brutalement la barre. La copie part
//      désormais exactement dans l'état où était le texte : SANS FOND,
//      dans la couleur du champ, avec les marges du champ. Le fond
//      accent et le blanc n'arrivent que pendant le vol. Ce qui décolle
//      ressemble à ce qui était là ; c'est toute la condition de la
//      continuité.
//
//   3. **L'ARRIVÉE MOLLE.** Un `easeOutCubic` se pose sans rien dire.
//      Telegram atterrit avec un RESSORT : la bulle dépasse sa place de
//      très peu, puis y revient. C'est ce dépassement minuscule qui
//      donne le sentiment d'une masse lancée plutôt que d'une
//      interpolation. Voir [_CourbeAtterrissage].
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fait voler une copie du message de la barre de saisie vers la liste.
class SendFlight {
  SendFlight._();

  /// Combien de temps dure le vol.
  ///
  /// Volontairement court. Une animation d'envoi trop longue devient
  /// pénible dès le dixième message — et on en envoie des centaines.
  /// 460 ms laisse tout juste la place au ressort d'arrivée ; en deçà,
  /// le rebond n'est plus perceptible et autant ne pas le mettre.
  static const Duration duree = Duration(milliseconds: 460);

  /// L'instant du vol où la VRAIE bulle doit redevenir visible.
  ///
  /// Exposé parce que l'écran de discussion en a besoin : c'est lui qui
  /// masque sa dernière bulle, et il doit savoir jusqu'à quand. En
  /// faire une constante partagée évite que les deux durées se mettent
  /// à diverger au premier réglage.
  static const double fractionRevelation = 0.86;

  /// Lance le vol. Renvoie `false` si rien n'a pu décoller.
  ///
  /// [depuis] est la boîte de texte de la barre de saisie ; [zoneListe]
  /// est la zone occupée par la conversation. Si l'une des deux ne peut
  /// pas être mesurée — l'écran a changé entre-temps, la liste n'est pas
  /// encore construite — on renonce silencieusement : rater l'animation
  /// ne doit jamais empêcher d'envoyer un message.
  ///
  /// [onRevele] est appelé aux dernières images, quand la vraie bulle
  /// doit reparaître sous la copie. [onFini] n'est pas exposé : la
  /// copie se retire toute seule.
  ///
  /// ⚠️ Les quatre paramètres de géométrie ([paddingDepart],
  /// [paddingArrivee], [rayonArrivee], [largeurMaxBulle]) ne sont PAS
  /// des réglages décoratifs : ils doivent valoir exactement ce que
  /// valent le champ de saisie et la bulle réelle. C'est pour ça qu'ils
  /// sont passés depuis l'écran plutôt que recopiés ici — une constante
  /// recopiée finit toujours par diverger de son original, et ici la
  /// divergence se voit sous forme de saut à l'atterrissage.
  static bool lancer({
    required BuildContext context,
    required GlobalKey depuis,
    required GlobalKey zoneListe,
    required String texte,
    required Color couleurBulle,
    required TextStyle styleTexte,
    required Color couleurTexteDepart,
    required EdgeInsets paddingDepart,
    required EdgeInsets paddingArrivee,
    required BorderRadius rayonArrivee,
    required double largeurMaxBulle,
    VoidCallback? onRevele,
  }) {
    final depart = _rectDe(depuis);
    final zone = _rectDe(zoneListe);
    if (depart == null || zone == null) return false;

    final arrivee = _ouLaBulleVaSePoser(
      zone: zone,
      texte: texte,
      style: styleTexte,
      padding: paddingArrivee,
      largeurMax: largeurMaxBulle,
      echelle: MediaQuery.textScalerOf(context),
    );

    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) return false;

    late OverlayEntry entree;
    entree = OverlayEntry(
      builder: (_) => _BulleEnVol(
        depart: depart,
        arrivee: arrivee,
        texte: texte,
        couleurBulle: couleurBulle,
        styleTexte: styleTexte,
        couleurTexteDepart: couleurTexteDepart,
        paddingDepart: paddingDepart,
        paddingArrivee: paddingArrivee,
        rayonArrivee: rayonArrivee,
        onRevele: onRevele,
        onFini: entree.remove,
      ),
    );
    overlay.insert(entree);
    return true;
  }

  /// Estime le rectangle qu'occupera la vraie bulle, en bas à droite de
  /// la conversation.
  ///
  /// ⚠️ POURQUOI UNE ESTIMATION ET NON UNE MESURE.
  ///
  /// Au moment où l'utilisateur lève le doigt du bouton d'envoi, la
  /// bulle d'arrivée N'EXISTE PAS ENCORE : le message n'est ni chiffré,
  /// ni enregistré, ni ajouté à la liste. Il n'y a donc rien à mesurer.
  ///
  /// On refait donc ici le même calcul de mise en page que fera la
  /// bulle : on met le texte en page avec le même style, les mêmes
  /// marges et la même largeur maximale, et on en déduit la taille. Le
  /// résultat n'est pas au pixel près — la vraie bulle porte en plus une
  /// heure et une coche — mais l'écart ne se joue plus que sur les
  /// dernières images, celles où la copie s'efface par-dessus la vraie.
  static Rect _ouLaBulleVaSePoser({
    required Rect zone,
    required String texte,
    required TextStyle style,
    required EdgeInsets padding,
    required double largeurMax,
    required TextScaler echelle,
  }) {
    // La marge latérale de la liste, et la marge basse jusqu'au dernier
    // message. Elles suivent le `padding` de la `ListView`.
    const margeListe = 12.0;
    const margeBasse = 10.0;

    final peintre = TextPainter(
      text: TextSpan(text: texte, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 3,
      ellipsis: '…',
      textScaler: echelle,
    )..layout(maxWidth: largeurMax - padding.horizontal);

    final largeur = peintre.width + padding.horizontal;
    final hauteur = peintre.height + padding.vertical;
    peintre.dispose();

    // Collée en bas à droite de la zone : c'est là que se pose un
    // message qu'on vient d'envoyer, une fois le défilement terminé.
    return Rect.fromLTWH(
      zone.right - margeListe - largeur,
      zone.bottom - margeBasse - hauteur,
      largeur,
      hauteur,
    );
  }

  /// Le rectangle occupé par un widget, en coordonnées d'écran.
  static Rect? _rectDe(GlobalKey cle) {
    final rendu = cle.currentContext?.findRenderObject();
    if (rendu is! RenderBox || !rendu.hasSize) return null;
    final origine = rendu.localToGlobal(Offset.zero);
    return origine & rendu.size;
  }
}

/// L'arrivée en ressort : la bulle dépasse sa place de très peu, puis y
/// revient.
///
/// ⚠️ CE DÉPASSEMENT EST LE CŒUR DE L'EFFET, ET IL DOIT RESTER MINUSCULE.
///
/// C'est l'oscillation d'un ressort amorti, la même équation que celle
/// d'une masse au bout d'un ressort qu'on lâche. Deux réglages :
///
///   • [_pulsation] — la vitesse à laquelle il rejoint sa cible ;
///   • [_amortissement] — combien il freine. À 1, il arrive sans jamais
///     dépasser (« critique ») ; plus bas, il rebondit.
///
/// À 0,78 le dépassement culmine autour de **2 %** de la distance
/// parcourue. C'est délibérément peu : sur un trajet de 400 points, cela
/// fait huit points de dépassement — assez pour que le geste se sente,
/// trop peu pour qu'on puisse le nommer. Les valeurs qui « font joli »
/// en isolation (5 %, 8 %) donnent un rebond de dessin animé, qu'on
/// remarque au troisième message et qui agace au trentième. Sur un geste
/// répété des centaines de fois par jour, la bonne dose d'animation est
/// celle qu'on ne voit pas.
///
/// Un détail rassurant : l'équation ne retombe pas EXACTEMENT sur 1 à la
/// dernière image (il reste deux millièmes d'oscillation). C'est sans
/// conséquence, parce que `Curve.transform` court-circuite les deux
/// extrémités et renvoie 0 et 1 tels quels — la bulle finit donc
/// rigoureusement à sa place.
class _CourbeAtterrissage extends Curve {
  const _CourbeAtterrissage();

  static const double _pulsation = 8.0;
  static const double _amortissement = 0.78;

  @override
  double transformInternal(double t) {
    const z = _amortissement;
    const w = _pulsation;
    final wd = w * math.sqrt(1 - z * z);
    return 1 -
        math.exp(-z * w * t) *
            (math.cos(wd * t) + (z * w / wd) * math.sin(wd * t));
  }
}

class _BulleEnVol extends StatefulWidget {
  const _BulleEnVol({
    required this.depart,
    required this.arrivee,
    required this.texte,
    required this.couleurBulle,
    required this.styleTexte,
    required this.couleurTexteDepart,
    required this.paddingDepart,
    required this.paddingArrivee,
    required this.rayonArrivee,
    required this.onRevele,
    required this.onFini,
  });

  final Rect depart;
  final Rect arrivee;
  final String texte;
  final Color couleurBulle;
  final TextStyle styleTexte;
  final Color couleurTexteDepart;
  final EdgeInsets paddingDepart;
  final EdgeInsets paddingArrivee;
  final BorderRadius rayonArrivee;
  final VoidCallback? onRevele;
  final VoidCallback onFini;

  @override
  State<_BulleEnVol> createState() => _BulleEnVolState();
}

class _BulleEnVolState extends State<_BulleEnVol>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  /// La révélation de la vraie bulle n'a lieu qu'UNE fois — le ressort
  /// d'arrivée peut faire repasser la valeur sous le seuil.
  bool _revele = false;

  static const _courbeVol = _CourbeAtterrissage();

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: SendFlight.duree);
    _ctrl.addListener(_peutEtreReveler);
    _ctrl.forward().whenComplete(() {
      // Ceinture et bretelles : si l'animation est coupée court, la
      // conversation ne doit JAMAIS rester avec une bulle invisible.
      _peutEtreReveler(force: true);
      widget.onFini();
    });
  }

  void _peutEtreReveler({bool force = false}) {
    if (_revele) return;
    if (!force && _ctrl.value < SendFlight.fractionRevelation) return;
    _revele = true;
    widget.onRevele?.call();
  }

  @override
  void dispose() {
    // L'écran a pu disparaître en plein vol (retour arrière, changement
    // de conversation). Le masquage ne doit pas lui survivre.
    _peutEtreReveler(force: true);
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // ⚠️ LES DEUX ENVELOPPES CI-DESSOUS SONT INDISPENSABLES, et chacune
    // a corrigé un défaut bien visible.
    //
    // `Stack` — sans lui, le `Positioned` plus bas n'a aucun effet. Un
    // `Positioned` n'est pas un widget de mise en page autonome : il ne
    // fait que déposer des coordonnées à l'intention d'un `Stack`
    // parent. Placé dans un `Overlay` sans `Stack` au-dessus, il est
    // ignoré, et la bulle prend alors TOUTE la place qu'on lui offre —
    // c'est-à-dire l'écran entier, en bleu.
    //
    // `Material` — sans lui, le texte de la bulle s'affiche avec le
    // style de secours de Flutter : soulignement double et jaune. Un
    // `Text` a besoin d'un `Material` ancêtre pour hériter d'un style
    // par défaut, et une entrée d'`Overlay` posée à la racine n'en a
    // pas. `MaterialType.transparency` en fournit un sans peindre le
    // moindre pixel.
    return IgnorePointer(
      child: Material(
        type: MaterialType.transparency,
        child: Stack(children: [_vol()]),
      ),
    );
  }

  Widget _vol() {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;

        // ── TROIS HORLOGES, ET C'EST DÉLIBÉRÉ ─────────────────────
        //
        // Le DÉPLACEMENT suit le ressort : il file, dépasse de deux
        // pour cent, revient. C'est lui qui porte le geste.
        //
        // La MÉTAMORPHOSE (largeur, hauteur, marges, arrondis) est
        // bouclée aux deux tiers du vol. Une bulle qui finirait encore
        // de changer de forme en se posant donnerait deux mouvements
        // concurrents à lire en même temps ; ici elle prend sa forme
        // en chemin, puis ne fait plus que voyager.
        //
        // La TEINTURE (le fond accent qui apparaît, le texte qui passe
        // au blanc) est bouclée au premier tiers, et c'est ce qui règle
        // le problème du pavé bleu : au décollage il n'y a pas de
        // bulle, juste le texte tel qu'il était dans le champ.
        final avance = _courbeVol.transform(t);
        final forme = Curves.easeInOutCubic.transform((t / 0.62).clamp(0.0, 1.0));
        final teinte = Curves.easeOutCubic.transform((t / 0.30).clamp(0.0, 1.0));

        final rect = _positionSur(avance, forme);

        // La copie s'efface sur les toutes dernières images, pendant
        // que la vraie bulle reparaît dessous. Trop tôt, on voit un
        // blanc ; trop tard, on voit les deux.
        const seuil = SendFlight.fractionRevelation;
        final opacite = t < seuil ? 1.0 : (1 - t) / (1 - seuil);

        final padding = EdgeInsets.lerp(
          widget.paddingDepart,
          widget.paddingArrivee,
          forme,
        )!;

        return Positioned(
          left: rect.left,
          top: rect.top,
          width: rect.width,
          height: rect.height,
          child: Opacity(
            opacity: opacite.clamp(0.0, 1.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                // Le fond n'existe pas encore au décollage.
                color: Color.lerp(
                  widget.couleurBulle.withValues(alpha: 0),
                  widget.couleurBulle,
                  teinte,
                ),
                borderRadius: BorderRadius.lerp(
                  // Le champ de saisie vit dans une pilule ; la bulle a
                  // ses propres arrondis. On part donc d'un arrondi de
                  // pilule, même s'il est invisible les premières
                  // images — sinon l'arrondi se met en place APRÈS le
                  // fond, et on voit brièvement un rectangle à angles
                  // droits.
                  BorderRadius.circular(20),
                  widget.rayonArrivee,
                  forme,
                ),
              ),
              child: Padding(
                padding: padding,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    widget.texte,
                    style: widget.styleTexte.copyWith(
                      // Le texte part dans la couleur du champ de
                      // saisie et devient blanc en même temps que le
                      // fond bleu arrive. Les deux doivent aller
                      // ensemble : du blanc sur un fond pas encore
                      // posé serait illisible une demi-seconde.
                      color: Color.lerp(
                        widget.couleurTexteDepart,
                        widget.styleTexte.color,
                        teinte,
                      ),
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Où se trouve la bulle à cet instant du vol.
  Rect _positionSur(double avance, double forme) {
    final d = widget.depart;
    final a = widget.arrivee;

    // Le centre suit une courbe de Bézier quadratique. Le point de
    // contrôle est placé à mi-chemin, mais décalé vers le HAUT et vers
    // la droite : c'est ce décalage qui transforme un glissement en un
    // lancer.
    //
    // ⚠️ `avance` peut dépasser 1 (le ressort). La formule de Bézier
    // l'accepte sans broncher : elle prolonge simplement la courbe dans
    // la direction du vol. C'est exactement le dépassement voulu — la
    // bulle continue sur sa lancée avant de revenir se poser.
    final debut = d.center;
    final fin = a.center;
    final controle = Offset(
      (debut.dx + fin.dx) / 2 + (fin.dx - debut.dx).abs() * 0.18,
      // Le creux de l'arc, proportionnel à la distance parcourue : un
      // vol court ne doit pas décrire la même boucle qu'un vol long.
      (debut.dy + fin.dy) / 2 - (debut.dy - fin.dy).abs() * 0.35 - 24,
    );

    final u = 1 - avance;
    final centre = Offset(
      u * u * debut.dx + 2 * u * avance * controle.dx + avance * avance * fin.dx,
      u * u * debut.dy + 2 * u * avance * controle.dy + avance * avance * fin.dy,
    );

    final largeur = _entre(d.width, a.width, forme);
    final hauteur = _entre(d.height, a.height, forme);

    return Rect.fromCenter(center: centre, width: largeur, height: hauteur);
  }

  /// Interpolation linéaire, nommée à part pour que la formule ci-dessus
  /// reste lisible.
  static double _entre(double a, double b, double t) => a + (b - a) * t;
}
