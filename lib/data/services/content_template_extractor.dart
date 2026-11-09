import 'dart:convert';

import '../../domain/models/catalog_mention.dart';
import '../../domain/models/content_template.dart';
import '../../domain/models/template.dart';
import 'api/api_service.dart';
import 'api/extractor_config.dart';

/// Content extracted by the LLM for one field.
class ExtractedField {
  final String text;
  final String guidance;

  const ExtractedField({this.text = '', this.guidance = ''});

  bool get isEmpty => text.isEmpty && guidance.isEmpty;
}

class ExtractionResult {
  final Map<String, ExtractedField> fields;
  final String globalGuidance;

  const ExtractionResult({required this.fields, this.globalGuidance = ''});

  bool get isEmpty =>
      globalGuidance.isEmpty && fields.values.every((f) => f.isEmpty);
}

/// Splits a complete sample record into per-field template text, refines an
/// existing content template with new sample/instructions, or migrates a
/// content template across different document structures.
class ContentTemplateExtractor {
  final ApiService _api;

  ContentTemplateExtractor(this._api);

  static String _formatSlotList(List<TemplateSlot> slots) {
    final fieldLines = StringBuffer();
    for (final s in slots) {
      fieldLines.write('- ${s.key}：${s.label}（${_typeLabel(s.type)}');
      if (s.options != null && s.options!.isNotEmpty) {
        fieldLines.write('，选项：${s.options!.join('/')}');
      }
      fieldLines.writeln('）');
    }
    return fieldLines.toString();
  }

  static String _buildOutputScopeRule({
    required bool includeExamples,
    required bool includeGuidance,
  }) {
    if (includeExamples && includeGuidance) {
      return '同时生成各目标字段的「示范文本 (text)」与「撰写要求 (guidance)」以及「全文要求 (global_guidance)」。';
    } else if (includeExamples && !includeGuidance) {
      return '本次仅生成「示范文本 (text)」：所有字段的 guidance 及 global_guidance 一律输出空字符串 ""。';
    } else if (!includeExamples && includeGuidance) {
      return '本次仅生成「撰写要求 (guidance)」与「全文要求 (global_guidance)」：所有字段的 text 一律输出空字符串 ""。';
    }
    return '不生成任何内容。';
  }

  static String _renderSystemTemplate(
    String template, {
    required String fieldList,
    required String outputScopeRule,
    String targetDocName = '当前文书',
    String sourceDocName = '',
  }) {
    var out = template
        .replaceAll('{target_doc_name}', targetDocName)
        .replaceAll('{source_doc_name}', sourceDocName)
        .replaceAll('{output_scope_rule}', outputScopeRule);

    if (out.contains('{field_list}')) {
      out = out.replaceAll('{field_list}', fieldList);
    } else {
      out = '$out\n\n【本次需要生成的目标字段列表】：\n$fieldList';
    }
    return out.trim();
  }

  /// Legacy helper kept for compatibility: delegates to [buildRefinePrompt].
  static ({String system, String user}) buildPrompt(
    List<TemplateSlot> slots,
    String record, {
    ExtractorConfig? config,
  }) {
    return buildRefinePrompt(
      slots: slots,
      sampleRecord: record,
      config: config,
    );
  }

  /// Builds prompt for incremental refinement (or zero-state extraction when
  /// [currentFields] and [currentGlobalGuidance] are empty).
  static ({String system, String user}) buildRefinePrompt({
    required List<TemplateSlot> slots,
    String targetStructureName = '当前文书',
    String currentGlobalGuidance = '',
    Map<String, ExtractedField> currentFields = const {},
    String sampleRecord = '',
    String instruction = '',
    bool includeExamples = true,
    bool includeGuidance = true,
    ExtractorConfig? config,
  }) {
    final cfg = config ?? const ExtractorConfig();
    final fieldLines = _formatSlotList(slots);
    final scopeRule = _buildOutputScopeRule(
      includeExamples: includeExamples,
      includeGuidance: includeGuidance,
    );

    final system = _renderSystemTemplate(
      cfg.refinePromptTemplate,
      fieldList: fieldLines,
      outputScopeRule: scopeRule,
      targetDocName: targetStructureName,
    );

    final hasCurrent = currentGlobalGuidance.trim().isNotEmpty ||
        currentFields.values.any((f) => !f.isEmpty);

    final userBuf = StringBuffer();
    if (hasCurrent) {
      final currentJson = <String, dynamic>{
        'global_guidance': currentGlobalGuidance.trim(),
        'fields': {
          for (final s in slots)
            if (currentFields[s.key] != null && !currentFields[s.key]!.isEmpty)
              s.key: {
                'label': s.label,
                'text': currentFields[s.key]!.text,
                'guidance': currentFields[s.key]!.guidance,
              },
        },
      };
      userBuf
        ..writeln('【当前已有模板内容】：')
        ..writeln(const JsonEncoder.withIndent('  ').convert(currentJson))
        ..writeln();
    } else {
      userBuf.writeln('【当前已有模板内容】：（当前为空白模板）\n');
    }

    if (instruction.trim().isNotEmpty) {
      userBuf
        ..writeln('【补充细化指令】：')
        ..writeln(instruction.trim())
        ..writeln();
    }

    if (sampleRecord.trim().isNotEmpty) {
      userBuf
        ..writeln('【参考文书材料】：')
        ..writeln(sampleRecord.trim());
    }

    return (
      system: system,
      user: userBuf.toString().trim(),
    );
  }

  /// Builds prompt for migrating a content template from a source structure
  /// template to a target structure template.
  static ({String system, String user}) buildMigratePrompt({
    required String sourceStructureName,
    required List<TemplateSlot> sourceSlots,
    required ContentTemplate sourceContent,
    required String targetStructureName,
    required List<TemplateSlot> targetSlots,
    String instruction = '',
    bool includeExamples = true,
    bool includeGuidance = true,
    ExtractorConfig? config,
  }) {
    final cfg = config ?? const ExtractorConfig();
    final targetFieldLines = _formatSlotList(targetSlots);
    final scopeRule = _buildOutputScopeRule(
      includeExamples: includeExamples,
      includeGuidance: includeGuidance,
    );

    final system = _renderSystemTemplate(
      cfg.migratePromptTemplate,
      fieldList: targetFieldLines,
      outputScopeRule: scopeRule,
      targetDocName: targetStructureName,
      sourceDocName: sourceStructureName,
    );

    final sourceSlotLabelMap = {
      for (final s in sourceSlots) s.key: s.label,
    };

    // Pass full source context ( ordered by source structure slots ) so the LLM
    // can understand the entire clinical picture and synthesize/digest it
    // into target fields rather than doing naive key-by-key copying.
    final sourceItems = <Map<String, dynamic>>[];
    final visitedKeys = <String>{};

    for (final s in sourceSlots) {
      final slotContent = sourceContent.slots[s.key];
      if (slotContent == null || slotContent.isEmpty) continue;
      visitedKeys.add(s.key);
      final refs = slotContent.catalogRefs.isNotEmpty
          ? slotContent.catalogRefs
          : [
              for (final tag in slotContent.catalogTags)
                CatalogMentionRef(catalogType: '', tag: tag),
            ];
      var guidance = _ensureCatalogTokens(
        slotContent.guidance,
        refs,
        s.catalogType ?? 'diagnosis',
      );
      sourceItems.add({
        'source_label': s.label,
        if (slotContent.examples.isNotEmpty &&
            slotContent.examples.first.trim().isNotEmpty)
          'sample_text': slotContent.examples.first.trim(),
        if (guidance.trim().isNotEmpty) 'writing_guidance': guidance.trim(),
      });
    }

    for (final entry in sourceContent.slots.entries) {
      if (visitedKeys.contains(entry.key) || entry.value.isEmpty) continue;
      final label = sourceSlotLabelMap[entry.key] ?? entry.key;
      final refs = entry.value.catalogRefs.isNotEmpty
          ? entry.value.catalogRefs
          : [
              for (final tag in entry.value.catalogTags)
                CatalogMentionRef(catalogType: '', tag: tag),
            ];
      var guidance = _ensureCatalogTokens(
        entry.value.guidance,
        refs,
        'diagnosis',
      );
      sourceItems.add({
        'source_label': label,
        if (entry.value.examples.isNotEmpty &&
            entry.value.examples.first.trim().isNotEmpty)
          'sample_text': entry.value.examples.first.trim(),
        if (guidance.trim().isNotEmpty) 'writing_guidance': guidance.trim(),
      });
    }

    final userBuf = StringBuffer()
      ..writeln('【源文书类型】：$sourceStructureName')
      ..writeln('【目标文书类型】：$targetStructureName')
      ..writeln('【源内容模板名称】：${sourceContent.name}')
      ..writeln('【源模板内容（请消化理解后按「$targetStructureName」的字段要求改写重组，勿原样照抄）】：')
      ..writeln(const JsonEncoder.withIndent('  ').convert({
        if (sourceContent.globalGuidance.trim().isNotEmpty)
          'source_global_guidance': sourceContent.globalGuidance.trim(),
        'source_sections': sourceItems,
      }));

    if (instruction.trim().isNotEmpty) {
      userBuf
        ..writeln()
        ..writeln('【迁移附加要求】：')
        ..writeln(instruction.trim());
    }

    return (
      system: system,
      user: userBuf.toString().trim(),
    );
  }

  static String _ensureCatalogTokens(
    String guidance,
    List<CatalogMentionRef> refs,
    String fallbackCatalogType,
  ) {
    var result = guidance;
    for (final ref in refs) {
      final type = ref.catalogType.trim().isEmpty
          ? fallbackCatalogType
          : ref.catalogType;
      final token = '\uFFFC[CATALOG:$type:${ref.tag}]\uFFFC';
      if (!result.contains(token)) {
        result = result.isEmpty ? token : '$result $token';
      }
    }
    return result;
  }

  /// Preserves any CatalogMentionRef tokens from [oldGuidance] if the LLM
  /// accidentally stripped them during refinement.
  static String preserveCatalogMentions(
      String oldGuidance, String newGuidance) {
    if (oldGuidance.trim().isEmpty || newGuidance.trim().isEmpty) {
      return newGuidance;
    }
    final oldMentions = CatalogMentionHelper.parseMentions(oldGuidance);
    if (oldMentions.isEmpty) return newGuidance;

    var result = newGuidance;
    for (final m in oldMentions) {
      if (!result.contains('[CATALOG:${m.catalogType}:${m.tag}]')) {
        result = '$result ${m.token}';
      }
    }
    return result.trim();
  }

  /// Parses the LLM reply. Throws [FormatException] if it is not usable JSON.
  static ExtractionResult parseResponse(
    String raw,
    List<TemplateSlot> slots,
  ) {
    final start = raw.indexOf('{');
    final end = raw.lastIndexOf('}');
    if (start < 0 || end <= start) {
      throw const FormatException('模型返回中没有 JSON');
    }
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('模型返回的 JSON 不是对象');
    }

    final validKeys = slots.map((s) => s.key).toSet();
    final fields = <String, ExtractedField>{};
    final rawFields = decoded['fields'];
    if (rawFields is Map) {
      for (final e in rawFields.entries) {
        final key = e.key.toString();
        if (!validKeys.contains(key)) continue;
        final v = e.value;
        if (v is Map) {
          final f = ExtractedField(
            text: _asText(v['text']),
            guidance: _asText(v['guidance']),
          );
          if (!f.isEmpty) fields[key] = f;
        } else if (v != null) {
          // Tolerate a bare string value.
          final f = ExtractedField(text: _asText(v));
          if (!f.isEmpty) fields[key] = f;
        }
      }
    }

    return ExtractionResult(
      fields: fields,
      globalGuidance: _asText(decoded['global_guidance']),
    );
  }

  Future<ExtractionResult> _runWithRetry({
    required ({String system, String user}) prompt,
    required List<TemplateSlot> slots,
  }) async {
    FormatException? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      final raw = await _api.chatCompletion(
        systemPrompt: prompt.system,
        userPrompt: prompt.user,
      );
      try {
        return parseResponse(raw, slots);
      } on FormatException catch (e) {
        lastError = e;
      }
    }
    throw lastError ?? const FormatException('解析失败');
  }

  /// Legacy method: delegates to [refine].
  Future<ExtractionResult> extract({
    required List<TemplateSlot> slots,
    required String record,
    ExtractorConfig? config,
  }) async {
    return refine(
      slots: slots,
      sampleRecord: record,
      config: config,
    );
  }

  /// Calls the LLM to refine/supplement the current template state using
  /// a reference record and/or user instructions.
  Future<ExtractionResult> refine({
    required List<TemplateSlot> slots,
    String targetStructureName = '当前文书',
    String currentGlobalGuidance = '',
    Map<String, ExtractedField> currentFields = const {},
    String sampleRecord = '',
    String instruction = '',
    bool includeExamples = true,
    bool includeGuidance = true,
    ExtractorConfig? config,
  }) async {
    final cfg = config ?? const ExtractorConfig();
    final prompt = buildRefinePrompt(
      slots: slots,
      targetStructureName: targetStructureName,
      currentGlobalGuidance: currentGlobalGuidance,
      currentFields: currentFields,
      sampleRecord: sampleRecord,
      instruction: instruction,
      includeExamples: includeExamples,
      includeGuidance: includeGuidance,
      config: cfg,
    );
    final res = await _runWithRetry(
      prompt: prompt,
      slots: slots,
    );

    final filteredFields = <String, ExtractedField>{};
    for (final entry in res.fields.entries) {
      final oldG = currentFields[entry.key]?.guidance ?? '';
      final newG = includeGuidance
          ? preserveCatalogMentions(oldG, entry.value.guidance)
          : '';
      final newT = includeExamples ? entry.value.text : '';
      final f = ExtractedField(text: newT, guidance: newG);
      if (!f.isEmpty) {
        filteredFields[entry.key] = f;
      }
    }

    return ExtractionResult(
      fields: filteredFields,
      globalGuidance: includeGuidance ? res.globalGuidance : '',
    );
  }

  /// Calls the LLM to migrate a content template from another structure.
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
    final cfg = config ?? const ExtractorConfig();
    final prompt = buildMigratePrompt(
      sourceStructureName: sourceStructureName,
      sourceSlots: sourceSlots,
      sourceContent: sourceContent,
      targetStructureName: targetStructureName,
      targetSlots: targetSlots,
      instruction: instruction,
      includeExamples: includeExamples,
      includeGuidance: includeGuidance,
      config: cfg,
    );
    final res = await _runWithRetry(
      prompt: prompt,
      slots: targetSlots,
    );

    final filteredFields = <String, ExtractedField>{};
    for (final entry in res.fields.entries) {
      final f = ExtractedField(
        text: includeExamples ? entry.value.text : '',
        guidance: includeGuidance ? entry.value.guidance : '',
      );
      if (!f.isEmpty) {
        filteredFields[entry.key] = f;
      }
    }

    return ExtractionResult(
      fields: filteredFields,
      globalGuidance: includeGuidance ? res.globalGuidance : '',
    );
  }

  static String _asText(dynamic v) {
    if (v == null) return '';
    if (v is List) return v.map((e) => e.toString()).join('\n').trim();
    return v.toString().trim();
  }

  static String _typeLabel(SlotType t) => switch (t) {
        SlotType.text => '文本',
        SlotType.multiline => '多行文本',
        SlotType.dropdown => '下拉',
        SlotType.checkbox => '多选',
        SlotType.typedChoice => '按选项键入',
        SlotType.date => '日期',
      };
}
