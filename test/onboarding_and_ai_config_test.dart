import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peipal/data/services/api/llm_provider_service.dart';
import 'package:peipal/data/services/sample_data_service.dart';
import 'package:peipal/domain/models/llm_provider.dart';
import 'package:peipal/domain/models/patient.dart';
import 'package:peipal/presentation/pages/onboarding/onboarding_flow.dart';
import 'package:peipal/presentation/pages/patients/patient_list_page.dart';
import 'package:peipal/presentation/pages/settings/api_key_guide_page.dart';
import 'package:peipal/presentation/pages/settings/asr_settings_page.dart';
import 'package:peipal/presentation/pages/settings/document_parser_settings_page.dart';
import 'package:peipal/presentation/pages/settings/llm_providers_page.dart';
import 'package:peipal/presentation/pages/settings/ocr_settings_page.dart';
import 'package:peipal/presentation/pages/settings/settings_page.dart';
import 'package:peipal/presentation/widgets/tutorial/tutorial_spotlight_overlay.dart';
import 'package:peipal/providers/asr_providers_provider.dart';
import 'package:peipal/providers/document_parser_provider.dart';
import 'package:peipal/providers/llm_providers_provider.dart';
import 'package:peipal/providers/ocr_providers_provider.dart';
import 'package:peipal/providers/providers.dart';
import 'package:peipal/providers/tutorial_provider.dart';

import 'tutorial_test.dart'
    show
        MockContentTemplateRepo,
        MockMessageRepo,
        MockPatientRepo,
        MockSettingsRepo,
        MockTemplateRepo;

class _ThrowingSecureStorage extends FlutterSecureStorage {
  const _ThrowingSecureStorage();

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw Exception('simulated secure storage error');
  }
}

class _FakeLlmProviderService extends LlmProviderService {
  final List<String> modelsToReturn;

  _FakeLlmProviderService(this.modelsToReturn);

  @override
  Future<List<String>> fetchModels(LlmProviderConfig provider) async {
    return modelsToReturn;
  }
}

Dio _mockVerifyDio({
  required bool accept,
  void Function(RequestOptions options)? onRequest,
}) {
  final dio = Dio();
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        onRequest?.call(options);
        handler.resolve(
          Response(
            requestOptions: options,
            statusCode: accept ? 200 : 401,
            data: accept
                ? {
                    'choices': [
                      {
                        'message': {'content': 'hi'},
                      },
                    ],
                  }
                : {
                    'error': {'message': 'Invalid API key'},
                  },
          ),
        );
      },
    ),
  );
  return dio;
}

void main() {
  testWidgets(
    'SettingsPage hides outer guide tile while unconfigured AI pages show dismissible tutorial notice',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final settings = MockSettingsRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(
              const FlutterSecureStorage(),
            ),
            settingsRepositoryProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('未配置 Key'), findsOneWidget);
      expect(find.text('获取 API Key'), findsNothing);
      expect(find.text('不知道如何配置？'), findsNothing);
      expect(find.text('点击查看配置教程'), findsNothing);
      expect(find.text('deepseek-flash'), findsNothing);

      for (final page in const <Widget>[
        LlmProvidersPage(),
        DocumentParserSettingsPage(),
        AsrSettingsPage(),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              secureStorageProvider.overrideWithValue(
                const FlutterSecureStorage(),
              ),
              settingsRepositoryProvider.overrideWithValue(settings),
            ],
            child: MaterialApp(home: page),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('不知道如何配置？'), findsOneWidget);
        expect(find.text('点击查看配置教程'), findsOneWidget);
        await tester.tap(find.byTooltip('关闭提示'));
        await tester.pumpAndSettle();
        expect(find.text('不知道如何配置？'), findsNothing);
      }

      // Local OCR is ready out of the box, so no unconfigured notice shows until switched to an unconfigured cloud provider
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(
              const FlutterSecureStorage(),
            ),
            settingsRepositoryProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: OcrSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('不知道如何配置？'), findsNothing);

      for (final guide in ApiKeyGuideProvider.values) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              secureStorageProvider.overrideWithValue(
                const FlutterSecureStorage(),
              ),
              settingsRepositoryProvider.overrideWithValue(settings),
            ],
            child: MaterialApp(home: ApiKeyGuidePage(provider: guide)),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('一个 Key 通用全部服务'), findsOneWidget);
        expect(find.textContaining('思考强度'), findsNothing);
        expect(find.textContaining('推理强度'), findsNothing);
      }
    },
  );

  test(
    'LLM, OCR, and ASR notifiers recover cleanly when secure storage throws',
    () async {
      final settings = MockSettingsRepo();
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(
            const _ThrowingSecureStorage(),
          ),
          settingsRepositoryProvider.overrideWithValue(settings),
        ],
      );
      addTearDown(container.dispose);

      // Initialize all three providers
      container.read(llmProvidersProvider);
      container.read(ocrProvidersProvider);
      container.read(asrProvidersProvider);

      // Let async _load complete
      await Future<void>.delayed(const Duration(milliseconds: 50));

      final llmState = container.read(llmProvidersProvider);
      final ocrState = container.read(ocrProvidersProvider);
      final asrState = container.read(asrProvidersProvider);

      expect(llmState.isLoading, isFalse);
      expect(llmState.providers, isNotEmpty);
      expect(ocrState.isLoading, isFalse);
      expect(ocrState.providers, isNotEmpty);
      expect(asrState.isLoading, isFalse);
      expect(asrState.providers, isNotEmpty);
    },
  );

  testWidgets(
    'LlmProvidersPage activates non-default provider on key fetch and model selection',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterSecureStorage.setMockInitialValues({});
      final settings = MockSettingsRepo();
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(
            const FlutterSecureStorage(),
          ),
          settingsRepositoryProvider.overrideWithValue(settings),
          llmProviderServiceProvider.overrideWithValue(
            _FakeLlmProviderService(['gpt-4o-mini', 'gpt-4o']),
          ),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LlmProvidersPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(container.read(llmProvidersProvider).activeProviderId, 'deepseek');

      // Expand OpenAI card and save key + fetch models
      await tester.scrollUntilVisible(
        find.text('OpenAI (官方 / 专线)'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('OpenAI (官方 / 专线)'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'API Key').first,
        'sk-openai-test-key',
      );
      await tester.drag(find.byType(ListView).first, const Offset(0, -180));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('保存 Key 并获取模型列表'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存 Key 并获取模型列表'));
      await tester.pumpAndSettle();

      // Provider should already become active after fetch succeeds
      expect(container.read(llmProvidersProvider).activeProviderId, 'openai');

      // Pick specific model in bottom sheet
      await tester.tap(find.text('gpt-4o-mini'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      final llmState = container.read(llmProvidersProvider);
      expect(llmState.activeProviderId, 'openai');
      expect(llmState.activeProvider?.selectedModel, 'gpt-4o-mini');
    },
  );

  testWidgets(
    'OnboardingFlow shows concise AI prompt page and allows skipping directly to tutorial prompt',
    (tester) async {
      tester.view.physicalSize = const Size(360, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterSecureStorage.setMockInitialValues({});
      final settings = MockSettingsRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(
              const FlutterSecureStorage(),
            ),
            settingsRepositoryProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: OnboardingFlow()),
        ),
      );
      await tester.pumpAndSettle();

      // Page 0: Welcome
      expect(find.text('欢迎使用小培同学'), findsOneWidget);
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();

      // Page 1: Permissions (shows system settings link when not all granted)
      expect(find.text('开启所需权限'), findsOneWidget);
      expect(find.text('去系统设置'), findsOneWidget);
      expect(find.text('也可以稍后在「设置」中再授权'), findsNothing);
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      // Page 2: Concise AI prompt matching other onboarding steps
      expect(find.text('已经有 API Key 了吗？'), findsOneWidget);
      expect(find.text('有，去配置'), findsOneWidget);
      expect(find.text('没有，先跳过'), findsOneWidget);
      await tester.tap(find.text('没有，先跳过'));
      await tester.pumpAndSettle();

      // Page 3: Unchanged tutorial prompt page
      expect(find.text('要不要花一分钟学一下？'), findsOneWidget);
      expect(find.text('开始学习'), findsOneWidget);
    },
  );

  testWidgets(
    'OnboardingFlow pushing AI config configures Zhipu bundle and advances on success',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterSecureStorage.setMockInitialValues({});
      final settings = MockSettingsRepo();
      RequestOptions? lastRequest;
      final dio = _mockVerifyDio(
        accept: true,
        onRequest: (opt) => lastRequest = opt,
      );
      addTearDown(dio.close);

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(
            const FlutterSecureStorage(),
          ),
          settingsRepositoryProvider.overrideWithValue(settings),
          apiKeyGuideDioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OnboardingFlow()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      // Open pushed AI config screen -> 3 equal collapsed cards
      await tester.tap(find.text('有，去配置'));
      await tester.pumpAndSettle();
      expect(find.text('配置 API Key'), findsOneWidget);
      expect(find.textContaining('https://'), findsNothing);
      expect(find.text('DeepSeek'), findsOneWidget);
      expect(find.text('智谱'), findsOneWidget);
      expect(find.text('其他供应商'), findsOneWidget);
      // All collapsed initially, matching uniform layout
      expect(find.text('验证并一键配置'), findsNothing);

      // Expand DeepSeek briefly to verify endpoint + model spec display
      await tester.tap(find.text('DeepSeek'));
      await tester.pumpAndSettle();
      expect(find.text('https://api.deepseek.com'), findsOneWidget);
      expect(find.text('deepseek-flash'), findsOneWidget);
      expect(find.textContaining('思考强度'), findsNothing);
      expect(find.textContaining('推理强度'), findsNothing);
      expect(find.text('DeepSeek ASR'), findsOneWidget);

      // Expand Zhipu and configure bundle -> shows Zhipu specs and advances on success
      await tester.tap(find.text('智谱'));
      await tester.pumpAndSettle();
      expect(find.text('https://open.bigmodel.cn/api/paas/v4'), findsOneWidget);
      expect(find.text('glm-5.3-flashx'), findsOneWidget);
      expect(find.text('glm-ocr'), findsOneWidget);
      expect(find.text('Prime-sync'), findsOneWidget);
      expect(find.text('glm-asr-2512'), findsOneWidget);

      await tester.enterText(
        find.widgetWithText(TextField, '智谱 API Key'),
        'zhipu-onboarding-key',
      );
      await tester.tap(find.text('验证并一键配置'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      expect(lastRequest?.uri.host, 'open.bigmodel.cn');
      expect(container.read(llmProvidersProvider).activeProvider?.id, 'zhipu');
      expect(container.read(ocrProvidersProvider).activeProvider?.id, 'zhipu');
      expect(container.read(asrProvidersProvider).activeProvider?.id, 'zhipu');
      expect(
        container.read(documentParserProvider).requireValue.activeProvider?.id,
        'zhipu',
      );
      // Onboarding must NOT hijack tutorial state yet, and advances straight to Page 3
      expect(container.read(tutorialProvider).isActive, isFalse);
      expect(find.text('要不要花一分钟学一下？'), findsOneWidget);
    },
  );

  testWidgets(
    'OnboardingFlow other provider collapsible configures LLM only and advances on success',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterSecureStorage.setMockInitialValues({});
      final settings = MockSettingsRepo();
      RequestOptions? lastRequest;
      final dio = _mockVerifyDio(
        accept: true,
        onRequest: (opt) => lastRequest = opt,
      );
      addTearDown(dio.close);

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(
            const FlutterSecureStorage(),
          ),
          settingsRepositoryProvider.overrideWithValue(settings),
          apiKeyGuideDioProvider.overrideWithValue(dio),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: OnboardingFlow()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('有，去配置'));
      await tester.pumpAndSettle();

      await container.read(ocrProvidersProvider.notifier).ready;
      final initialOcrId = container.read(ocrProvidersProvider).activeProvider?.id;

      // Expand other providers section and configure SiliconFlow LLM only
      await tester.tap(find.text('其他供应商'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'API Key').last,
        'other-llm-key',
      );
      await tester.ensureVisible(find.text('验证并启用大语言模型'));
      await tester.tap(find.text('验证并启用大语言模型'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      expect(lastRequest?.uri.host, 'api.siliconflow.cn');
      final activeLlm = container.read(llmProvidersProvider).activeProvider!;
      expect(activeLlm.id, 'siliconflow');
      expect(activeLlm.apiKey, 'other-llm-key');
      // OCR remains untouched (stays local default)
      expect(container.read(ocrProvidersProvider).activeProvider?.id, initialOcrId);
      // Automatically advances to tutorial prompt page
      expect(find.text('要不要花一分钟学一下？'), findsOneWidget);
    },
  );

  testWidgets(
    'TutorialSpotlightOverlay blocks taps outside target and tooltip',
    (tester) async {
      var backgroundTapped = false;
      final targetKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Positioned(
                  top: 30,
                  left: 20,
                  child: ElevatedButton(
                    onPressed: () => backgroundTapped = true,
                    child: const Text('BackgroundAction'),
                  ),
                ),
                Positioned(
                  bottom: 24,
                  right: 24,
                  child: SizedBox(
                    key: targetKey,
                    width: 56,
                    height: 56,
                  ),
                ),
                TutorialSpotlightOverlay(
                  targetKey: targetKey,
                  stepTag: '1/5',
                  title: 'Test',
                  description: 'Desc',
                  onNext: () {},
                  onSkip: () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('BackgroundAction'), warnIfMissed: false);
      await tester.pump();

      expect(backgroundTapped, isFalse);
    },
  );

  testWidgets(
    'PatientListPage tutorial step 2 recreates deleted sample patient instead of routing to real patient',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterSecureStorage.setMockInitialValues({});
      final settings = MockSettingsRepo();
      final patientRepo = MockPatientRepo();
      final messageRepo = MockMessageRepo();
      final sampleService = SampleDataService(
        patientRepo: patientRepo,
        messageRepo: messageRepo,
        templateRepo: MockTemplateRepo(),
        contentTemplateRepo: MockContentTemplateRepo(),
        settingsRepo: settings,
        seedMedia: false,
      );

      // Only a real user patient exists (sample patient was deleted)
      await patientRepo.insert(
        Patient(
          id: 'real_patient_01',
          name: '李四',
          status: PatientStatus.active,
        ),
      );

      String? navigatedPath;
      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const PatientListPage()),
          GoRoute(
            path: '/patients/:id/chat',
            builder: (_, state) {
              navigatedPath = state.uri.toString();
              return const Scaffold(body: Text('ChatRoute'));
            },
          ),
        ],
      );
      addTearDown(router.dispose);

      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(
            const FlutterSecureStorage(),
          ),
          settingsRepositoryProvider.overrideWithValue(settings),
          patientRepositoryProvider.overrideWithValue(patientRepo),
          messageRepositoryProvider.overrideWithValue(messageRepo),
          sampleDataServiceProvider.overrideWithValue(sampleService),
        ],
      );
      addTearDown(container.dispose);

      await container
          .read(tutorialProvider.notifier)
          .startTutorial(TutorialType.basicFlow, step: 2);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Real patient must NOT hold _sampleCardKey (only '进入示例会话' creates/enters sample)
      await tester.tap(find.text('进入示例会话'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();

      expect(navigatedPath, '/patients/${SampleDataService.samplePatientId}/chat');
      final recreated = await patientRepo.getById(SampleDataService.samplePatientId);
      expect(recreated, isNotNull);
    },
  );
}
