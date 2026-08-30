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
  bool _tabBarMinimized = false;
  double _scrollRun = 0;

  static const double _minimizeThreshold = 24;
  static const double _alwaysVisibleZone = 40;

  bool _onScroll(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification.metrics.axis != Axis.vertical) return false;

    if (notification is ScrollUpdateNotification) {
      final delta = notification.scrollDelta ?? 0;
      if (delta == 0) return false;

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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: OuroTabBar(
              items: _items,
              currentIndex: _currentIndex,
              minimized: _tabBarMinimized,
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
