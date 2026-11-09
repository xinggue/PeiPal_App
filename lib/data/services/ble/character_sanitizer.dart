import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/settings_repository.dart';
import '../../../providers/providers.dart';

/// 固件已能直接打出的字符。旧版规则库里若还留着这些映射，加载时丢掉，避免误替换。
const Set<String> kFirmwarePrintableChars = {
  '°', '±', '·', '×', '÷', '§', '¤',
  '—', '…', '‰', '℃', '№',
  'Ⅰ', 'Ⅱ', 'Ⅲ', 'Ⅳ', 'Ⅴ', 'Ⅵ', 'Ⅶ', 'Ⅷ', 'Ⅸ', 'Ⅹ', 'Ⅺ', 'Ⅻ',
  '√', '∴', '∵', '≈', '≠', '≤', '≥', '∞',
  '①', '②', '③', '④', '⑤', '⑥', '⑦', '⑧', '⑨', '⑩',
  '←', '↑', '→', '↓',
  '◆', '◇', '■', '□', '▲', '△', '▼', '▽', '●', '○', '★', '☆',
  'Α', 'Β', 'Γ', 'Δ', 'Ε', 'Ζ', 'Η', 'Θ', 'Ι', 'Κ', 'Λ', 'Μ',
  'Ν', 'Ξ', 'Ο', 'Π', 'Ρ', 'Σ', 'Τ', 'Υ', 'Φ', 'Χ', 'Ψ', 'Ω',
  'α', 'β', 'γ', 'δ', 'ε', 'ζ', 'η', 'θ', 'ι', 'κ', 'λ', 'μ',
  'ν', 'ξ', 'ο', 'π', 'ρ', 'σ', 'τ', 'υ', 'φ', 'χ', 'ψ', 'ω',
  'µ', 'Ω',
};

/// 默认内置转换规则。℃ ± ≤ ≥ 希腊字母等固件已能打出，不再内置替换。
/// 仅保留正文半角花括号（防控制标签冲突）和 GBK 打不出的冷门标记。
/// 上标在这台键盘上打不出来，一律写成 ^n。
const Map<String, String> kSuperscriptRules = {
  '⁰': '^0',
  '¹': '^1',
  '²': '^2',
  '³': '^3',
  '⁴': '^4',
  '⁵': '^5',
  '⁶': '^6',
  '⁷': '^7',
  '⁸': '^8',
  '⁹': '^9',
  '⁺': '^+',
  '⁻': '^-',
  'ⁿ': '^n',
};

const Map<String, String> kDefaultReplacementRules = {
  '{': '｛',
  '}': '｝',
  '‘': '\'',
  '’': '\'',
  '“': '"',
  '”': '"',
  '℉': '度F',
  '•': '·',
  '®': '(R)',
  '©': '(C)',
  '™': '(TM)',
  ...kSuperscriptRules,
};

/// 字符清洗与校验服务：基于固件物理白名单
class CharacterSanitizer {
  /// 固件特殊符号表白名单 (已内置到固件中的 U+00A0..02FF 与 U+2000..26FF 常用符号)
  static const Set<int> _supportedSpecialCodepoints = {
    0x00B0, // °
    0x00B1, // ±
    0x00B7, // ·
    0x00D7, // ×
    0x00F7, // ÷
    0x00A7, // §
    0x00A4, // ¤
    0x2014, // —
    0x2026, // …
    0x2030, // ‰
    0x2103, // ℃
    0x2116, // №
    // 罗马数字 Ⅰ ~ Ⅻ
    0x2160, 0x2161, 0x2162, 0x2163, 0x2164, 0x2165,
    0x2166, 0x2167, 0x2168, 0x2169, 0x216A, 0x216B,
    // 数学符号
    0x221A, 0x2234, 0x2235, 0x2248, 0x2260, 0x2264, 0x2265, 0x221E,
    // 带圈数字 ① ~ ⑩
    0x2460, 0x2461, 0x2462, 0x2463, 0x2464, 0x2465, 0x2466, 0x2467, 0x2468, 0x2469,
    // 箭头与几何形状
    0x2190, 0x2191, 0x2192, 0x2193,
    0x25C6, 0x25C7, 0x25A0, 0x25A1, 0x25B2, 0x25B3, 0x25BC, 0x25BD,
    0x25CF, 0x25CB, 0x2605, 0x2606,
    // 希腊字母 Α..Ω / α..ω（跳过空位 U+03A2），以及同形 µ / Ω
    0x0391, 0x0392, 0x0393, 0x0394, 0x0395, 0x0396, 0x0397, 0x0398, 0x0399, 0x039A,
    0x039B, 0x039C, 0x039D, 0x039E, 0x039F, 0x03A0, 0x03A1, 0x03A3, 0x03A4, 0x03A5,
    0x03A6, 0x03A7, 0x03A8, 0x03A9,
    0x03B1, 0x03B2, 0x03B3, 0x03B4, 0x03B5, 0x03B6, 0x03B7, 0x03B8, 0x03B9, 0x03BA,
    0x03BB, 0x03BC, 0x03BD, 0x03BE, 0x03BF, 0x03C0, 0x03C1, 0x03C3, 0x03C4, 0x03C5,
    0x03C6, 0x03C7, 0x03C8, 0x03C9,
    0x00B5, // µ
    0x2126, // Ω
  };

  /// 固件原生支持字符白名单校验 (ASCII + 常用汉字 + CJK标点 + 全角标点 + 特殊符号扩展 - 半角花括号敏感字符)
  static bool isSupportedByFirmware(int codepoint) {
    // 特别说明：半角英文花括号 '{' (0x7B) 和 '}' (0x7D) 在正文中必须被视作需提示转换字符，以防破坏固件控制标签
    if (codepoint == 0x7B || codepoint == 0x7D) {
      return false;
    }
    // 1. 控制字符：换行 \n (10), \r (13), 制表符 \t (9)
    if (codepoint == 0x0A || codepoint == 0x0D || codepoint == 0x09) {
      return true;
    }
    // 2. ASCII 可打印字符 (0x20 ~ 0x7E，除 {} 之外)
    if (codepoint >= 0x20 && codepoint <= 0x7E) {
      return true;
    }
    // 3. 中文常用汉字区 (0x4E00 ~ 0x9FA5)
    if (codepoint >= 0x4E00 && codepoint <= 0x9FA5) {
      return true;
    }
    // 4. 中日韩标点符号区 (0x3000 ~ 0x303F)
    if (codepoint >= 0x3000 && codepoint <= 0x303F) {
      return true;
    }
    // 5. 全角 ASCII 与中文全角标点符号 (0xFF00 ~ 0xFFEF，包含全角 ｛ ｝)
    if (codepoint >= 0xFF00 && codepoint <= 0xFFEF) {
      return true;
    }
    // 6. 固件内置特殊医疗与符号表 (U+00A0..02FF, U+2000..26FF)
    if (_supportedSpecialCodepoints.contains(codepoint)) {
      return true;
    }
    return false;
  }

  /// 扫描文本中不被固件直接支持或敏感的字符集合（自动跳过 G-Code/控制标签 `{...}`）
  static Set<String> findUnsupportedCharacters(String text) {
    final unsupported = <String>{};
    // 提前应用默认转义（如中文单双引号自动转为标准引号），避免对已能优雅转义的字符误报
    final textAfterDefaults = applyReplacements(text, kDefaultReplacementRules);
    final stripped = _stripTags(textAfterDefaults);

    for (final char in stripped.runes) {
      if (!isSupportedByFirmware(char)) {
        unsupported.add(String.fromCharCode(char));
      }
    }
    return unsupported;
  }

  /// 扫描文本中是否包含可能引发指令冲突的正文半角花括号 `{` 或 `}`
  static bool hasBracesInText(String text) {
    final stripped = _stripTags(text);
    return stripped.contains('{') || stripped.contains('}');
  }

  static final RegExp _controlTagPattern =
      RegExp(r'\{[A-Za-z0-9_:\+\-\?=\.\s]+\}');

  /// 过滤花括号控制标签后进行内容检测
  static String _stripTags(String text) {
    return text.replaceAll(_controlTagPattern, '');
  }

  /// 按照替换规则字典执行忠实替换（自动保护合法的硬件控制标签 `{...}` 不被 `{` `}` 规则拆毁）
  static String applyReplacements(String text, Map<String, String> rules) {
    if (rules.isEmpty || text.isEmpty) return text;

    final sortedKeys = rules.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));

    String replaceSegment(String seg) {
      var res = seg;
      for (final key in sortedKeys) {
        final val = rules[key] ?? '';
        res = res.replaceAll(key, val);
      }
      return res;
    }

    final buffer = StringBuffer();
    int lastEnd = 0;
    for (final match in _controlTagPattern.allMatches(text)) {
      if (match.start > lastEnd) {
        buffer.write(replaceSegment(text.substring(lastEnd, match.start)));
      }
      buffer.write(match.group(0));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      buffer.write(replaceSegment(text.substring(lastEnd)));
    }
    return buffer.toString();
  }
}

// ---- Riverpod State Provider ----

final charReplacementRulesProvider =
    StateNotifierProvider<CharReplacementNotifier, Map<String, String>>((ref) {
  return CharReplacementNotifier(ref.read(settingsRepositoryProvider));
});

class CharReplacementNotifier extends StateNotifier<Map<String, String>> {
  final SettingsRepository _repo;

  CharReplacementNotifier(this._repo) : super(kDefaultReplacementRules) {
    _load();
  }

  Future<void> _load() async {
    final raw = await _repo.get('char_replacement_rules');
    if (raw == null || raw.trim().isEmpty) return;
    try {
      final decoded = json.decode(raw);
      if (decoded is Map) {
        final loaded = Map<String, String>.from(
          decoded.map((k, v) => MapEntry(k.toString(), v.toString())),
        );
        loaded.removeWhere((k, _) => kFirmwarePrintableChars.contains(k));
        for (final e in kDefaultReplacementRules.entries) {
          loaded.putIfAbsent(e.key, () => e.value);
        }
        state = loaded;
        if (loaded.length != decoded.length) {
          await _repo.set('char_replacement_rules', json.encode(loaded));
        }
      }
    } catch (_) {}
  }

  Future<void> saveRule(String from, String to) async {
    final updated = Map<String, String>.from(state);
    updated[from] = to;
    state = updated;
    await _repo.set('char_replacement_rules', json.encode(updated));
  }

  /// 批量合并保存新规则到规则库
  Future<void> saveRules(Map<String, String> newRules) async {
    if (newRules.isEmpty) return;
    final updated = Map<String, String>.from(state)..addAll(newRules);
    state = updated;
    await _repo.set('char_replacement_rules', json.encode(updated));
  }

  Future<void> deleteRule(String from) async {
    final updated = Map<String, String>.from(state);
    updated.remove(from);
    state = updated;
    await _repo.set('char_replacement_rules', json.encode(updated));
  }

  Future<void> resetToDefaults() async {
    state = Map<String, String>.from(kDefaultReplacementRules);
    await _repo.set('char_replacement_rules', json.encode(state));
  }
}
