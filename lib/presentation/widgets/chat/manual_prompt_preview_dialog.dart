import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:markdown/markdown.dart' as md;

/// 弹出独立窗口查看拼接好的完整病历对话内容（供手动复制到外部 AI）
void showManualPromptPreviewDialog({
  required BuildContext context,
  required String title,
  required String promptText,
}) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.chat_outlined, color: Colors.amber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${promptText.length} 字',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: MediaQuery.of(context).size.height * 0.60,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.amber),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '已整理所有材料与要求。点击下方「复制全部内容」发送给豆包、Deepseek或网页版 AI，生成后将回答贴回即可。',
                      style: TextStyle(fontSize: 11.5, color: Colors.black87),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Markdown(
                  data: promptText,
                  selectable: true,
                  extensionSet: md.ExtensionSet.gitHubFlavored,
                  padding: const EdgeInsets.all(12),
                  styleSheet: MarkdownStyleSheet(
                    p: const TextStyle(fontSize: 12.5, height: 1.45),
                    h1: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, height: 1.4),
                    h2: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, height: 1.4),
                    h3: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, height: 1.4),
                    listBullet: const TextStyle(fontSize: 12.5, height: 1.45),
                    code: const TextStyle(fontSize: 11.5, height: 1.35),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton.icon(
          style: FilledButton.styleFrom(
            backgroundColor: Colors.amber.shade800,
            foregroundColor: Colors.white,
          ),
          icon: const Icon(Icons.copy, size: 16),
          label: const Text('复制全部内容'),
          onPressed: () {
            Clipboard.setData(ClipboardData(text: promptText));
            showAppToast(context, '已复制完整对话内容，可直接发送给豆包、Deepseek或网页版 AI 提问');
          },
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('关闭'),
        ),
      ],
    ),
  );
}
