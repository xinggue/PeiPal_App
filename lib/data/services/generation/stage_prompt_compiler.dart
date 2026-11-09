import 'package:intl/intl.dart';

import '../../../domain/generation/generation_plan.dart';
import '../../../domain/generation/standard_catalog.dart';
import '../../../domain/models/catalog_mention.dart';
import '../../../domain/models/message.dart';
import '../../../domain/models/patient.dart';
import '../../../domain/models/template.dart';
import '../processing_service.dart';

class CompiledBatchPrompt {
  final String systemPrompt;
  final String userPrompt;

  const CompiledBatchPrompt({
    required this.systemPrompt,
    required this.userPrompt,
  });
}

class StagePromptCompiler {
  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');

  /// Compiles system and user prompts for an execution batch.
  static CompiledBatchPrompt compile({
    required GenerationPlan plan,
    required List<TemplateSlot> batchSlots,
    required Map<String, String> accumulatedOutputs,
    String? batchPrompt, // node or group custom prompt
    String? batchTitle,
  }) {
    final systemBuffer = StringBuffer();
    final userBuffer = StringBuffer();

    // 1. Compile individual modular blocks content
    // Global guidance
    final globalGuidance = plan.contentTemplate?.globalGuidance.trim() ?? '';

    // Stage prompt
    final stagePrompt = batchPrompt?.trim() ?? '';

    // Field specifications
    final fieldSpecsBuffer = StringBuffer();
    for (final slot in batchSlots) {
      fieldSpecsBuffer.write('- 字段键名: "${slot.key}" (${slot.label}, 类型: ${_typeLabel(slot.type)}');
      if (slot.required) fieldSpecsBuffer.write(', 必填');
      if (slot.defaultValue != null) fieldSpecsBuffer.write(', 默认值: "${slot.defaultValue}"');
      if (slot.options != null && slot.options!.isNotEmpty) {
        fieldSpecsBuffer.write(', 可选范围: [${slot.options!.join(" / ")}]');
      }
      fieldSpecsBuffer.writeln(')');

      final slotContent = plan.contentTemplate?.slots[slot.key];
      final rawGuidance = slotContent?.guidance ?? '';

      // Per-slot guidance (将内部 \uFFFC Token 转换为 LLM 友好阅读的自然语言指示标记)
      if (rawGuidance.trim().isNotEmpty) {
        final llmGuidance = CatalogMentionHelper.toLlmReadableText(
          rawGuidance.trim(),
          catalogNames: _catalogNames(plan),
        );
        fieldSpecsBuffer.writeln('  * 撰写要求/约束: $llmGuidance');
      }

      // Per-slot examples (Few-shot)
      if (slotContent != null && slotContent.examples.isNotEmpty) {
        final nonEmptyEx = slotContent.examples
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
        if (nonEmptyEx.isNotEmpty) {
          fieldSpecsBuffer.writeln('  * 模板范文参考:');
          for (final ex in nonEmptyEx) {
            fieldSpecsBuffer.writeln('    "$ex"');
          }
        }
      }

      // Standard catalogs content (就近注入：紧随当前字段的撰写要求并列展开各个 @Mention 标签对应的词条)
      final mentions = CatalogMentionHelper.parseMentions(rawGuidance);
      if (mentions.isNotEmpty) {
        for (final m in mentions) {
          final availableEntries = plan.catalogEntriesByType[m.catalogType] ?? const [];
          final prompt = _compileSingleTagCatalogPrompt(
            catalogLabel: _catalogLabel(plan, m.catalogType),
            tag: m.tag,
            availableEntries: availableEntries,
          );
          if (prompt.isNotEmpty) {
            fieldSpecsBuffer.writeln(prompt);
          }
        }
      } else if (slot.catalogType != null && slot.catalogType!.isNotEmpty) {
        // 向后兼容旧模板
        final catalogType = slot.catalogType!;
        final availableEntries = plan.catalogEntriesByType[catalogType];
        if (availableEntries != null && availableEntries.isNotEmpty) {
          final prompt = _compileLegacyCatalogPrompt(
            catalogLabel: _catalogLabel(plan, catalogType),
            catalogTags: slotContent?.catalogTags ?? const [],
            availableEntries: availableEntries,
          );
          if (prompt.isNotEmpty) {
            fieldSpecsBuffer.writeln(prompt);
          }
        }
      }
    }

    // Assemble System Prompt strictly in the order and phrasing of enabled blocks!
    final blocks = plan.promptConfig.effectiveSystemBlocks;
    for (final block in blocks) {
      if (!block.isEnabled) continue;

      switch (block.id) {
        case 'role':
          var text = block.templateText
              .replaceAll('{document_title}', plan.template.name);
          if (text.trim().isNotEmpty) systemBuffer.writeln('$text\n');
          break;

        case 'globalGuidance':
          if (globalGuidance.isNotEmpty) {
            var text = block.templateText
                .replaceAll('{global_guidance}', globalGuidance);
            if (text.trim().isNotEmpty) systemBuffer.writeln('$text\n');
          }
          break;

        case 'stageCustomPrompt':
          if (stagePrompt.isNotEmpty) {
            var text = block.templateText
                .replaceAll('{stage_title}', batchTitle ?? '当前批次')
                .replaceAll('{stage_prompt}', stagePrompt);
            if (text.trim().isNotEmpty) systemBuffer.writeln('$text\n');
          }
          break;

        case 'fieldSpecs':
          if (fieldSpecsBuffer.isNotEmpty) {
            var text = block.templateText
                .replaceAll('{field_specs}', fieldSpecsBuffer.toString().trim());
            if (text.trim().isNotEmpty) systemBuffer.writeln('$text\n');
          }
          break;

        case 'standardCatalogs':
          // 标准术语参考已就近内聚编译在各字段规格中，此块不再重复输出
          break;

        case 'outputFormat':
          if (block.templateText.trim().isNotEmpty) {
            systemBuffer.writeln('${block.templateText.trim()}\n');
          }
          break;

        default:
          if (block.templateText.trim().isNotEmpty) {
            systemBuffer.writeln('${block.templateText.trim()}\n');
          }
      }
    }

    // ---------------- User Prompt ----------------

    // 0. Generation Timestamp Baseline (锚定当前时间，便于推算病程/病期)
    final refTime = plan.now ?? DateTime.now();
    final timeStr = _dateFormat.format(refTime);
    final weekdayStr = switch (refTime.weekday) {
      1 => '星期一',
      2 => '星期二',
      3 => '星期三',
      4 => '星期四',
      5 => '星期五',
      6 => '星期六',
      7 => '星期日',
      _ => '',
    };
    userBuffer.writeln('【当前生成时间】：$timeStr ($weekdayStr)\n');

    // 1. Patient Baseline Profile
    userBuffer.writeln('【会话基础信息】：');
    userBuffer.write('名称: ${_maskName(plan.patient.name)}，性别: ${plan.patient.gender.label}');
    if (plan.patient.age != null) userBuffer.write('，年龄: ${plan.patient.age}岁');
    if (plan.patient.medicalRecordNumber != null &&
        plan.patient.medicalRecordNumber!.isNotEmpty) {
      userBuffer.write('，编号: ${plan.patient.medicalRecordNumber}');
    }
    if (plan.patient.notes != null && plan.patient.notes!.isNotEmpty) {
      userBuffer.write('\n备注: ${plan.patient.notes}');
    }
    userBuffer.writeln();

    // 2. Historical Past Medical Records (历次已生成病历卡片，完整传入)
    if (plan.historicalRecords.isNotEmpty) {
      userBuffer.writeln('\n【既往已生成文书背景 (请保持前后连贯一致)】：');
      for (int i = 0; i < plan.historicalRecords.length; i++) {
        final m = plan.historicalRecords[i];
        final timeStr = _dateFormat.format(m.createdAt);
        userBuffer.writeln('--- 历史文书 #${i + 1} ($timeStr) ---');
        userBuffer.writeln(m.recordJson ?? '');
      }
    }

    // 3. Accumulated Prior Stage Outputs (前置阶段已生成的字段，保持因果一致)
    if (accumulatedOutputs.isNotEmpty) {
      userBuffer.writeln('\n【前置阶段已生成的文书字段 (当前阶段须以此为事实根据)】：');
      for (final e in accumulatedOutputs.entries) {
        userBuffer.writeln('${e.key}: ${e.value}');
      }
    }

    // 4. Chat & Materials Stream (聊天记录、语音识别、图片OCR材料识别)
    userBuffer.writeln('\n【本次聊天记录与材料】：');
    if (plan.rawChatStream.isEmpty) {
      userBuffer.writeln('(暂无其他聊天记录，请根据上方基础信息与历史文书规范生成)');
    } else {
      for (final m in plan.rawChatStream) {
        final timeStr = _dateFormat.format(m.createdAt);
        final senderLabel =
            m.sender == MessageSender.user ? '用户消息' : '系统消息';

        final textContent = m.content?.trim() ?? '';
        // 识别失败的占位文本不是临床素材，直接丢弃
        final asrContent = ProcessingService.isFailureText(m.transcribedText)
            ? ''
            : (m.transcribedText?.trim() ?? '');
        final ocrContent = ProcessingService.isFailureText(m.extractedText)
            ? ''
            : (m.extractedText?.trim() ?? '');

        if (ocrContent.isNotEmpty) {
          final prefix = m.type == MessageType.document ? '文件文档提取' : '材料OCR识别';
          userBuffer.writeln('[$timeStr] [$prefix] $ocrContent');
        } else if (asrContent.isNotEmpty) {
          userBuffer.writeln('[$timeStr] [语音转写] $asrContent');
        } else if (textContent.isNotEmpty) {
          userBuffer.writeln('[$timeStr] [$senderLabel] $textContent');
        }
      }
    }

    // 5. Special Clinical Instructions / Extra Requirements from Clinician
    if (plan.extraInstructions != null &&
        plan.extraInstructions!.trim().isNotEmpty) {
      userBuffer.writeln('\n【本次生成特别补充要求与指示 (最高优先级准则)】：');
      userBuffer.writeln(plan.extraInstructions!.trim());
    }

    return CompiledBatchPrompt(
      systemPrompt: systemBuffer.toString().trim(),
      userPrompt: userBuffer.toString().trim(),
    );
  }

  /// 为单个 @Mention 标签就近编译其词条列表
  static String _compileSingleTagCatalogPrompt({
    required String catalogLabel,
    required String tag,
    required List<CatalogItem> availableEntries,
  }) {
    final cleanTag = tag.trim().toLowerCase();
    final filtered = availableEntries
        .where((item) => item.tags.any((t) => t.trim().toLowerCase() == cleanTag))
        .toList();
    if (filtered.isEmpty) {
      return '  * [标准$catalogLabel词条: $tag] 包含的规范名称及编码：(词库中暂无此标签词条)';
    }

    final b = StringBuffer('  * [标准$catalogLabel词条: $tag] 包含的规范名称及编码：\n');
    for (final item in filtered) {
      b.write('    - ${item.name}');
      if (item.code.isNotEmpty) b.write(' (${item.code})');
      if (item.note != null && item.note!.isNotEmpty) {
        b.write(' [${item.note}]');
      }
      b.writeln();
    }
    return b.toString().trimRight();
  }

  /// 兼容旧 slot.catalogType 的编译辅助
  static String _compileLegacyCatalogPrompt({
    required String catalogLabel,
    required List<String> catalogTags,
    required List<CatalogItem> availableEntries,
  }) {
    List<CatalogItem> targetList = availableEntries;
    if (catalogTags.isNotEmpty) {
      final filtered = availableEntries
          .where((item) => item.tags.any((t) => catalogTags.contains(t)))
          .toList();
      if (filtered.isNotEmpty) {
        targetList = filtered;
      }
    }

    if (targetList.isEmpty) return '';

    final b = StringBuffer('  * [标准$catalogLabel词条参考]：\n');
    for (final item in targetList) {
      b.write('    - ${item.name}');
      if (item.code.isNotEmpty) b.write(' (${item.code})');
      if (item.note != null && item.note!.isNotEmpty) {
        b.write(' [${item.note}]');
      }
      b.writeln();
    }
    return b.toString().trimRight();
  }

  /// 平铺编译完整单阶段 Prompt（用于手动挡：无多阶段切分，将所有字段要求与全部上下文材料平铺拼装）
  static String compileFlatManualPrompt(GenerationPlan plan) {
    final effectiveSlotList = plan.selectedSlotKeys != null
        ? plan.template.sortedSlots
            .where((s) => plan.selectedSlotKeys!.contains(s.key))
            .toList()
        : plan.template.sortedSlots;

    final compiled = compile(
      plan: plan,
      batchSlots: effectiveSlotList,
      accumulatedOutputs: const {},
      batchTitle: '完整文书生成',
    );

    final exampleKeys = effectiveSlotList.take(3).map((s) => '  "${s.key}": "..."').join(',\n');

    return '''
===== 系统要求与字段规范 =====
${compiled.systemPrompt.trim()}

===== 会话信息与材料流水 =====
${compiled.userPrompt.trim()}

===== 最终输出要求 =====
请综合上述会话全部材料与书写要求，直接输出包含上方所有字段键名的纯 JSON 对象。
不要添加多余的聊天引言、解释或非 JSON 字符。
格式示例：
```json
{
$exampleKeys
}
```'''.trim();
  }

  static String _catalogLabel(GenerationPlan plan, String catalogType) {
    final configured = plan.catalogs[catalogType]?.name;
    if (configured != null && configured.trim().isNotEmpty) return configured;
    return switch (catalogType) {
      'procedure' => '手术',
      'diagnosis' => '诊断',
      _ => catalogType,
    };
  }

  static Map<String, String> _catalogNames(GenerationPlan plan) {
    final names = {
      for (final entry in plan.catalogs.entries) entry.key: entry.value.name,
    };
    names.putIfAbsent('diagnosis', () => '诊断');
    names.putIfAbsent('procedure', () => '手术');
    return names;
  }

  /// 对患者姓名做轻度模糊：超过 2 个字符时保留首尾，中间逐字替换为 *。
  static String _maskName(String name) {
    final value = name.trim();
    final chars = value.runes.toList();
    if (chars.length <= 2) return value;

    final buffer = StringBuffer(String.fromCharCode(chars.first));
    for (var i = 1; i < chars.length - 1; i++) {
      buffer.write('*');
    }
    buffer.write(String.fromCharCode(chars.last));
    return buffer.toString();
  }

  static String _typeLabel(SlotType t) => switch (t) {
        SlotType.text => '文本',
        SlotType.multiline => '多行文本',
        SlotType.dropdown => '下拉单选',
        SlotType.checkbox => '多选',
        SlotType.typedChoice => '按选项键入',
        SlotType.date => '日期',
      };
}
