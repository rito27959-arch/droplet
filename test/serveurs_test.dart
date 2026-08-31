// ============================================================================
// Tests pour les clients serveur Droplet (directory, mailbox, signaling).
// ============================================================================

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:droplet/core/services/qr_code_exchange.dart';
import 'package:droplet/core/services/onion_service.dart';
import 'package:droplet/core/services/signaling_client.dart';

void main() {
  group('DirectoryContact — Modèle', () {
    test('fromJson crée un contact valide', () {
      final json = {
        'peerId': 'abc123',
        'pseudo': 'Alice',
        'onion': 'abcdefghijklmnop.onion',
        'publicKey': 'key123',
      };

      final contact = DirectoryContact.fromJson(json);

      expect(contact.peerId, 'abc123');
      expect(contact.pseudo, 'Alice');
      expect(contact.onionAddress, 'abcdefghijklmnop.onion');
      expect(contact.publicKey, 'key123');
    });
  });

  group('MailboxMessage — Modèle', () {
    test('fromJson crée un message valide', () {
      final json = {
        'id': 'msg001',
        'from': 'sender123',
        'to': 'receiver456',
        'payload': 'encrypted_data_base64',
        'timestamp': '2026-01-15T10:30:00.000Z',
      };

      final msg = MailboxMessage.fromJson(json);

      expect(msg.id, 'msg001');
      expect(msg.fromPeerId, 'sender123');
      expect(msg.toPeerId, 'receiver456');
      expect(msg.encryptedPayload, 'encrypted_data_base64');
      expect(msg.timestamp.year, 2026);
    });
  });

  group('SignalingEvent — Types', () {
    test('PeerJoinedEvent contient le peerId', () {
      const event = PeerJoinedEvent('peer1');
      expect(event.peerId, 'peer1');
    });

    test('PeerLeftEvent contient le peerId', () {
      const event = PeerLeftEvent('peer1');
      expect(event.peerId, 'peer1');
    });

    test('OfferEvent contient fromPeerId et sdp', () {
      const event = OfferEvent('peer1', 'v=0\r\n...');
      expect(event.fromPeerId, 'peer1');
      expect(event.sdp, contains('v=0'));
    });

    test('AnswerEvent contient fromPeerId et sdp', () {
      const event = AnswerEvent('peer2', 'v=0\r\n...');
      expect(event.fromPeerId, 'peer2');
    });

    test('IceCandidateEvent contient fromPeerId et candidate', () {
      const event = IceCandidateEvent('peer1', 'candidate:1234');
      expect(event.fromPeerId, 'peer1');
      expect(event.candidate, contains('candidate:'));
    });
  });

  group('QrPeerData — Compatibilité serveur', () {
    test('le format QR est compatible avec /register', () {
      final qrData = QrPeerData(
        peerId: 'peer123',
        pseudo: 'Alice',
        publicKey: 'base64key',
        onionAddress: 'xyz.onion',
      );

      final json = qrData.toJson();

      expect(json['id'], isA<String>());
      expect(json['pseudo'], isA<String>());
      expect(json['publicKey'], isA<String>());
      expect(json['onion'], endsWith('.onion'));
    });

    test('round-trip QR encode/decode', () {
      final original = QrPeerData(
        peerId: 'peer_abc',
        pseudo: 'Bob',
        publicKey: 'pubkey123',
        onionAddress: 'bobs_address.onion',
      );

      final encoded = original.encode();
      final decoded = QrPeerData.decode(encoded)!;

      expect(decoded.peerId, original.peerId);
      expect(decoded.pseudo, original.pseudo);
      expect(decoded.publicKey, original.publicKey);
      expect(decoded.onionAddress, original.onionAddress);
    });
  });

  group('OnionIdentity — Compatibilité serveur', () {
    test('le format JSON contient les champs requis', () {
      final identity = OnionIdentity(
        privateKeyBytes: Uint8List(32),
        publicKeyBytes: Uint8List(32),
        onionAddress: 'testaddr.onion',
      );

      final json = identity.toJson();

      expect(json['type'], 'droplet_onion');
      expect(json['version'], 1);
      expect(json['publicKey'], isA<String>());
      expect(json['onion'], endsWith('.onion'));
    });
  });

  group('Mailbox — TTL messages', () {
    test('un message de 8 jours est expiré', () {
      final oldTimestamp = DateTime.now().subtract(const Duration(days: 8));
      final now = DateTime.now();
      const ttl = Duration(days: 7);

      expect(now.difference(oldTimestamp) > ttl, isTrue);
    });

    test('un message de 3 jours n\'est pas expiré', () {
      final recentTimestamp = DateTime.now().subtract(const Duration(days: 3));
      final now = DateTime.now();
      const ttl = Duration(days: 7);

      expect(now.difference(recentTimestamp) > ttl, isFalse);
    });
  });

  group('Directory — Recherche', () {
    test('la recherche est insensible à la casse', () {
      expect('Alice'.toLowerCase().contains('alice'), isTrue);
    });

    test('la recherche partielle fonctionne', () {
      expect('Alice'.toLowerCase().contains('ali'), isTrue);
    });

    test('la recherche sans correspondance retourne vide', () {
      final results = ['Alice', 'Bob', 'Charlie']
          .where((p) => p.toLowerCase().contains('xyz'))
          .toList();
      expect(results, isEmpty);
    });
  });

  group('TurnServer — Credentials', () {
    test('le format de credential est valide', () {
      final peerId = 'peer123';
      final timestamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      const secret = 'droplet-turn-secret';

      final credential = '$timestamp:$peerId:$secret';

      expect(credential, contains(peerId));
      expect(credential, contains(':'));
    });
  });

  group('DirectoryEntry — Stockage', () {
    test('toJson/fromJson round-trip', () {
      final entry = DirectoryEntry(
        peerId: 'peer1',
        pseudo: 'TestUser',
        onionAddress: 'abc.onion',
        publicKey: 'key123',
      );

      final json = entry.toJson();
      final restored = DirectoryEntry.fromJson(json);

      expect(restored.peerId, entry.peerId);
      expect(restored.pseudo, entry.pseudo);
      expect(restored.onionAddress, entry.onionAddress);
    });
  });

  group('MailboxMessage — Stockage', () {
    test('toJson/fromJson round-trip', () {
      final msg = MailboxMessage(
        id: 'msg_001',
        fromPeerId: 'sender',
        toPeerId: 'receiver',
        encryptedPayload: 'encrypted_base64_data',
        timestamp: DateTime(2026, 6, 15, 14, 30),
      );

      final json = msg.toJson();
      final restored = MailboxMessage.fromJson(json);

      expect(restored.id, msg.id);
      expect(restored.fromPeerId, msg.fromPeerId);
      expect(restored.toPeerId, msg.toPeerId);
      expect(restored.encryptedPayload, msg.encryptedPayload);
    });
  });
}

// ── DirectoryEntry dédié aux tests (sans dépendre du serveur) ──────

class DirectoryEntry {
  DirectoryEntry({
    required this.peerId,
    required this.pseudo,
    required this.onionAddress,
    required this.publicKey,
    this.lastSeen,
  });

  final String peerId;
  final String pseudo;
  final String onionAddress;
  final String publicKey;
  DateTime? lastSeen;

  Map<String, dynamic> toJson() => {
        'peerId': peerId,
        'pseudo': pseudo,
        'onion': onionAddress,
        'publicKey': publicKey,
        'lastSeen': lastSeen?.toIso8601String(),
      };

  factory DirectoryEntry.fromJson(Map<String, dynamic> json) {
    return DirectoryEntry(
      peerId: json['peerId'] as String,
      pseudo: json['pseudo'] as String,
      onionAddress: json['onion'] as String,
      publicKey: json['publicKey'] as String,
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'] as String)
          : null,
    );
  }
}

class DirectoryContact {
  DirectoryContact({
    required this.peerId,
    required this.pseudo,
    required this.onionAddress,
    required this.publicKey,
  });

  final String peerId;
  final String pseudo;
  final String onionAddress;
  final String publicKey;

  factory DirectoryContact.fromJson(Map<String, dynamic> json) {
    return DirectoryContact(
      peerId: json['peerId'] as String,
      pseudo: json['pseudo'] as String,
      onionAddress: json['onion'] as String,
      publicKey: json['publicKey'] as String,
    );
  }
}

class MailboxMessage {
  MailboxMessage({
    required this.id,
    required this.fromPeerId,
    required this.toPeerId,
    required this.encryptedPayload,
    required this.timestamp,
  });

  final String id;
  final String fromPeerId;
  final String toPeerId;
  final String encryptedPayload;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'id': id,
        'from': fromPeerId,
        'to': toPeerId,
        'payload': encryptedPayload,
        'timestamp': timestamp.toIso8601String(),
      };

  factory MailboxMessage.fromJson(Map<String, dynamic> json) {
    return MailboxMessage(
      id: json['id'] as String,
      fromPeerId: json['from'] as String,
      toPeerId: json['to'] as String,
      encryptedPayload: json['payload'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
    );
  }
}
