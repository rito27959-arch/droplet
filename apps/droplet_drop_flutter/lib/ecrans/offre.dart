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
import '../design/scene.dart';
import '../design/typo.dart';
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
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: p.sombre ? Colors.white.withValues(alpha: .1) : p.trait),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: p.sombre ? .5 : .12), blurRadius: 40, offset: const Offset(0, 16))],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Comme sur le site : l'appareil dans son halo, la phrase, la
                // mosaïque de ce qu'il envoie, et son code.
                Center(child: Lueur(rayon: 50, intensite: .45, child: AvatarAppareil(plateforme: o.de.plateforme, empreinte: o.de.empreinte, taille: 60))),
                const SizedBox(height: 14),
                Text(context.t('offre_titre', {'qui': o.de.nom}), textAlign: TextAlign.center, style: Typo.titre.copyWith(color: p.texte)),
                const SizedBox(height: 4),
                Text(
                  '${context.t('n_fichiers', {'n': '${o.fichiers.length}'})} · ${tailleLocale(o.total)}',
                  textAlign: TextAlign.center,
                  style: Typo.chiffres.copyWith(color: p.texte2),
                ),
                const SizedBox(height: 18),
                Mosaique(noms: [for (final f in o.fichiers) f.nom], max: 5, tuile: 56),
                if (o.fichiers.length <= 3) ...[
                  const SizedBox(height: 12),
                  for (final f in montres)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(f.chemin, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.secondaire.copyWith(color: p.texte2)),
                    ),
                ],
                const SizedBox(height: 14),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: p.surfaceHaute, borderRadius: BorderRadius.circular(99)),
                    child: Text(context.t('code_appareil', {'c': o.de.courte}), style: Typo.chiffres.copyWith(color: p.texte2, fontSize: 13)),
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
