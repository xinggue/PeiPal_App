import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peipal/data/services/sample_data_service.dart';
import 'package:peipal/presentation/pages/settings/api_key_guide_page.dart';
import 'package:peipal/presentation/pages/settings/api_key_guides_page.dart';
import 'package:peipal/providers/asr_providers_provider.dart';
import 'package:peipal/providers/llm_providers_provider.dart';
import 'package:peipal/providers/ocr_providers_provider.dart';
import 'package:peipal/providers/providers.dart';
import 'package:peipal/providers/tutorial_provider.dart';

import 'tutorial_test.dart'
    show
        MockSettingsRepo,
        MockPatientRepo,
        MockMessageRepo,
        MockTemplateRepo,
        MockContentTemplateRepo;

void main() {
  for (final provider in ApiKeyGuideProvider.values) {
    testWidgets(
      '${provider.label} tutorial selection opens the matching page',
      (tester) async {
        tester.view.physicalSize = const Size(320, 740);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        FlutterSecureStorage.setMockInitialValues({});
        final router = GoRouter(
          routes: [
            GoRoute(path: '/', builder: (_, _) => const ApiKeyGuidesPage()),
            for (final item in ApiKeyGuideProvider.values)
              GoRoute(
                path: '/settings/${item.name}-key-guide',
                builder: (_, _) => ApiKeyGuidePage(provider: item),
              ),
          ],
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          ProviderScope(child: MaterialApp.router(routerConfig: router)),
        );
        await tester.tap(find.text(provider.label));
        await tester.pumpAndSettle();
        expect(find.text('获取${provider.label} API Key'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    for (final accepted in [true, false]) {
      testWidgets(
        '${provider.label} key ${accepted ? "activates all services" : "failure preserves settings"}',
        (tester) async {
          FlutterSecureStorage.setMockInitialValues({});
          final settings = MockSettingsRepo();
          final dio = Dio();
          RequestOptions? request;
          dio.interceptors.add(
            InterceptorsWrapper(
              onRequest: (options, handler) {
                request = options;
                handler.resolve(
                  Response(
                    requestOptions: options,
                    statusCode: accepted ? 200 : 401,
                    data: accepted
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
          final container = ProviderContainer(
            overrides: [
              settingsRepositoryProvider.overrideWithValue(settings),
              apiKeyGuideDioProvider.overrideWithValue(dio),
              sampleDataServiceProvider.overrideWithValue(
                SampleDataService(
                  patientRepo: MockPatientRepo(),
                  messageRepo: MockMessageRepo(),
                  templateRepo: MockTemplateRepo(),
                  contentTemplateRepo: MockContentTemplateRepo(),
                  settingsRepo: settings,
                  seedMedia: false,
                ),
              ),
            ],
          );
          addTearDown(container.dispose);
          addTearDown(dio.close);
          await tester.pumpWidget(
            UncontrolledProviderScope(
              container: container,
              child: MaterialApp(home: ApiKeyGuidePage(provider: provider)),
            ),
          );
          await tester.pumpAndSettle();
          final previousLlm = container
              .read(llmProvidersProvider)
              .activeProvider;
          final previousOcr = container
              .read(ocrProvidersProvider)
              .activeProvider;
          final previousAsr = container
              .read(asrProvidersProvider)
              .activeProvider;
          final scrollable = find
              .descendant(
                of: find.byType(ListView),
                matching: find.byType(Scrollable),
              )
              .first;
          await tester.scrollUntilVisible(
            find.byType(TextField),
            500,
            scrollable: scrollable,
          );
          await tester.enterText(find.byType(TextField), 'test-guide-key');
          await tester.scrollUntilVisible(
            find.text('验证并一键配置'),
            150,
            scrollable: scrollable,
          );
          await tester.tap(find.text('验证并一键配置'));
          await tester.pumpAndSettle();
          expect(
            request?.uri.host,
            provider == ApiKeyGuideProvider.deepseek
                ? 'api.deepseek.com'
                : 'open.bigmodel.cn',
          );
          expect(request?.headers['Authorization'], 'Bearer test-guide-key');
          if (accepted) {
            final llm = container.read(llmProvidersProvider).activeProvider!;
            final ocr = container.read(ocrProvidersProvider).activeProvider!;
            final asr = container.read(asrProvidersProvider).activeProvider!;
            expect([llm.id, ocr.id, asr.id], everyElement(provider.name));
            expect([
              llm.apiKey,
              ocr.apiKey,
              asr.apiKey,
            ], everyElement('test-guide-key'));
            if (provider == ApiKeyGuideProvider.deepseek) {
              expect(llm.selectedModel, 'deepseek-flash');
              expect(llm.reasoningEffort, 'low');
              expect(ocr.selectedModel, isEmpty);
              expect(asr.selectedModel, isEmpty);
              expect(ocr.protocol.name, 'deepseek');
              expect(asr.protocol.name, 'deepseek');
              expect(ocr.baseUrl, 'https://api.deepseek.com/v1');
              expect(asr.baseUrl, 'https://api.deepseek.com/v1');
            }
            expect(container.read(tutorialProvider).currentStep, 4);
            expect(find.text('验证成功，AI 已全部配置好'), findsOneWidget);
          } else {
            expect(
              container.read(llmProvidersProvider).activeProvider,
              previousLlm,
            );
            expect(
              container.read(ocrProvidersProvider).activeProvider,
              previousOcr,
            );
            expect(
              container.read(asrProvidersProvider).activeProvider,
              previousAsr,
            );
            expect(find.text('API Key 无效或未复制完整 (401)'), findsOneWidget);
          }
          await tester.pump(const Duration(seconds: 4));
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
