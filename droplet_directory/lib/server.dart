// ============================================================================
// DROPLET DIRECTORY SERVER
// ============================================================================
// Serveur annuaire .onion pour Droplet.
//
// Les appareils s'enregistrent avec leur pseudo + adresse .onion.
// Les autres appareils peuvent chercher des contacts par nom.
//
// C'est aussi le seul des trois petits serveurs Droplet à connaître le
// secret Firebase (voir `fcm.dart`) : la mailbox et le serveur de
// signalisation appellent `/notify` ici plutôt que de porter chacun leur
// propre copie de ce secret.
//
// Endpoints :
//   POST /register       — Enregistrer/mettre à jour un appareil (+ jeton FCM)
//   DELETE /register     — Se désinscrire
//   GET /search?q=       — Chercher un contact par pseudo
//   POST /notify         — Réveiller un appareil par notification push
//   POST /report         — Signaler un contact (voir _handleReport)
//   POST /presence       — Battement « je suis joignable » (app ouverte)
//   GET /presence?ids=   — Heure du dernier battement de ces identifiants
//   GET /admin/reports   — [clé admin] Lister les signalements reçus
//   POST /admin/warn     — [clé admin] Envoyer un avertissement à un compte
//   PUT /cles/<id>       — Publier son paquet de clés Signal (voir cles_signal.dart)
//   GET /cles/<id>       — Obtenir le paquet d'une personne (une pré-clé unique)
//   GET /cles/<id>/etat  — Nombre de pré-clés restantes
//   POST /liaison/<canal> — Déposer l'enveloppe de liaison de Droplet Web
//   GET /liaison/<canal>  — La relever (navigateur) : 200, ou 204 en attente
//   DELETE /appareils/<id>/<appareil>      — Déconnecter un appareil lié
//   GET /appareils/<id>/<appareil>/etat    — Cet appareil est-il encore lié ?
//   GET /health          — Health check
//
// ── LES DEUX ENDPOINTS /admin/* ────────────────────────────────────
//
// Protégés par un en-tête `X-Admin-Key` qui doit correspondre à la
// variable d'environnement `ADMIN_KEY` (réglée sur Railway, jamais
// commitée). Sans `ADMIN_KEY`, ils répondent 503 : la modération est
// simplement désactivée, le reste de l'annuaire fonctionne normalement.
//
// C'est le strict minimum pour faire de la modération sur un réseau
// décentralisé : VOIR quels identifiants techniques ont été signalés et
// combien de fois, et AVERTIR un compte par notification push. Le
// serveur ne peut rien de plus — il ne voit jamais un message, et ne
// peut pas empêcher deux téléphones de se parler en direct par
// Bluetooth ou QR code. « Avertir » et un futur « dé-lister » n'agissent
// que sur l'annuaire (retrouver quelqu'un par pseudo) et sur le réveil
// par push.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;
import 'package:shelf_router/shelf_router.dart';
import 'package:args/args.dart';

import 'apercu_invitation.dart';
import 'cles_signal.dart';
import 'fcm.dart';
import 'liaisons.dart';
import 'persistance.dart';
import 'securite.dart';
import 'sauvegardes.dart';

// ── Modèle de données ──────────────────────────────────────────────

class DirectoryEntry {
  DirectoryEntry({
    required this.peerId,
    required this.pseudo,
    required this.onionAddress,
    required this.publicKey,
    this.fcmToken,
    this.lastSeen,
  });

  final String peerId;
  final String pseudo;
  final String onionAddress;
  final String publicKey;

  /// Jeton d'appareil Firebase Cloud Messaging, s'il en a fourni un —
  /// JAMAIS renvoyé par `/search` (voir [toJson]) : c'est un identifiant
  /// qui permet de réveiller CET appareil précis, il n'a rien à faire
  /// entre les mains de quelqu'un qui cherche juste un pseudo.
  String? fcmToken;
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
      fcmToken: json['fcmToken'] as String?,
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'] as String)
          : null,
    );
  }
}

/// Un signalement agrégé pour un `peerId` donné — jamais un signalement
/// individuel, jamais un contenu. Ce qu'un modérateur a besoin de savoir :
/// combien de fois ce pair a été signalé, pour quels motifs, depuis quand,
/// et combien d'avertissements lui ont déjà été envoyés.
class ReportRecord {
  ReportRecord({required this.peerId, DateTime? debut})
      : firstSeen = debut ?? DateTime.now(),
        lastSeen = debut ?? DateTime.now();

  final String peerId;
  int count = 0;

  /// motif (`spam`, `harcelement`, `illegal`, `autre`, `non_precise`) → nombre.
  final Map<String, int> reasons = {};

  DateTime firstSeen;
  DateTime lastSeen;
  int warningsSent = 0;
  DateTime? lastWarningAt;

  Map<String, dynamic> toJson() => {
        'peerId': peerId,
        'count': count,
        'reasons': reasons,
        'firstSeen': firstSeen.toIso8601String(),
        'lastSeen': lastSeen.toIso8601String(),
        'warningsSent': warningsSent,
        'lastWarningAt': lastWarningAt?.toIso8601String(),
      };

  factory ReportRecord.fromJson(Map<String, dynamic> j) {
    final r = ReportRecord(
      peerId: j['peerId'] as String,
      debut: DateTime.tryParse(j['firstSeen'] as String? ?? ''),
    );
    r.count = (j['count'] as num?)?.toInt() ?? 0;
    (j['reasons'] as Map<String, dynamic>?)?.forEach((k, v) {
      r.reasons[k] = (v as num).toInt();
    });
    r.lastSeen = DateTime.tryParse(j['lastSeen'] as String? ?? '') ?? r.lastSeen;
    r.warningsSent = (j['warningsSent'] as num?)?.toInt() ?? 0;
    final lw = j['lastWarningAt'] as String?;
    r.lastWarningAt = lw != null ? DateTime.tryParse(lw) : null;
    return r;
  }
}

// ── Base de données en mémoire ─────────────────────────────────────

class DirectoryDb {
  /// Entries par peerId.
  final Map<String, DirectoryEntry> _entries = {};

  /// TTL d'une entrée : 7 jours.
  static const _ttl = Duration(days: 7);

  void register(DirectoryEntry entry) {
    entry.lastSeen = DateTime.now();
    _entries[entry.peerId] = entry;
  }

  /// Le jeton FCM d'un appareil, s'il en a enregistré un — utilisé
  /// uniquement en interne par `/notify`, jamais par `/search`.
  String? fcmTokenPour(String peerId) => _entries[peerId]?.fcmToken;

  /// Le pseudo d'un appareil, pour les journaux (« qui a-t-on réveillé ? »)
  /// plutôt qu'un identifiant technique illisible.
  String? pseudoPour(String peerId) => _entries[peerId]?.pseudo;

  bool unregister(String peerId) {
    return _entries.remove(peerId) != null;
  }

  List<DirectoryEntry> search(String query) {
    final lower = query.toLowerCase();
    return _entries.values
        .where((e) => e.pseudo.toLowerCase().contains(lower))
        .toList();
  }

  /// Nettoie les entrées expirées.
  // ── Présence ────────────────────────────────────────────────────
  //
  // Le seul fait retenu ici : « cet identifiant était en ligne à telle
  // heure ». Pas un message, pas un destinataire, pas une adresse. L'app
  // ne bat QU'AU PREMIER PLAN : « en ligne » veut dire « son app est
  // ouverte », comme sur WhatsApp, et jamais « son téléphone existe
  // quelque part ».

  /// Heure du dernier battement, par peerId.
  final Map<String, DateTime> _presences = {};

  /// Une présence sans nouvelle depuis un jour ne dit plus rien : on
  /// l'oublie plutôt que de la garder pour rien.
  static const _ttlPresence = Duration(days: 1);

  /// Ce que le client peut demander en une fois.
  static const maxPresencesDemandees = 40;

  void battement(String peerId) {
    final maintenant = DateTime.now();
    _presences[peerId] = maintenant;
    // Un appareil qui bat est un appareil vivant : son entrée d'annuaire
    // ne doit pas expirer pendant ce temps-là.
    _entries[peerId]?.lastSeen = maintenant;
  }

  /// Les heures connues pour ces identifiants, en millisecondes.
  Map<String, int> presences(Iterable<String> peerIds) {
    final limite = DateTime.now().subtract(_ttlPresence);
    final sortie = <String, int>{};
    for (final id in peerIds) {
      final vu = _presences[id];
      if (vu == null || vu.isBefore(limite)) continue;
      sortie[id] = vu.millisecondsSinceEpoch;
    }
    return sortie;
  }

  int sweep() {
    final now = DateTime.now();
    final before = _entries.length;
    _entries.removeWhere((_, e) =>
        e.lastSeen != null && now.difference(e.lastSeen!) > _ttl);
    _presences.removeWhere((_, vu) => now.difference(vu) > _ttlPresence);
    return before - _entries.length;
  }

  int get count => _entries.length;

  // ── Signalements ────────────────────────────────────────────────
  //
  // ⚠️ AUCUN CONTENU DE CONVERSATION ICI — JAMAIS. Un signalement ne
  // porte que l'identifiant technique (peerId) de la personne signalée
  // et un motif choisi dans une liste fermée (voir `_motifsSignalement`
  // côté app) : ni le pseudo, ni le moindre message. C'est la seule
  // façon de garder un signal utile (repérer un pair signalé à
  // répétition) sans jamais faire transiter par ce serveur le contenu
  // chiffré de bout en bout qu'il n'a de toute façon jamais les moyens
  // de déchiffrer.
  //
  // Contrairement à `_entries` (les inscriptions, que les appareils
  // renvoient d'eux-mêmes à chaque démarrage), les signalements NE SE
  // RECONSTRUISENT PAS tout seuls : on les persiste donc sur le volume
  // Railway monté sur `/data` (voir [chargerSignalements] / [_sauver]).
  final Map<String, ReportRecord> _reports = {};

  /// Fichier où les signalements sont persistés. Renseigné par
  /// [chargerSignalements] au démarrage ; tant qu'il est `null`, les
  /// signalements restent en mémoire seule (mode dev/local).
  String? _reportsPath;

  /// Charge les signalements depuis le disque (appelé une fois au
  /// démarrage). Sans effet si le fichier n'existe pas encore.
  void chargerSignalements(String path) {
    _reportsPath = path;
    try {
      final f = File(path);
      if (!f.existsSync()) return;
      final data = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      final liste = (data['reports'] as List<dynamic>? ?? const []);
      for (final item in liste) {
        final r = ReportRecord.fromJson(item as Map<String, dynamic>);
        _reports[r.peerId] = r;
      }
      print('[Directory] ${_reports.length} signalements chargés depuis $path');
    } catch (e) {
      print('[Directory] Signalements illisibles ($path): $e');
    }
  }

  void _sauverSignalements() {
    final path = _reportsPath;
    if (path == null) return;
    try {
      final payload = jsonEncode({
        'savedAt': DateTime.now().toIso8601String(),
        'reports': _reports.values.map((r) => r.toJson()).toList(),
      });
      File(path).writeAsStringSync(payload, flush: true);
    } catch (e) {
      print('[Directory] Échec sauvegarde signalements: $e');
    }
  }

  void addReport(String peerId, String reason) {
    final r = _reports.putIfAbsent(peerId, () => ReportRecord(peerId: peerId));
    r.count++;
    r.reasons[reason] = (r.reasons[reason] ?? 0) + 1;
    r.lastSeen = DateTime.now();
    _sauverSignalements();
  }

  void recordWarning(String peerId) {
    final r = _reports[peerId];
    if (r == null) return;
    r.warningsSent++;
    r.lastWarningAt = DateTime.now();
    _sauverSignalements();
  }

  int reportCountFor(String peerId) => _reports[peerId]?.count ?? 0;

  /// Tous les signalements, du plus signalé au moins signalé.
  List<ReportRecord> allReports() {
    final liste = _reports.values.toList()
      ..sort((a, b) => b.count.compareTo(a.count));
    return liste;
  }
}

// ── Serveur ────────────────────────────────────────────────────────

final _db = DirectoryDb();

/// Postgres (null en local sans DATABASE_URL). Voir persistance.dart.
Persistance? _base;

/// Les signatures et la clé interne. Voir securite.dart.
late final Securite _securite;

/// Identifiant → clé publique attachée, et « a déjà signé ». Copie en
/// mémoire de la table `comptes` : une recherche par requête, sans base.
final Map<String, ({String cle, bool signe})> _comptes = {};

final _debitNotify = Debit(capacite: 20, parMinute: 30);
final _debitRecherche = Debit(capacite: 20, parMinute: 30);
final _debitInscription = Debit(capacite: 10, parMinute: 20);

/// Contrôle d'identité : null si la requête peut passer, sinon le refus.
/// Voir securite.dart pour la règle de transition (verrou après la
/// première signature).
Future<Response?> _controler(Request r, String peerId, List<int> corps) async {
  final compte = _comptes[peerId];
  final verdict = await _securite.verifier(r, peerId, corps, compte?.cle);
  switch (verdict) {
    case Verdict.signe:
      if (compte != null && !compte.signe) {
        _comptes[peerId] = (cle: compte.cle, signe: true);
        await _base?.marquerSigne(peerId);
      }
      return null;
    case Verdict.invalide:
      return json({'error': 'signature invalide'}, statut: 401);
    case Verdict.absent:
      if ((compte?.signe ?? false) || _securite.exigerSignature) {
        return json({'error': 'signature requise'}, statut: 401);
      }
      return null;
  }
}

/// Sauvegardes chiffrées des utilisateurs — voir `sauvegardes.dart`.
/// Initialisé dans [main], sur le volume quand il est monté.
late final StockSauvegardes _sauvegardes;

/// Les paquets de clés Signal, sur le volume (voir `cles_signal.dart`).
late StockClesSignal _clesSignal;

/// `null` tant que `FIREBASE_SERVICE_ACCOUNT_JSON` n'est pas configurée
/// (voir [main]) — l'annuaire continue de fonctionner sans, seul `/notify`
/// devient alors sans effet plutôt qu'en échec bruyant.
FcmSender? _fcm;

/// Le rendez-vous téléphone ↔ Droplet Web (voir `liaisons.dart`).
late final Liaisons _liaisons;

final _router = Router()
  ..post('/register', _handleRegister)
  ..delete('/register', _handleUnregister)
  ..get('/search', _handleSearch)
  ..post('/notify', _handleNotify)
  ..post('/report', _handleReport)
  ..post('/presence', _handlePresenceBattement)
  ..get('/presence', _handlePresenceLecture)
  ..get('/admin/reports', _handleAdminReports)
  ..post('/admin/warn', _handleAdminWarn)
  ..put('/sauvegarde/<id>', (Request r, String id) => _sauvegardes.deposer(r, id))
  ..get('/sauvegarde/<id>', (Request r, String id) => _sauvegardes.lire(r, id))
  ..delete('/sauvegarde/<id>', (Request r, String id) => _sauvegardes.supprimer(r, id))
  ..put('/cles/<id>', (Request r, String id) => _clesSignal.publier(r, id))
  ..get('/cles/<id>/etat', (Request r, String id) => _clesSignal.etat(r, id))
  ..get('/cles/<id>', (Request r, String id) => _clesSignal.recuperer(r, id))
  ..post('/liaison/<canal>', (Request r, String canal) => _liaisons.deposer(r, canal))
  ..get('/liaison/<canal>', (Request r, String canal) => _liaisons.relever(r, canal))
  ..delete('/appareils/<id>/<appareil>', (Request r, String id, String appareil) => _liaisons.revoquer(r, id, appareil))
  ..get('/appareils/<id>/<appareil>/etat', (Request r, String id, String appareil) => _liaisons.etat(r, id, appareil))
  ..get('/i', _handleInvitation)
  ..get('/i/apercu.jpg', _handleApercuInvitation)
  ..post('/interne/verifier', _handleVerifierInterne)
  ..get('/health', _handleHealth);

/// Version courte et non-sensible d'un identifiant technique, pour les
/// journaux — jamais l'identifiant complet, qui n'a rien à faire en clair
/// dans des logs conservés par un tiers (Railway).
String _court(String id) =>
    id.length <= 8 ? id : '${id.substring(0, 8)}…';

/// `true` si la requête porte un en-tête `X-Admin-Key` égal à la variable
/// d'environnement `ADMIN_KEY`. Comparaison à temps constant : une
/// comparaison de chaînes ordinaire s'arrête au premier caractère
/// différent, ce qui laisse deviner la clé octet par octet en mesurant le
/// temps de réponse.
bool _adminOk(Request request) {
  final attendu = Platform.environment['ADMIN_KEY'];
  if (attendu == null || attendu.isEmpty) return false;
  final fourni = request.headers['x-admin-key'] ?? '';
  if (fourni.length != attendu.length) return false;
  var diff = 0;
  for (var i = 0; i < attendu.length; i++) {
    diff |= fourni.codeUnitAt(i) ^ attendu.codeUnitAt(i);
  }
  return diff == 0;
}

/// Réponse commune quand la modération n'est pas utilisable : soit
/// `ADMIN_KEY` n'est pas configurée (503), soit la clé fournie est
/// mauvaise (401). `null` si tout va bien.
Response? _refusAdmin(Request request) {
  final attendu = Platform.environment['ADMIN_KEY'];
  if (attendu == null || attendu.isEmpty) {
    return Response(503,
        body: jsonEncode({'error': 'Modération désactivée : ADMIN_KEY non configurée'}),
        headers: {'content-type': 'application/json'});
  }
  if (!_adminOk(request)) {
    return Response(401,
        body: jsonEncode({'error': 'Clé admin absente ou invalide (en-tête X-Admin-Key)'}),
        headers: {'content-type': 'application/json'});
  }
  return null;
}

/// [clé admin] Liste tous les signalements reçus, du pair le plus signalé
/// au moins signalé. Pour chaque pair : le nombre de signalements, la
/// répartition par motif, les dates, le nombre d'avertissements déjà
/// envoyés, et — si le pair est encore inscrit à l'annuaire — son pseudo
/// actuel et s'il est joignable par push (donc « avertissable »).
Future<Response> _handleAdminReports(Request request) async {
  final refus = _refusAdmin(request);
  if (refus != null) return refus;

  final reports = _db.allReports().map((r) {
    final j = r.toJson();
    j['pseudoActuel'] = _db.pseudoPour(r.peerId); // null si désinscrit
    j['avertissable'] = _db.fcmTokenPour(r.peerId) != null;
    return j;
  }).toList();

  return Response.ok(
    jsonEncode({
      'generatedAt': DateTime.now().toIso8601String(),
      'total': reports.length,
      'reports': reports,
    }),
    headers: {'content-type': 'application/json'},
  );
}

/// [clé admin] Envoie un avertissement à un compte signalé, sous forme de
/// notification push. Corps attendu : `{ "peerId": "...", "message": "..." }`.
///
/// ⚠️ CE QUE ÇA PEUT ET NE PEUT PAS FAIRE. Ça envoie une notification à
/// l'appareil s'il a enregistré un jeton push et qu'il la reçoit. Ça
/// n'empêche personne de continuer à utiliser l'app, ça ne coupe aucune
/// conversation en cours, ça n'agit pas sur les échanges Bluetooth
/// directs. C'est un message, pas une sanction.
Future<Response> _handleAdminWarn(Request request) async {
  final refus = _refusAdmin(request);
  if (refus != null) return refus;

  try {
    final json = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
    final peerId = json['peerId'] as String?;
    final message = (json['message'] as String?)?.trim();

    if (peerId == null || peerId.isEmpty || message == null || message.isEmpty) {
      return Response(400,
          body: jsonEncode({'error': 'Champs requis : peerId, message'}),
          headers: {'content-type': 'application/json'});
    }

    final fcm = _fcm;
    if (fcm == null) {
      return Response(503,
          body: jsonEncode({'error': 'Firebase non configuré ici — envoi impossible'}),
          headers: {'content-type': 'application/json'});
    }

    final jeton = _db.fcmTokenPour(peerId);
    if (jeton == null) {
      return Response.ok(
          jsonEncode({
            'ok': true,
            'sent': false,
            'raison': 'aucun jeton push pour ce pair (désinscrit, ou push jamais activé)',
          }),
          headers: {'content-type': 'application/json'});
    }

    final envoye = await fcm.envoyer(
      jetonAppareil: jeton,
      titre: 'Avertissement de modération',
      corps: message,
      data: {'type': 'warning'},
      // Le seul cas où le texte vient vraiment du serveur : Android
      // l'affiche directement, sans passer par le code de l'app.
      afficherDirectement: true,
    );
    if (envoye) _db.recordWarning(peerId);
    print('[Directory] Avertissement ${envoye ? "envoyé" : "échoué"} → ${_court(peerId)}');

    return Response.ok(jsonEncode({'ok': true, 'sent': envoye}),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response(500, body: jsonEncode({'error': e.toString()}));
  }
}

Future<Response> _handleRegister(Request request) async {
  try {
    final octets = await request.read().fold<List<int>>([], (a, b) => a..addAll(b));
    if (octets.length > 16 * 1024) return Response(413);
    final json = jsonDecode(utf8.decode(octets)) as Map<String, dynamic>;

    final peerId = json['peerId'] as String?;
    final pseudo = json['pseudo'] as String?;
    final onion = json['onion'] as String?;
    final publicKey = json['publicKey'] as String?;
    // Optionnel : un appareil qui n'a pas encore activé les notifications
    // push, ou qui tourne sur une plateforme sans Firebase, s'enregistre
    // quand même — il restera joignable par sondage de la mailbox, juste
    // pas réveillable par push.
    final fcmToken = json['fcmToken'] as String?;

    if (peerId == null || pseudo == null || onion == null || publicKey == null) {
      return Response(400,
          body: jsonEncode({'error': 'Champs manquants: peerId, pseudo, onion, publicKey'}));
    }

    if (!onion.endsWith('.onion')) {
      return Response(400, body: jsonEncode({'error': 'Adresse onion invalide'}));
    }
    if (peerId.length > 128 || pseudo.length > 64 || publicKey.length > 128) {
      return Response(400, body: jsonEncode({'error': 'Champs trop longs'}));
    }
    if (!_debitInscription.autoriser(adresseClient(request))) {
      return Response(429, body: jsonEncode({'error': 'trop de requêtes'}));
    }

    // ── L'identifiant appartient à la clé qui l'a enregistré en premier ──
    final compte = _comptes[peerId];
    final refus = await _controler(request, peerId, octets);
    if (refus != null) return refus;
    if (compte != null && compte.cle != publicKey) {
      // Changer de clé n'est permis qu'avec la signature de l'ancienne :
      // sans cela, n'importe qui pourrait détourner un compte.
      final signe = request.headers.containsKey('x-droplet-sig');
      if (!signe) {
        print('[Directory] ⛔ Tentative de remplacer la clé de ${peerId.substring(0, 8)}… refusée');
        return Response(409, body: jsonEncode({'error': 'Cet identifiant appartient à une autre clé'}));
      }
    }
    if (compte == null || compte.cle != publicKey) {
      _comptes[peerId] = (cle: publicKey, signe: compte?.signe ?? false);
      await _base?.lierCle(peerId, publicKey);
    }
    await _base?.inscrire(peerId: peerId, pseudo: pseudo, onion: onion, cle: publicKey, fcm: fcmToken);

    _db.register(DirectoryEntry(
      peerId: peerId,
      pseudo: pseudo,
      onionAddress: onion,
      publicKey: publicKey,
      fcmToken: fcmToken,
    ));

    print('[Directory] Enregistré: $pseudo (${peerId.substring(0, 8)}…) '
        '${fcmToken != null ? "avec" : "sans"} jeton push — total: ${_db.count}');

    return Response.ok(jsonEncode({'ok': true, 'count': _db.count}),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response(500, body: jsonEncode({'error': e.toString()}));
  }
}

/// Réveille un appareil précis par notification push — appelé par la
/// mailbox (nouveau message) et le serveur de signalisation (appel
/// entrant), jamais directement par l'app.
///
/// Silencieux plutôt qu'en échec quand aucun jeton n'est enregistré pour
/// ce `peerId`, ou que Firebase n'est pas configuré ici : un push est un
/// coup de pouce, jamais le seul chemin — la mailbox reste sondée toutes
/// les 30 secondes de toute façon.
/// Le serveur d'appels (autre projet Railway) fait vérifier ici qu'une
/// demande d'entrer dans la boîte d'appel de X vient bien de X.
Future<Response> _handleVerifierInterne(Request request) async {
  if (!_securite.estInterne(request)) return Response(403);
  final j = jsonDecode(await request.readAsString()) as Map<String, dynamic>;
  final peerId = j['peerId'] as String? ?? '';
  final simulee = Request(
    (j['methode'] as String? ?? 'GET').toUpperCase(),
    Uri.parse('https://interne${j['chemin'] ?? '/'}'),
    headers: {
      if (j['ts'] != null) 'x-droplet-id': peerId,
      if (j['ts'] != null) 'x-droplet-ts': '${j['ts']}',
      if (j['sig'] != null) 'x-droplet-sig': '${j['sig']}',
    },
  );
  final refus = await _controler(simulee, peerId, const []);
  return json({'ok': refus == null, 'signeRequis': _comptes[peerId]?.signe ?? false});
}

Future<Response> _handleNotify(Request request) async {
  // Seuls nos serveurs (boîte aux lettres, appels) réveillent un téléphone.
  if (!_securite.estInterne(request)) {
    return Response(403, body: jsonEncode({'error': 'réservé aux serveurs Droplet'}));
  }
  try {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;

    final peerId = json['peerId'] as String?;
    final titre = json['title'] as String?;
    final corps = json['body'] as String?;
    final data = (json['data'] as Map<String, dynamic>?)
            ?.map((k, v) => MapEntry(k, v.toString())) ??
        const <String, String>{};

    if (peerId == null || titre == null || corps == null) {
      return Response(400,
          body: jsonEncode({'error': 'Champs manquants: peerId, title, body'}));
    }

    if (!_debitNotify.autoriser(peerId)) {
      return Response.ok(jsonEncode({'ok': true, 'sent': false, 'limite': true}),
          headers: {'content-type': 'application/json'});
    }
    final fcm = _fcm;
    final jetonAppareil = _db.fcmTokenPour(peerId);
    if (fcm == null || jetonAppareil == null) {
      return Response.ok(jsonEncode({'ok': true, 'sent': false}),
          headers: {'content-type': 'application/json'});
    }

    final envoye = await fcm.envoyer(
      jetonAppareil: jetonAppareil,
      titre: titre,
      corps: corps,
      data: data,
    );

    if (envoye) {
      print('[Directory] Push envoyé à ${_db.pseudoPour(peerId) ?? peerId}');
    }

    return Response.ok(jsonEncode({'ok': true, 'sent': envoye}),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response(500, body: jsonEncode({'error': e.toString()}));
  }
}

/// Reçoit un signalement de contact.
///
/// ⚠️ `peerId` DÉSIGNE LA PERSONNE SIGNALÉE, PAS QUI SIGNALE. On ne
/// demande d'ailleurs jamais l'identité de qui signale — l'action est
/// anonyme, comme l'app le promet à l'écran.
///
/// `reason` est un code court parmi une liste fermée choisie côté app
/// (`spam`, `harcelement`, `illegal`, `autre`) — jamais du texte libre,
/// pour ne jamais transformer ce champ en fuite de contenu déguisée.
/// Le battement : l'app ouverte le répète toutes les deux minutes.
///
/// Corps attendu : `{"peerId": "..."}`. Rien d'autre ne sert, et rien
/// d'autre n'est lu.
Future<Response> _handlePresenceBattement(Request request) async {
  try {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final peerId = json['peerId'] as String?;

    if (peerId == null || peerId.isEmpty || peerId.length > 128) {
      return Response(400,
          body: jsonEncode({'error': 'peerId manquant'}),
          headers: {'content-type': 'application/json'});
    }

    final refus = await _controler(request, peerId, utf8.encode(body));
    if (refus != null) return refus;
    _db.battement(peerId);
    return Response.ok(jsonEncode({'ok': true}),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response(500, body: jsonEncode({'error': e.toString()}));
  }
}

/// La lecture : « ces gens-là, vus quand ? »
///
/// `GET /presence?ids=a,b,c` → `{"a": 1735000000000, "b": …}`. Les
/// identifiants inconnus ou trop vieux sont simplement absents de la
/// réponse : le serveur ne dit jamais « celui-là, je ne le connais pas »,
/// il ne répond que sur ce qu'il sait.
Future<Response> _handlePresenceLecture(Request request) async {
  try {
    final brut = request.url.queryParameters['ids'] ?? '';
    final ids = brut
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .take(DirectoryDb.maxPresencesDemandees)
        .toList();

    return Response.ok(jsonEncode(_db.presences(ids)),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response(500, body: jsonEncode({'error': e.toString()}));
  }
}

Future<Response> _handleReport(Request request) async {
  try {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final peerId = json['peerId'] as String?;
    final reason = json['reason'] as String? ?? 'non_precise';

    if (peerId == null || peerId.isEmpty) {
      return Response(400, body: jsonEncode({'error': 'peerId manquant'}));
    }

    _db.addReport(peerId, reason);
    print('[Directory] Signalement reçu — ${_court(peerId)} '
        'motif: $reason, total pour ce pair: ${_db.reportCountFor(peerId)}');

    return Response.ok(jsonEncode({'ok': true}),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response(500, body: jsonEncode({'error': e.toString()}));
  }
}

Future<Response> _handleUnregister(Request request) async {
  try {
    final body = await request.readAsString();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final peerId = json['peerId'] as String?;

    if (peerId == null) {
      return Response(400, body: jsonEncode({'error': 'peerId manquant'}));
    }

    final refus = await _controler(request, peerId, utf8.encode(body));
    if (refus != null) return refus;
    final removed = _db.unregister(peerId);
    await _base?.desinscrire(peerId);
    return Response.ok(jsonEncode({'ok': true, 'removed': removed}),
        headers: {'content-type': 'application/json'});
  } catch (e) {
    return Response(500, body: jsonEncode({'error': e.toString()}));
  }
}

Future<Response> _handleSearch(Request request) async {
  final query = request.url.queryParameters['q'];
  if (query == null || query.isEmpty) {
    return Response(400, body: jsonEncode({'error': 'Paramètre q manquant'}));
  }

  if (query.trim().length < 2) {
    return Response.ok(jsonEncode({'results': []}), headers: {'content-type': 'application/json'});
  }
  if (!_debitRecherche.autoriser(adresseClient(request))) {
    return Response(429, body: jsonEncode({'error': 'trop de recherches'}));
  }
  final results = _db.search(query).take(20).toList();
  return Response.ok(
    jsonEncode({'results': results.map((e) => e.toJson()).toList()}),
    headers: {'content-type': 'application/json'},
  );
}

/// La page ouverte par un lien d'invitation Droplet (`…/i#données`).
///
/// ⚠️ LES DONNÉES SONT APRÈS LE `#` : le navigateur ne les envoie JAMAIS au
/// serveur. Cette page ne sait donc pas qui invite qui — c'est le script, sur
/// le téléphone de la personne invitée, qui lit le pseudo et construit le
/// lien `droplet://` vers l'application.
Response _handleInvitation(Request request) {
  return Response.ok(
    _pageInvitation.replaceAll('{{HOTE}}', _origine(request)),
    headers: {
      'content-type': 'text/html; charset=utf-8',
      'cache-control': 'public, max-age=3600',
      'referrer-policy': 'no-referrer',
      'x-content-type-options': 'nosniff',
      'content-security-policy':
          "default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; img-src data:",
    },
  );
}

/// L'adresse publique de l'annuaire, pour l'image d'aperçu (Open Graph)
/// que WhatsApp, Telegram ou les SMS affichent sous un lien partagé.
/// Derrière Railway, la requête arrive en HTTP : le schéma est forcé.
String _origine(Request request) {
  final hote = request.headers['x-forwarded-host'] ?? request.headers['host'] ?? '';
  if (!RegExp(r'^[A-Za-z0-9.\-]+(:\d+)?$').hasMatch(hote)) {
    return 'https://droplet-directory-production.up.railway.app';
  }
  return 'https://$hote';
}

/// L'image d'aperçu du lien d'invitation (1200×630).
Response _handleApercuInvitation(Request request) {
  return Response.ok(
    _apercuInvitation,
    headers: {
      'content-type': 'image/jpeg',
      'cache-control': 'public, max-age=86400',
      'x-content-type-options': 'nosniff',
    },
  );
}

final _apercuInvitation = base64Decode(kApercuInvitationBase64);

const _pageInvitation = r"""<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="robots" content="noindex">
<meta name="theme-color" content="#060D17">
<title>Invitation Droplet</title>
<meta name="description" content="Vous êtes invité à discuter en privé sur Droplet : messagerie chiffrée de bout en bout, même sans réseau.">
<meta property="og:type" content="website">
<meta property="og:site_name" content="Droplet">
<meta property="og:title" content="Vous êtes invité à discuter sur Droplet">
<meta property="og:description" content="Messagerie chiffrée de bout en bout, même sans réseau. Touchez pour ouvrir l'invitation.">
<meta property="og:image" content="{{HOTE}}/i/apercu.jpg">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 64 64'%3E%3Crect width='64' height='64' rx='16' fill='%230066E0'/%3E%3Cpath d='M32 13c6 7.4 10.6 13.2 10.6 19.1a10.6 10.6 0 0 1-21.2 0C21.4 26.2 26 20.4 32 13z' fill='white'/%3E%3C/svg%3E">
<style>
  :root {
    color-scheme: light dark;
    --goutte: #0066E0;
    --goutte-vive: #3B9BFF;
    --goutte-douce: rgba(0, 102, 224, .10);
    --fond: #F3F6FA;
    --surface: rgba(255, 255, 255, .78);
    --surface-pleine: #FFFFFF;
    --encre: #0A1420;
    --brume: #55677D;
    --trait: rgba(10, 20, 32, .09);
    --ombre: 0 1px 2px rgba(10, 20, 32, .04), 0 24px 60px -18px rgba(0, 60, 140, .28);
    --maille: 0, 102, 224;
    --vif: #17843D;
    --ease: cubic-bezier(.2, .8, .2, 1);
    --ressort: cubic-bezier(.34, 1.56, .64, 1);
  }
  @media (prefers-color-scheme: dark) {
    :root {
      --fond: #060D17;
      --surface: rgba(14, 24, 38, .72);
      --surface-pleine: #0E1826;
      --encre: #EEF3F9;
      --brume: #8C9FB6;
      --trait: rgba(232, 239, 247, .10);
      --ombre: 0 1px 0 rgba(255, 255, 255, .04) inset, 0 30px 80px -20px rgba(0, 0, 0, .7);
      --maille: 59, 155, 255;
      --goutte-douce: rgba(59, 155, 255, .12);
      --vif: #34D964;
    }
  }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html, body { margin: 0; }
  body {
    min-height: 100vh; min-height: 100dvh;
    background: var(--fond); color: var(--encre);
    font: 16px/1.5 "Inter", "SF Pro Text", system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    -webkit-font-smoothing: antialiased;
    overflow-x: hidden;
  }
  [hidden] { display: none !important; }

  /* ── Fond vivant : aurore + maillage (le réseau de téléphones) ── */
  .aurore { position: fixed; inset: -20%; z-index: 0; pointer-events: none; filter: blur(70px); opacity: .9; }
  .aurore i { position: absolute; border-radius: 50%; }
  .aurore i:nth-child(1) { width: 55vmax; height: 55vmax; left: 45%; top: -10%;
    background: radial-gradient(circle, rgba(0, 102, 224, .55), transparent 65%); animation: flotte 18s var(--ease) infinite alternate; }
  .aurore i:nth-child(2) { width: 45vmax; height: 45vmax; left: -5%; top: 45%;
    background: radial-gradient(circle, rgba(59, 155, 255, .35), transparent 65%); animation: flotte 22s var(--ease) infinite alternate-reverse; }
  @media (prefers-color-scheme: light) { .aurore { opacity: .45; } }
  @keyframes flotte { to { transform: translate3d(-8vmax, 6vmax, 0) scale(1.15); } }
  canvas#maille { position: fixed; inset: 0; width: 100%; height: 100%; z-index: 0; pointer-events: none; }

  /* ── Mise en page ── */
  .page {
    position: relative; z-index: 1;
    min-height: 100vh; min-height: 100dvh;
    display: flex; flex-direction: column; align-items: center;
    padding: max(16px, env(safe-area-inset-top)) 16px max(20px, env(safe-area-inset-bottom));
  }
  header.marque {
    width: 100%; max-width: 440px; display: flex; align-items: center; gap: 10px;
    padding: 8px 4px 20px; font-weight: 700; letter-spacing: -.01em; font-size: 17px;
    animation: entre .7s var(--ease) both;
  }
  header.marque svg { width: 30px; height: 30px; }
  header.marque .copier {
    margin-left: auto; display: inline-flex; align-items: center; gap: 6px;
    border: 1px solid var(--trait); background: var(--surface); color: var(--encre);
    backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px);
    border-radius: 999px; padding: 7px 12px; font: 600 13px/1 inherit; cursor: pointer;
    transition: transform .2s var(--ease), background .2s;
  }
  header.marque .copier:active { transform: scale(.94); }
  header.marque .copier svg { width: 15px; height: 15px; }
  .copier .coche { display: none; color: var(--vif); }
  .copier.fait .coche { display: block; animation: pop .4s var(--ressort); }
  .copier.fait .feuilles { display: none; }

  main.carte {
    width: 100%; max-width: 440px;
    background: var(--surface); border: 1px solid var(--trait); border-radius: 32px;
    backdrop-filter: blur(24px) saturate(1.4); -webkit-backdrop-filter: blur(24px) saturate(1.4);
    box-shadow: var(--ombre);
    padding: 36px 20px 22px; text-align: center;
    transform-style: preserve-3d; will-change: transform;
    transition: transform .5s var(--ease);
    animation: entre .9s .08s var(--ease) backwards;
  }
  @keyframes entre { from { opacity: 0; transform: translateY(24px) scale(.98); } }
  .revele { animation: entre .8s var(--ease) both; animation-delay: calc(var(--i, 0) * 90ms + 250ms); }

  /* ── Héros : logo qui se dessine, ou l'avatar de la personne ── */
  .heros { position: relative; width: 132px; height: 132px; margin: 0 auto 22px; }
  .heros .onde { position: absolute; inset: 22px; border-radius: 50%; border: 2px solid var(--goutte-vive); opacity: 0;
    animation: onde 3.2s 1.4s var(--ease) infinite; }
  .heros .onde:nth-child(2) { animation-delay: 2.5s; }
  @keyframes onde { 0% { transform: scale(.9); opacity: .4; } 100% { transform: scale(1.7); opacity: 0; } }

  .logo-anime { position: absolute; inset: 0; width: 100%; height: 100%; overflow: visible; }
  .logo-anime .bulle { fill: none; stroke: var(--goutte); stroke-width: 4.2; stroke-linejoin: round; stroke-linecap: round;
    stroke-dasharray: 1; stroke-dashoffset: 1; animation: trace 1.1s .2s var(--ease) forwards; }
  @media (prefers-color-scheme: dark) { .logo-anime .bulle { stroke: var(--goutte-vive); } }
  .logo-anime .goutte { transform-box: fill-box; transform-origin: 50% 100%; opacity: 0;
    animation: tombe .9s 1s var(--ressort) forwards; }
  @keyframes trace { to { stroke-dashoffset: 0; } }
  @keyframes tombe {
    0% { opacity: 0; transform: translateY(-26px) scale(.6, 1.2); }
    55% { opacity: 1; transform: translateY(0) scale(1.12, .86); }
    100% { opacity: 1; transform: none; }
  }

  .avatar { position: absolute; inset: 10px; border-radius: 50%; display: grid; place-items: center;
    animation: pop .8s .25s var(--ressort) both; }
  .avatar::before { content: ""; position: absolute; inset: -5px; border-radius: 50%;
    background: conic-gradient(from 0deg, var(--goutte-vive), transparent 30%, var(--goutte) 60%, transparent 80%, var(--goutte-vive));
    animation: tourne 4s linear infinite;
    -webkit-mask: radial-gradient(farthest-side, transparent calc(100% - 3px), #000 calc(100% - 2px));
            mask: radial-gradient(farthest-side, transparent calc(100% - 3px), #000 calc(100% - 2px)); }
  .avatar .rond { width: 100%; height: 100%; border-radius: 50%; display: grid; place-items: center;
    background: linear-gradient(145deg, #3B9BFF, #0066E0 55%, #004FB0);
    color: #fff; font-size: 46px; font-weight: 700; letter-spacing: -.02em;
    box-shadow: inset 0 2px 0 rgba(255, 255, 255, .25), 0 16px 40px -10px rgba(0, 102, 224, .6); }
  .avatar .badge { position: absolute; right: -2px; bottom: -2px; width: 38px; height: 38px; border-radius: 50%;
    background: var(--surface-pleine); display: grid; place-items: center; box-shadow: 0 4px 14px rgba(0, 0, 0, .18);
    animation: pop .6s 1s var(--ressort) both; }
  .avatar .badge svg { width: 26px; height: 26px; }
  @keyframes tourne { to { transform: rotate(1turn); } }
  @keyframes pop { from { opacity: 0; transform: scale(.4); } }

  h1 { font-size: clamp(25px, 7vw, 30px); line-height: 1.15; letter-spacing: -.025em; margin: 0 0 10px; font-weight: 750; }
  h1 .mot { display: inline-block; animation: mot .7s var(--ease) both; animation-delay: calc(var(--m) * 70ms + 450ms); }
  h1 .nom { background: linear-gradient(100deg, var(--goutte), var(--goutte-vive)); -webkit-background-clip: text; background-clip: text; color: transparent; }
  @keyframes mot { from { opacity: 0; transform: translateY(14px) rotate(2deg); filter: blur(6px); } }
  p.sous { color: var(--brume); margin: 0 auto 22px; max-width: 32ch; }

  /* ── Aperçu de conversation : trois points, puis la bulle ── */
  .fil { display: flex; flex-direction: column; align-items: flex-start; gap: 6px; margin: 0 0 22px; min-height: 64px; text-align: left; }
  .frappe, .message { background: var(--goutte-douce); border-radius: 20px 20px 20px 6px; padding: 12px 14px; }
  .frappe { display: inline-flex; gap: 4px; }
  .frappe i { width: 7px; height: 7px; border-radius: 50%; background: var(--goutte); opacity: .35; animation: point 1s infinite; }
  .frappe i:nth-child(2) { animation-delay: .15s; } .frappe i:nth-child(3) { animation-delay: .3s; }
  @keyframes point { 30% { opacity: 1; transform: translateY(-3px); } }
  .message { font-size: 15px; transform-origin: 0 100%; animation: bulle .5s var(--ressort) both; }
  .message small { display: flex; align-items: center; gap: 5px; color: var(--brume); font-size: 12px; margin-top: 4px; }
  .message small svg { width: 12px; height: 12px; }
  @keyframes bulle { from { opacity: 0; transform: scale(.6) translateY(8px); } }

  /* ── Boutons ── */
  .bouton {
    position: relative; overflow: hidden; isolation: isolate;
    display: flex; align-items: center; justify-content: center; gap: 10px;
    width: 100%; min-height: 56px; padding: 0 20px; border-radius: 18px; border: 0;
    font: 650 16.5px/1 inherit; letter-spacing: -.01em; text-decoration: none; cursor: pointer;
    transition: transform .25s var(--ressort), box-shadow .3s var(--ease), background .3s;
    user-select: none; -webkit-user-select: none;
  }
  .bouton:active { transform: scale(.965); }
  .bouton:focus-visible { outline: 3px solid var(--goutte-vive); outline-offset: 3px; }
  .bouton svg { width: 20px; height: 20px; flex: none; }
  .principal { color: #fff; background: linear-gradient(135deg, #1A7DFF, #0066E0 50%, #0052C2);
    box-shadow: 0 1px 0 rgba(255, 255, 255, .25) inset, 0 14px 30px -10px rgba(0, 102, 224, .75); }
  .principal:hover { box-shadow: 0 1px 0 rgba(255, 255, 255, .25) inset, 0 18px 40px -10px rgba(0, 102, 224, .9); }
  .principal::after { content: ""; position: absolute; inset: 0; z-index: -1;
    background: linear-gradient(110deg, transparent 30%, rgba(255, 255, 255, .35) 50%, transparent 70%);
    transform: translateX(-120%); animation: reflet 3.6s 2s var(--ease) infinite; }
  @keyframes reflet { 0%, 60% { transform: translateX(-120%); } 100% { transform: translateX(120%); } }
  .principal .fleche { transition: transform .3s var(--ressort); }
  .principal:hover .fleche { transform: translateX(4px); }
  .secondaire { margin-top: 10px; color: var(--encre); background: transparent; border: 1.5px solid var(--trait); }
  .secondaire:hover { background: var(--goutte-douce); }
  .secondaire .taille { color: var(--brume); font-weight: 500; font-size: 13px; }
  .secondaire.appel { border-color: var(--goutte); animation: appel 1.2s var(--ease) 2; }
  @keyframes appel { 30% { transform: scale(1.03); box-shadow: 0 0 0 6px var(--goutte-douce); } }

  .ripple { position: absolute; border-radius: 50%; pointer-events: none; z-index: -1;
    background: rgba(255, 255, 255, .45); transform: scale(0); animation: ripple .6s var(--ease) forwards; }
  .secondaire .ripple { background: var(--goutte-douce); }
  @keyframes ripple { to { transform: scale(1); opacity: 0; } }

  .roue { width: 18px; height: 18px; border-radius: 50%; border: 2.5px solid rgba(255, 255, 255, .35); border-top-color: #fff;
    animation: tourne .7s linear infinite; }
  .principal .etat-ok { display: none; }
  .principal[data-etat="ouverture"] .etat-repos, .principal[data-etat="ouvert"] .etat-repos { display: none; }
  .principal[data-etat="ouverture"] .etat-roue { display: inline-flex; }
  .principal[data-etat="ouvert"] .etat-ok { display: inline-flex; animation: pop .4s var(--ressort); }
  .etat-roue { display: none; align-items: center; gap: 10px; }
  .etat-repos, .etat-ok { align-items: center; gap: 10px; display: inline-flex; }

  /* ── Aide « pas encore installé » ── */
  .aide { display: grid; grid-template-rows: 0fr; transition: grid-template-rows .5s var(--ease), opacity .4s; opacity: 0; }
  .aide.visible { grid-template-rows: 1fr; opacity: 1; }
  .aide > div { overflow: hidden; }
  .aide p { margin: 16px 0 0; font-weight: 600; }

  .etapes { list-style: none; margin: 22px 0 4px; padding: 0; display: grid; grid-template-columns: repeat(3, 1fr); gap: 6px; position: relative; }
  .etapes::before { content: ""; position: absolute; top: 17px; left: 17%; right: 17%; height: 2px; background: var(--trait); }
  .etapes::after { content: ""; position: absolute; top: 17px; left: 17%; height: 2px; width: 66%;
    background: linear-gradient(90deg, var(--goutte), var(--goutte-vive)); transform-origin: left; transform: scaleX(0);
    animation: remplit 1.6s 1.6s var(--ease) forwards; }
  @keyframes remplit { to { transform: scaleX(1); } }
  .etapes li { position: relative; z-index: 1; font-size: 12.5px; color: var(--brume); line-height: 1.3; }
  .etapes b { display: grid; place-items: center; width: 36px; height: 36px; margin: 0 auto 8px; border-radius: 50%;
    background: var(--surface-pleine); border: 2px solid var(--trait); color: var(--encre); font-size: 14px;
    animation: allume .4s var(--ressort) both; animation-delay: calc(var(--e) * 530ms + 1.5s); }
  @keyframes allume { to { border-color: var(--goutte); color: var(--goutte); box-shadow: 0 0 0 5px var(--goutte-douce); } }

  .atouts { display: flex; flex-wrap: wrap; justify-content: center; gap: 6px; margin: 22px 0 0; padding: 0; list-style: none; }
  .atouts li { display: inline-flex; align-items: center; gap: 5px; padding: 7px 10px; border-radius: 999px;
    background: var(--goutte-douce); color: var(--encre); font-size: 12px; font-weight: 600;
    transition: transform .25s var(--ressort); }
  .atouts li:hover { transform: translateY(-2px); }
  .atouts svg { width: 14px; height: 14px; color: var(--goutte); }
  @media (prefers-color-scheme: dark) { .atouts svg { color: var(--goutte-vive); } }

  .note { font-size: 13px; color: var(--brume); margin: 14px 0 0; }

  footer { width: 100%; max-width: 440px; margin-top: auto; padding: 22px 8px 0; display: flex; gap: 10px;
    align-items: flex-start; color: var(--brume); font-size: 12.5px; line-height: 1.45; }
  footer svg { width: 18px; height: 18px; flex: none; margin-top: 1px; color: var(--vif); }

  .toast { position: fixed; left: 50%; bottom: max(24px, env(safe-area-inset-bottom)); z-index: 5;
    transform: translate(-50%, 16px); opacity: 0; visibility: hidden; background: #0A1420; color: #fff; padding: 11px 18px; border-radius: 999px;
    font-size: 14px; font-weight: 600; box-shadow: 0 12px 30px rgba(0, 0, 0, .3);
    transition: transform .45s var(--ressort), opacity .25s, visibility .25s; }
  .toast.visible { transform: translate(-50%, 0); opacity: 1; visibility: visible; }

  @media (prefers-reduced-motion: reduce) {
    *, *::before, *::after { animation-duration: .01ms !important; animation-delay: 0s !important; animation-iteration-count: 1 !important; transition-duration: .01ms !important; }
    .heros .onde, .principal::after { display: none; }
  }
</style>
</head>
<body>
<div class="aurore" aria-hidden="true"><i></i><i></i></div>
<canvas id="maille" aria-hidden="true"></canvas>

<div class="page">
  <header class="marque">
    <svg viewBox="0 0 64 64" aria-hidden="true">
      <path d="M33 10a21 21 0 1 1-10.3 39.3L12 53l3.3-10.6A21 21 0 0 1 33 10z" fill="none" stroke="#1A7DFF" stroke-width="4.6" stroke-linejoin="round"/>
      <path d="M33 20c4.5 5.6 8 10 8 14.4a8 8 0 0 1-16 0C25 30 28.5 25.6 33 20z" fill="#1A7DFF"/>
    </svg>
    <span>Droplet</span>
    <button class="copier" id="copier" type="button" aria-label="Copier le lien">
      <svg class="feuilles" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="9" y="9" width="11" height="11" rx="2.5"/><path d="M5 15V6a2 2 0 0 1 2-2h9"/></svg>
      <svg class="coche" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>
      <span id="copier-texte">Copier</span>
    </button>
  </header>

  <main class="carte" id="carte">
    <div class="heros" aria-hidden="true">
      <span class="onde"></span><span class="onde"></span>
      <svg class="logo-anime" id="logo" viewBox="0 0 64 64">
        <path class="bulle" pathLength="1" d="M33 10a21 21 0 1 1-10.3 39.3L12 53l3.3-10.6A21 21 0 0 1 33 10z"/>
        <defs><linearGradient id="dg" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#3B9BFF"/><stop offset="1" stop-color="#0060D6"/></linearGradient></defs>
        <path class="goutte" fill="url(#dg)" d="M33 20c4.5 5.6 8 10 8 14.4a8 8 0 0 1-16 0C25 30 28.5 25.6 33 20z"/>
      </svg>
      <div class="avatar" id="avatar" hidden>
        <div class="rond" id="initiale"></div>
        <div class="badge">
          <svg viewBox="0 0 64 64"><path d="M33 10a21 21 0 1 1-10.3 39.3L12 53l3.3-10.6A21 21 0 0 1 33 10z" fill="none" stroke="#1A7DFF" stroke-width="5"/><path d="M33 20c4.5 5.6 8 10 8 14.4a8 8 0 0 1-16 0C25 30 28.5 25.6 33 20z" fill="#1A7DFF"/></svg>
        </div>
      </div>
    </div>

    <h1 id="titre" aria-live="polite">Rejoignez Droplet</h1>
    <p class="sous revele" style="--i:4" id="texte">La messagerie chiffrée qui marche avec Internet, et même sans réseau, de téléphone en téléphone.</p>

    <div class="fil" id="fil" hidden aria-hidden="true">
      <div class="frappe" id="frappe"><i></i><i></i><i></i></div>
    </div>

    <div class="revele" style="--i:6">
      <a id="ouvrir" class="bouton principal" href="#" hidden>
        <span class="etat-repos">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 11.5a8.4 8.4 0 0 1-12.3 7.5L3 21l2-5.3A8.5 8.5 0 1 1 21 11.5z"/></svg>
          <span id="ouvrir-texte">Ouvrir dans Droplet</span>
          <svg class="fleche" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12h14M13 6l6 6-6 6"/></svg>
        </span>
        <span class="etat-roue"><span class="roue"></span>Ouverture de Droplet…</span>
        <span class="etat-ok">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="M5 12.5l4.5 4.5L19 7.5"/></svg>
          Ouvert dans Droplet
        </span>
      </a>

      <div class="aide" id="aide">
        <div><p>Droplet n'est pas encore sur ce téléphone&nbsp;?</p></div>
      </div>

      <a id="telecharger" class="bouton secondaire" href="https://github.com/rito27959-arch/droplet/releases/latest/download/app-arm64-v8a-release.apk">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 4v11M7 10.5l5 5 5-5M5 20h14"/></svg>
        <span>Installer Droplet <span class="taille">· Android</span></span>
      </a>
      <p class="note" id="note-plateforme" hidden></p>
    </div>

    <ol class="etapes revele" style="--i:8" id="etapes" hidden>
      <li style="--e:0"><b>1</b>Installez Droplet</li>
      <li style="--e:1"><b>2</b>Rouvrez ce lien</li>
      <li style="--e:2"><b>3</b>Discutez</li>
    </ol>

    <ul class="atouts revele" style="--i:9">
      <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><rect x="5" y="11" width="14" height="10" rx="2.5"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>Chiffré de bout en bout</li>
      <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><circle cx="5" cy="12" r="2"/><circle cx="19" cy="6" r="2"/><circle cx="19" cy="18" r="2"/><path d="M7 11l10-4M7 13l10 4"/></svg>Même sans réseau</li>
      <li><svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"><path d="M15 10l5-3v10l-5-3z"/><rect x="3" y="6" width="12" height="12" rx="2.5"/></svg>Appels audio et vidéo</li>
    </ul>
  </main>

  <footer class="revele" style="--i:11">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 3l7 3v5c0 4.6-3 8.5-7 10-4-1.5-7-5.4-7-10V6z"/><path d="M9 12l2 2 4-4"/></svg>
    <span>Cette invitation est lue uniquement sur votre téléphone. Nos serveurs ne voient ni qui vous invite, ni sa clé de chiffrement.</span>
  </footer>
</div>

<div class="toast" id="toast" role="status"></div>

<script>
(function () {
  "use strict";
  var $ = function (id) { return document.getElementById(id); };
  var calme = window.matchMedia && matchMedia("(prefers-reduced-motion: reduce)").matches;
  var ua = navigator.userAgent || "";
  var android = /Android/i.test(ua);
  var ios = /iPhone|iPad|iPod/i.test(ua) || (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1);
  var mobile = android || ios || /Mobi/i.test(ua);

  function vibre(ms) { try { if (navigator.vibrate) navigator.vibrate(ms); } catch (e) {} }

  var minuteurToast;
  function toast(texte) {
    var t = $("toast");
    t.textContent = texte;
    t.classList.add("visible");
    clearTimeout(minuteurToast);
    minuteurToast = setTimeout(function () { t.classList.remove("visible"); }, 2200);
  }

  // Titre révélé mot par mot.
  function titre(morceaux) {
    var h = $("titre");
    h.textContent = "";
    var m = 0;
    morceaux.forEach(function (bout) {
      bout.texte.split(" ").forEach(function (mot) {
        if (!mot) return;
        var s = document.createElement("span");
        s.className = "mot" + (bout.nom ? " nom" : "");
        s.style.setProperty("--m", m++);
        s.textContent = mot;
        h.appendChild(s);
        h.appendChild(document.createTextNode(" "));
      });
    });
  }

  // ── Invitation : lue ICI, après le #, jamais envoyée ─────────────
  var donnees = (location.hash || "").slice(1);
  var pseudo = "";
  if (donnees) {
    try {
      var b64 = donnees.replace(/-/g, "+").replace(/_/g, "/");
      while (b64.length % 4) b64 += "=";
      var octets = Uint8Array.from(atob(b64), function (c) { return c.charCodeAt(0); });
      var json = JSON.parse(new TextDecoder().decode(octets));
      pseudo = String(json.pseudo || "").replace(/[\u0000-\u001f]/g, "").trim().slice(0, 40);
    } catch (e) { pseudo = ""; /* lien abîmé : la page reste générique */ }
  }

  var ouvrir = $("ouvrir");
  if (pseudo) {
    document.title = pseudo + " vous invite sur Droplet";
    titre([{ texte: pseudo, nom: true }, { texte: "vous invite à discuter" }]);
    $("texte").textContent = "Sur Droplet, vos messages et appels sont chiffrés de bout en bout — et passent même sans réseau.";
    $("logo").style.display = "none";
    $("initiale").textContent = Array.from(pseudo)[0].toUpperCase();
    $("avatar").hidden = false;
    $("ouvrir-texte").textContent = "Discuter avec " + (pseudo.length > 16 ? Array.from(pseudo).slice(0, 15).join("") + "…" : pseudo);
    ouvrir.href = "droplet://droplet/invite?d=" + encodeURIComponent(donnees);
    ouvrir.hidden = false;

    // Aperçu : quelqu'un écrit… puis la bulle.
    var fil = $("fil");
    fil.hidden = false;
    setTimeout(function () {
      $("frappe").remove();
      var bulle = document.createElement("div");
      bulle.className = "message";
      bulle.textContent = "Nouvelle conversation avec " + pseudo;
      var pied = document.createElement("small");
      pied.innerHTML = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.4" stroke-linecap="round"><rect x="5" y="11" width="14" height="10" rx="2.5"/><path d="M8 11V8a4 4 0 0 1 8 0v3"/></svg>';
      pied.appendChild(document.createTextNode("Chiffrée de bout en bout"));
      bulle.appendChild(pied);
      fil.appendChild(bulle);
    }, calme ? 0 : 1900);
  } else {
    titre([{ texte: "Rejoignez" }, { texte: "Droplet", nom: true }]);
    $("etapes").hidden = false;
  }

  // Selon l'appareil.
  var note = $("note-plateforme");
  if (ios) {
    $("telecharger").hidden = true;
    ouvrir.hidden = true;
    note.textContent = "Droplet est pour l'instant disponible sur Android. Ouvrez ce lien sur un téléphone Android.";
    note.hidden = false;
  } else if (!mobile) {
    note.textContent = "Ouvrez ce lien sur votre téléphone Android pour rejoindre la conversation.";
    note.hidden = false;
  }

  // ── Ondulation au point de contact ──────────────────────────────
  document.querySelectorAll(".bouton").forEach(function (b) {
    b.addEventListener("pointerdown", function (e) {
      var r = b.getBoundingClientRect();
      var d = Math.max(r.width, r.height) * 2.2;
      var o = document.createElement("span");
      o.className = "ripple";
      o.style.width = o.style.height = d + "px";
      o.style.left = (e.clientX - r.left - d / 2) + "px";
      o.style.top = (e.clientY - r.top - d / 2) + "px";
      b.appendChild(o);
      vibre(8);
      setTimeout(function () { o.remove(); }, 650);
    });
  });

  // ── Ouvrir l'app, et aider si elle n'est pas installée ─────────
  var partie = false;
  document.addEventListener("visibilitychange", function () {
    if (document.hidden) { partie = true; return; }
    if (ouvrir.dataset.etat === "ouverture" || partie) ouvrir.dataset.etat = partie ? "ouvert" : "";
  });
  ouvrir.addEventListener("click", function (e) {
    e.preventDefault();
    if (ouvrir.dataset.etat === "ouverture") return;
    partie = false;
    ouvrir.dataset.etat = "ouverture";
    location.href = ouvrir.href;
    setTimeout(function () {
      if (partie || document.hidden) return;
      ouvrir.dataset.etat = "";
      $("aide").classList.add("visible");
      $("etapes").hidden = false;
      var t = $("telecharger");
      t.classList.remove("appel"); void t.offsetWidth; t.classList.add("appel");
      vibre([12, 60, 12]);
      t.scrollIntoView({ behavior: calme ? "auto" : "smooth", block: "center" });
    }, 1700);
  });

  // ── Copier le lien ──────────────────────────────────────────────
  $("copier").addEventListener("click", function () {
    var bouton = this;
    function ok() {
      bouton.classList.add("fait");
      $("copier-texte").textContent = "Copié";
      vibre(10);
      toast("Lien copié");
      setTimeout(function () { bouton.classList.remove("fait"); $("copier-texte").textContent = "Copier"; }, 2000);
    }
    function ancienne() {
      var zone = document.createElement("textarea");
      zone.value = location.href; zone.setAttribute("readonly", "");
      zone.style.position = "fixed"; zone.style.opacity = "0";
      document.body.appendChild(zone); zone.select();
      var reussi = false;
      try { reussi = document.execCommand("copy"); } catch (e) {}
      zone.remove();
      reussi ? ok() : toast("Copie impossible");
    }
    if (navigator.clipboard && navigator.clipboard.writeText) {
      navigator.clipboard.writeText(location.href).then(ok, ancienne);
    } else {
      ancienne();
    }
  });

  if (calme) return;

  // ── Carte qui suit légèrement le pointeur (souris uniquement) ───
  var carte = $("carte");
  if (matchMedia("(hover: hover) and (pointer: fine)").matches) {
    window.addEventListener("pointermove", function (e) {
      var r = carte.getBoundingClientRect();
      var x = (e.clientX - (r.left + r.width / 2)) / window.innerWidth;
      var y = (e.clientY - (r.top + r.height / 2)) / window.innerHeight;
      carte.style.transform = "perspective(1200px) rotateY(" + (x * 5).toFixed(2) + "deg) rotateX(" + (-y * 5).toFixed(2) + "deg)";
    });
    document.addEventListener("pointerleave", function () { carte.style.transform = ""; });
  }

  // ── Le maillage : des téléphones qui se relaient les messages ───
  var toile = $("maille");
  var ctx = toile.getContext && toile.getContext("2d");
  if (!ctx) return;
  var rgb = getComputedStyle(document.documentElement).getPropertyValue("--maille").trim() || "0, 102, 224";
  var noeuds = [], impulsions = [], L = 0, H = 0, dpr = 1, doigt = null;
  function taille() {
    dpr = Math.min(window.devicePixelRatio || 1, 2);
    L = innerWidth; H = innerHeight;
    toile.width = L * dpr; toile.height = H * dpr;
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    var n = Math.round(Math.min(46, Math.max(18, L * H / 26000)));
    noeuds = [];
    for (var i = 0; i < n; i++) {
      noeuds.push({ x: Math.random() * L, y: Math.random() * H, vx: (Math.random() - .5) * .22, vy: (Math.random() - .5) * .22, r: 1.2 + Math.random() * 1.6 });
    }
  }
  taille();
  addEventListener("resize", taille);
  addEventListener("pointermove", function (e) { doigt = { x: e.clientX, y: e.clientY }; }, { passive: true });
  addEventListener("pointerdown", function (e) { doigt = { x: e.clientX, y: e.clientY }; });
  var PORTEE = 150;
  function voisins(a) {
    var v = [];
    for (var j = 0; j < noeuds.length; j++) {
      var b = noeuds[j];
      if (b !== a && Math.hypot(a.x - b.x, a.y - b.y) < PORTEE) v.push(b);
    }
    return v;
  }
  // Un message saute de téléphone en téléphone.
  setInterval(function () {
    if (document.hidden || impulsions.length > 3) return;
    var a = noeuds[(Math.random() * noeuds.length) | 0];
    var v = voisins(a);
    if (v.length) impulsions.push({ de: a, vers: v[(Math.random() * v.length) | 0], t: 0, sauts: 4 });
  }, 1400);
  function image() {
    requestAnimationFrame(image);
    if (document.hidden) return;
    ctx.clearRect(0, 0, L, H);
    for (var i = 0; i < noeuds.length; i++) {
      var a = noeuds[i];
      a.x += a.vx; a.y += a.vy;
      if (a.x < -20) a.x = L + 20; else if (a.x > L + 20) a.x = -20;
      if (a.y < -20) a.y = H + 20; else if (a.y > H + 20) a.y = -20;
      for (var j = i + 1; j < noeuds.length; j++) {
        var b = noeuds[j];
        var d = Math.hypot(a.x - b.x, a.y - b.y);
        if (d < PORTEE) {
          ctx.strokeStyle = "rgba(" + rgb + "," + (0.16 * (1 - d / PORTEE)).toFixed(3) + ")";
          ctx.lineWidth = 1;
          ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
        }
      }
      if (doigt) {
        var dd = Math.hypot(a.x - doigt.x, a.y - doigt.y);
        if (dd < 180) {
          ctx.strokeStyle = "rgba(" + rgb + "," + (0.28 * (1 - dd / 180)).toFixed(3) + ")";
          ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(doigt.x, doigt.y); ctx.stroke();
        }
      }
      ctx.fillStyle = "rgba(" + rgb + ",.45)";
      ctx.beginPath(); ctx.arc(a.x, a.y, a.r, 0, 6.2832); ctx.fill();
    }
    for (var k = impulsions.length - 1; k >= 0; k--) {
      var p = impulsions[k];
      p.t += 0.022;
      var x = p.de.x + (p.vers.x - p.de.x) * p.t;
      var y = p.de.y + (p.vers.y - p.de.y) * p.t;
      var g = ctx.createRadialGradient(x, y, 0, x, y, 10);
      g.addColorStop(0, "rgba(" + rgb + ",.9)");
      g.addColorStop(1, "rgba(" + rgb + ",0)");
      ctx.fillStyle = g;
      ctx.beginPath(); ctx.arc(x, y, 10, 0, 6.2832); ctx.fill();
      if (p.t >= 1) {
        var suite = voisins(p.vers).filter(function (n) { return n !== p.de; });
        if (--p.sauts > 0 && suite.length) {
          p.de = p.vers; p.vers = suite[(Math.random() * suite.length) | 0]; p.t = 0;
        } else {
          impulsions.splice(k, 1);
        }
      }
    }
  }
  requestAnimationFrame(image);
})();
</script>
</body>
</html>
""";

Response _handleHealth(Request request) {
  return Response.ok(
    jsonEncode({
      'status': 'ok',
      'entries': _db.count,
      'pushConfigured': _fcm != null,
      'uptime': DateTime.now().toIso8601String(),
    }),
    headers: {'content-type': 'application/json'},
  );
}

// ── Main ───────────────────────────────────────────────────────────

Future<void> main(List<String> args) async {
  final parser = ArgParser()
    ..addOption('port', abbr: 'p', help: 'Port d\'écoute')
    ..addOption('host', abbr: 'h', help: 'Adresse d\'écoute');

  final results = parser.parse(args);

  _securite = await Securite.depuisEnvironnement();
  try {
    _base = await Persistance.ouvrir();
    if (_base != null) {
      _comptes.addAll(await _base!.comptes());
      for (final l in await _base!.annuaire()) {
        _db.register(DirectoryEntry(
          peerId: l[0] as String,
          pseudo: l[1] as String,
          onionAddress: l[2] as String,
          publicKey: l[3] as String,
          fcmToken: l[4] as String?,
        ));
      }
      print('[Directory] Postgres : ${_db.count} inscriptions et ${_comptes.length} comptes rechargés');
    } else {
      print('[Directory] ⚠️ DATABASE_URL absente — annuaire en mémoire seule');
    }
  } catch (e) {
    print('[Directory] ⚠️ Postgres injoignable ($e) — annuaire en mémoire seule');
    _base = null;
  }

  // ── Compte de service Firebase, pour /notify ──────────────────────
  //
  // ⚠️ JAMAIS DE FICHIER COMMITÉ — TOUJOURS UNE VARIABLE D'ENVIRONNEMENT.
  //
  // Cette clé a des droits d'administration sur tout le projet Firebase
  // (envoyer un push à N'IMPORTE QUEL appareil enregistré). La porter
  // dans un fichier suivi par git la conserverait dans l'historique pour
  // toujours, même après suppression du fichier. `FIREBASE_SERVICE_ACCOUNT_JSON`
  // se règle uniquement dans les variables d'environnement du service
  // Railway — jamais commitée nulle part.
  final fcmJson = Platform.environment['FIREBASE_SERVICE_ACCOUNT_JSON'];
  if (fcmJson != null && fcmJson.isNotEmpty) {
    try {
      _fcm = FcmSender(
        serviceAccountJson: jsonDecode(fcmJson) as Map<String, dynamic>,
      );
      print('[Directory] Notifications push Firebase configurées');
    } catch (e) {
      print('[Directory] FIREBASE_SERVICE_ACCOUNT_JSON illisible: $e');
    }
  } else {
    print('[Directory] FIREBASE_SERVICE_ACCOUNT_JSON absente — '
        '/notify restera sans effet');
  }

  // ── Signalements : persistés sur le volume Railway monté sur /data ──
  //
  // `REPORTS_PATH` surcharge l'emplacement (utile en local). À défaut :
  // `/data/reports.json` si `/data` existe (volume monté), sinon un
  // fichier local à côté du binaire — qui, lui, ne survit PAS à un
  // redéploiement Railway. Le message au démarrage dit lequel des deux.
  final reportsPath = Platform.environment['REPORTS_PATH'] ??
      (Directory('/data').existsSync()
          ? '/data/reports.json'
          : 'reports.json');
  _db.chargerSignalements(reportsPath);

  // ── Sauvegardes chiffrées : sur le volume, sinon elles seraient perdues ──
  final dossierSauvegardes = Directory(Platform.environment['SAUVEGARDES_PATH'] ??
      (Directory('/data').existsSync() ? '/data/sauvegardes' : 'sauvegardes'))
    ..createSync(recursive: true);
  _sauvegardes = StockSauvegardes(dossierSauvegardes);
  final dossierCles = Directory(Platform.environment['CLES_SIGNAL_PATH'] ??
      (Directory('/data').existsSync() ? '/data/cles_signal' : 'cles_signal'))
    ..createSync(recursive: true);
  _clesSignal = StockClesSignal(dossierCles);
  _liaisons = Liaisons(File(Platform.environment['REVOCATIONS_PATH'] ??
      (Directory('/data').existsSync() ? '/data/revocations.json' : 'revocations.json')));
  print('[Directory] Paquets de clés Signal dans ${dossierCles.path}');
  print('[Directory] Sauvegardes chiffrées dans ${dossierSauvegardes.path}');
  if (reportsPath.startsWith('/data/')) {
    print('[Directory] Signalements persistés sur le volume : $reportsPath');
  } else {
    print('[Directory] ⚠️ Signalements dans $reportsPath — PERDUS au prochain '
        'redéploiement (aucun volume monté sur /data)');
  }

  if ((Platform.environment['ADMIN_KEY'] ?? '').isEmpty) {
    print('[Directory] ⚠️ ADMIN_KEY absente — /admin/reports et /admin/warn '
        'répondront 503 (modération désactivée)');
  } else {
    print('[Directory] Modération activée (ADMIN_KEY configurée)');
  }

  // Deux modes de déploiement pour ce même binaire :
  //
  //   1. Service caché .onion (start.sh) : passe --port 8080 --host
  //      127.0.0.1 explicitement, Tor fait le pont vers l'extérieur.
  //   2. Railway (déploiement direct, sans daemon Tor local) : aucun
  //      argument n'est passé, on lit alors la variable d'environnement
  //      PORT que Railway fournit, et on écoute sur toutes les
  //      interfaces — sinon Railway ne peut jamais router le trafic
  //      jusqu'au conteneur.
  //
  // Le client (`TorHttpClient`) route de toute façon CETTE requête au
  // travers du proxy SOCKS5 de Tor sur l'appareil, qu'elle vise un
  // .onion ou une adresse Railway classique : l'anonymat côté client
  // est préservé dans les deux cas, seul le serveur cesse d'être lui
  // -même un service caché.
  final portEnv = Platform.environment['PORT'];
  final port = int.parse(results['port'] as String? ?? portEnv ?? '8080');
  final host = results['host'] as String? ?? '0.0.0.0';

  // Nettoyage périodique des entrées expirées (toutes les heures).
  Timer.periodic(const Duration(hours: 1), (_) {
    final cleaned = _db.sweep();
    if (cleaned > 0) print('[Directory] Nettoyé $cleaned entrées expirées');
    _base?.menage(const Duration(days: 30)).catchError((_) => 0);
  });

  final handler = const Pipeline()
      .addMiddleware(logRequests())
      .addMiddleware(limiteParIp(Debit(capacite: 120, parMinute: 600)))
      .addMiddleware(Liaisons.cors())
      .addHandler(_router.call);

  final server = await io.serve(handler, host, port);
  print('[Directory] Serveur annuaire démarré sur http://${server.address.host}:${server.port}');
  print('[Directory] Endpoints:');
  print('  POST /register      — Enregistrer un appareil');
  print('  DELETE /register    — Se désinscrire');
  print('  GET /search?q=      — Chercher un contact');
  print('  POST /notify        — Réveiller un appareil par push');
  print('  POST /report        — Signaler un contact');
  print('  POST /presence      — Battement de présence (app ouverte)');
  print('  GET /presence?ids=  — Dernier battement de ces identifiants');
  print('  GET /admin/reports  — [clé admin] Lister les signalements');
  print('  POST /admin/warn    — [clé admin] Avertir un compte');
  print('  POST|GET /liaison/<canal> — Liaison de Droplet Web');
  print('  DELETE /appareils/<id>/<appareil> — Déconnecter un appareil lié');
  print('  GET /health         — Health check');
}
