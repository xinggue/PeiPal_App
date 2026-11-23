import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// iOS 原生 Speech (SFSpeechRecognizer) 语音识别通道。
class AppleSpeechAsr {
  static const MethodChannel _channel =
      MethodChannel('com.xinggue.docmasterPei/apple_speech_asr');

  static bool get isSupported => !kIsWeb && Platform.isIOS;

  static Future<bool> isAvailable({String? language}) async {
    if (!isSupported) return false;
    try {
      final ok = await _channel.invokeMethod<bool>('isAvailable', {
        if (language != null && language.trim().isNotEmpty)
          'language': language.trim(),
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  static Future<String> transcribeFile(
    String filePath, {
    String? language,
  }) async {
    if (!isSupported) {
      throw UnsupportedError('Apple 系统语音识别仅支持 iOS 设备');
    }
    final text = await _channel.invokeMethod<String>('transcribe', {
      'filePath': filePath,
      if (language != null && language.trim().isNotEmpty)
        'language': language.trim(),
    });
    return (text ?? '').trim();
  }
}
