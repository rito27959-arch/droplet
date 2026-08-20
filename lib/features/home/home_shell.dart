// ============================================================================
// C'EST QUOI CE FICHIER ?
// ----------------------------------------------------------------------------
// La coquille principale de l'app : les quatre onglets du bas et l'écran
// affiché pour chacun.
//
// DEUX POINTS IMPORTANTS DANS LA FAÇON DONT C'EST ASSEMBLÉ :
//
// 1. LE CONTENU PASSE DERRIÈRE LA BARRE. Sur iOS, la barre d'onglets est
//    translucide et le contenu défile DESSOUS en étant flouté. Ça n'est
//    possible que si la barre est posée PAR-DESSUS le contenu (dans un
//    `Stack`), et non à côté de lui — ce que ferait le `bottomNavigationBar`
//    ordinaire de Flutter, qui réserve la place et empêche tout défilement
//    derrière.
//
// 2. LES ÉCRANS S'ARRÊTENT AU-DESSUS DE LA BARRE SANS LE SAVOIR. Puisque
//    la barre flotte au-dessus, le dernier élément d'une liste finirait
//    caché dessous. Plutôt que d'ajouter une marge à la main dans chacun
//    des quatre écrans (et de l'oublier dans le cinquième), on AGRANDIT la
//    zone de sécurité annoncée aux écrans, de la hauteur de la barre. Ils
//    la respectent déjà tous — ils s'arrêtent donc automatiquement au bon
//    endroit, sans une seule ligne à modifier chez eux.
//
// L'état de chaque onglet est préservé quand on navigue (`IndexedStack`) :
// revenir sur un onglet le retrouve exactement là où on l'avait laissé,
// position de défilement comprise. C'est le comportement attendu sur iOS.
// ============================================================================

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../design_system/ouro_colors.dart';
import '../../design_system/ouro_tab_bar.dart';
import '../chats/chats_screen.dart';
import '../news/news_screen.dart';
import '../calls/calls_screen.dart';
import '../peers/peers_screen.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _currentIndex = 0;

  /// La barre d'onglets est-elle escamotée ?
  bool _tabBarMinimized = false;

  /// Distance parcourue depuis le dernier changement de sens.
  ///
  /// ⚠️ SANS CE CUMUL, LA BARRE CLIGNOTERAIT. Un doigt sur un écran ne
  /// défile jamais parfaitement droit : chaque geste contient quelques
  /// pixels dans l'autre sens. Réagir au premier signal ferait
  /// apparaître et disparaître la barre plusieurs fois par seconde. On
  /// attend donc qu'un mouvement soit FRANC — 24 points dans le même
  /// sens — avant de la faire bouger.
  double _scrollRun = 0;

  static const double _minimizeThreshold = 24;

  /// En haut de liste, la barre est toujours visible : c'est là qu'on
  /// arrive, et c'est là qu'on cherche à changer d'onglet.
  static const double _alwaysVisibleZone = 40;

  bool _onScroll(ScrollNotification notification) {
    // Seuls les défilements VERTICAUX de la liste principale comptent :
    // une pellicule horizontale ou une feuille modale posée par-dessus
    // ne doivent pas escamoter le châssis de l'application.
    if (notification.depth != 0) return false;
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;

      // Changement de sens : on repart de zéro.
      if (delta.sign != _scrollRun.sign) _scrollRun = 0;
      _scrollRun += delta;

      final atTop = notification.metrics.pixels < _alwaysVisibleZone;
      final minimize = !atTop && _scrollRun > _minimizeThreshold;
      final restore = _scrollRun < -_minimizeThreshold || atTop;

      if (minimize && !_tabBarMinimized) {
        setState(() => _tabBarMinimized = true);
      } else if (restore && _tabBarMinimized) {
        setState(() => _tabBarMinimized = false);
      }
    }
    return false;
  }

  static const _pages = [
    ChatsScreen(),
    NewsScreen(),
    CallsScreen(),
    PeersScreen(),
  ];

  /// Icônes en deux versions, contour et plein — la convention iOS pour
  /// distinguer l'onglet actif.
  static const _items = [
    OuroTabItem(
      icon: Icons.chat_bubble_outline_rounded,
      activeIcon: Icons.chat_bubble_rounded,
      label: 'Discussions',
    ),
    OuroTabItem(
      icon: Icons.podcasts_outlined,
      activeIcon: Icons.podcasts_rounded,
      label: 'Actus',
    ),
    OuroTabItem(
      icon: Icons.phone_outlined,
      activeIcon: Icons.phone_rounded,
      label: 'Appels',
    ),
    OuroTabItem(
      icon: Icons.people_outline_rounded,
      activeIcon: Icons.people_rounded,
      label: 'Pairs',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: OuroColors.systemBackground,
      body: Stack(
        children: [
          // Point n°2 de l'en-tête : on annonce aux écrans une zone de
          // sécurité plus haute qu'elle ne l'est réellement, de la
          // hauteur de la barre. Chacun laisse alors la place nécessaire
          // tout seul.
          MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(
                bottom: OuroTabBar.reservedHeight(mq.padding.bottom),
              ),
            ),
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: IndexedStack(
                index: _currentIndex,
                children: _pages,
              ),
            ),
          ),
          // Point n°1 : la barre flotte au-dessus du contenu.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: OuroTabBar(
              items: _items,
              currentIndex: _currentIndex,
              minimized: _tabBarMinimized,
              // Changer d'onglet remet la barre en place : on ne laisse
              // jamais l'utilisateur arriver sur un écran dont le
              // châssis est caché.
              onTap: (i) => setState(() {
                _currentIndex = i;
                _tabBarMinimized = false;
                _scrollRun = 0;
              }),
            ),
          ),
        ],
      ),
    );
  }
}
