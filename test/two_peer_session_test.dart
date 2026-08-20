// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// UNE SESSION À DEUX APPAREILS, SANS DEUXIÈME APPAREIL.
//
// On fait passer 100 messages, 20 fichiers et 10 positions entre Droplet
// et un FAUX PAIR — qui n'a de faux que la radio. Tout le reste est le
// vrai code :
//
//   • les vraies clés X25519, le vrai secret partagé, le vrai AES-GCM ;
//   • la vraie enveloppe de `sendMessage` (octet de saut, type, JSON) ;
//   • la vraie file d'attente `PremiumMessageQueue`, avec ses relances,
//     son backoff exponentiel et sa limite de cinq envois parallèles ;
//   • un pair qui DÉCHIFFRE réellement ce qu'il reçoit et refuse ce qui
//     est abîmé.
//
// ── Ce que ce banc mesure, et ce qu'il ne mesure pas ─────────────────
//
// IL MESURE le coût du logiciel : chiffrement, mise en forme, file,
// relances, et le nombre de messages qui arrivent bel et bien à
// destination sur un lien qui perd des paquets.
//
// IL NE MESURE PAS la radio. Personne ne peut simuler honnêtement un
// Bluetooth qui traverse un mur. Le temps d'antenne est donc CALCULÉ à
// partir de la taille réelle des trames et du débit connu de chaque
// transport — et affiché séparément, jamais mélangé au reste.
//
// ⚠️ CE N'EST PAS UN REMPLAÇANT D'UN VRAI ESSAI À DEUX TÉLÉPHONES. Cela
// répond à la moitié des questions — celle qui dépend du code. L'autre
// moitié (portée, murs, batterie, coupures) exige deux appareils.
// ============================================================================

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:droplet/core/network/premium_message_queue.dart';
import 'package:droplet/core/services/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────
//  LE LIEN
// ─────────────────────────────────────────────────────────────

/// Les caractéristiques d'un transport réel.
class LinkProfile {
  const LinkProfile({
    required this.name,
    required this.latency,
    required this.chunkPayload,
    required this.perChunkMicros,
    required this.lossRate,
    this.refusesFiles = false,
    this.maxPayload = 1 << 30,
    this.reportsRefusalAsSuccess = false,
  });

  final String name;

  /// Temps d'établissement avant le premier octet.
  final Duration latency;

  /// Octets utiles par écriture.
  ///
  /// ⚠️ POUR LE BLUETOOTH, C'EST 19. Ce n'est pas une approximation :
  /// `ble_mesh_protocol.dart` découpe à `kMaxBleWriteSize - 1`, soit
  /// 19 octets par écriture, sans négociation de MTU. C'est le chiffre
  /// qui décide de tout le reste.
  final int chunkPayload;

  /// Durée d'une écriture, de bout en bout.
  final int perChunkMicros;

  /// Proportion d'envois qui échouent et devront être relancés.
  final double lossRate;

  /// Le transport écarte-t-il les fichiers et les grosses charges ?
  final bool refusesFiles;

  /// Charge maximale acceptée, en octets.
  final int maxPayload;

  /// Quand le transport refuse une charge, la couche au-dessus le
  /// signale-t-elle comme un échec, ou comme un succès ?
  ///
  /// ── L'histoire de ce champ ────────────────────────────────────────
  ///
  /// Il valait `true` pour le Bluetooth, et ce n'était pas un choix :
  /// c'était le comportement de l'application. `sendToPeer` ne rendait
  /// rien, `sendViaRoute` répondait `true` dès que le pair était connu,
  /// et un refus devenait une livraison. Ce banc l'a mis en évidence :
  /// 130 « livrés » pour 110 reçus.
  ///
  /// Depuis, les trois transports rendent un booléen et la file reçoit
  /// la vérité. Le champ reste — il permet de REJOUER l'ancien défaut
  /// et de vérifier que le test le détecterait s'il revenait.
  final bool reportsRefusalAsSuccess;

  double get bytesPerSecond => chunkPayload * 1e6 / perChunkMicros;
}

/// Bluetooth Low Energy, tel que Droplet l'utilise réellement.
///
/// 19 octets par écriture, un intervalle de connexion de 30 ms sur
/// Android en pratique, quelques écritures par intervalle : on retient
/// 20 ms par écriture, ce qui est déjà optimiste. La perte de 3 % couvre
/// les déconnexions courtes et les collisions.
const bleProfile = LinkProfile(
  name: 'Bluetooth LE',
  latency: Duration(milliseconds: 250),
  chunkPayload: 19,
  perChunkMicros: 20000,
  lossRate: 0.03,
  refusesFiles: true,
  maxPayload: 512,
  // Le comportement CORRIGÉ : un refus est un échec, et la file le sait.
  reportsRefusalAsSuccess: false,
);

/// Le Bluetooth TEL QU'IL ÉTAIT avant le correctif — conservé pour
/// vérifier que le banc verrait le défaut revenir.
const bleProfileAvantCorrectif = LinkProfile(
  name: 'Bluetooth LE (ancien comportement)',
  latency: Duration(milliseconds: 250),
  chunkPayload: 19,
  perChunkMicros: 20000,
  lossRate: 0.03,
  refusesFiles: true,
  maxPayload: 512,
  reportsRefusalAsSuccess: true,
);

/// Wi-Fi local (TCP sur le même réseau) — le transport rapide.
const wifiProfile = LinkProfile(
  name: 'Wi-Fi local',
  latency: Duration(milliseconds: 8),
  chunkPayload: 4096,
  perChunkMicros: 4000,
  lossRate: 0.005,
);

// ─────────────────────────────────────────────────────────────
//  LE FAUX PAIR
// ─────────────────────────────────────────────────────────────

/// Un correspondant qui se comporte comme un vrai : il possède sa propre
/// paire de clés, dérive le même secret partagé, et DÉCHIFFRE ce qu'on
/// lui envoie. Un message abîmé est refusé, comme il le serait sur un
/// vrai téléphone.
class FakePeer {
  FakePeer._(this.id, this._keyPair, this.publicKeyB64);

  static Future<FakePeer> create(String id) async {
    final algorithm = X25519();
    final keyPair = await algorithm.newKeyPair();
    final publicKey = await keyPair.extractPublicKey();
    return FakePeer._(id, keyPair, base64Encode(publicKey.bytes));
  }

  final String id;
  final SimpleKeyPair _keyPair;
  final String publicKeyB64;

  SecretKey? _shared;

  int received = 0;
  int rejected = 0;
  final List<String> plaintexts = [];

  /// Dérive le secret partagé avec l'autre partie — exactement ce que
  /// fait `CryptoService.sharedKeyWithPeer`, mais avec la clé de ce
  /// pair-ci.
  Future<void> handshake(String otherPublicKeyB64) async {
    final algorithm = X25519();
    final remote = SimplePublicKey(
      base64Decode(otherPublicKeyB64),
      type: KeyPairType.x25519,
    );
    _shared = await algorithm.sharedSecretKey(
      keyPair: _keyPair,
      remotePublicKey: remote,
    );
  }

  /// Reçoit une trame brute, la décode et la déchiffre.
  ///
  /// Renvoie `false` si quoi que ce soit cloche — c'est le comportement
  /// d'un vrai destinataire, et c'est ce qui permet de vérifier que le
  /// chiffrement fait l'aller-retour sans se perdre.
  Future<bool> receive(Uint8List frame) async {
    try {
      if (frame.length < 3) return _reject();

      // Un paquet FICHIER n'est pas du JSON : c'est
      // [saut, type, longueur des métadonnées sur 2 octets, JSON,
      // contenu chiffré brut].
      if (frame[1] == 0x30) {
        final metaLen = (frame[2] << 8) | frame[3];
        final meta = json.decode(utf8.decode(frame.sublist(4, 4 + metaLen)))
            as Map<String, dynamic>;
        final clear = await CryptoService.decryptBytes(
          _shared!,
          Uint8List.sublistView(frame, 4 + metaLen),
          base64Decode(meta['n'] as String),
        );
        if (clear == null) return _reject();
        received++;
        return true;
      }

      // L'enveloppe d'un message : [saut, type, JSON].
      final payload = utf8.decode(frame.sublist(2));
      final map = json.decode(payload) as Map<String, dynamic>;

      if (map['e'] == true) {
        final clear = await CryptoService.decryptBytes(
          _shared!,
          base64Decode(map['c'] as String),
          base64Decode(map['n'] as String),
        );
        if (clear == null) return _reject();
        plaintexts.add(utf8.decode(clear));
      } else {
        plaintexts.add(map['c'] as String);
      }
      received++;
      return true;
    } catch (_) {
      return _reject();
    }
  }

  bool _reject() {
    rejected++;
    return false;
  }
}

// ─────────────────────────────────────────────────────────────
//  LA SESSION
// ─────────────────────────────────────────────────────────────

class SessionResult {
  SessionResult(this.profile);

  final LinkProfile profile;

  int enqueued = 0;
  int delivered = 0;
  int failed = 0;
  int sendAttempts = 0;
  int bytesOnAir = 0;
  int radioMicros = 0;

  /// Charges écartées par le transport avant même de partir.
  int refusedByTransport = 0;

  final List<int> latenciesMicros = [];

  Duration softwareTime = Duration.zero;

  /// Ce que le faux pair a VRAIMENT déchiffré — le seul chiffre qui
  /// compte vraiment.
  int receivedByPeer = 0;

  double get deliveryRate => enqueued == 0 ? 0 : delivered / enqueued;
  Duration get radioTime => Duration(microseconds: radioMicros);
  double get retriesPerMessage =>
      delivered == 0 ? 0 : (sendAttempts - delivered) / delivered;

  int get medianLatencyMicros {
    if (latenciesMicros.isEmpty) return 0;
    final sorted = [...latenciesMicros]..sort();
    return sorted[sorted.length ~/ 2];
  }
}

/// Fait passer un lot complet entre l'application et le faux pair.
Future<SessionResult> runSession({
  required LinkProfile profile,
  required int textMessages,
  required int files,
  required int fileBytes,
  required int locations,
  required int seed,
}) async {
  final result = SessionResult(profile);
  final rng = Random(seed);

  // Les deux identités, et la poignée de main.
  final algorithm = X25519();
  final myKeyPair = await algorithm.newKeyPair();
  final myPublic = await myKeyPair.extractPublicKey();
  final myPublicB64 = base64Encode(myPublic.bytes);
  const myId = 'appareil-a';

  final peer = await FakePeer.create('appareil-b');
  await peer.handshake(myPublicB64);

  final shared = await algorithm.sharedSecretKey(
    keyPair: myKeyPair,
    remotePublicKey:
        SimplePublicKey(base64Decode(peer.publicKeyB64), type: KeyPairType.x25519),
  );

  final started = Stopwatch()..start();
  final pending = <String, Stopwatch>{};

  late final PremiumMessageQueue queue;
  queue = PremiumMessageQueue(
    onSend: (task) async {
      result.sendAttempts++;
      final frame = Uint8List.fromList(task.payload);

      // ⚠️ LES DEUX REFUS DU TRANSPORT BLUETOOTH, REPRODUITS TELS QUELS.
      //
      // `ble_mesh_transport.dart` écarte tout type de contenu ≥ 0x20
      // (donc les fichiers) et toute charge de plus de 512 octets.
      // C'est une bonne décision — un fichier de 250 Ko en écritures de
      // 19 octets prendrait des heures — mais elle a une conséquence
      // qu'il faut voir : SANS WI-FI, AUCUN FICHIER NE PART.
      if (profile.refusesFiles) {
        if (frame[1] >= 0x20) {
          result.refusedByTransport++;
          return profile.reportsRefusalAsSuccess;
        }
        if (frame.length > profile.maxPayload) {
          result.refusedByTransport++;
          return profile.reportsRefusalAsSuccess;
        }
      }

      // Temps d'antenne CALCULÉ — jamais attendu pour de vrai : on mesure
      // le logiciel en temps réel, la radio par le calcul. Compté APRÈS
      // les refus : une trame écartée n'occupe jamais l'antenne.
      final chunks = (frame.length / profile.chunkPayload).ceil();
      result.radioMicros +=
          profile.latency.inMicroseconds + chunks * profile.perChunkMicros;
      // Chaque écriture porte un octet d'en-tête de fragment.
      result.bytesOnAir += chunks * (profile.chunkPayload + 1);

      if (rng.nextDouble() < profile.lossRate) return false;
      return peer.receive(frame);
    },
    onDelivered: (id) {
      result.delivered++;
      final watch = pending.remove(id);
      if (watch != null) result.latenciesMicros.add(watch.elapsedMicroseconds);
    },
    onFailed: (id, _) {
      result.failed++;
      pending.remove(id);
    },
  );
  queue.start();

  Future<void> enqueue(String id, String clear, MessagePriority priority) async {
    // L'enveloppe RÉELLE de `MeshRepository.sendMessage`.
    final (cipher, nonce) =
        await CryptoService.encryptBytes(shared, Uint8List.fromList(utf8.encode(clear)));
    final map = <String, dynamic>{
      'c': base64Encode(cipher),
      's': myId,
      'e': true,
      'n': base64Encode(nonce),
      'm': id,
      't': peer.id,
    };
    final body = utf8.encode(json.encode(map));
    final frame = Uint8List(2 + body.length)
      ..[0] = 5
      ..[1] = 0x01
      ..setRange(2, 2 + body.length, body);

    pending[id] = Stopwatch()..start();
    result.enqueued++;
    queue.enqueue(
      messageId: id,
      targetId: peer.id,
      payload: frame,
      priority: priority,
    );
  }

  /// Le vrai paquet de `sendFile` : en-tête binaire, métadonnées JSON,
  /// puis le contenu CHIFFRÉ EN OCTETS — jamais de base64.
  Future<void> enqueueFile(String id, int sizeBytes) async {
    final content = Uint8List(sizeBytes);
    final (cipher, nonce) = await CryptoService.encryptBytes(shared, content);
    final meta = utf8.encode(json.encode({
      'fileId': id,
      's': myId,
      'sz': sizeBytes,
      't': peer.id,
      'e': true,
      'n': base64Encode(nonce),
    }));
    final frame = Uint8List(4 + meta.length + cipher.length)
      ..[0] = 5
      ..[1] = 0x30 // kFileTransferType
      ..[2] = (meta.length >> 8) & 0xFF
      ..[3] = meta.length & 0xFF
      ..setRange(4, 4 + meta.length, meta)
      ..setRange(4 + meta.length, 4 + meta.length + cipher.length, cipher);

    pending[id] = Stopwatch()..start();
    result.enqueued++;
    queue.enqueue(
      messageId: id,
      targetId: peer.id,
      payload: frame,
      priority: MessagePriority.normal,
    );
  }

  // ── 100 messages texte ────────────────────────────────────────────
  for (var i = 0; i < textMessages; i++) {
    await enqueue('txt-$i', 'Message numéro $i — on se retrouve où ?',
        MessagePriority.high);
  }

  // ── 10 positions ──────────────────────────────────────────────────
  for (var i = 0; i < locations; i++) {
    await enqueue('loc-$i', '📍loc:3.${848000 + i},11.${502000 + i}',
        MessagePriority.high);
  }

  // ── 20 fichiers ───────────────────────────────────────────────────
  //
  // ⚠️ UN FICHIER = UNE SEULE ENTRÉE DE FILE, EN OCTETS BRUTS.
  //
  // `sendFile` construit UN paquet binaire — en-tête, métadonnées JSON,
  // puis le contenu chiffré tel quel — et le confie à la file d'un
  // bloc. Le découpage n'a lieu que plus bas, dans le transport. Passer
  // les fichiers en morceaux de 4 Ko encodés en base64 dans la file,
  // comme le faisait une première version de ce banc, gonflait le
  // volume d'un tiers et inventait 1 300 entrées qui n'existent pas.
  for (var f = 0; f < files; f++) {
    await enqueueFile('file-$f', fileBytes);
  }

  // On laisse la file terminer : relances comprises.
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (result.delivered + result.failed < result.enqueued &&
      DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }

  started.stop();
  result.softwareTime = started.elapsed;
  result.receivedByPeer = peer.received;
  queue.stop();
  return result;
}

String _fmt(Duration d) {
  if (d.inMinutes > 0) {
    return '${d.inMinutes} min ${(d.inSeconds % 60).toString().padLeft(2, '0')} s';
  }
  if (d.inSeconds > 0) return '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
  return '${d.inMilliseconds} ms';
}

void _report(SessionResult r) {
  // ignore: avoid_print
  print('''

┌─ ${r.profile.name} ─────────────────────────────────────────
│ Envois mis en file        : ${r.enqueued}
│ Arrivés                   : ${r.delivered}  (${(r.deliveryRate * 100).toStringAsFixed(2)} %)
│ Perdus définitivement     : ${r.failed}
│ Refusés par le transport  : ${r.refusedByTransport}
│ Réellement reçus par B    : ${r.receivedByPeer}
│ Tentatives totales        : ${r.sendAttempts}
│ Relances par message      : ${r.retriesPerMessage.toStringAsFixed(3)}
│ Octets réellement émis    : ${(r.bytesOnAir / 1024).toStringAsFixed(1)} Kio
│ Temps LOGICIEL (mesuré)   : ${_fmt(r.softwareTime)}
│ Temps ANTENNE (calculé)   : ${_fmt(r.radioTime)}
│ Latence médiane en file   : ${(r.medianLatencyMicros / 1000).toStringAsFixed(1)} ms
└──────────────────────────────────────────────────────────────
''');
}

void main() {
  // Un lot complet prend du temps : les relances utilisent le vrai
  // backoff exponentiel de la file.
  const timeout = Timeout(Duration(minutes: 4));

  test('session à deux appareils — Wi-Fi local', () async {
    final r = await runSession(
      profile: wifiProfile,
      textMessages: 100,
      files: 20,
      fileBytes: 250 * 1024,
      locations: 10,
      seed: 1,
    );
    _report(r);
    expect(r.delivered, greaterThan(0));
    // Aucun message ne doit être abandonné : cinq relances suffisent
    // largement à 0,5 % de perte.
    expect(r.failed, 0);
  }, timeout: timeout);

  test('session à deux appareils — Bluetooth LE', () async {
    final r = await runSession(
      profile: bleProfile,
      textMessages: 100,
      files: 20,
      fileBytes: 250 * 1024,
      locations: 10,
      seed: 2,
    );
    _report(r);

    // ⚠️ LA PROPRIÉTÉ QUI COMPTE : CE QUI EST ANNONCÉ LIVRÉ A ÉTÉ REÇU.
    //
    // Le Bluetooth écarte toujours les vingt fichiers — c'est voulu, ils
    // demanderaient des heures d'antenne. Mais désormais ces refus
    // remontent : la file les relance, épuise ses cinq tentatives, et les
    // déclare ÉCHOUÉS au lieu de les compter comme livrés.
    expect(r.refusedByTransport, greaterThanOrEqualTo(20),
        reason: 'les fichiers sont écartés par BLE, et chaque relance aussi');
    expect(r.failed, 20,
        reason: 'les 20 fichiers doivent être signalés comme non partis');
    expect(r.delivered, r.receivedByPeer,
        reason: 'plus aucun message annoncé livré sans avoir été reçu');
  }, timeout: timeout);

  test('sans le correctif, le banc voit la livraison mensongère', () async {
    // Ce test garde la trace du défaut corrigé : si `sendViaRoute`
    // recommençait un jour à répondre « oui » sans rien envoyer, c'est
    // exactement l'écart que l'on reverrait.
    final r = await runSession(
      profile: bleProfileAvantCorrectif,
      textMessages: 10,
      files: 5,
      fileBytes: 250 * 1024,
      locations: 0,
      seed: 4,
    );
    expect(r.delivered, 15, reason: 'la file croyait tout avoir livré');
    expect(r.receivedByPeer, 10, reason: 'le pair n\'avait reçu que le texte');
    expect(r.failed, 0, reason: 'et rien n\'était signalé en échec');
  }, timeout: timeout);

  test('taille des trames face à la limite BLE de 512 octets', () async {
    // ⚠️ LA MARGE AVANT LE REFUS SILENCIEUX.
    //
    // BLE écarte toute charge de plus de 512 octets — et, aujourd'hui,
    // ce refus est compté comme une livraison. Il faut donc savoir à
    // quelle distance de ce plafond se trouve un message ordinaire, et
    // à partir de quelle longueur de texte on le franchit.
    final algorithm = X25519();
    final a = await algorithm.newKeyPair();
    final b = await algorithm.newKeyPair();
    final shared = await algorithm.sharedSecretKey(
      keyPair: a,
      remotePublicKey: await b.extractPublicKey(),
    );

    // Les identifiants de Droplet sont des empreintes hexadécimales de
    // 64 caractères : c'est ce qui pèse le plus dans l'enveloppe.
    final myId = 'a' * 64;
    final peerId = 'b' * 64;

    Future<int> frameSize(String text) async {
      final (cipher, nonce) = await CryptoService.encryptBytes(
          shared, Uint8List.fromList(utf8.encode(text)));
      final body = utf8.encode(json.encode({
        'c': base64Encode(cipher),
        's': myId,
        'e': true,
        'n': base64Encode(nonce),
        'm': 'm-1786460000000000',
        't': peerId,
      }));
      return 2 + body.length;
    }

    final short = await frameSize('Ok');
    final normal = await frameSize('On se retrouve devant la gare a 18 h ?');
    final long = await frameSize('a' * 200);
    final veryLong = await frameSize('a' * 300);

    // ignore: avoid_print
    print("""

+- Taille des trames (limite BLE : 512 o) ---------------------
| « Ok »                    : $short o
| message ordinaire (38 c.) : $normal o
| message de 200 caracteres : $long o
| message de 300 caracteres : $veryLong o
+-------------------------------------------------------------
""");

    expect(normal, lessThan(512),
        reason: 'un message ordinaire doit passer en Bluetooth');
  }, timeout: timeout);

  test('le faux pair déchiffre réellement tout ce qu\'il reçoit', () async {
    final r = await runSession(
      profile: wifiProfile,
      textMessages: 20,
      files: 0,
      fileBytes: 0,
      locations: 5,
      seed: 3,
    );
    // C'est la vérification qui donne du sens aux chiffres ci-dessus :
    // si le pair n'avait pas su déchiffrer, tout aurait été « livré »
    // sans que rien ne soit lisible à l'arrivée.
    expect(r.delivered, 25);
    expect(r.failed, 0);
  }, timeout: timeout);
}
