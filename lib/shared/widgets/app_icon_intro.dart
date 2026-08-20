// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'APPARITION DE L'ICÔNE au lancement de l'app — ces deux secondes que
// toutes les grandes applications soignent et que personne ne remarque
// consciemment.
//
// ── Pourquoi ce n'est pas juste « un fondu » ───────────────────────────
//
// Quand on appuie sur l'icône de Droplet, le téléphone affiche d'abord
// lui-même un écran fixe (le fond blanc ou noir du système), puis passe
// la main à l'app. Si l'app affichait alors son logo d'un coup, on
// verrait un à-coup : deux images qui se remplacent.
//
// L'astuce des grandes apps est de faire ARRIVER l'icône, très
// légèrement plus petite, en la faisant grandir jusqu'à sa taille finale
// pendant qu'elle apparaît. L'œil lit ce mouvement comme une continuité :
// l'icône sur laquelle on vient d'appuyer semble s'avancer vers nous,
// plutôt qu'une nouvelle image qui la remplace.
//
// Trois règles tenues ici, empruntées à ce que fait Apple :
//
//   1. AUCUN REBOND. L'icône ne dépasse jamais sa taille finale pour y
//      revenir : elle y arrive et s'y arrête. Un rebond, à l'ouverture
//      d'une app de messagerie d'urgence, fait jouet.
//   2. LE MOUVEMENT FINIT AVANT LE REGARD. La courbe est très rapide au
//      début puis très lente à la fin, si bien que l'icône est
//      pratiquement en place avant qu'on ait eu le temps de la fixer.
//   3. LA SORTIE FAIT PARTIE DE L'ENTRÉE. En quittant, l'icône grandit
//      encore un peu en s'effaçant — comme si on la traversait pour
//      entrer dans l'app.
// ============================================================================

import 'package:flutter/material.dart';

class AppIconIntro extends StatefulWidget {
  const AppIconIntro({
    super.key,
    this.size = 116,
    this.label,
    this.labelStyle,
    this.captionStyle,
    this.caption,
    this.leaving = false,
  });

  /// Côté de l'icône, en points.
  final double size;

  /// Le nom de l'app, écrit sous l'icône. Apparaît après elle.
  final String? label;
  final TextStyle? labelStyle;

  /// La ligne discrète sous le nom.
  final String? caption;
  final TextStyle? captionStyle;

  /// Passe à vrai au moment de quitter l'écran : l'ensemble grandit
  /// légèrement en s'effaçant.
  final bool leaving;

  @override
  State<AppIconIntro> createState() => _AppIconIntroState();
}

class _AppIconIntroState extends State<AppIconIntro>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  // Une seule horloge pour toute la séquence, et chaque élément y prend
  // sa tranche. C'est plus simple à régler qu'un contrôleur par élément,
  // et surtout impossible à désynchroniser.
  static const Duration _total = Duration(milliseconds: 1100);

  late final Animation<double> _iconFade;
  late final Animation<double> _iconScale;
  late final Animation<double> _glow;
  late final Animation<double> _labelFade;
  late final Animation<double> _labelRise;
  late final Animation<double> _captionFade;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: _total);

    // L'icône : elle apparaît vite (le fondu est terminé au tiers du
    // temps) mais continue de grandir bien après. C'est ce décalage qui
    // donne l'impression d'un objet qui s'avance, et non d'une image qui
    // se révèle.
    _iconFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.0, 0.34, curve: Curves.easeOut),
    );
    _iconScale = Tween<double>(begin: 0.74, end: 1.0).animate(
      CurvedAnimation(
        parent: _c,
        // Très rapide au début, très lente à la fin : l'icône est déjà
        // presque en place quand l'œil s'y pose.
        curve: const Interval(0.0, 0.62, curve: Curves.fastEaseInToSlowEaseOut),
      ),
    );

    // Une lueur qui s'installe sous l'icône, pour la décoller du fond.
    // Elle arrive APRÈS l'icône : une ombre déjà présente pendant que
    // l'objet grandit trahirait le trucage.
    _glow = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.28, 0.75, curve: Curves.easeOut),
    );

    _labelFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.38, 0.72, curve: Curves.easeOut),
    );
    _labelRise = Tween<double>(begin: 12, end: 0).animate(
      CurvedAnimation(
        parent: _c,
        curve: const Interval(0.38, 0.86, curve: Curves.easeOutCubic),
      ),
    );
    _captionFade = CurvedAnimation(
      parent: _c,
      curve: const Interval(0.58, 0.92, curve: Curves.easeOut),
    );

    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: widget.leaving ? 0 : 1,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeIn,
      child: AnimatedScale(
        // En partant, l'ensemble grandit encore un peu : on a
        // l'impression de traverser l'icône pour entrer dans l'app,
        // plutôt que de la voir s'éteindre.
        scale: widget.leaving ? 1.08 : 1.0,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeIn,
        child: AnimatedBuilder(
          animation: _c,
          builder: (context, _) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Opacity(
                  opacity: _iconFade.value,
                  child: Transform.scale(
                    scale: _iconScale.value,
                    child: _icon(),
                  ),
                ),
                if (widget.label != null) ...[
                  const SizedBox(height: 26),
                  Opacity(
                    opacity: _labelFade.value,
                    child: Transform.translate(
                      offset: Offset(0, _labelRise.value),
                      child: Text(widget.label!, style: widget.labelStyle),
                    ),
                  ),
                ],
                if (widget.caption != null) ...[
                  const SizedBox(height: 8),
                  Opacity(
                    opacity: _captionFade.value,
                    child: Text(
                      widget.caption!,
                      textAlign: TextAlign.center,
                      style: widget.captionStyle,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _icon() {
    final radius = widget.size * 0.2237; // le rayon des coins de l'icône
    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: [
          BoxShadow(
            // Teintée du bleu de l'icône plutôt que noire : une ombre
            // grise sous un objet coloré le salit, alors qu'une ombre de
            // sa propre teinte le fait rayonner.
            color: const Color(0xFF0E76FB).withValues(alpha: 0.28 * _glow.value),
            blurRadius: 44 * _glow.value,
            spreadRadius: -6,
            offset: Offset(0, 14 * _glow.value),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/icon/droplet_icon.png',
          width: widget.size,
          height: widget.size,
          // L'icône est déjà rendue en haute résolution : on laisse
          // Flutter la réduire avec un filtrage doux, sinon ses courbes
          // se crénellent aux petites tailles.
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
