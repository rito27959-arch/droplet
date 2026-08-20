import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/share_intent_service.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/glassmorphism.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/scene_animee.dart';

/// Écran affiché quand Droplet est choisi comme cible de partage depuis une
/// autre app Android (« Partager vers… ») — sélection de la conversation
/// destinataire pour le texte/fichier reçu, réutilisant les envois mesh
/// existants ([MeshNotifier.sendMessage]/[sendFile]).
class ShareTargetScreen extends ConsumerStatefulWidget {
  const ShareTargetScreen({super.key});

  @override
  ConsumerState<ShareTargetScreen> createState() => _ShareTargetScreenState();
}

class _ShareTargetScreenState extends ConsumerState<ShareTargetScreen> {
  late final List<SharedMediaFile> _items = List.of(ShareIntentService.pendingItems);
  final _searchCtrl = TextEditingController();
  String _query = '';
  bool _sending = false;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _cancel() {
    ShareIntentService.clear();
    context.go('/chats');
  }

  Future<void> _sendTo(Conversation conv) async {
    if (_sending) return;
    setState(() => _sending = true);
    HapticFeedback.selectionClick();
    final me = StorageService.currentUser;
    final notifier = ref.read(meshMessagesProvider.notifier);
    try {
      for (final item in _items) {
        if (item.type == SharedMediaType.text || item.type == SharedMediaType.url) {
          if (conv.isGroup) {
            await notifier.sendGroupMessage(me?.pseudo ?? 'Moi', item.path, groupId: conv.groupId!);
          } else {
            await notifier.sendMessage(me?.pseudo ?? 'Moi', item.path, targetId: conv.peerId);
          }
        } else {
          final file = File(item.path);
          if (!await file.exists()) continue;
          final bytes = await file.readAsBytes();
          await notifier.sendFile(
            pseudo: me?.pseudo ?? 'Moi',
            fileName: item.path.split('/').last,
            bytes: Uint8List.fromList(bytes),
            mimeType: item.mimeType ?? 'application/octet-stream',
            targetId: conv.isGroup ? null : conv.peerId,
            groupId: conv.groupId,
          );
        }
      }
    } finally {
      ShareIntentService.clear();
      if (mounted) context.go(conv.isGroup ? '/group/${conv.groupId}' : '/chat/${conv.peerId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final conversations = ref.watch(conversationsProvider).where((c) {
      if (_query.isEmpty) return true;
      return c.pseudo.toLowerCase().contains(_query.toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: OuroColors.background,
      appBar: AppBar(
        backgroundColor: OuroColors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: OuroColors.textPrimary),
          onPressed: _cancel,
        ),
        title: Text('Partager vers…', style: TextStyle(color: OuroColors.textPrimary, fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          if (_items.isNotEmpty) _SharedPreview(items: _items),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (v) => setState(() => _query = v),
              style: TextStyle(color: OuroColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Rechercher une conversation',
                hintStyle: TextStyle(color: OuroColors.textTertiary),
                prefixIcon: Icon(Icons.search_rounded, color: OuroColors.textTertiary),
                filled: true,
                fillColor: OuroColors.tertiarySystemFill,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(DesignTokens.radiusLg), borderSide: BorderSide.none),
              ),
            ),
          ),
          Expanded(
            child: conversations.isEmpty
                ? const EmptyState(
                    emoji: Scenes.partage,
                    icon: Icons.forum_outlined,
                    title: 'Aucune conversation',
                    subtitle: 'Ouvrez d\'abord une discussion dans Droplet pour pouvoir y partager du contenu.',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    itemCount: conversations.length,
                    itemBuilder: (context, i) {
                      final conv = conversations[i];
                      return ListTile(
                        enabled: !_sending,
                        leading: PeerAvatar(pseudo: conv.pseudo, radius: 22, online: conv.isOnline),
                        title: Text(conv.pseudo, style: TextStyle(color: OuroColors.textPrimary, fontWeight: FontWeight.w600)),
                        subtitle: Text(conv.isGroup ? 'Groupe' : 'Discussion',
                            style: TextStyle(color: OuroColors.textTertiary, fontSize: 12)),
                        onTap: () => _sendTo(conv),
                      ).animate().fadeIn(delay: (i * 24).ms, duration: DesignTokens.durationFast);
                    },
                  ),
          ),
          if (_sending)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(height: 2, child: LinearProgressIndicator()),
            ),
        ],
      ),
    );
  }
}

class _SharedPreview extends StatelessWidget {
  const _SharedPreview({required this.items});
  final List<SharedMediaFile> items;

  @override
  Widget build(BuildContext context) {
    final textItem = items.firstWhere(
      (i) => i.type == SharedMediaType.text || i.type == SharedMediaType.url,
      orElse: () => items.first,
    );
    final isText = textItem.type == SharedMediaType.text || textItem.type == SharedMediaType.url;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: GlassContainer(
        padding: const EdgeInsets.all(14),
        borderRadius: DesignTokens.radiusLg,
        child: Row(
          children: [
            Icon(isText ? Icons.article_outlined : Icons.attach_file_rounded, color: OuroColors.meshBlueBright),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                isText ? textItem.path : '${items.length} élément${items.length > 1 ? 's' : ''} à partager',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: OuroColors.textSecondary, fontSize: 13),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
