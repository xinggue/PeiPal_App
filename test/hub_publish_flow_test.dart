import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/engine_c/engine_c_models.dart';
import 'package:peipal/data/services/engine_c/template_bundle_engine.dart';
import 'package:peipal/data/services/hub/hub_service.dart';
import 'package:peipal/domain/models/template.dart';
import 'package:peipal/presentation/pages/hub/hub_publish_wizard_page.dart';
import 'package:peipal/presentation/pages/hub/hub_components.dart';
import 'package:peipal/presentation/pages/hub/template_hub_page.dart';

final structure = Template(
  id: 's',
  name: '巡检记录',
  slots: const [
    TemplateSlot(key: 'result', label: '检查结果', type: SlotType.text),
  ],
);

class _Engine implements TemplateBundleEngine {
  @override
  Future<EngineCBundleEnvelope> buildExportEnvelope(
    EngineCExportRequest request,
  ) async => EngineCBundleEnvelope(
    exportedAt: DateTime(2026),
    units: [StructureGroundedUnit(structure: structure, hasPipeline: false)],
  );
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Hub extends HubService {
  _Hub() : super(const FlutterSecureStorage());
  final calls =
      <
        ({
          String institution,
          bool skip,
          Completer<Map<String, dynamic>> result,
        })
      >[];
  @override
  Future<Map<String, dynamic>> analyzeUpload({
    required Map<String, dynamic> payload,
    required List<Map<String, dynamic>> targets,
    String scope = '',
    String institution = '',
    bool skipAssistance = false,
    CancelToken? cancelToken,
  }) {
    final result = Completer<Map<String, dynamic>>();
    calls.add((institution: institution, skip: skipAssistance, result: result));
    return result
        .future; // Intentionally ignores cancellation to exercise stale-result protection.
  }
}

Map<String, dynamic> analysis(String institution) => {
  'analysis_id': institution,
  'scope': 'institution',
  'institution': institution,
  'structure_id': '',
  'candidates': <Map<String, dynamic>>[],
  'items': [
    {
      'key': 'structure',
      'kind': 'structure',
      'name': '巡检记录',
      'readme': '日常巡检用。',
      'update_id': '',
    },
  ],
};

void main() {
  testWidgets(
    'publishing explains the wait and automatically refreshes only institution changes',
    (tester) async {
      final hub = _Hub();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            hubPublishServiceProvider.overrideWithValue(hub),
            templateBundleEngineProvider.overrideWithValue(_Engine()),
          ],
          child: MaterialApp(
            home: HubBatchPublishPage(
              selection: HubPublishItemSelection(
                template: structure,
                publishStructureItself: true,
                includePipeline: false,
                selectedProfiles: const [],
                selectedContents: const [],
                includeLinkedDiagnoses: false,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('正在匹配文书、整理使用说明…'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
      expect(find.text('已等待 2 秒'), findsOneWidget);
      hub.calls.first.result.complete(analysis('机构A'));
      await tester.pumpAndSettle();
      expect(find.text('提交审核'), findsOneWidget);
      expect(find.text('检查归属'), findsNothing);
      await tester.enterText(
        find.widgetWithText(TextField, '使用说明 *'),
        '自己填写的说明',
      );
      await tester.pump(const Duration(seconds: 1));
      expect(hub.calls, hasLength(1));
      await tester.enterText(find.widgetWithText(TextField, '机构名称'), '机构B');
      await tester.pump(const Duration(milliseconds: 700));
      expect(hub.calls, hasLength(2));
      expect(hub.calls.last.skip, true);
      expect(find.text('正在更新文书归属…'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '提交审核'))
            .onPressed,
        isNull,
      );
      await tester.enterText(find.widgetWithText(TextField, '机构名称'), '机构C');
      await tester.pump(const Duration(milliseconds: 700));
      hub.calls.last.result.complete(analysis('机构C'));
      await tester.pumpAndSettle();
      hub.calls[1].result.complete(analysis('机构B'));
      await tester.pumpAndSettle();
      expect(find.text('将新建：机构C · 巡检记录'), findsOneWidget);
      expect(find.text('自己填写的说明'), findsOneWidget);
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '提交审核'))
            .onPressed,
        isNotNull,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'document group renders context once and loads compact children without repeated cards',
    (tester) async {
      HubListing listing(int i) => HubListing.fromJson({
        'id': 'c$i',
        'kind': 'content',
        'name': '内容$i',
        'structure_id': 'cloud-s',
        'institution': '机构A',
        'summary': {
          'structure': {
            'name': '巡检记录',
            'slotCount': 1,
            'slotLabels': ['检查结果'],
          },
          'contents': [
            {'id': 'c$i', 'name': '内容$i', 'sampleSnippet': '示范$i'},
          ],
        },
      });
      int? offset;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: 207,
                  child: HubDocumentGroupCard(
                    group: HubDocumentGroup(
                      id: 'cloud-s',
                      name: '巡检记录',
                      items: [listing(1), listing(2), listing(3)],
                      counts: const {'content': 5},
                    ),
                    onOpen: (_) {},
                    onManage: (_) {},
                    loadMore: (kind, start) async {
                      offset = start;
                      return [listing(4), listing(5)];
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.text('机构A的'), findsOneWidget);
      expect(find.text('巡检记录'), findsOneWidget);
      expect(find.textContaining('含1个字段'), findsNothing);
      expect(find.byType(Card), findsOneWidget);
      await tester.ensureVisible(find.text('查看更多'));
      await tester.tap(find.text('查看更多'));
      await tester.pumpAndSettle();
      expect(offset, 3);
      expect(find.text('内容5'), findsOneWidget);
      expect(find.text('查看更多'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'document overview keeps count buttons in one row and opens details directly',
    (tester) async {
      final semantics = tester.ensureSemantics();
      try {
        final root = HubListing.fromJson({
          'id': 'root',
          'kind': 'structure',
          'structure_id': 's',
          'institution': '机构A',
          'summary': {
            'structure': {
              'id': 's',
              'name': '巡检记录',
              'slotCount': 1,
              'slotLabels': ['检查结果'],
            },
          },
        });
        final child = HubListing.fromJson({
          'id': 'child',
          'kind': 'content',
          'structure_id': 's',
          'summary': {
            'contents': [
              {'id': 'c', 'name': '不应展开的子项', 'sampleSnippet': '不应展开的示范'},
            ],
          },
        });
        HubCardItem? opened;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 207,
                    child: HubDocumentGroupCard(
                      group: HubDocumentGroup(
                        id: 's',
                        name: '巡检记录',
                        items: [root, child],
                        counts: const {
                          'structure': 1,
                          'content': 12,
                          'typing': 2,
                          'pipeline': 3,
                        },
                      ),
                      overview: true,
                      onOpen: (item) => opened = item,
                      onManage: (_) {},
                      loadMore: (_, offset) async => [],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        expect(find.textContaining('含1个字段'), findsOneWidget);
        final buttons = find.byType(OutlinedButton);
        expect(buttons, findsNWidgets(3));
        final y = tester.getTopLeft(buttons.first).dy;
        for (var i = 0; i < 3; i++) {
          expect(tester.getTopLeft(buttons.at(i)).dy, y);
        }
        for (final label in ['内容模板：12套', '输入方案：2套', '解析流程：3条']) {
          expect(find.bySemanticsLabel(label), findsWidgets);
        }
        expect(find.text('12'), findsOneWidget);
        expect(find.text('不应展开的子项'), findsNothing);
        expect(find.text('不应展开的示范'), findsNothing);
        await tester.tap(find.text('巡检记录'));
        expect(opened?.listing.id, 'root');
        expect(opened?.subtype, HubItemSubtype.structure);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
      }
    },
  );
}
