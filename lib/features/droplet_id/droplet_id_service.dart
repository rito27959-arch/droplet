// ============================================================================
// DROPLET ID DANS L'APP — le « téléphone » qui approuve les connexions.
// ----------------------------------------------------------------------------
// • Une clé Ed25519 PROPRE À DROPLET ID, distincte de la clé X25519 des
//   messages : une faille d'un côté ne touche pas l'autre. Sa partie privée
//   reste dans le coffre-fort du téléphone (FlutterSecureStorage).
// • Chaque requête au service est signée :
//     MÉTHODE \n chemin \n heure \n nonce \n sha256-hex(corps)
//   (même protocole que droplet-id/serveur/src/signature.js).
// • Le service ne reçoit jamais : numéro, e-mail, nom, contacts, messages.
// ============================================================================

import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'protocole.dart';

/// Le service en production, et celui de test (comptes séparés : une clé et
/// un compte par service, jamais partagés).
const emetteurDropletId = 'https://id.dropletmesh.app';
const emetteurDropletIdTest = 'https://id-test.dropletmesh.app';
const _hotes = {'id.dropletmesh.app': emetteurDropletId, 'id-test.dropletmesh.app': emetteurDropletIdTest};

/// Un lien de demande scanné ou ouvert : quel service, quelle demande.
typedef LienDropletId = ({String emetteur, String demandeId});

class DemandeDropletId {
  DemandeDropletId({required this.id, required this.nomSite, required this.hote, required this.portees, required this.expireLe, this.logo});
  final String id;
  final String nomSite;
  final String hote;
  final List<String> portees;
  final DateTime expireLe;

  /// Le logo du site (PNG servi par Droplet ID), ou null.
  final String? logo;
  bool get demandeProfil => portees.contains('profile');
}

class ConnexionDropletId {
  ConnexionDropletId({required this.clientId, required this.nom, required this.portees, required this.accordeLe});
  final String clientId;
  final String nom;
  final List<String> portees;
  final DateTime accordeLe;
}

class ErreurDropletId implements Exception {
  ErreurDropletId(this.code, [this.statut]);
  final String code;
  final int? statut;

  /// Un message clair pour l'écran.
  String get message => switch (code) {
        'demande_expiree' => 'Cette demande a expiré. Recommencez sur le site.',
        'mauvais_code' => "Ce n'était pas le bon nombre. La demande est annulée par sécurité.",
        'appareil_revoque' => 'Ce téléphone a été retiré de votre compte Droplet ID.',
        'reseau' => 'Pas de connexion au service Droplet ID. Vérifiez Internet.',
        _ => 'Droplet ID a refusé la demande ($code).',
      };
  @override
  String toString() => 'ErreurDropletId($code)';
}

class DropletIdService {
  DropletIdService._(this.emetteur, String prefixe)
      : _cleGraine = '${prefixe}_graine_ed25519',
        _cleAppareil = '${prefixe}_appareil',
        _cleCompte = '${prefixe}_compte';

  /// Production (https://id.dropletmesh.app).
  static final instance = DropletIdService._(emetteurDropletId, 'droplet_id_prod');

  /// Service de test (https://id-test.dropletmesh.app), pour les démos.
  static final test = DropletIdService._(emetteurDropletIdTest, 'droplet_id');

  /// Le service qui correspond à un émetteur, ou null s'il n'est pas reconnu.
  static DropletIdService? pour(String emetteur) => switch (emetteur) {
        emetteurDropletId => instance,
        emetteurDropletIdTest => test,
        _ => null,
      };

  final String emetteur;
  bool get estTest => emetteur == emetteurDropletIdTest;

  static const _coffre = FlutterSecureStorage();
  final String _cleGraine;
  final String _cleAppareil;
  final String _cleCompte;
  final _ed = Ed25519();

  /// Le service et la demande, si le texte scanné est un lien de demande
  /// (https://id[-test].dropletmesh.app/a/<id>).
  static LienDropletId? lienDepuis(String texte) {
    final u = Uri.tryParse(texte.trim());
    if (u == null || u.scheme != 'https') return null;
    final emetteur = _hotes[u.host];
    if (emetteur == null) return null;
    final s = u.pathSegments;
    if (s.length != 2 || s[0] != 'a' || !RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(s[1])) return null;
    return (emetteur: emetteur, demandeId: s[1]);
  }

  /// L'identifiant seul (compatibilité).
  static String? demandeDepuis(String texte) => lienDepuis(texte)?.demandeId;

  /// Le service d'un lien d'application dont on ne connaît que l'hôte.
  static DropletIdService pourHote(String? hote) => pour(_hotes[hote] ?? '') ?? instance;

  Future<bool> estActive() async => (await _coffre.read(key: _cleAppareil)) != null;

  Future<SimpleKeyPair> _paire() async {
    final graine = await _coffre.read(key: _cleGraine);
    if (graine == null) throw ErreurDropletId('pas_de_compte');
    return _ed.newKeyPairFromSeed(base64Url.decode(graine));
  }

  static String _b64(List<int> o) => b64url(o);

  /// Crée le compte (une seule fois) : une clé neuve, rien d'autre.
  Future<void> activer({String nomAppareil = 'Téléphone'}) async {
    if (await estActive()) return;
    final graine = List<int>.generate(32, (_) => Random.secure().nextInt(256));
    final paire = await _ed.newKeyPairFromSeed(graine);
    final pub = await paire.extractPublicKey();
    final r = await _appeler('POST', '/v1/comptes', {'nom': nomAppareil}, paire: paire, clePub: _b64(pub.bytes));
    // La graine n'est gardée qu'une fois le compte accepté.
    await _coffre.write(key: _cleGraine, value: base64Url.encode(graine));
    await _coffre.write(key: _cleAppareil, value: r['appareil_id'] as String);
    await _coffre.write(key: _cleCompte, value: r['compte_id'] as String);
  }

  Future<DemandeDropletId> lireDemande(String id) async {
    final r = await _appeler('GET', '/v1/demandes/$id', null);
    final client = r['client'] as Map<String, dynamic>;
    return DemandeDropletId(
      id: r['id'] as String,
      nomSite: (client['nom'] ?? client['id']) as String,
      hote: (client['site'] ?? '') as String,
      portees: List<String>.from(r['portees'] as List),
      expireLe: DateTime.parse(r['expire_le'] as String),
      // Seulement un logo servi par le service lui-même.
      logo: (client['logo'] is String && (client['logo'] as String).startsWith('$emetteur/logo/')) ? client['logo'] as String : null,
    );
  }

  Future<void> approuver(String id, {required String code, required List<String> portees, String? pseudo}) async {
    await _appeler('POST', '/v1/demandes/$id/decision', {
      'decision': 'approuver',
      'code': code,
      'portees': portees,
      if (pseudo != null && pseudo.trim().isNotEmpty) 'pseudo': pseudo.trim(),
    });
  }

  Future<void> refuser(String id) => _appeler('POST', '/v1/demandes/$id/decision', {'decision': 'refuser'});

  Future<List<ConnexionDropletId>> connexions() async {
    final r = await _appeler('GET', '/v1/connexions', null);
    return [
      for (final c in r['connexions'] as List)
        ConnexionDropletId(
          clientId: c['client_id'] as String,
          nom: c['nom'] as String,
          portees: List<String>.from(c['portees'] as List),
          accordeLe: DateTime.parse(c['accorde_le'] as String),
        ),
    ];
  }

  Future<void> retirer(String clientId) => _appeler('DELETE', '/v1/connexions/${Uri.encodeComponent(clientId)}', null);

  /// Oublie Droplet ID sur ce téléphone (retire l'appareil côté service).
  Future<void> desactiver() async {
    final appareil = await _coffre.read(key: _cleAppareil);
    if (appareil != null) {
      try {
        await _appeler('DELETE', '/v1/appareils/$appareil', null);
      } catch (_) {/* hors ligne : on oublie quand même ici */}
    }
    for (final k in [_cleGraine, _cleAppareil, _cleCompte]) {
      await _coffre.delete(key: k);
    }
  }

  // ── La requête signée (voir protocole.dart) ───────────────────────
  Future<Map<String, dynamic>> _appeler(String methode, String chemin, Map<String, dynamic>? corps,
      {SimpleKeyPair? paire, String? clePub}) async {
    final ReponseDroplet r;
    try {
      r = await requeteSignee(
        base: emetteur,
        methode: methode,
        chemin: chemin,
        corps: corps,
        paire: paire ?? await _paire(),
        appareilId: clePub == null ? await _coffre.read(key: _cleAppareil) : null,
        clePub: clePub,
      ).timeout(const Duration(seconds: 15));
    } catch (_) {
      throw ErreurDropletId('reseau');
    }
    if (r.statut >= 400) throw ErreurDropletId((r.corps['erreur'] ?? 'http_${r.statut}') as String, r.statut);
    return r.corps;
  }
}
