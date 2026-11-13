import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/domain/models/template.dart';
import 'package:peipal/domain/models/typing_profile.dart';
import 'package:peipal/domain/models/typing_action_block.dart';
import 'package:peipal/presentation/pages/templates/template_editor_page.dart';

void main() {
  testWidgets(
    'preview does not invent a pipeline and selects the requested profile',
    (tester) async {
      final structure = Template(
        name: '检查记录',
        slots: const [
          TemplateSlot(key: 'result', label: '结果', type: SlotType.text),
        ],
        typingProfiles: [
          TypingProfile(
            id: 'first',
            name: '方案一',
            blocks: [KeyComboBlock(combo: '{TAB}')],
          ),
          TypingProfile(
            id: 'second',
            name: '方案二',
            blocks: [KeyComboBlock(combo: '{ENTER}')],
          ),
        ],
      );
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: TemplateEditorPage(
              previewTemplate: structure,
              initialTabIndex: 2,
              initialProfileId: 'second',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('方案二'), findsOneWidget);
      expect(find.textContaining('{ENTER}'), findsWidgets);
      expect(find.text('保存'), findsNothing);
      expect(structure.pipeline.nodes, isEmpty);
      await tester.tap(find.text('解析流程'));
      await tester.pumpAndSettle();
      expect(find.text('暂无节点'), findsOneWidget);
      expect(find.text('添加节点'), findsNothing);
      expect(structure.pipeline.nodes, isEmpty);
    },
  );
}
