import 'dart:convert';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum PickedImportKind { text, zip }

class PickedImportFile {
  final PickedImportKind kind;
  final String fileName;
  final String? textContent;
  final File? tempZipFile;

  const PickedImportFile.text({
    required this.fileName,
    required String content,
  })  : kind = PickedImportKind.text,
        textContent = content,
        tempZipFile = null;

  const PickedImportFile.zip({
    required this.fileName,
    required File zipFile,
  })  : kind = PickedImportKind.zip,
        textContent = null,
        tempZipFile = zipFile;
}

/// 跨平台配置文件（.txt / .json）读写辅助工具
class ConfigFileIo {
  static const _channel =
      MethodChannel('com.xinggue.docmasterPei/config_file');

  /// 生成带时间戳的默认导出文件名
  static String buildFileName(String prefix, {String extension = 'txt'}) {
    final safePrefix = prefix
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final ts = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    return '${safePrefix}_$ts.$extension';
  }

  /// 将配置文本保存为本地文件
  /// - Android：默认通过系统 SAF 选择保存位置；若取消或使用快捷保存，则直接写入系统 `Download/` 目录
  /// - iOS：通过系统文件选择器导出到「文件」App / iCloud Drive / 第三方云盘
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

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      final saved = await _channel.invokeMethod<String>(
        'saveWithDocumentPicker',
        {
          'fileName': suggestedName,
          'content': content,
        },
      );
      return saved;
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

    // 其他平台兜底：写入应用文档目录
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/$suggestedName');
    await file.writeAsString(content, encoding: utf8);
    return file.path;
  }

  /// 从本地选取并读取配置文本文件
  static Future<String?> pickAndReadConfigFile() async {
    final typeGroup = XTypeGroup(
      label: '配置文件',
      extensions: <String>['txt', 'json', 'text', 'cfg', 'csv'],
      // iOS does not infer UTIs from extensions. public.data also permits
      // generic .cfg files supplied by Files/iCloud document providers.
      uniformTypeIdentifiers: defaultTargetPlatform == TargetPlatform.iOS
          ? const <String>['public.data']
          : null,
    );
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return utf8.decode(bytes, allowMalformed: true);
  }

  /// 第一步：唤起系统文件选择器（不阻塞在自定义弹窗之后）
  static Future<XFile?> pickImportXFile() {
    final typeGroup = XTypeGroup(
      label: '导入文件',
      extensions: <String>['txt', 'json', 'text', 'cfg', 'csv', 'zip'],
      uniformTypeIdentifiers: defaultTargetPlatform == TargetPlatform.iOS
          ? const <String>['public.data', 'public.zip-archive']
          : null,
    );
    return openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
  }

  /// 第二步：读取已选文件，自动按扩展名与文件头魔数区分文本配置与 ZIP 会话备份包。
  static Future<PickedImportFile> readPickedImportFile(XFile file) async {
    final header = <int>[];
    await for (final chunk in file.openRead(0, 4)) {
      header.addAll(chunk);
      if (header.length >= 4) break;
    }

    final isZipMagic =
        header.length >= 2 && header[0] == 0x50 && header[1] == 0x4B;
    final isZipExt = file.name.toLowerCase().endsWith('.zip');
    if (isZipMagic || isZipExt) {
      final tempDir =
          await Directory.systemTemp.createTemp('peipal_import_zip_');
      final localCopy = File(p.join(tempDir.path, 'backup.zip'));
      await file.saveTo(localCopy.path);
      return PickedImportFile.zip(fileName: file.name, zipFile: localCopy);
    }

    final bytes = await file.readAsBytes();
    return PickedImportFile.text(
      fileName: file.name,
      content: utf8.decode(bytes, allowMalformed: true),
    );
  }

  /// 统一导入文件选择器：自动按扩展名与文件头魔数区分文本配置与 ZIP 会话备份包。
  static Future<PickedImportFile?> pickImportFile() async {
    final file = await pickImportXFile();
    if (file == null) return null;
    return readPickedImportFile(file);
  }

  /// 将本地临时二进制文件（如 .zip 数据备份包）导出到用户指定位置。
  /// 使用文件路径传递而非内存字节，避免 Android Binder IPC 体积限制。
  static Future<String?> saveBinaryFile({
    required String sourcePath,
    required String suggestedName,
    String mimeType = 'application/zip',
    String typeLabel = '数据备份包',
    List<String> extensions = const ['zip'],
  }) async {
    if (!kIsWeb && Platform.isAndroid) {
      return _channel.invokeMethod<String>('saveFileWithSafPicker', {
        'fileName': suggestedName,
        'sourcePath': sourcePath,
        'mimeType': mimeType,
      });
    }

    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.iOS) {
      return _channel.invokeMethod<String>('saveFileWithDocumentPicker', {
        'fileName': suggestedName,
        'sourcePath': sourcePath,
      });
    }

    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      final location = await getSaveLocation(
        suggestedName: suggestedName,
        acceptedTypeGroups: [
          XTypeGroup(label: typeLabel, extensions: extensions),
        ],
      );
      if (location == null) return null;
      await File(sourcePath).copy(location.path);
      return location.path;
    }

    final dir = await getApplicationDocumentsDirectory();
    final dest = '${dir.path}/$suggestedName';
    await File(sourcePath).copy(dest);
    return dest;
  }

  /// 从本地选取二进制文件（如 .zip 备份包）。
  static Future<XFile?> pickBinaryFile({
    String label = '数据备份包',
    List<String> extensions = const ['zip'],
  }) {
    final typeGroup = XTypeGroup(
      label: label,
      extensions: extensions,
      uniformTypeIdentifiers: defaultTargetPlatform == TargetPlatform.iOS
          ? const <String>['public.zip-archive', 'public.data']
          : null,
    );
    return openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
  }
}
