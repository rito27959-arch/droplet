// L'ACCUEIL — envoyer ou recevoir, et les appareils autour. Rien d'autre :
// le partage reste au centre.
import 'package:flutter/material.dart';

import '../app/etat_app.dart';
import '../app/modeles.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/marque.dart';
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
                              Row(
                                children: [
                                  const Goutte(taille: 44),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Semantics(header: true, child: Text('Droplet Drop', style: Typo.grandTitre.copyWith(color: p.texte))),
                                        Text(context.t('slogan'), style: Typo.corps.copyWith(color: p.texte2)),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 28),
                              if (e.erreurDemarrage != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
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
                              BoutonLiquide(
                                texte: context.t('envoyer'),
                                icone: Icons.arrow_upward_rounded,
                                hauteur: 64,
                                onTap: e.pret ? () => choisirPuisEnvoyer(context) : null,
                                chargement: !e.pret && e.erreurDemarrage == null,
                              ),
                              const SizedBox(height: 12),
                              BoutonSecondaire(
                                texte: context.t('recevoir'),
                                icone: Icons.arrow_downward_rounded,
                                hauteur: 60,
                                onTap: e.pret ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Recevoir())) : null,
                              ),
                              const CartePareFeu(),
                              if (enCours.isNotEmpty) ...[
                                TitreSection(context.t('en_cours')),
                                for (final g in enCours) _CarteEnCours(groupe: g),
                              ],
                              TitreSection(
                                context.t('a_proximite'),
                                // La découverte tourne en continu : une pastille qui respire le dit.
                                fin: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (e.pret) Pulsation(couleur: p.succes, taille: 6),
                                    if (e.appareils.isNotEmpty) Text('${e.appareils.length}', style: Typo.legende.copyWith(color: p.texte3)),
                                  ],
                                ),
                              ),
                              if (e.appareils.isEmpty)
                                // Personne encore : le radar, comme AirDrop quand il cherche.
                                Carte(
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 8),
                                    child: Column(
                                      children: [
                                        Radar(
                                          taille: 170,
                                          child: AvatarAppareil(plateforme: EtatApp.plateforme(), empreinte: e.empreinte, taille: 56),
                                        ),
                                        Text(context.t('recherche_appareils'), textAlign: TextAlign.center, style: Typo.titreCarte.copyWith(color: p.texte)),
                                        const SizedBox(height: 6),
                                        ConstrainedBox(
                                          constraints: const BoxConstraints(maxWidth: 380),
                                          child: Text(context.t('personne_texte'), textAlign: TextAlign.center, style: Typo.secondaire.copyWith(color: p.texte2)),
                                        ),
                                        const SizedBox(height: 14),
                                        BoutonSecondaire(
                                          texte: context.t('recevoir'),
                                          icone: Icons.qr_code_2_rounded,
                                          hauteur: 44,
                                          large: false,
                                          onTap: e.pret ? () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const Recevoir())) : null,
                                        ),
                                        const SizedBox(height: 6),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                for (final (i, a) in e.appareils.values.indexed)
                                  Padding(
                                    padding: const EdgeInsets.only(bottom: 10),
                                    child: Apparition(delai: i * 40, child: CarteAppareil(appareil: a)),
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
