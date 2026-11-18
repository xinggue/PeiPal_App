import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/services/ble/record_text.dart';
import '../../../data/services/engine_c/config_file_io.dart';
import '../../../domain/models/template.dart';
import '../common/app_toast.dart';

/// 生成文书的纯软件输出操作（复制全文 / 导出文件），供审阅页、文书管理页与聊天流复用。
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
    final plainCheck = buildReadableRecordText(
      recordJson: recordJson,
      values: values,
      orderedSlots: orderedSlots,
      title: title,
    );
    if (plainCheck.isEmpty) {
      if (context.mounted) showAppToast(context, '没有可导出的内容');
      return;
    }

    final isMarkdown = await showModalBottomSheet<bool>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '选择导出格式',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('纯文本 (.txt)'),
              onTap: () => Navigator.pop(ctx, false),
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('Markdown (.md)'),
              onTap: () => Navigator.pop(ctx, true),
            ),
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
    if (isMarkdown == null || !context.mounted) return;

    final content = isMarkdown
        ? buildReadableRecordText(
            recordJson: recordJson,
            values: values,
            orderedSlots: orderedSlots,
            title: title,
            markdown: true,
          )
        : plainCheck;

    final ext = isMarkdown ? 'md' : 'txt';
    final prefix = (title?.trim().isNotEmpty == true) ? title!.trim() : '文书记录';
    final suggestedName = ConfigFileIo.buildFileName(prefix, extension: ext);

    try {
      final saved = await ConfigFileIo.saveConfigTextFile(
        content: content,
        suggestedName: suggestedName,
        typeLabel: '文书文件',
        extensions: [ext],
      );
      if (!context.mounted) return;
      if (saved == null) {
        showAppToast(context, '已取消导出');
      } else {
        showAppToast(context, '已导出文书文件');
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, '导出失败：$e');
      }
    }
  }
}
