// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le petit rond coloré avec une initiale qui représente chaque personne,
// faute de photo de profil (Droplet n'a ni compte ni serveur pour en
// héberger).
//
// CE QUI A CHANGÉ À LA REFONTE :
//   - Plus de DÉGRADÉ. Un aplat de couleur unie, comme les avatars de
//     Contacts et Messages sur iOS. Le dégradé sur un si petit élément
//     se lit comme du bruit, jamais comme une intention.
//   - Plus d'OMBRE PORTÉE. Sur un fond noir, elle ne se voit pas et
//     coûte du temps de rendu à chaque image affichée.
//   - Palette limitée aux teintes système d'Apple (voir `ouro_colors`).
//
// L'astuce d'origine est conservée : la couleur est CALCULÉE à partir du
// pseudo, donc la même personne garde toujours la même, sans que Droplet
// ait à la mémoriser où que ce soit.
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import '../../design_system/ouro_colors.dart';

/// Avatar circulaire à initiale, en aplat de couleur système.
///
/// L'avatar réagit à l'état du réseau :
/// - **En ligne** : pastille verte avec un léger pulse lumineux.
/// - **Reconnexion** : pastille orange (pas de pulse, statut transitoire).
/// - **Hors ligne** : pastille grise (désaturée), sans pastille d'état.
/// - **Pulse** : un anneau lumineux se propage quand le peer est en ligne.
class PeerAvatar extends StatefulWidget {
  const PeerAvatar({
    super.key,
    required this.pseudo,
    this.radius = 24,
    this.online = false,
    this.reconnecting = false,
    this.gradient,
    this.color,
    this.imagePath,
  });

  final String pseudo;
  final double radius;

  /// Le chemin ABSOLU d'une photo de profil, s'il y en a une.
  final String? imagePath;

  /// Affiche la pastille verte « en ligne » en bas à droite.
  final bool online;

  /// Le pair a perdu ses liens mais on lui laisse sa chance.
  final bool reconnecting;

  /// Conservé pour compatibilité avec les écrans pas encore migrés.
  final Gradient? gradient;

  /// Force une couleur précise, sinon elle est dérivée du pseudo.
  final Color? color;

  @override
  State<PeerAvatar> createState() => _PeerAvatarState();
}

class _PeerAvatarState extends State<PeerAvatar>
    with SingleTickerProviderStateMixin {
  AnimationController? _pulseController;

  @override
  void initState() {
    super.initState();
    if (widget.online) _startPulse();
  }

  @override
  void didUpdateWidget(PeerAvatar old) {
    super.didUpdateWidget(old);
    if (widget.online && !old.online) {
      _startPulse();
    } else if (!widget.online && old.online) {
      _stopPulse();
    }
  }

  void _startPulse() {
    _pulseController?.dispose();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    );
    // Pulse subtil : l'opacité de l'anneau varie, pas la taille
    _pulseController!.repeat(reverse: true);
  }

  void _stopPulse() {
    _pulseController?.stop();
    _pulseController?.dispose();
    _pulseController = null;
  }

  @override
  void dispose() {
    _stopPulse();
    super.dispose();
  }

  Widget _initiale(String initial) => Text(
        initial,
        style: TextStyle(
          fontSize: widget.radius * 0.82,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          letterSpacing: 0,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final initial = widget.pseudo.trim().isEmpty
        ? '?'
        : widget.pseudo.trim()[0].toUpperCase();

    final palette = OuroColors.avatarPalette;
    final resolved =
        widget.color ?? palette[widget.pseudo.hashCode.abs() % palette.length];

    // Désactivation des couleurs si hors ligne
    final avatarColor =
        widget.online ? resolved : Color.lerp(resolved, Colors.grey, 0.55)!;

    return SizedBox(
      width: widget.radius * 2,
      height: widget.radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Anneau pulse quand en ligne
          if (widget.online && _pulseController != null)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _pulseController!,
                builder: (context, child) {
                  final t = _pulseController!.value;
                  return Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: OuroColors.systemGreen.withValues(alpha: t * 0.3),
                        width: 2 + t * 2,
                      ),
                    ),
                  );
                },
              ),
            ),
          // Avatar principal
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOut,
            width: widget.radius * 2,
            height: widget.radius * 2,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: avatarColor,
            ),
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            child: widget.imagePath != null
                ? Image.file(
                    File(widget.imagePath!),
                    width: widget.radius * 2,
                    height: widget.radius * 2,
                    fit: BoxFit.cover,
                    cacheWidth: (widget.radius * 2 * 3).round(),
                    errorBuilder: (_, _, _) => _initiale(initial),
                    gaplessPlayback: true,
                  )
                : _initiale(initial),
          ),
          // Pastille d'état
          if (widget.online || widget.reconnecting)
            Positioned(
              right: 0,
              bottom: 0,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: widget.radius * 0.5,
                height: widget.radius * 0.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.online
                      ? OuroColors.systemGreen
                      : OuroColors.systemOrange,
                  border: Border.all(
                    color: OuroColors.systemBackground,
                    width: widget.radius * 0.09,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Formatte un horodatage à la façon de Messages sur iOS : l'heure seule
/// si c'est aujourd'hui, « Hier », le jour de la semaine si c'est dans la
/// semaine écoulée, sinon la date.
String formatMessageTime(DateTime t) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final that = DateTime(t.year, t.month, t.day);
  final diffDays = today.difference(that).inDays;

  if (diffDays == 0) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }
  if (diffDays == 1) return 'Hier';
  if (diffDays < 7) {
    const days = [
      'Lundi',
      'Mardi',
      'Mercredi',
      'Jeudi',
      'Vendredi',
      'Samedi',
      'Dimanche',
    ];
    return days[t.weekday - 1];
  }
  return '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${t.year % 100}';
}
