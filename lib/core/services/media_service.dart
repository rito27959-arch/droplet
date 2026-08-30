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
import 'package:image/image.dart' as img;

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

  /// Met à jour le widget d'écran d'accueil.
  ///
  /// ⚠️ AUCUN CONTENU DE MESSAGE N'EST TRANSMIS, jamais. Un widget est
  /// visible par quiconque regarde l'écran par-dessus une épaule — dans
  /// un taxi, au marché. Une application dont l'argument est que les
  /// messages ne sortent pas du téléphone ne peut pas les afficher sur
  /// l'écran d'accueil. On ne passe que deux nombres.
  static Future<void> majWidget({
    required int nonLus,
    required int pairs,
  }) async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<bool>('majWidget', {
        'nonLus': nonLus,
        'pairs': pairs,
      });
    } catch (e) {
      debugPrint('[Média] widget non mis à jour: $e');
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

  // ── Compression d'images pour le mesh ──────────────────────────────────
  //
  // Sur un réseau mesh, la bande passante est comptée : le Bluetooth ne
  // transport que 512 octets par paquet, et chaque émission ne dure que
  // quelques millisecondes. Une photo de 10 Mo mettrait des MINUTES à
  // traverser le réseau, bloquant tous les autres messages pendant ce
  // temps. On compresse donc les images volumineuses avant envoi.
  //
  // ⚠️ 10 Mo est un seuil CONSERVATEUR. La plupart des photos modernes
  // font 3-5 Mo. Un fichier >10 Mo est presque toujours une photo RAW,
  // un PNG géant, ou une image non compressée — des cas où la
  // compression est non seulement souhaitable mais nécessaire.

  /// Seuil au-delà duquel une image est compressée (en octets).
  static const int _kImageCompressionThreshold = 10 * 1024 * 1024; // 10 Mo

  /// Taille maximale de la plus grande dimension après redimensionnement.
  /// Les statuts n'ont pas besoin de la résolution originale : sur un
  /// écran de téléphone, 2048px est déjà au-delà de ce qui est visible.
  static const int _kMaxDimension = 2048;

  /// Qualité JPEG de sortie (0-100). 85 est le meilleur compromis
  /// taille/qualité perçue pour des photos de statut.
  static const int _kJpegQuality = 85;

  /// Compresse une image si elle dépasse le seuil [sizeThreshold].
  ///
  /// Renvoie les octets compressés (JPEG) et le nom de fichier suggéré.
  /// Si l'image est déjà sous le seuil ou si la compression échoue,
  /// retourne les octets originaux et le nom d'origine.
  ///
  /// Ne compresse QUE les images (JPEG, PNG, BMP, GIF, TIFF, WebP).
  /// Les vidéos et autres fichiers passent tels quels.
  static Future<({Uint8List bytes, String name})> compressIfNeeded({
    required Uint8List bytes,
    required String fileName,
    String mimeType = '',
  }) async {
    if (bytes.length < _kImageCompressionThreshold) {
      return (bytes: bytes, name: fileName);
    }

    // Déterminer si c'est une image à partir du type MIME ou de l'extension.
    final isImage = _isImageMime(mimeType) || _isImageExtension(fileName);
    if (!isImage) return (bytes: bytes, name: fileName);

    try {
      // Décoder l'image (le paquet `image` gère JPEG, PNG, BMP, GIF, WebP).
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        debugPrint('[Média] décodage impossible pour compression: $fileName');
        return (bytes: bytes, name: fileName);
      }

      // Redimensionner si une dimension dépasse la limite.
      var result = decoded;
      if (result.width > _kMaxDimension || result.height > _kMaxDimension) {
        result = img.copyResize(
          result,
          width: result.width > result.height ? _kMaxDimension : null,
          height: result.height >= result.width ? _kMaxDimension : null,
          interpolation: img.Interpolation.linear,
        );
      }

      // Encoder en JPEG avec la qualité réduite.
      final compressed = img.encodeJpg(result, quality: _kJpegQuality);
      final compressedBytes = Uint8List.fromList(compressed);

      // Ne garder la version compressée si elle est effectivement plus
      // petite — sinon on garde l'original (un PNG simple peut être
      // plus petit qu'un JPEG re-encodé).
      if (compressedBytes.length >= bytes.length) {
        debugPrint('[Média] compression inutile pour $fileName '
            '(${bytes.length} → ${compressedBytes.length} octets)');
        return (bytes: bytes, name: fileName);
      }

      // Remplacer l'extension par .jpg.
      final baseName = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;
      final newName = '$baseName.jpg';

      debugPrint('[Média] image compressée: $fileName '
          '(${_formatSize(bytes.length)} → ${_formatSize(compressedBytes.length)})');
      return (bytes: compressedBytes, name: newName);
    } catch (e) {
      debugPrint('[Média] échec compression $fileName: $e');
      return (bytes: bytes, name: fileName);
    }
  }

  /// Vérifie si le type MIME correspond à une image connue.
  static bool _isImageMime(String mime) {
    final lower = mime.toLowerCase();
    return lower.startsWith('image/');
  }

  /// Vérifie si l'extension du fichier est une image connue.
  static bool _isImageExtension(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    return const {'jpg', 'jpeg', 'png', 'bmp', 'gif', 'tiff', 'tif', 'webp'}
        .contains(ext);
  }

  /// Formate une taille en octets pour l'affichage dans les logs.
  static String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}o';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} Ko';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} Mo';
  }
}
