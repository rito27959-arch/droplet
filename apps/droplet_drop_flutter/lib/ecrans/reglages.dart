// LES RÉGLAGES — peu nombreux, chacun utile.
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../app/etat_app.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/marque.dart';
import '../design/typo.dart';
import 'choisir.dart' show estMobile;
import '../src/rust/api/simple.dart' as moteur;

class EcranReglages extends StatelessWidget {
  const EcranReglages({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ListenableBuilder(
      listenable: EtatApp.i,
      builder: (context, _) {
        final e = EtatApp.i;
        final confiance = e.pret ? e.confiance() : <String>[];
        return Scaffold(
          backgroundColor: p.fond,
          appBar: AppBar(
            backgroundColor: p.fond,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: p.accentTexte),
            title: Text(context.t('reglages'), style: Typo.titreCarte.copyWith(color: p.texte)),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
            children: [
              Colonne(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TitreSection(context.t('cet_appareil')),
                    Carte(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              AvatarAppareil(plateforme: EtatApp.plateforme(), empreinte: e.empreinte, taille: 48),
                              const SizedBox(width: 14),
                              Expanded(child: _ChampNom(initial: e.nom)),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(context.t('nom_texte'), style: Typo.secondaire.copyWith(color: p.texte2)),
                        ],
                      ),
                    ),
                    TitreSection(context.t('apparence')),
                    Carte(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SegmentedButton<Theme3>(
                            segments: [
                              ButtonSegment(value: Theme3.systeme, label: Text(context.t('theme_systeme'))),
                              ButtonSegment(value: Theme3.clair, label: Text(context.t('theme_clair'))),
                              ButtonSegment(value: Theme3.sombre, label: Text(context.t('theme_sombre'))),
                            ],
                            selected: {e.theme},
                            onSelectionChanged: (s) => e.definirTheme(s.first),
                          ),
                          const SizedBox(height: 16),
                          Text(context.t('couleur'), style: Typo.secondaire.copyWith(color: p.texte2)),
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 12,
                            children: [
                              for (final a in Accent.values)
                                Pressable(
                                  semantique: context.t('couleur_${a.name}'),
                                  onTap: () => e.definirAccent(a),
                                  child: Container(
                                    width: 40,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      gradient: Palette.de(sombre: p.sombre, accent: a).liquide,
                                      border: Border.all(color: e.accent == a ? p.texte : Colors.transparent, width: 2.5),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    TitreSection(context.t('langue')),
                    Carte(
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                      child: DropdownButton<String?>(
                        value: e.langue,
                        isExpanded: true,
                        underline: const SizedBox.shrink(),
                        dropdownColor: p.surface,
                        style: Typo.corps.copyWith(color: p.texte),
                        items: [
                          DropdownMenuItem(value: null, child: Text(context.t('langue_systeme'))),
                          for (final l in langues.entries) DropdownMenuItem(value: l.key, child: Text(l.value)),
                        ],
                        onChanged: e.definirLangue,
                      ),
                    ),
                    TitreSection(context.t('reception')),
                    Carte(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(context.t('dossier_reception'), style: Typo.secondaire.copyWith(color: p.texte2)),
                          const SizedBox(height: 4),
                          SelectableText(e.reception, style: Typo.secondaire.copyWith(color: p.texte)),
                          if (!estMobile) ...[
                            const SizedBox(height: 10),
                            Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: BoutonSecondaire(
                                texte: context.t('changer'),
                                icone: Icons.folder_rounded,
                                hauteur: 44,
                                large: false,
                                onTap: () async {
                                  final d = await FilePicker.platform.getDirectoryPath();
                                  if (d != null) e.definirReception(d);
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    TitreSection(context.t('confiance')),
                    Carte(
                      child: confiance.isEmpty
                          ? Text(context.t('confiance_vide'), style: Typo.secondaire.copyWith(color: p.texte2))
                          : Column(
                              children: [
                                for (final fp in confiance)
                                  Row(
                                    children: [
                                      AvatarAppareil(plateforme: '', empreinte: fp, taille: 34),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text('${fp.substring(0, 4)}-${fp.substring(4, 8)}'.toUpperCase(), style: Typo.chiffres.copyWith(color: p.texte)),
                                      ),
                                      TextButton(onPressed: () => e.retirerConfiance(fp), child: Text(context.t('retirer'), style: TextStyle(color: p.erreur))),
                                    ],
                                  ),
                              ],
                            ),
                    ),
                    TitreSection(context.t('securite')),
                    Carte(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.verified_user_rounded, color: p.succes),
                              const SizedBox(width: 10),
                              Expanded(child: Text(context.t('securite_titre'), style: Typo.titreCarte.copyWith(color: p.texte))),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(context.t('securite_texte'), style: Typo.secondaire.copyWith(color: p.texte2)),
                          const SizedBox(height: 10),
                          Text(context.t('code_appareil', {'c': e.courte}), style: Typo.chiffres.copyWith(color: p.texte)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 28),
                    Center(child: Goutte(taille: 36, fond: false)),
                    const SizedBox(height: 8),
                    Center(child: Text('Droplet Drop ${e.pret ? moteur.version() : ''}', style: Typo.legende.copyWith(color: p.texte3))),
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

class _ChampNom extends StatefulWidget {
  const _ChampNom({required this.initial});

  final String initial;

  @override
  State<_ChampNom> createState() => _ChampNomState();
}

class _ChampNomState extends State<_ChampNom> {
  late final _c = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return TextField(
      controller: _c,
      maxLength: 40,
      style: Typo.titreCarte.copyWith(color: p.texte),
      decoration: InputDecoration(counterText: '', labelText: context.t('nom_appareil'), border: InputBorder.none),
      onSubmitted: EtatApp.i.definirNom,
      onTapOutside: (_) {
        EtatApp.i.definirNom(_c.text);
        FocusScope.of(context).unfocus();
      },
    );
  }
}
