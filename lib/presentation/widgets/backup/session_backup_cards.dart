import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:peipal/presentation/widgets/common/app_toast.dart';

import '../../../data/services/backup/session_backup_service.dart';
import '../../../data/services/engine_c/config_file_io.dart';
import '../../../providers/providers.dart';

/// 展示不可误触关闭的中继进度弹窗并执行异步任务。
Future<T> runWithBackupProgressDialog<T>({
  required BuildContext context,
  required SessionBackupProgress initialProgress,
  required Future<T> Function(void Function(SessionBackupProgress) update) task,
}) async {
  final notifier = ValueNotifier<SessionBackupProgress>(initialProgress);
  final nav = Navigator.of(context, rootNavigator: true);
  var dialogOpen = true;
  var disposed = false;

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => _BackupProgressDialog(
      notifier: notifier,
      onDisposed: () => disposed = true,
    ),
  ).whenComplete(() {
    dialogOpen = false;
  });

  try {
    return await task((p) {
      if (!disposed) {
        notifier.value = p;
      }
    });
  } finally {
    if (dialogOpen && nav.canPop()) {
      nav.pop();
    }
  }
}

class _BackupProgressDialog extends StatefulWidget {
  final ValueNotifier<SessionBackupProgress> notifier;
  final VoidCallback onDisposed;

  const _BackupProgressDialog({
    required this.notifier,
    required this.onDisposed,
  });

  @override
  State<_BackupProgressDialog> createState() => _BackupProgressDialogState();
}

class _BackupProgressDialogState extends State<_BackupProgressDialog> {
  @override
  void dispose() {
    widget.onDisposed();
    widget.notifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: AlertDialog(
        content: ValueListenableBuilder<SessionBackupProgress>(
          valueListenable: widget.notifier,
          builder: (context, progress, _) {
            final fraction = progress.fraction;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        progress.message,
                        style: const TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(value: fraction),
                ),
                if (progress.total > 0) ...[
                  const SizedBox(height: 6),
                  Text(
                    '${progress.current} / ${progress.total}',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// 独立的确认密码弹窗：在自身 State.dispose 中安全释放 TextEditingController，
/// 避免弹窗退场动画未完成时被销毁而触发依赖断言异常。
class _ConfirmPasswordDialog extends StatefulWidget {
  final String expectedPassword;

  const _ConfirmPasswordDialog({required this.expectedPassword});

  @override
  State<_ConfirmPasswordDialog> createState() => _ConfirmPasswordDialogState();
}

class _ConfirmPasswordDialogState extends State<_ConfirmPasswordDialog> {
  final TextEditingController _confirmCtrl = TextEditingController();
  String? _errorText;

  @override
  void dispose() {
    _confirmCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_confirmCtrl.text != widget.expectedPassword) {
      setState(() => _errorText = '两次输入的密码不一致');
      return;
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('确认备份密码'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '请再次输入密码以防误输，密码遗忘后无法找回。',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _confirmCtrl,
            obscureText: true,
            autofocus: true,
            onSubmitted: (_) => _submit(),
            onChanged: (_) {
              if (_errorText != null) {
                setState(() => _errorText = null);
              }
            },
            decoration: InputDecoration(
              labelText: '再次输入密码',
              errorText: _errorText,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('确认'),
        ),
      ],
    );
  }
}

/// 备份会话数据卡片：展示本地会话统计、可选加密密码输入框与「确认备份会话」按钮。
class SessionExportCard extends ConsumerStatefulWidget {
  final VoidCallback? onExported;

  const SessionExportCard({super.key, this.onExported});

  @override
  ConsumerState<SessionExportCard> createState() => _SessionExportCardState();
}

class _SessionExportCardState extends ConsumerState<SessionExportCard> {
  final TextEditingController _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  SessionDataSummary? _summary;
  bool _isLoadingSummary = true;
  bool _isExporting = false;

  @override
  void initState() {
    super.initState();
    _loadSummary();
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadSummary() async {
    try {
      final summary =
          await ref.read(sessionBackupServiceProvider).getLocalSummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _isLoadingSummary = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoadingSummary = false);
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _handleExport() async {
    if (_isExporting) return;
    final password = _passwordCtrl.text;

    if (password.isNotEmpty) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (_) => _ConfirmPasswordDialog(expectedPassword: password),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _isExporting = true);

    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('peipal_session_out_');
      final fileName =
          ConfigFileIo.buildFileName('小培会话备份', extension: 'zip');
      final tempZip = File(p.join(tempDir.path, fileName));

      final result = await runWithBackupProgressDialog<SessionBackupExportResult>(
        context: context,
        initialProgress: const SessionBackupProgress(message: '正在准备会话数据…'),
        task: (updateProgress) async {
          final exportRes = await ref
              .read(sessionBackupServiceProvider)
              .exportToZipFile(
                tempZip,
                password: password.isEmpty ? null : password,
                onProgress: updateProgress,
              );
          updateProgress(const SessionBackupProgress(message: '正在打开系统保存界面…'));
          return exportRes;
        },
      );

      if (!mounted) return;
      final savedLocation = await ConfigFileIo.saveBinaryFile(
        sourcePath: result.file.path,
        suggestedName: fileName,
      );

      if (!mounted) return;
      if (savedLocation == null) {
        showAppToast(context, '已取消备份');
      } else {
        showAppToast(
          context,
          '已备份 ${result.patientCount} 个会话、${result.messageCount} 条记录 (${_formatBytes(result.zipBytes)})',
        );
        widget.onExported?.call();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '备份失败：$e');
      }
    } finally {
      if (tempDir != null) {
        try {
          await tempDir.delete(recursive: true);
        } catch (_) {}
      }
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Icon(Icons.forum_outlined, color: Colors.teal),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '备份会话数据',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '打包所有会话、聊天记录、生成结果与语音/照片文件（不含模板与密钥）',
              style: TextStyle(
                fontSize: 12.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            if (_isLoadingSummary)
              const LinearProgressIndicator()
            else if (_summary != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatChip(label: '会话', value: '${_summary!.patientCount}'),
                  _StatChip(label: '消息', value: '${_summary!.messageCount}'),
                  _StatChip(label: '结果', value: '${_summary!.recordCount}'),
                  _StatChip(
                    label: '媒体',
                    value:
                        '${_summary!.mediaFileCount} 个 (${_formatBytes(_summary!.mediaBytes)})',
                  ),
                ],
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '备份密码（可选，留空则不加密）',
                border: const OutlineInputBorder(),
                isDense: true,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _isExporting ? null : _handleExport,
              child: Text(_isExporting ? '正在打包…' : '确认备份会话'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 会话备份包解析与恢复预览区域：支持加密校验、合并/覆盖模式切换与执行恢复。
class SessionImportPreviewSection extends ConsumerStatefulWidget {
  final File zipFile;
  final String fileName;
  final VoidCallback onRestored;

  const SessionImportPreviewSection({
    super.key,
    required this.zipFile,
    required this.fileName,
    required this.onRestored,
  });

  @override
  ConsumerState<SessionImportPreviewSection> createState() =>
      _SessionImportPreviewSectionState();
}

class _SessionImportPreviewSectionState
    extends ConsumerState<SessionImportPreviewSection> {
  static final _dateFmt = DateFormat('yyyy-MM-dd HH:mm');

  final TextEditingController _passwordCtrl = TextEditingController();
  bool _obscurePassword = true;
  bool _needsPassword = false;
  String? _passwordError;
  String? _verifiedPassword;

  SessionBackupPreview? _preview;
  String? _inspectError;
  bool _isInspecting = true;
  bool _isRestoring = false;
  SessionRestoreMode _restoreMode = SessionRestoreMode.merge;

  @override
  void initState() {
    super.initState();
    _inspect(password: null, showModal: false);
  }

  @override
  void didUpdateWidget(covariant SessionImportPreviewSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zipFile.path != widget.zipFile.path) {
      _passwordCtrl.clear();
      _verifiedPassword = null;
      _needsPassword = false;
      _passwordError = null;
      _inspect(password: null, showModal: false);
    }
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _inspect({String? password, bool showModal = true}) async {
    setState(() {
      _isInspecting = true;
      _inspectError = null;
      _passwordError = null;
    });

    try {
      final Future<SessionBackupPreview> future;
      if (showModal && mounted) {
        future = runWithBackupProgressDialog<SessionBackupPreview>(
          context: context,
          initialProgress: SessionBackupProgress(
            message: password != null ? '正在解密与校验备份包…' : '正在解析备份包…',
          ),
          task: (updateProgress) => ref
              .read(sessionBackupServiceProvider)
              .inspectZipFile(
                widget.zipFile,
                password: password,
                onProgress: updateProgress,
              ),
        );
      } else {
        future = ref
            .read(sessionBackupServiceProvider)
            .inspectZipFile(widget.zipFile, password: password);
      }

      final preview = await future;
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _verifiedPassword = password;
        _needsPassword = false;
        _isInspecting = false;
      });
    } on BackupPasswordRequiredException {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _needsPassword = true;
        _isInspecting = false;
      });
    } on BackupWrongPasswordException catch (e) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _needsPassword = true;
        _passwordError = e.toString();
        _isInspecting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _needsPassword = false;
        _inspectError = '$e';
        _isInspecting = false;
      });
    }
  }

  Future<void> _handleRestore() async {
    if (_preview == null || _isRestoring) return;

    if (_restoreMode == SessionRestoreMode.replace) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('确认覆盖恢复'),
          content: const Text(
            '覆盖恢复将清空当前设备中的所有会话、聊天记录、生成结果以及语音/照片文件，并替换为备份包中的内容（系统会自动先保留一份恢复前数据库快照）。\n\n模板、标准词条与 AI 密钥不会受到影响。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确认覆盖'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    setState(() => _isRestoring = true);
    try {
      final result =
          await runWithBackupProgressDialog<SessionBackupRestoreResult>(
        context: context,
        initialProgress: const SessionBackupProgress(message: '正在准备恢复会话…'),
        task: (updateProgress) => ref
            .read(sessionBackupServiceProvider)
            .restoreFromZipFile(
              widget.zipFile,
              mode: _restoreMode,
              password: _verifiedPassword,
              onProgress: updateProgress,
            ),
      );

      ref.invalidate(patientsProvider);
      ref.invalidate(patientProvider);
      ref.invalidate(messagesProvider);
      ref.invalidate(patientRecordsProvider);
      ref.invalidate(patientMessageCountProvider);
      ref.invalidate(lastMessageProvider);

      if (!mounted) return;
      setState(() => _isRestoring = false);

      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green),
              SizedBox(width: 8),
              Text('恢复完成'),
            ],
          ),
          content: Text(
            '已恢复 ${result.restoredPatients} 个会话、${result.restoredMessages} 条记录、${result.restoredMediaFiles} 个媒体文件'
            '${result.skippedPatients > 0 ? '\n（已跳过 ${result.skippedPatients} 个本地已存在的会话）' : ''}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (mounted) {
        widget.onRestored();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isRestoring = false);
      showAppToast(context, '恢复失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '已选文件：${widget.fileName}',
          style: TextStyle(
            fontSize: 12.5,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        if (_isInspecting) ...[
          const SizedBox(height: 12),
          const Row(
            children: [
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              SizedBox(width: 10),
              Text('正在后台解析备份包…', style: TextStyle(fontSize: 13)),
            ],
          ),
        ],
        if (_needsPassword) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            obscureText: _obscurePassword,
            autofocus: true,
            onSubmitted: (val) => _inspect(password: val),
            decoration: InputDecoration(
              labelText: '输入解压密码',
              errorText: _passwordError,
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 20,
                ),
                onPressed: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _isInspecting
                  ? null
                  : () => _inspect(password: _passwordCtrl.text),
              child: const Text('验证密码'),
            ),
          ),
        ],
        if (_inspectError != null) ...[
          const SizedBox(height: 10),
          Text(
            _inspectError!,
            style: const TextStyle(color: Colors.red, fontSize: 12.5),
          ),
        ],
        if (_preview != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_preview!.exportedAt != null)
                  Text(
                    '导出时间：${_dateFmt.format(_preview!.exportedAt!.toLocal())}',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                const SizedBox(height: 4),
                Text(
                  '包含：${_preview!.patientCount} 个会话 · ${_preview!.messageCount} 条记录（结果 ${_preview!.recordCount} 份）· ${_preview!.mediaFileCount} 个媒体文件',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (_preview!.conflictPatientCount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                    '其中 ${_preview!.conflictPatientCount} 个会话在当前设备已存在',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.amber.shade800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          SegmentedButton<SessionRestoreMode>(
            segments: const [
              ButtonSegment(
                value: SessionRestoreMode.merge,
                label: Text('合并补全'),
                icon: Icon(Icons.merge_type, size: 16),
              ),
              ButtonSegment(
                value: SessionRestoreMode.replace,
                label: Text('覆盖恢复'),
                icon: Icon(Icons.restart_alt, size: 16),
              ),
            ],
            selected: {_restoreMode},
            onSelectionChanged: (s) {
              setState(() => _restoreMode = s.first);
            },
          ),
          const SizedBox(height: 8),
          Text(
            _restoreMode == SessionRestoreMode.merge
                ? '保留当前设备已有会话，仅补充缺失的会话、记录与媒体文件'
                : '清空当前会话数据与媒体后替换为备份包内容（模板与密钥不受影响）',
            style: TextStyle(
              fontSize: 12,
              color: _restoreMode == SessionRestoreMode.replace
                  ? Colors.red.shade700
                  : colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _isRestoring ? null : _handleRestore,
              icon: _isRestoring
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.check),
              label: Text(_isRestoring ? '正在恢复…' : '确认恢复会话'),
            ),
          ),
        ],
      ],
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '$label $value',
        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
      ),
    );
  }
}
