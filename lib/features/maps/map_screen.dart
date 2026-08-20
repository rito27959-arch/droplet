// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'ÉCRAN LOCALISATION : une carte, ma position, et celle des personnes
// du réseau qui ont partagé la leur.
//
// ── Ce qui rend cette carte différente d'une carte ordinaire ───────────
//
// Le fond de carte, lui, n'a rien d'original : ce sont les tuiles
// d'OpenStreetMap, gardées sur l'appareil au fur et à mesure (voir
// `offline_tile_provider.dart`).
//
// Ce qui change tout, ce sont les POINTS DESSUS. Ils ne viennent
// d'aucun serveur : chaque position a été relevée par le GPS d'un
// téléphone, chiffrée, puis relayée de proche en proche par le mesh
// jusqu'ici — Bluetooth, Wi-Fi direct, ou en passant par les téléphones
// des autres.
//
//     GPS de Michel  →  chiffré  →  Bluetooth / Wi-Fi  →  relais
//                    →  mon téléphone  →  le point sur cette carte
//
// C'est pour ça que la carte fonctionne quand plus rien d'autre ne
// fonctionne : au moment où on en a le plus besoin, il n'y a ni
// antenne, ni internet, ni serveur — et pourtant on voit où sont les
// autres.
//
// ── Le fond de carte peut manquer, pas les positions ───────────────────
//
// Si la zone n'a jamais été consultée en ligne, les tuiles sont
// absentes et le fond reste vide. Les points, eux, s'affichent quand
// même : savoir que quelqu'un est à 420 m au nord-est reste utile,
// même sans rue dessinée dessous.
// ============================================================================

import 'dart:async';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../core/models/mesh_message.dart';
import '../../core/providers/mesh_provider.dart';
import '../../core/services/storage_service.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_spinner.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_typography.dart';
import '../../shared/widgets/peer_avatar.dart';
import 'offline_tile_provider.dart';
import 'offline_tile_store.dart';

class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();

  /// Le centre par défaut quand on n'a encore ni position ni contact :
  /// une vue large, plutôt qu'un point arbitraire au milieu de l'océan.
  static const LatLng _fallbackCenter = LatLng(3.848, 11.502);

  Position? _me;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<SafetyCheckinRecord>? _checkinSub;

  List<SafetyCheckinRecord> _checkins = [];
  SafetyCheckinRecord? _selected;

  bool _ready = false;

  /// Vrai quand on refuse d'aller chercher les tuiles sur le réseau.
  bool _offlineOnly = false;

  /// LE fournisseur de tuiles — un seul, gardé d'un bout à l'autre de la
  /// vie de l'écran.
  ///
  /// ⚠️ NE JAMAIS le fabriquer dans `build()`. Il possède un client HTTP
  /// (`http.Client`), donc un pool de connexions, donc des descripteurs
  /// de fichiers ouverts. Or `build()` est rappelé à CHAQUE relevé GPS,
  /// à chaque check-in reçu, à chaque tap sur la carte. La version
  /// précédente en créait un neuf à chacun de ces événements : les
  /// téléchargements de tuiles en cours étaient coupés net à chaque
  /// pas de l'utilisateur (d'où des cases qui restaient vides pendant
  /// qu'on marche), et chaque client abandonné emportait ses sockets
  /// avec lui. Sur une longue session, c'est une fuite de descripteurs
  /// que le système finit par sanctionner en tuant le processus.
  late OfflineFirstTileProvider _tiles;

  @override
  void initState() {
    super.initState();
    _tiles = OfflineFirstTileProvider(allowNetwork: !_offlineOnly);
    _checkins = _withLocation(StorageService.getSafetyCheckins());
    _open();
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _checkinSub?.cancel();
    _tiles.dispose();
    // Le contrôleur est FABRIQUÉ ici, donc c'est à cet écran de le
    // refermer : `FlutterMap` ne dispose que les contrôleurs qu'il crée
    // lui-même. Sans cela, chaque ouverture de la carte laissait derrière
    // elle un flux d'événements toujours ouvert.
    _map.dispose();
    super.dispose();
  }

  /// Bascule en ligne / hors connexion.
  ///
  /// Changer de mode change la manière d'aller chercher les tuiles, donc
  /// exige un nouveau fournisseur — c'est le SEUL moment où on en
  /// remplace un, et l'ancien est refermé proprement au passage.
  void _toggleOffline() {
    final ancien = _tiles;
    setState(() {
      _offlineOnly = !_offlineOnly;
      _tiles = OfflineFirstTileProvider(allowNetwork: !_offlineOnly);
    });
    ancien.dispose();
  }

  Future<void> _open() async {
    await OfflineTileStore.instance.init();
    if (!mounted) return;
    setState(() => _ready = true);

    _checkinSub =
        ref.read(meshRepositoryProvider).safetyCheckinEvents.listen((_) {
      if (!mounted) return;
      setState(() =>
          _checkins = _withLocation(StorageService.getSafetyCheckins()));
    });

    await _followMe();
  }

  List<SafetyCheckinRecord> _withLocation(List<SafetyCheckinRecord> all) {
    final myId = ref.read(meshRepositoryProvider).myId;
    return all
        .where((c) => c.peerId != myId && _coordonneesSaines(c))
        .toList()
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
  }

  /// Un relevé de position est-il utilisable tel quel ?
  ///
  /// ⚠️ CE FILTRE N'EST PAS DE LA PARANOÏA — c'est la frontière de
  /// confiance de l'écran.
  ///
  /// Ces coordonnées n'ont pas été mesurées ici : elles arrivent
  /// D'AUTRES APPAREILS, par le mesh, et Droplet n'a pas de serveur
  /// central pour les avoir vérifiées au passage. Un pair au GPS
  /// défaillant, une trame abîmée par une transmission Bluetooth
  /// médiocre, ou simplement quelqu'un qui fabrique un message : rien
  /// n'empêche une latitude de valoir 400, ou `NaN`.
  ///
  /// Et `LatLng`, dans latlong2, est un simple constructeur `const` : il
  /// accepte n'importe quoi sans broncher. C'est plus loin que ça casse
  /// — la projection cartographique fait passer la valeur dans un
  /// logarithme, qui rend l'infini, qui devient une coordonnée d'écran
  /// `NaN`, qui descend jusqu'au moteur de rendu. À ce stade il n'y a
  /// plus de message d'erreur exploitable : juste une carte qui refuse
  /// de s'afficher.
  ///
  /// On écarte donc le relevé ici, à l'entrée, plutôt que de laisser un
  /// pair distant décider si la carte s'affiche.
  static bool _coordonneesSaines(SafetyCheckinRecord c) {
    final lat = c.lat, lon = c.lon;
    if (lat == null || lon == null) return false;
    if (!lat.isFinite || !lon.isFinite) return false;
    // Les pôles EXACTS sont exclus : à ±90°, la projection Web Mercator
    // part à l'infini. Aucune position réelle n'y tombe.
    return lat > -90 && lat < 90 && lon >= -180 && lon <= 180;
  }

  /// Suit ma position en continu, sans jamais la partager : ce qui est
  /// affiché ici ne quitte pas l'appareil. Le partage se fait
  /// explicitement, depuis l'écran Sécurité.
  Future<void> _followMe() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }

      final last = await Geolocator.getLastKnownPosition();
      if (last != null && mounted) {
        setState(() => _me = last);
        _moveTo(LatLng(last.latitude, last.longitude), 15);
      }

      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          // Un relevé tous les dix mètres, pas en continu : sur un
          // téléphone qu'on garde en poche pendant des heures, le GPS
          // est le premier poste de consommation de batterie.
          distanceFilter: 10,
        ),
      ).listen((position) {
        if (!mounted) return;
        // On ne redessine que si la position a VRAIMENT bougé. Le GPS
        // renvoie des relevés très proches les uns des autres même
        // immobile ; redessiner à chacun ferait clignoter la carte et
        // consommerait pour rien.
        final previous = _me;
        if (previous != null &&
            Geolocator.distanceBetween(previous.latitude, previous.longitude,
                    position.latitude, position.longitude) <
                5) {
          return;
        }
        setState(() => _me = position);
      });
    } catch (e) {
      debugPrint('[Carte] position indisponible: $e');
    }
  }

  void _recenter() {
    OuroHaptics.light();
    final me = _me;
    if (me == null) {
      ref.read(toastProvider.notifier).show(
            'Position indisponible — vérifiez que la localisation est '
            'activée.',
            type: DropletToastType.warning,
          );
      return;
    }
    _moveTo(LatLng(me.latitude, me.longitude), 16);
  }

  /// Déplace la carte SANS RISQUE.
  ///
  /// ⚠️ `MapController.move()` lève une exception si la carte n'est pas
  /// encore rattachée à l'arbre des widgets. Or la position peut très
  /// bien arriver AVANT la première image : `getLastKnownPosition()`
  /// répond parfois instantanément, alors que `FlutterMap` n'a pas
  /// encore été construit. L'exception remontait alors depuis un
  /// `Future` non surveillé — l'écran de la carte se fermait, ou
  /// affichait un écran rouge.
  ///
  /// On attend donc la fin de l'image en cours, et on protège l'appel.
  void _moveTo(LatLng target, double zoom) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _map.move(target, zoom);
      } catch (e) {
        debugPrint('[Carte] déplacement ignoré: $e');
      }
    });
  }

  double? _distanceTo(SafetyCheckinRecord c) {
    final me = _me;
    if (me == null) return null;
    return Geolocator.distanceBetween(
        me.latitude, me.longitude, c.lat!, c.lon!);
  }

  static String _formatDistance(double metres) {
    if (metres < 950) return '${(metres / 10).round() * 10} m';
    final km = metres / 1000;
    if (km < 10) return '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
    return '${km.round()} km';
  }

  static String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inMinutes < 1) return "à l'instant";
    if (diff.inMinutes < 60) return 'il y a ${diff.inMinutes} min';
    if (diff.inHours < 24) return 'il y a ${diff.inHours} h';
    return 'il y a ${diff.inDays} j';
  }

  // ─────────────────────────────────────────────────────────────
  //  AFFICHAGE
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final me = _me;
    final center = me != null
        ? LatLng(me.latitude, me.longitude)
        : _checkins.isNotEmpty
            ? LatLng(_checkins.first.lat!, _checkins.first.lon!)
            : _fallbackCenter;

    return Scaffold(
      // La carte est plein écran et sombre : comme l'écran d'appel, elle
      // ne suit pas le mode clair de l'app.
      backgroundColor: const Color(0xFF0B0D10),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Stack(
          children: [
            if (_ready) _buildMap(center) else _loading(),
            SafeArea(child: _topBar()),
            Positioned(
              right: 16,
              bottom: _selected != null ? 300 : 130,
              child: SafeArea(child: _controls()),
            ),
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(child: _bottomSheet()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loading() => const Center(
        child: OuroSpinner(color: Colors.white38, radius: 14),
      );

  Widget _buildMap(LatLng center) {
    final me = _me;

    return FlutterMap(
      mapController: _map,
      options: MapOptions(
        initialCenter: center,
        initialZoom: 15,
        minZoom: 3,
        maxZoom: 18,
        backgroundColor: const Color(0xFF0B0D10),
        onTap: (_, _) => setState(() => _selected = null),
      ),
      children: [
        TileLayer(
          tileProvider: _tiles,
          // `urlTemplate` n'est pas utilisé — c'est notre fournisseur qui
          // décide d'où vient chaque tuile — mais `flutter_map` exige
          // qu'il soit renseigné.
          urlTemplate:
              'https://a.basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.droplet.droplet',
          maxNativeZoom: 18,

          // ── ⚠️ NE PAS RESSERRER LA RÉTENTION DE TUILES ──────────────
          //
          // Les valeurs par défaut de `flutter_map` (`keepBuffer` 2,
          // `panBuffer` 1) sont volontairement laissées telles quelles.
          //
          // Carte ouverte, cet écran occupe environ 310 Mo de mémoire
          // graphique — le premier poste de toute l'application. La piste
          // évidente était donc de garder moins de tuiles autour de
          // l'écran. Elle a été ESSAYÉE ET MESURÉE sur un Pixel 6 Pro,
          // avec `keepBuffer: 1` :
          //
          //     défaut  (keepBuffer 2) : 865 Mo au total, GL 185 Mo
          //     resserré (keepBuffer 1) : 904 Mo au total, GL 210 Mo
          //
          // La mémoire a AUGMENTÉ au lieu de baisser. L'explication tient
          // au recyclage : des tuiles jetées trop tôt sont aussitôt
          // redemandées, et chaque aller-retour crée une texture neuve
          // que le pilote graphique ne rend pas immédiatement. On paie
          // donc le va-et-vient sans rien récupérer.
          //
          // (Des trous noirs ont aussi été observés pendant l'essai, mais
          // ils se sont reproduits APRÈS le retour aux valeurs par
          // défaut : c'est la latence de téléchargement des tuiles, pas
          // la purge. Ce point-là ne compte donc pas à charge.)
          //
          // La consommation de cet écran est réelle et reste à traiter,
          // mais PAS par ce levier — la piste est refermée, mesures à
          // l'appui.
        ),

        // Le halo de précision autour de ma position : il dit
        // honnêtement à quel point le GPS est sûr de lui, au lieu de
        // laisser croire à une précision au mètre près.
        if (me != null)
          CircleLayer(
            circles: [
              CircleMarker(
                point: LatLng(me.latitude, me.longitude),
                // ⚠️ `clamp` ne rattrape PAS un `NaN` : les comparaisons
                // avec `NaN` étant toutes fausses, `NaN.clamp(8, 120)`
                // renvoie `NaN`. Certains capteurs annoncent une
                // précision nulle ou indéfinie ; le test explicite est
                // donc nécessaire avant de borner.
                radius: me.accuracy.isFinite
                    ? me.accuracy.clamp(8.0, 120.0)
                    : 20.0,
                useRadiusInMeter: true,
                color: OuroColors.accent.withValues(alpha: 0.14),
                borderColor: OuroColors.accent.withValues(alpha: 0.30),
                borderStrokeWidth: 1,
              ),
            ],
          ),

        MarkerLayer(
          markers: [
            for (final c in _checkins)
              Marker(
                point: LatLng(c.lat!, c.lon!),
                width: 130,
                height: 74,
                alignment: Alignment.topCenter,
                child: _PeerPin(
                  checkin: c,
                  distance: _distanceTo(c),
                  selected: _selected?.peerId == c.peerId,
                  onTap: () {
                    OuroHaptics.selection();
                    setState(() => _selected = c);
                    _moveTo(LatLng(c.lat!, c.lon!), _map.camera.zoom);
                  },
                ),
              ),
            if (me != null)
              Marker(
                point: LatLng(me.latitude, me.longitude),
                width: 90,
                height: 60,
                child: const _MyPin(),
              ),
          ],
        ),

        // ⚠️ L'attribution n'est pas décorative : la licence ODbL des
        // données d'OpenStreetMap ET les conditions de CARTO, qui sert
        // les tuiles, imposent toutes deux de la faire apparaître
        // partout où la carte est montrée. La retirer rendrait la
        // publication de l'app illicite.
        const RichAttributionWidget(
          alignment: AttributionAlignment.bottomLeft,
          attributions: [
            TextSourceAttribution('© OpenStreetMap · © CARTO'),
          ],
        ),
      ],
    );
  }

  Widget _topBar() {
    final count = _checkins.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
      child: Row(
        children: [
          // Le bouton rond givré de la carte garde son dessin, mais
          // DÉPILE comme partout ailleurs : sans cela, « retour »
          // rejouait l'animation d'entrée au lieu de revenir.
          _round(Icons.arrow_back_ios_new_rounded, () {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            } else {
              context.go('/chats');
            }
          }),
          const Spacer(),
          Column(
            children: [
              Text('Localisation',
                  style: OuroTypography.headline.copyWith(
                    color: Colors.white,
                    fontSize: 20,
                    shadows: const [
                      Shadow(color: Colors.black87, blurRadius: 6),
                    ],
                  )),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _offlineOnly
                        ? Icons.cloud_off_rounded
                        : Icons.cloud_queue_rounded,
                    size: 13,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    _offlineOnly ? 'Hors connexion' : 'Carte en ligne',
                    style: OuroTypography.caption1
                        .copyWith(color: Colors.white54),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          _Frosted(
            radius: 20,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                OuroHaptics.selection();
                context.push('/maps/offline');
              },
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.people_outline_rounded,
                        color: Colors.white, size: 17),
                    const SizedBox(width: 6),
                    Text('$count',
                        style: OuroTypography.subheadline
                            .copyWith(color: Colors.white)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _controls() {
    return Column(
      children: [
        _round(Icons.my_location_rounded, _recenter, label: 'Ma position'),
        const SizedBox(height: 12),
        _round(
          _offlineOnly ? Icons.cloud_off_rounded : Icons.layers_rounded,
          () {
            OuroHaptics.selection();
            _toggleOffline();
            ref.read(toastProvider.notifier).show(
                  _offlineOnly
                      ? 'Carte hors connexion : seules les zones déjà '
                          'enregistrées s\'afficheront.'
                      : 'Carte en ligne : les zones consultées seront '
                          'enregistrées pour plus tard.',
                  type: DropletToastType.info,
                );
          },
          label: _offlineOnly ? 'Hors connexion' : 'Calques',
        ),
      ],
    );
  }

  Widget _round(IconData icon, VoidCallback onTap, {String? label}) {
    return Column(
      children: [
        _Frosted(
          shape: BoxShape.circle,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: SizedBox(
              width: 50,
              height: 50,
              child: Icon(icon, color: Colors.white, size: 22),
            ),
          ),
        ),
        if (label != null) ...[
          const SizedBox(height: 5),
          // Un liseré sombre derrière le libellé : posé à même la carte,
          // un texte gris devient illisible dès qu'il passe sur une zone
          // claire.
          Text(
            label,
            style: OuroTypography.caption2.copyWith(
              color: Colors.white,
              shadows: const [
                Shadow(color: Colors.black87, blurRadius: 4),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _bottomSheet() {
    final selected = _selected;
    if (selected == null) return _emptyHint();

    final distance = _distanceTo(selected);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: _Frosted(
        radius: 28,
        tint: 0.62,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // La petite poignée grise : elle dit « cette carte est un
            // panneau », convention immédiatement lue sur iOS.
            Center(
              child: Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Row(
              children: [
                PeerAvatar(pseudo: selected.pseudo, radius: 26),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(selected.pseudo,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OuroTypography.title3
                              .copyWith(color: Colors.white)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:
                              OuroColors.systemGreen.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(
                              DesignTokens.radiusFull),
                        ),
                        child: Text('En sécurité',
                            style: OuroTypography.footnote.copyWith(
                              color: OuroColors.systemGreen,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => setState(() => _selected = null),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded,
                        color: Colors.white38, size: 22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _sheetRow(
              Icons.location_on_outlined,
              distance == null
                  ? 'Position partagée'
                  : '${_formatDistance(distance)} de vous',
            ),
            const SizedBox(height: 10),
            _sheetRow(Icons.access_time_rounded, _timeAgo(selected.timestamp)),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: OuroColors.accent,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusLg),
                      ),
                    ),
                    onPressed: () => context.push('/chat/${selected.peerId}'),
                    icon: const Icon(Icons.chat_bubble_rounded, size: 18),
                    label: const Text('Écrire'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18)),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(DesignTokens.radiusLg),
                      ),
                    ),
                    onPressed: () {
                      OuroHaptics.light();
                      _moveTo(LatLng(selected.lat!, selected.lon!), 17);
                    },
                    icon: const Icon(Icons.center_focus_strong_rounded,
                        size: 18),
                    label: const Text('Centrer'),
                  ),
                ),
              ],
            ),
          ],
          ),
        ),
      ),
    );
  }

  Widget _sheetRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.white38, size: 18),
        const SizedBox(width: 12),
        Text(text,
            style: OuroTypography.subheadline.copyWith(color: Colors.white70)),
      ],
    );
  }

  /// Ce qui s'affiche tant que personne n'a partagé de position.
  Widget _emptyHint() {
    if (_checkins.isNotEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: _Frosted(
        radius: 22,
        tint: 0.58,
        child: Padding(
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(Icons.info_outline_rounded,
                color: OuroColors.accent, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Personne sur la carte',
                      style: OuroTypography.subheadline.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      )),
                  const SizedBox(height: 3),
                  Text(
                    'Les positions apparaissent ici quand un contact les '
                    'partage depuis le mode Sécurité.',
                    style: OuroTypography.footnote
                        .copyWith(color: Colors.white54, height: 1.3),
                  ),
                ],
              ),
            ),
          ],
        ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  LE VERRE DÉPOLI
// ─────────────────────────────────────────────────────────────

/// Une surface floutée posée sur la carte.
///
/// C'est LA différence de traitement entre une carte ordinaire et celle
/// des applications soignées : les commandes ne sont pas des pastilles
/// opaques posées par-dessus, elles laissent deviner la carte au
/// travers. On garde le repère de ce qui se trouve dessous tout en
/// gardant le bouton parfaitement lisible.
class _Frosted extends StatelessWidget {
  const _Frosted({
    required this.child,
    this.radius = 0,
    this.shape = BoxShape.rectangle,
    this.tint = 0.42,
  });

  final Widget child;
  final double radius;
  final BoxShape shape;

  /// Opacité du voile sombre posé PAR-DESSUS le flou. Le flou seul ne
  /// suffit pas : au-dessus d'une zone claire, une icône blanche
  /// disparaîtrait.
  final double tint;

  @override
  Widget build(BuildContext context) {
    final border = shape == BoxShape.circle
        ? null
        : BorderRadius.circular(radius);

    return ClipRRect(
      borderRadius: border ?? BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: shape,
            borderRadius: border,
            color: Colors.black.withValues(alpha: tint),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.14),
              width: 0.5,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  LES POINTS SUR LA CARTE
// ─────────────────────────────────────────────────────────────

/// Le point bleu de ma propre position.
class _MyPin extends StatelessWidget {
  const _MyPin();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: OuroColors.accent,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: [
              BoxShadow(
                color: OuroColors.accent.withValues(alpha: 0.5),
                blurRadius: 14,
                spreadRadius: 2,
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        const Text('Vous',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            )),
      ],
    );
  }
}

/// Le point d'un contact, avec son nom et sa distance.
class _PeerPin extends StatelessWidget {
  const _PeerPin({
    required this.checkin,
    required this.distance,
    required this.selected,
    required this.onTap,
  });

  final SafetyCheckinRecord checkin;
  final double? distance;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF0F1115),
              border: Border.all(
                color: selected ? OuroColors.accent : Colors.white24,
                width: selected ? 2.5 : 1.5,
              ),
            ),
            padding: const EdgeInsets.all(2),
            child: PeerAvatar(pseudo: checkin.pseudo, radius: 14),
          ),
          const SizedBox(height: 3),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.66),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  checkin.pseudo,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (distance != null)
                  Text(
                    _MapScreenState._formatDistance(distance!),
                    style: const TextStyle(
                        color: Colors.white54, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
