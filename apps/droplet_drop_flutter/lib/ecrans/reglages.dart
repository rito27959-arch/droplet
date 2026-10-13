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
                          Segments<Theme3>(
                            options: [
                              (Theme3.systeme, context.t('theme_systeme'), Icons.brightness_auto_rounded),
                              (Theme3.clair, context.t('theme_clair'), Icons.light_mode_rounded),
                              (Theme3.sombre, context.t('theme_sombre'), Icons.dark_mode_rounded),
                            ],
                            valeur: e.theme,
                            onChange: e.definirTheme,
                          ),
                          const SizedBox(height: 18),
                          Text(context.t('couleur'), style: Typo.secondaire.copyWith(color: p.texte2)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 14,
                            runSpacing: 10,
                            children: [
                              for (final a in Accent.values) _Pastille(accent: a, choisie: e.accent == a, onTap: () => e.definirAccent(a)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    TitreSection(context.t('general')),
                    Groupe(
                      lignes: [
                        Ligne(
                          icone: Icons.translate_rounded,
                          teinte: const Color(0xFF4855E8),
                          titre: context.t('langue'),
                          valeur: e.langue == null ? context.t('langue_systeme') : langues[e.langue],
                          onTap: () async {
                            // '' : la langue du système (null voudrait dire « fermé sans choisir »).
                            final choix = await choisirDansListe<String>(
                              context,
                              titre: context.t('langue'),
                              courant: e.langue ?? '',
                              options: [('', context.t('langue_systeme')), for (final l in langues.entries) (l.key, l.value)],
                            );
                            if (choix != null) e.definirLangue(choix.isEmpty ? null : choix);
                          },
                        ),
                        Ligne(
                          icone: Icons.folder_rounded,
                          teinte: const Color(0xFF168BFF),
                          titre: context.t('reception'),
                          sousTitre: e.reception,
                          onTap: estMobile
                              ? null
                              : () async {
                                  final d = await FilePicker.platform.getDirectoryPath();
                                  if (d != null) e.definirReception(d);
                                },
                        ),
                      ],
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

/// Une couleur d'accent : la goutte de couleur, et — choisie — un anneau
/// détaché avec une coche, comme les couleurs d'accent d'iOS.
class _Pastille extends StatelessWidget {
  const _Pastille({required this.accent, required this.choisie, required this.onTap});

  final Accent accent;
  final bool choisie;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final couleur = Palette.de(sombre: p.sombre, accent: accent);
    return Pressable(
      semantique: context.t('couleur_${accent.name}'),
      enfoncement: 0.9,
      onTap: onTap,
      child: AnimatedContainer(
        duration: duree(context, 220),
        width: 44,
        height: 44,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: choisie ? couleur.accent : Colors.transparent, width: 2)),
        child: DecoratedBox(
          decoration: BoxDecoration(shape: BoxShape.circle, gradient: couleur.liquide),
          child: AnimatedOpacity(
            opacity: choisie ? 1 : 0,
            duration: duree(context, 180),
            child: const Icon(Icons.check_rounded, color: Colors.white, size: 20),
          ),
        ),
      ),
    );
  }
}
