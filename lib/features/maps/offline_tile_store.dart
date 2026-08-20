// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE MAGASIN DE CARTES HORS CONNEXION : l'endroit où Droplet range les
// morceaux de carte, et d'où il les ressort quand il n'y a plus de
// réseau.
//
// ── Comment une carte est faite ────────────────────────────────────────
//
// Une carte n'est pas une grande image. C'est une mosaïque de petits
// carrés de 256 pixels appelés TUILES, rangés par niveau de zoom :
//
//     zoom 0  →  1 tuile      (la Terre entière)
//     zoom 1  →  4 tuiles
//     zoom 2  →  16 tuiles
//     ...
//     zoom 15 →  1 milliard de tuiles pour la planète
//
// Chaque tuile a trois coordonnées : z (le zoom), x et y (sa case dans
// la grille de ce zoom). Afficher une carte, c'est aller chercher la
// vingtaine de tuiles qui couvrent l'écran.
//
// ── Le format MBTiles ──────────────────────────────────────────────────
//
// MBTiles est le format standard pour ranger ces tuiles dans UN seul
// fichier. Et sa trouvaille, c'est que ce fichier est simplement une
// base SQLite avec une table `tiles(zoom_level, tile_column, tile_row,
// tile_data)`.
//
// C'est précisément pourquoi il a été retenu ici : Droplet embarque déjà
// SQLite pour ses messages. Lire et écrire des cartes ne demande donc
// AUCUNE bibliothèque supplémentaire, et le fichier produit s'ouvre
// dans n'importe quel outil cartographique du marché.
//
// ── ⚠️ Le piège du Y inversé ───────────────────────────────────────────
//
// MBTiles range les lignes selon la convention TMS, qui compte les Y du
// BAS vers le haut. Les cartes du web, elles, comptent du HAUT vers le
// bas. Une tuile stockée sans conversion se retrouve donc au bon
// endroit horizontalement, mais symétrique verticalement — et la carte
// affiche l'hémisphère d'en face. La conversion `y → 2^z - 1 - y` est
// appliquée à CHAQUE lecture et à chaque écriture.
// ============================================================================

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';

/// Une carte hors connexion rangée sur l'appareil.
class OfflineRegion {
  const OfflineRegion({
    required this.id,
    required this.name,
    required this.filePath,
    required this.sizeBytes,
    required this.tileCount,
    required this.minZoom,
    required this.maxZoom,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String filePath;
  final int sizeBytes;
  final int tileCount;
  final int minZoom;
  final int maxZoom;
  final DateTime updatedAt;

  /// Vrai s'il s'agit du cache des zones consultées, et non d'une carte
  /// importée : il se vide au lieu de se supprimer.
  bool get isCache {
    final name = Uri.file(filePath).pathSegments.last;
    return name == 'cache.mbtiles' || name.startsWith('cache-');
  }

  /// « 86 Mo », « 1,2 Go ».
  String get sizeLabel {
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).round()} ko';
    }
    final mo = sizeBytes / (1024 * 1024);
    if (mo < 1024) return '${mo.toStringAsFixed(mo < 10 ? 1 : 0)} Mo';
    return '${(mo / 1024).toStringAsFixed(1)} Go';
  }
}

/// Ouvre, lit et remplit les fichiers MBTiles de l'appareil.
class OfflineTileStore {
  OfflineTileStore._();

  static final OfflineTileStore instance = OfflineTileStore._();

  /// Le fichier dans lequel on ÉCRIT les tuiles vues en ligne.
  ///
  /// Séparé des cartes importées : celles-ci sont en lecture seule (on
  /// ne va pas modifier le fichier que quelqu'un nous a transmis), alors
  /// que celui-ci se remplit tout seul au fil de la navigation.
  Database? _cache;

  /// ⚠️ LE NOM DU FICHIER DE CACHE PORTE LA SOURCE DES TUILES, et c'est
  /// une leçon apprise à la dure.
  ///
  /// Une première version pointait vers les serveurs d'OpenStreetMap.
  /// Ceux-ci refusent les applications distribuées — mais ils le font en
  /// renvoyant une IMAGE « Access blocked » avec un statut HTTP 200, et
  /// non une erreur. Droplet a donc consciencieusement mis en cache
  /// cette image de refus pour chaque case de la carte.
  ///
  /// Le plus pernicieux est venu ensuite : en changeant de fournisseur,
  /// rien n'a changé à l'écran. Le magasin local est consulté AVANT le
  /// réseau, il trouvait les images de refus, et n'interrogeait donc
  /// jamais le nouveau serveur. Une carte de messages d'erreur, figée
  /// pour toujours.
  ///
  /// En inscrivant la source dans le nom du fichier, changer de
  /// fournisseur repart d'un cache vierge, mécaniquement.
  static const String _cacheName = 'cache-carto-dark.mbtiles';

  /// Les cartes importées, ouvertes en lecture.
  final Map<String, Database> _imported = {};

  Directory? _dir;
  bool _ready = false;

  // ─────────────────────────────────────────────────────────────
  //  OUVERTURE
  // ─────────────────────────────────────────────────────────────

  Future<Directory> _mapsDir() async {
    final existing = _dir;
    if (existing != null) return existing;
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/maps');
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// À appeler une fois avant d'afficher une carte.
  Future<void> init() async {
    if (_ready) return;
    try {
      final dir = await _mapsDir();

      // Les caches d'anciennes sources sont supprimés : ils ne
      // contiennent que des tuiles devenues inutilisables, et les garder
      // ferait réapparaître l'ancien fond par-dessus le nouveau.
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        final name = entry.uri.pathSegments.last;
        // ⚠️ ON NE TOUCHE JAMAIS AU CACHE COURANT NI À SES ANNEXES.
        //
        // C'EST LE BOGUE QUI FAISAIT « OUBLIER » LES CARTES CONSULTÉES.
        //
        // SQLite en mode WAL n'écrit pas directement dans le fichier
        // `.mbtiles` : il écrit d'abord dans deux fichiers voisins,
        // `…-wal` et `…-shm`, dont le contenu n'est recopié dans le
        // fichier principal qu'au fil des points de contrôle. Le `-wal`
        // contient donc, à tout instant, les tuiles les plus récentes —
        // exactement celles qu'on vient de consulter.
        //
        // Le test précédent (`name != _cacheName`) ne reconnaissait que
        // le fichier principal. Les deux annexes, elles, commençaient
        // bien par « cache- » sans être égales à `_cacheName` : elles
        // étaient donc SUPPRIMÉES À CHAQUE DÉMARRAGE de l'application.
        // Le journal de l'appareil le montrait noir sur blanc :
        //
        //     [Cartes] ancien cache supprimé: cache-carto-dark.mbtiles-wal
        //     [Cartes] ancien cache supprimé: cache-carto-dark.mbtiles-shm
        //
        // Parcourir un quartier, fermer l'app, la rouvrir : tout était
        // perdu. Et pour une application dont la promesse est de
        // fonctionner sans réseau, perdre le fond de carte hors
        // connexion, c'est perdre la fonction.
        if (name.startsWith(_cacheName)) continue;
        if (_isCacheFile(name)) {
          try {
            entry.deleteSync();
            debugPrint('[Cartes] ancien cache supprimé: $name');
          } catch (_) {}
        }
      }

      _cache = sqlite3.open('${dir.path}/$_cacheName');
      _tuneForSpeed(_cache!);
      _prepareSchema(_cache!, name: 'Zones consultées');
      _startFlushTimer();

      // Toutes les cartes importées présentes dans le dossier.
      for (final entry in dir.listSync()) {
        if (entry is! File) continue;
        if (!entry.path.endsWith('.mbtiles')) continue;
        if (_isCacheFile(entry.uri.pathSegments.last)) continue;
        try {
          _imported[entry.path] = sqlite3.open(entry.path, mode: OpenMode.readOnly);
        } catch (e) {
          debugPrint('[Cartes] fichier illisible ${entry.path}: $e');
        }
      }
      _ready = true;
    } catch (e) {
      debugPrint('[Cartes] ouverture impossible: $e');
    }
  }

  /// Règle SQLite pour l'usage qu'on en fait ici.
  ///
  /// ⚠️ Sans ces deux réglages, la carte SACCADE à chaque déplacement.
  ///
  /// Par défaut, SQLite force l'écriture physique sur le disque après
  /// CHAQUE enregistrement, et attend la confirmation du matériel. C'est
  /// la bonne politique pour des messages, qu'on ne veut jamais perdre.
  /// Pour des tuiles de carte, c'est absurde : elles sont
  /// retéléchargeables, et il y en a vingt à écrire par écran.
  ///
  ///   • Le journal WAL permet de lire pendant qu'on écrit, au lieu de
  ///     bloquer l'affichage le temps de l'écriture.
  ///   • `synchronous = NORMAL` cesse d'attendre le disque à chaque
  ///     tuile. Au pire, une coupure de courant perd les dernières
  ///     tuiles — soit exactement ce qu'un rafraîchissement récupère.
  void _tuneForSpeed(Database db) {
    try {
      db.execute('PRAGMA journal_mode = WAL');
      db.execute('PRAGMA synchronous = NORMAL');
    } catch (e) {
      debugPrint('[Cartes] réglages SQLite refusés: $e');
    }
  }

  /// Vrai pour un fichier de cache, quelle qu'en soit la source.
  static bool _isCacheFile(String fileName) =>
      fileName == 'cache.mbtiles' || fileName.startsWith('cache-');

  /// Crée les tables du format MBTiles si elles n'existent pas.
  void _prepareSchema(Database db, {required String name}) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS tiles (
        zoom_level  INTEGER,
        tile_column INTEGER,
        tile_row    INTEGER,
        tile_data   BLOB
      );
    ''');
    // L'index unique sert double : il accélère la lecture (c'est LA
    // requête faite vingt fois par écran) et il empêche d'enregistrer
    // deux fois la même tuile.
    db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS tile_index
        ON tiles (zoom_level, tile_column, tile_row);
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS metadata (name TEXT, value TEXT);
    ''');
    final count = db
        .select("SELECT COUNT(*) AS n FROM metadata WHERE name = 'name'")
        .first['n'] as int;
    if (count == 0) {
      db.execute("INSERT INTO metadata VALUES ('name', ?)", [name]);
      db.execute("INSERT INTO metadata VALUES ('format', 'png')");
      db.execute("INSERT INTO metadata VALUES ('type', 'baselayer')");
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  LECTURE
  // ─────────────────────────────────────────────────────────────

  /// Cherche une tuile, d'abord dans les cartes importées puis dans le
  /// cache. Renvoie `null` si personne ne l'a.
  Uint8List? read(int z, int x, int y) {
    // Conversion vers la convention TMS du format MBTiles — voir le
    // grand commentaire en tête de fichier.
    final tmsY = (1 << z) - 1 - y;

    for (final db in _imported.values) {
      final found = _selectTile(db, z, x, tmsY);
      if (found != null) return found;
    }
    final cache = _cache;
    if (cache != null) return _selectTile(cache, z, x, tmsY);
    return null;
  }

  Uint8List? _selectTile(Database db, int z, int x, int tmsY) {
    try {
      final rows = db.select(
        'SELECT tile_data FROM tiles '
        'WHERE zoom_level = ? AND tile_column = ? AND tile_row = ? LIMIT 1',
        [z, x, tmsY],
      );
      if (rows.isEmpty) return null;
      final data = rows.first['tile_data'];
      return data is Uint8List ? data : null;
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  ÉCRITURE
  // ─────────────────────────────────────────────────────────────

  /// Range une tuile récupérée en ligne, pour qu'elle soit encore là
  /// quand le réseau ne le sera plus.
  ///
  /// C'est le cœur du dispositif : Droplet ne télécharge JAMAIS une
  /// région entière d'avance — la politique d'utilisation des serveurs
  /// de tuiles l'interdit, et ce serait des dizaines de milliers de
  /// requêtes pour une ville. Il garde simplement ce qu'on a
  /// effectivement regardé. Parcourir son quartier une fois en ligne
  /// suffit à l'avoir hors connexion ensuite.
  void write(int z, int x, int y, Uint8List bytes) {
    if (_cache == null || bytes.isEmpty) return;
    // Une tuile de carte fait au minimum quelques centaines d'octets ;
    // en dessous, c'est une image d'erreur ou un fichier tronqué, et le
    // conserver empoisonnerait la carte durablement.
    if (bytes.length < 200) return;

    // ⚠️ MISE EN ATTENTE, PAS D'ÉCRITURE IMMÉDIATE.
    //
    // Chaque déplacement de la carte fait arriver une vingtaine de
    // tuiles quasi simultanément. Les écrire une par une, c'est vingt
    // transactions SQLite pendant que le doigt fait glisser la carte —
    // et l'affichage se fige visiblement à chaque fois.
    //
    // Elles sont donc mises de côté et écrites TOUTES ENSEMBLE, en une
    // seule transaction, une fois par seconde.
    _pending.add((z: z, x: x, y: y, bytes: bytes));
    // Garde-fou : un déplacement très rapide peut faire arriver des
    // centaines de tuiles avant le prochain vidage. Au-delà, on écrit
    // sans attendre plutôt que de laisser la mémoire enfler.
    if (_pending.length >= 128) _flush();
  }

  /// Jette une tuile du cache : elle s'est révélée indécodable.
  ///
  /// Seul le cache est touché, JAMAIS les cartes importées par
  /// l'utilisateur — celles-ci sont ouvertes en lecture seule et ne nous
  /// appartiennent pas. Si une carte importée contient une tuile abîmée,
  /// c'est à son auteur de la corriger ; la case restera simplement vide.
  void evict(int z, int x, int y) {
    final cache = _cache;
    if (cache == null) return;
    final tmsY = (1 << z) - 1 - y;
    try {
      cache.execute(
        'DELETE FROM tiles '
        'WHERE zoom_level = ? AND tile_column = ? AND tile_row = ?',
        [z, x, tmsY],
      );
    } catch (e) {
      debugPrint('[Cartes] suppression de $z/$x/$y impossible: $e');
    }
  }

  /// Les tuiles reçues et pas encore écrites.
  final List<({int z, int x, int y, Uint8List bytes})> _pending = [];
  Timer? _flushTimer;

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer.periodic(const Duration(seconds: 1), (_) => _flush());
  }

  /// Écrit d'un coup tout ce qui attend.
  void _flush() {
    final cache = _cache;
    if (cache == null || _pending.isEmpty) return;

    final batch = List.of(_pending);
    _pending.clear();

    try {
      // Une seule transaction pour tout le lot : c'est ce qui transforme
      // vingt écritures disque en une seule.
      cache.execute('BEGIN');
      final statement = cache.prepare(
        'INSERT OR IGNORE INTO tiles '
        '(zoom_level, tile_column, tile_row, tile_data) VALUES (?, ?, ?, ?)',
      );
      for (final tile in batch) {
        final tmsY = (1 << tile.z) - 1 - tile.y;
        statement.execute([tile.z, tile.x, tmsY, tile.bytes]);
      }
      statement.dispose();
      cache.execute('COMMIT');
    } catch (e) {
      try {
        cache.execute('ROLLBACK');
      } catch (_) {}
      debugPrint('[Cartes] écriture du lot impossible: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  //  GESTION DES CARTES
  // ─────────────────────────────────────────────────────────────

  /// Les cartes présentes sur l'appareil, cache compris.
  Future<List<OfflineRegion>> regions() async {
    final out = <OfflineRegion>[];
    final dir = await _mapsDir();
    if (!await dir.exists()) return out;

    for (final entry in dir.listSync()) {
      if (entry is! File || !entry.path.endsWith('.mbtiles')) continue;
      final db = _isCacheFile(entry.uri.pathSegments.last)
          ? _cache
          : _imported[entry.path];
      if (db == null) continue;

      try {
        final stat = entry.statSync();
        final count =
            db.select('SELECT COUNT(*) AS n FROM tiles').first['n'] as int;
        final zooms = db.select(
            'SELECT MIN(zoom_level) AS mn, MAX(zoom_level) AS mx FROM tiles');
        final name = _metadata(db, 'name') ??
            entry.uri.pathSegments.last.replaceAll('.mbtiles', '');

        out.add(OfflineRegion(
          id: entry.path,
          name: name,
          filePath: entry.path,
          sizeBytes: stat.size,
          tileCount: count,
          minZoom: (zooms.first['mn'] as int?) ?? 0,
          maxZoom: (zooms.first['mx'] as int?) ?? 0,
          updatedAt: stat.modified,
        ));
      } catch (e) {
        debugPrint('[Cartes] fiche illisible ${entry.path}: $e');
      }
    }

    // Le cache en tête : c'est celui qui bouge, et donc celui qu'on
    // vient consulter.
    out.sort((a, b) {
      if (a.isCache) return -1;
      if (b.isCache) return 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return out;
  }

  String? _metadata(Database db, String key) {
    try {
      final rows =
          db.select('SELECT value FROM metadata WHERE name = ? LIMIT 1', [key]);
      if (rows.isEmpty) return null;
      return rows.first['value'] as String?;
    } catch (_) {
      return null;
    }
  }

  /// Copie un fichier `.mbtiles` choisi par l'utilisateur dans le
  /// dossier des cartes, et l'ouvre.
  ///
  /// Renvoie un message d'erreur en cas de refus, `null` si tout va
  /// bien. On VÉRIFIE que le fichier est bien une carte avant de le
  /// copier : un fichier au bon nom mais au mauvais contenu produirait
  /// sinon une carte vide, sans explication.
  Future<String?> import(File source, {String? displayName}) async {
    try {
      final probe = sqlite3.open(source.path, mode: OpenMode.readOnly);
      final ok = probe
          .select("SELECT name FROM sqlite_master "
              "WHERE type='table' AND name='tiles'")
          .isNotEmpty;
      final tiles = ok
          ? probe.select('SELECT COUNT(*) AS n FROM tiles').first['n'] as int
          : 0;
      probe.dispose();

      if (!ok) return "Ce fichier n'est pas une carte MBTiles.";
      if (tiles == 0) return 'Cette carte est vide.';

      final dir = await _mapsDir();
      final base = displayName ??
          source.uri.pathSegments.last.replaceAll('.mbtiles', '');
      final safe = base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final target = File('${dir.path}/$safe.mbtiles');
      if (await target.exists()) return 'Cette carte est déjà installée.';

      await source.copy(target.path);
      _imported[target.path] =
          sqlite3.open(target.path, mode: OpenMode.readOnly);
      return null;
    } catch (e) {
      debugPrint('[Cartes] import impossible: $e');
      return 'Impossible de lire ce fichier.';
    }
  }

  /// Supprime une carte. Le cache, lui, n'est pas supprimé mais VIDÉ :
  /// il doit continuer d'exister pour accueillir les prochaines tuiles.
  Future<void> remove(OfflineRegion region) async {
    if (region.isCache) {
      try {
        _cache?.execute('DELETE FROM tiles');
        _cache?.execute('VACUUM');
      } catch (e) {
        debugPrint('[Cartes] vidage impossible: $e');
      }
      return;
    }
    _imported.remove(region.filePath)?.dispose();
    final file = File(region.filePath);
    if (await file.exists()) await file.delete();
  }

  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    // Ce qui attendait encore est écrit avant de fermer : sinon les
    // dernières tuiles consultées seraient perdues à chaque sortie.
    _flush();
    _cache?.dispose();
    for (final db in _imported.values) {
      db.dispose();
    }
    _imported.clear();
    _cache = null;
    _ready = false;
  }
}
