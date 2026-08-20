// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// Ce fichier décrit le « classeur permanent » de l'app — l'endroit où tout
// est rangé pour de vrai, même si on éteint le téléphone (contrairement à
// la mémoire de l'app, qui s'efface). C'est une base de données SQLite (un
// gros fichier organisé en tableaux), et on utilise un outil appelé Drift
// pour la manipuler facilement depuis Dart.
//
// Chaque classe `extends Table` ci-dessous décrit un TABLEAU de ce
// classeur : ses colonnes, et quel(s) champ(s) permettent de retrouver une
// ligne précise sans erreur (la `primaryKey`, un peu comme un numéro de
// dossier unique).
//
// Ce fichier ne contient QUE la description des tableaux — pas le code qui
// sait lire/écrire dedans (ça, c'est dans `storage_service.dart`). Une
// partie du travail (`part 'app_database.g.dart'`) est même écrite
// automatiquement par un robot à partir de ce fichier : on ne touche
// jamais ce fichier généré à la main.
// ============================================================================

import 'dart:io';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3_flutter_libs/sqlite3_flutter_libs.dart' as sqlite3_flutter_libs;

part 'app_database.g.dart';

// ---------------------------------------------------------------------------
// Table definitions (Droplet — mesh only)
// ---------------------------------------------------------------------------

/// Le tableau « Qui suis-je ? » — une seule ligne, avec mon pseudo et mon
/// identifiant secret sur le mesh.
class DropletUser extends Table {
  TextColumn get id => text()();
  TextColumn get pseudo => text()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get publicKey => text().nullable()();

  // La colonne qui sert de « numéro de dossier unique » pour retrouver une
  // ligne précise dans ce tableau.
  @override
  Set<Column> get primaryKey => {id};
}

/// Le tableau « Tous mes messages » — la table la plus grande et la plus
/// importante : chaque ligne est un message envoyé ou reçu, avec tout ce
/// qu'il faut pour l'afficher plus tard (texte, photo, fichier...).
class MeshMessages extends Table {
  TextColumn get id => text()();
  TextColumn get authorPseudo => text()();
  TextColumn get content => text()();
  TextColumn get type => text()();
  IntColumn get timestamp => integer()();
  TextColumn get senderId => text().nullable()();
  TextColumn get targetId => text().nullable()();
  TextColumn get imageUrl => text().nullable()();
  TextColumn get audioUrl => text().nullable()();
  IntColumn get hopCount => integer()();
  TextColumn get reactions => text()();
  IntColumn get updatedAt => integer()();
  TextColumn get syncStatus => text()();
  TextColumn get fileId => text().nullable()();
  TextColumn get fileName => text().nullable()();
  IntColumn get fileSize => integer().nullable()();
  TextColumn get fileMimeType => text().nullable()();
  TextColumn get replyToId => text().nullable()();
  TextColumn get status => text()();
  TextColumn get routeInfo => text().nullable()();
  IntColumn get readAt => integer().nullable()();

  /// Groupe de discussion ciblé — distinct de [targetId], qui reste réservé
  /// à l'adressage 1:1. Null pour les messages 1:1 ou de diffusion.
  TextColumn get groupId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Le tableau « Mes groupes de discussion » — un groupe, c'est comme une
/// grande conversation à plusieurs, avec un nom et une photo.
class MeshGroups extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get avatarUrl => text().nullable()();
  TextColumn get createdBy => text()();
  IntColumn get createdAt => integer()();
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Le tableau « Qui fait partie de quel groupe ». Tombstone (`removedAt`)
/// plutôt que suppression physique : permet la convergence décentralisée
/// par LWW sur le timestamp le plus récent entre ajout et retrait, sans
/// serveur central.
///
/// « Tombstone » (littéralement « pierre tombale ») : au lieu d'EFFACER une
/// ligne quand quelqu'un quitte un groupe, on la garde mais on note juste
/// « parti le [date] ». C'est utile ici car il n'y a pas de serveur central
/// pour trancher qui a raison si deux téléphones ne sont pas d'accord — en
/// gardant la trace, on peut toujours comparer les dates et prendre la
/// version la plus récente (« LWW » = Last Write Wins, « la dernière
/// écriture gagne »).
class GroupMembers extends Table {
  TextColumn get groupId => text()();
  TextColumn get peerId => text()();
  TextColumn get role => text()(); // 'admin' | 'member'
  IntColumn get addedAt => integer()();
  IntColumn get removedAt => integer().nullable()();
  TextColumn get addedBy => text()();

  @override
  Set<Column> get primaryKey => {groupId, peerId};
}

/// Sender-key (ratchet façon Signal) d'un membre de groupe. `isMine` indique
/// si c'est ma propre clé (matériel réellement secret dupliqué ici pour un
/// accès rapide, la source de vérité vivant en stockage sécurisé) ou une clé
/// reçue d'un autre membre pour déchiffrer ses messages.
///
/// C'est le « cadenas à combinaison qui change tout seul » utilisé pour
/// chiffrer les messages de groupe : à chaque nouveau message, la
/// combinaison change automatiquement (ça s'appelle un « ratchet », comme
/// un cliquet qui ne peut tourner que dans un sens), pour que même si
/// quelqu'un devine une combinaison, ça ne l'aide pas à deviner les
/// suivantes.
class GroupSenderKeys extends Table {
  TextColumn get groupId => text()();
  TextColumn get ownerPeerId => text()();
  TextColumn get chainKey => text()();
  IntColumn get counter => integer()();
  BoolColumn get isMine => boolean()();

  @override
  Set<Column> get primaryKey => {groupId, ownerPeerId};
}

/// Statut éphémère (façon "Statuts" WhatsApp) — texte uniquement pour ce
/// premier jet, expire après [expiresAt], diffusé publiquement à tout le
/// mesh (pas de ciblage par contact).
class MeshStatuses extends Table {
  TextColumn get id => text()();
  TextColumn get authorId => text()();
  TextColumn get authorPseudo => text()();
  TextColumn get content => text()();
  IntColumn get createdAt => integer()();
  IntColumn get expiresAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Le tableau « Messages déjà vus passer » — sert juste à se souvenir des
/// identifiants des messages déjà relayés, pour ne jamais relayer deux fois
/// le même message en boucle sur le réseau.
class SeenMessageIds extends Table {
  TextColumn get messageId => text()();
  IntColumn get seenAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {messageId};
}

/// Le tableau « Boîte à réglages » — un tableau tout simple à deux colonnes
/// (une étiquette, une valeur), utilisé un peu partout dans l'app pour
/// ranger de petites informations qui ne méritent pas leur propre tableau
/// (par exemple : la liste des conversations archivées).
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

// ---------------------------------------------------------------------------
// Database
// ---------------------------------------------------------------------------

/// Prépare le vrai fichier sur le disque où tout sera écrit, et l'ouvre.
///
/// `LazyDatabase` veut dire « attends qu'on ait vraiment besoin du fichier
/// avant de l'ouvrir » — comme ne sortir la boîte à outils que quand on en
/// a réellement besoin, pas avant.
QueryExecutor _createExecutor() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    await sqlite3_flutter_libs.applyWorkaroundToOpenSqlite3OnOldAndroidVersions();
    final file = File('${dir.path}/droplet.db');
    return NativeDatabase(file, setup: (db) {
      // Un réglage qui rend les lectures/écritures plus rapides et plus
      // sûres en cas de coupure (WAL = Write-Ahead Logging).
      db.execute('PRAGMA journal_mode=WAL');
      db.execute('PRAGMA foreign_keys=ON');
    });
  });
}

/// La base de données complète : la liste de tous les tableaux ci-dessus,
/// plus les règles pour la faire évoluer proprement quand on ajoute de
/// nouvelles colonnes dans une future version de l'app (voir `migration`
/// plus bas).
@DriftDatabase(
  tables: [
    DropletUser,
    MeshMessages,
    MeshGroups,
    GroupMembers,
    GroupSenderKeys,
    MeshStatuses,
    SeenMessageIds,
    AppSettings,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_createExecutor());

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
      await _createIndexes(m.database as AppDatabase);
    },
    onUpgrade: (m, from, to) async {
      final db = m.database as AppDatabase;
      if (from < 2) {
        await m.addColumn(db.meshMessages, db.meshMessages.readAt);
      }
      if (from < 3) {
        await m.addColumn(db.dropletUser, db.dropletUser.publicKey);
      }
      if (from < 4) {
        await m.addColumn(db.meshMessages, db.meshMessages.groupId);
        await m.createTable(db.meshGroups);
        await m.createTable(db.groupMembers);
        await m.createTable(db.groupSenderKeys);
      }
      if (from < 5) {
        await m.createTable(db.meshStatuses);
      }
      if (from < 6) {
        await _createIndexes(db);
      }
    },
  );

  /// Index pour les requêtes fréquentes — sans eux, chaque recherche
  /// par senderId/targetId/groupId/timestamp est un full table scan.
  static Future<void> _createIndexes(AppDatabase db) async {
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_sender ON mesh_messages(sender_id)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_target ON mesh_messages(target_id)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_group ON mesh_messages(group_id)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_timestamp ON mesh_messages(timestamp)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_status ON mesh_messages(status)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_conversation ON mesh_messages(sender_id, target_id, timestamp)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_messages_group_conv ON mesh_messages(group_id, timestamp)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_statuses_author ON mesh_statuses(author_id)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_statuses_expires ON mesh_statuses(expires_at)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_group_members_group ON group_members(group_id)',
    );
    await db.customStatement(
      'CREATE INDEX IF NOT EXISTS idx_seen_messages_seen ON seen_message_ids(seen_at)',
    );
  }
}

/// Le gardien de la base de données : s'assure qu'elle n'est ouverte
/// qu'UNE SEULE fois pour toute l'app, et que personne n'essaie de
/// l'utiliser avant qu'elle soit prête.
class DbProvider {
  static AppDatabase? _db;
  static AppDatabase get instance => _db ?? (throw StateError('AppDatabase not initialized'));
  static bool _initialized = false;
  static bool get isReady => _initialized;

  /// Ouvre le classeur — à appeler une seule fois, tout au début du
  /// lancement de l'app.
  static Future<void> init() async {
    if (_initialized) return;
    _db = AppDatabase();
    _initialized = true;
  }
}
