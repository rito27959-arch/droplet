// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LA MACHINE D'ÉTAT DU RÉSEAU : à tout instant, elle répond à la
// question « où en est Droplet, réseau-wise ? » par UN seul mot.
//
// ── Pourquoi c'était nécessaire ───────────────────────────────────────
//
// Jusqu'ici, personne ne tenait cette réponse. Chaque morceau du réseau
// savait son propre état dans son coin — le Wi-Fi savait s'il avait un
// socket, le Bluetooth savait s'il scannait — mais aucun endroit ne
// savait si l'APPAREIL, globalement, pouvait communiquer.
//
// La conséquence tenait en une ligne de journal, répétée toutes les
// trois secondes pendant des heures :
//
//     SocketException: Send failed (Network is unreachable, errno = 101)
//
// La balise Wi-Fi partait dans le vide parce que rien ne lui disait
// qu'il n'y avait plus de réseau. Ce n'était pas une erreur : c'était un
// ÉTAT que personne ne représentait. Un état se constate une fois et se
// surveille ; une erreur se relance indéfiniment.
//
// ── Le principe : une fonction, pas un empilement de drapeaux ─────────
//
// L'état n'est jamais « posé » par quelqu'un. Il est CALCULÉ, à partir
// de trois entrées seulement : l'état de chaque transport, le nombre de
// pairs joignables, et le fait qu'une synchronisation soit en cours.
//
// C'est délibéré. Un état qu'on assigne depuis quinze endroits finit
// toujours par se contredire — un morceau du code croit l'appareil
// connecté pendant qu'un autre le croit hors ligne, et le bogue qui en
// résulte est introuvable. Un état calculé ne peut pas mentir : deux
// entrées identiques donnent toujours le même état, ce qui le rend
// aussi entièrement testable, sans radio ni téléphone.
// ============================================================================

import 'dart:async';

import 'package:flutter/foundation.dart';

import 'mesh_transport.dart';

/// Où en est le réseau de cet appareil.
///
/// Ces états sont ORDONNÉS du pire au meilleur, ce qui permet de dire
/// simplement « l'état s'est dégradé » ou « il s'est amélioré ».
enum MeshNetworkState {
  /// Rien n'est démarré. L'utilisateur n'a pas encore d'identité, ou le
  /// mesh a été arrêté volontairement.
  offline,

  /// Le mesh tourne, mais AUCUN transport n'est utilisable : Wi-Fi
  /// coupé, Bluetooth désactivé, permissions refusées. Rien ne peut
  /// partir, et c'est inutile d'essayer.
  networkLost,

  /// Un transport vient de redevenir disponible après une coupure. On
  /// redécouvre le voisinage avant de pouvoir affirmer quoi que ce soit.
  recovering,

  /// Au moins un transport fonctionne, mais personne en vue.
  discovering,

  /// Des pairs sont détectés, les liaisons s'établissent.
  connecting,

  /// Au moins un pair est joignable — mais par un chemin médiocre
  /// seulement (Bluetooth seul, ou beaucoup d'échecs d'envoi). Les
  /// messages passent, pas les fichiers ni la voix.
  degraded,

  /// Au moins un pair joignable par un bon chemin.
  connected,

  /// Connecté ET en train d'échanger un arriéré de messages.
  syncing;

  /// Peut-on espérer qu'un envoi aboutisse ?
  ///
  /// Sert à s'abstenir plutôt qu'à échouer : une balise, un message ou
  /// une synchronisation n'ont rien à tenter dans les trois premiers
  /// états.
  bool get canSend => index >= MeshNetworkState.connecting.index;

  /// Y a-t-il au moins une radio en état de marche ?
  bool get hasUsableTransport => index >= MeshNetworkState.recovering.index;
}

/// Le passage d'un état à un autre, avec ce qui l'explique.
@immutable
class MeshStateTransition {
  const MeshStateTransition({
    required this.from,
    required this.to,
    required this.reason,
    required this.at,
  });

  final MeshNetworkState from;
  final MeshNetworkState to;

  /// En clair, pour le journal et l'écran de diagnostic.
  final String reason;

  final DateTime at;

  bool get isDegradation => to.index < from.index;
  bool get isImprovement => to.index > from.index;

  @override
  String toString() => '${from.name} → ${to.name} ($reason)';
}

/// Calcule et publie l'état du réseau.
class MeshStateMachine {
  MeshStateMachine({this.onTransition});

  /// Appelé à CHAQUE changement — jamais quand l'état se recalcule à
  /// l'identique. C'est ce qui distingue un journal lisible d'un flot
  /// d'exceptions.
  final void Function(MeshStateTransition)? onTransition;

  final _transitionsCtrl = StreamController<MeshStateTransition>.broadcast();
  Stream<MeshStateTransition> get transitions => _transitionsCtrl.stream;

  MeshNetworkState _state = MeshNetworkState.offline;
  MeshNetworkState get state => _state;

  bool get canSend => _state.canSend;

  DateTime? _changedAt;

  /// Depuis combien de temps l'état courant dure.
  Duration get durationInState => _changedAt == null
      ? Duration.zero
      : DateTime.now().difference(_changedAt!);

  /// Vrai si l'appareil a connu une coupure totale et n'a pas encore
  /// retrouvé de pair depuis. Sert à savoir qu'il faudra resynchroniser.
  bool _sortantDeCoupure = false;
  bool get needsResync => _sortantDeCoupure;

  // ── Historique, pour le diagnostic ────────────────────────────────
  final List<MeshStateTransition> _historique = [];

  /// Les dernières transitions, de la plus récente à la plus ancienne.
  List<MeshStateTransition> get recentTransitions =>
      List.unmodifiable(_historique.reversed);

  /// Combien de fois le réseau a été totalement perdu depuis le
  /// démarrage — une métrique bien plus parlante qu'un compteur
  /// d'exceptions.
  int networkLossCount = 0;

  /// Recalcule l'état à partir de la situation réelle.
  ///
  /// [transports] : l'état de chaque radio, tel qu'elle le rapporte.
  /// [connectedPeers] : combien de pairs sont joignables maintenant.
  /// [syncing] : une synchronisation est-elle en cours ?
  /// [qualityOk] : le chemin disponible est-il bon ? (faux = Bluetooth
  /// seul, ou trop d'échecs d'envoi récents)
  void update({
    required Map<String, TransportState> transports,
    required int connectedPeers,
    bool syncing = false,
    bool qualityOk = true,
  }) {
    _appliquer(_calculer(
      transports: transports,
      connectedPeers: connectedPeers,
      syncing: syncing,
      qualityOk: qualityOk,
    ));
  }

  /// Le mesh s'arrête volontairement.
  void markStopped() => _appliquer((
        MeshNetworkState.offline,
        'mesh arrêté',
      ));

  /// LA fonction pure : mêmes entrées, même sortie, toujours.
  ///
  /// Aucun effet de bord ici, aucune lecture d'horloge, aucun accès
  /// réseau — c'est ce qui la rend testable en totalité, y compris les
  /// situations impossibles à provoquer sur un vrai téléphone.
  (MeshNetworkState, String) _calculer({
    required Map<String, TransportState> transports,
    required int connectedPeers,
    required bool syncing,
    required bool qualityOk,
  }) {
    if (transports.isEmpty) {
      return (MeshNetworkState.offline, 'aucun transport');
    }

    final demarres =
        transports.values.where((t) => t != TransportState.stopped).toList();
    if (demarres.isEmpty) {
      return (MeshNetworkState.offline, 'tous les transports sont arrêtés');
    }

    // Tous démarrés mais aucun utilisable : c'est la coupure totale, et
    // c'est exactement le cas que la balise Wi-Fi ignorait.
    final utilisables =
        demarres.where((t) => t != TransportState.unavailable).toList();
    if (utilisables.isEmpty) {
      final noms = transports.entries
          .where((e) => e.value == TransportState.unavailable)
          .map((e) => e.key)
          .join(', ');
      return (MeshNetworkState.networkLost, 'aucune radio disponible ($noms)');
    }

    if (connectedPeers == 0) {
      // On sort d'une coupure : on le dit, plutôt que de faire comme si
      // de rien n'était. C'est ce qui déclenchera la resynchronisation.
      if (_sortantDeCoupure) {
        return (MeshNetworkState.recovering, 'radio retrouvée, redécouverte');
      }
      final cherchent =
          utilisables.where((t) => t == TransportState.searching).length;
      return (
        MeshNetworkState.discovering,
        '$cherchent transport(s) en recherche',
      );
    }

    // Des pairs sont vus par au moins un transport, mais aucun n'est
    // encore passé en `active` : les liaisons se montent.
    final actifs =
        utilisables.where((t) => t == TransportState.active).length;
    if (actifs == 0) {
      return (MeshNetworkState.connecting, 'liaisons en cours');
    }

    if (syncing) {
      return (MeshNetworkState.syncing, 'échange en cours');
    }
    if (!qualityOk) {
      return (
        MeshNetworkState.degraded,
        'lien de mauvaise qualité — texte seulement',
      );
    }
    return (
      MeshNetworkState.connected,
      '$connectedPeers pair(s) joignable(s)',
    );
  }

  void _appliquer((MeshNetworkState, String) resultat) {
    final (nouveau, raison) = resultat;
    if (nouveau == _state) return;

    final transition = MeshStateTransition(
      from: _state,
      to: nouveau,
      reason: raison,
      at: DateTime.now(),
    );

    if (nouveau == MeshNetworkState.networkLost) {
      networkLossCount++;
      _sortantDeCoupure = true;
    }
    // La reprise n'est acquise qu'une fois un pair réellement retrouvé,
    // pas au simple retour de la radio : c'est à ce moment-là seulement
    // qu'il y a quelqu'un avec qui se resynchroniser.
    if (nouveau.index >= MeshNetworkState.connecting.index) {
      _sortantDeCoupure = false;
    }

    _state = nouveau;
    _changedAt = transition.at;

    _historique.add(transition);
    if (_historique.length > 50) _historique.removeAt(0);

    debugPrint('[MeshState] $transition');
    onTransition?.call(transition);
    if (!_transitionsCtrl.isClosed) _transitionsCtrl.add(transition);
  }

  void dispose() => _transitionsCtrl.close();
}
