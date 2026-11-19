import 'package:flutter/material.dart';

import '../../../data/services/engine_c/config_file_io.dart';
import 'app_toast.dart';

/// 桌面端保存文件后的提示：若支持文件管理器高亮定位，提供快捷入口。
void showSavedFileNotice(
  BuildContext context, {
  required String message,
  required String savedPath,
}) {
  if (!context.mounted) return;
  if (ConfigFileIo.supportsRevealInFolder) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          action: SnackBarAction(
            label: '打开所在位置',
            onPressed: () => ConfigFileIo.revealSavedFile(savedPath),
          ),
        ),
      );
      return;
    }
  }
  showAppToast(context, message, type: ToastType.success);
}

/// 统一的「直接分享 / 保存到本地」导出动作弹窗。
///
/// 在不支持系统分享的桌面端（如 Windows / Linux）自动跳过弹窗，直接调用 [onSave]。
Future<void> showExportFileSheet(
  BuildContext context, {
  required String title,
  String? summary,
  required Future<bool> Function() onShare,
  required Future<String?> Function() onSave,
  String savedSuccessPrefix = '已保存',
  String sharedSuccessMessage = '已调起系统分享',
  bool allowMultipleActions = false,
}) async {
  if (!ConfigFileIo.supportsSystemShare) {
    try {
      final saved = await onSave();
      if (!context.mounted) return;
      if (saved == null) {
        showAppToast(context, '已取消导出');
      } else {
        showSavedFileNotice(
          context,
          message: '$savedSuccessPrefix：$saved',
          savedPath: saved,
        );
      }
    } catch (e) {
      if (context.mounted) {
        showAppToast(context, '导出失败：$e');
      }
    }
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => _ExportFileSheetBody(
      title: title,
      summary: summary,
      onShare: onShare,
      onSave: onSave,
      savedSuccessPrefix: savedSuccessPrefix,
      sharedSuccessMessage: sharedSuccessMessage,
      allowMultipleActions: allowMultipleActions,
    ),
  );
}

class _ExportFileSheetBody extends StatefulWidget {
  final String title;
  final String? summary;
  final Future<bool> Function() onShare;
  final Future<String?> Function() onSave;
  final String savedSuccessPrefix;
  final String sharedSuccessMessage;
  final bool allowMultipleActions;

  const _ExportFileSheetBody({
    required this.title,
    this.summary,
    required this.onShare,
    required this.onSave,
    required this.savedSuccessPrefix,
    required this.sharedSuccessMessage,
    required this.allowMultipleActions,
  });

  @override
  State<_ExportFileSheetBody> createState() => _ExportFileSheetBodyState();
}

class _ExportFileSheetBodyState extends State<_ExportFileSheetBody> {
  bool _busy = false;
  String? _statusText;

  Future<void> _handleShare() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final ok = await widget.onShare();
      if (!mounted) return;
      if (ok) {
        if (widget.allowMultipleActions) {
          setState(() {
            _busy = false;
            _statusText = widget.sharedSuccessMessage;
          });
        } else {
          Navigator.pop(context);
        }
      } else {
        setState(() => _busy = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, '分享失败：$e');
    }
  }

  Future<void> _handleSave() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final saved = await widget.onSave();
      if (!mounted) return;
      if (saved != null) {
        final msg = '${widget.savedSuccessPrefix}：$saved';
        if (widget.allowMultipleActions) {
          setState(() {
            _busy = false;
            _statusText = msg;
          });
        } else {
          Navigator.pop(context);
          showSavedFileNotice(context, message: msg, savedPath: saved);
        }
      } else {
        setState(() => _busy = false);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showAppToast(context, '保存失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            if (widget.summary != null && widget.summary!.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                widget.summary!,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_statusText != null) ...[
              const SizedBox(height: 10),
              Text(
                _statusText!,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _busy ? null : _handleShare,
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
              onPressed: _busy ? null : _handleSave,
              icon: const Icon(Icons.save_alt_outlined, size: 18),
              label: const Text('保存到本地'),
            ),
          ],
        ),
      ),
    );
  }
}
