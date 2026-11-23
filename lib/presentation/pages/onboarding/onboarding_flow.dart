import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../data/services/api/quick_ai_setup_service.dart';
import '../../../domain/models/asr_provider.dart';
import '../../../domain/models/llm_provider.dart';
import '../../../domain/models/ocr_provider.dart';
import '../../../providers/providers.dart';
import '../../../providers/storefront_compliance_provider.dart';
import '../../../providers/tutorial_provider.dart';
import '../../widgets/common/app_toast.dart';
import '../settings/disclaimer_page.dart';

/// 首次启动的四页引导：欢迎 -> 权限 -> 接入 AI -> 是否学习教程。
class OnboardingFlow extends ConsumerStatefulWidget {
  const OnboardingFlow({super.key});

  @override
  ConsumerState<OnboardingFlow> createState() => _OnboardingFlowState();
}

class _OnboardingFlowState extends ConsumerState<OnboardingFlow>
    with WidgetsBindingObserver {
  final PageController _controller = PageController();
  int _page = 0;

  bool _acceptedDisclaimer = false;
  bool _telemetryEnabled = true;

  bool _requesting = false;
  bool _pendingSettingsRefresh = false;
  final Map<String, bool> _granted = {
    'mic': false,
    'camera': false,
    'photos': false,
    'bluetooth': false,
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _pendingSettingsRefresh) {
      _pendingSettingsRefresh = false;
      _refreshPermissionStatuses();
    }
  }

  void _goTo(int page) {
    FocusScope.of(context).unfocus();
    setState(() => _page = page);
    _controller.animateToPage(
      page,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _refreshPermissionStatuses() async {
    try {
      final isAndroid = !kIsWeb && Platform.isAndroid;
      final isIos = !kIsWeb && Platform.isIOS;
      if (!isAndroid && !isIos) return;

      final mic = await Permission.microphone.status;
      final camera = await Permission.camera.status;
      final photos = await Permission.photos.status;
      var bluetooth = true;
      if (isAndroid) {
        final scan = await Permission.bluetoothScan.status;
        final connect = await Permission.bluetoothConnect.status;
        bluetooth = scan.isGranted && connect.isGranted;
      }

      if (mounted) {
        setState(() {
          _granted['mic'] = mic.isGranted;
          _granted['camera'] = camera.isGranted;
          _granted['photos'] = photos.isGranted || photos.isLimited;
          _granted['bluetooth'] = bluetooth;
        });
      }
    } catch (_) {}
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
          _granted['photos'] = photos.isGranted || photos.isLimited;
          _granted['bluetooth'] = bluetooth;
          _requesting = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _openSystemPermissionSettings() async {
    _pendingSettingsRefresh = true;
    await openAppSettings();
  }

  Future<void> _handleWelcomeStart() async {
    if (!_acceptedDisclaimer) return;
    final repo = ref.read(settingsRepositoryProvider);
    await repo.set('disclaimer_accepted_version', kDisclaimerVersion);
    await repo.set(
      'disclaimer_accepted_at',
      DateTime.now().toIso8601String(),
    );
    await ref
        .read(telemetryEnabledProvider.notifier)
        .setEnabled(_telemetryEnabled);
    if (mounted) {
      _goTo(1);
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
    final isAiRestricted = ref.watch(isChinaAiRestrictedProvider);

    final pages = <Widget>[
      _WelcomePage(
        acceptedDisclaimer: _acceptedDisclaimer,
        telemetryEnabled: _telemetryEnabled,
        onDisclaimerChanged: (v) => setState(() => _acceptedDisclaimer = v),
        onTelemetryChanged: (v) => setState(() => _telemetryEnabled = v),
        onNext: _handleWelcomeStart,
      ),
      _PermissionPage(
        granted: _granted,
        requesting: _requesting,
        isAiRestricted: isAiRestricted,
        onRequest: _requestPermissions,
        onOpenSystemSettings: _openSystemPermissionSettings,
        onNext: () => _goTo(2),
      ),
      if (!isAiRestricted) _AiPromptPage(onNext: () => _goTo(3)),
      _TutorialPromptPage(
        onLearn: () => _finish(learnTutorial: true),
        onSkip: () => _finish(learnTutorial: false),
      ),
    ];
    final currentDot = _page.clamp(0, pages.length - 1);

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
                children: pages,
              ),
            ),
            // 底部进度指示
            Padding(
              padding: const EdgeInsets.only(bottom: 18, top: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(pages.length, (i) {
                  final active = i == currentDot;
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

class _WelcomePage extends StatefulWidget {
  final bool acceptedDisclaimer;
  final bool telemetryEnabled;
  final ValueChanged<bool> onDisclaimerChanged;
  final ValueChanged<bool> onTelemetryChanged;
  final VoidCallback onNext;

  const _WelcomePage({
    required this.acceptedDisclaimer,
    required this.telemetryEnabled,
    required this.onDisclaimerChanged,
    required this.onTelemetryChanged,
    required this.onNext,
  });

  @override
  State<_WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<_WelcomePage> {
  late final TapGestureRecognizer _disclaimerTapRecognizer =
      TapGestureRecognizer()..onTap = _showDisclaimerDialog;

  @override
  void dispose() {
    _disclaimerTapRecognizer.dispose();
    super.dispose();
  }

  Future<void> _showDisclaimerDialog() async {
    final agreed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('免责声明与隐私说明'),
        content: const SizedBox(
          width: 440,
          child: SingleChildScrollView(
            child: DisclaimerPrivacyContent(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('关闭'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('阅读并同意'),
          ),
        ],
      ),
    );
    if (agreed == true && mounted) {
      widget.onDisclaimerChanged(true);
    }
  }

  void _showTelemetryFieldsDialog() {
    showTelemetryFieldsDialog(context, mentionCloseSetting: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.22),
                      blurRadius: 24,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => Container(
                      color: colorScheme.primary,
                      child: const Icon(Icons.auto_awesome,
                          color: Colors.white, size: 44),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                '欢迎使用小培同学',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '把零散的文字、语音和图片\n整理成一份结构清晰的结果',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.55,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              // 两行独立勾选：必选免责声明 + 可选匿名统计
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: widget.acceptedDisclaimer,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => widget.onDisclaimerChanged(v ?? false),
                  ),
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurface,
                          height: 1.4,
                        ),
                        children: [
                          const TextSpan(text: '我已阅读并同意'),
                          TextSpan(
                            text: '《免责声明与隐私说明》',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                            recognizer: _disclaimerTapRecognizer,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Checkbox(
                    value: widget.telemetryEnabled,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => widget.onTelemetryChanged(v ?? true),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onTap: () =>
                          widget.onTelemetryChanged(!widget.telemetryEnabled),
                      child: Text(
                        '发送匿名使用统计（仅含版本号与系统类型）',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colorScheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.help_outline_rounded,
                      size: 17,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    tooltip: '查看上报字段',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    onPressed: _showTelemetryFieldsDialog,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: FilledButton(
                  onPressed: widget.acceptedDisclaimer ? widget.onNext : null,
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
        ),
      ),
    );
  }
}

class _PermissionPage extends StatelessWidget {
  final Map<String, bool> granted;
  final bool requesting;
  final bool isAiRestricted;
  final VoidCallback onRequest;
  final VoidCallback onOpenSystemSettings;
  final VoidCallback onNext;

  const _PermissionPage({
    required this.granted,
    required this.requesting,
    this.isAiRestricted = false,
    required this.onRequest,
    required this.onOpenSystemSettings,
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

    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '开启所需权限',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isAiRestricted
                    ? '用于语音转文字、拍照离线识图与连接键盘设备。'
                    : '用于录音转文字、拍照识别与连接键盘设备。',
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
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
                        color: ok
                            ? Colors.green.shade600
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          item.$2,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600),
                        ),
                      ),
                      Icon(
                        ok ? Icons.check_circle_rounded : Icons.circle_outlined,
                        size: 20,
                        color: ok
                            ? Colors.green.shade600
                            : colorScheme.outlineVariant,
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
                        icon: Icon(Icons.check_rounded,
                            size: 18, color: colorScheme.primary),
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
                          style: const TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold),
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
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded, size: 18),
                    ],
                  ),
                ),
              ),
              if (!allGranted)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '未授权功能暂不可用，使用时会再提醒',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: onOpenSystemSettings,
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          '去系统设置',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AiPromptPage extends StatelessWidget {
  final VoidCallback onNext;

  const _AiPromptPage({required this.onNext});

  Future<void> _openConfig(BuildContext context) async {
    final configured = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const _OnboardingAiConfigPage(),
      ),
    );
    if (configured == true) {
      onNext();
    }
  }

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
            child: Icon(Icons.vpn_key_outlined,
                size: 46, color: colorScheme.primary),
          ),
          const SizedBox(height: 26),
          Text(
            '已经有 API Key 了吗？',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '现在配好就可以直接启用 AI 能力；\n暂时没有也可以稍后配置，随时可在「设置」里补配。',
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
              onPressed: () => _openConfig(context),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '有，去配置',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 10),
          TextButton(
            onPressed: onNext,
            child: Text(
              '稍后配置',
              style:
                  TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingAiConfigPage extends ConsumerStatefulWidget {
  const _OnboardingAiConfigPage();

  @override
  ConsumerState<_OnboardingAiConfigPage> createState() =>
      _OnboardingAiConfigPageState();
}

class _OnboardingAiConfigPageState
    extends ConsumerState<_OnboardingAiConfigPage> {
  String? _expandedSection;

  final Map<ApiKeyGuideProvider, TextEditingController> _bundleKeyCtrls = {
    ApiKeyGuideProvider.deepseek: TextEditingController(),
    ApiKeyGuideProvider.zhipu: TextEditingController(),
  };
  final Map<ApiKeyGuideProvider, bool> _bundleObscure = {
    ApiKeyGuideProvider.deepseek: true,
    ApiKeyGuideProvider.zhipu: true,
  };
  final Map<ApiKeyGuideProvider, bool> _bundleVerifying = {
    ApiKeyGuideProvider.deepseek: false,
    ApiKeyGuideProvider.zhipu: false,
  };
  final Map<ApiKeyGuideProvider, String?> _bundleErrors = {};

  // 其他供应商（同款可展开卡片，仅配 LLM）
  late final List<LlmProviderConfig> _otherProviders;
  late LlmProviderConfig _selectedOther;
  final TextEditingController _otherUrlCtrl = TextEditingController();
  final TextEditingController _otherModelCtrl = TextEditingController();
  final TextEditingController _otherKeyCtrl = TextEditingController();
  bool _obscureOtherKey = true;
  bool _verifyingOther = false;
  String? _otherError;

  @override
  void initState() {
    super.initState();
    _otherProviders = LlmProviderPresets.builtIn
        .where((p) => p.id != 'deepseek' && p.id != 'zhipu')
        .toList();
    _selectedOther = _otherProviders.first;
    _otherUrlCtrl.text = _selectedOther.defaultBaseUrl;
    _otherModelCtrl.text = _selectedOther.selectedModel;
  }

  @override
  void dispose() {
    for (final ctrl in _bundleKeyCtrls.values) {
      ctrl.dispose();
    }
    _otherUrlCtrl.dispose();
    _otherModelCtrl.dispose();
    _otherKeyCtrl.dispose();
    super.dispose();
  }

  Future<void> _pasteInto(
    TextEditingController ctrl,
    VoidCallback onChanged,
  ) async {
    final clip = await Clipboard.getData('text/plain');
    final text = clip?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) showAppToast(context, '剪贴板里没有内容');
      return;
    }
    setState(() {
      ctrl.text = text;
      onChanged();
    });
  }

  Future<void> _verifyAndSaveBundle(ApiKeyGuideProvider provider) async {
    final ctrl = _bundleKeyCtrls[provider]!;
    final key = ctrl.text.trim();
    if (key.isEmpty) {
      setState(() => _bundleErrors[provider] = '请先粘贴或输入${provider.label} API Key');
      return;
    }

    setState(() {
      _bundleVerifying[provider] = true;
      _bundleErrors[provider] = null;
    });

    final error = await ref
        .read(quickAiSetupServiceProvider)
        .verifyAndConfigureAllInOne(
          provider: provider,
          apiKey: key,
          fromGuide: false,
          ensureSampleAndResetTutorial: false,
        );

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _bundleVerifying[provider] = false;
        _bundleErrors[provider] = error;
      });
      return;
    }

    showAppToast(context, 'AI 已配好');
    Navigator.of(context).pop(true);
  }

  Future<void> _verifyAndSaveOtherLlm() async {
    setState(() {
      _verifyingOther = true;
      _otherError = null;
    });

    final error = await ref
        .read(quickAiSetupServiceProvider)
        .verifyAndConfigureLlmOnly(
          baseProvider: _selectedOther,
          baseUrl: _otherUrlCtrl.text,
          apiKey: _otherKeyCtrl.text,
          model: _otherModelCtrl.text,
        );

    if (!mounted) return;
    if (error != null) {
      setState(() {
        _verifyingOther = false;
        _otherError = error;
      });
      return;
    }

    showAppToast(context, '大语言模型已启用');
    Navigator.of(context).pop(true);
  }

  void _selectOtherProvider(LlmProviderConfig next) {
    setState(() {
      _selectedOther = next;
      _otherUrlCtrl.text = next.defaultBaseUrl;
      _otherModelCtrl.text = next.selectedModel;
      _otherError = null;
    });
  }

  Widget _buildExpandableCard({
    required String sectionKey,
    required String title,
    required Widget expandedChild,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final expanded = _expandedSection == sectionKey;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded
              ? colorScheme.primary.withValues(alpha: 0.45)
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () {
              setState(() {
                _expandedSection = expanded ? null : sectionKey;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  expandedChild,
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSpecRow(String label, String value) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBundleExpandedBody(ApiKeyGuideProvider provider) {
    final colorScheme = Theme.of(context).colorScheme;
    final ctrl = _bundleKeyCtrls[provider]!;
    final obscure = _bundleObscure[provider] ?? true;
    final verifying = _bundleVerifying[provider] ?? false;
    final error = _bundleErrors[provider];
    final isDeepSeek = provider == ApiKeyGuideProvider.deepseek;
    final llmPreset =
        LlmProviderPresets.builtIn.firstWhere((p) => p.id == provider.name);
    final ocrPreset =
        OcrProviderPresets.builtIn.firstWhere((p) => p.id == provider.name);
    final asrPreset =
        AsrProviderPresets.builtIn.firstWhere((p) => p.id == provider.name);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: colorScheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSpecRow('接口端点', llmPreset.baseUrl),
              _buildSpecRow('大语言模型', llmPreset.selectedModel),
              _buildSpecRow(
                '图像识别',
                isDeepSeek ? 'DeepSeek OCR' : ocrPreset.selectedModel,
              ),
              _buildSpecRow(
                '文件解析',
                isDeepSeek ? 'DeepSeek OCR' : 'Prime-sync',
              ),
              _buildSpecRow(
                '语音识别',
                isDeepSeek ? 'DeepSeek ASR' : asrPreset.selectedModel,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: ctrl,
          obscureText: obscure,
          onChanged: (_) {
            if (_bundleErrors[provider] != null) {
              setState(() => _bundleErrors[provider] = null);
            }
          },
          decoration: InputDecoration(
            labelText: '${provider.label} API Key',
            hintText: '一次配齐文本、识图、文件与语音',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    obscure ? Icons.visibility_off : Icons.visibility,
                    size: 18,
                  ),
                  tooltip: obscure ? '显示' : '隐藏',
                  onPressed: () =>
                      setState(() => _bundleObscure[provider] = !obscure),
                ),
                IconButton(
                  icon: const Icon(Icons.paste_rounded, size: 18),
                  tooltip: '粘贴',
                  onPressed: () => _pasteInto(
                    ctrl,
                    () => _bundleErrors[provider] = null,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (error != null) ...[
          const SizedBox(height: 8),
          _ErrorBanner(message: error),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: 46,
          child: FilledButton.icon(
            onPressed: verifying ? null : () => _verifyAndSaveBundle(provider),
            icon: verifying
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.verified_rounded, size: 18),
            label: Text(
              verifying ? '正在验证…' : '验证并一键配置',
              style:
                  const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOtherExpandedBody() {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '仅配置大语言模型，图像识别默认使用本机离线能力',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          initialValue: _selectedOther.id,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: '服务商',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          items: _otherProviders
              .map(
                (p) => DropdownMenuItem<String>(
                  value: p.id,
                  child: Text(
                    p.name,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
              .toList(),
          onChanged: (id) {
            if (id == null) return;
            final next = _otherProviders.firstWhere((p) => p.id == id);
            _selectOtherProvider(next);
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _otherUrlCtrl,
          onChanged: (_) {
            if (_otherError != null) {
              setState(() => _otherError = null);
            }
          },
          decoration: InputDecoration(
            labelText: '接口地址 (Base URL)',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _otherModelCtrl,
          onChanged: (_) {
            if (_otherError != null) {
              setState(() => _otherError = null);
            }
          },
          decoration: InputDecoration(
            labelText: '模型名称',
            hintText: '如 gpt-4o / qwen-plus',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _otherKeyCtrl,
          obscureText: _obscureOtherKey,
          onChanged: (_) {
            if (_otherError != null) {
              setState(() => _otherError = null);
            }
          },
          decoration: InputDecoration(
            labelText: 'API Key',
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    _obscureOtherKey
                        ? Icons.visibility_off
                        : Icons.visibility,
                    size: 18,
                  ),
                  onPressed: () =>
                      setState(() => _obscureOtherKey = !_obscureOtherKey),
                ),
                IconButton(
                  icon: const Icon(Icons.paste_rounded, size: 18),
                  onPressed: () =>
                      _pasteInto(_otherKeyCtrl, () => _otherError = null),
                ),
              ],
            ),
          ),
        ),
        if (_otherError != null) ...[
          const SizedBox(height: 8),
          _ErrorBanner(message: _otherError!),
        ],
        const SizedBox(height: 12),
        SizedBox(
          height: 46,
          child: FilledButton.icon(
            onPressed: _verifyingOther ? null : _verifyAndSaveOtherLlm,
            icon: _verifyingOther
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.check_circle_outline, size: 18),
            label: Text(
              _verifyingOther ? '正在验证…' : '验证并启用大语言模型',
              style:
                  const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('配置 API Key')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          _buildExpandableCard(
            sectionKey: 'deepseek',
            title: 'DeepSeek',
            expandedChild:
                _buildBundleExpandedBody(ApiKeyGuideProvider.deepseek),
          ),
          _buildExpandableCard(
            sectionKey: 'zhipu',
            title: '智谱',
            expandedChild: _buildBundleExpandedBody(ApiKeyGuideProvider.zhipu),
          ),
          _buildExpandableCard(
            sectionKey: 'other',
            title: '其他供应商',
            expandedChild: _buildOtherExpandedBody(),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Colors.red.shade700, size: 17),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.red.shade800,
                height: 1.4,
              ),
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
            child: Icon(Icons.school_outlined,
                size: 46, color: colorScheme.primary),
          ),
          const SizedBox(height: 26),
          Text(
            '要不要花一分钟学一下？',
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '跟着提示走一遍新建会话、录入材料\n与生成结果的基础流程。\n后续也可随时在「设置 - 关于与帮助」里重新打开。',
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
              style:
                  TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
