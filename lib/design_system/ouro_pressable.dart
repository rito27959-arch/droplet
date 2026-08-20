// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LA RÉPONSE AU TOUCHER — ce que fait un élément quand on pose le doigt
// dessus. Avec le rebond des listes et le glissement des pages, c'est le
// troisième geste par lequel on reconnaît une plateforme sans y penser.
//
// ── Les deux réponses ─────────────────────────────────────────────────
//
// Android propage UNE ONDE depuis le point touché — le fameux « ripple »
// de Material. Elle se répand, atteint les bords, puis s'efface. C'est
// une animation qui a sa propre durée : elle continue après que le doigt
// est parti.
//
// iOS ENFONCE l'élément. Il rapetisse d'un cheveu et s'assombrit, tant
// que le doigt est là, et revient dès qu'il se lève. Rien ne se propage,
// rien ne survit au geste. La réponse est instantanée et strictement
// liée au contact.
//
// ── Pourquoi ce fichier existe ────────────────────────────────────────
//
// Trois endroits de Droplet propageaient l'onde d'Android : les boutons
// de l'écran d'appel — celui qu'on regarde le plus longtemps sans rien
// faire d'autre —, ceux de l'appel de groupe, et surtout `OuroCard`, la
// carte partagée par une bonne partie de l'application. Un commentaire
// revendiquait même « un vrai ripple M3 ».
//
// Mettre la bonne réponse ici, une fois, évite de la réinventer à chaque
// élément cliquable — et évite surtout d'en avoir deux qui cohabitent.
// ============================================================================

import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// Enveloppe un élément cliquable et lui donne l'enfoncement d'iOS.
///
/// [scale] est le rétrécissement au toucher. 0,97 convient à une carte
/// large — le même pourcentage sur un grand élément se voit beaucoup
/// plus que sur un petit ; descendre vers 0,92 pour un bouton rond.
class OuroPressable extends StatefulWidget {
  const OuroPressable({
    super.key,
    required this.child,
    required this.onTap,
    this.scale = 0.97,
    this.opacity = 0.75,
    this.semantique,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double scale;
  final double opacity;

  /// Ce que le lecteur d'écran annonce à la place du contenu.
  ///
  /// ⚠️ À RENSEIGNER DÈS QUE L'ENFANT EST UNE ICÔNE SEULE.
  ///
  /// Quand l'enfant contient du texte, Flutter s'en sert
  /// automatiquement : VoiceOver lit « Envoyer, bouton ». Mais quand
  /// l'enfant est une icône — ce qui est le cas de la moitié des boutons
  /// de Droplet — il n'y a AUCUN texte à lire. Le lecteur d'écran
  /// annonce alors « bouton », sans dire lequel. Pour quelqu'un qui ne
  /// voit pas l'écran, une barre d'outils devient une rangée de boutons
  /// anonymes : l'app est là, mais elle est inutilisable.
  final String? semantique;

  @override
  State<OuroPressable> createState() => _OuroPressableState();
}

class _OuroPressableState extends State<OuroPressable> {
  bool _pressed = false;

  void _set(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;

    // `Semantics(button: true)` fait deux choses, toutes deux
    // nécessaires : il annonce l'élément COMME un bouton (VoiceOver dit
    // « … bouton », et l'utilisateur sait qu'il peut activer), et il
    // l'expose à l'activation directe — sans quoi un lecteur d'écran ne
    // peut PAS déclencher un simple `GestureDetector`, qui n'est pour
    // lui qu'une zone inerte.
    // ⚠️ `MergeSemantics` est indispensable quand aucun libellé n'est
    // fourni.
    //
    // Sans lui, le bouton et son contenu restent DEUX éléments distincts
    // pour le lecteur d'écran : il annonce « bouton » — sans nom — puis,
    // à l'arrêt suivant, « Envoyer ». L'utilisateur doit relier les deux
    // de tête, et pire, il peut activer le premier sans savoir ce qu'il
    // déclenche. Fusionnés, cela donne un seul arrêt : « Envoyer,
    // bouton ».
    //
    // Quand un libellé EST fourni, on masque au contraire le contenu :
    // le libellé dit déjà tout, et laisser passer l'enfant ferait
    // entendre l'information en double.
    final avecLibelle = widget.semantique != null;

    final semantique = Semantics(
      button: true,
      label: widget.semantique,
      excludeSemantics: avecLibelle,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? widget.scale : 1,
          duration: DesignTokens.durationFast,
          curve: DesignTokens.curveSpring,
          child: AnimatedOpacity(
            opacity: _pressed ? widget.opacity : 1,
            duration: DesignTokens.durationFast,
            child: widget.child,
          ),
        ),
      ),
    );

    return avecLibelle ? semantique : MergeSemantics(child: semantique);
  }
}
