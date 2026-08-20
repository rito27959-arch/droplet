// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LES PREMIERS ÉCRANS, ceux qu'on ne voit qu'une seule fois : ce que
// Droplet sait faire, comment il s'y prend, et le choix d'un pseudo.
//
// ── Le modèle suivi ────────────────────────────────────────────────────
//
// Celui des écrans de bienvenue d'Apple, qu'on retrouve à l'identique
// dans Réglages, Photos ou Messages à chaque grande mise à jour :
//
//   • une icône, seule, en haut ;
//   • un grand titre en deux ou trois mots ;
//   • puis des LIGNES DE FONCTIONNALITÉ : une icône colorée à gauche, un
//     titre, une phrase d'explication. Alignées sur une même colonne, et
//     qui apparaissent l'une APRÈS l'autre.
//
// Ce décalage n'est pas de la décoration. Tout faire apparaître en même
// temps donne un mur de texte que l'œil survole sans rien lire ; les
// faire arriver l'une après l'autre impose un ordre de lecture, et on
// lit vraiment les trois lignes.
//
// ── Ce qui a changé ────────────────────────────────────────────────────
//
// La version précédente enchaînait trois pages illustrées de dessins
// abstraits (un maillage de points, un bouclier), avec des animations en
// boucle permanentes. Joli, mais ça ne DISAIT rien : on arrivait au
// choix du pseudo sans savoir ce que l'app faisait de différent. Les
// dessins qui restent sont désormais au service d'une explication, et ne
// tournent plus en boucle indéfiniment.
// ============================================================================

import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/providers/mesh_provider.dart';
import '../../core/services/avatar_service.dart';
import '../../core/services/backup_service.dart';
import '../../core/services/crypto_service.dart';
import '../../core/services/media_service.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_alert.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_spinner.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_typography.dart';
import '../../shared/widgets/avatar_picker_sheet.dart';
import 'onboarding_animations.dart';

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _pageCtrl = PageController();
  final _pseudoCtrl = TextEditingController();

  int _page = 0;
  bool _busy = false;

  /// Le nom du fichier de la photo choisie, s'il y en a une.
  String? _avatarNom;

  /// Les octets de cette photo, gardés pour l'afficher sans relire le
  /// fichier qu'on vient tout juste d'écrire.
  Uint8List? _avatarApercu;

  /// Vrai une fois l'identité créée.
  ///
  /// ⚠️ À PARTIR DE LÀ, ON NE PEUT PLUS REVENIR EN ARRIÈRE, et c'est
  /// une protection et non une contrariété : le pseudo et la photo sont
  /// enregistrés, les clés sont générées. Laisser retourner sur l'écran
  /// du pseudo donnerait un champ modifiable dont les modifications ne
  /// seraient plus prises en compte — l'utilisateur croirait avoir
  /// changé son nom, et se retrouverait avec l'ancien.
  bool _identiteCreee = false;

  // ── L'ORDRE DES PAGES ────────────────────────────────────────────
  //
  // Quatre pages qui EXPLIQUENT, puis trois qui INSTALLENT. La coupure
  // se situe exactement au pseudo : avant, on lit ; après, on remplit.
  //
  // Le choix d'ordre le moins évident est celui de la dernière page.
  // Inviter des proches vient APRÈS la création de l'identité, pas
  // avant : on ne demande pas un service à quelqu'un qui n'a pas encore
  // décidé de rester. À ce stade il est installé, il a un nom, une
  // photo — l'invitation devient la suite logique plutôt qu'un péage.
  static const int _pagePseudo = 4;
  static const int _pagePhoto = 5;
  static const int _pageReseau = 6;
  static const int _pageCount = 7;

  @override
  void initState() {
    super.initState();
    _pseudoCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _pseudoCtrl.dispose();
    super.dispose();
  }

  bool get _pseudoValid => _pseudoCtrl.text.trim().length >= 3;

  void _next() {
    OuroHaptics.light();
    switch (_page) {
      // ⚠️ LE PSEUDO SE VALIDE ICI AUSSI, ET PAS SEULEMENT SUR LE BOUTON.
      //
      // Le bouton du bas se désactive tout seul quand le pseudo est trop
      // court — mais la touche « Terminé » du clavier appelle cette même
      // méthode en passant à côté de cette désactivation. Sans ce cas,
      // on arrivait sur la page de la photo avec un pseudo d'un
      // caractère.
      case _pagePseudo:
        if (!_pseudoValid) {
          _toast('Au moins 3 caractères', DropletToastType.warning);
          return;
        }
        _allerA(_page + 1);
      // La photo est la dernière chose enregistrée : c'est en quittant
      // cette page que l'identité est créée pour de bon.
      case _pagePhoto:
        _createIdentity();
      // La dernière page n'a plus rien à enregistrer, elle invite.
      case _pageReseau:
        context.go('/chats');
      default:
        _allerA(_page + 1);
    }
  }

  void _allerA(int page) {
    _pageCtrl.animateToPage(
      page,
      duration: DesignTokens.durationSheet,
      curve: DesignTokens.curveEnter,
    );
  }

  // ─────────────────────────────────────────────────────────────
  //  IDENTITÉ
  // ─────────────────────────────────────────────────────────────

  Future<void> _createIdentity() async {
    final pseudo = _pseudoCtrl.text.trim();
    if (pseudo.isEmpty) {
      _toast('Choisissez un pseudo pour commencer', DropletToastType.warning);
      return;
    }
    if (pseudo.length < 3) {
      _toast('Au moins 3 caractères', DropletToastType.warning);
      return;
    }

    setState(() => _busy = true);

    final id = StorageService.generateCryptoIdentity(pseudo);
    final publicKey = await CryptoService.ensureIdentityKeyPair();
    await StorageService.saveUser(DropletUserModel(
      id: id,
      pseudo: pseudo,
      publicKey: publicKey,
      // ⚠️ On enregistre le NOM du fichier, jamais son chemin absolu.
      // Voir la note en tête d'`AvatarService` : un chemin absolu
      // enregistré en base pointe dans le vide après une restauration.
      avatarUrl: _avatarNom,
    ));
    await StorageService.setOnboardingComplete();

    try {
      final repo = ref.read(meshRepositoryProvider);
      await repo.init(id, pseudo);
      ref.read(callProvider.notifier).init(repo.transport);
      ref.read(groupCallProvider.notifier).init(repo.transport, repo.myId);
    } catch (e) {
      debugPrint('[Onboarding] mesh init error: $e');
    }

    if (!mounted) return;
    setState(() => _busy = false);
    OuroHaptics.success();

    // On ne quitte PAS l'accueil ici : il reste une page, celle qui
    // explique que Droplet ne vaut rien tout seul. C'est le moment où
    // elle a le plus de chances d'être lue.
    //
    // ⚠️ LE VERROU NE SE POSE QU'UNE FOIS ARRIVÉ. Le mettre avant
    // reconstruirait le `PageView` avec d'autres `physics` en plein
    // vol : Flutter recrée alors la position de défilement, et
    // l'animation en cours est annulée à mi-chemin — on resterait
    // coincé entre deux pages.
    _pageCtrl
        .animateToPage(
          _pageReseau,
          duration: DesignTokens.durationSheet,
          curve: DesignTokens.curveEnter,
        )
        .whenComplete(() {
          if (mounted) setState(() => _identiteCreee = true);
        });
  }

  Future<String?> _promptBackupPassword() => ouroPrompt(
        context,
        title: 'Mot de passe de la sauvegarde',
        message: 'Celui que vous aviez choisi en exportant votre identité.',
        placeholder: 'Mot de passe',
        confirmLabel: 'Restaurer',
        obscure: true,
      );

  Future<void> _restoreFromBackup() async {
    final result = await FilePicker.platform.pickFiles();
    final path = result?.files.single.path;
    if (path == null) return;

    if (!mounted) return;
    final password = await _promptBackupPassword();
    if (password == null || password.isEmpty || !mounted) return;

    setState(() => _busy = true);
    try {
      final contents =
          await BackupService.readBackup(file: File(path), password: password);
      await BackupService.restoreBackup(contents);

      try {
        final repo = ref.read(meshRepositoryProvider);
        await repo.init(contents.identity.id, contents.identity.pseudo);
        ref.read(callProvider.notifier).init(repo.transport);
        ref.read(groupCallProvider.notifier).init(repo.transport, repo.myId);
      } catch (e) {
        debugPrint('[Onboarding] mesh init error (restore): $e');
      }

      if (!mounted) return;
      context.go('/chats');
    } on BackupPasswordException catch (e) {
      if (!mounted) return;
      _toast(e.message, DropletToastType.error);
    } catch (e) {
      if (!mounted) return;
      _toast('Échec de la restauration', DropletToastType.error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  PHOTO DE PROFIL
  // ─────────────────────────────────────────────────────────────

  /// Ouvre le choix de la photo, puis l'enregistre.
  ///
  /// ⚠️ RIEN N'EST JAMAIS CHARGÉ EN TAILLE RÉELLE. Voir la note en tête
  /// d'`AvatarService` : une photo de téléphone décodée occupe une
  /// cinquantaine de méga-octets, et Droplet vise des appareils de 2 Go.
  Future<void> _choisirPhoto() async {
    final octets = await choisirUnePhoto(context);
    if (octets == null || !mounted) return;

    final nom = await AvatarService.enregistrer(octets);
    if (!mounted) return;
    if (nom == null) {
      _toast('Impossible d\'enregistrer la photo', DropletToastType.error);
      return;
    }
    OuroHaptics.success();
    setState(() {
      _avatarNom = nom;
      _avatarApercu = octets;
    });
  }

  Future<void> _retirerPhoto() async {
    OuroHaptics.light();
    await AvatarService.supprimer();
    if (!mounted) return;
    setState(() {
      _avatarNom = null;
      _avatarApercu = null;
    });
  }

  // ─────────────────────────────────────────────────────────────
  //  INVITATION
  // ─────────────────────────────────────────────────────────────

  /// Partage Droplet — le fichier d'installation lui-même quand c'est
  /// possible, un texte sinon.
  ///
  /// ⚠️ ENVOYER L'APPLICATION ELLE-MÊME EST LE POINT ENTIER DE CETTE
  /// PAGE, et pas une commodité.
  ///
  /// Droplet a un paradoxe fondateur : il fonctionne sans internet, mais
  /// il en fallait pour se le procurer. Là où l'application a le plus de
  /// sens — pas de couverture, données mobiles chères — le premier
  /// obstacle n'a jamais été le maillage, c'est d'être deux à l'avoir
  /// installé. Un lien de téléchargement ne résout pas ce problème, il
  /// le déplace.
  ///
  /// Le fichier d'installation, lui, part par Bluetooth, par Wi-Fi
  /// Direct ou sur une carte mémoire. Personne n'a besoin de connexion,
  /// à aucun moment. C'est le seul moyen de partage qui soit cohérent
  /// avec ce que l'application prétend être.
  Future<void> _partagerLApp() async {
    OuroHaptics.light();
    final apk = await MediaService.installerPath;
    try {
      if (apk != null && File(apk).existsSync()) {
        await Share.shareXFiles(
          [
            XFile(apk,
                mimeType: 'application/vnd.android.package-archive',
                name: 'Droplet.apk'),
          ],
          subject: 'Droplet',
          text: kTexteInvitation,
        );
      } else {
        await Share.share(kTexteInvitation, subject: 'Droplet');
      }
    } catch (e) {
      debugPrint('[Onboarding] partage impossible: $e');
      if (!mounted) return;
      _toast('Partage indisponible', DropletToastType.error);
    }
  }

  void _toast(String message, DropletToastType type) {
    ref.read(toastProvider.notifier).show(message, type: type);
  }

  // ─────────────────────────────────────────────────────────────
  //  AFFICHAGE
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OuroColors.systemBackground,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pageCtrl,
                // Une fois l'identité créée, on ne fait plus défiler :
                // il ne reste qu'une page, et revenir en arrière
                // n'aurait plus aucun effet (voir `_identiteCreee`).
                physics: _identiteCreee
                    ? const NeverScrollableScrollPhysics()
                    : null,
                onPageChanged: (i) {
                  // ⚠️ LE GARDE-FOU DU PSEUDO.
                  //
                  // Le bouton se désactive tant que le pseudo est trop
                  // court, mais un `PageView` se fait glisser au doigt :
                  // sans cela, on arrivait sur la page de la photo puis
                  // sur la création d'identité sans jamais avoir donné
                  // de nom.
                  if (i > _pagePseudo && !_pseudoValid && !_identiteCreee) {
                    _allerA(_pagePseudo);
                    return;
                  }
                  OuroHaptics.selection();
                  setState(() => _page = i);
                },
                children: [
                  const _WelcomePage(),
                  const _HowItWorksPage(),
                  const _StatusPage(),
                  const _SafetyPage(),
                  _IdentityPage(
                    controller: _pseudoCtrl,
                    onRestore: _restoreFromBackup,
                    onSubmit: _next,
                  ),
                  _PhotoPage(
                    pseudo: _pseudoCtrl.text.trim(),
                    apercu: _avatarApercu,
                    onChoisir: _choisirPhoto,
                    onRetirer: _retirerPhoto,
                  ),
                  _NetworkPage(onPartager: _partagerLApp),
                ],
              ),
            ),
            _bottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _bottomBar() {
    // Le libellé du bouton dit ce qui va se passer, jamais « Suivant ».
    // Sur la page de la photo, il dit même les DEUX choses possibles :
    // sans photo choisie, continuer revient à passer l'étape, et le
    // bouton l'annonce plutôt que de le laisser deviner.
    final libelle = switch (_page) {
      _pagePhoto =>
        _avatarNom == null ? 'Passer cette étape' : 'Continuer',
      _pageReseau => 'Commencer',
      _ => 'Continuer',
    };
    final enabled = !_busy && (_page != _pagePseudo || _pseudoValid);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        DesignTokens.space6,
        DesignTokens.space3,
        DesignTokens.space6,
        MediaQuery.viewInsetsOf(context).bottom + DesignTokens.space5,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Dots(count: _pageCount, index: _page),
          const SizedBox(height: DesignTokens.space5),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: OuroColors.accent,
                disabledBackgroundColor: OuroColors.quaternarySystemFill,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
                ),
              ),
              onPressed: enabled ? _next : null,
              child: _busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: OuroSpinner(color: Colors.white, radius: 11),
                    )
                  : Text(
                      libelle,
                      style: OuroTypography.headline.copyWith(
                        color: enabled ? Colors.white : OuroColors.tertiaryLabel,
                      ),
                    ),
            ),
          ),
          // La restauration vit sur la page du pseudo, et là seulement :
          // c'est le moment où quelqu'un qui a DÉJÀ une identité doit
          // pouvoir dire « je n'ai pas à en créer une ». Plus tôt, il
          // n'aurait pas encore compris ; plus tard, il aurait déjà
          // fabriqué une identité neuve pour rien.
          if (_page == _pagePseudo) ...[
            const SizedBox(height: DesignTokens.space2),
            TextButton(
              onPressed: _busy ? null : _restoreFromBackup,
              child: Text(
                "J'ai déjà une sauvegarde",
                style: OuroTypography.subheadline
                    .copyWith(color: OuroColors.accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  LES PAGES
// ─────────────────────────────────────────────────────────────

/// Page 1 — ce que Droplet fait, en trois lignes.
class _WelcomePage extends StatelessWidget {
  const _WelcomePage();

  @override
  Widget build(BuildContext context) {
    return _PageBody(
      children: [
        // L'icône de l'app, la même que celle sur laquelle on vient
        // d'appuyer : c'est ce qui rattache cet écran à l'app plutôt
        // qu'à un diaporama générique.
        ClipRRect(
          borderRadius: BorderRadius.circular(88 * 0.2237),
          child: Image.asset('assets/icon/droplet_icon.png',
              width: 88, height: 88, filterQuality: FilterQuality.medium),
        )
            .animate()
            .fadeIn(duration: 380.ms)
            .scaleXY(
              begin: 0.76,
              duration: 620.ms,
              curve: Curves.fastEaseInToSlowEaseOut,
            ),
        const SizedBox(height: DesignTokens.space5),
        _Title('Bienvenue dans\nDroplet'),
        const SizedBox(height: DesignTokens.space3),
        _Subtitle(
          'Une messagerie qui fonctionne là où il n\'y a plus de réseau.',
        ),
        const SizedBox(height: 40),
        const _Feature(
          icon: Icons.wifi_off_rounded,
          color: Color(0xFF30B0C7),
          title: 'Sans internet, sans opérateur',
          text: 'Les téléphones se parlent directement, de proche en '
              'proche. Aucune antenne, aucune facture.',
          delay: 220,
        ),
        const _Feature(
          icon: Icons.lock_rounded,
          color: Color(0xFF34C759),
          title: 'Chiffré de bout en bout',
          text: 'Même les téléphones qui relaient vos messages ne '
              'peuvent pas les lire.',
          delay: 360,
        ),
        const _Feature(
          icon: Icons.smartphone_rounded,
          color: Color(0xFF5E5CE6),
          title: 'Rien ne quitte votre appareil',
          text: 'Pas de compte, pas de serveur, pas de collecte. Vos '
              'conversations restent chez vous.',
          delay: 500,
        ),
      ],
    );
  }
}

/// Page 2 — comment un message voyage sans réseau.
class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage();

  @override
  Widget build(BuildContext context) {
    return _PageBody(
      children: [
        const SizedBox(height: DesignTokens.space4),
        const _RelayDiagram(),
        const SizedBox(height: DesignTokens.space6),
        _Title('De proche\nen proche'),
        const SizedBox(height: DesignTokens.space3),
        _Subtitle(
          'Votre message saute d\'un téléphone à l\'autre jusqu\'à son '
          'destinataire, même si vous n\'êtes pas à portée directe.',
        ),
        const SizedBox(height: DesignTokens.space6),
        const _Feature(
          icon: Icons.groups_rounded,
          color: Color(0xFF007AFF),
          title: 'Plus on est nombreux, plus loin ça porte',
          text: 'Chaque appareil à portée agrandit le réseau pour tout '
              'le monde.',
          delay: 260,
        ),
        const _Feature(
          icon: Icons.schedule_rounded,
          color: Color(0xFFFF9500),
          title: 'Rien ne se perd',
          text: 'Un message destiné à quelqu\'un d\'absent attend, puis '
              'repart dès qu\'un chemin s\'ouvre.',
          delay: 400,
        ),
      ],
    );
  }
}

/// Page 3 — se retrouver et donner de ses nouvelles.
///
/// C'est la page qui explique ce que Droplet fait de PLUS qu'une
/// messagerie : la carte des personnes à portée, et le signal « je vais
/// bien » qui circule sans réseau.
///
/// Elle est placée AVANT le choix du pseudo, et pas après : ces deux
/// fonctions sont la raison d'être de l'application en situation
/// d'urgence. Les découvrir une fois installé, au hasard d'un onglet,
/// serait les découvrir trop tard.
class _SafetyPage extends StatelessWidget {
  const _SafetyPage();

  @override
  Widget build(BuildContext context) {
    return _PageBody(
      children: [
        const SizedBox(height: DesignTokens.space4),
        const _SafetyDiagram(),
        const SizedBox(height: DesignTokens.space6),
        _Title('Se retrouver,\nsans réseau'),
        const SizedBox(height: DesignTokens.space3),
        _Subtitle(
          'Quand plus rien ne fonctionne, savoir où sont les autres et '
          "qu'ils vont bien devient l'information la plus utile.",
        ),
        const SizedBox(height: DesignTokens.space6),
        const _Feature(
          icon: Icons.map_rounded,
          color: Color(0xFF34C759),
          title: 'Une carte qui marche hors ligne',
          text: 'Les zones que vous consultez restent sur le téléphone. '
              'Une fois parcourues, elles s\'affichent sans internet.',
          delay: 240,
        ),
        const _Feature(
          icon: Icons.near_me_rounded,
          color: Color(0xFF007AFF),
          title: 'Les positions viennent du mesh',
          text: 'Aucun serveur : la position part du téléphone de votre '
              "contact, chiffrée, et saute d'appareil en appareil jusqu'au "
              'vôtre.',
          delay: 380,
        ),
        const _Feature(
          icon: Icons.health_and_safety_rounded,
          color: Color(0xFFFF3B30),
          title: '« Je suis en sécurité », en un geste',
          text: 'Un seul appui diffuse votre statut à tout le voisinage. '
              'Vous choisissez d\'y joindre une position approximative, ou '
              'pas.',
          delay: 520,
        ),
      ],
    );
  }
}

/// Page 3 — les statuts.
///
/// ⚠️ POURQUOI CETTE PAGE EST PLACÉE AVANT LA MISE EN SÉCURITÉ.
///
/// Les statuts sont la fonction la plus FAMILIÈRE de Droplet : tout le
/// monde en a déjà publié ailleurs. Les montrer ici sert de pont — on
/// reconnaît quelque chose, donc on comprend que ce n'est pas un outil
/// technique réservé aux urgences.
///
/// Ce que la page ne dit PAS, et c'est délibéré : elle ne promet pas que
/// tout le monde verra le statut. Sur un maillage, une publication
/// atteint qui est à portée, directement ou de relais en relais — pas
/// « vos contacts », notion qui n'existe pas sans serveur.
class _StatusPage extends StatelessWidget {
  const _StatusPage();

  @override
  Widget build(BuildContext context) {
    return _PageBody(
      children: [
        const SizedBox(height: DesignTokens.space4),
        const StatusRingsDiagram(),
        const SizedBox(height: DesignTokens.space6),
        _Title('Donner des\nnouvelles'),
        const SizedBox(height: DesignTokens.space3),
        _Subtitle(
          'Une photo, un mot, une humeur : votre statut circule de '
          'téléphone en téléphone, comme vos messages.',
        ),
        const SizedBox(height: DesignTokens.space6),
        const _Feature(
          icon: Icons.auto_awesome_motion_rounded,
          color: Color(0xFF5E5CE6),
          title: 'Photo, vidéo ou texte',
          text: 'Publiez ce que vous voulez montrer. Les personnes à '
              'portée le reçoivent, sans passer par internet.',
          delay: 240,
        ),
        const _Feature(
          icon: Icons.visibility_rounded,
          color: Color(0xFF007AFF),
          title: 'Vous voyez qui l\'a regardé',
          text: 'Chaque personne qui ouvre votre statut vous le fait '
              'savoir en retour, par le même chemin.',
          delay: 380,
        ),
        const _Feature(
          icon: Icons.hourglass_bottom_rounded,
          color: Color(0xFFFF9500),
          title: 'Ça disparaît après un jour',
          text: 'Vingt-quatre heures, puis le statut s\'efface de tous '
              'les téléphones qui l\'avaient reçu.',
          delay: 520,
        ),
      ],
    );
  }
}

/// Page 6 — la photo de profil.
///
/// Elle vient APRÈS le pseudo, et pas avant : on accepte plus volontiers
/// de donner une image de soi quand on a déjà donné un nom. Elle est
/// aussi la seule page entièrement facultative de l'accueil, et le
/// bouton du bas le dit en toutes lettres (« Passer cette étape »)
/// plutôt que de le laisser deviner.
class _PhotoPage extends StatelessWidget {
  const _PhotoPage({
    required this.pseudo,
    required this.apercu,
    required this.onChoisir,
    required this.onRetirer,
  });

  final String pseudo;
  final Uint8List? apercu;
  final VoidCallback onChoisir;
  final VoidCallback onRetirer;

  @override
  Widget build(BuildContext context) {
    final octets = apercu;

    return _PageBody(
      children: [
        const SizedBox(height: DesignTokens.space4),
        Center(
          child: AvatarRing(
            rempli: octets != null,
            rayon: 62,
            onTap: onChoisir,
            child: octets != null
                ? Image.memory(
                    octets,
                    fit: BoxFit.cover,
                    // Bornes de décodage : la photo enregistrée fait
                    // déjà 320 pixels de côté, inutile de laisser
                    // Flutter la remettre à l'échelle de l'écran.
                    cacheWidth: AvatarService.cote,
                    cacheHeight: AvatarService.cote,
                    gaplessPlayback: true,
                  )
                : _AvatarVide(pseudo: pseudo),
          ),
        )
            .animate()
            .fadeIn(duration: 380.ms)
            .scaleXY(
              begin: 0.84,
              duration: 640.ms,
              curve: Curves.fastEaseInToSlowEaseOut,
            ),
        const SizedBox(height: DesignTokens.space3),
        Center(
          child: TextButton(
            onPressed: octets != null ? onRetirer : onChoisir,
            child: Text(
              octets != null ? 'Retirer la photo' : 'Choisir une photo',
              style: OuroTypography.subheadline.copyWith(
                color: octets != null
                    ? OuroColors.secondaryLabel
                    : OuroColors.accent,
              ),
            ),
          ),
        ),
        const SizedBox(height: DesignTokens.space5),
        _Title('Un visage,\nsi vous voulez'),
        const SizedBox(height: DesignTokens.space3),
        _Subtitle(
          'Elle aide les autres à vous reconnaître dans une liste. '
          'Rien ne vous oblige à en mettre une.',
        ),
        const SizedBox(height: DesignTokens.space6),
        const _Feature(
          icon: Icons.phone_android_rounded,
          color: Color(0xFF34C759),
          title: 'Elle reste sur ce téléphone',
          text: 'Aucun serveur ne la reçoit, aucune sauvegarde en ligne '
              'ne la conserve. Elle vit dans le dossier de '
              'l\'application, et nulle part ailleurs.',
          delay: 260,
        ),
        const _Feature(
          icon: Icons.compress_rounded,
          color: Color(0xFF30B0C7),
          title: 'Réduite avant d\'être rangée',
          text: 'Droplet n\'en garde qu\'une vignette de 320 pixels. '
              'Votre photo d\'origine n\'est jamais copiée.',
          delay: 400,
        ),
      ],
    );
  }
}

/// Le rond vide de la page photo : l'initiale, en attendant mieux.
class _AvatarVide extends StatelessWidget {
  const _AvatarVide({required this.pseudo});

  final String pseudo;

  @override
  Widget build(BuildContext context) {
    final initiale =
        pseudo.trim().isEmpty ? '?' : pseudo.trim()[0].toUpperCase();

    return ColoredBox(
      color: OuroColors.tertiarySystemFill,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Text(
            initiale,
            style: OuroTypography.largeTitle.copyWith(
              fontSize: 52,
              color: OuroColors.quaternaryLabel,
            ),
          ),
          // Le petit appareil photo en bas : sans lui, le rond ressemble
          // à un avatar déjà défini plutôt qu'à un bouton.
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: OuroColors.accent,
                ),
                child: const Icon(Icons.add_a_photo_rounded,
                    size: 15, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ⚠️ AUCUN LIEN DE TÉLÉCHARGEMENT N'EST ÉCRIT ICI, ET C'EST VOLONTAIRE.
///
/// Droplet n'est distribué à aucune adresse publique pour l'instant.
/// Écrire un lien qui n'existe pas ferait tomber sur une page d'erreur
/// la personne qu'on vient d'inviter — le plus sûr moyen de la perdre
/// définitivement, et sur le geste dont l'application dépend le plus.
///
/// Le jour de la publication, il suffit de renseigner [kLienTelechargement].
const String kLienTelechargement = '';

/// Le message qui accompagne le partage.
///
/// Il explique ce qu'est Droplet à quelqu'un qui n'en a jamais entendu
/// parler, en une phrase, et dit quoi faire du fichier joint.
String get kTexteInvitation {
  const base = 'Je t\'envoie Droplet — une messagerie qui marche sans '
      'internet et sans opérateur : les téléphones se parlent '
      'directement. Installe le fichier joint, et on pourra s\'écrire '
      'même sans réseau.';
  return kLienTelechargement.isEmpty
      ? base
      : '$base\n\n$kLienTelechargement';
}

/// Page 7 — l'effet de réseau.
///
/// ⚠️ C'EST LA PAGE LA PLUS IMPORTANTE DE TOUT L'ACCUEIL, et celle qui
/// n'existait pas.
///
/// Droplet a un défaut qu'aucune autre messagerie n'a : **seul, il ne
/// sert à rien**. On l'installe, on ouvre, il n'y a personne, et on
/// désinstalle. Ce n'est pas une panne — c'est la nature d'un réseau
/// maillé, et c'est de loin la première cause d'abandon.
///
/// Une phrase du genre « plus il y a d'utilisateurs, mieux ça marche »
/// est vraie et parfaitement inopérante : on la lit sans la ressentir.
/// L'animation, elle, la montre — un groupe isolé, puis une seule
/// personne qui arrive au milieu, et le compteur qui saute de quatre à
/// dix (voir [NetworkGrowthDiagram]).
///
/// Et surtout, la page ne se contente pas d'expliquer : elle donne le
/// moyen d'agir tout de suite, en envoyant l'application ELLE-MÊME sans
/// passer par internet.
class _NetworkPage extends StatelessWidget {
  const _NetworkPage({required this.onPartager});

  final VoidCallback onPartager;

  @override
  Widget build(BuildContext context) {
    return _PageBody(
      children: [
        const SizedBox(height: DesignTokens.space3),
        const NetworkGrowthDiagram(),
        const SizedBox(height: DesignTokens.space5),
        _Title('Droplet grandit\navec vous'),
        const SizedBox(height: DesignTokens.space3),
        _Subtitle(
          'Chaque personne qui l\'installe agrandit le réseau — pour '
          'elle, et pour tous ceux qui sont autour.',
        ),
        const SizedBox(height: DesignTokens.space5),

        // Le bouton d'action AVANT les explications : à ce stade de
        // l'accueil, la démonstration vient d'avoir lieu à l'écran. Le
        // moment de convertir, c'est maintenant, pas après trois
        // paragraphes de plus.
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onPartager,
            icon: Icon(Icons.ios_share_rounded,
                size: 19, color: OuroColors.accent),
            label: Text(
              'Envoyer Droplet à un proche',
              style:
                  OuroTypography.headline.copyWith(color: OuroColors.accent),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              side: BorderSide(
                  color: OuroColors.accent.withValues(alpha: 0.45)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              ),
            ),
          ),
        )
            .animate(delay: 300.ms)
            .fadeIn(duration: 420.ms)
            .moveY(begin: 14, curve: Curves.easeOutCubic),
        const SizedBox(height: DesignTokens.space6),

        const _Feature(
          icon: Icons.bluetooth_rounded,
          color: Color(0xFF007AFF),
          title: 'Même le partage se passe d\'internet',
          text: 'Droplet vous envoie son propre fichier d\'installation. '
              'Il part par Bluetooth, par Wi-Fi Direct ou sur une carte '
              'mémoire — aucune connexion nécessaire, des deux côtés.',
          delay: 420,
        ),
        const _Feature(
          icon: Icons.hub_rounded,
          color: Color(0xFF5E5CE6),
          title: 'Trois personnes suffisent pour commencer',
          text: 'À deux, vous vous écrivez à portée de vue. À quelques-uns '
              'dans un quartier, les messages se relaient et la portée '
              'devient bien plus grande que chaque téléphone.',
          delay: 560,
        ),
      ],
    );
  }
}

/// Page 4 — le choix du pseudo.
class _IdentityPage extends StatelessWidget {
  const _IdentityPage({
    required this.controller,
    required this.onRestore,
    required this.onSubmit,
  });

  final TextEditingController controller;
  final VoidCallback onRestore;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final length = controller.text.trim().length;

    return _PageBody(
      children: [
        const SizedBox(height: DesignTokens.space5),
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: OuroColors.accent.withValues(alpha: 0.14),
          ),
          child: Icon(Icons.badge_rounded,
              size: 34, color: OuroColors.accent),
        ).animate().fadeIn(duration: 320.ms).scaleXY(
              begin: 0.8,
              duration: 480.ms,
              curve: Curves.fastEaseInToSlowEaseOut,
            ),
        const SizedBox(height: DesignTokens.space5),
        _Title('Comment doit-on\nvous appeler ?'),
        const SizedBox(height: DesignTokens.space3),
        _Subtitle(
          'Ce nom apparaîtra auprès des personnes qui vous croisent. '
          'Vous pouvez en choisir un qui ne vous identifie pas.',
        ),
        const SizedBox(height: DesignTokens.space6),
        TextField(
          controller: controller,
          autofocus: false,
          textCapitalization: TextCapitalization.words,
          maxLength: 24,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => onSubmit(),
          inputFormatters: [LengthLimitingTextInputFormatter(24)],
          cursorColor: OuroColors.accent,
          style: OuroTypography.title3.copyWith(color: OuroColors.label),
          textAlign: TextAlign.center,
          decoration: InputDecoration(
            counterText: '',
            hintText: 'Votre pseudo',
            hintStyle:
                OuroTypography.title3.copyWith(color: OuroColors.tertiaryLabel),
            filled: true,
            fillColor: OuroColors.tertiarySystemFill,
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
              borderSide: BorderSide(color: OuroColors.accent, width: 1.5),
            ),
          ),
        ).animate(delay: 160.ms).fadeIn(duration: 320.ms).moveY(begin: 10),
        const SizedBox(height: DesignTokens.space3),
        AnimatedOpacity(
          // L'indication n'apparaît que lorsqu'elle sert : on a commencé
          // à écrire, mais c'est encore trop court. Affichée d'emblée,
          // elle ressemblerait à un reproche avant même d'avoir essayé.
          opacity: (length > 0 && length < 3) ? 1 : 0,
          duration: DesignTokens.durationFast,
          child: Text(
            'Au moins 3 caractères',
            style: OuroTypography.footnote
                .copyWith(color: OuroColors.secondaryLabel),
          ),
        ),
        const SizedBox(height: DesignTokens.space5),
        _Feature(
          icon: Icons.vpn_key_rounded,
          color: OuroColors.systemGreen,
          title: 'Vos clés sont créées ici, maintenant',
          text: 'Elles ne quittent jamais ce téléphone. Pensez à faire '
              'une sauvegarde depuis les réglages : sans elle, une '
              'identité perdue l\'est définitivement.',
          delay: 300,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  BRIQUES COMMUNES
// ─────────────────────────────────────────────────────────────

/// Le corps d'une page : marges, défilement, et alignement à gauche.
///
/// Défilant plutôt que fixe : sur un petit écran avec un clavier ouvert,
/// une page fixe couperait la dernière ligne — et une explication à
/// moitié visible ne vaut pas mieux qu'aucune explication.
class _PageBody extends StatelessWidget {
  const _PageBody({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: DesignTokens.space6,
        vertical: DesignTokens.space5,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: OuroTypography.largeTitle.copyWith(
        color: OuroColors.label,
        height: 1.1,
      ),
    ).animate().fadeIn(duration: 360.ms, delay: 80.ms).moveY(
          begin: 14,
          duration: 520.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

class _Subtitle extends StatelessWidget {
  const _Subtitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: OuroTypography.body.copyWith(
        color: OuroColors.secondaryLabel,
        height: 1.4,
      ),
    ).animate().fadeIn(duration: 360.ms, delay: 160.ms).moveY(
          begin: 12,
          duration: 520.ms,
          curve: Curves.easeOutCubic,
        );
  }
}

/// Une ligne de fonctionnalité : pastille colorée, titre, explication.
///
/// C'est la brique de base des écrans de bienvenue d'Apple. Les icônes
/// sont alignées sur une même colonne et de taille identique — c'est
/// cet alignement, plus que les icônes elles-mêmes, qui donne à
/// l'ensemble son air rangé.
class _Feature extends StatelessWidget {
  const _Feature({
    required this.icon,
    required this.color,
    required this.title,
    required this.text,
    required this.delay,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String text;

  /// Décalage d'apparition, en millièmes de seconde.
  final int delay;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Icon(icon, color: color, size: 27),
          ),
          const SizedBox(width: DesignTokens.space4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: OuroTypography.headline
                      .copyWith(color: OuroColors.label),
                ),
                const SizedBox(height: 3),
                Text(
                  text,
                  style: OuroTypography.subheadline.copyWith(
                    color: OuroColors.secondaryLabel,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    )
        .animate(delay: Duration(milliseconds: delay))
        .fadeIn(duration: 400.ms)
        .moveY(begin: 16, duration: 560.ms, curve: Curves.easeOutCubic);
  }
}

/// Les points de progression sous les pages.
class _Dots extends StatelessWidget {
  const _Dots({required this.count, required this.index});
  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          AnimatedContainer(
            duration: DesignTokens.durationStandard,
            curve: DesignTokens.curveStandard,
            margin: const EdgeInsets.symmetric(horizontal: 3),
            // Le point actif s'ALLONGE au lieu de simplement changer de
            // couleur : la différence se voit du coin de l'œil, sans
            // avoir à comparer deux teintes.
            width: i == index ? 20 : 7,
            height: 7,
            decoration: BoxDecoration(
              color: i == index
                  ? OuroColors.accent
                  : OuroColors.quaternaryLabel,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  LE SCHÉMA DU RELAIS
// ─────────────────────────────────────────────────────────────

/// Trois téléphones, et un message qui passe de l'un à l'autre.
///
/// Une seule idée montrée : ce que « de proche en proche » veut dire.
/// L'animation tourne en boucle, mais lentement et sur une petite
/// surface — c'est le seul mouvement de la page, et il illustre le
/// texte au lieu de lui faire concurrence.
class _RelayDiagram extends StatefulWidget {
  const _RelayDiagram();

  @override
  State<_RelayDiagram> createState() => _RelayDiagramState();
}

class _RelayDiagramState extends State<_RelayDiagram>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 130,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _RelayPainter(
            t: _c.value,
            accent: OuroColors.accent,
            idle: OuroColors.quaternaryLabel,
            surface: OuroColors.secondarySystemBackground,
          ),
        ),
      ),
    );
  }
}

class _RelayPainter extends CustomPainter {
  _RelayPainter({
    required this.t,
    required this.accent,
    required this.idle,
    required this.surface,
  });

  final double t;
  final Color accent;
  final Color idle;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final margin = size.width * 0.16;
    final xs = [margin, size.width / 2, size.width - margin];

    // Le trait qui relie les appareils, en pointillés : une ligne pleine
    // suggérerait un câble, or il n'y en a pas.
    final dash = Paint()
      ..color = idle
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 2; i++) {
      final from = xs[i] + 26;
      final to = xs[i + 1] - 26;
      for (var x = from; x < to; x += 11) {
        canvas.drawLine(Offset(x, y), Offset(math.min(x + 5, to), y), dash);
      }
    }

    // La goutte de message qui parcourt le trajet, d'un bout à l'autre.
    final travel = xs.first + (xs.last - xs.first) * Curves.easeInOut.transform(t);
    canvas.drawCircle(Offset(travel, y), 7, Paint()..color = accent);
    canvas.drawCircle(
      Offset(travel, y),
      13,
      Paint()..color = accent.withValues(alpha: 0.18),
    );

    // Les trois appareils. Celui que la goutte traverse s'illumine :
    // c'est ce qui fait comprendre qu'il RELAIE, et n'est pas seulement
    // posé là.
    for (var i = 0; i < 3; i++) {
      final x = xs[i];
      final near = (travel - x).abs() < 34;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(x, y), width: 34, height: 54),
        const Radius.circular(9),
      );
      canvas.drawRRect(rect, Paint()..color = surface);
      canvas.drawRRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = near ? 2.4 : 1.4
          ..color = near ? accent : idle,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RelayPainter old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────
//  LE SCHÉMA DE LA MISE EN SÉCURITÉ
// ─────────────────────────────────────────────────────────────

/// Une carte stylisée, trois points, et un halo qui se propage.
///
/// Le dessin montre UNE idée : une position émise quelque part atteint
/// les autres de proche en proche. Les rues sont suggérées, jamais
/// détaillées — ce n'est pas une carte, c'est l'explication d'un
/// mécanisme.
class _SafetyDiagram extends StatefulWidget {
  const _SafetyDiagram();

  @override
  State<_SafetyDiagram> createState() => _SafetyDiagramState();
}

class _SafetyDiagramState extends State<_SafetyDiagram>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 150,
      width: double.infinity,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _SafetyPainter(
            t: _c.value,
            accent: OuroColors.accent,
            safe: OuroColors.systemGreen,
            idle: OuroColors.quaternaryLabel,
            surface: OuroColors.secondarySystemBackground,
          ),
        ),
      ),
    );
  }
}

class _SafetyPainter extends CustomPainter {
  _SafetyPainter({
    required this.t,
    required this.accent,
    required this.safe,
    required this.idle,
    required this.surface,
  });

  final double t;
  final Color accent;
  final Color safe;
  final Color idle;
  final Color surface;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // ── Le fond : quelques rues suggérées ────────────────────────
    final street = Paint()
      ..color = idle.withValues(alpha: 0.30)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final rect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      const Radius.circular(18),
    );
    canvas.save();
    canvas.clipRRect(rect);
    canvas.drawRRect(rect, Paint()..color = surface);

    for (var i = 1; i < 5; i++) {
      final y = h * i / 5;
      canvas.drawLine(Offset(0, y), Offset(w, y), street);
    }
    for (var i = 1; i < 7; i++) {
      final x = w * i / 7;
      canvas.drawLine(Offset(x, 0), Offset(x, h), street);
    }

    // ── L'émetteur, et l'onde qui part de lui ────────────────────
    final origin = Offset(w * 0.28, h * 0.62);

    // Trois ondes décalées : une seule donnerait un clignotement, trois
    // donnent une propagation continue.
    for (var i = 0; i < 3; i++) {
      final phase = (t + i / 3) % 1.0;
      final radius = phase * w * 0.55;
      canvas.drawCircle(
        origin,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          // L'onde s'efface en s'éloignant : c'est ce qui la fait
          // « partir » au lieu de simplement grandir.
          ..color = safe.withValues(alpha: (1 - phase) * 0.55),
      );
    }

    _pin(canvas, origin, safe, filled: true);

    // ── Les destinataires, atteints quand l'onde les touche ──────
    final others = [
      Offset(w * 0.62, h * 0.34),
      Offset(w * 0.80, h * 0.70),
    ];
    for (final other in others) {
      final distance = (other - origin).distance;
      final front = ((t % 1.0) * w * 0.55);
      // « Atteint » pendant un court instant après le passage du front :
      // c'est ce qui donne la sensation d'un relais, et non d'un simple
      // décor allumé en permanence.
      final reached = front > distance && front < distance + w * 0.22;
      _pin(canvas, other, reached ? safe : idle, filled: reached);
    }

    canvas.restore();
    canvas.drawRRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = idle.withValues(alpha: 0.4),
    );
  }

  /// Une goutte posée sur la carte — la même forme que la marque de
  /// l'application, en miniature.
  void _pin(Canvas canvas, Offset center, Color color, {bool filled = false}) {
    final path = Path()
      ..moveTo(center.dx, center.dy - 13)
      ..cubicTo(center.dx + 9, center.dy - 3, center.dx + 9, center.dy + 3,
          center.dx + 9, center.dy + 4)
      ..arcToPoint(Offset(center.dx - 9, center.dy + 4),
          radius: const Radius.circular(9), clockwise: false)
      ..cubicTo(center.dx - 9, center.dy + 3, center.dx - 9, center.dy - 3,
          center.dx, center.dy - 13)
      ..close();

    if (filled) {
      canvas.drawCircle(center, 17, Paint()..color = color.withValues(alpha: 0.18));
    }
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SafetyPainter old) => old.t != t;
}
