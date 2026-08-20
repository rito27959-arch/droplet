// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LA FEUILLE QUI EXPLIQUE COMMENT UN MESSAGE EST PARTI.
//
// On l'ouvre en touchant l'heure d'un message. C'est l'endroit où Droplet
// dit ce qu'aucune autre messagerie ne peut dire : non pas seulement
// « envoyé », mais PAR OÙ.
//
// ── ⚠️ TOUT CE QUI EST AFFICHÉ ICI EST UNE DONNÉE RÉELLE ──────────────
//
// C'est la contrainte la plus importante de ce fichier, et elle a
// restreint ce qu'il montre.
//
// Il aurait été facile — et joli — de dessiner un chemin nommé :
//
//     Moi ↓ Pair A ↓ Pair B ↓ Michel
//
// Le modèle porte bien un champ `routeInfo` prévu pour ça, et la base de
// données a la colonne. Mais AUCUN code ne le remplit : seul le code
// généré par Drift le mentionne. Dessiner ce chemin reviendrait donc à
// inventer les noms des relais — c'est-à-dire à fabriquer une preuve
// technique fausse, dans une application dont l'argument principal est
// précisément qu'on peut lui faire confiance sur la transmission.
//
// Cette feuille montre donc ce que le système sait vraiment :
//
//   • `status` + `readAt` + `deliveryCount` → où en est le message ;
//   • `hopCount` → combien d'appareils il a traversés ;
//   • l'heure d'envoi et l'heure de lecture → le délai réel.
//
// Il n'y a délibérément AUCUNE ligne « chiffré / non chiffré ». Le
// chiffrement existe bel et bien — mais il vit dans l'enveloppe réseau
// (`e` et `n`, voir `resolveIncomingContent`), et n'est PAS conservé
// dans le message enregistré. Afficher un cadenas ici reviendrait donc à
// affirmer, sans preuve, quelque chose que le système ne sait plus. Sur
// une application dont le chiffrement est un argument central, une
// affirmation de sécurité non vérifiée est la pire chose à écrire.
//
// Le jour où la couche mesh enregistrera le chemin dans `routeInfo`, le
// bloc « Chemin » viendra ici sans rien changer d'autre.
// ============================================================================

import 'package:flutter/material.dart';

import '../../core/models/mesh_message.dart';
import '../../core/repositories/mesh_repository.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_typography.dart';

/// Ouvre la feuille de transmission pour [message].
Future<void> showTransmissionSheet(
  BuildContext context,
  MeshMessage message, {
  required bool mine,
}) {
  OuroHaptics.selection();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _TransmissionSheet(message: message, mine: mine),
  );
}

class _TransmissionSheet extends StatelessWidget {
  const _TransmissionSheet({required this.message, required this.mine});

  final MeshMessage message;
  final bool mine;

  /// L'état, en une phrase compréhensible sans rien connaître au mesh.
  ///
  /// Le brief est explicite : un utilisateur normal doit comprendre. Les
  /// mots « ACK », « saut » et « TTL » n'apparaissent donc nulle part.
  (String, IconData, Color) get _etat {
    if (message.status == MessageStatus.failed) {
      return ('Non distribué', Icons.error_outline_rounded,
          OuroColors.errorRed);
    }
    if (message.readAt != null) {
      return ('Lu', Icons.done_all_rounded, OuroColors.meshBlueBright);
    }
    if (message.deliveryCount > 0) {
      return ('Distribué', Icons.done_all_rounded, OuroColors.successGreen);
    }
    return switch (message.status) {
      MessageStatus.sending => ('Envoi en cours', Icons.schedule_rounded,
          OuroColors.textSecondary),
      MessageStatus.pending => ('En attente d\'un relais',
          Icons.schedule_rounded, OuroColors.textSecondary),
      _ => ('Envoyé', Icons.done_rounded, OuroColors.textSecondary),
    };
  }

  /// Le temps écoulé entre l'envoi et la lecture.
  ///
  /// Renvoie `null` tant que le message n'a pas été lu : il n'existe
  /// aucun horodatage de simple réception dans le modèle, et en inventer
  /// un à partir de `deliveryCount` donnerait un chiffre faux.
  String? get _delai {
    final lu = message.readAt;
    if (lu == null) return null;
    final d = lu.difference(message.timestamp);
    if (d.isNegative) return null;
    if (d.inSeconds < 60) {
      return '${(d.inMilliseconds / 1000).toStringAsFixed(1)} seconde'
          '${d.inSeconds > 1 ? 's' : ''}';
    }
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    if (d.inHours < 24) return '${d.inHours} h';
    return '${d.inDays} jours';
  }

  @override
  Widget build(BuildContext context) {
    final (libelle, icone, couleur) = _etat;
    final delai = _delai;
    // ⚠️ LE CALCUL DES SAUTS, ET POURQUOI IL NE VAUT QUE POUR LES
    // MESSAGES REÇUS.
    //
    // `hopCount` n'est PAS le nombre de relais traversés : c'est le
    // nombre de relais qu'il RESTE au message avant qu'on cesse de le
    // faire suivre. Il part de `kDefaultHopCount` (5) et perd un point à
    // chaque appareil traversé (voir `_relayNow`).
    //
    // Sur un message REÇU, la soustraction donne donc le trajet réel :
    // arrivé avec 3 points restants, il a franchi deux appareils.
    //
    // Sur un message ENVOYÉ, la valeur stockée est toujours 5 — celle du
    // départ. Elle ne dit rien du trajet, parce que rien ne revient nous
    // le raconter : l'accusé de réception ne transporte pas le chemin.
    // Une version précédente affichait ce 5 comme « relayé par 5
    // appareils » sur chacun de nos propres messages. C'était faux à tous
    // les coups.
    final sauts = mine ? null : (MeshRepository.kDefaultHopCount - message.hopCount);

    return FrostedSheet(
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Transmission',
              style: OuroTypography.title3.copyWith(color: OuroColors.label),
            ),
            const SizedBox(height: DesignTokens.space4),

            _Ligne(
              icone: icone,
              couleur: couleur,
              titre: 'Statut',
              valeur: libelle,
            ),

            if (delai != null)
              _Ligne(
                icone: Icons.timer_outlined,
                couleur: OuroColors.systemGray,
                titre: 'Délai jusqu\'à la lecture',
                valeur: delai,
              ),

            // ── LE CHEMIN NOMMÉ ─────────────────────────────────
            //
            // Ce que cette feuille ne pouvait pas montrer jusqu'ici : par
            // QUELS appareils le message est passé. Chaque relais signe
            // désormais son passage dans l'enveloppe (`_signerLePassage`),
            // et le destinataire reçoit le trajet complet.
            //
            // C'est la seule chose qu'aucune autre messagerie ne peut
            // afficher — parce qu'aucune autre ne fait transiter les
            // messages par les téléphones de ses utilisateurs.
            if (message.routeInfo != null && message.routeInfo!.isNotEmpty)
              _Ligne(
                icone: Icons.route_rounded,
                couleur: OuroColors.systemPurple,
                titre: 'Trajet',
                valeur: message.routeInfo!,
                detail: 'Les appareils qui ont fait suivre ce message, '
                    'dans l\'ordre.',
              ),

            // Le nombre de sauts — affiché seulement quand il est CONNU.
            if (sauts != null)
              _Ligne(
                icone: sauts > 0
                    ? Icons.alt_route_rounded
                    : Icons.arrow_forward_rounded,
                couleur: sauts > 0
                    ? OuroColors.systemPurple
                    : OuroColors.systemGreen,
                titre: 'Chemin',
                valeur: sauts > 0
                    ? 'Passé par $sauts appareil${sauts > 1 ? 's' : ''}'
                    : 'Reçu en direct',
                // ⚠️ La phrase qui justifie toute l'application. Un
                // relais n'est pas une dégradation : c'est ce qui permet
                // au message d'arriver là où aucun réseau ne va.
                detail: sauts > 0
                    ? 'Des appareils intermédiaires ont fait suivre ce '
                        'message jusqu\'à vous.'
                    : null,
              )
            else
              // Pour nos propres messages, on dit qu'on ne sait pas —
              // plutôt que de meubler avec un chiffre inventé.
              _Ligne(
                icone: Icons.help_outline_rounded,
                couleur: OuroColors.systemGray,
                titre: 'Chemin',
                valeur: 'Inconnu',
                detail: 'Le trajet d\'un message envoyé n\'est pas renvoyé '
                    'à son expéditeur.',
              ),

            _Ligne(
              icone: Icons.wifi_tethering_rounded,
              couleur: OuroColors.accent,
              titre: 'Réseau',
              valeur: 'Mesh Droplet',
              detail: 'Aucun serveur, aucun opérateur.',
            ),

            const SizedBox(height: DesignTokens.space2),
          ],
        ),
      ),
    );
  }
}

class _Ligne extends StatelessWidget {
  const _Ligne({
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
                    style: OuroTypography.caption1.copyWith(
                      color: OuroColors.tertiaryLabel,
                    ),
                  ),
                  Text(
                    valeur,
                    style: OuroTypography.body.copyWith(
                      color: OuroColors.label,
                    ),
                  ),
                  if (detail != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        detail!,
                        style: OuroTypography.footnote.copyWith(
                          color: OuroColors.secondaryLabel,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
