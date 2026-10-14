// LES FICHIERS REÇUS — rangés par type, comme dans Xender : Photos, Vidéos,
// Musique, Applications, Documents. Les plus récents d'abord.
//
//   • Toucher un fichier l'ouvre dans l'app qui convient ; une application
//     reçue s'installe (Android demande toujours confirmation).
//   • Une application en plusieurs APK arrive en dossier : elle s'installe
//     d'un toucher, comme une seule.
//   • Appui long : partager, ou supprimer.
//
// La liste vient du DOSSIER de réception lui-même, pas de l'historique : un
// fichier déplacé ou supprimé ailleurs n'y apparaît plus.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/etat_app.dart';
import '../app/natif.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/typo.dart';
import 'choisir.dart' show iconeFichier, estMobile;
import 'transfert.dart' show confirmer;

enum Genre { tout, photos, videos, musique, apps, documents }

class Recu {
  Recu(this.chemin, this.nom, this.taille, this.date, this.genre, {this.dossierApp = false});

  final String chemin;
  final String nom;
  final int taille;
  final DateTime date;
  final Genre genre;

  /// Un dossier d'APK (application découpée).
  final bool dossierApp;
}

Genre genreDe(String nom) {
  final ext = nom.contains('.') ? nom.split('.').last.toLowerCase() : '';
  return switch (ext) {
    'jpg' || 'jpeg' || 'png' || 'gif' || 'heic' || 'heif' || 'webp' || 'bmp' => Genre.photos,
    'mp4' || 'mov' || 'mkv' || 'avi' || 'webm' || '3gp' || 'm4v' => Genre.videos,
    'mp3' || 'wav' || 'm4a' || 'flac' || 'ogg' || 'aac' || 'opus' => Genre.musique,
    'apk' || 'apks' || 'xapk' => Genre.apps,
    _ => Genre.documents,
  };
}

/// Lit le dossier de réception (et ses sous-dossiers ; le dossier caché des
/// reprises est ignoré).
Future<List<Recu>> lireRecus(String racine) async {
  final l = <Recu>[];
  final d = Directory(racine);
  if (!await d.exists()) return l;
  Future<void> parcourir(Directory dir, int profondeur) async {
    await for (final e in dir.list(followLinks: false)) {
      final nom = e.path.split(Platform.pathSeparator).last;
      if (nom.startsWith('.')) continue;
      if (e is File) {
        final s = await e.stat();
        l.add(Recu(e.path, nom, s.size, s.modified, genreDe(nom)));
      } else if (e is Directory && profondeur < 6) {
        // Un dossier qui ne contient que des APK : une application.
        final enfants = await e.list().toList();
        final apk = enfants.whereType<File>().where((f) => f.path.toLowerCase().endsWith('.apk')).toList();
        if (apk.isNotEmpty && apk.length == enfants.length) {
          var taille = 0;
          var date = DateTime(1970);
          for (final f in apk) {
            final s = await f.stat();
            taille += s.size;
            if (s.modified.isAfter(date)) date = s.modified;
          }
          l.add(Recu(e.path, nom, taille, date, Genre.apps, dossierApp: true));
        } else {
          await parcourir(e, profondeur + 1);
        }
      }
    }
  }

  await parcourir(d, 0);
  l.sort((a, b) => b.date.compareTo(a.date));
  return l;
}

/// Ouvre (ou installe) un fichier reçu, sur chaque plateforme.
Future<void> ouvrirRecu(BuildContext context, Recu r) async {
  if (Natif.android) {
    final res = await Natif.ouvrir(r.chemin);
    if (!context.mounted) return;
    final cle = switch (res) {
      'autorisation' => 'installer_autorisation',
      'aucune_app' => 'aucune_app_ouvrir',
      'ouvert' || 'lancee' => null,
      _ => 'ouverture_impossible',
    };
    if (cle != null) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t(cle))));
    return;
  }
  if (estMobile) {
    await Share.shareXFiles([XFile(r.chemin)]);
  } else {
    await launchUrl(Uri.file(r.chemin));
  }
}

class EcranRecus extends StatefulWidget {
  const EcranRecus({super.key});

  @override
  State<EcranRecus> createState() => _EcranRecusState();
}

class _EcranRecusState extends State<EcranRecus> {
  Genre _genre = Genre.tout;
  List<Recu>? _recus;
  StreamSubscription<Object?>? _abonnement;

  @override
  void initState() {
    super.initState();
    _charger();
    // Un transfert se termine : la liste se met à jour.
    _abonnement = EtatApp.i.finis.stream.listen((_) => _charger());
  }

  @override
  void dispose() {
    _abonnement?.cancel();
    super.dispose();
  }

  Future<void> _charger() async {
    final l = await lireRecus(EtatApp.i.reception);
    if (mounted) setState(() => _recus = l);
  }

  Future<void> _actions(Recu r) async {
    final p = context.p;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Carte(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Ligne(
                  icone: r.genre == Genre.apps ? Icons.install_mobile_rounded : Icons.open_in_new_rounded,
                  titre: c.t(r.genre == Genre.apps && Natif.android ? 'installer' : 'ouvrir'),
                  fin: const SizedBox.shrink(),
                  onTap: () {
                    Navigator.pop(c);
                    ouvrirRecu(context, r);
                  },
                ),
                if (!r.dossierApp)
                  Ligne(
                    icone: Icons.ios_share_rounded,
                    teinte: const Color(0xFF4855E8),
                    titre: c.t('partager'),
                    fin: const SizedBox.shrink(),
                    onTap: () {
                      Navigator.pop(c);
                      Share.shareXFiles([XFile(r.chemin)]);
                    },
                  ),
                Ligne(
                  icone: Icons.delete_outline_rounded,
                  teinte: p.erreur,
                  titre: c.t('supprimer'),
                  fin: const SizedBox.shrink(),
                  onTap: () async {
                    Navigator.pop(c);
                    if (!await confirmer(context, context.t('supprimer_fichier'), r.nom)) return;
                    try {
                      if (r.dossierApp) {
                        await Directory(r.chemin).delete(recursive: true);
                      } else {
                        await File(r.chemin).delete();
                      }
                    } catch (_) {}
                    _charger();
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final tout = _recus;
    final options = <(Genre, String, IconData?)>[
      (Genre.tout, context.t('tout'), null),
      (Genre.photos, context.t('onglet_photos'), null),
      (Genre.videos, context.t('onglet_videos'), null),
      (Genre.musique, context.t('onglet_musique'), null),
      (Genre.apps, context.t('onglet_apps'), null),
      (Genre.documents, context.t('documents'), null),
    ];
    final liste = tout == null ? null : (_genre == Genre.tout ? tout : tout.where((r) => r.genre == _genre).toList());
    return Scaffold(
      backgroundColor: p.fond,
      appBar: AppBar(
        backgroundColor: p.fond,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: p.accentTexte),
        title: Text(context.t('recus'), style: Typo.titreCarte.copyWith(color: p.texte)),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: MediaQuery.sizeOf(context).width - 32),
                child: Segments<Genre>(options: options, valeur: _genre, onChange: (g) => setState(() => _genre = g)),
              ),
            ),
          ),
          Expanded(
            child: liste == null
                ? const Center(child: CircularProgressIndicator.adaptive())
                : liste.isEmpty
                    ? Center(child: EtatVide(icone: Icons.inbox_rounded, titre: context.t('aucun_recu'), texte: context.t('aucun_recu_texte')))
                    : RefreshIndicator(
                        onRefresh: _charger,
                        child: _genre == Genre.photos || _genre == Genre.videos
                            ? GridView.builder(
                                padding: const EdgeInsets.fromLTRB(2, 0, 2, 24),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: (MediaQuery.sizeOf(context).width / 120).floor().clamp(3, 8), mainAxisSpacing: 2, crossAxisSpacing: 2),
                                itemCount: liste.length,
                                itemBuilder: (context, i) {
                                  final r = liste[i];
                                  return GestureDetector(
                                    onTap: () => ouvrirRecu(context, r),
                                    onLongPress: () => _actions(r),
                                    child: r.genre == Genre.photos
                                        ? Image.file(File(r.chemin), fit: BoxFit.cover, cacheWidth: 320, errorBuilder: (_, _, _) => ColoredBox(color: p.surfaceHaute, child: Icon(Icons.image_rounded, color: p.texte3)))
                                        : ColoredBox(color: p.surfaceHaute, child: Icon(Icons.play_circle_fill_rounded, color: p.texte2, size: 36)),
                                  );
                                },
                              )
                            : ListView.builder(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                                itemCount: liste.length,
                                itemBuilder: (context, i) {
                                  final r = liste[i];
                                  return Pressable(
                                    onTap: () => ouvrirRecu(context, r),
                                    semantique: r.nom,
                                    child: GestureDetector(
                                      onLongPress: () => _actions(r),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(vertical: 7),
                                        child: Row(
                                          children: [
                                            ClipRRect(
                                              borderRadius: BorderRadius.circular(10),
                                              child: SizedBox(
                                                width: 46,
                                                height: 46,
                                                child: r.genre == Genre.photos
                                                    ? Image.file(File(r.chemin), fit: BoxFit.cover, cacheWidth: 120, errorBuilder: (_, _, _) => const SizedBox())
                                                    : DecoratedBox(
                                                        decoration: BoxDecoration(gradient: r.genre == Genre.apps ? p.liquide : null, color: r.genre == Genre.apps ? null : p.surfaceHaute),
                                                        child: Icon(r.genre == Genre.apps ? Icons.android_rounded : iconeFichier(r.nom), color: r.genre == Genre.apps ? Colors.white : p.texte2),
                                                      ),
                                              ),
                                            ),
                                            const SizedBox(width: 14),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  Text(r.nom, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.corps.copyWith(color: p.texte, fontWeight: FontWeight.w500)),
                                                  Text(tailleLocale(r.taille), style: Typo.secondaire.copyWith(color: p.texte2)),
                                                ],
                                              ),
                                            ),
                                            if (r.genre == Genre.apps && Natif.android)
                                              TextButton(onPressed: () => ouvrirRecu(context, r), child: Text(context.t('installer'), style: Typo.secondaire.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600))),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
          ),
        ],
      ),
    );
  }
}
