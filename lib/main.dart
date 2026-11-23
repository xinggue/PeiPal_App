import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'data/services/ble/character_sanitizer.dart';
import 'data/services/compliance/storefront_compliance.dart';
import 'data/services/logging/app_log_service.dart';
import 'data/services/media/ocr_image_optimizer.dart';
import 'presentation/pages/onboarding/onboarding_flow.dart';
import 'presentation/widgets/ble/draggable_typing_overlay.dart';
import 'presentation/widgets/common/root_overlay_host.dart';
import 'providers/asr_providers_provider.dart';
import 'providers/llm_providers_provider.dart';
import 'providers/ocr_providers_provider.dart';
import 'providers/document_parser_provider.dart';
import 'providers/document_processing_provider.dart';
import 'providers/providers.dart';
import 'providers/storefront_compliance_provider.dart';
import 'providers/tutorial_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final log = AppLogService.instance;
  unawaited(log.init());
  log.info('App', '启动平台=${kIsWeb ? 'web' : Platform.operatingSystem}');

  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) {
    unawaited(log.recordCrash('FlutterError', details.exception, details.stack));
    if (previousOnError != null) {
      previousOnError(details);
    } else {
      FlutterError.presentError(details);
    }
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    unawaited(log.recordCrash('PlatformDispatcher', error, stack));
    return kReleaseMode;
  };

  if (kReleaseMode) {
    ErrorWidget.builder = (details) => Material(
          color: Colors.white,
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                '页面渲染出现异常，请返回重试',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
              ),
            ),
          ),
        );
  }

  // 为 Windows / Linux / macOS 桌面端启用 sqflite_common_ffi 引擎
  if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }

  // 异步清空 OCR 临时压缩图历史缓存
  OcrImageOptimizer.purgePreparedCache();

  final initialCompliance = await StorefrontComplianceService.resolve();
  log.info(
    'Compliance',
    'storefront=${initialCompliance.storefrontCountryCode ?? "-"} '
        'deviceRegion=${initialCompliance.deviceRegionCode ?? "-"} '
        'restricted=${initialCompliance.isAiDirectDisabled} '
        'source=${initialCompliance.source}',
  );

  runApp(
    ProviderScope(
      overrides: [
        initialStorefrontComplianceProvider.overrideWithValue(initialCompliance),
      ],
      child: const DocMasterPeiApp(),
    ),
  );
}

typedef MedHistoryApp = DocMasterPeiApp;

class DocMasterPeiApp extends ConsumerStatefulWidget {
  const DocMasterPeiApp({super.key});

  @override
  ConsumerState<DocMasterPeiApp> createState() => _DocMasterPeiAppState();
}

class _DocMasterPeiAppState extends ConsumerState<DocMasterPeiApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !kIsWeb && Platform.isIOS) {
      unawaited(ref.read(storefrontComplianceProvider.notifier).refresh());
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(storefrontComplianceProvider);
    final router = ref.watch(routerProvider);
    final fontScale = ref.watch(appFontScaleProvider);
    // 启动时加载服务商列表并同步到 ApiService；运行时配置不再单独持久化。
    ref.read(llmConfigProvider);
    ref.watch(llmProvidersProvider);
    ref.read(asrConfigProvider);
    ref.watch(asrProvidersProvider);
    ref.read(ocrConfigProvider);
    ref.watch(ocrProvidersProvider);
    ref.read(documentParserProvider);
    ref.read(documentProcessingProvider);
    ref.read(bleConfigProvider);
    ref.read(charReplacementRulesProvider);
    ref.read(floatingOverlayEnabledProvider);
    ref.read(activeTimingControllerProvider);

    final onboardingDone = ref.watch(onboardingCompletedProvider);

    return onboardingDone.when(
      loading: () => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        locale: const Locale('zh', 'CN'),
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (_, _) => _buildMainApp(router, fontScale),
      data: (done) {
        if (done) {
          unawaited(ref.read(telemetryServiceProvider).pingIfNeeded());
          return _buildMainApp(router, fontScale);
        }
        return MaterialApp(
          title: '小培同学',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.light,
          theme: AppTheme.lightTheme,
          locale: const Locale('zh', 'CN'),
          home: const OnboardingFlow(),
        );
      },
    );
  }

  Widget _buildMainApp(
    GoRouter router,
    double fontScale,
  ) {
    return MaterialApp.router(
      title: '小培同学',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(fontScale),
        ),
        child: RootOverlayHost(
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
