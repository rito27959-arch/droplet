// LA GOUTTE DE DROPLET — le logo, dessiné plutôt qu'importé : il prend la
// couleur d'accent et reste net à toutes les tailles.
//
// Même tracé que le site (viewBox 64 × 64) : la goutte, et l'onde qu'un
// message fait en arrivant.
import 'package:flutter/widgets.dart';

class Goutte extends StatelessWidget {
  const Goutte({super.key, this.taille = 28, required this.couleur});

  final double taille;
  final Color couleur;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: taille,
        child: CustomPaint(painter: _PeintreGoutte(couleur)),
      );
}

class _PeintreGoutte extends CustomPainter {
  _PeintreGoutte(this.couleur);

  final Color couleur;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 64;
    canvas.scale(k);
    // M32 6 c7.6 9.6 18 20 18 31.5 a18 18 0 0 1 -36 0 C14 26 24.4 15.6 32 6z
    final goutte = Path()
      ..moveTo(32, 6)
      ..cubicTo(39.6, 15.6, 50, 26, 50, 37.5)
      ..arcToPoint(const Offset(14, 37.5), radius: const Radius.circular(18))
      ..cubicTo(14, 26, 24.4, 15.6, 32, 6)
      ..close();
    canvas.drawPath(goutte, Paint()..color = couleur);
    canvas.drawCircle(
      const Offset(32, 38),
      6.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = const Color(0xEBFFFFFF),
    );
  }

  @override
  bool shouldRepaint(_PeintreGoutte ancien) => ancien.couleur != couleur;
}
