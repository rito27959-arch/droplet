// LIRE UN CODE — par la caméra (Android, iOS, macOS), ou en collant le
// lien (partout, et quand la caméra n'est pas disponible).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/typo.dart';

bool get cameraDisponible => Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

Future<String?> scannerCode(BuildContext context) {
  if (!cameraDisponible) return collerCode(context);
  return Navigator.of(context).push<String>(MaterialPageRoute(builder: (_) => const _Scanner()));
}

Future<String?> collerCode(BuildContext context) async {
  final champ = TextEditingController();
  final presse = await Clipboard.getData('text/plain');
  // Une invitation dans le presse-papiers (lien web, ou ancien lien
  // « dropletdrop:// ») : le champ est déjà rempli.
  final copie = presse?.text?.trim() ?? '';
  if (copie.contains('/rejoindre') && copie.contains('#')) champ.text = copie;
  if (!context.mounted) return null;
  final r = await showDialog<String>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(c.t('coller_invitation')),
      content: TextField(controller: champ, autofocus: true, minLines: 1, maxLines: 4, decoration: InputDecoration(hintText: 'https://drop.dropletmesh.app/rejoindre/#…')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c), child: Text(c.t('annuler'))),
        TextButton(onPressed: () => Navigator.pop(c, champ.text.trim()), child: Text(c.t('continuer'))),
      ],
    ),
  );
  return (r == null || r.isEmpty) ? null : r;
}

class _Scanner extends StatefulWidget {
  const _Scanner();

  @override
  State<_Scanner> createState() => _ScannerState();
}

class _ScannerState extends State<_Scanner> {
  final _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode]);
  bool _fini = false;

  @override
  void dispose() {
    _camera.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: Text(context.t('scanner_code'))),
      body: Stack(
        children: [
          MobileScanner(
            controller: _camera,
            onDetect: (capture) {
              final v = capture.barcodes.firstOrNull?.rawValue;
              if (v == null || _fini) return;
              _fini = true;
              HapticFeedback.mediumImpact();
              Navigator.of(context).pop(v);
            },
            errorBuilder: (context, error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(context.t('camera_indisponible'), textAlign: TextAlign.center, style: Typo.corps.copyWith(color: Colors.white)),
              ),
            ),
          ),
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(32), border: Border.all(color: p.accent2, width: 3)),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 32,
            child: SafeArea(
              child: BoutonSecondaire(
                texte: context.t('coller_lien'),
                icone: Icons.content_paste_rounded,
                onTap: () async {
                  final v = await collerCode(context);
                  if (v != null && context.mounted) Navigator.of(context).pop(v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
