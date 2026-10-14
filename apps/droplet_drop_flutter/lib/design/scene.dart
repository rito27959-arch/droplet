// LES PIÈCES DU SITE, DANS L'APP — ce qui donne à drop.dropletmesh.app son
// allure, recréé pour de vrai :
//
//   • la MOSAÏQUE : les fichiers en tuiles colorées (les vraies photos quand
//     elles sont là), « +20 » sur la dernière ;
//   • la CONSTELLATION : vous au centre, les appareils autour, reliés par
//     des fils de lumière — la section Group Drop du site, mais vivante ;
//   • la LUEUR : le halo bleu derrière ce qui compte.
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'composants.dart';
import 'couleurs.dart';
import 'marque.dart';
import 'typo.dart';

/// Les teintes des tuiles, par type de fichier (celles du site).
const _teintes = {
  'image': [Color(0xFFFF9A5A), Color(0xFFFF4F7A)],
  'video': [Color(0xFF6A5BFF), Color(0xFF2FA8FF)],
  'audio': [Color(0xFF35D6C4), Color(0xFF168BFF)],
  'app': [Color(0xFF7BE0A0), Color(0xFF16B46C)],
  'archive': [Color(0xFFFFD86B), Color(0xFFFF8A3D)],
  'doc': [Color(0xFF8C95FF), Color(0xFF4855E8)],
};

String typeDe(String nom) {
  final ext = nom.contains('.') ? nom.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'heic' || 'heif' || 'webp' => 'image',
    'mp4' || 'mov' || 'mkv' || 'avi' || 'webm' || '3gp' => 'video',
    'mp3' || 'wav' || 'm4a' || 'flac' || 'ogg' || 'aac' => 'audio',
    'apk' => 'app',
    'zip' || 'rar' || '7z' || 'tar' || 'gz' => 'archive',
    _ => 'doc',
  };
}

IconData _icone(String type) => switch (type) {
      'image' => Icons.image_rounded,
      'video' => Icons.play_arrow_rounded,
      'audio' => Icons.music_note_rounded,
      'app' => Icons.android_rounded,
      'archive' => Icons.folder_zip_rounded,
      _ => Icons.description_rounded,
    };

/// Les fichiers en tuiles. [chemins] : les fichiers sur le disque, quand on
/// les a (les photos s'y affichent en vrai).
class Mosaique extends StatelessWidget {
  const Mosaique({super.key, required this.noms, this.chemins = const [], this.colonnes = 3, this.max = 6, this.tuile = 64});

  final List<String> noms;
  final List<String> chemins;
  final int colonnes;
  final int max;
  final double tuile;

  @override
  Widget build(BuildContext context) {
    final montres = noms.take(max).toList();
    final reste = noms.length - montres.length;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final (i, n) in montres.indexed)
          _Tuile(
            nom: n,
            chemin: i < chemins.length ? chemins[i] : null,
            taille: tuile,
            plus: i == montres.length - 1 && reste > 0 ? reste + 1 : null,
            delai: i * 50,
          ),
      ],
    );
  }
}

class _Tuile extends StatelessWidget {
  const _Tuile({required this.nom, required this.chemin, required this.taille, required this.plus, required this.delai});

  final String nom;
  final String? chemin;
  final double taille;
  final int? plus;
  final int delai;

  @override
  Widget build(BuildContext context) {
    final type = typeDe(nom);
    final c = _teintes[type]!;
    final photo = type == 'image' && chemin != null && File(chemin!).existsSync();
    return Apparition(
      delai: delai,
      child: Container(
        width: taille,
        height: taille,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(taille * 0.22),
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: c),
          boxShadow: [BoxShadow(color: c.last.withValues(alpha: 0.28), blurRadius: 14, offset: const Offset(0, 6))],
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo)
              Image.file(File(chemin!), fit: BoxFit.cover, cacheWidth: (taille * 3).round(), errorBuilder: (_, __, ___) => const SizedBox())
            else
              Icon(_icone(type), color: Colors.white.withValues(alpha: 0.92), size: taille * 0.42),
            if (plus != null)
              ColoredBox(
                color: Colors.black.withValues(alpha: 0.45),
                child: Center(child: Text('+$plus', style: Typo.titreCarte.copyWith(color: Colors.white, fontWeight: FontWeight.w700))),
              ),
          ],
        ),
      ),
    );
  }
}

/// Le halo d'accent derrière un élément (la nuit seulement).
class Lueur extends StatelessWidget {
  const Lueur({super.key, required this.child, this.rayon = 70, this.intensite = 0.4});

  final Widget child;
  final double rayon;
  final double intensite;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    if (!p.sombre) return child;
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(color: p.accent.withValues(alpha: intensite), blurRadius: rayon, spreadRadius: -rayon * 0.25)],
      ),
      child: child,
    );
  }
}

/// Un nœud de la constellation : un appareil.
class NoeudConstellation {
  const NoeudConstellation({required this.id, required this.nom, required this.plateforme, required this.empreinte, this.progression, this.fini = false});

  final String id;
  final String nom;
  final String plateforme;
  final String empreinte;

  /// Pour Group Drop : la part reçue (null : pas de transfert).
  final double? progression;
  final bool fini;
}

/// Vous au centre, les appareils autour, reliés par des fils de lumière.
/// Les fils s'animent doucement (des points qui voyagent) — sauf si
/// l'utilisateur réduit les animations.
class Constellation extends StatefulWidget {
  const Constellation({super.key, required this.centre, required this.noeuds, this.onTap, this.hauteur = 300, this.tailleNoeud = 54});

  final Widget centre;
  final List<NoeudConstellation> noeuds;
  final ValueChanged<NoeudConstellation>? onTap;
  final double hauteur;
  final double tailleNoeud;

  @override
  State<Constellation> createState() => _ConstellationState();
}

class _ConstellationState extends State<Constellation> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(seconds: 3));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduireAnimations(context) || widget.noeuds.isEmpty) {
      _a.stop();
    } else if (!_a.isAnimating) {
      _a.repeat();
    }
  }

  @override
  void didUpdateWidget(Constellation old) {
    super.didUpdateWidget(old);
    if (widget.noeuds.isEmpty) {
      _a.stop();
    } else if (!_a.isAnimating && !reduireAnimations(context)) {
      _a.repeat();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  /// Les positions : sur une ellipse, en commençant en haut, les suivants
  /// sur une seconde orbite au-delà de 8.
  List<Offset> _positions(Size s, int n) {
    final c = Offset(s.width / 2, s.height / 2);
    final l = <Offset>[];
    final premier = math.min(n, 8);
    for (var i = 0; i < n; i++) {
      final orbite = i < 8 ? 0 : 1;
      final dansOrbite = orbite == 0 ? premier : n - 8;
      final k = orbite == 0 ? i : i - 8;
      final angle = -math.pi / 2 + 2 * math.pi * k / dansOrbite + (orbite == 1 ? math.pi / dansOrbite : 0) + (dansOrbite == 2 ? math.pi / 2 : 0);
      final rx = s.width * (orbite == 0 ? 0.36 : 0.46);
      final ry = s.height * (orbite == 0 ? 0.36 : 0.46);
      l.add(c + Offset(math.cos(angle) * rx, math.sin(angle) * ry));
    }
    return l;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return SizedBox(
      height: widget.hauteur,
      child: LayoutBuilder(builder: (context, cs) {
        final s = Size(cs.maxWidth, widget.hauteur);
        final pos = _positions(s, widget.noeuds.length);
        final t = widget.tailleNoeud;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _a,
                builder: (context, _) => CustomPaint(painter: _Fils(centre: Offset(s.width / 2, s.height / 2), points: pos, phase: _a.value, couleur: p.accent, couleur2: p.accent2, sombre: p.sombre)),
              ),
            ),
            Positioned(left: s.width / 2 - 60, top: s.height / 2 - 60, width: 120, height: 120, child: Center(child: widget.centre)),
            for (final (i, n) in widget.noeuds.indexed)
              Positioned(
                left: pos[i].dx - 50,
                top: pos[i].dy - t / 2,
                width: 100,
                child: Apparition(
                  delai: i * 60,
                  child: GestureDetector(
                    onTap: widget.onTap == null ? null : () => widget.onTap!(n),
                    child: Semantics(
                      button: widget.onTap != null,
                      label: n.nom,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _TuileAppareil(noeud: n, taille: t),
                          const SizedBox(height: 6),
                          Text(n.nom, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: Typo.legende.copyWith(color: p.texte, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      }),
    );
  }
}

/// L'appareil, comme sur le site : une tuile sombre aux coins doux, son
/// icône ; un anneau de progression autour pendant Group Drop.
class _TuileAppareil extends StatelessWidget {
  const _TuileAppareil({required this.noeud, required this.taille});

  final NoeudConstellation noeud;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final tuile = Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(taille * 0.3),
        gradient: noeud.fini
            ? const LinearGradient(colors: [Color(0xFF35E0C8), Color(0xFF16B46C)])
            : LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: p.sombre ? [const Color(0xFF1C2638), const Color(0xFF0E1420)] : [Colors.white, const Color(0xFFEEF2F8)]),
        border: Border.all(color: noeud.fini ? Colors.transparent : (p.sombre ? Colors.white.withValues(alpha: 0.12) : p.trait)),
        boxShadow: [BoxShadow(color: (noeud.fini ? const Color(0xFF35E0C8) : p.accent).withValues(alpha: p.sombre ? 0.28 : 0.12), blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Icon(noeud.fini ? Icons.check_rounded : AvatarAppareil.icone(noeud.plateforme), color: noeud.fini ? Colors.white : (p.sombre ? Colors.white.withValues(alpha: 0.85) : p.accentTexte), size: taille * 0.46),
    );
    if (noeud.progression == null || noeud.fini) return tuile;
    return SizedBox(
      width: taille + 10,
      height: taille + 10,
      child: Stack(alignment: Alignment.center, children: [AnneauProgression(valeur: noeud.progression!, taille: taille + 10, epaisseur: 3), tuile]),
    );
  }
}

class _Fils extends CustomPainter {
  _Fils({required this.centre, required this.points, required this.phase, required this.couleur, required this.couleur2, required this.sombre});

  final Offset centre;
  final List<Offset> points;
  final double phase;
  final Color couleur;
  final Color couleur2;
  final bool sombre;

  @override
  void paint(Canvas canvas, Size size) {
    for (final (i, q) in points.indexed) {
      // Un fil légèrement courbé, plus lumineux près de vous.
      final milieu = Offset((centre.dx + q.dx) / 2, (centre.dy + q.dy) / 2);
      final normale = Offset(-(q.dy - centre.dy), q.dx - centre.dx) / 9;
      final controle = milieu + normale;
      final chemin = Path()
        ..moveTo(centre.dx, centre.dy)
        ..quadraticBezierTo(controle.dx, controle.dy, q.dx, q.dy);
      final pinceau = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..shader = LinearGradient(colors: [couleur.withValues(alpha: sombre ? .55 : .4), couleur2.withValues(alpha: .06)]).createShader(Rect.fromPoints(centre, q));
      canvas.drawPath(chemin, pinceau);
      // Une goutte de lumière qui voyage sur le fil.
      final k = (phase + i * 0.17) % 1.0;
      final u = 1 - k;
      final pt = centre * (u * u) + controle * (2 * u * k) + q * (k * k);
      canvas.drawCircle(pt, 6, Paint()..color = couleur2.withValues(alpha: .18 * math.sin(k * math.pi)));
      canvas.drawCircle(pt, 2.2, Paint()..color = (sombre ? Colors.white : couleur).withValues(alpha: .85 * math.sin(k * math.pi)));
    }
  }

  @override
  bool shouldRepaint(_Fils old) => old.phase != phase || old.points != points || old.couleur != couleur;
}

/// Le centre de la constellation : vous, dans un halo qui respire.
class CentreMoi extends StatelessWidget {
  const CentreMoi({super.key, this.taille = 64});

  final double taille;

  @override
  Widget build(BuildContext context) {
    return Radar(taille: taille * 1.9, child: Lueur(rayon: 60, intensite: .5, child: Goutte(taille: taille)));
  }
}
