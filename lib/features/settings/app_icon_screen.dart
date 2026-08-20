// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// L'écran où l'on CHOISIT L'ICÔNE de Droplet — celle qui apparaîtra sur
// l'écran d'accueil du téléphone.
//
// Une grille de vignettes à la taille réelle d'une icône, avec une coche
// sur celle qui est active. C'est la disposition qu'emploient toutes les
// applications proposant ce réglage, et pour une bonne raison : on
// choisit une icône À L'ŒIL, pas d'après son nom. Une liste de lignes
// obligerait à imaginer le résultat.
//
// ── Pourquoi une confirmation ─────────────────────────────────────────
//
// Le changement se répercute sur l'écran d'accueil du téléphone, hors de
// l'application — et certains lanceurs mettent quelques secondes à s'en
// apercevoir. Un appui accidentel qui modifierait l'icône du téléphone
// sans prévenir serait déroutant, d'où la confirmation.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers/mesh_provider.dart';
import '../../core/providers/premium_provider.dart';
import '../../core/services/app_icon_service.dart';
import '../../design_system/design_tokens.dart';
import '../../design_system/ouro_alert.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_haptics.dart';
import '../../design_system/ouro_scaffold.dart';
import '../../design_system/ouro_typography.dart';
import '../../shared/widgets/premium_badge.dart';

class AppIconScreen extends ConsumerStatefulWidget {
  const AppIconScreen({super.key});

  @override
  ConsumerState<AppIconScreen> createState() => _AppIconScreenState();
}

class _AppIconScreenState extends ConsumerState<AppIconScreen> {
  String _current = 'Default';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final alias = await AppIconService.current();
    if (mounted) setState(() => _current = alias);
  }

  Future<void> _choose(AppIconOption option) async {
    if (_busy || option.alias == _current) return;
    OuroHaptics.selection();

    // ⚠️ LE VERROU EST ICI, DANS L'ACTION — pas seulement sur la
    // vignette. Une grille peut être parcourue au clavier, par un
    // lecteur d'écran, ou touchée pendant que l'état change ; contrôler
    // uniquement à l'affichage laisserait toutes ces portes ouvertes.
    // L'affichage prévient, l'action décide.
    if (option.premium && !ref.read(packDebloqueProvider)) {
      // On emmène là où ça se débloque plutôt que d'opposer un refus
      // sans issue.
      context.push('/premium');
      return;
    }

    final confirmed = await ouroConfirm(
      context,
      title: "Changer l'icône ?",
      message: "L'icône « ${option.name} » remplacera celle de votre écran "
          "d'accueil. Certains lanceurs mettent quelques secondes à "
          "l'afficher, ou demandent de revenir à l'accueil.",
      confirmLabel: 'Appliquer',
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    final ok = await AppIconService.apply(option.alias);
    if (!mounted) return;

    // ⚠️ `_busy` est relâché DANS TOUS LES CAS.
    //
    // La première version le laissait levé en cas de succès, en
    // supposant qu'Android allait tuer l'application juste après. Or le
    // changement se fait avec `DONT_KILL_APP` : l'app survit, et l'écran
    // restait alors définitivement grisé et insensible — on ne pouvait
    // plus changer d'avis sans quitter la page.
    setState(() {
      _busy = false;
      if (ok) _current = option.alias;
    });

    if (ok) {
      OuroHaptics.success();
      ref.read(toastProvider.notifier).show(
            'Icône « ${option.name} » appliquée',
            type: DropletToastType.success,
          );
    } else {
      OuroHaptics.error();
      ref.read(toastProvider.notifier).show(
            "Changement d'icône impossible sur cet appareil",
            type: DropletToastType.error,
          );
    }
  }

  @override
  Widget build(BuildContext context) {
    final supported = AppIconService.isSupported;

    return OuroLargeTitleScaffold(
      title: 'Icône',
      subtitle: supported
          ? 'Celle qui apparaît sur votre écran d\'accueil'
          : 'Indisponible sur cette plateforme',
      backgroundColor: OuroColors.systemGroupedBackground,
      leading: const OuroBackButton(fallback: '/settings'),
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            DesignTokens.screenMargin,
            0,
            DesignTokens.screenMargin,
            DesignTokens.space5,
          ),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 20,
              crossAxisSpacing: 16,
              // Un peu plus haut que large : la vignette est carrée, le
              // nom vient en dessous.
              childAspectRatio: 0.78,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final option = AppIconService.options[index];
                final verrouille =
                    option.premium && !ref.watch(packDebloqueProvider);
                return _IconTile(
                  option: option,
                  selected: option.alias == _current,
                  // Verrouillée mais TOUCHABLE : le geste mène à la page
                  // de déblocage. La désactiver ne dirait rien à
                  // personne — un carreau qui ne réagit pas se lit comme
                  // une panne, pas comme une offre.
                  enabled: supported && !_busy,
                  verrouille: verrouille,
                  onTap: () => _choose(option),
                );
              },
              childCount: AppIconService.options.length,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.screenMargin,
              0,
              DesignTokens.screenMargin,
              DesignTokens.space6,
            ),
            child: Text(
              supported
                  ? 'Android fige l\'icône d\'une application dans son '
                      'installation. Droplet contourne cela en déclarant '
                      'plusieurs points d\'entrée, un par icône, et en '
                      'n\'en laissant qu\'un actif. Votre lanceur peut '
                      'mettre quelques secondes à s\'en apercevoir.'
                  : 'Le changement d\'icône n\'est disponible que sur '
                      'Android.',
              style: OuroTypography.footnote.copyWith(
                color: OuroColors.secondaryLabel,
                height: 1.4,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Une vignette d'icône dans la grille.
class _IconTile extends StatefulWidget {
  const _IconTile({
    required this.option,
    required this.selected,
    required this.enabled,
    required this.onTap,
    this.verrouille = false,
  });

  final AppIconOption option;
  final bool selected;
  final bool enabled;
  final VoidCallback onTap;

  /// Demande le pack : la vignette s'affaiblit et porte une étoile.
  final bool verrouille;

  @override
  State<_IconTile> createState() => _IconTileState();
}

class _IconTileState extends State<_IconTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? widget.onTap : null,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.93 : 1,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    // Pas d'opacité réduite ici : une icône à 40 %
                    // devient une bouillie grise, et c'est justement sa
                    // COULEUR qu'on vient regarder. Le blocage
                    // temporaire pendant l'application se signale par
                    // l'absence de réaction au doigt, pas en délavant
                    // toute la grille.
                    // ⚠️ LA VIGNETTE VERROUILLÉE RESTE PRESQUE PLEINE.
                    //
                    // C'est la COULEUR de l'icône qu'on vient regarder,
                    // et c'est elle qui donne envie de l'acheter. La
                    // délaver à 40 % en ferait une bouillie grise :
                    // on aurait caché exactement ce qu'on essaie de
                    // vendre. On retire donc un quart de la lumière,
                    // et c'est l'étoile en coin qui dit « pas encore ».
                    child: Opacity(
                      opacity: widget.verrouille ? 0.72 : 1,
                      child: Image.asset(
                        widget.option.asset,
                        width: 88,
                        height: 88,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  ),
                ),
                if (widget.verrouille)
                  Positioned(
                    right: 2,
                    top: 2,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: OuroColors.systemBackground
                            .withValues(alpha: 0.9),
                      ),
                      child: Icon(Icons.auto_awesome_rounded,
                          size: 12, color: OuroColors.accent),
                    ),
                  ),
                // ⚠️ UNE ICÔNE VERROUILLÉE N'EST PAS DÉLAVÉE, et c'est
                // le même raisonnement que le commentaire ci-dessus :
                // c'est sa COULEUR qu'on vient regarder. L'affaiblir la
                // rendrait terne — donc moins désirable — alors que tout
                // l'intérêt est qu'on ait envie de celle-là. On se
                // contente d'une étoile dans le coin, qui dit « pas
                // encore à vous » sans abîmer ce qu'on montre.
                if (widget.verrouille)
                  const Positioned(
                    right: -2,
                    top: -2,
                    child: EtiquettePremium(compacte: true),
                  ),
                if (widget.selected)
                  Positioned(
                    right: -4,
                    bottom: -4,
                    child: Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: OuroColors.accent,
                        // Le liseré prend la couleur du fond de l'écran,
                        // pas du blanc : sinon il apparaîtrait comme un
                        // cerne clair en mode sombre.
                        border: Border.all(
                          color: OuroColors.systemGroupedBackground,
                          width: 3,
                        ),
                      ),
                      child: const Icon(Icons.check_rounded,
                          color: Colors.white, size: 15),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.option.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: OuroTypography.caption1.copyWith(
                color: widget.selected
                    ? OuroColors.accent
                    : OuroColors.secondaryLabel,
                fontWeight:
                    widget.selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
