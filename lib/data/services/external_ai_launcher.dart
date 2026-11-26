import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../presentation/widgets/common/app_toast.dart';
import '../../providers/providers.dart';
import '../repositories/settings_repository.dart';

const String kPreferredExternalAiAppKey = 'preferred_external_ai_app';

/// 外部 AI 跳转目标定义（仅用于中国大陆 iOS 受限模式手动复制跳转）。
class ExternalAiApp {
  final String id;
  final String name;
  final String? universalLink;
  final String? appScheme;
  final String webFallback;

  const ExternalAiApp({
    required this.id,
    required this.name,
    this.universalLink,
    this.appScheme,
    required this.webFallback,
  });
}

const List<ExternalAiApp> kChinaExternalAiApps = [
  ExternalAiApp(
    id: 'doubao',
    name: '豆包',
    universalLink: 'https://www.doubao.com/chat/',
    appScheme: 'doubao://',
    webFallback: 'https://www.doubao.com/chat/',
  ),
  ExternalAiApp(
    id: 'deepseek',
    name: 'DeepSeek',
    appScheme: 'deepseek://',
    webFallback: 'https://chat.deepseek.com/',
  ),
  ExternalAiApp(
    id: 'kimi',
    name: 'Kimi',
    universalLink: 'https://www.kimi.com/app/',
    appScheme: 'kimi://',
    webFallback: 'https://www.kimi.com/',
  ),
  ExternalAiApp(
    id: 'qianwen',
    name: '通义千问',
    universalLink: 'https://www.qianwen.com/app/',
    appScheme: 'tongyi://',
    webFallback: 'https://www.qianwen.com/',
  ),
  ExternalAiApp(
    id: 'yuanbao',
    name: '腾讯元宝',
    appScheme: 'yuanbao://',
    webFallback: 'https://yuanbao.tencent.com/',
  ),
];

ExternalAiApp findExternalAiApp(String? id) {
  if (id == null || id.trim().isEmpty) return kChinaExternalAiApps.first;
  return kChinaExternalAiApps
          .where((app) => app.id == id.trim())
          .firstOrNull ??
      kChinaExternalAiApps.first;
}

enum ExternalAiLaunchOutcome {
  openedNative,
  openedWebFallback,
  failed,
}

typedef ExternalUriLauncher = Future<bool> Function(
  Uri uri, {
  required LaunchMode mode,
});

/// 通过 Universal Link（优先）与 URL Scheme 拉起外部 AI，失败时回落官网网页。
class ExternalAiLauncher {
  static Future<bool> _defaultLaunch(Uri uri, {required LaunchMode mode}) {
    return launchUrl(uri, mode: mode);
  }

  static Future<bool> _tryLaunch(
    ExternalUriLauncher launcher,
    String? rawUrl,
    LaunchMode mode,
  ) async {
    if (rawUrl == null || rawUrl.isEmpty) return false;
    final uri = Uri.tryParse(rawUrl);
    if (uri == null) return false;
    try {
      return await launcher(uri, mode: mode);
    } catch (_) {
      return false;
    }
  }

  static Future<ExternalAiLaunchOutcome> launch(
    ExternalAiApp app, {
    ExternalUriLauncher? launcher,
  }) async {
    final fn = launcher ?? _defaultLaunch;

    // 1. 若支持有效 Universal Link，优先强制拉起原生 App（不进浏览器）
    if (await _tryLaunch(
      fn,
      app.universalLink,
      LaunchMode.externalNonBrowserApplication,
    )) {
      return ExternalAiLaunchOutcome.openedNative;
    }

    // 2. 尝试 Custom URL Scheme 拉起原生 App
    if (await _tryLaunch(
      fn,
      app.appScheme,
      LaunchMode.externalApplication,
    )) {
      return ExternalAiLaunchOutcome.openedNative;
    }

    // 3. 回落到官方网页端
    if (await _tryLaunch(
      fn,
      app.webFallback,
      LaunchMode.externalApplication,
    )) {
      return ExternalAiLaunchOutcome.openedWebFallback;
    }

    return ExternalAiLaunchOutcome.failed;
  }
}

class PreferredExternalAiNotifier extends StateNotifier<ExternalAiApp> {
  final SettingsRepository _repo;
  bool _loaded = false;

  PreferredExternalAiNotifier(this._repo)
      : super(kChinaExternalAiApps.first) {
    ensureLoaded();
  }

  Future<void> ensureLoaded() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final savedId = await _repo.get(kPreferredExternalAiAppKey);
      if (mounted) {
        state = findExternalAiApp(savedId);
      }
    } catch (_) {}
  }

  Future<void> select(String id) async {
    final resolved = findExternalAiApp(id);
    _loaded = true;
    state = resolved;
    try {
      await _repo.set(kPreferredExternalAiAppKey, resolved.id);
    } catch (_) {}
  }
}

final preferredExternalAiProvider =
    StateNotifierProvider<PreferredExternalAiNotifier, ExternalAiApp>((ref) {
  return PreferredExternalAiNotifier(ref.read(settingsRepositoryProvider));
});

/// 测试时可注入模拟 URI 启动器；生产环境保持 null 使用 `url_launcher`。
final externalUriLauncherProvider = Provider<ExternalUriLauncher?>((ref) => null);

/// 复制提示词、记录偏好并跳转外部 AI。
Future<ExternalAiLaunchOutcome> copyPromptAndLaunchExternalAi({
  required BuildContext context,
  required WidgetRef ref,
  required String promptText,
  required ExternalAiApp target,
}) async {
  await Clipboard.setData(ClipboardData(text: promptText));
  await ref.read(preferredExternalAiProvider.notifier).select(target.id);
  final launcher = ref.read(externalUriLauncherProvider);
  final outcome = await ExternalAiLauncher.launch(target, launcher: launcher);
  if (context.mounted) {
    if (outcome == ExternalAiLaunchOutcome.failed) {
      showAppToast(context, '已复制全部内容，请手动打开${target.name}粘贴');
    } else {
      showAppToast(context, '已复制全部内容，正在打开${target.name}');
    }
  }
  return outcome;
}
