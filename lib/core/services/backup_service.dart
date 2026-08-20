// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Droplet n'a pas de compte ni de serveur central — donc si on perd ou
// casse son téléphone, il n'y a personne à appeler pour « récupérer son
// compte ». Ce fichier est la SEULE solution de secours : il permet de
// fabriquer un fichier de sauvegarde complet (identité, contacts,
// groupes, et si voulu l'historique des messages), protégé par un mot de
// passe choisi par l'utilisateur, qu'on peut ensuite restaurer sur un
// nouveau téléphone.
//
// Analogie : c'est comme mettre tous ses papiers importants (carte
// d'identité, carnet d'adresses, journal intime) dans un coffre-fort
// verrouillé par un mot de passe, avant de le ranger où on veut (une clé
// USB, le cloud, peu importe — Droplet ne s'en occupe pas). Un point
// crucial : Droplet ne connaît PAS ce mot de passe et ne le garde nulle
// part — s'il est oublié, le coffre reste fermé pour toujours, il n'y a
// aucun moyen de le forcer.
// ============================================================================

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import '../models/mesh_message.dart';
import 'crypto_service.dart';
import 'storage_service.dart';

/// Contenu déchiffré d'une sauvegarde d'identité Droplet — tout ce qui a
/// été mis dans le coffre, une fois qu'on l'a rouvert avec le bon mot de
/// passe.
class BackupContents {
  final DropletUserModel identity;
  final String privateKeySeed;
  final List<PeerRecord> peers;
  final List<GroupInfo> groups;
  final List<({String groupId, String ownerPeerId, String chainKey, int counter, bool isMine})> senderKeys;
  final List<MeshMessage> messages;

  const BackupContents({
    required this.identity,
    required this.privateKeySeed,
    required this.peers,
    required this.groups,
    required this.senderKeys,
    required this.messages,
  });
}

/// Levée quand une sauvegarde ne peut pas être déchiffrée — mot de passe
/// erroné ou fichier corrompu/invalide (les deux sont indistinguables par
/// construction : un AEAD ne révèle pas pourquoi il échoue).
class BackupPasswordException implements Exception {
  final String message;
  const BackupPasswordException(this.message);
  @override
  String toString() => message;
}

/// Sauvegarde et restauration chiffrées de l'identité Droplet (clé privée,
/// contacts, groupes, sender-keys, et optionnellement l'historique des
/// messages) — seul mécanisme de récupération en cas de perte d'appareil,
/// l'app ne dépendant d'aucun compte ni serveur central.
///
/// Le fichier exporté n'est protégé que par le mot de passe choisi par
/// l'utilisateur : il n'est ni stocké ni transmis nulle part par l'app, et
/// sa perte rend la sauvegarde définitivement inexploitable (aucun
/// recouvrement possible, par construction).
class BackupService {
  static const int _kdfIterations = 300000;
  static const int _saltLength = 16;
  static const int _formatVersion = 1;

  /// Génère des octets vraiment aléatoires (pas prévisibles) — utilisé
  /// pour le « sel » qui rend le mot de passe unique à chaque sauvegarde.
  static Uint8List _randomBytes(int length) {
    final random = Random.secure();
    return Uint8List.fromList(List.generate(length, (_) => random.nextInt(256)));
  }

  /// Construit et chiffre la sauvegarde, l'écrit dans un fichier temporaire
  /// et retourne ce fichier (prêt à être partagé via `share_plus`).
  ///
  /// Les grandes étapes : 1) rassembler toutes les données importantes
  /// dans un gros paquet JSON en clair, 2) transformer le mot de passe en
  /// une vraie clé de chiffrement solide (via un « KDF », qui rend le
  /// piratage par essais-erreurs très lent exprès), 3) chiffrer le
  /// paquet avec cette clé, 4) tout emballer dans un fichier avec les
  /// petites infos nécessaires pour le déchiffrer plus tard (mais jamais
  /// le mot de passe lui-même).
  static Future<File> createBackup({
    required String password,
    required bool includeMessages,
  }) async {
    final user = StorageService.currentUser;
    final privateKeySeed = await CryptoService.exportPrivateKeySeed();
    if (user == null || privateKeySeed == null) {
      throw StateError('Aucune identité locale à sauvegarder');
    }

    final senderKeys = await StorageService.getAllGroupSenderKeys();

    final plain = <String, dynamic>{
      'identity': {
        ...user.toJson(),
        'privateKeySeed': privateKeySeed,
      },
      'peers': StorageService.getKnownPeers().map((p) => p.toJson()).toList(),
      'groups': StorageService.getGroups().map((g) => {
            'id': g.id,
            'name': g.name,
            'avatarUrl': g.avatarUrl,
            'createdBy': g.createdBy,
            'createdAt': g.createdAt.toIso8601String(),
            'updatedAt': g.updatedAt.toIso8601String(),
            'members': g.members.map((m) => {
                  'peerId': m.peerId,
                  'role': m.role,
                  'addedAt': m.addedAt.toIso8601String(),
                  'removedAt': m.removedAt?.toIso8601String(),
                  'addedBy': m.addedBy,
                }).toList(),
          }).toList(),
      'senderKeys': senderKeys.map((k) => {
            'groupId': k.groupId,
            'ownerPeerId': k.ownerPeerId,
            'chainKey': k.chainKey,
            'counter': k.counter,
            'isMine': k.isMine,
          }).toList(),
      'messages': includeMessages
          ? StorageService.getMessages().map((m) => m.toJson()).toList()
          : const [],
    };
    final plainBytes = Uint8List.fromList(utf8.encode(json.encode(plain)));

    final salt = _randomBytes(_saltLength);
    final key = await CryptoService.deriveBackupKey(password, salt, iterations: _kdfIterations);
    final (cipher, nonce) = await CryptoService.encryptBytes(key, plainBytes);

    final envelope = {
      'version': _formatVersion,
      'kdf': {
        'algorithm': 'pbkdf2-hmac-sha256',
        'iterations': _kdfIterations,
        'salt': base64Encode(salt),
      },
      'nonce': base64Encode(nonce),
      'ciphertext': base64Encode(cipher),
    };

    final dir = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${dir.path}/backups');
    if (!await backupDir.exists()) await backupDir.create(recursive: true);
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final file = File('${backupDir.path}/droplet-$timestamp.dropletbackup');
    await file.writeAsString(json.encode(envelope));
    return file;
  }

  /// Déchiffre une sauvegarde. Lève [BackupPasswordException] si le mot de
  /// passe est incorrect ou le fichier invalide.
  static Future<BackupContents> readBackup({
    required File file,
    required String password,
  }) async {
    final Map<String, dynamic> envelope;
    try {
      envelope = json.decode(await file.readAsString()) as Map<String, dynamic>;
    } catch (_) {
      throw const BackupPasswordException('Fichier de sauvegarde illisible ou corrompu');
    }

    try {
      final kdf = envelope['kdf'] as Map<String, dynamic>;
      final salt = base64Decode(kdf['salt'] as String);
      final iterations = kdf['iterations'] as int;
      final nonce = base64Decode(envelope['nonce'] as String);
      final cipher = base64Decode(envelope['ciphertext'] as String);

      final key = await CryptoService.deriveBackupKey(password, salt, iterations: iterations);
      final plainBytes = await CryptoService.decryptBytes(key, cipher, nonce);
      if (plainBytes == null) {
        throw const BackupPasswordException('Mot de passe incorrect');
      }

      final plain = json.decode(utf8.decode(plainBytes)) as Map<String, dynamic>;
      final identityJson = plain['identity'] as Map<String, dynamic>;
      final privateKeySeed = identityJson['privateKeySeed'] as String;

      final peers = (plain['peers'] as List)
          .cast<Map<String, dynamic>>()
          .map(PeerRecord.fromJson)
          .toList();

      final groups = (plain['groups'] as List).cast<Map<String, dynamic>>().map((g) {
        return GroupInfo(
          id: g['id'] as String,
          name: g['name'] as String,
          avatarUrl: g['avatarUrl'] as String?,
          createdBy: g['createdBy'] as String,
          createdAt: DateTime.parse(g['createdAt'] as String),
          updatedAt: DateTime.parse(g['updatedAt'] as String),
          members: (g['members'] as List).cast<Map<String, dynamic>>().map((m) {
            return GroupMemberRecord(
              peerId: m['peerId'] as String,
              role: m['role'] as String,
              addedAt: DateTime.parse(m['addedAt'] as String),
              removedAt: m['removedAt'] != null ? DateTime.parse(m['removedAt'] as String) : null,
              addedBy: m['addedBy'] as String,
            );
          }).toList(),
        );
      }).toList();

      final senderKeys = (plain['senderKeys'] as List).cast<Map<String, dynamic>>().map((k) {
        return (
          groupId: k['groupId'] as String,
          ownerPeerId: k['ownerPeerId'] as String,
          chainKey: k['chainKey'] as String,
          counter: k['counter'] as int,
          isMine: k['isMine'] as bool,
        );
      }).toList();

      final messages = (plain['messages'] as List)
          .cast<Map<String, dynamic>>()
          .map(MeshMessage.fromJson)
          .toList();

      return BackupContents(
        identity: DropletUserModel.fromJson(identityJson),
        privateKeySeed: privateKeySeed,
        peers: peers,
        groups: groups,
        senderKeys: senderKeys,
        messages: messages,
      );
    } on BackupPasswordException {
      rethrow;
    } catch (_) {
      // Mauvais mot de passe : la clé dérivée est différente, donc le tag
      // AEAD ne correspond jamais — indistinguable d'un fichier corrompu.
      throw const BackupPasswordException('Mot de passe incorrect ou fichier corrompu');
    }
  }

  /// Réécrit l'état local à partir d'une sauvegarde déchiffrée — remet
  /// tout en place sur le nouvel appareil : identité, contacts, groupes,
  /// clés de groupe, puis messages si présents. Réservé au flux de
  /// restauration à l'onboarding (aucune identité locale existante).
  static Future<void> restoreBackup(BackupContents contents) async {
    await CryptoService.restorePrivateKeySeed(contents.privateKeySeed);
    await StorageService.saveUser(contents.identity);
    await StorageService.savePeers(contents.peers);

    for (final group in contents.groups) {
      try {
        await StorageService.upsertGroup(
          id: group.id,
          name: group.name,
          avatarUrl: group.avatarUrl,
          createdBy: group.createdBy,
          createdAt: group.createdAt,
          updatedAt: group.updatedAt,
        );
        for (final member in group.members) {
          await StorageService.upsertGroupMember(
            groupId: group.id,
            peerId: member.peerId,
            role: member.role,
            addedAt: member.addedAt,
            removedAt: member.removedAt,
            addedBy: member.addedBy,
          );
        }
      } catch (e) {
        // Groupe corrompu — on le saute.
      }
    }

    for (final key in contents.senderKeys) {
      try {
        await StorageService.upsertGroupSenderKey(
          groupId: key.groupId,
          ownerPeerId: key.ownerPeerId,
          chainKey: key.chainKey,
          counter: key.counter,
          isMine: key.isMine,
        );
      } catch (e) {
        // Sender key corrompu — on le saute.
      }
    }

    for (final message in contents.messages) {
      try {
        await StorageService.saveMessage(message);
      } catch (e) {
        // Message corrompu ou incomplet — on le saute plutôt que de planter
        // toute la restauration.
      }
    }

    await StorageService.setOnboardingComplete();
  }
}
