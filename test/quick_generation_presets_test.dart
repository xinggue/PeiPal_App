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

  test('同文书同模板但不同字段应区分展示字段数量', () {
    final full = QuickGenerationPreset.create(
      template: t1,
      contentTemplate: ct1,
      allMaterials: true,
      selectAllSlots: true,
      selectedSlotKeys: const ['cc', 'hpi', 'dx'],
    );
    final partial = QuickGenerationPreset.create(
      template: t1,
      contentTemplate: ct1,
      allMaterials: true,
      selectAllSlots: false,
      selectedSlotKeys: const ['cc', 'dx'],
    );

    expect(
      full.displayTitle(liveTemplate: t1, liveContentTemplate: ct1),
      '门诊病历 · 糖尿病 · 全3字段',
    );
    expect(
      partial.displayTitle(liveTemplate: t1, liveContentTemplate: ct1),
      '门诊病历 · 糖尿病 · 2/3字段',
    );
  });

  test('pinFromRecent 会在置顶区多出一份且保留最近区，删除置顶不影响最近区', () async {
    final repo = MockSettingsRepo();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(quickGenerationPresetsProvider.notifier);
    await notifier.ensureLoaded();

    await notifier.recordUsage(
      template: t1,
      contentTemplate: ct1,
      allMaterials: true,
      selectedSlotKeys: const {'cc', 'hpi', 'dx'},
    );

    final recentItem = container.read(quickGenerationPresetsProvider).single;
    expect(recentItem.isPinned, isFalse);

    // 收藏/Pin 后：置顶区多 1 份，最近区仍保留原记录
    expect(await notifier.pinFromRecent(recentItem.id), isTrue);
    final afterPin = container.read(quickGenerationPresetsProvider);
    expect(afterPin.where((p) => p.isPinned).length, 1);
    expect(afterPin.where((p) => !p.isPinned).length, 1);

    // 重复点同一个配置的 Pin 不重复生成两份
    expect(await notifier.pinFromRecent(recentItem.id), isFalse);

    // 删除置顶区的副本：只删上面那份，下面最近记录依然保留
    final pinnedItem = afterPin.firstWhere((p) => p.isPinned);
    await notifier.deletePreset(pinnedItem.id);
    final afterDeletePinned = container.read(quickGenerationPresetsProvider);
    expect(afterDeletePinned.where((p) => p.isPinned), isEmpty);
    expect(afterDeletePinned.where((p) => !p.isPinned).length, 1);
  });

  test('QuickGenerationPresetsNotifier 持久化、LRU 去重淘汰与 Pin 置顶保护', () async {
    final repo = MockSettingsRepo();
    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final notifier = container.read(quickGenerationPresetsProvider.notifier);
    await notifier.ensureLoaded();

    await notifier.addPinnedPreset(
      template: t1,
      contentTemplate: ct1,
      allMaterials: true,
      customTitle: '糖随访',
    );

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
    expect(list.any((p) => p.templateId == 'extra_0'), isFalse);
    expect(list.any((p) => p.templateId == 'extra_5'), isTrue);

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
    expect(resolved!.contentTemplate, isNull);
    expect(resolved.allMaterials, isTrue);
    expect(resolved.selectedSlotKeys, {'cc', 'hpi', 'dx', 'rx'});
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

      expect(find.text('第 1 / 3 步'), findsOneWidget);
      expect(find.text('最近生成'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(find.text('入院记录'), findsNWidgets(2)); // 1 个在快捷胶囊，1 个在下方模板列表
      expect(find.text('无模板 · 全2字段'), findsOneWidget);
      expect(find.text('点选直达最后一步'), findsNothing);
      expect(find.byIcon(Icons.push_pin), findsNothing);

      // 向导内两行布局：标题+设置在上，胶囊在下一行
      final wizardHeaderY = tester.getCenter(find.text('最近生成')).dy;
      final wizardSettingsY = tester.getCenter(find.text('设置')).dy;
      final wizardCapsuleY = tester.getCenter(find.text('无模板 · 全2字段')).dy;
      expect((wizardHeaderY - wizardSettingsY).abs(), lessThan(6));
      expect(wizardCapsuleY, greaterThan(wizardHeaderY + 12));

      // 初始不默认选中任何文书类型，所有卡片折叠
      expect(find.text('主诉'), findsNothing);
      expect(find.text('现病史'), findsNothing);
      expect(find.text('诊断'), findsNothing);
      expect(find.text('入院情况'), findsNothing);

      // 点击「门诊病历」展开字段勾选
      await tester.tap(find.text('门诊病历'));
      await tester.pumpAndSettle();
      expect(find.text('主诉'), findsOneWidget);
      expect(find.text('现病史'), findsOneWidget);
      expect(find.text('诊断'), findsOneWidget);

      await tester.tap(find.text('全不选'));
      await tester.pumpAndSettle();
      expect(find.text('3 个字段（已选 0/3）'), findsOneWidget);
      await tester.tap(find.text('全选'));
      await tester.pumpAndSettle();
      expect(find.text('3 个字段（已选 3/3）'), findsOneWidget);

      // 再次点击「门诊病历」取消选中并收起
      await tester.tap(find.text('门诊病历'));
      await tester.pumpAndSettle();
      expect(find.text('主诉'), findsNothing);

      // 点快捷胶囊直达第 3 步
      await tester.tap(find.text('无模板 · 全2字段'));
      await tester.pumpAndSettle();

      expect(find.text('第 3 / 3 步'), findsOneWidget);
      expect(find.text('生成总览'), findsOneWidget);
      expect(find.text('点顶部站点可回退修改'), findsNothing);
      expect(find.text('入院记录（2/2 个字段）'), findsOneWidget);
      expect(find.text('不使用内容模板'), findsOneWidget);

      await tester.tap(find.text('上一步'));
      await tester.pumpAndSettle();
      expect(find.text('第 2 / 3 步'), findsOneWidget);

      await tester.tap(find.text('类型与字段'));
      await tester.pumpAndSettle();
      expect(find.text('第 1 / 3 步'), findsOneWidget);

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
    'QuickGenerationBar 单行显示字段数量；设置页置顶区仅有排序与删除，最近区仅有收藏按钮且 Pin 保留最近记录',
    (tester) async {
      final repo = MockSettingsRepo();
      final preset = QuickGenerationPreset.create(
        template: t1,
        contentTemplate: ct1,
        allMaterials: true,
        selectAllSlots: false,
        selectedSlotKeys: const ['cc', 'dx'],
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
      expect(find.text('门诊病历'), findsOneWidget);
      expect(find.text('糖尿病 · 2/3字段'), findsOneWidget);
      expect(find.byIcon(Icons.push_pin), findsNothing);
      expect(find.text('点选直达最后一步'), findsNothing);

      // 胶囊内部上下两行展示：文书名在上、模板与字段数在下
      final capsuleTitleY = tester.getCenter(find.text('门诊病历')).dy;
      final capsuleSubY = tester.getCenter(find.text('糖尿病 · 2/3字段')).dy;
      expect(capsuleTitleY, lessThan(capsuleSubY));

      final labelCenterY = tester.getCenter(find.text('最近生成')).dy;
      final capsuleCenterY = (capsuleTitleY + capsuleSubY) / 2;
      final closeCenterY = tester.getCenter(find.byIcon(Icons.close)).dy;
      expect((labelCenterY - capsuleCenterY).abs(), lessThan(4));
      expect((closeCenterY - capsuleCenterY).abs(), lessThan(4));
      final barHeight = tester.getSize(find.byType(QuickGenerationBar)).height;
      expect(barHeight, greaterThanOrEqualTo(46));
      expect(barHeight, lessThanOrEqualTo(66));

      await tester.tap(find.byIcon(Icons.close));
      expect(closed, isTrue);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: QuickGenerationSettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('文书快捷生成管理'), findsOneWidget);
      expect(find.byIcon(Icons.bolt_outlined), findsNothing);
      expect(find.text('置顶管理'), findsOneWidget);
      expect(find.text('暂无置顶'), findsOneWidget);
      expect(find.text('门诊病历 · 糖尿病 · 2/3字段'), findsOneWidget);

      // 最近区只有 1 个收藏/Pin 按钮，点 Pin 后置顶区多出一份且最近区仍在
      await tester.tap(find.byIcon(Icons.push_pin_outlined));
      await tester.pumpAndSettle();
      expect(find.text('暂无置顶'), findsNothing);
      expect(find.text('门诊病历 · 糖尿病 · 2/3字段'), findsNWidgets(2));
      expect(find.text('暂无最近生成记录'), findsNothing);

      // 置顶区有排序(↑/↓)和删除按钮，无独立重命名按钮；删除后只删置顶区那份
      expect(find.byIcon(Icons.keyboard_arrow_up), findsOneWidget);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('暂无置顶'), findsOneWidget);
      expect(find.text('门诊病历 · 糖尿病 · 2/3字段'), findsOneWidget);

      await tester.tap(find.text('输入框上方显示最近生成'));
      await tester.pumpAndSettle();
      expect(container.read(chatQuickPresetsEnabledProvider), isFalse);
      expect(repo.data[kChatQuickPresetsEnabledKey], 'false');

      // 消耗 AppToast 的 2.2s 自动消失计时器，避免结束时 pending timer 断言失败
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
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
