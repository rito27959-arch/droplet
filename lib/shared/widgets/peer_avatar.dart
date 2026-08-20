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
import '../../design_system/ouro_typography.dart';

/// Avatar circulaire à initiale, en aplat de couleur système.
class PeerAvatar extends StatelessWidget {
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
  ///
  /// ⚠️ NE JAMAIS Y METTRE LA VALEUR BRUTE DE `avatarUrl` : la base ne
  /// contient qu'un NOM de fichier, et le dossier de données d'une
  /// application Android n'est pas garanti stable d'une installation à
  /// l'autre. Le chemin se résout par `AvatarService.chemin(...)`, qui
  /// vérifie au passage que le fichier existe encore — après une
  /// restauration de sauvegarde sur un autre téléphone, il aura disparu.
  ///
  /// Quand il est nul, ou que la photo est illisible, on retombe sur
  /// l'initiale colorée. Une case vide serait pire qu'une initiale.
  final String? imagePath;

  /// Affiche la pastille verte « en ligne » en bas à droite.
  final bool online;

  /// Le pair a perdu ses liens mais on lui laisse sa chance.
  ///
  /// ⚠️ CET ÉTAT MÉRITE SA PROPRE COULEUR, et pas seulement pour faire
  /// joli. Dans Droplet, une liaison qui hoquette est le cas ORDINAIRE :
  /// le Bluetooth se coupe et se rétablit sans arrêt sans que personne
  /// ne bouge (voir `ConnectedPeer.reconnecting`). Peindre ces
  /// secondes-là en gris « hors ligne » ferait clignoter la pastille en
  /// permanence, et l'utilisateur apprendrait très vite à ne plus la
  /// regarder — ce qui la rendrait inutile le jour où elle dit quelque
  /// chose.
  ///
  /// L'ambre dit la vérité : « ça n'est pas coupé, ça se rétablit ».
  final bool reconnecting;

  /// Conservé pour compatibilité avec les écrans pas encore migrés —
  /// ignoré, les avatars sont désormais en aplat.
  final Gradient? gradient;

  /// Force une couleur précise, sinon elle est dérivée du pseudo.
  final Color? color;

  Widget _initiale(String initial) => Text(
        initial,
        style: OuroTypography.headline.copyWith(
          // L'initiale occupe un peu moins de la moitié du cercle : la
          // proportion qu'utilise iOS dans Contacts.
          fontSize: radius * 0.82,
          fontWeight: FontWeight.w500,
          color: Colors.white,
          letterSpacing: 0,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final initial = pseudo.trim().isEmpty
        ? '?'
        : pseudo.trim()[0].toUpperCase();

    // Le pseudo est transformé en nombre stable, qui désigne une couleur
    // de la palette — même pseudo, même couleur, toujours, sans stockage.
    final palette = OuroColors.avatarPalette;
    final resolved = color ?? palette[pseudo.hashCode.abs() % palette.length];

    return SizedBox(
      // ─────────────────────────────────────────────────────────────
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: radius * 2,
            height: radius * 2,
            decoration: BoxDecoration(shape: BoxShape.circle, color: resolved),
            alignment: Alignment.center,
            clipBehavior: Clip.antiAlias,
            child: imagePath != null
                ? Image.file(
                    File(imagePath!),
                    width: radius * 2,
                    height: radius * 2,
                    fit: BoxFit.cover,
                    // ⚠️ BORNES DE DÉCODAGE OBLIGATOIRES. Sans elles,
                    // Flutter décode l'image à la résolution de l'écran
                    // et la garde ainsi en cache : on paierait une image
                    // pleine page pour dessiner une pastille de
                    // quarante-huit points. L'avatar est carré, donc une
                    // seule borne suffit.
                    cacheWidth: (radius * 2 * 3).round(),
                    // Un fichier effacé entre deux images ne doit pas
                    // faire un carré rouge : on retombe sur l'initiale.
                    errorBuilder: (_, _, _) => _initiale(initial),
                    gaplessPlayback: true,
                  )
                : _initiale(initial),
          ),
          if (online || reconnecting)
            Positioned(
              right: 0,
              bottom: 0,
              // Le changement d'état se fond au lieu de sauter : une
              // pastille qui clignote attire l'œil bien plus que
              // l'information ne le mérite.
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOut,
                width: radius * 0.5,
                height: radius * 0.5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: online
                      ? OuroColors.systemGreen
                      : OuroColors.systemOrange,
                  // Le liseré sombre détache la pastille de l'avatar,
                  // exactement comme le fait iOS.
                  border: Border.all(
                    color: OuroColors.systemBackground,
                    width: radius * 0.09,
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
