// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE PARTAGE DE POSITION dans une conversation : comment une position
// voyage, et la carte miniature qui s'affiche à l'arrivée.
//
// ── Pourquoi une position est un simple message texte ──────────────────
//
// Elle est encodée ainsi, et envoyée par le canal des messages :
//
//     📍loc:3.848212,11.502341
//
// Ce n'est pas un raccourci, c'est ce qui la rend fiable. Une position
// pèse quarante octets. En empruntant le canal des messages, elle
// hérite d'un coup de TOUT ce qui a été construit pour eux :
//
//   • le chiffrement de bout en bout,
//   • la file d'attente qui réessaie tant que ce n'est pas passé,
//   • l'accusé de réception,
//   • le relais par les téléphones intermédiaires,
//   • la conservation hors ligne jusqu'à ce qu'un chemin s'ouvre.
//
// Inventer un type de paquet dédié aurait imposé de redévelopper tout
// cela — et un téléphone équipé d'une version antérieure de Droplet
// n'aurait rien reçu. Ici, au pire, il affiche une ligne de texte avec
// des coordonnées : compréhensible, et copiable.
//
// ── L'emoji en tête n'est pas décoratif ────────────────────────────────
//
// Il sert de repère visuel dans les aperçus (liste des conversations,
// notifications) là où le message n'est pas interprété. On y lit « 📍 »
// plutôt qu'une suite de chiffres.
// ============================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../maps/offline_tile_store.dart';

/// Encode et décode une position partagée dans une conversation.
class LocationMessage {
  const LocationMessage({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  static const String _prefix = '📍loc:';

  /// Le texte à envoyer.
  ///
  /// Six décimales, soit une précision d'environ dix centimètres : bien
  /// au-delà de ce que fait un GPS de téléphone, et suffisamment court
  /// pour ne pas alourdir un paquet Bluetooth.
  static String encode(double latitude, double longitude) =>
      '$_prefix${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';

  /// Relit une position depuis le texte d'un message, ou `null` si ce
  /// message n'en est pas un.
  static LocationMessage? tryParse(String content) {
    final text = content.trim();
    if (!text.startsWith(_prefix)) return null;

    final parts = text.substring(_prefix.length).split(',');
    if (parts.length != 2) return null;

    final lat = double.tryParse(parts[0]);
    final lon = double.tryParse(parts[1]);
    if (lat == null || lon == null) return null;
    // Des coordonnées hors bornes viennent d'un message abîmé : mieux
    // vaut afficher le texte brut que placer un point n'importe où.
    if (lat.abs() > 90 || lon.abs() > 180) return null;

    return LocationMessage(latitude: lat, longitude: lon);
  }

  /// Ce qu'on écrit dans les aperçus (liste des conversations,
  /// notifications) à la place des coordonnées.
  static String describe(String content) =>
      tryParse(content) == null ? content : '📍 Position partagée';
}

// ─────────────────────────────────────────────────────────────
//  LA VIGNETTE DANS LA BULLE
// ─────────────────────────────────────────────────────────────

/// La petite carte affichée dans une bulle de conversation.
///
/// Elle est dessinée à partir des tuiles DÉJÀ présentes sur l'appareil :
/// aucune requête réseau n'est faite pour l'afficher. Si la zone n'a
/// jamais été consultée, un fond neutre s'affiche à la place, avec les
/// coordonnées — l'information reste utilisable, seule l'illustration
/// manque.
class LocationBubble extends StatelessWidget {
  const LocationBubble({
    super.key,
    required this.location,
    required this.mine,
    required this.onOpen,
  });

  final LocationMessage location;
  final bool mine;
  final VoidCallback onOpen;

  /// Le zoom de la vignette. 15 montre le quartier : assez près pour
  /// reconnaître l'endroit, assez loin pour le situer.
  static const int _zoom = 15;

  @override
  Widget build(BuildContext context) {
    final onBubble = mine ? Colors.white : OuroColors.label;

    return GestureDetector(
      onTap: onOpen,
      child: SizedBox(
        width: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              child: SizedBox(
                height: 132,
                width: 220,
                child: _MiniMap(location: location, zoom: _zoom),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.near_me_rounded, size: 15, color: onBubble),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Position partagée',
                    style: OuroTypography.subheadline.copyWith(
                      color: onBubble,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '${location.latitude.toStringAsFixed(4)}, '
              '${location.longitude.toStringAsFixed(4)}',
              style: OuroTypography.caption1.copyWith(
                color: onBubble.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Les quatre tuiles qui entourent la position, assemblées.
///
/// Quatre plutôt qu'une : la position tombe rarement au centre d'une
/// tuile, et une seule laisserait le point collé à un bord, sans
/// contexte autour.
class _MiniMap extends StatelessWidget {
  const _MiniMap({required this.location, required this.zoom});

  final LocationMessage location;
  final int zoom;

  /// Convertit une latitude et une longitude en coordonnées de tuile.
  ///
  /// C'est la projection de Mercator, celle qu'utilisent toutes les
  /// cartes du web : la longitude se répartit linéairement, la latitude
  /// passe par un logarithme — c'est ce qui explique que le Groenland
  /// paraisse aussi grand que l'Afrique.
  static ({double x, double y}) _project(double lat, double lon, int z) {
    final n = 1 << z;
    final x = (lon + 180.0) / 360.0 * n;
    final latRad = lat * math.pi / 180.0;
    final y = (1.0 -
            math.log(math.tan(latRad) + 1 / math.cos(latRad)) / math.pi) /
        2.0 *
        n;
    return (x: x, y: y);
  }

  @override
  Widget build(BuildContext context) {
    final p = _project(location.latitude, location.longitude, zoom);
    final tileX = p.x.floor();
    final tileY = p.y.floor();

    // La position du point À L'INTÉRIEUR de sa tuile, entre 0 et 1.
    final fx = p.x - tileX;
    final fy = p.y - tileY;

    // ⚠️ Y A-T-IL SEULEMENT UNE CARTE À MONTRER ?
    //
    // `_Tile` ne lit que le cache local — Droplet ne télécharge JAMAIS
    // de tuile pour une bulle de conversation : ce serait neuf requêtes
    // réseau par message de position, dans une application dont l'
    // argument est de fonctionner sans réseau.
    //
    // Conséquence : si l'utilisateur n'a jamais parcouru cette zone sur
    // la grande carte, il n'y a rien en cache. L'ancienne version
    // affichait alors un RECTANGLE NOIR avec un point rouge au milieu —
    // ce qui ne ressemble pas à « pas de carte », mais à « c'est cassé ».
    //
    // On le dit donc franchement, avec les coordonnées qui, elles, sont
    // toujours exactes. L'information utile passe ; l'app n'a pas l'air
    // en panne.
    final centre = OfflineTileStore.instance.read(zoom, tileX, tileY);
    if (centre == null || centre.isEmpty) return const _CarteAbsente();

    return LayoutBuilder(
      builder: (context, constraints) {
        const tileSize = 256.0;
        // On centre l'assemblage sur le point : le décalage place la
        // position exactement au milieu de la vignette.
        final dx = constraints.maxWidth / 2 - (fx + 1) * tileSize;
        final dy = constraints.maxHeight / 2 - (fy + 1) * tileSize;

        return ColoredBox(
          color: const Color(0xFF14161A),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              for (var ox = 0; ox < 3; ox++)
                for (var oy = 0; oy < 3; oy++)
                  Positioned(
                    left: dx + ox * tileSize,
                    top: dy + oy * tileSize,
                    width: tileSize,
                    height: tileSize,
                    child: _Tile(
                      z: zoom,
                      x: tileX + ox - 1,
                      y: tileY + oy - 1,
                    ),
                  ),
              // Le point, au centre exact.
              Center(
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: OuroColors.systemRed,
                    border: Border.all(color: Colors.white, width: 2.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.45),
                        blurRadius: 6,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Une tuile lue sur l'appareil, ou rien.
/// Ce qu'on montre quand aucune tuile n'est enregistrée pour la zone.
///
/// Volontairement sobre : une trame discrète, un repère, une phrase. Le
/// but n'est pas de faire semblant d'avoir une carte, mais de rendre
/// l'absence lisible — et de rappeler comment y remédier.
class _CarteAbsente extends StatelessWidget {
  const _CarteAbsente();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: OuroColors.systemGray5,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.map_outlined,
            size: 26,
            color: OuroColors.tertiaryLabel,
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'Fond de carte non enregistré pour cette zone',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                height: 1.25,
                color: OuroColors.secondaryLabel,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.z, required this.x, required this.y});

  final int z;
  final int x;
  final int y;

  @override
  Widget build(BuildContext context) {
    final bytes = OfflineTileStore.instance.read(z, x, y);
    if (bytes == null || bytes.isEmpty) return const SizedBox.shrink();
    return Image.memory(
      bytes,
      fit: BoxFit.cover,
      gaplessPlayback: true,
      // Une tuile illisible ne doit pas casser la bulle entière.
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}
