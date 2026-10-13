// SUR ORDINATEUR : GLISSER-DÉPOSER ET RACCOURCIS CLAVIER.
//
//   • Déposer des fichiers ou des dossiers sur la fenêtre ouvre directement
//     le choix des destinataires — le geste le plus naturel d'un ordinateur,
//     celui d'AirDrop dans le Finder.
//   • ⌘O / Ctrl+O : choisir des fichiers à envoyer ; ⌘R / Ctrl+R :
//     recevoir ; ⌘, / Ctrl+, : réglages (les raccourcis habituels du Mac).
//
// Sur téléphone, rien de tout cela : la zone et les raccourcis s'effacent.
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/modeles.dart';
import '../app/textes.dart';
import '../design/composants.dart';
import '../design/couleurs.dart';
import '../design/marque.dart';
import '../design/typo.dart';
import 'choisir.dart';
import 'recevoir.dart';
import 'reglages.dart';

class ZoneDepot extends StatefulWidget {
  const ZoneDepot({super.key, required this.child});

  final Widget child;

  @override
  State<ZoneDepot> createState() => _ZoneDepotState();
}

class _ZoneDepotState extends State<ZoneDepot> {
  bool _survol = false;

  Future<void> _deposer(List<String> chemins) async {
    final choisis = <Choisi>[];
    for (final c in chemins) {
      if (FileSystemEntity.isDirectorySync(c)) {
        choisis.addAll(await contenuDossier(Directory(c)));
      } else {
        final f = File(c);
        if (f.existsSync()) choisis.add(Choisi(chemin: c, nom: c.split(Platform.pathSeparator).last, taille: f.lengthSync()));
      }
    }
    if (choisis.isEmpty || !mounted) return;
    HapticFeedback.mediumImpact();
    await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => EcranDestinataires(choisis: choisis)));
  }

  @override
  Widget build(BuildContext context) {
    if (estMobile) return widget.child;
    final p = context.p;
    return DropTarget(
      onDragEntered: (_) => setState(() => _survol = true),
      onDragExited: (_) => setState(() => _survol = false),
      onDragDone: (d) {
        setState(() => _survol = false);
        _deposer([for (final f in d.files) f.path]);
      },
      child: Stack(
        children: [
          widget.child,
          // Le voile de dépôt : il n'intercepte rien, il montre seulement
          // que la fenêtre attend les fichiers.
          IgnorePointer(
            child: AnimatedOpacity(
              opacity: _survol ? 1 : 0,
              duration: duree(context, 180),
              child: Container(
                color: p.fond.withValues(alpha: 0.82),
                padding: const EdgeInsets.all(20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(color: p.accent, width: 2),
                    color: p.accent.withValues(alpha: 0.06),
                  ),
                  child: Center(
                    child: AnimatedScale(
                      scale: _survol ? 1 : 0.92,
                      duration: duree(context, 320),
                      curve: kRessort,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Goutte(taille: 72),
                          const SizedBox(height: 18),
                          Text(context.t('deposer_titre'), style: Typo.titre.copyWith(color: p.texte)),
                          const SizedBox(height: 6),
                          Text(context.t('deposer_texte'), textAlign: TextAlign.center, style: Typo.secondaire.copyWith(color: p.texte2)),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Raccourcis extends StatelessWidget {
  const Raccourcis({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (estMobile) return child;
    final mac = Platform.isMacOS;
    SingleActivator touche(LogicalKeyboardKey k) => SingleActivator(k, meta: mac, control: !mac);
    void ouvrir(Widget Function() ecran) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ecran()));
    return CallbackShortcuts(
      bindings: {
        touche(LogicalKeyboardKey.keyO): () => choisirPuisEnvoyer(context),
        touche(LogicalKeyboardKey.keyR): () => ouvrir(() => const Recevoir()),
        touche(LogicalKeyboardKey.comma): () => ouvrir(() => const EcranReglages()),
      },
      child: Focus(autofocus: true, child: child),
    );
  }
}
