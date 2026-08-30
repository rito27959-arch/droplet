// ============================================================================
// UN TRANSPORT SIMULÉ, POUR TESTER LE MAILLAGE SANS AUCUNE RADIO.
// ----------------------------------------------------------------------------
// C'est la raison d'être du contrat `MeshTransport` : tant que les trois
// transports réels étaient connus nommément par la couche supérieure,
// vérifier le comportement du maillage exigeait de vrais téléphones. On
// ne pouvait donc mesurer ni la perte de paquets, ni le
// réordonnancement, ni ce qui se passe à vingt nœuds.
//
// Ce transport-ci remplit le même contrat, mais ne parle à aucune radio :
// il relie des nœuds à l'intérieur d'un seul processus, à travers un
// `RezeauSimule` qui joue le rôle de l'air ambiant. On peut alors lui
// demander de perdre 5 % des paquets, d'en dupliquer, de les livrer dans
// le désordre ou d'ajouter 300 ms de latence — et observer ce que le
// maillage en fait.
//
// Il vit dans `test/` et non dans `lib/` : c'est un instrument de
// mesure, il n'a rien à faire dans l'application livrée.
// ============================================================================

import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:droplet/core/services/ble_mesh_protocol.dart';
import 'package:droplet/core/services/mesh_transport.dart';

/// L'air ambiant : ce qui relie les nœuds simulés, et ce qui les abîme.
class RezeauSimule {
  RezeauSimule({
    this.tauxDePerte = 0.0,
    this.tauxDeDuplication = 0.0,
    this.latence = Duration.zero,
    this.gigue = Duration.zero,
    int graine = 42,
  }) : _alea = Random(graine);

  /// Probabilité qu'un paquet soit purement perdu, entre 0 et 1.
  final double tauxDePerte;

  /// Probabilité qu'un paquet arrive en double.
  final double tauxDeDuplication;

  /// Délai de livraison de base.
  final Duration latence;

  /// Variation aléatoire ajoutée à la latence. Non nulle, elle suffit à
  /// provoquer du RÉORDONNANCEMENT : deux paquets partis dans l'ordre
  /// peuvent alors arriver dans le désordre, exactement comme sur un
  /// vrai réseau.
  final Duration gigue;

  /// Graine fixe par défaut : deux exécutions du même test perdent
  /// EXACTEMENT les mêmes paquets. Sans cela, un test qui échoue une
  /// fois sur dix serait impossible à instruire.
  final Random _alea;

  final Map<String, FauxTransport> _noeuds = {};

  /// Qui est à portée de qui. Absent de cette table = hors de portée.
  final Map<String, Set<String>> _portee = {};

  // ── Compteurs, pour les mesures ──────────────────────────────────
  int paquetsTransmis = 0;
  int paquetsPerdus = 0;
  int paquetsDupliques = 0;

  void inscrire(FauxTransport noeud) {
    _noeuds[noeud.monId] = noeud;
    _portee.putIfAbsent(noeud.monId, () => <String>{});
  }

  /// Met deux nœuds à portée l'un de l'autre.
  void relier(String a, String b) {
    _portee.putIfAbsent(a, () => <String>{}).add(b);
    _portee.putIfAbsent(b, () => <String>{}).add(a);
    _noeuds[a]?.signalerPair(b);
    _noeuds[b]?.signalerPair(a);
  }

  /// Les éloigne — ce que fait quelqu'un qui sort de la pièce.
  void separer(String a, String b) {
    _portee[a]?.remove(b);
    _portee[b]?.remove(a);
    _noeuds[a]?.signalerPerte(b);
    _noeuds[b]?.signalerPerte(a);
  }

  /// Relie tout le monde à tout le monde.
  void relierTous() {
    final ids = _noeuds.keys.toList();
    for (var i = 0; i < ids.length; i++) {
      for (var j = i + 1; j < ids.length; j++) {
        relier(ids[i], ids[j]);
      }
    }
  }

  bool aPortee(String de, String vers) => _portee[de]?.contains(vers) ?? false;

  /// Achemine un paquet — ou le perd, ou le double, ou le retarde.
  Future<bool> acheminer(String de, String vers, Uint8List donnees) async {
    if (!aPortee(de, vers)) return false;
    final destinataire = _noeuds[vers];
    if (destinataire == null || !destinataire.isRunning) return false;

    if (_alea.nextDouble() < tauxDePerte) {
      paquetsPerdus++;
      // Volontairement `true` : sur un vrai réseau sans accusé de
      // réception, l'émetteur croit son paquet parti. Renvoyer `false`
      // ici masquerait la perte au lieu de la simuler, et le test
      // vérifierait une situation qui n'existe pas.
      return true;
    }

    final exemplaires =
        _alea.nextDouble() < tauxDeDuplication ? 2 : 1;
    if (exemplaires > 1) paquetsDupliques++;

    for (var i = 0; i < exemplaires; i++) {
      final delai = latence +
          Duration(
            microseconds: gigue.inMicroseconds == 0
                ? 0
                : _alea.nextInt(gigue.inMicroseconds),
          );
      paquetsTransmis++;
      if (delai == Duration.zero) {
        destinataire.recevoir(de, donnees);
      } else {
        Future<void>.delayed(delai, () => destinataire.recevoir(de, donnees));
      }
    }
    return true;
  }
}

/// Un nœud du réseau simulé.
class FauxTransport implements MeshTransport {
  FauxTransport(this.monId, this._reseau) {
    _reseau.inscrire(this);
  }

  final String monId;
  final RezeauSimule _reseau;

  final _peerEventsCtrl = StreamController<MeshPeerEvent>.broadcast();
  final _incomingCtrl = StreamController<MeshIncomingData>.broadcast();

  bool _running = false;
  final Set<String> _pairs = {};

  /// Tout ce qui a été reçu, dans l'ordre d'arrivée — c'est là qu'un
  /// test va vérifier les doublons et le réordonnancement.
  final List<Uint8List> recus = [];

  @override
  String get name => 'faux';

  @override
  bool get isRunning => _running;

  @override
  TransportState get state {
    if (!_running) return TransportState.stopped;
    return _pairs.isEmpty ? TransportState.searching : TransportState.active;
  }

  @override
  final TransportMetrics metrics = TransportMetrics();

  @override
  TransportCapabilities get capabilities => const TransportCapabilities(
        maxPayloadBytes: 1 << 20,
        maxContentType: 0xFF,
        portePhotosEtFichiers: true,
        porteVoixEnDirect: true,
        coutEnergetique: 0.0,
      );

  @override
  Stream<MeshPeerEvent> get peerEvents => _peerEventsCtrl.stream;

  @override
  Stream<MeshIncomingData> get incomingData => _incomingCtrl.stream;

  @override
  Future<void> start(String myId, String myPseudo) async {
    _running = true;
  }

  @override
  Future<void> stop() async {
    _running = false;
    for (final p in _pairs.toList()) {
      signalerPerte(p);
    }
  }

  @override
  Future<bool> sendToPeer(String peerId, Uint8List data,
      {int type = 0x00, int priority = 2}) async {
    if (!_running) return false;
    if (!capabilities.accepte(tailleOctets: data.length, type: type)) {
      metrics.echecsEnvoi++;
      return false;
    }
    final ok = await _reseau.acheminer(monId, peerId, data);
    if (ok) {
      metrics.paquetsEnvoyes++;
      metrics.octetsEnvoyes += data.length;
    } else {
      metrics.echecsEnvoi++;
    }
    return ok;
  }

  void recevoir(String de, Uint8List donnees) {
    if (!_running) return;
    recus.add(donnees);
    metrics.paquetsRecus++;
    metrics.octetsRecus += donnees.length;
    if (!_incomingCtrl.isClosed) {
      _incomingCtrl.add(MeshIncomingData(
        peerId: de,
        data: donnees,
        messageId: '${de}_${recus.length}',
      ));
    }
  }

  void signalerPair(String peerId) {
    if (!_pairs.add(peerId)) return;
    metrics.pairsDecouverts++;
    metrics.pairsConnectes++;
    if (!_peerEventsCtrl.isClosed) {
      _peerEventsCtrl.add(MeshPeerEvent(
        peerId: peerId,
        pseudo: peerId,
        isConnected: true,
      ));
    }
  }

  void signalerPerte(String peerId) {
    if (!_pairs.remove(peerId)) return;
    metrics.pairsConnectes--;
    if (!_peerEventsCtrl.isClosed) {
      _peerEventsCtrl.add(MeshPeerEvent(
        peerId: peerId,
        pseudo: peerId,
        isConnected: false,
      ));
    }
  }

  @override
  void dispose() {
    _peerEventsCtrl.close();
    _incomingCtrl.close();
  }
}
