// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Gestionnaire du circuit Tor pour Droplet.
//
// Utilise le package `tor` (FFI natif Arti) pour créer un proxy SOCKS5
// local. Gère aussi l'identité Tor (clé Ed25519 + adresse .onion).
// ============================================================================

import 'dart:async';
import 'dart:math' as math;

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

  /// L'état, en commençant par CELUI D'AUJOURD'HUI.
  ///
  /// ⚠️ C'ÉTAIT `_stateCtrl.stream` NU, ET C'EST UN DÉFAUT VISIBLE.
  ///
  /// Un `StreamController.broadcast` ne rejoue rien : celui qui s'abonne
  /// après coup n'apprend l'état qu'au PROCHAIN changement. Or Tor met
  /// dix à trente secondes à s'établir, puis ne bouge plus pendant des
  /// heures. Tout widget construit après cet instant — c'est-à-dire
  /// presque tous, puisqu'on change d'écran — recevait donc `loading`
  /// indéfiniment. `TorStatusIndicator` affichait alors une boîte vide, et
  /// `torConnectedProvider` répondait « non » alors que le circuit
  /// tournait. Le réseau marchait ; l'interface disait le contraire.
  ///
  /// En émettant d'abord l'état courant, tout nouvel abonné est à jour à
  /// la première image.
  Stream<TorServiceState> get stateStream async* {
    yield _state;
    yield* _stateCtrl.stream;
  }

  /// Vrai quand le circuit est réellement utilisable.
  ///
  /// Deux conditions et pas une : notre état interne dit « connecté », et
  /// la bibliothèque confirme que l'amorçage tient toujours. C'est cette
  /// seconde condition que surveille le chien de garde.
  bool get isConnected =>
      _state == TorServiceState.connected && _tor?.bootstrapped == true;

  /// Port SOCKS5 du proxy local. Retourne -1 si Tor n'est pas prêt.
  int get proxyPort => _tor?.port ?? -1;

  /// Identité Tor de cet appareil (clé + .onion).
  OnionIdentity? get identity => _identity;

  /// Adresse .onion de cet appareil.
  String? get onionAddress => _identity?.onionAddress;

  Future<void> start() async {
    if (_state == TorServiceState.connecting || isConnected) return;

    _arreteVoulu = false;
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
      _tentatives = 0;
      _setState(TorServiceState.connected);
      _demarrerChienDeGarde();
    } catch (e) {
      _lastError = e.toString();
      _setState(TorServiceState.error);
      debugPrint('[TorService] Erreur: $e');
      _programmerNouvelEssai();
    }
  }

  Future<void> stop() async {
    // L'arrêt est VOULU : il ne doit pas déclencher la reconnexion
    // automatique. Sans ce drapeau, éteindre Tor depuis les réglages le
    // rallumerait quelques secondes plus tard.
    _arreteVoulu = true;
    _chienDeGarde?.cancel();
    _chienDeGarde = null;
    _essai?.cancel();
    _essai = null;
    try {
      await _tor?.stop();
    } catch (_) {}
    _tor = null;
    _setState(TorServiceState.stopped);
    debugPrint('[TorService] Arrêté');
  }

  // ── Reconnexion et surveillance ────────────────────────────────────────────
  //
  // ⚠️ CE QUI MANQUAIT : PERSONNE NE REGARDAIT SI LE CIRCUIT TENAIT.
  //
  // `start()` posait l'état « connecté » une fois pour toutes. Si le
  // circuit tombait ensuite — changement de réseau, veille prolongée,
  // relais qui disparaît —, plus rien ne le remarquait : l'interface
  // continuait d'afficher « Tor actif » pendant que les envois
  // échouaient en silence. Et une erreur au démarrage restait définitive
  // jusqu'à ce que l'utilisateur pense à revenir dans les réglages.
  //
  // Sur un téléphone qui change de réseau plusieurs fois par jour, ces
  // deux manques suffisent à donner l'impression que « Tor ne marche
  // pas ».

  Timer? _chienDeGarde;
  Timer? _essai;
  int _tentatives = 0;
  bool _arreteVoulu = false;

  /// Combien de fois on retente avant de laisser l'utilisateur décider.
  ///
  /// Au-delà, ce n'est plus un incident réseau : c'est un problème qui
  /// demande une action (pas de connexion du tout, Tor bloqué par le
  /// réseau local). Continuer à essayer viderait la batterie sans rien
  /// résoudre.
  static const int _maxTentatives = 5;

  void _demarrerChienDeGarde() {
    _chienDeGarde?.cancel();
    // Vingt secondes : assez rare pour ne rien coûter, assez fréquent
    // pour qu'on ne reste pas une minute à croire qu'on est protégé.
    _chienDeGarde = Timer.periodic(const Duration(seconds: 20), (_) {
      if (_arreteVoulu) return;
      if (_state != TorServiceState.connected) return;
      if (_tor?.bootstrapped == true) return;

      debugPrint('[TorService] Circuit perdu — reconnexion');
      _lastError = 'Circuit interrompu';
      _setState(TorServiceState.connecting);
      _tentatives = 0;
      _programmerNouvelEssai(immediat: true);
    });
  }

  void _programmerNouvelEssai({bool immediat = false}) {
    if (_arreteVoulu) return;
    if (_tentatives >= _maxTentatives) {
      debugPrint('[TorService] Abandon après $_tentatives tentatives');
      _setState(TorServiceState.error);
      return;
    }
    _tentatives++;
    // Attente qui double à chaque échec (2, 4, 8, 16, 32 s), plafonnée.
    // Le même principe que la file d'envoi du mesh : réessayer sans
    // relâche épuise la batterie et ne répare rien.
    final delai = immediat
        ? const Duration(milliseconds: 300)
        : Duration(seconds: math.min(32, 1 << _tentatives));
    _essai?.cancel();
    _essai = Timer(delai, () {
      if (_arreteVoulu) return;
      debugPrint('[TorService] Tentative $_tentatives');
      unawaited(_redemarrer());
    });
  }

  Future<void> _redemarrer() async {
    try {
      await _tor?.stop();
    } catch (_) {}
    _tor = null;
    // `start` remet l'état à `connecting` et relance le compte à rebours
    // en cas de nouvel échec.
    _arreteVoulu = false;
    await start();
  }

  void disable() {
    _tor?.disable();
  }

  void _setState(TorServiceState newState) {
    if (_state == newState) return;
    _state = newState;
    // ⚠️ `isClosed` OBLIGATOIRE. `dispose()` appelait `stop()` — qui est
    // asynchrone — puis fermait le contrôleur immédiatement. Quand
    // `stop()` finissait, il posait l'état « arrêté » sur un contrôleur
    // déjà fermé : `Bad state: Cannot add event after closing`, levé
    // depuis la destruction d'un provider, c'est-à-dire à un endroit où
    // personne ne l'attrape.
    if (_stateCtrl.isClosed) return;
    _stateCtrl.add(newState);
  }

  Future<void> dispose() async {
    _arreteVoulu = true;
    _chienDeGarde?.cancel();
    _essai?.cancel();
    await stop();
    await _stateCtrl.close();
  }
}
