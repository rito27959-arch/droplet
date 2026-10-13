// L'HISTORIQUE — ce qui a été envoyé et reçu. Ouvrir un fichier, voir où
// il est, retirer une ligne. Effacer l'historique ne supprime aucun fichier.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/etat_app.dart';
import '../app/modeles.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/typo.dart';
import 'choisir.dart' show iconeFichier, estMobile;
import 'transfert.dart';

class EcranHistorique extends StatefulWidget {
  const EcranHistorique({super.key});

  @override
  State<EcranHistorique> createState() => _EcranHistoriqueState();
}

class _EcranHistoriqueState extends State<EcranHistorique> {
  String _q = '';
  int _filtre = 0; // 0 tous, 1 envoyés, 2 reçus

  Future<void> _ouvrir(EntreeHistorique h) async {
    if (h.chemins.isEmpty) return;
    final chemin = h.chemins.first;
    if (!File(chemin).existsSync()) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('fichier_deplace'))));
      return;
    }
    if (estMobile) {
      await Share.shareXFiles([for (final c in h.chemins.take(20)) XFile(c)]);
    } else {
      await launchUrl(Uri.file(chemin));
    }
  }

  Future<void> _emplacement(EntreeHistorique h) async {
    if (h.chemins.isEmpty) return;
    await launchUrl(Uri.file(File(h.chemins.first).parent.path));
  }

  Future<void> _actions(EntreeHistorique h) async {
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
                if (!h.envoi && h.chemins.isNotEmpty) ...[
                  Ligne(
                    icone: estMobile ? Icons.ios_share_rounded : Icons.open_in_new_rounded,
                    titre: estMobile ? c.t('partager') : c.t('ouvrir'),
                    fin: const SizedBox.shrink(),
                    onTap: () {
                      Navigator.pop(c);
                      _ouvrir(h);
                    },
                  ),
                  if (!estMobile)
                    Ligne(
                      icone: Icons.folder_open_rounded,
                      teinte: const Color(0xFF4855E8),
                      titre: c.t('afficher_emplacement'),
                      fin: const SizedBox.shrink(),
                      onTap: () {
                        Navigator.pop(c);
                        _emplacement(h);
                      },
                    ),
                ],
                Ligne(
                  icone: Icons.delete_outline_rounded,
                  teinte: p.erreur,
                  titre: c.t('retirer_historique'),
                  fin: const SizedBox.shrink(),
                  onTap: () {
                    Navigator.pop(c);
                    EtatApp.i.effacerHistorique(h.id);
                    setState(() {});
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
    return ListenableBuilder(
      listenable: EtatApp.i,
      builder: (context, _) {
        final tout = EtatApp.i.pret ? EtatApp.i.historique(_q) : <EntreeHistorique>[];
        final liste = tout.where((h) => _filtre == 0 || (_filtre == 1) == h.envoi).toList();
        return Scaffold(
          backgroundColor: p.fond,
          appBar: AppBar(
            backgroundColor: p.fond,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: p.accentTexte),
            title: Text(context.t('historique'), style: Typo.titreCarte.copyWith(color: p.texte)),
            actions: [
              if (tout.isNotEmpty)
                TextButton(
                  onPressed: () async {
                    if (await confirmer(context, context.t('effacer_historique'), context.t('effacer_historique_texte'))) {
                      EtatApp.i.effacerHistorique();
                    }
                  },
                  child: Text(context.t('tout_effacer'), style: Typo.secondaire.copyWith(color: p.erreur)),
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              Colonne(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      onChanged: (v) => setState(() => _q = v),
                      decoration: InputDecoration(
                        hintText: context.t('rechercher'),
                        prefixIcon: Icon(Icons.search_rounded, color: p.texte2),
                        filled: true,
                        fillColor: p.surfaceHaute,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                        contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Segments<int>(
                      options: [(0, context.t('tous'), null), (1, context.t('envoyes'), Icons.north_east_rounded), (2, context.t('recus'), Icons.south_west_rounded)],
                      valeur: _filtre,
                      onChange: (v) => setState(() => _filtre = v),
                    ),
                    const SizedBox(height: 12),
                    if (liste.isEmpty)
                      EtatVide(icone: Icons.history_rounded, titre: context.t('historique_vide'), texte: context.t('historique_vide_texte'))
                    else
                      for (final (i, h) in liste.indexed) ...[
                        // Les jours, comme dans Photos ou Fichiers : « Aujourd'hui »,
                        // « Hier », puis la date.
                        if (i == 0 || !_memeJour(liste[i - 1].fin, h.fin)) TitreSection(_jour(context, h.fin)),
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Carte(
                            onTap: () => _actions(h),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(color: p.surfaceHaute, borderRadius: BorderRadius.circular(12)),
                                  child: Icon(iconeFichier(h.titre), color: p.accentTexte),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(h.titre, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.titreCarte.copyWith(color: p.texte)),
                                      Text(
                                        '${h.envoi ? context.t('vers', {'qui': h.appareil}) : context.t('de', {'qui': h.appareil})} · ${tailleLocale(h.taille)} · ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(h.fin))}',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Typo.secondaire.copyWith(color: p.texte2),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  h.etat == EtatTransfert.termine ? (h.envoi ? Icons.north_east_rounded : Icons.south_west_rounded) : Icons.block_rounded,
                                  size: 18,
                                  color: h.etat == EtatTransfert.termine ? p.succes : p.texte3,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static bool _memeJour(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

  static String _jour(BuildContext context, DateTime d) {
    final maintenant = DateTime.now();
    if (_memeJour(d, maintenant)) return context.t('aujourd_hui');
    if (_memeJour(d, maintenant.subtract(const Duration(days: 1)))) return context.t('hier');
    return MaterialLocalizations.of(context).formatMediumDate(d);
  }
}
