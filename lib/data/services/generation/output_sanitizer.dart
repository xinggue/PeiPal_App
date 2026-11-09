import 'dart:convert';

import '../../../domain/models/template.dart';

class OutputSanitizer {
  /// 提取并清洗模型返回的 JSON，映射到目标 [batchSlots]。
  ///
  /// 特性：
  /// 1. 宽容剥离 Markdown 围栏或前后思考、闲聊文本。
  /// 2. 支持大模型输出多个 JSON（如推理思考中草拟了一个 JSON，最终又给出了一个正式 JSON）：
  ///    从后向前智能查找完整合法的 JSON 对象并解析。
  /// 3. 键名对齐：优先匹配 key，也支持回落匹配中文 label。
  /// 4. 复杂结构智能展平：模型若返回嵌套 map/list，转为格式整齐的病历行，不输出 Dart toString()。
  /// 5. 彻底幻觉拦截：若有效槽位非空但完全没匹配到任何一个预期键名，抛出 FormatException 触发重试。
  static Map<String, String> sanitize({
    required String rawResponse,
    required List<TemplateSlot> batchSlots,
  }) {
    final decoded = _extractBestJsonObject(rawResponse);
    if (decoded == null) {
      throw const FormatException('LLM 输出中未找到有效的 JSON 对象');
    }

    final keyMap = {for (final s in batchSlots) s.key: s};
    final labelMap = {for (final s in batchSlots) s.label: s};

    final sanitizedResult = <String, String>{};
    var matchedExplicitKeys = 0;

    for (final entry in decoded.entries) {
      final rawKey = entry.key.toString().trim();
      // 优先查 key，其次查 label
      final slotSpec = keyMap[rawKey] ?? labelMap[rawKey];
      if (slotSpec == null) continue;

      matchedExplicitKeys++;
      final val = entry.value;
      sanitizedResult[slotSpec.key] = _flattenValue(val, slotSpec.defaultValue);
    }

    // 若本阶段有槽位，但没有匹配到任何一个目标字段（可能输出格式严重走样），抛出异常让 executor 重发重试
    if (batchSlots.isNotEmpty && matchedExplicitKeys == 0) {
      throw FormatException(
          'LLM 返回的键名(${decoded.keys.take(5).join(", ")})与本阶段字段不符');
    }

    // 补齐缺失字段的默认值
    for (final slot in batchSlots) {
      if (!sanitizedResult.containsKey(slot.key)) {
        sanitizedResult[slot.key] = slot.defaultValue ?? '';
      }
    }

    return sanitizedResult;
  }

  /// 从可能混杂推理文本、Markdown、重复 JSON 的原始模型响应中，提取出最合法的 JSON Map 对象
  static Map<String, dynamic>? _extractBestJsonObject(String text) {
    var cleaned = text.trim();

    // 1. 如果有 markdown 代码块标记，优先提取代码块内的内容
    final codeBlockPattern = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```', caseSensitive: false);
    final matches = codeBlockPattern.allMatches(cleaned).toList();
    if (matches.isNotEmpty) {
      // 优先看最后一个代码块（通常是模型的最终回答）
      for (final match in matches.reversed) {
        final content = match.group(1)?.trim();
        if (content != null && content.isNotEmpty) {
          final res = _tryParseJson(content);
          if (res != null) return res;
        }
      }
    }

    // 2. 尝试直接整段解析（针对纯 JSON 返回）
    final direct = _tryParseJson(cleaned);
    if (direct != null) return direct;

    // 3. 扫描文本中所有平衡的 {...} 括号区间
    final candidateMaps = _findAllJsonObjects(cleaned);
    if (candidateMaps.isNotEmpty) {
      // 优先返回最后一个完整合法的 JSON 对象（模型思考后给出的正式结果通常在最后）
      return candidateMaps.last;
    }

    // 4. 容错尝试：最前 { 到最后 }
    final start = cleaned.indexOf('{');
    final end = cleaned.lastIndexOf('}');
    if (start >= 0 && end > start) {
      final sub = cleaned.substring(start, end + 1);
      final res = _tryParseJson(sub);
      if (res != null) return res;
    }

    return null;
  }

  /// 扫描文本中所有语法平衡闭合的 JSON 对象
  static List<Map<String, dynamic>> _findAllJsonObjects(String text) {
    final results = <Map<String, dynamic>>[];
    final len = text.length;

    for (int i = 0; i < len; i++) {
      if (text[i] != '{') continue;

      int depth = 0;
      bool inString = false;
      bool escape = false;
      int endIndex = -1;

      for (int j = i; j < len; j++) {
        final c = text[j];

        if (escape) {
          escape = false;
          continue;
        }

        if (c == r'\') {
          escape = true;
          continue;
        }

        if (c == '"') {
          inString = !inString;
          continue;
        }

        if (!inString) {
          if (c == '{') {
            depth++;
          } else if (c == '}') {
            depth--;
            if (depth == 0) {
              endIndex = j;
              break;
            }
          }
        }
      }

      if (endIndex != -1) {
        final candidate = text.substring(i, endIndex + 1);
        final parsed = _tryParseJson(candidate);
        if (parsed != null) {
          results.add(parsed);
          // 跳过已解析的对象，寻找下一个独立对象
          i = endIndex;
        }
      }
    }

    return results;
  }

  static Map<String, dynamic>? _tryParseJson(String str) {
    final trimmed = str.trim();
    if (!trimmed.startsWith('{') || !trimmed.endsWith('}')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map) {
        return decoded.cast<String, dynamic>();
      }
    } catch (_) {}
    return null;
  }

  /// 智能展平值，避免产生 Dart 内部格式字符
  static String _flattenValue(dynamic val, String? defaultValue) {
    if (val == null) return defaultValue ?? '';

    if (val is String) {
      return val.trim();
    }

    if (val is List) {
      if (val.isEmpty) return '';
      // 如果是简单类型列表（如 checkbox 的多选结果）
      if (val.every((e) => e is! Map && e is! List)) {
        return val.map((e) => e.toString().trim()).join('，');
      }
      // 复杂列表：每个元素一行
      final lines = <String>[];
      for (int i = 0; i < val.length; i++) {
        final item = val[i];
        if (item is Map) {
          final parts = item.entries.map((e) => '${e.key}: ${e.value}').join(', ');
          lines.add('${i + 1}. $parts');
        } else {
          lines.add('${i + 1}. $item');
        }
      }
      return lines.join('\n');
    }

    if (val is Map) {
      // 键值对逐行展开
      final lines = <String>[];
      for (final e in val.entries) {
        lines.add('${e.key}：${e.value}');
      }
      return lines.join('\n');
    }

    return val.toString().trim();
  }
}
