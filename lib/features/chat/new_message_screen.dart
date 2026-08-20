// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'écran « Nouveau message » : à qui veut-on écrire ?
//
// CE QUI A CHANGÉ : deux des trois raccourcis du haut ne faisaient
// RIEN (« Diffusion » et « Scanner QR » étaient des boutons vides,
// `onTap: () {}`). Un bouton qui ne réagit pas est pire qu'un bouton
// absent : on croit avoir mal appuyé, on recommence, et on finit par se
// demander si l'app est cassée. « Scanner QR » est maintenant branché
// sur le vrai scanner, et « Diffusion » a été retiré tant que la
// fonction n'existe pas.
//
// L'écran adopte par ailleurs la présentation du reste de l'app :
// grand titre repliable, liste groupée, mode clair comme sombre.
// ============================================================================

import 'package:flutter/cupertino.dart' show CupertinoPageRoute;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/mesh_transport_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_list.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/peer_avatar.dart';
import 'qr_scan_screen.dart';
import '../../shared/widgets/scene_animee.dart';

class NewMessageScreen extends ConsumerStatefulWidget {
  const NewMessageScreen({super.key});

  @override
  ConsumerState<NewMessageScreen> createState() => _NewMessageScreenState();
}

class _NewMessageScreenState extends ConsumerState<NewMessageScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final peers = ref.watch(meshPeerListProvider);
    final filtered = _query.isEmpty
        ? peers
        : peers
            .where((p) => p.pseudo.toLowerCase().contains(_query))
            .toList();

    return OuroLargeTitleScaffold(
      title: 'Nouveau message',
      backgroundColor: OuroColors.systemGroupedBackground,
      leading: OuroBarButton(
        icon: Icons.close_rounded,
        tooltip: 'Fermer',
        onPressed: () => context.pop(),
      ),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.screenMargin,
              0,
              DesignTokens.screenMargin,
              DesignTokens.space4,
            ),
            child: SizedBox(
              height: 36,
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                style: OuroTypography.body.copyWith(color: OuroColors.label),
                cursorColor: OuroColors.accent,
                onChanged: (v) =>
                    setState(() => _query = v.trim().toLowerCase()),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Rechercher',
                  hintStyle: OuroTypography.body
                      .copyWith(color: OuroColors.tertiaryLabel),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: OuroColors.tertiaryLabel,
                    size: DesignTokens.iconMd,
                  ),
                  prefixIconConstraints: const BoxConstraints(minWidth: 34),
                  filled: true,
                  fillColor: OuroColors.tertiarySystemFill,
                  contentPadding: const EdgeInsets.symmetric(vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusMd),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
          ),
        ),

        // ── Raccourcis ────────────────────────────────────────────────
        // Deux entrées, toutes deux fonctionnelles. Elles disparaissent
        // dès qu'on tape une recherche : à ce moment-là, on cherche une
        // personne, pas une action.
        if (_query.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.screenMargin,
                0,
                DesignTokens.screenMargin,
                DesignTokens.space5,
              ),
              child: OuroListSection(
                children: [
                  OuroListRow(
                    icon: Icons.group_add_rounded,
                    iconColor: OuroColors.systemGreen,
                    title: 'Nouveau groupe',
                    onTap: () {
                      OuroHaptics.selection();
                      context.go('/group/create');
                    },
                  ),
                  OuroListRow(
                    icon: Icons.qr_code_scanner_rounded,
                    iconColor: OuroColors.accent,
                    title: 'Scanner un code',
                    subtitle: 'Vérifier l\'identité d\'un contact',
                    onTap: () {
                      OuroHaptics.selection();
                      Navigator.of(context).push(
                        // Le scanner est un cran plus profond que la
                        // liste : il glisse depuis la droite, et le geste
                        // de retour au bord gauche le referme.
                        CupertinoPageRoute<void>(
                          builder: (_) => const QrScanScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

        if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: EmptyState(
                emoji: _query.isEmpty
                    ? Scenes.rechercheDePairs
                    : Scenes.aucunResultat,
                icon: _query.isEmpty
                    ? Icons.wifi_tethering_rounded
                    : Icons.person_search_rounded,
                title: _query.isEmpty
                    ? 'Personne à portée'
                    : 'Aucun résultat',
                subtitle: _query.isEmpty
                    ? 'Les personnes que votre appareil détecte '
                        'apparaîtront ici.'
                    : null,
              ),
            ),
          )
        else
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                DesignTokens.screenMargin,
                0,
                DesignTokens.screenMargin,
                DesignTokens.space6,
              ),
              child: OuroListSection(
                header: 'À portée',
                separatorInset: 68,
                children: [
                  for (final p in filtered) _PeerPickRow(peer: p),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Une personne qu'on peut choisir comme destinataire.
class _PeerPickRow extends StatefulWidget {
  const _PeerPickRow({required this.peer});

  final ConnectedPeer peer;

  @override
  State<_PeerPickRow> createState() => _PeerPickRowState();
}

class _PeerPickRowState extends State<_PeerPickRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.peer;

    return GestureDetector(
      onTap: () {
        OuroHaptics.selection();
        context.go('/chat/${p.peerId}');
      },
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: Container(
        color: _pressed
            ? OuroColors.systemFill
            : OuroColors.secondarySystemGroupedBackground,
        padding: const EdgeInsets.symmetric(
          horizontal: DesignTokens.space4,
          vertical: DesignTokens.space3,
        ),
        child: Row(
          children: [
            PeerAvatar(pseudo: p.pseudo, radius: 20, online: true),
            const SizedBox(width: DesignTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    p.pseudo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OuroTypography.body.copyWith(
                      color: OuroColors.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    p.hopCount == 0
                        ? 'Connexion directe'
                        : 'Via ${p.hopCount} relais',
                    style: OuroTypography.footnote
                        .copyWith(color: OuroColors.secondaryLabel),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: OuroColors.tertiaryLabel,
            ),
          ],
        ),
      ),
    );
  }
}
