// GROUP DROP — distribuer un même envoi à toute une salle.
//
// L'hôte crée une session ; chacun la rejoint avec le QR code (ou le lien),
// ce qui marche même quand la découverte automatique est bloquée. L'hôte
// lance quand tout le monde est là, peut mettre en pause, reprendre,
// annuler ; chaque participant a son propre état.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/etat_app.dart';
import '../app/modeles.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/typo.dart';
import '../src/rust/api/simple.dart' as moteur;
import 'choisir.dart';
import 'scanner.dart';
import 'transfert.dart';

class EcranGroupDrop extends StatelessWidget {
  const EcranGroupDrop({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ListenableBuilder(
      listenable: EtatApp.i,
      builder: (context, _) {
        final sessions = EtatApp.i.mesSessions.values.toList().reversed.toList();
        return Scaffold(
          backgroundColor: p.fond,
          appBar: AppBar(
            backgroundColor: p.fond,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: p.accentTexte),
            title: Text(context.t('group_drop'), style: Typo.titreCarte.copyWith(color: p.texte)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Colonne(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(context.t('group_drop_texte'), style: Typo.corps.copyWith(color: p.texte2)),
                    const SizedBox(height: 20),
                    BoutonLiquide(
                      texte: context.t('creer_distribution'),
                      icone: Icons.add_rounded,
                      onTap: () async {
                        final f = await choisirFichiers(context);
                        if (f != null && f.isNotEmpty && context.mounted) {
                          await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => CreerDistribution(choisis: f)));
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    BoutonSecondaire(texte: context.t('rejoindre_distribution'), icone: Icons.qr_code_scanner_rounded, onTap: () => rejoindreDistribution(context)),
                    if (sessions.isNotEmpty) ...[
                      TitreSection(context.t('mes_distributions')),
                      for (final s in sessions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Carte(
                            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => TableauSession(session: s))),
                            child: Row(
                              children: [
                                Icon(Icons.groups_2_rounded, color: p.accentTexte),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        s.fichiers.length == 1 ? s.fichiers.first.nom : context.t('n_fichiers', {'n': '${s.fichiers.length}'}),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Typo.titreCarte.copyWith(color: p.texte),
                                      ),
                                      Text(_resume(context, s), style: Typo.secondaire.copyWith(color: p.texte2)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, color: p.texte3),
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

  static String _resume(BuildContext context, Session s) {
    final e = EtatApp.i.sessions[s.id];
    return '${tailleLocale(s.total)} · ${context.t('x_sur_y_termines', {'x': '${e?.termines ?? 0}', 'y': '${e?.participants ?? 0}'})}';
  }
}

/// Rejoindre : scanner le QR code (ou coller le lien), puis suivre la
/// réception.
Future<void> rejoindreDistribution(BuildContext context) async {
  final code = await scannerCode(context);
  if (code == null || !context.mounted) return;
  try {
    final apercu = jsonDecode(moteur.lireInvitation(invitation: code)) as Map;
    final hote = apercu['nom'] as String? ?? '';
    if (!context.mounted) return;
    final ok = await confirmer(context, context.t('rejoindre_titre', {'qui': hote}), context.t('rejoindre_texte'), oui: context.t('rejoindre'));
    if (!ok || !context.mounted) return;
    final id = await EtatApp.i.rejoindre(code);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EcranTransfert(groupe: id)));
  } catch (e) {
    if (!context.mounted) return;
    final expiree = '$e'.contains('expir');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(expiree ? context.t('err_session_expiree') : context.t('err_session_invalide'))));
  }
}

class CreerDistribution extends StatefulWidget {
  const CreerDistribution({super.key, required this.choisis});

  final List<Choisi> choisis;

  @override
  State<CreerDistribution> createState() => _CreerDistributionState();
}

class _CreerDistributionState extends State<CreerDistribution> {
  int _minutes = 120;
  bool _creation = false;

  Future<void> _creer() async {
    setState(() => _creation = true);
    try {
      final s = await EtatApp.i.creerSession(widget.choisis, _minutes);
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(MaterialPageRoute<void>(builder: (_) => TableauSession(session: s)));
    } catch (_) {
      if (!mounted) return;
      setState(() => _creation = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('err_fichier_introuvable'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final total = widget.choisis.fold<int>(0, (a, f) => a + f.taille);
    return Scaffold(
      backgroundColor: p.fond,
      appBar: AppBar(
        backgroundColor: p.fond,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: p.accentTexte),
        title: Text(context.t('creer_distribution'), style: Typo.titreCarte.copyWith(color: p.texte)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          Colonne(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Carte(
                  child: Row(
                    children: [
                      Icon(iconeFichier(widget.choisis.first.nom), color: p.accentTexte, size: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.choisis.length == 1 ? widget.choisis.first.nom : context.t('n_fichiers', {'n': '${widget.choisis.length}'}),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: Typo.titreCarte.copyWith(color: p.texte),
                            ),
                            Text(tailleLocale(total), style: Typo.chiffres.copyWith(color: p.texte2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                TitreSection(context.t('duree_session')),
                SegmentedButton<int>(
                  segments: [
                    ButtonSegment(value: 30, label: Text(context.t('minutes_30'))),
                    ButtonSegment(value: 120, label: Text(context.t('heures_2'))),
                    ButtonSegment(value: 480, label: Text(context.t('heures_8'))),
                  ],
                  selected: {_minutes},
                  onSelectionChanged: (s) => setState(() => _minutes = s.first),
                ),
                const SizedBox(height: 10),
                Text(context.t('duree_session_texte'), style: Typo.secondaire.copyWith(color: p.texte2)),
                const SizedBox(height: 28),
                if (_creation)
                  ListenableBuilder(
                    listenable: EtatApp.i,
                    builder: (context, _) {
                      final prep = EtatApp.i.preparations.values.lastOrNull;
                      return Column(
                        children: [
                          BarreProgression(valeur: prep == null || prep.$2 == 0 ? 0 : prep.$1 / prep.$2),
                          const SizedBox(height: 8),
                          Text(context.t('preparation_texte'), style: Typo.secondaire.copyWith(color: p.texte2)),
                          const SizedBox(height: 16),
                        ],
                      );
                    },
                  ),
                BoutonLiquide(texte: context.t('creer_session'), icone: Icons.qr_code_2_rounded, chargement: _creation, onTap: _creer),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class TableauSession extends StatefulWidget {
  const TableauSession({super.key, required this.session});

  final Session session;

  @override
  State<TableauSession> createState() => _TableauSessionState();
}

class _TableauSessionState extends State<TableauSession> {
  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ListenableBuilder(
      listenable: EtatApp.i,
      builder: (context, _) {
        final e = EtatApp.i;
        final s = widget.session;
        final etat = e.sessions[s.id]?.etat ?? 'ouverte';
        final parts = e.groupe(s.id);
        final total = parts.length * s.total;
        final fait = parts.fold<int>(0, (a, t) => a + t.octets);
        final debit = parts.fold<int>(0, (a, t) => a + t.debit);
        final termines = parts.where((t) => t.etat == EtatTransfert.termine).length;
        final enCours = parts.where((t) => t.etat.actif || t.etat == EtatTransfert.connexion).length;
        final attente = parts.where((t) => t.etat == EtatTransfert.enAttente).length;
        final coupes = parts.where((t) => t.etat == EtatTransfert.interrompu).length;
        final restant = parts.map((t) => t.restant ?? 0).fold<int>(0, (a, b) => a > b ? a : b);
        final large = MediaQuery.sizeOf(context).width > 900;

        final qr = Carte(
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: QrImageView(
                  data: s.invitation,
                  size: large ? 260 : 200,
                  backgroundColor: Colors.white,
                  eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFF080C16)),
                  dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF080C16)),
                ),
              ),
              const SizedBox(height: 12),
              Text(context.t('scanner_pour_rejoindre'), textAlign: TextAlign.center, style: Typo.secondaire.copyWith(color: p.texte2)),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: s.invitation));
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('copie'))));
                },
                icon: Icon(Icons.link_rounded, color: p.accentTexte),
                label: Text(context.t('copier_lien'), style: Typo.secondaire.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
              ),
              Text(context.t('expire_a', {'h': TimeOfDay.fromDateTime(s.expire).format(context)}), style: Typo.legende.copyWith(color: p.texte3)),
            ],
          ),
        );

        final tableau = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Carte(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text('$termines', style: Typo.grandChiffre.copyWith(color: p.texte)),
                      Text(' / ${parts.length}', style: Typo.titre.copyWith(color: p.texte2)),
                      const Spacer(),
                      PastilleEtat(
                        couleur: etat == 'en_cours' ? p.accentTexte : (etat == 'pause' ? p.attention : p.texte2),
                        libelle: context.t('session_$etat'),
                      ),
                    ],
                  ),
                  Text(context.t('appareils_termines'), style: Typo.secondaire.copyWith(color: p.texte2)),
                  const SizedBox(height: 14),
                  BarreProgression(valeur: total == 0 ? 0 : fait / total, hauteur: 8),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    children: [
                      _Chiffre(context.t('en_cours'), '$enCours'),
                      _Chiffre(context.t('etat_attente'), '$attente'),
                      _Chiffre(context.t('deconnectes'), '$coupes'),
                      _Chiffre(context.t('debit'), debit > 0 ? debitLocal(debit) : '—'),
                      _Chiffre(context.t('transfere'), tailleLocale(fait)),
                      _Chiffre(context.t('temps_restant'), restant > 0 ? dureeLocale(restant) : '—'),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (etat == 'ouverte')
              BoutonLiquide(texte: context.t('demarrer_n', {'n': '${parts.length}'}), icone: Icons.play_arrow_rounded, onTap: () => e.reprendre(s.id))
            else if (etat != 'terminee')
              Row(
                children: [
                  Expanded(
                    child: etat == 'pause'
                        ? BoutonLiquide(texte: context.t('reprendre'), icone: Icons.play_arrow_rounded, onTap: () => e.reprendre(s.id))
                        : BoutonSecondaire(texte: context.t('pause'), icone: Icons.pause_rounded, onTap: () => e.pause(s.id)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: BoutonSecondaire(
                      texte: context.t('annuler'),
                      icone: Icons.close_rounded,
                      couleur: p.erreur,
                      onTap: () async {
                        if (await confirmer(context, context.t('annuler_distribution'), context.t('annuler_distribution_texte'))) e.annuler(s.id);
                      },
                    ),
                  ),
                ],
              ),
            TitreSection(context.t('participants'), fin: Text('${parts.length}', style: Typo.legende.copyWith(color: p.texte3))),
            if (parts.isEmpty)
              Carte(child: EtatVide(icone: Icons.qr_code_2_rounded, titre: context.t('personne_encore'), texte: context.t('personne_encore_texte')))
            else
              for (final t in parts) Padding(padding: const EdgeInsets.only(bottom: 10), child: Apparition(child: LigneTransfert(t: t))),
          ],
        );

        return Scaffold(
          backgroundColor: p.fond,
          appBar: AppBar(
            backgroundColor: p.fond,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: p.accentTexte),
            title: Text(
              s.fichiers.length == 1 ? s.fichiers.first.nom : context.t('n_fichiers', {'n': '${s.fichiers.length}'}),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Typo.titreCarte.copyWith(color: p.texte),
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Colonne(
                max: large ? 1100 : 720,
                child: large
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [SizedBox(width: 340, child: qr), const SizedBox(width: 20), Expanded(child: tableau)],
                      )
                    : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [qr, const SizedBox(height: 16), tableau]),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre(this.libelle, this.valeur);

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return SizedBox(
      width: 120,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valeur, style: Typo.chiffres.copyWith(color: p.texte, fontWeight: FontWeight.w600, fontSize: 16)),
          Text(libelle, style: Typo.legende.copyWith(color: p.texte2)),
        ],
      ),
    );
  }
}
