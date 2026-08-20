// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Droplet chiffre les messages de bout en bout — mais comment être VRAIMENT
// sûr que la « clé » utilisée pour parler à un contact est bien la
// sienne, et pas celle de quelqu'un qui se ferait passer pour lui
// (une attaque appelée « homme du milieu ») ? Cet écran permet de
// VÉRIFIER ça en personne : Droplet calcule un long numéro (le « code
// de sécurité »/« safety number », la même idée que sur WhatsApp/Signal)
// à partir des deux clés secrètes des deux téléphones. Si les DEUX
// personnes voient exactement le même numéro sur leurs écrans (soit en
// le lisant à voix haute, soit en scannant le QR code de l'autre), c'est
// la preuve que la connexion est bien sécurisée entre elles deux, sans
// personne qui écoute au milieu.
//
// Analogie : c'est comme deux amis qui comparent chacun un même mot de
// passe secret écrit sur un bout de papier — s'ils correspondent
// exactement, ils savent qu'ils parlent bien l'un à l'autre et pas à un
// imposteur.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../core/models/mesh_message.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/crypto_service.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_spinner.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/success_seal.dart';
import 'qr_scan_screen.dart';
import '../../shared/widgets/scene_animee.dart';

/// Code de sécurité (vérification hors-bande des clés, façon WhatsApp/Signal)
/// pour une conversation 1:1 : nombre à 60 chiffres + QR code, à comparer ou
/// scanner en personne avec le contact pour sortir du Trust-On-First-Use.
class SecurityCodeScreen extends ConsumerStatefulWidget {
  const SecurityCodeScreen({super.key, required this.peerId});
  final String peerId;

  @override
  ConsumerState<SecurityCodeScreen> createState() => _SecurityCodeScreenState();
}

class _SecurityCodeScreenState extends ConsumerState<SecurityCodeScreen> {
  String? _code;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _computeCode();
  }

  String? _peerPublicKey() {
    for (final p in ref.read(meshPeerListProvider)) {
      if (p.peerId == widget.peerId && p.publicKey != null) return p.publicKey;
    }
    return StorageService.getPeerRecord(widget.peerId)?.publicKey;
  }

  /// Calcule le fameux code de sécurité à partir de MA clé publique et
  /// de celle du contact — le même calcul, fait des deux côtés, donne
  /// toujours exactement le même résultat.
  Future<void> _computeCode() async {
    final myId = ref.read(meshRepositoryProvider).myId;
    final myPublicKey = StorageService.currentUser?.publicKey;
    final peerPublicKey = _peerPublicKey();
    if (myPublicKey == null || peerPublicKey == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    final code = await CryptoService.computeSafetyNumber(
      myId: myId,
      myPublicKey: myPublicKey,
      peerId: widget.peerId,
      peerPublicKey: peerPublicKey,
    );
    if (!mounted) return;
    setState(() {
      _code = code;
      _loading = false;
    });
  }

  /// Ouvre l'appareil photo pour scanner le QR code du contact, puis
  /// vérifie que la clé qu'il contient correspond bien à celle qu'on
  /// connaissait déjà pour ce pair — c'est ça, la vraie vérification.
  Future<void> _scan() async {
    final raw = await Navigator.of(context).push<String>(
      CupertinoPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (raw == null || !mounted) return;

    String? scannedId;
    String? scannedKey;
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      scannedId = decoded['id'] as String?;
      scannedKey = decoded['pk'] as String?;
    } catch (_) {
      _showResult('QR code invalide', success: false);
      return;
    }

    final knownPeerKey = _peerPublicKey();
    if (scannedId != widget.peerId || scannedKey == null || scannedKey != knownPeerKey) {
      _showResult('Ce n\'est pas le bon code — la clé ne correspond pas', success: false);
      return;
    }

    final pseudo = ref.read(peerPseudoProvider(widget.peerId));
    final existing = StorageService.getPeerRecord(widget.peerId);
    final record = (existing ??
            PeerRecord(peerId: widget.peerId, pseudo: pseudo, lastSeen: DateTime.now()))
        .copyWith(verified: true, verifiedPublicKey: scannedKey, publicKey: scannedKey);
    await StorageService.upsertPeer(record);
    if (!mounted) return;
    setState(() {});
    // Moment de confiance le plus important de l'app : un sceau plein écran
    // au lieu d'un simple toast, cohérent avec l'enjeu de la vérification.
    unawaited(SuccessSeal.show(context,
        icon: Icons.verified_rounded,
        emoji: Scenes.identiteVerifiee,
        message: 'Code vérifié'));
  }

  void _showResult(String message, {required bool success}) {
    // Retour haptique distinct sur l'échec — absent jusqu'ici, alors que
    // c'est le seul signal immédiat sur une vérification ratée.
    if (!success) HapticFeedback.heavyImpact();
    ref.read(toastProvider.notifier).show(
          message,
          type: success ? DropletToastType.success : DropletToastType.error,
        );
  }

  @override
  Widget build(BuildContext context) {
    final peerPseudo = ref.watch(peerPseudoProvider(widget.peerId));
    final peerRecord = StorageService.getPeerRecord(widget.peerId);
    final verified = peerRecord?.isVerifiedAndCurrent ?? false;
    final keyChanged = peerRecord?.keyChangedSinceVerification ?? false;

    final me = StorageService.currentUser;
    final myId = ref.watch(meshRepositoryProvider).myId;
    final qrPayload = me?.publicKey != null
        ? json.encode({'id': myId, 'pk': me!.publicKey})
        : null;

    return Scaffold(
      backgroundColor: OuroColors.background,
      appBar: AppBar(
        backgroundColor: OuroColors.background,
        elevation: 0,
        leading: OuroBackButton(fallback: '/chat/${widget.peerId}/info'),
        title: Text('Code de sécurité',
            style: TextStyle(color: OuroColors.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: _loading
          ? const Center(child: OuroSpinner(radius: 14))
          : ListView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
              children: [
                if (verified)
                  _StatusBanner(
                    icon: Icons.verified_rounded,
                    color: OuroColors.successGreen,
                    text: 'Vérifié — la clé de $peerPseudo correspond à ce code.',
                    pulse: true,
                  )
                else if (keyChanged)
                  _StatusBanner(
                    icon: Icons.warning_amber_rounded,
                    color: OuroColors.warningAmber,
                    text: 'La clé de $peerPseudo a changé depuis la dernière vérification.',
                  )
                else
                  _StatusBanner(
                    icon: Icons.info_outline_rounded,
                    color: OuroColors.textTertiary,
                    text: 'Pas encore vérifié.',
                  ),
                const SizedBox(height: 20),
                Text(
                  'Compare ce code avec celui affiché sur l\'appareil de $peerPseudo, ou '
                  'scanne directement son QR code pour vérifier automatiquement.',
                  style: TextStyle(color: OuroColors.textSecondary, fontSize: 13, height: 1.5),
                ),
                const SizedBox(height: 24),
                if (qrPayload != null)
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
                      ),
                      child: QrImageView(data: qrPayload, size: 220, backgroundColor: Colors.white),
                    ),
                  )
                      .animate()
                      .fadeIn(delay: 80.ms, duration: DesignTokens.durationSlow)
                      .scaleXY(begin: 0.85, curve: DesignTokens.curveEmphasis, duration: DesignTokens.durationSlow)
                      .blur(begin: const Offset(8, 8), end: Offset.zero, duration: DesignTokens.durationSlow),
                const SizedBox(height: 24),
                if (_code != null)
                  _SafetyNumberGrid(code: _code!)
                else
                  Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text(
                        'Clé du contact pas encore connue — reconnecte-toi à ce pair sur le mesh.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: OuroColors.textTertiary, fontSize: 13),
                      ),
                    ),
                  ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: _scan,
                    style: FilledButton.styleFrom(
                      backgroundColor: OuroColors.meshBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusLg)),
                    ),
                    icon: const Icon(Icons.qr_code_scanner_rounded),
                    label: Text('Scanner le code de $peerPseudo'),
                  ),
                ),
              ],
            ),
    );
  }
}

/// La bannière colorée en haut de l'écran qui résume l'état de
/// vérification : vert « vérifié » (avec un halo qui pulse doucement),
/// orange « la clé a changé » (signal d'alerte), ou gris « pas encore
/// vérifié ».
class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.icon, required this.color, required this.text, this.pulse = false});
  final IconData icon;
  final Color color;
  final String text;
  /// Halo respirant — réservé à l'état "vérifié", le seul qui mérite un
  /// signal ambiant continu plutôt qu'une simple bannière statique.
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    final banner = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600))),
        ],
      ),
    );
    final entrance = banner
        .animate()
        .fadeIn(duration: DesignTokens.durationNormal)
        .slideY(begin: -0.15, curve: DesignTokens.curveEmphasis);
    if (!pulse) return entrance;
    return entrance.animate(onPlay: (c) => c.repeat(reverse: true)).custom(
          duration: DesignTokens.durationXXSlow,
          builder: (context, value, child) => DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              boxShadow: DesignTokens.glow(color, radius: 10 + value * 12, spread: 1 + value),
            ),
            child: child,
          ),
        );
  }
}

/// Grille des 12 groupes de 5 chiffres du code de sécurité.
class _SafetyNumberGrid extends StatelessWidget {
  const _SafetyNumberGrid({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    final groups = code.split(' ');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: OuroColors.glassBg,
        borderRadius: BorderRadius.circular(DesignTokens.radiusXl),
        border: Border.all(color: OuroColors.glassBorder),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 14,
        runSpacing: 10,
        children: groups
            .asMap()
            .entries
            .map((entry) => Text(
                  entry.value,
                  style: TextStyle(
                    color: OuroColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                )
                    .animate()
                    .fadeIn(delay: (entry.key * 40).ms, duration: DesignTokens.durationFast)
                    .scaleXY(begin: 0.5, curve: DesignTokens.curveSpring, duration: DesignTokens.durationNormal))
            .toList(),
      ),
    ).animate().fadeIn(duration: DesignTokens.durationNormal);
  }
}
