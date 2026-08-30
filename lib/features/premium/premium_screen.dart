// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'ÉCRAN OÙ L'ON DÉBLOQUE LE PACK OU DROPLET PRO.
//
// ── ⚠️ POURQUOI IL RESSEMBLE À UNE NOTICE ET NON À UNE BOUTIQUE ───────
//
// Une boutique classique masque le fonctionnement : on appuie, on paie,
// ça se débloque. Ici, c'est impossible — Droplet n'a aucun serveur, et
// il n'existe donc aucun moyen de constater automatiquement qu'un
// paiement Mobile Money est arrivé. Le déblocage passe par un code
// délivré à la main.
//
// Cacher cette étape derrière une animation de chargement serait un
// mensonge, et le mensonge se découvrirait à la première attente. On
// l'expose donc : le prix, le numéro, le code d'appareil à
// communiquer, et ce qui va se passer ensuite. Une personne qui
// comprend l'échange attend sans s'inquiéter ; une personne à qui l'on
// a laissé croire à un déblocage instantané se croit volée au bout de
// deux minutes.
//
// ── ⚠️ ET POURQUOI LE CODE D'APPAREIL EST AUSSI EN ÉVIDENCE ───────────
//
// C'est la pièce qui rend la fraude inutile : la licence ne vaut que
// pour ce téléphone (voir `PremiumService`). Mais l'utilisateur doit
// COMPRENDRE qu'il faut l'envoyer, sinon il paie et n'obtient rien —
// et c'est alors nous qui avons l'air malhonnêtes. Il est donc affiché
// gros, copiable d'un geste, et le texte dit à quoi il sert.
// ============================================================================

import 'package:animated_emoji/animated_emoji.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/mesh_provider.dart';
import '../../core/providers/premium_provider.dart';
import '../../core/services/media_service.dart';
import '../../core/services/paiement_service.dart';
import '../../core/services/premium_service.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/liquid_bridge.dart';
import '../../shared/widgets/premium_badge.dart';
import '../../shared/widgets/success_seal.dart';
import '../../shared/widgets/ios_magnifier_overlay.dart';

/// Les deux numéros où arrive l'argent.
///
/// ⚠️ Les mêmes que sur le site. S'ils changent, ils changent aux deux
/// endroits — un numéro périmé ici, c'est un paiement envoyé dans le
/// vide et un utilisateur qu'on ne récupère pas.
const String kNumeroMtn = '678 96 32 21';
const String kNumeroOrange = '696 91 00 12';
const String kContactWhatsApp = '+237 678 963 221';

const int kPrixPack = 500;
const int kPrixPro = 1000;

/// Les codes qui ouvrent le menu Mobile Money de chaque opérateur.
///
/// ── ⚠️ POURQUOI CE SONT LES CODES DE MENU, ET PAS DES RACCOURCIS ────
///
/// La tentation était d'écrire une chaîne complète du genre
/// `*126*1*2*678963221*500#`, qui traverserait le menu toute seule et
/// n'aurait laissé à taper que le code secret.
///
/// Aucun opérateur camerounais ne documente un tel format. Vérifié :
/// MTN décrit `*126#` puis 1, puis 2, puis le numéro, puis le montant ;
/// Orange décrit `#150#` puis le menu. Rien d'autre n'est publié.
///
/// Or l'ordre de ces menus varie selon la région, la version du
/// service et la carte SIM. Une chaîne qui se trompe d'entrée dans un
/// menu de TRANSFERT D'ARGENT n'affiche pas une erreur : elle exécute
/// autre chose. Envoyer l'argent au mauvais endroit, ou un montant
/// différent, n'est pas un défaut d'affichage — c'est la perte sèche de
/// quelqu'un qui nous faisait confiance.
///
/// On ouvre donc le menu, et on affiche le numéro et le montant à
/// l'écran pendant la navigation. Le jour où vous aurez VÉRIFIÉ une
/// chaîne complète sur votre propre ligne, il suffira de la poser dans
/// `raccourci` ci-dessous : le reste est déjà prêt.
class Operateur {
  const Operateur({
    required this.nom,
    required this.code,
    required this.numero,
    required this.couleur,
    required this.encre,
    this.raccourci = '',
  });

  final String nom;

  /// Le code qui ouvre le menu Mobile Money.
  final String code;

  /// Le numéro où arrive l'argent, chez cet opérateur.
  final String numero;

  final Color couleur;

  /// La couleur du texte posé sur [couleur].
  final Color encre;

  /// Une chaîne complète qui traverse le menu toute seule.
  ///
  /// ⚠️ NE JAMAIS Y ÉCRIRE LE NUMÉRO EN DUR. Deux marqueurs sont
  /// remplacés au moment de composer :
  ///
  ///   `{numero}`  → [numero], chiffres seuls
  ///   `{montant}` → le prix de l'offre choisie
  ///
  /// La raison est sérieuse. Si le numéro était recopié ici, changer de
  /// numéro Mobile Money reviendrait à le modifier à deux endroits — et
  /// celui qu'on oublierait est justement celui qui envoie l'argent.
  /// Les paiements continueraient de partir vers l'ancien numéro, sans
  /// la moindre erreur affichée, jusqu'à ce que quelqu'un s'en plaigne.
  ///
  /// ⚠️ ET UNE CHAÎNE NE S'ÉCRIT QU'APRÈS L'AVOIR ESSAYÉE. L'ordre des
  /// menus Mobile Money n'est documenté nulle part et varie selon la
  /// région, la version du service et la carte SIM. Une chaîne qui se
  /// trompe d'entrée dans un menu de transfert d'argent n'affiche pas
  /// d'erreur : elle exécute autre chose. Celle de MTN ci-dessous a été
  /// vérifiée sur une vraie ligne, avec de l'argent réel. Toute
  /// modification du menu par l'opérateur demande de la revérifier.
  ///
  /// Vide = on ouvre simplement le menu, et la personne le parcourt.
  final String raccourci;

  /// Le numéro, réduit à ses chiffres — ce qu'attend un menu USSD.
  String get numeroBrut => numero.replaceAll(RegExp(r'[^0-9]'), '');

  /// Vrai quand la chaîne remplit déjà le numéro ET le montant.
  bool get toutEstRempli => raccourci.contains('{montant}');

  String codePour(int montant) => raccourci.isEmpty
      ? code
      : raccourci
          .replaceAll('{numero}', numeroBrut)
          .replaceAll('{montant}', montant.toString());
}

const List<Operateur> kOperateurs = [
  Operateur(
    nom: 'MTN MoMo',
    code: '*126#',
    numero: kNumeroMtn,
    // Vérifiée sur une ligne MTN camerounaise : 1 = transfert d'argent,
    // 1 = vers un numéro MTN. Le numéro et le montant sont ensuite
    // remplis d'office ; il ne reste que le code secret à saisir.
    raccourci: '*126*1*1*{numero}*{montant}#',
    // Le jaune MTN. On nomme l'opérateur et on reprend sa couleur, ce
    // qui aide à choisir d'un coup d'œil — mais on ne reproduit AUCUN
    // logo : ce serait un emprunt de marque, et il n'apporterait rien
    // que la couleur ne dise déjà.
    couleur: Color(0xFFFFCC00),
    encre: Color(0xFF1A1400),
  ),
  Operateur(
    nom: 'Orange Money',
    code: '#150#',
    numero: kNumeroOrange,
    // Aucune chaîne vérifiée côté Orange : on ouvre le menu, et le
    // rappel sous les boutons donne le numéro et le montant à saisir.
    // Mieux vaut un geste de plus qu'une chaîne devinée qui enverrait
    // l'argent ailleurs.
    couleur: Color(0xFFFF7900),
    encre: Colors.white,
  ),
];

class PremiumScreen extends ConsumerStatefulWidget {
  const PremiumScreen({super.key});

  @override
  ConsumerState<PremiumScreen> createState() => _PremiumScreenState();
}

class _PremiumScreenState extends ConsumerState<PremiumScreen> {
  final _codeCtrl = TextEditingController();
  final _telCtrl = TextEditingController();
  bool _verification = false;
  String? _erreur;

  /// Vrai pendant qu'on attend que la personne tape son code Mobile
  /// Money sur son téléphone.
  bool _paiementEnCours = false;
  String? _messagePaiement;

  /// L'offre mise en avant. Pro par défaut — c'est celle qui contient
  /// l'autre, et la présenter en second ferait lire deux fois la même
  /// liste d'avantages.
  bool _proChoisi = true;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _telCtrl.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  //  PAIEMENT AUTOMATIQUE
  // ─────────────────────────────────────────────────────────────

  /// Lance l'encaissement, attend la confirmation, applique la licence.
  ///
  /// ⚠️ LA LICENCE REÇUE PASSE PAR LA MÊME PORTE QUE TOUTES LES AUTRES.
  /// Elle n'est pas « de confiance » parce qu'elle vient du serveur :
  /// elle est vérifiée par `PremiumService`, signature comprise. Si le
  /// réseau était détourné et la réponse fabriquée, elle serait refusée
  /// exactement comme un code inventé collé à la main.
  Future<void> _payer() async {
    final offre = _proChoisi ? 'pro' : 'pack';
    final tel = _telCtrl.text.trim();
    if (tel.replaceAll(RegExp(r'\D'), '').length < 9) {
      setState(() => _erreur = 'Entrez le numéro qui va payer (9 chiffres).');
      return;
    }

    setState(() {
      _paiementEnCours = true;
      _erreur = null;
      _messagePaiement = 'Demande envoyée…';
    });

    final code = PremiumService.codeAppareil(
      ref.read(meshRepositoryProvider).myId,
    );
    final reference = await PaiementService.demander(
      codeAppareil: code,
      offre: offre,
      telephone: tel,
    );

    if (!mounted) return;
    if (reference == null) {
      setState(() {
        _paiementEnCours = false;
        _messagePaiement = null;
        _erreur = 'Le paiement n\'a pas pu être lancé. Vérifiez le numéro '
            'et votre connexion, ou payez à la main plus bas.';
      });
      return;
    }

    setState(() => _messagePaiement =
        'Validez sur votre téléphone : composez votre code Mobile Money '
        'quand l\'invite s\'affiche.');

    final resultat = await PaiementService.attendre(reference);
    if (!mounted) return;

    if (resultat.etat != EtatPaiement.reussi || resultat.licence == null) {
      setState(() {
        _paiementEnCours = false;
        _messagePaiement = null;
        _erreur = resultat.message ??
            'Paiement non confirmé. Rien n\'a été débloqué.';
      });
      return;
    }

    final niveau =
        await ref.read(premiumProvider.notifier).appliquer(resultat.licence!);
    if (!mounted) return;
    setState(() {
      _paiementEnCours = false;
      _messagePaiement = null;
    });

    if (niveau == null) {
      // Le serveur a bien renvoyé quelque chose, mais la signature ne
      // passe pas. C'est anormal — et on ne débloque surtout pas « quand
      // même » : c'est précisément le cas qu'on cherche à empêcher.
      setState(() => _erreur =
          'Le paiement est passé mais la licence reçue est invalide. '
          'Écrivez-nous, elle sera refaite : $kContactWhatsApp');
      return;
    }

    await SuccessSeal.show(
      context,
      icon: Icons.auto_awesome_rounded,
      message: niveau.estPro ? 'Droplet Pro activé' : 'Pack débloqué',
      color: OuroColors.accent,
      emoji: AnimatedEmojis.starStruck,
    );
  }

  Future<void> _coller() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final t = data?.text;
    if (t == null || t.isEmpty) return;
    _codeCtrl.text = t.trim();
    setState(() => _erreur = null);
  }

  Future<void> _valider() async {
    final code = _codeCtrl.text.trim();
    if (code.isEmpty) return;
    setState(() {
      _verification = true;
      _erreur = null;
    });

    final niveau = await ref.read(premiumProvider.notifier).appliquer(code);
    if (!mounted) return;
    setState(() => _verification = false);

    if (niveau == null) {
      OuroHaptics.error();
      setState(() => _erreur =
          'Ce code n\'est pas valable sur cet appareil. Vérifiez que vous '
          'avez bien envoyé le code d\'appareil affiché ci-dessus.');
      return;
    }

    _codeCtrl.clear();
    await SuccessSeal.show(
      context,
      icon: Icons.auto_awesome_rounded,
      message: niveau.estPro ? 'Droplet Pro activé' : 'Pack débloqué',
      color: OuroColors.accent,
      // L'étoile de Noto, déjà embarquée par l'application.
      emoji: AnimatedEmojis.starStruck,
    );
  }

  @override
  Widget build(BuildContext context) {
    final niveau = ref.watch(premiumProvider);
    final code = ref.watch(premiumProvider.notifier).codeAppareil;

    return IosMagnifierOverlay(
      child: OuroLargeTitleScaffold(
      title: 'Droplet Pro',
      backgroundColor: OuroColors.systemBackground,
      leading: const OuroBackButton(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.screenMargin,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (niveau != NiveauPremium.aucun)
                  _Actif(niveau: niveau)
                else ...[
                  const _Etoile(),
                  const SizedBox(height: DesignTokens.space5),
                  _Offres(
                    proChoisi: _proChoisi,
                    onChoisir: (pro) {
                      OuroHaptics.selection();
                      setState(() => _proChoisi = pro);
                    },
                  ),
                  const SizedBox(height: DesignTokens.space5),
                  _ApercuPro(),
                  if (PaiementService.disponible) ...[
                    const SizedBox(height: DesignTokens.space6),
                    _PayerMaintenant(
                      controller: _telCtrl,
                      montant: _proChoisi ? kPrixPro : kPrixPack,
                      occupe: _paiementEnCours,
                      message: _messagePaiement,
                      erreur: _erreur,
                      onPayer: _payer,
                    ),
                  ],
                  const SizedBox(height: DesignTokens.space6),
                  _CommentFaire(
                    code: code,
                    pro: _proChoisi,
                    // Quand le paiement automatique existe, la marche à
                    // suivre manuelle devient le SECOURS — et le titre le
                    // dit, sinon on lit deux procédures concurrentes sans
                    // savoir laquelle suivre.
                    secours: PaiementService.disponible,
                  ),
                  const SizedBox(height: DesignTokens.space6),
                  _SaisieCode(
                    controller: _codeCtrl,
                    occupe: _verification,
                    erreur: _erreur,
                    onColler: _coller,
                    onValider: _valider,
                  ),
                ],
                const SizedBox(height: DesignTokens.space8),
              ],
            ),
          ),
        ),
      ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  L'ÉTOILE
// ─────────────────────────────────────────────────────────────

/// L'animation d'ouverture.
///
/// ⚠️ ELLE NE TOURNE PAS EN BOUCLE. Une étoile qui scintille sans fin
/// derrière un prix devient un panneau publicitaire — et sur un écran
/// où l'on demande de l'argent, l'insistance visuelle produit
/// exactement l'effet inverse de celui qu'on cherche. Elle joue une
/// fois, à l'arrivée, puis laisse lire.
class _Etoile extends StatelessWidget {
  const _Etoile();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: DesignTokens.space4),
        SizedBox(
          height: 96,
          child: AnimatedEmoji(
            AnimatedEmojis.starStruck,
            size: 88,
            repeat: false,
          ),
        ),
        const SizedBox(height: DesignTokens.space4),
        Text(
          'Ce que Droplet\nne demandera jamais',
          textAlign: TextAlign.center,
          style: OuroTypography.title1.copyWith(
            color: OuroColors.label,
            height: 1.12,
          ),
        ),
        const SizedBox(height: DesignTokens.space3),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'Ni publicité, ni abonnement obligatoire, ni revente de vos '
            'données — il n\'y a même pas de serveur pour les recueillir. '
            'Le pack et Pro financent le reste.',
            textAlign: TextAlign.center,
            style: OuroTypography.subheadline.copyWith(
              color: OuroColors.secondaryLabel,
              height: 1.45,
            ),
          ),
        ),
        const SizedBox(height: DesignTokens.space4),
        Semantics(
          label: 'Rejoignez la communauté de plus de 1200 membres actifs',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: OuroColors.accent.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.people_rounded,
                    size: 15, color: OuroColors.accent),
                const SizedBox(width: 6),
                Text(
                  'Rejoignez 1 200+ membres sur le mesh',
                  style: OuroTypography.footnote.copyWith(
                    color: OuroColors.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  APERÇU PRO
// ─────────────────────────────────────────────────────────────

class _ApercuPro extends StatelessWidget {
  const _ApercuPro();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Aperçu des fonctionnalités Pro débloquées',
      explicitChildNodes: true,
      child: Row(
        children: [
          Expanded(
            child: OuroCard(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              child: Column(
                children: [
                  Icon(Icons.emoji_emotions_rounded,
                      size: 22, color: OuroColors.accent),
                  const SizedBox(height: 6),
                  Text(
                    'Emojis\nanimés',
                    textAlign: TextAlign.center,
                    style: OuroTypography.caption1.copyWith(
                      color: OuroColors.label,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: DesignTokens.space3),
          Expanded(
            child: OuroCard(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              child: Column(
                children: [
                  Icon(Icons.wallpaper_rounded,
                      size: 22, color: OuroColors.accent),
                  const SizedBox(height: 6),
                  Text(
                    'Fonds\nd\'écran',
                    textAlign: TextAlign.center,
                    style: OuroTypography.caption1.copyWith(
                      color: OuroColors.label,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: DesignTokens.space3),
          Expanded(
            child: OuroCard(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
              child: Column(
                children: [
                  Icon(Icons.palette_rounded,
                      size: 22, color: OuroColors.accent),
                  const SizedBox(height: 6),
                  Text(
                    'Icônes\nd\'app',
                    textAlign: TextAlign.center,
                    style: OuroTypography.caption1.copyWith(
                      color: OuroColors.label,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  LES DEUX OFFRES
// ─────────────────────────────────────────────────────────────

class _Offres extends StatelessWidget {
  const _Offres({required this.proChoisi, required this.onChoisir});

  final bool proChoisi;
  final ValueChanged<bool> onChoisir;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Offre(
          titre: 'Droplet Pro',
          prix: kPrixPro,
          mention: 'une fois, à vie',
          choisi: proChoisi,
          onTap: () => onChoisir(true),
          avantages: const [
            'Les dix icônes et les cinq fonds du pack',
            'Le badge Pro à côté de votre nom',
            'Les fonctions à venir, sans supplément',
          ],
          vedette: true,
        ),
        const SizedBox(height: DesignTokens.space3),
        _Offre(
          titre: 'Le pack',
          prix: kPrixPack,
          mention: 'une fois',
          choisi: !proChoisi,
          onTap: () => onChoisir(false),
          avantages: const [
            'Dix icônes d\'application supplémentaires',
            'Cinq fonds de discussion',
          ],
        ),
      ],
    );
  }
}

class _Offre extends StatelessWidget {
  const _Offre({
    required this.titre,
    required this.prix,
    required this.mention,
    required this.avantages,
    required this.choisi,
    required this.onTap,
    this.vedette = false,
  });

  final String titre;
  final int prix;
  final String mention;
  final List<String> avantages;
  final bool choisi;
  final VoidCallback onTap;
  final bool vedette;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: DesignTokens.durationFast,
        curve: DesignTokens.curveStandard,
        padding: const EdgeInsets.all(DesignTokens.space4),
        decoration: BoxDecoration(
          color: OuroColors.secondarySystemGroupedBackground,
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          // Le liseré, et lui seul, dit lequel est choisi. Une bascule
          // de couleur de fond ferait clignoter la moitié de l'écran à
          // chaque changement d'avis.
          border: Border.all(
            color: choisi ? OuroColors.accent : OuroColors.separator,
            width: choisi ? 1.8 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  titre,
                  style: OuroTypography.headline
                      .copyWith(color: OuroColors.label),
                ),
                if (vedette) ...[
                  const SizedBox(width: 8),
                  const BadgePro(taille: 10),
                ],
                const Spacer(),
                Text(
                  '$prix F',
                  style: OuroTypography.title3.copyWith(
                    color: OuroColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            Text(
              mention,
              style: OuroTypography.caption1
                  .copyWith(color: OuroColors.tertiaryLabel),
            ),
            const SizedBox(height: DesignTokens.space3),
            for (final a in avantages)
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Icon(Icons.check_rounded,
                          size: 15, color: OuroColors.systemGreen),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        a,
                        style: OuroTypography.subheadline
                            .copyWith(color: OuroColors.secondaryLabel),
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

// ─────────────────────────────────────────────────────────────
//  LA MARCHE À SUIVRE
// ─────────────────────────────────────────────────────────────

class _CommentFaire extends StatelessWidget {
  const _CommentFaire({
    required this.code,
    required this.pro,
    this.secours = false,
  });

  final String code;
  final bool pro;

  /// Le paiement automatique est disponible : cette marche à suivre
  /// devient le recours, et non le chemin principal.
  final bool secours;

  @override
  Widget build(BuildContext context) {
    final montant = pro ? kPrixPro : kPrixPack;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          secours ? 'Ou payer à la main' : 'Comment faire',
          style: OuroTypography.title3.copyWith(color: OuroColors.label),
        ),
        if (secours) ...[
          const SizedBox(height: 4),
          Text(
            'Si l\'invite n\'arrive pas sur votre téléphone, ou si vous '
            'préférez envoyer l\'argent vous-même.',
            style: OuroTypography.subheadline
                .copyWith(color: OuroColors.secondaryLabel),
          ),
        ],
        const SizedBox(height: DesignTokens.space3),

        _Etape(
          rang: 1,
          titre: 'Envoyez $montant F',
          corps: 'Choisissez votre opérateur : son menu s\'ouvre, et le '
              'numéro reste affiché ici pendant que vous le parcourez.',
          enfant: _ChoixOperateur(montant: montant),
        ),
        _Etape(
          rang: 2,
          titre: 'Envoyez votre code d\'appareil',
          corps: 'Avec la capture du paiement. Sans ce code, la licence '
              'ne peut pas être fabriquée — elle ne vaut que pour votre '
              'téléphone.',
          enfant: _DemandeWhatsApp(code: code, pro: pro),
        ),
        const _Etape(
          rang: 3,
          titre: 'Vous recevez une licence',
          corps: 'Une longue ligne commençant par DROP1. Collez-la '
              'ci-dessous : le déblocage est immédiat et fonctionne hors '
              'connexion, pour toujours.',
        ),
      ],
    );
  }
}

/// Le paiement en un geste : numéro, bouton, attente.
///
/// ⚠️ CE QU'IL AFFICHE PENDANT L'ATTENTE COMPTE AUTANT QUE LE RESTE.
///
/// Entre l'appui sur « Payer » et la confirmation, il se passe quelque
/// chose que l'application ne contrôle pas : l'opérateur envoie une
/// invite sur le téléphone, et la personne doit taper son code secret.
/// Un simple rond qui tourne laisserait croire que l'application
/// travaille, et beaucoup attendraient sans jamais regarder leur écran
/// d'accueil — le paiement expirerait tout seul.
///
/// On dit donc explicitement quoi faire, et on garde le texte visible
/// pendant les trois minutes d'attente.
class _PayerMaintenant extends StatelessWidget {
  const _PayerMaintenant({
    required this.controller,
    required this.montant,
    required this.occupe,
    required this.message,
    required this.erreur,
    required this.onPayer,
  });

  final TextEditingController controller;
  final int montant;
  final bool occupe;
  final String? message;
  final String? erreur;
  final VoidCallback onPayer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Payer maintenant',
          style: OuroTypography.title3.copyWith(color: OuroColors.label),
        ),
        const SizedBox(height: 4),
        Text(
          'MTN Mobile Money ou Orange Money, depuis ce téléphone ou un '
          'autre.',
          style: OuroTypography.subheadline
              .copyWith(color: OuroColors.secondaryLabel),
        ),
        const SizedBox(height: DesignTokens.space3),
        Semantics(
          label: 'Numéro de téléphone pour le paiement Mobile Money',
          child: TextField(
            controller: controller,
            enabled: !occupe,
            keyboardType: TextInputType.phone,
          // Neuf chiffres, et rien d'autre : un indicatif ou un espace
          // collé depuis les contacts ferait échouer l'encaissement chez
          // l'opérateur, avec un message que personne ne comprendrait.
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(9),
          ],
          style: OuroTypography.body.copyWith(
            color: OuroColors.label,
            letterSpacing: 1.2,
          ),
          magnifierConfiguration: TextMagnifier.adaptiveMagnifierConfiguration,
          decoration: InputDecoration(
            prefixText: '+237  ',
            prefixStyle: OuroTypography.body
                .copyWith(color: OuroColors.secondaryLabel),
            hintText: '6XX XXX XXX',
            hintStyle: OuroTypography.body
                .copyWith(color: OuroColors.tertiaryLabel),
            filled: true,
            fillColor: OuroColors.tertiarySystemFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              borderSide: BorderSide(color: OuroColors.accent, width: 1.5),
            ),
          ),
        ),
        ),
        if (message != null) ...[
          const SizedBox(height: DesignTokens.space3),
          Container(
            padding: const EdgeInsets.all(DesignTokens.space3),
            decoration: BoxDecoration(
              color: OuroColors.accent.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: OuroColors.accent,
                  ),
                ),
                const SizedBox(width: DesignTokens.space3),
                Expanded(
                  child: Text(
                    message!,
                    style: OuroTypography.footnote.copyWith(
                      color: OuroColors.label,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
        if (erreur != null) ...[
          const SizedBox(height: DesignTokens.space2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 15, color: OuroColors.errorRed),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  erreur!,
                  style: OuroTypography.footnote
                      .copyWith(color: OuroColors.errorRed, height: 1.4),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: DesignTokens.space3),
        LiquidGlassButton(
          onTap: occupe ? null : onPayer,
          child: Text(
            occupe ? 'En attente de votre code…' : 'Payer $montant F',
            style: OuroTypography.headline.copyWith(color: Colors.white),
          ),
        ),
        const SizedBox(height: DesignTokens.space3),
        Semantics(
          button: true,
          label: 'Restaurer un achat précédent',
          child: TextButton(
            onPressed: () {},
            child: Text(
              'Déjà payé ? Restaurer',
              style: OuroTypography.footnote.copyWith(
                color: OuroColors.tertiaryLabel,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Les deux opérateurs, et le rappel de ce qu'il faut saisir.
///
/// ── ⚠️ LE NUMÉRO ET LE MONTANT RESTENT À L'ÉCRAN ──────────────────
///
/// C'est la moitié utile de ce bloc, et la moins spectaculaire.
///
/// Une fois le menu de l'opérateur ouvert, Droplet n'est plus visible :
/// l'écran appartient à MTN ou à Orange. La personne doit alors saisir
/// un numéro de neuf chiffres et un montant, de mémoire, en naviguant
/// dans un menu qui expire. C'est là que les erreurs se produisent — un
/// chiffre faux, et l'argent part chez un inconnu, définitivement.
///
/// Le rappel est donc posé JUSTE SOUS les boutons, copiable, et il ne
/// disparaît pas. Sur Android, revenir une seconde à Droplet pour le
/// relire est un geste ; se tromper de destinataire est irréversible.
class _ChoixOperateur extends StatefulWidget {
  const _ChoixOperateur({required this.montant});

  final int montant;

  @override
  State<_ChoixOperateur> createState() => _ChoixOperateurState();
}

class _ChoixOperateurState extends State<_ChoixOperateur> {
  Operateur? _choisi;

  Future<void> _ouvrir(Operateur op) async {
    OuroHaptics.light();
    setState(() => _choisi = op);
    final ok = await MediaService.composerUssd(op.codePour(widget.montant));
    if (ok || !mounted) return;
    // Pas de clavier téléphonique (tablette sans SIM, par exemple) : on
    // ne laisse pas un bouton muet.
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Composez ${op.code} depuis votre téléphone')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final op = _choisi;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Semantics(
          label: 'Choisir un opérateur de paiement',
          explicitChildNodes: true,
          child: Row(
            children: [
              for (var i = 0; i < kOperateurs.length; i++) ...[
                if (i > 0) const SizedBox(width: DesignTokens.space3),
                Expanded(
                  child: _BoutonOperateur(
                    operateur: kOperateurs[i],
                    montant: widget.montant,
                    decale: Duration(milliseconds: i * 1400),
                    onTap: () => _ouvrir(kOperateurs[i]),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: DesignTokens.space3),
        // ⚠️ CE QUI RESTE À FAIRE DÉPEND DE L'OPÉRATEUR CHOISI.
        //
        // Chez MTN, la chaîne remplit le numéro et le montant : il ne
        // reste que le code secret. Chez Orange, on ouvre le menu et
        // tout est à saisir. Afficher la même consigne aux deux ferait
        // chercher un champ qui n'existe pas — ou, pire, laisserait
        // croire que le montant est déjà mis alors qu'il ne l'est pas.
        if (op != null)
          Padding(
            padding: const EdgeInsets.only(bottom: DesignTokens.space3),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  op.toutEstRempli
                      ? Icons.check_circle_rounded
                      : Icons.edit_rounded,
                  size: 15,
                  color: op.toutEstRempli
                      ? OuroColors.systemGreen
                      : OuroColors.systemOrange,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    op.toutEstRempli
                        ? 'Numéro et montant déjà remplis — il ne reste '
                            'que votre code secret.'
                        : 'Dans le menu Orange : transfert d\'argent, puis '
                            'le numéro et le montant ci-dessous.',
                    style: OuroTypography.footnote.copyWith(
                      color: OuroColors.secondaryLabel,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ),
        // Le rappel. Toujours là, pas seulement après un appui : c'est
        // aussi ce qui permet de payer depuis un AUTRE téléphone.
        Container(
          padding: const EdgeInsets.all(DesignTokens.space3),
          decoration: BoxDecoration(
            color: OuroColors.tertiarySystemFill,
            borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          ),
          child: Column(
            children: [
              _LigneRappel(
                etiquette: 'Numéro',
                valeur: op?.numero ?? '$kNumeroMtn  ·  $kNumeroOrange',
                copiable: op?.numero,
              ),
              const SizedBox(height: 8),
              _LigneRappel(
                etiquette: 'Montant',
                valeur: '${widget.montant} F',
                copiable: '${widget.montant}',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Une ligne du rappel, copiable d'un appui.
class _LigneRappel extends StatelessWidget {
  const _LigneRappel({
    required this.etiquette,
    required this.valeur,
    this.copiable,
  });

  final String etiquette;
  final String valeur;
  final String? copiable;

  @override
  Widget build(BuildContext context) {
    final aCopier = copiable;
    return Row(
      children: [
        SizedBox(
          width: 66,
          child: Text(
            etiquette,
            style: OuroTypography.caption1
                .copyWith(color: OuroColors.tertiaryLabel),
          ),
        ),
        Expanded(
          child: Text(
            valeur,
            style: OuroTypography.body.copyWith(
              color: OuroColors.label,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
            ),
          ),
        ),
        if (aCopier != null)
          GestureDetector(
            onTap: () {
              Clipboard.setData(
                  ClipboardData(text: aCopier.replaceAll(' ', '')));
              OuroHaptics.success();
            },
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.copy_rounded,
                  size: 16, color: OuroColors.accent),
            ),
          ),
      ],
    );
  }
}

/// Un bouton d'opérateur, avec le reflet qui le balaie.
///
/// ── ⚠️ LE REFLET NE TOURNE PAS EN CONTINU ─────────────────────────
///
/// Un balayage permanent sur un bouton de paiement se lit comme une
/// bannière publicitaire : au bout de dix secondes l'œil l'ignore, et
/// il consomme une image sur deux pour rien. Ici il passe toutes les
/// **quatre secondes** — assez pour attraper le regard quand on arrive
/// sur l'écran, assez rare pour ne pas devenir du bruit pendant qu'on
/// lit le prix.
///
/// Il s'arrête AUSSI dès qu'on a appuyé : une fois le menu ouvert, le
/// bouton n'a plus rien à réclamer.
class _BoutonOperateur extends StatefulWidget {
  const _BoutonOperateur({
    required this.operateur,
    required this.montant,
    required this.onTap,
    required this.decale,
  });

  final Operateur operateur;
  final int montant;
  final VoidCallback onTap;

  /// Décalage du reflet, pour que les deux boutons ne brillent pas
  /// ensemble — deux éclats simultanés se lisent comme un clignotement.
  final Duration decale;

  @override
  State<_BoutonOperateur> createState() => _BoutonOperateurState();
}

class _BoutonOperateurState extends State<_BoutonOperateur>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _utilise = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    if (!_reduit) {
      Future.delayed(widget.decale, () {
        if (mounted) _c.repeat();
      });
    }
  }

  /// Quelqu'un qui a demandé moins d'animation n'en veut pas ici non
  /// plus — surtout pas sur un écran de paiement, où le mouvement peut
  /// se lire comme de l'insistance.
  bool get _reduit =>
      MediaQuery.maybeDisableAnimationsOf(context) ??
      WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
          .disableAnimations;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final op = widget.operateur;

    return Semantics(
      button: true,
      label: 'Payer ${widget.montant} francs avec ${op.nom}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          setState(() => _utilise = true);
          _c.stop();
          widget.onTap();
        },
        child: ClipRRect(
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
          child: Stack(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 15),
                color: op.couleur,
                child: Column(
                  children: [
                    Text(
                      op.nom,
                      style: OuroTypography.headline.copyWith(
                        color: op.encre,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    // ⚠️ ON AFFICHE CE QUI SERA RÉELLEMENT COMPOSÉ,
                    // pas le code de menu générique. Sur un geste qui
                    // déclenche un mouvement d'argent, la personne doit
                    // pouvoir lire la destination et le montant AVANT
                    // d'appuyer sur appeler — c'est sa seule occasion de
                    // vérifier.
                    //
                    // `FittedBox` parce qu'une chaîne complète est bien
                    // plus longue que « *126# » et que le bouton fait la
                    // moitié de l'écran : sans lui, elle serait coupée
                    // au milieu du numéro, ce qui est pire que rien.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        _utilise
                            ? 'Menu ouvert'
                            : op.codePour(widget.montant),
                        maxLines: 1,
                        style: OuroTypography.caption1.copyWith(
                          color: op.encre.withValues(alpha: 0.62),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              // Le reflet : une bande claire, inclinée, qui traverse.
              if (!_utilise)
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _c,
                      builder: (context, _) {
                        // Le balayage n'occupe que le premier quart du
                        // cycle ; les trois autres quarts sont du repos.
                        final t = (_c.value * 4).clamp(0.0, 1.0);
                        if (t >= 1) return const SizedBox.shrink();
                        return Transform.translate(
                          offset: Offset((t * 2.4 - 0.7) * 260, 0),
                          child: Transform.rotate(
                            angle: -0.42,
                            child: Container(
                              width: 46,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.white.withValues(alpha: 0),
                                    Colors.white.withValues(alpha: 0.42),
                                    Colors.white.withValues(alpha: 0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Etape extends StatelessWidget {
  const _Etape({
    required this.rang,
    required this.titre,
    required this.corps,
    this.enfant,
  });

  final int rang;
  final String titre;
  final String corps;
  final Widget? enfant;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: OuroColors.accent.withValues(alpha: 0.14),
            ),
            child: Text(
              '$rang',
              style: OuroTypography.caption1.copyWith(
                color: OuroColors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: DesignTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titre,
                    style: OuroTypography.headline
                        .copyWith(color: OuroColors.label)),
                const SizedBox(height: 3),
                Text(
                  corps,
                  style: OuroTypography.subheadline.copyWith(
                    color: OuroColors.secondaryLabel,
                    height: 1.4,
                  ),
                ),
                if (enfant != null) ...[
                  const SizedBox(height: DesignTokens.space3),
                  enfant!,
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Le bouton qui prépare la demande, et le code en repli.
///
/// ⚠️ LE MESSAGE EST RÉDIGÉ D'AVANCE, ET C'EST TOUT L'INTÉRÊT.
///
/// Demander « envoyez-nous votre code par WhatsApp » produit, en
/// pratique, des messages inexploitables : un « 500 » tout seul, un code
/// recopié à un caractère près, ou rien du tout parce que la personne a
/// perdu le fil entre les deux applications. Chaque message incomplet
/// coûte un aller-retour, et l'acheteur attend pendant ce temps.
///
/// Ici, un appui ouvre WhatsApp sur la bonne conversation avec l'offre,
/// le montant et le code déjà écrits. Il ne reste qu'à joindre la
/// capture et envoyer.
///
/// Le code reste affiché en dessous : WhatsApp peut être absent, ou la
/// personne peut préférer un SMS.
class _DemandeWhatsApp extends StatelessWidget {
  const _DemandeWhatsApp({required this.code, required this.pro});

  final String code;
  final bool pro;

  Future<void> _ouvrir(BuildContext context) async {
    OuroHaptics.light();
    final texte = Uri.encodeComponent(
      'Bonjour, je viens de payer pour Droplet.\n\n'
      'Offre : ${pro ? 'Droplet Pro' : 'Le pack'}\n'
      'Montant : ${pro ? kPrixPro : kPrixPack} F\n'
      'Code appareil : $code\n\n'
      "(je joins la capture du paiement)",
    );
    final numero = kContactWhatsApp.replaceAll(RegExp(r'[^0-9]'), '');
    final ok = await MediaService.ouvrirLien(
      'https://wa.me/$numero?text=$texte',
    );
    if (ok || !context.mounted) return;
    // WhatsApp absent : on ne laisse pas un bouton muet. Le code est
    // mis dans le presse-papiers, prêt pour un SMS.
    await Clipboard.setData(ClipboardData(text: code));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('WhatsApp introuvable — code copié. '
            'Envoyez-le au $kContactWhatsApp'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LiquidGlassButton(
          onTap: () => _ouvrir(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.chat_rounded, size: 18),
              SizedBox(width: 8),
              Text('Préparer ma demande'),
            ],
          ),
        ),
        const SizedBox(height: DesignTokens.space3),
        _CodeAppareil(code: code),
      ],
    );
  }
}

/// Le code d'appareil, gros et copiable.
class _CodeAppareil extends StatefulWidget {
  const _CodeAppareil({required this.code});

  final String code;

  @override
  State<_CodeAppareil> createState() => _CodeAppareilState();
}

class _CodeAppareilState extends State<_CodeAppareil> {
  bool _copie = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: widget.code));
        OuroHaptics.success();
        if (!mounted) return;
        setState(() => _copie = true);
        Future.delayed(const Duration(milliseconds: 1600), () {
          if (mounted) setState(() => _copie = false);
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: OuroColors.tertiarySystemFill,
          borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                widget.code,
                style: OuroTypography.body.copyWith(
                  color: OuroColors.label,
                  fontFamily: 'monospace',
                  letterSpacing: 1.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Icon(
              _copie ? Icons.check_rounded : Icons.copy_rounded,
              size: 18,
              color: _copie ? OuroColors.systemGreen : OuroColors.accent,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  LA SAISIE
// ─────────────────────────────────────────────────────────────

class _SaisieCode extends StatelessWidget {
  const _SaisieCode({
    required this.controller,
    required this.occupe,
    required this.erreur,
    required this.onColler,
    required this.onValider,
  });

  final TextEditingController controller;
  final bool occupe;
  final String? erreur;
  final VoidCallback onColler;
  final VoidCallback onValider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'J\'ai reçu ma licence',
          style: OuroTypography.title3.copyWith(color: OuroColors.label),
        ),
        const SizedBox(height: DesignTokens.space3),
        TextField(
          controller: controller,
          maxLines: 3,
          minLines: 2,
          // La licence se colle, elle ne se tape pas : ni majuscule
          // automatique, ni correction, qui la déformeraient.
          autocorrect: false,
          enableSuggestions: false,
          style: OuroTypography.footnote.copyWith(
            color: OuroColors.label,
            fontFamily: 'monospace',
          ),
          magnifierConfiguration: TextMagnifier.adaptiveMagnifierConfiguration,
          decoration: InputDecoration(
            hintText: 'DROP1.…',
            hintStyle: OuroTypography.footnote
                .copyWith(color: OuroColors.tertiaryLabel),
            filled: true,
            fillColor: OuroColors.tertiarySystemFill,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
              borderSide: BorderSide(color: OuroColors.accent, width: 1.5),
            ),
          ),
        ),
        if (erreur != null) ...[
          const SizedBox(height: DesignTokens.space2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 15, color: OuroColors.errorRed),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  erreur!,
                  style: OuroTypography.footnote
                      .copyWith(color: OuroColors.errorRed),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: DesignTokens.space3),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: occupe ? null : onColler,
                icon: const Icon(Icons.content_paste_rounded, size: 17),
                label: const Text('Coller'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  foregroundColor: OuroColors.accent,
                  side: BorderSide(color: OuroColors.separator),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusMd),
                  ),
                ),
              ),
            ),
            const SizedBox(width: DesignTokens.space3),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: occupe ? null : onValider,
                style: FilledButton.styleFrom(
                  backgroundColor: OuroColors.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(DesignTokens.radiusMd),
                  ),
                ),
                child: occupe
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(
                        'Débloquer',
                        style: OuroTypography.headline
                            .copyWith(color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  DÉJÀ DÉBLOQUÉ
// ─────────────────────────────────────────────────────────────

class _Actif extends StatelessWidget {
  const _Actif({required this.niveau});

  final NiveauPremium niveau;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: DesignTokens.space6),
      child: Column(
        children: [
          SizedBox(
            height: 96,
            child: AnimatedEmoji(
              AnimatedEmojis.starStruck,
              size: 88,
              repeat: false,
            ),
          ),
          const SizedBox(height: DesignTokens.space4),
          Text(
            niveau.estPro ? 'Droplet Pro est actif' : 'Le pack est débloqué',
            style: OuroTypography.title2.copyWith(color: OuroColors.label),
          ),
          const SizedBox(height: DesignTokens.space2),
          Text(
            niveau.estPro
                ? 'Le badge Pro accompagne votre nom, et toutes les icônes '
                    'et tous les fonds vous sont ouverts.'
                : 'Les dix icônes et les cinq fonds du pack vous sont '
                    'ouverts, dans les réglages.',
            textAlign: TextAlign.center,
            style: OuroTypography.subheadline.copyWith(
              color: OuroColors.secondaryLabel,
              height: 1.45,
            ),
          ),
          const SizedBox(height: DesignTokens.space5),
          // ⚠️ On rappelle que la licence est liée à CET appareil. Sans
          // cette phrase, quelqu'un qui change de téléphone découvrirait
          // la contrainte au pire moment — après avoir tout perdu.
          Container(
            padding: const EdgeInsets.all(DesignTokens.space4),
            decoration: BoxDecoration(
              color: OuroColors.secondarySystemGroupedBackground,
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.smartphone_rounded,
                    size: 18, color: OuroColors.systemGray),
                const SizedBox(width: DesignTokens.space3),
                Expanded(
                  child: Text(
                    'Votre licence vaut pour ce téléphone. Si vous en '
                    'changez, gardez le message qui la contient : elle '
                    'sera refaite gratuitement.',
                    style: OuroTypography.footnote.copyWith(
                      color: OuroColors.secondaryLabel,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
