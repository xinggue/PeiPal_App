import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/api/api_config.dart';
import 'package:peipal/data/services/api/api_service.dart';
import 'package:peipal/data/services/compliance/storefront_compliance.dart';
import 'package:peipal/domain/models/asr_provider.dart';
import 'package:peipal/domain/models/ocr_provider.dart';
import 'package:peipal/presentation/pages/onboarding/onboarding_flow.dart';
import 'package:peipal/presentation/pages/settings/about_page.dart';
import 'package:peipal/presentation/pages/settings/asr_settings_page.dart';
import 'package:peipal/presentation/pages/settings/document_parser_settings_page.dart';
import 'package:peipal/presentation/pages/settings/ocr_settings_page.dart';
import 'package:peipal/presentation/pages/settings/prompt_settings_page.dart';
import 'package:peipal/presentation/pages/settings/settings_page.dart';
import 'package:peipal/providers/asr_providers_provider.dart';
import 'package:peipal/providers/ocr_providers_provider.dart';
import 'package:peipal/providers/providers.dart';
import 'package:peipal/providers/storefront_compliance_provider.dart';

import 'tutorial_test.dart' show MockSettingsRepo;

void main() {
  group('evaluateStorefrontCompliance', () {
    test('non-iOS is always unrestricted even with CHN storefront or CN region', () {
      final result = evaluateStorefrontCompliance(
        isIos: false,
        storefrontCountryCode: 'CHN',
        deviceRegionCode: 'CN',
      );
      expect(result.isAiDirectDisabled, isFalse);
      expect(result.source, 'non_ios');
    });

    test('iOS with CHN storefront disables direct AI even when device region is US', () {
      final result = evaluateStorefrontCompliance(
        isIos: true,
        storefrontCountryCode: 'CHN',
        deviceRegionCode: 'US',
      );
      expect(result.isAiDirectDisabled, isTrue);
      expect(result.source, 'storefront');
      expect(result.storefrontCountryCode, 'CHN');
    });

    test('iOS with USA or HKG storefront keeps direct AI enabled even when device region is CN', () {
      final usa = evaluateStorefrontCompliance(
        isIos: true,
        storefrontCountryCode: 'USA',
        deviceRegionCode: 'CN',
      );
      expect(usa.isAiDirectDisabled, isFalse);
      expect(usa.source, 'storefront');

      final hkg = evaluateStorefrontCompliance(
        isIos: true,
        storefrontCountryCode: 'HKG',
        deviceRegionCode: 'CN',
      );
      expect(hkg.isAiDirectDisabled, isFalse);
      expect(hkg.source, 'storefront');
    });

    test('iOS with null storefront falls back to device region code', () {
      final cn = evaluateStorefrontCompliance(
        isIos: true,
        storefrontCountryCode: null,
        deviceRegionCode: 'CN',
      );
      expect(cn.isAiDirectDisabled, isTrue);
      expect(cn.source, 'locale_fallback');

      final us = evaluateStorefrontCompliance(
        isIos: true,
        storefrontCountryCode: null,
        deviceRegionCode: 'US',
      );
      expect(us.isAiDirectDisabled, isFalse);
      expect(us.source, 'locale_fallback');
    });

    test('debugOverride works only when isDebugMode is true and is ignored in release', () {
      final debugRestricted = evaluateStorefrontCompliance(
        isIos: false,
        debugOverride: 'true',
        isDebugMode: true,
      );
      expect(debugRestricted.isAiDirectDisabled, isTrue);
      expect(debugRestricted.source, 'debug_override');

      final releaseIgnored = evaluateStorefrontCompliance(
        isIos: true,
        storefrontCountryCode: 'USA',
        debugOverride: 'true',
        isDebugMode: false,
      );
      expect(releaseIgnored.isAiDirectDisabled, isFalse);
      expect(releaseIgnored.source, 'storefront');
    });

    test('locked storefront marks state as locked_storefront', () {
      final lockedUsa = evaluateStorefrontCompliance(
        isIos: true,
        storefrontCountryCode: 'USA',
        deviceRegionCode: 'CN',
        isStorefrontLocked: true,
      );
      expect(lockedUsa.isAiDirectDisabled, isFalse);
      expect(lockedUsa.isLocked, isTrue);
      expect(lockedUsa.source, 'locked_storefront');

      final lockedChn = evaluateStorefrontCompliance(
        isIos: true,
        storefrontCountryCode: 'CHN',
        deviceRegionCode: 'US',
        isStorefrontLocked: true,
      );
      expect(lockedChn.isAiDirectDisabled, isTrue);
      expect(lockedChn.isLocked, isTrue);
      expect(lockedChn.source, 'locked_storefront');
    });

    test('extractRegionFromLocaleName handles script subtags without confusing Hans for region', () {
      expect(extractRegionFromLocaleName('zh_CN'), 'CN');
      expect(extractRegionFromLocaleName('zh_Hans_CN'), 'CN');
      expect(extractRegionFromLocaleName('zh-Hant-HK'), 'HK');
      expect(extractRegionFromLocaleName('zh_Hans'), isNull);
      expect(extractRegionFromLocaleName('en'), isNull);
    });
  });

  group('ApiService, OCR & ASR guards', () {
    test('ApiService blocks LLM and foreign/LLM-endpoint ASR & OCR when AI direct mode is disabled', () async {
      final api = ApiService()..setAiDirectDisabled(true);

      await expectLater(
        () => api.chatCompletion(
          systemPrompt: 'sys',
          userPrompt: 'usr',
        ),
        throwsA(isA<UnsupportedError>()),
      );
      expect(await api.testLlmConnection(), isFalse);

      // 默认为 openaiWhisper（境外）与 mimoV25（走 /chat/completions），均应被拦截
      await expectLater(
        () => api.transcribeAudio('/tmp/fake.wav'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(await api.testAsrConnection(), isFalse);

      api.updateAsrConfig(const AsrConfig(provider: AsrProvider.mimoV25));
      await expectLater(
        () => api.transcribeAudio('/tmp/fake.wav'),
        throwsA(isA<UnsupportedError>()),
      );
      expect(await api.testAsrConnection(), isFalse);

      // 默认为 openai（境外 / chat/completions 通用视觉大模型），应被拦截
      await expectLater(
        () => api.extractTextFromImages(const []),
        throwsA(isA<UnsupportedError>()),
      );
      expect(await api.testOcrConnection(), isFalse);
    });

    test('ocrProvidersProvider removes OpenAI Vision while keeping Apple Vision and domestic non-LLM presets (empty keys)', () async {
      FlutterSecureStorage.setMockInitialValues({
        'ocr_active_provider_id_v1': 'openai',
      });
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          initialStorefrontComplianceProvider.overrideWithValue(
            const StorefrontComplianceState.chinaRestricted(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(ocrProvidersProvider.notifier).ready;
      final state = container.read(ocrProvidersProvider);

      expect(state.isLoading, isFalse);
      expect(
        state.providers.any(
          (p) => p.protocol == OcrProtocol.openaiVision || p.id == 'openai',
        ),
        isFalse,
      );
      expect(
        state.providers.map((p) => p.id),
        containsAll(['deepseek', 'modelbest', 'zhipu', 'paddleOcr', 'mineru']),
      );
      expect(state.activeProviderId, isNot('openai'));
      for (final cloud in state.providers.where((p) => p.requiresApiKey)) {
        expect(cloud.apiKey, isEmpty);
      }
    });

    test('asrProvidersProvider removes OpenAI Whisper and MiMo while keeping DeepSeek and Zhipu with empty keys', () async {
      FlutterSecureStorage.setMockInitialValues({
        'asr_active_provider_id_v1': 'openaiWhisper',
      });
      final container = ProviderContainer(
        overrides: [
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          initialStorefrontComplianceProvider.overrideWithValue(
            const StorefrontComplianceState.chinaRestricted(),
          ),
        ],
      );
      addTearDown(container.dispose);

      await container.read(asrProvidersProvider.notifier).ready;
      final state = container.read(asrProvidersProvider);

      expect(state.isLoading, isFalse);
      expect(
        state.providers.any(
          (p) =>
              p.protocol == AsrProtocol.openaiWhisper ||
              p.protocol == AsrProtocol.mimoV25,
        ),
        isFalse,
      );
      expect(state.providers.map((p) => p.id), containsAll(['deepseek', 'zhipu']));
      expect(state.activeProviderId, isNot('openaiWhisper'));
      for (final cloud in state.providers.where((p) => p.requiresApiKey)) {
        expect(cloud.apiKey, isEmpty);
      }
    });
  });

  group('China restricted UI gating', () {
    testWidgets('OnboardingFlow skips AI prompt page and transitions Welcome -> Permission -> TutorialPrompt', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterSecureStorage.setMockInitialValues({});
      final settings = MockSettingsRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
            settingsRepositoryProvider.overrideWithValue(settings),
            initialStorefrontComplianceProvider.overrideWithValue(
              const StorefrontComplianceState.chinaRestricted(),
            ),
          ],
          child: const MaterialApp(home: OnboardingFlow()),
        ),
      );
      await tester.pumpAndSettle();

      // 3 dots instead of 4 when AI prompt page is omitted
      expect(find.byType(AnimatedContainer), findsNWidgets(3));

      // Accept disclaimer and go to permissions
      await tester.tap(find.byType(Checkbox).first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始'));
      await tester.pumpAndSettle();

      expect(find.text('开启所需权限'), findsOneWidget);
      expect(find.textContaining('语音转文字、拍照离线识图'), findsOneWidget);

      // Next goes directly to tutorial prompt, skipping '已经有 API Key 了吗？'
      await tester.tap(find.text('下一步'));
      await tester.pumpAndSettle();

      expect(find.text('已经有 API Key 了吗？'), findsNothing);
      expect(find.text('要不要花一分钟学一下？'), findsOneWidget);
    });

    testWidgets('SettingsPage hides LLM only while keeping prompts, OCR, ASR and DocumentParser in China restricted mode', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final settings = MockSettingsRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
            settingsRepositoryProvider.overrideWithValue(settings),
            initialStorefrontComplianceProvider.overrideWithValue(
              const StorefrontComplianceState.chinaRestricted(),
            ),
          ],
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('识别与提示词'), findsOneWidget);
      expect(find.text('人工智能'), findsNothing);
      expect(find.text('大语言模型'), findsNothing);
      expect(find.text('提示词'), findsOneWidget);
      expect(find.text('图像识别'), findsOneWidget);
      expect(find.text('文件解析'), findsOneWidget);
      expect(find.text('语音识别'), findsOneWidget);
    });

    testWidgets('AsrSettingsPage hides custom add button, API tutorial banner and foreign/LLM-endpoint presets in China restricted mode', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
            initialStorefrontComplianceProvider.overrideWithValue(
              const StorefrontComplianceState.chinaRestricted(),
            ),
          ],
          child: const MaterialApp(home: AsrSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.text('不知道如何配置？'), findsNothing);
      expect(find.textContaining('DeepSeek'), findsOneWidget);
      expect(find.textContaining('智谱 AI'), findsAtLeastNWidgets(1));
      expect(find.textContaining('OpenAI Whisper'), findsNothing);
      expect(find.textContaining('小米 MiMo'), findsNothing);
    });

    testWidgets('OcrSettingsPage hides custom add button, API tutorial banner and OpenAI Vision while keeping domestic OCR in China restricted mode', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
            initialStorefrontComplianceProvider.overrideWithValue(
              const StorefrontComplianceState.chinaRestricted(),
            ),
          ],
          child: const MaterialApp(home: OcrSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.text('不知道如何配置？'), findsNothing);
      expect(find.textContaining('OpenAI Vision'), findsNothing);
      expect(find.textContaining('DeepSeek 文字识别'), findsOneWidget);
      expect(find.textContaining('智谱 AI'), findsOneWidget);
    });

    testWidgets('DocumentParserSettingsPage hides API tutorial banner while keeping DeepSeek and Zhipu presets in China restricted mode', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final settings = MockSettingsRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
            settingsRepositoryProvider.overrideWithValue(settings),
            initialStorefrontComplianceProvider.overrideWithValue(
              const StorefrontComplianceState.chinaRestricted(),
            ),
          ],
          child: const MaterialApp(home: DocumentParserSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('不知道如何配置？'), findsNothing);
      expect(find.text('DeepSeek'), findsOneWidget);
      expect(find.text('智谱'), findsOneWidget);
    });

    testWidgets('PromptSettingsPage hides AI extractor & dry-run switch in China restricted mode', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final settings = MockSettingsRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
            settingsRepositoryProvider.overrideWithValue(settings),
            initialStorefrontComplianceProvider.overrideWithValue(
              const StorefrontComplianceState.chinaRestricted(),
            ),
          ],
          child: const MaterialApp(home: PromptSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('文书生成'), findsOneWidget);
      expect(find.text('内容模板补充与迁移'), findsNothing);
      expect(find.text('提示词监视'), findsNothing);
    });

    testWidgets('AboutPage hides API Key guide tile in China restricted mode', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final settings = MockSettingsRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
            settingsRepositoryProvider.overrideWithValue(settings),
            initialStorefrontComplianceProvider.overrideWithValue(
              const StorefrontComplianceState.chinaRestricted(),
            ),
          ],
          child: const MaterialApp(home: AboutPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.scrollUntilVisible(
        find.text('重新开启入门操作演练'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('重新开启入门操作演练'), findsOneWidget);
      expect(find.text('获取 API Key'), findsNothing);
    });
  });
}
