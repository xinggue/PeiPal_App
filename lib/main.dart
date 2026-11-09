import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'data/services/ble/character_sanitizer.dart';
import 'data/services/media/ocr_image_optimizer.dart';
import 'presentation/widgets/ble/draggable_typing_overlay.dart';
import 'providers/asr_providers_provider.dart';
import 'providers/llm_providers_provider.dart';
import 'providers/ocr_providers_provider.dart';
import 'providers/providers.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

  // 为 Windows / Linux / macOS 桌面端启用 sqflite_common_ffi 引擎
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 异步清空 OCR 临时压缩图历史缓存
  OcrImageOptimizer.purgePreparedCache();

  runApp(const ProviderScope(child: DocMasterPeiApp()));
}

typedef MedHistoryApp = DocMasterPeiApp;

class DocMasterPeiApp extends ConsumerWidget {
  const DocMasterPeiApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final fontScale = ref.watch(appFontScaleProvider);
    // 这些配置 notifier 在被创建时才会从存储加载并注入 ApiService / BleService。
    // 必须在启动时就创建，否则没进过设置页时语音/OCR/蓝牙都在用默认空配置。
    ref.read(llmConfigProvider);
    ref.read(llmProvidersProvider);
    ref.read(asrConfigProvider);
    ref.read(asrProvidersProvider);
    ref.read(ocrConfigProvider);
    ref.read(ocrProvidersProvider);
    ref.read(bleConfigProvider);
    ref.read(charReplacementRulesProvider);
    ref.read(floatingOverlayEnabledProvider);
    ref.read(activeTimingControllerProvider);
    return MaterialApp.router(
      title: '小培同学',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(fontScale),
        ),
        child: _RootOverlayHost(
          child: SafeArea(
            top: false,
            bottom: true,
            child: DraggableTypingOverlay(
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
      routerConfig: router,
      locale: const Locale('zh', 'CN'),
    );
  }
}

/// 将整棵应用树（含悬浮窗）挂在一个常驻 [Overlay] 内，
/// 从而让悬浮窗里的 TextField 拥有 Overlay 祖先，长按可正常呼出系统编辑菜单。
class _RootOverlayHost extends StatefulWidget {
  const _RootOverlayHost({required this.child});

  final Widget child;

  @override
  State<_RootOverlayHost> createState() => _RootOverlayHostState();
}

class _RootOverlayHostState extends State<_RootOverlayHost> {
  late final OverlayEntry _entry = OverlayEntry(
    builder: (_) => widget.child,
  );

  @override
  void didUpdateWidget(covariant _RootOverlayHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.child, widget.child)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _entry.markNeedsBuild();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Overlay(initialEntries: [_entry]);
  }

  @override
  void dispose() {
    if (_entry.mounted) {
      _entry.remove();
    }
    _entry.dispose();
    super.dispose();
  }
}
