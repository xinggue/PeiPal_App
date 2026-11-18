import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:peipal/presentation/widgets/common/app_toast.dart';

import '../../../data/services/backup/session_backup_service.dart';
import '../../../data/services/engine_c/config_file_io.dart';
import '../../widgets/backup/session_backup_cards.dart';

/// 设置页「数据 → 会话数据备份与恢复」独立页面，仅处理会话、记录与媒体备份。
class SessionBackupPage extends ConsumerStatefulWidget {
  const SessionBackupPage({super.key});

  @override
  ConsumerState<SessionBackupPage> createState() => _SessionBackupPageState();
}

class _SessionBackupPageState extends ConsumerState<SessionBackupPage> {
  File? _pickedZipFile;
  String? _pickedFileName;
  int _exportCardVersion = 0;

  @override
  void dispose() {
    _cleanupPickedFile();
    super.dispose();
  }

  void _cleanupPickedFile() {
    final f = _pickedZipFile;
    if (f != null) {
      try {
        if (f.parent.existsSync() &&
            f.parent.path.contains('peipal_session_in_')) {
          f.parent.deleteSync(recursive: true);
        } else if (f.existsSync()) {
          f.deleteSync();
        }
      } catch (_) {}
      _pickedZipFile = null;
      _pickedFileName = null;
    }
  }

  Future<void> _handlePickBackupZip() async {
    try {
      final xfile = await ConfigFileIo.pickBinaryFile(label: '会话备份包');
      if (xfile == null || !mounted) return;

      final localCopy = await runWithBackupProgressDialog<File>(
        context: context,
        initialProgress: const SessionBackupProgress(message: '正在读取所选备份文件…'),
        task: (_) async {
          final tempDir =
              await Directory.systemTemp.createTemp('peipal_session_in_');
          final copy = File(p.join(tempDir.path, 'restore.zip'));
          await xfile.saveTo(copy.path);
          return copy;
        },
      );

      if (!mounted) return;
      _cleanupPickedFile();
      setState(() {
        _pickedZipFile = localCopy;
        _pickedFileName = xfile.name;
      });
    } catch (e) {
      if (mounted) {
        showAppToast(context, '读取文件失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('会话数据备份与恢复'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          SessionExportCard(
            key: ValueKey(_exportCardVersion),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.unarchive_outlined, color: Colors.teal),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          '恢复会话数据',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _handlePickBackupZip,
                        icon: const Icon(Icons.folder_open, size: 16),
                        label: const Text('选择备份文件'),
                      ),
                    ],
                  ),
                  if (_pickedZipFile == null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '从之前导出的会话备份包恢复会话、消息与语音/照片文件',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ] else ...[
                    const SizedBox(height: 10),
                    SessionImportPreviewSection(
                      zipFile: _pickedZipFile!,
                      fileName: _pickedFileName ?? '会话备份包',
                      onRestored: () {
                        setState(() {
                          _cleanupPickedFile();
                          _exportCardVersion++;
                        });
                      },
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
