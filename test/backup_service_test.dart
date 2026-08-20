import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:droplet/core/services/backup_service.dart';
import 'package:droplet/core/services/crypto_service.dart';

/// Couvre le round-trip de l'enveloppe de sauvegarde (chiffrement par mot
/// de passe + analyse du contenu) sans passer par `createBackup`, qui
/// dépend du stockage sécurisé (indisponible hors d'un vrai appareil/
/// binding de test avec canaux de plateforme mockés). L'enveloppe est
/// construite manuellement ici avec les mêmes primitives
/// (`deriveBackupKey`/`encryptBytes`) que `BackupService.createBackup`
/// utilise réellement.
void main() {
  Future<File> writeEnvelope(String password, Map<String, dynamic> plain, {int iterations = 1000}) async {
    final plainBytes = Uint8List.fromList(utf8.encode(json.encode(plain)));
    final salt = Uint8List.fromList(List.generate(16, (i) => i * 7 % 256));
    final key = await CryptoService.deriveBackupKey(password, salt, iterations: iterations);
    final (cipher, nonce) = await CryptoService.encryptBytes(key, plainBytes);

    final envelope = {
      'version': 1,
      'kdf': {
        'algorithm': 'pbkdf2-hmac-sha256',
        'iterations': iterations,
        'salt': base64Encode(salt),
      },
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(cipher),
    };

    final file = File('${Directory.systemTemp.path}/droplet_backup_test_${DateTime.now().microsecondsSinceEpoch}.dropletbackup');
    await file.writeAsString(json.encode(envelope));
    return file;
  }

  Map<String, dynamic> samplePlain() => {
        'identity': {
          'id': 'alice-id',
          'pseudo': 'Alice',
          'avatarUrl': null,
          'publicKey': 'pkA==',
          'privateKeySeed': 'c2VlZC1zZWNyZXQ=',
        },
        'peers': [
          {
            'peerId': 'bob-id',
            'pseudo': 'Bob',
            'role': 'leaf',
            'transports': ['ble'],
            'platform': 'android',
            'interestGroups': [],
            'reliability': 1.0,
            'lastSeen': DateTime.now().toIso8601String(),
            'totalMessagesExchanged': 3,
            'publicKey': 'pkB==',
            'verified': true,
            'verifiedPublicKey': 'pkB==',
          },
        ],
        'groups': [
          {
            'id': 'group-1',
            'name': 'Amis',
            'avatarUrl': null,
            'createdBy': 'alice-id',
            'createdAt': DateTime.now().toIso8601String(),
            'updatedAt': DateTime.now().toIso8601String(),
            'members': [
              {
                'peerId': 'alice-id',
                'role': 'admin',
                'addedAt': DateTime.now().toIso8601String(),
                'removedAt': null,
                'addedBy': 'alice-id',
              },
            ],
          },
        ],
        'senderKeys': [
          {
            'groupId': 'group-1',
            'ownerPeerId': 'alice-id',
            'chainKey': 'Y2hhaW4ta2V5',
            'counter': 5,
            'isMine': true,
          },
        ],
        'messages': [
          {
            'id': 'msg-1',
            'authorPseudo': 'Alice',
            'content': 'Bonjour',
            'type': 'text',
            'reactions': [],
            'timestamp': DateTime.now().toIso8601String(),
            'senderId': 'alice-id',
            'targetId': 'bob-id',
            'hopCount': 0,
            'status': 'sent',
            'deliveryCount': 0,
          },
        ],
      };

  test('bon mot de passe : la sauvegarde se déchiffre et se parse correctement', () async {
    final file = await writeEnvelope('correct horse battery', samplePlain());
    addTearDown(() => file.delete());

    final contents = await BackupService.readBackup(file: file, password: 'correct horse battery');

    expect(contents.identity.id, 'alice-id');
    expect(contents.identity.pseudo, 'Alice');
    expect(contents.privateKeySeed, 'c2VlZC1zZWNyZXQ=');
    expect(contents.peers, hasLength(1));
    expect(contents.peers.first.peerId, 'bob-id');
    expect(contents.peers.first.isVerifiedAndCurrent, isTrue);
    expect(contents.groups, hasLength(1));
    expect(contents.groups.first.activeMembers, hasLength(1));
    expect(contents.senderKeys, hasLength(1));
    expect(contents.senderKeys.first.counter, 5);
    expect(contents.messages, hasLength(1));
    expect(contents.messages.first.content, 'Bonjour');
  });

  test('mauvais mot de passe : échec propre via BackupPasswordException', () async {
    final file = await writeEnvelope('correct horse battery', samplePlain());
    addTearDown(() => file.delete());

    expect(
      () => BackupService.readBackup(file: file, password: 'wrong password'),
      throwsA(isA<BackupPasswordException>()),
    );
  });

  test('fichier corrompu (pas du JSON) : échec propre, pas d\'exception non gérée', () async {
    final file = File('${Directory.systemTemp.path}/droplet_backup_corrupt_${DateTime.now().microsecondsSinceEpoch}.dropletbackup');
    await file.writeAsString('ceci n\'est pas un fichier de sauvegarde valide');
    addTearDown(() => file.delete());

    expect(
      () => BackupService.readBackup(file: file, password: 'peu importe'),
      throwsA(isA<BackupPasswordException>()),
    );
  });
}
