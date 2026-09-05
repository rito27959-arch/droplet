// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE MENU QUI S'OUVRE QUAND ON RESTE APPUYÉ SUR UN MESSAGE — celui
// d'iMessage et de WhatsApp sur iPhone.
//
// ── Ce qui le distingue d'une feuille qui monte du bas ────────────────
//
// Une feuille modale répond à la question « quelles actions existent ? ».
// Le menu d'iOS répond à une autre : « que veux-tu faire À CE
// MESSAGE-CI ? ». La différence n'est pas cosmétique :
//
//   • TOUT LE RESTE S'EFFACE. L'arrière-plan se floute et s'assombrit,
//     et le message choisi reste NET, seul objet lisible à l'écran. On
//     n'a plus besoin de se souvenir sur lequel on avait appuyé.
//   • LE MESSAGE SE SOULÈVE. Il grossit à peine et se détache par une
//     ombre. C'est ce léger décollement qui fait croire qu'on le tient.
//   • LE MENU EST ANCRÉ À LUI. Les émojis juste au-dessus, les actions
//     juste en dessous — pas à l'autre bout de l'écran.
//
// ── Le point délicat : le placement ───────────────────────────────────
//
// L'ensemble (barre d'émojis + message + actions) est souvent plus haut
// que la place disponible au-dessus ou en dessous du message. iMessage
// résout cela en DÉPLAÇANT LE MESSAGE : il glisse jusqu'à ce que tout
// tienne à l'écran, et l'animation part de sa position réelle, si bien
// que l'œil le suit sans le perdre. C'est ce que fait `_placement()`.
// ============================================================================

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:motor/motor.dart';

import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/glassmorphism.dart';

/// Une action proposée sous le message.
class MessageAction {
  const MessageAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.destructive = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  /// Affichée en rouge, et toujours placée en dernier — convention iOS.
  final bool destructive;
}

/// Ouvre le menu contextuel ancré sur la bulle repérée par [anchorKey].
///
/// [preview] est une copie de la bulle : on ne peut pas déplacer
/// l'originale, qui vit dans la liste. La copie est posée exactement à sa
/// place, puis animée — l'illusion tient tant que les deux se
/// ressemblent.
Future<void> showMessageContextMenu({
  required BuildContext context,
  required GlobalKey anchorKey,
  required Widget preview,
  required bool mine,
  required List<String> current,
  required ValueChanged<String> onReact,
  required List<MessageAction> actions,
}) {
  final box = anchorKey.currentContext?.findRenderObject() as RenderBox?;
  if (box == null || !box.hasSize) return Future<void>.value();
  final origin = box.localToGlobal(Offset.zero) & box.size;

  HapticFeedback.mediumImpact();

  return Navigator.of(context, rootNavigator: true).push<void>(
    PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.transparent,
      // ⚠️ Assez long pour qu'on VOIE le message se soulever. En dessous
      // de ~250 ms le mouvement passe pour un simple changement d'écran.
      transitionDuration: const Duration(milliseconds: 320),
      reverseTransitionDuration: const Duration(milliseconds: 220),
      // ⚠️ `Material` OBLIGATOIRE, MÊME TRANSPARENT.
      //
      // Une route poussée sur le navigateur racine n'hérite d'aucun
      // `Material` : les `Text` qu'elle contient retombent alors sur le
      // style de secours de Flutter — SOULIGNÉ DEUX FOIS EN JAUNE. Tout
      // le menu s'affichait ainsi, y compris la copie du message. Le
      // type `transparency` fournit l'ancêtre manquant sans peindre
      // quoi que ce soit par-dessus le flou.
      pageBuilder: (context, animation, _) => Material(
        type: MaterialType.transparency,
        child: _ContextMenuOverlay(
          animation: animation,
          origin: origin,
          preview: preview,
          mine: mine,
          current: current,
          onReact: onReact,
          actions: actions,
        ),
      ),
    ),
  );
}

class _ContextMenuOverlay extends StatelessWidget {
  const _ContextMenuOverlay({
    required this.animation,
    required this.origin,
    required this.preview,
    required this.mine,
    required this.current,
    required this.onReact,
    required this.actions,
  });

  final Animation<double> animation;
  final Rect origin;
  final Widget preview;
  final bool mine;
  final List<String> current;
  final ValueChanged<String> onReact;
  final List<MessageAction> actions;

  /// iMessage tapback : ❤️ 👍 👎 😂 ‼️ ❓
  static const List<String> _emojis = ['❤️', '👍', '👎', '😂', '‼️', '❓'];

  static const double _barHeight = 56;
  static const double _gap = 10;
  static const double _menuWidth = 250;
  static const double _rowHeight = 46;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final safeTop = media.padding.top + 8;
    final safeBottom = media.size.height - media.padding.bottom - 8;

    final menuHeight = actions.isEmpty ? 0.0 : actions.length * _rowHeight;
    final total = _barHeight + _gap + origin.height + _gap + menuHeight;

    // Position idéale : la barre d'émojis juste au-dessus du message.
    var top = origin.top - _gap - _barHeight;
    // Puis on ramène l'ensemble dans l'écran, sans jamais le couper.
    if (top + total > safeBottom) top = safeBottom - total;
    if (top < safeTop) top = safeTop;

    final bubbleTop = top + _barHeight + _gap;
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return AnimatedBuilder(
      animation: curved,
      builder: (context, _) {
        final t = curved.value;

        return Stack(
          children: [
            // ── Le fond : flou + assombrissement, tous deux progressifs.
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: BackdropFilter(
                  // ⚠️ FLOU **ET** SATURATION, comme le reste du châssis.
                  //
                  // C'est le changement qu'a apporté WhatsApp à son menu
                  // contextuel sur iOS 26 : le calque ne se contente plus
                  // de flouter, il reprend les couleurs de la
                  // conversation derrière lui. Un flou seul rend gris ce
                  // qu'il recouvre — et sur un fond de conversation
                  // coloré, c'est très visible.
                  //
                  // La saturation ne monte qu'avec l'ouverture (`t`) :
                  // à mi-course, le fond est à moitié flouté et à moitié
                  // ravivé, sans quoi la couleur sauterait d'un coup au
                  // premier vingtième de seconde.
                  filter: ui.ImageFilter.compose(
                    outer: ui.ColorFilter.matrix(
                      OuroMaterialFilter.matricePour(
                        1 + (OuroMaterialFilter.saturation - 1) * t,
                      ),
                    ),
                    inner: ui.ImageFilter.blur(
                      sigmaX: 22 * t,
                      sigmaY: 22 * t,
                    ),
                  ),
                  child: ColoredBox(
                    color: Colors.black.withValues(
                      alpha: (OuroColors.isDark ? 0.5 : 0.28) * t,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),

            // ── Le message, soulevé et amené à sa place.
            //
            // Il part de sa position réelle dans la liste et glisse vers
            // la position calculée : l'œil ne le lâche pas. Il grossit de
            // 3 % — assez pour qu'on sente qu'on le tient, pas assez pour
            // qu'on remarque le changement d'échelle.
            Positioned(
              left: origin.left,
              top: ui.lerpDouble(origin.top, bubbleTop, t)!,
              width: origin.width,
              child: IgnorePointer(
                child: Transform.scale(
                  scale: 1 + 0.03 * t,
                  alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: preview,
                ),
              ),
            ),

            // ── La barre d'émojis, au-dessus.
            Positioned(
              left: 12,
              right: 12,
              top: top,
              child: Align(
                alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Opacity(
                  opacity: t,
                  child: _ReactionBar(
                    emojis: _emojis,
                    current: current,
                    progress: t,
                    onSelect: (emoji) {
                      OuroHaptics.light();
                      Navigator.of(context).pop();
                      onReact(emoji);
                    },
                  ),
                ),
              ),
            ),

            // ── Les actions, en dessous.
            if (actions.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                top: bubbleTop + origin.height + _gap,
                child: Align(
                  alignment:
                      mine ? Alignment.centerRight : Alignment.centerLeft,
                  child: Opacity(
                    opacity: t,
                    child: Transform.scale(
                      // Le menu s'ouvre DEPUIS LE MESSAGE : il grandit à
                      // partir de son bord haut, du côté du message.
                      scale: 0.86 + 0.14 * t,
                      alignment: mine
                          ? Alignment.topRight
                          : Alignment.topLeft,
                      child: _ActionMenu(
                        width: _menuWidth,
                        rowHeight: _rowHeight,
                        actions: actions,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// La capsule d'émojis iMessage : capsule avec shadow, 24pt radius.
class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.emojis,
    required this.current,
    required this.progress,
    required this.onSelect,
  });

  final List<String> emojis;
  final List<String> current;
  final double progress;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    // iMessage tapback strip : capsule with shadow.
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: OuroColors.isDark
            ? const Color(0xFF2C2C2E)
            : Colors.white,
        borderRadius: BorderRadius.circular(24),
        // iMessage : shadow in light, border in dark.
        boxShadow: OuroColors.isDark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.12),
                  blurRadius: 20,
                  offset: const Offset(0, 6),
                ),
              ],
        border: OuroColors.isDark
            ? Border.all(
                color: OuroColors.separator,
                width: 0.5,
              )
            : null,
      ),
      child: SizedBox(
        height: 44,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < emojis.length; i++)
              Semantics(
                button: true,
                label: 'Réagir avec ${emojis[i]}',
                child: _Emoji(
                  emoji: emojis[i],
                  selected: current.contains(emojis[i]),
                  progress: ((progress - i * 0.07) / 0.6).clamp(0.0, 1.0),
                  onTap: () => onSelect(emojis[i]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Emoji extends StatefulWidget {
  const _Emoji({
    required this.emoji,
    required this.selected,
    required this.progress,
    required this.onTap,
  });

  final String emoji;
  final bool selected;
  final double progress;
  final VoidCallback onTap;

  @override
  State<_Emoji> createState() => _EmojiState();
}

class _EmojiState extends State<_Emoji> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    // iMessage : 28pt glyph, 44pt hit target.
    // Quand l'émojis est déjà sélectionné, appuyer fait rétrécir (0.85)
    // pour signaler « tap pour retirer ». Sinon, grossir (1.25) pour
    // signaler « tap pour ajouter ».
    final pressScale = widget.selected ? 0.85 : 1.25;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: SingleMotionBuilder(
        motion: const CupertinoMotion.snappy(),
        value: _pressed ? pressScale : 1.0,
        builder: (context, scale, child) => Transform.scale(
          scale: widget.progress * scale,
          child: child,
        ),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.selected
                    ? OuroColors.accent.withValues(alpha: 0.22)
                    : Colors.transparent,
              ),
              alignment: Alignment.center,
              child: Text(widget.emoji, style: const TextStyle(fontSize: 28)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Le petit panneau d'actions, dessiné comme un menu contextuel iOS :
/// intitulé à gauche, icône à droite, filets de séparation entre les
/// lignes, et la destruction en rouge tout en bas.
class _ActionMenu extends StatelessWidget {
  const _ActionMenu({
    required this.width,
    required this.rowHeight,
    required this.actions,
  });

  final double width;
  final double rowHeight;
  final List<MessageAction> actions;

  @override
  Widget build(BuildContext context) {
    return OuroCard(
      child: SizedBox(
        width: width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0)
                Divider(
                  height: 0.5,
                  thickness: 0.5,
                  color: OuroColors.separator,
                ),
              Semantics(
                button: true,
                label: actions[i].label,
                child: _ActionRow(action: actions[i], height: rowHeight),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatefulWidget {
  const _ActionRow({required this.action, required this.height});

  final MessageAction action;
  final double height;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.action.destructive
        ? OuroColors.systemRed
        : OuroColors.label;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: () {
        setState(() => _pressed = false);
        OuroHaptics.light();
        Navigator.of(context).pop();
        widget.action.onTap();
      },
      child: AnimatedContainer(
        duration: DesignTokens.durationFast,
        height: widget.height,
        // L'enfoncement iOS : la ligne s'assombrit sous le doigt, sans
        // onde qui se propage.
        color: _pressed ? OuroColors.systemFill : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.action.label,
                style: OuroTypography.callout.copyWith(color: color),
              ),
            ),
            Icon(widget.action.icon, size: 20, color: color),
          ],
        ),
      ),
    );
  }
}
