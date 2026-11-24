import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/repositories/content_template_repository.dart';
import 'package:peipal/data/repositories/message_repository.dart';
import 'package:peipal/data/repositories/template_repository.dart';
import 'package:peipal/domain/models/content_template.dart';
import 'package:peipal/domain/models/message.dart';
import 'package:peipal/domain/models/template.dart';
import 'package:peipal/presentation/pages/settings/quick_generation_settings_page.dart';
import 'package:peipal/presentation/widgets/chat/quick_generation_bar.dart';
import 'package:peipal/presentation/widgets/chat/record_generation_wizard_sheet.dart';
import 'package:peipal/providers/providers.dart';
import 'package:peipal/providers/quick_generation_presets_provider.dart';

import 'tutorial_test.dart' show MockSettingsRepo;

class _FakeTemplateRepo extends TemplateRepository {
  final List<Template> items;
  _FakeTemplateRepo(this.items);

  @override
  Future<List<Template>> getAll() async => items;
}

class _FakeContentTemplateRepo extends ContentTemplateRepository {
  final Map<String, List<ContentTemplate>> byStructure;
  _FakeContentTemplateRepo(this.byStructure);

  @override
  Future<List<ContentTemplate>> getByStructure(String structureTemplateId) async =>
      byStructure[structureTemplateId] ?? const [];
}

class _FakeMessageRepo extends MessageRepository {
  final List<Message> msgs;
  _FakeMessageRepo(this.msgs);

  @override
  Future<List<Message>> getAllChronological(String patientId) async => msgs;
}

void main() {
  final t1 = Template(
    id: 't1',
    name: '门诊病历',
    slots: const [
      TemplateSlot(key: 'cc', label: '主诉', type: SlotType.text),
      TemplateSlot(key: 'hpi', label: '现病史', type: SlotType.text),
      TemplateSlot(key: 'dx', label: '诊断', type: SlotType.text),
    ],
  );
  final t2 = Template(
    id: 't2',
    name: '入院记录',
    slots: const [
      TemplateSlot(key: 'adm', label: '入院情况', type: SlotType.text),
      TemplateSlot(key: 'plan', label: '诊疗计划', type: SlotType.text),
    ],
  );
  final ct1 = ContentTemplate(
    id: 'ct1',
    structureTemplateId: 't1',
    name: '糖尿病',
  );

  test('QuickGenerationPresetsNotifier 持久化、LRU 去重淘汰与 Pin 置顶保护', () async {
    final repo = MockSettingsRepo();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(quickGenerationPresetsProvider.notifier);
    await notifier.ensureLoaded();

    // 1. 添加 1 条并 Pin 置顶
    await notifier.addPinnedPreset(
      template: t1,
      contentTemplate: ct1,
      allMaterials: true,
      customTitle: '糖随访',
    );

    // 2. 连续记录 6 条不同的非 Pin 配置，校验非 Pin 最多保留 5 条且 Pin 永不被挤掉
    for (var i = 0; i < 6; i++) {
      final tmpl = Template(
        id: 'extra_$i',
        name: '文书_$i',
        slots: const [TemplateSlot(key: 's1', label: '字段', type: SlotType.text)],
      );
      await notifier.recordUsage(
        template: tmpl,
        contentTemplate: null,
        allMaterials: true,
        selectedSlotKeys: const {'s1'},
      );
    }

    final list = container.read(quickGenerationPresetsProvider);
    expect(list.first.isPinned, isTrue);
    expect(list.first.customTitle, '糖随访');
    expect(list.where((p) => !p.isPinned).length, 5);
    // 最早那条 extra_0 应被 LRU 淘汰
    expect(list.any((p) => p.templateId == 'extra_0'), isFalse);
    expect(list.any((p) => p.templateId == 'extra_5'), isTrue);

    // 3. 新容器从同一 SettingsRepository 重新加载，验证持久化生效
    final reloaded = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(reloaded.dispose);
    final loadedList = await reloaded
        .read(quickGenerationPresetsProvider.notifier)
        .ensureLoaded();
    expect(loadedList.length, 6);
    expect(loadedList.first.customTitle, '糖随访');
  });

  test('QuickGenerationPreset 解析兼容新字段与已删除内容模板回退', () {
    final pAll = QuickGenerationPreset.create(
      template: t1,
      contentTemplate: ContentTemplate(
        id: 'deleted_ct',
        structureTemplateId: 't1',
        name: '已删范例',
      ),
      allMaterials: false,
      selectAllSlots: true,
      selectedSlotKeys: const ['cc', 'hpi', 'dx'],
    );
    final t1WithExtra = t1.copyWith(slots: [
      ...t1.slots,
      const TemplateSlot(key: 'rx', label: '处方', type: SlotType.text),
    ]);

    final resolved = pAll.resolve(
      templates: [t1WithExtra],
      contentTemplatesByStructure: {'t1': [ct1]},
      hasPastRecords: false,
    );
    expect(resolved, isNotNull);
    expect(resolved!.contentTemplate, isNull); // 已删内容模板自动回退为无模板
    expect(resolved.allMaterials, isTrue); // 无既往记录回退为全部材料
    expect(resolved.selectedSlotKeys, {'cc', 'hpi', 'dx', 'rx'}); // 全选跟随新字段
  });

  testWidgets(
    '3 步向导：第 1 步含最近生成+设置按钮并就地展开字段，点胶囊直达第 3 步且总览干净，可回退修改',
    (tester) async {
      tester.view.physicalSize = const Size(420, 860);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = MockSettingsRepo();
      final preseeded = QuickGenerationPreset.create(
        template: t2,
        contentTemplate: null,
        allMaterials: true,
        selectAllSlots: true,
        selectedSlotKeys: const ['adm', 'plan'],
        isPinned: true,
      );
      repo.data[kRecentGenerationPresetsKey] =
          QuickGenerationPreset.encodeList([preseeded]);

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repo),
          templateRepositoryProvider.overrideWithValue(_FakeTemplateRepo([t1, t2])),
          contentTemplateRepositoryProvider.overrideWithValue(
            _FakeContentTemplateRepo({'t1': [ct1]}),
          ),
          messageRepositoryProvider.overrideWithValue(_FakeMessageRepo(const [])),
          templatesProvider.overrideWith((_) => Stream.value([t1, t2])),
          contentTemplatesProvider('t1').overrideWith((_) => Stream.value([ct1])),
          contentTemplatesProvider('t2').overrideWith((_) => Stream.value([])),
        ],
      );
      addTearDown(container.dispose);

      await container.read(quickGenerationPresetsProvider.notifier).ensureLoaded();

      GenerationWizardResult? wizardResult;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (ctx) => Center(
                  child: FilledButton(
                    onPressed: () async {
                      wizardResult = await showDialog<GenerationWizardResult>(
                        context: ctx,
                        builder: (_) =>
                            const RecordGenerationWizardSheet(patientId: 'p1'),
                      );
                    },
                    child: const Text('OPEN_WIZARD'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('OPEN_WIZARD'));
      await tester.pumpAndSettle();

      // 1. 顶部 3 步指示，向导第 1 步顶部有最近生成 + 设置按钮且无关闭按钮
      expect(find.text('第 1 / 3 步'), findsOneWidget);
      expect(find.text('最近生成'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('入院记录 · 无模板'), findsOneWidget);
      expect(find.text('点选直达最后一步'), findsNothing);

      // 2. 第 1 步默认选中门诊病历并展开其字段，支持全选/全不选
      expect(find.text('主诉'), findsOneWidget);
      expect(find.text('现病史'), findsOneWidget);
      expect(find.text('诊断'), findsOneWidget);
      expect(find.text('入院情况'), findsNothing);

      await tester.tap(find.text('全不选'));
      await tester.pumpAndSettle();
      expect(find.text('3 个字段（已选 0/3）'), findsOneWidget);
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('3 个字段（已选 3/3）'), findsOneWidget);

      // 3. 点击快捷生成胶囊「入院记录 · 无模板」直接跳到第 3 步并填好总览
      await tester.tap(find.text('入院记录 · 无模板'));
      await tester.pumpAndSettle();

      expect(find.text('第 3 / 3 步'), findsOneWidget);
      expect(find.text('生成总览'), findsOneWidget);
      expect(find.text('点顶部站点可回退修改'), findsNothing);
      expect(find.text('入院记录（2/2 个字段）'), findsOneWidget);
      expect(find.text('不使用内容模板'), findsOneWidget);

      // 4. 点击「上一步」可以回到第 2 步、再回到第 1 步重新选择
      await tester.tap(find.text('上一步'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 / 3 步'), findsOneWidget);

      await tester.tap(find.text('类型与字段'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 / 3 步'), findsOneWidget);

      // 5. 切回第 3 步并点「开始生成」返回完整配置
      await tester.tap(find.text('生成要求'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开始生成 (2)'));
      await tester.pumpAndSettle();

      expect(wizardResult, isNotNull);
      expect(wizardResult!.template.id, 't2');
      expect(wizardResult!.selectedSlotKeys, {'adm', 'plan'});
    },
  );

  testWidgets(
    'QuickGenerationBar 显示关闭按钮且无废话；QuickGenerationSettingsPage 可管理开关与 Pin',
    (tester) async {
      final repo = MockSettingsRepo();
      final preset = QuickGenerationPreset.create(
        template: t1,
        contentTemplate: ct1,
        allMaterials: true,
        selectAllSlots: true,
        selectedSlotKeys: const ['cc', 'hpi', 'dx'],
      );
      repo.data[kRecentGenerationPresetsKey] =
          QuickGenerationPreset.encodeList([preset]);

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repo),
          templatesProvider.overrideWith((_) => Stream.value([t1, t2])),
          contentTemplatesProvider('t1').overrideWith((_) => Stream.value([ct1])),
        ],
      );
      addTearDown(container.dispose);

      await container.read(quickGenerationPresetsProvider.notifier).ensureLoaded();
      await container.read(chatQuickPresetsEnabledProvider.notifier).ensureLoaded();

      var closed = false;
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: QuickGenerationBar(
                onClose: () => closed = true,
                onSelectPreset: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('最近生成'), findsOneWidget);
      expect(find.text('门诊病历 · 糖尿病'), findsOneWidget);
      expect(find.text('点选直达最后一步'), findsNothing);

      // 验证「最近生成」、胶囊与关闭按钮在同一单行内且整体紧凑
      final labelCenterY = tester.getCenter(find.text('最近生成')).dy;
      final pillCenterY = tester.getCenter(find.text('门诊病历 · 糖尿病')).dy;
      final closeCenterY = tester.getCenter(find.byIcon(Icons.close)).dy;
      expect((labelCenterY - pillCenterY).abs(), lessThan(4));
      expect((closeCenterY - pillCenterY).abs(), lessThan(4));
      expect(tester.getSize(find.byType(QuickGenerationBar)).height,
          lessThanOrEqualTo(46));

      await tester.tap(find.byIcon(Icons.close));
      expect(closed, isTrue);

      // 验证专属设置页文案（文书快捷生成管理 / 置顶管理 / 暂无置顶，无“套餐”与闪电图标）、开关和 Pin 切换
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: QuickGenerationSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('文书快捷生成管理'), findsOneWidget);
      expect(find.byIcon(Icons.bolt_outlined), findsNothing);
      expect(find.text('输入框上方显示最近生成'), findsOneWidget);
      expect(find.text('置顶管理'), findsOneWidget);
      expect(find.text('暂无置顶'), findsOneWidget);
      expect(find.textContaining('套餐'), findsNothing);
      expect(find.text('门诊病历 · 糖尿病'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.push_pin_outlined));
      await tester.pumpAndSettle();
      expect(find.text('暂无置顶'), findsNothing);
      expect(find.text('暂无最近生成记录'), findsOneWidget);

      await tester.tap(find.text('输入框上方显示最近生成'));
      await tester.pumpAndSettle();
      expect(container.read(chatQuickPresetsEnabledProvider), isFalse);
      expect(repo.data[kChatQuickPresetsEnabledKey], 'false');
    },
  );

  testWidgets(
    '3 步向导顶部地铁站标签在大字体 (1.6x) 与窄屏 (360px) 下完整显示不截断也不溢出',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = MockSettingsRepo();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(repo),
          templateRepositoryProvider.overrideWithValue(_FakeTemplateRepo([t1, t2])),
          contentTemplateRepositoryProvider
              .overrideWithValue(_FakeContentTemplateRepo({'t1': [ct1]})),
          messageRepositoryProvider.overrideWithValue(_FakeMessageRepo(const [])),
          templatesProvider.overrideWith((_) => Stream.value([t1, t2])),
          contentTemplatesProvider('t1').overrideWith((_) => Stream.value([ct1])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(1.6)),
            child: MaterialApp(
              home: Scaffold(
                body: RecordGenerationWizardSheet(patientId: 'p1'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final stepLabelRect = tester.getRect(find.text('类型与字段').last);
      final fittedBoxRect = tester.getRect(
        find.ancestor(
          of: find.text('类型与字段').last,
          matching: find.byType(FittedBox),
        ),
      );
      expect(stepLabelRect.width, greaterThan(0));
      expect(fittedBoxRect.width, greaterThanOrEqualTo(stepLabelRect.width - 1));
      expect(find.text('内容模板'), findsOneWidget);
      expect(find.text('生成要求'), findsOneWidget);
    },
  );
}
