// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Écran d'affichage du QR code de cet appareil.
//
// Permet à l'utilisateur de montrer son QR code à un contact pour
// l'ajouter comme contact Tor. Le QR code contient l'ID, le pseudo,
// la clé publique et l'adresse .onion.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/services/qr_code_exchange.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';

class QrGeneratorScreen extends StatefulWidget {
  const QrGeneratorScreen({super.key});

  @override
  State<QrGeneratorScreen> createState() => _QrGeneratorScreenState();
}

class _QrGeneratorScreenState extends State<QrGeneratorScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  String? _qrData;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _generateQr();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _generateQr() async {
    try {
      final data = await QrCodeExchange.generateQrData();
      if (mounted) {
        setState(() {
          _qrData = data;
          _loading = false;
        });
        _fadeController.forward();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _copyToClipboard() {
    if (_qrData == null) return;
    Clipboard.setData(ClipboardData(text: _qrData!));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR code copié dans le presse-papiers'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = StorageService.currentUser;

    return OuroLargeTitleScaffold(
      title: 'Mon QR Code',
      backgroundColor: OuroColors.systemGroupedBackground,
      leading: const OuroBackButton(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: DesignTokens.screenMargin),
            child: Column(
              children: [
                const SizedBox(height: DesignTokens.space8),

                // ── Avatar + Pseudo ─────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: OuroColors.secondarySystemGroupedBackground,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    children: [
                      // Avatar
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              OuroColors.accent,
                              OuroColors.accent.withValues(alpha: 0.7),
                            ],
                          ),
                        ),
                        child: Center(
                          child: Text(
                            (me?.pseudo ?? '—')[0].toUpperCase(),
                            style: OuroTypography.largeTitle.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        me?.pseudo ?? '—',
                        style: OuroTypography.title2,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Scannez ce QR code pour vous connecter',
                        style: OuroTypography.subheadline.copyWith(
                          color: OuroColors.secondaryLabel,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: DesignTokens.space6),

                // ── QR Code ────────────────────────────────────────
                if (_loading)
                  const SizedBox(
                    width: 240,
                    height: 240,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else if (_qrData != null)
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: _qrData!,
                        version: QrVersions.auto,
                        size: 200,
                        backgroundColor: Colors.white,
                      ),
                    ),
                  ),

                const SizedBox(height: DesignTokens.space6),

                // ── Bouton copier ──────────────────────────────────
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _copyToClipboard,
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copier le code'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: DesignTokens.space6),

                // ── Instructions ───────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: OuroColors.secondarySystemGroupedBackground,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.info_outline_rounded,
                              size: 16, color: OuroColors.secondaryLabel),
                          const SizedBox(width: 8),
                          Text(
                            'Comment ça marche',
                            style: OuroTypography.subheadline.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '1. Montrez ce QR code à votre contact\n'
                        '2. Il le scanne depuis son écran Tor\n'
                        '3. Vous êtes connectés via Tor',
                        style: OuroTypography.footnote.copyWith(
                          color: OuroColors.secondaryLabel,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: DesignTokens.space8),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
