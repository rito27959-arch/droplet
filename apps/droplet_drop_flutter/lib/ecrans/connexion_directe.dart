// LA CONNEXION DIRECTE — envoyer sans box ni Internet, comme Xender.
//
// Un téléphone Android ouvre un petit réseau Wi‑Fi local. Son nom et son mot
// de passe sont dans le QR code de l'écran « Recevoir » : un autre téléphone
// qui le scanne rejoint ce réseau tout seul, puis envoie. Un ordinateur le
// rejoint comme n'importe quel Wi‑Fi (nom et mot de passe affichés), et
// apparaît alors dans « À proximité ».
//
// La connexion reste ouverte tant qu'on ne l'arrête pas — un transfert en
// cours n'est jamais coupé parce qu'on a quitté un écran.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/etat_app.dart';
import '../app/natif.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/typo.dart';

class CarteConnexionDirecte extends StatefulWidget {
  const CarteConnexionDirecte({super.key});

  @override
  State<CarteConnexionDirecte> createState() => _CarteConnexionDirecteState();
}

class _CarteConnexionDirecteState extends State<CarteConnexionDirecte> {
  bool _enCours = false;

  Future<void> _ouvrir() async {
    setState(() => _enCours = true);
    HapticFeedback.selectionClick();
    final echec = await EtatApp.i.ouvrirPointAcces();
    if (!mounted) return;
    setState(() => _enCours = false);
    if (echec == null) {
      HapticFeedback.mediumImpact();
      return;
    }
    final cle = switch (echec) {
      EchecPointAcces.autorisation => 'direct_echec_autorisation',
      EchecPointAcces.localisation => 'direct_echec_localisation',
      EchecPointAcces.partageActif => 'direct_echec_partage',
      EchecPointAcces.nonSupporte => 'direct_echec_version',
      EchecPointAcces.autre => 'direct_echec',
    };
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(context.t(cle)),
      action: echec == EchecPointAcces.localisation ? SnackBarAction(label: context.t('ouvrir'), onPressed: Natif.ouvrirReglagesLocalisation) : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    if (!Natif.android) return const SizedBox.shrink();
    final p = context.p;
    return ListenableBuilder(
      listenable: EtatApp.i,
      builder: (context, _) {
        final pa = EtatApp.i.pointAcces;
        return AnimatedSize(
          duration: duree(context, 320),
          curve: kRessort,
          child: Carte(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(gradient: pa == null ? null : p.liquide, color: pa == null ? p.accent.withValues(alpha: .14) : null, borderRadius: BorderRadius.circular(12)),
                      child: Icon(Icons.wifi_tethering_rounded, size: 22, color: pa == null ? p.accentTexte : Colors.white),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(context.t(pa == null ? 'direct_titre' : 'direct_actif'), style: Typo.titreCarte.copyWith(color: p.texte)),
                          const SizedBox(height: 2),
                          Text(context.t(pa == null ? 'direct_texte' : 'direct_actif_texte'), style: Typo.secondaire.copyWith(color: p.texte2)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (pa != null) ...[
                  const SizedBox(height: 14),
                  _Info(libelle: context.t('direct_reseau'), valeur: pa.ssid),
                  if (pa.motDePasse.isNotEmpty) _Info(libelle: context.t('direct_mdp'), valeur: pa.motDePasse),
                  const SizedBox(height: 10),
                  BoutonSecondaire(texte: context.t('direct_arreter'), icone: Icons.stop_circle_outlined, hauteur: 46, onTap: () => EtatApp.i.fermerPointAcces()),
                ] else ...[
                  const SizedBox(height: 14),
                  BoutonLiquide(texte: context.t('direct_creer'), icone: Icons.wifi_tethering_rounded, hauteur: 48, chargement: _enCours, onTap: _enCours ? null : _ouvrir),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.libelle, required this.valeur});

  final String libelle;
  final String valeur;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(libelle, style: Typo.secondaire.copyWith(color: p.texte2))),
          Flexible(child: SelectableText(valeur, style: Typo.chiffres.copyWith(color: p.texte))),
          BoutonIcone(
            icone: Icons.copy_rounded,
            nom: context.t('copier'),
            taille: 32,
            onTap: () {
              Clipboard.setData(ClipboardData(text: valeur));
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('copie'))));
            },
          ),
        ],
      ),
    );
  }
}

/// Rejoindre la connexion directe lue dans un QR code, avec une attente
/// visible. Vrai si on y est.
Future<bool> rejoindreConnexion(BuildContext context, PointAcces pa, String nom) async {
  if (!Natif.android) return false;
  final p = context.p;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (c) => PopScope(
      canPop: false,
      child: AlertDialog(
        backgroundColor: p.surface,
        content: Row(
          children: [
            const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5)),
            const SizedBox(width: 18),
            Expanded(child: Text(c.t('direct_rejoindre', {'nom': nom}), style: Typo.corps.copyWith(color: p.texte))),
          ],
        ),
      ),
    ),
  );
  final ok = await Natif.rejoindre(pa);
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('direct_rejoindre_echec', {'nom': nom}))));
  }
  return ok;
}
