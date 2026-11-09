import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class MediaStorage {
  static Future<String> get _docDir async {
    final dir = await getApplicationDocumentsDirectory();
    return dir.path;
  }

  static Future<String> audioDir(String patientId) async {
    final path = p.join(await _docDir, 'audio', patientId);
    await Directory(path).create(recursive: true);
    return path;
  }

  static Future<String> photoDir(String patientId, String messageId) async {
    final path = p.join(await _docDir, 'photos', patientId, messageId);
    await Directory(path).create(recursive: true);
    return path;
  }

  static Future<String> saveAudio(String patientId, String messageId,
      String sourcePath) async {
    final dir = await audioDir(patientId);
    final ext = sourcePath.split('.').last;
    final dest = p.join(dir, '$messageId.$ext');
    await File(sourcePath).copy(dest);
    return dest;
  }

  static Future<List<String>> savePhotos(
      String patientId, String messageId, List<String> sourcePaths) async {
    final dir = await photoDir(patientId, messageId);
    final saved = <String>[];
    for (int i = 0; i < sourcePaths.length; i++) {
      final dest = p.join(dir, 'page_${(i + 1).toString().padLeft(3, '0')}.jpg');
      await File(sourcePaths[i]).copy(dest);
      saved.add(dest);
    }
    return saved;
  }

  static Future<String> fileDir(String patientId) async {
    final path = p.join(await _docDir, 'documents', patientId);
    await Directory(path).create(recursive: true);
    return path;
  }

  static Future<String> saveDocument(String patientId, String messageId, String sourcePath) async {
    final dir = await fileDir(patientId);
    final fileName = p.basename(sourcePath);
    final dest = p.join(dir, '${messageId}_$fileName');
    await File(sourcePath).copy(dest);
    return dest;
  }

  static Future<void> deleteAudio(String filePath) async {
    final file = File(filePath);
    if (await file.exists()) await file.delete();
  }

  static Future<void> deletePhotos(String patientId, String messageId) async {
    final dir = Directory(p.join(await _docDir, 'photos', patientId, messageId));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// 删除某个患者的全部本地媒体（语音 + 照片 + 文档）。
  static Future<void> deletePatientMedia(String patientId) async {
    final root = await _docDir;
    for (final sub in ['audio', 'photos', 'documents']) {
      final dir = Directory(p.join(root, sub, patientId));
      if (await dir.exists()) await dir.delete(recursive: true);
    }
  }
}
