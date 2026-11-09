import 'package:flutter/services.dart';

class AppleVisionOcr {
  static const _channel = MethodChannel('com.xinggue.docmasterPei/apple_vision_ocr');

  static Future<String> recognize(List<String> imagePaths) async {
    final text = await _channel.invokeMethod<String>('recognize', {
      'paths': imagePaths,
      'languages': const ['zh-Hans', 'en-US'],
    });
    return text ?? '';
  }

  static Future<bool> isAvailable() async {
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable');
      return ok ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
