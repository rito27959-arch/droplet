// LIRE UN CODE — par la caméra (Android, iOS, macOS), ou en collant le
// lien (partout, et quand la caméra n'est pas disponible).
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:permission_handler/permission_handler.dart';

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

/// Où en est la caméra.
enum _Camera { verification, prete, refusee, refuseeDefinitivement, erreur }

class _ScannerState extends State<_Scanner> with WidgetsBindingObserver {
  final _camera = MobileScannerController(formats: const [BarcodeFormat.qrCode], autoStart: false);
  _Camera _etat = _Camera.verification;
  bool _fini = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _verifier(demander: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera.dispose();
    super.dispose();
  }

  /// Au retour des Réglages : l'utilisateur vient peut-être d'autoriser.
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && (_etat == _Camera.refusee || _etat == _Camera.refuseeDefinitivement)) {
      _verifier(demander: false);
    }
  }

  /// Sur Android, on demande l'autorisation NOUS-MÊMES, avant d'ouvrir la
  /// caméra : un refus devient un écran clair (autoriser, ou ouvrir les
  /// Réglages si Android ne redemandera plus) au lieu d'une erreur muette.
  /// Sur iOS et macOS, le système pose la question au démarrage de la
  /// caméra.
  Future<void> _verifier({required bool demander}) async {
    if (Platform.isAndroid) {
      var statut = await Permission.camera.status;
      if (!statut.isGranted && demander) statut = await Permission.camera.request();
      if (!mounted) return;
      if (!statut.isGranted) {
        setState(() => _etat = statut.isPermanentlyDenied || statut.isRestricted ? _Camera.refuseeDefinitivement : _Camera.refusee);
        return;
      }
    }
    setState(() => _etat = _Camera.prete);
    await _demarrer();
  }

  Future<void> _demarrer() async {
    try {
      await _camera.start();
    } on MobileScannerException catch (e) {
      if (!mounted) return;
      setState(() => _etat = e.errorCode == MobileScannerErrorCode.permissionDenied ? _Camera.refuseeDefinitivement : _Camera.erreur);
    } catch (_) {
      if (mounted) setState(() => _etat = _Camera.erreur);
    }
  }

  Future<void> _reessayer() async {
    setState(() => _etat = _Camera.verification);
    try {
      await _camera.stop();
    } catch (_) {}
    await _verifier(demander: true);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final prete = _etat == _Camera.prete;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, surfaceTintColor: Colors.transparent, title: Text(context.t('scanner_code'))),
      body: Stack(
        children: [
          if (prete) ...[
            Positioned.fill(
              child: MobileScanner(
                controller: _camera,
                onDetect: (capture) {
                  final v = capture.barcodes.firstOrNull?.rawValue;
                  if (v == null || _fini) return;
                  _fini = true;
                  HapticFeedback.mediumImpact();
                  Navigator.of(context).pop(v);
                },
                errorBuilder: (context, error, _) {
                  // L'erreur arrive pendant la construction : on change
                  // d'écran au tour suivant.
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    setState(() => _etat = error.errorCode == MobileScannerErrorCode.permissionDenied ? _Camera.refuseeDefinitivement : _Camera.erreur);
                  });
                  return const ColoredBox(color: Colors.black);
                },
              ),
            ),
            // Le cadre de visée et sa consigne.
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 250,
                    height: 250,
                    decoration: BoxDecoration(borderRadius: BorderRadius.circular(34), border: Border.all(color: Colors.white, width: 3)),
                  ),
                  const SizedBox(height: 22),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                    child: Text(context.t('camera_viser'), style: Typo.secondaire.copyWith(color: Colors.white)),
                  ),
                ],
              ),
            ),
          ] else if (_etat == _Camera.verification)
            const Center(child: SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)))
          else
            _Explication(etat: _etat, accent: p.accent, onAutoriser: _reessayer),
          Positioned(
            left: 24,
            right: 24,
            bottom: 24,
            child: SafeArea(
              top: false,
              child: BoutonSecondaire(
                texte: context.t('coller_lien'),
                icone: Icons.content_paste_rounded,
                couleur: Colors.white,
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

/// Pas de caméra : pourquoi, et comment y remédier — en une action.
class _Explication extends StatelessWidget {
  const _Explication({required this.etat, required this.accent, required this.onAutoriser});

  final _Camera etat;
  final Color accent;
  final VoidCallback onAutoriser;

  @override
  Widget build(BuildContext context) {
    final definitif = etat == _Camera.refuseeDefinitivement;
    final erreur = etat == _Camera.erreur;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 140),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84,
              height: 84,
              decoration: BoxDecoration(shape: BoxShape.circle, color: accent.withValues(alpha: 0.16)),
              child: Icon(erreur ? Icons.no_photography_outlined : Icons.photo_camera_rounded, size: 40, color: accent),
            ),
            const SizedBox(height: 22),
            Text(
              context.t(erreur ? 'camera_indisponible' : 'camera_titre'),
              textAlign: TextAlign.center,
              style: Typo.titre.copyWith(color: Colors.white),
            ),
            const SizedBox(height: 10),
            Text(
              context.t(erreur ? 'camera_erreur' : (definitif ? 'camera_reglages_texte' : 'camera_refusee')),
              textAlign: TextAlign.center,
              style: Typo.secondaire.copyWith(color: Colors.white.withValues(alpha: 0.72)),
            ),
            const SizedBox(height: 26),
            BoutonLiquide(
              texte: context.t(erreur ? 'reessayer' : (definitif ? 'camera_reglages' : 'camera_autoriser')),
              icone: erreur ? Icons.refresh_rounded : (definitif ? Icons.settings_rounded : Icons.photo_camera_rounded),
              hauteur: 52,
              onTap: definitif ? () => openAppSettings() : onAutoriser,
            ),
          ],
        ),
      ),
    );
  }
}
