// CHOISIR CE QU'ON ENVOIE, SUR TÉLÉPHONE — comme Xender et Quick Share :
// des onglets Photos, Vidéos, Musique, Applications et Fichiers, des
// vignettes, la sélection multiple d'un geste, et le total en bas.
//
//   • Photos et vidéos : la galerie du téléphone, la plus récente d'abord,
//     chargée par pages (des milliers de photos restent fluides).
//   • Musique : les morceaux de l'appareil.
//   • Applications (Android) : les apps installées, avec leur icône. Une app
//     découpée en plusieurs APK part en dossier ; le destinataire l'installe
//     d'un toucher.
//   • Fichiers : le sélecteur du système, pour tout le reste.
//
// La sélection traverse les onglets ; « Suivant » mène aux destinataires.
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';

import '../app/modeles.dart';
import '../app/natif.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/typo.dart';

enum Onglet { photos, videos, musique, apps, fichiers }

/// Un élément choisi : une photo de la galerie (son fichier n'est résolu
/// qu'à la fin), une app, ou un fichier.
class _Element {
  _Element.media(this.media)
      : choisis = const [],
        taille = 0;
  _Element.fichiers(this.choisis, this.taille) : media = null;

  final AssetEntity? media;
  final List<Choisi> choisis;
  final int taille;
}

/// Ouvre l'écran ; rend les fichiers choisis (null si on revient).
Future<List<Choisi>?> choisirSurTelephone(BuildContext context) {
  return Navigator.of(context).push<List<Choisi>>(MaterialPageRoute(builder: (_) => const EcranSelection()));
}

class EcranSelection extends StatefulWidget {
  const EcranSelection({super.key});

  @override
  State<EcranSelection> createState() => _EcranSelectionState();
}

class _EcranSelectionState extends State<EcranSelection> {
  Onglet _onglet = Onglet.photos;
  final Map<String, _Element> _selection = {};
  final Map<String, int> _taillesMedias = {};
  bool _fin = false;

  int get _total => _selection.values.fold(0, (a, e) => a + (e.media != null ? (_taillesMedias[e.media!.id] ?? 0) : e.taille));

  void _basculer(String cle, _Element e) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selection.remove(cle) == null) _selection[cle] = e;
    });
    final m = e.media;
    if (m != null && !_taillesMedias.containsKey(m.id)) {
      m.originFile.then((f) {
        if (f != null && mounted) setState(() => _taillesMedias[m.id] = f.lengthSync());
      });
    }
  }

  Future<void> _suivant() async {
    setState(() => _fin = true);
    final l = <Choisi>[];
    for (final e in _selection.values) {
      if (e.media != null) {
        final f = await e.media!.originFile;
        if (f == null) continue;
        final nom = (await e.media!.titleAsync).trim();
        l.add(Choisi(chemin: f.path, nom: nom.isEmpty ? f.uri.pathSegments.last : nom, taille: f.lengthSync()));
      } else {
        l.addAll(e.choisis);
      }
    }
    if (!mounted) return;
    setState(() => _fin = false);
    Navigator.of(context).pop(l);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final options = <(Onglet, String, IconData?)>[
      (Onglet.photos, context.t('onglet_photos'), null),
      (Onglet.videos, context.t('onglet_videos'), null),
      (Onglet.musique, context.t('onglet_musique'), null),
      if (Natif.android) (Onglet.apps, context.t('onglet_apps'), null),
      (Onglet.fichiers, context.t('onglet_fichiers'), null),
    ];
    final n = _selection.length;
    return Scaffold(
      backgroundColor: p.fond,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: p.accentTexte),
        title: Text(context.t('envoyer'), style: Typo.titreCarte.copyWith(color: p.texte)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 32),
                child: Segments<Onglet>(options: options, valeur: _onglet, onChange: (o) => setState(() => _onglet = o)),
              ),
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: duree(context, 220),
              child: KeyedSubtree(
                key: ValueKey(_onglet),
                child: switch (_onglet) {
                  Onglet.photos => _Galerie(type: RequestType.image, selection: _selection, onBasculer: _basculer),
                  Onglet.videos => _Galerie(type: RequestType.video, selection: _selection, onBasculer: _basculer),
                  Onglet.musique => _Musique(selection: _selection, onBasculer: _basculer),
                  Onglet.apps => _Apps(selection: _selection, onBasculer: _basculer),
                  Onglet.fichiers => _Fichiers(selection: _selection, onAjouter: (cle, e) => setState(() => _selection[cle] = e), onRetirer: (cle) => setState(() => _selection.remove(cle))),
                },
              ),
            ),
          ),
          // La barre du bas : ce qui est choisi, et Suivant.
          AnimatedContainer(
            duration: duree(context, 260),
            curve: kRessort,
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
            decoration: BoxDecoration(color: p.fondEleve, border: Border(top: BorderSide(color: p.trait, width: 0.5))),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(n == 0 ? context.t('rien_choisi') : context.t('n_elements', {'n': '$n'}), style: Typo.titreCarte.copyWith(color: p.texte)),
                      if (n > 0 && _total > 0) Text(tailleLocale(_total), style: Typo.secondaire.copyWith(color: p.texte2)),
                    ],
                  ),
                ),
                BoutonLiquide(texte: context.t('suivant'), icone: Icons.arrow_forward_rounded, hauteur: 48, large: false, chargement: _fin, onTap: n == 0 || _fin ? null : _suivant),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── L'autorisation d'accéder aux médias ─────────────────────────────────

class _AccesMedias extends StatelessWidget {
  const _AccesMedias({required this.onAutoriser});

  final VoidCallback onAutoriser;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: EtatVide(
        icone: Icons.photo_library_rounded,
        titre: context.t('acces_medias_titre'),
        texte: context.t('acces_medias_texte'),
        action: BoutonLiquide(texte: context.t('autoriser'), hauteur: 48, large: false, onTap: onAutoriser),
      ),
    );
  }
}

Future<bool> _demanderMedias({bool reglages = false}) async {
  final r = await PhotoManager.requestPermissionExtend();
  if (r.hasAccess) return true;
  if (reglages) await PhotoManager.openSetting();
  return false;
}

// ── Photos et vidéos ───────────────────────────────────────────────────

class _Galerie extends StatefulWidget {
  const _Galerie({required this.type, required this.selection, required this.onBasculer});

  final RequestType type;
  final Map<String, _Element> selection;
  final void Function(String, _Element) onBasculer;

  @override
  State<_Galerie> createState() => _GalerieState();
}

class _GalerieState extends State<_Galerie> {
  final List<AssetEntity> _medias = [];
  bool? _acces;
  bool _charge = false;
  bool _fini = false;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _ouvrir();
  }

  Future<void> _ouvrir({bool reglages = false}) async {
    final ok = await _demanderMedias(reglages: reglages);
    if (!mounted) return;
    setState(() => _acces = ok);
    if (ok) _suite();
  }

  Future<void> _suite() async {
    if (_charge || _fini) return;
    _charge = true;
    final l = await PhotoManager.getAssetListPaged(page: _page, pageCount: 120, type: widget.type);
    _charge = false;
    if (!mounted) return;
    setState(() {
      _medias.addAll(l);
      _page++;
      _fini = l.length < 120;
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    if (_acces == null) return const Center(child: CircularProgressIndicator.adaptive());
    if (_acces == false) return _AccesMedias(onAutoriser: () => _ouvrir(reglages: true));
    if (_medias.isEmpty && _fini) {
      return Center(child: EtatVide(icone: widget.type == RequestType.video ? Icons.videocam_rounded : Icons.photo_rounded, titre: context.t(widget.type == RequestType.video ? 'aucune_video' : 'aucune_photo')));
    }
    final colonnes = (MediaQuery.sizeOf(context).width / 110).floor().clamp(3, 8);
    final cles = [for (final m in _medias) 'm:${m.id}'];
    final toutes = cles.isNotEmpty && cles.every(widget.selection.containsKey);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 4),
          child: Row(
            children: [
              Expanded(child: Text(context.t('recents'), style: Typo.legende.copyWith(color: p.texte2, letterSpacing: .6))),
              TextButton(
                onPressed: () {
                  for (final m in _medias) {
                    final c = 'm:${m.id}';
                    if (toutes == widget.selection.containsKey(c)) widget.onBasculer(c, _Element.media(m));
                  }
                },
                child: Text(context.t(toutes ? 'tout_deselectionner' : 'tout_selectionner'), style: Typo.secondaire.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (n) {
              if (n.metrics.extentAfter < 900) _suite();
              return false;
            },
            child: GridView.builder(
              padding: const EdgeInsets.fromLTRB(2, 0, 2, 16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: colonnes, mainAxisSpacing: 2, crossAxisSpacing: 2),
              itemCount: _medias.length,
              itemBuilder: (context, i) {
                final m = _medias[i];
                final cle = 'm:${m.id}';
                return _Vignette(media: m, choisie: widget.selection.containsKey(cle), onTap: () => widget.onBasculer(cle, _Element.media(m)));
              },
            ),
          ),
        ),
      ],
    );
  }
}

/// Le cache des vignettes : on ne redemande pas une miniature déjà faite.
final Map<String, Uint8List?> _miniatures = {};

class _Vignette extends StatelessWidget {
  const _Vignette({required this.media, required this.choisie, required this.onTap});

  final AssetEntity media;
  final bool choisie;
  final VoidCallback onTap;

  Future<Uint8List?> _mini() async {
    if (_miniatures.containsKey(media.id)) return _miniatures[media.id];
    final d = await media.thumbnailDataWithSize(const ThumbnailSize.square(240), quality: 80);
    return _miniatures[media.id] = d;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final s = media.videoDuration;
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(
            color: p.surfaceHaute,
            child: FutureBuilder<Uint8List?>(
              future: _mini(),
              initialData: _miniatures[media.id],
              builder: (c, v) => v.data == null ? const SizedBox() : Image.memory(v.data!, fit: BoxFit.cover, gaplessPlayback: true),
            ),
          ),
          AnimatedScale(
            scale: choisie ? .86 : 1,
            duration: duree(context, 220),
            curve: kRessort,
            child: AnimatedContainer(
              duration: duree(context, 160),
              decoration: BoxDecoration(border: Border.all(color: choisie ? p.accent : Colors.transparent, width: 3), borderRadius: BorderRadius.circular(choisie ? 10 : 0)),
            ),
          ),
          if (media.type == AssetType.video)
            Positioned(
              left: 6,
              bottom: 5,
              child: Text(
                '${s.inMinutes}:${(s.inSeconds % 60).toString().padLeft(2, '0')}',
                style: Typo.legende.copyWith(color: Colors.white, shadows: const [Shadow(blurRadius: 4, color: Colors.black54)]),
              ),
            ),
          Positioned(top: 6, right: 6, child: _Coche(choisie: choisie)),
        ],
      ),
    );
  }
}

class _Coche extends StatelessWidget {
  const _Coche({required this.choisie, this.surFond = false});

  final bool choisie;
  final bool surFond;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AnimatedContainer(
      duration: duree(context, 180),
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: choisie ? p.liquide : null,
        color: choisie ? null : (surFond ? Colors.transparent : Colors.black.withValues(alpha: .18)),
        border: Border.all(color: choisie ? Colors.transparent : (surFond ? p.texte3 : Colors.white), width: 1.8),
      ),
      child: choisie ? const Icon(Icons.check_rounded, size: 16, color: Colors.white) : null,
    );
  }
}

// ── Musique ────────────────────────────────────────────────────────────

class _Musique extends StatefulWidget {
  const _Musique({required this.selection, required this.onBasculer});

  final Map<String, _Element> selection;
  final void Function(String, _Element) onBasculer;

  @override
  State<_Musique> createState() => _MusiqueState();
}

class _MusiqueState extends State<_Musique> {
  List<AssetEntity>? _morceaux;
  bool? _acces;

  @override
  void initState() {
    super.initState();
    _ouvrir();
  }

  Future<void> _ouvrir({bool reglages = false}) async {
    final ok = await _demanderMedias(reglages: reglages);
    if (!mounted) return;
    setState(() => _acces = ok);
    if (!ok) return;
    final l = await PhotoManager.getAssetListPaged(page: 0, pageCount: 2000, type: RequestType.audio);
    if (mounted) setState(() => _morceaux = l);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    if (_acces == false) return _AccesMedias(onAutoriser: () => _ouvrir(reglages: true));
    final l = _morceaux;
    if (l == null) return const Center(child: CircularProgressIndicator.adaptive());
    if (l.isEmpty) return Center(child: EtatVide(icone: Icons.music_note_rounded, titre: context.t('aucune_musique')));
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      itemCount: l.length,
      itemBuilder: (context, i) {
        final m = l[i];
        final cle = 'm:${m.id}';
        final s = m.videoDuration;
        return _LigneChoix(
          choisie: widget.selection.containsKey(cle),
          onTap: () => widget.onBasculer(cle, _Element.media(m)),
          tete: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(gradient: p.liquide, borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.music_note_rounded, color: Colors.white),
          ),
          titre: m.title ?? '',
          sous: '${s.inMinutes}:${(s.inSeconds % 60).toString().padLeft(2, '0')}',
        );
      },
    );
  }
}

class _LigneChoix extends StatelessWidget {
  const _LigneChoix({required this.choisie, required this.onTap, required this.tete, required this.titre, required this.sous});

  final bool choisie;
  final VoidCallback onTap;
  final Widget tete;
  final String titre;
  final String sous;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Pressable(
      onTap: onTap,
      semantique: titre,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7),
        child: Row(
          children: [
            tete,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.corps.copyWith(color: p.texte, fontWeight: FontWeight.w500)),
                  Text(sous, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.secondaire.copyWith(color: p.texte2)),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _Coche(choisie: choisie, surFond: true),
          ],
        ),
      ),
    );
  }
}

// ── Applications ───────────────────────────────────────────────────────

/// Un nom de fichier sûr (pas de « / », pas de caractères de contrôle).
String _sur(String s) => s.replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1F]'), ' ').trim();

class _Apps extends StatefulWidget {
  const _Apps({required this.selection, required this.onBasculer});

  final Map<String, _Element> selection;
  final void Function(String, _Element) onBasculer;

  @override
  State<_Apps> createState() => _AppsState();
}

class _AppsState extends State<_Apps> {
  static List<AppInstallee>? _cache;
  List<AppInstallee>? _apps = _cache;
  String _recherche = '';

  @override
  void initState() {
    super.initState();
    if (_apps == null) {
      Natif.applications().then((l) {
        _cache = l;
        if (mounted) setState(() => _apps = l);
      });
    }
  }

  _Element _element(AppInstallee a) {
    final base = _sur('${a.nom}${a.version == null ? '' : ' ${a.version}'}');
    if (a.apk.length == 1) {
      return _Element.fichiers([Choisi(chemin: a.apk.first, nom: '$base.apk', taille: a.taille)], a.taille);
    }
    // Une app découpée : un dossier avec tous ses APK.
    return _Element.fichiers([
      for (final c in a.apk) Choisi(chemin: c, nom: '$base/${c.split('/').last}', taille: File(c).lengthSync()),
    ], a.taille);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final l = _apps;
    if (l == null) return const Center(child: CircularProgressIndicator.adaptive());
    if (l.isEmpty) return Center(child: EtatVide(icone: Icons.apps_rounded, titre: context.t('aucune_app')));
    final q = _recherche.toLowerCase();
    final visibles = q.isEmpty ? l : l.where((a) => a.nom.toLowerCase().contains(q)).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: TextField(
            onChanged: (v) => setState(() => _recherche = v),
            style: Typo.corps.copyWith(color: p.texte),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: p.surfaceHaute,
              prefixIcon: Icon(Icons.search_rounded, color: p.texte2),
              hintText: context.t('rechercher_app'),
              hintStyle: Typo.corps.copyWith(color: p.texte3),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            itemCount: visibles.length,
            itemBuilder: (context, i) {
              final a = visibles[i];
              final cle = 'a:${a.paquet}';
              return _LigneChoix(
                choisie: widget.selection.containsKey(cle),
                onTap: () => widget.onBasculer(cle, _element(a)),
                tete: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: a.icone == null ? Container(width: 44, height: 44, color: p.surfaceHaute) : Image.memory(a.icone!, width: 44, height: 44),
                ),
                titre: a.nom,
                sous: [if (a.version != null) a.version!, tailleLocale(a.taille)].join(' · '),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Fichiers ───────────────────────────────────────────────────────────

class _Fichiers extends StatelessWidget {
  const _Fichiers({required this.selection, required this.onAjouter, required this.onRetirer});

  final Map<String, _Element> selection;
  final void Function(String, _Element) onAjouter;
  final void Function(String) onRetirer;

  Future<void> _parcourir(BuildContext context) async {
    try {
      final r = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
      if (r == null) return;
      for (final f in r.files) {
        if (f.path == null) continue;
        onAjouter('f:${f.path}', _Element.fichiers([Choisi(chemin: f.path!, nom: f.name, taille: f.size)], f.size));
      }
    } catch (_) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('selection_impossible'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final fichiers = selection.entries.where((e) => e.key.startsWith('f:')).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      children: [
        Carte(
          onTap: () => _parcourir(context),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: p.accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(12)),
                child: Icon(Icons.folder_open_rounded, color: p.accentTexte),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(context.t('parcourir_fichiers'), style: Typo.titreCarte.copyWith(color: p.texte)),
                    Text(context.t('parcourir_texte'), style: Typo.secondaire.copyWith(color: p.texte2)),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: p.texte3),
            ],
          ),
        ),
        if (fichiers.isNotEmpty) ...[
          TitreSection(context.t('n_elements', {'n': '${fichiers.length}'})),
          for (final e in fichiers)
            _LigneChoix(
              choisie: true,
              onTap: () => onRetirer(e.key),
              tete: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(color: p.surfaceHaute, borderRadius: BorderRadius.circular(10)),
                child: Icon(Icons.insert_drive_file_rounded, color: p.texte2),
              ),
              titre: e.value.choisis.first.nom,
              sous: tailleLocale(e.value.taille),
            ),
        ],
      ],
    );
  }
}
