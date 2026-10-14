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
import 'package:share_plus/share_plus.dart';

import '../app/etat_app.dart';
import '../app/modeles.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/marque.dart';
import '../design/scene.dart';
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
          extendBodyBehindAppBar: true,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: p.accentTexte),
            title: Text(context.t('group_drop'), style: Typo.titreCarte.copyWith(color: p.texte)),
          ),
          body: ListView(
            // La barre du haut est transparente et le contenu passe dessous :
            // il commence donc SOUS elle (barre d'état + barre de titre).
            padding: EdgeInsets.fromLTRB(20, MediaQuery.paddingOf(context).top + kToolbarHeight + 8, 20, 32),
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
                    BoutonSecondaire(texte: context.t('rejoindre_distribution'), icone: Icons.group_add_rounded, onTap: () => rejoindreDistribution(context)),
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

/// Rejoindre une distribution : l'écran qui propose les trois chemins.
Future<void> rejoindreDistribution(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EcranRejoindre()));

/// Rejoint avec une invitation (QR code, lien, code à six chiffres, lien
/// ouvert depuis une autre app), puis suit la réception.
Future<void> rejoindreAvecInvitation(BuildContext context, String invitation, {bool demander = true}) async {
  try {
    final apercu = jsonDecode(moteur.lireInvitation(invitation: invitation)) as Map;
    final hote = apercu['nom'] as String? ?? '';
    if (!context.mounted) return;
    if (demander) {
      final ok = await confirmer(context, context.t('rejoindre_titre', {'qui': hote}), context.t('rejoindre_texte'), oui: context.t('rejoindre'));
      if (!ok || !context.mounted) return;
    }
    final id = await EtatApp.i.rejoindre(invitation);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EcranTransfert(groupe: id)));
  } catch (e) {
    if (!context.mounted) return;
    final expiree = '$e'.contains('expir');
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(expiree ? context.t('err_session_expiree') : context.t('err_session_invalide'))));
  }
}

/// REJOINDRE — sans QR code s'il le faut.
///
/// 1. Les distributions À PROXIMITÉ : un hôte sur le même Wi‑Fi (ou sur
///    sa connexion directe) annonce les siennes ; on touche la bonne et on
///    tape le code à six chiffres affiché sur son écran. Rien ne passe par
///    Internet.
/// 2. Scanner le QR code.
/// 3. Coller le lien reçu par message.
class EcranRejoindre extends StatelessWidget {
  const EcranRejoindre({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ListenableBuilder(
      listenable: EtatApp.i,
      builder: (context, _) {
        final proches = [
          for (final a in EtatApp.i.appareils.values)
            for (final d in a.distributions) (a, d),
        ];
        return Scaffold(
          backgroundColor: p.fond,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: p.accentTexte),
            title: Text(context.t('rejoindre_distribution'), style: Typo.titreCarte.copyWith(color: p.texte)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Colonne(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TitreSection(context.t('distributions_proches')),
                    if (proches.isEmpty)
                      Carte(
                        child: EtatVide(
                          icone: Icons.wifi_tethering_rounded,
                          titre: context.t('aucune_distribution'),
                          texte: context.t('aucune_distribution_texte'),
                        ),
                      )
                    else
                      for (final (a, d) in proches)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Carte(
                            onTap: () => _avecCode(context, a, d),
                            child: Row(
                              children: [
                                AvatarAppareil(plateforme: a.plateforme, empreinte: a.empreinte, taille: 44),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(context.t('distribution_de', {'qui': a.nom}), maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.titreCarte.copyWith(color: p.texte)),
                                      const SizedBox(height: 2),
                                      Text(context.t('toucher_code'), style: Typo.secondaire.copyWith(color: p.texte2)),
                                    ],
                                  ),
                                ),
                                Icon(Icons.chevron_right_rounded, color: p.texte3),
                              ],
                            ),
                          ),
                        ),
                    const SizedBox(height: 20),
                    if (cameraDisponible) ...[
                      BoutonLiquide(
                        texte: context.t('scanner_qr'),
                        icone: Icons.qr_code_scanner_rounded,
                        onTap: () async {
                          final code = await scannerCode(context);
                          if (code != null && context.mounted) await rejoindreAvecInvitation(context, code);
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    BoutonSecondaire(
                      texte: context.t('coller_lien'),
                      icone: Icons.content_paste_rounded,
                      onTap: () async {
                        final code = await collerCode(context);
                        if (code != null && context.mounted) await rejoindreAvecInvitation(context, code);
                      },
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

  /// Le code à six chiffres, puis l'invitation demandée à l'hôte.
  Future<void> _avecCode(BuildContext context, AppareilVu a, String session) async {
    final code = await showDialog<String>(context: context, builder: (_) => _SaisieCode(hote: a.nom));
    if (code == null || !context.mounted) return;
    try {
      final invitation = await moteur.invitationParCode(appareil: a.id, session: session, code: code);
      if (!context.mounted) return;
      // On a choisi la distribution ET tapé son code : pas de seconde question.
      await rejoindreAvecInvitation(context, invitation, demander: false);
    } catch (e) {
      if (!context.mounted) return;
      final m = '$e';
      final cle = m.contains('code_incorrect') ? 'err_code_incorrect' : (m.contains('session') ? 'err_session_invalide' : 'err_injoignable');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t(cle))));
    }
  }
}

/// La saisie du code : six chiffres, le clavier numérique, et « Rejoindre »
/// qui ne s'allume qu'au sixième.
class _SaisieCode extends StatefulWidget {
  const _SaisieCode({required this.hote});

  final String hote;

  @override
  State<_SaisieCode> createState() => _SaisieCodeState();
}

class _SaisieCodeState extends State<_SaisieCode> {
  final _champ = TextEditingController();

  @override
  void dispose() {
    _champ.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final pret = _champ.text.length == 6;
    return AlertDialog(
      title: Text(context.t('code_titre', {'qui': widget.hote})),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.t('code_texte'), style: Typo.secondaire.copyWith(color: p.texte2)),
          const SizedBox(height: 16),
          TextField(
            controller: _champ,
            autofocus: true,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 6,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            style: Typo.grandChiffre.copyWith(color: p.texte, fontSize: 32, letterSpacing: 8),
            decoration: const InputDecoration(counterText: '', hintText: '000000'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (v) {
              if (v.length == 6) Navigator.pop(context, v);
            },
          ),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.t('annuler'))),
        TextButton(onPressed: pret ? () => Navigator.pop(context, _champ.text) : null, child: Text(context.t('rejoindre'))),
      ],
    );
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
              if (s.code.length == 6) ...[
                // Le code : pour les voisins qui voient la distribution
                // dans leur liste « À proximité », sans QR code ni Internet.
                const SizedBox(height: 14),
                Text(context.t('ou_code'), style: Typo.legende.copyWith(color: p.texte3)),
                const SizedBox(height: 4),
                Semantics(
                  label: s.code.split('').join(' '),
                  excludeSemantics: true,
                  child: Text('${s.code.substring(0, 3)} ${s.code.substring(3)}', style: Typo.grandChiffre.copyWith(color: p.texte, letterSpacing: 4)),
                ),
              ],
              const SizedBox(height: 6),
              Wrap(
                alignment: WrapAlignment.center,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: s.invitation));
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('copie'))));
                    },
                    icon: Icon(Icons.link_rounded, color: p.accentTexte),
                    label: Text(context.t('copier_lien'), style: Typo.secondaire.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
                  ),
                  // Partager l'invitation : WhatsApp, SMS, Bluetooth, Quick
                  // Share… tout ce que le téléphone propose.
                  TextButton.icon(
                    onPressed: () => Share.share(context.t('invitation_message', {'qui': EtatApp.i.nom, 'lien': s.invitation, 'code': s.code})),
                    icon: Icon(Icons.ios_share_rounded, color: p.accentTexte),
                    label: Text(context.t('partager'), style: Typo.secondaire.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              Text(context.t('expire_a', {'h': TimeOfDay.fromDateTime(s.expire).format(context)}), style: Typo.legende.copyWith(color: p.texte3)),
            ],
          ),
        );

        // La scène du site : le code au centre, chaque appareil autour avec
        // son anneau, qui devient vert quand il a tout reçu.
        final scene = Constellation(
          hauteur: large ? 360 : 300,
          tailleNoeud: parts.length > 10 ? 40 : 48,
          centre: Lueur(
            rayon: 60,
            intensite: .45,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
              child: QrImageView(
                data: s.invitation,
                size: 78,
                padding: EdgeInsets.zero,
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFF080C16)),
                dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF080C16)),
              ),
            ),
          ),
          noeuds: [
            for (final t in parts.take(16))
              NoeudConstellation(
                id: t.id,
                nom: t.pair.nom.isEmpty ? t.pair.courte : t.pair.nom,
                plateforme: t.pair.plateforme,
                empreinte: t.pair.empreinte,
                progression: t.progression,
                fini: t.etat == EtatTransfert.termine,
              ),
          ],
        );

        final tableau = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            scene,
            const SizedBox(height: 8),
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
                  // Six chiffres en grille régulière (3 colonnes), comme les
                  // widgets d'iOS : l'œil lit les colonnes, pas un vrac.
                  _Grille(chiffres: [
                    _Chiffre(context.t('en_cours'), '$enCours'),
                    _Chiffre(context.t('etat_attente'), '$attente'),
                    _Chiffre(context.t('deconnectes'), '$coupes', alerte: coupes > 0),
                    _Chiffre(context.t('debit'), debit > 0 ? debitLocal(debit) : '—'),
                    _Chiffre(context.t('transfere'), tailleLocale(fait)),
                    _Chiffre(context.t('temps_restant'), restant > 0 ? dureeLocale(restant) : '—'),
                  ]),
                  if (parts.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Divider(height: 1, color: p.trait),
                    const SizedBox(height: 16),
                    _Mosaique(parts: parts),
                  ],
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
          body: Fond(
            child: SafeArea(
            bottom: false,
            child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: [
              Colonne(
                max: large ? 1100 : 720,
                child: large
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [SizedBox(width: 340, child: qr), const SizedBox(width: 20), Expanded(child: tableau)],
                      )
                    // Sur téléphone : tant que la distribution attend ses
                    // participants, le code d'abord ; une fois lancée, le
                    // tableau d'abord — c'est lui qu'on regarde.
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: etat == 'ouverte' ? [qr, const SizedBox(height: 16), tableau] : [tableau, const SizedBox(height: 16), qr],
                      ),
              ),
            ],
          ),
          ),
          ),
        );
      },
    );
  }
}

class _Chiffre extends StatelessWidget {
  const _Chiffre(this.libelle, this.valeur, {this.alerte = false});

  final String libelle;
  final String valeur;
  final bool alerte;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(valeur, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.chiffres.copyWith(color: alerte ? p.attention : p.texte, fontWeight: FontWeight.w600, fontSize: 17)),
        const SizedBox(height: 2),
        Text(libelle, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.legende.copyWith(color: p.texte2)),
      ],
    );
  }
}

class _Grille extends StatelessWidget {
  const _Grille({required this.chiffres});

  final List<Widget> chiffres;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < chiffres.length; i += 3) ...[
          if (i > 0) const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var k = i; k < i + 3; k++) Expanded(child: k < chiffres.length ? chiffres[k] : const SizedBox()),
            ],
          ),
        ],
      ],
    );
  }
}

/// Tous les participants d'un coup d'œil : un anneau par appareil, vert
/// quand il a tout reçu, orange s'il est déconnecté. La liste détaillée
/// suit dessous.
class _Mosaique extends StatelessWidget {
  const _Mosaique({required this.parts});

  final List<Transfert> parts;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final t in parts)
          Tooltip(
            message: t.pair.nom.isEmpty ? t.pair.courte : t.pair.nom,
            child: AnneauProgression(
              valeur: t.progression,
              taille: 34,
              epaisseur: 3.5,
              couleur: t.etat == EtatTransfert.termine ? p.succes : (t.etat == EtatTransfert.interrompu ? p.attention : null),
              centre: Icon(
                t.etat == EtatTransfert.termine ? Icons.check_rounded : AvatarAppareil.icone(t.pair.plateforme),
                size: 15,
                color: t.etat == EtatTransfert.termine ? p.succes : p.texte2,
              ),
            ),
          ),
      ],
    );
  }
}
