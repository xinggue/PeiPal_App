import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// 将 HTML `<table>...</table>` 转换为标准 Markdown 表格，并清理会导致 flutter_markdown 吞字的块级 HTML 标签
String _convertHtmlTablesAndTags(String input) {
  var text = input;

  // 1. 将 <br> / <br/> 转为空格（避免破坏表格单行结构）
  final tableBlockRegex = RegExp(r'<table[^>]*>([\s\S]*?)<\/table>', caseSensitive: false);
  final trRegex = RegExp(r'<tr[^>]*>([\s\S]*?)<\/tr>', caseSensitive: false);
  final cellRegex = RegExp(r'<(?:td|th)[^>]*>([\s\S]*?)<\/(?:td|th)>', caseSensitive: false);
  final tagStripRegex = RegExp(r'<[^>]+>');

  text = text.replaceAllMapped(tableBlockRegex, (tableMatch) {
    final tableInner = tableMatch.group(1) ?? '';
    final rows = <List<String>>[];

    for (final trMatch in trRegex.allMatches(tableInner)) {
      final trInner = trMatch.group(1) ?? '';
      final cells = <String>[];
      for (final cellMatch in cellRegex.allMatches(trInner)) {
        var rawCell = cellMatch.group(1) ?? '';
        rawCell = rawCell
            .replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), ' ')
            .replaceAll(tagStripRegex, '')
            .replaceAll('\r', '')
            .replaceAll('\n', ' ')
            .replaceAll('|', '｜')
            .trim();
        cells.add(rawCell);
      }
      if (cells.isNotEmpty) {
        rows.add(cells);
      }
    }

    if (rows.isEmpty) return '';

    int maxCols = 0;
    for (final r in rows) {
      if (r.length > maxCols) maxCols = r.length;
    }
    if (maxCols == 0) return '';

    final buf = StringBuffer('\n\n');
    for (int i = 0; i < rows.length; i++) {
      final padded = List<String>.from(rows[i]);
      while (padded.length < maxCols) {
        padded.add('');
      }
      buf.writeln('| ${padded.join(' | ')} |');
      if (i == 0) {
        buf.writeln('|${List.filled(maxCols, ' --- ').join('|')}|');
      }
    }
    buf.write('\n');
    return buf.toString();
  });

  // 2. 清理剩余孤立的块级 HTML 外壳标签（防止 markdown HtmlBlockSyntax 在根节点生成裸 Text 被丢弃）
  text = text
      .replaceAll(RegExp(r'<\/?(?:html|body|div|span|thead|tbody|tfoot|p)[^>]*>', caseSensitive: false), '')
      .replaceAll(RegExp(r'<br\s*\/?>', caseSensitive: false), '\n');

  return text;
}

/// 切分单行 Markdown 表格的单元格列表
List<String> _splitTableCells(String line) {
  var stripped = line.trim();
  if (stripped.startsWith('|')) stripped = stripped.substring(1);
  if (stripped.endsWith('|')) stripped = stripped.substring(0, stripped.length - 1);
  return stripped.split('|').map((c) => c.trim()).toList();
}

/// 对 OCR 输出文本中的表格格式进行智能规范化：
/// 1. 转换 HTML <table> 为 Markdown 表格；
/// 2. 确保表格前有空行、自动补齐缺失的 `| --- |` 分隔行；
/// 3. 强制同一张表格的所有行列数严格对齐，杜绝 Flutter `Table` 因列数不齐抛异常导致后续内容截断消失。
String normalizeOcrMarkdownTables(String input) {
  final preCleaned = _convertHtmlTablesAndTags(input);
  final lines = preCleaned.split('\n');
  final output = <String>[];

  final tableLineRegex = RegExp(r'^\s*\|.*\|\s*$');
  final dividerCellRegex = RegExp(r'^:?-{2,}:?$');

  bool isDividerRow(List<String> cells) {
    return cells.isNotEmpty &&
        cells.every((c) => dividerCellRegex.hasMatch(c.replaceAll(' ', '')));
  }

  int i = 0;
  while (i < lines.length) {
    final line = lines[i];
    if (!tableLineRegex.hasMatch(line)) {
      output.add(line);
      i++;
      continue;
    }

    // 收集连续的表格行块
    final blockLines = <String>[];
    while (i < lines.length && tableLineRegex.hasMatch(lines[i])) {
      blockLines.add(lines[i]);
      i++;
    }

    if (blockLines.length < 2) {
      output.addAll(blockLines);
      continue;
    }

    // 确保表格块前有空行，防止紧贴段落文字导致 GFM 不识别表格
    if (output.isNotEmpty && output.last.trim().isNotEmpty) {
      output.add('');
    }

    final parsedRows = blockLines.map(_splitTableCells).toList();
    int colCount = parsedRows.first.length;
    for (final r in parsedRows) {
      if (!isDividerRow(r) && r.length > colCount) {
        colCount = r.length;
      }
    }
    if (colCount <= 0) colCount = 1;

    // 构建对齐后的表头
    List<String> normalizeRow(List<String> row, {bool isDivider = false}) {
      if (isDivider) {
        return List<String>.filled(colCount, '---');
      }
      final copy = List<String>.from(row);
      while (copy.length < colCount) {
        copy.add('');
      }
      if (copy.length > colCount) {
        final mergedTail = copy.sublist(colCount - 1).join(' ');
        return [...copy.sublist(0, colCount - 1), mergedTail];
      }
      return copy;
    }

    final header = normalizeRow(parsedRows.first);
    output.add('| ${header.join(' | ')} |');
    output.add('| ${List.filled(colCount, '---').join(' | ')} |');

    final startDataIdx =
        (parsedRows.length > 1 && isDividerRow(parsedRows[1])) ? 2 : 1;
    for (int r = startDataIdx; r < parsedRows.length; r++) {
      if (isDividerRow(parsedRows[r])) continue;
      final row = normalizeRow(parsedRows[r]);
      output.add('| ${row.join(' | ')} |');
    }

    // 确保表格块后也有空行，保证后续普通文本段落正常渲染
    output.add('');
  }

  return output.join('\n');
}

/// 弹出独立全屏/大窗口查看文书识别完整内容
/// 使用 Dialog 而非 AlertDialog，彻底避免 AlertDialog 内置 IntrinsicWidth 与 Table/ScrollView 冲突导致表格后内容消失及无法滚动
void showOcrTextDetailsDialog({
  required BuildContext context,
  required String title,
  required String text,
}) {
  final normalizedText = normalizeOcrMarkdownTables(text);

  showDialog(
    context: context,
    builder: (ctx) => _OcrTextDetailsDialogContent(
      title: title,
      rawText: text,
      normalizedText: normalizedText,
    ),
  );
}

class _OcrTextDetailsDialogContent extends StatefulWidget {
  final String title;
  final String rawText;
  final String normalizedText;

  const _OcrTextDetailsDialogContent({
    required this.title,
    required this.rawText,
    required this.normalizedText,
  });

  @override
  State<_OcrTextDetailsDialogContent> createState() =>
      _OcrTextDetailsDialogContentState();
}

class _OcrTextDetailsDialogContentState
    extends State<_OcrTextDetailsDialogContent> {
  final ScrollController _scrollController = ScrollController();
  bool _showRawText = false;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final dialogWidth = (media.size.width * 0.92).clamp(280.0, 640.0);
    final dialogHeight = (media.size.height * 0.72).clamp(320.0, 760.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部标题栏
              Row(
                children: [
                  const Icon(Icons.document_scanner_outlined,
                      color: Colors.teal, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Text(
                    '${widget.rawText.length} 字',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(width: 6),
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    icon: Icon(
                      _showRawText ? Icons.table_chart_outlined : Icons.subject,
                      size: 15,
                    ),
                    label: Text(
                      _showRawText ? '排版视图' : '纯文本',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: () =>
                        setState(() => _showRawText = !_showRawText),
                  ),
                ],
              ),
              const SizedBox(height: 10),

              // 中部可滚动内容区（外层明确给出有限宽高约束，彻底杜绝 Table / ScrollView 布局截断）
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Scrollbar(
                    controller: _scrollController,
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(12),
                      child: _showRawText
                          ? SelectableText(
                              widget.rawText,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: Colors.black87,
                              ),
                            )
                          : MarkdownBody(
                              data: widget.normalizedText,
                              shrinkWrap: true,
                              softLineBreak: true,
                              extensionSet: md.ExtensionSet.gitHubFlavored,
                              styleSheet: MarkdownStyleSheet(
                                p: const TextStyle(
                                    fontSize: 13,
                                    height: 1.45,
                                    color: Colors.black87),
                                h1: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    height: 1.4),
                                h2: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    height: 1.4),
                                h3: const TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: FontWeight.bold,
                                    height: 1.4),
                                listBullet: const TextStyle(
                                    fontSize: 13, height: 1.45),
                                tableHead: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                                tableBody: const TextStyle(
                                  fontSize: 12,
                                  height: 1.35,
                                  color: Colors.black87,
                                ),
                                tableColumnWidth: const FlexColumnWidth(),
                                tableBorder: TableBorder.all(
                                  color: Colors.grey.withValues(alpha: 0.35),
                                  width: 0.8,
                                ),
                                tableCellsPadding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 5),
                                code: const TextStyle(
                                    fontSize: 12, height: 1.4),
                                blockquotePadding:
                                    const EdgeInsets.only(left: 10),
                                blockquoteDecoration: BoxDecoration(
                                  border: Border(
                                    left: BorderSide(
                                      color:
                                          Colors.teal.withValues(alpha: 0.6),
                                      width: 3,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),

              // 底部操作按钮
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制全部'),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: widget.rawText));
                      showAppToast(context, '已复制识别全文到剪贴板');
                    },
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('关闭'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
