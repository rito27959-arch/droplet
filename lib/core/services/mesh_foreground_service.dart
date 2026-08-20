// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Normalement, quand on ferme/balaie une app pour la faire disparaître de
// la liste des apps récentes, Android l'endort ou la tue complètement
// pour économiser la batterie. Le problème, c'est que Droplet doit
// continuer à relayer les messages des autres même quand elle n'est pas
// affichée à l'écran — sinon le réseau mesh s'effondre dès que
// l'utilisateur change d'app.
//
// La solution Android officielle pour ça s'appelle un « service premier
// plan » (foreground service) : l'app garde une petite notification
// permanente et discrète (« Droplet actif — relais du mesh »)
// visible en permanence dans la barre de notifications, et EN ÉCHANGE,
// Android accepte de ne pas tuer l'app. C'est un contrat : « je te
// préviens toujours que je tourne, et toi tu me laisses tourner ».
//
// Point important à comprendre : ce fichier NE CONTIENT AUCUNE logique de
// réseau mesh lui-même ! Il ne fait qu'allumer/éteindre ce contrat avec
// Android. Le vrai mesh (Bluetooth, Wi-Fi, etc.) continue de tourner
// exactement comme avant, ailleurs dans le code — ce fichier se contente
// de garder la porte ouverte pour qu'Android le laisse vivre.
// ============================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Handler minimal exécuté dans l'isolate du service premier plan Android.
///
/// Il ne fait volontairement RIEN côté métier : le mesh (BLE/Wi-Fi/Nearby,
/// `MeshRepository`, providers Riverpod) continue de tourner tel quel dans
/// l'isolate principal de l'app. Le seul rôle de ce service est de faire
/// passer le PROCESSUS de l'app en priorité « premier plan » côté Android
/// (via la notification persistante), ce qui empêche le système de tuer le
/// processus — et donc l'isolate principal avec lui — quand l'app n'est
/// plus à l'écran. Dupliquer le mesh dans cet isolate séparé aurait exigé
/// de réécrire tout le transport (BLE/Nearby ne sont pas garantis
/// utilisables hors isolate UI) pour un bénéfice nul.
@pragma('vm:entry-point')
void _startForegroundCallback() {
  FlutterForegroundTask.setTaskHandler(_NoopTaskHandler());
}

/// « Noop » veut dire « no operation », c'est-à-dire « ne fait rien ».
/// C'est volontaire : ce handler existe juste parce qu'Android exige d'en
/// avoir un pour accepter de démarrer le service, mais tout le vrai
/// travail se fait ailleurs (voir le commentaire au-dessus).
class _NoopTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {}

  @override
  void onRepeatEvent(DateTime timestamp) {}

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

/// Démarre/arrête le service premier plan qui maintient Droplet actif en
/// arrière-plan (relais mesh même app fermée/swipée).
class MeshForegroundService {
  MeshForegroundService._();

  static bool _initialized = false;

  /// Prépare le service (nom du canal de notification, priorité basse
  /// pour rester discret, autorisation de garder le Wi-Fi/l'écran
  /// allumés si besoin) — à appeler une seule fois avant de pouvoir le
  /// démarrer.
  static void init() {
    if (_initialized) return;
    _initialized = true;
    FlutterForegroundTask.initCommunicationPort();
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'droplet_mesh_service',
        channelName: 'Droplet — relais mesh actif',
        channelDescription:
            'Notification permanente tant que Droplet relaie le mesh en arrière-plan.',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.nothing(),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  static Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  static Future<NotificationPermission> checkNotificationPermission() =>
      FlutterForegroundTask.checkNotificationPermission();

  static Future<NotificationPermission> requestNotificationPermission() =>
      FlutterForegroundTask.requestNotificationPermission();

  /// Est-ce que l'utilisateur a déjà autorisé Droplet à ignorer les
  /// économies de batterie d'Android (sinon le système peut quand même
  /// ralentir/couper l'app de temps en temps, même avec le service
  /// premier plan actif) ?
  static Future<bool> get isIgnoringBatteryOptimizations =>
      FlutterForegroundTask.isIgnoringBatteryOptimizations;

  static Future<bool> requestIgnoreBatteryOptimization() =>
      FlutterForegroundTask.requestIgnoreBatteryOptimization();

  /// Démarre vraiment le service premier plan et fait apparaître la
  /// notification permanente « Droplet actif ».
  static Future<void> start() async {
    init();
    try {
      if (await isRunning) return;
      await FlutterForegroundTask.startService(
        serviceId: 501,
        notificationTitle: 'Droplet actif',
        notificationText: 'Relais du mesh en arrière-plan',
        callback: _startForegroundCallback,
      );
    } catch (e) {
      debugPrint('[MeshForegroundService] échec démarrage: $e');
    }
  }

  /// Arrête le service et fait disparaître la notification permanente.
  static Future<void> stop() async {
    try {
      if (!await isRunning) return;
      await FlutterForegroundTask.stopService();
    } catch (e) {
      debugPrint('[MeshForegroundService] échec arrêt: $e');
    }
  }
}
