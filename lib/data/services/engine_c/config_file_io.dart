import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

/// 跨平台配置文件（.txt / .json）读写辅助工具
class ConfigFileIo {
  static const _channel =
      MethodChannel('com.xinggue.docmasterPei/config_file');

  /// 生成带时间戳的默认配置文件名
  static String buildFileName(String prefix) {
    final safePrefix = prefix
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return '${safePrefix}_$ts.txt';
  }

  /// 将配置文本保存为本地文件
  /// - Android：默认通过系统 SAF 选择保存位置；若取消或使用快捷保存，则直接写入系统 `Download/` 目录
  /// - 桌面端 (macOS/Windows/Linux)：弹出系统另存为对话框
  /// 返回保存后的路径或文件名描述，若用户主动取消则返回 null
  static Future<String?> saveConfigTextFile({
    required String content,
    required String suggestedName,
    bool preferDirectDownloadOnAndroid = false,
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      if (preferDirectDownloadOnAndroid) {
        final saved = await _channel.invokeMethod<String>('saveToDownloads', {
          'fileName': suggestedName,
          'content': content,
        });
        return saved;
      } else {
        final saved = await _channel.invokeMethod<String>('saveWithSafPicker', {
          'fileName': suggestedName,
          'content': content,
        });
        return saved;
      }
    }

    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: const [
          XTypeGroup(label: '配置文本', extensions: ['txt', 'json']),
        ],
      );
      if (location == null) return null;
      final file = File(location.path);
      await file.writeAsString(content, encoding: utf8);
      return location.path;
    }

    // iOS 或其他平台兜底：写入应用文档目录
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$suggestedName');
    await file.writeAsString(content, encoding: utf8);
    return file.path;
  }

  /// 从本地选取并读取配置文本文件
  static Future<String?> pickAndReadConfigFile() async {
    const typeGroup = XTypeGroup(
      label: '配置文件',
      extensions: <String>['txt', 'json', 'text', 'cfg', 'csv'],
    );
    final file = await openFile(acceptedTypeGroups: const <XTypeGroup>[typeGroup]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }
}
