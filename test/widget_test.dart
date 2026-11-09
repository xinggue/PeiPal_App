import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/presentation/widgets/chat/ocr_text_details_dialog.dart';

void main() {
  testWidgets('OCR details dialog renders tables and all content after tables cleanly',
      (WidgetTester tester) async {
    const sampleOcr = '''
前置段落：患者入院血常规与生化检验报告如下：
| 项目 | 结果 | 参考值 |
| 白细胞 | 12.5 ↑ | 4.0-10.0 |
| 血红蛋白 | 110 | 120-160 | 多出来的一列 |
| 血小板 | 210 |
中间段落：上面是第一个 Markdown 表格，下面是第二个 HTML 表格：
<html><body><table><tr><th>指标</th><th>数值</th></tr><tr><td>肌酐</td><td>98 μmol/L</td></tr></table></body></html>
尾部段落：这是所有表格之后的结论文字，必须完整显示且可滚动到底部！
''';

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: ElevatedButton(
              onPressed: () => showOcrTextDetailsDialog(
                context: context,
                title: '测试OCR详情',
                text: sampleOcr,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.textContaining('前置段落'), findsOneWidget);
    expect(find.textContaining('白细胞'), findsOneWidget);
    expect(find.textContaining('中间段落'), findsOneWidget);
    expect(find.textContaining('肌酐'), findsOneWidget);
    expect(find.textContaining('尾部段落'), findsOneWidget);
  });
}
