import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/presentation/widgets/engine_c/engine_c_sheets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ExportPreviewPage', () {
    test('wechatWeightedLength counts ASCII as 1 and non-ASCII as 2', () {
      expect(ExportPreviewPage.wechatWeightedLength('abc123'), 6);
      expect(ExportPreviewPage.wechatWeightedLength('中文a'), 5);
    });

    test('compactForCopy removes indentation from valid JSON', () {
      const pretty = '{\n  "a": 1,\n  "b": "中文"\n}';
      expect(ExportPreviewPage.compactForCopy(pretty), '{"a":1,"b":"中文"}');
      expect(ExportPreviewPage.compactForCopy('not json'), 'not json');
    });

    testWidgets(
      'keeps indented preview while copying compact JSON when within WeChat limit',
      (tester) async {
        String? copiedClipboardText;
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            final args = call.arguments as Map<dynamic, dynamic>;
            copiedClipboardText = args['text'] as String?;
          }
          return null;
        });
        addTearDown(() {
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
        });

        final payload = {
          'engine': 'medhistory_engine_c',
          'slots': [
            for (var i = 0; i < 20; i++)
              {'key': 'slot_$i', 'label': '字段$i', 'guidance': '测试规则描述$i'},
          ],
        };
        final prettyText = const JsonEncoder.withIndent('  ').convert(payload);
        final compactText = jsonEncode(payload);
        expect(prettyText.length, greaterThan(1000));
        expect(
          ExportPreviewPage.wechatWeightedLength(compactText),
          lessThanOrEqualTo(ExportPreviewPage.copyWeightedLimit),
        );

        await tester.pumpWidget(
          MaterialApp(
            home: ExportPreviewPage(
              text: prettyText,
              suggestedFilePrefix: '模板配置_测试',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('共 ${compactText.length} 字'), findsOneWidget);
        expect(find.text('内容长度超出上限，请使用分享发送文件'), findsNothing);
        expect(find.text(prettyText), findsOneWidget);

        final copyButton = find.widgetWithIcon(OutlinedButton, Icons.copy);
        expect(copyButton, findsOneWidget);
        expect(tester.widget<OutlinedButton>(copyButton).onPressed, isNotNull);

        await tester.tap(copyButton);
        await tester.pump();
        expect(copiedClipboardText, compactText);

        // Allow AppToast auto-dismiss timer (2.2s) to finish before teardown.
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'disables copy and shows limit hint when compact JSON exceeds WeChat limit',
      (tester) async {
        final payload = {
          'engine': 'medhistory_engine_c',
          'content': List.filled(2000, '汉').join(),
        };
        final prettyText = const JsonEncoder.withIndent('  ').convert(payload);

        await tester.pumpWidget(
          MaterialApp(
            home: ExportPreviewPage(
              text: prettyText,
              suggestedFilePrefix: '模板配置_超长',
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('内容长度超出上限，请使用分享发送文件'), findsOneWidget);
        final copyButton = find.widgetWithIcon(OutlinedButton, Icons.copy);
        expect(tester.widget<OutlinedButton>(copyButton).onPressed, isNull);
      },
    );
  });
}
