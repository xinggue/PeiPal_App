import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/tutorial_provider.dart';
import '../../widgets/tutorial/tutorial_spotlight_overlay.dart';

class MainNavigationShell extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;
  final List<Widget> children;

  const MainNavigationShell({
    super.key,
    required this.navigationShell,
    required this.children,
  });

  @override
  ConsumerState<MainNavigationShell> createState() => _MainNavigationShellState();
}

class _MainNavigationShellState extends ConsumerState<MainNavigationShell> {
  static const int _settingsTabIndex = 3;

  late final PageController _pageController;
  final GlobalKey _settingsTabKey = GlobalKey();
  bool _isProgrammaticJump = false;

  @override
  void initState() {
    super.initState();
    _pageController =
        PageController(initialPage: widget.navigationShell.currentIndex);
  }

  @override
  void didUpdateWidget(covariant MainNavigationShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.navigationShell.currentIndex !=
            oldWidget.navigationShell.currentIndex &&
        !_isProgrammaticJump) {
      _moveToPage(widget.navigationShell.currentIndex);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _moveToPage(int index) async {
    if (!_pageController.hasClients || _pageController.page == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _moveToPage(index);
      });
      return;
    }
    final currentPage = _pageController.page!.round();
    if (currentPage == index) return;

    _isProgrammaticJump = true;
    try {
      if ((currentPage - index).abs() > 1) {
        _pageController.jumpToPage(index);
      } else {
        await _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      _isProgrammaticJump = false;
    }
  }

  int? get _visiblePage {
    if (!_pageController.hasClients) return null;
    return _pageController.page?.round();
  }

  void _onTabTapped(int index) {
    if (_isGuidingToSettings) {
      if (index == _settingsTabIndex) _enterSettingsGuide();
      return;
    }
    final alreadyHere =
        index == widget.navigationShell.currentIndex && index == _visiblePage;
    if (alreadyHere) {
      widget.navigationShell.goBranch(index, initialLocation: true);
    } else {
      widget.navigationShell.goBranch(index);
      _moveToPage(index);
    }
  }

  bool get _isGuidingToSettings {
    final tutorial = ref.read(tutorialProvider);
    return tutorial.isActive &&
        tutorial.activeTutorial == TutorialType.aiConfig &&
        tutorial.currentStep == 1;
  }

  void _enterSettingsGuide() {
    widget.navigationShell.goBranch(_settingsTabIndex);
    _moveToPage(_settingsTabIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_visiblePage != _settingsTabIndex) {
        _moveToPage(_settingsTabIndex);
      }
      final tutorial = ref.read(tutorialProvider);
      if (tutorial.isActive &&
          tutorial.activeTutorial == TutorialType.aiConfig &&
          tutorial.currentStep == 1 &&
          _visiblePage == _settingsTabIndex) {
        ref.read(tutorialProvider.notifier).nextStep();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tutorial = ref.watch(tutorialProvider);
    final guideSettings = tutorial.isActive &&
        tutorial.activeTutorial == TutorialType.aiConfig &&
        tutorial.currentStep == 1;

    final scaffold = Scaffold(
      body: PageView(
        controller: _pageController,
        physics: const ClampingScrollPhysics(),
        onPageChanged: (index) {
          if (_isProgrammaticJump) return;
          if (index != widget.navigationShell.currentIndex) {
            widget.navigationShell.goBranch(index);
          }
          if (index == _settingsTabIndex && _isGuidingToSettings) {
            ref.read(tutorialProvider.notifier).nextStep();
          }
        },
        children: widget.children,
      ),
      bottomNavigationBar: _WeChatBottomBar(
        currentIndex: widget.navigationShell.currentIndex,
        onTap: _onTabTapped,
        settingsTabKey: _settingsTabKey,
      ),
    );

    return Stack(
      children: [
        scaffold,
        if (guideSettings)
          TutorialSpotlightOverlay(
            targetKey: _settingsTabKey,
            stepTag: '配置指引 · 1/2',
            title: '打开设置',
            description: '点底部「设置」。',
            nextButtonLabel: '去设置',
            borderRadius: 12,
            onNext: _enterSettingsGuide,
            onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
            onTargetTap: _enterSettingsGuide,
          ),
      ],
    );
  }
}

class _WeChatBottomBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;
  final GlobalKey settingsTabKey;

  const _WeChatBottomBar({
    required this.currentIndex,
    required this.onTap,
    required this.settingsTabKey,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final activeColor = colorScheme.primary;
    final inactiveColor = Colors.grey.shade600;

    final tabs = const [
      (
        label: '会话列表',
        icon: Icons.chat_bubble_outline_rounded,
        activeIcon: Icons.chat_bubble_rounded,
      ),
      (
        label: '蓝牙与键盘',
        icon: Icons.bluetooth,
        activeIcon: Icons.bluetooth_connected,
      ),
      (
        label: '文书与模板',
        icon: Icons.folder_outlined,
        activeIcon: Icons.folder_rounded,
      ),
      (
        label: '设置',
        icon: Icons.settings_outlined,
        activeIcon: Icons.settings,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: SizedBox(
            height: 56,
            child: Row(
              children: List.generate(tabs.length, (index) {
                final isSelected = index == currentIndex;
                final tab = tabs[index];
                final color = isSelected ? activeColor : inactiveColor;

                return Expanded(
                  child: InkWell(
                    key: index == 3 ? settingsTabKey : null,
                    onTap: () => onTap(index),
                    splashColor: Colors.transparent,
                    highlightColor: Colors.transparent,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          isSelected ? tab.activeIcon : tab.icon,
                          color: color,
                          size: 24,
                        ),
                        const SizedBox(height: 3),
                        Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            color: color,
                            letterSpacing: -0.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
