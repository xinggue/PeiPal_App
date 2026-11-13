import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/engine_c/engine_c_models.dart';
import 'package:peipal/data/services/hub/hub_service.dart';
import 'package:peipal/domain/models/content_template.dart';
import 'package:peipal/domain/models/template.dart';
import 'package:peipal/domain/models/typing_action_block.dart';
import 'package:peipal/domain/models/typing_profile.dart';
import 'package:peipal/presentation/pages/hub/hub_components.dart';
import 'package:peipal/presentation/pages/hub/hub_management.dart';
import 'package:peipal/presentation/widgets/engine_c/engine_c_sheets.dart';

EngineCBundleEnvelope fixture() {
  final structure = Template(
    id: 's',
    name: '巡检记录',
    slots: const [
      TemplateSlot(
        key: 'result',
        label: '检查结果',
        type: SlotType.dropdown,
        options: ['正常', '需复查'],
        required: true,
      ),
    ],
  );
  return EngineCBundleEnvelope(
    exportedAt: DateTime(2026),
    units: [
      StructureGroundedUnit(
        structure: structure,
        hasPipeline: false,
        contentTemplates: [
          ContentTemplate(
            id: 'c',
            structureTemplateId: 's',
            name: '日常检查',
            globalGuidance: '按实际检查情况填写',
            fullExample: '设备运行正常。',
            slots: {
              'result': SlotContent(examples: ['设备无异常'], guidance: '注明异常位置'),
            },
          ),
        ],
        typingProfiles: [
          TypingProfile(
            id: 'p',
            name: '桌面系统',
            blocks: [
              FieldInputBlock(fieldKey: 'result', postKeys: ['{TAB}']),
              KeyComboBlock(combo: '{ENTER}'),
            ],
          ),
        ],
      ),
    ],
  );
}

HubCardItem item(HubItemSubtype subtype) => HubCardItem(
  listing: HubListing.fromJson({
    'id': 'entry',
    'kind': subtype.name,
    'institution': '海港设备管理中心',
    'is_mine': true,
    'summary': {
      'structure': {
        'slotLabels': ['检查结果', '处理意见'],
        'slotCount': 2,
      },
    },
  }),
  subtype: subtype,
  subId: 's',
  subName: subtype == HubItemSubtype.structure ? '巡检记录' : '日常检查',
  structureName: '巡检记录',
  formattedTitle: '',
  primaryDetail: '检查结果、处理意见',
  secondaryDetail: '用于设备日常巡检。',
);

void main() {
  testWidgets('institution precedes document and child names on narrow cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 860);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final type in [HubItemSubtype.structure, HubItemSubtype.content]) {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 231,
                  child: MediaQuery(
                    data: const MediaQueryData(
                      textScaler: TextScaler.linear(1.3),
                    ),
                    child: HubListingCard(
                      item: item(type),
                      onTap: () {},
                      trailing: const Icon(Icons.more_horiz),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final institution = find.text('海港设备管理中心的');
      final title = find.text(
        type == HubItemSubtype.structure ? '巡检记录' : '日常检查 内容模板',
      );
      expect(
        tester.getTopLeft(institution).dy,
        lessThan(tester.getTopLeft(title).dy),
      );
      if (type == HubItemSubtype.structure) {
        expect(find.text('含2个字段：检查结果、处理意见'), findsOneWidget);
        expect(find.text('巡检记录 文书类型'), findsNothing);
      } else {
        expect(
          tester.getTopLeft(find.text('巡检记录的')).dy,
          lessThan(tester.getTopLeft(title).dy),
        );
      }
    }
  });

  testWidgets(
    'fields, examples and typing actions are visible without opening editors',
    (tester) async {
      for (final type in [
        HubItemSubtype.structure,
        HubItemSubtype.content,
        HubItemSubtype.typing,
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: HubContentPreview(
                  envelope: fixture(),
                  subtype: type,
                  targetId: type == HubItemSubtype.content ? 'c' : 'p',
                ),
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
        switch (type) {
          case HubItemSubtype.structure:
            expect(find.text('检查结果'), findsOneWidget);
            expect(find.text('正常、需复查'), findsNothing);
          case HubItemSubtype.content:
            expect(find.text('设备运行正常。'), findsOneWidget);
            expect(find.text('设备无异常'), findsOneWidget);
            expect(find.text('注明异常位置'), findsOneWidget);
          case HubItemSubtype.typing:
            expect(find.text('1. 录入检查结果'), findsOneWidget);
            expect(find.text('输入后：{TAB}'), findsOneWidget);
            expect(find.text('2. {ENTER}'), findsOneWidget);
          default:
            break;
        }
      }
    },
  );

  testWidgets('missing content never shows a sibling template', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HubContentPreview(
            envelope: fixture(),
            subtype: HubItemSubtype.content,
            targetId: 'missing',
          ),
        ),
      ),
    );
    expect(find.text('所选内容已更新，请刷新后重试'), findsOneWidget);
    expect(find.text('设备无异常'), findsNothing);
  });

  testWidgets(
    'delete defaults to one publication and cascade requires choosing checkbox',
    (tester) async {
      for (final cascade in [false, true]) {
        Object? result = 'pending';
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    result = await showDialog<bool>(
                      context: context,
                      builder: (_) => const HubDeletePublicationDialog(
                        name: '巡检记录',
                        allowOwnChildren: true,
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(
          tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
          false,
        );
        if (cascade) {
          await tester.tap(find.byType(CheckboxListTile));
          await tester.pumpAndSettle();
        }
        await tester.tap(find.text('删除'));
        await tester.pumpAndSettle();
        expect(result, cascade);
      }
    },
  );

  testWidgets(
    'online import shows content and long notes inside scrollable sheet on narrow screens',
    (tester) async {
      tester.view.physicalSize = const Size(320, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () => showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    builder: (_) => EngineCImportSheet(
                      title: '导入 · 设备管理日常检查内容模板',
                      readme: List.filled(50, '核对设备后填写。').join('\n'),
                      preview: HubContentPreview(
                        envelope: fixture(),
                        subtype: HubItemSubtype.content,
                        targetId: 'c',
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('设备运行正常。'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.text('选择配置文件'), findsNothing);
      expect(find.text('确认导入'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
