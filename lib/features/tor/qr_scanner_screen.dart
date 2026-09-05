// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Écran de scan de QR code pour ajouter un contact Tor.
//
// Utilise `mobile_scanner` pour scanner le QR code d'un contact.
// Le QR code contient l'ID, le pseudo, la clé publique et l'adresse .onion.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../core/services/qr_code_exchange.dart';
import '../../core/providers/tor_providers.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/ouro_scaffold.dart';

class QrScannerScreen extends ConsumerStatefulWidget {
  const QrScannerScreen({super.key});

  @override
  ConsumerState<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends ConsumerState<QrScannerScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  MobileScannerController? _scannerController;
  bool _processed = false;
  QrPeerData? _scannedPeer;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnimation = CurvedAnimation(
      parent: _animController,
      // ⚠️ C'ÉTAIT `Curves.elasticOut`. Le cadre de visée d'un scanner
      // doit se poser là où l'on vise, pas osciller autour.
      curve: DesignTokens.curveEnter,
    );
    _scannerController = MobileScannerController(
      detectionSpeed: DetectionSpeed.normal,
      facing: CameraFacing.back,
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_processed) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      if (!QrCodeExchange.isDropletOnionQr(raw)) continue;

      final peerData = QrPeerData.decode(raw);
      if (peerData == null) continue;

      // QR valide trouvé !
      _processed = true;
      _scannerController?.stop();

      setState(() => _scannedPeer = peerData);
      _animController.forward();

      // Traiter le peer.
      QrCodeExchange.processScannedQr(raw);

      break;
    }
  }

  void _confirmAdd() {
    if (_scannedPeer == null) return;

    // Retourner les données du peer scanné.
    Navigator.of(context).pop(_scannedPeer);
  }

  void _scanAgain() {
    setState(() {
      _processed = false;
      _scannedPeer = null;
    });
    _animController.reset();
    _scannerController?.start();
  }

  @override
  Widget build(BuildContext context) {
    final torConnected = ref.watch(torConnectedProvider);

    return OuroLargeTitleScaffold(
      title: 'Scanner',
      backgroundColor: Colors.black,
      leading: const OuroBackButton(color: Colors.white),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Column(
            children: [
              // ── Zone de scan ──────────────────────────────────────
              Expanded(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Caméra
                    if (_scannerController != null)
                      MobileScanner(
                        controller: _scannerController!,
                        onDetect: _onDetect,
                      ),

                    // Overlay de scan
                    if (!_processed)
                      Container(
                        width: 260,
                        height: 260,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: OuroColors.accent.withValues(alpha: 0.8),
                            width: 3,
                          ),
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),

                    // Animation de succès
                    if (_processed && _scannedPeer != null)
                      ScaleTransition(
                        scale: _scaleAnimation,
                        child: Container(
                          width: 100,
                          height: 100,
                          decoration: BoxDecoration(
                            color: Colors.green,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.green.withValues(alpha: 0.4),
                                blurRadius: 30,
                                spreadRadius: 5,
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 50,
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              // ── Panneau inférieur ────────────────────────────────
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: OuroColors.secondarySystemGroupedBackground,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(20),
                  ),
                ),
                child: _scannedPeer != null
                    ? _buildSuccessPanel()
                    : _buildScanningPanel(torConnected),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScanningPanel(bool torConnected) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Indicateur Tor
        if (!torConnected)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded,
                    color: Colors.red, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Tor n\'est pas actif. Activez-le dans Réglages > Tor.',
                    style: OuroTypography.subheadline.copyWith(
                      color: Colors.red,
                    ),
                  ),
                ),
              ],
            ),
          ),

        Text(
          'Placez le QR code dans le cadre',
          style: OuroTypography.title3.copyWith(color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          'Le QR code doit être celui d\'un contact Droplet',
          style: OuroTypography.subheadline.copyWith(
            color: OuroColors.secondaryLabel,
          ),
        ),
      ],
    );
  }

  Widget _buildSuccessPanel() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Contact scopé !',
          style: OuroTypography.title2.copyWith(color: Colors.green),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: OuroColors.systemGray6,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: OuroColors.accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    _scannedPeer!.pseudo[0].toUpperCase(),
                    style: OuroTypography.body.copyWith(
                      color: OuroColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _scannedPeer!.pseudo,
                      style: OuroTypography.body.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      '${_scannedPeer!.onionAddress.substring(0, 16)}…',
                      style: OuroTypography.caption1.copyWith(
                        color: OuroColors.secondaryLabel,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _scanAgain,
                child: const Text('Scanner un autre'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: _confirmAdd,
                child: const Text('Ajouter'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
