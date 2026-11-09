import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../providers/tutorial_provider.dart';

/// 首次启动的三页引导：欢迎 -> 权限 -> 是否学习教程。
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow> {
  final PageController _controller = PageController();
  int _page = 0;

  bool _requesting = false;
  final Map<String, bool> _granted = {
    'mic': false,
    'camera': false,
    'photos': false,
    'bluetooth': false,
  };

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    setState(() => _page = page);
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _requestPermissions() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    try {
      final isAndroid = !kIsWeb && Platform.isAndroid;
      final isIos = !kIsWeb && Platform.isIOS;

      if (!isAndroid && !isIos) {
        // 桌面端无需运行时权限。
        setState(() {
          _granted.updateAll((_, _) => true);
          _requesting = false;
        });
        return;
      }

      final mic = await Permission.microphone.request();
      final camera = await Permission.camera.request();
      final photos = await Permission.photos.request();

      var bluetooth = false;
      if (isAndroid) {
        final scan = await Permission.bluetoothScan.request();
        final connect = await Permission.bluetoothConnect.request();
        bluetooth = scan.isGranted && connect.isGranted;
      } else {
        // iOS 的蓝牙权限由系统在使用时授权，这里视为可用。
        bluetooth = true;
      }

      if (mounted) {
        setState(() {
          _granted['mic'] = mic.isGranted;
          _granted['camera'] = camera.isGranted;
          _granted['photos'] = photos.isGranted;
          _granted['bluetooth'] = bluetooth;
          _requesting = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _finish({required bool learnTutorial}) async {
    if (learnTutorial) {
      await ref
          .read(tutorialProvider.notifier)
          .startTutorial(TutorialType.basicFlow, step: 1);
    } else {
      await ref.read(tutorialProvider.notifier).skipTutorial();
    }
    await markOnboardingCompleted(ref);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _controller,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (i) => setState(() => _page = i),
                children: [
                  _WelcomePage(onNext: () => _goTo(1)),
                  _PermissionPage(
                    granted: _granted,
                    requesting: _requesting,
                    onRequest: _requestPermissions,
                    onNext: () => _goTo(2),
                  ),
                  _TutorialPromptPage(
                    onLearn: () => _finish(learnTutorial: true),
                    onSkip: () => _finish(learnTutorial: false),
                  ),
                ],
              ),
            ),
            // 底部进度指示
            Padding(
              padding: const EdgeInsets.only(bottom: 18, top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(3, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 20 : 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: active
                          ? colorScheme.primary
                          : colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WelcomePage extends StatelessWidget {
  final VoidCallback onNext;

  const _WelcomePage({required this.onNext});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 104,
            height: 104,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: colorScheme.primary.withValues(alpha: 0.22),
                  blurRadius: 24,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(28),
              child: Image.asset(
                'assets/icons/app_icon.png',
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Container(
                  color: colorScheme.primary,
                  child: const Icon(Icons.auto_awesome, color: Colors.white, size: 44),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            '欢迎使用小培同学',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: colorScheme.onSurface,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '把零散的文字、语音和图片\n整理成一份结构清晰的结果',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14.5,
              height: 1.55,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 44),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: onNext,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '开始',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PermissionPage extends StatelessWidget {
  final Map<String, bool> granted;
  final bool requesting;
  final VoidCallback onRequest;
  final VoidCallback onNext;

  const _PermissionPage({
    required this.granted,
    required this.requesting,
    required this.onRequest,
    required this.onNext,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final items = <(String, String, IconData)>[
      ('mic', '麦克风', Icons.mic_none_rounded),
      ('camera', '相机', Icons.photo_camera_outlined),
      ('photos', '相册', Icons.photo_library_outlined),
      ('bluetooth', '蓝牙', Icons.bluetooth),
    ];

    final allGranted = granted.values.every((v) => v);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '开启所需权限',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: colorScheme.onSurface,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '用于录音转文字、拍照识别与连接键盘设备。',
            style: TextStyle(
              fontSize: 13.5,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),
          ...items.map((item) {
            final ok = granted[item.$1] ?? false;
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: ok
                      ? Colors.green.withValues(alpha: 0.5)
                      : colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    item.$3,
                    size: 22,
                    color: ok ? Colors.green.shade600 : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.$2,
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600),
                    ),
                  ),
                  Icon(
                    ok ? Icons.check_circle_rounded : Icons.circle_outlined,
                    size: 20,
                    color: ok ? Colors.green.shade600 : colorScheme.outlineVariant,
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: allGranted
                ? OutlinedButton.icon(
                    onPressed: () {},
                    icon: Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
                    label: Text(
                      '已授权',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      backgroundColor: colorScheme.surface,
                      side: BorderSide(
                        color: colorScheme.primary.withValues(alpha: 0.35),
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  )
                : FilledButton.icon(
                    onPressed: requesting ? null : onRequest,
                    icon: requesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.lock_open_rounded, size: 18),
                    label: Text(
                      requesting ? '正在申请…' : '一键授权',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: onNext,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '下一步',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 18),
                ],
              ),
            ),
          ),
          if (!allGranted)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                '也可以稍后在「设置」中再授权',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

class _TutorialPromptPage extends StatelessWidget {
  final VoidCallback onLearn;
  final VoidCallback onSkip;

  const _TutorialPromptPage({
    required this.onLearn,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.school_outlined, size: 46, color: colorScheme.primary),
          ),
          const SizedBox(height: 26),
          Text(
            '要不要花一分钟学一下？',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: colorScheme.onSurface,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '跟着提示走一遍新建会话、录入材料\n与生成结果的基础流程。',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              height: 1.55,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: FilledButton(
              onPressed: onLearn,
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '开始学习',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onSkip,
            child: Text(
              '先自己探索',
              style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
