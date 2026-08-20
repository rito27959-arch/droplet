// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LA PHOTO DE PROFIL : la choisir, la réduire, la ranger.
//
// Droplet n'a ni compte ni serveur. Une photo de profil ne peut donc pas
// être « téléversée » : elle est un fichier posé dans le dossier de
// l'application, et rien d'autre.
//
// ── ⚠️ POURQUOI ON NE STOCKE JAMAIS LA PHOTO D'ORIGINE ────────────────
//
// C'est la règle la plus importante de ce fichier, et elle n'est pas
// négociable.
//
// Une photo prise avec un téléphone récent fait douze millions de
// pixels. Décodée en mémoire pour être affichée, elle occupe environ
// 48 Mo — pour un rond de quarante-huit points de côté. Droplet a déjà
// été tué par un `OutOfMemoryError` en lisant un fichier, et vise des
// téléphones de 2 Go (voir `DeviceProfile`). Garder l'original pour
// dessiner une pastille serait une faute grave, pas une négligence.
//
// Deux chemins d'entrée, tous deux bornés :
//
//   1. LA GALERIE (chemin normal) — on demande au système une VIGNETTE
//      carrée de 320 points. Android la produit lui-même, déjà rognée et
//      compressée en JPEG : une vingtaine de kilo-octets, et l'original
//      n'est jamais chargé dans notre processus.
//
//   2. UN FICHIER QUELCONQUE (chemin de secours) — on décode à
//      résolution RÉDUITE (`targetWidth`), ce qui borne la mémoire dès
//      le décodage, puis on rogne au carré et on ré-encode en 320×320.
//      Décoder d'abord et redimensionner ensuite reviendrait à faire
//      exactement ce qu'on cherche à éviter.
//
// ── ⚠️ POURQUOI LE NOM DE FICHIER CHANGE À CHAQUE ENREGISTREMENT ──────
//
// Flutter garde les images décodées dans un cache indexé par le chemin
// du fichier. Réécrire toujours `avatar.jpg` afficherait donc l'ANCIENNE
// photo après un changement, jusqu'au prochain redémarrage — un défaut
// qui donne l'impression que l'enregistrement a échoué.
//
// Chaque photo reçoit donc un nom neuf (`avatar_<horodatage>.jpg`), et
// les précédentes sont effacées dans la foulée. Le dossier ne contient
// jamais plus d'un fichier.
//
// ── ⚠️ ON ENREGISTRE UN NOM, PAS UN CHEMIN ───────────────────────────
//
// `DropletUserModel.avatarUrl` ne contient que le NOM du fichier. Le
// dossier de données d'une application Android n'est pas garanti stable
// d'une installation à l'autre ; un chemin absolu enregistré en base
// finirait par pointer dans le vide après une restauration de
// sauvegarde. Le nom, lui, reste valable.
// ============================================================================

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

class AvatarService {
  AvatarService._();

  /// Le côté de la photo enregistrée, en pixels.
  ///
  /// 320 et pas davantage : le plus grand avatar affiché par Droplet
  /// fait 60 points de rayon, soit 120 points de côté — 360 pixels sur
  /// un écran à trois fois la densité. Au-delà, on stockerait des
  /// pixels que personne ne verra jamais.
  static const int cote = 320;

  /// Le dossier où vit la photo, mis en cache au démarrage.
  static Directory? _dossier;

  /// À appeler une fois au lancement, avant tout affichage d'avatar.
  static Future<void> initialiser() async {
    try {
      final base = await getApplicationDocumentsDirectory();
      final d = Directory('${base.path}/profil');
      if (!d.existsSync()) d.createSync(recursive: true);
      _dossier = d;
    } catch (e) {
      // Sans dossier, la photo de profil n'existe simplement pas : le
      // reste de l'application continue avec les initiales.
      debugPrint('[Avatar] dossier indisponible: $e');
    }
  }

  /// Le chemin absolu d'une photo à partir du nom enregistré en base.
  ///
  /// Renvoie `null` si le nom est vide, si le dossier n'a pas pu être
  /// ouvert, ou si le fichier a disparu — ce dernier cas étant celui
  /// d'une sauvegarde restaurée sur un autre appareil. L'appelant
  /// retombe alors sur l'initiale, sans erreur ni case vide.
  static String? chemin(String? nom) {
    final d = _dossier;
    if (nom == null || nom.isEmpty || d == null) return null;
    final f = File('${d.path}/$nom');
    return f.existsSync() ? f.path : null;
  }

  /// Extrait une vignette carrée d'un média de la galerie.
  ///
  /// C'est le système qui rogne et compresse : notre processus ne voit
  /// jamais l'image d'origine.
  static Future<Uint8List?> vignetteDe(AssetEntity asset) async {
    try {
      return await asset.thumbnailDataWithSize(ThumbnailSize.square(cote));
    } catch (e) {
      debugPrint('[Avatar] vignette illisible: $e');
      return null;
    }
  }

  /// Réduit un fichier image quelconque à une vignette carrée.
  ///
  /// ⚠️ `targetWidth` sur le CODEC, et pas un redimensionnement après
  /// coup : c'est ce qui empêche la photo d'origine d'exister en
  /// mémoire, ne serait-ce qu'un instant.
  static Future<Uint8List?> reduireFichier(File fichier) async {
    try {
      final octets = await fichier.readAsBytes();
      final codec = await ui.instantiateImageCodec(
        octets,
        // Deux fois le côté final : de la marge pour que le rognage
        // carré ne parte pas d'une image déjà plus petite que la cible.
        targetWidth: cote * 2,
      );
      final frame = await codec.getNextFrame();
      final source = frame.image;

      // Rognage centré : on prend le plus grand carré possible au milieu
      // de l'image. C'est ce que fait tout le monde, et c'est ce à quoi
      // on s'attend quand on choisit un portrait.
      final petitCote =
          math.min(source.width, source.height).toDouble();
      final zone = ui.Rect.fromCenter(
        center: ui.Offset(source.width / 2, source.height / 2),
        width: petitCote,
        height: petitCote,
      );

      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.drawImageRect(
        source,
        zone,
        ui.Rect.fromLTWH(0, 0, cote.toDouble(), cote.toDouble()),
        ui.Paint()..filterQuality = ui.FilterQuality.medium,
      );
      final image = await recorder.endRecording().toImage(cote, cote);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);

      source.dispose();
      image.dispose();
      codec.dispose();

      return data?.buffer.asUint8List();
    } catch (e) {
      debugPrint('[Avatar] réduction impossible: $e');
      return null;
    }
  }

  /// Enregistre la photo et renvoie le NOM du fichier créé.
  ///
  /// Les photos précédentes sont effacées : le dossier ne garde jamais
  /// qu'un seul fichier.
  static Future<String?> enregistrer(Uint8List octets) async {
    final d = _dossier;
    if (d == null) return null;
    try {
      await _viderLeDossier(d);
      final nom = 'avatar_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File('${d.path}/$nom').writeAsBytes(octets, flush: true);
      return nom;
    } catch (e) {
      debugPrint('[Avatar] enregistrement impossible: $e');
      return null;
    }
  }

  /// Retire la photo de profil.
  static Future<void> supprimer() async {
    final d = _dossier;
    if (d == null) return;
    await _viderLeDossier(d);
  }

  static Future<void> _viderLeDossier(Directory d) async {
    try {
      for (final e in d.listSync()) {
        if (e is File) e.deleteSync();
      }
    } catch (e) {
      debugPrint('[Avatar] nettoyage partiel: $e');
    }
  }

  /// Les derniers médias de la galerie, pour le choix de la photo.
  ///
  /// Renvoie une liste vide si l'accès est refusé — la grille disparaît
  /// alors, et il reste le bouton « Parcourir ». Réclamer une permission
  /// que quelqu'un vient de refuser est le meilleur moyen qu'il la
  /// refuse pour toujours.
  static Future<List<AssetEntity>> recents({int combien = 40}) async {
    try {
      final etat = await PhotoManager.requestPermissionExtend();
      if (!etat.hasAccess) return const [];
      final albums = await PhotoManager.getAssetPathList(
        type: RequestType.image,
        onlyAll: true,
      );
      if (albums.isEmpty) return const [];
      return await albums.first.getAssetListPaged(page: 0, size: combien);
    } catch (e) {
      debugPrint('[Avatar] galerie indisponible: $e');
      return const [];
    }
  }
}
