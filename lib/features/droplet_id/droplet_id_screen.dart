// Réglages → Droplet ID : activer, scanner un code de connexion, voir et
// retirer les sites connectés, oublier Droplet ID sur ce téléphone.

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_list.dart';
import '../chat/qr_scan_screen.dart';
import 'approbation_screen.dart';
import 'droplet_id_service.dart';

class DropletIdScreen extends StatefulWidget {
  const DropletIdScreen({super.key});

  @override
  State<DropletIdScreen> createState() => _DropletIdScreenState();
}

class _DropletIdScreenState extends State<DropletIdScreen> {
  final _service = DropletIdService.instance;
  bool? _active;
  List<ConnexionDropletId>? _connexions;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final a = await _service.estActive();
    List<ConnexionDropletId>? c;
    String? e;
    if (a) {
      try {
        c = await _service.connexions();
      } on ErreurDropletId catch (x) {
        e = x.message;
      }
    }
    if (mounted) setState(() { _active = a; _connexions = c; _erreur = e; });
  }

  Future<void> _activer() async {
    try {
      await _service.activer();
    } on ErreurDropletId catch (x) {
      if (mounted) setState(() => _erreur = x.message);
    }
    _charger();
  }

  Future<void> _scanner() async {
    final texte = await Navigator.of(context).push<String>(CupertinoPageRoute(builder: (_) => const QrScanScreen()));
    if (texte == null || !mounted) return;
    final lien = DropletIdService.lienDepuis(texte);
    if (lien == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Ce code n'est pas une connexion Droplet ID.")));
      return;
    }
    await Navigator.of(context).push(CupertinoPageRoute(builder: (_) => ApprobationScreen(demandeId: lien.demandeId, service: DropletIdService.pour(lien.emetteur))));
    _charger();
  }

  Future<void> _retirer(ConnexionDropletId c) async {
    await _service.retirer(c.clientId);
    _charger();
  }

  Future<void> _desactiver() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Oublier Droplet ID ?'),
        content: const Text("Ce téléphone ne pourra plus approuver de connexions. Les sites connectés ne vous reconnaîtront plus avec ce téléphone."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          TextButton(onPressed: () => Navigator.pop(c, true), child: const Text('Oublier')),
        ],
      ),
    );
    if (ok == true) {
      await _service.desactiver();
      _charger();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OuroColors.systemGroupedBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Droplet ID', style: TextStyle(color: OuroColors.label)),
        iconTheme: IconThemeData(color: OuroColors.label),
      ),
      body: _active == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
                  child: Text(
                    'Connectez-vous à des sites et des apps sans numéro, sans e-mail, sans nom. Chaque site reçoit un identifiant qui ne vaut que pour lui.',
                    style: TextStyle(fontSize: 15, color: OuroColors.secondaryLabel),
                  ),
                ),
                if (_erreur != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
                    child: Text(_erreur!, style: TextStyle(color: OuroColors.systemRed)),
                  ),
                if (_active == false)
                  OuroListSection(
                    footer: 'Crée une clé sur ce téléphone. Rien de personnel n’est envoyé.',
                    children: [OuroListRow(icon: Icons.water_drop_rounded, iconColor: OuroColors.accent, title: 'Activer Droplet ID', onTap: _activer)],
                  )
                else ...[
                  OuroListSection(
                    footer: 'Scannez le code affiché par un site « Continuer avec Droplet ID ».',
                    children: [OuroListRow(icon: Icons.qr_code_scanner_rounded, iconColor: OuroColors.accent, title: 'Scanner un code de connexion', onTap: _scanner)],
                  ),
                  const SizedBox(height: 22),
                  OuroListSection(
                    header: 'Sites connectés',
                    footer: 'Retirer un site le déconnecte partout.',
                    children: [
                      if ((_connexions ?? []).isEmpty)
                        const OuroListRow(title: 'Aucun site pour l’instant', showChevron: false)
                      else
                        for (final c in _connexions!)
                          OuroListRow(
                            title: c.nom,
                            subtitle: c.portees.contains('profile') ? 'Identifiant et pseudo' : 'Identifiant seulement',
                            showChevron: false,
                            trailing: TextButton(onPressed: () => _retirer(c), child: const Text('Retirer')),
                          ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  OuroListSection(children: [
                    OuroListRow(title: 'Oublier Droplet ID sur ce téléphone', isDestructive: true, showChevron: false, onTap: _desactiver),
                  ]),
                ],
              ],
            ),
    );
  }
}
