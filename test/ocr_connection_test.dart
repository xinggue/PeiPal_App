import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/api/api_config.dart';
import 'package:peipal/data/services/api/api_service.dart';
import 'package:peipal/data/services/api/ocr_provider_service.dart';
import 'package:peipal/domain/models/ocr_provider.dart';

class _MockAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions options) handler;

  _MockAdapter(this.handler);

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);

  @override
  void close({bool force = false}) {}
}

ResponseBody _jsonBody(int status, Map<String, dynamic> body) {
  return ResponseBody.fromString(
    jsonEncode(body),
    status,
    headers: {
      Headers.contentTypeHeader: ['application/json'],
    },
  );
}

void main() {
  group('PaddleOCR 连通测试与模型校验', () {
    test('发送 multipart/form-data 且 400 缺文件视为鉴权通过与连通正常', () async {
      late RequestOptions captured;
      final dio = Dio()
        ..httpClientAdapter = _MockAdapter((options) async {
          captured = options;
          return _jsonBody(400, {'code': 400, 'msg': 'file is required'});
        });

      final service = OcrProviderService(dio);
      final provider = OcrProviderPresets.builtIn
          .firstWhere((p) => p.protocol == OcrProtocol.paddleOcr)
          .copyWith(
            baseUrl: 'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs/',
            apiKey: 'secret-token',
          );

      final msg = await service.fetchStatusOrPing(provider);
      expect(msg, startsWith('连通正常'));
      expect(captured.uri.toString(),
          'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs');
      expect(captured.headers['Authorization'], 'bearer secret-token');
      expect(captured.contentType, startsWith('multipart/form-data'));

      final api = ApiService(rawDio: dio)
        ..updateOcrConfig(const OcrConfig(
          provider: OcrProvider.paddleOcr,
          baseUrl: 'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs',
          apiKey: 'secret-token',
          model: 'PaddleOCR-VL-1.6',
        ));
      expect(await api.testOcrConnection(), isTrue);
    });

    test('401 / 404 / 500 均应判定为失败', () async {
      for (final status in [401, 403, 404, 500]) {
        final dio = Dio()
          ..httpClientAdapter = _MockAdapter(
            (_) async => _jsonBody(status, {'code': status}),
          );
        final api = ApiService(rawDio: dio)
          ..updateOcrConfig(const OcrConfig(
            provider: OcrProvider.paddleOcr,
            baseUrl: 'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs',
            apiKey: 'bad-token',
            model: 'PaddleOCR-VL-1.6',
          ));
        expect(await api.testOcrConnection(), isFalse,
            reason: 'HTTP $status should fail');

        final service = OcrProviderService(dio);
        final provider = OcrProviderPresets.builtIn
            .firstWhere((p) => p.protocol == OcrProtocol.paddleOcr)
            .copyWith(apiKey: 'bad-token');
        await expectLater(service.fetchModels(provider), throwsException);
      }
    });
  });

  group('MinerU 连通测试', () {
    test('400 参数校验错误视为端点可达且未限频', () async {
      late RequestOptions captured;
      final dio = Dio()
        ..httpClientAdapter = _MockAdapter((options) async {
          captured = options;
          return _jsonBody(400, {
            'error': {'code': 'invalid_request', 'message': 'field "file_name" is not set'}
          });
        });

      final api = ApiService(rawDio: dio)
        ..updateOcrConfig(const OcrConfig(
          provider: OcrProvider.mineru,
          baseUrl: 'https://mineru.net/api/v1/agent/',
        ));
      expect(await api.testOcrConnection(), isTrue);
      expect(captured.uri.toString(), 'https://mineru.net/api/v1/agent/parse/file');
      expect(captured.data, isA<Map>());

      final service = OcrProviderService(dio);
      final provider = OcrProviderPresets.builtIn
          .firstWhere((p) => p.protocol == OcrProtocol.mineru);
      expect(await service.fetchStatusOrPing(provider), startsWith('连通正常'));
    });

    test('429 限频与 404/500 均应判定为失败', () async {
      for (final status in [429, 404, 500]) {
        final dio = Dio()
          ..httpClientAdapter = _MockAdapter(
            (_) async => _jsonBody(status, {'code': status}),
          );
        final api = ApiService(rawDio: dio)
          ..updateOcrConfig(const OcrConfig(
            provider: OcrProvider.mineru,
            baseUrl: 'https://mineru.net/api/v1/agent',
          ));
        expect(await api.testOcrConnection(), isFalse,
            reason: 'HTTP $status should fail');
      }

      final dio429 = Dio()
        ..httpClientAdapter = _MockAdapter((_) async => _jsonBody(429, {}));
      final service = OcrProviderService(dio429);
      final provider = OcrProviderPresets.builtIn
          .firstWhere((p) => p.protocol == OcrProtocol.mineru);
      expect(await service.fetchStatusOrPing(provider), '公网 IP 触发限频 (429)');
    });
  });
}
