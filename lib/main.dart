// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est la toute PREMIÈRE porte d'entrée de l'application Droplet — un peu
// comme la page de garde d'un livre. Quand tu appuies sur l'icône de l'app
// sur ton téléphone, c'est CE fichier qui démarre en premier.
//
// Il fait 3 grandes choses :
//   1. Il allume les petits moteurs dont l'app a besoin AVANT de s'afficher
//      (la mémoire de l'app, les notifications, le service qui tourne même
//      quand l'app est fermée).
//   2. Il dessine les fenêtres qui doivent apparaître PAR-DESSUS tout le
//      reste, peu importe l'écran où tu es : l'appel qui sonne, l'invitation
//      à un appel de groupe.
//   3. Il tient la « carte au trésor » de toutes les pages de l'app (le
//      routeur) : quand tu tapes sur un bouton qui doit t'emmener sur une
//      nouvelle page, c'est cette carte qui dit où aller.
// ============================================================================

import 'dart:async';
import 'package:flutter/cupertino.dart' show CupertinoPage;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/models/mesh_message.dart';
import 'core/models/voice_note_meta.dart';
import 'core/providers/appearance_provider.dart';
import 'core/providers/mesh_provider.dart';
import 'core/services/mesh_foreground_service.dart';
import 'core/services/crash_journal.dart';
import 'core/services/device_profile.dart';
import 'features/chat/animated_sticker.dart';
import 'core/services/notification_service.dart';
import 'core/services/share_intent_service.dart';
import 'core/services/avatar_service.dart';
import 'core/services/premium_service.dart';
import 'core/services/reponses_differees.dart';
import 'features/premium/premium_screen.dart';
import 'core/services/storage_service.dart';
import 'design_system/ouro_colors.dart';
import 'design_system/ouro_liquid.dart';
import 'design_system/mode_transition.dart';
import 'features/nexus_connection/nexus_shader.dart';
import 'features/nexus_connection/nexus_overlay.dart';
import 'features/nexus_connection/nexus_event.dart';
import 'design_system/ouro_scroll_behavior.dart';
import 'design_system/ouro_theme.dart';
import 'design_system/liquid_bridge.dart';
import 'package:liquid_glass_ui_design/liquid_glass_ui.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/splash_screen.dart';
import 'features/home/home_shell.dart';
import 'features/chats/chats_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/chat/location_message.dart';
import 'features/chat/chat_info_screen.dart';
import 'features/chat/security_code_screen.dart';
import 'features/chat/new_message_screen.dart';
import 'features/call/call_screen.dart';
import 'features/call/group_call_screen.dart';
import 'features/safety/emergency_mode_screen.dart';
import 'features/group/group_create_screen.dart';
import 'features/group/group_info_screen.dart';
import 'features/settings/backup_export_screen.dart';
import 'features/settings/app_icon_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/contribution/contribution_screen.dart';
import 'features/safety/safety_screen.dart';
import 'features/status/status_viewer_screen.dart';
import 'features/maps/map_screen.dart';
import 'features/maps/offline_maps_screen.dart';
import 'features/mesh/mesh_network_screen.dart';
import 'features/share/share_target_screen.dart';
import 'shared/widgets/droplet_logo.dart';
import 'shared/widgets/peer_avatar.dart';
import 'shared/widgets/toast_overlay.dart';

// `main()` est la fonction magique que Dart (le langage utilisé par Flutter)
// lance TOUJOURS en premier, quel que soit le projet. C'est le tout début de
// tout. `async`/`await` veut dire « attends que ce soit fini avant de
// continuer » — comme attendre que le four sonne avant de sortir le gâteau.
Future<void> main() async {
  // Prépare le moteur Flutter (celui qui dessine les images à l'écran)
  // avant qu'on lui demande quoi que ce soit — obligatoire en premier.
  WidgetsFlutterBinding.ensureInitialized();
  // Branche la boîte noire AVANT tout le reste : à partir d'ici, plus
  // aucune erreur non attrapée ne disparaît sans laisser de trace.
  await CrashJournal.install();
  // ⚠️ LA RÉSERVE D'IMAGES SUIT L'APPAREIL, elle n'est plus fixe.
  //
  // Un plafond unique de 48 Mo convenait au Pixel de développement. Sur
  // un téléphone de 2 Go — celui de l'utilisateur type de Droplet, qui
  // n'a pas de réseau mais pas non plus de matériel neuf — cette seule
  // réserve suffit à faire tuer l'application par le système.
  //
  // On demande donc au système ce dont il dispose AVANT de décider, et
  // tous les effets coûteux de l'app se règlent sur cette réponse (voir
  // `DeviceProfile`).
  await DeviceProfile.detecter();
  PaintingBinding.instance.imageCache
    ..maximumSizeBytes = DeviceProfile.budgetImages
    ..maximumSize = DeviceProfile.nombreImages;
  // Ouvre la mémoire permanente de l'app (là où sont rangés les messages,
  // les contacts, etc.) — comme ouvrir le classeur avant de pouvoir y lire
  // ou écrire quelque chose.
  await StorageService.init();
  // Ouvre le dossier de la photo de profil. Rapide (une création de
  // dossier), et il faut le faire AVANT le premier écran : sans lui,
  // `AvatarService.chemin` renvoie `null` et le premier affichage
  // retomberait sur l'initiale alors qu'une photo existe.
  await AvatarService.initialiser();
  // Relit la licence enregistrée et REVÉRIFIE sa signature. Il faut le
  // faire avant le premier écran : sans cela, une personne qui a payé
  // verrait ses fonds et ses icônes verrouillés pendant une seconde à
  // chaque lancement — ce qui se lit comme « on m'a repris ce que
  // j'avais acheté ».
  await PremiumService.charger(StorageService.currentUser?.id ?? '');
  // Prépare (sans encore l'allumer) le service qui peut garder le mesh
  // actif même quand on a fermé l'app.
  MeshForegroundService.init();
  // Prépare le système qui affichera les vraies notifications Android
  // (message reçu, appel manqué, etc.).
  await NotificationService.init();
  // Précompile le shader liquide en tâche de fond. Sans ce préchargement,
  // la toute première transition se jouerait sans effet (le temps que le
  // GPU compile le programme), ce qui donnerait l'impression que l'effet
  // « ne marche qu'une fois sur deux ». On n'attend PAS le résultat : si
  // la compilation échoue ou traîne, l'app démarre normalement, sans
  // l'effet.
  // ⚠️ On ne compile le shader QUE s'il va servir. Sur un appareil
  // modeste, le verre liquide est désactivé (voir `ouroGlassDegraded`) :
  // compiler quand même un programme graphique qu'on n'affichera jamais,
  // c'est payer le coût sans le bénéfice.
  if (!DeviceProfile.sansShader) unawaited(LiquidShader.load());
  // Précompile le shader Nexus (connexion entre appareils). Même logique
  // que le shader liquide : on lance la compilation en tâche de fond pour
  // que l'effet soit prêt quand l'utilisateur en aura besoin.
  if (!DeviceProfile.sansShader) unawaited(NexusShaderLoader.load());
  // Recense les stickers animés (.tgs / .json Lottie) déposés dans
  // `assets/stickers/`. Rapide — c'est une lecture d'index, pas de
  // fichiers — et sans conséquence si le dossier est vide, ce qui est
  // le cas par défaut.
  await AnimatedStickerCatalog.charger();
  // Et on allume vraiment l'application ! `ProviderScope` est la boîte
  // magique de Riverpod qui permet à toutes les pages de l'app de partager
  // des informations (qui je suis, mes messages, mes contacts...) sans
  // avoir à se les passer à la main.
  runApp(const ProviderScope(child: DropletApp()));
}

/// Le widget racine de toute l'application — la « coquille » qui contient
/// absolument tout le reste. Un widget, en Flutter, c'est simplement un
/// morceau d'interface (un bouton, un texte, une page entière...).
class DropletApp extends ConsumerWidget {
  const DropletApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Le réglage d'apparence choisi par l'utilisateur (Automatique / Clair
    // / Sombre — sombre par défaut, voir `appearance_provider.dart`).
    final appearance = ref.watch(appearanceProvider);

    // En mode « Automatique », on suit le téléphone ; sinon le choix
    // explicite de l'utilisateur l'emporte.
    final brightness =
        appearance.resolve(MediaQuery.platformBrightnessOf(context));

    // ⚠️ ORDRE IMPORTANT : `OuroColors` est consulté de partout dans l'app
    // sous forme d'accesseurs statiques (`OuroColors.label`, etc.) plutôt
    // qu'à travers le `Theme` de Flutter. Il faut donc lui dire dans quel
    // mode on se trouve AVANT de construire le moindre widget qui
    // l'interroge — d'où cet appel juste ici, à la racine, avant le
    // `return`.
    OuroColors.setBrightness(brightness);
    // Idem pour les barres système d'Android (heure, batterie, boutons de
    // navigation) : elles doivent s'inverser avec le mode.
    OuroTheme.applySystemOverlay(brightness);

    // `MaterialApp.router` est le widget qui dit à Flutter « voici une
    // application complète, avec un thème (des couleurs) et un système de
    // pages (le routeur, défini plus bas dans ce fichier) ».
    // `LiquidThemeProvider` enveloppe le MaterialApp pour fournir le thème
    // Liquid Glass à TOUS les composants liquid_glass_ui_design de l'app.
    return LiquidThemeProvider(
      theme: liquidTheme,
      child: MaterialApp.router(
        title: 'Droplet',
        debugShowCheckedModeBanner: false,
        theme: OuroTheme.of(brightness),
        scrollBehavior: const OuroScrollBehavior(),
        routerConfig: _router,
        builder: (context, child) => ToastOverlay(
          child: MeshBootstrap(
            // La couche Nexus s'insère ici, avec les autres écrans plein
            // écran de l'app (appel entrant, appel de groupe). Elle ne
            // passe PAS par `Overlay` : il n'y en a aucun au-dessus de ce
            // point de l'arbre — voir `NexusStage` pour l'histoire
            // complète de ce bug.
            child: NexusHost(
              child: NotificationBridge(
                child: IncomingCallOverlay(
                  child: GroupIncomingCallOverlay(
                    child: RepaintBoundary(
                      // ⚠️ CE BOUNDARY EST LA SOURCE DE L'INSTANTANÉ DE
                      // TRANSITION DE THÈME. `ModeTransitionOverlay.capture()`
                      // le lit pour prendre une photo de l'écran AVANT que le
                      // thème ne change, comme Telegram. Ne pas le retirer ni
                      // le remplacer par un enfant simple.
                      key: ModeTransitionOverlay.repaintBoundaryKey,
                      child: KeyedSubtree(
                        key: ValueKey(brightness),
                        child: child ?? const SizedBox(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Overlay plein écran d'appel entrant (accepte/refuse).
///
/// Un « overlay », c'est une fenêtre qui s'affiche PAR-DESSUS l'écran
/// actuel, comme un post-it collé sur une page de cahier. Celui-ci
/// surveille en permanence « est-ce que quelqu'un est en train de
/// m'appeler ? » et, si oui, recouvre tout l'écran avec la fenêtre
/// « Appel entrant » — peu importe la page où on se trouvait.
class IncomingCallOverlay extends ConsumerWidget {
  const IncomingCallOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // On regarde l'état actuel des appels (comme regarder un tableau
    // d'affichage qui se met à jour tout seul).
    final call = ref.watch(callProvider);
    // On n'affiche la fenêtre d'appel entrant QUE si toutes ces conditions
    // sont vraies en même temps : un appel est actif, il vient de
    // quelqu'un d'autre (pas moi qui appelle), il est encore en train de
    // sonner (pas encore décroché), et on sait qui appelle.
    final showIncoming =
        call.isCallActive &&
        call.direction == CallDirection.incoming &&
        call.connectionState == CallConnectionState.connecting &&
        call.peerId != null;

    // `Stack` empile des widgets les uns sur les autres, comme des
    // transparents posés sur un rétroprojecteur. Ici : l'écran normal en
    // dessous, et par-dessus (seulement si `showIncoming` est vrai) la
    // fenêtre d'appel qui recouvre tout.
    return Stack(
      children: [
        child,
        if (showIncoming)
          Positioned.fill(
            child: _IncomingCallView(
              peerId: call.peerId!,
              onAccept: () {
                ref.read(callProvider.notifier).answerCall();
                context.go('/call/${call.peerId}');
              },
              onReject: () => ref.read(callProvider.notifier).hangUp(),
            ),
          ),
      ],
    );
  }
}

/// Le dessin de la fenêtre « Appel entrant » elle-même : le logo qui
/// respire, le nom de la personne, et les deux gros boutons ronds
/// (raccrocher en rouge / décrocher en vert).
class _IncomingCallView extends ConsumerWidget {
  const _IncomingCallView({
    required this.peerId,
    required this.onAccept,
    required this.onReject,
  });

  final String peerId;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // On demande « comment s'appelle cette personne ? » à partir de son
    // identifiant technique (une longue suite de lettres/chiffres que
    // l'utilisateur ne voit jamais).
    final pseudo = ref.watch(peerPseudoProvider(peerId));
    return Scaffold(
      // Noir fixe, même quand l'app est en mode clair : voir
      // `OuroColors.callBackground` pour le pourquoi.
      backgroundColor: OuroColors.callBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Un joli dégradé de couleur en fond, comme un ciel qui s'assombrit.
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.3),
                radius: 1.2,
                colors: [OuroColors.callGlow, OuroColors.callBackground],
              ),
            ),
          ),
          // Des petits ronds qui s'agrandissent doucement, comme des ronds
          // dans l'eau — pour montrer que ça sonne « en direct ».
          const Positioned.fill(
            child: DropletRipples(active: true),
          ),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),
                Text('Appel entrant',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: OuroColors.callSecondaryLabel,
                    )),
                const Spacer(),
                const DropletLogo(radius: 62, glow: true),
                const SizedBox(height: 24),
                PeerAvatar(pseudo: pseudo, radius: 48, online: true),
                const SizedBox(height: 16),
                Text(pseudo,
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: OuroColors.callLabel,
                    )),
                const SizedBox(height: 6),
                Text('Appel vocal mesh',
                    style: TextStyle(fontSize: 14, color: OuroColors.callSecondaryLabel)),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _IncomingButton(
                      icon: Icons.call_end_rounded,
                      color: OuroColors.errorRed,
                      label: 'Refuser',
                      onTap: onReject,
                    ),
                    _IncomingButton(
                      icon: Icons.call_rounded,
                      color: OuroColors.successGreen,
                      label: 'Accepter',
                      onTap: onAccept,
                    ),
                  ],
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Overlay plein écran d'invitation à un appel de groupe (accepte/refuse).
///
/// Même idée que [IncomingCallOverlay] juste au-dessus, mais pour les
/// appels avec PLUSIEURS personnes en même temps au lieu d'une seule.
class GroupIncomingCallOverlay extends ConsumerWidget {
  const GroupIncomingCallOverlay({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Déclenche une reconstruction quand une invitation arrive : l'état
    // observable (GroupCallState) ne porte pas l'invitation elle-même
    // (stockée sur le notifier), mais est réémis à chaque changement.
    ref.watch(groupCallProvider);
    final notifier = ref.read(groupCallProvider.notifier);
    final invite = notifier.pendingInvite;

    return Stack(
      children: [
        child,
        if (invite != null)
          Positioned.fill(
            child: _GroupIncomingCallView(
              fromPeerId: invite.fromPeerId,
              participantCount: invite.participants.length,
              onAccept: () {
                notifier.acceptInvite(pseudoFor: (id) => ref.read(peerPseudoProvider(id)));
                context.go('/group-call');
              },
              onReject: () => notifier.declineInvite(),
            ),
          ),
      ],
    );
  }
}

/// Le dessin de la fenêtre « Appel de groupe entrant » (même esprit que
/// [_IncomingCallView], avec le nombre de participants en plus).
class _GroupIncomingCallView extends ConsumerWidget {
  const _GroupIncomingCallView({
    required this.fromPeerId,
    required this.participantCount,
    required this.onAccept,
    required this.onReject,
  });

  final String fromPeerId;
  final int participantCount;
  final VoidCallback onAccept;
  final VoidCallback onReject;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pseudo = ref.watch(peerPseudoProvider(fromPeerId));
    return Scaffold(
      backgroundColor: OuroColors.callBackground,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment(0, -0.3),
                radius: 1.2,
                colors: [OuroColors.callGlow, OuroColors.callBackground],
              ),
            ),
          ),
          const Positioned.fill(child: DropletRipples(active: true)),
          SafeArea(
            child: Column(
              children: [
                const SizedBox(height: 40),
                Text('Appel de groupe entrant',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: OuroColors.callSecondaryLabel)),
                const Spacer(),
                const DropletLogo(radius: 62, glow: true),
                const SizedBox(height: 24),
                PeerAvatar(pseudo: pseudo, radius: 48, online: true),
                const SizedBox(height: 16),
                Text('$pseudo t\'invite',
                    style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800, color: OuroColors.callLabel)),
                const SizedBox(height: 6),
                Text('Appel de groupe · $participantCount autre${participantCount > 1 ? 's' : ''} participant${participantCount > 1 ? 's' : ''}',
                    style: TextStyle(fontSize: 14, color: OuroColors.callSecondaryLabel)),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _IncomingButton(icon: Icons.call_end_rounded, color: OuroColors.errorRed, label: 'Refuser', onTap: onReject),
                    _IncomingButton(icon: Icons.call_rounded, color: OuroColors.successGreen, label: 'Accepter', onTap: onAccept),
                  ],
                ),
                const SizedBox(height: 48),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Un des deux gros boutons ronds (raccrocher/décrocher) : une icône dans
/// un cercle coloré avec une ombre, et un petit mot en dessous.
class _IncomingButton extends StatelessWidget {
  const _IncomingButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // `GestureDetector` transforme n'importe quel dessin en bouton
        // cliquable : dès qu'on tapote dedans, `onTap` se déclenche.
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(label,
            style: TextStyle(fontSize: 13, color: OuroColors.callSecondaryLabel)),
      ],
    );
  }
}

// ============================================================================
// LE ROUTEUR — LA CARTE AU TRÉSOR DE TOUTES LES PAGES
// ----------------------------------------------------------------------------
// `GoRouter` est un peu comme le plan d'un centre commercial : chaque
// « chemin » (par exemple `/chat/123`) correspond à une pièce précise
// (ici, la conversation avec la personne n°123). Quand le code fait
// `context.go('/chat/123')` n'importe où dans l'app, c'est CETTE liste qui
// décide quelle page dessiner.
// ============================================================================
final _router = GoRouter(
  // La toute première page qu'on voit en ouvrant l'app.
  initialLocation: '/',
  // `redirect` s'exécute AVANT chaque changement de page, et peut décider
  // de rediriger ailleurs — un peu comme un videur à l'entrée d'une boîte
  // qui vérifie si tu as le droit d'entrer, et t'envoie ailleurs sinon.
  redirect: (context, state) {
    // La racine '/' a maintenant sa propre route (SplashScreen) : elle gère
    // elle-même sa redirection après sa courte chorégraphie d'entrée, donc
    // on la laisse passer ici plutôt que de la court-circuiter comme avant.
    if (state.matchedLocation == '/') return null;
    // Est-ce qu'on a déjà créé une identité sur cet appareil ?
    final loggedIn = StorageService.hasIdentity;
    final onBoarding = state.matchedLocation == '/onboarding';
    // Pas encore d'identité → direction la page de création de compte.
    if (!loggedIn) return onBoarding ? null : '/onboarding';
    // Déjà une identité, mais on est encore sur la page de création →
    // direction la liste des discussions.
    if (onBoarding) return '/chats';
    return null;
  },
  // Filet de sécurité : toute localisation inconnue (deep link périmé, état
  // de navigation restauré par l'OS après réinstallation/mise à jour, etc.)
  // ne doit jamais faire planter l'app — on revient à l'écran principal
  // plutôt que de laisser GoRouter lever une exception non rattrapée.
  errorBuilder: (context, state) =>
      StorageService.hasIdentity ? const ChatsScreen() : const OnboardingScreen(),
  // La liste de toutes les pages de l'app, chacune associée à son
  // « adresse » (le chemin) et à la manière dont elle apparaît à l'écran
  // (la transition — fondu, glissement, etc., définies plus bas).
  routes: [
    GoRoute(
      path: '/',
      pageBuilder: (context, state) => _fadePage(const SplashScreen()),
    ),
    GoRoute(
      path: '/onboarding',
      // Premier écran après le démarrage : c'est LE moment où la
      // transition liquide se justifie (voir `_liquidPage`).
      pageBuilder: (context, state) => _liquidPage(const OnboardingScreen()),
    ),
    GoRoute(
      path: '/chats',
      pageBuilder: (context, state) => _fadePage(const HomeShell()),
    ),
    GoRoute(
      // Le `:peerId` est une case vide dans l'adresse, remplie avec le
      // vrai identifiant de la personne au moment d'y aller — comme une
      // adresse postale avec un numéro de maison qui change.
      path: '/chat/:peerId',
      pageBuilder: (context, state) => _pushPage(
        ChatScreen(peerId: state.pathParameters['peerId'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/chat/:peerId/info',
      pageBuilder: (context, state) => _pushPage(
        ChatInfoScreen(peerId: state.pathParameters['peerId'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/chat/:peerId/security',
      pageBuilder: (context, state) => _pushPage(
        SecurityCodeScreen(peerId: state.pathParameters['peerId'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/group/create',
      pageBuilder: (context, state) => _modalPage(const GroupCreateScreen()),
    ),
    GoRoute(
      path: '/backup/export',
      pageBuilder: (context, state) => _pushPage(const BackupExportScreen()),
    ),
    GoRoute(
      path: '/contribution',
      pageBuilder: (context, state) => _pushPage(const ContributionScreen()),
    ),
    GoRoute(
      path: '/map',
      pageBuilder: (context, state) => _pushPage(const MapScreen()),
    ),
    GoRoute(
      path: '/premium',
      builder: (context, state) => const PremiumScreen(),
    ),
    GoRoute(
      path: '/settings/icon',
      pageBuilder: (context, state) => _pushPage(const AppIconScreen()),
    ),
    GoRoute(
      path: '/maps/offline',
      pageBuilder: (context, state) => _pushPage(const OfflineMapsScreen()),
    ),
    GoRoute(
      path: '/mesh-network',
      pageBuilder: (context, state) => _pushPage(const MeshNetworkScreen()),
    ),
    GoRoute(
      path: '/share-target',
      pageBuilder: (context, state) => _modalPage(const ShareTargetScreen()),
    ),
    GoRoute(
      path: '/settings',
      pageBuilder: (context, state) => _pushPage(const SettingsScreen()),
    ),
    GoRoute(
      path: '/safety',
      pageBuilder: (context, state) => _pushPage(const SafetyScreen()),
    ),
    GoRoute(
      path: '/status/:authorId',
      pageBuilder: (context, state) => _fadePage(
        StatusViewerScreen(authorId: state.pathParameters['authorId'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/group/:groupId',
      pageBuilder: (context, state) => _pushPage(
        ChatScreen(groupId: state.pathParameters['groupId'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/group/:groupId/info',
      pageBuilder: (context, state) => _pushPage(
        GroupInfoScreen(groupId: state.pathParameters['groupId'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/call/:peerId',
      pageBuilder: (context, state) => _scaleFadePage(
        CallScreen(peerId: state.pathParameters['peerId'] ?? ''),
      ),
    ),
    GoRoute(
      path: '/group-call',
      pageBuilder: (context, state) => _scaleFadePage(const GroupCallScreen()),
    ),
    GoRoute(
      path: '/new-message',
      pageBuilder: (context, state) => _modalPage(const NewMessageScreen()),
    ),
    GoRoute(
      path: '/emergency',
      pageBuilder: (context, state) => _modalPage(const EmergencyModeScreen()),
    ),
    GoRoute(
      path: '/:unknown',
      redirect: (context, state) => '/chats',
    ),
  ],
);

/// ENTRER DANS QUELQUE CHOSE — la navigation hiérarchique d'iOS.
///
/// ── Pourquoi ce n'est pas un détail ───────────────────────────────────
///
/// Sur iOS, ouvrir une conversation, un réglage ou une fiche fait
/// GLISSER LA PAGE DEPUIS LA DROITE, pendant que la précédente recule
/// d'un tiers vers la gauche en s'assombrissant. Ce décalage entre les
/// deux plans dit, sans un mot, « tu es entré d'un cran ». Et surtout :
/// on revient en TIRANT DEPUIS LE BORD GAUCHE, la page suivant le doigt,
/// annulable en cours de route.
///
/// Toutes ces pages arrivaient jusqu'ici par un fondu avec un léger
/// glissement vers le haut — la même transition pour tout, sans notion
/// de profondeur, et sans le moindre geste de retour. C'est le genre de
/// détail qu'on ne sait pas nommer mais qui fait dire « ça ne fait pas
/// natif » dès la première navigation.
///
/// `CupertinoPage` apporte les deux d'un coup : le mouvement exact et le
/// geste de retour interactif.
CupertinoPage<void> _pushPage(Widget child) => CupertinoPage<void>(child: child);

/// PRÉSENTER PAR-DESSUS — la feuille modale d'iOS.
///
/// À réserver aux pages qui ne sont pas un cran plus profond mais une
/// PARENTHÈSE : composer, choisir un destinataire, déclencher une
/// alerte. Elles montent depuis le bas et se referment par un bouton,
/// pas par le geste de retour — précisément parce qu'on ne veut pas
/// qu'on en sorte par mégarde.
CupertinoPage<void> _modalPage(Widget child) =>
    CupertinoPage<void>(child: child, fullscreenDialog: true);

/// Transition LIQUIDE — une onde traverse l'écran en le déformant pendant
/// que la page apparaît (voir `ouro_liquid.dart` et `shaders/liquid.frag`).
///
/// Volontairement réservée à l'ENTRÉE DANS L'APP, un moment unique et
/// marquant. L'appliquer à chaque navigation la rendrait fatigante en
/// quelques minutes : une déformation d'écran attire fortement l'œil, et
/// ce qui impressionne au premier passage agace au vingtième.
CustomTransitionPage<void> _liquidPage(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: const Duration(milliseconds: 700),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return LiquidPageTransition(animation: animation, child: child);
    },
  );
}

/// Transition fade simple (chats ↔ onboarding) : la nouvelle page apparaît
/// tout doucement, comme une lumière qu'on allume petit à petit.
CustomTransitionPage<void> _fadePage(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 220),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      return FadeTransition(
        opacity: CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        child: child,
      );
    },
  );
}


/// Transition scale + fade (écran d'appel, type iOS) : la page grandit
/// légèrement en même temps qu'elle apparaît, comme un zoom doux.
CustomTransitionPage<void> _scaleFadePage(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.9, end: 1.0).animate(curved),
          child: child,
        ),
      );
    },
  );
}

/// Démarre le mesh (le réseau qui connecte les téléphones entre eux) une
/// seule fois au lancement, mais SEULEMENT si l'utilisateur a déjà une
/// identité (donc pas pendant la toute première création de compte).
///
/// Pense à ce widget comme au bouton « marche » caché derrière l'écran :
/// personne ne le voit, mais dès que l'app s'allume, il appuie une fois
/// sur ce bouton pour que le téléphone commence à chercher d'autres
/// appareils Droplet autour de lui.
class MeshBootstrap extends ConsumerStatefulWidget {
  const MeshBootstrap({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<MeshBootstrap> createState() => _MeshBootstrapState();
}

class _MeshBootstrapState extends ConsumerState<MeshBootstrap> {
  @override
  void initState() {
    // `initState` est appelé UNE SEULE FOIS, dès que ce widget apparaît
    // pour la première fois — l'endroit parfait pour démarrer quelque
    // chose qui ne doit se produire qu'une fois.
    super.initState();
    _start();
  }

  Future<void> _start() async {
    final user = StorageService.currentUser;
    // Personne n'est encore connecté (pas de compte créé) → on ne fait rien.
    if (user == null) return;
    final repo = ref.read(meshRepositoryProvider);
    // Allume vraiment le réseau mesh, avec mon identité.
    await repo.init(user.id, user.pseudo);
    // Branche aussi les systèmes d'appel (1 contre 1, puis en groupe) sur
    // ce même réseau, une fois qu'il est prêt.
    ref.read(callProvider.notifier).init(repo.transport);
    ref.read(groupCallProvider.notifier).init(repo.transport, repo.myId);
    // Active le service premier plan pour garder le mesh en vie en
    // arrière-plan (sinon Android tue le processus après quelques minutes).
    MeshForegroundService.start().catchError((e) =>
        debugPrint('[MeshBootstrap] foreground service: $e'));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Relie les flux mesh existants (nouveaux messages, statuts, check-ins
/// d'urgence, appels) aux notifications système Android réelles, et suit le
/// cycle de vie de l'app pour ne jamais notifier ce que l'utilisateur
/// regarde déjà à l'écran. Additif : ne modifie aucune logique métier, se
/// contente d'observer les streams déjà exposés par [MeshRepository] et
/// [CallNotifier].
///
/// En mots simples : c'est le petit espion discret qui regarde tout ce qui
/// se passe dans le mesh (« un message est arrivé ! », « quelqu'un
/// t'appelle ! ») et qui, à chaque fois, décide s'il doit faire vibrer le
/// téléphone et afficher une notification — ou rester silencieux parce que
/// tu es déjà en train de regarder cette conversation.
class NotificationBridge extends ConsumerStatefulWidget {
  const NotificationBridge({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<NotificationBridge> createState() => _NotificationBridgeState();
}

class _NotificationBridgeState extends ConsumerState<NotificationBridge>
    with WidgetsBindingObserver {
  StreamSubscription<MeshMessage>? _msgSub;
  StreamSubscription<MeshStatusRecord>? _statusSub;
  StreamSubscription<SafetyCheckinRecord>? _checkinSub;
  ProviderSubscription<CallState>? _callSub;
  StreamSubscription<dynamic>? _nexusPeerSub;
  StreamSubscription<NexusEvent>? _nexusEventSub;
  Timer? _retryTimer;
  // Se souvient si l'appel entrant en cours a fini par être décroché, pour
  // savoir s'il faut afficher « appel manqué » quand il se termine.
  bool _incomingWasConnected = false;
  // ⚠️ Plus de drapeau « une animation Nexus est en cours » ici : c'est
  // `NexusStage` qui détient cet état, au même endroit que la couche
  // affichée. Deux copies d'une même vérité finissent toujours par
  // diverger — ici, elles divergeaient dès que l'affichage échouait.
  Timer? _nexusSafetyTimer;

  /// Envoie une réponse écrite depuis une notification.
  ///
  /// ⚠️ ELLE PASSE PAR LE MÊME CHEMIN QU'UN MESSAGE ORDINAIRE.
  ///
  /// La tentation serait d'écrire directement dans la base « puisque
  /// c'est plus simple ». Ce serait contourner le chiffrement, la file
  /// d'attente, les accusés de réception et la signature du trajet — et
  /// produire un message qui n'a l'air normal que dans la liste.
  ///
  /// Sans pair à portée, `sendMessage` met en attente de lui-même : la
  /// réponse repartira à la prochaine rencontre, exactement comme si
  /// elle avait été tapée dans l'application.
  Future<void> _repondreDepuisNotification(String route, String texte) async {
    final id = route.split('/').last;
    if (id.isEmpty) return;
    final moi = StorageService.currentUser?.pseudo ?? 'Moi';
    final notifier = ref.read(meshMessagesProvider.notifier);

    if (route.startsWith('/group/')) {
      await notifier.sendGroupMessage(moi, texte, groupId: id);
    } else {
      await notifier.sendMessage(moi, texte, targetId: id);
    }
  }

  @override
  void initState() {
    super.initState();
    // S'abonne aux changements d'état de l'app (au premier plan / en
    // arrière-plan) pour toute la durée de vie de ce widget.
    WidgetsBinding.instance.addObserver(this);
    NotificationService.isAppForeground =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed ||
            WidgetsBinding.instance.lifecycleState == null;
    // Quand l'utilisateur tapote sur une notification, on lui dit
    // comment naviguer vers la bonne page.
    NotificationService.bindNavigation((path) {
      if (!mounted) return;
      _router.go(path);
    });

    // ── RÉPONDRE ET DÉCROCHER SANS OUVRIR L'APPLICATION ────────────
    //
    // ⚠️ C'EST ICI, ET NULLE PART AILLEURS, QUE LE MAILLAGE EST
    // ACCESSIBLE.
    //
    // `NotificationService` ne connaît ni les providers ni le réseau, et
    // ne doit pas les connaître : c'est un afficheur de bulles. Quand
    // Android nous rend une réponse tapée, il la remet donc ici, au seul
    // endroit qui sait quoi en faire.
    NotificationService.bindActions(
      onRepondre: (route, texte) => _repondreDepuisNotification(route, texte),
      onLu: (route) {
        // Marquer lu envoie AUSSI les accusés de lecture, comme si on
        // avait ouvert la conversation. C'est la vérité : la personne a
        // lu le message dans la notification.
        final id = route.split('/').last;
        unawaited(
          ref.read(meshMessagesProvider.notifier).sendReadReceipts(id),
        );
      },
      onAppel: (peerId, accepter) {
        if (accepter) {
          _router.go('/call/\$peerId');
        } else {
          ref.read(callProvider.notifier).hangUp();
        }
      },
    );

    // Les réponses écrites pendant que l'application était fermée. Le
    // rappel est branché AVANT le premier rejeu : sans lui,
    // `ReponsesDifferees.rejouer` ne touche à rien et les garde pour
    // plus tard, ce qui est le bon défaut mais pas le résultat voulu.
    ReponsesDifferees.onRejouer = (r) => _repondreDepuisNotification(
          r.route,
          r.texte,
        );
    unawaited(ReponsesDifferees.rejouer());
    // Écoute si une autre app essaie de « partager » du contenu vers
    // Droplet (texte, photo...) et prépare l'écran de choix du contact.
    unawaited(ShareIntentService.init(onShared: () => _router.go('/share-target')));
    WidgetsBinding.instance.addPostFrameCallback((_) => _subscribe());
  }

  void _subscribe() {
    if (!mounted) return;
    // Comme MeshBootstrap._start(), on ne touche jamais au provider tant
    // qu'aucune identité n'existe : le lire construirait MeshRepository (et
    // son transport BLE/plateforme) prématurément — y compris en test, où
    // aucun canal de plateforme n'est disponible. Au premier lancement (pas
    // encore d'identité, onboarding en cours), on réessaie périodiquement :
    // ce widget racine n'est jamais reconstruit après la création du compte.
    if (StorageService.currentUser == null) {
      _retryTimer ??= Timer.periodic(const Duration(seconds: 2), (_) => _subscribe());
      return;
    }
    _retryTimer?.cancel();
    _retryTimer = null;
    final repo = ref.read(meshRepositoryProvider);
    // « Un nouveau message est arrivé ! » → on prépare une jolie petite
    // notification (avec un aperçu adapté : texte, 🎤 message vocal,
    // 📷 photo, ou 📎 fichier).
    _msgSub = repo.newMessageEvents.listen((msg) {
      if (msg.senderId == repo.myId) return;
      final conv = msg.groupId ?? msg.senderId ?? 'broadcast';
      final preview = msg.audioUrl != null
          ? '🎤 Message vocal'
          : msg.imageUrl != null
              ? '📷 Photo'
              : msg.type == 'file'
                  // Un vocal reçu doit s'annoncer « 🎤 Message vocal ·
                  // 0:12 » dans la notification, jamais avec son nom de
                  // fichier brut (qui contient la forme d'onde encodée).
                  ? VoiceNoteMeta.describeAttachment(msg.fileName)
                  // Une position partagée s'annonce « 📍 Position
                  // partagée », jamais avec ses coordonnées brutes.
                  : LocationMessage.describe(msg.content);
      unawaited(NotificationService.showNewMessage(
        conversationId: conv,
        pseudo: msg.authorPseudo,
        preview: preview,
        routePath: msg.groupId != null ? '/group/$conv' : '/chat/$conv',
      ));
    });
    // « Quelqu'un a publié un nouveau statut ! » (comme les stories).
    _statusSub = repo.statusEvents.listen((status) {
      if (status.authorId == repo.myId) return;
      unawaited(NotificationService.showStatusPublished(
        pseudo: status.authorPseudo,
        authorId: status.authorId,
      ));
    });
    // « Quelqu'un a signalé qu'il est en sécurité ! » (mode urgence).
    _checkinSub = repo.safetyCheckinEvents.listen((checkin) {
      if (checkin.peerId == repo.myId) return;
      unawaited(NotificationService.showEmergency(pseudo: checkin.pseudo));
    });
    // ── NEXUS : animation de connexion ─────────────────────────────────
    //
    // Quand un NOUveau pair se connecte pour la première fois dans cette
    // session, on lance l'animation Nexus sur les DEUX appareils.
    // L'émetteur envoie un NexusEvent (seed + couleur) au destinataire,
    // et les deux jouent la même animation synchronisée.
    _nexusPeerSub = repo.firstPeerConnection.listen((peer) {
      if (!mounted) return;
      _startNexusSafetyTimer();

      final event = NexusEvent(
        seed: NexusEvent.generateSeed(),
        timestamp: DateTime.now().toUtc().toIso8601String(),
        intensity: 1.0,
        colorSignature: NexusEvent.deriveColorSignature(repo.myId, peer.peerId),
      );

      // Envoyer l'événement au pair pour synchroniser les deux animations.
      unawaited(repo.sendNexusEvent(peer.peerId, event));

      // `play` ignore la demande si une séquence est déjà à l'écran :
      // c'est la scène qui tient cet état, plus un drapeau local qu'il
      // fallait penser à remettre à zéro dans chaque chemin de sortie.
      NexusStage.play(NexusRequest(
        seed: event.seed,
        colorSignature: event.colorSignature,
        peerName: peer.pseudo,
      ));
    });
    // Quand on REÇOIT un NexusEvent d'un pair (l'autre appareil a détecté
    // la connexion en premier), on lance la même animation avec sa seed.
    _nexusEventSub = repo.nexusEvents.listen((event) {
      if (!mounted) return;
      _startNexusSafetyTimer();
      NexusStage.play(NexusRequest(
        seed: event.seed,
        colorSignature: event.colorSignature,
      ));
    });
    // Surveille l'état des appels pour détecter deux moments précis :
    // « on m'appelle et l'app est en arrière-plan » (→ notif d'appel
    // entrant) et « on m'a appelé, je n'ai pas répondu, et ça s'est arrêté »
    // (→ notif d'appel manqué).
    _callSub = ref.listenManual<CallState>(callProvider, (previous, next) {
      final wasIncomingRinging = previous != null &&
          previous.isCallActive &&
          previous.direction == CallDirection.incoming &&
          previous.connectionState == CallConnectionState.connecting;
      if (wasIncomingRinging && next.connectionState == CallConnectionState.connected) {
        _incomingWasConnected = true;
      }
      if (wasIncomingRinging && !next.isCallActive && !_incomingWasConnected) {
        if (!NotificationService.isAppForeground) {
          final peerId = previous.peerId;
          if (peerId != null) {
            unawaited(NotificationService.showMissedCall(
              peerId: peerId,
              pseudo: ref.read(peerPseudoProvider(peerId)),
            ));
          }
        }
        _incomingWasConnected = false;
      }
      if (next.isCallActive && next.direction == CallDirection.incoming &&
          next.connectionState == CallConnectionState.connecting &&
          (previous == null || !previous.isCallActive)) {
        _incomingWasConnected = false;
        if (!NotificationService.isAppForeground && next.peerId != null) {
          unawaited(NotificationService.showIncomingCall(
            peerId: next.peerId!,
            pseudo: ref.read(peerPseudoProvider(next.peerId!)),
          ));
        }
      }
    });
  }

  // Appelé automatiquement par Android/iOS chaque fois que l'app passe au
  // premier plan ou en arrière-plan — comme quelqu'un qui te tape sur
  // l'épaule pour te dire « attention, l'app vient d'être minimisée ! ».
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    NotificationService.isAppForeground = state == AppLifecycleState.resumed;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _retryTimer?.cancel();
    _nexusSafetyTimer?.cancel();
    _msgSub?.cancel();
    _statusSub?.cancel();
    _checkinSub?.cancel();
    _nexusPeerSub?.cancel();
    _nexusEventSub?.cancel();
    _callSub?.close();
    super.dispose();
  }

  /// Sécurité : si l'animation Nexus ne se referme pas toute seule, on
  /// retire la couche de force après 12 s.
  ///
  /// La séquence dure 9,9 s au total ; passé douze, quelque chose s'est
  /// mal passé. L'ancienne version se contentait de remettre un drapeau à
  /// zéro — ce qui autorisait une NOUVELLE animation par-dessus celle
  /// restée coincée, sans jamais retirer la première. Ici on retire
  /// vraiment ce qui est à l'écran.
  void _startNexusSafetyTimer() {
    _nexusSafetyTimer?.cancel();
    _nexusSafetyTimer = Timer(const Duration(seconds: 12), () {
      if (NexusStage.current.value != null) {
        debugPrint('[Droplet] nexus safety: couche retirée de force');
        NexusStage.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
