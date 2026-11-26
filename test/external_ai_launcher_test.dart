import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/compliance/storefront_compliance.dart';
import 'package:peipal/data/services/external_ai_launcher.dart';
import 'package:peipal/data/services/task/task_center.dart';
import 'package:peipal/presentation/widgets/chat/copy_and_launch_ai_button.dart';
import 'package:peipal/presentation/widgets/chat/generation_pending_bubble.dart';
import 'package:peipal/presentation/widgets/chat/manual_prompt_preview_dialog.dart';
import 'package:peipal/providers/providers.dart';
import 'package:peipal/providers/storefront_compliance_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'tutorial_test.dart' show MockSettingsRepo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExternalAiLauncher', () {
    test('Universal Link 优先原生拉起，失败回落 Scheme，再失败回落网页端', () async {
      final doubao = findExternalAiApp('doubao');
      final calls = <(Uri, LaunchMode)>[];

      final outcome1 = await ExternalAiLauncher.launch(
        doubao,
        launcher: (uri, {required mode}) async {
          calls.add((uri, mode));
          return true;
        },
      );
      expect(outcome1, ExternalAiLaunchOutcome.openedNative);
      expect(calls, [
        (
          Uri.parse('https://www.doubao.com/chat/'),
          LaunchMode.externalNonBrowserApplication,
        ),
      ]);

      // Universal Link 与 Scheme 均失败时回落网页版
      calls.clear();
      final outcome2 = await ExternalAiLauncher.launch(
        doubao,
        launcher: (uri, {required mode}) async {
          calls.add((uri, mode));
          return mode == LaunchMode.externalApplication &&
              uri.scheme == 'https';
        },
      );
      expect(outcome2, ExternalAiLaunchOutcome.openedWebFallback);
      expect(calls, [
        (
          Uri.parse('https://www.doubao.com/chat/'),
          LaunchMode.externalNonBrowserApplication,
        ),
        (Uri.parse('doubao://'), LaunchMode.externalApplication),
        (
          Uri.parse('https://www.doubao.com/chat/'),
          LaunchMode.externalApplication,
        ),
      ]);

      // 无 Universal Link 的 DeepSeek 直接走 deepseek://，失败后走 chat.deepseek.com
      calls.clear();
      final deepseek = findExternalAiApp('deepseek');
      final outcome3 = await ExternalAiLauncher.launch(
        deepseek,
        launcher: (uri, {required mode}) async {
          calls.add((uri, mode));
          return uri.scheme == 'https';
        },
      );
      expect(outcome3, ExternalAiLaunchOutcome.openedWebFallback);
      expect(calls, [
        (Uri.parse('deepseek://'), LaunchMode.externalApplication),
        (
          Uri.parse('https://chat.deepseek.com/'),
          LaunchMode.externalApplication,
        ),
      ]);
    });
  });

  group('Storefront gating & Plan A preference UI', () {
    final copiedTexts = <String>[];

    setUp(() {
      copiedTexts.clear();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedTexts.add((call.arguments as Map)['text'] as String);
        } else if (call.method == 'Clipboard.getData') {
          return {'text': copiedTexts.isEmpty ? '' : copiedTexts.last};
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    testWidgets('非中国大陆 iOS（unrestricted）绝不展示外部 AI 直达按钮', (tester) async {
      final repo = MockSettingsRepo();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(repo),
            initialStorefrontComplianceProvider.overrideWithValue(
              const StorefrontComplianceState.unrestricted(),
            ),
          ],
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  const CopyAndLaunchAiButton(promptText: '测试内容'),
                  Builder(
                    builder: (ctx) => ElevatedButton(
                      onPressed: () => showManualPromptPreviewDialog(
                        context: ctx,
                        title: '病历内容',
                        promptText: '完整测试 Prompt',
                      ),
                      child: const Text('OPEN_DIALOG'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('复制并打开'), findsNothing);

      await tester.tap(find.text('OPEN_DIALOG'));
      await tester.pumpAndSettle();

      expect(find.text('复制全部内容'), findsOneWidget);
      expect(find.textContaining('复制并打开'), findsNothing);
    });

    testWidgets(
      '中国大陆 iOS 受限模式：弹窗与气泡显示「复制并打开 XX」，切换后自动记忆偏好并复用',
      (tester) async {
        final repo = MockSettingsRepo();
        final launched = <(Uri, LaunchMode)>[];

        final container1 = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(repo),
            initialStorefrontComplianceProvider.overrideWithValue(
              const StorefrontComplianceState.chinaRestricted(),
            ),
            externalUriLauncherProvider.overrideWithValue(
              (uri, {required mode}) async {
                launched.add((uri, mode));
                return true;
              },
            ),
          ],
        );
        addTearDown(container1.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container1,
            child: MaterialApp(
              home: Scaffold(
                body: Builder(
                  builder: (ctx) => ElevatedButton(
                    onPressed: () => showManualPromptPreviewDialog(
                      context: ctx,
                      title: '已整理对话内容',
                      promptText: '请生成门诊病历，主诉：头痛3天。',
                    ),
                    child: const Text('OPEN_DIALOG'),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.text('OPEN_DIALOG'));
        await tester.pumpAndSettle();

        // 默认记忆豆包
        expect(find.text('复制并打开 豆包'), findsOneWidget);
        expect(find.text('仅复制'), findsOneWidget);

        // 直接点主按钮：复制全文 + Universal Link 拉起豆包
        await tester.tap(find.text('复制并打开 豆包'));
        await tester.pumpAndSettle();
        expect(copiedTexts.last, '请生成门诊病历，主诉：头痛3天。');
        expect(launched.last.$1.toString(), 'https://www.doubao.com/chat/');

        // 点右侧下拉箭头切换至 DeepSeek：复制全文 + 启动 deepseek:// + 记忆偏好
        await tester.tap(find.byIcon(Icons.arrow_drop_down_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.text('DeepSeek'));
        await tester.pumpAndSettle();

        expect(launched.last.$1.toString(), 'deepseek://');
        expect(find.text('复制并打开 DeepSeek'), findsOneWidget);
        expect(repo.data[kPreferredExternalAiAppKey], 'deepseek');

        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();

        // 关闭预览弹窗后再切换挂载气泡视图
        await tester.tap(find.text('关闭'));
        await tester.pumpAndSettle();

        // 模拟重新打开页面 / 聊天中待贴回气泡：记住上次选的 DeepSeek
        final task = BackgroundTask(
          id: 't1',
          type: TaskType.generation,
          patientId: 'p1',
          patientName: '张三',
          title: '门诊病历',
          status: TaskStatus.running,
          isManual: true,
          createdAt: DateTime.now(),
          manualPrompt: '气泡内完整 Prompt',
        );

        final container2 = ProviderContainer(
          overrides: [
            settingsRepositoryProvider.overrideWithValue(repo),
            initialStorefrontComplianceProvider.overrideWithValue(
              const StorefrontComplianceState.chinaRestricted(),
            ),
            externalUriLauncherProvider.overrideWithValue(
              (uri, {required mode}) async {
                launched.add((uri, mode));
                return true;
              },
            ),
          ],
        );
        addTearDown(container2.dispose);
        await container2.read(preferredExternalAiProvider.notifier).ensureLoaded();

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container2,
            child: MaterialApp(
              home: Scaffold(
                body: GenerationPendingBubble(task: task),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('复制并打开 DeepSeek'), findsOneWidget);
        await tester.tap(find.text('复制并打开 DeepSeek'));
        await tester.pumpAndSettle();
        expect(copiedTexts.last, '气泡内完整 Prompt');
        expect(launched.last.$1.toString(), 'deepseek://');

        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      },
    );
  });
}
