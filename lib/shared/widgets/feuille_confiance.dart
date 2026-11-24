// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LES MENTIONS DE CONFIANCE ET LEUR FEUILLE D'EXPLICATION.
//
// Une messagerie chiffrée doit le DIRE au bon endroit, sans en faire un
// argument publicitaire : une ligne discrète en bas de la liste des
// discussions, une bulle neutre en haut de chaque conversation. Un toucher
// sur la mention fait monter une feuille (comme chez les grandes messageries)
// qui explique en trois points, avec des mots simples, ce que cela veut dire.
// Un bouton « En savoir plus » ouvre la section exacte du site de Droplet.
//
// ⚠️ CE FICHIER N'EXPLIQUE QUE CE QUE DROPLET FAIT VRAIMENT.
// Chaque phrase reprend la page Sécurité du site (dropletmesh.app/security/).
// Si le chiffrement change, ces textes changent avec lui — jamais l'inverse.
// Ce fichier ne touche ni au chiffrement ni au réseau maillé : il les décrit.
// ============================================================================

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../design_system/design_tokens.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/liquid_bridge.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_typography.dart';

/// Les sujets qu'une mention peut expliquer, chacun relié à sa section du site.
enum SujetConfiance { chiffrement, relais, identite, appels, ephemeres, limites }

class _Point {
  const _Point(this.icone, this.texte);
  final IconData icone;
  final String texte;
}

class _Explication {
  const _Explication({
    required this.icone,
    required this.titre,
    required this.chapeau,
    required this.points,
    required this.ancre,
  });
  final IconData icone;
  final String titre;
  final String chapeau;
  final List<_Point> points;

  /// La section de la page Sécurité du site (`#ancre`).
  final String ancre;
}

const _site = 'https://dropletmesh.app/security/';

const Map<SujetConfiance, _Explication> _explications = {
  SujetConfiance.chiffrement: _Explication(
    icone: Icons.lock_rounded,
    titre: 'Chiffré de bout en bout',
    chapeau:
        'Vos messages personnels restent entre vous et la personne à qui vous écrivez. Personne d\'autre ne peut les lire, pas même Droplet.',
    points: [
      _Point(Icons.smartphone_rounded,
          'Un message est chiffré sur votre téléphone, et ne redevient lisible que sur celui de votre destinataire.'),
      _Point(Icons.key_rounded,
          'Chaque message a sa propre clé. Une clé dérobée n\'ouvrirait ni les messages d\'avant, ni ceux d\'après.'),
      _Point(Icons.mail_lock_rounded,
          'Les téléphones et les serveurs qui le transportent ne voient qu\'une enveloppe scellée.'),
    ],
    ancre: 'bout-en-bout',
  ),
  SujetConfiance.relais: _Explication(
    icone: Icons.cell_tower_rounded,
    titre: 'Des relais aveugles',
    chapeau:
        'Quand il n\'y a pas Internet, vos messages passent de téléphone en téléphone jusqu\'à leur destinataire.',
    points: [
      _Point(Icons.mail_lock_rounded,
          'Chaque téléphone qui relaie porte une enveloppe scellée : il sait d\'où elle vient et où elle va, pas ce qu\'elle contient.'),
      _Point(Icons.visibility_off_rounded,
          'Sur Internet, Droplet peut passer par Tor pour cacher aussi qui parle à qui.'),
    ],
    ancre: 'relais',
  ),
  SujetConfiance.identite: _Explication(
    icone: Icons.verified_user_rounded,
    titre: 'Une identité sans numéro',
    chapeau:
        'Votre identité est une paire de clés créée sur votre téléphone. Aucun numéro, aucun e-mail, aucun mot de passe à voler sur un serveur.',
    points: [
      _Point(Icons.qr_code_2_rounded,
          'Pour être sûr de parler à la bonne personne, comparez vos codes de sécurité ou scannez son code QR.'),
      _Point(Icons.shield_rounded,
          'Si les deux codes correspondent, personne ne s\'est glissé entre vous.'),
    ],
    ancre: 'identite',
  ),
  SujetConfiance.appels: _Explication(
    icone: Icons.call_rounded,
    titre: 'Des appels chiffrés',
    chapeau:
        'Les appels audio et vidéo sont chiffrés de bout en bout, comme les messages.',
    points: [
      _Point(Icons.swap_horiz_rounded,
          'Ils passent directement d\'un téléphone à l\'autre dès que c\'est possible.'),
      _Point(Icons.hearing_disabled_rounded,
          'Sinon, un relais fait suivre le son et l\'image chiffrés, sans pouvoir les écouter.'),
    ],
    ancre: 'appels',
  ),
  SujetConfiance.ephemeres: _Explication(
    icone: Icons.timer_rounded,
    titre: 'Messages éphémères',
    chapeau:
        'Les nouveaux messages de cette discussion s\'effacent tout seuls après le délai choisi.',
    points: [
      _Point(Icons.devices_rounded,
          'Ils disparaissent des deux côtés : sur votre téléphone et sur celui de votre correspondant.'),
      _Point(Icons.history_toggle_off_rounded,
          'Les messages déjà envoyés avant l\'activation ne sont pas concernés.'),
      _Point(Icons.screenshot_rounded,
          'Votre correspondant peut toujours faire une capture d\'écran avant qu\'ils s\'effacent.'),
    ],
    ancre: 'sur-le-telephone',
  ),
  SujetConfiance.limites: _Explication(
    icone: Icons.info_rounded,
    titre: 'Ce que Droplet ne peut pas protéger',
    chapeau: 'Être honnête sur la sécurité, c\'est aussi en dire les limites.',
    points: [
      _Point(Icons.lock_open_rounded,
          'Quelqu\'un qui tient votre téléphone déverrouillé peut lire vos discussions non verrouillées.'),
      _Point(Icons.screenshot_rounded,
          'Votre correspondant peut faire une capture d\'écran.'),
      _Point(Icons.schedule_rounded,
          'Qui écrit à qui, et quand, reste visible des relais et des serveurs, sauf si Tor est actif.'),
    ],
    ancre: 'limites',
  ),
};

/// Fait monter la feuille d'explication d'un sujet.
Future<void> montrerFeuilleConfiance(BuildContext context, SujetConfiance sujet) {
  OuroHaptics.selection();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Le verre de la feuille garde le fond visible derrière lui.
    barrierColor: Colors.black.withValues(alpha: 0.35),
    builder: (_) => _FeuilleConfiance(_explications[sujet]!),
  );
}

class _FeuilleConfiance extends StatelessWidget {
  const _FeuilleConfiance(this.e);
  final _Explication e;

  @override
  Widget build(BuildContext context) {
    final bas = MediaQuery.paddingOf(context).bottom;
    return FrostedSheet(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, 8, 24, 16 + bas),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            // Le sceau : un disque teinté qui porte l'icône du sujet.
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: OuroColors.accent.withValues(alpha: 0.14),
              ),
              child: Icon(e.icone, size: 36, color: OuroColors.accent),
            ),
            const SizedBox(height: 18),
            Text(e.titre,
                textAlign: TextAlign.center,
                style: OuroTypography.title2.copyWith(
                    color: OuroColors.label, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Text(e.chapeau,
                textAlign: TextAlign.center,
                style: OuroTypography.subheadline
                    .copyWith(color: OuroColors.secondaryLabel, height: 1.35)),
            const SizedBox(height: 22),
            for (final p in e.points)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(p.icone, size: 22, color: OuroColors.secondaryLabel),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(p.texte,
                          style: OuroTypography.subheadline
                              .copyWith(color: OuroColors.label, height: 1.35)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            // Le bouton de verre : la section exacte du site.
            SizedBox(
              width: double.infinity,
              child: LiquidGlassButton(
                onTap: () => _ouvrirSite(context, e.ancre),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text('En savoir plus',
                      textAlign: TextAlign.center,
                      style: OuroTypography.headline
                          .copyWith(color: Colors.white)),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('OK',
                  style: OuroTypography.headline.copyWith(color: OuroColors.accent)),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _ouvrirSite(BuildContext context, String ancre) async {
  OuroHaptics.selection();
  final ok = await launchUrl(Uri.parse('$_site#$ancre'),
      mode: LaunchMode.externalApplication);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Impossible d\'ouvrir le site. Vérifiez votre connexion.')));
  }
}

/// La ligne discrète en bas de la liste des discussions :
/// « 🔒 Vos messages personnels sont chiffrés de bout en bout. »
class MentionChiffrementPied extends StatelessWidget {
  const MentionChiffrementPied({super.key});

  @override
  Widget build(BuildContext context) {
    final style = OuroTypography.footnote.copyWith(color: OuroColors.secondaryLabel);
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 28),
      child: Semantics(
        button: true,
        label: 'Vos messages personnels sont chiffrés de bout en bout. En savoir plus.',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => montrerFeuilleConfiance(context, SujetConfiance.chiffrement),
          child: ExcludeSemantics(
            child: Text.rich(
              TextSpan(children: [
                WidgetSpan(
                  alignment: PlaceholderAlignment.middle,
                  child: Icon(Icons.lock_rounded, size: 13, color: OuroColors.secondaryLabel),
                ),
                TextSpan(text: ' Vos messages personnels sont ', style: style),
                TextSpan(
                  text: 'chiffrés de bout en bout',
                  style: style.copyWith(color: OuroColors.accent, fontWeight: FontWeight.w600),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () => montrerFeuilleConfiance(context, SujetConfiance.chiffrement),
                ),
                TextSpan(text: '.', style: style),
              ]),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}

/// La bulle neutre en haut d'une conversation.
class MentionChiffrementBulle extends StatelessWidget {
  const MentionChiffrementBulle({super.key, this.pseudo});

  /// Le correspondant ; `null` dans un groupe.
  final String? pseudo;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
        child: Semantics(
          button: true,
          child: GestureDetector(
            onTap: () => montrerFeuilleConfiance(context, SujetConfiance.chiffrement),
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: OuroColors.secondarySystemBackground,
                borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                border: Border.all(color: OuroColors.separator, width: 0.5),
              ),
              child: Text.rich(
                TextSpan(children: [
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Icon(Icons.lock_rounded, size: 13, color: OuroColors.secondaryLabel),
                  ),
                  TextSpan(
                    text: pseudo == null
                        ? ' Cette discussion est chiffrée de bout en bout : seuls ses membres peuvent la lire, pas même Droplet. '
                        : ' Cette discussion est chiffrée de bout en bout : seuls vous et $pseudo pouvez la lire, pas même Droplet. ',
                  ),
                  TextSpan(
                    text: 'En savoir plus',
                    style: TextStyle(color: OuroColors.accent, fontWeight: FontWeight.w600),
                  ),
                ]),
                textAlign: TextAlign.center,
                style: OuroTypography.caption1
                    .copyWith(color: OuroColors.secondaryLabel, height: 1.35),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
