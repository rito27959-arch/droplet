// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Ce fichier contient les « moules à gâteau » de l'app : des classes qui ne
// font QUE ranger des informations, sans rien faire d'autre (pas de bouton,
// pas de dessin, pas de réseau). Un peu comme des fiches Bristol : chaque
// classe décrit précisément ce qu'on écrit sur UNE fiche (un message, un
// contact, un appel...) et dans quel ordre.
//
// Beaucoup de ces classes ont 3 outils qui reviennent tout le temps :
//   - `copyWith(...)` : recopie la fiche à l'identique, sauf les quelques
//     champs qu'on précise — pratique pour « changer juste une chose »
//     sans tout réécrire à la main.
//   - `toJson()` : transforme la fiche en texte, pour pouvoir l'écrire dans
//     le classeur permanent du téléphone (la base de données) ou l'envoyer
//     par le réseau.
//   - `fromJson(...)` : fait l'inverse — relit du texte et reconstruit la
//     fiche d'origine.
// ============================================================================

/// Statut d'un message dans le mesh — où il en est dans son voyage.
///   - `sending`  : en train de partir.
///   - `sent`     : parti avec succès.
///   - `pending`  : en attente (aucun pair à portée pour l'instant).
///   - `failed`   : n'a pas pu partir.
enum MessageStatus { sending, sent, pending, failed }

/// La fiche d'identité que l'app garde sur chaque personne déjà croisée sur
/// le réseau — un peu comme un carnet d'adresses, pour la reconnaître plus
/// vite la prochaine fois qu'elle est à portée (sans avoir à tout
/// redécouvrir depuis zéro).
class PeerRecord {
  /// Identifiant unique de cette personne (une longue suite de lettres et
  /// chiffres, générée une fois pour toutes — jamais son vrai nom).
  final String peerId;
  final String pseudo;
  final String role;
  /// Par quels « chemins » on peut la joindre (Bluetooth, Wi-Fi...).
  final List<String> transports;
  final String platform;
  final List<String> interestGroups;
  /// Fiabilité de la connexion avec cette personne, entre 0 (jamais fiable)
  /// et 1 (toujours fiable) — comme une note de confiance.
  final double reliability;
  /// La dernière fois qu'on l'a vue à portée.
  final DateTime lastSeen;
  final int totalMessagesExchanged;

  /// Clé publique X25519 (base64) de ce pair, si déjà échangée — utilisée
  /// pour dériver le secret partagé du chiffrement de bout en bout.
  ///
  /// En mots simples : c'est le « cadenas » que cette personne a partagé
  /// avec tout le monde. Combiné à MA clé secrète à moi, ça permet de
  /// fabriquer un code secret que seuls elle et moi connaissons — sans que
  /// personne d'autre sur le réseau ne puisse le deviner.
  final String? publicKey;

  /// Vrai si ce pair a été vérifié hors-bande (QR code, code de sécurité).
  ///
  /// « Hors-bande » veut dire : vérifié par un AUTRE moyen que le réseau
  /// mesh lui-même (par exemple en scannant son QR code en vrai, en face à
  /// face) — pour être sûr à 100% que c'est bien la bonne personne, et pas
  /// quelqu'un qui essaierait de se faire passer pour elle.
  final bool verified;

  /// Clé publique confirmée lors de la vérification hors-bande. Si elle
  /// diffère de [publicKey] courant, la clé a changé depuis la vérification
  /// (nouvel appareil, réinstallation, ou usurpation potentielle) — l'UI
  /// doit avertir plutôt qu'afficher le badge vérifié.
  final String? verifiedPublicKey;

  const PeerRecord({
    required this.peerId,
    required this.pseudo,
    this.role = 'leaf',
    this.transports = const [],
    this.platform = 'unknown',
    this.interestGroups = const [],
    this.reliability = 1.0,
    required this.lastSeen,
    this.totalMessagesExchanged = 0,
    this.publicKey,
    this.verified = false,
    this.verifiedPublicKey,
  });

  /// Vrai si la clé publique courante correspond à celle vérifiée
  /// hors-bande (donc que la vérification est toujours valable).
  bool get isVerifiedAndCurrent =>
      verified && verifiedPublicKey != null && verifiedPublicKey == publicKey;

  /// Vrai si ce pair a été vérifié par le passé mais que sa clé publique a
  /// changé depuis — situation à signaler à l'utilisateur.
  bool get keyChangedSinceVerification =>
      verified && verifiedPublicKey != null && verifiedPublicKey != publicKey;

  /// Fabrique une copie de cette fiche, en changeant seulement ce qu'on
  /// précise (le reste reste identique).
  PeerRecord copyWith({
    String? pseudo,
    String? role,
    List<String>? transports,
    String? platform,
    List<String>? interestGroups,
    double? reliability,
    DateTime? lastSeen,
    int? totalMessagesExchanged,
    String? publicKey,
    bool? verified,
    String? verifiedPublicKey,
  }) {
    return PeerRecord(
      peerId: peerId,
      pseudo: pseudo ?? this.pseudo,
      role: role ?? this.role,
      transports: transports ?? this.transports,
      platform: platform ?? this.platform,
      interestGroups: interestGroups ?? this.interestGroups,
      reliability: reliability ?? this.reliability,
      lastSeen: lastSeen ?? this.lastSeen,
      totalMessagesExchanged: totalMessagesExchanged ?? this.totalMessagesExchanged,
      publicKey: publicKey ?? this.publicKey,
      verified: verified ?? this.verified,
      verifiedPublicKey: verifiedPublicKey ?? this.verifiedPublicKey,
    );
  }

  /// Transforme la fiche en texte (pour la ranger dans le classeur permanent).
  Map<String, dynamic> toJson() => {
    'peerId': peerId,
    'pseudo': pseudo,
    'role': role,
    'transports': transports,
    'platform': platform,
    'interestGroups': interestGroups,
    'reliability': reliability,
    'lastSeen': lastSeen.toIso8601String(),
    'totalMessagesExchanged': totalMessagesExchanged,
    'publicKey': publicKey,
    'verified': verified,
    'verifiedPublicKey': verifiedPublicKey,
  };

  /// Relit du texte et reconstruit la fiche d'origine.
  factory PeerRecord.fromJson(Map<String, dynamic> json) => PeerRecord(
    peerId: json['peerId'] as String,
    pseudo: json['pseudo'] as String,
    role: json['role'] as String? ?? 'leaf',
    transports: (json['transports'] as List?)?.cast<String>() ?? [],
    platform: json['platform'] as String? ?? 'unknown',
    interestGroups: (json['interestGroups'] as List?)?.cast<String>() ?? [],
    reliability: (json['reliability'] as num?)?.toDouble() ?? 1.0,
    lastSeen: DateTime.parse(json['lastSeen'] as String),
    totalMessagesExchanged: json['totalMessagesExchanged'] as int? ?? 0,
    publicKey: json['publicKey'] as String?,
    verified: json['verified'] as bool? ?? false,
    verifiedPublicKey: json['verifiedPublicKey'] as String?,
  );
}

/// Un message tel qu'il apparaît dans une conversation — le cœur de toute
/// l'app. Peut être du texte, une photo, un fichier ou un message vocal :
/// c'est le champ [type] (et les champs image/audio/fichier ci-dessous) qui
/// disent lequel.
class MeshMessage {
  final String id;
  final String authorPseudo;
  final String content;

  /// ID du pair émetteur (wire: `s`).
  ///
  /// « wire » = comment ce champ s'appelle une fois compressé pour voyager
  /// sur le réseau (une lettre au lieu d'un mot entier, pour que le
  /// message pèse le moins lourd possible — important en Bluetooth, qui
  /// est très lent).
  final String? senderId;

  /// ID du pair destinataire — null = diffusion mesh (broadcast),
  /// non null = message 1:1 dirigé (wire: `t`).
  final String? targetId;

  /// ID du groupe destinataire (wire: `g`) — distinct de [targetId], qui
  /// reste réservé à l'adressage 1:1. Null pour les messages 1:1/diffusion.
  final String? groupId;
  final String type;
  final List<String> reactions;
  final DateTime timestamp;
  final String? imageUrl;
  final String? audioUrl;

  /// Combien de « sauts » (de téléphone en téléphone) ce message peut
  /// encore faire avant qu'on arrête de le relayer — comme un jeu de
  /// téléphone arabe qui s'arrête après un certain nombre de joueurs, pour
  /// ne pas tourner en rond sur le réseau pour toujours.
  final int hopCount;
  final String? fileId;
  final String? fileName;
  final int? fileSize;
  final String? fileMimeType;
  final String? replyToId;
  final MessageStatus status;
  final String? routeInfo;

  /// Horodatage de lecture par le destinataire (reçu/`lu`).
  final DateTime? readAt;

  /// Nombre de pairs ayant confirmé la réception (ACK).
  ///
  /// « ACK » (accusé de réception) = un petit mot que le destinataire
  /// renvoie automatiquement pour dire « bien reçu ! », comme un accusé de
  /// réception postal.
  final int deliveryCount;

  /// Effet de message façon Telegram/iMessage (slam/loud/gentle/invisible_ink
  /// pour la bulle, confetti/fireworks/hearts pour le plein écran) —
  /// délibérément TRANSITOIRE : absent de [toJson]/[fromJson] et donc jamais
  /// persisté en base. Ne doit se jouer qu'une fois, au moment précis où le
  /// message vient d'être envoyé ou reçu ; le garder hors de la
  /// sérialisation garantit qu'il ne rejoue jamais après un redémarrage ou
  /// un rechargement de l'historique.
  final String? effect;

  /// Nom d'affichage de l'auteur original si ce message a été transféré
  /// (forward) depuis un autre message — null si le message est original.
  final String? forwardedFrom;

  /// Date de la dernière édition du message. Null si le message n'a
  /// jamais été modifié. Affiché comme « modifié » dans la bulle.
  final DateTime? editedAt;

  /// Durée de vie du message en secondes. Null = pas de disparition.
  /// Quand le destinataire lit le message, un timer démarre et le
  /// message est supprimé quand il atteint cette durée.
  final int? expiresInSeconds;

  /// Timestamp de la première lecture du message par le destinataire.
  /// Utilisé pour calculer quand le message doit disparaître.
  final DateTime? firstReadAt;

  /// ID du fil de discussion. Tous les messages d'une même conversation
  /// en réponse à un message original partagent le même threadId.
  /// Null si le message n'est pas dans un fil.
  final String? threadId;

  const MeshMessage({
    required this.id,
    required this.authorPseudo,
    required this.content,
    this.type = 'text',
    this.reactions = const [],
    required this.timestamp,
    this.senderId,
    this.targetId,
    this.groupId,
    this.imageUrl,
    this.audioUrl,
    this.hopCount = 0,
    this.fileId,
    this.fileName,
    this.fileSize,
    this.fileMimeType,
    this.replyToId,
    this.status = MessageStatus.sent,
    this.routeInfo,
    this.readAt,
    this.deliveryCount = 0,
    this.effect,
    this.forwardedFrom,
    this.editedAt,
    this.expiresInSeconds,
    this.firstReadAt,
    this.threadId,
  });

  /// Fabrique une copie de ce message, en changeant seulement ce qu'on
  /// précise (le reste reste identique).
  MeshMessage copyWith({
    String? id,
    String? authorPseudo,
    String? content,
    String? type,
    List<String>? reactions,
    DateTime? timestamp,
    String? senderId,
    String? targetId,
    String? groupId,
    String? imageUrl,
    String? audioUrl,
    int? hopCount,
    String? fileId,
    String? fileName,
    int? fileSize,
    String? fileMimeType,
    String? replyToId,
    MessageStatus? status,
    String? routeInfo,
    DateTime? readAt,
    int? deliveryCount,
    String? effect,
    String? forwardedFrom,
    DateTime? editedAt,
    int? expiresInSeconds,
    DateTime? firstReadAt,
    String? threadId,
  }) {
    return MeshMessage(
      id: id ?? this.id,
      authorPseudo: authorPseudo ?? this.authorPseudo,
      content: content ?? this.content,
      type: type ?? this.type,
      reactions: reactions ?? this.reactions,
      timestamp: timestamp ?? this.timestamp,
      senderId: senderId ?? this.senderId,
      targetId: targetId ?? this.targetId,
      groupId: groupId ?? this.groupId,
      imageUrl: imageUrl ?? this.imageUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      hopCount: hopCount ?? this.hopCount,
      fileId: fileId ?? this.fileId,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      fileMimeType: fileMimeType ?? this.fileMimeType,
      replyToId: replyToId ?? this.replyToId,
      status: status ?? this.status,
      routeInfo: routeInfo ?? this.routeInfo,
      readAt: readAt ?? this.readAt,
      deliveryCount: deliveryCount ?? this.deliveryCount,
      effect: effect ?? this.effect,
      forwardedFrom: forwardedFrom ?? this.forwardedFrom,
      editedAt: editedAt ?? this.editedAt,
      expiresInSeconds: expiresInSeconds ?? this.expiresInSeconds,
      firstReadAt: firstReadAt ?? this.firstReadAt,
      threadId: threadId ?? this.threadId,
    );
  }

  /// Transforme le message en texte (pour le ranger dans le classeur
  /// permanent). Remarque : [effect] n'est volontairement PAS inclus ici
  /// (voir son explication plus haut).
  Map<String, dynamic> toJson() => {
    'id': id,
    'authorPseudo': authorPseudo,
    'content': content,
    'type': type,
    'reactions': reactions,
    'timestamp': timestamp.toIso8601String(),
    'senderId': senderId,
    'targetId': targetId,
    'groupId': groupId,
    'imageUrl': imageUrl,
    'audioUrl': audioUrl,
    'hopCount': hopCount,
    'fileId': fileId,
    'fileName': fileName,
    'fileSize': fileSize,
    'fileMimeType': fileMimeType,
    'replyToId': replyToId,
    'status': status.name,
    'routeInfo': routeInfo,
    'readAt': readAt?.toIso8601String(),
    'deliveryCount': deliveryCount,
    'forwardedFrom': forwardedFrom,
    'editedAt': editedAt?.toIso8601String(),
    'expiresInSeconds': expiresInSeconds,
    'firstReadAt': firstReadAt?.toIso8601String(),
    'threadId': threadId,
  };

  /// Relit du texte et reconstruit le message d'origine.
  factory MeshMessage.fromJson(Map<String, dynamic> json) => MeshMessage(
    id: json['id'] as String,
    authorPseudo: json['authorPseudo'] as String,
    content: json['content'] as String,
    type: json['type'] as String? ?? 'text',
    reactions: (json['reactions'] as List?)?.cast<String>() ?? [],
    timestamp: DateTime.parse(json['timestamp'] as String),
    senderId: json['senderId'] as String?,
    targetId: json['targetId'] as String?,
    groupId: json['groupId'] as String?,
    imageUrl: json['imageUrl'] as String?,
    audioUrl: json['audioUrl'] as String?,
    hopCount: json['hopCount'] as int? ?? 0,
    fileId: json['fileId'] as String?,
    fileName: json['fileName'] as String?,
    fileSize: json['fileSize'] as int?,
    fileMimeType: json['fileMimeType'] as String?,
    replyToId: json['replyToId'] as String?,
    status: MessageStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => MessageStatus.sent,
    ),
    routeInfo: json['routeInfo'] as String?,
    readAt: json['readAt'] != null
        ? DateTime.tryParse(json['readAt'] as String)
        : null,
    deliveryCount: json['deliveryCount'] as int? ?? 0,
    forwardedFrom: json['forwardedFrom'] as String?,
    editedAt: json['editedAt'] != null
        ? DateTime.tryParse(json['editedAt'] as String)
        : null,
    expiresInSeconds: json['expiresInSeconds'] as int?,
    firstReadAt: json['firstReadAt'] != null
        ? DateTime.tryParse(json['firstReadAt'] as String)
        : null,
    threadId: json['threadId'] as String?,
  );
}

/// Membre d'un groupe de discussion (vue applicative de la table
/// `GroupMembers`).
///
/// « Vue applicative » = une version simplifiée et pratique d'une ligne de
/// la base de données, prête à être utilisée directement par l'app (au
/// lieu de manipuler les données brutes du classeur).
class GroupMemberRecord {
  final String peerId;
  final String role; // 'admin' | 'member'
  final DateTime addedAt;
  final DateTime? removedAt;
  final String addedBy;

  const GroupMemberRecord({
    required this.peerId,
    required this.role,
    required this.addedAt,
    this.removedAt,
    required this.addedBy,
  });

  /// Toujours membre du groupe (pas encore retiré) ?
  bool get isActive => removedAt == null;
  bool get isAdmin => role == 'admin';
}

/// Groupe de discussion à membres fixes (vue applicative de la table
/// `MeshGroups`).
class GroupInfo {
  final String id;
  final String name;
  final String? avatarUrl;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<GroupMemberRecord> members;

  const GroupInfo({
    required this.id,
    required this.name,
    this.avatarUrl,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.members = const [],
  });

  /// Seulement les membres qui n'ont pas quitté (ou été retirés) du groupe.
  List<GroupMemberRecord> get activeMembers =>
      members.where((m) => m.isActive).toList();

  bool isActiveMember(String peerId) =>
      activeMembers.any((m) => m.peerId == peerId);

  bool isAdmin(String peerId) =>
      activeMembers.any((m) => m.peerId == peerId && m.isAdmin);

  /// Fabrique une copie de ce groupe, en changeant seulement ce qu'on
  /// précise.
  GroupInfo copyWith({
    String? name,
    String? avatarUrl,
    DateTime? updatedAt,
    List<GroupMemberRecord>? members,
  }) {
    return GroupInfo(
      id: id,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      createdBy: createdBy,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      members: members ?? this.members,
    );
  }
}

/// Une personne visible sur le réseau mesh en ce moment (utilisé surtout
/// pour l'écran qui montre la « carte » des appareils autour de soi).
class MeshPeer {
  final String id;
  final String pseudo;
  final String? avatarUrl;
  /// Nombre de téléphones intermédiaires entre elle et moi (0 = connexion
  /// directe, pas de relais).
  final int hopCount;
  /// Force du signal, entre 0 (très faible) et 1 (excellent).
  final double signalStrength;
  /// Vrai si cette personne fait office de « passerelle » (elle aide à
  /// relayer les messages des autres plus loin dans le réseau).
  final bool isGateway;

  const MeshPeer({
    required this.id,
    required this.pseudo,
    this.avatarUrl,
    this.hopCount = 0,
    this.signalStrength = 1.0,
    this.isGateway = false,
  });
}

/// Direction de l'appel : est-ce moi qui appelle, ou est-ce qu'on m'appelle ?
enum CallDirection { outgoing, incoming }

/// État de connexion WebRTC (la technologie qui fait passer la voix d'un
/// téléphone à l'autre pendant un appel).
///   - `connecting`   : ça sonne / ça essaie de se connecter.
///   - `connected`    : l'appel est bien établi, on s'entend.
///   - `failed`       : la connexion n'a pas pu se faire.
///   - `disconnected` : l'appel est terminé.
enum CallConnectionState { connecting, connected, failed, disconnected }

/// Toutes les informations sur l'appel en cours (1 contre 1) — à quel
/// volume, avec qui, depuis combien de temps ça sonne, etc.
class CallState {
  final bool isMuted;
  final bool isSpeakerOn;
  final bool isCallActive;
  /// Le délai entre le moment où je parle et le moment où l'autre
  /// personne m'entend, en millièmes de seconde — plus c'est petit,
  /// mieux c'est.
  final int latencyMs;
  /// La quantité de données envoyées par seconde pendant l'appel — reflète
  /// un peu la qualité audio.
  final int bitrateKbps;
  final int hopCount;
  final String? peerPseudo;
  final String? peerId;
  final CallDirection direction;
  final CallConnectionState connectionState;
  /// Le volume de la voix en ce moment (0 = silence, 1 = très fort) — sert
  /// à dessiner une petite jauge qui bouge pendant qu'on parle.
  final double audioLevel;
  final bool isVideoEnabled;
  final bool isRemoteVideoActive;

  const CallState({
    this.isMuted = false,
    this.isSpeakerOn = false,
    this.isCallActive = false,
    this.latencyMs = 0,
    this.bitrateKbps = 0,
    this.hopCount = 0,
    this.peerPseudo,
    this.peerId,
    this.direction = CallDirection.outgoing,
    this.connectionState = CallConnectionState.disconnected,
    this.audioLevel = 0.0,
    this.isVideoEnabled = false,
    this.isRemoteVideoActive = false,
  });

  /// Fabrique une copie de cet état d'appel, en changeant seulement ce
  /// qu'on précise.
  CallState copyWith({
    bool? isMuted,
    bool? isSpeakerOn,
    bool? isCallActive,
    int? latencyMs,
    int? bitrateKbps,
    int? hopCount,
    String? peerPseudo,
    String? peerId,
    CallDirection? direction,
    CallConnectionState? connectionState,
    double? audioLevel,
    bool? isVideoEnabled,
    bool? isRemoteVideoActive,
  }) {
    return CallState(
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
      isCallActive: isCallActive ?? this.isCallActive,
      latencyMs: latencyMs ?? this.latencyMs,
      bitrateKbps: bitrateKbps ?? this.bitrateKbps,
      hopCount: hopCount ?? this.hopCount,
      peerPseudo: peerPseudo ?? this.peerPseudo,
      peerId: peerId ?? this.peerId,
      direction: direction ?? this.direction,
      connectionState: connectionState ?? this.connectionState,
      audioLevel: audioLevel ?? this.audioLevel,
      isVideoEnabled: isVideoEnabled ?? this.isVideoEnabled,
      isRemoteVideoActive: isRemoteVideoActive ?? this.isRemoteVideoActive,
    );
  }
}

/// Registre de points de contribution mesh — un peu comme un compteur de
/// bonnes actions : plus ton téléphone aide à faire circuler les messages
/// des autres, plus tu gagnes de points.
///
/// ## Événements qui rapportent des points
/// | Événement | Points | Condition |
/// |-----------|--------|-----------|
/// | Relais de message réussi | +10 | message relayé à au moins un pair |
/// | Disponibilité relais | +2/min | temps passé en rôle gateway/superPeer |
class ContributionPoints {
  final int totalPoints;
  final int relaysCount;
  final int gatewayMinutes;

  const ContributionPoints({
    this.totalPoints = 0,
    this.relaysCount = 0,
    this.gatewayMinutes = 0,
  });

  /// Le badge (Bronze, Argent...) qui correspond au total de points actuel.
  ContributionRank get rank => ContributionRank.fromPoints(totalPoints);
}

/// Palier cosmétique déduit du total de points — aucune fonctionnalité
/// déblocable associée, juste un badge de reconnaissance pour les
/// appareils qui relaient le plus pour les autres.
///
/// Comme les ceintures au judo : ça ne débloque rien de spécial, c'est
/// juste une belle médaille qui montre que tu as beaucoup aidé.
enum ContributionRank {
  bronze(0, 'Bronze'),
  argent(100, 'Argent'),
  or(500, 'Or'),
  diamant(2000, 'Diamant');

  final int minPoints;
  final String label;
  const ContributionRank(this.minPoints, this.label);

  /// Trouve le meilleur badge possible pour un total de points donné.
  static ContributionRank fromPoints(int points) {
    ContributionRank best = ContributionRank.bronze;
    for (final rank in ContributionRank.values) {
      if (points >= rank.minPoints) best = rank;
    }
    return best;
  }

  /// Palier suivant, ou null si déjà au maximum.
  ContributionRank? get next {
    final values = ContributionRank.values;
    final i = values.indexOf(this);
    return i + 1 < values.length ? values[i + 1] : null;
  }
}

/// Un instantané des statistiques du réseau mesh — pour l'écran qui montre
/// « comment ça se passe » (combien de pairs autour, combien de données
/// partagées, etc.).
class MeshStats {
  final double distributedGb;
  final int relayedFiles;
  final int helpedPeers;
  final int totalPeers;
  final int blePeers;
  final int wifiPeers;
  final int nativePeers;

  /// Points de contribution (relais rendus au mesh).
  final ContributionPoints contribution;

  /// Fiabilité moyenne des transports (0.0 – 1.0).
  final double averageReliability;

  /// Nombre de messages envoyés depuis le démarrage.
  final int messagesSent;

  /// Nombre d'ACK reçus (total).
  final int acksReceived;

  const MeshStats({
    this.distributedGb = 4.2,
    this.relayedFiles = 12,
    this.helpedPeers = 8,
    this.totalPeers = 42,
    this.blePeers = 0,
    this.wifiPeers = 0,
    this.nativePeers = 0,
    this.contribution = const ContributionPoints(),
    this.averageReliability = 1.0,
    this.messagesSent = 0,
    this.acksReceived = 0,
  });
}

/// Check-in "je suis en sécurité" reçu d'un pair (mode urgence/catastrophe).
/// Diffusé publiquement à tout le mesh — la localisation, si incluse, est
/// arrondie côté émetteur avant envoi (jamais la position exacte).
///
/// C'est le mode « je vais bien » qu'on active en cas de catastrophe (genre
/// tremblement de terre) pour rassurer tout le monde autour, même sans
/// Internet.
class SafetyCheckinRecord {
  final String peerId;
  final String pseudo;
  final DateTime timestamp;
  final double? lat;
  final double? lon;
  final String? helpRequest;
  final int? batteryLevel;

  const SafetyCheckinRecord({
    required this.peerId,
    required this.pseudo,
    required this.timestamp,
    this.lat,
    this.lon,
    this.helpRequest,
    this.batteryLevel,
  });

  bool get hasLocation => lat != null && lon != null;
  bool get isHelpRequest => helpRequest != null;

  Map<String, dynamic> toJson() => {
    'peerId': peerId,
    'pseudo': pseudo,
    'timestamp': timestamp.toIso8601String(),
    'lat': lat,
    'lon': lon,
    'helpRequest': helpRequest,
    'batteryLevel': batteryLevel,
  };

  factory SafetyCheckinRecord.fromJson(Map<String, dynamic> json) => SafetyCheckinRecord(
    peerId: json['peerId'] as String,
    pseudo: json['pseudo'] as String,
    timestamp: DateTime.parse(json['timestamp'] as String),
    lat: (json['lat'] as num?)?.toDouble(),
    lon: (json['lon'] as num?)?.toDouble(),
    helpRequest: json['helpRequest'] as String?,
    batteryLevel: (json['batteryLevel'] as num?)?.toInt(),
  );
}

/// Statut éphémère (texte, façon "Statuts" WhatsApp) — diffusé publiquement
/// à tout le mesh, expire après [expiresAt] (24h par défaut à la création).
///
/// « Éphémère » = qui ne dure pas longtemps, comme un dessin à la craie sur
/// un trottoir qui s'efface avec la pluie. Après 24 heures, ce statut
/// disparaît tout seul.
class MeshStatusRecord {
  final String id;
  final String authorId;
  final String authorPseudo;
  final String content;
  final DateTime createdAt;
  final DateTime expiresAt;

  const MeshStatusRecord({
    required this.id,
    required this.authorId,
    required this.authorPseudo,
    required this.content,
    required this.createdAt,
    required this.expiresAt,
  });

  /// Vrai si les 24h sont passées et que ce statut doit disparaître.
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

/// Accusé de vue d'un statut — qui l'a vu et quand (façon « Vu par » de
/// WhatsApp), reçu uniquement par l'auteur du statut concerné.
class StatusViewRecord {
  final String viewerId;
  final String viewerPseudo;
  final DateTime viewedAt;

  const StatusViewRecord({
    required this.viewerId,
    required this.viewerPseudo,
    required this.viewedAt,
  });
}

/// État de connexion d'un participant à un appel de groupe (une personne
/// à la fois dans un appel à plusieurs).
enum GroupCallParticipantState { connecting, connected, failed, disconnected }

/// Un participant à un appel de groupe (voix uniquement, maillage complet
/// sans serveur — modèle séparé de [CallState] pour ne jamais toucher au
/// chemin d'appel 1:1 existant).
class GroupCallParticipant {
  final String peerId;
  final String pseudo;
  final GroupCallParticipantState state;

  const GroupCallParticipant({
    required this.peerId,
    required this.pseudo,
    this.state = GroupCallParticipantState.connecting,
  });

  /// Fabrique une copie de ce participant, en changeant seulement son état.
  GroupCallParticipant copyWith({GroupCallParticipantState? state}) {
    return GroupCallParticipant(peerId: peerId, pseudo: pseudo, state: state ?? this.state);
  }
}

/// État d'un appel de groupe en cours — plafonné à 4 participants (voir
/// [GroupWebrtcCallService.maxParticipants]), voix uniquement.
class GroupCallState {
  final bool isActive;
  final String? groupId;
  final String? groupName;
  final List<GroupCallParticipant> participants;
  final bool isMuted;
  final bool isSpeakerOn;

  const GroupCallState({
    this.isActive = false,
    this.groupId,
    this.groupName,
    this.participants = const [],
    this.isMuted = false,
    this.isSpeakerOn = false,
  });

  /// Fabrique une copie de cet état d'appel de groupe, en changeant
  /// seulement ce qu'on précise.
  GroupCallState copyWith({
    bool? isActive,
    String? groupId,
    String? groupName,
    List<GroupCallParticipant>? participants,
    bool? isMuted,
    bool? isSpeakerOn,
  }) {
    return GroupCallState(
      isActive: isActive ?? this.isActive,
      groupId: groupId ?? this.groupId,
      groupName: groupName ?? this.groupName,
      participants: participants ?? this.participants,
      isMuted: isMuted ?? this.isMuted,
      isSpeakerOn: isSpeakerOn ?? this.isSpeakerOn,
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  JOURNAL D'APPELS
// ─────────────────────────────────────────────────────────────

/// Comment un appel s'est terminé.
enum CallOutcome {
  /// Décroché — la conversation a bien eu lieu.
  answered,

  /// Sonné sans que personne ne décroche.
  missed,

  /// L'appel n'a jamais pu s'établir (pair hors de portée, échec réseau).
  failed,
}

/// Une ligne du journal d'appels.
///
/// Droplet n'enregistrait AUCUN appel jusqu'ici : l'onglet « Appels »
/// fabriquait un faux historique à partir de la liste des pairs
/// connectés (« il y a 3h », « il y a 6h »… en réalité de simples
/// multiples de l'indice dans la liste). Ce modèle, et le stockage qui
/// l'accompagne, remplacent cette illusion par de vraies traces.
class CallLogEntry {
  final String id;
  final String peerId;
  final String peerPseudo;

  /// Qui a lancé l'appel.
  final CallDirection direction;

  final CallOutcome outcome;

  /// Quand la sonnerie a commencé.
  final DateTime startedAt;

  /// Durée de la conversation elle-même — zéro pour un appel manqué ou
  /// échoué, puisque rien n'a été dit.
  final Duration duration;

  const CallLogEntry({
    required this.id,
    required this.peerId,
    required this.peerPseudo,
    required this.direction,
    required this.outcome,
    required this.startedAt,
    this.duration = Duration.zero,
  });

  /// Un appel manqué, c'est-à-dire non décroché ET entrant. Un appel
  /// sortant sans réponse n'est pas « manqué » : c'est moi qui ai appelé,
  /// je n'ai rien raté.
  bool get isMissedIncoming =>
      outcome == CallOutcome.missed && direction == CallDirection.incoming;

  Map<String, dynamic> toJson() => {
        'id': id,
        'peerId': peerId,
        'peerPseudo': peerPseudo,
        'direction': direction.name,
        'outcome': outcome.name,
        'startedAt': startedAt.toIso8601String(),
        'durationMs': duration.inMilliseconds,
      };

  factory CallLogEntry.fromJson(Map<String, dynamic> json) => CallLogEntry(
        id: json['id'] as String,
        peerId: json['peerId'] as String,
        peerPseudo: json['peerPseudo'] as String? ?? 'Inconnu',
        direction: CallDirection.values.firstWhere(
          (d) => d.name == json['direction'],
          orElse: () => CallDirection.incoming,
        ),
        outcome: CallOutcome.values.firstWhere(
          (o) => o.name == json['outcome'],
          orElse: () => CallOutcome.failed,
        ),
        startedAt: DateTime.parse(json['startedAt'] as String),
        duration: Duration(milliseconds: (json['durationMs'] as int?) ?? 0),
      );
}
