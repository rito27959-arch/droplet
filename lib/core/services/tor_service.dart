// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Gestionnaire du circuit Tor pour Droplet.
//
// Utilise le package `tor` (FFI natif Arti) pour créer un proxy SOCKS5
// local. Gère aussi l'identité Tor (clé Ed25519 + adresse .onion).
// ============================================================================

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:tor/tor.dart';

import 'onion_service.dart';

/// État du service Tor.
enum TorServiceState {
  stopped,
  connecting,
  connected,
  error,
}

/// Gestionnaire du proxy Tor local + identité hidden service.
class TorService {
  Tor? _tor;
  TorServiceState _state = TorServiceState.stopped;
  String? _lastError;
  OnionIdentity? _identity;

  final _stateCtrl = StreamController<TorServiceState>.broadcast();

  TorServiceState get state => _state;
  String? get lastError => _lastError;
  Stream<TorServiceState> get stateStream => _stateCtrl.stream;
  bool get isConnected => _state == TorServiceState.connected && _tor?.bootstrapped == true;

  /// Port SOCKS5 du proxy local. Retourne -1 si Tor n'est pas prêt.
  int get proxyPort => _tor?.port ?? -1;

  /// Identité Tor de cet appareil (clé + .onion).
  OnionIdentity? get identity => _identity;

  /// Adresse .onion de cet appareil.
  String? get onionAddress => _identity?.onionAddress;

  Future<void> start() async {
    if (_state == TorServiceState.connecting || isConnected) return;

    _setState(TorServiceState.connecting);
    _lastError = null;

    try {
      // Charger ou générer l'identité Tor.
      _identity = await OnionService.ensureIdentity();
      debugPrint('[TorService] Identité: ${_identity!.shortOnion}');

      _tor = await Tor.init(enabled: true);
      await _tor!.start();

      // Attendre que le circuit soit établi.
      await _tor!.isReady();

      debugPrint('[TorService] Circuit Tor établi — SOCKS5 sur port ${_tor!.port}');
      _setState(TorServiceState.connected);
    } catch (e) {
      _lastError = e.toString();
      _setState(TorServiceState.error);
      debugPrint('[TorService] Erreur: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tor?.stop();
    } catch (_) {}
    _tor = null;
    _setState(TorServiceState.stopped);
    debugPrint('[TorService] Arrêté');
  }

  void disable() {
    _tor?.disable();
  }

  void _setState(TorServiceState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateCtrl.add(newState);
  }

  void dispose() {
    stop();
    _stateCtrl.close();
  }
}
