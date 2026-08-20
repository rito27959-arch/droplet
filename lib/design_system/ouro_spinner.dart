// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'INDICATEUR D'ATTENTE — la petite chose qui tourne pendant qu'on
// patiente. Il y en a un dans presque chaque écran, et c'est justement ce
// qui rend son dessin important.
//
// ── Les deux dessins, et pourquoi ils ne se valent pas ────────────────
//
// Android fait tourner UN ARC : un fragment de cercle qui court après sa
// queue, s'allonge et se raccourcit. C'est le `CircularProgressIndicator`
// de Flutter, celui qu'on obtient sans rien demander.
//
// iOS dessine UNE COURONNE DE TRAITS qui s'éteignent l'un après l'autre.
// Rien ne tourne réellement : c'est la luminosité qui se déplace autour
// du cercle. Le mouvement est plus calme, et il ne dit pas la même chose
// — l'arc d'Android suggère une progression, la couronne d'iOS dit
// simplement « ça travaille ».
//
// Onze écrans de Droplet affichaient l'arc d'Android. C'est le genre de
// détail qu'on ne remarque jamais consciemment, mais qui apparaît à
// chaque envoi de message, chaque chargement d'image, chaque
// sauvegarde — et qui, répété, trahit la plateforme d'origine plus
// sûrement qu'un écran entier mal dessiné.
//
// ⚠️ CE COMPOSANT NE SERT QU'À L'ATTENTE SANS FIN. Quand on connaît
// l'avancement (un fichier à 40 %, une vidéo à 30 secondes sur 90), il
// faut un anneau qui se remplit — pas celui-ci.
// ============================================================================

import 'package:flutter/cupertino.dart';

import 'ouro_colors.dart';

/// Indicateur d'attente iOS.
///
/// [radius] est la MOITIÉ de la taille occupée : 10 donne 20 points de
/// côté, la taille standard d'iOS. En descendre à 8 ou 9 pour un
/// indicateur logé dans un bouton.
class OuroSpinner extends StatelessWidget {
  const OuroSpinner({super.key, this.color, this.radius = 10});

  final Color? color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CupertinoActivityIndicator(
      radius: radius,
      color: color ?? OuroColors.secondaryLabel,
    );
  }
}
