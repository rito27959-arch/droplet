import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:cryptography/cryptography.dart';
import 'package:droplet/core/services/crypto_service.dart';

/// Couvre les briques cryptographiques pures (AEAD générique + ratchet
/// sender-key), sans toucher au stockage sécurisé de l'identité — ces
/// fonctions n'en dépendent pas.
void main() {
  group('AEAD octets bruts (encryptBytes/decryptBytes)', () {
    test('round-trip: les octets déchiffrés sont identiques aux octets originaux', () async {
      final key = SecretKey(List<int>.generate(32, (i) => i));
      final plaintext = Uint8List.fromList(List<int>.generate(5000, (i) => i % 256));

      final (cipher, nonce) = await CryptoService.encryptBytes(key, plaintext);
      final decrypted = await CryptoService.decryptBytes(key, cipher, nonce);

      expect(decrypted, plaintext);
    });

    test('déchiffrement avec la mauvaise clé retourne null', () async {
      final key = SecretKey(List<int>.generate(32, (i) => i));
      final wrongKey = SecretKey(List<int>.generate(32, (i) => 255 - i));
      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);

      final (cipher, nonce) = await CryptoService.encryptBytes(key, plaintext);
      final decrypted = await CryptoService.decryptBytes(wrongKey, cipher, nonce);

      expect(decrypted, isNull);
    });

    test('encrypt/decrypt (texte) et encryptBytes/decryptBytes partagent la même primitive', () async {
      final key = SecretKey(List<int>.generate(32, (i) => i));
      const plaintext = 'même AEAD sous le capot';

      final (cipherB64, nonceB64) = await CryptoService.encrypt(key, plaintext);
      final decryptedViaBytes = await CryptoService.decryptBytes(
        key,
        base64Decode(cipherB64),
        base64Decode(nonceB64),
      );

      expect(decryptedViaBytes, isNotNull);
      expect(utf8.decode(decryptedViaBytes!), plaintext);
    });
  });

  group('AEAD (encrypt/decrypt)', () {
    test('round-trip: le texte déchiffré est identique au texte original', () async {
      final key = SecretKey(List<int>.generate(32, (i) => i));
      const plaintext = 'Bonjour depuis le mesh 🔒';

      final (cipherB64, nonceB64) = await CryptoService.encrypt(key, plaintext);
      final decrypted = await CryptoService.decrypt(key, cipherB64, nonceB64);

      expect(decrypted, plaintext);
    });

    test('deux chiffrements du même texte produisent des nonces différents', () async {
      final key = SecretKey(List<int>.generate(32, (i) => i));
      const plaintext = 'même message';

      final (cipher1, nonce1) = await CryptoService.encrypt(key, plaintext);
      final (cipher2, nonce2) = await CryptoService.encrypt(key, plaintext);

      expect(nonce1, isNot(equals(nonce2)));
      expect(cipher1, isNot(equals(cipher2)));
    });

    test('déchiffrement avec la mauvaise clé retourne null (pas d\'exception)', () async {
      final key = SecretKey(List<int>.generate(32, (i) => i));
      final wrongKey = SecretKey(List<int>.generate(32, (i) => 255 - i));
      final (cipherB64, nonceB64) = await CryptoService.encrypt(key, 'secret');

      final decrypted = await CryptoService.decrypt(wrongKey, cipherB64, nonceB64);

      expect(decrypted, isNull);
    });

    test('un ciphertext altéré échoue le déchiffrement (tag AEAD invalide)', () async {
      final key = SecretKey(List<int>.generate(32, (i) => i));
      final (cipherB64, nonceB64) = await CryptoService.encrypt(key, 'secret');
      final tampered = '${cipherB64.substring(0, cipherB64.length - 4)}AAAA';

      final decrypted = await CryptoService.decrypt(key, tampered, nonceB64);

      expect(decrypted, isNull);
    });
  });

  group('Ratchet sender-key', () {
    test('ratchetForward est déterministe : même chain key → même sortie', () async {
      final chainKey = await CryptoService.generateChainKey();

      final (msgKeyA, nextA) = await CryptoService.ratchetForward(chainKey);
      final (msgKeyB, nextB) = await CryptoService.ratchetForward(chainKey);

      expect(nextA, nextB);
      expect(await msgKeyA.extractBytes(), await msgKeyB.extractBytes());
    });

    test('avancer le ratchet change la chain key et la clé de message', () async {
      final chainKey = await CryptoService.generateChainKey();
      final (msgKey1, next1) = await CryptoService.ratchetForward(chainKey);
      final (msgKey2, next2) = await CryptoService.ratchetForward(next1);

      expect(next1, isNot(equals(chainKey)));
      expect(next2, isNot(equals(next1)));
      expect(await msgKey1.extractBytes(), isNot(equals(await msgKey2.extractBytes())));
    });

    test('un message chiffré avec la clé du cran N ne se déchiffre qu\'avec elle', () async {
      final chainKey = await CryptoService.generateChainKey();
      final (msgKey1, next1) = await CryptoService.ratchetForward(chainKey);
      final (msgKey2, _) = await CryptoService.ratchetForward(next1);

      final (cipherB64, nonceB64) = await CryptoService.encrypt(msgKey1, 'message du cran 1');

      expect(await CryptoService.decrypt(msgKey1, cipherB64, nonceB64), 'message du cran 1');
      expect(await CryptoService.decrypt(msgKey2, cipherB64, nonceB64), isNull);
    });

    test('fastForward jusqu\'au compteur N produit la même clé qu\'un ratchet pas à pas', () async {
      final chainKey = await CryptoService.generateChainKey();

      // Référence : 3 avancées manuelles successives (compteurs 1, 2, 3).
      final (_, chain1) = await CryptoService.ratchetForward(chainKey);
      final (_, chain2) = await CryptoService.ratchetForward(chain1);
      final (expectedKey, expectedNextChain) = await CryptoService.ratchetForward(chain2);

      final result = await CryptoService.fastForward(chainKey, 0, 3);

      expect(await result.messageKey.extractBytes(), await expectedKey.extractBytes());
      expect(result.nextChainKeyB64, expectedNextChain);
      // Les clés des compteurs 1 et 2 (sautés) doivent être mises en cache.
      expect(result.skipped.keys.toSet(), {1, 2});
    });

    test('fastForward refuse un intervalle vide ou inversé', () async {
      final chainKey = await CryptoService.generateChainKey();
      expect(() => CryptoService.fastForward(chainKey, 5, 5), throwsArgumentError);
      expect(() => CryptoService.fastForward(chainKey, 5, 2), throwsArgumentError);
    });

    test('fastForward refuse de rattraper un nombre de messages sautés excessif', () async {
      final chainKey = await CryptoService.generateChainKey();
      expect(
        () => CryptoService.fastForward(chainKey, 0, 2000, maxSteps: 1000),
        throwsStateError,
      );
    });

    test('une clé de message sautée peut déchiffrer un message arrivé en désordre', () async {
      final chainKey = await CryptoService.generateChainKey();
      // L'auteur envoie 3 messages (compteurs 1, 2, 3) ; seul le 3e arrive
      // d'abord (relais multi-hop), le destinataire doit fastForward et
      // mettre en cache les clés des compteurs 1 et 2.
      final (msgKey1, chain1) = await CryptoService.ratchetForward(chainKey);
      final (msgKey2, chain2) = await CryptoService.ratchetForward(chain1);
      final (msgKey3, _) = await CryptoService.ratchetForward(chain2);

      final (cipher2, nonce2) = await CryptoService.encrypt(msgKey2, 'message 2');

      final result = await CryptoService.fastForward(chainKey, 0, 3);
      expect(await result.messageKey.extractBytes(), await msgKey3.extractBytes());

      final skippedKeyForCounter2 = CryptoService.secretKeyFromBase64(result.skipped[2]!);
      expect(await skippedKeyForCounter2.extractBytes(), await msgKey2.extractBytes());
      expect(await CryptoService.decrypt(skippedKeyForCounter2, cipher2, nonce2), 'message 2');
    });
  });

  group('Code de sécurité (computeSafetyNumber)', () {
    test('format : 12 groupes de 5 chiffres séparés par des espaces', () async {
      final code = await CryptoService.computeSafetyNumber(
        myId: 'alice', myPublicKey: 'pkA==',
        peerId: 'bob', peerPublicKey: 'pkB==',
      );
      final groups = code.split(' ');
      expect(groups.length, 12);
      for (final g in groups) {
        expect(g.length, 5);
        expect(int.tryParse(g), isNotNull);
      }
    });

    test('symétrique : même résultat en inversant "moi" et "le pair"', () async {
      final fromAlice = await CryptoService.computeSafetyNumber(
        myId: 'alice', myPublicKey: 'pkA==',
        peerId: 'bob', peerPublicKey: 'pkB==',
      );
      final fromBob = await CryptoService.computeSafetyNumber(
        myId: 'bob', myPublicKey: 'pkB==',
        peerId: 'alice', peerPublicKey: 'pkA==',
      );
      expect(fromAlice, fromBob);
    });

    test('déterministe : deux calculs identiques donnent le même code', () async {
      final a = await CryptoService.computeSafetyNumber(
        myId: 'alice', myPublicKey: 'pkA==',
        peerId: 'bob', peerPublicKey: 'pkB==',
      );
      final b = await CryptoService.computeSafetyNumber(
        myId: 'alice', myPublicKey: 'pkA==',
        peerId: 'bob', peerPublicKey: 'pkB==',
      );
      expect(a, b);
    });

    test('change si l\'une des deux clés publiques change (détecte une substitution)', () async {
      final original = await CryptoService.computeSafetyNumber(
        myId: 'alice', myPublicKey: 'pkA==',
        peerId: 'bob', peerPublicKey: 'pkB==',
      );
      final withDifferentPeerKey = await CryptoService.computeSafetyNumber(
        myId: 'alice', myPublicKey: 'pkA==',
        peerId: 'bob', peerPublicKey: 'pkB_evil==',
      );
      expect(original, isNot(equals(withDifferentPeerKey)));
    });
  });

  group('Dérivation de clé de sauvegarde (deriveBackupKey)', () {
    test('même mot de passe + même sel → même clé', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final a = await CryptoService.deriveBackupKey('correct horse battery', salt, iterations: 1000);
      final b = await CryptoService.deriveBackupKey('correct horse battery', salt, iterations: 1000);
      expect(await a.extractBytes(), await b.extractBytes());
    });

    test('mot de passe différent → clé différente', () async {
      final salt = Uint8List.fromList(List.generate(16, (i) => i));
      final a = await CryptoService.deriveBackupKey('correct horse battery', salt, iterations: 1000);
      final b = await CryptoService.deriveBackupKey('wrong password', salt, iterations: 1000);
      expect(await a.extractBytes(), isNot(equals(await b.extractBytes())));
    });

    test('même mot de passe, sel différent → clé différente', () async {
      final saltA = Uint8List.fromList(List.generate(16, (i) => i));
      final saltB = Uint8List.fromList(List.generate(16, (i) => 255 - i));
      final a = await CryptoService.deriveBackupKey('correct horse battery', saltA, iterations: 1000);
      final b = await CryptoService.deriveBackupKey('correct horse battery', saltB, iterations: 1000);
      expect(await a.extractBytes(), isNot(equals(await b.extractBytes())));
    });
  });
}
