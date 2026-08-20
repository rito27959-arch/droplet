// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// C'est le grand bibliothécaire de l'app : TOUT ce qui doit survivre à un
// redémarrage du téléphone (mes messages, mes contacts, mes groupes, mes
// réglages...) passe par lui.
//
// Le truc à comprendre : chaque type d'information a DEUX copies.
//   1. Une copie RAPIDE en mémoire (une simple variable, comme un
//      brouillon sur un post-it) — c'est celle qu'on lit tout le temps,
//      instantanément, sans jamais attendre.
//   2. Une copie DURABLE dans le classeur permanent (la base de données
//      SQLite décrite dans `app_database.dart`) — c'est celle qui survit
//      même si on éteint le téléphone.
//
// Donc le principe est TOUJOURS le même : quand on ÉCRIT quelque chose, on
// l'écrit dans les DEUX (le classeur permanent d'abord, puis le post-it) ;
// quand on LIT quelque chose, on lit SEULEMENT le post-it (instantané, pas
// besoin d'attendre le classeur). Au tout début du lancement de l'app,
// `init()` recopie tout le classeur vers les post-its une bonne fois pour
// toutes.
//
// Ce fichier a aussi un petit magasin générique « clé → valeur » (comme un
// vestiaire avec des casiers numérotés) utilisé pour ranger plein de
// petites choses qui ne méritent pas leur propre tableau dans le classeur :
// la liste des conversations archivées, la file d'attente des messages pas
// encore envoyés, etc.
// ============================================================================

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart';
import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import '../database/app_database.dart' as db;
import '../models/mesh_message.dart';
import '../models/status_media.dart';

/// Facade statique avec cache mémoire + persistance Drift atomique.
///
/// Tous les getters sont synchrones (lecture depuis le cache).
/// Toutes les écritures passent par Drift (transaction) + mettent à jour le cache.
/// Si Drift n'est pas initialisé (tests), les écritures ne font que mettre à jour
/// le cache mémoire sans persister.
///
/// « Facade statique » = une classe dont on n'a jamais besoin de créer
/// d'exemplaire (pas de `StorageService()`) : on appelle directement
/// `StorageService.maFonction()`, un peu comme on appelle directement
/// `Maths.racineCarree()` sans avoir besoin de fabriquer un objet
/// « calculatrice » avant.
class StorageService {
  static db.AppDatabase? get _database =>
      db.DbProvider.isReady ? db.DbProvider.instance : null;

  // Les post-its (caches mémoire) : une variable par type d'information.
  static DropletUserModel? _userCache;
  static List<MeshMessage> _messagesCache = [];
  static final LinkedHashSet<String> _seenIdsCache = LinkedHashSet();
  static final Set<String> _seenIdsPending = {};
  static Timer? _seenIdsFlushTimer;
  static const int _seenIdsCacheCap = 50000;
  static Map<String, dynamic> _settingsCache = {};
  static Map<String, GroupInfo> _groupsCache = {};
  static List<MeshStatusRecord> _statusesCache = [];

  /// À appeler UNE SEULE FOIS, tout au début du lancement de l'app : ouvre
  /// le classeur permanent, puis recopie tout dedans vers les post-its.
  static Future<void> init() async {
    await db.DbProvider.init();
    await _reloadCaches();
  }

  static Future<void> _reloadCaches() async {
    final d = _database;
    if (d == null) return;

    _userCache = await _readUser();
    _messagesCache = (await d.select(d.meshMessages).get()).map(_msgFromRow).toList();
    _seenIdsCache
      ..clear()
      ..addAll((await d.select(d.seenMessageIds).get()).map((r) => r.messageId));
    _settingsCache = {for (final r in (await d.select(d.appSettings).get())) r.key: _parseSettingValue(r.value)};
    await _reloadGroupsCache();
    await _reloadStatusesCache();
    _startSeenIdsFlushTimer();
  }

  /// Les IDs « déjà vus » sont persistés EN LOT (toutes les [interval]) et
  /// non à chaque paquet reçu : sur un mesh actif, un write SQLite par
  /// message relayé serait le goulet d'étranglement qui ferait s'effondrer
  /// l'app (file d'écriture saturée, latence perçue, batterie). Le cache
  /// mémoire reste la source de vérité immédiate pour le dedup.
  static void _startSeenIdsFlushTimer({Duration interval = const Duration(seconds: 15)}) {
    _seenIdsFlushTimer?.cancel();
    _seenIdsFlushTimer = Timer.periodic(interval, (_) => flushSeenMessageIds());
  }

  /// Vide le buffer d'IDs vus en attente vers la base, en UNE transaction
  /// (pas un insert par ID). Appelé périodiquement et à la fermeture.
  static Future<void> flushSeenMessageIds() async {
    final d = _database;
    if (d == null) {
      _seenIdsPending.clear();
      return;
    }
    if (_seenIdsPending.isEmpty) return;
    final batch = List<String>.from(_seenIdsPending);
    _seenIdsPending.clear();
    try {
      await d.transaction(() async {
        for (final id in batch) {
          await d.into(d.seenMessageIds).insert(
            db.SeenMessageIdsCompanion(
              messageId: Value(id),
              seenAt: Value(DateTime.now().millisecondsSinceEpoch),
            ),
            mode: InsertMode.insertOrIgnore,
          );
        }
      });
    } catch (e) {
      // La base est peut-être en cours de nettoyage — on remet de côté
      // plutôt que de perdre les IDs (le dedup restera mémoire en attendant).
      _seenIdsPending.addAll(batch);
      if (_seenIdsPending.length > _seenIdsCacheCap) {
        _seenIdsPending.removeAll(batch.take(_seenIdsPending.length - _seenIdsCacheCap));
      }
    }
  }

  static Future<void> _reloadStatusesCache() async {
    final d = _database;
    if (d == null) return;
    final rows = await d.select(d.meshStatuses).get();
    _statusesCache = rows
        .map((r) => MeshStatusRecord(
              id: r.id,
              authorId: r.authorId,
              authorPseudo: r.authorPseudo,
              content: r.content,
              createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
              expiresAt: DateTime.fromMillisecondsSinceEpoch(r.expiresAt),
            ))
        .toList();
  }

  static Future<void> _reloadGroupsCache() async {
    final d = _database;
    if (d == null) return;
    final groupRows = await d.select(d.meshGroups).get();
    final memberRows = await d.select(d.groupMembers).get();
    final membersByGroup = <String, List<GroupMemberRecord>>{};
    for (final r in memberRows) {
      membersByGroup.putIfAbsent(r.groupId, () => []).add(GroupMemberRecord(
            peerId: r.peerId,
            role: r.role,
            addedAt: DateTime.fromMillisecondsSinceEpoch(r.addedAt),
            removedAt: r.removedAt != null ? DateTime.fromMillisecondsSinceEpoch(r.removedAt!) : null,
            addedBy: r.addedBy,
          ));
    }
    _groupsCache = {
      for (final r in groupRows)
        r.id: GroupInfo(
          id: r.id,
          name: r.name,
          avatarUrl: r.avatarUrl,
          createdBy: r.createdBy,
          createdAt: DateTime.fromMillisecondsSinceEpoch(r.createdAt),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(r.updatedAt),
          members: membersByGroup[r.id] ?? [],
        ),
    };
  }

  // -- Helpers --------------------------------------------------------------

  /// Fabrique un identifiant unique à partir du pseudo + de l'heure
  /// actuelle, puis le brouille (SHA-256) pour qu'il ne ressemble à rien de
  /// reconnaissable — c'est CET identifiant, pas le pseudo, qui circule sur
  /// le réseau.
  static String generateCryptoIdentity(String pseudo) {
    final bytes = utf8.encode(pseudo + DateTime.now().toIso8601String());
    return sha256.convert(bytes).toString();
  }

  /// Fabrique un identifiant unique aléatoire (UUID) — utilisé partout où
  /// on a juste besoin d'un numéro qui ne sera jamais utilisé deux fois.
  static String generateId() => const Uuid().v4();

  // -- User -----------------------------------------------------------------
  //
  // « Qui suis-je ? » — une seule fiche, la mienne.

  static Future<DropletUserModel?> _readUser() async {
    final d = _database;
    if (d == null) return null;
    final rows = await d.select(d.dropletUser).get();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return DropletUserModel(
      id: r.id,
      pseudo: r.pseudo,
      avatarUrl: r.avatarUrl,
      publicKey: r.publicKey,
    );
  }

  /// Est-ce qu'un compte a déjà été créé sur cet appareil ?
  static bool get hasIdentity => _userCache != null;
  /// Mon profil actuel (ou null si pas encore de compte).
  static DropletUserModel? get currentUser => _userCache;

  static Future<void> saveUser(DropletUserModel user) async {
    final d = _database;
    if (d != null) {
      await d.transaction(() async {
        await d.into(d.dropletUser).insert(
          db.DropletUserCompanion(
            id: Value(user.id),
            pseudo: Value(user.pseudo),
            avatarUrl: Value(user.avatarUrl),
            publicKey: Value(user.publicKey),
          ),
          mode: InsertMode.insertOrReplace,
        );
      });
    }
    _userCache = user;
  }

  // -- Mesh Messages --------------------------------------------------------
  //
  // La plus grosse collection de l'app : tous les messages, toutes
  // conversations confondues.

  /// Tous les messages actuellement connus (lecture instantanée depuis le
  /// post-it, jamais depuis le classeur).
  static List<MeshMessage> getMessages() => _messagesCache;

  /// Supprime définitivement un message (DB + cache mémoire).
  static Future<void> deleteMessage(String id) async {
    final d = _database;
    if (d != null) {
      await (d.delete(d.meshMessages)..where((t) => t.id.equals(id))).go();
    }
    _messagesCache = _messagesCache.where((m) => m.id != id).toList();
  }

  static Future<void> saveMessage(MeshMessage msg) async {
    final d = _database;
    if (d != null) {
      final now = msg.timestamp.millisecondsSinceEpoch;
      await d.transaction(() async {
        await d.into(d.meshMessages).insert(db.MeshMessagesCompanion(
          id: Value(msg.id),
          authorPseudo: Value(msg.authorPseudo),
          content: Value(msg.content),
          type: Value(msg.type),
          timestamp: Value(now),
          senderId: Value<String?>(msg.senderId),
          targetId: Value<String?>(msg.targetId),
          groupId: Value<String?>(msg.groupId),
          imageUrl: Value<String?>(msg.imageUrl),
          audioUrl: Value<String?>(msg.audioUrl),
          hopCount: Value(msg.hopCount),
          reactions: Value(json.encode(msg.reactions)),
          updatedAt: Value(now),
          syncStatus: const Value('synced'),
          fileId: Value<String?>(msg.fileId),
          fileName: Value<String?>(msg.fileName),
          fileSize: Value<int?>(msg.fileSize),
          fileMimeType: Value<String?>(msg.fileMimeType),
          replyToId: Value<String?>(msg.replyToId),
          status: Value(msg.status.name),
          routeInfo: Value<String?>(msg.routeInfo),
          readAt: Value<int?>(msg.readAt?.millisecondsSinceEpoch),
        ),
        mode: InsertMode.insertOrIgnore,
        );
      });
      // Mise à jour incrémentale au lieu du rechargement complet —
      // évite de re-lire TOUTES les lignes à chaque insertion.
      if (!_messagesCache.any((m) => m.id == msg.id)) {
        _messagesCache.add(msg);
      }
    }
  }

  static Future<void> updateMessageStatus(String messageId, MessageStatus status) async {
    final d = _database;
    if (d != null) {
      await (d.update(d.meshMessages)..where((t) => t.id.equals(messageId)))
          .write(db.MeshMessagesCompanion(
            status: Value(status.name),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ));
    }
    final idx = _messagesCache.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      _messagesCache[idx] = _messagesCache[idx].copyWith(status: status);
    }
  }

  /// Marque un message comme lu et persiste l'horodatage.
  static Future<void> updateMessageReadAt(String messageId, DateTime readAt) async {
    final d = _database;
    if (d != null) {
      await (d.update(d.meshMessages)..where((t) => t.id.equals(messageId)))
          .write(db.MeshMessagesCompanion(
            readAt: Value(readAt.millisecondsSinceEpoch),
            updatedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ));
    }
    final idx = _messagesCache.indexWhere((m) => m.id == messageId);
    if (idx >= 0) {
      _messagesCache[idx] = _messagesCache[idx].copyWith(readAt: readAt);
    }
  }

  /// Charge les messages paginés (les plus récents d'abord).
  ///
  /// « Paginé » = par petits paquets plutôt que tout d'un coup — comme
  /// tourner les pages d'un livre une par une au lieu d'essayer de lire
  /// les 300 pages en même temps.
  static List<MeshMessage> getMessagesPaginated({int limit = 50, int offset = 0}) {
    final sorted = List<MeshMessage>.from(_messagesCache)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    if (offset >= sorted.length) return [];
    final end = (offset + limit).clamp(0, sorted.length);
    return sorted.sublist(offset, end);
  }

  /// Sauvegarde un fichier partagé (photo, document...) dans le dossier
  /// dédié de l'app — les vrais octets du fichier, pas juste son nom, sont
  /// écrits sur le disque ici (la base de données ne garde qu'un chemin
  /// vers ce fichier, pas son contenu).
  static Future<String> saveSharedFile({
    required String fileId,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final sharedDir = Directory('${dir.path}/shared');
    if (!await sharedDir.exists()) await sharedDir.create(recursive: true);
    final file = File('${sharedDir.path}/$fileId-$fileName');
    await file.writeAsBytes(bytes);
    return file.path;
  }

  /// Retourne le chemin local d'un fichier partagé.
  static Future<String?> getSharedFilePath(String fileId, String fileName) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/shared/$fileId-$fileName');
    if (await file.exists()) return file.path;
    return null;
  }

  /// Transforme une ligne brute du classeur en un joli objet [MeshMessage]
  /// prêt à être utilisé par le reste de l'app.
  static List<String> _safeParseReactions(String raw) {
    try {
      final decoded = json.decode(raw);
      if (decoded is List) {
        return decoded.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList();
      }
    } catch (_) {}
    return [];
  }

  static MeshMessage _msgFromRow(db.MeshMessage r) => MeshMessage(
    id: r.id,
    authorPseudo: r.authorPseudo,
    content: r.content,
    type: r.type,
    reactions: r.reactions.isNotEmpty
        ? _safeParseReactions(r.reactions)
        : [],
    timestamp: DateTime.fromMillisecondsSinceEpoch(r.timestamp),
    senderId: r.senderId,
    targetId: r.targetId,
    groupId: r.groupId,
    imageUrl: r.imageUrl,
    audioUrl: r.audioUrl,
    hopCount: r.hopCount,
    fileId: r.fileId,
    fileName: r.fileName,
    fileSize: r.fileSize,
    fileMimeType: r.fileMimeType,
    replyToId: r.replyToId,
    status: MessageStatus.values.firstWhere(
      (s) => s.name == r.status,
      orElse: () => MessageStatus.sent,
    ),
    routeInfo: r.routeInfo,
    readAt: r.readAt != null
        ? DateTime.fromMillisecondsSinceEpoch(r.readAt!)
        : null,
  );

  static int getMessageCount() => _messagesCache.length;

  // -- Settings -------------------------------------------------------------

  /// Le classeur ne sait ranger que du texte — cette fonction devine si un
  /// texte représente en fait un nombre ou un vrai/faux, pour le rendre
  /// dans le bon type quand on le relit.
  static dynamic _parseSettingValue(String raw) {
    if (raw == 'true') return true;
    if (raw == 'false') return false;
    final intVal = int.tryParse(raw);
    if (intVal != null) return intVal;
    final doubleVal = double.tryParse(raw);
    if (doubleVal != null) return doubleVal;
    return raw;
  }

  static Map<String, dynamic>? getSettings() {
    if (_settingsCache.isEmpty) return null;
    return Map<String, dynamic>.from(_settingsCache);
  }

  static Future<void> saveSettings(Map<String, dynamic> settings) async {
    final d = _database;
    if (d != null) {
      await d.transaction(() async {
        for (final entry in settings.entries) {
          await d.into(d.appSettings).insert(
            db.AppSettingsCompanion(
              key: Value(entry.key),
              value: Value(entry.value.toString()),
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    }
    _settingsCache = Map<String, dynamic>.from(settings);
  }

  // -- Seen message ids -----------------------------------------------------
  //
  // Sur un réseau mesh, un message fait souvent plusieurs sauts (téléphone
  // A → B → C → D). Sans cette liste des « déjà vus », un même message
  // pourrait tourner en boucle indéfiniment entre les téléphones — comme
  // se souvenir des blagues déjà entendues pour ne pas les raconter en
  // boucle.

  static Set<String> getSeenMessageIds() => _seenIdsCache;

  /// Marque [id] comme « déjà vu » — SYNCHRONE et sans I/O : on met à jour
  /// le cache mémoire (source de vérité du dedup) et on ajoute l'ID au
  /// buffer qui sera persisté en lot par [flushSeenMessageIds]. L'ancien
  /// comportement écrivait dans SQLite à CHAQUE paquet reçu — impossible à
  /// tenir sur un mesh à grande échelle (un nœud traverse des dizaines de
  /// messages/s relayés).
  static void addSeenMessageId(String id) {
    if (_seenIdsCache.contains(id)) return;
    // Cache borné : au-delà de la borne, on évince les plus anciens — le
    // dedup transport (Bloom filter, taille constante) prend le relais pour
    // les très vieux IDs, et re-traiter un vieux message est sans danger.
    if (_seenIdsCache.length >= _seenIdsCacheCap) {
      _seenIdsCache.remove(_seenIdsCache.first);
    }
    _seenIdsCache.add(id);
    _seenIdsPending.add(id);
    if (_seenIdsPending.length > _seenIdsCacheCap) {
      _seenIdsPending.remove(_seenIdsPending.first);
    }
  }

  /// Purge les IDs de messages déjà relayés depuis plus de [maxAge], ET
  /// borne la table à [maxRows] lignes (les plus récentes) pour que le
  /// rechargement initial du cache reste léger, même après des mois
  /// d'usage intensif.
  ///
  /// Sans ce ménage régulier, cette liste grandirait pour toujours — comme
  /// jeter les vieux tickets de caisse après un moment plutôt que les
  /// garder à vie.
  static Future<void> pruneSeenMessageIds({
    Duration maxAge = const Duration(days: 7),
    int maxRows = 100000,
  }) async {
    final d = _database;
    if (d == null) return;
    final cutoff = DateTime.now().subtract(maxAge).millisecondsSinceEpoch;
    await (d.delete(d.seenMessageIds)
      ..where((t) => t.seenAt.isSmallerThanValue(cutoff) | t.seenAt.isNull())
    ).go();

    // Borne la taille : on ne garde que les [maxRows] plus récentes.
    try {
      await d.customStatement(
        'DELETE FROM seen_message_ids WHERE seen_at NOT IN '
        '(SELECT seen_at FROM seen_message_ids ORDER BY seen_at DESC LIMIT $maxRows)',
      );
    } catch (e) {
      debugPrint('[Storage] cap seenMessageIds impossible: $e');
    }

    _seenIdsCache
      ..clear()
      ..addAll((await d.select(d.seenMessageIds).get()).map((r) => r.messageId));
  }

  // -- Generic key/value ----------------------------------------------------
  //
  // Le « vestiaire à casiers » évoqué tout en haut du fichier : une
  // étiquette (`key`), une valeur (`value`), rien de plus. Tout ce qui
  // suit dans ce fichier (conversations archivées, file d'attente,
  // réglages divers...) est construit PAR-DESSUS ces trois fonctions.

  static String? getString(String key) => _settingsCache[key]?.toString();

  static Future<void> setString(String key, String value) async {
    final d = _database;
    if (d != null) {
      await d.into(d.appSettings).insert(
        db.AppSettingsCompanion(key: Value(key), value: Value(value)),
        mode: InsertMode.insertOrReplace,
      );
    }
    _settingsCache[key] = value;
  }

  static Future<void> remove(String key) async {
    final d = _database;
    if (d != null) {
      await (d.delete(d.appSettings)..where((t) => t.key.equals(key))).go();
    }
    _settingsCache.remove(key);
  }

  // -- Conversations archivées (swipe dans la liste des discussions) --------

  static const String _archivedConversationsKey = 'archived_conversations';

  /// La liste des conversations qu'on a rangées de côté (glissées pour
  /// archiver), stockée comme une simple liste de textes séparés par des
  /// virgules dans le casier générique.
  static Set<String> getArchivedConversations() {
    final raw = getString(_archivedConversationsKey);
    if (raw == null || raw.isEmpty) return {};
    return raw.split(',').toSet();
  }

  static Future<void> setConversationArchived(String key, bool archived) async {
    final current = getArchivedConversations();
    if (archived) {
      current.add(key);
    } else {
      current.remove(key);
    }
    await setString(_archivedConversationsKey, current.join(','));
  }

  // -- Outbox (messages en attente d'envoi) ----------------------------------
  //
  // « Outbox » (boîte de sortie) : quand on envoie un message alors
  // qu'aucun autre téléphone n'est à portée, il attend ici — comme une
  // lettre posée dans la boîte aux lettres en attendant que le facteur
  // passe — jusqu'à ce qu'un pair réapparaisse et qu'on puisse enfin
  // l'envoyer pour de vrai.

  static const String _outboxKey = 'mesh_outbox';

  static Future<void> saveOutbox(Map<String, dynamic> entry) async {
    final existing = getString(_outboxKey);
    List<Map<String, dynamic>> outbox;
    if (existing != null && existing.isNotEmpty) {
      try {
        outbox = (jsonDecode(existing) as List).cast<Map<String, dynamic>>();
      } catch (_) { outbox = []; }
    } else {
      outbox = [];
    }
    outbox.add(entry);
    await setString(_outboxKey, jsonEncode(outbox));
  }

  static List<Map<String, dynamic>> getOutbox() {
    final existing = getString(_outboxKey);
    if (existing == null || existing.isEmpty) return [];
    try {
      return (jsonDecode(existing) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearOutboxEntry(String messageId) async {
    final existing = getString(_outboxKey);
    if (existing == null || existing.isEmpty) return;
    try {
      final list = (jsonDecode(existing) as List).cast<Map<String, dynamic>>();
      list.removeWhere((e) => e['id'] == messageId);
      await setString(_outboxKey, jsonEncode(list));
    } catch (_) {}
  }

  static Future<void> clearOutbox() async {
    await remove(_outboxKey);
  }

  // -- Pending relays (store-and-forward) ------------------------------------
  //
  // Même idée que l'outbox, mais pour les messages des AUTRES qu'on est en
  // train de RELAYER (pas les nôtres) : si on doit faire suivre un message
  // mais qu'aucun pair n'est à portée pour l'instant, on le garde de côté
  // pour l'envoyer dès que possible — c'est le principe du « store-and-
  // forward » (garder, puis transmettre), essentiel sur un réseau qui n'a
  // pas toujours tout le monde connecté en même temps.

  static const String _pendingRelaysKey = 'pending_relays';

  static Future<void> savePendingRelay(String messageId, Uint8List payload) async {
    final existing = getString(_pendingRelaysKey);
    List<Map<String, dynamic>> relays;
    if (existing != null && existing.isNotEmpty) {
      try {
        relays = (jsonDecode(existing) as List).cast<Map<String, dynamic>>();
      } catch (_) { relays = []; }
    } else {
      relays = [];
    }
    relays.add({
      'id': messageId,
      'payload': base64Encode(payload),
    });
    await setString(_pendingRelaysKey, jsonEncode(relays));
  }

  static List<Map<String, dynamic>> getPendingRelays() {
    final existing = getString(_pendingRelaysKey);
    if (existing == null || existing.isEmpty) return [];
    try {
      return (jsonDecode(existing) as List).cast<Map<String, dynamic>>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearPendingRelays() async {
    await remove(_pendingRelaysKey);
  }

  // -- Onboarding ------------------------------------------------------------

  static const String _onboardingKey = 'onboarding_complete';

  /// A-t-on déjà fini de créer le compte, la toute première fois ?
  static bool isOnboardingComplete() {
    final v = getString(_onboardingKey);
    return v == 'true';
  }

  static Future<void> setOnboardingComplete() async {
    await setString(_onboardingKey, 'true');
  }

  // -- Contribution (relais rendus au mesh) ----------------------------------

  static const String _relaysCountKey = 'contribution_relays_count';
  static const String _gatewayMinutesKey = 'contribution_gateway_minutes';

  /// Calcule mon total de points de contribution (voir [ContributionPoints]
  /// dans `mesh_message.dart` pour le barème complet).
  static ContributionPoints getContributionPoints() {
    final relaysCount = int.tryParse(getString(_relaysCountKey) ?? '0') ?? 0;
    final gatewayMinutes = int.tryParse(getString(_gatewayMinutesKey) ?? '0') ?? 0;
    return ContributionPoints(
      totalPoints: relaysCount * 10 + gatewayMinutes * 2,
      relaysCount: relaysCount,
      gatewayMinutes: gatewayMinutes,
    );
  }

  static Future<void> incrementRelayCount() async {
    final current = int.tryParse(getString(_relaysCountKey) ?? '0') ?? 0;
    await setString(_relaysCountKey, (current + 1).toString());
  }

  static Future<void> addGatewayMinutes(int minutes) async {
    if (minutes <= 0) return;
    final current = int.tryParse(getString(_gatewayMinutesKey) ?? '0') ?? 0;
    await setString(_gatewayMinutesKey, (current + minutes).toString());
  }

  // -- Check-in de sécurité (mode urgence/catastrophe) -----------------------

  static const String _safetyCheckinsKey = 'safety_checkins';

  /// Enregistre (ou remplace) le dernier check-in connu d'un pair.
  static Future<void> saveSafetyCheckin(SafetyCheckinRecord checkin) async {
    final existing = getSafetyCheckins();
    existing.removeWhere((c) => c.peerId == checkin.peerId);
    existing.add(checkin);
    await setString(_safetyCheckinsKey, jsonEncode(existing.map((c) => c.toJson()).toList()));
  }

  /// Derniers check-in reçus, un par pair (le plus récent), triés du plus
  /// récent au plus ancien.
  static List<SafetyCheckinRecord> getSafetyCheckins() {
    final existing = getString(_safetyCheckinsKey);
    if (existing == null || existing.isEmpty) return [];
    try {
      final list = jsonDecode(existing) as List;
      final checkins = list.map((e) => SafetyCheckinRecord.fromJson(e as Map<String, dynamic>)).toList();
      checkins.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return checkins;
    } catch (_) {
      return [];
    }
  }

  // -- Peer persistence (table de routage durable) --------------------------
  //
  // Le carnet d'adresses des personnes déjà croisées sur le mesh, pour les
  // reconnaître instantanément la prochaine fois qu'elles repassent à
  // portée, sans repartir de zéro.

  static const String _knownPeersKey = 'known_peers';

  /// Sauvegarde la liste des pairs connus pour reconnection rapide.
  static Future<void> savePeers(List<PeerRecord> peers) async {
    final json = peers.map((p) => p.toJson()).toList();
    await setString(_knownPeersKey, jsonEncode(json));
  }

  /// Ajoute ou met à jour un pair dans la table persistante.
  static Future<void> upsertPeer(PeerRecord peer) async {
    final existing = getKnownPeers();
    existing.removeWhere((p) => p.peerId == peer.peerId);
    existing.add(peer);
    await savePeers(existing);
  }

  /// Charge la table de pairs persistée.
  static List<PeerRecord> getKnownPeers() {
    final existing = getString(_knownPeersKey);
    if (existing == null || existing.isEmpty) return [];
    try {
      final list = jsonDecode(existing) as List;
      return list.map((e) => PeerRecord.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      return [];
    }
  }

  /// Charge un pair connu précis, ou null si jamais rencontré.
  static PeerRecord? getPeerRecord(String peerId) {
    for (final p in getKnownPeers()) {
      if (p.peerId == peerId) return p;
    }
    return null;
  }

  /// Supprime un pair de la table persistante.
  static Future<void> removeKnownPeer(String peerId) async {
    final existing = getKnownPeers();
    existing.removeWhere((p) => p.peerId == peerId);
    await savePeers(existing);
  }

  // -- Groupes de discussion --------------------------------------------
  //
  // Même pattern que le reste du fichier : écritures via Drift, lectures
  // synchrones depuis `_groupsCache` (rechargé après chaque écriture).

  static Future<void> upsertGroup({
    required String id,
    required String name,
    String? avatarUrl,
    required String createdBy,
    required DateTime createdAt,
    required DateTime updatedAt,
  }) async {
    final d = _database;
    if (d != null) {
      await d.into(d.meshGroups).insert(
        db.MeshGroupsCompanion(
          id: Value(id),
          name: Value(name),
          avatarUrl: Value(avatarUrl),
          createdBy: Value(createdBy),
          createdAt: Value(createdAt.millisecondsSinceEpoch),
          updatedAt: Value(updatedAt.millisecondsSinceEpoch),
        ),
        mode: InsertMode.insertOrReplace,
      );
      // Mise à jour incrémentale du cache.
      final existing = _groupsCache[id];
      _groupsCache = {
        ..._groupsCache,
        id: GroupInfo(
          id: id,
          name: name,
          avatarUrl: avatarUrl,
          createdBy: createdBy,
          createdAt: createdAt,
          updatedAt: updatedAt,
          members: existing?.members ?? [],
        ),
      };
    } else {
      final existing = _groupsCache[id];
      _groupsCache = {
        ..._groupsCache,
        id: GroupInfo(
          id: id,
          name: name,
          avatarUrl: avatarUrl,
          createdBy: createdBy,
          createdAt: createdAt,
          updatedAt: updatedAt,
          members: existing?.members ?? [],
        ),
      };
    }
  }

  static Future<void> upsertGroupMember({
    required String groupId,
    required String peerId,
    required String role,
    required DateTime addedAt,
    DateTime? removedAt,
    required String addedBy,
  }) async {
    final d = _database;
    if (d != null) {
      await d.into(d.groupMembers).insert(
        db.GroupMembersCompanion(
          groupId: Value(groupId),
          peerId: Value(peerId),
          role: Value(role),
          addedAt: Value(addedAt.millisecondsSinceEpoch),
          removedAt: Value(removedAt?.millisecondsSinceEpoch),
          addedBy: Value(addedBy),
        ),
        mode: InsertMode.insertOrReplace,
      );
      // Mise à jour incrémentale du cache groupes.
      final group = _groupsCache[groupId];
      if (group != null) {
        final members = List<GroupMemberRecord>.from(group.members)
          ..removeWhere((m) => m.peerId == peerId);
        members.add(GroupMemberRecord(
          peerId: peerId,
          role: role,
          addedAt: addedAt,
          removedAt: removedAt,
          addedBy: addedBy,
        ));
        _groupsCache = {..._groupsCache, groupId: group.copyWith(members: members)};
      }
    } else {
      final group = _groupsCache[groupId];
      if (group == null) return;
      final members = List<GroupMemberRecord>.from(group.members)
        ..removeWhere((m) => m.peerId == peerId);
      members.add(GroupMemberRecord(
        peerId: peerId,
        role: role,
        addedAt: addedAt,
        removedAt: removedAt,
        addedBy: addedBy,
      ));
      _groupsCache = {..._groupsCache, groupId: group.copyWith(members: members)};
    }
  }

  static List<GroupMemberRecord> getGroupMembers(String groupId) =>
      _groupsCache[groupId]?.members ?? [];

  static GroupInfo? getGroup(String groupId) => _groupsCache[groupId];

  /// Groupes connus localement (y compris ceux dont on n'est plus membre
  /// actif, pour l'historique).
  static List<GroupInfo> getGroups() => _groupsCache.values.toList();

  // -- Statuts éphémères ------------------------------------------------

  static Future<void> saveStatus(MeshStatusRecord status) async {
    final d = _database;
    if (d != null) {
      await d.into(d.meshStatuses).insert(
        db.MeshStatusesCompanion(
          id: Value(status.id),
          authorId: Value(status.authorId),
          authorPseudo: Value(status.authorPseudo),
          content: Value(status.content),
          createdAt: Value(status.createdAt.millisecondsSinceEpoch),
          expiresAt: Value(status.expiresAt.millisecondsSinceEpoch),
        ),
        mode: InsertMode.insertOrReplace,
      );
      // Mise à jour incrémentale du cache statuts.
      _statusesCache = [..._statusesCache.where((s) => s.id != status.id), status];
    } else {
      _statusesCache = [..._statusesCache.where((s) => s.id != status.id), status];
    }
  }

  /// Statuts encore actifs, triés du plus récent au plus ancien. Les
  /// statuts expirés sont exclus ici même s'ils n'ont pas encore été purgés
  /// de la base (purge périodique séparée, voir [pruneExpiredStatuses]).
  static List<MeshStatusRecord> getActiveStatuses() {
    final active = _statusesCache.where((s) => !s.isExpired).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return active;
  }

  /// Fait le ménage : jette les statuts périmés (plus de 24h), comme des
  /// dessins à la craie qu'on efface une fois qu'ils ont fait leur temps.
  static Future<void> pruneExpiredStatuses() async {
    final d = _database;
    if (d == null) {
      _statusesCache = _statusesCache.where((s) => !s.isExpired).toList();
      return;
    }
    final cutoff = DateTime.now().millisecondsSinceEpoch;
    await (d.delete(d.meshStatuses)..where((t) => t.expiresAt.isSmallerOrEqualValue(cutoff))).go();
    await _reloadStatusesCache();
    await _pruneStatusViews();
    await _pruneStatusExtras();
  }

  // -- Accusés de vue des statuts (« vu par ») -------------------------------
  //
  // Petit volume borné par la durée de vie des statuts (24h) : un blob JSON
  // sous une seule clé du magasin générique suffit, pas besoin d'une table
  // Drift dédiée (même pattern que l'outbox ci-dessus).

  static const String _statusViewsKey = 'status_views';

  static Map<String, List<Map<String, dynamic>>> _readStatusViews() {
    final raw = getString(_statusViewsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      return decoded.map((k, v) => MapEntry(k, (v as List).cast<Map<String, dynamic>>()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> _writeStatusViews(Map<String, List<Map<String, dynamic>>> views) async {
    await setString(_statusViewsKey, jsonEncode(views));
  }

  /// Enregistre que [viewerId] a vu le statut [statusId] à [ts]. Idempotent
  /// (un même spectateur ne compte qu'une fois par statut).
  ///
  /// « Idempotent » = même si on appelle cette fonction plusieurs fois de
  /// suite pour la même personne, le résultat final ne change pas — elle
  /// n'apparaît qu'UNE SEULE fois dans la liste des « vu par », pas
  /// plusieurs.
  static Future<void> recordStatusView({
    required String statusId,
    required String viewerId,
    required String viewerPseudo,
    required DateTime ts,
  }) async {
    final views = _readStatusViews();
    final list = views.putIfAbsent(statusId, () => []);
    if (list.any((v) => v['viewerId'] == viewerId)) return;
    list.add({
      'viewerId': viewerId,
      'viewerPseudo': viewerPseudo,
      'ts': ts.toIso8601String(),
    });
    await _writeStatusViews(views);
  }

  /// Spectateurs d'un statut, du plus récent au plus ancien.
  static List<StatusViewRecord> getStatusViewers(String statusId) {
    final list = _readStatusViews()[statusId] ?? const [];
    final viewers = list
        .map((v) => StatusViewRecord(
              viewerId: v['viewerId'] as String,
              viewerPseudo: v['viewerPseudo'] as String,
              viewedAt: DateTime.tryParse(v['ts'] as String? ?? '') ?? DateTime.now(),
            ))
        .toList()
      ..sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
    return viewers;
  }

  static Future<void> _pruneStatusViews() async {
    final activeIds = _statusesCache.map((s) => s.id).toSet();
    final views = _readStatusViews();
    views.removeWhere((statusId, _) => !activeIds.contains(statusId));
    await _writeStatusViews(views);
  }

  // -- Médias, j'aime et commentaires des statuts ---------------------------
  //
  // Ces trois informations vivent dans le magasin clé/valeur générique
  // plutôt que dans la table des statuts.
  //
  // Ce n'est pas de la paresse : la table `MeshStatuses` est lue et
  // écrite par du code généré (Drift), et lui ajouter des colonnes
  // imposerait une migration de base sur tous les appareils déjà
  // installés — pour des données qui, de toute façon, s'effacent d'elles-
  // mêmes au bout de 24 heures avec le statut qu'elles décorent. Le
  // volume est minuscule et borné par cette durée de vie ; c'est
  // exactement le même raisonnement que pour les accusés de vue
  // ci-dessus, et pour la file d'attente d'envoi.

  static const String _statusMediaKey = 'status_media';
  static const String _statusFeedbackKey = 'status_feedback';

  static Map<String, dynamic> _readMap(String key) {
    final raw = getString(key);
    if (raw == null || raw.isEmpty) return {};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return {};
    }
  }

  /// Enregistre ce qui accompagne un statut (photo, vidéo, vocal,
  /// musique, couleur de fond).
  static Future<void> saveStatusMedia(String statusId, StatusMedia media) async {
    if (media.isPlainText) return;
    final all = _readMap(_statusMediaKey);
    all[statusId] = media.toJson();
    await setString(_statusMediaKey, jsonEncode(all));
  }

  /// Ce qui accompagne un statut — [StatusMedia.empty] s'il est en texte
  /// seul, ou si l'annonce vient d'une version de Droplet antérieure aux
  /// statuts en média.
  static StatusMedia getStatusMedia(String statusId) {
    final entry = _readMap(_statusMediaKey)[statusId];
    if (entry is! Map<String, dynamic>) return StatusMedia.empty;
    try {
      return StatusMedia.fromJson(entry);
    } catch (_) {
      return StatusMedia.empty;
    }
  }

  /// Ajoute un « j'aime » ou un commentaire reçu sur l'un de mes statuts.
  ///
  /// Un même auteur ne peut avoir qu'UN « j'aime » par statut : réappuyer
  /// remplace l'emoji précédent au lieu d'en empiler un second. Les
  /// commentaires, eux, s'accumulent — on peut dire plusieurs choses.
  static Future<void> addStatusFeedback(StatusFeedback feedback) async {
    final all = _readMap(_statusFeedbackKey);
    final list = (all[feedback.statusId] as List?)?.toList() ?? <dynamic>[];

    if (feedback.isLike) {
      list.removeWhere((e) =>
          e is Map && e['authorId'] == feedback.authorId && e['emoji'] != null);
    }
    list.add(feedback.toJson());

    // Plafond de sécurité : un statut ne vit que 24 heures, mais rien
    // n'empêche un pair défaillant d'envoyer mille fois la même chose.
    all[feedback.statusId] =
        list.length > 300 ? list.sublist(list.length - 300) : list;
    await setString(_statusFeedbackKey, jsonEncode(all));
  }

  /// Retire mon « j'aime » d'un statut (deuxième appui sur le cœur).
  static Future<void> removeStatusLike(String statusId, String authorId) async {
    final all = _readMap(_statusFeedbackKey);
    final list = (all[statusId] as List?)?.toList();
    if (list == null) return;
    list.removeWhere(
        (e) => e is Map && e['authorId'] == authorId && e['emoji'] != null);
    all[statusId] = list;
    await setString(_statusFeedbackKey, jsonEncode(all));
  }

  /// Tous les retours reçus sur un statut, du plus ancien au plus récent.
  static List<StatusFeedback> getStatusFeedback(String statusId) {
    final list = _readMap(_statusFeedbackKey)[statusId];
    if (list is! List) return const [];
    final out = <StatusFeedback>[];
    for (final e in list) {
      if (e is! Map) continue;
      try {
        out.add(StatusFeedback.fromJson(Map<String, dynamic>.from(e)));
      } catch (_) {}
    }
    out.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return out;
  }

  /// Fait le ménage en même temps que les statuts : ce qui décorait un
  /// statut expiré n'a plus de raison d'être conservé.
  static Future<void> _pruneStatusExtras() async {
    final activeIds = _statusesCache.map((s) => s.id).toSet();
    for (final key in [_statusMediaKey, _statusFeedbackKey]) {
      final all = _readMap(key);
      all.removeWhere((statusId, _) => !activeIds.contains(statusId));
      await setString(key, jsonEncode(all));
    }
  }

  // -- Journal d'appels ----------------------------------------------------
  //
  // Même choix de stockage que les accusés de vue : un blob JSON sous une
  // clé du magasin générique. Le volume est borné à la main (200 entrées),
  // ce qui représente au grand maximum quelques dizaines de kilo-octets —
  // très en dessous de ce qui justifierait une table dédiée.

  static const String _callLogKey = 'call_log';
  static const int _callLogMaxEntries = 200;

  /// Ajoute un appel au journal, le plus récent en tête.
  static Future<void> addCallLog(CallLogEntry entry) async {
    final entries = getCallLogs();
    entries.insert(0, entry);
    // Au-delà de la limite, les plus anciens sont oubliés : un journal
    // d'appels qui grossit indéfiniment finirait par ralentir l'ouverture
    // de l'onglet sans que personne ne remonte jamais aussi loin.
    final kept = entries.take(_callLogMaxEntries).toList();
    await setString(
      _callLogKey,
      jsonEncode(kept.map((e) => e.toJson()).toList()),
    );
  }

  /// Le journal complet, du plus récent au plus ancien.
  static List<CallLogEntry> getCallLogs() {
    final raw = getString(_callLogKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((e) => CallLogEntry.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      // Journal illisible (version antérieure, écriture interrompue) : on
      // repart d'une liste vide plutôt que de faire échouer l'écran.
      return [];
    }
  }

  /// Vide le journal d'appels.
  static Future<void> clearCallLogs() => setString(_callLogKey, '');

  // -- Sender-keys de groupe (ratchet) -----------------------------------
  //
  // Les « combinaisons de cadenas qui changent toutes seules » utilisées
  // pour chiffrer les messages de groupe (voir `crypto_service.dart` pour
  // l'explication complète du ratchet) — ici, on ne fait que les ranger et
  // les relire.

  static Future<void> upsertGroupSenderKey({
    required String groupId,
    required String ownerPeerId,
    required String chainKey,
    required int counter,
    required bool isMine,
  }) async {
    final d = _database;
    if (d == null) return;
    await d.into(d.groupSenderKeys).insert(
      db.GroupSenderKeysCompanion(
        groupId: Value(groupId),
        ownerPeerId: Value(ownerPeerId),
        chainKey: Value(chainKey),
        counter: Value(counter),
        isMine: Value(isMine),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  static Future<({String chainKey, int counter, bool isMine})?> getGroupSenderKey(
    String groupId,
    String ownerPeerId,
  ) async {
    final d = _database;
    if (d == null) return null;
    final rows = await (d.select(d.groupSenderKeys)
          ..where((t) => t.groupId.equals(groupId) & t.ownerPeerId.equals(ownerPeerId)))
        .get();
    if (rows.isEmpty) return null;
    final r = rows.first;
    return (chainKey: r.chainKey, counter: r.counter, isMine: r.isMine);
  }

  /// Dump complet de toutes les sender-keys connues (miennes et celles
  /// reçues d'autres membres), pour une sauvegarde d'identité — sans quoi
  /// une restauration perdrait la capacité de déchiffrer les messages de
  /// groupe déjà échangés.
  static Future<List<({String groupId, String ownerPeerId, String chainKey, int counter, bool isMine})>> getAllGroupSenderKeys() async {
    final d = _database;
    if (d == null) return [];
    final rows = await d.select(d.groupSenderKeys).get();
    return rows
        .map((r) => (
              groupId: r.groupId,
              ownerPeerId: r.ownerPeerId,
              chainKey: r.chainKey,
              counter: r.counter,
              isMine: r.isMine,
            ))
        .toList();
  }

  static Future<void> deleteGroupSenderKey(String groupId, String ownerPeerId) async {
    final d = _database;
    if (d == null) return;
    await (d.delete(d.groupSenderKeys)
          ..where((t) => t.groupId.equals(groupId) & t.ownerPeerId.equals(ownerPeerId)))
        .go();
  }

  /// Cache borné des clés de message "sautées" (désordre de livraison
  /// multi-hop) — même pattern JSON blob que [savePendingRelay].
  static const int _maxSkippedGroupKeysPerOwner = 1000;

  static String _skippedGroupKeyStorageKey(String groupId, String ownerPeerId) =>
      'group_skipped_keys_${groupId}_$ownerPeerId';

  static Future<void> saveSkippedGroupKey(
    String groupId,
    String ownerPeerId,
    int counter,
    String messageKeyB64,
  ) async {
    final storageKey = _skippedGroupKeyStorageKey(groupId, ownerPeerId);
    final existing = getString(storageKey);
    Map<String, String> skipped = {};
    if (existing != null && existing.isNotEmpty) {
      try {
        skipped = Map<String, String>.from(jsonDecode(existing) as Map);
      } catch (_) {}
    }
    skipped[counter.toString()] = messageKeyB64;
    // On ne garde pas ces clés « sautées » indéfiniment non plus — au-delà
    // d'un certain nombre, on jette les plus anciennes pour laisser la
    // place aux plus récentes.
    if (skipped.length > _maxSkippedGroupKeysPerOwner) {
      final sortedKeys = skipped.keys.map(int.parse).toList()..sort();
      final toRemove = sortedKeys.length - _maxSkippedGroupKeysPerOwner;
      for (var i = 0; i < toRemove; i++) {
        skipped.remove(sortedKeys[i].toString());
      }
    }
    await setString(storageKey, jsonEncode(skipped));
  }

  static Future<String?> takeSkippedGroupKey(String groupId, String ownerPeerId, int counter) async {
    final storageKey = _skippedGroupKeyStorageKey(groupId, ownerPeerId);
    final existing = getString(storageKey);
    if (existing == null || existing.isEmpty) return null;
    try {
      final skipped = Map<String, String>.from(jsonDecode(existing) as Map);
      final key = skipped.remove(counter.toString());
      if (key != null) await setString(storageKey, jsonEncode(skipped));
      return key;
    } catch (_) {
      return null;
    }
  }
}

/// Identité locale de l'utilisateur Droplet — mon propre profil, tel qu'il
/// est rangé dans le classeur.
class DropletUserModel {
  final String id;
  final String pseudo;
  final String? avatarUrl;

  /// Clé publique X25519 (base64) de cet appareil, générée à l'onboarding.
  final String? publicKey;

  const DropletUserModel({
    required this.id,
    required this.pseudo,
    this.avatarUrl,
    this.publicKey,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'pseudo': pseudo,
    'avatarUrl': avatarUrl,
    'publicKey': publicKey,
  };

  factory DropletUserModel.fromJson(Map<String, dynamic> json) => DropletUserModel(
    id: json['id'] as String,
    pseudo: json['pseudo'] as String,
    avatarUrl: json['avatarUrl'] as String?,
    publicKey: json['publicKey'] as String?,
  );
}
