// RECEVOIR — cet appareil est visible ; voici son nom, son code, et un QR
// code pour qu'on le trouve même quand la découverte automatique ne marche
// pas sur ce réseau.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/etat_app.dart';
import '../app/natif.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/marque.dart';
import '../design/typo.dart';
import 'connexion_directe.dart';
import 'group_drop.dart';
import 'pare_feu.dart';
import 'partage_web.dart';
import 'reglages.dart';

class Recevoir extends StatelessWidget {
  const Recevoir({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return ListenableBuilder(
      listenable: EtatApp.i,
      builder: (context, _) {
        final e = EtatApp.i;
        final code = jsonEncode({
          't': 'droplet_drop_appareil',
          'a': e.adresses,
          'p': e.port,
          'fp': e.empreinte,
          'n': e.nom,
          // La connexion directe : l'autre téléphone la rejoint tout seul.
          if (e.pointAcces != null) 'w': e.pointAcces!.json(),
        });
        return Scaffold(
          backgroundColor: p.fond,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            iconTheme: IconThemeData(color: p.accentTexte),
            title: Text(context.t('recevoir'), style: Typo.titreCarte.copyWith(color: p.texte)),
          ),
          body: Fond(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                Colonne(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(child: _Onde(child: AvatarAppareil(plateforme: EtatApp.plateforme(), empreinte: e.empreinte, taille: 88))),
                      const SizedBox(height: 18),
                      Text(context.t('visible_sous', {'nom': e.nom}), textAlign: TextAlign.center, style: Typo.titre.copyWith(color: p.texte)),
                      const SizedBox(height: 6),
                      Text(context.t('recevoir_texte'), textAlign: TextAlign.center, style: Typo.secondaire.copyWith(color: p.texte2)),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const EcranReglages())),
                          child: Text(context.t('changer_nom'), style: Typo.secondaire.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const CartePareFeu(),
                      if (Natif.android) ...[const SizedBox(height: 18), const CarteConnexionDirecte()],
                      const SizedBox(height: 14),
                      const CarteNavigateur(),
                      TitreSection(context.t('qr_appareil')),
                      Carte(
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                              child: QrImageView(data: code, size: 210, backgroundColor: Colors.white, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFF080C16)), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF080C16))),
                            ),
                            const SizedBox(height: 14),
                            Text(context.t('qr_appareil_texte'), textAlign: TextAlign.center, style: Typo.secondaire.copyWith(color: p.texte2)),
                            const SizedBox(height: 12),
                            _Info(libelle: context.t('code_securite'), valeur: e.courte),
                            if (e.adresses.isNotEmpty) _Info(libelle: context.t('adresse'), valeur: '${e.adresses.first}:${e.port}', copiable: true),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      BoutonSecondaire(
                        texte: context.t('rejoindre_distribution'),
                        icone: Icons.qr_code_scanner_rounded,
                        onTap: () => rejoindreDistribution(context),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.libelle, required this.valeur, this.copiable = false});

  final String libelle;
  final String valeur;
  final bool copiable;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(child: Text(libelle, style: Typo.secondaire.copyWith(color: p.texte2))),
          SelectableText(valeur, style: Typo.chiffres.copyWith(color: p.texte)),
          if (copiable)
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

/// Une onde lente autour de l'avatar : visible, sans pulsation agressive.
/// Elle s'arrête si l'utilisateur réduit les animations.
class _Onde extends StatefulWidget {
  const _Onde({required this.child});

  final Widget child;

  @override
  State<_Onde> createState() => _OndeState();
}

class _OndeState extends State<_Onde> with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(vsync: this, duration: const Duration(seconds: 4));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduireAnimations(context)) {
      _a.stop();
    } else if (!_a.isAnimating) {
      _a.repeat();
    }
  }

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return SizedBox(
      width: 180,
      height: 180,
      child: AnimatedBuilder(
        animation: _a,
        builder: (context, enfant) => Stack(
          alignment: Alignment.center,
          children: [
            for (final decalage in [0.0, 0.5])
              Builder(builder: (context) {
                final v = (_a.value + decalage) % 1.0;
                return Container(
                  width: 88 + 92 * v,
                  height: 88 + 92 * v,
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: p.accent.withValues(alpha: 0.35 * (1 - v)), width: 1.5)),
                );
              }),
            enfant!,
          ],
        ),
        child: widget.child,
      ),
    );
  }
}
