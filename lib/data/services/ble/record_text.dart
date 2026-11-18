import 'dart:convert';

import '../../../domain/models/template.dart';

/// 把生成文书（recordJson）转成适合“打进电脑”的纯文本。
///
/// recordJson 是 LLM/管线输出的 JSON 字符串，直接逐字打会打出花括号。
/// 这里扁平化成“键：值”的普通文本行，汉字照打、多行回车交给固件映射成 Enter。
String buildTypingText(String? recordJson) {
  final raw = (recordJson ?? '').trim();
  if (raw.isEmpty) return '';

  dynamic data;
  try {
    data = json.decode(raw);
  } catch (_) {
    // 若外层像损坏的 JSON，不再原样把花括号与转义符吐给硬件或剪贴板
    if (raw.startsWith('{') || raw.startsWith('[')) {
      return '';
    }
    return raw;
  }

  final lines = <String>[];
  _render(data, lines, '');
  final text = lines.join('\n');
  return text;
}

/// 将已解析或原始的文书内容格式化为供复制/导出的可读全文（纯文本或 Markdown）。
String buildReadableRecordText({
  String? recordJson,
  Map<String, String>? values,
  List<TemplateSlot>? orderedSlots,
  String? title,
  bool markdown = false,
}) {
  final orderedMap = <String, String>{};
  if (values != null) {
    if (orderedSlots != null && orderedSlots.isNotEmpty) {
      for (final slot in orderedSlots) {
        final v = (values[slot.key] ?? '').trim();
        if (v.isNotEmpty) orderedMap[slot.label.isNotEmpty ? slot.label : slot.key] = v;
      }
      for (final e in values.entries) {
        final inSlots = orderedSlots.any((s) => s.key == e.key);
        if (!inSlots && e.value.trim().isNotEmpty) {
          orderedMap[e.key] = e.value.trim();
        }
      }
    } else {
      for (final e in values.entries) {
        if (e.value.trim().isNotEmpty) orderedMap[e.key] = e.value.trim();
      }
    }
  } else {
    final raw = (recordJson ?? '').trim();
    if (raw.isEmpty) return '';
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) {
        if (orderedSlots != null && orderedSlots.isNotEmpty) {
          for (final slot in orderedSlots) {
            final v = (decoded[slot.key]?.toString() ?? '').trim();
            if (v.isNotEmpty) {
              orderedMap[slot.label.isNotEmpty ? slot.label : slot.key] = v;
            }
          }
          for (final e in decoded.entries) {
            final k = e.key.toString();
            if (!orderedSlots.any((s) => s.key == k)) {
              final v = (e.value?.toString() ?? '').trim();
              if (v.isNotEmpty) orderedMap[k] = v;
            }
          }
        } else {
          for (final e in decoded.entries) {
            final v = (e.value?.toString() ?? '').trim();
            if (v.isNotEmpty) orderedMap[e.key.toString()] = v;
          }
        }
      } else {
        return buildTypingText(recordJson);
      }
    } catch (_) {
      return buildTypingText(recordJson);
    }
  }

  if (orderedMap.isEmpty) return '';

  final buf = StringBuffer();
  final cleanTitle = title?.trim() ?? '';
  if (markdown) {
    if (cleanTitle.isNotEmpty) {
      buf.writeln('# $cleanTitle');
      buf.writeln();
    }
    for (final e in orderedMap.entries) {
      buf.writeln('## ${e.key}');
      buf.writeln(e.value);
      buf.writeln();
    }
    return buf.toString().trimRight();
  }

  if (cleanTitle.isNotEmpty) {
    buf.writeln(cleanTitle);
    buf.writeln();
  }
  for (final e in orderedMap.entries) {
    buf.writeln('${e.key}：${e.value}');
  }
  return buf.toString().trimRight();
}

void _render(dynamic value, List<String> out, String prefix) {
  if (value is Map) {
    if (value.isEmpty) return;
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final childPrefix = prefix.isEmpty ? key : '$prefix · $key';
      _render(entry.value, out, childPrefix);
    }
  } else if (value is List) {
    if (value.isEmpty) return;
    if (value.every((e) => e is! Map && e is! List)) {
      out.add('$prefix：${value.join('、')}');
      return;
    }
    var i = 0;
    for (final item in value) {
      i++;
      if (item is Map) {
        for (final entry in item.entries) {
          _render(entry.value, out, '$prefix $i · ${entry.key}');
        }
      } else {
        _render(item, out, '$prefix $i');
      }
    }
  } else {
    final s = value == null ? '' : value.toString();
    if (s.trim().isNotEmpty) {
      out.add('$prefix：$s');
    }
  }
}
