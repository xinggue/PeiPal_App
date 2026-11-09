import 'dart:convert';

/// 把生成病历（recordJson）转成适合“打进电脑”的纯文本。
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
    return raw; // 不是合法 JSON 就当纯文本发
  }

  final lines = <String>[];
  _render(data, lines, '');
  final text = lines.join('\n');
  return text.isEmpty ? raw : text;
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
