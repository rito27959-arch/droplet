// ============================================================================
// LE MIROIR DES APPAREILS LIÉS — ce qui fait vivre Droplet Web.
// ----------------------------------------------------------------------------
// Le téléphone reste le seul à détenir l'identité du compte et les sessions
// de chiffrement avec les contacts. Droplet Web n'en a pas besoin : il
// parle au TÉLÉPHONE, par un canal chiffré qui n'est qu'à eux deux.
//
//   clé du canal = HKDF-SHA256( X25519(clé d'identité du téléphone,
//                                      clé publique du navigateur),
//                               sel « droplet-mesh », info « droplet-appareil-v1 » )
//   chiffrement  = AES-256-GCM, nonce de 12 octets, étiquette de 16 octets
//                  collée à la fin du chiffré
//
// Le canal passe par la boîte aux lettres : chaque appareil lié y a sa
// propre file, à son identifiant d'appareil (déclarée à la liaison, voir
// `AppareilsLies.lier`). Le serveur ne voit que des blobs.
//
// ── Téléphone → navigateur : des « lots » ───────────────────────────
//
//   dépôt : to = <appareil>, from = <moi>, payload = {"w":1,"c":…,"n":…}
//   clair :
//     {"v":1,
//      "profil":      {"pseudo":…, "invitation":…}         (synchro)
//      "contacts":    [{"id":peerId, "pseudo":…}],
//      "discussions": [{"id":"p:<peerId>"|"g:<groupId>", "type":"directe"|"groupe",
//                       "titre":…, "membres":[peerId…], "nonLus":n}],
//      "messages":    [{"id":…, "d":<discussion>, "a":<auteur>|"moi",
//                       "texte":…, "date":ISO-8601, "statut":"envoi"|"envoye"|"recu"|"lu"|"echec",
//                       "r":<réponse à>}]}
//
// Une synchro complète part à la liaison (et à la demande du navigateur) :
// les 40 discussions les plus récentes, leurs 80 derniers messages. Ensuite,
// chaque message nouveau ou modifié (envoyé, reçu, coches) part dans un
// petit lot, regroupé sur 350 ms.
//
// ── Navigateur → téléphone : des demandes ───────────────────────────
//
//   dépôt : to = <moi>, from = <appareil>, payload = {"l":1,"c":…,"n":…}
//   clair : {"t":"envoyer", "d":<discussion>, "id":…, "texte":…, "r":…,
//            "pseudo":…, "cle":…}       (pseudo/clé : contact trouvé par
//                                         recherche, inconnu du téléphone)
//           {"t":"synchro"}
//
//           {"t":"fichier", "d", "id", "nom", "mime", "taille", "legende",
//            "r", "i", "n", "b64"}   un fichier écrit sur le web, en n
//                                    morceaux de 700 Ko au plus (la boîte
//                                    accepte 2 Mo par dépôt)
//           {"t":"telecharger", "id"}  le navigateur veut le contenu d'un
//                                    fichier (photo, vocal, vidéo…)
//           {"t":"lu", "d"}          la discussion a été lue sur le web
//           {"t":"reaction", "id", "emoji", "retirer":[…]}
//           {"t":"modifier", "id", "texte"}
//           {"t":"supprimer", "id"}
//
//           {"t":"etat", "d", "champ", "valeur"}
//                                    champ : epinglee | archivee | sourdine
//                                            | ephemere | bloque | nonLue
//                                    | ephemere (secondes) | bloque (1:1)
//           {"t":"msg_etat", "id", "champ", "valeur"}
//                                    champ : epingle | important
//           {"t":"frappe", "d"}      on écrit sur le web : le contact voit
//                                    « en train d'écrire… »
//           {"t":"discussion", "d", "op":"supprimer"|"vider"}
//           {"t":"groupe", "g", "op":"renommer", "titre"}
//                          | "op":"description", "texte"
//                          | "op":"ajouter", "membres":[peerId…]
//                          | "op":"retirer", "membre"
//                          | "op":"quitter"
//           {"t":"profil", "pseudo"}
//           {"t":"statut", "texte", "fond"}           statut texte seul
//           {"t":"fichier", "but":"statut", "k":"photo"|"video"|"voice",
//            "texte", "fond", "ms", …morceaux…}       statut avec média
//           {"t":"statut_vu", "id", "auteur"}
//           {"t":"statut_reaction", "id", "auteur", "emoji"}
//           {"t":"statut_reponse", "id", "auteur", "texte"}
//   L'instantané d'état porte aussi les statuts actifs :
//     "statuts":[{"id","a":<auteur>|"moi","pseudo","texte","date",
//                 "k":"texte"|"photo"|"video"|"voice","nom","mime","ms",
//                 "fond":ARGB,"vu":bool}]
//   et « telecharger » accepte l'id d'un statut (son média).
//   Les discussions de groupe portent aussi "admins" (["moi" si je le
//   suis, puis les peerIds) et "description".
//
//   ── L'ÉTAT PARTAGÉ (téléphone → navigateur) ──
//   Comme WhatsApp : ce qui change d'un côté change de l'autre. Le
//   téléphone fait foi ; il envoie un instantané COMPLET dès qu'il change
//   (vérifié toutes les 1,5 s, déposé seulement s'il a bougé) :
//     {"v":1, "etat":{
//        "disc":      {"<d>":{"e":épinglée,"a":archivée,"s":sourdine,
//                             "v":verrouillée,"x":éphémère (s)}},
//        "epingles":  {"<d>":[id…]},      messages épinglés (3 au plus)
//        "importants":[id…],              messages favoris
//        "bloques":   [peerId…],
//        "presence":  {"<peerId>":{"l":en ligne,"vu":ISO-8601 (à la minute)}}}}
//   et, à chaque « en train d'écrire » reçu par le téléphone :
//     {"v":1, "frappe":{"d":<discussion>, "a":<auteur>}}
//   Une discussion VERROUILLÉE sur le téléphone n'est pas montrée sur le
//   web — comme WhatsApp, qui ne déverrouille pas un appareil lié.
//
//   Le téléphone répond à « telecharger » par des lots
//     {"v":1, "fichier":{"id", "i", "n", "b64"}}
//   et chaque message de fichier porte, dans ses lots ordinaires,
//     "f": {"id", "nom", "mime", "taille"}.
//   Chaque lot donne aussi le nombre de non-lus de ses discussions : lire
//   sur le téléphone efface le badge du web, et inversement.
//
// Le message écrit sur le web garde SON identifiant : il revient dans le
// lot suivant avec ses vraies coches, et le navigateur le reconnaît.
//
// ⚠️ CE QUE CE MODÈLE NE FAIT PAS (encore) : le navigateur n'envoie rien
// quand le téléphone est éteint — sa demande attend dans la boîte, et part
// au réveil du téléphone. C'est le modèle de WhatsApp Web avant 2021.
// L'étape suivante (des sessions de chiffrement propres à chaque appareil)
// rendra le navigateur autonome.
// ============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../models/mesh_message.dart';
import '../repositories/mesh_repository.dart';
import '../../features/chat/messages_importants.dart';
import '../../features/group/reglages_groupe.dart';
import '../../features/status/ordre_statuts.dart';
import '../models/status_media.dart';
import 'appareils_lies.dart';
import 'avatar_service.dart';
import 'epingles.dart';
import 'presence_internet.dart';
import 'crypto_service.dart';
import 'invitation.dart';
import 'qr_code_exchange.dart';
import 'storage_service.dart';

typedef EnvoiDepuisAppareil = Future<void> Function(String cible, String texte, {String? id, String? reponseA});

/// Un fichier écrit sur le web, à envoyer depuis le téléphone.
typedef FichierDepuisAppareil = Future<void> Function({
  String? cible,
  String? groupe,
  required String id,
  required String nom,
  required String mime,
  required Uint8List octets,
  String? legende,
  String? reponseA,
});

/// Ce que le web peut faire d'autre, et que le téléphone refait à
/// l'identique (lectures, réactions, modifications, suppressions).
class ActionsMiroir {
  const ActionsMiroir({
    required this.lire,
    required this.lireGroupe,
    required this.reagir,
    required this.modifier,
    required this.supprimer,
    required this.epingler,
    required this.frappe,
    required this.supprimerConversation,
    this.noterEnvoiAutonome,
    this.noterFichierAutonome,
  });

  /// Pareil pour une photo, un vocal, un document parti directement du web.
  final Future<void> Function({required String peer, required String id, required String nom, required String mime, required Uint8List octets, String? legende, String? reponseA})? noterFichierAutonome;

  /// Droplet Web a envoyé un message LUI-MÊME (téléphone éteint) : on
  /// l'inscrit dans l'historique du téléphone, sans le renvoyer.
  final Future<void> Function({required String peer, required String id, required String texte, required DateTime date, String? reponseA})? noterEnvoiAutonome;

  final Future<void> Function(String peerId) lire;
  final Future<void> Function(String groupId) lireGroupe;
  final void Function(String messageId, String emoji) reagir;
  final void Function(String messageId, String texte) modifier;
  final void Function(String messageId) supprimer;

  /// Épingle ou désépingle un message, ici ET chez les autres (comme
  /// depuis la discussion du téléphone).
  final Future<void> Function(String messageId, bool epingle) epingler;

  /// « En train d'écrire » depuis le web : prévenir le contact ou le groupe.
  final void Function({String? peer, String? groupe}) frappe;

  /// Supprime une discussion du téléphone (comme depuis la liste).
  final void Function({String? peer, String? groupe}) supprimerConversation;
}

/// Un fichier qui arrive du web morceau par morceau.
class _Assemblage {
  _Assemblage(this.n) : morceaux = List<Uint8List?>.filled(n, null);
  final int n;
  final List<Uint8List?> morceaux;
  final DateTime debut = DateTime.now();
  Map<String, dynamic> entete = const {};
  bool get complet => morceaux.every((m) => m != null);
}

class MiroirAppareils {
  MiroirAppareils(this._repo, {required this.envoyer, required this.envoyerGroupe, required this.envoyerFichier, required this.actions}) {
    actuel = this;
  }

  /// L'instance vivante (une seule : celle du `MeshNotifier`).
  static MiroirAppareils? actuel;

  final MeshRepository _repo;
  final EnvoiDepuisAppareil envoyer;
  final EnvoiDepuisAppareil envoyerGroupe;
  final FichierDepuisAppareil envoyerFichier;
  final ActionsMiroir actions;

  /// Les morceaux d'un fichier : 700 Ko d'octets, soit ~1,3 Mo une fois
  /// encodés et chiffrés — sous les 2 Mo d'un dépôt.
  static const tailleMorceau = 700 * 1024;

  /// Au-delà, un fichier ne passe pas par Internet (`FichierEnLigne`).
  static const maxFichier = 16 * 1024 * 1024;

  final Map<String, _Assemblage> _assemblages = {};

  static const _maxDiscussions = 40;
  static const _maxParDiscussion = 80;
  static const _maxParLot = 300;

  final Map<String, String> _empreintes = {};
  final Map<String, SecretKey> _cles = {};
  bool _amorce = false;
  Timer? _minuteur;
  List<MeshMessage> _dernier = const [];

  // ── L'état partagé ─────────────────────────────────────────────────

  /// Les pairs à portée du maillage, tenus à jour par la liste des pairs.
  static Set<String> pairsMaillage = const {};

  /// « En train d'écrire » par Internet (branché par le notifier d'appels).
  static void Function(String peerId, {String? groupId})? frappeEnLigne;

  /// Incrémenté quand le web change un état (épinglée, archivée…) : la
  /// liste des discussions du téléphone se relit.
  static final ValueNotifier<int> revisionEtat = ValueNotifier<int>(0);

  Timer? _veilleEtat;
  String? _dernierEtat;
  StreamSubscription<String>? _subFrappe;
  StreamSubscription<({String groupId, String peerId})>? _subFrappeGroupe;
  final Map<String, DateTime> _frappeEnvoyee = {};

  void _demarrerVeille() {
    _veilleEtat ??= Timer.periodic(const Duration(milliseconds: 1500), (_) => unawaited(_pousserEtat()));
    _subFrappe ??= _repo.typingEvents.listen((p) => unawaited(_pousserFrappe('p:$p', p)));
    _subFrappeGroupe ??= _repo.frappeGroupeEvents.listen((e) => unawaited(_pousserFrappe('g:${e.groupId}', e.peerId)));
    // Un contact change (ou retire) sa photo : le web suit aussitôt.
    _subAvatars ??= _repo.peerAvatarEvents.listen((p) => unawaited(_pousserAvatars([p])));
  }

  StreamSubscription<String>? _subAvatars;

  /// Les photos de profil de mes contacts, pour le web. Une photo pèse
  /// 20 à 60 Ko : on en groupe jusqu'à ~900 Ko par dépôt (la boîte
  /// accepte 2 Mo une fois chiffré et encodé). Un contact sans photo part
  /// avec `av: null` — c'est ainsi que le web apprend un retrait.
  Future<void> _pousserAvatars(List<String> ids, {AppareilLie? seul}) async {
    var lot = <String, dynamic>{};
    var taille = 0;
    Future<void> vider() async {
      if (lot.isEmpty) return;
      for (final a in seul != null ? [seul] : _appareils()) {
        await _deposer(a, {'v': 1, 'avatars': lot});
      }
      lot = <String, dynamic>{};
      taille = 0;
    }

    for (final id in ids.take(200)) {
      final chemin = AvatarService.cheminPair(id);
      final av = AvatarService.empreintePair(id);
      if (chemin == null || av == null) {
        lot[id] = {'av': null};
        continue;
      }
      try {
        final b64 = base64.encode(await File(chemin).readAsBytes());
        if (b64.length > 600 * 1024) continue;
        if (taille + b64.length > 900 * 1024) await vider();
        lot[id] = {'av': av, 'photo': b64};
        taille += b64.length;
      } catch (_) {}
    }
    await vider();
  }

  /// L'instantané complet de l'état, pour les 60 discussions les plus
  /// récentes — ce que le web montre.
  Map<String, dynamic> _etat() {
    final moi = _repo.myId;
    final recence = <String, int>{};
    for (final m in _dernier) {
      final d = _discussionDe(m, moi);
      if (d == null) continue;
      final t = m.timestamp.millisecondsSinceEpoch;
      if (t > (recence[d] ?? 0)) recence[d] = t;
    }
    final discs = (recence.entries.toList()..sort((a, b) => b.value.compareTo(a.value))).take(60).map((e) => e.key);
    final epinglees = StorageService.getPinnedConversations();
    final archivees = StorageService.getArchivedConversations();
    final sourdines = StorageService.getMutedConversations();
    final verrouillees = StorageService.getLockedConversations();
    final ephemeres = StorageService.getEphemeralTimers();
    final nonLues = StorageService.getMarkedUnreadConversations();
    final etat = <String, Map<String, dynamic>>{};
    final epingles = <String, List<String>>{};
    final presence = <String, Map<String, dynamic>>{};
    for (final d in discs) {
      final cle = d.substring(2);
      etat[d] = {
        'e': epinglees.contains(cle),
        'a': archivees.contains(cle),
        's': sourdines.contains(cle),
        'v': verrouillees.contains(cle),
        'x': ephemeres[cle] ?? 0,
        // « Marquée comme non lue » : la pastille, des deux côtés.
        'n': nonLues.contains(cle),
      };
      final ep = Epingles.lire(cle);
      if (ep.isNotEmpty) epingles[d] = ep;
      if (d.startsWith('p:')) presence[cle] = _presence(cle);
    }
    return {
      'statuts': _statuts(moi),
      'disc': etat,
      'epingles': epingles,
      'importants': [for (final m in MessagesImportants.tous()) m.id],
      'bloques': StorageService.getBlockedContacts().toList(),
      'presence': presence,
    };
  }

  /// Les statuts actifs (24 h), des contacts non bloqués et les miens.
  static List<Map<String, dynamic>> _statuts(String moi) {
    final bloques = StorageService.getBlockedContacts();
    final actifs = StorageService.getActiveStatuses()
        .where((s) => !s.isExpired && !bloques.contains(s.authorId))
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return [
      for (final s in actifs.length > 120 ? actifs.sublist(actifs.length - 120) : actifs)
        () {
          final media = StorageService.getStatusMedia(s.id);
          final avecFichier = media.hasMedia;
          return {
            'id': s.id,
            'a': s.authorId == moi ? 'moi' : s.authorId,
            'pseudo': s.authorPseudo,
            'texte': s.content,
            'date': s.createdAt.toUtc().toIso8601String(),
            'k': avecFichier ? media.kind.name : 'texte',
            if (avecFichier) 'nom': media.fileName,
            if (avecFichier) 'mime': media.mimeType,
            if (media.durationMs != null) 'ms': media.durationMs,
            if (media.backgroundColor != null) 'fond': media.backgroundColor,
            'vu': StatutsVus.estVu(s.id),
          };
        }(),
    ];
  }

  /// En ligne : à portée du maillage, ou signe de vie par Internet de moins
  /// de cinq minutes. « Vu » : le plus récent des deux, arrondi à la minute
  /// pour ne pas renvoyer l'instantané à chaque seconde.
  static Map<String, dynamic> _presence(String peer) {
    final net = PresenceInternet.dernierSigne(peer);
    final fiche = StorageService.getPeerRecord(peer)?.lastSeen;
    DateTime? vu = net;
    if (fiche != null && (vu == null || fiche.isAfter(vu))) vu = fiche;
    return {
      'l': pairsMaillage.contains(peer) || PresenceInternet.enLigne(peer),
      if (vu != null)
        'vu': DateTime.fromMillisecondsSinceEpoch(vu.millisecondsSinceEpoch ~/ 60000 * 60000).toUtc().toIso8601String(),
    };
  }

  /// Dépose l'instantané s'il a changé (ou toujours, vers [seul]).
  Future<void> _pousserEtat({AppareilLie? seul}) async {
    final appareils = seul == null ? _appareils() : [seul];
    if (appareils.isEmpty) return;
    final etat = _etat();
    final empreinte = jsonEncode(etat);
    if (seul == null && empreinte == _dernierEtat) return;
    _dernierEtat = empreinte;
    for (final a in appareils) {
      await _deposer(a, {'v': 1, 'etat': etat});
    }
  }

  /// Un « en train d'écrire » reçu : relayé au web, une fois toutes les 3 s
  /// au plus par personne (le web l'affiche 6 s).
  Future<void> _pousserFrappe(String d, String auteur) async {
    final cle = '$d|$auteur';
    final maintenant = DateTime.now();
    if (maintenant.difference(_frappeEnvoyee[cle] ?? DateTime(0)) < const Duration(seconds: 3)) return;
    _frappeEnvoyee[cle] = maintenant;
    for (final a in _appareils()) {
      await _deposer(a, {
        'v': 1,
        'frappe': {'d': d, 'a': auteur},
      });
    }
  }

  // ── Ce que le téléphone envoie ─────────────────────────────────────

  /// Appelé à chaque changement de la liste des messages.
  void surMessages(List<MeshMessage> tous) {
    _dernier = tous;
    if (AppareilsLies.liste().every((a) => a.cle == null)) {
      _amorce = false;
      return;
    }
    _demarrerVeille();
    if (!_amorce) {
      // Premier passage : ce qui existe déjà a été synchronisé à la
      // liaison. On ne renvoie que ce qui changera désormais.
      for (final m in tous) {
        _empreintes[m.id] = _empreinte(m);
      }
      _amorce = true;
      return;
    }
    _minuteur?.cancel();
    _minuteur = Timer(const Duration(milliseconds: 350), () => unawaited(_pousserChangements()));
  }

  Future<void> _pousserChangements() async {
    final appareils = _appareils();
    if (appareils.isEmpty) return;
    final changes = <MeshMessage>[];
    // Un message reçu que le web n'a jamais vu : il mérite une notification
    // (une simple mise à jour — lu, réaction, modification — non).
    var nouveauRecu = false;
    final moi = _repo.myId;
    for (final m in _dernier) {
      final e = _empreinte(m);
      if (_empreintes[m.id] != e) {
        if (_empreintes[m.id] == null && m.senderId != null && m.senderId != moi) nouveauRecu = true;
        _empreintes[m.id] = e;
        changes.add(m);
      }
    }
    if (changes.isEmpty) return;
    final lot = _lot(changes);
    if (lot == null) return;
    for (final a in appareils) {
      await _deposer(a, lot, notifier: nouveauRecu);
    }
  }

  /// Une synchro complète vers [appareil] : les discussions récentes et
  /// leurs derniers messages, en plusieurs lots si besoin.
  Future<void> synchroniser(AppareilLie appareil) async {
    if (appareil.cle == null) return;
    final moi = _repo.myId;
    final parDiscussion = <String, List<MeshMessage>>{};
    for (final m in _dernier.isEmpty ? StorageService.getMessages() : _dernier) {
      final d = _discussionDe(m, moi);
      if (d != null) (parDiscussion[d] ??= []).add(m);
    }
    final recentes = parDiscussion.entries.toList()
      ..sort((a, b) => _plusRecent(b.value).compareTo(_plusRecent(a.value)));
    final choisis = <MeshMessage>[];
    for (final e in recentes.take(_maxDiscussions)) {
      final l = [...e.value]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
      choisis.addAll(l.length > _maxParDiscussion ? l.sublist(l.length - _maxParDiscussion) : l);
    }

    String? invitation;
    try {
      invitation = InvitationDroplet.lien(await QrCodeExchange.generateQrData());
    } catch (_) {}
    final profil = {'pseudo': StorageService.currentUser?.pseudo ?? '', 'invitation': ?invitation};

    if (choisis.isEmpty) {
      await _deposer(appareil, {'v': 1, 'profil': profil});
      await _pousserEtat(seul: appareil);
      return;
    }
    for (var i = 0; i < choisis.length; i += _maxParLot) {
      final morceau = choisis.sublist(i, (i + _maxParLot).clamp(0, choisis.length));
      final lot = _lot(morceau, nonLus: i == 0);
      if (lot == null) continue;
      if (i == 0) lot['profil'] = profil;
      await _deposer(appareil, lot);
    }
    // Ma photo de profil, dans un dépôt à part : quelques dizaines de Ko
    // qu'on n'ajoute pas à un lot de 300 messages, déjà gros.
    await _deposer(appareil, {'v': 1, 'profil': _maPhoto()});
    for (final m in _dernier) {
      _empreintes[m.id] = _empreinte(m);
    }
    _amorce = true;
    _demarrerVeille();
    await _pousserEtat(seul: appareil);
  }

  // ── Ce que le navigateur demande ───────────────────────────────────

  /// Une demande d'un appareil lié (`l: 1`). Rend `true` si elle a été
  /// reconnue — quoi qu'il en advienne, le dépôt peut être acquitté.
  Future<bool> recevoir(String de, Map<String, dynamic> parsed) async {
    if (parsed['l'] != 1) return false;
    final appareil = _appareils().where((a) => a.id == de).firstOrNull;
    if (appareil == null) return true; // appareil retiré, ou inconnu : ignoré
    final clair = await _dechiffrer(appareil, parsed['c'] as String?, parsed['n'] as String?);
    if (clair == null) return true;
    try {
      final j = (jsonDecode(clair) as Map).cast<String, dynamic>();
      switch (j['t']) {
        case 'synchro':
          await synchroniser(appareil);
        case 'fichier':
          await _morceauRecu(j);
        case 'telecharger':
          await _envoyerContenu(appareil, j['id'] as String? ?? '');
        case 'lu':
          final d = j['d'] as String? ?? '';
          if (d.startsWith('p:')) await actions.lire(d.substring(2));
          if (d.startsWith('g:')) await actions.lireGroupe(d.substring(2));
        case 'reaction':
          final id = j['id'] as String? ?? '';
          final m = _dernier.where((x) => x.id == id).firstOrNull;
          if (m == null) return true;
          // Le web garde une réaction par personne : il dit laquelle il
          // remplace, le téléphone la retire avant d'ajouter la nouvelle.
          for (final e in (j['retirer'] as List? ?? const []).whereType<String>()) {
            if (m.reactions.contains(e)) actions.reagir(id, e);
          }
          final emoji = j['emoji'] as String? ?? '';
          if (emoji.isNotEmpty) actions.reagir(id, emoji);
        case 'modifier':
          final texte = (j['texte'] as String? ?? '').trim();
          if (texte.isNotEmpty && texte.length <= 20000) actions.modifier(j['id'] as String? ?? '', texte);
        case 'supprimer':
          actions.supprimer(j['id'] as String? ?? '');
        case 'etat':
          await _appliquerEtat(j);
        case 'msg_etat':
          await _appliquerEtatMessage(j);
        case 'discussion':
          final d = j['d'] as String? ?? '';
          if (j['op'] == 'supprimer' || j['op'] == 'vider') {
            if (d.startsWith('p:')) actions.supprimerConversation(peer: d.substring(2));
            if (d.startsWith('g:')) actions.supprimerConversation(groupe: d.substring(2));
          }
        case 'groupe':
          await _appliquerGroupe(j);
        case 'profil':
          await _appliquerProfil(j);
        case 'avatars':
          final ids = (j['ids'] as List? ?? const []).whereType<String>().toList();
          if (ids.isNotEmpty) await _pousserAvatars(ids, seul: appareil);
        case 'statut':
          final texte = (j['texte'] as String? ?? '').trim();
          if (texte.isEmpty || texte.length > 700) return true;
          await _repo.sendStatus(texte, media: StatusMedia(backgroundColor: j['fond'] as int?));
          _dernierEtat = null;
          await _pousserEtat();
        case 'statut_vu':
          final id = j['id'] as String? ?? '';
          final auteur = j['auteur'] as String? ?? '';
          if (id.isEmpty) return true;
          StatutsVus.marquer(id);
          if (auteur.isNotEmpty) unawaited(_repo.sendStatusSeen(authorId: auteur, statusId: id).then<void>((_) {}, onError: (Object _) {}));
        case 'statut_reaction':
          final auteur = j['auteur'] as String? ?? '';
          final emoji = j['emoji'] as String? ?? '';
          if (auteur.isEmpty || emoji.isEmpty || emoji.length > 16) return true;
          await _repo.sendStatusFeedback(authorId: auteur, statusId: j['id'] as String? ?? '', emoji: emoji);
        case 'statut_reponse':
          final auteur = j['auteur'] as String? ?? '';
          final texte = (j['texte'] as String? ?? '').trim();
          if (auteur.isEmpty || texte.isEmpty || texte.length > 2000) return true;
          await _repo.sendStatusFeedback(authorId: auteur, statusId: j['id'] as String? ?? '', text: texte);
        case 'frappe':
          final d = j['d'] as String? ?? '';
          if (d.startsWith('p:')) actions.frappe(peer: d.substring(2));
          if (d.startsWith('g:')) actions.frappe(groupe: d.substring(2));
        case 'envoye':
          final d = j['d'] as String? ?? '';
          final texte = j['texte'] as String? ?? '';
          final quand = j['date'];
          if (!d.startsWith('p:') || texte.isEmpty || texte.length > 20000) return true;
          await actions.noterEnvoiAutonome?.call(
            peer: d.substring(2),
            id: j['id'] as String? ?? '',
            texte: texte,
            date: quand is int ? DateTime.fromMillisecondsSinceEpoch(quand) : DateTime.now(),
            reponseA: j['r'] as String?,
          );
        case 'envoyer':
          final d = j['d'] as String? ?? '';
          final texte = (j['texte'] as String? ?? '').trim();
          final id = j['id'] as String?;
          if (texte.isEmpty || texte.length > 20000) return true;
          if (_dernier.any((m) => m.id == id)) return true; // déjà parti
          if (d.startsWith('p:')) {
            final peer = d.substring(2);
            _apprendreContact(peer, j['pseudo'] as String?, j['cle'] as String?);
            await envoyer(peer, texte, id: id, reponseA: j['r'] as String?);
          } else if (d.startsWith('g:')) {
            await envoyerGroupe(d.substring(2), texte, id: id, reponseA: j['r'] as String?);
          }
      }
    } catch (e) {
      debugPrint('[Miroir] demande illisible : $e');
    }
    return true;
  }

  /// Un état de discussion changé sur le web, refait ici avec les mêmes
  /// fonctions que les écrans du téléphone. L'instantané repart aussitôt :
  /// le web reçoit l'état tel que le téléphone l'a réellement appliqué.
  Future<void> _appliquerEtat(Map<String, dynamic> j) async {
    final d = j['d'] as String? ?? '';
    if (!(d.startsWith('p:') || d.startsWith('g:'))) return;
    final cle = d.substring(2);
    if (cle.isEmpty) return;
    final oui = j['valeur'] == true;
    switch (j['champ']) {
      case 'epinglee':
        await StorageService.setConversationPinned(cle, oui);
      case 'archivee':
        await StorageService.setConversationArchived(cle, oui);
        // Une discussion archivée quitte les épinglées, comme sur le web.
        if (oui) await StorageService.setConversationPinned(cle, false);
      case 'sourdine':
        await StorageService.setConversationMuted(cle, oui);
      case 'ephemere':
        final s = j['valeur'];
        if (s is int && s >= 0 && s <= 90 * 24 * 3600) await StorageService.setEphemeralTimer(cle, s);
      case 'bloque':
        if (d.startsWith('p:')) await StorageService.setContactBlocked(cle, oui);
      case 'nonLue':
        await StorageService.setConversationMarkedUnread(cle, oui);
      default:
        return;
    }
    revisionEtat.value++;
    _dernierEtat = null;
    await _pousserEtat();
  }

  /// Un groupe géré depuis le web : les mêmes fonctions que l'écran
  /// d'informations du groupe sur le téléphone, puis la discussion repart
  /// vers le web avec son titre, ses membres et ses admins à jour.
  Future<void> _appliquerGroupe(Map<String, dynamic> j) async {
    final g = j['g'] as String? ?? '';
    final groupe = StorageService.getGroup(g);
    if (groupe == null || !groupe.isActiveMember(_repo.myId)) return;
    switch (j['op']) {
      case 'renommer':
        final titre = (j['titre'] as String? ?? '').trim();
        if (titre.isNotEmpty && titre.length <= 100) await _repo.renameGroup(groupId: g, name: titre);
      case 'description':
        final texte = (j['texte'] as String? ?? '').trim();
        if (texte.length > 1000) return;
        ReglagesGroupes.definir(g, ReglagesGroupes.de(g).copier(description: texte));
        await _repo.diffuserReglagesGroupe(g);
      case 'ajouter':
        for (final p in (j['membres'] as List? ?? const []).whereType<String>().take(50)) {
          if (!groupe.isActiveMember(p)) await _repo.addGroupMember(groupId: g, peerId: p);
        }
      case 'retirer':
        final p = j['membre'] as String? ?? '';
        if (p.isNotEmpty && p != _repo.myId) await _repo.removeGroupMember(groupId: g, peerId: p);
      case 'quitter':
        await _repo.leaveGroup(g);
      // Nommer ou retirer un admin : mêmes règles que sur le téléphone
      // (réservé aux admins ; le dernier admin ne peut pas se retirer).
      case 'admin':
        final p = j['membre'] as String? ?? '';
        if (p.isEmpty) return;
        await _repo.changerRoleMembre(groupId: g, peerId: p == 'moi' ? _repo.myId : p, admin: j['admin'] == true);
      default:
        return;
    }
    await _pousserDiscussion('g:$g');
  }

  /// Le pseudo changé sur le web : enregistré et annoncé comme depuis les
  /// réglages du téléphone.
  /// Ma photo telle que le navigateur la reçoit : `photo` (JPEG en
  /// base64), ou `sansPhoto` si je n'en ai pas.
  Map<String, dynamic> _maPhoto() {
    final octets = AvatarService.mesOctets();
    return octets == null ? {'sansPhoto': true} : {'photo': base64.encode(octets)};
  }

  /// Le profil changé depuis Droplet Web : pseudo, photo, ou retrait de
  /// la photo.
  ///
  /// ⚠️ LA PHOTO CHOISIE SUR LE WEB DEVIENT CELLE DU COMPTE. Avant, elle
  /// restait dans le navigateur : mes contacts (et mon propre téléphone)
  /// ne la voyaient jamais. C'est le téléphone qui la distribue, exactement
  /// comme une photo choisie dans ses Réglages : « hello » portant la
  /// nouvelle empreinte, et envoi direct aux contacts joints par Internet.
  Future<void> _appliquerProfil(Map<String, dynamic> j) async {
    final moi = StorageService.currentUser;
    if (moi == null) return;
    var pseudo = moi.pseudo;
    var avatar = moi.avatarUrl;
    final changes = <String, dynamic>{};

    final p = (j['pseudo'] as String? ?? '').trim();
    if (p.isNotEmpty && p.length <= 40 && p != moi.pseudo) {
      pseudo = p;
      changes['pseudo'] = p;
    }

    var photoChangee = false;
    final b64 = j['photo'];
    if (b64 is String && b64.isNotEmpty) {
      Uint8List? octets;
      try {
        octets = base64.decode(b64);
      } catch (_) {}
      // Une vignette JPEG (le navigateur la réduit à 320 × 320 avant
      // l'envoi) : on refuse tout ce qui n'en a pas l'allure.
      final jpeg = octets != null && octets.length > 3 && octets[0] == 0xFF && octets[1] == 0xD8;
      if (jpeg && octets.length <= 400 * 1024 && AvatarService.empreinteDe(octets) != AvatarService.monEmpreinte()) {
        final nom = await AvatarService.enregistrer(octets);
        if (nom != null) {
          avatar = nom;
          photoChangee = true;
          changes['photo'] = b64;
        }
      }
    } else if (j['retirerPhoto'] == true && moi.avatarUrl != null) {
      await AvatarService.supprimer();
      avatar = null;
      photoChangee = true;
      changes['sansPhoto'] = true;
    }

    if (changes.isEmpty) return;
    await StorageService.saveUser(DropletUserModel(id: moi.id, pseudo: pseudo, publicKey: moi.publicKey, avatarUrl: avatar));
    if (photoChangee) AvatarService.oublierMonEmpreinte();
    // Le « hello » porte le pseudo et l'empreinte de la photo : les
    // contacts proches voient le changement et redemandent la photo.
    unawaited(_repo.sendHello().then<void>((_) {}, onError: (Object _) {}));
    // Le « hello » ne franchit pas Internet : la photo est poussée aux
    // contacts éloignés directement.
    if (photoChangee) {
      unawaited(_repo.diffuserMaPhotoAuxContacts().then<void>((_) {}, onError: (Object _) {}));
    }
    // Les autres navigateurs liés suivent.
    for (final a in _appareils()) {
      await _deposer(a, {'v': 1, 'profil': changes});
    }
  }

  /// Ma photo a changé sur le téléphone : les navigateurs liés suivent.
  Future<void> annoncerMaPhoto() async {
    for (final a in _appareils()) {
      await _deposer(a, {'v': 1, 'profil': _maPhoto()});
    }
  }


  /// Une discussion seule (sans message), pour en rafraîchir le titre, les
  /// membres et les admins sur le web.
  Future<void> _pousserDiscussion(String d) async {
    final contacts = <String, Map<String, dynamic>>{};
    final disc = _discussion(d, _repo.myId, contacts);
    for (final a in _appareils()) {
      await _deposer(a, {
        'v': 1,
        'contacts': contacts.values.toList(),
        'discussions': [disc],
      });
    }
  }

  /// Un message épinglé ou mis en favori sur le web.
  Future<void> _appliquerEtatMessage(Map<String, dynamic> j) async {
    final id = j['id'] as String? ?? '';
    final m = _dernier.where((x) => x.id == id).firstOrNull;
    if (m == null) return;
    final oui = j['valeur'] == true;
    switch (j['champ']) {
      case 'epingle':
        await actions.epingler(id, oui);
      case 'important':
        if (MessagesImportants.estImportant(id) != oui) MessagesImportants.basculer(_versImportant(m));
      default:
        return;
    }
    _dernierEtat = null;
    await _pousserEtat();
  }

  MessageImportant _versImportant(MeshMessage m) {
    final moi = _repo.myId;
    return MessageImportant(
      id: m.id,
      contenu: m.content,
      type: m.type,
      horodatage: m.timestamp.millisecondsSinceEpoch,
      deMoi: m.senderId == moi,
      auteur: m.authorPseudo,
      peerId: m.groupId == null ? (m.senderId == moi ? m.targetId : m.senderId) : null,
      groupId: m.groupId,
      nomFichier: m.fileName,
    );
  }

  /// Un morceau d'un fichier écrit sur le web. Le dernier arrivé, le
  /// téléphone envoie le fichier comme s'il avait été choisi ici : même
  /// identifiant, même légende, même réponse.
  Future<void> _morceauRecu(Map<String, dynamic> j) async {
    final id = j['id'] as String? ?? '';
    final n = j['n'] as int? ?? 0;
    final i = j['i'] as int? ?? -1;
    final taille = j['taille'] as int? ?? 0;
    if (id.isEmpty || n <= 0 || i < 0 || i >= n || taille > maxFichier || n > maxFichier ~/ tailleMorceau + 2) return;
    if (_dernier.any((m) => m.id == id)) return; // déjà parti
    // Les assemblages abandonnés (navigateur fermé en cours d'envoi) ne
    // restent pas en mémoire.
    _assemblages.removeWhere((_, a) => DateTime.now().difference(a.debut) > const Duration(minutes: 15));
    final a = _assemblages.putIfAbsent(id, () => _Assemblage(n));
    if (a.n != n) return;
    try {
      a.morceaux[i] = base64Decode(j['b64'] as String? ?? '');
    } catch (_) {
      return;
    }
    if (i == 0 || a.entete.isEmpty) a.entete = j;
    if (!a.complet) return;
    _assemblages.remove(id);
    final octets = BytesBuilder(copy: false);
    for (final m in a.morceaux) {
      octets.add(m!);
    }
    final e = a.entete;
    if (e['but'] == 'statut') {
      await _publierStatutFichier(e, octets.takeBytes());
      return;
    }
    final d = e['d'] as String? ?? '';
    if (d.startsWith('p:')) _apprendreContact(d.substring(2), e['pseudo'] as String?, e['cle'] as String?);
    final legende = (e['legende'] as String? ?? '').trim();
    // Déjà parti directement depuis le web (téléphone éteint à ce moment-là) :
    // on l'inscrit dans l'historique, sans le renvoyer au contact.
    if (e['deja'] == true && d.startsWith('p:')) {
      await actions.noterFichierAutonome?.call(
        peer: d.substring(2),
        id: id,
        nom: (e['nom'] as String? ?? 'fichier').replaceAll(RegExp(r'[/\\]'), '_'),
        mime: e['mime'] as String? ?? 'application/octet-stream',
        octets: octets.takeBytes(),
        legende: legende.isEmpty ? null : legende,
        reponseA: e['r'] as String?,
      );
      return;
    }
    await envoyerFichier(
      cible: d.startsWith('p:') ? d.substring(2) : null,
      groupe: d.startsWith('g:') ? d.substring(2) : null,
      id: id,
      nom: (e['nom'] as String? ?? 'fichier').replaceAll(RegExp(r'[/\\]'), '_'),
      mime: e['mime'] as String? ?? 'application/octet-stream',
      octets: octets.takeBytes(),
      legende: legende.isEmpty ? null : legende,
      reponseA: e['r'] as String?,
    );
  }

  /// Un statut photo, vidéo ou vocal publié depuis le web : il part du
  /// téléphone exactement comme depuis l'éditeur de statut (fichier
  /// d'abord, annonce ensuite), à tous les contacts.
  Future<void> _publierStatutFichier(Map<String, dynamic> e, Uint8List octets) async {
    final kind = StatusMediaKind.fromName(e['k'] as String?);
    if (kind == StatusMediaKind.none) return;
    final nom = (e['nom'] as String? ?? 'statut').replaceAll(RegExp(r'[/\\]'), '_');
    final mime = e['mime'] as String? ?? 'application/octet-stream';
    final fileId = await _repo.sendStatusFile(fileName: nom, bytes: octets, mimeType: mime);
    final ms = e['ms'];
    await _repo.sendStatus(
      (e['texte'] as String? ?? '').trim(),
      media: StatusMedia(
        kind: kind,
        fileId: fileId,
        fileName: nom,
        mimeType: mime,
        durationMs: kind == StatusMediaKind.voice && ms is int ? ms : null,
        backgroundColor: kind == StatusMediaKind.voice ? e['fond'] as int? : null,
      ),
    );
    _dernierEtat = null;
    await _pousserEtat();
  }

  /// Le contenu d'un fichier, demandé par le web : lu sur le disque du
  /// téléphone, envoyé en morceaux chiffrés dans la file de ce navigateur.
  Future<void> _envoyerContenu(AppareilLie appareil, String id) async {
    final m = _dernier.where((x) => x.id == id || x.fileId == id).firstOrNull;
    String? chemin;
    if (m != null && m.fileName != null) {
      chemin = await StorageService.getSharedFilePath(m.fileId ?? m.id, m.fileName!);
    } else {
      // L'identifiant d'un statut : sa photo, sa vidéo ou son vocal.
      final media = StorageService.getStatusMedia(id);
      if (media.hasMedia && media.fileName != null) {
        chemin = await StorageService.getSharedFilePath(media.fileId!, media.fileName!);
      }
    }
    if (chemin == null) return;
    final octets = await File(chemin).readAsBytes();
    if (octets.length > maxFichier) return;
    final n = (octets.length / tailleMorceau).ceil().clamp(1, 1 << 20);
    for (var i = 0; i < n; i++) {
      final fin = ((i + 1) * tailleMorceau).clamp(0, octets.length);
      await _deposer(appareil, {
        'v': 1,
        'fichier': {'id': id, 'i': i, 'n': n, 'b64': base64Encode(octets.sublist(i * tailleMorceau, fin))},
      });
    }
  }

  /// Un contact trouvé sur le web par son pseudo : le téléphone apprend sa
  /// clé et son nom avant de lui écrire.
  void _apprendreContact(String peerId, String? pseudo, String? cle) {
    if (cle != null && cle.isNotEmpty) _repo.apprendreCleMailbox(peerId, cle);
    if (pseudo == null || pseudo.trim().isEmpty) return;
    final fiche = StorageService.getPeerRecord(peerId);
    if (fiche == null) {
      unawaited(StorageService.upsertPeer(PeerRecord(
        peerId: peerId,
        pseudo: pseudo.trim(),
        lastSeen: DateTime.now(),
        publicKey: cle,
        transports: const ['tor'],
      )));
    } else if (fiche.pseudo.isEmpty || fiche.pseudo == peerId) {
      unawaited(StorageService.upsertPeer(fiche.copyWith(pseudo: pseudo.trim())));
    }
  }

  // ── La mise en forme ────────────────────────────────────────────────

  Map<String, dynamic>? _lot(List<MeshMessage> messages, {bool nonLus = false}) {
    final moi = _repo.myId;
    final contacts = <String, Map<String, dynamic>>{};
    final discussions = <String, Map<String, dynamic>>{};
    final dtos = <Map<String, dynamic>>[];
    // Une discussion verrouillée sur le téléphone ne part pas sur le web.
    final verrouillees = StorageService.getLockedConversations();
    for (final m in messages) {
      final d = _discussionDe(m, moi);
      if (d == null) continue;
      if (verrouillees.contains(d.substring(2))) continue;
      final dto = _message(m, d, moi);
      if (dto == null) continue;
      dtos.add(dto);
      discussions.putIfAbsent(d, () => _discussion(d, moi, contacts));
      if (m.senderId != null && m.senderId != moi) {
        contacts.putIfAbsent(m.senderId!, () => {'id': m.senderId, 'pseudo': _pseudo(m.senderId!, m)});
      }
    }
    if (dtos.isEmpty) return null;
    // Les non-lus voyagent avec chaque lot : une discussion lue sur le
    // téléphone perd aussi son badge sur le web.
    for (final e in discussions.entries) {
      e.value['nonLus'] = _nonLus(e.key, moi);
    }
    return {
      'v': 1,
      'contacts': contacts.values.toList(),
      'discussions': discussions.values.toList(),
      'messages': dtos,
    };
  }

  static String? _discussionDe(MeshMessage m, String moi) {
    if (m.groupId != null) return 'g:${m.groupId}';
    final peer = m.senderId == moi ? m.targetId : m.senderId;
    if (peer == null || peer.isEmpty) return null; // diffusion mesh
    return 'p:$peer';
  }

  Map<String, dynamic> _discussion(String d, String moi, Map<String, Map<String, dynamic>> contacts) {
    if (d.startsWith('g:')) {
      final g = StorageService.getGroup(d.substring(2));
      final membres = (g?.members ?? const [])
          .where((x) => x.removedAt == null && x.peerId != moi)
          .map((x) => x.peerId)
          .toList();
      for (final p in membres) {
        contacts.putIfAbsent(p, () => {'id': p, 'pseudo': _pseudo(p, null)});
      }
      // Les admins : « moi » si je le suis (le web ne connaît pas mon id).
      final admins = [
        for (final x in g?.activeMembers ?? const <GroupMemberRecord>[])
          if (x.isAdmin) x.peerId == moi ? 'moi' : x.peerId,
      ];
      return {
        'id': d,
        'type': 'groupe',
        'titre': g?.name ?? 'Groupe',
        'membres': membres,
        'admins': admins,
        'description': ReglagesGroupes.de(d.substring(2)).description,
      };
    }
    final peer = d.substring(2);
    contacts.putIfAbsent(peer, () => {'id': peer, 'pseudo': _pseudo(peer, null)});
    return {'id': d, 'type': 'directe', 'titre': _pseudo(peer, null), 'membres': [peer]};
  }

  static String _pseudo(String peerId, MeshMessage? m) {
    final fiche = StorageService.getPeerRecord(peerId)?.pseudo;
    if (fiche != null && fiche.isNotEmpty && fiche != peerId) return fiche;
    if (m != null && m.senderId == peerId && m.authorPseudo.isNotEmpty && m.authorPseudo != peerId) return m.authorPseudo;
    return peerId.length > 8 ? '${peerId.substring(0, 8)}…' : peerId;
  }

  int _nonLus(String d, String moi) => _dernier
      .where((m) => _discussionDe(m, moi) == d && m.senderId != moi && m.readAt == null)
      .length
      .clamp(0, 99);

  static Map<String, dynamic>? _message(MeshMessage m, String d, String moi) {
    if (m.type == 'appel' || m.type == 'call' || m.type == 'mesh' || m.type == 'warning') return null;
    var texte = m.content;
    Map<String, dynamic>? fichier;
    if (m.type == 'file') {
      // Le fichier lui-même : le web l'affiche (photo, vocal, vidéo,
      // document) et en demande le contenu quand il en a besoin.
      final legende = m.content.trim();
      texte = legende == m.fileName ? '' : legende;
      fichier = {
        'id': m.id,
        'nom': m.fileName ?? 'fichier',
        'mime': (m.fileMimeType ?? '').split(';').first,
        'taille': m.fileSize ?? 0,
      };
    }
    if (texte.trim().isEmpty && fichier == null) return null;
    final deMoi = m.senderId == moi;
    return {
      'id': m.id,
      'd': d,
      'a': deMoi ? 'moi' : (m.senderId ?? ''),
      'texte': texte,
      'date': m.timestamp.toUtc().toIso8601String(),
      'statut': !deMoi
          ? 'lu'
          : switch (m.status) {
              MessageStatus.failed => 'echec',
              MessageStatus.sending || MessageStatus.pending => 'envoi',
              MessageStatus.sent => m.readAt != null ? 'lu' : (m.deliveryCount > 0 ? 'recu' : 'envoye'),
            },
      'r': ?m.replyToId,
      if (m.editedAt != null) 'modifie': true,
      'f': ?fichier,
      if (m.reactions.isNotEmpty) 'reactions': m.reactions,
    };
  }

  static String _empreinte(MeshMessage m) =>
      '${m.status.index}|${m.deliveryCount > 0}|${m.readAt != null}|${m.content.length}|${m.content.hashCode}|${m.editedAt?.millisecondsSinceEpoch}|${m.reactions.join(',')}';

  static DateTime _plusRecent(List<MeshMessage> l) =>
      l.fold(DateTime(2000), (a, m) => m.timestamp.isAfter(a) ? m.timestamp : a);

  // ── Le chiffrement et la boîte ──────────────────────────────────────

  List<AppareilLie> _appareils() => AppareilsLies.liste().where((a) => a.cle != null).toList();

  Future<SecretKey?> _cle(AppareilLie a) async {
    final deja = _cles[a.id];
    if (deja != null) return deja;
    try {
      final k = await CryptoService.cleAppareil(base64Decode(a.cle!));
      if (k != null) _cles[a.id] = k;
      return k;
    } catch (_) {
      return null;
    }
  }

  /// [notifier] : ce lot contient un message reçu — la boîte réveille
  /// alors le navigateur par une notification, même onglet fermé (`nt: 1`,
  /// lu en clair par la boîte ; le contenu, lui, reste chiffré).
  Future<void> _deposer(AppareilLie a, Map<String, dynamic> lot, {bool notifier = false}) async {
    // Chaque contact envoyé au web porte l'EMPREINTE de sa photo de
    // profil (16 caractères, ou rien) : le web demande la photo elle-même
    // (`avatars`) quand il ne l'a pas, ou quand elle a changé.
    final contacts = lot['contacts'];
    if (contacts is List) {
      for (final c in contacts) {
        if (c is Map && c['id'] is String && !c.containsKey('av')) {
          final av = AvatarService.empreintePair(c['id'] as String);
          if (av != null && AvatarService.cheminPair(c['id'] as String) != null) c['av'] = av;
        }
      }
    }
    final k = await _cle(a);
    if (k == null) return;
    try {
      final boite = await AesGcm.with256bits().encrypt(utf8.encode(jsonEncode(lot)), secretKey: k);
      await _repo.transport.storeMailboxMessage(
        toPeerId: a.id,
        encryptedPayload: jsonEncode({
          'w': 1,
          if (notifier) 'nt': 1,
          'c': base64Encode([...boite.cipherText, ...boite.mac.bytes]),
          'n': base64Encode(boite.nonce),
        }),
      );
    } catch (e) {
      debugPrint('[Miroir] dépôt vers ${a.nom} impossible : $e');
    }
  }

  Future<String?> _dechiffrer(AppareilLie a, String? c, String? n) async {
    if (c == null || n == null) return null;
    final k = await _cle(a);
    if (k == null) return null;
    try {
      final octets = base64Decode(c);
      if (octets.length < 17) return null;
      final clair = await AesGcm.with256bits().decrypt(
        SecretBox(octets.sublist(0, octets.length - 16), nonce: base64Decode(n), mac: Mac(octets.sublist(octets.length - 16))),
        secretKey: k,
      );
      return utf8.decode(clair);
    } catch (_) {
      return null;
    }
  }

  void oublierCle(String appareilId) => _cles.remove(appareilId);
}
