// VERS (OU DEPUIS) UN NAVIGATEUR — pour l'appareil qui n'a pas Droplet
// Drop : un ordinateur au bureau, l'iPhone d'un ami. Cet appareil ouvre une
// petite page sur le réseau local ; l'autre l'ouvre dans son navigateur
// (adresse ou QR code) et télécharge — ou dépose des fichiers, si on l'a
// permis.
//
// C'est du HTTP simple : moins protégé qu'un envoi entre deux apps Droplet
// Drop (TLS 1.3). L'écran le dit, et la page se ferme avec l'écran.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../app/modeles.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/typo.dart';
import '../src/rust/api/simple.dart' as moteur;

class EcranPartageWeb extends StatefulWidget {
  const EcranPartageWeb({super.key, this.choisis = const [], this.recevoir = false});

  final List<Choisi> choisis;
  final bool recevoir;

  @override
  State<EcranPartageWeb> createState() => _EcranPartageWebState();
}

class _EcranPartageWebState extends State<EcranPartageWeb> {
  List<String> _adresses = const [];
  int _choisie = 0;
  String? _erreur;
  int _telecharges = 0;
  final List<String> _recus = [];
  StreamSubscription<String>? _abonnement;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_adresses.isEmpty && _erreur == null && _abonnement == null) _demarrer();
  }

  /// Les textes de la page, dans la langue de l'app.
  Map<String, Object> _textesPage() {
    final t = context.t;
    final fr = langueCourante() == 'fr';
    return {
      'langue': langueCourante(),
      'telecharger': t('web_p_telecharger'),
      'a_telecharger': t('web_p_a_telecharger'),
      'tout_telecharger': t('web_p_tout'),
      'envoyer_vers': t('web_p_envoyer_vers'),
      'choisir_fichiers': t('web_p_choisir'),
      'ou_glisser': t('web_p_glisser'),
      'sous_titre': t(widget.choisis.isEmpty ? 'web_p_sous_recevoir' : 'web_p_sous'),
      'pied': t('web_p_pied'),
      'envoye': t('web_p_envoye'),
      'echec': t('web_p_echec'),
      'unites': fr ? ['o', 'Ko', 'Mo', 'Go', 'To'] : ['B', 'KB', 'MB', 'GB', 'TB'],
    };
  }

  Future<void> _demarrer() async {
    _abonnement = moteur.evenements().listen((brut) {
      final e = jsonDecode(brut) as Map;
      if (!mounted) return;
      if (e['type'] == 'web_telecharge') {
        HapticFeedback.lightImpact();
        setState(() => _telecharges++);
      } else if (e['type'] == 'web_recu') {
        HapticFeedback.mediumImpact();
        setState(() => _recus.insert(0, e['nom'] as String));
      }
    });
    try {
      final r = jsonDecode(await moteur.partageWebDemarrer(
        chemins: [for (final f in widget.choisis) f.chemin],
        noms: [for (final f in widget.choisis) f.nom],
        recevoir: widget.recevoir,
        textes: jsonEncode(_textesPage()),
      )) as Map;
      final port = r['port'] as int;
      final jeton = r['jeton'] as String;
      final adresses = [for (final a in (r['adresses'] as List).cast<String>()) if (a != '127.0.0.1') 'http://$a:$port/?k=$jeton'];
      // La connexion directe d'abord (l'autre appareil y est), puis les
      // réseaux privés habituels.
      int rang(String u) => u.contains('//192.168.') ? 0 : (u.contains('//10.') || u.contains('//172.') ? 1 : 2);
      adresses.sort((a, b) => rang(a).compareTo(rang(b)));
      if (mounted) setState(() => _adresses = adresses);
    } catch (e) {
      if (mounted) setState(() => _erreur = '$e');
    }
  }

  @override
  void dispose() {
    moteur.partageWebArreter();
    _abonnement?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final url = _adresses.isEmpty ? null : _adresses[_choisie.clamp(0, _adresses.length - 1)];
    return Scaffold(
      backgroundColor: p.fond,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        iconTheme: IconThemeData(color: p.accentTexte),
        title: Text(context.t(widget.choisis.isEmpty ? 'web_recevoir' : 'web_titre'), style: Typo.titreCarte.copyWith(color: p.texte)),
      ),
      body: Fond(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          children: [
            Colonne(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(context.t(widget.choisis.isEmpty ? 'web_recevoir_texte' : 'web_texte'), textAlign: TextAlign.center, style: Typo.secondaire.copyWith(color: p.texte2)),
                  const SizedBox(height: 18),
                  if (_erreur != null)
                    Carte(child: EtatVide(icone: Icons.error_outline_rounded, titre: context.t('web_echec')))
                  else if (url == null)
                    const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator.adaptive()))
                  else
                    Carte(
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                            child: QrImageView(data: url, size: 210, backgroundColor: Colors.white, eyeStyle: const QrEyeStyle(eyeShape: QrEyeShape.circle, color: Color(0xFF080C16)), dataModuleStyle: const QrDataModuleStyle(dataModuleShape: QrDataModuleShape.circle, color: Color(0xFF080C16))),
                          ),
                          const SizedBox(height: 14),
                          SelectableText(url, textAlign: TextAlign.center, style: Typo.chiffres.copyWith(color: p.texte)),
                          const SizedBox(height: 8),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              TextButton.icon(
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: url));
                                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.t('copie'))));
                                },
                                icon: Icon(Icons.copy_rounded, size: 18, color: p.accentTexte),
                                label: Text(context.t('copier'), style: Typo.secondaire.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
                              ),
                              if (_adresses.length > 1)
                                TextButton.icon(
                                  onPressed: () => setState(() => _choisie = (_choisie + 1) % _adresses.length),
                                  icon: Icon(Icons.swap_horiz_rounded, size: 18, color: p.accentTexte),
                                  label: Text(context.t('web_autre_adresse'), style: Typo.secondaire.copyWith(color: p.accentTexte, fontWeight: FontWeight.w600)),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  if (url != null) ...[
                    TitreSection(context.t('web_activite')),
                    Carte(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (widget.choisis.isNotEmpty) Text(context.t('web_telechargements', {'n': '$_telecharges'}), style: Typo.corps.copyWith(color: p.texte)),
                          if (widget.recevoir) ...[
                            if (widget.choisis.isNotEmpty) const SizedBox(height: 6),
                            Text(context.t('web_recus', {'n': '${_recus.length}'}), style: Typo.corps.copyWith(color: p.texte)),
                            for (final n in _recus.take(8))
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Row(children: [Icon(Icons.check_circle_rounded, size: 18, color: p.succes), const SizedBox(width: 8), Expanded(child: Text(n, maxLines: 1, overflow: TextOverflow.ellipsis, style: Typo.secondaire.copyWith(color: p.texte2)))]),
                              ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 18, color: p.texte3),
                        const SizedBox(width: 8),
                        Expanded(child: Text(context.t('web_avertissement'), style: Typo.legende.copyWith(color: p.texte3, fontWeight: FontWeight.w400))),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// La carte qui ouvre l'écran, sur « Recevoir » et sur « Destinataires ».
class CarteNavigateur extends StatelessWidget {
  const CarteNavigateur({super.key, this.choisis = const []});

  final List<Choisi> choisis;

  @override
  Widget build(BuildContext context) {
    final p = context.p;
    final envoi = choisis.isNotEmpty;
    return Carte(
      onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EcranPartageWeb(choisis: choisis, recevoir: !envoi))),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: p.accent.withValues(alpha: .14), borderRadius: BorderRadius.circular(14)),
            child: Icon(Icons.language_rounded, color: p.accentTexte),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t(envoi ? 'web_titre' : 'web_recevoir'), style: Typo.titreCarte.copyWith(color: p.texte)),
                const SizedBox(height: 2),
                Text(context.t(envoi ? 'web_carte' : 'web_carte_recevoir'), style: Typo.secondaire.copyWith(color: p.texte2)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.texte3),
        ],
      ),
    );
  }
}
