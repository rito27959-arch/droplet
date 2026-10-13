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
                  ListTile(
                    leading: Icon(estMobile ? Icons.ios_share_rounded : Icons.open_in_new_rounded, color: p.accentTexte),
                    title: Text(estMobile ? c.t('partager') : c.t('ouvrir'), style: Typo.corps.copyWith(color: p.texte)),
                    onTap: () {
                      Navigator.pop(c);
                      _ouvrir(h);
                    },
                  ),
                  if (!estMobile)
                    ListTile(
                      leading: Icon(Icons.folder_open_rounded, color: p.accentTexte),
                      title: Text(c.t('afficher_emplacement'), style: Typo.corps.copyWith(color: p.texte)),
                      onTap: () {
                        Navigator.pop(c);
                        _emplacement(h);
                      },
                    ),
                ],
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded, color: p.erreur),
                  title: Text(c.t('retirer_historique'), style: Typo.corps.copyWith(color: p.erreur)),
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
                    SegmentedButton<int>(
                      segments: [
                        ButtonSegment(value: 0, label: Text(context.t('tous'))),
                        ButtonSegment(value: 1, label: Text(context.t('envoyes'))),
                        ButtonSegment(value: 2, label: Text(context.t('recus'))),
                      ],
                      selected: {_filtre},
                      onSelectionChanged: (s) => setState(() => _filtre = s.first),
                    ),
                    const SizedBox(height: 12),
                    if (liste.isEmpty)
                      EtatVide(icone: Icons.history_rounded, titre: context.t('historique_vide'), texte: context.t('historique_vide_texte'))
                    else
                      for (final h in liste)
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
                                        '${h.envoi ? context.t('vers', {'qui': h.appareil}) : context.t('de', {'qui': h.appareil})} · ${tailleLocale(h.taille)} · ${MaterialLocalizations.of(context).formatShortDate(h.fin)}',
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
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
