// WINDOWS : AUTORISER LA RÉCEPTION À TRAVERS LE PARE-FEU.
//
// Au premier lancement, Windows demande si l'application peut recevoir des
// connexions. Une case mal cochée (réseau « public »), une fenêtre fermée,
// et Windows crée des règles qui BLOQUENT Droplet Drop : on ne peut plus
// lui envoyer de fichiers, alors que lui peut toujours envoyer.
//
// Cette carte le détecte (aucune règle « Droplet Drop » qui l'autorise) et
// le répare en une fois : on retire les règles entrantes existantes pour
// le programme (celles de Windows, autoriser ou bloquer) puis on ajoute
// une règle qui l'autorise sur tous les profils réseau. Windows demande la
// confirmation de l'administrateur (UAC) ; rien ne se fait sans elle.
//
// Même sans cette règle, les envois vers ce PC aboutissent souvent : le
// moteur fait alors venir chercher l'envoi par ce PC (tirage). La règle
// rend tout plus direct et plus rapide.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/typo.dart';

const _nomRegle = 'Droplet Drop';

class CartePareFeu extends StatefulWidget {
  const CartePareFeu({super.key});

  @override
  State<CartePareFeu> createState() => _CartePareFeuState();
}

class _CartePareFeuState extends State<CartePareFeu> {
  /// null : on ne sait pas encore (ou pas Windows) ; la carte reste cachée.
  bool? _autorise;
  bool _enCours = false;

  @override
  void initState() {
    super.initState();
    if (Platform.isWindows) _verifier();
  }

  Future<void> _verifier() async {
    try {
      final r = await Process.run('netsh', ['advfirewall', 'firewall', 'show', 'rule', 'name=$_nomRegle'], runInShell: false);
      if (mounted) setState(() => _autorise = r.exitCode == 0);
    } catch (_) {
      // netsh introuvable (Windows réduit) : on ne propose rien.
    }
  }

  Future<void> _autoriser() async {
    setState(() => _enCours = true);
    HapticFeedback.selectionClick();
    final exe = Platform.resolvedExecutable.replaceAll("'", "''");
    final commandes = 'netsh advfirewall firewall delete rule name=all dir=in program="$exe" & '
        'netsh advfirewall firewall add rule name="$_nomRegle" dir=in action=allow program="$exe" enable=yes profile=any';
    try {
      await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "\$p = Start-Process -FilePath cmd -ArgumentList '/c $commandes' -Verb RunAs -WindowStyle Hidden -Wait -PassThru; exit \$p.ExitCode",
      ]);
    } catch (_) {}
    await _verifier();
    if (!mounted) return;
    setState(() => _enCours = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t(_autorise == true ? 'pare_feu_ok' : 'pare_feu_echec'))));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    return AnimatedSize(
      duration: duree(context, 320),
      curve: Curves.easeOutCubic,
      child: _autorise != false
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.only(top: 18),
              child: Carte(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(color: p.accent.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
                          child: Icon(Icons.shield_outlined, size: 20, color: p.accentTexte),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(context.t('pare_feu_titre'), style: Typo.titreCarte.copyWith(color: p.texte))),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(context.t('pare_feu_texte'), style: Typo.secondaire.copyWith(color: p.texte2)),
                    const SizedBox(height: 14),
                    BoutonLiquide(texte: context.t('pare_feu_bouton'), icone: Icons.verified_user_outlined, chargement: _enCours, hauteur: 48, onTap: _enCours ? null : _autoriser),
                  ],
                ),
              ),
            ),
    );
  }
}
