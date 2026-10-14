// L'ACCUEIL — envoyer ou recevoir, et les appareils autour. Rien d'autre :
// le partage reste au centre.
import 'package:flutter/material.dart';

import '../app/etat_app.dart';
import '../app/modeles.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/marque.dart';
import '../design/scene.dart';
import '../design/typo.dart';
import 'choisir.dart';
import 'group_drop.dart';
import 'historique.dart';
import 'pare_feu.dart';
import 'recevoir.dart';
import 'recus.dart';
import 'reglages.dart';
import 'transfert.dart';
import 'depot.dart';

class Accueil extends StatelessWidget {
  const Accueil({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: EtatApp.i,
      builder: (context, _) {
        final e = EtatApp.i;
        final p = context.p;
        final enCours = _groupesEnCours(e);
        return ZoneDepot(
          child: Raccourcis(
            child: Scaffold(
          backgroundColor: p.fond,
          body: Fond(
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 24),
                      children: [
                        Colonne(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // La marque, discrète ; puis le titre du site.
                              Row(
                                children: [
                                  const Goutte(taille: 30),
                                  const SizedBox(width: 10),
                                  Semantics(header: true, child: Text('Droplet Drop', style: Typo.titreCarte.copyWith(color: p.texte, fontWeight: FontWeight.w700))),
                                ],
                              ),
                              const SizedBox(height: 22),
                              Text(context.t('hero_accueil'), style: Typo.hero.copyWith(color: p.texte, fontSize: MediaQuery.sizeOf(context).width < 420 ? 30 : 38)),
                              const SizedBox(height: 8),
                              if (e.erreurDemarrage != null)
                                Padding(
                                  padding: const EdgeInsets.only(top: 12),
                                  child: Carte(
                                    child: Row(
                                      children: [
                                        Icon(Icons.error_outline_rounded, color: p.erreur),
                                        const SizedBox(width: 12),
                                        Expanded(child: Text(context.t('erreur_demarrage'), style: Typo.secondaire.copyWith(color: p.texte))),
                                      ],
                                    ),
                                  ),
                                ),
                              // Les appareils autour de vous : la constellation du site.
                              Constellation(
                                hauteur: MediaQuery.sizeOf(context).width > 700 ? 340 : 300,
                                centre: const CentreMoi(taille: 58),
                                noeuds: [
                                  for (final a in e.appareils.values)
                                    NoeudConstellation(id: a.id, nom: a.nom, plateforme: a.plateforme, empreinte: a.empreinte),
                                ],
                                onTap: e.pret ? (n) => choisirPuisEnvoyer(context, vers: e.appareils[n.id]) : null,
                              ),
                              Center(
                                child: AnimatedSwitcher(
                                  duration: duree(context, 260),
                                  child: Text(
                                    e.appareils.isEmpty ? context.t('recherche_appareils') : context.t('toucher_appareil'),
                                    key: ValueKey(e.appareils.isEmpty),
                                    textAlign: TextAlign.center,
                                    style: Typo.secondaire.copyWith(color: p.texte2),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 22),
                              Row(
                                children: [
                                  Expanded(
                                    child: BoutonLiquide(
                                      texte: context.t('envoyer'),
                                      icone: Icons.arrow_upward_rounded,
                                      hauteur: 58,
                                      onTap: e.pret ? () => choisirPuisEnvoyer(context) : null,
                                      chargement: !e.pret && e.erreurDemarrage == null,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: BoutonSecondaire(
                                      texte: context.t('recevoir'),
                                      icone: Icons.arrow_downward_rounded,
                                      hauteur: 58,
                                      onTap: e.pret ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Recevoir())) : null,
                                    ),
                                  ),
                                ],
                              ),
                              const CartePareFeu(),
                              if (enCours.isNotEmpty) ...[
                                TitreSection(context.t('en_cours')),
                                for (final g in enCours) _CarteEnCours(groupe: g),
                              ],
                              if (e.appareils.isNotEmpty) ...[
                                TitreSection(
                                  context.t('a_proximite'),
                                  // La découverte tourne en continu : une pastille qui respire le dit.
                                  fin: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (e.pret) Pulsation(couleur: p.succes, taille: 6),
                                      Text('${e.appareils.length}', style: Typo.legende.copyWith(color: p.texte3)),
                                    ],
                                  ),
                                ),
                                for (final (i, a) in e.appareils.values.indexed)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Apparition(delai: i * 40, child: CarteAppareil(appareil: a)),
                                  ),
                              ] else
                                Padding(
                                  padding: const EdgeInsets.only(top: 18),
                                  child: Text(context.t('personne_texte'), textAlign: TextAlign.center, style: Typo.secondaire.copyWith(color: p.texte3)),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const _Barre(),
                ],
              ),
            ),
          ),
            ),
          ),
        );
      },
    );
  }

  /// Les envois et réceptions non terminés, un par groupe.
  static List<List<Transfert>> _groupesEnCours(EtatApp e) {
    final groupes = <String, List<Transfert>>{};
    for (final t in e.transferts.values) {
      if (e.mesSessions.containsKey(t.groupe)) continue;
      (groupes[t.groupe.isEmpty ? t.id : t.groupe] ??= []).add(t);
    }
    return groupes.values.where((l) => l.any((t) => !t.etat.finale)).toList();
  }
}

class CarteAppareil extends StatelessWidget {
  const CarteAppareil({super.key, required this.appareil, this.selectionne, this.onTap});

  final AppareilVu appareil;
  final bool? selectionne;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Carte(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      selectionnee: selectionne ?? false,
      onTap: onTap ?? () => choisirPuisEnvoyer(context, vers: appareil),
      child: Row(
        children: [
          AvatarAppareil(plateforme: appareil.plateforme, empreinte: appareil.empreinte),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(appareil.nom.isEmpty ? appareil.courte : appareil.nom, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.titreCarte.copyWith(color: p.texte)),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(width: 7, height: 7, decoration: BoxDecoration(color: p.succes, shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${nomPlateforme(appareil.plateforme)} · ${appareil.courte}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Typo.secondaire.copyWith(color: p.texte2),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (selectionne == null)
            Icon(Icons.chevron_right_rounded, color: p.texte3)
          else
            AnimatedContainer(
              duration: duree(context, 200),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: selectionne! ? p.liquide : null,
                border: selectionne! ? null : Border.all(color: p.texte3, width: 1.6),
              ),
              child: selectionne! ? const Icon(Icons.check_rounded, size: 17, color: Colors.white) : null,
            ),
        ],
      ),
    );
  }
}

String nomPlateforme(String p) => switch (p) {
      'android' => 'Android',
      'ios' => 'iPhone',
      'macos' => 'Mac',
      'windows' => 'Windows',
      'linux' => 'Linux',
      _ => tr('appareil'),
    };

class _CarteEnCours extends StatelessWidget {
  const _CarteEnCours({required this.groupe});

  final List<Transfert> groupe;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final total = groupe.fold<int>(0, (a, t) => a + t.total);
    final fait = groupe.fold<int>(0, (a, t) => a + t.octets);
    final premier = groupe.first;
    final titre = premier.fichiers.isEmpty
        ? context.t('preparation')
        : premier.fichiers.length == 1
            ? premier.fichiers.first.nom
            : context.t('n_fichiers', {'n': '${premier.fichiers.length}'});
    final qui = groupe.length == 1 ? premier.pair.nom : context.t('n_appareils', {'n': '${groupe.length}'});
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Carte(
        onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EcranTransfert(groupe: premier.groupe.isEmpty ? premier.id : premier.groupe))),
        child: Row(
          children: [
            AnneauProgression(
              valeur: total == 0 ? 0 : fait / total,
              taille: 44,
              centre: Icon(premier.envoi ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded, size: 18, color: p.accentTexte),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titre, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.titreCarte.copyWith(color: p.texte)),
                  const SizedBox(height: 2),
                  Text(
                    '${premier.envoi ? context.t('vers', {'qui': qui}) : context.t('de', {'qui': qui})} · ${tailleLocale(fait)} / ${tailleLocale(total)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Typo.chiffres.copyWith(color: p.texte2),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: p.texte3),
          ],
        ),
      ),
    );
  }
}

/// La barre du bas : historique, distributions, réglages.
class _Barre extends StatelessWidget {
  const _Barre();

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    Widget entree(IconData i, String nom, Widget Function() ecran) => Expanded(
          child: Pressable(
            semantique: nom,
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ecran())),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(i, color: p.texte2, size: 24),
                  const SizedBox(height: 4),
                  Text(nom, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.legende.copyWith(color: p.texte2)),
                ],
              ),
            ),
          ),
        );
    return Givre(
      child: SafeArea(
        top: false,
        child: Colonne(
          max: 560,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                entree(Icons.inbox_rounded, context.t('recus'), () => const EcranRecus()),
                entree(Icons.history_rounded, context.t('historique'), () => const EcranHistorique()),
                entree(Icons.groups_2_rounded, context.t('group_drop'), () => const EcranGroupDrop()),
                entree(Icons.tune_rounded, context.t('reglages'), () => const EcranReglages()),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
