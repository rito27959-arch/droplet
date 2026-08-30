// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est l'écran « Infos » d'une conversation — celui qu'on ouvre en
// tapant sur le nom d'un contact en haut d'une discussion. On y trouve
// l'avatar en grand, si la personne est actuellement en ligne, le lien
// vers la vérification du « code de sécurité » (voir
// `security_code_screen.dart`), quelques statistiques (nombre de
// messages, de médias, depuis quand on discute), puis toutes les photos,
// notes vocales et fichiers échangés dans cette conversation, rangés
// dans des petites galeries — un peu comme l'onglet « Médias partagés »
// de WhatsApp.
// ============================================================================

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:local_auth/local_auth.dart';
import '../../core/models/mesh_message.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/mesh_transport_service.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_spinner.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/glassmorphism.dart';
import '../../core/models/voice_note_meta.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../shared/widgets/scene_animee.dart';

/// Page « Infos et médias » d'une conversation.
class ChatInfoScreen extends ConsumerStatefulWidget {
  const ChatInfoScreen({super.key, required this.peerId});

  /// ID du pair, ou 'broadcast' pour le canal diffusion.
  final String peerId;

  @override
  ConsumerState<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends ConsumerState<ChatInfoScreen> {
  late bool _isLocked;
  late int _ephemeralTimer;

  @override
  void initState() {
    super.initState();
    _isLocked = StorageService.getLockedConversations().contains(widget.peerId);
    _ephemeralTimer = StorageService.getEphemeralTimer(widget.peerId);
  }

  Future<void> _toggleLock() async {
    final auth = LocalAuthentication();
    final newState = !_isLocked;

    if (newState) {
      // Verrouiller : vérifier que la biométrie est disponible.
      try {
        final available = await auth.canCheckBiometrics;
        if (!available) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text(
                'Configurez un empreinte digitale ou Face ID dans les réglages de votre appareil.',
                style: OuroTypography.subheadline.copyWith(color: OuroColors.label),
              ),
              backgroundColor: OuroColors.tertiarySystemBackground,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              ),
            ));
          }
          return;
        }
        // Demander une authentification pour confirmer l'activation.
        final didAuth = await auth.authenticate(
          localizedReason: 'Activer le verrouillage pour cette conversation',
          options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
        );
        if (!didAuth) return;
        HapticFeedback.mediumImpact();
      } catch (_) {
        return;
      }
    } else {
      // Déverrouiller : petit feedback.
      HapticFeedback.lightImpact();
    }

    await StorageService.setConversationLocked(widget.peerId, newState);
    if (mounted) setState(() => _isLocked = newState);
  }

  @override
  Widget build(BuildContext context) {
    final peerId = widget.peerId;
    final isBroadcast = peerId == 'broadcast';
    final messages = ref.watch(conversationMessagesProvider(isBroadcast ? null : peerId));
    final peers = ref.watch(meshPeerListProvider);
    final pseudo = isBroadcast
        ? 'Diffusion mesh'
        : ref.watch(peerPseudoProvider(peerId));

    ConnectedPeer? peer;
    if (!isBroadcast) {
      for (final p in peers) {
        if (p.peerId == peerId) {
          peer = p;
          break;
        }
      }
    }

    final media = messages.where((m) => m.type == 'file').toList();
    final images = media
        .where((m) => m.fileMimeType?.startsWith('image') ?? false)
        .toList();
    final audio = media
        .where((m) => m.fileMimeType?.startsWith('audio') ?? false)
        .toList();
    final docs = media
        .where((m) =>
            !(m.fileMimeType?.startsWith('image') ?? false) &&
            !(m.fileMimeType?.startsWith('audio') ?? false))
        .toList();

    final firstMessage = messages.isEmpty ? null : messages.first.timestamp;

    return Scaffold(
      backgroundColor: OuroColors.systemGroupedBackground,
      appBar: AppBar(
        backgroundColor: OuroColors.systemGroupedBackground,
        elevation: 0,
        title: Text('Infos',
            style: TextStyle(color: OuroColors.textPrimary, fontWeight: FontWeight.w700)),
        leading: OuroBackButton(fallback: '/chat/$peerId'),
        actions: [
          if (!isBroadcast)
            IconButton(
              tooltip: 'Voir la conversation',
              icon: Icon(Icons.chat_bubble_rounded, color: OuroColors.meshBlueBright),
              // On REVIENT à la conversation d'où l'on vient, on n'en
              // ouvre pas une deuxième par-dessus.
              onPressed: () => Navigator.of(context).canPop()
                  ? Navigator.of(context).pop()
                  : context.go('/chat/$peerId'),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(DesignTokens.screenMargin, 8, DesignTokens.screenMargin, DesignTokens.space8),
        children: [
          // En-tête : avatar + pseudo + présence.
          Center(
            child: Column(
              children: [
                PeerAvatar(
                  pseudo: pseudo,
                  radius: 38,
                  online: peer != null,
                ),
                const SizedBox(height: 14),
                Text(pseudo,
                    style: TextStyle(
                        color: OuroColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: peer != null
                            ? OuroColors.successGreen
                            : OuroColors.textTertiary,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      peer != null
                          ? (peer.isGateway ? 'Passerelle · en ligne' : 'En ligne')
                          : 'Hors ligne',
                      style: TextStyle(fontSize: 13, color: OuroColors.textSecondary),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          if (!isBroadcast) _SecurityCodeRow(peerId: peerId, pseudo: pseudo),

          if (!isBroadcast) ...[
            const SizedBox(height: 12),
            _LockToggleRow(locked: _isLocked, onTap: _toggleLock),
          ],

          if (!isBroadcast) ...[
            const SizedBox(height: 12),
            _EphemeralTimerRow(
              currentSeconds: _ephemeralTimer,
              onChanged: (seconds) async {
                await StorageService.setEphemeralTimer(widget.peerId, seconds);
                if (mounted) setState(() => _ephemeralTimer = seconds);
              },
            ),
          ],

          const SizedBox(height: 24),

          // Statistiques.
          Row(
            children: [
              _StatCard(
                icon: Icons.forum_rounded,
                label: 'Messages',
                value: '${messages.length}',
                color: OuroColors.meshBlueBright,
                delayMs: 0,
              ),
              const SizedBox(width: 12),
              _StatCard(
                icon: Icons.photo_library_rounded,
                label: 'Médias',
                value: '${media.length}',
                color: OuroColors.accentPink,
                delayMs: 60,
              ),
              const SizedBox(width: 12),
              _StatCard(
                icon: Icons.calendar_month_rounded,
                label: 'Début',
                value: _shortDate(firstMessage),
                color: OuroColors.successGreen,
                delayMs: 120,
              ),
            ],
          ),
          const SizedBox(height: 28),

          if (images.isNotEmpty) _sectionTitle('Photos (${images.length})'),
          if (images.isNotEmpty) ...[
            const SizedBox(height: 10),
            _ImageGrid(images: images).animate().fadeIn(delay: 100.ms, duration: DesignTokens.durationNormal),
            const SizedBox(height: 24),
          ],

          if (audio.isNotEmpty) _sectionTitle('Notes vocales (${audio.length})'),
          if (audio.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...audio.asMap().entries.map((e) => _AudioTile(message: e.value)
                .animate()
                .fadeIn(delay: (140 + e.key * 40).ms, duration: DesignTokens.durationFast)
                .slideX(begin: 0.08)),
            const SizedBox(height: 24),
          ],

          if (docs.isNotEmpty) _sectionTitle('Fichiers (${docs.length})'),
          if (docs.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...docs.asMap().entries.map((e) => _FileTile(message: e.value)
                .animate()
                .fadeIn(delay: (140 + e.key * 40).ms, duration: DesignTokens.durationFast)
                .slideX(begin: 0.08)),
            const SizedBox(height: 24),
          ],

          if (media.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Column(
                children: [
                  SceneAnimee(
                    emoji: Scenes.aucunResultat,
                    iconeDeSecours: Icons.photo_library_outlined,
                    taille: 56,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Aucun média partagé pour le moment.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: OuroColors.textTertiary,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),

          // Bouton d'appel si connecté.
          if (peer != null) ...[
            const SizedBox(height: 8),
            _CallButton(peerId: peerId),
          ],
        ],
      ),
    );
  }

  /// L'en-tête de section, dessiné comme partout ailleurs dans l'app.
  ///
  /// iOS écrit ces titres en PETITES CAPITALES GRISES, de graisse
  /// normale : ce sont des repères, pas du contenu. Ils étaient ici en
  /// gras et de la couleur du texte principal — ils pesaient donc plus
  /// lourd que les lignes qu'ils annonçaient, et cet écran ne
  /// ressemblait plus aux autres. Même recette que `OuroListSection`.
  Widget _sectionTitle(String label) {
    return Text(
      label.toUpperCase(),
      style: OuroTypography.sectionHeader.copyWith(
        color: OuroColors.secondaryLabel,
        letterSpacing: 0.5,
      ),
    );
  }

  String _shortDate(DateTime? t) {
    if (t == null) return '—';
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year}';
  }
}

/// Ligne cliquable vers l'écran de vérification hors-bande (code de
/// sécurité) — reflète l'état de vérification connu localement pour ce pair.
class _SecurityCodeRow extends StatelessWidget {
  const _SecurityCodeRow({required this.peerId, required this.pseudo});
  final String peerId;
  final String pseudo;

  @override
  Widget build(BuildContext context) {
    final record = StorageService.getPeerRecord(peerId);
    final verified = record?.isVerifiedAndCurrent ?? false;
    final keyChanged = record?.keyChangedSinceVerification ?? false;

    final color = verified
        ? OuroColors.successGreen
        : keyChanged
            ? OuroColors.warningAmber
            : OuroColors.textSecondary;
    final label = verified
        ? 'Vérifié'
        : keyChanged
            ? 'La clé a changé'
            : 'Non vérifié';
    final icon = verified
        ? Icons.verified_rounded
        : keyChanged
            ? Icons.warning_amber_rounded
            : Icons.qr_code_rounded;

    return GestureDetector(
      onTap: () => context.push('/chat/$peerId/security'),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: OuroColors.secondarySystemGroupedBackground,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(color: OuroColors.glassBorder, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Code de sécurité',
                      style: TextStyle(color: OuroColors.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: OuroColors.textTertiary),
          ],
        ),
      ),
    );
  }
}

/// Une des 3 petites cartes de statistiques en haut (nombre de
/// messages, nombre de médias, date du premier message).
class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.delayMs = 0,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final int delayMs;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: OuroColors.secondarySystemGroupedBackground,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(color: OuroColors.glassBorder, width: 0.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 8),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: OuroColors.textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(color: OuroColors.textTertiary, fontSize: 11)),
          ],
        ),
      ),
    )
        .animate()
        .fadeIn(delay: delayMs.ms, duration: DesignTokens.durationNormal)
        .slideY(begin: 0.15, curve: DesignTokens.curveEmphasis);
  }
}

/// La petite grille en 3 colonnes de toutes les photos partagées dans
/// cette conversation.
class _ImageGrid extends StatelessWidget {
  const _ImageGrid({required this.images});
  final List<MeshMessage> images;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: images.length,
      itemBuilder: (context, i) => _ImageThumb(message: images[i]),
    );
  }
}

/// Une seule vignette de photo dans la grille — un tap l'ouvre en grand
/// avec [_ImageViewer].
class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.message});
  final MeshMessage message;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: GestureDetector(
        onTap: () => _openViewer(context),
        child: Hero(
          tag: 'chat-image-${message.id}',
          child: FutureBuilder<String?>(
            future: StorageService.getSharedFilePath(
              message.fileId ?? '',
              message.fileName ?? '',
            ),
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const _SkeletonBox();
              }
              final path = snap.data;
              if (path != null && File(path).existsSync()) {
                return Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => _placeholder(),
                );
              }
              return _placeholder();
            },
          ),
        ),
      ),
    );
  }

  Widget _placeholder() {
    return Container(
      color: OuroColors.secondarySystemGroupedBackground,
      child: Icon(Icons.image_rounded, color: OuroColors.textTertiary, size: 26),
    );
  }

  void _openViewer(BuildContext context) {
    HapticFeedback.selectionClick();
    showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (context) => _ImageViewer(message: message),
    );
  }
}

/// L'affichage plein écran d'une photo, avec zoom au pincement (comme
/// dans une galerie photo classique).
class _ImageViewer extends StatefulWidget {
  const _ImageViewer({required this.message});
  final MeshMessage message;

  @override
  State<_ImageViewer> createState() => _ImageViewerState();
}

class _ImageViewerState extends State<_ImageViewer> {
  String? _path;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final path = await StorageService.getSharedFilePath(
      widget.message.fileId ?? '',
      widget.message.fileName ?? '',
    );
    if (mounted && path != null && File(path).existsSync()) {
      setState(() => _path = path);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                maxScale: 5,
                child: Center(
                  child: Hero(
                    tag: 'chat-image-${widget.message.id}',
                    child: _path != null
                        ? Image.file(File(_path!), fit: BoxFit.contain)
                        : OuroSpinner(color: OuroColors.meshBlueBright, radius: 14),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 12,
              child: IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _formatFull(widget.message.timestamp),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatFull(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year} · $h:$m';
  }
}

/// Une ligne de la liste des notes vocales partagées.
class _AudioTile extends StatelessWidget {
  const _AudioTile({required this.message});
  final MeshMessage message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: OuroColors.secondarySystemGroupedBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OuroColors.glassBorder, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.mic_rounded, color: OuroColors.errorRed, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(VoiceNoteMeta.describeAttachment(message.fileName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: OuroColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(_formatFull(message.timestamp),
                    style: TextStyle(color: OuroColors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
          Icon(Icons.play_circle_fill_rounded, color: OuroColors.meshBlueBright, size: 24),
        ],
      ),
    );
  }

  String _formatFull(DateTime t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')} · $h:$m';
  }
}

/// Une ligne de la liste des documents (ni photo, ni audio) partagés.
class _FileTile extends StatelessWidget {
  const _FileTile({required this.message});
  final MeshMessage message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: OuroColors.secondarySystemGroupedBackground,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: OuroColors.glassBorder, width: 0.5),
      ),
      child: Row(
        children: [
          Icon(Icons.insert_drive_file_rounded, color: OuroColors.warningAmber, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(VoiceNoteMeta.describeAttachment(message.fileName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: OuroColors.textPrimary, fontSize: 13, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(_formatSize(message.fileSize ?? 0),
                    style: TextStyle(color: OuroColors.textTertiary, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}

/// Ligne de verrouillage de conversation — verrouille/déverrouille
/// l'accès biométrique à cette conversation.
class _LockToggleRow extends StatelessWidget {
  const _LockToggleRow({required this.locked, required this.onTap});
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: OuroColors.secondarySystemGroupedBackground,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(color: OuroColors.glassBorder, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(
              locked ? Icons.lock_rounded : Icons.lock_open_rounded,
              color: locked ? OuroColors.accent : OuroColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Verrouillage de conversation',
                    style: TextStyle(
                      color: OuroColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    locked
                        ? 'Activé — empreinte requise pour ouvrir'
                        : 'Désactivé',
                    style: TextStyle(
                      color: locked
                          ? OuroColors.accent
                          : OuroColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              locked ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
              color: locked ? OuroColors.systemGreen : OuroColors.textTertiary,
              size: 32,
            ),
          ],
        ),
      ),
    );
  }
}

/// Sélecteur de timer pour les messages éphémères — affiche un menu
/// déroulant avec des durées prédéfinies (30s, 5min, 1h, 24h, off).
class _EphemeralTimerRow extends StatelessWidget {
  const _EphemeralTimerRow({required this.currentSeconds, required this.onChanged});
  final int currentSeconds;
  final ValueChanged<int> onChanged;

  static const _options = <MapEntry<String, int>>[
    MapEntry('Désactivé', 0),
    MapEntry('30 secondes', 30),
    MapEntry('5 minutes', 300),
    MapEntry('1 heure', 3600),
    MapEntry('24 heures', 86400),
  ];

  String _label() {
    for (final o in _options) {
      if (o.value == currentSeconds) return o.key;
    }
    return 'Désactivé';
  }

  @override
  Widget build(BuildContext context) {
    final active = currentSeconds > 0;
    return GestureDetector(
      onTap: () => _showPicker(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: OuroColors.secondarySystemGroupedBackground,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(color: OuroColors.glassBorder, width: 0.5),
        ),
        child: Row(
          children: [
            Icon(
              Icons.timer_off_rounded,
              color: active ? OuroColors.warningAmber : OuroColors.textSecondary,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Messages éphémères',
                    style: TextStyle(
                      color: OuroColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _label(),
                    style: TextStyle(
                      color: active
                          ? OuroColors.warningAmber
                          : OuroColors.textSecondary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: OuroColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  void _showPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FrostedSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                'Durée avant disparition',
                style: OuroTypography.headline.copyWith(color: OuroColors.label),
              ),
            ),
            for (final o in _options) ...[
              Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
              ListTile(
                title: Text(
                  o.key,
                  style: TextStyle(
                    color: currentSeconds == o.value
                        ? OuroColors.accent
                        : OuroColors.label,
                    fontWeight: currentSeconds == o.value
                        ? FontWeight.w700
                        : FontWeight.w400,
                  ),
                ),
                trailing: currentSeconds == o.value
                    ? Icon(Icons.check_rounded, color: OuroColors.accent, size: 20)
                    : null,
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  onChanged(o.value);
                },
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Le gros bouton vert « Appel vocal » tout en bas de l'écran, visible
/// seulement si ce pair est actuellement connecté.
class _CallButton extends StatelessWidget {
  const _CallButton({required this.peerId});
  final String peerId;

  @override
  Widget build(BuildContext context) {
    // ⚠️ `FilledButton` et non `ElevatedButton` : le second porte une
    // OMBRE PORTÉE, héritage de Material. iOS ne met jamais d'ombre sous
    // un bouton plein — il repose à plat sur le fond. C'était le dernier
    // bouton de l'app à flotter, et il ne partageait ni la hauteur (52)
    // ni le rayon des autres actions principales.
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        onPressed: () {
          HapticFeedback.mediumImpact();
          context.push('/call/$peerId');
        },
        style: FilledButton.styleFrom(
          backgroundColor: OuroColors.successGreen,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          ),
        ),
        icon: const Icon(Icons.call_rounded, size: 20),
        label: Text('Appel vocal',
            style: OuroTypography.headline.copyWith(color: Colors.white)),
      ),
    );
  }
}

/// Placeholder skeleton animé avec effet shimmer pour les médias en chargement.
class _SkeletonBox extends StatefulWidget {
  const _SkeletonBox();
  @override
  State<_SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<_SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        final t = _ctrl.value;
        return Container(
          color: OuroColors.secondarySystemGroupedBackground,
          child: ShaderMask(
            shaderCallback: (bounds) {
              return LinearGradient(
                begin: Alignment(-1.0 + t * 2, 0),
                end: Alignment(-0.6 + t * 2, 0),
                colors: const [
                  Colors.transparent,
                  Colors.white24,
                  Colors.transparent,
                ],
                stops: const [0.0, 0.5, 1.0],
              ).createShader(bounds);
            },
            blendMode: BlendMode.srcATop,
            child: Container(
              color: OuroColors.secondarySystemGroupedBackground,
            ),
          ),
        );
      },
    );
  }
}
