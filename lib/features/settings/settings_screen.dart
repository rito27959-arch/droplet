// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'écran RÉGLAGES — refait à l'identique du modèle de Réglages sur iOS,
// puisque c'est exactement le même besoin : une liste d'options rangées
// par thème.
//
// CE QUI A CHANGÉ À LA REFONTE : l'ancienne version empilait de grandes
// cartes espacées, chacune avec sa propre icône dans un cercle coloré et
// sa propre animation d'entrée décalée. C'était lisible, mais ça
// n'utilisait qu'une fraction de l'écran et ne ressemblait à aucune
// convention connue.
//
// La nouvelle version utilise les LISTES GROUPÉES (voir `ouro_list.dart`) :
// des îlots compacts, séparés par de petits titres gris, avec les icônes
// en pastilles carrées colorées. C'est plus dense, immédiatement familier,
// et surtout ça permet d'ajouter des explications sous chaque groupe sans
// alourdir les lignes elles-mêmes.
// ============================================================================

import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/providers/appearance_provider.dart';
import '../../core/providers/chat_background_provider.dart';
import '../../core/providers/premium_provider.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/providers/tor_providers.dart';
import '../../core/services/tor_service.dart';
import '../../core/services/avatar_service.dart';
import '../../core/services/premium_service.dart';
import '../../core/services/mesh_foreground_service.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_typography.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_list.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/liquid_bridge.dart';
import '../../design_system/mode_transition.dart';
import '../../shared/widgets/avatar_picker_sheet.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../shared/widgets/premium_badge.dart';
import '../../shared/widgets/moon_sun_avatar.dart';
import 'journal_sheet.dart';
import '../chat/telegram_gradient_background.dart';
import '../contribution/contribution_screen.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = StorageService.currentUser;
    final myId = ref.watch(meshRepositoryProvider).myId;
    final rank = StorageService.getContributionPoints().rank;

    return OuroLargeTitleScaffold(
      title: 'Réglages',
      // Fond « groupé » : c'est le fond que prend iOS dès qu'un écran
      // contient des îlots de liste, plutôt que du contenu plein écran.
      backgroundColor: OuroColors.systemGroupedBackground,
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
                // ── Profil ────────────────────────────────────────────
                // Une grande ligne d'identité en tête, exactement comme
                // la fiche de compte en haut de Réglages iOS.
                _ProfileCard(
                  pseudo: me?.pseudo ?? '—',
                  identifier: myId,
                ),

                const SizedBox(height: DesignTokens.space5),

                const _AppearanceSection(),

                const SizedBox(height: DesignTokens.space5),

                const _ChatBackgroundSection(),

                const SizedBox(height: DesignTokens.space5),

                OuroListSection(
                  header: 'Icône',
                  footer: "Treize icônes au choix pour l'écran d'accueil.",
                  children: [
                    OuroListRow(
                      icon: Icons.apps_rounded,
                      iconColor: OuroColors.systemPink,
                      title: "Icône de l'application",
                      subtitle: '13 variantes',
                      onTap: () => context.push('/settings/icon'),
                    ),
                  ],
                ),

                const SizedBox(height: DesignTokens.space5),

                OuroListSection(
                  header: 'Réseau',
                  footer: 'Le relais en arrière-plan permet de transmettre '
                      'les messages des autres même quand Droplet est fermé.',
                  children: [
                    OuroListRow(
                      icon: Icons.wifi_tethering_rounded,
                      iconColor: OuroColors.systemTeal,
                      title: 'Réseau mesh',
                      subtitle: 'Pairs connectés et topologie',
                      onTap: () => context.push('/mesh-network'),
                    ),
                    const _BackgroundServiceRow(),
                    OuroListRow(
                      icon: Icons.map_rounded,
                      iconColor: OuroColors.systemGreen,
                      title: 'Cartes hors connexion',
                      subtitle: 'Zones enregistrées et import de cartes',
                      onTap: () => context.push('/maps/offline'),
                    ),
                  ],
                ),

                const SizedBox(height: DesignTokens.space5),

                OuroListSection(
                  header: 'Sécurité',
                  footer: 'Droplet ne conserve aucune copie de votre '
                      'identité. Sans sauvegarde, elle est perdue avec '
                      "l'appareil.",
                  children: [
                    OuroListRow(
                      icon: Icons.lock_rounded,
                      iconColor: OuroColors.systemGray,
                      title: 'Sauvegarder mon identité',
                      subtitle: 'Export chiffré par mot de passe',
                      onTap: () => context.push('/backup/export'),
                    ),
                    // L'écran existait déjà, sans aucun chemin pour y
                    // arriver. C'est ce chemin.
                    const _TorRow(),
                    OuroListRow(
                      icon: Icons.health_and_safety_rounded,
                      iconColor: OuroColors.systemRed,
                      title: 'Mode urgence',
                      subtitle: 'Signaler que vous êtes en sécurité',
                      onTap: () => context.push('/safety'),
                    ),
                  ],
                ),

                const SizedBox(height: DesignTokens.space5),

                OuroListSection(
                  header: 'Contribution',
                  children: [
                    OuroListRow(
                      icon: rankIcon(rank),
                      iconColor: rankColor(rank),
                      title: 'Ma contribution',
                      value: rank.label,
                      onTap: () => context.push('/contribution'),
                    ),
                    // ⚠️ ICI ET PAS EN TÊTE D'ÉCRAN. Une entrée payante
                    // posée tout en haut des réglages est la première
                    // chose que voit quelqu'un qui cherchait à changer
                    // son fond d'écran — et une application qui réclame
                    // de l'argent avant d'avoir servi se désinstalle.
                    // Elle vit donc à côté de la contribution, qui parle
                    // déjà de soutenir le projet.
                    OuroListRow(
                      icon: Icons.auto_awesome_rounded,
                      iconColor: OuroColors.accent,
                      title: 'Droplet Pro',
                      value: switch (PremiumService.niveau) {
                        NiveauPremium.pro => 'Actif',
                        NiveauPremium.pack => 'Pack débloqué',
                        NiveauPremium.aucun => 'Icônes et fonds',
                      },
                      onTap: () => context.push('/premium'),
                    ),
                  ],
                ),

                const SizedBox(height: DesignTokens.space5),

                OuroListSection(
                  children: [
                    // Le journal des erreurs.
                    //
                    // Droplet n'a AUCUN serveur, donc aucun rapport de
                    // plantage ne remonte nulle part. Quand l'app se
                    // ferme toute seule chez quelqu'un, la seule trace
                    // existante est ce fichier local — encore faut-il
                    // pouvoir le lire sans brancher l'appareil à un
                    // ordinateur. C'est le rôle de cette rangée.
                    OuroListRow(
                      icon: Icons.bug_report_rounded,
                      iconColor: OuroColors.systemGray,
                      title: 'Journal des erreurs',
                      onTap: () => _showJournal(context),
                    ),
                    OuroListRow(
                      icon: Icons.info_rounded,
                      iconColor: OuroColors.systemGray,
                      title: 'À propos de Droplet',
                      onTap: () => _showAbout(context),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showJournal(BuildContext context) async {
    await afficherJournal(context);
  }

  Future<void> _showAbout(BuildContext context) {
    OuroHaptics.selection();
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const _AboutSheet(),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  PROFIL
// ─────────────────────────────────────────────────────────────

/// Fiche d'identité en haut de l'écran — grand avatar, pseudo, début de
/// l'identifiant public.
///
/// ⚠️ C'EST ICI QU'ON CHANGE SA PHOTO, ET IL FALLAIT QUE ÇA EXISTE.
///
/// La photo se choisit à l'installation. Si c'était le SEUL endroit,
/// se tromper de photo obligerait à réinstaller l'application — donc à
/// perdre son identité et toutes ses conversations, puisque Droplet n'a
/// aucun serveur pour les restituer. Une décision définitive prise en
/// dix secondes le premier jour serait une faute de conception, pas un
/// détail d'ergonomie.
class _ProfileCard extends StatefulWidget {
  const _ProfileCard({required this.pseudo, required this.identifier});

  final String pseudo;
  final String identifier;

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  /// Le nom du fichier de la photo — jamais son chemin. Voir
  /// `AvatarService`.
  String? _nom = StorageService.currentUser?.avatarUrl;

  Future<void> _changerLaPhoto() async {
    final octets = await choisirUnePhoto(context);
    if (octets == null || !mounted) return;
    final nom = await AvatarService.enregistrer(octets);
    if (nom == null || !mounted) return;
    await _enregistrer(nom);
  }

  Future<void> _retirerLaPhoto() async {
    OuroHaptics.light();
    await AvatarService.supprimer();
    if (!mounted) return;
    await _enregistrer(null);
  }

  Future<void> _enregistrer(String? nom) async {
    final me = StorageService.currentUser;
    if (me == null) return;
    await StorageService.saveUser(DropletUserModel(
      id: me.id,
      pseudo: me.pseudo,
      publicKey: me.publicKey,
      avatarUrl: nom,
    ));
    if (!mounted) return;
    if (nom != null) OuroHaptics.success();
    setState(() => _nom = nom);
  }

  @override
  Widget build(BuildContext context) {
    final pseudo = widget.pseudo;
    final identifier = widget.identifier;
    final chemin = AvatarService.chemin(_nom);
    final estPro = PremiumService.niveau.estPro;
    // L'identifiant complet fait 64 caractères : illisible et inutile en
    // entier. On en montre juste assez pour reconnaître le sien.
    final short = identifier.isEmpty
        ? '—'
        : '${identifier.substring(0, identifier.length.clamp(0, 16))}…';

    return Container(
      padding: const EdgeInsets.all(DesignTokens.space4),
      decoration: BoxDecoration(
        color: OuroColors.secondarySystemGroupedBackground,
        borderRadius: BorderRadius.circular(DesignTokens.radiusGroupedList),
      ),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: chemin == null
                ? 'Ajouter une photo de profil'
                : 'Changer la photo de profil',
            excludeSemantics: true,
            child: GestureDetector(
              onTap: _changerLaPhoto,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  chemin == null
                      ? MoonSunAvatar(
                          pseudo: pseudo,
                          radius: 30,
                        )
                      : PeerAvatar(pseudo: pseudo, radius: 30, imagePath: chemin),
                  // La pastille d'appareil photo : sans elle, rien
                  // n'indique que l'avatar est touchable, et personne
                  // n'appuie sur un avatar.
                  Positioned(
                    right: -2,
                    bottom: -2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: OuroColors.accent,
                        border: Border.all(
                          color: OuroColors.secondarySystemGroupedBackground,
                          width: 2,
                        ),
                      ),
                      child: const Icon(Icons.photo_camera_rounded,
                          size: 11, color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: DesignTokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        pseudo,
                        style: OuroTypography.title3.copyWith(
                          color: OuroColors.label,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    // ⚠️ `Flexible` sur le nom, et le badge APRÈS : un
                    // pseudo long doit se faire tronquer, jamais pousser
                    // le badge hors de l'écran. L'inverse donnait un
                    // badge invisible précisément chez les gens qui
                    // avaient payé pour l'avoir.
                    if (estPro) ...[
                      const SizedBox(width: 7),
                      const BadgePro(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  short,
                  style: OuroTypography.footnote.copyWith(
                    color: OuroColors.secondaryLabel,
                  ),
                ),
                // Le retrait n'apparaît que s'il y a quelque chose à
                // retirer : proposer « retirer la photo » à quelqu'un
                // qui n'en a pas est du bruit.
                if (chemin != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: GestureDetector(
                      onTap: _retirerLaPhoto,
                      child: Text(
                        'Retirer la photo',
                        style: OuroTypography.footnote
                            .copyWith(color: OuroColors.accent),
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

// ─────────────────────────────────────────────────────────────
//  APPARENCE
// ─────────────────────────────────────────────────────────────

/// Le choix du thème : Automatique, Clair ou Sombre.
///
/// Trois lignes cochables plutôt qu'une ligne menant à une sous-page :
/// avec seulement trois choix, une sous-page ferait payer deux
/// navigations pour un réglage qu'on veut justement pouvoir essayer
/// d'un coup d'œil — et ici le résultat est visible immédiatement,
/// puisque toute la page se repeint sous le doigt.
/// Le choix du fond de discussion — le dégradé qui tourne d'un cran à
/// chaque message envoyé.
class _ChatBackgroundSection extends ConsumerWidget {
  const _ChatBackgroundSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final courant = ref.watch(chatBackgroundProvider);
    final sombre = Theme.of(context).brightness == Brightness.dark;
    final debloque = ref.watch(packDebloqueProvider);

    Widget rangee(String cle, String titre, Widget apercu) {
      // ⚠️ LE VERROU SE DÉCIDE ICI, À PARTIR DE LA MÊME LISTE QUE
      // PARTOUT AILLEURS (`TelegramGradientPalettes.premium`). Recopier
      // la liste des fonds payants dans l'écran de réglages aurait
      // garanti qu'un jour l'une des deux oublie un fond — et un fond
      // payant offert à tout le monde ne se rattrape pas.
      final verrouille = TelegramGradientPalettes.estPremium(cle) && !debloque;

      return OuroListRow(
        leading: VoileVerrouille(verrouille: verrouille, child: apercu),
        title: titre,
        showChevron: false,
        trailing: verrouille
            ? const EtiquettePremium()
            : cle == courant
                ? Icon(Icons.check_rounded,
                    size: 20, color: OuroColors.accent)
                : const SizedBox(width: 20),
        onTap: () {
          if (verrouille) {
            // On n'affiche pas un refus : on emmène là où ça se
            // débloque. Un « non » sans issue est la façon la plus
            // sûre de perdre quelqu'un qui était prêt à payer.
            OuroHaptics.selection();
            context.push('/premium');
            return;
          }
          if (cle == courant) return;
          OuroHaptics.selection();
          ref.read(chatBackgroundProvider.notifier).set(cle);
        },
      );
    }

    return OuroListSection(
      header: 'Fond de discussion',
      footer: "Le dégradé avance d'un cran à chaque message envoyé. "
          "Choisissez « Aucun » pour un fond uni : rien n'est alors "
          'calculé, ce qui ménage la batterie.',
      children: [
        for (final entree in TelegramGradientPalettes.etiquettes.entries)
          rangee(
            entree.key,
            entree.value,
            GradientPreview(
              couleurs: TelegramGradientPalettes.pour(
                entree.key,
                sombre: sombre,
              )!,
              taille: 28,
            ),
          ),
        rangee(
          kFondAucun,
          'Aucun',
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: OuroColors.systemBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: OuroColors.separator),
            ),
          ),
        ),
      ],
    );
  }
}

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(appearanceProvider);

    return OuroListSection(
      header: 'Apparence',
      footer: 'Droplet est conçu pour le mode sombre : sur un écran OLED '
          'les pixels noirs sont éteints, ce qui économise la batterie et '
          "n'éblouit pas dans l'obscurité. Le mode clair reste disponible "
          'pour la lecture en plein soleil.',
      children: [
        for (final mode in AppearanceMode.values)
          OuroListRow(
            icon: switch (mode) {
              AppearanceMode.system => Icons.brightness_auto_rounded,
              AppearanceMode.light => Icons.light_mode_rounded,
              AppearanceMode.dark => Icons.dark_mode_rounded,
            },
            iconColor: switch (mode) {
              AppearanceMode.system => OuroColors.systemGray,
              AppearanceMode.light => OuroColors.systemOrange,
              AppearanceMode.dark => OuroColors.systemIndigo,
            },
            title: mode.label,
            showChevron: false,
            trailing: mode == current
                ? Icon(Icons.check_rounded,
                    size: 20, color: OuroColors.accent)
                : const SizedBox(width: 20),
            onTap: () async {
              if (mode == current) return;
              OuroHaptics.selection();

              // Direction du changement pour la couleur du cercle.
              final targetBrightness = mode.resolve(Brightness.dark);
              final toDark = targetBrightness == Brightness.dark;

              // ⚠️ TOUT CE QUI SUIT EST SYNCHRONE AVANT set() :
              // Overlay.of, MediaQuery.of, et la capture doivent tous
              // être faits AVANT que set() ne déclenche le rebuild
              // (via ValueKey(brightness) dans main.dart) qui invalide
              // le contexte courant.
              OverlayState? overlay;
              Size? screenSize;
              ui.Image? snapshot;

              try {
                overlay = Overlay.of(context);
                screenSize = MediaQuery.of(context).size;
                snapshot = await ModeTransitionOverlay.capture()
                    .timeout(const Duration(seconds: 2), onTimeout: () => null);
              } catch (_) {
                // La capture peut échouer — ce n'est pas grave, le
                // changement de thème fonctionne quand même.
              }

              final tapPosition = screenSize != null
                  ? Offset(screenSize.width / 2, 250)
                  : Offset.zero;

              // Appliquer le thème — déclenche un rebuild complet via
              // ValueKey(brightness) dans MaterialApp.
              ref.read(appearanceProvider.notifier).set(mode);

              // Lancer la transition Telegram si la capture a réussi.
              // L'overlay reste valide même après le rebuild car c'est
              // un objet OverlayState, pas un contexte.
              if (overlay != null) {
                ModeTransitionOverlay.showWithImage(
                  overlay,
                  tapPosition,
                  snapshot,
                  toDark: toDark,
                  screenSize: screenSize ?? Size.zero,
                );
              }
            },
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  SERVICE D'ARRIÈRE-PLAN
// ─────────────────────────────────────────────────────────────

/// Ligne à interrupteur qui active le relais mesh en arrière-plan, et
/// propose l'exemption d'optimisation batterie quand c'est nécessaire.
class _BackgroundServiceRow extends ConsumerStatefulWidget {
  const _BackgroundServiceRow();

  @override
  ConsumerState<_BackgroundServiceRow> createState() =>
      _BackgroundServiceRowState();
}

class _BackgroundServiceRowState extends ConsumerState<_BackgroundServiceRow> {
  bool? _running;
  bool _batteryExempt = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final running = await MeshForegroundService.isRunning;
    final exempt = await MeshForegroundService.isIgnoringBatteryOptimizations;
    if (!mounted) return;
    setState(() {
      _running = running;
      _batteryExempt = exempt;
    });
  }

  Future<void> _toggle(bool value) async {
    OuroHaptics.light();
    if (value) {
      final confirmed = await _confirmEnable();
      if (confirmed != true) {
        // L'utilisateur a renoncé : on rafraîchit pour que
        // l'interrupteur revienne à sa position réelle.
        await _refresh();
        return;
      }
      await MeshForegroundService.requestNotificationPermission();
      await MeshForegroundService.start();
    } else {
      await MeshForegroundService.stop();
    }
    await _refresh();
  }

  Future<bool?> _confirmEnable() {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => _EnableBackgroundSheet(
        onConfirm: () => Navigator.of(context).pop(true),
        onCancel: () => Navigator.of(context).pop(false),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final running = _running ?? false;

    return Column(
      children: [
        OuroListRow(
          icon: Icons.autorenew_rounded,
          iconColor: OuroColors.systemIndigo,
          title: 'Relais en arrière-plan',
          subtitle: _running == null
              ? '…'
              : running
                  ? 'Actif même app fermée'
                  : 'Actif seulement app ouverte',
          showChevron: false,
          trailing: LiquidGlassSwitch(
            value: running,
            onChanged: _running == null ? null : _toggle,
          ),
        ),
        // L'avertissement batterie n'apparaît QUE s'il est pertinent —
        // c'est-à-dire service actif mais Android encore autorisé à le
        // brider. Un avertissement affiché en permanence finit par ne
        // plus être lu du tout.
        if (running && !_batteryExempt)
          OuroListRow(
            icon: Icons.battery_alert_rounded,
            iconColor: OuroColors.systemOrange,
            title: 'Optimisation de batterie',
            subtitle: 'Android peut limiter le relais',
            value: 'Corriger',
            showChevron: false,
            onTap: () async {
              await MeshForegroundService.requestIgnoreBatteryOptimization();
              await _refresh();
            },
          ),
      ],
    );
  }
}

/// Feuille expliquant le compromis avant d'activer le service
/// d'arrière-plan.
class _EnableBackgroundSheet extends StatelessWidget {
  const _EnableBackgroundSheet({
    required this.onConfirm,
    required this.onCancel,
  });

  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return FrostedSheet(
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Garder Droplet actif ?',
              style: OuroTypography.title2.copyWith(color: OuroColors.label),
            ),
            const SizedBox(height: DesignTokens.space2),
            Text(
              'Une notification permanente indiquera que Droplet relaie le '
              'mesh, même app fermée. En échange, la batterie sera '
              'davantage sollicitée.',
              style: OuroTypography.subheadline.copyWith(
                color: OuroColors.secondaryLabel,
              ),
            ),
            const SizedBox(height: DesignTokens.space5),
            FilledButton(
              onPressed: onConfirm,
              child: const Text('Activer'),
            ),
            const SizedBox(height: DesignTokens.space2),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: onCancel,
                child: const Text('Annuler'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  À PROPOS
// ─────────────────────────────────────────────────────────────

class _AboutSheet extends StatelessWidget {
  const _AboutSheet();

  @override
  Widget build(BuildContext context) {
    return FrostedSheet(
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Droplet',
              style: OuroTypography.title1.copyWith(color: OuroColors.label),
            ),
            const SizedBox(height: DesignTokens.space1),
            Text(
              'Messagerie et appels hors ligne, sans Internet ni opérateur.',
              style: OuroTypography.subheadline.copyWith(
                color: OuroColors.secondaryLabel,
              ),
            ),
            const SizedBox(height: DesignTokens.space5),
            const _AboutPoint(
              icon: Icons.wifi_tethering_rounded,
              text: 'Réseau direct entre appareils — aucun serveur',
            ),
            const _AboutPoint(
              icon: Icons.lock_rounded,
              text: 'Chiffrement de bout en bout sur tous les messages',
            ),
            const _AboutPoint(
              icon: Icons.visibility_off_rounded,
              text: 'Aucune donnée transmise à un tiers',
            ),
            const SizedBox(height: DesignTokens.space3),
            // ⚠️ MENTION OBLIGATOIRE, PAS DÉCORATIVE.
            //
            // Les emojis animés du panneau de stickers viennent de Noto
            // Animated Emoji, publié par Google sous licence CC BY 4.0.
            // Cette licence autorise l'usage commercial et la
            // redistribution, mais EXIGE de créditer l'auteur. Retirer
            // cette ligne ferait de Droplet une application en
            // violation de licence — et c'est le genre de manquement qui
            // fait retirer une application d'un magasin.
            _Attribution(),
          ],
        ),
      ),
    );
  }
}

/// La feuille qui montre le journal des erreurs.
///
/// Volontairement austère : c'est un outil de diagnostic, pas une page à
/// consulter tous les jours. Le journal vide est le cas NORMAL, et c'est

/// Les crédits des ressources tierces embarquées.
class _Attribution extends StatelessWidget {
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return Text(
      'Emojis animés : Noto Animated Emoji © Google, sous licence '
      'CC BY 4.0.',
      style: OuroTypography.caption1.copyWith(
        color: OuroColors.tertiaryLabel,
      ),
    );
  }
}

class _AboutPoint extends StatelessWidget {
  const _AboutPoint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DesignTokens.space3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: DesignTokens.iconMd, color: OuroColors.systemGray),
          const SizedBox(width: DesignTokens.space3),
          Expanded(
            child: Text(
              text,
              style: OuroTypography.subheadline.copyWith(
                color: OuroColors.label,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// La ligne Tor des réglages : elle dit l'état réel, pas seulement le nom
/// de l'écran.
///
/// ⚠️ Le sous-titre porte l'information utile. « Tor » seul obligerait à
/// ouvrir l'écran pour savoir si c'est allumé — et c'est précisément la
/// question qu'on se pose en parcourant les réglages.
class _TorRow extends ConsumerWidget {
  const _TorRow();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etat = ref.watch(torStateProvider).valueOrNull;
    final actif = ref.watch(torActifProvider);

    final (couleur, sousTitre) = switch (etat) {
      TorServiceState.connected => (
          OuroColors.systemGreen,
          'Circuit établi — trafic acheminé par Tor',
        ),
      TorServiceState.connecting => (
          OuroColors.systemOrange,
          'Connexion en cours…',
        ),
      TorServiceState.error => (
          OuroColors.systemRed,
          'Connexion impossible — toucher pour réessayer',
        ),
      _ => (
          OuroColors.systemGray,
          actif ? 'Activé, en attente' : 'Éteint — joindre au-delà du mesh',
        ),
    };

    return OuroListRow(
      icon: Icons.hub_rounded,
      iconColor: couleur,
      title: 'Tor',
      subtitle: sousTitre,
      onTap: () => context.push('/settings/tor'),
    );
  }
}
