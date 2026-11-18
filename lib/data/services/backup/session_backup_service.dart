import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../database/database_helper.dart';
import '../../database/database_path.dart';

/// Test hook for media root directory (defaults to getApplicationDocumentsDirectory()).
Future<String> Function()? sessionBackupMediaRootOverride;

enum SessionRestoreMode {
  /// 保留现有会话数据，仅补入备份中本地不存在的会话、消息与日志。
  merge,

  /// 清空当前会话数据与媒体后，完全还原备份包内容。
  replace,
}

class SessionBackupProgress {
  final String message;
  final int current;
  final int total;

  const SessionBackupProgress({
    required this.message,
    this.current = 0,
    this.total = 0,
  });

  double? get fraction => total > 0 ? (current / total).clamp(0.0, 1.0) : null;
}

class BackupPasswordRequiredException implements Exception {
  const BackupPasswordRequiredException();

  @override
  String toString() => '该备份包已加密，请输入解压密码';
}

class BackupWrongPasswordException implements Exception {
  const BackupWrongPasswordException();

  @override
  String toString() => '解压密码错误，请重新输入';
}

class SessionDataSummary {
  final int patientCount;
  final int messageCount;
  final int recordCount;
  final int mediaFileCount;
  final int mediaBytes;

  const SessionDataSummary({
    required this.patientCount,
    required this.messageCount,
    required this.recordCount,
    required this.mediaFileCount,
    required this.mediaBytes,
  });
}

class SessionBackupExportResult {
  final File file;
  final int patientCount;
  final int messageCount;
  final int recordCount;
  final int logCount;
  final int mediaFileCount;
  final int zipBytes;
  final bool encrypted;

  const SessionBackupExportResult({
    required this.file,
    required this.patientCount,
    required this.messageCount,
    required this.recordCount,
    required this.logCount,
    required this.mediaFileCount,
    required this.zipBytes,
    required this.encrypted,
  });
}

class SessionBackupPreview {
  final DateTime? exportedAt;
  final int patientCount;
  final int messageCount;
  final int recordCount;
  final int logCount;
  final int mediaFileCount;
  final int conflictPatientCount;

  const SessionBackupPreview({
    required this.exportedAt,
    required this.patientCount,
    required this.messageCount,
    required this.recordCount,
    required this.logCount,
    required this.mediaFileCount,
    required this.conflictPatientCount,
  });
}

class SessionBackupRestoreResult {
  final SessionRestoreMode mode;
  final int restoredPatients;
  final int skippedPatients;
  final int restoredMessages;
  final int skippedMessages;
  final int restoredLogs;
  final int restoredMediaFiles;

  const SessionBackupRestoreResult({
    required this.mode,
    required this.restoredPatients,
    required this.skippedPatients,
    required this.restoredMessages,
    required this.skippedMessages,
    required this.restoredLogs,
    required this.restoredMediaFiles,
  });
}

class SessionBackupService {
  static const String backupFormat = 'peipal_session_backup';
  static const Set<String> acceptedFormats = {
    'peipal_session_backup',
    'peipal_data_backup',
  };
  static const int backupVersion = 1;
  static const List<String> _mediaSubdirs = ['audio', 'photos', 'documents'];

  Future<String> _resolveMediaRoot() async {
    final override = sessionBackupMediaRootOverride;
    if (override != null) return override();
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  Future<SessionDataSummary> getLocalSummary() async {
    final db = await DatabaseHelper.database;
    final pCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM patients')) ??
        0;
    final mCount = Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM messages')) ??
        0;
    final rCount = Sqflite.firstIntValue(await db.rawQuery(
            "SELECT COUNT(*) FROM messages WHERE msg_type = 'generatedRecord'")) ??
        0;

    final mediaRoot = await _resolveMediaRoot();
    int fileCount = 0;
    int totalBytes = 0;
    for (final sub in _mediaSubdirs) {
      final dir = Directory(p.join(mediaRoot, sub));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          fileCount++;
          totalBytes += await entity.length();
        }
      }
    }

    return SessionDataSummary(
      patientCount: pCount,
      messageCount: mCount,
      recordCount: rCount,
      mediaFileCount: fileCount,
      mediaBytes: totalBytes,
    );
  }

  /// 将全部会话数据（patients / messages / generation_logs）与本地媒体文件导出为 .zip。
  /// 繁重的打包与 AES 加密在后台 Isolate 执行，不阻塞主 UI 线程。
  Future<SessionBackupExportResult> exportToZipFile(
    File targetZipFile, {
    String? password,
    void Function(SessionBackupProgress progress)? onProgress,
  }) async {
    onProgress?.call(const SessionBackupProgress(message: '正在整理会话记录…'));

    final db = await DatabaseHelper.database;
    final mediaRoot = await _resolveMediaRoot();
    final normalizedMediaRoot = p.normalize(mediaRoot);
    final effectivePassword =
        (password == null || password.isEmpty) ? null : password;

    final patientRows = await db.query('patients', orderBy: 'created_at ASC');
    final rawMessageRows = await db.query('messages', orderBy: 'created_at ASC');
    final logRows =
        await db.query('generation_logs', orderBy: 'created_at ASC');

    final zipFilesToAdd = <String, String>{};

    // 1. 收录应用媒体目录下的全部文件
    for (final sub in _mediaSubdirs) {
      final dir = Directory(p.join(normalizedMediaRoot, sub));
      if (!await dir.exists()) continue;
      await for (final entity in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          final rel = p.relative(entity.path, from: normalizedMediaRoot);
          final posixRel = p.posix.joinAll(['media', ...p.split(rel)]);
          zipFilesToAdd[posixRel] = entity.path;
        }
      }
    }

    // 2. 转换 messages.file_paths 为跨设备相对路径（media/...）
    int recordCount = 0;
    final portableMessages = <Map<String, dynamic>>[];
    for (final row in rawMessageRows) {
      final copy = Map<String, dynamic>.from(row);
      if (copy['msg_type'] == 'generatedRecord') {
        recordCount++;
      }

      final rawPaths = copy['file_paths'] as String?;
      if (rawPaths != null && rawPaths.isNotEmpty) {
        try {
          final decoded = jsonDecode(rawPaths);
          if (decoded is List) {
            final rewritten = <String>[];
            for (var i = 0; i < decoded.length; i++) {
              final originalPath = decoded[i]?.toString() ?? '';
              if (originalPath.isEmpty) continue;
              final portable = await _toPortableMediaPath(
                originalPath: originalPath,
                normalizedMediaRoot: normalizedMediaRoot,
                messageId: copy['id']?.toString() ?? 'msg',
                index: i,
                zipFilesToAdd: zipFilesToAdd,
              );
              rewritten.add(portable);
            }
            copy['file_paths'] = jsonEncode(rewritten);
          }
        } catch (_) {}
      }
      portableMessages.add(copy);
    }

    final exportedAt = DateTime.now().toIso8601String();
    final manifest = <String, dynamic>{
      'format': backupFormat,
      'version': backupVersion,
      'exportedAt': exportedAt,
      'dbVersion': DatabaseHelper.currentVersion,
      'patientCount': patientRows.length,
      'messageCount': portableMessages.length,
      'recordCount': recordCount,
      'logCount': logRows.length,
      'mediaFileCount': zipFilesToAdd.length,
    };

    final dataPayload = <String, dynamic>{
      'patients': patientRows,
      'messages': portableMessages,
      'generationLogs': logRows,
    };

    final manifestJson = const JsonEncoder.withIndent('  ').convert(manifest);
    final dataJson = jsonEncode(dataPayload);

    final mediaEntries = zipFilesToAdd.entries
        .map((e) => {'entryName': e.key, 'sourcePath': e.value})
        .toList();

    final workerResult = await _runIsolateWithProgress<Map<String, dynamic>>(
      entryPoint: _exportZipWorker,
      payload: {
        'targetZipPath': targetZipFile.path,
        'manifestJson': manifestJson,
        'dataJson': dataJson,
        'mediaEntries': mediaEntries,
        'password': effectivePassword,
      },
      onProgress: onProgress,
    );

    return SessionBackupExportResult(
      file: targetZipFile,
      patientCount: patientRows.length,
      messageCount: portableMessages.length,
      recordCount: recordCount,
      logCount: logRows.length,
      mediaFileCount: zipFilesToAdd.length,
      zipBytes: workerResult['zipBytes'] as int,
      encrypted: effectivePassword != null,
    );
  }

  Future<String> _toPortableMediaPath({
    required String originalPath,
    required String normalizedMediaRoot,
    required String messageId,
    required int index,
    required Map<String, String> zipFilesToAdd,
  }) async {
    final normalizedOrig = p.normalize(originalPath);
    if (p.isWithin(normalizedMediaRoot, normalizedOrig)) {
      final rel = p.relative(normalizedOrig, from: normalizedMediaRoot);
      final posixRel = p.posix.joinAll(['media', ...p.split(rel)]);
      if (await File(originalPath).exists()) {
        zipFilesToAdd.putIfAbsent(posixRel, () => originalPath);
      }
      return posixRel;
    }

    final unixOrig = originalPath.replaceAll('\\', '/');
    for (final sub in _mediaSubdirs) {
      final marker = '/$sub/';
      final idx = unixOrig.indexOf(marker);
      if (idx >= 0) {
        final suffix = unixOrig.substring(idx + 1);
        final posixRel = 'media/$suffix';
        final localCandidatePath =
            p.joinAll([normalizedMediaRoot, ...suffix.split('/')]);
        if (await File(localCandidatePath).exists()) {
          zipFilesToAdd.putIfAbsent(posixRel, () => localCandidatePath);
        } else if (await File(originalPath).exists()) {
          zipFilesToAdd.putIfAbsent(posixRel, () => originalPath);
        }
        return posixRel;
      }
    }

    if (await File(originalPath).exists()) {
      final base = p
          .basename(originalPath)
          .replaceAll(RegExp(r'[^\w.\-\u4e00-\u9fa5]'), '_');
      final posixRel = 'media/external/${messageId}_${index}_$base';
      zipFilesToAdd.putIfAbsent(posixRel, () => originalPath);
      return posixRel;
    }

    return originalPath;
  }

  /// 在后台 Isolate 中读取并校验会话备份包摘要。
  Future<SessionBackupPreview> inspectZipFile(
    File zipFile, {
    String? password,
    void Function(SessionBackupProgress progress)? onProgress,
  }) async {
    if (!await zipFile.exists()) {
      throw const FormatException('找不到选择的备份文件');
    }

    onProgress?.call(const SessionBackupProgress(message: '正在解析与校验备份包…'));

    final effectivePassword =
        (password == null || password.isEmpty) ? null : password;

    final workerResult = await _runIsolateWithProgress<Map<String, dynamic>>(
      entryPoint: _inspectZipWorker,
      payload: {
        'zipPath': zipFile.path,
        'password': effectivePassword,
        'acceptedFormats': acceptedFormats.toList(),
        'maxVersion': backupVersion,
      },
      onProgress: onProgress,
    );

    final db = await DatabaseHelper.database;
    final existingIds = (await db.query('patients', columns: ['id']))
        .map((r) => r['id']?.toString() ?? '')
        .toSet();

    final patientIds =
        (workerResult['patientIds'] as List).map((e) => e.toString()).toList();
    int conflicts = 0;
    for (final id in patientIds) {
      if (id.isNotEmpty && existingIds.contains(id)) {
        conflicts++;
      }
    }

    DateTime? exportedAt;
    final rawExportedAt = workerResult['exportedAt'] as String?;
    if (rawExportedAt != null && rawExportedAt.isNotEmpty) {
      exportedAt = DateTime.tryParse(rawExportedAt);
    }

    return SessionBackupPreview(
      exportedAt: exportedAt,
      patientCount: workerResult['patientCount'] as int,
      messageCount: workerResult['messageCount'] as int,
      recordCount: workerResult['recordCount'] as int,
      logCount: workerResult['logCount'] as int,
      mediaFileCount: workerResult['mediaFileCount'] as int,
      conflictPatientCount: conflicts,
    );
  }

  /// 从 .zip 备份包恢复会话记录与本地媒体文件。
  /// 解压与解密在后台 Isolate 执行，主线程只做最后的 SQLite 事务写入。
  Future<SessionBackupRestoreResult> restoreFromZipFile(
    File zipFile, {
    SessionRestoreMode mode = SessionRestoreMode.merge,
    String? password,
    void Function(SessionBackupProgress progress)? onProgress,
  }) async {
    if (!await zipFile.exists()) {
      throw const FormatException('找不到选择的备份文件');
    }

    final mediaRoot = await _resolveMediaRoot();
    final normalizedMediaRoot = p.normalize(mediaRoot);
    final effectivePassword =
        (password == null || password.isEmpty) ? null : password;

    if (mode == SessionRestoreMode.replace) {
      onProgress?.call(const SessionBackupProgress(message: '正在留存当前数据库快照…'));
      await _snapshotCurrentDbBeforeReplace();
    }

    final workerResult = await _runIsolateWithProgress<Map<String, dynamic>>(
      entryPoint: _restoreZipWorker,
      payload: {
        'zipPath': zipFile.path,
        'password': effectivePassword,
        'acceptedFormats': acceptedFormats.toList(),
        'maxVersion': backupVersion,
        'mediaRoot': normalizedMediaRoot,
        'replaceMode': mode == SessionRestoreMode.replace,
      },
      onProgress: onProgress,
    );

    final patients = (workerResult['patients'] as List)
        .cast<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final messages = (workerResult['messages'] as List)
        .cast<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final logs = (workerResult['logs'] as List)
        .cast<Map>()
        .map((m) => Map<String, dynamic>.from(m))
        .toList();
    final restoredMediaFiles = workerResult['restoredMediaFiles'] as int;

    onProgress?.call(const SessionBackupProgress(message: '正在写入本地会话数据库…'));

    final db = await DatabaseHelper.database;
    int restoredPatients = 0;
    int skippedPatients = 0;
    int restoredMessages = 0;
    int skippedMessages = 0;
    int restoredLogs = 0;

    await db.transaction((txn) async {
      if (mode == SessionRestoreMode.replace) {
        await txn.delete('generation_logs');
        await txn.delete('messages');
        await txn.delete('patients');
      }

      final validPatientIds = <String>{};
      if (mode == SessionRestoreMode.merge) {
        final existingPatients = await txn.query('patients', columns: ['id']);
        for (final row in existingPatients) {
          final id = row['id']?.toString() ?? '';
          if (id.isNotEmpty) validPatientIds.add(id);
        }
      }

      for (final row in patients) {
        final id = row['id']?.toString() ?? '';
        if (id.isEmpty) continue;
        if (mode == SessionRestoreMode.merge) {
          final insertedId = await txn.insert(
            'patients',
            row,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          if (insertedId != 0) {
            restoredPatients++;
          } else {
            skippedPatients++;
          }
        } else {
          await txn.insert(
            'patients',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          restoredPatients++;
        }
        validPatientIds.add(id);
      }

      final validMessageIds = <String>{};
      if (mode == SessionRestoreMode.merge) {
        final existingMessages = await txn.query('messages', columns: ['id']);
        for (final row in existingMessages) {
          final id = row['id']?.toString() ?? '';
          if (id.isNotEmpty) validMessageIds.add(id);
        }
      }

      for (final rawRow in messages) {
        final id = rawRow['id']?.toString() ?? '';
        final patientId = rawRow['patient_id']?.toString() ?? '';
        if (id.isEmpty || !validPatientIds.contains(patientId)) {
          skippedMessages++;
          continue;
        }

        final row = _rewriteRowMediaPaths(rawRow, normalizedMediaRoot);

        if (mode == SessionRestoreMode.merge) {
          final insertedId = await txn.insert(
            'messages',
            row,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          if (insertedId != 0) {
            restoredMessages++;
          } else {
            skippedMessages++;
          }
        } else {
          await txn.insert(
            'messages',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          restoredMessages++;
        }
        validMessageIds.add(id);
      }

      for (final row in logs) {
        final id = row['id']?.toString() ?? '';
        final messageId = row['message_id']?.toString() ?? '';
        if (id.isEmpty || !validMessageIds.contains(messageId)) {
          continue;
        }
        if (mode == SessionRestoreMode.merge) {
          final insertedId = await txn.insert(
            'generation_logs',
            row,
            conflictAlgorithm: ConflictAlgorithm.ignore,
          );
          if (insertedId != 0) restoredLogs++;
        } else {
          await txn.insert(
            'generation_logs',
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          restoredLogs++;
        }
      }
    });

    return SessionBackupRestoreResult(
      mode: mode,
      restoredPatients: restoredPatients,
      skippedPatients: skippedPatients,
      restoredMessages: restoredMessages,
      skippedMessages: skippedMessages,
      restoredLogs: restoredLogs,
      restoredMediaFiles: restoredMediaFiles,
    );
  }

  Map<String, dynamic> _rewriteRowMediaPaths(
    Map<String, dynamic> rawRow,
    String normalizedMediaRoot,
  ) {
    final row = Map<String, dynamic>.from(rawRow);
    final rawPaths = row['file_paths'] as String?;
    if (rawPaths == null || rawPaths.isEmpty) return row;

    try {
      final decoded = jsonDecode(rawPaths);
      if (decoded is! List) return row;
      final resolved = <String>[];
      for (final item in decoded) {
        final raw = item?.toString() ?? '';
        if (raw.isEmpty) continue;
        if (raw.startsWith('media/')) {
          final rel = raw.substring('media/'.length);
          final segments = rel
              .split('/')
              .where((s) => s.isNotEmpty && s != '..' && s != '.')
              .toList();
          if (segments.isEmpty) continue;
          final targetSegments = segments.first == 'external'
              ? ['documents', ...segments]
              : segments;
          resolved.add(p.joinAll([normalizedMediaRoot, ...targetSegments]));
        } else {
          resolved.add(raw);
        }
      }
      row['file_paths'] = jsonEncode(resolved);
    } catch (_) {}
    return row;
  }

  Future<void> _snapshotCurrentDbBeforeReplace() async {
    try {
      await DatabaseHelper.closeDatabase();
      final dbDir = await appDatabasesPath();
      final dbFile = File(p.join(dbDir, 'medhistory.db'));
      if (await dbFile.exists()) {
        await dbFile.copy(p.join(dbDir, 'medhistory.db.pre_restore.bak'));
      }
    } catch (_) {}
  }

  Future<T> _runIsolateWithProgress<T>({
    required void Function(Map<String, dynamic> args) entryPoint,
    required Map<String, dynamic> payload,
    void Function(SessionBackupProgress progress)? onProgress,
  }) async {
    final receivePort = ReceivePort();
    final completer = Completer<T>();

    late final StreamSubscription sub;
    sub = receivePort.listen((message) {
      if (message is! Map) return;
      final kind = message['kind'] as String?;
      if (kind == 'progress') {
        onProgress?.call(SessionBackupProgress(
          message: message['message'] as String? ?? '',
          current: message['current'] as int? ?? 0,
          total: message['total'] as int? ?? 0,
        ));
      } else if (kind == 'done') {
        if (!completer.isCompleted) {
          completer.complete(message['result'] as T);
        }
      } else if (kind == 'error') {
        if (!completer.isCompleted) {
          final errType = message['errorType'] as String?;
          final errMsg = message['message'] as String? ?? '处理失败';
          if (errType == 'password_required') {
            completer.completeError(const BackupPasswordRequiredException());
          } else if (errType == 'wrong_password') {
            completer.completeError(const BackupWrongPasswordException());
          } else {
            completer.completeError(FormatException(errMsg));
          }
        }
      }
    });

    final args = Map<String, dynamic>.from(payload)
      ..['sendPort'] = receivePort.sendPort;

    try {
      await Isolate.spawn(entryPoint, args);
      return await completer.future;
    } finally {
      await sub.cancel();
      receivePort.close();
    }
  }
}

// ============================================================================
// Top-level Isolate workers (must not capture non-sendable instances)
// ============================================================================

const Set<String> _alreadyCompressedExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.webp',
  '.gif',
  '.heic',
  '.heif',
  '.m4a',
  '.mp3',
  '.aac',
  '.ogg',
  '.opus',
  '.mp4',
  '.mov',
  '.pdf',
  '.zip',
  '.gz',
};

void _sendProgress(SendPort port, String message, [int current = 0, int total = 0]) {
  port.send({
    'kind': 'progress',
    'message': message,
    'current': current,
    'total': total,
  });
}

void _sendError(SendPort port, Object error) {
  if (error is BackupPasswordRequiredException) {
    port.send({'kind': 'error', 'errorType': 'password_required', 'message': error.toString()});
  } else if (error is BackupWrongPasswordException) {
    port.send({'kind': 'error', 'errorType': 'wrong_password', 'message': error.toString()});
  } else if (error is FormatException) {
    port.send({'kind': 'error', 'errorType': 'format', 'message': error.message});
  } else {
    port.send({'kind': 'error', 'errorType': 'generic', 'message': '$error'});
  }
}

Future<void> _exportZipWorker(Map<String, dynamic> args) async {
  final sendPort = args['sendPort'] as SendPort;
  final targetZipPath = args['targetZipPath'] as String;
  final manifestJson = args['manifestJson'] as String;
  final dataJson = args['dataJson'] as String;
  final mediaEntries = (args['mediaEntries'] as List).cast<Map>();
  final password = args['password'] as String?;

  Directory? tempWorkDir;
  try {
    tempWorkDir =
        await Directory.systemTemp.createTemp('peipal_zip_worker_');
    final manifestFile = File(p.join(tempWorkDir.path, 'manifest.json'));
    await manifestFile.writeAsString(manifestJson, flush: true);

    final dataFile = File(p.join(tempWorkDir.path, 'data.json'));
    await dataFile.writeAsString(dataJson, flush: true);

    final targetZip = File(targetZipPath);
    if (await targetZip.exists()) {
      await targetZip.delete();
    }
    await targetZip.parent.create(recursive: true);

    final total = mediaEntries.length;
    _sendProgress(
      sendPort,
      password != null
          ? (total > 0 ? '正在打包并加密媒体文件…' : '正在加密并生成备份包…')
          : (total > 0 ? '正在打包媒体文件…' : '正在生成备份包…'),
      0,
      total,
    );

    final encoder = ZipFileEncoder(password: password);
    encoder.create(targetZip.path);
    await encoder.addFile(manifestFile, 'manifest.json', ZipFileEncoder.gzip);
    await encoder.addFile(dataFile, 'data.json', ZipFileEncoder.gzip);

    for (var i = 0; i < total; i++) {
      final entry = mediaEntries[i];
      final entryName = entry['entryName'] as String;
      final sourcePath = entry['sourcePath'] as String;
      final file = File(sourcePath);
      if (await file.exists()) {
        final ext = p.extension(sourcePath).toLowerCase();
        final level = _alreadyCompressedExtensions.contains(ext)
            ? ZipFileEncoder.store
            : ZipFileEncoder.gzip;
        await encoder.addFile(file, entryName, level);
      }
      _sendProgress(
        sendPort,
        password != null
            ? '正在打包并加密（${i + 1} / $total）…'
            : '正在打包媒体文件（${i + 1} / $total）…',
        i + 1,
        total,
      );
    }

    await encoder.close();
    final zipBytes = await targetZip.length();
    sendPort.send({
      'kind': 'done',
      'result': {'zipBytes': zipBytes},
    });
  } catch (e) {
    _sendError(sendPort, e);
  } finally {
    if (tempWorkDir != null) {
      try {
        await tempWorkDir.delete(recursive: true);
      } catch (_) {}
    }
  }
}

Future<void> _inspectZipWorker(Map<String, dynamic> args) async {
  final sendPort = args['sendPort'] as SendPort;
  final zipPath = args['zipPath'] as String;
  final password = args['password'] as String?;
  final acceptedFormats = (args['acceptedFormats'] as List).cast<String>().toSet();
  final maxVersion = args['maxVersion'] as int;

  final input = InputFileStream(zipPath);
  try {
    _sendProgress(
      sendPort,
      password != null ? '正在解密与校验备份包…' : '正在解析备份包…',
    );
    final decoded = _readAndValidateArchiveInWorker(
      input: input,
      password: password,
      acceptedFormats: acceptedFormats,
      maxVersion: maxVersion,
    );

    final patients = decoded['patients'] as List<Map<String, dynamic>>;
    final messages = decoded['messages'] as List<Map<String, dynamic>>;
    final logs = decoded['logs'] as List<Map<String, dynamic>>;
    final mediaEntries = decoded['mediaEntries'] as List<ArchiveFile>;

    int recordCount = 0;
    for (final row in messages) {
      if (row['msg_type'] == 'generatedRecord') {
        recordCount++;
      }
    }

    sendPort.send({
      'kind': 'done',
      'result': {
        'exportedAt': decoded['exportedAt'] as String?,
        'patientIds':
            patients.map((r) => r['id']?.toString() ?? '').toList(),
        'patientCount': patients.length,
        'messageCount': messages.length,
        'recordCount': recordCount,
        'logCount': logs.length,
        'mediaFileCount': mediaEntries.length,
      },
    });
  } catch (e) {
    _sendError(sendPort, e);
  } finally {
    await input.close();
  }
}

Future<void> _restoreZipWorker(Map<String, dynamic> args) async {
  final sendPort = args['sendPort'] as SendPort;
  final zipPath = args['zipPath'] as String;
  final password = args['password'] as String?;
  final acceptedFormats = (args['acceptedFormats'] as List).cast<String>().toSet();
  final maxVersion = args['maxVersion'] as int;
  final mediaRoot = args['mediaRoot'] as String;
  final replaceMode = args['replaceMode'] as bool;

  final input = InputFileStream(zipPath);
  try {
    _sendProgress(
      sendPort,
      password != null ? '正在解密与校验备份包…' : '正在校验备份包…',
    );

    final decoded = _readAndValidateArchiveInWorker(
      input: input,
      password: password,
      acceptedFormats: acceptedFormats,
      maxVersion: maxVersion,
    );

    final mediaEntries = decoded['mediaEntries'] as List<ArchiveFile>;

    // 只有备份包和密码全部校验通过后，才清理覆盖旧媒体目录
    if (replaceMode) {
      for (final sub in const ['audio', 'photos', 'documents', 'external']) {
        final dir = Directory(p.join(mediaRoot, sub));
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      }
    }

    int restoredMediaFiles = 0;
    final total = mediaEntries.length;
    for (var i = 0; i < total; i++) {
      final entry = mediaEntries[i];
      final relWithoutPrefix = entry.name.substring('media/'.length);
      if (relWithoutPrefix.isEmpty) continue;
      final segments = relWithoutPrefix
          .split('/')
          .where((s) => s.isNotEmpty)
          .toList();
      if (segments.isEmpty || segments.any((s) => s == '.' || s == '..')) {
        continue;
      }

      final targetSegments =
          segments.first == 'external' ? ['documents', ...segments] : segments;
      final destPath = p.normalize(p.joinAll([mediaRoot, ...targetSegments]));
      if (!p.isWithin(mediaRoot, destPath)) {
        continue;
      }

      final destFile = File(destPath);
      if (!replaceMode && await destFile.exists()) {
        _sendProgress(
          sendPort,
          '正在恢复媒体文件（${i + 1} / $total）…',
          i + 1,
          total,
        );
        continue;
      }

      final entryBytes = _readEntryBytesInWorker(entry);
      await destFile.parent.create(recursive: true);
      await destFile.writeAsBytes(entryBytes, flush: true);
      restoredMediaFiles++;

      _sendProgress(
        sendPort,
        '正在解压媒体文件（${i + 1} / $total）…',
        i + 1,
        total,
      );
    }

    sendPort.send({
      'kind': 'done',
      'result': {
        'patients': decoded['patients'],
        'messages': decoded['messages'],
        'logs': decoded['logs'],
        'restoredMediaFiles': restoredMediaFiles,
      },
    });
  } catch (e) {
    _sendError(sendPort, e);
  } finally {
    await input.close();
  }
}

List<int> _readEntryBytesInWorker(ArchiveFile entry) {
  try {
    return entry.readBytes() ?? const [];
  } on ArchiveException catch (e) {
    final msg = e.message.toLowerCase();
    if (msg.contains('password is needed')) {
      throw const BackupPasswordRequiredException();
    }
    if (msg.contains('wrong password')) {
      throw const BackupWrongPasswordException();
    }
    rethrow;
  }
}

Map<String, dynamic> _readAndValidateArchiveInWorker({
  required InputFileStream input,
  required String? password,
  required Set<String> acceptedFormats,
  required int maxVersion,
}) {
  final Archive archive;
  try {
    archive = ZipDecoder().decodeStream(input, password: password);
  } catch (e) {
    throw FormatException('无法读取该压缩包（请确认文件未损坏）：$e');
  }

  ArchiveFile? manifestFile;
  ArchiveFile? dataFile;
  final mediaEntries = <ArchiveFile>[];

  for (final file in archive.files) {
    if (!file.isFile) continue;
    if (file.name == 'manifest.json') {
      manifestFile = file;
    } else if (file.name == 'data.json') {
      dataFile = file;
    } else if (file.name.startsWith('media/')) {
      mediaEntries.add(file);
    }
  }

  if (manifestFile == null || dataFile == null) {
    throw const FormatException('该文件不是有效的会话备份包（缺少清单或数据文件）');
  }

  final dynamic manifestObj;
  try {
    final manifestBytes = _readEntryBytesInWorker(manifestFile);
    manifestObj = jsonDecode(utf8.decode(manifestBytes));
  } on BackupPasswordRequiredException {
    rethrow;
  } on BackupWrongPasswordException {
    rethrow;
  } catch (_) {
    if (password != null) {
      throw const BackupWrongPasswordException();
    }
    throw const FormatException('备份清单损坏或无法解析');
  }

  if (manifestObj is! Map || !acceptedFormats.contains(manifestObj['format'])) {
    throw const FormatException('文件格式不匹配，可能选成了配置文本或其他压缩包');
  }
  final version = manifestObj['version'];
  if (version is! int || version > maxVersion) {
    throw FormatException('备份包版本 ($version) 高于当前应用支持的版本，请更新应用后再恢复');
  }

  final dynamic dataObj;
  try {
    final dataBytes = _readEntryBytesInWorker(dataFile);
    dataObj = jsonDecode(utf8.decode(dataBytes));
  } on BackupPasswordRequiredException {
    rethrow;
  } on BackupWrongPasswordException {
    rethrow;
  } catch (_) {
    if (password != null) {
      throw const BackupWrongPasswordException();
    }
    throw const FormatException('备份数据损坏或无法解析');
  }

  if (dataObj is! Map) {
    throw const FormatException('备份数据格式损坏');
  }

  List<Map<String, dynamic>> readRowList(String key) {
    final raw = dataObj[key];
    if (raw == null) return const [];
    if (raw is! List) {
      throw FormatException('备份数据中的 $key 字段格式异常');
    }
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  return {
    'exportedAt': manifestObj['exportedAt']?.toString(),
    'patients': readRowList('patients'),
    'messages': readRowList('messages'),
    'logs': readRowList('generationLogs'),
    'mediaEntries': mediaEntries,
  };
}
