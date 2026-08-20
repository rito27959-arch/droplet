// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Ce qui accompagne un statut au-delà du texte : une photo, une vidéo ou
// un message vocal, et éventuellement une chanson prise dans le
// téléphone pour l'accompagner.
//
// ── Comment un statut avec média voyage sur le mesh ────────────────────
//
// En DEUX temps, et c'est important de comprendre pourquoi.
//
//   1. Le ou les FICHIERS partent d'abord, par le même canal que les
//      pièces jointes des conversations (le transfert de fichiers
//      découpé en morceaux, qui sait reprendre là où il s'est arrêté).
//      Une photo pèse souvent plusieurs centaines de kilo-octets : en
//      Bluetooth, cela prend un moment.
//   2. L'ANNONCE du statut part ensuite. Elle est minuscule et ne
//      contient que du texte : la légende, et les identifiants des
//      fichiers qui l'accompagnent.
//
// Le destinataire peut donc recevoir l'annonce avant d'avoir fini de
// recevoir la photo. C'est voulu : il voit tout de suite qu'il y a
// quelque chose de nouveau, et l'image se complète ensuite. L'inverse —
// tout attendre avant d'afficher quoi que ce soit — donnerait
// l'impression que rien ne se passe pendant une minute.
//
// ── Pourquoi la musique est un fichier séparé ? ────────────────────────
//
// Parce qu'elle est facultative et souvent bien plus lourde que le
// reste. En la gardant à part, un téléphone qui n'a reçu que la photo
// peut déjà l'afficher en silence, et la musique s'ajoute quand elle
// arrive. Elle est aussi coupée à trente secondes à l'envoi : personne
// n'a besoin d'une chanson entière pour accompagner une image qu'on
// regarde cinq secondes, et cela évite d'inonder un réseau lent.
// ============================================================================

/// Le genre de média attaché à un statut.
enum StatusMediaKind {
  /// Rien : un statut de texte seul, sur fond coloré.
  none,

  photo,
  video,

  /// Un message vocal — la voix, sans image.
  voice;

  static StatusMediaKind fromName(String? name) => StatusMediaKind.values
      .firstWhere((k) => k.name == name, orElse: () => StatusMediaKind.none);
}

/// Tout ce qu'un statut porte en plus de sa légende.
class StatusMedia {
  const StatusMedia({
    this.kind = StatusMediaKind.none,
    this.fileId,
    this.fileName,
    this.mimeType,
    this.durationMs,
    this.waveform,
    this.musicFileId,
    this.musicFileName,
    this.musicTitle,
    this.backgroundColor,
  });

  final StatusMediaKind kind;

  /// L'identifiant du fichier principal (photo, vidéo ou vocal), tel
  /// qu'il a été transmis. Null pour un statut de texte seul.
  final String? fileId;
  final String? fileName;
  final String? mimeType;

  /// Durée du vocal ou de la vidéo, en millièmes de seconde.
  final int? durationMs;

  /// Le dessin de la voix pour un statut vocal — même principe que dans
  /// les conversations : 48 valeurs entre 0 et 1, ici sous forme de
  /// chaîne compacte (voir `VoiceNoteMeta`).
  final String? waveform;

  /// La chanson qui accompagne, si l'auteur en a choisi une.
  final String? musicFileId;
  final String? musicFileName;

  /// Ce qu'on affiche à l'écran (« Titre — Artiste »), déduit du nom du
  /// fichier au moment du choix.
  final String? musicTitle;

  /// Pour un statut de texte seul : la couleur de fond choisie, en
  /// entier ARGB. Null = la couleur par défaut.
  final int? backgroundColor;

  bool get hasMedia => kind != StatusMediaKind.none && fileId != null;
  bool get hasMusic => musicFileId != null;

  /// Vrai quand ce statut n'a strictement rien de plus qu'un texte.
  bool get isPlainText => !hasMedia && !hasMusic && backgroundColor == null;

  StatusMedia copyWith({
    StatusMediaKind? kind,
    String? fileId,
    String? fileName,
    String? mimeType,
    int? durationMs,
    String? waveform,
    String? musicFileId,
    String? musicFileName,
    String? musicTitle,
    int? backgroundColor,
  }) {
    return StatusMedia(
      kind: kind ?? this.kind,
      fileId: fileId ?? this.fileId,
      fileName: fileName ?? this.fileName,
      mimeType: mimeType ?? this.mimeType,
      durationMs: durationMs ?? this.durationMs,
      waveform: waveform ?? this.waveform,
      musicFileId: musicFileId ?? this.musicFileId,
      musicFileName: musicFileName ?? this.musicFileName,
      musicTitle: musicTitle ?? this.musicTitle,
      backgroundColor: backgroundColor ?? this.backgroundColor,
    );
  }

  /// Les clés sont volontairement très courtes : ce bloc voyage dans
  /// chaque annonce de statut, y compris en Bluetooth où chaque octet
  /// compte.
  Map<String, dynamic> toJson() => {
        if (kind != StatusMediaKind.none) 'k': kind.name,
        if (fileId != null) 'f': fileId,
        if (fileName != null) 'fn': fileName,
        if (mimeType != null) 'm': mimeType,
        if (durationMs != null) 'd': durationMs,
        if (waveform != null) 'w': waveform,
        if (musicFileId != null) 'mf': musicFileId,
        if (musicFileName != null) 'mn': musicFileName,
        if (musicTitle != null) 'mt': musicTitle,
        if (backgroundColor != null) 'bg': backgroundColor,
      };

  factory StatusMedia.fromJson(Map<String, dynamic> json) => StatusMedia(
        kind: StatusMediaKind.fromName(json['k'] as String?),
        fileId: json['f'] as String?,
        fileName: json['fn'] as String?,
        mimeType: json['m'] as String?,
        durationMs: (json['d'] as num?)?.toInt(),
        waveform: json['w'] as String?,
        musicFileId: json['mf'] as String?,
        musicFileName: json['mn'] as String?,
        musicTitle: json['mt'] as String?,
        backgroundColor: (json['bg'] as num?)?.toInt(),
      );

  static const StatusMedia empty = StatusMedia();
}

// ─────────────────────────────────────────────────────────────
//  RÉACTIONS ET COMMENTAIRES
// ─────────────────────────────────────────────────────────────

/// Un « j'aime » ou un commentaire laissé sur le statut de quelqu'un.
///
/// ⚠️ CES RÉPONSES NE SONT ENVOYÉES QU'À L'AUTEUR DU STATUT, jamais
/// diffusées à tout le réseau — exactement comme sur WhatsApp, où
/// répondre à un statut ouvre une conversation privée avec la personne.
///
/// Ce n'est pas qu'une question de discrétion, c'est aussi ce qui rend
/// la chose RÉALISABLE ici. Un compteur public de « j'aime » supposerait
/// que tous les téléphones du réseau tombent d'accord sur un même
/// nombre. Sur un maillage où chacun ne voit qu'une poignée de voisins,
/// où les messages arrivent dans le désordre et où certains n'arrivent
/// jamais, cet accord est impossible à garantir : chacun afficherait un
/// compte différent. En n'envoyant qu'à l'auteur, une seule personne
/// tient le compte — et c'est justement la seule que ça intéresse.
class StatusFeedback {
  const StatusFeedback({
    required this.statusId,
    required this.authorId,
    required this.authorPseudo,
    required this.createdAt,
    this.emoji,
    this.text,
  });

  final String statusId;

  /// Qui a réagi (et non l'auteur du statut).
  final String authorId;
  final String authorPseudo;
  final DateTime createdAt;

  /// L'emoji d'un « j'aime ». Null pour un commentaire écrit.
  final String? emoji;

  /// Le texte d'un commentaire. Null pour un simple « j'aime ».
  final String? text;

  bool get isLike => emoji != null;

  Map<String, dynamic> toJson() => {
        'statusId': statusId,
        'authorId': authorId,
        'authorPseudo': authorPseudo,
        'createdAt': createdAt.toIso8601String(),
        if (emoji != null) 'emoji': emoji,
        if (text != null) 'text': text,
      };

  factory StatusFeedback.fromJson(Map<String, dynamic> json) => StatusFeedback(
        statusId: json['statusId'] as String,
        authorId: json['authorId'] as String,
        authorPseudo: json['authorPseudo'] as String? ?? 'Inconnu',
        createdAt:
            DateTime.tryParse(json['createdAt'] as String? ?? '') ??
                DateTime.now(),
        emoji: json['emoji'] as String?,
        text: json['text'] as String?,
      );
}
