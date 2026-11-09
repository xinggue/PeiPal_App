import 'dart:io';

import 'package:paddle_ocr_flutter/paddle_ocr_flutter.dart';

class PaddleLocalOcr {
  static final PaddleOcrFlutter _engine = PaddleOcrFlutter();
  static Future<void>? _initFuture;

  static Future<void> ensureInit() {
    return _initFuture ??= _engine.init(threadNum: 4);
  }

  static Future<bool> isAvailable() async {
    if (!Platform.isAndroid) return false;
    try {
      await ensureInit();
      return true;
    } catch (_) {
      _initFuture = null;
      return false;
    }
  }

  static Future<String> recognize(List<String> imagePaths) async {
    await ensureInit();
    final pages = <String>[];
    for (var i = 0; i < imagePaths.length; i++) {
      try {
        final regions = await _engine.recognize(imagePaths[i]);
        final lines = regions
            .map((r) => r.text.trim())
            .where((t) => t.isNotEmpty)
            .join('\n');
        if (lines.isNotEmpty) pages.add(lines);
      } catch (e) {
        pages.add('[第 ${i + 1} 页: $e]');
      }
    }
    return pages.join('\n\n');
  }
}
