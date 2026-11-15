import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/domain/models/document_parse_info.dart';
import 'package:peipal/domain/models/message.dart';
import 'package:peipal/presentation/widgets/chat/message_bubble.dart';

Widget _wrapBubble(Message message) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Padding(
            padding: const EdgeInsets.all(12),
            child: MessageBubble(message: message, ref: ref),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'parsed document renders compact OCR-style preview card and opens full details dialog on tap',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const fullText = '''
第一行摘要内容，包含检验表格：
| 项目 | 数值 |
| --- | --- |
| 血红蛋白 | 135 |
末尾结论段落，应在弹窗中完整展示。''';

      final msg = Message.document(
        patientId: 'p1',
        filePath: '/tmp/lab_report.pdf',
        fileSize: 2048,
        fileName: 'lab_report.pdf',
        extractedText: fullText,
        documentParse: const DocumentParseInfo(
          status: DocumentParseStatus.success,
          attemptId: 'a1',
          hasResult: true,
        ),
      );

      await tester.pumpWidget(_wrapBubble(msg));
      await tester.pumpAndSettle();

      expect(find.text('lab_report.pdf'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('解析内容摘要 (${fullText.length}字)'), findsOneWidget);
      expect(find.text('复制全部'), findsNothing);

      final cardFinder = find.ancestor(
        of: find.text('PDF'),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.decoration is BoxDecoration && w.padding == const EdgeInsets.all(8),
        ),
      );
      final iconBoxFinder = find.ancestor(
        of: find.text('PDF'),
        matching: find.byWidgetPredicate(
          (w) => w is Container && w.constraints?.maxWidth == 64 && w.constraints?.maxHeight == 64,
        ),
      );
      final cardRect = tester.getRect(cardFinder);
      final iconRect = tester.getRect(iconBoxFinder);
      expect(iconRect.center.dy, closeTo(cardRect.center.dy, 0.5));

      await tester.tap(find.text('lab_report.pdf'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('复制全部'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.textContaining('血红蛋白'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(Dialog),
          matching: find.textContaining('末尾结论段落'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'document bubble shows running, failed, and partial warnings cleanly',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final runningMsg = Message.document(
        patientId: 'p1',
        filePath: '/tmp/pending.docx',
        fileSize: 1024,
        fileName: 'pending.docx',
        documentParse: const DocumentParseInfo(
          status: DocumentParseStatus.running,
          attemptId: 'a2',
        ),
      );

      await tester.pumpWidget(_wrapBubble(runningMsg));
      await tester.pump();
      expect(find.text('文件解析中...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      final partialMsg = Message.document(
        patientId: 'p1',
        filePath: '/tmp/partial.pdf',
        fileSize: 4096,
        fileName: 'partial.pdf',
        extractedText: '已解析前两页文本',
        documentParse: const DocumentParseInfo(
          status: DocumentParseStatus.partial,
          attemptId: 'a3',
          hasResult: true,
          warnings: ['第 3 页识别结果不完整'],
        ),
      );

      await tester.pumpWidget(_wrapBubble(partialMsg));
      await tester.pumpAndSettle();
      expect(find.text('部分解析 (8字)'), findsOneWidget);
      expect(find.text('第 3 页识别结果不完整'), findsOneWidget);

      await tester.tap(find.text('partial.pdf'));
      await tester.pumpAndSettle();
      expect(find.text('第 3 页识别结果不完整'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );
}
