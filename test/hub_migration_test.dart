import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peipal/data/repositories/content_template_repository.dart';
import 'package:peipal/data/repositories/settings_repository.dart';
import 'package:peipal/data/repositories/template_repository.dart';
import 'package:peipal/data/services/api/api_config.dart';
import 'package:peipal/data/services/api/extractor_config.dart';
import 'package:peipal/data/services/content_template_extractor.dart';
import 'package:peipal/domain/models/content_template.dart';
import 'package:peipal/domain/models/template.dart';
import 'package:peipal/presentation/pages/templates/content_template_editor_page.dart';
import 'package:peipal/providers/providers.dart';

final target = Template(
  id: 'local-target',
  name: '本地文书',
  slots: const [
    TemplateSlot(key: 'local-result', label: '结果', type: SlotType.text),
  ],
);
final source = Template(
  id: 'cloud-source',
  name: '云端文书',
  slots: const [
    TemplateSlot(key: 'source-result', label: '检查结果', type: SlotType.text),
  ],
);
final content = ContentTemplate(
  id: 'cloud-content',
  structureTemplateId: source.id,
  name: '云端内容',
  slots: {
    'source-result': SlotContent(examples: ['运行正常']),
  },
);

class _Templates implements TemplateRepository {
  @override
  Future<Template?> getById(String id) async => id == target.id ? target : null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Contents implements ContentTemplateRepository {
  final saved = <ContentTemplate>[];
  @override
  Future<void> insert(ContentTemplate value) async {
    saved.add(value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings implements SettingsRepository {
  @override
  Future<String?> get(String key) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Extractor implements ContentTemplateExtractor {
  String? receivedSource;
  String? receivedTarget;
  @override
  Future<ExtractionResult> migrate({
    required String sourceStructureName,
    required List<TemplateSlot> sourceSlots,
    required ContentTemplate sourceContent,
    required String targetStructureName,
    required List<TemplateSlot> targetSlots,
    String instruction = '',
    bool includeExamples = true,
    bool includeGuidance = true,
    ExtractorConfig? config,
  }) async {
    receivedSource = sourceContent.id;
    receivedTarget = targetSlots.single.key;
    return const ExtractionResult(
      fields: {'local-result': ExtractedField(text: '迁移后的结果')},
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'cloud migration uses existing migration editor and writes only the saved target content',
    (tester) async {
      FlutterSecureStorage.setMockInitialValues({'llm_api_key': 'test-only'});
      final contents = _Contents();
      final extractor = _Extractor();
      final container = ProviderContainer(
        overrides: [
          templateRepositoryProvider.overrideWithValue(_Templates()),
          contentTemplateRepositoryProvider.overrideWithValue(contents),
          settingsRepositoryProvider.overrideWithValue(_Settings()),
          catalogsProvider.overrideWith((ref) async => []),
          contentTemplateExtractorProvider.overrideWithValue(extractor),
        ],
      );
      addTearDown(container.dispose);
      await tester.runAsync(
        () => container
            .read(llmConfigProvider.notifier)
            .save(const LlmConfig(apiKey: 'test-only')),
      );
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: TextButton(
                onPressed: () => context.push('/new'),
                child: const Text('open'),
              ),
            ),
          ),
          GoRoute(
            path: '/new',
            builder: (context, state) => ContentTemplateEditorPage(
              structureTemplateId: target.id,
              initialMigrateStructure: source,
              initialMigrateContent: content,
            ),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('迁移到「本地文书」'), findsOneWidget);
      expect(find.text('云端内容'), findsOneWidget);
      expect(contents.saved, isEmpty);
      // Cancel before generation: neither cloud source nor target is persisted.
      Navigator.of(tester.element(find.text('迁移到「本地文书」'))).pop();
      await tester.pumpAndSettle();
      router.pop();
      await tester.pumpAndSettle();
      expect(contents.saved, isEmpty);
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开始智能迁移'));
      await tester.tap(find.text('开始智能迁移'));
      await tester.pumpAndSettle();
      expect(extractor.receivedSource, content.id);
      expect(extractor.receivedTarget, 'local-result');
      expect(contents.saved, isEmpty);
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();
      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();
      expect(contents.saved, hasLength(1));
      expect(contents.saved.single.structureTemplateId, target.id);
      expect(contents.saved.single.id, isNot(content.id));
      expect(contents.saved.single.slots['local-result']!.examples, ['迁移后的结果']);
      await tester.pump(const Duration(seconds: 5));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
