/// 主导航框架
/// 底部导航栏和页面切换
library;

import 'package:flutter/material.dart';

import '../services/services.dart';
import 'home_screen.dart';
import 'schedule_screen.dart';
import 'study_screen.dart';
import 'grades_screen.dart';
import 'profile_screen.dart';

/// 主导航框架
class MainShell extends StatefulWidget {
  final DataManager dataManager;
  final VoidCallback onLogout;
  final VoidCallback? onSwitchAccount;

  const MainShell({
    super.key,
    required this.dataManager,
    required this.onLogout,
    this.onSwitchAccount,
  });

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _currentIndex = 0;

  // 导航项
  static const _navigationItems = [
    NavigationDestination(
      icon: Icon(Icons.home_outlined),
      selectedIcon: Icon(Icons.home),
      label: '首页',
    ),
    NavigationDestination(
      icon: Icon(Icons.calendar_month_outlined),
      selectedIcon: Icon(Icons.calendar_month),
      label: '课程表',
    ),
    NavigationDestination(
      icon: Icon(Icons.menu_book_outlined),
      selectedIcon: Icon(Icons.menu_book),
      label: '学习',
    ),
    NavigationDestination(
      icon: Icon(Icons.school_outlined),
      selectedIcon: Icon(Icons.school),
      label: '成绩',
    ),
    NavigationDestination(
      icon: Icon(Icons.person_outline),
      selectedIcon: Icon(Icons.person),
      label: '我的',
    ),
  ];

  @override
  void initState() {
    super.initState();
    // 初始化数据加载
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.dataManager.initialize();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: widget.dataManager,
      builder: (context, child) {
        return Scaffold(
          body: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.02, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: _buildPage(),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            destinations: _navigationItems,
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            shadowColor: Colors.transparent,
          ),
        );
      },
    );
  }

  Widget _buildPage() {
    switch (_currentIndex) {
      case 0:
        return HomeScreen(
          key: const ValueKey('home'),
          dataManager: widget.dataManager,
        );
      case 1:
        return ScheduleScreen(
          key: const ValueKey('schedule'),
          dataManager: widget.dataManager,
        );
      case 2:
        return const StudyScreen(key: ValueKey('study'));
      case 3:
        return GradesScreen(
          key: const ValueKey('grades'),
          dataManager: widget.dataManager,
        );
      case 4:
        return ProfileScreen(
          key: const ValueKey('profile'),
          dataManager: widget.dataManager,
          onLogout: widget.onLogout,
          onSwitchAccount: widget.onSwitchAccount,
        );
      default:
        return HomeScreen(
          key: const ValueKey('home'),
          dataManager: widget.dataManager,
        );
    }
  }
}
