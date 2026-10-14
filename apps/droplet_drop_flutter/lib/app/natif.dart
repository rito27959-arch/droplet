// LE PONT VERS ANDROID — ce qu'Android seul sait faire (voir Natif.kt) :
// le point d'accès local, les applications installées, ouvrir et installer
// un fichier reçu. Ailleurs qu'Android, ces fonctions ne sont pas proposées.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

const _canal = MethodChannel('droplet_drop/natif');

/// Un point d'accès local ouvert par cet appareil.
class PointAcces {
  const PointAcces({required this.ssid, required this.motDePasse, required this.securite});

  final String ssid;
  final String motDePasse;

  /// 0 ouvert, 1 WPA2, 2 WPA3 (transition), 3 WPA3.
  final int securite;

  Map<String, Object> json() => {'s': ssid, 'k': motDePasse, 'x': securite};

  static PointAcces? depuis(Object? j) {
    if (j is! Map || j['s'] is! String) return null;
    return PointAcces(ssid: j['s'] as String, motDePasse: (j['k'] as String?) ?? '', securite: (j['x'] as num?)?.toInt() ?? 1);
  }
}

/// Une application installée, prête à partager.
class AppInstallee {
  const AppInstallee({required this.paquet, required this.nom, required this.version, required this.apk, required this.taille, this.icone});

  final String paquet;
  final String nom;
  final String? version;

  /// Le ou les APK (une app découpée en a plusieurs).
  final List<String> apk;
  final int taille;
  final Uint8List? icone;
}

/// Pourquoi le point d'accès n'a pas pu s'ouvrir.
enum EchecPointAcces { autorisation, localisation, partageActif, nonSupporte, autre }

class Natif {
  static bool get android => Platform.isAndroid;

  static int? _version;
  static Future<int> versionAndroid() async => _version ??= (await _canal.invokeMethod<int>('versionAndroid')) ?? 0;

  /// Les autorisations du Wi‑Fi local : « appareils à proximité » (13+),
  /// la localisation avant.
  static Future<bool> autoriserWifi() async {
    if ((await versionAndroid()) >= 33) return (await Permission.nearbyWifiDevices.request()).isGranted;
    return (await Permission.locationWhenInUse.request()).isGranted;
  }

  /// Ouvre un point d'accès local. Rend son nom et son mot de passe, ou la
  /// raison de l'échec.
  static Future<(PointAcces?, EchecPointAcces?)> ouvrirPointAcces() async {
    if ((await versionAndroid()) < 26) return (null, EchecPointAcces.nonSupporte);
    if (!await autoriserWifi()) return (null, EchecPointAcces.autorisation);
    if ((await versionAndroid()) < 33 && !((await _canal.invokeMethod<bool>('localisationActive')) ?? true)) {
      return (null, EchecPointAcces.localisation);
    }
    try {
      final r = (await _canal.invokeMethod<Map<Object?, Object?>>('ouvrirPointAcces'))!;
      final ssid = r['ssid'] as String?;
      if (ssid == null || ssid.isEmpty) return (null, EchecPointAcces.autre);
      return (PointAcces(ssid: ssid, motDePasse: (r['mdp'] as String?) ?? '', securite: (r['securite'] as int?) ?? 1), null);
    } on PlatformException catch (e) {
      if (e.code == 'echec' && e.message == '2') return (null, EchecPointAcces.partageActif);
      if (e.code == 'non_supporte') return (null, EchecPointAcces.nonSupporte);
      return (null, EchecPointAcces.autre);
    }
  }

  static Future<void> fermerPointAcces() async {
    if (android) await _canal.invokeMethod<void>('fermerPointAcces');
  }

  /// Rejoint le point d'accès d'un autre appareil (Android affiche sa
  /// propre confirmation). Vrai une fois connecté.
  static Future<bool> rejoindre(PointAcces p) async {
    if (!android) return false;
    if (!await autoriserWifi()) return false;
    try {
      return (await _canal.invokeMethod<bool>('rejoindrePointAcces', {'ssid': p.ssid, 'mdp': p.motDePasse, 'securite': p.securite})) ?? false;
    } on PlatformException {
      return false;
    }
  }

  static Future<void> quitter() async {
    if (android) await _canal.invokeMethod<void>('quitterPointAcces');
  }

  static Future<void> ouvrirReglagesLocalisation() => _canal.invokeMethod<void>('ouvrirReglagesLocalisation');

  static Future<List<AppInstallee>> applications() async {
    final l = (await _canal.invokeMethod<List<Object?>>('applications')) ?? const [];
    return [
      for (final x in l.cast<Map<Object?, Object?>>())
        AppInstallee(
          paquet: x['paquet'] as String,
          nom: x['nom'] as String,
          version: x['version'] as String?,
          apk: (x['apk'] as List).cast<String>(),
          taille: (x['taille'] as num).toInt(),
          icone: x['icone'] as Uint8List?,
        ),
    ];
  }

  /// Ouvre un fichier reçu (ou installe une app : un APK, ou un dossier
  /// d'APK). Rend « ouvert », « lancee », « autorisation » ou une erreur.
  static Future<String> ouvrir(String chemin) async {
    try {
      return (await _canal.invokeMethod<String>('ouvrir', {'chemin': chemin})) ?? 'ouvert';
    } on PlatformException catch (e) {
      return e.code;
    }
  }

  /// « Téléchargements/Droplet Drop » : là où Android range les fichiers
  /// reçus, visibles dans la galerie et l'app Fichiers.
  static Future<String?> dossierPublic() async => android ? _canal.invokeMethod<String>('dossierPublic') : null;
}
