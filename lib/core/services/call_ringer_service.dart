// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est le fichier qui fait « SONNER » le téléphone quand quelqu'un
// appelle — exactement comme WhatsApp ou n'importe quelle app d'appel :
// une mélodie qui tourne en boucle + le téléphone qui vibre quand
// quelqu'un t'appelle, et un petit bip régulier quand c'est TOI qui
// attends que l'autre décroche.
//
// Ce fichier n'a même pas besoin d'avoir son propre fichier de musique
// dans l'app — il utilise directement les sonneries déjà installées sur
// le téléphone Android (comme n'importe quelle app de téléphone le
// ferait), donc l'utilisateur entend sa propre sonnerie habituelle.
// ============================================================================

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

/// Son et vibration d'appel façon WhatsApp : sonnerie système en boucle +
/// vibration répétée côté entrant, tonalité de rappel périodique côté
/// sortant. Aucun asset audio fourni par l'app — tout passe par les sons
/// système Android (RingtoneManager), au même titre que n'importe quelle
/// app de téléphonie.
class CallRingerService {
  CallRingerService._();

  static Timer? _pulseTimer;
  static bool _ringing = false;

  /// Sonnerie entrante : mélodie système en boucle + vibration régulière
  /// (une petite secousse chaque seconde), jusqu'à ce que l'appel soit
  /// décroché, refusé, ou qu'il s'arrête tout seul.
  static void startIncoming() {
    if (_ringing) return;
    _ringing = true;
    FlutterRingtonePlayer().play(
      android: AndroidSounds.ringtone,
      ios: IosSounds.electronic,
      looping: true,
      volume: 1.0,
    );
    HapticFeedback.heavyImpact();
    _pulseTimer = Timer.periodic(const Duration(seconds: 1), (_) => HapticFeedback.heavyImpact());
  }

  /// Tonalité de rappel sortante (quand c'est MOI qui appelle et
  /// j'attends) : un petit bip toutes les 1,8 secondes, sans vibration —
  /// comme le « bip... bip... » d'un téléphone classique qui sonne chez
  /// l'autre.
  static void startOutgoing() {
    if (_ringing) return;
    _ringing = true;
    FlutterRingtonePlayer().playNotification();
    _pulseTimer = Timer.periodic(const Duration(milliseconds: 1800), (_) {
      FlutterRingtonePlayer().playNotification();
    });
  }

  /// Coupure immédiate du son et de la vibration — dès que l'appel est
  /// connecté, manqué, raccroché ou refusé, plus aucun bruit ne doit
  /// continuer.
  static void stop() {
    if (!_ringing) return;
    _ringing = false;
    FlutterRingtonePlayer().stop();
    _pulseTimer?.cancel();
    _pulseTimer = null;
  }
}
