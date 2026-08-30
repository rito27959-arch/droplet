// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// La synchronisation du-mondes entre deux appareils Nexus.
//
// Quand deux pairs établissent une connexion (découverte → handshake →
// échange X25519 → HKDF), celui qui détecte l'autre en premier émet un
// `NexusEvent` avec une seed partagée. L'autre le reçoit, et les deux
// lancent l'animation Nexus en parallèle.
//
// La synchronisation n'est PAS frame-perfect (impossible sans horloge
// partagée), mais elle est PERCEPTUELLE : même seed, mêmes formes,
// mêmes couleurs, même timing approximatif. L'utilisateur voit deux
// écrans qui vivent la même scène.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'nexus_event.dart';

/// Callback quand un NexusEvent est émis ou reçu.
typedef NexusEventHandler = void Function(NexusEvent event);

/// Gère l'échange d'événements Nexus entre deux appareils.
///
/// N'est PAS responsable de l'animation — uniquement du protocole
/// réseau. Le contrôleur (`NexusController`) consomme les événements
/// ici produits pour lancer la séquence visuelle.
class NexusSync {
  NexusSync({
    required this.peerIdA,
    required this.peerIdB,
    this.onEventEmitted,
  });

  /// ID local de cet appareil.
  final String peerIdA;

  /// ID du pair distant.
  final String peerIdB;

  /// Appelé quand un événement doit être envoyé au pair distant.
  final NexusEventHandler? onEventEmitted;

  final _eventsController = StreamController<NexusEvent>.broadcast();

  /// Flux des événements reçus du pair distant.
  Stream<NexusEvent> get events => _eventsController.stream;

  bool _hasEmitted = false;

  /// Émet un événement Nexus vers le pair distant.
  ///
  /// Doit être appelé une seule fois par connexion, depuis l'appareil
  /// qui détecte l'autre en premier. L'autre appareil recevra l'événement
  /// via [receiveEvent].
  void emitConnection() {
    if (_hasEmitted) return;
    _hasEmitted = true;

    final event = NexusEvent(
      seed: NexusEvent.generateSeed(),
      timestamp: DateTime.now().toUtc().toIso8601String(),
      intensity: 1.0,
      colorSignature: NexusEvent.deriveColorSignature(peerIdA, peerIdB),
    );

    debugPrint('[NexusSync] Émission connexion: seed=${event.seed.substring(0, 8)}...');
    onEventEmitted?.call(event);
  }

  /// Reçoit un événement du pair distant.
  ///
  /// Appelé par la couche réseau quand un message de type nexus arrive.
  void receiveEvent(NexusEvent event) {
    debugPrint('[NexusSync] Réception: seed=${event.seed.substring(0, 8)}...');
    if (!_eventsController.isClosed) {
      _eventsController.add(event);
    }
  }

  /// Nettoyage.
  void dispose() {
    _eventsController.close();
  }
}
