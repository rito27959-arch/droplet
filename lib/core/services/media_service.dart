// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// La télécommande de deux services rendus par Android lui-même : COUPER
// UNE VIDÉO et ENREGISTRER UN FICHIER DANS LA GALERIE.
//
// Le travail se fait côté natif (`MediaBridge.kt`) ; ici on ne fait que
// l'appeler. Voir ce fichier-là pour le détail — en résumé :
//
//   • Couper une vidéo demande de réécrire son conteneur. La solution
//     habituelle (embarquer ffmpeg) ajouterait des dizaines de
//     méga-octets à l'application. Android sait recopier les images
//     telles quelles, sans les décoder : c'est instantané, sans perte,
//     et sans dépendance.
//
//   • Depuis Android 10, une application n'écrit plus librement dans les
//     dossiers publics. Il faut passer par `MediaStore`, qui range le
//     fichier au bon endroit ET prévient la galerie de son existence.
// ============================================================================

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MediaService {
  MediaService._();

  static const MethodChannel _channel =
      MethodChannel('com.droplet.droplet/media');

  static bool get isSupported => Platform.isAndroid;

  /// Le téléphone est-il trop chaud pour filmer ?
  ///
  /// ⚠️ À PARTIR DU NIVEAU 3, ANDROID COUPE LES ENCODEURS VIDÉO. La
  /// caméra continue d'afficher son aperçu et le micro d'enregistrer,
  /// mais plus une seule image n'atteint l'encodeur : le fichier ne
  /// contient que du son. Sans cette vérification, on ne peut annoncer
  /// que « l'enregistrement n'a rien capturé », ce qui laisse croire à
  /// un défaut de l'application.
  static Future<bool> get isOverheating async {
    if (!isSupported) return false;
    try {
      final level = await _channel.invokeMethod<int>('thermalStatus');
      return level != null && level >= 3;
    } catch (e) {
      debugPrint('[Média] état thermique indisponible: $e');
      return false;
    }
  }

  /// Ouvre le clavier téléphonique avec un code opérateur déjà écrit.
  ///
  /// La personne n'a plus qu'à appuyer sur appeler. On ne compose PAS à
  /// sa place : cela demanderait la permission `CALL_PHONE`, hors de
  /// proportion pour ce service — et il vaut mieux qu'elle voie ce qui
  /// part avant que ça parte.
  static Future<bool> composerUssd(String code) async {
    if (!isSupported) return false;
    try {
      return await _channel
              .invokeMethod<bool>('composerUssd', {'code': code}) ??
          false;
    } catch (e) {
      debugPrint('[Média] code non composé: $e');
      return false;
    }
  }

  /// Ouvre un lien avec l'application qui sait le traiter.
  ///
  /// Renvoie `false` si rien ne peut l'ouvrir — WhatsApp absent, par
  /// exemple. L'appelant doit alors proposer le chemin habituel plutôt
  /// que de laisser l'utilisateur devant un bouton qui n'a rien fait.
  static Future<bool> ouvrirLien(String url) async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('ouvrirLien', {'url': url}) ??
          false;
    } catch (e) {
      debugPrint('[Média] lien non ouvert: $e');
      return false;
    }
  }

  /// Le chemin du fichier d'installation de Droplet sur ce téléphone.
  ///
  /// ── ⚠️ POURQUOI C'EST ICI ET PAS AILLEURS ────────────────────────
  ///
  /// Droplet fonctionne sans internet, mais jusqu'ici il en fallait pour
  /// se le PROCURER. C'est un défaut sérieux : dans les endroits où
  /// cette application a le plus de sens — pas de réseau, données mobiles
  /// chères — le premier obstacle n'est pas de faire marcher le maillage,
  /// c'est d'être deux à l'avoir installé.
  ///
  /// Ce chemin permet d'envoyer Droplet lui-même par Bluetooth, par
  /// Wi-Fi Direct ou sur une carte mémoire. Personne n'a besoin de
  /// connexion, à aucun moment.
  ///
  /// Renvoie `null` hors Android, ou si le système refuse de dire où il
  /// a rangé l'application.
  static Future<String?> get installerPath async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('installerPath');
    } catch (e) {
      debugPrint('[Média] chemin d\'installation indisponible: $e');
      return null;
    }
  }

  /// Durée d'une vidéo, ou `null` si elle est illisible.
  static Future<Duration?> videoDuration(String path) async {
    if (!isSupported) return null;
    try {
      final ms = await _channel.invokeMethod<int>(
        'videoDurationMs',
        {'path': path},
      );
      if (ms == null || ms < 0) return null;
      return Duration(milliseconds: ms);
    } catch (e) {
      debugPrint('[Média] durée illisible: $e');
      return null;
    }
  }

  /// Ne garde que les [max] premières secondes de la vidéo.
  ///
  /// Renvoie le chemin du fichier à utiliser — le fichier raccourci si
  /// une coupe a eu lieu, le fichier d'origine sinon.
  ///
  /// ⚠️ La coupe tombe sur une image-clé, donc un peu AVANT la limite
  /// demandée. Une vidéo compressée ne contient des images complètes que
  /// de loin en loin ; couper ailleurs laisserait la fin en bouillie. La
  /// durée obtenue est donc toujours inférieure ou égale à la limite,
  /// ce qui est le sens de la contrainte.
  static Future<String> trimVideo(String path, Duration max) async {
    if (!isSupported) return path;
    try {
      final result = await _channel.invokeMethod<String>('trimVideo', {
        'path': path,
        'maxMs': max.inMilliseconds,
      });
      return result ?? path;
    } catch (e) {
      debugPrint('[Média] découpe impossible: $e');
      return path;
    }
  }

  /// Copie un fichier dans la galerie ou les téléchargements du
  /// téléphone. Renvoie le dossier de destination, ou `null` en cas
  /// d'échec.
  static Future<String?> saveToGallery({
    required String path,
    required String name,
    String mimeType = '',
  }) async {
    if (!isSupported) return null;
    try {
      return await _channel.invokeMethod<String>('saveToGallery', {
        'path': path,
        'name': name,
        'mime': mimeType,
      });
    } catch (e) {
      debugPrint('[Média] enregistrement impossible: $e');
      return null;
    }
  }
}
