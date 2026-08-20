// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// CELUI QUI VA CHERCHER CHAQUE MORCEAU DE CARTE, et qui décide où.
//
// Sa règle tient en trois lignes :
//
//   1. La tuile est-elle déjà sur l'appareil ? On la prend, sans réseau.
//   2. Sinon, y a-t-il du réseau ? On la télécharge, on l'affiche, ET on
//      la range pour la prochaine fois.
//   3. Sinon, on affiche une case vide plutôt que de faire échouer la
//      carte entière.
//
// ── Pourquoi Droplet ne télécharge pas les villes d'avance ────────────
//
// Ce serait la solution évidente : un bouton « Télécharger Yaoundé », et
// tout est réglé. Elle est écartée pour une raison qui n'est pas
// technique.
//
// Une ville aux zooms utiles (13 à 16), c'est plusieurs dizaines de
// MILLIERS de tuiles. Les conditions d'utilisation des serveurs de
// tuiles d'OpenStreetMap interdisent explicitement ce genre de
// téléchargement en masse — ce sont des serveurs financés par des dons,
// pas une infrastructure commerciale. Une application publiée qui le
// ferait se ferait bloquer, et à raison.
//
// Droplet garde donc ce que l'utilisateur a RÉELLEMENT regardé. Parcourir
// son quartier une fois, en ligne, suffit à l'avoir hors connexion pour
// de bon. Et pour couvrir une région entière d'avance, l'écran des
// cartes permet d'importer un fichier `.mbtiles` produit ailleurs — le
// format standard, que n'importe quel outil cartographique sait générer.
//
// ── ⚠️ Pourquoi PAS les serveurs d'OpenStreetMap ──────────────────────
//
// Une première version pointait vers `tile.openstreetmap.org`. Le
// premier essai sur un vrai téléphone a renvoyé, sur CHAQUE tuile :
//
//     403 — Access blocked
//     App is not following the tile usage policy of
//     OpenStreetMap's volunteer-run servers
//
// Ce n'était pas une erreur de configuration. Leur politique
// d'utilisation interdit à une APPLICATION DISTRIBUÉE de s'appuyer sur
// ces serveurs, quel que soit le volume : ils sont financés par des dons
// et destinés à l'édition de la carte, pas à alimenter des apps.
//
// Le fond vient donc de CARTO, dont les fonds de carte sont servis par
// un CDN commercial, sans compte ni clé, et prévus pour cet usage. Les
// DONNÉES restent celles d'OpenStreetMap — d'où la double attribution,
// obligatoire, portée en permanence en bas de la carte (voir
// `map_screen.dart`). Ce n'est pas une politesse : c'est la condition
// de la licence ODbL et des conditions de CARTO.
// ============================================================================

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:http/http.dart' as http;

import 'offline_tile_store.dart';

/// Va chercher les tuiles sur l'appareil, puis sur le réseau.
class OfflineFirstTileProvider extends TileProvider {
  OfflineFirstTileProvider({this.allowNetwork = true});

  /// Faux pour rester strictement hors connexion, même si du réseau est
  /// disponible — utile en itinérance ou pour économiser des données.
  final bool allowNetwork;

  /// Le fond de carte sombre de CARTO.
  ///
  /// « dark_all » est choisi plutôt que le fond clair parce qu'il est
  /// DÉJÀ sombre : l'assombrir après coup avec un filtre de couleur,
  /// comme le faisait la version précédente, délave les routes et rend
  /// les noms de rues illisibles.
  static const String _urlTemplate =
      'https://{s}.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png';

  /// Les quatre sous-domaines du CDN.
  ///
  /// Un navigateur — et Flutter — limite le nombre de connexions
  /// simultanées vers un même hôte. Répartir les tuiles sur quatre noms
  /// multiplie d'autant le nombre de téléchargements en parallèle, ce
  /// qui change tout quand vingt cases doivent arriver d'un coup.
  static const List<String> _subdomains = ['a', 'b', 'c', 'd'];

  /// Identifie l'application auprès du serveur, comme le veut l'usage.
  static const String _userAgent = 'Droplet/1.0 (offline mesh messenger)';

  final http.Client _client = http.Client();

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return _OfflineTileImage(
      z: coordinates.z,
      x: coordinates.x,
      y: coordinates.y,
      client: _client,
      allowNetwork: allowNetwork,
    );
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  static String urlFor(int z, int x, int y) => _urlTemplate
      // Le sous-domaine est choisi d'après les coordonnées, et non au
      // hasard : la même tuile garde ainsi toujours la même adresse, et
      // reste donc mise en cache par le système.
      .replaceFirst('{s}', _subdomains[(x + y) % _subdomains.length])
      .replaceFirst('{z}', '$z')
      .replaceFirst('{x}', '$x')
      .replaceFirst('{y}', '$y');

  /// L'en-tête exigé par OpenStreetMap.
  ///
  /// Il ne s'appelle PAS `headers` : `TileProvider` définit déjà un champ
  /// de ce nom, et Dart interdit qu'un membre statique et un membre
  /// d'instance partagent un identifiant.
  static Map<String, String> get requestHeaders =>
      const {'User-Agent': _userAgent};
}

/// L'image d'UNE tuile, résolue à la demande.
@immutable
class _OfflineTileImage extends ImageProvider<_OfflineTileImage> {
  const _OfflineTileImage({
    required this.z,
    required this.x,
    required this.y,
    required this.client,
    required this.allowNetwork,
  });

  final int z;
  final int x;
  final int y;
  final http.Client client;
  final bool allowNetwork;

  @override
  Future<_OfflineTileImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_OfflineTileImage>(this);

  @override
  ImageStreamCompleter loadImage(
      _OfflineTileImage key, ImageDecoderCallback decode) {
    return MultiFrameImageStreamCompleter(
      codec: _load(decode),
      scale: 1,
      debugLabel: 'tuile $z/$x/$y',
    );
  }

  Future<ui.Codec> _load(ImageDecoderCallback decode) async {
    // 1. Sur l'appareil ?
    //
    // ⚠️ Le décodage est protégé, et l'échec entraîne la SUPPRESSION de
    // la tuile fautive. Une tuile peut être arrivée abîmée en base : une
    // réponse tronquée par une coupure réseau au mauvais moment, une
    // écriture interrompue par une fermeture brutale de l'app. Sans ce
    // filet, l'exception remontait jusqu'au `MultiFrameImageStreamCompleter`
    // — et surtout, la tuile abîmée restant en base, elle rejouait
    // l'erreur à chaque affichage de cette zone, indéfiniment. En la
    // jetant, on laisse la case se retélécharger proprement.
    try {
      final local = OfflineTileStore.instance.read(z, x, y);
      if (local != null && local.isNotEmpty) {
        return await decode(await ui.ImmutableBuffer.fromUint8List(local));
      }
    } catch (e) {
      debugPrint('[Cartes] tuile $z/$x/$y illisible en cache, rejetée: $e');
      OfflineTileStore.instance.evict(z, x, y);
    }

    // 2. Sur le réseau ?
    if (allowNetwork) {
      try {
        final response = await client
            .get(
              Uri.parse(OfflineFirstTileProvider.urlFor(z, x, y)),
              headers: OfflineFirstTileProvider.requestHeaders,
            )
            .timeout(const Duration(seconds: 12));

        if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
          // Le décodage passe AVANT le rangement : si le serveur a
          // renvoyé autre chose qu'une image — une page d'erreur, une
          // réponse tronquée par un portail captif — on ne veut surtout
          // pas la garder en base, sinon la zone reste durablement
          // cassée. Une tuile n'est rangée qu'une fois prouvée lisible.
          final codec =
              await decode(await ui.ImmutableBuffer.fromUint8List(
                  response.bodyBytes));
          OfflineTileStore.instance.write(z, x, y, response.bodyBytes);
          return codec;
        }
      } catch (_) {
        // Pas de réseau, ou serveur injoignable : on retombe sur la case
        // vide ci-dessous. Ce n'est pas une erreur à remonter — c'est le
        // fonctionnement normal d'une app hors connexion.
      }
    }

    // 3. Une case vide, plutôt qu'une carte qui refuse de s'afficher.
    return decode(await ui.ImmutableBuffer.fromUint8List(_blankTile));
  }

  /// Un PNG transparent de 1×1, encodé en dur.
  ///
  /// Renvoyer une image vide plutôt que de laisser l'exception remonter
  /// est délibéré : `flutter_map` afficherait sinon une croix d'erreur
  /// sur chaque case manquante, et une carte à moitié couverte
  /// deviendrait un damier d'avertissements.
  static final Uint8List _blankTile = Uint8List.fromList(const [
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  @override
  bool operator ==(Object other) =>
      other is _OfflineTileImage &&
      other.z == z &&
      other.x == x &&
      other.y == y &&
      other.allowNetwork == allowNetwork;

  @override
  int get hashCode => Object.hash(z, x, y, allowNetwork);
}
