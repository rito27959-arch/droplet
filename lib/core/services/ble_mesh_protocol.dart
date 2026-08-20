// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Le Bluetooth (BLE, pour « Bluetooth Low Energy », une version qui
// consomme très peu de batterie) a un GROS défaut : il ne peut envoyer
// qu'un TOUT PETIT bout de message à la fois — environ 20 lettres
// seulement ! C'est comme essayer d'envoyer une lettre entière en écrivant
// un mot par carte postale.
//
// Ce fichier résout ce problème : il découpe un message trop long en plein
// de petits « chunks » (morceaux), chacun assez petit pour tenir dans une
// carte postale Bluetooth, avec un numéro dessus pour savoir dans quel
// ordre les remettre bout à bout à l'arrivée — un peu comme les pièces
// numérotées d'un puzzle.
//
// Il définit aussi les « adresses » (UUID) des différentes boîtes aux
// lettres Bluetooth de l'app, et tous les petits codes numériques qui
// disent « c'est quel genre de message ? » (du texte ? un fichier ? un
// signe de vie ?).
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';
import 'package:uuid/uuid.dart';

/// UUID de service BLE dédié à OURO PREP.
/// Généré une fois, doit être identique sur tous les appareils de l'app.
///
/// Un « UUID » est une très longue adresse unique — pense-y comme au nom
/// de la « chaîne de radio Bluetooth » que Droplet utilise pour se faire
/// repérer par d'autres téléphones Droplet, et par eux seulement.
const String kMeshServiceUuid = '3c0a1234-5678-4abc-9def-0123456789ab';

/// Characteristic "presence" : en notify/read, chaque pair annonce
/// {peerId, pseudo, hopCount} au format JSON.
///
/// Une « characteristic », en Bluetooth, c'est comme une boîte aux lettres
/// précise à l'intérieur de la grande adresse ci-dessus. Celle-ci sert de
/// panneau « je suis là, voici qui je suis » que les autres peuvent
/// consulter.
const String kPresenceCharUuid = '3c0a1234-5678-4abc-9def-0123456789ac';

/// Characteristic "inbox" : en write (sans réponse), réception des messages
/// entrants. Les messages sont envoyés en chunks si nécessaire.
/// Toujours écrite par un *central* vers le *périphérique* auquel il est
/// connecté (sens central → périphérique).
///
/// En Bluetooth, il y a toujours un « central » (celui qui va chercher/se
/// connecte) et un « périphérique » (celui qu'on trouve/auquel on se
/// connecte) — comme quelqu'un qui frappe à une porte (central) et
/// quelqu'un qui l'ouvre (périphérique). Cette boîte aux lettres ne
/// fonctionne que dans UN sens : celui qui frappe peut y déposer des
/// lettres, pas l'inverse.
const String kInboxCharUuid = '3c0a1234-5678-4abc-9def-0123456789ad';

/// Characteristic "downlink" : en notify, permet à un *périphérique*
/// d'envoyer des messages au *central* qui lui est connecté (sens
/// périphérique → central). En BLE, un périphérique ne peut jamais écrire
/// directement chez un central — seule la notification sur une
/// characteristic à laquelle le central s'est abonné le permet. Nécessaire
/// car chaque appareil du mesh joue les deux rôles simultanément (central
/// ET périphérique), donc chaque sens de communication a besoin de son
/// propre mécanisme GATT.
///
/// C'est la boîte aux lettres dans l'AUTRE sens : celui qui a ouvert la
/// porte (périphérique) peut aussi répondre, mais seulement en « agitant
/// un drapeau » (notify) que celui qui a frappé (central) doit avoir
/// accepté de regarder à l'avance.
const String kDownlinkCharUuid = '3c0a1234-5678-4abc-9def-0123456789ae';

/// Taille max d'une écriture BLE sans négociation MTU.
/// En pratique, on peut écrire 20 bytes sans MTU, mais certains OS
/// supportent plus. On reste conservateur pour la compatibilité max.
const int kMaxBleWriteSize = 20;

/// Type pour le transfert de fichiers dans le forum.
const int kFileTransferType = 0x30;
const int kTextMessageType = 0x01;
const int kTypingIndicator = 0x02;
const int kTypingStop = 0x03;
const int kAckType = 0x04;

/// Poignée de main BLE : un *central* nouvellement connecté envoie ce
/// message sur la characteristic inbox pour s'identifier auprès du
/// *périphérique* (qui ne peut jamais lire l'identité d'un central qui se
/// connecte à lui — seule la characteristic "presence" côté périphérique
/// est lisible par le central, pas l'inverse).
const int kHelloType = 0x09;

/// Annonce de routes : « voici les destinations que je sais joindre, et à
/// combien de sauts ».
///
/// ⚠️ C'EST CE QUI REND LE MULTI-SAUT INTELLIGENT.
///
/// Sans cette annonce, la table de routage ne contient que des voisins
/// DIRECTS : personne n'apprend jamais qu'un pair hors de portée est
/// joignable à travers un autre. Un message pour un destinataire lointain
/// était alors DIFFUSÉ à tout le monde, à charge pour le réseau de le
/// faire suivre jusqu'à épuisement du compteur de sauts — ça marche, mais
/// ça réveille toutes les radios à portée pour un seul destinataire.
///
/// Avec elle, chaque appareil apprend « pour atteindre C, passe par B »,
/// et le message ne suit qu'un chemin.
const int kRouteAnnounceType = 0x0A;

/// Types pour les quiz pair-à-pair.
const int kQuizChallenge = 0x05;
const int kQuizAccept = 0x06;
const int kQuizAnswerSheet = 0x07;
const int kQuizResult = 0x08;

/// Types de messages de contrôle pour le transfert de contenu viral.
/// Ces messages transitent par BLE (contrôle), les payloads par Wi-Fi.
const int kContentTypeAnnouncement = 0x20;
const int kContentTypeRequest = 0x21;
const int kContentTypeChunkOffer = 0x22;
const int kContentTypeChunkRequest = 0x23;
const int kContentTypeChunkData = 0x24;
const int kContentTypeResumeRequest = 0x25;
const int kContentTypeResumeOffer = 0x26;
const int kContentTypeManifest = 0x27;
const int kContentTypeDiffOffer = 0x28;
const int kContentTypeComplete = 0x29;

// Les constantes kContentChunkSize et kMaxConcurrentChunks
// sont définies dans content_transfer_protocol.dart

/// En-tête de chunk : 1 byte d'identifiant de chunk.
/// 0x00 = message complet tient dans ce chunk unique
/// 0x01 = premier chunk d'un message multi-chunk
/// 0x02 = chunk intermédiaire
/// 0x03 = dernier chunk
///
/// C'est l'étiquette collée sur chaque « carte postale » du puzzle : elle
/// dit si c'est la SEULE carte (tout tient dedans), la PREMIÈRE, une
/// carte du MILIEU, ou la DERNIÈRE.
const int kChunkHeaderComplete = 0x00;
const int kChunkHeaderFirst = 0x01;
const int kChunkHeaderMiddle = 0x02;
const int kChunkHeaderLast = 0x03;

/// Message binaire format :
/// [messageId 16 bytes][hopCount 1 byte][type 1 byte][payloadLen 2 bytes][payload]
///
/// type :
///   0x00 = text/utf8
///   0x01 = json
///   0x02 = file metadata
///   0x03 = ping (keep-alive)
///   0x04 = pong
///
/// C'est cette classe qui sait DÉCOUPER un message en petits morceaux
/// avant l'envoi (`encodeMessage`), et RECOLLER les morceaux reçus pour
/// reformer le message d'origine (`decodeChunk`) — le cœur du « puzzle »
/// expliqué tout en haut du fichier.
class BleMeshProtocol {
  /// Taille maximale du payload dans un chunk unique (hors chunk header).
  /// Chunk header = 1 byte, message header = 20 bytes (16+1+1+2)
  /// Reste : 20 - 1 = 19 bytes par chunk pour les data brutes
  /// Message header = 20 bytes → un chunk peut contenir header + payload si
  /// payload ≤ (20 - 1 - 20) = -1 → impossible.
  /// Donc on envoie TOUJOURS le header dans le premier chunk, payload dans
  /// les chunks suivants. Un message d'au plus 19 bytes tient dans un chunk
  /// unique (header uniquement, pas de payload, c'est un message de contrôle).
  /// Pour simplifier, on traite tout message comme multi-chunk potentiel.

  /// Taille de payload par chunk (hors header de chunk).
  static const int _payloadPerChunk = kMaxBleWriteSize - 1;

  /// Encode un message en chunks BLE.
  /// Retourne une liste de Uint8List, chaque élément fait au plus
  /// kMaxBleWriteSize bytes.
  ///
  /// En clair : prend un message (avec son numéro unique, son compteur de
  /// sauts, son type, et son vrai contenu) et le découpe en une liste de
  /// petits paquets prêts à partir un par un sur Bluetooth.
  static List<Uint8List> encodeMessage({
    required String messageId,
    required int hopCount,
    required int type,
    required Uint8List payload,
  }) {
    final msgIdBytes = _hexToBytes(messageId.replaceAll('-', ''));
    final hopByte = Uint8List.fromList([hopCount.clamp(0, 255)]);
    final typeByte = Uint8List.fromList([type.clamp(0, 255)]);
    final payloadLen = Uint8List.fromList([
      (payload.length >> 8) & 0xFF,
      payload.length & 0xFF,
    ]);

    final header = Uint8List.fromList([
      ...msgIdBytes,
      ...hopByte,
      ...typeByte,
      ...payloadLen,
    ]);

    final totalPayload = Uint8List.fromList([...header, ...payload]);
    final chunks = <Uint8List>[];

    if (totalPayload.length <= _payloadPerChunk) {
      // Tout tient dans une seule petite carte postale.
      chunks.add(Uint8List.fromList([kChunkHeaderComplete, ...totalPayload]));
    } else {
      // Trop gros pour une seule carte : on en découpe plusieurs, avec
      // « première », « milieu » (autant que nécessaire) et « dernière ».
      int offset = 0;
      chunks.add(Uint8List.fromList([
        kChunkHeaderFirst,
        ...totalPayload.sublist(offset, (offset + _payloadPerChunk).clamp(0, totalPayload.length)),
      ]));
      offset += _payloadPerChunk;

      while (offset < totalPayload.length) {
        final remaining = totalPayload.length - offset;
        final isLast = remaining <= _payloadPerChunk;
        final chunkSize = isLast ? remaining : _payloadPerChunk;
        chunks.add(Uint8List.fromList([
          isLast ? kChunkHeaderLast : kChunkHeaderMiddle,
          ...totalPayload.sublist(offset, offset + chunkSize),
        ]));
        offset += chunkSize;
      }
    }

    return chunks;
  }

  /// Décode et reassemble un message depuis un flux de chunks.
  /// Retourne null si le reassemblage n'est pas complet.
  ///
  /// À chaque nouveau petit paquet reçu, cette fonction regarde son
  /// étiquette : s'il est « complet » à lui seul, on peut tout de suite le
  /// décoder ; sinon, on le range dans le bon puzzle en cours (identifié
  /// par le numéro du message) jusqu'à ce que la « dernière carte » arrive
  /// et permette enfin de reconstituer le message entier.
  static BleDecodedMessage? decodeChunk(Uint8List chunk, Map<String, ChunkAssembly> assemblies) {
    if (chunk.isEmpty) return null;

    final header = chunk[0];
    final data = chunk.sublist(1);

    switch (header) {
      case kChunkHeaderComplete:
        return _parseMessageData(data);

      case kChunkHeaderFirst:
        final msgId = _extractMsgId(data);
        if (msgId == null) return null;
        assemblies[msgId] = ChunkAssembly(buffer: Uint8List.fromList(data));
        return null;

      case kChunkHeaderMiddle:
        if (data.length < 16) return null;
        final msgId = _extractMsgId(data);
        if (msgId == null || !assemblies.containsKey(msgId)) return null;
        assemblies[msgId]!.buffer = Uint8List.fromList([...assemblies[msgId]!.buffer, ...data]);
        return null;

      case kChunkHeaderLast:
        if (data.length < 16) return null;
        final msgId = _extractMsgId(data);
        if (msgId == null || !assemblies.containsKey(msgId)) return null;
        assemblies[msgId]!.buffer = Uint8List.fromList([...assemblies[msgId]!.buffer, ...data]);
        final full = assemblies.remove(msgId)!.buffer;
        return _parseMessageData(full);

      default:
        return null;
    }
  }

  static BleDecodedMessage? _parseMessageData(Uint8List data) {
    if (data.length < 20) return null;
    final msgId = _bytesToHex(data.sublist(0, 16));
    final hopCount = data[16];
    final type = data[17];
    final payloadLen = (data[18] << 8) | data[19];
    final payload = data.length > 20 ? data.sublist(20, (20 + payloadLen).clamp(20, data.length)) : Uint8List(0);

    return BleDecodedMessage(
      messageId: _formatUuid(msgId),
      hopCount: hopCount,
      type: type,
      payload: payload,
    );
  }

  static String? _extractMsgId(Uint8List data) {
    if (data.length < 16) return null;
    return _bytesToHex(data.sublist(0, 16));
  }

  // Petites fonctions de traduction entre octets bruts (des nombres) et
  // texte hexadécimal (des lettres/chiffres lisibles) — un peu comme
  // traduire entre deux langues qui disent la même chose différemment.
  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join('');
  }

  static Uint8List _hexToBytes(String hex) {
    final result = Uint8List(hex.length ~/ 2);
    for (int i = 0; i < result.length; i++) {
      result[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return result;
  }

  static String _formatUuid(String hex) {
    if (hex.length < 32) return hex;
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  static String generateMessageId() => const Uuid().v4();

  static Uint8List encodePayload(String content) => Uint8List.fromList(utf8.encode(content));

  static String decodePayload(Uint8List bytes) => utf8.decode(bytes);
}

/// Un message une fois COMPLÈTEMENT reconstitué à partir de ses chunks —
/// prêt à être compris par le reste de l'app.
class BleDecodedMessage {
  final String messageId;
  final int hopCount;
  final int type;
  final Uint8List payload;

  const BleDecodedMessage({
    required this.messageId,
    required this.hopCount,
    required this.type,
    required this.payload,
  });
}

/// État d'assemblage d'un message multi-chunk.
///
/// C'est la « table de puzzle en cours » : le petit tas de morceaux déjà
/// reçus pour un message précis, en attendant que tous les morceaux
/// soient arrivés.
class ChunkAssembly {
  Uint8List buffer;
  ChunkAssembly({required this.buffer});
}

/// Événements de pair dérivés des découvertes BLE — « telle personne vient
/// d'apparaître (ou de disparaître) sur le réseau ».
class MeshPeerEvent {
  final String peerId;
  final String pseudo;
  final int hopCount;
  final bool isConnected;
  final bool isGateway;
  final String platform;

  const MeshPeerEvent({
    required this.peerId,
    required this.pseudo,
    this.hopCount = 0,
    this.isConnected = true,
    this.isGateway = false,
    this.platform = 'unknown',
  });
}

/// Données reçues après réassemblage BLE — un message complet, prêt à être
/// transmis au reste de l'app pour être compris et affiché.
class MeshIncomingData {
  final String messageId;
  final String peerId;
  final Uint8List data;

  const MeshIncomingData({
    required this.messageId,
    required this.peerId,
    required this.data,
  });
}
