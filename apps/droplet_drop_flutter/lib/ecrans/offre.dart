// UNE PROPOSITION DE FICHIERS — qui envoie, quoi, combien. Accepter et
// Refuser bien séparés ; rien ne commence sans réponse.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/etat_app.dart';
import '../app/modeles.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/marque.dart';
import '../design/typo.dart';
import 'choisir.dart' show iconeFichier;
import 'transfert.dart';

Future<void> montrerOffre(BuildContext context, Offre o) async {
  HapticFeedback.lightImpact();
  final accepte = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: Colors.transparent,
    builder: (_) => _FeuilleOffre(offre: o),
  );
  if (accepte == true && context.mounted) {
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EcranTransfert(groupe: o.id)));
  }
}

class _FeuilleOffre extends StatefulWidget {
  const _FeuilleOffre({required this.offre});

  final Offre offre;

  @override
  State<_FeuilleOffre> createState() => _FeuilleOffreState();
}

class _FeuilleOffreState extends State<_FeuilleOffre> {
  bool _toujours = false;

  @override
  void initState() {
    super.initState();
    EtatApp.i.addListener(_verifier);
  }

  /// L'offre a expiré, ou l'expéditeur a annulé : la feuille se ferme.
  void _verifier() {
    if (!EtatApp.i.offres.any((x) => x.id == widget.offre.id) && mounted) {
      final t = EtatApp.i.transferts[widget.offre.id];
      if (t == null || t.etat == EtatTransfert.refuse || t.etat.finale) Navigator.of(context).maybePop(false);
    }
  }

  @override
  void dispose() {
    EtatApp.i.removeListener(_verifier);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final o = widget.offre;
    final montres = o.fichiers.take(4).toList();
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Colonne(
          max: 560,
          child: Container(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
            decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(28), border: Border.all(color: p.trait)),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    AvatarAppareil(plateforme: o.de.plateforme, empreinte: o.de.empreinte, taille: 52),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.t('offre_titre', {'qui': o.de.nom}), style: Typo.titreCarte.copyWith(color: p.texte)),
                          const SizedBox(height: 2),
                          Text(context.t('code_appareil', {'c': o.de.courte}), style: Typo.chiffres.copyWith(color: p.texte2, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: p.surfaceHaute, borderRadius: BorderRadius.circular(18)),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final f in montres)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Icon(iconeFichier(f.nom), size: 18, color: p.texte2),
                              const SizedBox(width: 10),
                              Expanded(child: Text(f.chemin, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.secondaire.copyWith(color: p.texte))),
                              Text(tailleLocale(f.taille), style: Typo.legende.copyWith(color: p.texte3)),
                            ],
                          ),
                        ),
                      if (o.fichiers.length > montres.length)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(context.t('et_n_autres', {'n': '${o.fichiers.length - montres.length}'}), style: Typo.secondaire.copyWith(color: p.texte2)),
                        ),
                      const Divider(height: 18),
                      Row(
                        children: [
                          Expanded(child: Text(context.t('n_fichiers', {'n': '${o.fichiers.length}'}), style: Typo.secondaire.copyWith(color: p.texte2))),
                          Text(tailleLocale(o.total), style: Typo.chiffres.copyWith(color: p.texte, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ],
                  ),
                ),
                if (o.fichiers.any((f) => _executable(f.nom))) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.shield_outlined, size: 18, color: p.attention),
                      const SizedBox(width: 8),
                      Expanded(child: Text(context.t('avertissement_executable'), style: Typo.secondaire.copyWith(color: p.texte2))),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                // Sa propre surface Material : sur le fond peint de la feuille,
                // l'effet du toucher resterait sinon invisible.
                Material(
                  type: MaterialType.transparency,
                  child: SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _toujours,
                    onChanged: (v) => setState(() => _toujours = v),
                    title: Text(context.t('toujours_accepter'), style: Typo.secondaire.copyWith(color: p.texte)),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: BoutonSecondaire(
                        texte: context.t('refuser'),
                        onTap: () {
                          EtatApp.i.repondre(o, false);
                          Navigator.of(context).pop(false);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: BoutonLiquide(
                        texte: context.t('accepter'),
                        onTap: () {
                          EtatApp.i.repondre(o, true, toujours: _toujours);
                          Navigator.of(context).pop(true);
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

bool _executable(String nom) {
  final ext = nom.contains('.') ? nom.split('.').last.toLowerCase() : '';
  return const {'exe', 'msi', 'bat', 'cmd', 'ps1', 'sh', 'apk', 'dmg', 'pkg', 'app', 'deb', 'rpm', 'appimage', 'jar', 'scr', 'vbs'}.contains(ext);
}
