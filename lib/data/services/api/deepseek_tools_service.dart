import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';

class DeepSeekToolsService {
  final Dio _dio;

  DeepSeekToolsService({Dio? dio})
    : _dio =
          dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 30)));

  /// Accept an API origin, a /v1 base, or a complete tool endpoint.
  static String apiBase(String baseUrl) {
    var base = baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    base = base.replaceFirst(RegExp(r'/tools(?:/(?:asr|ocr))?$'), '');
    if (!base.endsWith('/v1')) base = '$base/v1';
    return base;
  }

  static String modelsEndpoint(String baseUrl) => '${apiBase(baseUrl)}/models';

  Options _options(String apiKey, {required bool audio}) => Options(
    headers: {'Authorization': 'Bearer ${apiKey.trim()}'},
    contentType: 'multipart/form-data',
    sendTimeout: Duration(seconds: audio ? 600 : 120),
    receiveTimeout: const Duration(seconds: 180),
  );

  Map _result(dynamic data) {
    if (data is String) data = jsonDecode(data);
    if (data is! Map) {
      throw const FormatException('DeepSeek 返回的识别结果格式不正确');
    }
    if (data['error'] != null) {
      final error = data['error'];
      throw FormatException(
        error is Map
            ? error['message']?.toString() ?? 'DeepSeek 识别失败'
            : error.toString(),
      );
    }
    return data;
  }

  Future<String> transcribe({
    required String baseUrl,
    required String apiKey,
    required String filePath,
  }) async {
    final file = File(filePath);
    if (await file.length() > 8 * 1024 * 1024) {
      throw const FormatException('DeepSeek 语音文件不能超过 8 MiB');
    }
    _validateAudio(await file.readAsBytes());
    final response = await _dio.post(
      '${apiBase(baseUrl)}/tools/asr',
      data: FormData.fromMap({'file': await MultipartFile.fromFile(filePath)}),
      options: _options(apiKey, audio: true),
    );
    final data = _result(response.data);
    if (data['text'] is! String) {
      throw const FormatException('DeepSeek 语音识别响应未包含 text 字段');
    }
    return (data['text'] as String).trim();
  }

  void _validateAudio(Uint8List bytes) {
    String tag(int start, int end) =>
        String.fromCharCodes(bytes.sublist(start, end));
    if (bytes.length >= 12 && tag(0, 4) == 'RIFF' && tag(8, 12) == 'WAVE') {
      final data = ByteData.sublistView(bytes);
      int? byteRate;
      int? audioSize;
      var hasFormat = false;
      for (var offset = 12; offset + 8 <= bytes.length;) {
        final kind = tag(offset, offset + 4);
        final size = data.getUint32(offset + 4, Endian.little);
        final start = offset + 8;
        if (start + size > bytes.length) {
          throw const FormatException('WAV 文件不完整');
        }
        if (kind == 'fmt ' && size >= 16) {
          final format = data.getUint16(start, Endian.little);
          final channels = data.getUint16(start + 2, Endian.little);
          final sampleRate = data.getUint32(start + 4, Endian.little);
          byteRate = data.getUint32(start + 8, Endian.little);
          final bits = data.getUint16(start + 14, Endian.little);
          if (format != 1 ||
              bits != 16 ||
              ![1, 2].contains(channels) ||
              ![
                8000,
                16000,
                22050,
                24000,
                32000,
                44100,
                48000,
              ].contains(sampleRate) ||
              byteRate != sampleRate * channels * 2) {
            throw const FormatException(
              'DeepSeek 语音识别需要 16 位 PCM WAV 或 Ogg Opus 音频',
            );
          }
          hasFormat = true;
        } else if (kind == 'data') {
          audioSize = size;
        }
        offset = start + size + (size.isOdd ? 1 : 0);
      }
      if (!hasFormat ||
          byteRate == null ||
          audioSize == null ||
          audioSize == 0) {
        throw const FormatException('WAV 文件缺少有效的音频数据');
      }
      if (audioSize > byteRate * 120) {
        throw const FormatException('DeepSeek 单次语音识别最长 120 秒，请分段录音');
      }
      return;
    }
    if (bytes.length >= 4 &&
        tag(0, 4) == 'OggS' &&
        String.fromCharCodes(bytes.take(128)).contains('OpusHead')) {
      return;
    }
    throw const FormatException('DeepSeek 语音识别需要 16 位 PCM WAV 或 Ogg Opus 音频');
  }

  Future<String> recognize({
    required String baseUrl,
    required String apiKey,
    required String filePath,
  }) async {
    if (await File(filePath).length() > 100 * 1024 * 1024) {
      throw const FormatException('DeepSeek 识别文件不能超过 100 MiB');
    }
    final response = await _dio.post(
      '${apiBase(baseUrl)}/tools/ocr',
      data: FormData.fromMap({
        'file': await MultipartFile.fromFile(filePath),
        'purpose': 'text_recognition',
      }),
      options: _options(apiKey, audio: false),
    );
    final data = _result(response.data);
    final pages = data['pages'];
    if (pages is! List || pages.isEmpty) {
      throw const FormatException('DeepSeek 文字识别响应未包含页面结果');
    }
    final results = <String>[];
    for (var i = 0; i < pages.length; i++) {
      final page = pages[i];
      if (page is! Map || page['text'] is! String) {
        throw const FormatException('DeepSeek 文字识别页面结果格式不正确');
      }
      final text = (page['text'] as String)
          .replaceAll(RegExp(r'<｜box｜>[\s\S]*?<｜/box｜>'), '\n')
          .replaceAll(RegExp(r'<｜/?ref｜>'), '')
          .trim();
      results.add(
        [
          if (pages.length > 1) '--- 第 ${i + 1} 页 ---',
          if (page['finish_reason'] == 'length') '【第 ${i + 1} 页识别结果不完整】',
          text,
        ].join('\n'),
      );
    }
    return results.join('\n\n').trim();
  }
}
