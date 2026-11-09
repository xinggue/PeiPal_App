import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 优雅的 G-Code 积木化指令流全屏预览页面
class GCodePreviewPage extends StatelessWidget {
  final String title;
  final String gcodeText;

  const GCodePreviewPage({
    super.key,
    required this.title,
    required this.gcodeText,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tokens = _tokenizeGCode(gcodeText);

    return Scaffold(
      appBar: AppBar(
        title: Text('代码预览 · $title'),
        actions: [
          IconButton(
            icon: const Icon(Icons.copy_all_rounded),
            tooltip: '复制指令文本',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: gcodeText));
              showAppToast(context, '已复制完整指令文本到剪贴板');
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. 顶部统计信息卡片
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.terminal_rounded, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  '指令步骤 (${tokens.length} 项 · ${gcodeText.length} 字符)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // 2. 积木化流式卡片渲染
          for (int i = 0; i < tokens.length; i++)
            _buildTokenBrick(context, i + 1, tokens[i], colorScheme),

          const SizedBox(height: 20),
          // 3. 原始文本源码折叠框
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
            ),
            child: ExpansionTile(
              title: const Text('查看原始指令字符串 (Raw Code)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
              childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: SelectableText(
                    gcodeText,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildTokenBrick(
    BuildContext context,
    int index,
    _GCodeToken token,
    ColorScheme colorScheme,
  ) {
    Color brickColor;
    IconData icon;
    String badgeText;

    switch (token.type) {
      case _TokenType.key:
        brickColor = Colors.amber.shade800;
        icon = Icons.keyboard_rounded;
        badgeText = '按键/组合键';
        break;
      case _TokenType.delay:
        brickColor = Colors.purple.shade600;
        icon = Icons.timer_outlined;
        badgeText = '停顿延时';
        break;
      case _TokenType.cfg:
        brickColor = Colors.deepOrange.shade600;
        icon = Icons.tune_rounded;
        badgeText = '时序调参';
        break;
      case _TokenType.done:
        brickColor = Colors.green.shade700;
        icon = Icons.check_circle_outline;
        badgeText = '完成回执';
        break;
      case _TokenType.text:
        brickColor = Colors.blue.shade700;
        icon = Icons.text_fields_rounded;
        badgeText = '字符文本';
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: brickColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: brickColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 11,
            backgroundColor: brickColor.withValues(alpha: 0.15),
            child: Text(
              '$index',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: brickColor),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: brickColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: brickColor),
                const SizedBox(width: 4),
                Text(
                  badgeText,
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: brickColor),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: SelectableText(
              token.content,
              style: TextStyle(
                fontFamily: token.type == _TokenType.text ? null : 'monospace',
                fontSize: 12.5,
                fontWeight: token.type == _TokenType.text ? FontWeight.normal : FontWeight.bold,
                color: token.type == _TokenType.text ? Colors.black87 : brickColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 将包含标签和文本的整段 G-Code 切分成结构化积木
  static List<_GCodeToken> _tokenizeGCode(String input) {
    final tokens = <_GCodeToken>[];
    if (input.isEmpty) return tokens;

    int i = 0;
    final len = input.length;
    final textBuf = StringBuffer();

    void flushText() {
      if (textBuf.isNotEmpty) {
        tokens.add(_GCodeToken(type: _TokenType.text, content: textBuf.toString()));
        textBuf.clear();
      }
    }

    while (i < len) {
      if (input[i] == '{') {
        final end = input.indexOf('}', i);
        if (end != -1) {
          flushText();
          final tag = input.substring(i, end + 1);
          final upper = tag.toUpperCase();

          if (upper.startsWith('{DELAY:')) {
            tokens.add(_GCodeToken(type: _TokenType.delay, content: tag));
          } else if (upper.startsWith('{CFG:') || upper == '{CFGSAVE}' || upper == '{CFGRESET}') {
            tokens.add(_GCodeToken(type: _TokenType.cfg, content: tag));
          } else if (upper.startsWith('{DONE')) {
            tokens.add(_GCodeToken(type: _TokenType.done, content: tag));
          } else {
            tokens.add(_GCodeToken(type: _TokenType.key, content: tag));
          }
          i = end + 1;
          continue;
        }
      }
      textBuf.write(input[i]);
      i++;
    }
    flushText();

    return tokens;
  }
}

enum _TokenType { key, delay, cfg, done, text }

class _GCodeToken {
  final _TokenType type;
  final String content;

  const _GCodeToken({required this.type, required this.content});
}
