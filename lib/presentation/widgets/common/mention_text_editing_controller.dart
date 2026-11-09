import 'package:flutter/material.dart';
import '../../../domain/models/catalog_definition.dart';
import '../../../domain/models/catalog_mention.dart';
import 'catalog_visuals.dart';

/// 自定义 Mention TextEditingController
/// - 底层保存完整文本（含 `\uFFFC[CATALOG:type:tag]\uFFFC`）
/// - 界面上将 Token 渲染为原子小胶囊 WidgetSpan
/// - 智能拦截删除/光标跳跃：当检测到删到了 Token 内部字符时，自动整块删除整个 Token，杜绝露出内部 `[CATALOG:...]`
class MentionTextEditingController extends TextEditingController {
  final BuildContext Function()? contextGetter;
  final Map<String, CatalogDefinition> Function()? catalogsGetter;

  MentionTextEditingController({
    super.text,
    this.contextGetter,
    this.catalogsGetter,
  });

  @override
  set value(TextEditingValue newValue) {
    // 监听文本变化，智能整块消除被破坏的半截 Token
    final sanitized = _sanitizeTokens(oldVal: value, newVal: newValue);
    super.value = sanitized;
  }

  /// 扫描所有 Token 区间：如果用户删掉了 Token 的一部分字符，直接整块裁掉
  TextEditingValue _sanitizeTokens({
    required TextEditingValue oldVal,
    required TextEditingValue newVal,
  }) {
    final oldText = oldVal.text;
    final newText = newVal.text;

    // 如果文本没有被缩短，或者根本没有 Token，直接放行
    if (newText.length >= oldText.length || !oldText.contains('\uFFFC[CATALOG:')) {
      return newVal;
    }

    // 找出 oldText 中所有完整的 Token 区间 [start, end)
    final tokens = _findTokenRanges(oldText);
    if (tokens.isEmpty) return newVal;

    // 用户删除操作所触碰的区域 (oldVal 的选择区，或单字符删除点)
    final delStart = newVal.selection.start;

    // 遍历看哪一个 token 破损了 (在 oldText 中存在，但在 newText 中被局部截断)
    for (final range in tokens) {
      final tokenStr = oldText.substring(range.start, range.end);
      if (!newText.contains(tokenStr)) {
        final cleanText = newText.replaceAll(RegExp(r'\uFFFC\[CATALOG:[^\]]*\]?\uFFFC?|\[CATALOG:[^\]]*\]?'), '');
        final offset = delStart.clamp(0, cleanText.length);
        return TextEditingValue(
          text: cleanText,
          selection: TextSelection.collapsed(offset: offset),
        );
      }
    }

    return newVal;
  }

  List<_TokenRange> _findTokenRanges(String text) {
    final list = <_TokenRange>[];
    var start = 0;
    while (start < text.length) {
      final tokenStart = text.indexOf('\uFFFC[CATALOG:', start);
      if (tokenStart == -1) break;
      final tokenEnd = text.indexOf(']\uFFFC', tokenStart);
      if (tokenEnd == -1) break;
      list.add(_TokenRange(tokenStart, tokenEnd + 2));
      start = tokenEnd + 2;
    }
    return list;
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final rawText = value.text;
    if (!CatalogMentionHelper.hasMentions(rawText)) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final catalogs = catalogsGetter?.call() ?? const <String, CatalogDefinition>{};
    final catalogNames = {
      for (final entry in catalogs.entries) entry.key: entry.value.name,
    };

    final children = <InlineSpan>[];
    var currentIdx = 0;

    while (currentIdx < rawText.length) {
      final tokenStart = rawText.indexOf('\uFFFC[CATALOG:', currentIdx);
      if (tokenStart == -1) {
        children.add(TextSpan(
          text: rawText.substring(currentIdx),
          style: style,
        ));
        break;
      }

      if (tokenStart > currentIdx) {
        children.add(TextSpan(
          text: rawText.substring(currentIdx, tokenStart),
          style: style,
        ));
      }

      final tokenEnd = rawText.indexOf(']\uFFFC', tokenStart);
      if (tokenEnd == -1) {
        children.add(TextSpan(
          text: rawText.substring(tokenStart),
          style: style,
        ));
        break;
      }

      final fullToken = rawText.substring(tokenStart, tokenEnd + 2);
      final rawInside = rawText.substring(tokenStart + 10, tokenEnd);
      final colonIdx = rawInside.indexOf(':');

      if (colonIdx != -1) {
        final catalogType = rawInside.substring(0, colonIdx).trim();
        final tag = rawInside.substring(colonIdx + 1).trim();
        final mention = CatalogMentionRef(catalogType: catalogType, tag: tag);

        final theme = Theme.of(context);
        final definition = catalogs[mention.catalogType];
        final accent = catalogColor(definition, theme);
        final chipColor = accent.withValues(alpha: 0.12);
        final textColor = accent;

        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: chipColor,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: textColor.withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(
                  catalogIcon(definition?.icon ?? mention.catalogType),
                  size: 11,
                  color: textColor,
                ),
                const SizedBox(width: 3),
                Text(
                  mention.displayChipText(catalogNames: catalogNames),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ));
      } else {
        children.add(TextSpan(text: fullToken, style: style));
      }

      currentIdx = tokenEnd + 2;
    }

    return TextSpan(style: style, children: children);
  }

  /// 插入单个 Mention Token
  void insertMention(CatalogMentionRef mention) {
    insertMentions([mention]);
  }

  /// 一次性插入多个 Mention Tokens，整合成连续原子胶囊
  void insertMentions(List<CatalogMentionRef> mentions) {
    if (mentions.isEmpty) return;

    final rawText = text;
    final sel = selection;

    var start = sel.start;
    var end = sel.end;
    if (start < 0 || end < 0) {
      start = rawText.length;
      end = rawText.length;
    }

    // 如果光标前一个字符是 '@'，则将该 '@' 替换掉
    if (start > 0 && rawText[start - 1] == '@') {
      start--;
    }

    final tokenStr = '${mentions.map((m) => m.token).join(" ")} ';
    final newText = rawText.replaceRange(start, end, tokenStr);
    final newCursorPos = start + tokenStr.length;

    value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );
  }
}

class _TokenRange {
  final int start;
  final int end;
  _TokenRange(this.start, this.end);
}
