// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'onglet APPELS — la liste de qui on a appelé, qui nous a appelé, et
// qui on a raté.
//
// CE QUI A CHANGÉ : cet écran affichait un historique ENTIÈREMENT
// INVENTÉ. Il prenait la liste des pairs actuellement connectés et
// fabriquait une ligne d'appel pour chacun, avec une heure calculée à
// partir de sa position dans la liste (« il y a 3h », « il y a 6h »,
// « il y a 9h »…) et un sens d'appel décidé par la parité de l'indice.
// Aucun de ces appels n'avait eu lieu. Pire : la liste changeait à
// chaque fois que quelqu'un se connectait ou se déconnectait.
//
// Droplet enregistre désormais réellement ses appels (voir
// `CallLogEntry`, écrit par `CallNotifier` à la fin de chaque appel), et
// cet écran ne montre que ça. Quand il n'y a rien, il le dit.
//
// Le reste est un alignement sur le design du reste de l'app : grand
// titre repliable, listes groupées, couleurs qui suivent le mode clair
// ou sombre.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/mesh_message.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_list.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/empty_state.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../shared/widgets/scene_animee.dart';

/// Les deux filtres de la liste, comme dans Téléphone sur iOS.
enum _CallFilter { all, missed }

class CallsScreen extends ConsumerStatefulWidget {
  const CallsScreen({super.key});

  @override
  ConsumerState<CallsScreen> createState() => _CallsScreenState();
}

class _CallsScreenState extends ConsumerState<CallsScreen> {
  _CallFilter _filter = _CallFilter.all;

  @override
  Widget build(BuildContext context) {
    // Observé pour redessiner la liste quand un appel se termine : le
    // journal est écrit à ce moment-là.
    ref.watch(callProvider);

    final all = StorageService.getCallLogs();
    final missedCount = all.where((c) => c.isMissedIncoming).length;
    final entries =
        _filter == _CallFilter.missed ? all.where((c) => c.isMissedIncoming).toList() : all;

    return OuroLargeTitleScaffold(
      title: 'Appels',
      subtitle: missedCount > 0
          ? '$missedCount appel${missedCount > 1 ? 's' : ''} manqué'
              '${missedCount > 1 ? 's' : ''}'
          : null,
      backgroundColor: OuroColors.systemGroupedBackground,
      actions: [
        OuroBarButton(
          icon: Icons.add_ic_call_rounded,
          tooltip: 'Nouvel appel',
          onPressed: () {
            OuroHaptics.selection();
            context.go('/new-message');
          },
        ),
      ],
      slivers: [
        // ── Filtre Tous / Manqués ─────────────────────────────────────
        // Un vrai segmenté iOS plutôt que deux pastilles arrondies : le
        // segmenté dit visuellement « ce sont deux vues de la MÊME
        // liste », là où deux pastilles séparées ressemblent à deux
        // boutons indépendants.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.screenMargin,
              0,
              DesignTokens.screenMargin,
              DesignTokens.space4,
            ),
            child: _Segmented(
              selected: _filter,
              onChanged: (f) {
                OuroHaptics.selection();
                setState(() => _filter = f);
              },
            ),
          ),
        ),

        if (entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 60),
              child: EmptyState(
                emoji: Scenes.aucunAppel,
                icon: Icons.phone_rounded,
                title: _filter == _CallFilter.missed
                    ? 'Aucun appel manqué'
                    : 'Aucun appel',
                subtitle: _filter == _CallFilter.missed
                    ? 'Les appels auxquels vous n\'avez pas répondu '
                        'apparaîtront ici.'
                    : 'Les appels passent par le réseau local, sans '
                        'opérateur ni forfait. Votre historique '
                        'apparaîtra ici.',
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
                separatorInset: 68,
                footer: 'Les 200 derniers appels sont conservés sur cet '
                    'appareil uniquement.',
                children: [
                  for (final entry in entries) _CallRow(entry: entry),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SEGMENTÉ
// ─────────────────────────────────────────────────────────────

class _Segmented extends StatelessWidget {
  const _Segmented({required this.selected, required this.onChanged});

  final _CallFilter selected;
  final ValueChanged<_CallFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 32,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: OuroColors.tertiarySystemFill,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Row(
        children: [
          _segment(context, _CallFilter.all, 'Tous'),
          _segment(context, _CallFilter.missed, 'Manqués'),
        ],
      ),
    );
  }

  Widget _segment(BuildContext context, _CallFilter filter, String label) {
    final active = filter == selected;
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onChanged(filter),
        child: AnimatedContainer(
          duration: DesignTokens.durationFast,
          curve: DesignTokens.curveStandard,
          decoration: BoxDecoration(
            // La pastille active est une surface claire posée dans le
            // creux gris, comme sur iOS — pas un aplat de couleur vive.
            color: active
                ? OuroColors.secondarySystemGroupedBackground
                : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
            boxShadow: active
                ? [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: OuroTypography.footnote.copyWith(
              color: active ? OuroColors.label : OuroColors.secondaryLabel,
              fontWeight: active ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  UNE LIGNE D'APPEL
// ─────────────────────────────────────────────────────────────

class _CallRow extends StatefulWidget {
  const _CallRow({required this.entry});

  final CallLogEntry entry;

  @override
  State<_CallRow> createState() => _CallRowState();
}

class _CallRowState extends State<_CallRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final e = widget.entry;
    final missed = e.isMissedIncoming;

    return GestureDetector(
      // Taper la ligne ouvre la conversation ; le bouton téléphone à
      // droite rappelle. C'est la répartition de Téléphone sur iOS, et
      // elle évite de déclencher un appel par accident.
      onTap: () {
        OuroHaptics.selection();
        context.push('/chat/${e.peerId}');
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
            PeerAvatar(pseudo: e.peerPseudo, radius: 20),
            const SizedBox(width: DesignTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    e.peerPseudo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OuroTypography.body.copyWith(
                      // Un appel manqué s'écrit en rouge, comme partout
                      // ailleurs — c'est la seule information de cet
                      // écran qui demande une action.
                      color: missed ? OuroColors.systemRed : OuroColors.label,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(
                        _iconFor(e),
                        size: 13,
                        color: missed
                            ? OuroColors.systemRed
                            : OuroColors.tertiaryLabel,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          _detailFor(e),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OuroTypography.footnote
                              .copyWith(color: OuroColors.secondaryLabel),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: DesignTokens.space2),
            Text(
              _timeFor(e.startedAt),
              style: OuroTypography.footnote
                  .copyWith(color: OuroColors.tertiaryLabel),
            ),
            const SizedBox(width: DesignTokens.space2),
            // Zone de rappel : 44 points de côté, le minimum en dessous
            // duquel une cible devient difficile à viser au pouce.
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                OuroHaptics.light();
                context.go('/call/${e.peerId}');
              },
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(
                  Icons.phone_rounded,
                  size: 20,
                  color: OuroColors.accent,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconFor(CallLogEntry e) {
    if (e.outcome == CallOutcome.failed) return Icons.error_outline_rounded;
    if (e.outcome == CallOutcome.missed) {
      return e.direction == CallDirection.incoming
          ? Icons.call_missed_rounded
          : Icons.call_missed_outgoing_rounded;
    }
    return e.direction == CallDirection.incoming
        ? Icons.call_received_rounded
        : Icons.call_made_rounded;
  }

  String _detailFor(CallLogEntry e) {
    switch (e.outcome) {
      case CallOutcome.answered:
        final d = e.duration;
        final m = d.inMinutes;
        final s = d.inSeconds % 60;
        final length = m > 0 ? '$m min $s s' : '$s s';
        return e.direction == CallDirection.incoming
            ? 'Entrant · $length'
            : 'Sortant · $length';
      case CallOutcome.missed:
        return e.direction == CallDirection.incoming
            ? 'Manqué'
            : 'Sans réponse';
      case CallOutcome.failed:
        return 'Échec de la connexion';
    }
  }

  /// « 14:32 » pour aujourd'hui, « hier », puis la date. Même logique que
  /// la liste des discussions, pour que les deux se lisent pareil.
  String _timeFor(DateTime dt) {
    final now = DateTime.now();
    final sameDay =
        now.year == dt.year && now.month == dt.month && now.day == dt.day;
    if (sameDay) {
      return '${dt.hour.toString().padLeft(2, '0')}:'
          '${dt.minute.toString().padLeft(2, '0')}';
    }
    final yesterday = now.subtract(const Duration(days: 1));
    if (yesterday.year == dt.year &&
        yesterday.month == dt.month &&
        yesterday.day == dt.day) {
      return 'hier';
    }
    return '${dt.day.toString().padLeft(2, '0')}/'
        '${dt.month.toString().padLeft(2, '0')}';
  }
}
