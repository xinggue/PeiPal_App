import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/domain/models/llm_provider.dart';
import 'package:peipal/presentation/pages/settings/llm_providers_page.dart';
import 'package:peipal/providers/llm_providers_provider.dart';
import 'package:peipal/providers/providers.dart';

void main() {
  for (final id in ['deepseek', 'zhipu']) {
    testWidgets('$id effort fits a narrow screen and defaults to low', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = LlmProviderPresets.builtIn
          .firstWhere((p) => p.id == id)
          .copyWith(apiKey: 'test-key');
      FlutterSecureStorage.setMockInitialValues({
        'llm_providers_matrix_v1': jsonEncode([provider.toJson()]),
        'llm_active_provider_id_v1': id,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(1.3)),
              child: child!,
            ),
            home: const LlmProvidersPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(container.read(llmConfigProvider).reasoningEffort, 'low');
      final cardTitle = find.text(provider.name).last;
      await tester.ensureVisible(cardTitle);
      await tester.tap(cardTitle);
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('高级'));
      await tester.tap(find.text('高级'));
      await tester.pumpAndSettle();
      final dropdown = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(dropdown);
      await tester.pumpAndSettle();
      final bounds = tester.getRect(dropdown);
      expect(bounds.width, greaterThanOrEqualTo(300));
      expect(bounds.height, greaterThanOrEqualTo(56));
      final selected = tester.getRect(find.text('低'));
      expect(bounds.contains(selected.topLeft), isTrue);
      expect(bounds.contains(selected.bottomRight), isTrue);
      await tester.tap(dropdown);
      await tester.pumpAndSettle();
      expect(find.text('最高'), findsOneWidget);
      await tester.tap(find.text('服务商默认').last);
      await tester.pumpAndSettle();
      expect(container.read(llmConfigProvider).reasoningEffort, '');
      expect(
        container.read(llmProvidersProvider).activeProvider!.reasoningEfforts,
        {provider.selectedModel: ''},
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'advanced effort remembers each model and updates active requests',
    (tester) async {
      tester.view.physicalSize = const Size(1200, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = LlmProviderPresets.builtIn.first.copyWith(
        selectedModel: 'deepseek-v4-pro',
        apiKey: 'test-key',
      );
      FlutterSecureStorage.setMockInitialValues({
        'llm_providers_matrix_v1': jsonEncode([provider.toJson()]),
        'llm_active_provider_id_v1': 'deepseek',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: LlmProvidersPage()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text(provider.name).last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('高级'));
      await tester.pumpAndSettle();
      expect(container.read(llmConfigProvider).reasoningEffort, 'low');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('最高').last);
      await tester.pumpAndSettle();
      expect(container.read(llmConfigProvider).reasoningEffort, 'max');

      final modelField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == '选用模型名称',
      );
      await tester.enterText(modelField, 'deepseek-flash');
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('关闭').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('仅保存'));
      await tester.pumpAndSettle();
      expect(container.read(llmConfigProvider).reasoningEffort, 'none');

      await tester.enterText(modelField, 'deepseek-v4-pro');
      await tester.pumpAndSettle();
      expect(find.text('最高'), findsOneWidget);
      await tester.tap(find.text('仅保存'));
      await tester.pumpAndSettle();
      expect(container.read(llmConfigProvider).reasoningEffort, 'max');

      await tester.enterText(modelField, 'deepseek-chat');
      await tester.pumpAndSettle();
      expect(find.text('当前模型不支持推理强度设置'), findsOneWidget);
      await tester.tap(find.text('仅保存'));
      await tester.pumpAndSettle();
      expect(container.read(llmConfigProvider).reasoningEffort, '');
      expect(
        container.read(llmProvidersProvider).activeProvider!.reasoningEfforts,
        {'deepseek-v4-pro': 'max', 'deepseek-flash': 'none'},
      );
      final stored = await const FlutterSecureStorage().read(
        key: 'llm_providers_matrix_v1',
      );
      expect(jsonDecode(stored!).first['reasoningEfforts'], {
        'deepseek-v4-pro': 'max',
        'deepseek-flash': 'none',
      });
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
