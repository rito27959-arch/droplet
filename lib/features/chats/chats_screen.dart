import 'dart:convert';
// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'écran d'ACCUEIL — la liste des conversations, première chose que voit
// l'utilisateur. C'est l'écran qui donne son impression générale à toute
// l'app.
//
// CE QUI A CHANGÉ À LA REFONTE — l'ancienne version empilait, avant même
// d'atteindre la première conversation : un bandeau rouge « Mode
// urgence », une grande carte animée avec des points en orbite, une
// rangée de statuts, une rangée « À proximité », et seulement ensuite la
// liste. L'information principale (« à qui je parle ») était repoussée
// hors de l'écran par de la décoration.
//
// Le nouvel écran suit la règle d'iOS : LE CONTENU D'ABORD.
//   - Un grand titre « Discussions » qui se replie au défilement.
//   - Une barre de recherche, comme dans Messages.
//   - Les statuts sur une seule ligne compacte, seulement s'il y en a.
//   - Puis immédiatement les conversations, en pleine largeur.
//
// Le mode urgence et l'état du réseau ne sont pas supprimés : ils
// deviennent des éléments discrets de la barre de navigation, accessibles
// en un geste mais sans occuper le tiers de l'écran en permanence.
// ============================================================================

import 'dart:async';
import 'dart:ui' as ui;
import 'dart:ui' show FontFeature;
import 'dart:math' as math;

import 'package:flutter/cupertino.dart'
    show CupertinoAlertDialog, CupertinoDialogAction, showCupertinoDialog;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/models/mesh_message.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/storage_service.dart';
import '../../core/services/crash_journal.dart';
import '../../core/services/media_service.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/reglages_apparence.dart';
import '../../design_system/ouro_typography.dart';
import '../../shared/widgets/avatar_groupe.dart';
import '../../shared/widgets/bulle_guide.dart';
import '../chat/message_context_menu.dart';
import '../../shared/widgets/glissement_actions.dart';
import '../settings/journal_sheet.dart';
import '../../core/services/journal_notifs.dart';
import '../../core/services/reglages_notifs.dart';
import '../../design_system/ouro_alert.dart';
import '../notifications/notifs_conversation_screen.dart'
    show kDureesSourdine, libelleDureeSourdine;
import '../../design_system/ouro_haptics.dart';
import '../call/bandeau_appel_groupe.dart';
import '../../l10n/generated/app_localizations.dart';
import 'package:local_auth/local_auth.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/ouro_pressable.dart';
import '../../design_system/glassmorphism.dart';
import '../../design_system/design_tokens.dart';
import '../../shared/widgets/peer_avatar.dart';
import '../../design_system/ouro_motion.dart';
import 'chats_filter_bar.dart';
import '../../shared/widgets/scene_animee.dart';
import '../../shared/widgets/ios_magnifier_overlay.dart';
import '../../core/services/avatar_service.dart';
import '../../core/config/server_config.dart';
import '../../core/services/etat_connexion.dart';
import '../../core/providers/internet_provider.dart';
import '../../design_system/ouro_compteur.dart';
import '../../design_system/ouro_retour_ios.dart';
import '../status/status_pager_screen.dart';
import '../status/ordre_statuts.dart';
import '../chat/sticker_picker.dart';
import '../../design_system/ouro_avatar.dart';
import '../ai/etat_assistant.dart';
import '../../core/models/apercu_systeme.dart';
import '../../shared/widgets/typing_indicator.dart';
import '../../shared/widgets/afficher_toast.dart';
import 'apercu_conversation.dart';
import '../../core/services/brouillons.dart';
import '../../core/models/voice_note_meta.dart';
import '../chat/media_kind.dart';
import '../chat/location_message.dart';
import 'dart:io' show File;
import '../../core/providers/locale_provider.dart' show kSupportedLocales;
import '../status/anneau_statuts.dart';
import '../../core/services/miroir_appareils.dart';
import '../../design_system/flou.dart';
import '../../core/config/compte_droplet.dart';
import '../../shared/widgets/avatar_officiel.dart';

class ChatsScreen extends ConsumerStatefulWidget {
  const ChatsScreen({super.key});

  @override
  ConsumerState<ChatsScreen> createState() => _ChatsScreenState();
}

class _ChatsScreenState extends ConsumerState<ChatsScreen> {
  bool _meshStarted = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  /// Un rapport d'erreur attend d'être envoyé.
  bool _rapportEnAttente = false;

  /// L'astuce « Droplet marche sans Internet », fermée une fois pour toutes.
  static const String _cleAstuce = 'astuce_proximite_fermee';
  bool _astuceFermee = StorageService.getString(_cleAstuce) == '1';

  /// Le filtre retenu au-dessus de la liste.
  ///
  /// Il remplace les en-têtes « ÉPINGLÉES » / « DISCUSSIONS », qui
  /// occupaient chacun une ligne pour étiqueter ce que la position dans
  /// la liste disait déjà. Voir `chats_filter_bar.dart`.
  FiltreChats _filtre = FiltreChats.toutes;

  // Les points désignés par la visite guidée. Ce sont les trois choses
  // qu'on ne devine pas : que « zéro pair » n'est pas une panne, que le
  // réseau se regarde, et que la conversation commence par un geste.
  final _cleReseau = GlobalKey();
  final _clePlus = GlobalKey();
  final _cleReglages = GlobalKey();

  @override
  void initState() {
    super.initState();
    _ensureMesh();
    _chercherUnRapport();
    // Après la première image : les boutons doivent exister pour qu'on
    // puisse les désigner.
    // ⚠️ PAS SUR LA PREMIÈRE IMAGE. La visite se lançait avant même que
    // la liste soit peinte : la toute première vision de Droplet était un
    // voile noir et une bulle bleue. On laisse l'accueil se poser, puis on
    // propose l'aide — c'est l'ordre qu'Apple impose à ses propres
    // présentations de fonctionnalités.
    Future.delayed(const Duration(milliseconds: 900), _visiteGuidee);
    _searchCtrl.addListener(() => setState(() => _query = _searchCtrl.text.trim().toLowerCase()));
  }

  @override
  void dispose() {
    _minuteurVerrous?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// La visite guidée du premier lancement.
  ///
  /// ⚠️ TROIS ÉTAPES, PAS DIX. Ce ne sont pas les fonctions de
  /// l'application qu'on explique — on les découvre très bien seul.
  /// Ce sont les trois comportements que Droplet ne PARTAGE PAS avec
  /// les messageries habituelles, et que l'on prend pour des pannes
  /// faute d'un mot d'explication :
  ///
  ///   • « zéro pair à proximité » est l'état normal, pas une erreur ;
  ///   • un message peut mettre des heures sans être perdu ;
  ///   • le réseau se regarde, et c'est là qu'on comprend pourquoi.
  ///
  /// Tout le reste — les statuts, les appels, la carte — ressemble
  /// assez à ce que les gens connaissent pour se passer de tutoriel.
  void _visiteGuidee() {
    if (!mounted) return;
    final l10n = AppLocalizations.of(context);
    Guide.lancer(
      context,
      nom: 'accueil',
      etapes: [
        EtapeGuide(
          cible: _cleReseau,
          titre: l10n.csGuideNetworkTitle,
          texte: l10n.csGuideNetworkText,
        ),
        EtapeGuide(cible: _clePlus, titre: l10n.csGuideWriteTitle, texte: l10n.csGuideWriteText),
        EtapeGuide(
          cible: _cleReglages,
          titre: l10n.csGuideBackupTitle,
          texte: l10n.csGuideBackupText,
        ),
      ],
    );
  }

  /// Regarde si l'application s'est fermée anormalement depuis la
  /// dernière fois qu'on a regardé.
  ///
  /// ⚠️ ON DEMANDE, ON N'ENVOIE PAS. Le journal ne contient aucun
  /// message ni contact — mais c'est un fichier technique, et
  /// l'expédier sans le dire serait exactement ce que Droplet reproche
  /// aux autres applications. C'est l'utilisateur qui décide, à chaque
  /// fois.
  Future<void> _chercherUnRapport() async {
    final oui = await CrashJournal.aDuNouveau();
    if (mounted && oui) setState(() => _rapportEnAttente = true);
  }

  /// Démarre le réseau mesh une seule fois, dès l'affichage de l'écran.
  Future<void> _ensureMesh() async {
    if (_meshStarted) return;
    _meshStarted = true;
    final user = StorageService.currentUser;
    if (user == null) return;
    try {
      final repo = ref.read(meshRepositoryProvider);
      await repo.init(user.id, user.pseudo);
      // ⚠️ AVEC L'ADRESSE DU SERVEUR D'APPELS, COMME `MeshBootstrap`.
      // `CallNotifier.init` ne s'exécute qu'une fois : si cet écran passait
      // en premier sans `signalingUrl`, les appels par Internet restaient
      // désactivés pour toute la session — selon la simple course entre les
      // deux initialisations au lancement.
      ref.read(callProvider.notifier).init(repo.transport, repo: repo, signalingUrl: kSignalingUrl);
      ref.read(groupCallProvider.notifier).init(repo.transport, repo.myId, repo: repo);
    } catch (e) {
      debugPrint('[Chats] mesh init error: $e');
    }
  }

  /// Les discussions verrouillées sont révélées (tirer vers le bas).
  bool _verrousVisibles = false;
  Timer? _minuteurVerrous;

  Future<void> _onRefresh() async {
    // La découverte de pairs tourne déjà en continu en arrière-plan ; ce
    // geste sert de confirmation rassurante, comme dans Mail sur iOS.
    OuroHaptics.light();
    await Future.delayed(const Duration(milliseconds: 600));
    // Et c'est le geste qui révèle les discussions verrouillées, s'il y en
    // a — voir la ligne correspondante dans `build`.
    if (!mounted || ref.read(lockedConversationsProvider).isEmpty) return;
    setState(() => _verrousVisibles = true);
    _minuteurVerrous?.cancel();
    _minuteurVerrous = Timer(const Duration(seconds: 30), () {
      if (mounted) setState(() => _verrousVisibles = false);
    });
  }

  Future<void> _archiveConversation(Conversation c) async {
    OuroHaptics.medium();
    await StorageService.setConversationArchived(c.key, true);
    if (!mounted) return;
    ref.read(archivedRevisionProvider.notifier).state++;
  }

  Future<void> _pinConversation(Conversation c) async {
    OuroHaptics.medium();
    await StorageService.setConversationPinned(c.key, !c.isPinned);
    if (!mounted) return;
    ref.read(pinMuteRevisionProvider.notifier).state++;
  }

  /// Silence : combien de temps ? — ou, si c'est déjà silencieux, le son
  /// revient tout de suite.
  ///
  /// ⚠️ PLUS UN SIMPLE INTERRUPTEUR. « Silence » coupait pour toujours, et
  /// c'est précisément pourquoi on hésitait à s'en servir : on coupe un
  /// groupe pour la soirée, et on l'oublie pour un mois. Les durées sont
  /// celles de WhatsApp et d'iMessage.
  Future<void> _muteConversation(Conversation c) async {
    OuroHaptics.medium();
    if (c.isMuted) {
      await ReglagesNotifs.leverSourdine(c.key);
    } else {
      final l10n = AppLocalizations.of(context);
      // ⚠️ « TOUJOURS » N'EST PAS `null`. `null` est déjà la réponse
      // « Annuler » de la boîte ; on le représente donc par une durée
      // impossible, reconnue juste en dessous.
      final choix = await ouroChoice<Duration>(
        context,
        title: l10n.muTitle(c.pseudo),
        message: c.groupId != null ? l10n.ncMuteFooterGroup : l10n.ncMuteFooter,
        options: [
          for (final d in kDureesSourdine)
            OuroChoiceOption(
              value: d ?? const Duration(days: 36500),
              label: libelleDureeSourdine(l10n, d),
            ),
        ],
      );
      if (choix == null) return;
      await ReglagesNotifs.mettreEnSourdine(
        c.key,
        duree: choix.inDays >= 36500 ? null : choix,
      );
    }
    if (!mounted) return;
    ref.read(pinMuteRevisionProvider.notifier).state++;
  }

  Future<void> _openArchived() async {
    OuroHaptics.selection();
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _ArchivedSheet(),
    );
  }

  /// Ouvre la liste des conversations verrouillées — derrière sa PROPRE
  /// authentification biométrique.
  ///
  /// ⚠️ CETTE DEMANDE-CI EST DISTINCTE DE CELLE DE `ConversationLockScreen`.
  /// Ouvrir cette feuille ne dispense pas d'authentifier ENSUITE l'accès à
  /// une conversation précise en la touchant — exactement comme le dossier
  /// « Discussions verrouillées » de WhatsApp redemande la biométrie au
  /// moment d'ouvrir une conversation à l'intérieur. Ce n'est pas une
  /// redondance : le premier verrou protège la LISTE (qui discute avec
  /// qui), le second protège le CONTENU (ce qui a été dit).
  Future<void> _openLocked() async {
    OuroHaptics.selection();
    final l10n = AppLocalizations.of(context);
    final auth = LocalAuthentication();
    try {
      final available = await auth.canCheckBiometrics;
      if (!available) return;
      final didAuth = await auth.authenticate(
        localizedReason: l10n.csShowLockedChatsReason,
        options: const AuthenticationOptions(stickyAuth: true, biometricOnly: true),
      );
      if (!didAuth) return;
    } catch (_) {
      return;
    }
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const _LockedChatsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(archivedRevisionProvider);
    ref.watch(pinMuteRevisionProvider);
    // Une photo de profil vient d'arriver : les lignes se redessinent avec.
    ref.watch(peerAvatarRevisionProvider);
    final all = ref.watch(conversationsProvider);
    // Recherche dans le TEXTE des messages, pas seulement dans les noms.
    final trouves = _messagesTrouves(ref.watch(meshMessagesProvider));
    final conversations = _query.isEmpty
        ? all
        : all.where((c) => c.pseudo.toLowerCase().contains(_query)).toList();
    final peers = ref.watch(meshPeerListProvider);
    final internet = ref.watch(internetDisponibleProvider);
    final archivedCount = StorageService.getArchivedConversations().length;
    // `ref.watch` et non `StorageService` directement : cette ligne doit
    // apparaître/disparaître dès qu'une conversation est verrouillée ou
    // déverrouillée, sans attendre un autre déclencheur de reconstruction.
    final lockedCount = ref.watch(lockedConversationsProvider).length;

    // ── LE WIDGET D'ÉCRAN D'ACCUEIL ──────────────────────────────
    //
    // ⚠️ MIS À JOUR DEPUIS ICI, ET APRÈS L'IMAGE.
    //
    // C'est le seul écran qui connaît à la fois le nombre de messages
    // non lus et le nombre de pairs — les deux chiffres du widget. Les
    // recalculer ailleurs aurait donné deux comptes qui divergent, et un
    // widget qui contredit l'application est pire qu'un widget absent.
    //
    // `addPostFrameCallback` parce qu'un appel de canal natif pendant
    // `build` déclenche une reconstruction en pleine construction. Et
    // `unawaited` parce que l'affichage ne doit jamais attendre le
    // lanceur d'Android.
    // ── LE TRI ET LE FILTRAGE, FAITS UNE SEULE FOIS ─────────────
    //
    // Tout ce qui suit était fait à l'intérieur des `itemBuilder`, donc
    // recalculé pour chaque ligne, à chaque image. Ici c'est calculé une
    // fois par construction, et la liste n'a plus qu'à lire une case.
    //
    // ⚠️ LES ÉPINGLÉES RESTENT EN TÊTE MÊME SANS EN-TÊTE DE SECTION.
    // C'était le seul service que rendait le titre « ÉPINGLÉES » :
    // expliquer pourquoi ces conversations sont en haut. Un tri stable
    // qui les remonte le rend inutile — leur position EST l'information,
    // et la petite punaise sur la ligne la confirme.
    final motionEcran = OuroMotion.of(context);

    // Joignables sans Internet, à cet instant : ceux que le maillage relie.
    final idsProches = {for (final pair in peers) pair.peerId};
    bool estProche(Conversation c) => !c.isGroup && idsProches.contains(c.peerId);
    final compteurs = <FiltreChats, int>{
      FiltreChats.proches: conversations.where(estProche).length,
      FiltreChats.toutes: conversations.length,
      FiltreChats.nonLues: conversations.where((c) => c.aLire).length,
      FiltreChats.groupes: conversations.where((c) => c.isGroup).length,
      // ⚠️ + 1 : L'ASSISTANT. Il est épinglé en tête de liste, punaise
      // comprise, mais n'est pas une conversation du maillage : le filtre
      // affichait « Épinglées 1 » au-dessus de deux lignes épinglées.
      FiltreChats.epinglees: conversations.where((c) => c.isPinned).length + 1,
    };

    final filtrees = switch (_filtre) {
      FiltreChats.toutes => conversations,
      FiltreChats.proches => conversations.where(estProche).toList(),
      FiltreChats.nonLues => conversations.where((c) => c.aLire).toList(),
      FiltreChats.groupes => conversations.where((c) => c.isGroup).toList(),
      FiltreChats.epinglees => conversations.where((c) => c.isPinned).toList(),
    };

    // Pendant une recherche, l'ordre est celui de la pertinence : on ne
    // remonte pas les épinglées, qui n'ont rien à voir avec la requête.
    final visibles = _query.isNotEmpty
        ? filtrees
        : [...filtrees.where((c) => c.isPinned), ...filtrees.where((c) => !c.isPinned)];

    final nonLus = all.fold<int>(0, (t, c) => t + c.unreadCount);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(MediaService.majWidget(nonLus: nonLus, pairs: peers.length));
    });

    final l10n = AppLocalizations.of(context);

    return IosMagnifierOverlay(
      child: _AmbianceHoraire(
      child: OuroLargeTitleScaffold(
        // Transparent : c'est `_AmbianceHoraire` qui peint le fond, avec sa
        // teinte du moment en haut. Les lignes, elles, restent opaques.
        backgroundColor: Colors.transparent,
        title: l10n.chatsTitle,
        // Le sous-titre remplace à lui seul l'ancienne grande carte animée
        // du réseau : l'information utile (« combien de personnes sont
        // joignables ») en une ligne, au lieu d'un tiers d'écran.
        // Mesh ET Internet, dans la même ligne — voir `etat_connexion.dart`.
        subtitle: _sousTitreReseau(l10n, peers.length, internet),
        // Le même état, compris avant d'être lu : couleur de Droplet quand le
        // maillage relie quelqu'un, vert pour Internet seul, rond vide sinon.
        subtitleLeading: _PointReseau(pairs: peers.length, internet: internet),
        onRefresh: _onRefresh,
        floatingNotification: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Un appel de groupe réduit : la pastille qui y ramène. Au-dessus
            // du reste, et toujours visible — un appel en cours n'est pas une
            // information qu'on doit aller chercher en défilant.
            const BandeauAppelGroupe(),
            _MeshNotificationBanner(conversations: all),
          ],
        ),
        leading: KeyedSubtree(
          key: _cleReglages,
          // ── ⚠️ UNE SEULE ICÔNE COLORÉE DANS L'EN-TÊTE ──────────────
          //
          // Les quatre étaient rouges : réglages, réseau, cloche, plus.
          // Quatre appels à l'attention de même force, c'est n'en faire
          // aucun. iOS garde la couleur pour l'action principale de
          // l'écran — ici, écrire — et laisse le reste à l'encre du texte.
          child: OuroBarButton(
            icon: Icons.settings_outlined,
            tooltip: l10n.settingsTitle,
            color: OuroColors.label,
            onPressed: () => context.push('/settings'),
          ),
        ),
        actions: [
          KeyedSubtree(
            key: _cleReseau,
            // L'icône des ondes, signature de Droplet : des ronds s'en
            // échappent tant qu'un appareil est à portée, immobile sinon.
            // Même couleur que l'icône — rien de nouveau dans la palette.
            child: Stack(
              alignment: Alignment.center,
              children: [
                Positioned.fill(
                  child: IgnorePointer(
                    child: _OndesEnTete(actif: peers.isNotEmpty),
                  ),
                ),
                OuroBarButton(
                  icon: Icons.wifi_tethering_rounded,
                  tooltip: l10n.chatsMeshNetwork,
                  color: OuroColors.label,
                  onPressed: () => context.push('/mesh-network'),
                ),
              ],
            ),
          ),
          // ── LA CLOCHE DU CENTRE DE NOTIFICATIONS ──────────────────────
          //
          // Sa pastille compte ce qui est nouveau — mentions, réactions,
          // appels manqués. Rien de nouveau : pas de pastille du tout, pas
          // un « 0 » qui crierait pour rien.
          ListenableBuilder(
            listenable: JournalNotifs.instance,
            builder: (context, _) {
              final n = JournalNotifs.instance.nonLues;
              return Semantics(
                label: n > 0 ? l10n.cnBellUnread(n) : null,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    OuroBarButton(
                      icon: n > 0
                          ? Icons.notifications_rounded
                          : Icons.notifications_none_rounded,
                      tooltip: l10n.cnTitle,
                      color: OuroColors.label,
                      onPressed: () => context.push('/notifications'),
                    ),
                    Positioned(
                      right: 2,
                      top: 2,
                      child: IgnorePointer(
                        child: AnimatedScale(
                          scale: n > 0 ? 1 : 0,
                          duration: const Duration(milliseconds: 260),
                          curve: Curves.easeOutBack,
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 17),
                            height: 17,
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: OuroColors.systemRed,
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: OuroColors.systemBackground,
                                width: 1.5,
                              ),
                            ),
                            child: Text(
                              n > 99 ? '99+' : '$n',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                height: 1,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          KeyedSubtree(
            key: _clePlus,
            child: OuroBarButton(
              icon: Icons.add_rounded,
              tooltip: l10n.chatsNew,
              onPressed: _showComposeMenu,
            ),
          ),
        ],
        slivers: [
          if (_rapportEnAttente)
            SliverToBoxAdapter(
              child: _BandeauRapport(
                onEnvoyer: () async {
                  await afficherJournal(context);
                  await CrashJournal.marquerVu();
                  if (mounted) setState(() => _rapportEnAttente = false);
                },
                onIgnorer: () async {
                  await CrashJournal.marquerVu();
                  if (mounted) setState(() => _rapportEnAttente = false);
                },
              ),
            ),
          SliverToBoxAdapter(child: _SearchField(controller: _searchCtrl)),

          // ── LA BARRE DE FILTRES ────────────────────────────────────
          //
          // Elle remplace les deux en-têtes « ÉPINGLÉES » et
          // « DISCUSSIONS ». Ceux-ci consommaient une ligne chacun pour
          // ÉTIQUETER ce que la position dans la liste disait déjà, et ils
          // ne rendaient service que dans un cas : quand on cherchait
          // quelque chose de précis. Un filtre traite ce cas-là
          // directement — il ENLÈVE les conversations hors sujet au lieu
          // de les surmonter d'un titre.
          //
          // Elle disparaît d'elle-même pendant une recherche : le champ
          // filtre déjà, deux filtres empilés ne se comprennent plus.
          if (_query.isEmpty)
            SliverToBoxAdapter(
              child: ChatsFilterBar(
                actif: _filtre,
                compteurs: compteurs,
                onChange: (f) => setState(() => _filtre = f),
              ),
            ),

          // ── LE RÉSUMÉ DU JOUR ──────────────────────────────────────────
          //
          // À la première ouverture de la journée, s'il s'est passé quelque
          // chose : « 12 messages non lus dans 3 discussions · 1 mention ·
          // 1 appel manqué ». Un toucher filtre les non-lus ; la croix le
          // range jusqu'au lendemain.
          if (_query.isEmpty && _filtre == FiltreChats.toutes)
            SliverToBoxAdapter(
              child: _ResumeDuJour(
                conversations: all,
                onVoir: () => setState(() => _filtre = FiltreChats.nonLues),
              ),
            ),

          if (_query.isEmpty && archivedCount > 0)
            SliverToBoxAdapter(
              child: _ArchivedRow(count: archivedCount, onTap: _openArchived),
            ),

          // ── ⚠️ LES DISCUSSIONS VERROUILLÉES NE SE SIGNALENT PAS ───────
          //
          // La ligne « Discussions verrouillées 1 » était visible en
          // permanence : quiconque prenait le téléphone apprenait qu'il
          // existait une conversation cachée — ce qu'un verrou sert
          // précisément à taire. Comme chez WhatsApp, elle n'apparaît plus
          // que si l'on TIRE la liste vers le bas, et repart d'elle-même
          // après trente secondes. Et sans compteur : « 1 » ou « 4 » en dit
          // déjà trop.
          if (_query.isEmpty && lockedCount > 0 && _verrousVisibles)
            SliverToBoxAdapter(
              child: _LockedChatsRow(onTap: _openLocked),
            ),

          // ── L'ASSISTANT, ÉPINGLÉ EN TÊTE ────────────────────────────
          //
          // ⚠️ IL ÉTAIT CACHÉ DANS LE MENU « NOUVEAU » (LE CRAYON), entre
          // « Nouveau groupe » et « Mode urgence » : deux gestes, derrière
          // une icône qui promet d'ÉCRIRE un message, pas de parler à un
          // assistant. Rien à l'écran ne disait qu'il existait.
          //
          // Il apparaît désormais comme ce qu'il est — une conversation —
          // à l'endroit où l'on regarde en premier. Même disposition qu'une
          // vraie discussion, et masqué pendant une recherche comme les
          // autres lignes spéciales.
          // ⚠️ SEULEMENT SOUS « TOUTES » ET « ÉPINGLÉES ». Il restait affiché
          // sous « Non lues » et « Groupes », où il n'avait rien à faire.
          if (_query.isEmpty &&
              (_filtre == FiltreChats.toutes || _filtre == FiltreChats.epinglees))
            SliverToBoxAdapter(
              child: _AssistantPinnedRow(
                onTap: () async {
                  OuroHaptics.selection();
                  await context.push('/ai-chat');
                  // Rafraîchir l'aperçu du dernier échange au retour.
                  if (mounted) setState(() {});
                },
              ),
            ),

          if (visibles.isEmpty &&
              trouves.isEmpty &&
              // Sous « Épinglées », l'assistant suffit à ne pas être vide.
              !(_query.isEmpty && _filtre == FiltreChats.epinglees))
            SliverFillRemaining(
              hasScrollBody: false,
              child: AnimatedSwitcher(
                duration: motionEcran.duree(DesignTokens.durationStandard),
                child: _EmptyChats(
                  key: ValueKey(_query.isEmpty ? 'empty_${_filtre.name}' : 'search_$_query'),
                  searching: _query.isNotEmpty,
                  filtre: _filtre,
                ),
              ),
            )
          else
            // ── ⚠️ UNE SEULE LISTE, DÉJÀ CALCULÉE ────────────────────
            //
            // Il y avait ici deux `SliverList.builder`, et chacun refaisait
            // un `.where(...).toList()` À L'INTÉRIEUR de son `itemBuilder`
            // — donc une fois PAR LIGNE CONSTRUITE, à chaque image de
            // défilement. Parcourir la liste entière pour afficher une
            // ligne rend le coût quadratique : à 200 conversations, c'est
            // 40 000 tests par image, sur le fil principal, pendant un
            // geste. C'est exactement le genre de chose qui ne se voit pas
            // sur l'appareil du développeur avec huit conversations, et
            // qui fait tomber le défilement à 30 images par seconde chez
            // quelqu'un qui se sert vraiment de l'application.
            //
            // Le tri et le filtrage sont maintenant faits UNE FOIS dans
            // `build`, et l'`itemBuilder` ne fait plus qu'un accès indexé.
            SliverList.builder(
              itemCount: visibles.length,
              itemBuilder: (context, i) {
                final c = visibles[i];
                return _ConversationRow(
                  key: ValueKey(c.key),
                  conversation: c,
                  onArchive: () => _archiveConversation(c),
                  onPin: () => _pinConversation(c),
                  onMute: () => _muteConversation(c),
                );
              },
            ),
          // ── ⚠️ UNE ASTUCE, PAS UN ÉCRAN VIDE ─────────────────────────
          //
          // Il y avait ici, sous toute liste de moins de sept discussions,
          // un grand bloc centré — emblème, titre, paragraphe, lien. C'est
          // la mise en page d'un écran VIDE, posée sous une liste qui ne
          // l'était pas : on aurait dit que la liste s'arrêtait sur une
          // erreur, ou qu'on avait oublié de retirer un brouillon.
          //
          // C'est désormais une carte d'une ligne et demie, qu'on ferme
          // d'un toucher — et qui ne revient plus.
          if (_query.isEmpty &&
              _filtre == FiltreChats.toutes &&
              visibles.isNotEmpty &&
              visibles.length <= 3 &&
              !_astuceFermee)
            SliverToBoxAdapter(
              child: _AstuceProximite(
                proches: peers.length,
                surVoir: () => context.push('/mesh-network'),
                surFermer: () {
                  OuroHaptics.light();
                  setState(() => _astuceFermee = true);
                  unawaited(StorageService.setString(_cleAstuce, '1'));
                },
              ),
            ),
          if (trouves.isNotEmpty) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 6),
                child: Text(
                  AppLocalizations.of(context).csMessagesSection.toUpperCase(),
                  style: OuroTypography.caption1.copyWith(
                    color: OuroColors.secondaryLabel,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ),
            SliverList.builder(
              itemCount: trouves.length,
              itemBuilder: (context, i) => _ResultatMessage(
                message: trouves[i],
                requete: _query,
                moi: ref.read(meshRepositoryProvider).myId,
              ),
            ),
          ],
        ],
      ),
      ),
    );
  }

  /// Les messages dont le texte contient la recherche, du plus récent au plus
  /// ancien (40 au plus). À partir de deux lettres : une seule lettre
  /// trouverait presque tout.
  List<MeshMessage> _messagesTrouves(List<MeshMessage> tous) {
    if (_query.length < 2) return const [];
    final resultat = <MeshMessage>[];
    for (final m in tous.reversed) {
      // Un fichier sans légende n'a pour texte que son nom.
      if (m.type == 'file' && m.content == m.fileName) continue;
      if (m.type == 'appel') continue;
      if (m.content.toLowerCase().contains(_query)) {
        resultat.add(m);
        if (resultat.length >= 40) break;
      }
    }
    return resultat;
  }

  /// Menu d'action rapide, façon feuille iOS.
  void _showComposeMenu() {
    OuroHaptics.selection();
    final l10n = AppLocalizations.of(context);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => FrostedSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Les messages mis de côté : en tête, comme chez WhatsApp, là
            // où la main arrive.
            _SheetAction(
              icon: Icons.star_rounded,
              label: l10n.imTitle,
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/starred');
              },
            ),
            Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
            _SheetAction(
              icon: Icons.group_add_rounded,
              label: l10n.chatsNewGroup,
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.go('/group/create');
              },
            ),
            Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
            // Écrire à quelqu'un qui n'a pas encore Droplet : un lien qui vaut
            // un QR code (voir `invitation.dart`).
            _SheetAction(
              icon: Icons.person_add_alt_1_rounded,
              label: l10n.chatsInvitePerson,
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/inviter');
              },
            ),
            Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
            _SheetAction(
              icon: Icons.auto_awesome_rounded,
              label: l10n.chatsAssistant,
              color: OuroColors.accent,
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/ai-chat');
              },
            ),
            Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
            // ── « NOUVEAU STATUT » A ÉTÉ RETIRÉ D'ICI ────────────────
            //
            // Publier un statut n'est pas une action de l'écran des
            // discussions : ça ne produit aucune conversation, ça
            // n'écrit à personne en particulier, et ça n'apparaîtra
            // jamais dans la liste qu'on a sous les yeux. Ça vivait dans
            // ce menu par commodité de placement, pas par logique.
            //
            // Le compositeur reste accessible depuis l'écran des
            // actualités (`news_screen.dart`), qui est l'endroit où les
            // statuts se regardent — donc l'endroit où l'on pense à en
            // publier un.
            _SheetAction(
              icon: Icons.health_and_safety_rounded,
              label: l10n.chatsEmergencyMode,
              // Le seul élément coloré du menu : le rouge y garde son
              // sens d'alerte, justement parce qu'il est isolé.
              color: OuroColors.systemRed,
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/safety');
              },
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  RECHERCHE
// ─────────────────────────────────────────────────────────────

/// Barre de recherche façon iOS : capsule grise, loupe à l'intérieur,
/// aucune bordure.
/// Le bandeau qui signale un rapport d'erreur non envoyé.
///
/// ── ⚠️ POURQUOI IL EXISTE, ET POURQUOI IL EST DISCRET ─────────────
///
/// Droplet n'a aucun serveur : quand l'application se ferme toute seule
/// chez quelqu'un, la seule trace au monde est un fichier sur son
/// téléphone. S'il ne l'envoie pas, le défaut n'existe pour personne —
/// et il ne sera jamais corrigé.
///
/// Or ce journal vivait au fond des réglages, sans que rien ne signale
/// jamais son contenu. Un testeur qui plante rouvre l'application et
/// continue : aller voir demande de se souvenir qu'un journal existe, à
/// un moment où l'on pensait à autre chose. Les rapports ne remontaient
/// donc pas, par oubli et non par mauvaise volonté.
///
/// Il est ambre et non rouge : il ne s'est rien passé de grave pour
/// l'utilisateur — ses messages sont intacts, rien n'est perdu. Le
/// rouge dirait « danger » là où il n'y a qu'une demande de service.
///
/// Et il porte un « Plus tard » qui le fait taire DÉFINITIVEMENT pour
/// ces lignes-là. Un bandeau qu'on ne peut pas congédier devient un
/// harcèlement, et la première chose qu'on apprend à faire d'un
/// harcèlement est de ne plus le lire.
class _BandeauRapport extends StatelessWidget {
  const _BandeauRapport({required this.onEnvoyer, required this.onIgnorer});

  final VoidCallback onEnvoyer;
  final VoidCallback onIgnorer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.screenMargin,
        DesignTokens.space2,
        DesignTokens.screenMargin,
        0,
      ),
      child: Container(
        padding: const EdgeInsets.all(DesignTokens.space4),
        decoration: BoxDecoration(
          color: OuroColors.systemOrange.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(DesignTokens.radiusLg),
          border: Border.all(color: OuroColors.systemOrange.withValues(alpha: 0.32)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.warning_amber_rounded, size: 19, color: OuroColors.systemOrange),
                const SizedBox(width: DesignTokens.space3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.chatsCrashTitle,
                        style: OuroTypography.headline.copyWith(color: OuroColors.label),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        l10n.chatsCrashBody,
                        style: OuroTypography.footnote.copyWith(
                          color: OuroColors.secondaryLabel,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: DesignTokens.space3),
            Row(
              children: [
                Expanded(
                  child: OuroRetourIos(child: FilledButton(
                    onPressed: onEnvoyer,
                    style: FilledButton.styleFrom(overlayColor: Colors.transparent, 
                      backgroundColor:
                          OuroColors.surRemplissage(OuroColors.systemOrange),
                      padding: const EdgeInsets.symmetric(vertical: 11),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(DesignTokens.radiusMd),
                      ),
                    ),
                    child: Text(
                      l10n.chatsSendReport,
                      style: OuroTypography.subheadline.copyWith(
                        color: OuroColors.texteSurRemplissage(
                          OuroColors.systemOrange,
                        ),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  )),
                ),
                const SizedBox(width: DesignTokens.space3),
                OuroRetourIos(child: TextButton(
                  onPressed: onIgnorer,
                  child: Text(
                    l10n.chatsLater,
                    style: OuroTypography.subheadline.copyWith(color: OuroColors.secondaryLabel),
                  ),
                )),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});
  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.screenMargin,
        DesignTokens.space1,
        DesignTokens.screenMargin,
        DesignTokens.space2,
      ),
      // ⚠️ UN FOND GRIS PLEIN, PAS UNE CARTE. `OuroCard` est presque de la
      // couleur de la page : sur fond clair, la recherche n'était plus
      // qu'un mot gris flottant, qu'on ne reconnaissait pas comme un champ.
      // La barre de recherche d'iOS est un rectangle gris arrondi — c'est
      // à sa forme qu'on la reconnaît, avant même de lire « Rechercher ».
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: OuroColors.tertiarySystemFill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: TextField(
            controller: controller,
            style: OuroTypography.body.copyWith(color: OuroColors.label),
            cursorColor: OuroColors.accent,
            magnifierConfiguration: TextMagnifier.adaptiveMagnifierConfiguration,
            decoration: InputDecoration(
              isDense: true,
              hintText: AppLocalizations.of(context).chatsSearchHint,
              // Le gris des indications d'iOS (60 %) : au gris tertiaire
              // (30 %), le mot « Rechercher » disparaissait sur le fond.
              hintStyle: OuroTypography.body.copyWith(color: OuroColors.secondaryLabel),
              prefixIcon: Icon(
                Icons.search_rounded,
                color: OuroColors.secondaryLabel,
                size: DesignTokens.iconMd,
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 34),
              filled: true,
              fillColor: Colors.transparent,
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  LIGNE DE CONVERSATION
// ─────────────────────────────────────────────────────────────

/// Une conversation dans la liste — mise en page identique à Messages sur
/// iOS : avatar, nom, aperçu sur deux lignes, heure et chevron à droite,
/// et un séparateur qui démarre après l'avatar.
class _ConversationRow extends ConsumerStatefulWidget {
  const _ConversationRow({
    super.key,
    required this.conversation,
    required this.onArchive,
    required this.onPin,
    required this.onMute,
  });

  final Conversation conversation;
  final VoidCallback onArchive;
  final VoidCallback onPin;
  final VoidCallback onMute;

  @override
  ConsumerState<_ConversationRow> createState() => _ConversationRowState();
}

class _ConversationRowState extends ConsumerState<_ConversationRow>
    with SingleTickerProviderStateMixin {
  bool _pressed = false;

  // ── L'ARRIVÉE D'UN MESSAGE ─────────────────────────────────────────
  //
  // Une conversation qui reçoit un message remonte en tête de liste.
  // Elle y SAUTAIT : d'une image à l'autre, la ligne était ailleurs, et
  // l'œil perdait le fil de la liste qu'il était en train de lire.
  //
  // Elle y descend maintenant d'un cran, depuis le haut, et sa ligne
  // s'éclaire un instant de la couleur de Droplet avant de s'éteindre :
  // on voit QUI vient d'écrire sans avoir à chercher. C'est l'effet
  // d'iMessage, à une fraction de sa durée pour ne jamais gêner.
  late final AnimationController _arrivee = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
    value: 1,
  );

  @override
  void initState() {
    super.initState();
    // Une conversation qui apparaît avec un message de l'instant : c'est
    // une arrivée, pas un affichage de la liste.
    final age = DateTime.now().difference(widget.conversation.lastTimestamp);
    // Après la première image : `MediaQuery` n'est pas lisible pendant
    // `initState`.
    if (age < const Duration(seconds: 3) && !age.isNegative) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jouerArrivee();
      });
    }
  }

  @override
  void didUpdateWidget(covariant _ConversationRow ancien) {
    super.didUpdateWidget(ancien);
    if (widget.conversation.lastTimestamp
        .isAfter(ancien.conversation.lastTimestamp)) {
      _jouerArrivee();
    }
  }

  void _jouerArrivee() {
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return;
    unawaited(_arrivee.forward(from: 0));
  }

  @override
  void dispose() {
    _arrivee.dispose();
    super.dispose();
  }

  /// Le rectangle exact de la ligne : l'aperçu de l'appui long part de là.
  final GlobalKey _cleLigne = GlobalKey();

  static const double _avatarSize = 52;
  static const double _textInset = DesignTokens.screenMargin + _avatarSize + DesignTokens.space3;

  void _open() {
    final c = widget.conversation;
    OuroHaptics.selection();
    final route = c.isGroup
        ? '/group/${c.groupId}'
        : c.isBroadcast
        ? '/chat/broadcast'
        : '/chat/${c.peerId}';
    // `push` et non `go` : la liste des discussions reste DERRIÈRE la
    // conversation. C'est ce qui donne la parallaxe à l'ouverture et,
    // surtout, ce qui permet de revenir en tirant depuis le bord.
    context.push(route);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.conversation;
    final unread = c.aLire;
    // Quelqu'un m'écrit en ce moment dans cette discussion.
    final ecrit = c.peerId != null && ref.watch(typingPeersProvider).contains(c.peerId);

    // ⚠️ LA JOIGNABILITÉ (« • Hors de portée », « 2 sauts ») N'EST PLUS
    // ICI. C'est une information sur le RÉSEAU, pas sur la conversation :
    // sur l'écran d'accueil elle se lisait comme du jargon, et elle
    // allongeait une ligne sur deux. Elle vit dans l'en-tête de la
    // discussion, là où l'on en a besoin — au moment d'écrire.

    // ── LE RYTHME D'UNE LIGNE ─────────────────────────────────────
    //
    // ⚠️ TOUTES LES LIGNES ONT LA MÊME HAUTEUR, et c'est ce qui manquait.
    // Un aperçu d'une ligne donnait 64 points, un aperçu de deux en
    // donnait 88 : la liste avançait par à-coups, et l'œil ne pouvait
    // plus s'appuyer sur une grille. Messages, WhatsApp et Telegram ont
    // tous une hauteur FIXE ; le texte y est tronqué, pas la maille.
    //
    // ⚠️ PAS DE CHEVRON. Il y en avait un sur chaque ligne : sur iOS, une
    // liste de conversations n'en porte aucun — le chevron annonce un
    // réglage, pas une discussion, et répété douze fois il devient une
    // colonne de bruit gris le long du bord.
    //
    // ⚠️ LE COMPTEUR EST À DROITE, sous l'heure. Il était à gauche, dans
    // une colonne de dix points, ce qui le coupait dès deux chiffres.
    final lignesApercu = ReglagesApparence.lignesListe - 1;
    final row = Container(
      color: _pressed ? OuroColors.systemGray6 : Colors.transparent,
      // Lignes resserrées : deux conversations de plus par écran.
      constraints: BoxConstraints(minHeight: lignesApercu >= 2 ? 76 : 64),
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.screenMargin,
        DesignTokens.space2,
        DesignTokens.screenMargin,
        DesignTokens.space2,
      ),
      // Centré dans la hauteur de la ligne : un aperçu d'une seule ligne
      // laissait sinon un vide sous lui, et la colonne des avatars
      // perdait son alignement dès qu'une conversation était plus courte
      // que sa voisine.
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // ── L'AVATAR VIVANT ──────────────────────────────────────────
          //
          // Un appui long sur la photo l'agrandit, avec ce qu'on peut faire
          // de cette personne sans ouvrir la discussion : écrire, appeler,
          // voir sa fiche ou son statut. C'est la carte de WhatsApp —
          // déclenchée par l'appui long et non par le toucher, parce que
          // le toucher sur un anneau de statut ouvre déjà le statut.
          GestureDetector(
            onLongPress: () => _ApercuProfil.ouvrir(context, c),
            child: Hero(
            tag: 'avatar-${c.peerId}',
            child: _AnneauStatutDiscussion(
              peerId: c.peerId ?? '',
              estGroupe: c.isGroup,
              // ⚠️ UN GROUPE N'A PAS DE `peerId`, donc pas de photo : il
              // tombait sur les initiales de son NOM. Deux groupes dont le
              // nom commence par la même lettre étaient alors deux disques
              // identiques, et cinq groupes dans une liste de huit
              // conversations, cinq fois le même dessin.
              //
              // On montre à la place les deux premiers membres, moi exclu
              // — voir `avatar_groupe.dart` pour pourquoi ces deux-là et
              // pas d'autres.
              // Le compte officiel : son visage, posé par le code (jamais
              // une photo reçue — voir `avatar_officiel.dart`).
              child: c.peerId == CompteDroplet.id
                  ? AvatarOfficiel(rayon: _avatarSize / 2)
                  : c.isGroup
                  ? AvatarGroupe(
                      groupe: StorageService.getGroup(c.groupId ?? ''),
                      monId: ref.read(meshRepositoryProvider).myId,
                      rayon: _avatarSize / 2,
                    )
                  : PeerAvatar(
                      pseudo: ApercuSysteme.localiser(
                        c.pseudo,
                        AppLocalizations.of(context),
                      ),
                      radius: _avatarSize / 2,
                      online: c.isOnline,
                      imagePath: AvatarService.cheminPair(c.peerId),
                    ),
            ),
          ),
          ),
          const SizedBox(width: DesignTokens.space3),
          // ── DEUX LIGNES, DEUX COLONNES — LA GRILLE DE WHATSAPP ────────
          //
          // En haut : QUI, et QUAND. En bas : QUOI, et les marques (son
          // coupé, mention, non-lus, épingle). Chaque information a SA
          // place, la même sur toutes les lignes.
          //
          // ⚠️ AVANT, l'épingle et le son coupé collaient au nom, et la
          // joignabilité (« • Hors de portée ») s'empilait sous l'heure :
          // une ligne avait une colonne de droite sur deux étages, sa
          // voisine sur un seul, et l'épingle n'était jamais au même
          // endroit d'une ligne à l'autre. L'œil ne trouvait plus de
          // colonne où s'appuyer.
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (c.isGroup) ...[
                      Icon(Icons.group_rounded, size: 14, color: OuroColors.secondaryLabel),
                      const SizedBox(width: 4),
                    ],
                    // ⚠️ `Expanded` AUTOUR DU NOM ET DE LA COCHE, puis `Flexible`
                    // pour le nom seul. Avant, un `Flexible` suivi d'un
                    // `Spacer` se partageaient la place à parts égales :
                    // l'heure flottait au milieu de la ligne, à une position
                    // différente pour chaque discussion.
                    Expanded(
                      child: Row(
                        children: [
                          Flexible(
                            child: Text(
                        c.peerId == CompteDroplet.id
                            ? CompteDroplet.pseudo
                            : titreLisible(
                                ApercuSysteme.localiser(
                                  c.pseudo,
                                  AppLocalizations.of(context),
                                ),
                              ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: OuroTypography.headline.copyWith(
                          color: c.isMuted ? OuroColors.secondaryLabel : OuroColors.label,
                          // Non lue : le nom passe en gras. On reconnaît la
                          // ligne sans la lire, comme chez WhatsApp.
                          fontWeight: unread ? FontWeight.w700 : null,
                        ),
                      ),
                          ),
                          // La coche officielle, posée par le code pour cet
                          // identifiant seul : un pair qui se renommerait
                          // « Droplet » ne l'aura jamais.
                          if (c.peerId == CompteDroplet.id) ...[
                            const SizedBox(width: 4),
                            Icon(Icons.verified_rounded, size: 16, color: OuroColors.accent),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      formatMessageTime(
                        c.lastTimestamp,
                        langue: Localizations.localeOf(context).toLanguageTag(),
                        hier: AppLocalizations.of(context).chYesterday,
                      ),
                      maxLines: 1,
                      style: OuroTypography.caption1.copyWith(
                        // Non lue : l'heure prend la couleur, comme le
                        // compteur juste dessous — les deux se répondent.
                        color: unread && !c.isMuted
                            ? OuroColors.accent
                            : OuroColors.secondaryLabel,
                        fontWeight: unread ? FontWeight.w600 : FontWeight.w400,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Expanded(
                      // Quelqu'un est en train de m'écrire : ça passe devant
                      // l'aperçu, en couleur d'accent, avec les points qui
                      // respirent — comme dans la discussion.
                      child: ecrit
                          ? Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    AppLocalizations.of(context).chTypingNow,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: OuroTypography.subheadline.copyWith(
                                      color: OuroColors.accent,
                                      fontWeight: FontWeight.w500,
                                      height: 1.25,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                const TypingIndicator(),
                              ],
                            )
                          : _ApercuRiche(
                              conversation: c,
                              monId: ref.read(meshRepositoryProvider).myId,
                              // Non lu : l'aperçu passe au gris foncé — on
                              // devine qu'il reste à lire avant même de
                              // voir le compteur.
                              style: OuroTypography.subheadline.copyWith(
                                color: unread
                                    ? OuroColors.label.withValues(alpha: 0.78)
                                    : OuroColors.secondaryLabel,
                                height: 1.25,
                              ),
                            ),
                    ),
                    _MarquesLigne(conversation: c),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );

    final l10n = AppLocalizations.of(context);
    return GlissementActions(
      // ── LES GESTES D'iOS ─────────────────────────────────────────
      //
      // À gauche (on tire vers la droite) : épingler — l'action qu'on
      // fait le plus souvent, donc du côté du pouce.
      // À droite : couper le son, puis archiver. La première de cette
      // liste est celle que déclenche un balayage complet, et c'est
      // l'archivage : le geste franc, celui de Mail.
      debut: [
        ActionGlissee(
          icone: c.isPinned
              ? Icons.push_pin_outlined
              : Icons.push_pin_rounded,
          libelle: c.isPinned ? l10n.swipeUnpin : l10n.swipePin,
          couleur: OuroColors.systemOrange,
          onTap: widget.onPin,
        ),
      ],
      fin: [
        ActionGlissee(
          icone: Icons.archive_rounded,
          libelle: l10n.swipeArchive,
          couleur: OuroColors.systemGray,
          onTap: widget.onArchive,
        ),
        ActionGlissee(
          icone: c.isMuted
              ? Icons.notifications_active_rounded
              : Icons.notifications_off_rounded,
          libelle: c.isMuted ? l10n.swipeUnmute : l10n.swipeMute,
          couleur: OuroColors.systemIndigo,
          onTap: widget.onMute,
        ),
      ],
      child: AnimatedBuilder(
        animation: _arrivee,
        builder: (context, enfant) {
          final t = _arrivee.value;
          // Le glissement se fait dans le premier tiers, l'éclairage
          // s'éteint sur toute la durée.
          final glisse = Curves.easeOutCubic.transform((t * 3).clamp(0.0, 1.0));
          final lueur = 1 - Curves.easeOut.transform(t);
          return ColoredBox(
            color: Color.alphaBlend(
              OuroColors.accent.withValues(alpha: 0.07 * lueur),
              OuroColors.systemBackground,
            ),
            child: Transform.translate(
              offset: Offset(0, -14 * (1 - glisse)),
              child: Opacity(opacity: 0.4 + 0.6 * glisse, child: enfant),
            ),
          );
        },
        child: Column(
          key: _cleLigne,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTapDown: (_) => setState(() => _pressed = true),
              onTapCancel: () => setState(() => _pressed = false),
              onTap: () {
                setState(() => _pressed = false);
                _open();
              },
              onLongPress: _showContextMenu,
              child: row,
            ),
            Padding(
              padding: EdgeInsets.only(left: _textInset),
              child: Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
            ),
          ],
        ),
      ),
    );
  }

  /// L'appui long, comme sur iOS : la ligne se soulève, le reste de
  /// l'écran s'efface derrière un flou, et les actions se posent dessous.
  ///
  /// ⚠️ PAS UNE FEUILLE QUI MONTE DU BAS. C'était le geste d'avant : on
  /// perdait de vue la conversation qu'on venait de désigner, et le menu
  /// ressemblait à celui de n'importe quel autre écran. Ici l'objet reste
  /// sous le doigt — c'est ce qui fait qu'on sait toujours sur quoi on agit.
  /// Effacer une discussion : on prévient d'abord que ça ne concerne que
  /// ce téléphone — sans serveur, personne ne peut retirer ce qui est déjà
  /// arrivé ailleurs.
  Future<void> _confirmerSuppression() async {
    final l10n = AppLocalizations.of(context);
    final c = widget.conversation;
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (context) => CupertinoAlertDialog(
        title: Text(
          l10n.chatsDeleteTitle(ApercuSysteme.localiser(c.pseudo, l10n)),
        ),
        content: Text(l10n.chatsDeleteBody),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.chatsDeleteConfirm),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    OuroHaptics.light();
    ref.read(meshMessagesProvider.notifier).supprimerConversation(
          peerId: c.peerId,
          groupId: c.groupId,
        );
    if (mounted) afficherToast(context, l10n.chatsDeleted);
  }

  /// « Marquer comme non lu » / « Marquer comme lu », comme WhatsApp.
  /// Lue : la marque tombe et les messages non lus sont lus pour de bon.
  Future<void> _basculerNonLue() async {
    final c = widget.conversation;
    if (c.aLire) {
      await StorageService.setConversationMarkedUnread(c.key, false);
      final notifier = ref.read(meshMessagesProvider.notifier);
      if (c.unreadCount > 0) {
        if (c.groupId != null) {
          await notifier.envoyerLecturesGroupe(c.groupId!);
        } else {
          await notifier.sendReadReceipts(c.peerId);
        }
      }
    } else {
      await StorageService.setConversationMarkedUnread(c.key, true);
    }
    MiroirAppareils.revisionEtat.value++;
  }

  void _showContextMenu() {
    final c = widget.conversation;
    final l10n = AppLocalizations.of(context);
    showMessageContextMenu(
      context: context,
      anchorKey: _cleLigne,
      // ⚠️ L'APERÇU EST UN COUP D'ŒIL DANS LA CONVERSATION, PLUS LA
      // LIGNE. Il montrait la ligne elle-même, reconstruite à
      // l'identique : c'est-à-dire exactement ce qu'on avait sous les
      // yeux une demi-seconde plus tôt, au même endroit. Le geste coûtait
      // une attente pour n'apprendre rien.
      //
      // Chez Apple, l'aperçu d'un menu contextuel est un coup d'œil DANS
      // la destination, et le toucher y emmène. C'est ce que fait
      // WhatsApp sur iOS depuis des années sur cette liste précisément.
      preview: ApercuConversation(
        pseudo: ApercuSysteme.localiser(c.pseudo, l10n),
        // ⚠️ ON TESTE `groupId`, PAS `isGroup`. `isGroup` se déduit du
        // TYPE de la conversation, pas de la présence de l'identifiant :
        // un `c.groupId!` planterait sur un appui long si les deux
        // venaient à diverger, et une exception dans un geste aussi
        // courant est le pire endroit pour en avoir une.
        messages: c.groupId != null
            ? ref.read(groupMessagesProvider(c.groupId!))
            : ref.read(conversationMessagesProvider(c.peerId)),
        monId: ref.read(meshRepositoryProvider).myId,
        peerId: c.peerId,
        groupId: c.groupId,
        estGroupe: c.isGroup,
        enLigne: c.isOnline,
      ),
      previewHeight: kHauteurApercuConversation,
      // Toucher l'aperçu ouvre la conversation : c'est la moitié du
      // geste, et sans elle on a montré la destination sans y conduire.
      onPreviewTap: _open,
      mine: false,
      current: const [],
      onReact: (_) {},
      avecReactions: false,
      actions: [
        MessageAction(
          icon: c.isPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
          label: c.isPinned ? l10n.swipeUnpin : l10n.swipePin,
          onTap: widget.onPin,
        ),
        MessageAction(
          icon: c.isMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
          label: c.isMuted ? l10n.swipeUnmute : l10n.swipeMute,
          onTap: widget.onMute,
        ),
        MessageAction(
          icon: c.aLire ? Icons.mark_chat_read_outlined : Icons.mark_chat_unread_outlined,
          label: c.aLire ? l10n.chatsMarkRead : l10n.chatsMarkUnread,
          onTap: _basculerNonLue,
        ),
        MessageAction(
          icon: Icons.archive_rounded,
          label: l10n.chatsArchive,
          onTap: widget.onArchive,
        ),
        MessageAction(
          icon: Icons.delete_outline_rounded,
          label: l10n.chatsDelete,
          destructive: true,
          onTap: _confirmerSuppression,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  STATUTS
// ─────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────
//  DIVERS
// ─────────────────────────────────────────────────────────────

/// Ligne d'accès aux conversations archivées, façon Messages iOS.
/// L'assistant, présenté comme une conversation épinglée en tête de liste.
///
/// L'aperçu reprend le dernier échange enregistré par l'écran de
/// l'assistant (`ai_chat_screen.dart`, clé `ai_chat_historique`) ; à défaut,
/// une invitation à poser une question.
class _AssistantPinnedRow extends StatelessWidget {
  const _AssistantPinnedRow({required this.onTap});

  final VoidCallback onTap;

  /// Même diamètre que l'avatar d'une vraie discussion.
  static const double _taille = 52;

  /// Le dernier VRAI message de la conversation avec l'assistant.
  ///
  /// ⚠️ JAMAIS UNE ERREUR. « Désolé, une erreur s'est produite » devenait
  /// l'aperçu de la ligne — la première chose qu'on lisait de l'assistant
  /// en ouvrant Droplet, et en espagnol si l'erreur était survenue en
  /// espagnol. On saute les messages marqués comme erreurs (`'e'`), et,
  /// pour les historiques d'avant ce marquage, ceux dont le texte est la
  /// phrase d'erreur dans l'une des dix langues.
  static String? _dernierEchange() {
    final brut = StorageService.getString('ai_chat_historique');
    if (brut == null || brut.isEmpty) return null;
    final phrasesErreur = {
      for (final l in kSupportedLocales) lookupAppLocalizations(l).aiGenericError,
    };
    try {
      final liste = jsonDecode(brut) as List<dynamic>;
      for (final e in liste.reversed) {
        final m = e as Map<String, dynamic>;
        if (m['e'] == true) continue;
        final t = (m['t'] as String? ?? '').trim();
        if (t.isEmpty || phrasesErreur.contains(t)) continue;
        return t.replaceAll(RegExp(r'\s+'), ' ');
      }
    } catch (_) {
      // Historique illisible : on retombe sur l'invitation.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final apercu = _dernierEchange() ?? l10n.aiAskQuestion;
    // L'heure du dernier échange, notée par `ai_chat_screen.dart` à chaque
    // sauvegarde. Absente (historique d'une version précédente) : on n'en
    // invente pas.
    final ms = int.tryParse(StorageService.getString('ai_chat_quand') ?? '');
    final quand = ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    return Semantics(
      button: true,
      label: '${l10n.chatsAssistant}, ${l10n.chatsFilterPinned}',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: DesignTokens.screenMargin,
                vertical: DesignTokens.space2,
              ),
              child: ConstrainedBox(
                // La hauteur d'une ligne de discussion (voir
                // `_ConversationRow`) : la première ligne de la liste ne
                // doit pas être plus haute que les suivantes.
                constraints: BoxConstraints(
                  minHeight: (ReglagesApparence.lignesListe - 1 >= 2 ? 76 : 64) -
                      2 * DesignTokens.space2,
                ),
                child: Row(
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: assistantEcrit,
                    builder: (context, ecrit, _) =>
                        AvatarAssistant(taille: _taille, actif: ecrit),
                  ),
                  const SizedBox(width: DesignTokens.space3),
                  // ⚠️ LA MÊME GRILLE QU'UNE VRAIE DISCUSSION. L'aperçu
                  // tenait sur DEUX lignes ici et sur UNE ailleurs, l'épingle
                  // collait au nom, et il n'y avait pas d'heure : la première
                  // ligne de la liste était la seule à ne ressembler à aucune
                  // autre.
                  Expanded(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                l10n.chatsAssistant,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OuroTypography.headline.copyWith(color: OuroColors.label),
                              ),
                            ),
                            if (quand != null) ...[
                              const SizedBox(width: 8),
                              Text(
                                formatMessageTime(
                                  quand,
                                  langue: Localizations.localeOf(context).toLanguageTag(),
                                  hier: l10n.chYesterday,
                                ),
                                maxLines: 1,
                                style: OuroTypography.caption1.copyWith(
                                  color: OuroColors.secondaryLabel,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                apercu,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: OuroTypography.subheadline.copyWith(
                                  color: OuroColors.secondaryLabel,
                                  height: 1.25,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Transform.rotate(
                              angle: 0.6,
                              child: Icon(
                                Icons.push_pin_rounded,
                                size: 15,
                                color: OuroColors.tertiaryLabel,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              ),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.only(
                start: DesignTokens.screenMargin + _taille + DesignTokens.space3,
              ),
              child: Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArchivedRow extends StatelessWidget {
  const _ArchivedRow({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.screenMargin,
              vertical: 11,
            ),
            child: Row(
              children: [
                // ⚠️ LA LARGEUR DE LA COLONNE DES AVATARS, PAS 24. Le mot
                // « Archivées » commençait 40 points plus à gauche que les
                // noms juste dessous, et son séparateur partait du bord :
                // deux grilles dans la même liste. Ici l'icône est centrée
                // dans la colonne des photos, et le texte s'aligne sur les
                // noms.
                //
                // ⚠️ ET GRISE, PAS ROUGE. Une icône rouge sur une ligne de
                // rangement criait plus fort que les conversations elles-
                // mêmes — et le cadenas voisin, lui, était gris.
                SizedBox(
                  width: _ConversationRowState._avatarSize,
                  child: Icon(Icons.archive_outlined, size: 22, color: OuroColors.secondaryLabel),
                ),
                const SizedBox(width: DesignTokens.space3),
                Expanded(
                  child: Text(
                    l10n.chatsArchivedTitle,
                    style: OuroTypography.body.copyWith(color: OuroColors.label),
                  ),
                ),
                Text(
                  '$count',
                  style: OuroTypography.body.copyWith(color: OuroColors.secondaryLabel),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: OuroColors.quaternaryLabel),
              ],
            ),
          ),
          // Le séparateur part de la colonne des noms, comme celui des
          // conversations.
          Padding(
            padding: EdgeInsets.only(left: _ConversationRowState._textInset),
            child: Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
          ),
        ],
      ),
    );
  }
}

/// Le point d'entrée vers les conversations verrouillées — même
/// disposition que [_ArchivedRow], mais l'icône dit ce qui est différent :
/// ce n'est pas un tiroir de rangement, c'est un coffre.
class _LockedChatsRow extends StatelessWidget {
  const _LockedChatsRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: DesignTokens.screenMargin,
              vertical: 11,
            ),
            child: Row(
              children: [
                // Même colonne et même gris que la ligne des archives.
                SizedBox(
                  width: _ConversationRowState._avatarSize,
                  child: Icon(
                    Icons.lock_outline_rounded,
                    size: 22,
                    color: OuroColors.secondaryLabel,
                  ),
                ),
                const SizedBox(width: DesignTokens.space3),
                Expanded(
                  child: Text(
                    l10n.chatsLockedTitle,
                    style: OuroTypography.body.copyWith(color: OuroColors.label),
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 18, color: OuroColors.quaternaryLabel),
              ],
            ),
          ),
          // Le séparateur part de la colonne des noms, comme celui des
          // conversations.
          Padding(
            padding: EdgeInsets.only(left: _ConversationRowState._textInset),
            child: Divider(height: 0.5, thickness: 0.5, color: OuroColors.separator),
          ),
        ],
      ),
    );
  }
}

/// Une action dans une feuille modale.
class _SheetAction extends StatelessWidget {
  const _SheetAction({required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? OuroColors.label;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 56,
        alignment: Alignment.centerLeft,
        child: Row(
          children: [
            Icon(icon, color: c, size: DesignTokens.iconLg),
            const SizedBox(width: DesignTokens.space3),
            Text(label, style: OuroTypography.body.copyWith(color: c)),
          ],
        ),
      ),
    );
  }
}

/// État vide de la liste des conversations.
class _EmptyChats extends StatelessWidget {
  const _EmptyChats({
    super.key,
    required this.searching,
    this.filtre = FiltreChats.toutes,
  });
  final bool searching;

  /// ⚠️ UN FILTRE VIDE N'EST PAS UNE LISTE VIDE. « Non lues » sans rien
  /// de non lu affichait « Aucune conversation » — alors qu'il y en avait
  /// dix, toutes lues. C'est une bonne nouvelle, et il faut la dire comme
  /// telle.
  final FiltreChats filtre;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    if (!searching && filtre != FiltreChats.toutes) {
      final (titre, texte, icone) = switch (filtre) {
        FiltreChats.nonLues => (
            l10n.cfEmptyUnreadTitle,
            l10n.cfEmptyUnreadBody,
            Icons.mark_chat_read_outlined,
          ),
        FiltreChats.groupes => (
            l10n.cfEmptyGroupsTitle,
            l10n.cfEmptyGroupsBody,
            Icons.group_outlined,
          ),
        _ => (l10n.cfEmptyOtherTitle, null, Icons.filter_list_rounded),
      };
      return Padding(
        padding: const EdgeInsets.fromLTRB(40, 56, 40, DesignTokens.space16 + 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, size: 44, color: OuroColors.tertiaryLabel),
            const SizedBox(height: DesignTokens.space3),
            Text(
              titre,
              textAlign: TextAlign.center,
              style: OuroTypography.headline.copyWith(color: OuroColors.label),
            ),
            if (texte != null) ...[
              const SizedBox(height: 6),
              Text(
                texte,
                textAlign: TextAlign.center,
                style: OuroTypography.subheadline.copyWith(
                  color: OuroColors.secondaryLabel,
                ),
              ),
            ],
          ],
        ),
      );
    }
    return Padding(
      // La barre flottante mange le bas de l'écran : on lui laisse sa
      // place plutôt que de couper la dernière conversation.
      padding: const EdgeInsets.only(bottom: DesignTokens.space16 + 40),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: DesignTokens.space8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Une scène animée plutôt qu'une icône figée. L'écran vide
              // est le moment où l'utilisateur se demande s'il a raté
              // quelque chose ; un mouvement doux répond que non.
              SceneAnimee(
                emoji: searching ? Scenes.aucunResultat : Scenes.aucuneConversation,
                iconeDeSecours: searching ? Icons.search_off_rounded : Icons.forum_outlined,
                taille: 92,
              ),
              const SizedBox(height: DesignTokens.space4),
              Text(
                searching ? l10n.chatsSearchEmptyTitle : l10n.chatsEmptyTitle,
                textAlign: TextAlign.center,
                style: OuroTypography.title3.copyWith(color: OuroColors.label),
              ),
              const SizedBox(height: DesignTokens.space2),
              Text(
                searching ? l10n.chatsSearchEmptySubtitle : l10n.chatsEmptySubtitle,
                textAlign: TextAlign.center,
                style: OuroTypography.subheadline.copyWith(color: OuroColors.secondaryLabel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Feuille listant les conversations archivées.
class _ArchivedSheet extends ConsumerWidget {
  const _ArchivedSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final archived = ref.watch(archivedConversationsProvider);
    final l10n = AppLocalizations.of(context);
    return FrostedSheet(
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.chatsArchivedTitle,
              style: OuroTypography.title2.copyWith(color: OuroColors.label),
            ),
            const SizedBox(height: DesignTokens.space3),
            if (archived.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DesignTokens.space5),
                child: Column(
                  children: [
                    SceneAnimee(
                      emoji: Scenes.aucunResultat,
                      iconeDeSecours: Icons.archive_outlined,
                      taille: 54,
                    ),
                    const SizedBox(height: DesignTokens.space2),
                    Text(
                      l10n.chatsNoArchived,
                      style: OuroTypography.subheadline.copyWith(color: OuroColors.secondaryLabel),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: archived.length,
                  itemBuilder: (context, i) {
                    final c = archived[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: DesignTokens.space2),
                      // Enfoncement iOS plutôt que l'onde de Material —
                      // c'est la même liste de conversations que dans
                      // l'écran principal, elle doit répondre pareil.
                      child: OuroPressable(
                        onTap: () {
                          Navigator.of(context).pop();
                          if (c.peerId != null) {
                            context.push('/chat/${c.peerId}');
                          } else if (c.groupId != null) {
                            context.push('/group/${c.groupId}');
                          }
                        },
                        child: Row(
                          children: [
                            PeerAvatar(
                              pseudo: c.pseudo,
                              radius: 20,
                              imagePath: AvatarService.cheminPair(c.peerId),
                            ),
                            const SizedBox(width: DesignTokens.space3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.pseudo,
                                    style: OuroTypography.body.copyWith(color: OuroColors.label),
                                  ),
                                  Text(
                                    c.lastMessage,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: OuroTypography.footnote.copyWith(
                                      color: OuroColors.secondaryLabel,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            OuroRetourIos(child: TextButton(
                              onPressed: () async {
                                OuroHaptics.medium();
                                await StorageService.setConversationArchived(c.key, false);
                                ref.read(archivedRevisionProvider.notifier).state++;
                              },
                              child: Text(l10n.chatsUnarchive),
                            )),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// La feuille des conversations verrouillées — n'apparaît qu'APRÈS que
/// `_openLocked` a validé la biométrie.
///
/// ⚠️ CONTRAIREMENT À `_ArchivedSheet`, RIEN N'EST MASQUÉ ICI.
/// L'utilisateur vient de s'authentifier pour voir CETTE liste ; afficher
/// « Discussion verrouillée » à la place de l'aperçu serait cacher un
/// contenu déjà déverrouillé, ce qui ne protège rien et rend la feuille
/// inutile pour retrouver une conversation précise. Le masquage de
/// `conversationsProvider` reste, lui, nécessaire : LUI est visible sans
/// authentification.
class _LockedChatsSheet extends ConsumerWidget {
  const _LockedChatsSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(lockedConversationsProvider);
    final l10n = AppLocalizations.of(context);
    return FrostedSheet(
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.chatsLockedTitle,
              style: OuroTypography.title2.copyWith(color: OuroColors.label),
            ),
            const SizedBox(height: DesignTokens.space3),
            if (locked.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: DesignTokens.space5),
                child: Column(
                  children: [
                    SceneAnimee(
                      emoji: Scenes.aucunResultat,
                      iconeDeSecours: Icons.lock_outline_rounded,
                      taille: 54,
                    ),
                    const SizedBox(height: DesignTokens.space2),
                    Text(
                      l10n.chatsNoLocked,
                      style: OuroTypography.subheadline.copyWith(color: OuroColors.secondaryLabel),
                    ),
                  ],
                ),
              )
            else
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.5),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: locked.length,
                  itemBuilder: (context, i) {
                    final c = locked[i];
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: DesignTokens.space2),
                      child: OuroPressable(
                        onTap: () {
                          Navigator.of(context).pop();
                          // ⚠️ ENTRER OUVRE `ChatScreen` NORMALEMENT — qui
                          // affichera À SON TOUR `ConversationLockScreen`
                          // (biométrie n°2, sur le CONTENU cette fois).
                          // Voir la note en tête de cette classe.
                          if (c.peerId != null) {
                            context.push('/chat/${c.peerId}');
                          } else if (c.groupId != null) {
                            context.push('/group/${c.groupId}');
                          }
                        },
                        child: Row(
                          children: [
                            PeerAvatar(
                              pseudo: c.pseudo,
                              radius: 20,
                              imagePath: AvatarService.cheminPair(c.peerId),
                            ),
                            const SizedBox(width: DesignTokens.space3),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    c.pseudo,
                                    style: OuroTypography.body.copyWith(color: OuroColors.label),
                                  ),
                                  Text(
                                    c.lastMessage,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: OuroTypography.footnote.copyWith(
                                      color: OuroColors.secondaryLabel,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 18,
                              color: OuroColors.quaternaryLabel,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────
///  NOTIFICATION MESH FLOTTANTE
/// ─────────────────────────────────────────────────────────────
///
/// Bulle flottante en haut de l'écran d'accueil qui montre le dernier
/// message reçu du mesh, avec un mini avatar et un preview. Pas de push
/// notification classique — c'est un élément in-app qui apparaît quand
/// un message arrive pendant qu'on est sur l'écran d'accueil.
///
/// L'animation est un slide-in par le haut avec un léger bounce, puis
/// un slide-out après 4 secondes ou au tap.
class _MeshNotificationBanner extends StatefulWidget {
  const _MeshNotificationBanner({required this.conversations});

  final List<Conversation> conversations;

  @override
  State<_MeshNotificationBanner> createState() => _MeshNotificationBannerState();
}

class _MeshNotificationBannerState extends State<_MeshNotificationBanner>
    with SingleTickerProviderStateMixin {
  AnimationController? _ctrl;
  Animation<Offset>? _slideAnim;
  Conversation? _lastUnread;
  bool _dismissed = false;

  @override
  void didUpdateWidget(_MeshNotificationBanner old) {
    super.didUpdateWidget(old);
    _checkForNewMessage();
  }

  void _checkForNewMessage() {
    if (_dismissed) return;
    // Trouver la conversation avec le dernier message non lu
    final unread = widget.conversations.where((c) => c.unreadCount > 0).toList()
      ..sort((a, b) => b.lastTimestamp.compareTo(a.lastTimestamp));

    if (unread.isEmpty) {
      if (_ctrl?.isAnimating == true) _dismiss();
      return;
    }

    final latest = unread.first;
    // Si c'est un nouveau message non lu qu'on n'affichait pas
    if (_lastUnread?.key != latest.key) {
      _lastUnread = latest;
      _show(latest);
    }
  }

  void _show(Conversation conv) {
    _dismissed = false;
    _ctrl?.dispose();
    _ctrl = AnimationController(
      vsync: this,
      // 350 ms : la durée de référence des transitions iOS. Les 500 ms
      // d'origine servaient à laisser le rebond se terminer ; sans rebond,
      // elles ne font plus qu'attendre.
      duration: DesignTokens.durationStandard,
    );
    _slideAnim = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _ctrl!,
        // ⚠️ C'ÉTAIT `Curves.elasticOut`. Une bannière de message non lu qui
        // rebondit en descendant du haut est exactement ce que
        // `design_tokens.dart` interdit : elle dépasse sa position finale,
        // revient, et retarde de plusieurs dixièmes de seconde la lecture du
        // message — à chaque message, toute la journée. iOS ne fait jamais
        // rebondir une notification.
        curve: DesignTokens.curveEnter,
      ),
    );
    _ctrl!.forward();
    // Auto-masquer après 4 secondes
    Future.delayed(const Duration(seconds: 4), () {
      if (mounted && !_dismissed) _dismiss();
    });
  }

  void _dismiss() {
    _dismissed = true;
    _ctrl?.reverse().then((_) {
      if (mounted) setState(() => _lastUnread = null);
    });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final conv = _lastUnread;
    if (conv == null || _ctrl == null || _slideAnim == null) {
      return const SizedBox.shrink();
    }

    return SlideTransition(
      position: _slideAnim!,
      child: GestureDetector(
        onTap: () {
          _dismiss();
          // Même construction de route que la ligne de conversation
          // normale (voir `_ChatRowState._ouvrir` plus haut) — un tap
          // sur la bannière doit ouvrir EXACTEMENT la même conversation
          // qu'un tap sur sa ligne dans la liste.
          final route = conv.isGroup
              ? '/group/${conv.groupId}'
              : conv.isBroadcast
              ? '/chat/broadcast'
              : '/chat/${conv.peerId}';
          context.push(route);
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: OuroColors.systemBackground.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.15),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              PeerAvatar(
                pseudo: conv.pseudo,
                radius: 18,
                imagePath: AvatarService.cheminPair(conv.peerId),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      conv.pseudo,
                      style: OuroTypography.subheadline.copyWith(
                        color: OuroColors.label,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      conv.lastMessage,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OuroTypography.footnote.copyWith(color: OuroColors.secondaryLabel),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: OuroColors.accentRempli,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: OuroCompteur(valeur: conv.unreadCount, style: TextStyle(
                    color: OuroColors.texteSurAccent,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// La ligne sous « Discussions » : combien de pairs à portée, et si Internet
/// est là aussi.
String _sousTitreReseau(AppLocalizations l10n, int pairs, bool internet) {
  return switch (etatReseauGlobal(pairs: pairs, internet: internet)) {
    EtatReseauGlobal.meshEtInternet => l10n.chatsNetMeshInternet(pairs),
    EtatReseauGlobal.meshSeul => l10n.chatsNetMeshOnly(pairs),
    EtatReseauGlobal.internetSeul => l10n.chatsNetInternetOnly,
    // « Recherche d'appareils proches… » plutôt que « Recherche de
    // pairs… » : « pair » est le mot de l'ingénieur réseau, pas celui de
    // la personne qui tient le téléphone.
    EtatReseauGlobal.aucun => l10n.chatsNetSearching,
  };
}

/// Un message trouvé par la recherche : sa conversation, l'extrait avec le
/// mot cherché en évidence, et l'heure. Le toucher ouvre la conversation.
class _ResultatMessage extends StatelessWidget {
  const _ResultatMessage({required this.message, required this.requete, required this.moi});

  final MeshMessage message;
  final String requete;
  final String moi;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final groupe = m.groupId == null ? null : StorageService.getGroup(m.groupId!);
    final autre = m.senderId == moi ? m.targetId : m.senderId;
    final titre =
        groupe?.name ??
        (autre == null
            ? m.authorPseudo
            : StorageService.getPeerRecord(autre)?.pseudo ?? m.authorPseudo);
    final route = groupe != null ? '/group/${groupe.id}' : (autre == null ? null : '/chat/$autre');

    return ListTile(
      onTap: route == null
          ? null
          : () {
              OuroHaptics.selection();
              context.push(route);
            },
      leading: PeerAvatar(
        pseudo: titre,
        radius: 22,
        imagePath: groupe == null ? AvatarService.cheminPair(autre) : null,
      ),
      title: Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: _TexteSurligne(texte: m.content, requete: requete),
      trailing: Text(
        formatMessageTime(
          m.timestamp,
          langue: Localizations.localeOf(context).toLanguageTag(),
          hier: AppLocalizations.of(context).chYesterday,
        ),
        style: OuroTypography.caption1.copyWith(color: OuroColors.tertiaryLabel),
      ),
    );
  }
}

/// L'extrait d'un message, le mot cherché en gras et en couleur.
class _TexteSurligne extends StatelessWidget {
  const _TexteSurligne({required this.texte, required this.requete});

  final String texte;
  final String requete;

  @override
  Widget build(BuildContext context) {
    final base = OuroTypography.subheadline.copyWith(color: OuroColors.secondaryLabel);
    final minuscule = texte.toLowerCase();
    var debut = minuscule.indexOf(requete);
    if (debut < 0 || requete.isEmpty) {
      return Text(texte, maxLines: 2, overflow: TextOverflow.ellipsis, style: base);
    }
    // L'extrait commence un peu avant le mot, pour qu'il soit visible.
    final depart = debut > 30 ? debut - 25 : 0;
    final extrait = (depart > 0 ? '…' : '') + texte.substring(depart);
    debut = debut - depart + (depart > 0 ? 1 : 0);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: extrait.substring(0, debut)),
          TextSpan(
            text: extrait.substring(debut, debut + requete.length),
            style: TextStyle(color: OuroColors.accent, fontWeight: FontWeight.w700),
          ),
          TextSpan(text: extrait.substring(debut + requete.length)),
        ],
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }
}


/// L'anneau de statut autour d'un avatar de la liste.
///
/// Dégradé d'accent tant qu'un statut n'a pas été vu, gris fin ensuite, rien
/// sans statut. Un toucher sur l'avatar ouvre le statut en zoomant depuis
/// l'avatar lui-même ; le reste de la rangée ouvre toujours la discussion.
///
/// L'anneau est PEINT autour de l'avatar, sans le déplacer : une rangée avec
/// anneau garde exactement l'alignement des autres.
class _AnneauStatutDiscussion extends StatelessWidget {
  const _AnneauStatutDiscussion({
    required this.peerId,
    required this.estGroupe,
    required this.child,
  });

  final String peerId;
  final bool estGroupe;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (estGroupe || peerId.isEmpty) return child;
    return ValueListenableBuilder<int>(
      valueListenable: StatutsVus.revision,
      builder: (context, _, _) {
        if (StorageService.isContactBlocked(peerId)) return child;
        final statuts = StorageService.getActiveStatuses()
            .where((s) => s.authorId == peerId)
            .toList();
        if (statuts.isEmpty) return child;
        final nouveau = !StatutsVus.contactVu(statuts);
        // Un arc par statut, comme dans les Actus : les deux écrans
        // racontent la même chose de la même façon.
        final segments = [for (final st in statuts) StatutsVus.estVu(st.id)];
        return Semantics(
          button: true,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              final boite = context.findRenderObject() as RenderBox?;
              if (boite != null && boite.hasSize) {
                StatusPagerScreen.rectCarte = boite.localToGlobal(Offset.zero) & boite.size;
              }
              statutsSeanceReinitialiser(origine: GoRouterState.of(context).uri.toString());
              OuroHaptics.selection();
              context.push('/status/$peerId');
            },
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                child,
                Positioned(
                  left: -3.5,
                  top: -3.5,
                  right: -3.5,
                  bottom: -3.5,
                  child: IgnorePointer(
                    child: AnneauStatuts(
                      segments: segments,
                      epaisseur: 2,
                      ecart: 2.5,
                      couleurNeuf: nouveau ? OuroColors.accent : OuroColors.tertiaryLabel,
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PeintreAnneau extends CustomPainter {
  _PeintreAnneau({required this.nouveau});

  final bool nouveau;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final rayon = size.shortestSide / 2 - 1;
    final trait = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = nouveau ? 2 : 1.2;
    if (nouveau) {
      // L'accent de Droplet qui « coule » autour de l'avatar : un balayage
      // dans la famille de la couleur choisie, jamais une couleur étrangère.
      final accent = OuroColors.accent;
      final hsl = HSLColor.fromColor(accent);
      final voisin = hsl.withHue((hsl.hue + 42) % 360).toColor();
      trait.shader = SweepGradient(
        colors: [accent, voisin, accent],
        transform: const GradientRotation(-1.5708),
      ).createShader(Rect.fromCircle(center: centre, radius: rayon));
    } else {
      trait.color = OuroColors.systemGray3;
    }
    canvas.drawCircle(centre, rayon, trait);
  }

  @override
  bool shouldRepaint(_PeintreAnneau ancien) => ancien.nouveau != nouveau;
}


/// Sous une liste courte : ce que Droplet fait de différent — en une
/// carte qu'on ferme.
///
/// L'emblème d'ondes ne bouge QUE si des appareils sont à portée :
/// l'animation dit « ça se passe autour de vous », elle ne tourne pas pour
/// rien.
class _AstuceProximite extends StatelessWidget {
  const _AstuceProximite({
    required this.proches,
    required this.surVoir,
    required this.surFermer,
  });

  final int proches;
  final VoidCallback surVoir;
  final VoidCallback surFermer;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.screenMargin,
        DesignTokens.space4,
        DesignTokens.screenMargin,
        DesignTokens.space2,
      ),
      child: Material(
        color: OuroColors.quaternarySystemFill,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: surVoir,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _EmblemeOndes(actif: proches > 0, taille: 36),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        proches > 0 ? l10n.chProxActive : l10n.chProxTitle,
                        style: OuroTypography.subheadline.copyWith(
                          color: OuroColors.label,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.chProxBody,
                        style: OuroTypography.footnote.copyWith(
                          color: OuroColors.secondaryLabel,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.chProxSee,
                        style: OuroTypography.footnote.copyWith(
                          color: OuroColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                Semantics(
                  button: true,
                  label: l10n.actionClose,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: surFermer,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: OuroColors.tertiaryLabel,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmblemeOndes extends StatefulWidget {
  const _EmblemeOndes({required this.actif, this.taille = 72});

  final bool actif;
  final double taille;

  @override
  State<_EmblemeOndes> createState() => _EmblemeOndesState();
}

class _EmblemeOndesState extends State<_EmblemeOndes>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ondes = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _majAnimation();
  }

  @override
  void didUpdateWidget(covariant _EmblemeOndes ancien) {
    super.didUpdateWidget(ancien);
    _majAnimation();
  }

  void _majAnimation() {
    final anime = widget.actif && !MediaQuery.disableAnimationsOf(context);
    if (anime && !_ondes.isAnimating) _ondes.repeat();
    if (!anime && _ondes.isAnimating) _ondes.stop();
  }

  @override
  void dispose() {
    _ondes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.taille,
      height: widget.taille,
      child: RepaintBoundary(
        child: CustomPaint(
          painter: _PeintreOndes(progression: _ondes, couleur: OuroColors.accent),
        ),
      ),
    );
  }
}

class _PeintreOndes extends CustomPainter {
  _PeintreOndes({required this.progression, required this.couleur})
      : super(repaint: progression);

  final Animation<double> progression;
  final Color couleur;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    canvas.drawCircle(centre, r * 0.15, Paint()..color = couleur);
    for (var i = 0; i < 3; i++) {
      final t = (progression.value + i / 3) % 1.0;
      canvas.drawCircle(
        centre,
        r * (0.24 + 0.76 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = couleur.withValues(alpha: (1 - t) * 0.55),
      );
    }
  }

  @override
  bool shouldRepaint(_PeintreOndes ancien) => ancien.couleur != couleur;
}


/// Les ronds qui s'échappent de l'icône des ondes, dans l'en-tête.
///
/// Deux cercles seulement, très pâles, de la couleur de l'icône : on doit
/// sentir que « ça vit autour », pas voir une animation. Rien ne tourne
/// quand personne n'est à portée, ni quand le système demande de réduire les
/// animations.
class _OndesEnTete extends StatefulWidget {
  const _OndesEnTete({required this.actif});

  final bool actif;

  @override
  State<_OndesEnTete> createState() => _OndesEnTeteState();
}

class _OndesEnTeteState extends State<_OndesEnTete>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ondes = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maj();
  }

  @override
  void didUpdateWidget(covariant _OndesEnTete ancien) {
    super.didUpdateWidget(ancien);
    _maj();
  }

  void _maj() {
    final anime = widget.actif && !MediaQuery.disableAnimationsOf(context);
    if (anime && !_ondes.isAnimating) _ondes.repeat();
    if (!anime && _ondes.isAnimating) {
      _ondes
        ..stop()
        ..value = 0;
    }
  }

  @override
  void dispose() {
    _ondes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.actif) return const SizedBox.shrink();
    return RepaintBoundary(
      child: CustomPaint(
        // De l'encre de l'icône, comme elle — voir l'en-tête de l'écran.
        painter: _PeintreOndesEnTete(progression: _ondes, couleur: OuroColors.label),
      ),
    );
  }
}

class _PeintreOndesEnTete extends CustomPainter {
  _PeintreOndesEnTete({required this.progression, required this.couleur})
      : super(repaint: progression);

  final Animation<double> progression;
  final Color couleur;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    for (var i = 0; i < 2; i++) {
      final t = (progression.value + i / 2) % 1.0;
      canvas.drawCircle(
        centre,
        r * (0.42 + 0.58 * t),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = couleur.withValues(alpha: (1 - t) * 0.32),
      );
    }
  }

  @override
  bool shouldRepaint(_PeintreOndesEnTete ancien) => ancien.couleur != couleur;
}


/// Le petit repère devant « Personne à proximité · Internet ».
///
/// Immobile : c'est l'icône des ondes, en haut, qui vit quand quelqu'un est
/// à portée. Deux animations pour le même état, ce serait du bruit.
///
/// ⚠️ CE POINT-CI GARDE SA PROPRE LANGUE, ET C'EST VOULU. Il ne dit pas la
/// présence de QUELQU'UN mais l'état de MA connexion : bleu Droplet quand
/// le maillage relie quelqu'un, vert quand seul Internet répond. Les trois
/// couleurs de `FraicheurPair` sont réservées aux contacts — les appliquer
/// ici ferait dire à un point « cette personne est là » alors qu'il parle
/// de mon téléphone. À ne pas « harmoniser » par mégarde.
class _PointReseau extends StatelessWidget {
  const _PointReseau({required this.pairs, required this.internet});

  final int pairs;
  final bool internet;

  @override
  Widget build(BuildContext context) {
    final maillage = pairs > 0;
    final couleur = maillage
        ? OuroColors.accent
        : internet
            ? OuroColors.systemGreen
            : OuroColors.tertiaryLabel;
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: maillage || internet ? couleur : null,
        border: maillage || internet ? null : Border.all(color: couleur, width: 1.5),
      ),
    );
  }
}

/// L'aperçu d'un message, avec un pictogramme sobre à la place de l'émoji
/// de tête (🎤, 📷, 🎥…). Les émojis en couleur, au milieu d'une ligne
/// grise, attiraient l'œil plus que le nom de la personne ; le pictogramme
/// prend la couleur du texte. Un émoji tapé par quelqu'un, lui, reste tel quel.
class _ApercuAvecPictogramme extends StatelessWidget {
  const _ApercuAvecPictogramme({
    required this.texte,
    required this.style,
    required this.maxLines,
  });

  final String texte;
  final TextStyle style;
  final int maxLines;

  static const Map<String, IconData> _pictos = {
    '🎤': Icons.mic_rounded,
    '🎙': Icons.mic_rounded,
    '📷': Icons.photo_camera_rounded,
    '🖼': Icons.image_rounded,
    '🎥': Icons.videocam_rounded,
    '📹': Icons.videocam_rounded,
    '📎': Icons.attach_file_rounded,
    '📄': Icons.description_rounded,
    '📍': Icons.location_on_rounded,
    '📊': Icons.bar_chart_rounded,
    '🎵': Icons.music_note_rounded,
    '🎞': Icons.emoji_emotions_outlined,
    '👤': Icons.person_rounded,
  };

  @override
  Widget build(BuildContext context) {
    final t = texte.trimLeft();
    for (final entree in _pictos.entries) {
      if (!t.startsWith(entree.key)) continue;
      var reste = t.substring(entree.key.length);
      if (reste.startsWith('\uFE0F')) reste = reste.substring(1);
      reste = reste.trimLeft();
      return Text.rich(
        TextSpan(
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(end: 4),
                child: Icon(
                  entree.value,
                  size: (style.fontSize ?? 15) * 1.05,
                  color: style.color,
                ),
              ),
            ),
            TextSpan(text: reste),
          ],
        ),
        maxLines: maxLines,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Text(texte, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
  }
}

/// L'aperçu d'une ligne, riche quand il y a de quoi : brouillon en rouge,
/// coches de mon dernier message, forme d'onde d'un vocal, vignette d'une
/// photo, petit plan d'une position.
///
/// ⚠️ TOUT TIENT SUR UNE LIGNE ET À LA HAUTEUR DU TEXTE. Une vignette plus
/// haute que le texte rendrait cette ligne plus haute que ses voisines —
/// exactement le défaut qu'on vient de corriger. Tout est donc dessiné à
/// 18 points, la hauteur d'une ligne de `subheadline`.
class _ApercuRiche extends StatelessWidget {
  const _ApercuRiche({
    required this.conversation,
    required this.monId,
    required this.style,
  });

  final Conversation conversation;
  final String monId;
  final TextStyle style;

  static const double _h = 18;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = conversation;
    return ValueListenableBuilder<int>(
      valueListenable: Brouillons.revision,
      builder: (context, _, _) {
        // ── 1. LE BROUILLON PASSE DEVANT TOUT ─────────────────────────
        final brouillon = c.isLocked ? null : Brouillons.lire(c.key);
        if (brouillon != null) {
          return Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${l10n.chDraftLabel} ',
                  style: TextStyle(
                    color: OuroColors.systemRed,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: brouillon.replaceAll(RegExp(r'\s+'), ' ')),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }

        final m = c.dernier;
        final texte = isStickerMessage(c.lastMessage)
            ? '🎞 ${l10n.chStickerPreview}'
            : ApercuSysteme.localiser(c.lastMessage, l10n);
        if (m == null) {
          return _ApercuAvecPictogramme(texte: texte, style: style, maxLines: 1);
        }

        final deMoi = m.senderId == monId;
        // Dans un groupe, qui parle — le fournisseur l'écrit déjà dans
        // `lastMessage` (« ~ Nico: … »), mais un aperçu riche le recompose.
        final auteur = (c.isGroup && !deMoi && m.authorPseudo.trim().isNotEmpty)
            ? '${m.authorPseudo}: '
            : null;

        final debut = <Widget>[
          if (deMoi) ...[_Coches(message: m, taille: _h - 2), const SizedBox(width: 3)],
          if (auteur != null)
            Text(auteur, maxLines: 1, style: style.copyWith(fontWeight: FontWeight.w600)),
        ];

        Widget ligne(List<Widget> riche, String? suite) => Row(
              children: [
                ...debut,
                ...riche,
                if (suite != null)
                  Flexible(
                    child: Text(
                      suite,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: style,
                    ),
                  ),
              ],
            );

        // ── 2. UN VOCAL : SA FORME D'ONDE ─────────────────────────────
        final vocal = m.type == 'file' ? VoiceNoteMeta.tryParse(m.fileName) : null;
        if (vocal != null) {
          final sec = vocal.duration.inSeconds;
          return ligne([
            Icon(Icons.mic_rounded, size: _h - 2, color: style.color),
            const SizedBox(width: 3),
            if (vocal.waveform.isNotEmpty) ...[
              SizedBox(
                width: 38,
                height: _h - 4,
                child: CustomPaint(
                  painter: _PeintreMiniOnde(
                    valeurs: vocal.waveform,
                    couleur: style.color ?? OuroColors.secondaryLabel,
                  ),
                ),
              ),
              const SizedBox(width: 5),
            ],
          ], '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}');
        }

        // ── 3. UNE PHOTO : SA VIGNETTE ────────────────────────────────
        if (m.type == 'file' &&
            mediaKindOf(m.fileMimeType, m.fileName) == MediaKind.image &&
            m.fileId != null) {
          final legende = m.content.trim().isNotEmpty && m.content != m.fileName
              ? m.content.trim()
              : l10n.chPhotoLabel;
          return ligne([
            _Vignette(fileId: m.fileId!, fileName: m.fileName ?? '', cote: _h),
            const SizedBox(width: 5),
          ], legende);
        }

        // ── 4. UNE POSITION : UN PETIT PLAN ───────────────────────────
        if (LocationMessage.tryParse(m.content) != null) {
          return ligne([
            const _MiniPlan(cote: _h),
            const SizedBox(width: 5),
          ], l10n.sfLocationShared);
        }

        // ── 5. LE RESTE : LE TEXTE, AVEC SON PICTOGRAMME ──────────────
        //
        // `texte` contient déjà l'auteur dans un groupe (« ~ Nico: … ») :
        // on ne le répète pas.
        return Row(
          children: [
            if (deMoi) ...[_Coches(message: m, taille: _h - 2), const SizedBox(width: 3)],
            Flexible(
              child: _ApercuAvecPictogramme(texte: texte, style: style, maxLines: 1),
            ),
          ],
        );
      },
    );
  }
}

/// Les coches de mon dernier message, comme dans la bulle.
///
/// Horloge : en route. Une coche : parti. Deux grises : reçu. Deux en
/// couleur : lu. Rouge : pas parti.
class _Coches extends StatelessWidget {
  const _Coches({required this.message, required this.taille});

  final MeshMessage message;
  final double taille;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final (icone, couleur) = switch (m.status) {
      MessageStatus.sending || MessageStatus.pending => (
          Icons.schedule_rounded,
          OuroColors.tertiaryLabel,
        ),
      MessageStatus.failed => (Icons.error_outline_rounded, OuroColors.systemRed),
      MessageStatus.sent when m.readAt != null => (
          Icons.done_all_rounded,
          OuroColors.accent,
        ),
      MessageStatus.sent when m.deliveryCount > 0 => (
          Icons.done_all_rounded,
          OuroColors.secondaryLabel,
        ),
      MessageStatus.sent => (Icons.done_rounded, OuroColors.secondaryLabel),
    };
    return Icon(icone, size: taille, color: couleur);
  }
}

class _PeintreMiniOnde extends CustomPainter {
  const _PeintreMiniOnde({required this.valeurs, required this.couleur});

  final List<double> valeurs;
  final Color couleur;

  /// Douze barres : à 38 points de large, c'est ce qui se lit encore comme
  /// une voix et pas comme une texture.
  static const int _barres = 12;

  @override
  void paint(Canvas toile, Size taille) {
    final pas = taille.width / _barres;
    final trait = Paint()
      ..color = couleur
      ..strokeWidth = pas * 0.55
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < _barres; i++) {
      final debut = (i * valeurs.length / _barres).floor();
      final fin = ((i + 1) * valeurs.length / _barres).ceil().clamp(debut + 1, valeurs.length);
      var max = 0.0;
      for (var j = debut; j < fin; j++) {
        if (valeurs[j] > max) max = valeurs[j];
      }
      final h = (0.18 + 0.82 * max.clamp(0.0, 1.0)) * taille.height;
      final x = pas * (i + 0.5);
      toile.drawLine(
        Offset(x, (taille.height - h) / 2),
        Offset(x, (taille.height + h) / 2),
        trait,
      );
    }
  }

  @override
  bool shouldRepaint(_PeintreMiniOnde ancien) =>
      ancien.couleur != couleur || !identical(ancien.valeurs, valeurs);
}

/// La vignette d'une photo reçue ou envoyée.
///
/// ⚠️ LE CHEMIN EST CHERCHÉ UNE FOIS PAR PHOTO, PAS À CHAQUE IMAGE. La
/// liste se redessine sans arrêt (frappe, présence, défilement) ; sans
/// cache, chaque redessin relançait une lecture du disque.
class _Vignette extends StatelessWidget {
  const _Vignette({required this.fileId, required this.fileName, required this.cote});

  final String fileId;
  final String fileName;
  final double cote;

  static final Map<String, Future<String?>> _chemins = {};

  @override
  Widget build(BuildContext context) {
    final futur = _chemins.putIfAbsent(
      fileId,
      () => StorageService.getSharedFilePath(fileId, fileName),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox.square(
        dimension: cote,
        child: FutureBuilder<String?>(
          future: futur,
          builder: (context, instantane) {
            final chemin = instantane.data;
            if (chemin == null) {
              return ColoredBox(
                color: OuroColors.tertiarySystemFill,
                child: Icon(
                  Icons.photo_rounded,
                  size: cote * 0.7,
                  color: OuroColors.secondaryLabel,
                ),
              );
            }
            return Image.file(
              File(chemin),
              fit: BoxFit.cover,
              // Trois fois le côté : net sur un écran très dense, sans
              // décoder une photo de douze mégapixels pour 18 points.
              cacheWidth: (cote * 3).round(),
              errorBuilder: (_, _, _) => ColoredBox(color: OuroColors.tertiarySystemFill),
            );
          },
        ),
      ),
    );
  }
}

/// Un plan miniature : deux rues et une épingle. Pas une vraie carte — à
/// 18 points elle ne serait qu'une tache — mais un dessin qu'on reconnaît
/// comme « un endroit ».
class _MiniPlan extends StatelessWidget {
  const _MiniPlan({required this.cote});

  final double cote;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: cote,
      child: CustomPaint(
        painter: _PeintreMiniPlan(
          fond: OuroColors.systemGreen.withValues(alpha: 0.22),
          rue: OuroColors.systemBackground,
          epingle: OuroColors.systemRed,
        ),
      ),
    );
  }
}

class _PeintreMiniPlan extends CustomPainter {
  const _PeintreMiniPlan({required this.fond, required this.rue, required this.epingle});

  final Color fond;
  final Color rue;
  final Color epingle;

  @override
  void paint(Canvas toile, Size t) {
    final cadre = RRect.fromRectAndRadius(Offset.zero & t, const Radius.circular(4));
    toile
      ..save()
      ..clipRRect(cadre)
      ..drawRRect(cadre, Paint()..color = fond);
    final r = Paint()
      ..color = rue
      ..strokeWidth = t.width * 0.12;
    toile
      ..drawLine(Offset(0, t.height * 0.62), Offset(t.width, t.height * 0.38), r)
      ..drawLine(Offset(t.width * 0.35, 0), Offset(t.width * 0.48, t.height), r)
      ..restore();
    final c = Offset(t.width * 0.62, t.height * 0.4);
    toile
      ..drawCircle(c, t.width * 0.2, Paint()..color = epingle)
      ..drawCircle(c, t.width * 0.08, Paint()..color = rue);
  }

  @override
  bool shouldRepaint(_PeintreMiniPlan ancien) =>
      ancien.fond != fond || ancien.rue != rue || ancien.epingle != epingle;
}

/// Le fond de l'écran des discussions, teinté selon l'heure.
///
/// ⚠️ À PEINE. Une lueur pêche le matin, bleu ciel le jour, rose le soir,
/// indigo la nuit — sur le haut de l'écran seulement, et si légère qu'on
/// la sent plus qu'on ne la voit. Elle ne colore jamais une ligne : les
/// conversations restent sur leur fond, lisibles à toute heure. C'est le
/// genre de détail qu'on ne remarque pas, et qui fait que l'écran paraît
/// vivant plutôt que figé.
class _AmbianceHoraire extends StatelessWidget {
  const _AmbianceHoraire({required this.child});

  final Widget child;

  static Color _teinte(int heure) {
    if (heure >= 5 && heure < 10) return const Color(0xFFFFB37A); // matin
    if (heure >= 10 && heure < 17) return const Color(0xFF8EC5FF); // jour
    if (heure >= 17 && heure < 21) return const Color(0xFFFF8FA3); // soir
    return const Color(0xFF7C83FD); // nuit
  }

  @override
  Widget build(BuildContext context) {
    final fond = OuroColors.systemBackground;
    final teinte = _teinte(DateTime.now().hour)
        .withValues(alpha: OuroColors.isDark ? 0.16 : 0.12);
    return DecoratedBox(
      decoration: BoxDecoration(color: fond),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 320,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [teinte, teinte.withValues(alpha: 0)],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

/// Le résumé de la journée — voir son emplacement dans `build`.
class _ResumeDuJour extends StatefulWidget {
  const _ResumeDuJour({required this.conversations, required this.onVoir});

  final List<Conversation> conversations;
  final VoidCallback onVoir;

  @override
  State<_ResumeDuJour> createState() => _ResumeDuJourState();
}

class _ResumeDuJourState extends State<_ResumeDuJour> {
  static const String _cle = 'resume_jour_range';

  static String _aujourdhui() {
    final t = DateTime.now();
    return '${t.year}-${t.month}-${t.day}';
  }

  /// Rangé pour aujourd'hui ? Lu une fois : le résumé ne doit pas
  /// disparaître parce qu'on a lu un message en passant, seulement quand
  /// on l'a fermé.
  late bool _range = StorageService.getString(_cle) == _aujourdhui();

  /// ⚠️ FIGÉ À L'OUVERTURE. Recalculé à chaque image, le résumé fondrait
  /// sous les yeux au fil de la lecture — « 12 non lus », puis 11, puis
  /// 10 — et l'on ne saurait plus ce qu'il disait en arrivant.
  late final ({int messages, int discussions, int mentions, int appels}) _bilan =
      _calculer();

  ({int messages, int discussions, int mentions, int appels}) _calculer() {
    final nonLues = widget.conversations.where((c) => c.unreadCount > 0);
    final debutJour = DateTime.now().subtract(const Duration(hours: 18));
    return (
      messages: nonLues.fold(0, (t, c) => t + c.unreadCount),
      discussions: nonLues.length,
      mentions: nonLues.where((c) => c.mentionne).length,
      appels: JournalNotifs.instance.entrees
          .where((e) =>
              e.type == TypeEntreeNotif.appelManque &&
              !e.lu &&
              e.quand.isAfter(debutJour))
          .length,
    );
  }

  void _ranger() {
    OuroHaptics.light();
    setState(() => _range = true);
    unawaited(StorageService.setString(_cle, _aujourdhui()));
  }

  @override
  Widget build(BuildContext context) {
    final b = _bilan;
    // Rien à résumer : pas de carte. Un « 0 message » le matin est un bruit.
    if (_range || (b.messages == 0 && b.appels == 0)) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final heure = DateTime.now().hour;
    final salut = heure >= 18 || heure < 4 ? l10n.rsEvening : l10n.rsMorning;
    final morceaux = <String>[
      if (b.messages > 0)
        [
          b.messages == 1 ? l10n.rsUnreadOne : l10n.rsUnreadMany(b.messages),
          b.discussions == 1 ? l10n.rsChatsOne : l10n.rsChatsMany(b.discussions),
        ].join(' '),
      if (b.mentions > 0)
        b.mentions == 1 ? l10n.rsMentionsOne : l10n.rsMentionsMany(b.mentions),
      if (b.appels > 0)
        b.appels == 1 ? l10n.rsMissedOne : l10n.rsMissedMany(b.appels),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        DesignTokens.screenMargin,
        DesignTokens.space1,
        DesignTokens.screenMargin,
        DesignTokens.space3,
      ),
      child: Material(
        color: OuroColors.secondarySystemGroupedBackground,
        borderRadius: BorderRadius.circular(18),
        clipBehavior: Clip.antiAlias,
        elevation: 0,
        child: InkWell(
          onTap: b.messages > 0
              ? () {
                  OuroHaptics.selection();
                  widget.onVoir();
                }
              : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: OuroColors.separator.withValues(alpha: 0.5), width: 0.5),
            ),
            padding: const EdgeInsets.fromLTRB(14, 12, 4, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: OuroColors.accent.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    heure >= 18 || heure < 4
                        ? Icons.nights_stay_rounded
                        : Icons.wb_sunny_rounded,
                    size: 19,
                    color: OuroColors.accent,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        salut,
                        style: OuroTypography.subheadline.copyWith(
                          color: OuroColors.label,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        morceaux.join(' · '),
                        style: OuroTypography.footnote.copyWith(
                          color: OuroColors.secondaryLabel,
                          height: 1.3,
                        ),
                      ),
                      if (b.messages > 0) ...[
                        const SizedBox(height: 6),
                        Text(
                          l10n.rsSeeUnread,
                          style: OuroTypography.footnote.copyWith(
                            color: OuroColors.accent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Semantics(
                  button: true,
                  label: l10n.actionClose,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _ranger,
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Icon(Icons.close_rounded, size: 18, color: OuroColors.tertiaryLabel),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// La carte « avatar vivant » — la photo en grand, et quatre gestes.
class _ApercuProfil extends StatelessWidget {
  const _ApercuProfil({required this.conversation});

  final Conversation conversation;

  static Future<void> ouvrir(BuildContext context, Conversation c) {
    if (c.isBroadcast) return Future.value();
    OuroHaptics.medium();
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      barrierColor: Colors.black.withValues(alpha: 0.35),
      transitionDuration: const Duration(milliseconds: 280),
      pageBuilder: (context, _, _) => _ApercuProfil(conversation: c),
      transitionBuilder: (context, animation, _, enfant) {
        final reduit = MediaQuery.disableAnimationsOf(context);
        final courbe = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutBack,
          reverseCurve: Curves.easeInCubic,
        );
        return Flou(repli: const Color(0x00000000), 
          filter: ui.ImageFilter.blur(
            sigmaX: 14 * animation.value,
            sigmaY: 14 * animation.value,
          ),
          child: FadeTransition(
            opacity: animation,
            child: reduit
                ? enfant
                : ScaleTransition(
                    scale: Tween(begin: 0.86, end: 1.0).animate(courbe),
                    child: enfant,
                  ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = conversation;
    final nom = ApercuSysteme.localiser(c.pseudo, l10n);
    final photo = c.isGroup ? null : AvatarService.cheminPair(c.peerId);
    final aDesStatuts = !c.isGroup &&
        c.peerId != null &&
        StorageService.getActiveStatuses().any((st) => st.authorId == c.peerId);
    final largeur = math.min(MediaQuery.sizeOf(context).width - 80, 300.0);

    // Le routeur est pris AVANT de fermer la carte : après `pop`, son
    // contexte est en train de disparaître.
    final routeur = GoRouter.of(context);
    void aller(String route) {
      Navigator.of(context).pop();
      OuroHaptics.selection();
      routeur.push(route);
    }

    final discussion = c.isGroup ? '/group/${c.groupId}' : '/chat/${c.peerId}';
    final fiche = c.isGroup ? '/group/${c.groupId}/info' : '/chat/${c.peerId}/info';

    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: largeur,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: OuroColors.secondarySystemGroupedBackground,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 40,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: largeur,
                height: largeur,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (photo != null)
                      Image.file(
                        File(photo),
                        fit: BoxFit.cover,
                        cacheWidth: (largeur * 3).round(),
                        errorBuilder: (_, _, _) => _fondInitiales(nom, c),
                      )
                    else
                      _fondInitiales(nom, c),
                    // Le nom en surimpression, sur un dégradé qui le rend
                    // lisible sur n'importe quelle photo.
                    Positioned(
                      left: 0,
                      right: 0,
                      top: 0,
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 26),
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0x80000000), Color(0x00000000)],
                          ),
                        ),
                        child: Text(
                          nom,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OuroTypography.headline.copyWith(color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _ActionProfil(
                      icone: Icons.chat_bubble_rounded,
                      libelle: l10n.pfMessage,
                      onTap: () => aller(discussion),
                    ),
                    if (!c.isGroup)
                      _ActionProfil(
                        icone: Icons.call_rounded,
                        libelle: l10n.pfCall,
                        onTap: () => aller('/call/${c.peerId}'),
                      ),
                    if (aDesStatuts)
                      _ActionProfil(
                        icone: Icons.motion_photos_on_rounded,
                        libelle: l10n.svStatusLabel,
                        onTap: () => aller('/status/${c.peerId}'),
                      ),
                    _ActionProfil(
                      icone: Icons.info_outline_rounded,
                      libelle: l10n.ciInfoTitle,
                      onTap: () => aller(fiche),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _fondInitiales(String nom, Conversation c) {
    if (c.isGroup) {
      return ColoredBox(
        color: OuroColors.tertiarySystemFill,
        child: Center(
          child: AvatarGroupe(
            groupe: StorageService.getGroup(c.groupId ?? ''),
            monId: StorageService.currentUser?.id ?? '',
            rayon: 80,
          ),
        ),
      );
    }
    return ColoredBox(
      color: OuroColors.tertiarySystemFill,
      child: Center(child: PeerAvatar(pseudo: nom, radius: 80)),
    );
  }
}

class _ActionProfil extends StatelessWidget {
  const _ActionProfil({required this.icone, required this.libelle, required this.onTap});

  final IconData icone;
  final String libelle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: libelle,
      excludeSemantics: true,
      child: InkResponse(
        onTap: onTap,
        radius: 32,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Icon(icone, size: 24, color: OuroColors.accent),
        ),
      ),
    );
  }
}

/// Les marques en bas à droite d'une ligne : son coupé, mention, non-lus,
/// épingle — toujours dans cet ordre, toujours au même endroit.
///
/// ⚠️ L'ÉPINGLE EST LA DERNIÈRE, AU BORD. C'est là que WhatsApp et
/// Telegram la mettent, et c'est là que l'œil la cherche ; collée au nom,
/// elle décalait le titre d'une ligne à l'autre.
class _MarquesLigne extends StatelessWidget {
  const _MarquesLigne({required this.conversation});

  final Conversation conversation;

  @override
  Widget build(BuildContext context) {
    final c = conversation;
    final unread = c.unreadCount > 0;
    final marques = <Widget>[
      // Marquée « non lue » à la main : un point, sans nombre.
      if (!unread && c.marqueeNonLue)
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: c.isMuted ? OuroColors.systemGray : OuroColors.accentRempli,
            shape: BoxShape.circle,
          ),
        ),
      if (c.isMuted)
        Icon(Icons.volume_off_rounded, size: 15, color: OuroColors.tertiaryLabel),
      // Une mention non lue passe devant le compte : on veut savoir tout
      // de suite qu'on nous a appelé par notre nom.
      if (c.mentionne)
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: OuroColors.accentRempli,
            shape: BoxShape.circle,
          ),
          child: Text(
            '@',
            style: OuroTypography.caption1.copyWith(
              color: OuroColors.texteSurAccent,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      if (unread)
        Container(
          constraints: const BoxConstraints(minWidth: 20),
          height: 20,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            // En sourdine : gris. Le compte reste là, mais il ne réclame
            // plus d'attention — c'est tout le sens de la sourdine.
            color: c.isMuted ? OuroColors.systemGray : OuroColors.accentRempli,
            borderRadius: BorderRadius.circular(10),
          ),
          child: OuroCompteur(
            valeur: c.unreadCount,
            max: 99,
            style: TextStyle(
              color: c.isMuted ? Colors.white : OuroColors.texteSurAccent,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              height: 1,
            ),
          ),
        ),
      if (c.isPinned)
        Transform.rotate(
          angle: 0.6,
          child: Icon(Icons.push_pin_rounded, size: 15, color: OuroColors.tertiaryLabel),
        ),
    ];
    if (marques.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, m) in marques.indexed) ...[
            if (i > 0) const SizedBox(width: 6),
            m,
          ],
        ],
      ),
    );
  }
}

/// Un nom de discussion lisible d'un coup d'œil.
///
/// Certains groupes s'appellent « Écosystème 🏔🌊🌋🌪🌳🏕🖼 » : la file
/// d'émojis mange la ligne, pousse l'heure vers le bord et ne dit rien de
/// plus que le premier. On garde le premier de chaque rafale, on jette la
/// suite — le vrai nom reste entier, seule la décoration est rabotée.
String titreLisible(String nom) {
  final rafale = RegExp(
    r'([\u{1F000}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}'
    r'\u{3297}\u{3299}\u{303D}\u{00A9}\u{00AE}\u{FE0F}\u{200D}]'
    r'[\u{FE0F}\u{200D}]?\s*){3,}',
    unicode: true,
  );
  return nom
      .replaceAllMapped(rafale, (m) {
        final morceau = m.group(0)!.trim();
        final premier = morceau.runes.take(2).toList();
        return '${String.fromCharCodes(premier)} ';
      })
      .trim();
}
