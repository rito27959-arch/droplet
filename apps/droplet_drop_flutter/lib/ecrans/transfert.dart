// UN TRANSFERT EN COURS — un ou plusieurs destinataires, chacun son état,
// son débit mesuré et son temps restant. À la fin, une confirmation courte.
import 'package:flutter/material.dart';

import '../app/etat_app.dart';
import '../app/modeles.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/marque.dart';
import '../design/typo.dart';

class EcranTransfert extends StatelessWidget {
  const EcranTransfert({super.key, required this.groupe});

  final String groupe;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ListenableBuilder(
      listenable: EtatApp.i,
      builder: (context, _) {
        final e = EtatApp.i;
        final liste = e.groupe(groupe);
        final prep = e.preparations[groupe];
        final enPreparation = liste.isEmpty || (liste.every((t) => t.etat == EtatTransfert.enAttente) && prep != null && prep.$1 < prep.$2);
        final total = liste.fold<int>(0, (a, t) => a + t.total);
        final fait = liste.fold<int>(0, (a, t) => a + t.octets);
        final debit = liste.fold<int>(0, (a, t) => a + t.debit);
        final termines = liste.where((t) => t.etat == EtatTransfert.termine).length;
        final finis = liste.isNotEmpty && liste.every((t) => t.etat.finale);
        final restant = liste.map((t) => t.restant ?? 0).fold<int>(0, (a, b) => a > b ? a : b);
        final premier = liste.isEmpty ? null : liste.first;
        final enPause = liste.isNotEmpty && liste.where((t) => !t.etat.finale).every((t) => t.etat == EtatTransfert.interrompu);
        final envoi = premier?.envoi ?? true;
        final titre = premier == null || premier.fichiers.isEmpty
            ? context.t('preparation')
            : premier.fichiers.length == 1
                ? premier.fichiers.first.nom
                : context.t('n_fichiers', {'n': '${premier.fichiers.length}'});

        return Scaffold(
          backgroundColor: p.fond,
          appBar: AppBar(
            backgroundColor: p.fond,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: p.accentTexte),
            title: Text(envoi ? context.t('envoi') : context.t('reception'), style: Typo.titreCarte.copyWith(color: p.texte)),
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
                          Center(
                            child: AnimatedSwitcher(
                              duration: duree(context, 420),
                              switchInCurve: kRessort,
                              transitionBuilder: (c, a) => ScaleTransition(scale: a, child: FadeTransition(opacity: a, child: c)),
                              child: finis && termines == liste.length
                                  ? _Reussite(key: const ValueKey('ok'))
                                  : AnneauProgression(
                                      key: const ValueKey('anneau'),
                                      valeur: enPreparation ? ((prep?.$2 ?? 0) == 0 ? 0 : prep!.$1 / prep.$2) : (total == 0 ? 0 : fait / total),
                                      taille: 168,
                                      epaisseur: 10,
                                      centre: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            '${(100 * (enPreparation ? ((prep?.$2 ?? 0) == 0 ? 0 : prep!.$1 / prep.$2) : (total == 0 ? 0 : fait / total))).floor()} %',
                                            style: Typo.grandChiffre.copyWith(color: p.texte, fontSize: 36),
                                          ),
                                          if (debit > 0 && !enPreparation) Text(debitLocal(debit), style: Typo.chiffres.copyWith(color: p.texte2)),
                                        ],
                                      ),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 22),
                          Text(titre, textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis, style: Typo.titre.copyWith(color: p.texte)),
                          const SizedBox(height: 6),
                          Text(
                            enPreparation
                                ? context.t('preparation_texte')
                                : finis
                                    ? (termines == liste.length ? context.t('tout_termine') : context.t('x_sur_y_termines', {'x': '$termines', 'y': '${liste.length}'}))
                                    : [
                                        '${tailleLocale(fait)} / ${tailleLocale(total)}',
                                        if (liste.length > 1) context.t('x_sur_y_termines', {'x': '$termines', 'y': '${liste.length}'}),
                                        if (restant > 0) context.t('restant', {'d': dureeLocale(restant)}),
                                      ].join(' · '),
                            textAlign: TextAlign.center,
                            style: Typo.chiffres.copyWith(color: p.texte2),
                          ),
                          TitreSection(envoi ? context.t('destinataires') : context.t('expediteur')),
                          for (final t in liste) Padding(padding: const EdgeInsets.only(bottom: 10), child: LigneTransfert(t: t)),
                          if (finis && !envoi && termines > 0 && premier!.chemins.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Text(context.t('enregistre_dans', {'d': EtatApp.i.reception}), style: Typo.secondaire.copyWith(color: p.texte2)),
                          ],
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
                      child: finis
                          ? BoutonLiquide(texte: context.t('termine'), onTap: () => Navigator.of(context).pop())
                          : Row(
                              children: [
                                if (envoi) ...[
                                  Expanded(
                                    child: BoutonSecondaire(
                                      texte: enPause ? context.t('reprendre') : context.t('pause'),
                                      icone: enPause ? Icons.play_arrow_rounded : Icons.pause_rounded,
                                      onTap: () => enPause ? e.reprendre(groupe) : e.pause(groupe),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                ],
                                Expanded(
                                  child: BoutonSecondaire(
                                    texte: context.t('annuler'),
                                    icone: Icons.close_rounded,
                                    couleur: p.erreur,
                                    onTap: () async {
                                      if (await confirmer(context, context.t('annuler_transfert'), context.t('annuler_transfert_texte'))) {
                                        e.annuler(groupe);
                                      }
                                    },
                                  ),
                                ),
                              ],
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

class _Reussite extends StatelessWidget {
  const _Reussite({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Semantics(
      label: tr('tout_termine'),
      child: Container(
        width: 168,
        height: 168,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: p.liquide,
          boxShadow: [BoxShadow(color: p.accent.withValues(alpha: 0.35), blurRadius: 40, offset: const Offset(0, 14))],
        ),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 84),
      ),
    );
  }
}

/// Une ligne par destinataire (ou l'expéditeur) : état, barre, débit.
class LigneTransfert extends StatelessWidget {
  const LigneTransfert({super.key, required this.t, this.actions});

  final Transfert t;
  final Widget? actions;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final (couleur, libelle) = presentation(context, t);
    return Carte(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              AvatarAppareil(plateforme: t.pair.plateforme, empreinte: t.pair.empreinte, taille: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.pair.nom.isEmpty ? t.pair.courte : t.pair.nom, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.titreCarte.copyWith(color: p.texte)),
                    Text(
                      t.etat.actif && t.debit > 0
                          ? [debitLocal(t.debit), if (t.restant != null) context.t('restant', {'d': dureeLocale(t.restant!)})].join(' · ')
                          : '${tailleLocale(t.octets)} / ${tailleLocale(t.total)}',
                      style: Typo.chiffres.copyWith(color: p.texte2, fontSize: 13),
                    ),
                  ],
                ),
              ),
              PastilleEtat(couleur: couleur, libelle: libelle),
              ?actions,
            ],
          ),
          if (!t.etat.finale || t.etat == EtatTransfert.termine) ...[
            const SizedBox(height: 12),
            BarreProgression(valeur: t.progression, couleur: t.etat == EtatTransfert.termine ? p.succes : (t.etat == EtatTransfert.interrompu ? p.attention : null)),
          ],
          if (t.erreur != null && (t.etat == EtatTransfert.echec || t.etat == EtatTransfert.interrompu)) ...[
            const SizedBox(height: 10),
            Text(messageErreur(t.erreur!, interrompu: t.etat == EtatTransfert.interrompu), style: Typo.secondaire.copyWith(color: t.etat == EtatTransfert.echec ? p.erreur : p.texte2)),
          ],
        ],
      ),
    );
  }
}

class PastilleEtat extends StatelessWidget {
  const PastilleEtat({super.key, required this.couleur, required this.libelle});

  final Color couleur;
  final String libelle;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: duree(context, 250),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: couleur.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
      child: Text(libelle, style: Typo.legende.copyWith(color: couleur, fontWeight: FontWeight.w600)),
    );
  }
}

/// La couleur et le nom de chaque état — les mêmes partout.
(Color, String) presentation(BuildContext context, Transfert t) {
  final p = context.p;
  return switch (t.etat) {
    EtatTransfert.enAttente => (p.texte2, context.t('etat_attente')),
    EtatTransfert.connexion => (p.accentTexte, context.t('etat_connexion')),
    EtatTransfert.attenteReponse => (p.attention, context.t('etat_attente_reponse')),
    EtatTransfert.transfert => (p.accentTexte, context.t('etat_transfert')),
    EtatTransfert.interrompu => (p.attention, context.t('etat_interrompu')),
    EtatTransfert.reprise => (p.accentTexte, context.t('etat_reprise')),
    EtatTransfert.verification => (p.accentTexte, context.t('etat_verification')),
    EtatTransfert.termine => (p.succes, context.t('etat_termine')),
    EtatTransfert.refuse => (p.texte2, context.t('etat_refuse')),
    EtatTransfert.annule => (p.texte2, context.t('etat_annule')),
    EtatTransfert.echec => (p.erreur, context.t('etat_echec')),
  };
}

/// Une phrase claire pour chaque code d'erreur du moteur.
String messageErreur(String code, {bool interrompu = false}) {
  final cle = 'err_$code';
  final m = tr(cle);
  final base = m == cle ? tr('err_inconnue') : m;
  return interrompu && code == 'connexion_interrompue' ? '$base ${tr('err_reprise_auto')}' : base;
}

Future<bool> confirmer(BuildContext context, String titre, String texte, {String? oui}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(titre),
      content: Text(texte),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: Text(c.t('non'))),
        TextButton(onPressed: () => Navigator.pop(c, true), child: Text(oui ?? c.t('oui'))),
      ],
    ),
  );
  return r ?? false;
}
