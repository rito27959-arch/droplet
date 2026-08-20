// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est le petit menu qui remonte du bas de l'écran quand on reste
// appuyé sur un message (comme sur WhatsApp) : une rangée de 6 émojis à
// choisir pour réagir (👍❤️😂😮😢🙏), et en dessous, des actions comme
// « Répondre », « Copier », « Supprimer ». Chaque bouton se ferme le
// menu automatiquement après avoir été touché, et les émojis ont une
// petite animation d'apparition en cascade (chacun arrive un chouïa
// après le précédent) pour que ça paraisse vivant plutôt que figé.
//
// Les trois actions (répondre/copier/supprimer) sont FACULTATIVES —
// selon l'écran qui affiche ce menu, on peut choisir de n'en montrer
// que certaines (par exemple, pas de « supprimer » sur un message qu'on
// n'a pas envoyé soi-même) simplement en ne fournissant pas la fonction
// correspondante.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_pressable.dart';
import '../../design_system/design_tokens.dart';

/// Menu d'actions sur un message (style WhatsApp) : réactions rapides +
/// répondre / copier / supprimer.
class ReactionPicker extends StatelessWidget {
  const ReactionPicker({
    super.key,
    required this.current,
    required this.onSelect,
    this.onReply,
    this.onCopy,
    this.onSave,
    this.onDelete,
  });

  final List<String> current;
  final void Function(String emoji) onSelect;

  /// Répondre au message — null pour masquer l'action.
  final VoidCallback? onReply;

  /// Copier le contenu du message — null pour masquer l'action.
  final VoidCallback? onCopy;

  /// Enregistrer la pièce jointe dans la galerie du téléphone —
  /// proposé uniquement sur les messages qui en portent une.
  final VoidCallback? onSave;

  /// Supprimer le message (localement) — null pour masquer l'action.
  final VoidCallback? onDelete;

  static const List<String> _emojis = ['👍', '❤️', '😂', '😮', '😢', '🙏'];

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        decoration: BoxDecoration(
          color: OuroColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          border: Border(top: BorderSide(color: OuroColors.glassBorder, width: 0.5)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: OuroColors.textTertiary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 18),
            Text('Réagir',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: OuroColors.textPrimary)),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: _emojis.map((e) {
                final selected = current.contains(e);
                return GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    onSelect(e);
                  },
                  child: Column(
                    children: [
                      AnimatedScale(
                        scale: selected ? 1.25 : 1.0,
                        duration: DesignTokens.durationNormal,
                        curve: Curves.easeOutCubic,
                        child: AnimatedContainer(
                          duration: DesignTokens.durationFast,
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? OuroColors.meshBlue.withValues(alpha: 0.25) : Colors.transparent,
                            border: Border.all(
                              color: selected ? OuroColors.meshBlue : Colors.transparent,
                              width: 1.5,
                            ),
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 30)),
                        ),
                      ),
                    ],
                  ),
                ).animate().scale(
                  begin: const Offset(0, 0.5),
                  end: const Offset(1, 1),
                  duration: 400.ms,
                  curve: Curves.easeOutCubic,
                  delay: (_emojis.indexOf(e) * 60).ms,
                );
              }).toList(),
            ),
            if (onReply != null ||
                onCopy != null ||
                onSave != null ||
                onDelete != null) ...[
              const SizedBox(height: 18),
              Divider(color: OuroColors.glassBorder, height: 1),
              if (onReply != null)
                _ActionRow(
                  icon: Icons.reply_rounded,
                  label: 'Répondre',
                  onTap: () { Navigator.pop(context); onReply!(); },
                ),
              if (onCopy != null)
                _ActionRow(
                  icon: Icons.copy_rounded,
                  label: 'Copier',
                  onTap: () { Navigator.pop(context); onCopy!(); },
                ),
              if (onSave != null)
                _ActionRow(
                  icon: Icons.download_rounded,
                  label: 'Enregistrer sur le téléphone',
                  onTap: () { Navigator.pop(context); onSave!(); },
                ),
              if (onDelete != null)
                _ActionRow(
                  icon: Icons.delete_outline_rounded,
                  label: 'Supprimer',
                  color: OuroColors.errorRed,
                  onTap: () { Navigator.pop(context); onDelete!(); },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Une seule ligne d'action (icône + texte), utilisée pour Répondre,
/// Copier et Supprimer.
class _ActionRow extends StatelessWidget {
  const _ActionRow({required this.icon, required this.label, required this.onTap, this.color});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? OuroColors.textPrimary;
    // Enfoncement iOS, pas l'onde de Material : c'est un menu contextuel
    // posé au-dessus d'un message, l'endroit où une onde qui se propage
    // se remarque le plus.
    return OuroPressable(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: c),
            const SizedBox(width: 14),
            Text(label, style: TextStyle(fontSize: 15, color: c, fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
