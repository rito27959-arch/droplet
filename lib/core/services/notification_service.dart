// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est le fichier qui fait apparaître les petites bulles en haut de
// l'écran du téléphone (les « notifications ») quand quelque chose
// d'important se passe dans l'app — même quand Droplet n'est pas ouvert
// à l'écran : « nouveau message », « appel manqué », « ton message n'a
// pas pu être envoyé », « quelqu'un a publié un statut », etc. Exactement
// comme le font WhatsApp, Messenger ou n'importe quelle app de discussion.
//
// Toute la classe est « statique » (pas besoin de créer un objet, on
// appelle directement `NotificationService.showNewMessage(...)` de
// n'importe où dans l'app) — un peu comme un panneau d'affichage public :
// n'importe qui dans l'app peut y accrocher une annonce sans avoir à
// demander la permission à un gardien.
//
// Règle importante respectée partout ici : on n'affiche JAMAIS de
// notification pour quelque chose que l'utilisateur est déjà en train de
// regarder à l'écran (par exemple, un message dans la conversation
// actuellement ouverte) — ce serait comme sonner à la porte de quelqu'un
// qui est déjà en train de te parler face à face.
// ============================================================================

import 'dart:async';
import 'dart:math';
import 'dart:ui' show DartPluginRegistrant;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'reponses_differees.dart';

/// Notifications système Android réelles pour les événements applicatifs
/// (message reçu, appel manqué, envoi échoué, statut/urgence publiés par un
/// pair). Volontairement statique : appelée depuis des couches très
/// différentes (providers Riverpod, repository mesh, UI) sans avoir à faire
/// transiter une instance partout.
/// Ce qu'Android exécute quand on répond alors que l'application est
/// morte.
///
/// ── ⚠️ CETTE FONCTION VIT DANS UN AUTRE MONDE ─────────────────────
///
/// Elle ne tourne PAS dans l'application : Android démarre un isolate
/// séparé qui ne contient qu'elle. Aucune variable statique de
/// `NotificationService` n'y est renseignée, aucun provider n'existe,
/// le maillage n'est pas allumé. Tout ce qu'elle peut faire est écrire
/// sur le disque.
///
/// `@pragma('vm:entry-point')` est OBLIGATOIRE : sans lui, le
/// compilateur de production supprime cette fonction — elle n'est
/// appelée depuis nulle part dans le code Dart — et l'appui sur
/// « Répondre » ne fait plus rien du tout, silencieusement, en release
/// seulement. C'est le genre de défaut qu'on ne voit jamais en
/// développement.
@pragma('vm:entry-point')
Future<void> reponseEnArrierePlan(NotificationResponse r) async {
  if (r.actionId != NotificationService.actionRepondre) return;
  final route = r.payload;
  final texte = r.input?.trim();
  if (route == null || route.isEmpty || texte == null || texte.isEmpty) {
    return;
  }
  // Les greffons ne sont pas branchés d'office dans un isolate
  // secondaire : sans cette ligne, `path_provider` échoue et la
  // réponse est perdue.
  DartPluginRegistrant.ensureInitialized();
  await ReponsesDifferees.ajouter(route, texte);
}

class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static final _rng = Random();

  /// Vrai tant que l'app est au premier plan (mise à jour par
  /// [AppLifecycleObserver] dans main.dart) — on n'affiche jamais de
  /// notification système pour un événement que l'utilisateur est déjà en
  /// train de regarder à l'écran.
  static bool isAppForeground = true;

  /// Conversation actuellement ouverte à l'écran (peerId, groupId, ou
  /// 'broadcast') — mise à jour par ChatScreen. Un message entrant pour
  /// cette conversation précise n'a pas besoin de notification système
  /// même si l'app est au premier plan (l'utilisateur la lit déjà).
  static String? openConversationId;

  /// Conversations archivées — on ne notifie jamais pour elles.
  static Set<String> _archivedConversations = {};

  /// Met à jour l'ensemble des conversations archivées (appelé quand
  /// l'utilisateur archive/désarchive une conversation).
  static void setArchivedConversations(Set<String> keys) {
    _archivedConversations = keys;
  }

  /// Chemin go_router à ouvrir au tap sur une notification, consommé une
  /// fois par main.dart après le premier frame.
  static String? pendingNavigation;
  static void Function(String path)? _onNavigate;

  /// Enregistre la fonction qui sait naviguer dans l'app (fournie par
  /// main.dart) — pour que, quand on tape sur une notification, l'app
  /// sache emmener l'utilisateur directement au bon écran.
  static void bindNavigation(void Function(String path) onNavigate) {
    _onNavigate = onNavigate;
  }

  // ══════════════════════════════════════════════════════════════
  //  RÉPONDRE SANS OUVRIR L'APPLICATION
  // ══════════════════════════════════════════════════════════════
  //
  // ⚠️ CE QUI REND CETTE FONCTION PARTICULIÈRE DANS DROPLET.
  //
  // Ailleurs, répondre depuis une notification suppose un serveur qui
  // relaiera. Ici, il n'y en a pas : la réponse ne part que s'il existe
  // un appareil à portée à cet instant précis. Quand ce n'est pas le
  // cas, elle rejoint la file d'attente et repartira d'elle-même — ce
  // qui est le comportement NORMAL de l'application, pas un échec.
  //
  // C'est pourquoi on ne promet jamais « envoyé » depuis la
  // notification : on enregistre, et le fil de discussion dira la
  // vérité (envoyé, en attente) quand on l'ouvrira.

  /// Identifiants d'action, tels qu'Android nous les renvoie.
  static const String actionRepondre = 'repondre';
  static const String actionLu = 'marquer_lu';
  static const String actionDecrocher = 'decrocher';
  static const String actionRaccrocher = 'raccrocher';

  static Future<void> Function(String route, String texte)? _onRepondre;
  static void Function(String route)? _onLu;
  static void Function(String peerId, bool accepter)? _onAppel;

  /// Branche les actions sur le reste de l'application.
  ///
  /// Appelé depuis `main.dart`, comme [bindNavigation] : ce service ne
  /// connaît ni le maillage ni les providers, et ne doit pas les
  /// connaître.
  static void bindActions({
    Future<void> Function(String route, String texte)? onRepondre,
    void Function(String route)? onLu,
    void Function(String peerId, bool accepter)? onAppel,
  }) {
    _onRepondre = onRepondre;
    _onLu = onLu;
    _onAppel = onAppel;
  }

  /// Traite un appui sur une action de notification.
  static Future<void> _traiterAction(NotificationResponse r) async {
    final route = r.payload;
    if (route == null || route.isEmpty) return;

    switch (r.actionId) {
      case actionRepondre:
        final texte = r.input?.trim();
        if (texte == null || texte.isEmpty) return;
        final f = _onRepondre;
        if (f != null) {
          await f(route, texte);
        } else {
          // L'application n'est pas en état de répondre : on met de
          // côté. Voir `ReponsesDiffrees`.
          await ReponsesDifferees.ajouter(route, texte);
        }
      case actionLu:
        _onLu?.call(route);
      case actionDecrocher:
      case actionRaccrocher:
        final id = route.split('/').last;
        _onAppel?.call(id, r.actionId == actionDecrocher);
      default:
        // Appui sur la notification elle-même : on navigue.
        final nav = _onNavigate;
        if (nav != null) {
          nav(route);
        } else {
          pendingNavigation = route;
        }
    }
  }

  // Les « canaux » de notification servent à Android à grouper les
  // notifications par catégorie, avec un niveau d'importance chacun — un
  // peu comme trois casiers postaux différents : un pour les messages
  // normaux, un pour les appels (plus urgent, ça doit vraiment attirer
  // l'attention), un pour le mesh/l'urgence.
  static const _channelMessages = AndroidNotificationChannel(
    'droplet_messages',
    'Messages',
    description: 'Nouveaux messages et statuts mesh',
    importance: Importance.high,
  );
  static const _channelCalls = AndroidNotificationChannel(
    'droplet_calls',
    'Appels',
    description: 'Appels entrants et manqués',
    importance: Importance.max,
  );
  static const _channelMesh = AndroidNotificationChannel(
    'droplet_mesh',
    'Mesh & urgence',
    description: 'Service mesh actif, statuts et messages d\'urgence',
    importance: Importance.defaultImportance,
  );

  /// À appeler une seule fois au démarrage de l'app : prépare le système
  /// de notifications, crée les trois canaux, et demande la permission
  /// d'afficher des notifications à l'utilisateur.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _plugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: _traiterAction,
      // ⚠️ ET LE MÊME TRAITEMENT QUAND L'APPLICATION EST MORTE.
      //
      // Android réveille alors un isolate séparé, qui n'a accès ni aux
      // providers ni au maillage : `_onRepondre` y vaut toujours `null`,
      // et la réponse part en attente sur le disque. L'application la
      // reprendra à son prochain démarrage.
      //
      // Sans cette ligne, un appui sur « Répondre » application fermée
      // ne faisait RIEN — le texte tapé disparaissait sans trace, ce
      // qu'aucun utilisateur ne pardonne.
      onDidReceiveBackgroundNotificationResponse: reponseEnArrierePlan,
    );

    // Les réponses tapées pendant que l'application était fermée.
    unawaited(ReponsesDifferees.rejouer());
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(_channelMessages);
    await android?.createNotificationChannel(_channelCalls);
    await android?.createNotificationChannel(_channelMesh);
    await android?.requestNotificationsPermission();
  }

  /// Tire un numéro d'identité au hasard pour chaque nouvelle
  /// notification — Android en a besoin pour savoir que c'est une
  /// NOUVELLE bulle et pas la mise à jour d'une ancienne.
  static int _nextId() => _rng.nextInt(1 << 31);

  /// Est-ce qu'on doit garder le silence pour cette notification ? Oui,
  /// si l'app est au premier plan ET que la conversation concernée est
  /// justement celle actuellement ouverte à l'écran.
  static bool _shouldSuppress(String? conversationId) {
    if (!isAppForeground) return false;
    if (conversationId == null) return false;
    // Pas de notification pour une conversation archivée —
    // c'est l'utilisateur qui a décidé de la ranger, et la notification
    // briserait ce silence intentionnel.
    if (_archivedConversations.contains(conversationId)) return true;
    return openConversationId == conversationId;
  }

  /// La fonction commune qui affiche vraiment une bulle de notification
  /// — toutes les fonctions `show...` publiques ci-dessous passent par
  /// ici avec leur propre titre/texte/canal.
  static Future<void> _show({
    required String title,
    required String body,
    required AndroidNotificationChannel channel,
    String? payload,
    List<AndroidNotificationAction> actions = const [],
  }) async {
    try {
      await _plugin.show(
        id: _nextId(),
        title: title,
        body: body,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channel.id,
            channel.name,
            channelDescription: channel.description,
            importance: channel.importance,
            priority: Priority.high,
            actions: actions,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('[NotificationService] échec affichage: $e');
    }
  }

  /// Notification « nouveau message » — sauf si la conversation est déjà
  /// ouverte à l'écran (voir [_shouldSuppress]).
  static Future<void> showNewMessage({
    required String conversationId,
    required String pseudo,
    required String preview,
    required String routePath,
  }) async {
    if (_shouldSuppress(conversationId)) return;
    await _show(
      title: pseudo,
      body: preview,
      channel: _channelMessages,
      payload: routePath,
      actions: [
        AndroidNotificationAction(
          actionRepondre,
          'Répondre',
          // ⚠️ `allowGeneratedReplies` laisse Android proposer des
          // réponses toutes faites (« D'accord », « Merci »). On le
          // laisse : sur un clavier de téléphone, dans la rue, un appui
          // vaut mieux que dix.
          allowGeneratedReplies: true,
          inputs: const [
            AndroidNotificationActionInput(label: 'Votre réponse'),
          ],
          // Sans cela, Android ouvre l'application pour traiter
          // l'action — ce qui annule tout l'intérêt de répondre depuis
          // la notification.
          showsUserInterface: false,
          cancelNotification: true,
        ),
        const AndroidNotificationAction(
          actionLu,
          'Marquer comme lu',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );
  }

  /// Notification « appel entrant » — seulement si l'app n'est pas au
  /// premier plan, car sinon un écran d'appel natif est déjà affiché en
  /// plein écran, une notification en plus serait redondante.
  static Future<void> showIncomingCall({
    required String peerId,
    required String pseudo,
  }) async {
    if (isAppForeground) return; // overlay natif déjà affiché à l'écran
    await _show(
      title: 'Appel entrant',
      body: pseudo,
      channel: _channelCalls,
      payload: '/call/$peerId',
      actions: const [
        // ⚠️ DÉCROCHER OUVRE L'APPLICATION, ET C'EST OBLIGATOIRE.
        //
        // Un appel demande le micro, le haut-parleur et un écran pour
        // raccrocher. Le traiter sans interface laisserait quelqu'un en
        // communication sans aucun moyen d'y mettre fin.
        //
        // Refuser, en revanche, ne demande rien : c'est le seul des
        // deux qui peut se faire sans quitter ce qu'on était en train
        // de faire.
        AndroidNotificationAction(
          actionDecrocher,
          'Répondre',
          showsUserInterface: true,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          actionRaccrocher,
          'Refuser',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    );
  }

  /// Notification « appel manqué » — envoyée quand un appel entrant n'a
  /// jamais été décroché.
  static Future<void> showMissedCall({
    required String peerId,
    required String pseudo,
  }) async {
    await _show(
      title: 'Appel manqué',
      body: pseudo,
      channel: _channelCalls,
      payload: '/chat/$peerId',
    );
  }

  /// Notification « ton message n'est pas parti » — rassure l'utilisateur
  /// que Droplet réessaiera automatiquement dès qu'un pair repasse à
  /// portée, plutôt que de laisser croire que le message est perdu.
  static Future<void> showSendFailed({
    required String conversationId,
    required String routePath,
  }) async {
    await _show(
      title: 'Échec de l\'envoi',
      body: 'Un message n\'a pas pu être envoyé — nouvel essai dès qu\'un pair est à portée.',
      channel: _channelMessages,
      payload: routePath,
    );
  }

  /// Notification « quelqu'un a publié un statut ».
  static Future<void> showStatusPublished({
    required String pseudo,
    required String authorId,
  }) async {
    await _show(
      title: 'Nouveau statut',
      body: '$pseudo a publié un statut',
      channel: _channelMesh,
      payload: '/status/$authorId',
    );
  }

  /// Notification « message d'urgence/sécurité » — quand un contact
  /// diffuse « Je suis en sécurité » sur le mesh.
  static Future<void> showEmergency({required String pseudo}) async {
    await _show(
      title: 'Message d\'urgence',
      body: '$pseudo a diffusé « Je suis en sécurité »',
      channel: _channelMesh,
      payload: '/safety',
    );
  }
}
