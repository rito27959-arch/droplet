import 'package:flutter/material.dart';

/// Les trois variantes officielles du bouton.
enum VarianteDropletId { sombre, clair, bleu }

/// Le bouton officiel « Continuer avec Droplet ID ».
class DropletIdBouton extends StatelessWidget {
  const DropletIdBouton({
    super.key,
    required this.onPressed,
    this.variante = VarianteDropletId.sombre,
    this.langue,
    this.hauteur = 48,
    this.pleineLargeur = false,
    this.chargement = false,
  });

  final VoidCallback? onPressed;
  final VarianteDropletId variante;

  /// 'fr' ou 'en' ; par défaut, la langue de l'app.
  final String? langue;
  final double hauteur;
  final bool pleineLargeur;
  final bool chargement;

  static const _encre = Color(0xFF0A1A24);
  static const _bleu = Color(0xFF0A7CFF);
  static const _bleuClair = Color(0xFF3D9BFF);

  @override
  Widget build(BuildContext context) {
    final l = langue ?? Localizations.maybeLocaleOf(context)?.languageCode ?? 'fr';
    final texte = l == 'en' ? 'Continue with Droplet ID' : 'Continuer avec Droplet ID';
    final (fond, encre, goutte, bord) = switch (variante) {
      VarianteDropletId.sombre => (_encre, Colors.white, _bleuClair, null),
      VarianteDropletId.clair => (Colors.white, _encre, _bleu, const Color(0xFFD6DEE4)),
      VarianteDropletId.bleu => (_bleu, Colors.white, Colors.white, null),
    };
    final bouton = Semantics(
      button: true,
      label: texte,
      child: Material(
        color: fond,
        shape: StadiumBorder(side: bord == null ? BorderSide.none : BorderSide(color: bord)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: chargement ? null : onPressed,
          child: SizedBox(
            height: hauteur,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisSize: pleineLargeur ? MainAxisSize.max : MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  chargement
                      ? SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2, color: goutte))
                      : CustomPaint(size: const Size(18, 18), painter: _Goutte(goutte)),
                  const SizedBox(width: 10),
                  Text(texte, style: TextStyle(color: encre, fontSize: 15, fontWeight: FontWeight.w600, letterSpacing: -0.1)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    return pleineLargeur ? SizedBox(width: double.infinity, child: bouton) : bouton;
  }
}

/// La goutte Droplet, dessinée (aucune image à embarquer).
class _Goutte extends CustomPainter {
  _Goutte(this.couleur);
  final Color couleur;

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    final p = Path()
      ..moveTo(w * 0.5, h * 0.09)
      ..cubicTo(w * 0.35, h * 0.30, w * 0.25, h * 0.45, w * 0.25, h * 0.575)
      ..arcToPoint(Offset(w * 0.75, h * 0.575), radius: Radius.circular(w * 0.25), clockwise: false)
      ..cubicTo(w * 0.75, h * 0.45, w * 0.65, h * 0.30, w * 0.5, h * 0.09)
      ..close();
    canvas.drawPath(p, Paint()..color = couleur..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_Goutte old) => old.couleur != couleur;
}
