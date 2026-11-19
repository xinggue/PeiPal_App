import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

class AppLogStats {
  final int fileCount;
  final int totalBytes;
  final int crashCount;

  const AppLogStats({
    required this.fileCount,
    required this.totalBytes,
    required this.crashCount,
  });
}

/// 纯本地滚动运行日志与崩溃日志记录服务。
///
/// 约束：
/// - 仅存储在应用本地支持目录 `logs/` 下，永不自动上传。
/// - 常规运行日志按单文件 512 KB 滚动，最多保留 5 份（总计 <= 2.5 MB）。
/// - 崩溃日志独立写入 `crash.log`（最多保留最近 20 条），避免被常规日志刷掉。
/// - 所有写入均经过敏感凭证脱敏过滤器，禁止写入业务/患者正文内容。
class AppLogService {
  AppLogService._();

  static final AppLogService instance = AppLogService._();

  static const int maxLogFileBytes = 512 * 1024;
  static const int maxRotatedFiles = 4; // app.log + app.log.1..4 = 5 files
  static const int maxCrashEntries = 20;
  static const String _crashDelimiter = '=== PEIPAL CRASH ===';

  /// 测试钩子：覆盖日志目录，避免在单测中依赖平台 path_provider。
  @visibleForTesting
  static Future<Directory> Function()? directoryOverride;

  static final DateFormat _tsFormat = DateFormat('yyyy-MM-dd HH:mm:ss.SSS');

  static final RegExp _bearerPattern = RegExp(
    r'(Bearer\s+)[A-Za-z0-9._\-+/=]{6,}',
    caseSensitive: false,
  );
  static final RegExp _skPattern = RegExp(r'\bsk-[A-Za-z0-9_\-]{6,}');
  static final RegExp _kvSecretPattern = RegExp(
    r'((?:api_?key|secret|token|password|authorization|x-owner-key|x-admin-token)["\x27]?\s*[:=]\s*(?:Bearer\s+)?)(?:"[^"]*"|\x27[^\x27]*\x27|[^\s,&;}\]]+)',
    caseSensitive: false,
  );

  Directory? _logDir;
  Future<void> _writeChain = Future<void>.value();

  @visibleForTesting
  static void resetForTesting() {
    instance._logDir = null;
    instance._writeChain = Future<void>.value();
  }

  /// 对文本中的常见密钥与鉴权凭证进行脱敏。
  static String sanitize(String input, {int maxLength = 2000}) {
    var out = input.replaceAll('\r', '');
    out = out.replaceAllMapped(_bearerPattern, (m) => '${m.group(1)}***');
    out = out.replaceAll(_skPattern, 'sk-***');
    out = out.replaceAllMapped(_kvSecretPattern, (m) => '${m.group(1)}***');
    if (out.length > maxLength) {
      out = '${out.substring(0, maxLength)}…[truncated]';
    }
    return out;
  }

  Future<Directory> _resolveDir() async {
    if (_logDir != null) return _logDir!;
    final override = directoryOverride;
    final dir = override != null
        ? await override()
        : Directory(
            p.join((await getApplicationSupportDirectory()).path, 'logs'),
          );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _logDir = dir;
    return dir;
  }

  Future<void> init() async {
    try {
      await _resolveDir();
    } catch (_) {}
  }

  void info(String tag, String message) {
    _enqueueLog('INFO', tag, message);
  }

  void warn(String tag, String message) {
    _enqueueLog('WARN', tag, message);
  }

  void error(
    String tag,
    String message, [
    Object? err,
    StackTrace? stack,
  ]) {
    final buf = StringBuffer(message);
    if (err != null) {
      buf.write(' | err=$err');
    }
    if (stack != null) {
      final stackLines = stack.toString().split('\n').take(8).join('\n');
      buf.write('\n$stackLines');
    }
    _enqueueLog('ERROR', tag, buf.toString());
  }

  Future<void> recordCrash(
    String source,
    Object err, [
    StackTrace? stack,
  ]) {
    final ts = _tsFormat.format(DateTime.now());
    final cleanErr = sanitize(err.toString(), maxLength: 1200);
    final cleanStack = stack == null
        ? ''
        : '\n${sanitize(stack.toString(), maxLength: 3000)}';
    final entry = '$_crashDelimiter [$ts] [$source]\n$cleanErr$cleanStack\n';

    return _enqueue(() async {
      final dir = await _resolveDir();
      final crashFile = File(p.join(dir.path, 'crash.log'));
      var existing = '';
      if (await crashFile.exists()) {
        existing = await crashFile.readAsString();
      }
      final entries = existing
          .split(_crashDelimiter)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .map((e) => '$_crashDelimiter $e\n')
          .toList();
      entries.add(entry);
      if (entries.length > maxCrashEntries) {
        entries.removeRange(0, entries.length - maxCrashEntries);
      }
      await crashFile.writeAsString(entries.join('\n'));

      // 同步在运行日志留一条索引，便于按时间线还原上下文
      await _appendRuntimeLine(
        dir,
        '[$ts] [CRASH] [$source] $cleanErr',
      );
    });
  }

  void _enqueueLog(String level, String tag, String message) {
    final ts = _tsFormat.format(DateTime.now());
    final cleanTag = sanitize(tag, maxLength: 40).replaceAll('\n', ' ');
    final cleanMsg = sanitize(message);
    final line = '[$ts] [$level] [$cleanTag] $cleanMsg';
    _enqueue(() async {
      final dir = await _resolveDir();
      await _appendRuntimeLine(dir, line);
    });
  }

  Future<void> _enqueue(Future<void> Function() action) {
    _writeChain = _writeChain.then((_) async {
      try {
        await action();
      } catch (_) {
        // 日志本身绝不能抛出未捕获异常影响主流程
      }
    });
    return _writeChain;
  }

  /// 等待当前队列中的日志全部落盘（供诊断导出与测试使用）。
  Future<void> flush() => _writeChain;

  Future<void> _appendRuntimeLine(Directory dir, String line) async {
    final active = File(p.join(dir.path, 'app.log'));
    if (await active.exists()) {
      final len = await active.length();
      if (len + line.length + 1 > maxLogFileBytes) {
        await _rotateLogs(dir);
      }
    }
    await active.writeAsString('$line\n', mode: FileMode.append);
  }

  Future<void> _rotateLogs(Directory dir) async {
    final oldest = File(p.join(dir.path, 'app.log.$maxRotatedFiles'));
    if (await oldest.exists()) {
      await oldest.delete();
    }
    for (var i = maxRotatedFiles - 1; i >= 1; i--) {
      final src = File(p.join(dir.path, 'app.log.$i'));
      if (await src.exists()) {
        await src.rename(p.join(dir.path, 'app.log.${i + 1}'));
      }
    }
    final active = File(p.join(dir.path, 'app.log'));
    if (await active.exists()) {
      await active.rename(p.join(dir.path, 'app.log.1'));
    }
  }

  Future<AppLogStats> getStats() async {
    await flush();
    try {
      final dir = await _resolveDir();
      if (!await dir.exists()) {
        return const AppLogStats(fileCount: 0, totalBytes: 0, crashCount: 0);
      }
      var fileCount = 0;
      var totalBytes = 0;
      var crashCount = 0;
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name == 'crash.log' || name == 'app.log' || name.startsWith('app.log.')) {
            fileCount++;
            totalBytes += await entity.length();
            if (name == 'crash.log') {
              final text = await entity.readAsString();
              crashCount = text
                  .split(_crashDelimiter)
                  .where((e) => e.trim().isNotEmpty)
                  .length;
            }
          }
        }
      }
      return AppLogStats(
        fileCount: fileCount,
        totalBytes: totalBytes,
        crashCount: crashCount,
      );
    } catch (_) {
      return const AppLogStats(fileCount: 0, totalBytes: 0, crashCount: 0);
    }
  }

  Future<void> clearLogs() {
    return _enqueue(() async {
      final dir = await _resolveDir();
      if (!await dir.exists()) return;
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = p.basename(entity.path);
          if (name == 'crash.log' || name == 'app.log' || name.startsWith('app.log.')) {
            await entity.delete();
          }
        }
      }
    });
  }

  /// 生成用于排障分享/导出的诊断报告文本（不含任何密钥与业务正文）。
  Future<String> buildDiagnosticReport({
    Map<String, String>? configSummary,
    int maxRuntimeChars = 80 * 1024,
  }) async {
    await flush();
    final buf = StringBuffer();
    var appVersion = 'unknown';
    var buildNumber = '';
    try {
      final info = await PackageInfo.fromPlatform();
      if (info.version.isNotEmpty) appVersion = info.version;
      buildNumber = info.buildNumber;
    } catch (_) {}

    final stats = await getStats();
    final nowStr = _tsFormat.format(DateTime.now());
    buf.writeln('=== PeiPal 诊断日志 ===');
    buf.writeln('生成时间: $nowStr');
    buf.writeln('应用版本: v$appVersion${buildNumber.isNotEmpty ? '+$buildNumber' : ''}');
    buf.writeln('运行平台: ${Platform.operatingSystem} (${Platform.operatingSystemVersion})');
    buf.writeln('日志统计: ${stats.fileCount} 个文件, ${stats.totalBytes} 字节, 崩溃记录 ${stats.crashCount} 条');

    if (configSummary != null && configSummary.isNotEmpty) {
      buf.writeln('');
      buf.writeln('--- 服务配置状态（已脱敏）---');
      for (final entry in configSummary.entries) {
        buf.writeln('${entry.key}: ${sanitize(entry.value, maxLength: 200)}');
      }
    }

    final dir = await _resolveDir();
    final crashFile = File(p.join(dir.path, 'crash.log'));
    buf.writeln('');
    buf.writeln('--- 最近崩溃记录 ---');
    if (await crashFile.exists()) {
      final crashText = (await crashFile.readAsString()).trim();
      buf.writeln(crashText.isEmpty ? '（无）' : sanitize(crashText, maxLength: 32 * 1024));
    } else {
      buf.writeln('（无）');
    }

    buf.writeln('');
    buf.writeln('--- 近期运行日志 ---');
    final runtimeBuf = StringBuffer();
    final prevFile = File(p.join(dir.path, 'app.log.1'));
    final activeFile = File(p.join(dir.path, 'app.log'));
    if (await prevFile.exists()) {
      runtimeBuf.write(await prevFile.readAsString());
    }
    if (await activeFile.exists()) {
      runtimeBuf.write(await activeFile.readAsString());
    }
    var runtimeText = runtimeBuf.toString().trim();
    if (runtimeText.length > maxRuntimeChars) {
      runtimeText = '...(已截取末尾内容)...\n${runtimeText.substring(runtimeText.length - maxRuntimeChars)}';
    }
    buf.writeln(runtimeText.isEmpty ? '（无）' : sanitize(runtimeText, maxLength: maxRuntimeChars + 64));

    return buf.toString();
  }
}
