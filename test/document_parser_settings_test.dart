import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/api/document_parser_api.dart';
import 'package:peipal/domain/models/document_parser_provider.dart';
import 'package:peipal/presentation/pages/settings/document_parser_settings_page.dart';
import 'package:peipal/providers/document_parser_provider.dart';

class _FakeDocumentParserApi extends DocumentParserApi {
  DocumentParserProviderConfig? lastTested;

  @override
  Future<String> testConnection(DocumentParserProviderConfig config) async {
    lastTested = config;
    return '连通正常 (12ms)';
  }
}

void main() {
  testWidgets(
    'document services start unselected, save independently, and test active connection at mobile width',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      FlutterSecureStorage.setMockInitialValues({});
      final fakeApi = _FakeDocumentParserApi();
      final container = ProviderContainer(
        overrides: [documentParserApiProvider.overrideWithValue(fakeApi)],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: DocumentParserSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('未配置'), findsOneWidget);
      expect(find.text('当前选用解析服务'), findsOneWidget);
      expect(find.text('测试当前连接'), findsOneWidget);

      await tester.tap(find.text('智谱'));
      await tester.pumpAndSettle();
      expect(find.text('Prime-sync · 按页计费'), findsOneWidget);
      await tester.enterText(
        find.byWidgetPredicate(
          (w) => w is TextField && w.decoration?.labelText == 'API Key',
        ),
        'test-key',
      );
      await tester.ensureVisible(find.text('确认选用该服务'));
      await tester.tap(find.text('确认选用该服务'));
      await tester.pumpAndSettle();
      final settings = container.read(documentParserProvider).requireValue;
      expect(settings.activeProviderId, 'zhipu');
      expect(settings.activeProvider!.apiKey, 'test-key');
      expect(settings.providers.first.apiKey, isEmpty);
      expect(find.text('已就绪'), findsOneWidget);
      expect(find.text('已选用 (点击更新)'), findsOneWidget);

      await tester.ensureVisible(find.text('测试当前连接'));
      await tester.tap(find.text('测试当前连接'));
      await tester.pumpAndSettle();
      expect(fakeApi.lastTested?.id, 'zhipu');
      expect(find.text('状态: 连通正常 (12ms)'), findsOneWidget);

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
