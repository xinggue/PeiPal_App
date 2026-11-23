import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peipal/data/repositories/template_repository.dart';
import 'package:peipal/domain/models/content_template.dart';
import 'package:peipal/domain/models/template.dart';
import 'package:peipal/presentation/pages/templates/content_template_list_page.dart';
import 'package:peipal/presentation/pages/templates/docs_hub_page.dart';
import 'package:peipal/providers/providers.dart';

import 'tutorial_test.dart' show MockSettingsRepo;

class _FakeTemplateRepo extends TemplateRepository {
  final List<Template> inserted = [];

  @override
  Future<void> insert(Template template) async {
    inserted.add(template);
  }
}

void main() {
  testWidgets(
    'DocsHubPage shows 文书一览 (expand/collapse all, 3-dot menu with 另存副本, slot-only count, 内容模板： prefix) above 文书管理 portals',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final t1 = Template(
        id: 't1',
        name: '门诊病历',
        slots: const [
          TemplateSlot(key: 'cc', label: '主诉', type: SlotType.text),
          TemplateSlot(key: 'dx', label: '诊断', type: SlotType.text),
        ],
      );
      final t2 = Template(
        id: 't2',
        name: '入院记录',
        slots: const [
          TemplateSlot(key: 'hpi', label: '现病史', type: SlotType.text),
        ],
      );

      final ct1 = ContentTemplate(
        id: 'ct1',
        structureTemplateId: 't1',
        name: '糖尿病',
        slots: {'cc': const SlotContent(examples: ['口渴多饮'])},
      );

      final router = GoRouter(
        routes: [
          GoRoute(path: '/', builder: (_, _) => const DocsHubPage()),
          GoRoute(
            path: '/templates/new',
            builder: (_, _) => const Scaffold(body: Text('TEMPLATE_NEW')),
          ),
          GoRoute(
            path: '/templates/:id/edit',
            builder: (_, s) =>
                Scaffold(body: Text('TEMPLATE_EDIT:${s.pathParameters['id']}')),
          ),
          GoRoute(
            path: '/templates/:id/content/new',
            builder: (_, s) =>
                Scaffold(body: Text('CONTENT_NEW:${s.pathParameters['id']}')),
          ),
          GoRoute(
            path: '/templates/:sid/content/:cid/edit',
            builder: (_, s) => Scaffold(
              body: Text(
                'CONTENT_EDIT:${s.pathParameters['sid']}:${s.pathParameters['cid']}',
              ),
            ),
          ),
          GoRoute(
            path: '/templates',
            builder: (_, _) => const Scaffold(body: Text('TEMPLATES_LIST')),
          ),
          GoRoute(
            path: '/content-templates',
            builder: (_, _) => const Scaffold(body: Text('CONTENT_LIST')),
          ),
          GoRoute(
            path: '/diagnoses',
            builder: (_, _) => const Scaffold(body: Text('DIAGNOSES_PAGE')),
          ),
          GoRoute(
            path: '/hub',
            builder: (_, _) => const Scaffold(body: Text('HUB_PAGE')),
          ),
          GoRoute(
            path: '/typing-presets',
            builder: (_, _) => const Scaffold(body: Text('TYPING_PRESETS')),
          ),
          GoRoute(
            path: '/settings/backup',
            builder: (_, _) => const Scaffold(body: Text('BACKUP_PAGE')),
          ),
        ],
      );

      final fakeRepo = _FakeTemplateRepo();
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(MockSettingsRepo()),
          templateRepositoryProvider.overrideWithValue(fakeRepo),
          templatesProvider.overrideWith((_) => Stream.value([t1, t2])),
          contentTemplatesProvider('t1').overrideWith((_) => Stream.value([ct1])),
          contentTemplatesProvider('t2').overrideWith((_) => Stream.value([])),
          favoriteDiagnosesProvider.overrideWith((_) async => []),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 顶部操作为「新建文书」，上下半区「文书一览」与「文书管理」分区标题清晰，顺序正确
      expect(find.text('新建文书'), findsOneWidget);
      expect(find.text('新建'), findsNothing);
      expect(find.text('文书一览'), findsOneWidget);
      expect(find.text('文书管理'), findsOneWidget);
      final overviewY = tester.getTopLeft(find.text('文书一览')).dy;
      final docY = tester.getTopLeft(find.text('门诊病历')).dy;
      final manageY = tester.getTopLeft(find.text('文书管理')).dy;
      final portalY = tester.getTopLeft(find.text('文书类型')).dy;
      expect(overviewY, lessThan(docY));
      expect(docY, lessThan(manageY));
      expect(manageY, lessThan(portalY));

      // 2. 文书类型小字仅显示字段数量，不显示输入方案数；内容模板带「内容模板：」前缀且无已填比例
      expect(find.text('2 个字段'), findsOneWidget);
      expect(find.text('1 个字段'), findsOneWidget);
      expect(find.textContaining('套输入'), findsNothing);
      expect(find.text('内容模板：糖尿病'), findsOneWidget);
      expect(find.text('1/2'), findsNothing);
      expect(find.text('新建内容模板'), findsOneWidget);

      // 3. 每张文书类型只有 1 个三点菜单按钮（没有加号/箭头双按钮），且与内容模板右箭头、文书管理右箭头水平居中对齐
      expect(find.byIcon(Icons.more_vert), findsNWidgets(2));
      expect(find.byIcon(Icons.add_circle_outline), findsNothing);
      final moreCenterX = tester.getCenter(find.byIcon(Icons.more_vert).first).dx;
      final chevrons = find.byIcon(Icons.chevron_right_rounded);
      final subChevronX = tester.getCenter(chevrons.at(0)).dx;
      final portalChevronX = tester.getCenter(chevrons.at(1)).dx;
      expect(subChevronX, moreCenterX);
      expect(portalChevronX, moreCenterX);

      // 4. 一键全部折叠 / 全部展开
      expect(find.text('全部折叠'), findsOneWidget);
      await tester.tap(find.text('全部折叠'));
      await tester.pumpAndSettle();
      expect(find.text('内容模板：糖尿病'), findsNothing);
      expect(find.text('全部展开'), findsOneWidget);

      await tester.tap(find.text('全部展开'));
      await tester.pumpAndSettle();
      expect(find.text('内容模板：糖尿病'), findsOneWidget);
      expect(find.text('全部折叠'), findsOneWidget);

      // 5. 三点菜单复用底部菜单并执行「另存副本」
      await tester.tap(find.byIcon(Icons.more_vert).first);
      await tester.pumpAndSettle();
      expect(find.text('另存副本'), findsOneWidget);
      expect(find.text('新建内容模板（基于该结构）'), findsOneWidget);
      expect(find.text('删除文书类型'), findsOneWidget);

      await tester.tap(find.text('另存副本'));
      await tester.pumpAndSettle();
      expect(find.text('另存为新文书类型'), findsOneWidget);
      await tester.tap(find.text('另存'));
      await tester.pumpAndSettle();
      expect(fakeRepo.inserted.length, 1);
      expect(fakeRepo.inserted.single.id, isNot(t1.id));
      expect(fakeRepo.inserted.single.name, '门诊病历（副本）');
      expect(fakeRepo.inserted.single.slots.length, 2);

      // 6. 去掉废话副标题，保留全部 6 个入口
      expect(find.text('字段定义、解析流程与打字方案'), findsNothing);
      expect(find.text('档案袋式范例库与各字段写作示范'), findsNothing);
      expect(find.text('文书类型'), findsOneWidget);
      expect(find.text('内容模板'), findsOneWidget);
      expect(find.text('标准词条库'), findsOneWidget);
      expect(find.text('在线模板广场'), findsOneWidget);
      expect(find.text('快捷动作预设'), findsOneWidget);
      expect(find.text('导入与导出中心'), findsOneWidget);

      // 7. 点击下属内容模板直接进入编辑
      await tester.tap(find.text('内容模板：糖尿病'));
      await tester.pumpAndSettle();
      expect(find.text('CONTENT_EDIT:t1:ct1'), findsOneWidget);

      // 8. 返回后点击文书类型进入结构编辑
      router.pop();
      await tester.pumpAndSettle();
      await tester.tap(find.text('门诊病历'));
      await tester.pumpAndSettle();
      expect(find.text('TEMPLATE_EDIT:t1'), findsOneWidget);
    },
  );

  testWidgets(
    'ContentTemplateListPage omits filledSlotCount subtitle fluff under each content template',
    (tester) async {
      final t1 = Template(
        id: 't1',
        name: '门诊病历',
        slots: const [
          TemplateSlot(key: 'cc', label: '主诉', type: SlotType.text),
          TemplateSlot(key: 'dx', label: '诊断', type: SlotType.text),
        ],
      );
      final ct1 = ContentTemplate(
        id: 'ct1',
        structureTemplateId: 't1',
        name: '糖尿病',
        slots: {'cc': const SlotContent(examples: ['口渴多饮'])},
      );

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(MockSettingsRepo()),
          templatesProvider.overrideWith((_) => Stream.value([t1])),
          contentTemplatesProvider('t1').overrideWith((_) => Stream.value([ct1])),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: ContentTemplateListPage()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('糖尿病'), findsOneWidget);
      expect(find.textContaining('已填入范例'), findsNothing);
    },
  );
}
