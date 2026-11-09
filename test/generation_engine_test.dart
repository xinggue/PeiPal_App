import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/api/api_service.dart';
import 'package:peipal/data/services/api/llm_prompt_config.dart';
import 'package:peipal/data/services/processing_service.dart';
import 'package:peipal/data/services/task/task_center.dart';
import 'package:peipal/data/services/generation_engine.dart';
import 'package:peipal/data/services/generation/output_sanitizer.dart';
import 'package:peipal/data/services/generation/output_schema_builder.dart';
import 'package:peipal/data/services/generation/pipeline_executor.dart';
import 'package:peipal/data/services/generation/stage_prompt_compiler.dart';
import 'package:peipal/domain/generation/generation_log.dart';
import 'package:peipal/domain/generation/generation_plan.dart';
import 'package:peipal/domain/generation/generation_result.dart';
import 'package:peipal/domain/generation/record_validator.dart';
import 'package:peipal/presentation/widgets/chat/document_collate_sheet.dart';
import 'package:peipal/domain/generation/standard_catalog.dart';
import 'package:peipal/domain/models/content_template.dart';
import 'package:peipal/domain/models/favorite_diagnosis.dart';
import 'package:peipal/domain/models/message.dart';
import 'package:peipal/domain/models/patient.dart';
import 'package:peipal/domain/models/pipeline_graph.dart';
import 'package:peipal/domain/models/record_meta.dart';
import 'package:peipal/domain/models/template.dart';

class _MockApiService extends Fake implements ApiService {
  final List<dynamic> script;
  int callIndex = 0;
  final List<String> sentUserPrompts = [];

  _MockApiService(this.script);

  @override
  Future<String> chatCompletion({
    required String systemPrompt,
    required String userPrompt,
    bool jsonMode = true,
    Map<String, dynamic>? jsonSchema,
    CancelToken? cancelToken,
    void Function(String chunk, String accumulated)? onChunk,
  }) async {
    sentUserPrompts.add(userPrompt);

    if (cancelToken?.isCancelled == true) {
      throw DioException(
        requestOptions: RequestOptions(),
        type: DioExceptionType.cancel,
      );
    }

    if (callIndex >= script.length) {
      throw StateError('No more mock responses available');
    }
    final next = script[callIndex++];
    if (next is Exception) throw next;
    if (next is Error) throw next;
    return next as String;
  }
}

void main() {
  final patient = Patient(
    name: '张三',
    gender: Gender.male,
    age: 58,
    medicalRecordNumber: 'MRN888',
    notes: '高血压10年',
  );

  final slotHpi = const TemplateSlot(
    key: 'hpi',
    label: '现病史',
    type: SlotType.multiline,
    required: true,
  );

  final slotDiag = const TemplateSlot(
    key: 'primary_diag',
    label: '主要诊断',
    type: SlotType.text,
    catalogType: 'diagnosis',
    required: true,
  );

  final template = Template(
    name: '首程模板',
    slots: [slotHpi, slotDiag],
  );

  group('StagePromptCompiler', () {
    test('injects current time and Chinese weekday anchor', () {
      final fixedDate = DateTime(2026, 10, 14, 16, 30); // Wednesday
      final plan = GenerationPlan(
        template: template,
        patient: patient,
        rawChatStream: [],
        historicalRecords: [],
        now: fixedDate,
      );

      final compiled = StagePromptCompiler.compile(
        plan: plan,
        batchSlots: [slotHpi],
        accumulatedOutputs: {},
      );

      expect(compiled.userPrompt, contains('【当前生成时间】：2026-10-14 16:30 (星期三)'));
    });

    test('masks patient names longer than two characters', () {
      final maskedPatient =
          Patient(name: '欧阳娜娜', gender: Gender.female, age: 30);
      final plan = GenerationPlan(
        template: template,
        patient: maskedPatient,
        rawChatStream: [
          Message.text(patientId: maskedPatient.id, content: '胸闷三天'),
        ],
        historicalRecords: [],
      );

      final compiled = StagePromptCompiler.compile(
        plan: plan,
        batchSlots: [slotHpi],
        accumulatedOutputs: {},
      );

      expect(compiled.userPrompt, contains('名称: 欧**娜'));
      expect(compiled.userPrompt, isNot(contains('欧阳娜娜')));
      expect(compiled.userPrompt, contains('【本次聊天记录与材料】'));
      expect(compiled.userPrompt, contains('[用户消息]'));
    });

    test('keeps two-character patient names unmasked', () {
      final plan = GenerationPlan(
        template: template,
        patient: patient,
        rawChatStream: [],
        historicalRecords: [],
      );

      final compiled = StagePromptCompiler.compile(
        plan: plan,
        batchSlots: [slotHpi],
        accumulatedOutputs: {},
      );

      expect(compiled.userPrompt, contains('名称: 张三'));
    });

    test('injects catalog diagnoses driven by @Mention in guidance', () {
      final fav1 = FavoriteDiagnosis(code: 'I25.1', name: '冠心病', tags: ['心内科']);
      final fav2 = FavoriteDiagnosis(code: 'E11.9', name: '2型糖尿病', tags: ['内分泌']);
      final fav3 = FavoriteDiagnosis(code: 'I10.x00', name: '高血压', tags: ['门诊高频']);

      final contentTemplate = ContentTemplate(
        structureTemplateId: template.id,
        name: '心内专科',
        globalGuidance: '严谨书写',
        slots: {
          'primary_diag': const SlotContent(
            guidance: '必须规范书写，参考 \uFFFC[CATALOG:diagnosis:心内科]\uFFFC 与 \uFFFC[CATALOG:diagnosis:门诊高频]\uFFFC 并列选用',
          ),
        },
      );

      final plan = GenerationPlan(
        template: template,
        contentTemplate: contentTemplate,
        patient: patient,
        rawChatStream: [
          Message.text(patientId: patient.id, content: '胸痛3天'),
        ],
        historicalRecords: [],
        catalogEntriesByType: {
          'diagnosis': [
            CatalogItem.fromFavoriteDiagnosis(fav1),
            CatalogItem.fromFavoriteDiagnosis(fav2),
            CatalogItem.fromFavoriteDiagnosis(fav3),
          ],
        },
      );

      final compiled = StagePromptCompiler.compile(
        plan: plan,
        batchSlots: [slotDiag],
        accumulatedOutputs: {'hpi': '患者3天前出现胸骨后压榨性疼痛'},
        batchPrompt: '请针对心内科体征推断',
      );

      // 验证底层 Token 彻底被转为给 LLM 阅读的高可读标记
      expect(compiled.systemPrompt, isNot(contains('\uFFFC')));
      expect(compiled.systemPrompt, contains('[标准诊断词条: 心内科]'));
      expect(compiled.systemPrompt, contains('[标准诊断词条: 门诊高频]'));

      // 验证各胶囊标签就近展开并列词条
      expect(compiled.systemPrompt, contains('* [标准诊断词条: 心内科] 包含的规范名称及编码：'));
      expect(compiled.systemPrompt, contains('- 冠心病 (I25.1)'));
      expect(compiled.systemPrompt, contains('* [标准诊断词条: 门诊高频] 包含的规范名称及编码：'));
      expect(compiled.systemPrompt, contains('- 高血压 (I10.x00)'));

      // 未被提及的标签词条绝不注入
      expect(compiled.systemPrompt, isNot(contains('2型糖尿病')));
      expect(compiled.systemPrompt, contains('严谨书写'));
      expect(compiled.systemPrompt, contains('请针对心内科体征推断'));
      expect(compiled.userPrompt, contains('张三'));
      expect(compiled.userPrompt, contains('患者3天前出现胸骨后压榨性疼痛'));
      expect(compiled.userPrompt, contains('胸痛3天'));
    });

    test('handles multiple cross-catalog mentions and empty tag fallbacks gracefully', () {
      final slotProc = const TemplateSlot(
        key: 'proc_plan',
        label: '拟行手术',
        type: SlotType.text,
      );

      final contentTemplate = ContentTemplate(
        structureTemplateId: template.id,
        name: '介入专科',
        slots: {
          'proc_plan': const SlotContent(
            guidance: '必须规范：参考 \uFFFC[CATALOG:procedure:微创介入]\uFFFC 与 \uFFFC[CATALOG:diagnosis:空标签测试]\uFFFC',
          ),
        },
      );

      final plan = GenerationPlan(
        template: template,
        contentTemplate: contentTemplate,
        patient: patient,
        rawChatStream: [],
        historicalRecords: [],
        catalogEntriesByType: {
          'procedure': [
            const CatalogItem(code: '36.06', name: '冠状动脉支架置入术', tags: ['微创介入']),
          ],
          'diagnosis': [],
        },
      );

      final compiled = StagePromptCompiler.compile(
        plan: plan,
        batchSlots: [slotProc],
        accumulatedOutputs: {},
      );

      expect(compiled.systemPrompt, contains('[标准手术词条: 微创介入]'));
      expect(compiled.systemPrompt, contains('[标准诊断词条: 空标签测试]'));
      expect(compiled.systemPrompt, contains('- 冠状动脉支架置入术 (36.06)'));
      expect(compiled.systemPrompt, contains('(词库中暂无此标签词条)'));
    });

    test('does NOT inject catalog prompt if slot.catalogType is null, ignoring label heuristics', () {
      final slotPlain = const TemplateSlot(
        key: 'diff_diag',
        label: '鉴别诊断',
        type: SlotType.text,
      );

      final plan = GenerationPlan(
        template: template,
        patient: patient,
        rawChatStream: [],
        historicalRecords: [],
        catalogEntriesByType: {
          'diagnosis': [
            const CatalogItem(code: 'I25.1', name: '冠心病'),
          ],
        },
      );

      final compiled = StagePromptCompiler.compile(
        plan: plan,
        batchSlots: [slotPlain],
        accumulatedOutputs: {},
      );

      expect(compiled.systemPrompt, isNot(contains('【标准')));
      expect(compiled.systemPrompt, isNot(contains('冠心病')));
    });

    test('retains all past medical records in user prompt', () {
      final pastRecord = Message.generatedRecord(
        patientId: patient.id,
        recordJson: '{"hpi": "既往出院小结内容"}',
        templateId: template.id,
      );

      final ocrMsg = Message.ocrResult(
        patientId: patient.id,
        extractedText: '血常规：白细胞 12.5×10^9/L',
      );

      final asrMsg = Message.asrResult(
        patientId: patient.id,
        transcribedText: '患者自述昨日发热38.5度',
      );

      final plan = GenerationPlan(
        template: template,
        patient: patient,
        rawChatStream: [ocrMsg, asrMsg],
        historicalRecords: [pastRecord],
      );

      final compiled = StagePromptCompiler.compile(
        plan: plan,
        batchSlots: [slotHpi],
        accumulatedOutputs: {},
      );

      expect(compiled.userPrompt, contains('既往已生成文书背景'));
      expect(compiled.userPrompt, contains('既往出院小结内容'));
      expect(compiled.userPrompt, contains('材料OCR识别'));
      expect(compiled.userPrompt, contains('白细胞 12.5'));
      expect(compiled.userPrompt, contains('语音转写'));
      expect(compiled.userPrompt, contains('昨日发热38.5度'));
    });
  });

  group('OutputSanitizer & OutputSchemaBuilder', () {
    test('OutputSchemaBuilder includes enum with empty fallback for dropdown', () {
      final slotDropdown = const TemplateSlot(
        key: 'gender',
        label: '性别',
        type: SlotType.dropdown,
        options: ['男', '女'],
      );
      final schema = OutputSchemaBuilder.build(
        stageTitle: '基本信息',
        slots: [slotDropdown],
      );

      final props = (schema['schema'] as Map)['properties'] as Map;
      expect(props['gender']['enum'], ['', '男', '女']);
      expect((schema['schema'] as Map)['required'], ['gender']);
      expect(schema['strict'], isTrue);
    });

    test('OutputSanitizer flattens nested maps and arrays, falls back to labels', () {
      final slotAllergies = const TemplateSlot(
        key: 'allergies',
        label: '过敏史',
        type: SlotType.multiline,
      );

      final raw = '''
```json
{
  "现病史": "3天前胸痛",
  "allergies": [
    {"drug": "青霉素", "reaction": "皮疹"},
    {"drug": "磺胺", "reaction": "休克"}
  ]
}
```
''';

      final sanitized = OutputSanitizer.sanitize(
        rawResponse: raw,
        batchSlots: [slotHpi, slotAllergies],
      );

      // Chinese label "现病史" mapped back to key "hpi"
      expect(sanitized['hpi'], '3天前胸痛');
      // Nested list of maps flattened neatly
      expect(sanitized['allergies'], contains('1. drug: 青霉素, reaction: 皮疹'));
      expect(sanitized['allergies'], contains('2. drug: 磺胺, reaction: 休克'));
    });

    test('OutputSanitizer throws FormatException if zero target keys match', () {
      final raw = '{"totally_hallucinated": "val"}';
      expect(
        () => OutputSanitizer.sanitize(
          rawResponse: raw,
          batchSlots: [slotHpi],
        ),
        throwsFormatException,
      );
    });

    test('OutputSanitizer extracts clean JSON when model mixes thoughts and multiple JSON blocks', () {
      final slotDiag = const TemplateSlot(key: '诊断', label: '诊断', type: SlotType.multiline);
      final raw1 = '''
The task: generate "诊断" field for 首程. Need based on clinical data.
Diagnosis should list: 认知障碍, 脑白质病变.

{"诊断": "草稿诊断：认知障碍待查"}

The 诊断 field maybe doesn't include note; but fine. Keep concise.{"诊断": "1. 认知障碍（病因待查）；2. 脑白质病变；3. 双侧额叶略萎缩。"}
''';
      final res1 = OutputSanitizer.sanitize(
        rawResponse: raw1,
        batchSlots: [slotDiag],
      );
      // 应精准提取出最终正式生效的最后一个 JSON 内容
      expect(res1['诊断'], contains('1. 认知障碍（病因待查）'));

      final slotPe = const TemplateSlot(key: '查体', label: '查体', type: SlotType.multiline);
      final slotLab = const TemplateSlot(key: '辅助检查', label: '辅助检查', type: SlotType.multiline);
      final raw2 = '''
We need to respond with JSON only, fields 查体 and 辅助检查.
Let's draft:
{
  "查体": "草稿草稿",
  "辅助检查": "旧检查"
}
I will output a standard concise 查体 with caveat. Since JSON only.{"查体":"患者一般情况可，神志清楚。","辅助检查":"2025-08-21 脑PET/MR示白质病变。"}
''';
      final res2 = OutputSanitizer.sanitize(
        rawResponse: raw2,
        batchSlots: [slotPe, slotLab],
      );
      expect(res2['查体'], '患者一般情况可，神志清楚。');
      expect(res2['辅助检查'], '2025-08-21 脑PET/MR示白质病变。');
    });
  });

  group('RecordValidator', () {
    test('detects option mismatch for dropdown and checkbox', () {
      final slotSex = const TemplateSlot(
        key: 'sex',
        label: '性别',
        type: SlotType.dropdown,
        options: ['男', '女'],
      );
      final slotHabits = const TemplateSlot(
        key: 'habits',
        label: '不良嗜好',
        type: SlotType.checkbox,
        options: ['吸烟', '饮酒', '熬夜'],
      );

      final issue1 = RecordValidator.validateField(
        slot: slotSex,
        rawValue: '男性', // Should mismatch!
      );
      expect(issue1?.type, FieldIssueType.notInOptions);
      expect(issue1?.message, contains('不在预设选项中'));

      final issue2 = RecordValidator.validateField(
        slot: slotSex,
        rawValue: '男', // Exact match
      );
      expect(issue2, isNull);

      final issue3 = RecordValidator.validateField(
        slot: slotHabits,
        rawValue: '吸烟，嗜甜', // '嗜甜' not in options
      );
      expect(issue3?.type, FieldIssueType.notInOptions);
      expect(issue3?.message, contains('嗜甜'));
    });

    test('detects missing required field', () {
      final slotReq = const TemplateSlot(
        key: 'name',
        label: '姓名',
        type: SlotType.text,
        required: true,
      );

      final issue = RecordValidator.validateField(
        slot: slotReq,
        rawValue: '   ',
      );
      expect(issue?.type, FieldIssueType.missingRequired);
    });
  });

  group('PipelineExecutor Batch Planning & Deduplication', () {
    test('groups properly and auto-appends remainder batch for unassigned slots', () {
      final s1 = const TemplateSlot(key: 's1', label: 's1', type: SlotType.text);
      final s2 = const TemplateSlot(key: 's2', label: 's2', type: SlotType.text);
      final s3 = const TemplateSlot(key: 's3', label: 's3', type: SlotType.text);
      final s4 = const TemplateSlot(key: 's4', label: 's4', type: SlotType.text);

      final graph = PipelineGraph(
        nodes: [
          PipelineNode(label: '起点', slotKeys: []),
          PipelineNode(label: '现病史', slotKeys: ['s1'], group: 1),
          // s2 and s3 share group 2
          PipelineNode(label: '体检', slotKeys: ['s2'], group: 2),
        ],
      );

      final tWithFourSlots = Template(
        name: '四槽位',
        slots: [s1, s2, s3, s4],
        pipeline: graph,
      );

      final plan = GenerationPlan(
        template: tWithFourSlots,
        patient: patient,
        rawChatStream: [],
        historicalRecords: [],
      );

      final executor = PipelineExecutor(_MockApiService([]));
      final batches = executor.planBatches(plan);

      // s3 and s4 were not assigned to any node, so they are grouped into a "其余字段" remainder batch!
      expect(batches.length, 3);
      expect(batches[0].slots.map((s) => s.key).toList(), ['s1']);
      expect(batches[1].slots.map((s) => s.key).toList(), ['s2']);
      expect(batches[2].title, '其余字段');
      expect(batches[2].slots.map((s) => s.key).toList(), ['s3', 's4']);
    });

    test('custom slot selection only plans requested slots and skips remainder batch', () {
      final s1 = const TemplateSlot(key: 's1', label: 's1', type: SlotType.text);
      final s2 = const TemplateSlot(key: 's2', label: 's2', type: SlotType.text);
      final s3 = const TemplateSlot(key: 's3', label: 's3', type: SlotType.text);
      final s4 = const TemplateSlot(key: 's4', label: 's4', type: SlotType.text);

      final graph = PipelineGraph(
        nodes: [
          PipelineNode(label: '现病史', slotKeys: ['s1'], group: 1),
          PipelineNode(label: '体检', slotKeys: ['s2'], group: 2),
        ],
      );

      final tWithFourSlots = Template(
        name: '四槽位',
        slots: [s1, s2, s3, s4],
        pipeline: graph,
      );

      // 用户仅勾选了 s1 和 s4，没有选 s2 和 s3
      final customPlan = GenerationPlan(
        template: tWithFourSlots,
        patient: patient,
        rawChatStream: [],
        historicalRecords: [],
        selectedSlotKeys: {'s1', 's4'},
      );

      final executor = PipelineExecutor(_MockApiService([]));
      final batches = executor.planBatches(customPlan);

      expect(customPlan.isCustomSlotSelection, isTrue);
      // s2 和 s3 不应该出现；且未分配的槽位不再自动追加“其余字段”兜底批次
      expect(batches.length, 1);
      expect(batches[0].slots.map((s) => s.key).toList(), ['s1']);
    });
  });

  group('PipelineExecutor Execution & Resumption & Retries', () {
    test('recovers from transient network error via retry', () async {
      final mock = _MockApiService([
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.receiveTimeout,
        ),
        '{"hpi": "平稳"}',
      ]);

      final plan = GenerationPlan(
        template: Template(name: '单槽位', slots: [slotHpi]),
        patient: patient,
        rawChatStream: [],
        historicalRecords: [],
      );

      final executor = PipelineExecutor(mock, sleepOverride: (_) async {});
      final result = await executor.execute(plan: plan);

      expect(result.isSuccess, isTrue);
      expect(result.fieldValues['hpi'], '平稳');
      expect(result.stageLogs.first.attempts, 2);
    });

    test('recovers from format error by appending prompt hint', () async {
      final mock = _MockApiService([
        '抱歉我无法输出JSON',
        '{"hpi": "格式已修复"}',
      ]);

      final plan = GenerationPlan(
        template: Template(name: '单槽位', slots: [slotHpi]),
        patient: patient,
        rawChatStream: [],
        historicalRecords: [],
      );

      final executor = PipelineExecutor(mock, sleepOverride: (_) async {});
      final result = await executor.execute(plan: plan);

      expect(result.isSuccess, isTrue);
      expect(result.fieldValues['hpi'], '格式已修复');
      expect(mock.sentUserPrompts[1], contains('重要提醒：上次返回内容未能成功提取出指定的字段 JSON'));
    });

    test('preserves partial results on failure and allows resuming from checkpoint', () async {
      final s1 = const TemplateSlot(key: 's1', label: 's1', type: SlotType.text);
      final s2 = const TemplateSlot(key: 's2', label: 's2', type: SlotType.text);
      final t = Template(name: '两阶段', slots: [s1, s2]).copyWith(
        pipeline: PipelineGraph(nodes: [
          PipelineNode(label: '阶段1', slotKeys: ['s1'], col: 0),
          PipelineNode(label: '阶段2', slotKeys: ['s2'], col: 1),
        ]),
      );

      final plan = GenerationPlan(
        template: t,
        patient: patient,
        rawChatStream: [],
        historicalRecords: [],
      );

      // Run 1: stage 1 succeeds, stage 2 fails
      final mock1 = _MockApiService([
        '{"s1": "第一阶段成功"}',
        DioException(
          requestOptions: RequestOptions(),
          response: Response(requestOptions: RequestOptions(), statusCode: 401),
        ),
      ]);

      final exec1 = PipelineExecutor(mock1, sleepOverride: (_) async {});
      final failResult = await exec1.execute(plan: plan);

      expect(failResult.isSuccess, isFalse);
      expect(failResult.isPartial, isTrue);
      expect(failResult.fieldValues['s1'], '第一阶段成功');
      expect(failResult.completedStages, 1);
      expect(failResult.totalStages, 2);

      // Run 2: resume from checkpoint, only calling stage 2
      final mock2 = _MockApiService([
        '{"s2": "第二阶段恢复成功"}',
      ]);

      final exec2 = PipelineExecutor(mock2, sleepOverride: (_) async {});
      final resumedResult = await exec2.execute(plan: plan, resumeFrom: failResult);

      expect(resumedResult.isSuccess, isTrue);
      expect(resumedResult.fieldValues['s1'], '第一阶段成功');
      expect(resumedResult.fieldValues['s2'], '第二阶段恢复成功');
      expect(resumedResult.stageLogs.length, 2);
    });

    test('cancels immediately via cancelToken', () async {
      final token = CancelToken()..cancel('用户主动退出');
      final mock = _MockApiService(['{"hpi": "未执行"}']);

      final plan = GenerationPlan(
        template: Template(name: '单槽位', slots: [slotHpi]),
        patient: patient,
        rawChatStream: [],
        historicalRecords: [],
      );

      final executor = PipelineExecutor(mock);
      final result = await executor.execute(plan: plan, cancelToken: token);

      expect(result.isSuccess, isFalse);
      expect(result.errorMessage, contains('已取消'));
    });
  });

  group('GenerationEngine Defensive Ordering & Slicing', () {
    test('buildPlan sorts descending input messages to strictly ascending order', () {
      final m1 = Message(
        patientId: patient.id,
        sender: MessageSender.user,
        type: MessageType.text,
        content: '第一天',
        createdAt: DateTime(2026, 1, 1, 8, 0),
      );
      final m2 = Message(
        patientId: patient.id,
        sender: MessageSender.user,
        type: MessageType.text,
        content: '第二天',
        createdAt: DateTime(2026, 1, 2, 8, 0),
      );
      final m3 = Message(
        patientId: patient.id,
        sender: MessageSender.user,
        type: MessageType.text,
        content: '第三天',
        createdAt: DateTime(2026, 1, 3, 8, 0),
      );

      final engine = GenerationEngine(_MockApiService([]));

      // Pass in reverse order: [m3, m2, m1]
      final plan = engine.buildPlan(
        template: template,
        contentTemplate: null,
        patient: patient,
        chatMessages: [m3, m2, m1],
        allMaterials: true,
      );

      expect(
        plan.rawChatStream.map((m) => m.content).toList(),
        ['第一天', '第二天', '第三天'],
      );
    });

    test('buildPlan with allMaterials=false picks only messages after the last record', () {
      final m1 = Message(
        patientId: patient.id,
        sender: MessageSender.user,
        type: MessageType.text,
        content: '首诊前材料',
        createdAt: DateTime(2026, 1, 1),
      );
      final rec = Message.generatedRecord(
        patientId: patient.id,
        recordJson: '{"hpi": "首诊病历"}',
        templateId: template.id,
        createdAt: DateTime(2026, 1, 2),
      );
      final m2 = Message(
        patientId: patient.id,
        sender: MessageSender.user,
        type: MessageType.text,
        content: '查房新材料',
        createdAt: DateTime(2026, 1, 3),
      );

      final engine = GenerationEngine(_MockApiService([]));
      // Input in reverse order: [m2, rec, m1]
      final plan = engine.buildPlan(
        template: template,
        contentTemplate: null,
        patient: patient,
        chatMessages: [m2, rec, m1],
        allMaterials: false,
      );

      expect(plan.rawChatStream.length, 1);
      expect(plan.rawChatStream.first.content, '查房新材料');
      expect(plan.historicalRecords.length, 1);
    });

    test('buildPlan and StagePromptCompiler integrate extraInstructions cleanly', () {
      final engine = GenerationEngine(_MockApiService([]));
      final plan = engine.buildPlan(
        template: template,
        contentTemplate: null,
        patient: patient,
        chatMessages: [],
        extraInstructions: '请着重强调患者对头孢过敏，且体温偏高',
      );

      expect(plan.extraInstructions, '请着重强调患者对头孢过敏，且体温偏高');

      final compiled = StagePromptCompiler.compile(
        plan: plan,
        batchSlots: [slotHpi],
        accumulatedOutputs: {},
      );

      expect(compiled.userPrompt, contains('【本次生成特别补充要求与指示 (最高优先级准则)】：'));
      expect(compiled.userPrompt, contains('请着重强调患者对头孢过敏，且体温偏高'));
    });
  });

  group('RecordMeta & GenerationLog Models', () {
    test('RecordMeta and GenerationLog round-trip JSON serialization', () {
      final meta = RecordMeta(
        templateName: '首程模板',
        templateVersion: '1.2',
        model: 'gpt-4o',
        isPartial: true,
        missingSlotKeys: ['primary_diag'],
        generatedAt: DateTime(2026, 10, 14, 10, 0),
        totalDurationMs: 4200,
        slotSnapshots: RecordMeta.snapshotSlots([slotHpi, slotDiag]),
        aiOriginalValues: {'hpi': 'AI 原始文本'},
      );

      final backMeta = RecordMeta.fromJson(meta.toJson());
      expect(backMeta.templateName, '首程模板');
      expect(backMeta.isPartial, isTrue);
      expect(backMeta.missingSlotKeys, ['primary_diag']);
      expect(backMeta.slotSnapshots.length, 2);
      expect(backMeta.aiOriginalValues['hpi'], 'AI 原始文本');

      final log = GenerationLog(
        id: 'log_1',
        messageId: 'msg_1',
        patientId: 'pat_1',
        templateId: 'tmpl_1',
        templateName: '首程模板',
        model: 'gpt-4o',
        status: 'partial',
        totalDurationMs: 4200,
        stages: [
          StageLog(
            index: 1,
            title: '现病史',
            slotKeys: ['hpi'],
            systemPrompt: 'sys',
            userPrompt: 'usr',
            rawResponse: '{"hpi": "AI 原始文本"}',
            attempts: 1,
            duration: const Duration(seconds: 4),
            success: true,
          ),
        ],
        issues: [
          const FieldIssue(
            key: 'sex',
            type: FieldIssueType.notInOptions,
            message: '不符合选项',
          ),
        ],
        errorMessage: '第 2 阶段超时',
        createdAt: DateTime(2026, 10, 14, 10, 0),
      );

      final backLog = GenerationLog.fromMap(log.toMap());
      expect(backLog.status, 'partial');
      expect(backLog.stages.length, 1);
      expect(backLog.stages.first.rawResponse, '{"hpi": "AI 原始文本"}');
      expect(backLog.issues.first.key, 'sex');
      expect(backLog.errorMessage, '第 2 阶段超时');
    });
  });

  group('Regression', () {
    test('failed ASR/OCR placeholder text is excluded from the LLM prompt', () {
      final plan = GenerationPlan(
        template: template,
        patient: patient,
        rawChatStream: [
          Message.asrResult(patientId: patient.id, transcribedText: 'ASR失败\nHTTP 401'),
          Message.ocrResult(patientId: patient.id, extractedText: 'OCR超时\n服务器未响应'),
          Message.asrResult(patientId: patient.id, transcribedText: '发热两天'),
        ],
        historicalRecords: [],
      );
      final compiled = StagePromptCompiler.compile(
        plan: plan,
        batchSlots: [slotHpi],
        accumulatedOutputs: {},
      );
      expect(compiled.userPrompt, contains('发热两天'));
      expect(compiled.userPrompt, isNot(contains('ASR失败')));
      expect(compiled.userPrompt, isNot(contains('OCR超时')));
      expect(ProcessingService.isFailureText('ASR失败'), isTrue);
      expect(ProcessingService.isFailureText('患者自述 ASR失败过'), isFalse);
      expect(ProcessingService.isFailureText(null), isFalse);
    });

    test('Message.copyWith(filePaths) keeps id and swaps paths', () {
      final m = Message.photo(
          patientId: 'p', filePaths: ['/tmp/a.jpg'], fileSizes: [10]);
      final u = m.copyWith(filePaths: ['/docs/page_001.jpg']);
      expect(u.id, m.id);
      expect(u.filePaths, ['/docs/page_001.jpg']);
      expect(u.fileSizes, [10]);
    });

    test('LlmPromptConfig JSON round-trip preserves order and disabled blocks', () {
      final blocks = LlmPromptConfig.defaultSystemBlocks.reversed.toList();
      blocks[0] = blocks[0].copyWith(isEnabled: false);
      final cfg = LlmPromptConfig(systemBlocks: blocks);
      final back = LlmPromptConfig.fromJson(cfg.toJson());
      expect(back.systemBlocks.map((b) => b.id).toList(),
          blocks.map((b) => b.id).toList());
      expect(back.systemBlocks.first.isEnabled, isFalse);
    });

    test('custom block order and disabled blocks drive the system prompt', () {
      final byId = {for (final b in LlmPromptConfig.defaultSystemBlocks) b.id: b};
      final cfg = LlmPromptConfig(systemBlocks: [
        byId['outputFormat']!,
        byId['role']!.copyWith(isEnabled: false),
        byId['fieldSpecs']!,
      ]);
      final plan = GenerationPlan(
        template: template,
        patient: patient,
        rawChatStream: [],
        historicalRecords: [],
        promptConfig: cfg,
      );
      final sys = StagePromptCompiler.compile(
        plan: plan,
        batchSlots: [slotHpi],
        accumulatedOutputs: {},
      ).systemPrompt;
      expect(sys, isNot(contains('严谨、专业的文书助手')));
      expect(sys.indexOf('输出格式约束'), lessThan(sys.indexOf('字段规格列表')));
    });

    test('BackgroundTask models and cancel logic operate cleanly', () {
      final task = BackgroundTask(
        id: 't_1',
        type: TaskType.generation,
        patientId: 'p_1',
        patientName: '李四',
        title: '病历生成',
      );

      expect(task.isRunning, isTrue);
      expect(task.isDone, isFalse);

      task.cancelToken.cancel('主动取消');
      expect(task.cancelToken.isCancelled, isTrue);
    });

    test('CollateDocument multi-page bundling and cover path logic', () {
      final doc = CollateDocument(
        title: '文书 1',
        imagePaths: ['/tmp/page1.jpg', '/tmp/page2.jpg', '/tmp/page3.jpg'],
      );

      expect(doc.pageCount, 3);
      expect(doc.isMultiPage, isTrue);
      expect(doc.coverPath, '/tmp/page1.jpg');
    });

    test('StagePromptCompiler.compileFlatManualPrompt flattens all slots and formats prompt', () {
      final t = Template(
        id: 't_flat',
        name: '门诊病历',
        version: '1.0',
        slots: const [
          TemplateSlot(key: 'cc', label: '主诉', type: SlotType.text, required: true),
          TemplateSlot(key: 'hpi', label: '现病史', type: SlotType.multiline, required: true),
        ],
      );
      final p = Patient(id: 'p_flat', name: '王五', gender: Gender.male, age: 40);
      final plan = GenerationPlan(
        template: t,
        contentTemplate: null,
        patient: p,
        rawChatStream: [
          Message.text(patientId: 'p_flat', content: '头晕3天伴乏力'),
        ],
        historicalRecords: const [],
        promptConfig: const LlmPromptConfig(),
      );

      final prompt = StagePromptCompiler.compileFlatManualPrompt(plan);
      expect(prompt, contains('===== 系统要求与字段规范 ====='));
      expect(prompt, contains('主诉'));
      expect(prompt, contains('现病史'));
      expect(prompt, contains('王五'));
      expect(prompt, contains('头晕3天伴乏力'));
      expect(prompt, contains('===== 最终输出要求 ====='));

      // 验证贴回的内容解析
      const externalLlmOutput = '''
```json
{
  "cc": "发作性头晕3天",
  "hpi": "患者3天前无明显诱因出现头晕，伴乏力..."
}
```
''';
      final parsed = OutputSanitizer.sanitize(
        rawResponse: externalLlmOutput,
        batchSlots: t.sortedSlots,
      );
      expect(parsed['cc'], '发作性头晕3天');
      expect(parsed['hpi'], contains('伴乏力'));

      final issues = RecordValidator.validateAll(
        slots: t.sortedSlots,
        values: parsed,
      );
      expect(issues.isEmpty, isTrue);
    });
  });
}
