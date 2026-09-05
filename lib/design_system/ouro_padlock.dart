// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// UN CADENAS DONT L'ANSE BOUGE VRAIMENT.
//
// ── Pourquoi pas `Icons.lock_rounded` ─────────────────────────────────
//
// Parce qu'une icône ne se ferme pas : elle est REMPLACÉE. Le geste de
// verrouillage d'un enregistrement vocal — glisser le micro vers le haut
// — est progressif : à mi-chemin, on est à moitié verrouillé, et
// l'interface doit le montrer. Avec deux icônes, il ne peut rien se
// passer entre les deux : le cadenas est ouvert, puis, d'une image à
// l'autre, il est fermé. L'utilisateur n'apprend jamais que son geste
// avait un effet continu, ni où se trouve le seuil.
//
// Avec une anse qui descend au rythme du doigt, le seuil devient
// visible : on VOIT qu'il reste un centimètre à parcourir. C'est ce que
// fait WhatsApp, et c'est ce que fait iOS partout où un geste franchit un
// seuil (le tiroir de notifications, la barre de recherche qui se
// déploie, le glissement pour supprimer).
//
// ── Où il sert ────────────────────────────────────────────────────────
//
//   • bouton micro : le geste « glisser vers le haut pour verrouiller » ;
//   • indicateur Tor : anse fermée quand le circuit est établi, ouverte
//     quand il retombe — le même objet raconte les deux états, au lieu de
//     deux icônes sans rapport.
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Un cadenas dessiné, dont l'anse se lève et s'abaisse.
class OuroPadlock extends StatelessWidget {
  const OuroPadlock({
    super.key,
    required this.fermeture,
    required this.couleur,
    this.taille = 18,
    this.epaisseur = 2.0,
  });

  /// 0 = grand ouvert, 1 = fermé. Les valeurs intermédiaires sont le
  /// cœur du composant : c'est là que vit le geste.
  final double fermeture;

  final Color couleur;
  final double taille;

  /// Épaisseur de l'anse. Le corps, lui, est plein.
  final double epaisseur;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: taille,
      height: taille,
      child: CustomPaint(
        painter: _PadlockPainter(
          fermeture: fermeture.clamp(0.0, 1.0),
          couleur: couleur,
          epaisseur: epaisseur,
        ),
      ),
    );
  }
}

class _PadlockPainter extends CustomPainter {
  _PadlockPainter({
    required this.fermeture,
    required this.couleur,
    required this.epaisseur,
  });

  final double fermeture;
  final Color couleur;
  final double epaisseur;

  @override
  void paint(Canvas canvas, Size size) {
    final l = size.width;
    final h = size.height;

    // ── Le corps ─────────────────────────────────────────────────────
    // Il ne bouge jamais : c'est le point fixe qui permet de lire le
    // mouvement de l'anse.
    final corps = RRect.fromRectAndRadius(
      Rect.fromLTWH(l * 0.16, h * 0.44, l * 0.68, h * 0.50),
      Radius.circular(l * 0.14),
    );
    canvas.drawRRect(corps, Paint()..color = couleur);

    // ── L'anse ───────────────────────────────────────────────────────
    //
    // Fermée, ses deux pieds plongent DANS le corps. Ouverte, elle
    // remonte de 22 % de la hauteur et s'incline légèrement — un cadenas
    // ouvert ne reste pas droit, il pend d'un côté. C'est ce détail qui
    // fait la différence entre « une anse qui coulisse » et « un cadenas
    // qui s'ouvre ».
    final leve = (1 - fermeture) * h * 0.22;
    final inclinaison = (1 - fermeture) * 0.20;

    final rayon = l * 0.22;
    final centreAnse = Offset(l * 0.5, h * 0.40 - leve);

    canvas.save();
    // Le pivot de l'inclinaison est le pied DROIT de l'anse : c'est lui
    // qui reste engagé dans le corps le plus longtemps.
    final pivot = Offset(l * 0.5 + rayon, h * 0.46);
    canvas.translate(pivot.dx, pivot.dy);
    canvas.rotate(inclinaison);
    canvas.translate(-pivot.dx, -pivot.dy);

    final anse = Path()
      // Pied gauche : il sort du corps quand l'anse se lève.
      ..moveTo(centreAnse.dx - rayon, h * 0.50)
      ..lineTo(centreAnse.dx - rayon, centreAnse.dy)
      // Le demi-cercle du haut.
      ..arcTo(
        Rect.fromCircle(center: centreAnse, radius: rayon),
        math.pi,
        math.pi,
        false,
      )
      // Pied droit.
      ..lineTo(centreAnse.dx + rayon, h * 0.50);

    canvas.drawPath(
      anse,
      Paint()
        ..color = couleur
        ..style = PaintingStyle.stroke
        ..strokeWidth = epaisseur
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.restore();

    // ── Le trou de serrure ───────────────────────────────────────────
    // Uniquement au-dessus de 22 points : en dessous, il devient une
    // tache sale au milieu du corps plutôt qu'un détail.
    if (l >= 22) {
      final trou = Paint()..blendMode = BlendMode.clear;
      canvas.saveLayer(Offset.zero & size, Paint());
      canvas.drawRRect(corps, Paint()..color = couleur);
      canvas.drawCircle(Offset(l * 0.5, h * 0.63), l * 0.075, trou);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(l * 0.47, h * 0.63, l * 0.06, h * 0.14),
          Radius.circular(l * 0.03),
        ),
        trou,
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _PadlockPainter old) =>
      old.fermeture != fermeture ||
      old.couleur != couleur ||
      old.epaisseur != epaisseur;
}
