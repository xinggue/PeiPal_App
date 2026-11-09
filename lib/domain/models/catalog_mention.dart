class CatalogMentionRef {
  final String catalogType; // catalog id, e.g. 'diagnosis', 'procedure', 'tcm'
  final String tag;

  const CatalogMentionRef({
    required this.catalogType,
    required this.tag,
  });

  /// Fallback display label for built-in catalogs. Prefer passing [catalogNames].
  String get catalogLabel => label();

  String label({Map<String, String>? catalogNames}) {
    final name = catalogNames?[catalogType];
    if (name != null && name.trim().isNotEmpty) return name;
    return switch (catalogType) {
      'procedure' => '手术',
      'diagnosis' => '诊断',
      _ => catalogType,
    };
  }

  String displayChipText({Map<String, String>? catalogNames}) =>
      '@$tag${label(catalogNames: catalogNames)}';

  String get token => '\uFFFC[CATALOG:$catalogType:$tag]\uFFFC';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CatalogMentionRef &&
          runtimeType == other.runtimeType &&
          catalogType == other.catalogType &&
          tag == other.tag;

  @override
  int get hashCode => Object.hash(catalogType, tag);

  @override
  String toString() => displayChipText();
}

class CatalogMentionHelper {
  static const String markerChar = '\uFFFC';

  // 正则匹配 Token：容错可选的 \uFFFC 定界符，保证无论是否保留了对象占位符都能稳健提取
  static final _mentionRegex = RegExp(
    r'\uFFFC?\[CATALOG:([a-zA-Z0-9_-]+):([^\]\uFFFC]+)\]\uFFFC?',
  );

  /// 检测文本中是否包含任何 Catalog Mention Token
  static bool hasMentions(String text) {
    return text.contains('[CATALOG:');
  }

  /// 从文本中提取所有引用的词库及标签（按出现顺序且去重）
  static List<CatalogMentionRef> parseMentions(String text) {
    if (!hasMentions(text)) return const [];

    final list = <CatalogMentionRef>[];
    final seen = <String>{};

    for (final match in _mentionRegex.allMatches(text)) {
      final catalogType = match.group(1)!.trim();
      final tag = match.group(2)!.trim();
      final key = '$catalogType:$tag';
      if (!seen.contains(key)) {
        seen.add(key);
        list.add(CatalogMentionRef(catalogType: catalogType, tag: tag));
      }
    }
    return list;
  }

  /// Replaces every mention token using [replacer].
  static String replaceMentions(
    String text,
    String Function(CatalogMentionRef ref) replacer,
  ) {
    if (!hasMentions(text)) return text;
    return text.replaceAllMapped(_mentionRegex, (match) {
      return replacer(CatalogMentionRef(
        catalogType: match.group(1)!.trim(),
        tag: match.group(2)!.trim(),
      ));
    });
  }

  /// 转换为给 LLM 大模型阅读的自然语言指示标记（如 [标准诊断库词条: 心内科]）
  static String toLlmReadableText(
    String text, {
    Map<String, String>? catalogNames,
  }) {
    if (!hasMentions(text)) return text;
    return text.replaceAllMapped(_mentionRegex, (match) {
      final ref = CatalogMentionRef(
        catalogType: match.group(1)!.trim(),
        tag: match.group(2)!.trim(),
      );
      return '[标准${ref.label(catalogNames: catalogNames)}词条: ${ref.tag}]';
    });
  }

  /// 转换为纯展示文本（如 @心内科诊断库）
  static String toDisplayText(
    String text, {
    Map<String, String>? catalogNames,
  }) {
    if (!hasMentions(text)) return text;
    return text.replaceAllMapped(_mentionRegex, (match) {
      final ref = CatalogMentionRef(
        catalogType: match.group(1)!.trim(),
        tag: match.group(2)!.trim(),
      );
      return '@${ref.tag}${ref.label(catalogNames: catalogNames)}';
    });
  }

  /// 清洗去除所有 Token，返回干净的纯文本指令
  static String stripMentions(String text) {
    if (!hasMentions(text)) return text;
    final clean = text.replaceAll(_mentionRegex, '');
    return clean.replaceAll(RegExp(r'\s{2,}'), ' ').trim();
  }
}
