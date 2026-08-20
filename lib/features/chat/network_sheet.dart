// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE PANNEAU « RÉSEAU DROPLET », ouvert depuis l'en-tête d'une
// conversation.
//
// ── Pourquoi il n'est PAS affiché en permanence ───────────────────────
//
// La tentation, sur une application dont le réseau maillé est l'argument
// principal, est de le montrer tout le temps : un bandeau de statistiques
// en haut du fil, des compteurs qui bougent. C'est exactement ce qu'il ne
// faut pas faire.
//
// Quelqu'un qui écrit à un ami ne veut pas savoir combien de relais sont
// disponibles — il veut envoyer son message. Poser cette information en
// permanence sous ses yeux la transforme en bruit, et fait ressembler
// l'application à un outil de diagnostic plutôt qu'à une messagerie.
//
// Elle est donc rangée UN GESTE PLUS LOIN : celui qui est curieux la
// trouve, celui qui discute ne la voit jamais. C'est le principe que le
// cahier des charges résume par « l'utilisateur normal doit pouvoir
// discuter sans comprendre la technologie ».
//
// ── ⚠️ TOUT VIENT DE COMPTEURS RÉELS ──────────────────────────────────
//
// Chaque chiffre affiché est lu dans l'état vivant du transport
// (`meshPeerListProvider`, `MeshStats`) — rien n'est estimé, rien n'est
// arrondi pour faire joli. Sur une application qui demande qu'on lui
// fasse confiance pour acheminer des messages sans serveur, un compteur
// décoratif serait pire qu'un compteur absent.
//
// Une conséquence assumée : quand il n'y a personne, le panneau le dit
// franchement au lieu d'afficher un zéro qui ressemble à une panne.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/mesh_provider.dart';
import '../../core/services/mesh_transport_service.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_typography.dart';

/// Ouvre le panneau réseau.
Future<void> showNetworkSheet(BuildContext context) {
  OuroHaptics.selection();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const _NetworkSheet(),
  );
}

class _NetworkSheet extends ConsumerWidget {
  const _NetworkSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairs = ref.watch(meshPeerListProvider);

    // Un pair « joignable » est un pair qui a au moins un chemin ouvert.
    // Ceux en cours de reconnexion sont comptés à part : les mélanger
    // ferait annoncer des interlocuteurs à qui rien ne part.
    final joignables = pairs.where((p) => !p.reconnecting).toList();
    final enReconnexion = pairs.length - joignables.length;

    // Un relais, c'est un pair joignable DIRECTEMENT (sans intermédiaire)
    // : lui seul peut faire suivre nos messages vers plus loin.
    final relais = joignables.where((p) => p.hopCount == 0).length;

    final ble = joignables
        .where((p) => p.transports.contains(TransportKind.ble))
        .length;
    final wifi = joignables
        .where((p) =>
            p.transports.contains(TransportKind.localWifi) ||
            p.transports.contains(TransportKind.nativeP2P))
        .length;

    final actif = joignables.isNotEmpty;

    return FrostedSheet(
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: actif
                        ? OuroColors.systemGreen
                        : OuroColors.systemGray,
                  ),
                ),
                const SizedBox(width: DesignTokens.space2),
                Text(
                  actif ? 'Mesh actif' : 'Aucun appareil à portée',
                  style:
                      OuroTypography.title3.copyWith(color: OuroColors.label),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.space2),
            Text(
              actif
                  // La phrase qui retourne la perception : ici, l'absence
                  // d'Internet n'est pas une panne, c'est le mode normal.
                  ? 'Vos messages circulent d\'appareil en appareil, sans '
                      'passer par Internet.'
                  : 'Rapprochez-vous d\'un autre appareil Droplet. Vos '
                      'messages sont conservés et repartiront tout seuls.',
              style: OuroTypography.footnote.copyWith(
                color: OuroColors.secondaryLabel,
              ),
            ),
            const SizedBox(height: DesignTokens.space5),

            _Compteur(
              icone: Icons.people_alt_rounded,
              couleur: OuroColors.accent,
              titre: 'Appareils à portée',
              valeur: '${joignables.length}',
            ),
            if (enReconnexion > 0)
              _Compteur(
                icone: Icons.sync_rounded,
                couleur: OuroColors.systemOrange,
                titre: 'En reconnexion',
                valeur: '$enReconnexion',
                detail: 'Liaison momentanément perdue, pas encore abandonnée.',
              ),
            _Compteur(
              icone: Icons.alt_route_rounded,
              couleur: OuroColors.systemPurple,
              titre: 'Relais disponibles',
              valeur: '$relais',
              detail: relais == 0
                  ? 'Aucun appareil ne peut faire suivre vos messages plus '
                      'loin pour l\'instant.'
                  : null,
            ),
            _Compteur(
              icone: Icons.bluetooth_rounded,
              couleur: OuroColors.systemTeal,
              titre: 'Par Bluetooth',
              valeur: '$ble',
            ),
            _Compteur(
              icone: Icons.wifi_rounded,
              couleur: OuroColors.systemGreen,
              titre: 'Par Wi-Fi local',
              valeur: '$wifi',
              detail: 'Le Wi-Fi porte les fichiers et la voix ; le Bluetooth '
                  'ne transporte que le texte.',
            ),
            const SizedBox(height: DesignTokens.space2),
          ],
        ),
      ),
    );
  }
}

class _Compteur extends StatelessWidget {
  const _Compteur({
    required this.icone,
    required this.couleur,
    required this.titre,
    required this.valeur,
    this.detail,
  });

  final IconData icone;
  final Color couleur;
  final String titre;
  final String valeur;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$titre : $valeur${detail != null ? '. $detail' : ''}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(bottom: DesignTokens.space4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icone, size: 19, color: couleur),
            const SizedBox(width: DesignTokens.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    titre,
                    style: OuroTypography.body
                        .copyWith(color: OuroColors.label),
                  ),
                  if (detail != null)
                    Text(
                      detail!,
                      style: OuroTypography.footnote.copyWith(
                        color: OuroColors.secondaryLabel,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: DesignTokens.space2),
            Text(
              valeur,
              style: OuroTypography.title3.copyWith(color: OuroColors.label),
            ),
          ],
        ),
      ),
    );
  }
}
