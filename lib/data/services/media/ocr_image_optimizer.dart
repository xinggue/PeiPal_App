import 'dart:io';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

class OcrImageOptimizer {
  /// 针对医疗病历 OCR 的最佳压缩规格：
  /// - 最大长边：2048 像素（足以保留检验单最小号字与小数点的清晰度）
  /// - JPEG 质量：85%（无肉眼可见伪影）
  /// - 若原图本来就小于 750KB，则无需额外压缩
  static Future<List<String>> prepareForOcr(List<String> originalPaths) async {
    final tempDir = await getTemporaryDirectory();
    final ocrCacheDir = Directory(p.join(tempDir.path, 'ocr_prepared'));
    if (!await ocrCacheDir.exists()) {
      await ocrCacheDir.create(recursive: true);
    }

    final preparedPaths = <String>[];

    for (int i = 0; i < originalPaths.length; i++) {
      final src = originalPaths[i];
      final file = File(src);
      if (!await file.exists()) {
        preparedPaths.add(src);
        continue;
      }

      final fileSize = await file.length();
      // 如果文件本身小于 750KB，说明已经是压缩图或小图，直接使用
      if (fileSize < 750 * 1024) {
        preparedPaths.add(src);
        continue;
      }

      final targetPath = p.join(
        ocrCacheDir.path,
        'ocr_${DateTime.now().millisecondsSinceEpoch}_$i.jpg',
      );

      try {
        final result = await FlutterImageCompress.compressAndGetFile(
          src,
          targetPath,
          minWidth: 2048,
          minHeight: 2048,
          quality: 85,
          format: CompressFormat.jpeg,
        );

        if (result != null && await File(result.path).exists()) {
          preparedPaths.add(result.path);
        } else {
          preparedPaths.add(src);
        }
      } catch (_) {
        // 若压缩发生异常，回退使用原图
        preparedPaths.add(src);
      }
    }

    return preparedPaths;
  }

  /// 在一次 OCR 请求执行完毕后立即清理本次产生的临时压缩图片
  /// （仅清理在 ocr_prepared 目录下的临时副本，原图绝对不动）
  static Future<void> cleanPreparedFiles(
      List<String> preparedPaths, List<String> originalPaths) async {
    final originalSet = originalPaths.toSet();
    for (final path in preparedPaths) {
      if (originalSet.contains(path)) continue;
      if (path.contains('ocr_prepared')) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {}
      }
    }
  }

  /// App 启动时清空 ocr_prepared 目录下的所有残留历史缓存
  static Future<void> purgePreparedCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      final ocrCacheDir = Directory(p.join(tempDir.path, 'ocr_prepared'));
      if (await ocrCacheDir.exists()) {
        final entities = await ocrCacheDir.list().toList();
        for (final entity in entities) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }
}
