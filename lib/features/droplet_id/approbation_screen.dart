// L'écran qui s'ouvre quand on scanne le code d'un site « Continuer avec
// Droplet ID » : qui demande, quoi, et le nombre à taper. Approuver demande
// le déverrouillage du téléphone (empreinte, visage ou code) s'il est
// configuré.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';

import '../../design_system/ouro_colors.dart';
import 'droplet_id_service.dart';

class ApprobationScreen extends StatefulWidget {
  const ApprobationScreen({super.key, required this.demandeId});
  final String demandeId;

  @override
  State<ApprobationScreen> createState() => _ApprobationScreenState();
}

class _ApprobationScreenState extends State<ApprobationScreen> {
  final _service = DropletIdService.instance;
  final _code = TextEditingController();
  final _pseudo = TextEditingController();
  DemandeDropletId? _demande;
  String? _erreur;
  bool _occupe = false;
  bool _partagerPseudo = true;
  String? _fini; // message final

  @override
  void initState() {
    super.initState();
    _charger();
  }

  @override
  void dispose() {
    _code.dispose();
    _pseudo.dispose();
    super.dispose();
  }

  Future<void> _charger() async {
    try {
      if (!await _service.estActive()) await _service.activer();
      final d = await _service.lireDemande(widget.demandeId);
      if (mounted) setState(() => _demande = d);
    } on ErreurDropletId catch (e) {
      if (mounted) setState(() => _erreur = e.message);
    }
  }

  Future<bool> _deverrouiller() async {
    final auth = LocalAuthentication();
    try {
      if (!await auth.isDeviceSupported()) return true; // pas de verrou configuré
      return await auth.authenticate(localizedReason: 'Confirmer la connexion à ${_demande!.nomSite}');
    } catch (_) {
      return true;
    }
  }

  Future<void> _approuver() async {
    final d = _demande!;
    if (!await _deverrouiller()) return;
    setState(() => _occupe = true);
    try {
      await _service.approuver(
        d.id,
        code: _code.text,
        portees: [...d.portees.where((p) => p != 'profile' || _partagerPseudo)],
        pseudo: _partagerPseudo ? _pseudo.text : null,
      );
      HapticFeedback.mediumImpact();
      setState(() => _fini = 'Connexion approuvée. Revenez sur ${d.nomSite}.');
    } on ErreurDropletId catch (e) {
      setState(() => _erreur = e.message);
    } finally {
      if (mounted) setState(() => _occupe = false);
    }
  }

  Future<void> _refuser() async {
    setState(() => _occupe = true);
    try {
      await _service.refuser(_demande!.id);
    } catch (_) {}
    if (mounted) setState(() => _fini = 'Connexion refusée.');
  }

  @override
  Widget build(BuildContext context) {
    final d = _demande;
    return Scaffold(
      backgroundColor: OuroColors.systemGroupedBackground,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Droplet ID', style: TextStyle(color: OuroColors.label)),
        iconTheme: IconThemeData(color: OuroColors.label),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          children: [
            if (_fini != null) ...[
              const SizedBox(height: 40),
              Icon(Icons.check_circle_rounded, size: 64, color: OuroColors.systemGreen),
              const SizedBox(height: 16),
              Text(_fini!, textAlign: TextAlign.center, style: TextStyle(fontSize: 18, color: OuroColors.label)),
              const SizedBox(height: 24),
              FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer')),
            ] else if (_erreur != null) ...[
              const SizedBox(height: 40),
              Icon(Icons.error_outline_rounded, size: 56, color: OuroColors.systemRed),
              const SizedBox(height: 16),
              Text(_erreur!, textAlign: TextAlign.center, style: TextStyle(fontSize: 17, color: OuroColors.label)),
              const SizedBox(height: 24),
              OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Fermer')),
            ] else if (d == null) ...[
              const SizedBox(height: 80),
              const Center(child: CircularProgressIndicator()),
            ] else ...[
              Row(children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: OuroColors.accent.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(14)),
                  child: Text(d.nomSite.characters.first.toUpperCase(),
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: OuroColors.accent)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(d.nomSite, style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: OuroColors.label)),
                    Text(d.hote, style: TextStyle(fontSize: 14, color: OuroColors.secondaryLabel)),
                  ]),
                ),
              ]),
              const SizedBox(height: 24),
              Text('Se connecter à ${d.nomSite} ?',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, height: 1.15, color: OuroColors.label)),
              const SizedBox(height: 20),
              Text('Tapez le nombre affiché sur l’écran de connexion',
                  style: TextStyle(fontSize: 15, color: OuroColors.secondaryLabel)),
              const SizedBox(height: 10),
              Center(
                child: SizedBox(
                  width: 150,
                  child: TextField(
                    controller: _code,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 2,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (_) => setState(() {}),
                    style: TextStyle(fontSize: 40, fontWeight: FontWeight.w700, letterSpacing: 12, color: OuroColors.label),
                    decoration: InputDecoration(counterText: '', filled: true, fillColor: OuroColors.secondarySystemGroupedBackground,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none)),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text("Pas d'écran de connexion devant vous ? Refusez : quelqu'un essaie peut-être d'entrer dans votre compte.",
                  style: TextStyle(fontSize: 13, color: OuroColors.secondaryLabel)),
              if (d.demandeProfil) ...[
                const SizedBox(height: 18),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  value: _partagerPseudo,
                  onChanged: (v) => setState(() => _partagerPseudo = v),
                  title: Text('Partager un pseudo avec ce site', style: TextStyle(color: OuroColors.label)),
                ),
                if (_partagerPseudo)
                  TextField(
                    controller: _pseudo,
                    maxLength: 40,
                    decoration: const InputDecoration(labelText: 'Pseudo pour ce site', counterText: ''),
                  ),
              ],
              const SizedBox(height: 14),
              Text('${d.nomSite} recevra un identifiant propre à ce site. Ni numéro, ni e-mail, ni nom.',
                  style: TextStyle(fontSize: 13, color: OuroColors.secondaryLabel)),
              const SizedBox(height: 22),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
                onPressed: _occupe || _code.text.length != 2 ? null : _approuver,
                child: _occupe ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Approuver'),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52), shape: const StadiumBorder()),
                onPressed: _occupe ? null : _refuser,
                child: const Text('Refuser'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
