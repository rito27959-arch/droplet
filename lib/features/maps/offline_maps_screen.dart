// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'écran CARTES HORS CONNEXION : ce que Droplet a gardé de la carte, ce
// que ça pèse, et comment en ajouter.
//
// ── Deux façons d'avoir une carte hors connexion ──────────────────────
//
// 1. EN LA REGARDANT. Tout ce qu'on parcourt avec du réseau est
//    conservé et reste consultable ensuite. C'est automatique, il n'y a
//    rien à faire — et ça couvre le cas le plus fréquent : son quartier,
//    son trajet, l'endroit où l'on va.
//
// 2. EN IMPORTANT UN FICHIER `.mbtiles`. Une région entière, préparée à
//    l'avance sur un ordinateur, puis copiée sur le téléphone. C'est la
//    seule façon d'avoir une ville complète sans l'avoir parcourue.
//
// ── Pourquoi pas un bouton « Télécharger Yaoundé » ? ──────────────────
//
// Parce qu'il n'existe aucun serveur de tuiles gratuit qui autorise ce
// téléchargement. Une ville aux zooms utiles, c'est plusieurs dizaines
// de milliers de requêtes ; les conditions d'utilisation d'OpenStreetMap
// l'interdisent explicitement, et les services commerciaux qui le
// permettent réclament un compte et un abonnement.
//
// Un bouton qui promettrait ce téléchargement serait donc soit
// inopérant, soit un moyen de faire bannir l'application. L'import de
// fichier, lui, fonctionne vraiment — c'est un format standard que
// n'importe quel outil cartographique sait produire.
// ============================================================================

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/mesh_provider.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_alert.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_list.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/ouro_typography.dart';
import '../../shared/widgets/empty_state.dart';
import 'offline_tile_store.dart';
import '../../shared/widgets/scene_animee.dart';

class OfflineMapsScreen extends ConsumerStatefulWidget {
  const OfflineMapsScreen({super.key});

  @override
  ConsumerState<OfflineMapsScreen> createState() => _OfflineMapsScreenState();
}

class _OfflineMapsScreenState extends ConsumerState<OfflineMapsScreen> {
  List<OfflineRegion> _regions = const [];
  bool _loading = true;
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    await OfflineTileStore.instance.init();
    final regions = await OfflineTileStore.instance.regions();
    if (!mounted) return;
    setState(() {
      _regions = regions;
      _loading = false;
    });
  }

  Future<void> _import() async {
    OuroHaptics.selection();
    setState(() => _importing = true);
    try {
      final result = await FilePicker.platform.pickFiles();
      final path = result?.files.single.path;
      if (path == null) return;

      final error = await OfflineTileStore.instance.import(File(path));
      if (!mounted) return;
      if (error != null) {
        _toast(error, DropletToastType.error);
      } else {
        OuroHaptics.success();
        _toast('Carte installée', DropletToastType.success);
        await _reload();
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  Future<void> _remove(OfflineRegion region) async {
    final isCache = region.isCache;
    final confirmed = await ouroConfirm(
      context,
      title: isCache ? 'Vider le cache ?' : 'Supprimer cette zone ?',
      message: isCache
          ? 'Les zones que vous avez parcourues ne seront plus disponibles '
              'hors connexion. Elles se reconstitueront en les consultant à '
              'nouveau avec du réseau.'
          : '« ${region.name} » sera supprimée de cet appareil.',
      confirmLabel: isCache ? 'Vider' : 'Supprimer',
      destructive: true,
    );
    if (confirmed != true) return;

    await OfflineTileStore.instance.remove(region);
    if (!mounted) return;
    OuroHaptics.medium();
    await _reload();
  }

  void _toast(String message, DropletToastType type) {
    ref.read(toastProvider.notifier).show(message, type: type);
  }

  @override
  Widget build(BuildContext context) {
    final total = _regions.fold<int>(0, (sum, r) => sum + r.sizeBytes);

    return OuroLargeTitleScaffold(
      title: 'Cartes',
      subtitle: _loading
          ? 'Lecture…'
          : total == 0
              ? 'Aucune carte enregistrée'
              : '${_sizeLabel(total)} sur cet appareil',
      backgroundColor: OuroColors.systemGroupedBackground,
      leading: const OuroBackButton(fallback: '/map'),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(
                horizontal: DesignTokens.screenMargin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_loading && _regions.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40, bottom: 24),
                    child: EmptyState(
                      emoji: Scenes.aucuneCarte,
                      icon: Icons.map_outlined,
                      title: 'Aucune carte enregistrée',
                      subtitle: 'Parcourez la carte avec du réseau : les '
                          'zones que vous regardez restent disponibles hors '
                          'connexion.',
                    ),
                  )
                else if (!_loading)
                  OuroListSection(
                    header: 'Sur cet appareil',
                    footer: 'Les zones consultées se remplissent toutes '
                        'seules pendant que vous parcourez la carte avec du '
                        'réseau.',
                    separatorInset: 60,
                    children: [
                      for (final region in _regions)
                        OuroListRow(
                          icon: region.isCache
                              ? Icons.history_rounded
                              : Icons.map_rounded,
                          iconColor: region.isCache
                              ? OuroColors.systemGray
                              : OuroColors.systemGreen,
                          title: region.name,
                          subtitle: '${region.sizeLabel} · '
                              '${_tileLabel(region.tileCount)} · '
                              'zoom ${region.minZoom}–${region.maxZoom}',
                          showChevron: false,
                          trailing: IconButton(
                            tooltip: region.isCache ? 'Vider' : 'Supprimer',
                            icon: Icon(Icons.delete_outline_rounded,
                                color: OuroColors.systemRed, size: 20),
                            onPressed: () => _remove(region),
                          ),
                        ),
                    ],
                  ),

                const SizedBox(height: DesignTokens.space5),

                OuroListSection(
                  header: 'Ajouter',
                  footer: 'Un fichier .mbtiles contient une région entière, '
                      'préparée à l\'avance. C\'est le format standard des '
                      'cartes hors connexion : n\'importe quel outil '
                      'cartographique sait en produire.',
                  children: [
                    OuroListRow(
                      icon: Icons.file_open_rounded,
                      iconColor: OuroColors.accent,
                      title: 'Importer une carte',
                      subtitle: _importing
                          ? 'Lecture du fichier…'
                          : 'Fichier .mbtiles depuis ce téléphone',
                      onTap: _importing ? null : _import,
                    ),
                  ],
                ),

                const SizedBox(height: DesignTokens.space5),
                _explainer(),
                const SizedBox(height: DesignTokens.space6),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Le bloc qui explique d'où viennent les cartes — et qui porte
  /// l'attribution qu'impose la licence des données.
  Widget _explainer() {
    return Container(
      padding: const EdgeInsets.all(DesignTokens.space4),
      decoration: BoxDecoration(
        color: OuroColors.secondarySystemGroupedBackground,
        borderRadius: BorderRadius.circular(DesignTokens.radiusGroupedList),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.public_rounded, size: 18, color: OuroColors.accent),
              const SizedBox(width: 8),
              Text('OpenStreetMap · CARTO',
                  style: OuroTypography.subheadline.copyWith(
                    color: OuroColors.label,
                    fontWeight: FontWeight.w600,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Les données viennent d\'OpenStreetMap (licence ODbL), le fond '
            'de carte est servi par CARTO. Droplet ne télécharge jamais de '
            'région entière à l\'avance : aucun service gratuit ne '
            'l\'autorise. Seul ce que vous consultez est conservé.',
            style: OuroTypography.footnote.copyWith(
              color: OuroColors.secondaryLabel,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  static String _tileLabel(int count) {
    if (count < 1000) return '$count tuiles';
    return '${(count / 1000).toStringAsFixed(1).replaceAll('.', ',')} k tuiles';
  }

  static String _sizeLabel(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).round()} ko';
    final mo = bytes / (1024 * 1024);
    if (mo < 1024) return '${mo.toStringAsFixed(mo < 10 ? 1 : 0)} Mo';
    return '${(mo / 1024).toStringAsFixed(1)} Go';
  }
}
