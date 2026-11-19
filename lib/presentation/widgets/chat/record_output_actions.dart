import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/services/ble/record_text.dart';
import '../../../data/services/engine_c/config_file_io.dart';
import '../../../domain/models/template.dart';
import '../common/app_toast.dart';
import '../common/export_action_sheet.dart';

/// 生成文书的纯软件输出操作（复制全文 / 导出或分享文件），供审阅页、文书管理页与聊天流复用。
class RecordOutputActions {
  static Future<void> copyRecord(
    BuildContext context, {
    String? recordJson,
    Map<String, String>? values,
    List<TemplateSlot>? orderedSlots,
    String? title,
    String successMessage = '已复制文书全文',
  }) async {
    final text = buildReadableRecordText(
      recordJson: recordJson,
      values: values,
      orderedSlots: orderedSlots,
      title: title,
    );
    if (text.isEmpty) {
      if (context.mounted) showAppToast(context, '没有可复制的内容');
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (context.mounted) showAppToast(context, successMessage);
  }

  static Future<void> exportRecordFile(
    BuildContext context, {
    String? recordJson,
    Map<String, String>? values,
    List<TemplateSlot>? orderedSlots,
    String? title,
  }) async {
    final plainText = buildReadableRecordText(
      recordJson: recordJson,
      values: values,
      orderedSlots: orderedSlots,
      title: title,
    );
    if (plainText.isEmpty) {
      if (context.mounted) showAppToast(context, '没有可导出的内容');
      return;
    }
    final markdownText = buildReadableRecordText(
      recordJson: recordJson,
      values: values,
      orderedSlots: orderedSlots,
      title: title,
      markdown: true,
    );
    final prefix = (title?.trim().isNotEmpty == true) ? title!.trim() : '文书记录';

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => _RecordExportSheet(
        prefix: prefix,
        plainText: plainText,
        markdownText: markdownText,
      ),
    );
  }
}

class _RecordExportSheet extends StatefulWidget {
  final String prefix;
  final String plainText;
  final String markdownText;

  const _RecordExportSheet({
    required this.prefix,
    required this.plainText,
    required this.markdownText,
  });

  @override
  State<_RecordExportSheet> createState() => _RecordExportSheetState();
}

class _RecordExportSheetState extends State<_RecordExportSheet> {
  bool _isMarkdown = false;
  bool _busy = false;

  String get _ext => _isMarkdown ? 'md' : 'txt';
  String get _mimeType => _isMarkdown ? 'text/markdown' : 'text/plain';
  String get _content => _isMarkdown ? widget.markdownText : widget.plainText;

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final fileName = ConfigFileIo.buildFileName(widget.prefix, extension: _ext);
      final ok = await ConfigFileIo.shareTextFile(
        content: _content,
        fileName: fileName,
        mimeType: _mimeType,
        subject: widget.prefix,
      );
      if (!mounted) return;
      if (ok) {
        Navigator.pop(context);
      } else {
        setState(() => _busy = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, '分享失败：$e');
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final suggestedName = ConfigFileIo.buildFileName(
        widget.prefix,
        extension: _ext,
      );
      final saved = await ConfigFileIo.saveConfigTextFile(
        content: _content,
        suggestedName: suggestedName,
        typeLabel: '文书文件',
        extensions: [_ext],
      );
      if (!mounted) return;
      Navigator.pop(context);
      if (saved == null) {
        showAppToast(context, '已取消导出');
      } else {
        showSavedFileNotice(
          context,
          message: '已导出文书文件',
          savedPath: saved,
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, '导出失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final supportsShare = ConfigFileIo.supportsSystemShare;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '导出文书',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(
                  value: false,
                  icon: Icon(Icons.description_outlined, size: 18),
                  label: Text('纯文本 (.txt)'),
                ),
                ButtonSegment<bool>(
                  value: true,
                  icon: Icon(Icons.article_outlined, size: 18),
                  label: Text('Markdown (.md)'),
                ),
              ],
              selected: {_isMarkdown},
              onSelectionChanged: _busy
                  ? null
                  : (v) => setState(() => _isMarkdown = v.first),
            ),
            const SizedBox(height: 16),
            if (supportsShare) ...[
              FilledButton.icon(
                onPressed: _busy ? null : _share,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.share_outlined, size: 18),
                label: const Text('直接分享'),
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: _busy ? null : _save,
                icon: const Icon(Icons.save_alt_outlined, size: 18),
                label: const Text('保存到本地'),
              ),
            ] else
              FilledButton.icon(
                onPressed: _busy ? null : _save,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_alt_outlined, size: 18),
                label: const Text('保存到本地'),
              ),
          ],
        ),
      ),
    );
  }
}
