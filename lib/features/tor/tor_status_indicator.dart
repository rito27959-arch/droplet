// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'ÉTAT DE TOR, DIT PAR UN CADENAS QUI SE FERME.
//
// ── Ce que faisait la version précédente ──────────────────────────────
//
// Un bandeau pleine largeur, avec trois couleurs Material brutes
// (`Colors.amber.shade700`, `Colors.green.shade600`, `Colors.red.shade600`)
// qui n'existent nulle part ailleurs dans l'application, une icône
// différente par état — bouclier, roue, point d'exclamation — et un
// clignotement de toute la barre pendant la connexion.
//
// Trois problèmes, dans l'ordre de gravité :
//
//   1. CHANGER D'ICÔNE À CHAQUE ÉTAT EMPÊCHE DE LIRE LA TRANSITION. Un
//      bouclier qui remplace une roue ne raconte rien ; un cadenas dont
//      l'anse descend raconte « c'est en train de se fermer ». iOS ne
//      remplace jamais un symbole par un autre pour dire qu'un même objet
//      a changé d'état.
//
//   2. LE CLIGNOTEMENT EST UN MARQUEUR D'INTERFACE AMATEUR. Il attire
//      l'œil en permanence, à un rythme que rien ne justifie, et fatigue
//      en quelques secondes. iOS emploie un mouvement CONTINU (une barre
//      qui progresse, un halo qui balaie) pour dire « ça travaille ».
//
//   3. UNE ERREUR SANS ISSUE. « Erreur Tor » s'affichait sans qu'on
//      puisse rien en faire : il fallait deviner qu'il fallait aller dans
//      les réglages. Ici, la capsule elle-même relance.
//
// ── Ce qu'il fait maintenant ──────────────────────────────────────────
//
// Une capsule qui DESCEND du haut, un cadenas dont l'anse se ferme quand
// le circuit s'établit, et qui se rouvre s'il retombe. Quand tout va
// bien, la capsule se réduit d'elle-même au seul cadenas au bout de
// quelques secondes : l'information reste disponible, elle cesse
// d'occuper une bande entière pour répéter que tout va bien.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers/tor_providers.dart';
import '../../core/services/tor_service.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_liquid_surface.dart';
import '../../design_system/ouro_padlock.dart';
import '../../design_system/ouro_pressable.dart';
import '../../design_system/ouro_typography.dart';

class TorStatusIndicator extends ConsumerStatefulWidget {
  const TorStatusIndicator({super.key});

  @override
  ConsumerState<TorStatusIndicator> createState() => _TorStatusIndicatorState();
}

class _TorStatusIndicatorState extends ConsumerState<TorStatusIndicator>
    with TickerProviderStateMixin {
  /// Le balayage lumineux pendant la connexion — un mouvement continu,
  /// pas un clignotement.
  late final AnimationController _balayage;

  /// L'anse du cadenas. Sa valeur EST l'état du circuit : 1 = fermé.
  late final AnimationController _anse;

  /// La capsule est-elle réduite à son seul cadenas ?
  bool _reduite = false;

  @override
  void initState() {
    super.initState();
    _balayage = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _anse = AnimationController(
      vsync: this,
      duration: DesignTokens.durationStandard,
    );
  }

  @override
  void dispose() {
    _balayage.dispose();
    _anse.dispose();
    super.dispose();
  }

  /// Répercute l'état du service sur l'anse et sur la réduction.
  ///
  /// ⚠️ Appelé depuis `build`, donc jamais de `setState` synchrone ici :
  /// on programme les changements pour la fin de l'image.
  void _accorder(TorServiceState etat) {
    final ferme = etat == TorServiceState.connected;
    if (ferme && _anse.status != AnimationStatus.forward && _anse.value < 1) {
      _anse.forward();
      // Une fois connecté, la capsule se retire d'elle-même. Trois
      // secondes : le temps de lire, pas plus.
      Future<void>.delayed(const Duration(seconds: 3), () {
        if (mounted && ref.read(torStateProvider).valueOrNull ==
            TorServiceState.connected) {
          setState(() => _reduite = true);
        }
      });
    } else if (!ferme && _anse.value > 0 && _anse.status != AnimationStatus.reverse) {
      // Le circuit est retombé : l'anse se rouvre. C'est le seul moment
      // où l'utilisateur doit relever la tête, donc la capsule reprend
      // sa taille entière.
      _anse.reverse();
      if (_reduite) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) setState(() => _reduite = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final etat = ref.watch(torStateProvider).valueOrNull;

    // `stopped` et l'absence d'état ne méritent aucune place à l'écran :
    // Tor est une option, pas une promesse permanente.
    if (etat == null || etat == TorServiceState.stopped) {
      return const SizedBox.shrink();
    }

    _accorder(etat);

    final (couleur, texte) = switch (etat) {
      TorServiceState.connecting => (OuroColors.systemOrange, 'Connexion Tor…'),
      TorServiceState.connected => (OuroColors.systemGreen, 'Tor actif'),
      TorServiceState.error => (OuroColors.systemRed, 'Tor indisponible'),
      TorServiceState.stopped => (OuroColors.systemGray, 'Tor éteint'),
    };

    final capsule = AnimatedBuilder(
      animation: Listenable.merge([_anse, _balayage]),
      builder: (context, _) => _Capsule(
        couleur: couleur,
        texte: texte,
        fermeture: _anse.value,
        balayage: etat == TorServiceState.connecting ? _balayage.value : null,
        reduite: _reduite,
      ),
    );

    return Center(
      // La capsule DESCEND du haut à son apparition, et remonte pour
      // disparaître : elle vient de la barre d'état, là où le système
      // range ce qui concerne la connexion.
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0, end: 1),
        duration: DesignTokens.durationStandard,
        curve: DesignTokens.curveEnter,
        builder: (context, t, enfant) => Transform.translate(
          offset: Offset(0, -18 * (1 - t)),
          child: Opacity(opacity: t, child: enfant),
        ),
        child: etat == TorServiceState.error
            // Une erreur doit pouvoir être traitée là où elle s'affiche.
            ? OuroPressable(
                semantique: 'Tor indisponible. Toucher pour réessayer.',
                onTap: () => ref.read(torServiceProvider).start(),
                child: capsule,
              )
            : capsule,
      ),
    );
  }
}

/// Le dessin de la capsule.
class _Capsule extends StatelessWidget {
  const _Capsule({
    required this.couleur,
    required this.texte,
    required this.fermeture,
    required this.balayage,
    required this.reduite,
  });

  final Color couleur;
  final String texte;

  /// 0 = anse ouverte, 1 = fermée.
  final double fermeture;

  /// Position du balayage lumineux (0..1), ou `null` si rien ne progresse.
  final double? balayage;

  final bool reduite;

  @override
  Widget build(BuildContext context) {
    // Même matière que la capsule de notification et que la barre
    // d'onglets : sur iOS, tout ce qui flotte au-dessus du contenu est
    // fait de la même chose. Une seule capsule sur cet écran qui serait
    // en verre dépoli quand les autres réfractent se remarquerait
    // immédiatement, sans qu'on sache dire quoi.
    return OuroLiquidSurface(
      borderRadius: DesignTokens.radiusFull,
      thickness: 8,
      blur: 10,
      child: AnimatedContainer(
      duration: DesignTokens.durationStandard,
      curve: DesignTokens.curveStandard,
      margin: const EdgeInsets.symmetric(vertical: DesignTokens.space1),
      padding: EdgeInsets.symmetric(
        horizontal: reduite ? DesignTokens.space2 : DesignTokens.space3,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
        border: Border.all(color: couleur.withValues(alpha: 0.30), width: 0.5),
      ),
      child: Stack(
        children: [
          // Le balayage : une bande claire qui traverse la capsule de
          // gauche à droite, en boucle. C'est la façon dont iOS dit
          // « quelque chose progresse » sans clignoter.
          if (balayage != null)
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(DesignTokens.radiusFull),
                child: FractionallySizedBox(
                  alignment: Alignment(-1 + balayage! * 2.6, 0),
                  widthFactor: 0.42,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          couleur.withValues(alpha: 0),
                          couleur.withValues(alpha: 0.20),
                          couleur.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              OuroPadlock(fermeture: fermeture, couleur: couleur, taille: 14),
              // Le texte disparaît en fondu ET en largeur : sans la
              // largeur, la capsule garderait sa taille pour du vide.
              ClipRect(
                child: AnimatedAlign(
                  duration: DesignTokens.durationStandard,
                  curve: DesignTokens.curveStandard,
                  alignment: Alignment.centerLeft,
                  widthFactor: reduite ? 0 : 1,
                  child: Padding(
                    padding: const EdgeInsets.only(left: DesignTokens.space2),
                    child: Text(
                      texte,
                      style: OuroTypography.caption1.copyWith(
                        color: couleur,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }
}
