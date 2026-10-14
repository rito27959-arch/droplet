// CHOISIR LES FICHIERS, puis LES DESTINATAIRES.
//
// Les sélecteurs du système (pas d'accès global au stockage), plusieurs
// fichiers à la fois, des dossiers sur ordinateur. La sélection se garde :
// on peut revenir en arrière, en ajouter, en retirer.
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/etat_app.dart';
import '../app/modeles.dart';
import '../app/natif.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/typo.dart';
import '../src/rust/api/simple.dart' as moteur;
import 'accueil.dart';
import 'connexion_directe.dart';
import 'group_drop.dart';
import 'partage_web.dart';
import 'scanner.dart';
import 'selection.dart';
import 'transfert.dart';

bool get estMobile => Platform.isAndroid || Platform.isIOS;

/// Ouvre le sélecteur, puis l'écran des destinataires.
Future<void> choisirPuisEnvoyer(BuildContext context, {AppareilVu? vers}) async {
  final choisis = await choisirFichiers(context);
  if (choisis == null || choisis.isEmpty || !context.mounted) return;
  await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EcranDestinataires(choisis: choisis, preselection: vers)));
}

/// Fichiers, photos et vidéos, ou un dossier entier (ordinateur).
Future<List<Choisi>?> choisirFichiers(BuildContext context) async {
  // Sur téléphone : l'écran à onglets (Photos, Vidéos, Musique, Apps…).
  if (estMobile) return choisirSurTelephone(context);
  final p = context.p;
  final genre = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Carte(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Option(icone: Icons.description_rounded, titre: c.t('choisir_fichiers'), onTap: () => Navigator.pop(c, 'fichiers')),
              if (estMobile) _Option(icone: Icons.photo_library_rounded, titre: c.t('choisir_medias'), onTap: () => Navigator.pop(c, 'medias')),
              if (!estMobile) _Option(icone: Icons.folder_rounded, titre: c.t('choisir_dossier'), onTap: () => Navigator.pop(c, 'dossier')),
            ],
          ),
        ),
      ),
    ),
  );
  if (genre == null) return null;
  try {
    if (genre == 'dossier') {
      final d = await FilePicker.platform.getDirectoryPath();
      if (d == null) return null;
      return await contenuDossier(Directory(d));
    }
    final r = await FilePicker.platform.pickFiles(allowMultiple: true, type: genre == 'medias' ? FileType.media : FileType.any, withData: false);
    if (r == null) return null;
    return [
      for (final f in r.files)
        if (f.path != null) Choisi(chemin: f.path!, nom: f.name, taille: f.size),
    ];
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('selection_impossible')), backgroundColor: p.surfaceHaute));
    }
    return null;
  }
}

/// Tout le contenu d'un dossier, avec ses sous-dossiers, sous son nom.
Future<List<Choisi>> contenuDossier(Directory d) async {
  final racine = d.path;
  final nomDossier = racine.split(Platform.pathSeparator).where((x) => x.isNotEmpty).last;
  final l = <Choisi>[];
  await for (final e in d.list(recursive: true, followLinks: false)) {
    if (e is File) {
      final rel = e.path.substring(racine.length).replaceAll('\\', '/').replaceFirst(RegExp('^/+'), '');
      l.add(Choisi(chemin: e.path, nom: '$nomDossier/$rel', taille: await e.length()));
    }
  }
  return l;
}

class _Option extends StatelessWidget {
  const _Option({required this.icone, required this.titre, required this.onTap});

  final IconData icone;
  final String titre;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Pressable(
      onTap: onTap,
      semantique: titre,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Row(
          children: [
            Icon(icone, color: p.accentTexte),
            const SizedBox(width: 16),
            Expanded(child: Text(titre, style: Typo.corps.copyWith(color: p.texte))),
          ],
        ),
      ),
    );
  }
}

class EcranDestinataires extends StatefulWidget {
  const EcranDestinataires({super.key, required this.choisis, this.preselection});

  final List<Choisi> choisis;
  final AppareilVu? preselection;

  @override
  State<EcranDestinataires> createState() => _EcranDestinatairesState();
}

class _EcranDestinatairesState extends State<EcranDestinataires> {
  late final List<Choisi> _fichiers = [...widget.choisis];
  final Set<String> _selection = {};
  final Map<String, Map<String, dynamic>> _manuels = {};
  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    if (widget.preselection != null) _selection.add(widget.preselection!.id);
  }

  int get _total => _fichiers.fold(0, (a, f) => a + f.taille);

  Future<void> _ajouterFichiers() async {
    final plus = await choisirFichiers(context);
    if (plus != null) setState(() => _fichiers.addAll(plus.where((x) => !_fichiers.any((f) => f.chemin == x.chemin))));
  }

  Future<void> _adresse() async {
    final champ = TextEditingController();
    final adresse = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(c.t('saisir_adresse')),
        content: TextField(
          controller: champ,
          autofocus: true,
          keyboardType: TextInputType.url,
          decoration: InputDecoration(hintText: '192.168.1.12', helperText: c.t('saisir_adresse_aide'), helperMaxLines: 3),
          onSubmitted: (v) => Navigator.pop(c, v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c), child: Text(c.t('annuler'))),
          TextButton(onPressed: () => Navigator.pop(c, champ.text), child: Text(c.t('ajouter'))),
        ],
      ),
    );
    if (adresse == null || adresse.trim().isEmpty) return;
    try {
      final cibles = jsonDecode(moteur.cibleManuelle(adresse: adresse.trim())) as List;
      final c = (cibles.first as Map).cast<String, dynamic>();
      setState(() {
        _manuels[adresse.trim()] = c;
        _selection.add('manuel:${adresse.trim()}');
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('adresse_invalide'))));
    }
  }

  /// Le code d'un appareil (écran « Recevoir ») : adresse ET empreinte.
  Future<void> _scanner() async {
    final brut = await scannerCode(context);
    if (brut == null) return;
    try {
      final j = (jsonDecode(brut) as Map).cast<String, dynamic>();
      if (j['t'] != 'droplet_drop_appareil') throw const FormatException();
      // L'autre appareil a ouvert une connexion directe : on la rejoint
      // d'abord (pas besoin de box ni d'Internet).
      final pa = PointAcces.depuis(j['w']);
      if (pa != null && Natif.android) {
        if (!mounted) return;
        final ok = await rejoindreConnexion(context, pa, j['n'] as String? ?? '');
        if (!ok || !mounted) return;
      }
      final port = j['p'] as int;
      final cible = {
        'adresses': [for (final a in (j['a'] as List)) '$a:$port'],
        'empreinte': j['fp'] as String,
        'nom': j['n'] as String? ?? '',
      };
      setState(() {
        _manuels[j['fp'] as String] = cible;
        _selection.add('manuel:${j['fp']}');
      });
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('code_invalide'))));
    }
  }

  Future<void> _envoyer() async {
    final e = EtatApp.i;
    final cibles = <Map<String, dynamic>>[
      for (final id in _selection)
        if (id.startsWith('manuel:')) _manuels[id.substring(7)]! else if (e.appareils[id] != null) e.appareils[id]!.cible(),
    ];
    if (cibles.isEmpty) return;
    setState(() => _envoi = true);
    try {
      final g = await e.envoyer(_fichiers, cibles);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => EcranTransfert(groupe: g)));
    } catch (_) {
      if (mounted) {
        setState(() => _envoi = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('envoi_impossible'))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ListenableBuilder(
      listenable: EtatApp.i,
      builder: (context, _) {
        final appareils = EtatApp.i.appareils.values.toList();
        final n = _selection.length;
        return Scaffold(
          backgroundColor: p.fond,
          appBar: AppBar(
            backgroundColor: p.fond,
            surfaceTintColor: Colors.transparent,
            title: Text(context.t('destinataires'), style: Typo.titreCarte.copyWith(color: p.texte)),
            iconTheme: IconThemeData(color: p.accentTexte),
          ),
          body: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  children: [
                    Colonne(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _Selection(fichiers: _fichiers, total: _total, onAjouter: _ajouterFichiers, onRetirer: (f) => setState(() => _fichiers.remove(f))),
                          TitreSection(
                            context.t('a_proximite'),
                            fin: appareils.length > 1
                                ? TextButton(
                                    onPressed: () => setState(() {
                                      final tous = appareils.every((a) => _selection.contains(a.id));
                                      for (final a in appareils) {
                                        tous ? _selection.remove(a.id) : _selection.add(a.id);
                                      }
                                    }),
                                    child: Text(context.t('tout_selectionner'), style: Typo.legende.copyWith(color: p.accentTexte)),
                                  )
                                : null,
                          ),
                          if (appareils.isEmpty && _manuels.isEmpty)
                            Carte(child: EtatVide(icone: Icons.wifi_tethering_rounded, titre: context.t('personne_titre'), texte: context.t('personne_texte_envoi'))),
                          for (final (i, a) in appareils.indexed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Apparition(
                                delai: i * 40,
                                child: CarteAppareil(
                                  appareil: a,
                                  selectionne: _selection.contains(a.id),
                                  onTap: () => setState(() => _selection.contains(a.id) ? _selection.remove(a.id) : _selection.add(a.id)),
                                ),
                              ),
                            ),
                          for (final m in _manuels.entries)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: CarteAppareil(
                                appareil: AppareilVu(
                                  id: 'manuel:${m.key}',
                                  nom: (m.value['nom'] as String?)?.isNotEmpty == true ? m.value['nom'] as String : m.key,
                                  plateforme: '',
                                  empreinte: (m.value['empreinte'] as String?) ?? '',
                                  adresses: (m.value['adresses'] as List).cast<String>(),
                                ),
                                selectionne: _selection.contains('manuel:${m.key}'),
                                onTap: () => setState(() {
                                  final k = 'manuel:${m.key}';
                                  _selection.contains(k) ? _selection.remove(k) : _selection.add(k);
                                }),
                              ),
                            ),
                          TitreSection(context.t('pas_dans_la_liste')),
                          Row(
                            children: [
                              if (estMobile || Platform.isMacOS) ...[
                                Expanded(child: BoutonSecondaire(texte: context.t('scanner_code'), icone: Icons.qr_code_scanner_rounded, hauteur: 50, onTap: _scanner)),
                                const SizedBox(width: 10),
                              ],
                              Expanded(child: BoutonSecondaire(texte: context.t('adresse'), icone: Icons.dialpad_rounded, hauteur: 50, onTap: _adresse)),
                            ],
                          ),
                          if (Natif.android) ...[const SizedBox(height: 14), const CarteConnexionDirecte()],
                          const SizedBox(height: 14),
                          CarteNavigateur(choisis: _fichiers),
                          const SizedBox(height: 18),
                          Carte(
                            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CreerDistribution(choisis: _fichiers))),
                            child: Row(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(gradient: p.liquide, borderRadius: BorderRadius.circular(14)),
                                  child: const Icon(Icons.groups_2_rounded, color: Colors.white),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(context.t('creer_distribution'), style: Typo.titreCarte.copyWith(color: p.texte)),
                                      const SizedBox(height: 2),
                                      Text(context.t('creer_distribution_texte'), style: Typo.secondaire.copyWith(color: p.texte2)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, color: p.texte3),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Givre(
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                    child: Colonne(
                      child: BoutonLiquide(
                        texte: n <= 1 ? context.t('envoyer') : context.t('envoyer_a_n', {'n': '$n'}),
                        icone: Icons.arrow_upward_rounded,
                        chargement: _envoi,
                        onTap: n == 0 || _fichiers.isEmpty ? null : _envoyer,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Selection extends StatelessWidget {
  const _Selection({required this.fichiers, required this.total, required this.onAjouter, required this.onRetirer});

  final List<Choisi> fichiers;
  final int total;
  final VoidCallback onAjouter;
  final void Function(Choisi) onRetirer;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final montres = fichiers.take(4).toList();
    return Carte(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  fichiers.length == 1 ? fichiers.first.nom.split('/').last : context.t('n_fichiers', {'n': '${fichiers.length}'}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Typo.titreCarte.copyWith(color: p.texte),
                ),
              ),
              Text(tailleLocale(total), style: Typo.chiffres.copyWith(color: p.texte2)),
            ],
          ),
          const SizedBox(height: 12),
          for (final f in montres)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(iconeFichier(f.nom), size: 18, color: p.texte2),
                  const SizedBox(width: 10),
                  Expanded(child: Text(f.nom, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.secondaire.copyWith(color: p.texte))),
                  Text(tailleLocale(f.taille), style: Typo.legende.copyWith(color: p.texte3)),
                  const SizedBox(width: 10),
                  BoutonIcone(icone: Icons.close_rounded, nom: context.t('retirer'), taille: 28, onTap: fichiers.length > 1 ? () => onRetirer(f) : null),
                ],
              ),
            ),
          if (fichiers.length > montres.length)
            Text(context.t('et_n_autres', {'n': '${fichiers.length - montres.length}'}), style: Typo.secondaire.copyWith(color: p.texte2)),
          const SizedBox(height: 8),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              onPressed: onAjouter,
              icon: Icon(Icons.add_rounded, color: p.accentTexte),
              label: Text(context.t('ajouter_fichiers'), style: Typo.secondaire.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

IconData iconeFichier(String nom) {
  final ext = nom.contains('.') ? nom.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'heic' || 'webp' => Icons.image_rounded,
    'mp4' || 'mov' || 'mkv' || 'avi' || 'webm' => Icons.movie_rounded,
    'mp3' || 'wav' || 'm4a' || 'flac' || 'ogg' => Icons.audiotrack_rounded,
    'zip' || 'rar' || '7z' || 'tar' || 'gz' || 'xz' => Icons.folder_zip_rounded,
    'pdf' => Icons.picture_as_pdf_rounded,
    'exe' || 'msi' || 'apk' || 'dmg' || 'pkg' || 'deb' || 'appimage' => Icons.inventory_2_rounded,
    _ => Icons.insert_drive_file_rounded,
  };
}
