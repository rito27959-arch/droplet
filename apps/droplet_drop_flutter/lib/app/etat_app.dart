// L'état de l'application : il écoute le moteur Rust et garde ce que les
// écrans affichent. Rien n'est inventé ici : chaque chiffre vient d'un
// événement du moteur.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/couleurs.dart';
import '../src/rust/api/simple.dart' as moteur;
import 'modeles.dart';
import 'natif.dart';

enum Theme3 { systeme, clair, sombre }

class EtatApp extends ChangeNotifier {
  EtatApp._();

  static final EtatApp i = EtatApp._();

  // ── Appareil ─────────────────────────────────────────────────────────
  String nom = '';
  String empreinte = '';
  String courte = '';
  int port = 0;
  List<String> adresses = const [];
  String reception = '';
  bool pret = false;
  String? erreurDemarrage;

  /// La connexion directe ouverte par cet appareil (Android) : un point
  /// d'accès local que les autres rejoignent, sans box ni Internet.
  PointAcces? pointAcces;

  // ── Réglages ─────────────────────────────────────────────────────────
  Theme3 theme = Theme3.systeme;
  Accent accent = Accent.bleu;
  String? langue;
  late SharedPreferences _prefs;

  // ── Ce que le moteur raconte ─────────────────────────────────────────
  final Map<String, AppareilVu> appareils = {};
  final Map<String, Transfert> transferts = {};
  final List<Offre> offres = [];
  final Map<String, EtatSession> sessions = {};
  final Map<String, Session> mesSessions = {};
  final Map<String, (int, int)> preparations = {};

  /// Prévenu à chaque nouvelle offre (la feuille « Accepter / Refuser »).
  final StreamController<Offre> nouvellesOffres = StreamController.broadcast();

  /// Prévenu quand un transfert se termine (confirmation, haptique).
  final StreamController<Transfert> finis = StreamController.broadcast();

  StreamSubscription<String>? _abonnement;

  static String plateforme() {
    if (Platform.isAndroid) return 'android';
    if (Platform.isIOS) return 'ios';
    if (Platform.isMacOS) return 'macos';
    if (Platform.isWindows) return 'windows';
    return 'linux';
  }

  /// Le nom par défaut de l'appareil : celui de la machine sur ordinateur,
  /// le modèle de plateforme sur mobile.
  static String nomParDefaut() {
    final h = Platform.localHostname;
    if (!Platform.isAndroid && !Platform.isIOS && h.isNotEmpty && h != 'localhost') return h.split('.').first;
    return switch (plateforme()) { 'android' => 'Android', 'ios' => 'iPhone', _ => 'Droplet Drop' };
  }

  Future<void> demarrer() async {
    _prefs = await SharedPreferences.getInstance();
    theme = Theme3.values[(_prefs.getInt('theme') ?? 0).clamp(0, 2)];
    accent = Accent.values[(_prefs.getInt('accent') ?? 0).clamp(0, Accent.values.length - 1)];
    langue = _prefs.getString('langue');
    nom = _prefs.getString('nom') ?? nomParDefaut();
    try {
      final donnees = (await getApplicationSupportDirectory()).path;
      reception = _prefs.getString('reception') ?? await _receptionParDefaut();
      // L'ancien dossier par défaut d'Android (privé à l'app) cède la place
      // au dossier public, s'il est utilisable.
      if (Platform.isAndroid && reception.contains('/Android/data/') && _prefs.getBool('reception_choisie') != true) {
        final nouveau = await _receptionParDefaut();
        if (!nouveau.contains('/Android/data/')) {
          reception = nouveau;
          _prefs.setString('reception', nouveau);
        }
      }
      await Directory(reception).create(recursive: true);
      final info = await moteur.demarrer(nom: nom, plateforme: plateforme(), donnees: donnees, reception: reception);
      empreinte = info.empreinte;
      courte = info.courte;
      port = info.port;
      adresses = info.adresses;
      _abonnement = moteur.evenements().listen(_recevoir);
      for (final a in (jsonDecode(moteur.appareils()) as List)) {
        final x = AppareilVu.json((a as Map).cast<String, dynamic>());
        appareils[x.id] = x;
      }
      pret = true;
    } catch (e) {
      erreurDemarrage = '$e';
    }
    notifyListeners();
  }

  /// Le dossier de réception : « Téléchargements/Droplet Drop » sur
  /// ordinateur ; le dossier de l'app sur mobile (visible dans Fichiers
  /// sur iOS, et partageable depuis l'historique).
  static Future<String> _receptionParDefaut() async {
    // Android : « Téléchargements/Droplet Drop », visible dans la galerie et
    // l'app Fichiers — comme Xender. Si on ne peut pas y écrire (Android 9
    // et avant sans l'autorisation), le dossier de l'app.
    if (Platform.isAndroid) {
      final public = await Natif.dossierPublic();
      if (public != null) {
        try {
          await Directory(public).create(recursive: true);
          final essai = File('$public${Platform.pathSeparator}.essai');
          await essai.writeAsString('');
          await essai.delete();
          return public;
        } catch (_) {}
      }
    }
    if (Platform.isAndroid || Platform.isIOS) {
      final d = Platform.isAndroid ? (await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory()) : await getApplicationDocumentsDirectory();
      return '${d.path}${Platform.pathSeparator}Droplet Drop';
    }
    final t = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    return '${t.path}${Platform.pathSeparator}Droplet Drop';
  }

  void _recevoir(String brut) {
    final Map<String, dynamic> e;
    try {
      e = (jsonDecode(brut) as Map).cast<String, dynamic>();
    } catch (_) {
      return;
    }
    switch (e['type']) {
      case 'transfert':
        final t = Transfert.json(e);
        final avant = transferts[t.id];
        transferts[t.id] = t;
        if (t.etat.finale && (avant == null || !avant.etat.finale)) finis.add(t);
      case 'offre':
        final o = Offre(
          id: e['offre'] as String,
          de: Pair.json((e['de'] as Map).cast<String, dynamic>()),
          fichiers: Fichier.liste(e['fichiers']),
          total: (e['total'] as num).toInt(),
        );
        offres.add(o);
        nouvellesOffres.add(o);
      case 'offre_retiree':
        offres.removeWhere((o) => o.id == e['offre']);
      case 'preparation':
        preparations[e['groupe'] as String] = ((e['octets'] as num).toInt(), (e['total'] as num).toInt());
      case 'session':
        final s = EtatSession(
          id: e['session'] as String,
          etat: e['etat'] as String,
          participants: (e['participants'] as num).toInt(),
          termines: (e['termines'] as num).toInt(),
        );
        sessions[s.id] = s;
      case 'appareil_trouve':
        final a = AppareilVu.json((e['appareil'] as Map).cast<String, dynamic>());
        appareils[a.id] = a;
      case 'appareil_perdu':
        appareils.remove(e['id']);
      default:
        return;
    }
    notifyListeners();
  }

  // ── Commandes ────────────────────────────────────────────────────────

  List<Transfert> groupe(String g) => transferts.values.where((t) => t.groupe == g || t.id == g).toList()..sort((a, b) => a.pair.nom.compareTo(b.pair.nom));

  Future<String> envoyer(List<Choisi> fichiers, List<Map<String, dynamic>> cibles) => moteur.envoyer(
        chemins: [for (final f in fichiers) f.chemin],
        noms: [for (final f in fichiers) f.nom],
        cibles: jsonEncode(cibles),
      );

  void repondre(Offre o, bool accepter, {bool toujours = false}) {
    if (accepter && toujours) moteur.definirConfiance(empreinte: o.de.empreinte, confiance: true);
    moteur.repondre(offre: o.id, accepter: accepter);
    offres.remove(o);
    notifyListeners();
  }

  void pause(String id) => moteur.pause(id: id);
  void reprendre(String id) => moteur.reprendre(id: id);
  void annuler(String id) => moteur.annuler(id: id);

  Future<Session> creerSession(List<Choisi> fichiers, int minutes, {bool demarrer = false}) async {
    final j = await moteur.creerSession(
      chemins: [for (final f in fichiers) f.chemin],
      noms: [for (final f in fichiers) f.nom],
      minutes: minutes,
      demarrer: demarrer,
    );
    final s = Session.json((jsonDecode(j) as Map).cast<String, dynamic>());
    mesSessions[s.id] = s;
    notifyListeners();
    return s;
  }

  Future<String> rejoindre(String invitation, {String? adresse}) => moteur.rejoindre(invitation: invitation, adresse: adresse);

  List<EntreeHistorique> historique(String recherche) => [
        for (final e in (jsonDecode(moteur.historique(recherche: recherche)) as List)) EntreeHistorique.json((e as Map).cast<String, dynamic>()),
      ];

  void effacerHistorique([String? id]) {
    moteur.effacerHistorique(id: id);
    notifyListeners();
  }

  // ── Réglages ─────────────────────────────────────────────────────────

  void definirNom(String n) {
    final propre = n.trim();
    if (propre.isEmpty) return;
    nom = propre;
    _prefs.setString('nom', propre);
    moteur.definirNom(nom: propre);
    notifyListeners();
  }

  void definirTheme(Theme3 t) {
    theme = t;
    _prefs.setInt('theme', t.index);
    notifyListeners();
  }

  void definirAccent(Accent a) {
    accent = a;
    _prefs.setInt('accent', a.index);
    notifyListeners();
  }

  void definirLangue(String? l) {
    langue = l;
    if (l == null) {
      _prefs.remove('langue');
    } else {
      _prefs.setString('langue', l);
    }
    notifyListeners();
  }

  void definirReception(String dossier) {
    reception = dossier;
    _prefs.setString('reception', dossier);
    _prefs.setBool('reception_choisie', true);
    moteur.definirReception(dossier: dossier);
    notifyListeners();
  }

  List<String> confiance() => moteur.confiance();

  /// Relit les adresses de l'appareil (un point d'accès vient de s'ouvrir).
  Future<void> rafraichirAdresses() async {
    try {
      final donnees = (await getApplicationSupportDirectory()).path;
      final info = await moteur.demarrer(nom: nom, plateforme: plateforme(), donnees: donnees, reception: reception);
      adresses = info.adresses;
      notifyListeners();
    } catch (_) {}
  }

  /// Ouvre la connexion directe. Rend null si tout va bien, sinon la raison.
  Future<EchecPointAcces?> ouvrirPointAcces() async {
    final (pa, echec) = await Natif.ouvrirPointAcces();
    if (pa == null) return echec ?? EchecPointAcces.autre;
    pointAcces = pa;
    notifyListeners();
    // L'interface du point d'accès reçoit son adresse un instant après.
    for (final attente in const [300, 900, 2000]) {
      await Future<void>.delayed(Duration(milliseconds: attente));
      await rafraichirAdresses();
    }
    return null;
  }

  Future<void> fermerPointAcces() async {
    await Natif.fermerPointAcces();
    pointAcces = null;
    await rafraichirAdresses();
  }

  void retirerConfiance(String fp) {
    moteur.definirConfiance(empreinte: fp, confiance: false);
    notifyListeners();
  }

  @override
  void dispose() {
    _abonnement?.cancel();
    super.dispose();
  }
}

/// « 4,2 Go », « 812 Mo »… (unités décimales, comme les systèmes).
String taille(int octets, {String virgule = ','}) {
  const unites = ['o', 'Ko', 'Mo', 'Go', 'To'];
  var v = octets.toDouble();
  var u = 0;
  while (v >= 1000 && u < unites.length - 1) {
    v /= 1000;
    u++;
  }
  final t = u == 0 || v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
  return '${t.replaceAll('.', virgule)} ${unites[u]}';
}
