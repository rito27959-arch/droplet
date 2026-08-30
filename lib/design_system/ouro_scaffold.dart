// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// LE GRAND TITRE REPLIABLE — le geste signature d'iOS, celui qu'on voit
// dans Réglages, Mail, Messages ou Musique.
//
// COMMENT ÇA MARCHE : au repos, le nom de l'écran s'affiche en très gros
// (34 points) sous la barre du haut. Dès qu'on fait défiler le contenu,
// ce grand titre remonte, rétrécit et vient se loger, en petit et centré,
// dans la barre de navigation — pendant qu'un fin trait de séparation
// apparaît sous celle-ci. On peut lire l'écran en grand quand on arrive,
// et garder le repère de « où je suis » une fois plongé dans le contenu.
//
// POURQUOI C'EST DÉCISIF : c'est le comportement que tout utilisateur
// d'iPhone connaît sans savoir le nommer. Une app qui affiche un titre
// fixe et petit paraît immédiatement « portée depuis une autre
// plateforme », même si tout le reste est parfait. C'est probablement le
// seul détail de cette refonte qui se remarque dès la première seconde.
//
// Le fond de la barre est un matériau translucide (voir
// `glassmorphism.dart`) : le contenu passe DERRIÈRE en étant flouté, au
// lieu de disparaître sous un bandeau opaque.
// ============================================================================

import 'package:flutter/cupertino.dart' show CupertinoSliverRefreshControl;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'ouro_colors.dart';
import 'ouro_haptics.dart';
import 'ouro_typography.dart';
import 'glassmorphism.dart';
import 'design_tokens.dart';

/// Écran à grand titre repliable, façon iOS.
///
/// À utiliser pour tous les écrans de premier niveau (Discussions,
/// Réglages, Réseau...). Pour un écran secondaire ouvert par-dessus, un
/// simple `AppBar` avec titre centré suffit — c'est aussi ce que fait iOS.
class OuroLargeTitleScaffold extends StatefulWidget {
  const OuroLargeTitleScaffold({
    super.key,
    required this.title,
    required this.slivers,
    this.leading,
    this.actions,
    this.subtitle,
    this.floatingActionButton,
    this.floatingNotification,
    this.backgroundColor,
    this.onRefresh,
  });

  /// Nom de l'écran, affiché en grand puis replié dans la barre.
  final String title;

  /// Ligne discrète sous le grand titre (état de connexion, compteur).
  final String? subtitle;

  /// Le contenu, sous forme de slivers (`SliverList`, `SliverToBoxAdapter`...)
  /// — nécessaire pour que le défilement pilote le repli du titre.
  final List<Widget> slivers;

  final Widget? leading;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? floatingNotification;
  final Color? backgroundColor;

  /// Tirer vers le bas pour rafraîchir — utilise l'indicateur iOS.
  final Future<void> Function()? onRefresh;

  @override
  State<OuroLargeTitleScaffold> createState() => _OuroLargeTitleScaffoldState();
}

class _OuroLargeTitleScaffoldState extends State<OuroLargeTitleScaffold> {
  final _scrollController = ScrollController();

  /// Vrai quand le grand titre a disparu — la barre affiche alors le
  /// petit titre et son trait de séparation.
  bool _collapsed = false;

  /// Hauteur du grand titre, au-delà de laquelle on considère qu'il est
  /// replié.
  static const double _largeTitleHeight = 52;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final collapsed = _scrollController.offset > _largeTitleHeight * 0.6;
    if (collapsed != _collapsed) {
      setState(() => _collapsed = collapsed);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    const navBarHeight = 44.0; // Hauteur exacte d'une barre iOS.

    Widget content = CustomScrollView(
      controller: _scrollController,
      // Le rebond élastique en fin de liste est le comportement de
      // défilement iOS — sur Android, la liste s'arrête net avec un halo.
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        // Espace réservé sous la barre de navigation.
        SliverToBoxAdapter(
          child: SizedBox(height: topPadding + navBarHeight),
        ),
        // Tirer pour rafraîchir, avec l'indicateur natif iOS : un cercle
        // de progression fin qui s'étire à mesure qu'on tire, sans flèche
        // ni roue tournante ostentatoire.
        if (widget.onRefresh != null)
          CupertinoSliverRefreshControl(onRefresh: widget.onRefresh),
        // Le grand titre : un sliver ordinaire qui défile avec le contenu
        // et sort simplement de l'écran par le haut. C'est exactement ce
        // que fait iOS — le titre ne « rétrécit » pas réellement, il
        // s'efface pendant que son homologue apparaît dans la barre.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              DesignTokens.screenMargin,
              0,
              DesignTokens.screenMargin,
              DesignTokens.space2,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.title,
                  style: OuroTypography.largeTitle.copyWith(
                    color: OuroColors.label,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    widget.subtitle!,
                    style: OuroTypography.subheadline.copyWith(
                      color: OuroColors.secondaryLabel,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        ...widget.slivers,
        // Marge de sécurité en bas, au-dessus de la zone de geste système.
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.paddingOf(context).bottom + DesignTokens.space8,
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: widget.backgroundColor ?? OuroColors.systemBackground,
      // Le contenu passe SOUS la barre translucide, au lieu de commencer
      // en dessous — c'est ce qui permet au flou d'avoir quelque chose à
      // flouter.
      extendBodyBehindAppBar: true,
      floatingActionButton: widget.floatingActionButton,
      body: Stack(
        children: [
          content,
          // La barre de navigation flottante.
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _NavigationBar(
              title: widget.title,
              collapsed: _collapsed,
              leading: widget.leading,
              actions: widget.actions,
              topPadding: topPadding,
              height: navBarHeight,
            ),
          ),
          // Notification mesh flottante — si fournie.
          if (widget.floatingNotification != null)
            Positioned(
              top: topPadding + navBarHeight + 8,
              left: 16,
              right: 16,
              child: widget.floatingNotification!,
            ),
        ],
      ),
    );
  }
}

/// La barre du haut : transparente tant que le grand titre est visible,
/// puis translucide floutée avec le petit titre une fois replié.
class _NavigationBar extends StatelessWidget {
  const _NavigationBar({
    required this.title,
    required this.collapsed,
    required this.topPadding,
    required this.height,
    this.leading,
    this.actions,
  });

  final String title;
  final bool collapsed;
  final double topPadding;
  final double height;
  final Widget? leading;
  final List<Widget>? actions;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: DesignTokens.durationFast,
      child: collapsed
          ? OuroBlurSurface(
              key: const ValueKey('collapsed'),
              material: OuroMaterial.thin,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _bar(context),
                  // Le trait qui n'apparaît qu'une fois replié : il
                  // matérialise la limite entre la barre et le contenu qui
                  // glisse dessous.
                  Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: OuroColors.separator,
                  ),
                ],
              ),
            )
          : SizedBox(
              key: const ValueKey('expanded'),
              child: _bar(context),
            ),
    );
  }

  Widget _bar(BuildContext context) {
    return SizedBox(
      // ⚠️ `width: double.infinity` est indispensable.
      //
      // Sans lui, la pile se dimensionne sur son plus grand enfant NON
      // positionné — ici le titre — et devient donc aussi étroite que ce
      // texte. Les boutons « collés à gauche » et « collés à droite » se
      // retrouvent alors collés aux bords de ce petit bloc central,
      // c'est-à-dire groupés au milieu de l'écran au lieu d'être aux
      // deux extrémités.
      width: double.infinity,
      height: topPadding + height,
      child: Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Le petit titre centré, en fondu — il n'existe que lorsque
            // le grand titre a disparu, pour ne jamais être affiché deux
            // fois simultanément.
            AnimatedOpacity(
              opacity: collapsed ? 1 : 0,
              duration: DesignTokens.durationFast,
              curve: DesignTokens.curveStandard,
              child: Text(
                title,
                style: OuroTypography.navTitle.copyWith(
                  color: OuroColors.label,
                ),
              ),
            ),
            if (leading != null)
              Positioned(
                left: DesignTokens.space2,
                child: leading!,
              ),
            if (actions != null && actions!.isNotEmpty)
              Positioned(
                right: DesignTokens.space2,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: actions!,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
//  BOUTON DE BARRE
// ─────────────────────────────────────────────────────────────

/// Bouton d'action dans une barre de navigation iOS : une icône bleue
/// sans fond, dans une zone tactile de 44×44 conforme aux règles
/// d'accessibilité d'Apple.
/// LE BOUTON RETOUR — le même partout, et qui revient vraiment en
/// arrière.
///
/// ── Deux défauts qu'il corrige ────────────────────────────────────────
///
/// 1. **Deux dessins différents cohabitaient.** La moitié des écrans
///    affichait le chevron d'iOS (`arrow_back_ios_new`), l'autre moitié
///    la flèche d'Android (`arrow_back`). Sur deux écrans voisins, le
///    bouton changeait de forme — rien ne trahit plus vite un assemblage
///    de morceaux.
///
/// 2. **Ils ne revenaient pas en arrière : ils allaient ailleurs.** Ces
///    boutons appelaient `context.go('/quelque-part')`, qui EMPILE une
///    nouvelle page au lieu de retirer celle du dessus. Tant que toutes
///    les transitions se ressemblaient, cela ne se voyait pas ; depuis
///    qu'une page entre en glissant depuis la droite, « retour »
///    rejouait l'animation d'entrée — on avançait en croyant reculer.
///    Et le geste de retour au bord de l'écran, lui, dépilait
///    correctement : le bouton et le geste ne faisaient plus la même
///    chose.
///
/// [fallback] sert au cas où il n'y a rien à dépiler — on arrive parfois
/// directement sur un écran depuis une notification, sans historique
/// derrière soi.
class OuroBackButton extends StatelessWidget {
  const OuroBackButton({super.key, this.fallback = '/chats', this.color});

  final String fallback;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return OuroBarButton(
      icon: Icons.arrow_back_ios_new_rounded,
      tooltip: 'Retour',
      color: color,
      onPressed: () {
        OuroHaptics.light();
        final navigator = Navigator.of(context);
        if (navigator.canPop()) {
          navigator.pop();
        } else {
          GoRouter.of(context).go(fallback);
        }
      },
    );
  }
}

class OuroBarButton extends StatelessWidget {
  const OuroBarButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.color,
  });

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final button = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onPressed,
      child: SizedBox(
        width: DesignTokens.minTouchTarget,
        height: DesignTokens.minTouchTarget,
        child: Icon(
          icon,
          size: DesignTokens.iconLg,
          color: color ?? OuroColors.accent,
        ),
      ),
    );
    if (tooltip == null) return button;
    return Tooltip(message: tooltip!, child: button);
  }
}
