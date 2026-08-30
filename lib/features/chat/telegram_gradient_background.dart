// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE FOND DE DISCUSSION QUI BOUGE À CHAQUE MESSAGE ENVOYÉ — l'effet le
// plus reconnaissable de Telegram, reproduit ici à partir de l'algorithme
// qu'ils décrivent.
//
// ── Comment ça marche vraiment ────────────────────────────────────────
//
// Ce n'est PAS une image, ni une vidéo, ni un dégradé linéaire. C'est un
// « dégradé libre » calculé point par point :
//
//   • Quatre COULEURS, chacune avec un CENTRE quelque part sur l'écran.
//   • Chaque pixel prend un mélange des quatre, pondéré par sa distance
//     à chacun des centres — plus un centre est proche, plus il pèse.
//     C'est une pondération par l'inverse de la distance.
//   • Les quatre centres occupent quatre des HUIT positions réparties
//     autour de l'écran. À chaque message envoyé, tous les centres
//     avancent d'un cran, dans le sens inverse des aiguilles d'une
//     montre.
//
// Le résultat : le fond ne défile pas en boucle comme un économiseur
// d'écran. Il RÉAGIT. Envoyer un message fait doucement tourner les
// couleurs, et l'œil fait le lien entre son geste et le mouvement.
//
// ── ⚠️ Pourquoi une petite image, et pas un dessin plein écran ────────
//
// La pondération par distance demande, pour CHAQUE pixel, quatre racines
// carrées et un mélange de couleurs. En plein écran — disons 1080×2400,
// soit 2,6 millions de pixels — ce serait deux millions et demi de fois
// ce calcul, à chaque image de l'animation. Impensable sur un téléphone,
// et c'est exactement le genre de chose qui vide une batterie.
//
// On calcule donc le dégradé sur une image MINUSCULE (32×32 pixels, soit
// mille fois moins de travail), qu'on étire ensuite à la taille de
// l'écran avec un lissage. Comme un dégradé n'a par nature aucun détail
// fin, l'agrandissement ne se voit pas — c'est le même compromis que
// celui retenu par Telegram.
//
// Et le calcul n'a lieu QUE pendant les quelques centaines de
// millisecondes où les centres se déplacent. Au repos, l'image calculée
// est simplement réaffichée : coût nul.
// ============================================================================

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Les huit positions que peuvent occuper les centres de couleur.
///
/// Elles sont exprimées en fraction de l'écran (0 = bord gauche/haut,
/// 1 = bord droit/bas) et disposées en anneau, un peu écrasé
/// verticalement pour convenir à un écran de téléphone. Les valeurs
/// débordent volontairement un peu des bords : un centre de couleur posé
/// exactement dans le coin donne un dégradé qui « colle » au bord au
/// lieu de s'en échapper.
const List<Offset> _positions = [
  Offset(0.35, 0.25),
  Offset(0.72, 0.16),
  Offset(0.92, 0.42),
  Offset(0.82, 0.75),
  Offset(0.65, 0.91),
  Offset(0.28, 0.84),
  Offset(0.08, 0.58),
  Offset(0.18, 0.31),
];

/// Le fond animé d'une conversation.
///
/// [tick] est un compteur : à chaque fois qu'il augmente, les centres de
/// couleur avancent d'un cran. L'écran de discussion l'incrémente à
/// chaque message envoyé.
class TelegramGradientBackground extends StatefulWidget {
  const TelegramGradientBackground({
    super.key,
    required this.tick,
    required this.couleurs,
  });

  /// Le nombre de pas déjà effectués. Augmenter cette valeur déclenche la
  /// rotation.
  final int tick;

  /// Les quatre couleurs du dégradé.
  final List<Color> couleurs;

  @override
  State<TelegramGradientBackground> createState() =>
      _TelegramGradientBackgroundState();
}

class _TelegramGradientBackgroundState extends State<TelegramGradientBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  /// La résolution de calcul. 32×32 suffit largement — voir la note en
  /// tête de fichier.
  static const int _resolution = 32;

  /// L'image calculée, réutilisée telle quelle tant que rien ne bouge.
  ui.Image? _image;

  /// Le pas courant : quel décalage appliquer dans la liste des huit
  /// positions.
  int _pas = 0;

  /// Le calcul d'image est asynchrone ; ce drapeau évite d'en lancer un
  /// second avant que le premier n'ait rendu son résultat.
  bool _calculEnCours = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      // La durée d'un pas. Assez lent pour qu'on voie le mouvement,
      // assez court pour que deux messages envoyés coup sur coup ne
      // fassent pas la queue.
      duration: const Duration(milliseconds: 500),
    )..addListener(_rafraichir);
    _pas = widget.tick;
    _ctrl.value = 1;
    _recalculer();
  }

  @override
  void didUpdateWidget(TelegramGradientBackground old) {
    super.didUpdateWidget(old);
    if (widget.tick != old.tick) {
      _pas = widget.tick;
      // `forward(from: 0)` et non `forward()` : un second message envoyé
      // pendant que le fond bouge encore doit REPARTIR du début vers la
      // nouvelle position, pas reprendre là où il en était.
      _ctrl.forward(from: 0);
    } else if (widget.couleurs != old.couleurs) {
      _recalculer();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _image?.dispose();
    super.dispose();
  }

  /// Appelé à chaque changement de valeur du contrôleur.
  ///
  /// Sans condition sur `isAnimating` : à la toute dernière image, le
  /// contrôleur s'est déjà arrêté quand il prévient ses auditeurs. Tester
  /// `isAnimating` ferait donc sauter cette image-là, et le dégradé
  /// s'immobiliserait un cheveu avant sa position d'arrivée — décalage
  /// qui s'accumulerait message après message.
  void _rafraichir() => _recalculer();

  /// Fabrique l'image du dégradé pour l'état courant de l'animation.
  Future<void> _recalculer() async {
    if (_calculEnCours || !mounted) return;
    _calculEnCours = true;

    final t = Curves.easeInOut.transform(_ctrl.value.clamp(0.0, 1.0));
    final octets = _peindre(t);

    // `decodeImageFromPixels` évite l'encodage/décodage PNG : on donne
    // directement les octets bruts au moteur graphique.
    ui.decodeImageFromPixels(
      octets,
      _resolution,
      _resolution,
      ui.PixelFormat.rgba8888,
      (image) {
        _calculEnCours = false;
        if (!mounted) {
          image.dispose();
          return;
        }
        setState(() {
          _image?.dispose();
          _image = image;
        });
      },
    );
  }

  /// Le cœur du dégradé libre : pour chaque pixel, un mélange des quatre
  /// couleurs pondéré par l'inverse de la distance à leur centre.
  Uint8List _peindre(double t) {
    final couleurs = widget.couleurs;
    final n = couleurs.length;

    // Position de chaque centre : entre là où il était au pas précédent
    // et là où il va. Les centres sont répartis régulièrement dans
    // l'anneau des huit positions, et avancent tous ensemble.
    final centres = <Offset>[];
    for (var i = 0; i < n; i++) {
      final ecart = _positions.length ~/ n; // 2 pour quatre couleurs
      final depuis = _positions[((_pas - 1) + i * ecart) % _positions.length];
      final vers = _positions[(_pas + i * ecart) % _positions.length];
      centres.add(Offset.lerp(depuis, vers, t)!);
    }

    final octets = Uint8List(_resolution * _resolution * 4);
    var k = 0;
    for (var y = 0; y < _resolution; y++) {
      final py = (y + 0.5) / _resolution;
      for (var x = 0; x < _resolution; x++) {
        final px = (x + 0.5) / _resolution;

        double r = 0, g = 0, b = 0, sommePoids = 0;
        for (var i = 0; i < n; i++) {
          final dx = px - centres[i].dx;
          final dy = py - centres[i].dy;
          // Distance au carré. On reste au carré plutôt que de prendre
          // la racine : cela accentue la décroissance, ce qui donne des
          // taches de couleur plus franches — c'est ce qui distingue
          // l'aspect « Telegram » d'un dégradé mou et uniforme.
          //
          // Le petit terme ajouté évite la division par zéro quand un
          // pixel tombe pile sur un centre.
          final poids = 1.0 / (dx * dx + dy * dy + 0.0012);
          final c = couleurs[i];
          r += c.r * poids;
          g += c.g * poids;
          b += c.b * poids;
          sommePoids += poids;
        }

        octets[k++] = ((r / sommePoids) * 255).round().clamp(0, 255);
        octets[k++] = ((g / sommePoids) * 255).round().clamp(0, 255);
        octets[k++] = ((b / sommePoids) * 255).round().clamp(0, 255);
        octets[k++] = 255;
      }
    }
    return octets;
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) {
      // Le temps du tout premier calcul, un aplat de la première couleur
      // plutôt qu'un trou blanc.
      return ColoredBox(color: widget.couleurs.first);
    }
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _EtirementPainter(image),
      ),
    );
  }
}

/// Étire l'image de 32×32 à la taille de l'écran, avec lissage.
class _EtirementPainter extends CustomPainter {
  _EtirementPainter(this.image);

  final ui.Image image;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      // ⚠️ `FilterQuality.high` est ce qui rend l'agrandissement
      // invisible. Sans lui, on verrait les 32×32 carrés d'origine.
      Paint()..filterQuality = FilterQuality.high,
    );
  }

  @override
  bool shouldRepaint(_EtirementPainter old) => old.image != image;
}

/// Les palettes proposées.
///
/// Les valeurs sont sombres exprès : le fond passe DERRIÈRE les bulles et
/// le texte de la conversation. Un dégradé vif serait joli deux secondes
/// et illisible ensuite — c'est le piège de cet effet, et la raison pour
/// laquelle les fonds par défaut de Telegram restent eux aussi
/// désaturés.
class TelegramGradientPalettes {
  TelegramGradientPalettes._();

  /// Le fond par défaut de Droplet : les bleus du mesh, en profondeur.
  static const List<Color> mesh = [
    Color(0xFF10243A),
    Color(0xFF16374F),
    Color(0xFF0E2033),
    Color(0xFF1B3D5C),
  ];

  static const List<Color> crepuscule = [
    Color(0xFF2A1A3E),
    Color(0xFF3D2247),
    Color(0xFF1A1230),
    Color(0xFF4A2A52),
  ];

  static const List<Color> foret = [
    Color(0xFF10281F),
    Color(0xFF1A3B2C),
    Color(0xFF0C1F18),
    Color(0xFF204436),
  ];

  static const List<Color> braise = [
    Color(0xFF2E1A16),
    Color(0xFF44251C),
    Color(0xFF1F1310),
    Color(0xFF52301F),
  ];

  // ── Les mêmes ambiances, en clair ─────────────────────────────────
  //
  // ⚠️ Ce ne sont PAS les palettes sombres éclaircies au hasard. Un fond
  // clair passe derrière les mêmes bulles et le même texte foncé : il
  // doit rester assez pâle pour que le contraste tienne. Les couleurs
  // ci-dessous sont donc très désaturées — c'est aussi ce que fait
  // Telegram sur ses thèmes clairs.

  static const List<Color> meshClair = [
    Color(0xFFDCE9F5),
    Color(0xFFCBDDF0),
    Color(0xFFE6F0F8),
    Color(0xFFBFD6EC),
  ];

  static const List<Color> crepusculeClair = [
    Color(0xFFEADDF2),
    Color(0xFFDCC9EA),
    Color(0xFFF3E9F7),
    Color(0xFFD2BCE6),
  ];

  static const List<Color> foretClair = [
    Color(0xFFDDEFE2),
    Color(0xFFC9E5D4),
    Color(0xFFEBF6EE),
    Color(0xFFBCDEC9),
  ];

  static const List<Color> braiseClair = [
    Color(0xFFF7E5DA),
    Color(0xFFEFD3C2),
    Color(0xFFFBEFE7),
    Color(0xFFE9C6AE),
  ];

  // ══════════════════════════════════════════════════════════════
  //  LES CINQ PALETTES DU PACK
  // ══════════════════════════════════════════════════════════════
  //
  // ⚠️ ELLES SUIVENT LA MÊME RÈGLE QUE LES AUTRES, ET C'EST VOULU.
  //
  // La tentation, sur des fonds payants, est de les rendre plus vifs
  // que les gratuits — « on voit ce qu'on a payé ». Ce serait un piège :
  // le fond passe DERRIÈRE le texte, et un dégradé saturé rend une
  // conversation illisible au bout de trois messages. On aurait vendu
  // quelque chose qu'on finit par éteindre.
  //
  // Ce qui les distingue n'est donc pas l'intensité, mais la
  // COMPOSITION : quatre teintes qui se répondent au lieu de quatre
  // nuances d'une même couleur, et un contraste interne plus large qui
  // fait respirer le mouvement. Elles restent désaturées — comme celles
  // de Telegram, et pour la même raison.

  /// Bleu nuit traversé d'un vert d'eau : le fond le plus proche de
  /// l'identité de Droplet, en version longue.
  static const List<Color> abysse = [
    Color(0xFF071B2E),
    Color(0xFF0F3B4C),
    Color(0xFF0A2540),
    Color(0xFF14536B),
  ];

  // ── PALETTES ADAPTATIVES AU CONTENU ──────────────────────────────
  //
  // Ces palettes sont utilisées quand le thème adaptatif est actif :
  // le fond change légèrement selon le type du dernier message.

  /// Fond neutre pour messages texte — pas de couleur dominante.
  static const List<Color> texte = mesh;

  /// Fond légèrement chaud pour les photos — comme si la dernière image
  /// avait laissé sa dominante colorée sur le fond.
  static const List<Color> photo = [
    Color(0xFF1A1A2E),
    Color(0xFF2D1B3D),
    Color(0xFF151525),
    Color(0xFF3A2240),
  ];

  /// Fond avec un gradient subtil pour les vocaux — comme si la voix
  /// résonnait dans l'espace.
  static const List<Color> vocal = [
    Color(0xFF0E1A2A),
    Color(0xFF162A3A),
    Color(0xFF0A1520),
    Color(0xFF1E3545),
  ];

  /// Les ors éteints d'un coucher de soleil sur la latérite.
  static const List<Color> laterite = [
    Color(0xFF2E1A12),
    Color(0xFF4A2A18),
    Color(0xFF231410),
    Color(0xFF5C3A1E),
  ];

  /// Un violet froid piqué d'indigo — le plus « nocturne » des cinq.
  static const List<Color> nebuleuse = [
    Color(0xFF1B1436),
    Color(0xFF2E1F52),
    Color(0xFF120E28),
    Color(0xFF3D2A6B),
  ];

  /// Vert profond et bleu pétrole : lisible même en plein soleil, une
  /// fois l'écran au maximum.
  static const List<Color> palmeraie = [
    Color(0xFF0A2119),
    Color(0xFF123528),
    Color(0xFF07180F),
    Color(0xFF1B4A34),
  ];

  /// Gris chauds et cuivre : le seul presque neutre, pour qui trouve
  /// que la couleur distrait.
  static const List<Color> ardoise = [
    Color(0xFF1C1C1F),
    Color(0xFF2B2A2E),
    Color(0xFF141416),
    Color(0xFF3A3236),
  ];

  // Les mêmes, éclaircies pour le mode clair. Comme pour les gratuites,
  // ce ne sont PAS les sombres remontées en luminosité : un fond clair
  // qui garde la saturation d'un fond sombre vire au fluo.
  static const List<Color> abysseClair = [
    Color(0xFFDCEBF5),
    Color(0xFFC3DDEA),
    Color(0xFFE8F3F8),
    Color(0xFFB2D3E4),
  ];
  static const List<Color> lateriteClair = [
    Color(0xFFF6E7DA),
    Color(0xFFEBD3BE),
    Color(0xFFFBF1E8),
    Color(0xFFE0C0A3),
  ];
  static const List<Color> nebuleuseClair = [
    Color(0xFFE6E1F2),
    Color(0xFFD3CAE6),
    Color(0xFFF0ECF8),
    // ⚠️ 0xFFC2B5DC ici donnait une luminance de 0,4968 — sous le seuil
    // de 0,5 exigé par `fond_degrade_test`, et le test l'a rattrapé.
    // Un mauve juste trop sombre derrière du texte noir : invisible sur
    // un écran de bureau, illisible en plein soleil, c'est-à-dire dans
    // les conditions où cette application sert le plus.
    Color(0xFFCEC4E6),
  ];
  static const List<Color> palmeraieClair = [
    Color(0xFFDDEDE3),
    Color(0xFFC4DFD0),
    Color(0xFFECF5F0),
    Color(0xFFB0D3BE),
  ];
  static const List<Color> ardoiseClair = [
    Color(0xFFE9E7E6),
    Color(0xFFDAD6D4),
    Color(0xFFF3F1F0),
    Color(0xFFCAC4C1),
  ];

  /// Les fonds qui demandent le pack.
  ///
  /// ⚠️ UNE SEULE LISTE, et c'est délibéré. Marquer « premium » à la
  /// fois dans la grille de choix, dans l'écran d'achat et au moment
  /// d'appliquer aurait donné trois listes qui finissent par diverger —
  /// et une divergence, ici, se traduit par un fond payant offert à tout
  /// le monde, ou par un fond gratuit qu'on ne peut plus appliquer.
  static const Set<String> premium = {
    'abysse', 'laterite', 'nebuleuse', 'palmeraie', 'ardoise',
  };

  static bool estPremium(String cle) => premium.contains(cle);

  /// Toutes les palettes, dans l'ordre où elles sont proposées.
  static const Map<String, List<Color>> toutes = {
    'mesh': mesh,
    'crepuscule': crepuscule,
    'foret': foret,
    'braise': braise,
    'abysse': abysse,
    'laterite': laterite,
    'nebuleuse': nebuleuse,
    'palmeraie': palmeraie,
    'ardoise': ardoise,
    'adaptatif': mesh, // Le mode adaptatif utilise mesh par défaut
  };

  static const Map<String, List<Color>> toutesClaires = {
    'mesh': meshClair,
    'crepuscule': crepusculeClair,
    'foret': foretClair,
    'braise': braiseClair,
    'abysse': abysseClair,
    'laterite': lateriteClair,
    'nebuleuse': nebuleuseClair,
    'palmeraie': palmeraieClair,
    'ardoise': ardoiseClair,
    'adaptatif': meshClair,
  };

  static const Map<String, String> etiquettes = {
    'mesh': 'Mesh',
    'crepuscule': 'Crépuscule',
    'foret': 'Forêt',
    'braise': 'Braise',
    'abysse': 'Abysse',
    'laterite': 'Latérite',
    'nebuleuse': 'Nébuleuse',
    'palmeraie': 'Palmeraie',
    'ardoise': 'Ardoise',
    'adaptatif': 'Adaptatif',
  };

  /// La palette adaptative selon le type de contenu.
  ///
  /// En mode adaptatif, le fond change légèrement selon le type du
  /// dernier message envoyé — texte, photo, ou vocal.
  static List<Color> pourContenu(String typeContenu, {required bool sombre}) {
    return switch (typeContenu) {
      'photo' => sombre ? photo : photo,
      'audio' || 'voice' => sombre ? vocal : vocal,
      _ => sombre ? texte : texte,
    };
  }

  /// La palette correspondant à une clé, dans la bonne luminosité.
  ///
  /// Renvoie `null` si la clé ne correspond à aucune palette connue —
  /// notamment `kFondAucun`, ou une valeur enregistrée par une version
  /// antérieure de l'app.
  static List<Color>? pour(String cle, {required bool sombre}) =>
      (sombre ? toutes : toutesClaires)[cle];
}

/// Un carré de prévisualisation d'une palette, pour l'écran de choix.
///
/// Il montre le dégradé tel qu'il sera, sans animation : le mouvement se
/// juge dans la conversation, pas sur une vignette de quarante pixels.
class GradientPreview extends StatelessWidget {
  const GradientPreview({super.key, required this.couleurs, this.taille = 44});

  final List<Color> couleurs;
  final double taille;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: taille,
      height: taille,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: CustomPaint(painter: _PreviewPainter(couleurs)),
      ),
    );
  }
}

class _PreviewPainter extends CustomPainter {
  _PreviewPainter(this.couleurs);

  final List<Color> couleurs;

  @override
  void paint(Canvas canvas, Size size) {
    // Quatre halos radiaux superposés : bien plus économique qu'un vrai
    // calcul par pixel, et suffisant pour une vignette.
    canvas.drawRect(Offset.zero & size, Paint()..color = couleurs.first);
    final ecart = _positions.length ~/ couleurs.length;
    for (var i = 0; i < couleurs.length; i++) {
      final p = _positions[(i * ecart) % _positions.length];
      final centre = Offset(p.dx * size.width, p.dy * size.height);
      final rayon = size.longestSide * 0.62;
      canvas.drawCircle(
        centre,
        rayon,
        Paint()
          ..shader = ui.Gradient.radial(centre, rayon, [
            couleurs[i],
            couleurs[i].withValues(alpha: 0),
          ]),
      );
    }
  }

  @override
  bool shouldRepaint(_PreviewPainter old) => old.couleurs != couleurs;
}
