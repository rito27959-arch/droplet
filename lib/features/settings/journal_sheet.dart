// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LA FEUILLE DU JOURNAL DES ERREURS, et le seul chemin pour l'ouvrir.
//
// Elle vivait dans l'écran des réglages, en privé. Depuis qu'un bandeau
// propose aussi d'envoyer un rapport après une fermeture inattendue,
// DEUX écrans en ont besoin — et une feuille recopiée dans les deux
// aurait fini par diverger : deux boutons « Envoyer » au comportement
// légèrement différent, deux textes qui ne disent pas la même chose de
// ce que le journal contient.
//
// ⚠️ CE QUE CETTE FEUILLE PROMET DOIT RESTER VRAI. Elle affirme que le
// journal ne contient ni messages, ni contacts, ni clés. C'est exact
// aujourd'hui (voir `CrashJournal`), et ça doit le rester : le jour où
// l'on y consignerait un identifiant de pair « pour aider au
// diagnostic », cette phrase deviendrait un mensonge affiché juste
// au-dessus d'un bouton d'envoi.
// ============================================================================

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/services/crash_journal.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_typography.dart';

/// Ouvre le journal des erreurs. Le seul point d'entrée.
Future<void> afficherJournal(BuildContext context) async {
  OuroHaptics.selection();
  final contenu = await CrashJournal.lire();
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => _JournalSheet(contenu: contenu),
  );
}

/// ce que dit le texte affiché — un utilisateur qui ouvre cet écran par
/// curiosité ne doit pas croire qu'il manque quelque chose.
class _JournalSheet extends StatelessWidget {
  const _JournalSheet({required this.contenu});

  final String? contenu;

  @override
  Widget build(BuildContext context) {
    final vide = contenu == null;
    return FrostedSheet(
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Journal des erreurs',
              style: OuroTypography.title1.copyWith(color: OuroColors.label),
            ),
            const SizedBox(height: DesignTokens.space1),
            Text(
              vide
                  ? 'Aucune erreur enregistrée. C\'est le cas normal.'
                  : 'Ces lignes restent sur cet appareil : Droplet n\'a '
                      'aucun serveur où les envoyer. Si vous testez '
                      'l\'application, transmettez-les — sans elles, le '
                      'défaut n\'existe pour personne.',
              style: OuroTypography.subheadline.copyWith(
                color: OuroColors.secondaryLabel,
              ),
            ),
            if (!vide) ...[
              const SizedBox(height: DesignTokens.space4),
              // Hauteur bornée : un journal peut faire des centaines de
              // lignes, et une feuille qui pousse jusqu'en haut de
              // l'écran ne se referme plus d'un geste.
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.45,
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    contenu!,
                    style: OuroTypography.footnote.copyWith(
                      color: OuroColors.secondaryLabel,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ),
              const SizedBox(height: DesignTokens.space4),
              Row(
                children: [
                  // ── ENVOYER, ET POURQUOI IL PASSE AVANT COPIER ──
                  //
                  // ⚠️ DROPLET N'A AUCUN SERVEUR : aucun rapport de
                  // plantage ne remonte nulle part, jamais. Quand
                  // l'application se ferme toute seule chez quelqu'un,
                  // la SEULE trace au monde est ce fichier — et si son
                  // propriétaire ne l'envoie pas, le défaut n'existe
                  // pour personne.
                  //
                  // Or « Copier » seul demandait cinq gestes : ouvrir
                  // les réglages, ouvrir le journal, copier, quitter
                  // l'application, retrouver le bon contact, coller.
                  // Un testeur qui doit faire cinq gestes ne les fait
                  // pas — et on perd le rapport, pas par mauvaise
                  // volonté, par friction. Ce bouton en fait deux.
                  //
                  // « Copier » reste : il sert quand on veut coller
                  // ailleurs que dans une application de partage.
                  TextButton.icon(
                    onPressed: () => _envoyer(context),
                    icon: const Icon(Icons.ios_share_rounded, size: 18),
                    label: const Text('Envoyer'),
                  ),
                  const SizedBox(width: DesignTokens.space2),
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: contenu!));
                      OuroHaptics.light();
                      Navigator.of(context).pop();
                    },
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: const Text('Copier'),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () async {
                      await CrashJournal.vider();
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: Text(
                      'Effacer',
                      style: TextStyle(color: OuroColors.errorRed),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Ouvre le partage du système avec le journal en pièce jointe.
  ///
  /// ⚠️ UN FICHIER, ET NON DU TEXTE BRUT.
  ///
  /// Le premier réflexe serait de passer le journal en `text:` du
  /// partage. Deux raisons de ne pas le faire :
  ///
  ///   1. le journal monte jusqu'à 64 Ko (voir `CrashJournal`), et les
  ///      applications de messagerie TRONQUENT les textes longs sans
  ///      prévenir — on recevrait un rapport amputé de sa fin, c'est-à-
  ///      dire précisément de l'erreur la plus récente ;
  ///   2. au-delà d'une certaine taille, l'intent Android échoue tout
  ///      court.
  ///
  /// Un fichier arrive entier, et la personne peut toujours ajouter une
  /// phrase en légende — laquelle vaut souvent plus que le journal.
  ///
  /// La feuille NE SE FERME PAS après l'envoi : on revient dessus, et
  /// « Effacer » est à portée de pouce. C'est ce qui évite de recevoir
  /// dix fois le même défaut.
  Future<void> _envoyer(BuildContext context) async {
    final texte = contenu;
    if (texte == null) return;
    OuroHaptics.light();
    try {
      final dossier = await getTemporaryDirectory();
      // Horodaté : deux rapports envoyés le même jour ne s'écrasent pas,
      // et le nom dit déjà de quand il date.
      final marque = DateTime.now().toIso8601String().substring(0, 16)
          .replaceAll(':', 'h').replaceAll('T', '_');
      final fichier = File('${dossier.path}/droplet-journal-$marque.txt');
      await fichier.writeAsString(texte, flush: true);

      await Share.shareXFiles(
        [XFile(fichier.path, mimeType: 'text/plain')],
        subject: 'Droplet — journal des erreurs',
        text: 'Journal des erreurs Droplet. Ce fichier ne contient ni '
            'messages, ni contacts, ni clés.',
      );
    } catch (e) {
      debugPrint('[Journal] partage impossible: $e');
      if (!context.mounted) return;
      // Le partage a échoué : plutôt que de laisser l'utilisateur sans
      // rien, on lui met quand même le journal dans le presse-papiers.
      Clipboard.setData(ClipboardData(text: texte));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Partage indisponible — journal copié'),
        ),
      );
    }
  }
}
