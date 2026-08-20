// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// COMMENT LES LISTES RÉAGISSENT QUAND ON ARRIVE AU BOUT. C'est un détail
// d'une ligne de code, et pourtant l'un des deux ou trois gestes par
// lesquels on reconnaît un iPhone d'un Android les yeux fermés.
//
// ── Les deux comportements ────────────────────────────────────────────
//
// Android : la liste S'ARRÊTE NET, et un halo lumineux s'étire au bord
// de l'écran pour signaler la butée. Depuis Android 12, tout le contenu
// se déforme légèrement à la place du halo. Dans les deux cas, le
// mouvement est INTERROMPU.
//
// iOS : la liste CONTINUE au-delà de sa fin, de plus en plus lentement,
// puis revient d'elle-même en place comme un élastique. Rien ne s'arrête
// jamais brutalement. C'est le « rubber banding », et c'est ce qui donne
// aux listes d'iOS leur sensation de matière.
//
// ── Pourquoi ce fichier existe ────────────────────────────────────────
//
// Un seul écran de Droplet avait le rebond : celui à grand titre, qui le
// demandait explicitement. Partout ailleurs — les infos d'une
// conversation, les membres d'un groupe, la sauvegarde, la galerie d'un
// statut, la conversation elle-même — les listes s'arrêtaient net avec le
// halo d'Android. On passait donc d'une sensation à l'autre en changeant
// d'écran, ce qui est pire que d'avoir partout la même, même mauvaise.
//
// Le poser sur `MaterialApp` le rend valable pour TOUT ce qui défile
// dans l'app, y compris les listes qu'on écrira demain — plutôt que
// d'avoir à y penser à chaque `ListView`.
// ============================================================================

import 'package:flutter/material.dart';

/// Comportement de défilement iOS, appliqué à toute l'application.
class OuroScrollBehavior extends MaterialScrollBehavior {
  const OuroScrollBehavior();

  /// Le rebond élastique, sur tous les axes et toutes les listes.
  ///
  /// `RangeMaintainingScrollPhysics` en parent est ce que fait Flutter
  /// lui-même sur iOS : il garde la position de lecture stable quand le
  /// contenu grandit au-dessus du point où l'on se trouve — sans lui,
  /// une conversation sauterait à chaque message qui arrive plus haut.
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: RangeMaintainingScrollPhysics());

  /// Pas de halo ni d'étirement au bord : c'est le rebond qui dit qu'on
  /// est arrivé au bout, et les deux ensemble feraient doublon.
  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
