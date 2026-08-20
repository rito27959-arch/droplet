// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est l'écran de la CAMÉRA qui s'ouvre quand on veut scanner le QR
// code de sécurité d'un contact (voir `security_code_screen.dart`) —
// un viseur avec 4 petits coins en L (comme sur un vrai scanner de
// caméra de film), une ligne lumineuse qui monte et descend en
// attendant qu'un code soit détecté, et le cadre qui devient vert dès
// qu'un QR code est trouvé.
//
// Dès qu'un code est détecté, l'écran attend un tout petit instant
// (pour que l'utilisateur voie bien le cadre passer au vert) puis se
// referme tout seul en renvoyant le contenu du QR code à l'écran
// précédent, qui décidera si c'est le bon code ou non.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/design_tokens.dart';

/// Scanner de QR code plein écran. Retourne (via `Navigator.pop`) la valeur
/// brute du premier code détecté, ou null si l'utilisateur annule.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> with SingleTickerProviderStateMixin {
  final _controller = MobileScannerController();
  bool _handled = false;
  bool _detected = false;
  late final AnimationController _scanLine;

  @override
  void initState() {
    super.initState();
    _scanLine = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _scanLine.dispose();
    _controller.dispose();
    super.dispose();
  }

  /// Appelé par la caméra chaque fois qu'elle croit voir un QR code
  /// dans l'image — on ne traite que le TOUT PREMIER trouvé (`_handled`
  /// empêche d'en traiter un deuxième par erreur).
  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty) return;
    _handled = true;
    HapticFeedback.mediumImpact();
    setState(() => _detected = true);
    // Bref instant pour montrer le cadre confirmé en vert avant de fermer,
    // plutôt qu'une fermeture instantanée qui ne laisse aucun retour visuel.
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) Navigator.of(context).pop(raw);
    });
  }

  @override
  Widget build(BuildContext context) {
    final frameColor = _detected ? OuroColors.successGreen : OuroColors.meshBlueBright;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: OuroColors.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('Scanner le code de sécurité', style: TextStyle(color: OuroColors.textPrimary)),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          IgnorePointer(
            child: Center(
              child: SizedBox(
                width: 240,
                height: 240,
                child: Stack(
                  children: [
                    AnimatedContainer(
                      duration: DesignTokens.durationNormal,
                      decoration: BoxDecoration(
                        border: Border.all(color: frameColor.withValues(alpha: 0.5), width: 1.5),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: _detected ? DesignTokens.glow(frameColor, radius: 24) : null,
                      ),
                    ),
                    ..._corners(frameColor),
                    if (!_detected)
                      AnimatedBuilder(
                        animation: _scanLine,
                        builder: (context, _) => Positioned(
                          top: 8 + _scanLine.value * 224,
                          left: 12,
                          right: 12,
                          child: Container(
                            height: 2,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(1),
                              gradient: LinearGradient(
                                colors: [
                                  frameColor.withValues(alpha: 0),
                                  frameColor,
                                  frameColor.withValues(alpha: 0),
                                ],
                              ),
                              boxShadow: [BoxShadow(color: frameColor.withValues(alpha: 0.6), blurRadius: 6)],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(
              _detected ? 'Code détecté' : 'Cadre le QR code affiché sur l\'appareil de ton contact',
              textAlign: TextAlign.center,
              style: TextStyle(color: OuroColors.textPrimary.withValues(alpha: 0.85), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// Quatre coins en L, façon viseur de scanner — plus moderne qu'un simple
  /// cadre plein, et permet un accent de couleur bien visible.
  List<Widget> _corners(Color color) {
    const len = 26.0;
    const thickness = 3.0;
    Widget corner({required Alignment alignment, required bool top, required bool left}) {
      return Align(
        alignment: alignment,
        child: SizedBox(
          width: len,
          height: len,
          child: CustomPaint(
            painter: _CornerPainter(color: color, top: top, left: left, thickness: thickness),
          ),
        ),
      );
    }

    return [
      corner(alignment: Alignment.topLeft, top: true, left: true),
      corner(alignment: Alignment.topRight, top: true, left: false),
      corner(alignment: Alignment.bottomLeft, top: false, left: true),
      corner(alignment: Alignment.bottomRight, top: false, left: false),
    ];
  }
}

/// Dessine UN SEUL coin en forme de L, dans le bon coin et la bonne
/// orientation — les 4 appels (un par coin) forment ensemble le viseur.
class _CornerPainter extends CustomPainter {
  _CornerPainter({required this.color, required this.top, required this.left, required this.thickness});
  final Color color;
  final bool top;
  final bool left;
  final double thickness;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final path = Path();
    final y = top ? 0.0 : size.height;
    final x = left ? 0.0 : size.width;
    final vDir = top ? 1 : -1;
    final hDir = left ? 1 : -1;
    path.moveTo(x, y + vDir * size.height);
    path.lineTo(x, y);
    path.lineTo(x + hDir * size.width, y);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _CornerPainter oldDelegate) => oldDelegate.color != color;
}
