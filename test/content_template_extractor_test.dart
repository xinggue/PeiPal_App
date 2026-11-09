import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/content_template_extractor.dart';
import 'package:peipal/domain/models/content_template.dart';
import 'package:peipal/domain/models/template.dart';

void main() {
  final slots = [
    const TemplateSlot(key: 'chief', label: '主诉', type: SlotType.text),
    const TemplateSlot(
      key: 'sex',
      label: '性别',
      type: SlotType.dropdown,
      options: ['男', '女'],
    ),
  ];

  group('buildPrompt / buildRefinePrompt', () {
    test('lists every field with key, label, type and options', () {
      final p = ContentTemplateExtractor.buildPrompt(slots, '  病历正文  ');
      expect(p.system, contains('- chief：主诉（文本）'));
      expect(p.system, contains('- sex：性别（下拉，选项：男/女）'));
      expect(p.user, contains('病历正文'));
    });

    test('includes existing fields, sample record, instruction and scope rules', () {
      final p = ContentTemplateExtractor.buildRefinePrompt(
        slots: slots,
        targetStructureName: '入院记录',
        currentGlobalGuidance: '简明扼要',
        currentFields: {
          'chief': const ExtractedField(text: '胸痛3天', guidance: '20字以内'),
        },
        sampleRecord: '患者胸闷气短5天入院。',
        instruction: '细化主诉的时间格式要求',
        includeExamples: false,
        includeGuidance: true,
      );
      expect(p.system, contains('入院记录'));
      expect(p.system, contains('- chief：主诉（文本）'));
      expect(p.system, contains('仅生成「撰写要求 (guidance)」'));
      expect(p.user, contains('简明扼要'));
      expect(p.user, contains('20字以内'));
      expect(p.user, contains('细化主诉的时间格式要求'));
      expect(p.user, contains('患者胸闷气短5天入院。'));
    });

    test('preserves catalog mentions when refining guidance', () {
      const oldG = '必须包含标准诊断 \uFFFC[CATALOG:diagnosis:冠心病]\uFFFC';
      const newG = '按主次顺序排列诊断，不超过3条';
      final merged = ContentTemplateExtractor.preserveCatalogMentions(oldG, newG);
      expect(merged, contains('[CATALOG:diagnosis:冠心病]'));
      expect(merged, contains('按主次顺序排列诊断'));
    });
  });

  group('buildMigratePrompt', () {
    test('serializes full source sections and target structure slots with digest rules', () {
      final sourceCt = ContentTemplate(
        structureTemplateId: 'st_adm',
        name: '心内科入院模板',
        globalGuidance: '规范严谨',
        slots: {
          'chief': const SlotContent(
            examples: ['反复胸痛3年，加重2天'],
            guidance: '症状+持续时间',
            catalogTags: ['冠心病'],
          ),
        },
      );
      final targetSlots = [
        const TemplateSlot(
          key: 'case_features',
          label: '病例特点',
          type: SlotType.multiline,
        ),
      ];
      final p = ContentTemplateExtractor.buildMigratePrompt(
        sourceStructureName: '入院记录',
        sourceSlots: slots,
        sourceContent: sourceCt,
        targetStructureName: '首次病程记录',
        targetSlots: targetSlots,
        instruction: '浓缩为首程口吻',
        includeExamples: true,
        includeGuidance: false,
      );
      expect(p.system, contains('入院记录'));
      expect(p.system, contains('首次病程记录'));
      expect(p.system, contains('- case_features：病例特点（多行文本）'));
      expect(p.system, contains('仅生成「示范文本 (text)」'));
      expect(p.user, contains('反复胸痛3年，加重2天'));
      expect(p.user, contains('[CATALOG:diagnosis:冠心病]'));
      expect(p.user, contains('浓缩为首程口吻'));
    });
  });

  group('parseResponse', () {
    test('parses fields and global guidance', () {
      final r = ContentTemplateExtractor.parseResponse(
        '{"fields":{"chief":{"text":"胸痛3天","guidance":"20字内"}},'
        '"global_guidance":"严谨口吻"}',
        slots,
      );
      expect(r.fields['chief']!.text, '胸痛3天');
      expect(r.fields['chief']!.guidance, '20字内');
      expect(r.globalGuidance, '严谨口吻');
    });

    test('drops unknown keys and empty fields', () {
      final r = ContentTemplateExtractor.parseResponse(
        '{"fields":{"bogus":{"text":"x"},"sex":{"text":"","guidance":""}}}',
        slots,
      );
      expect(r.fields, isEmpty);
      expect(r.isEmpty, isTrue);
    });

    test('tolerates code fences and a bare string value', () {
      final r = ContentTemplateExtractor.parseResponse(
        '```json\n{"fields":{"chief":"胸痛"}}\n```',
        slots,
      );
      expect(r.fields['chief']!.text, '胸痛');
    });

    test('joins list values and trims whitespace', () {
      final r = ContentTemplateExtractor.parseResponse(
        '{"fields":{"chief":{"text":[" a ","b"]}}}',
        slots,
      );
      expect(r.fields['chief']!.text, 'a \nb');
    });

    test('throws FormatException when there is no JSON', () {
      expect(
        () => ContentTemplateExtractor.parseResponse('抱歉我做不到', slots),
        throwsFormatException,
      );
    });
  });
}
