import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/api/api_config.dart';
import 'package:peipal/data/services/api/api_service.dart';
import 'package:peipal/data/services/api/deepseek_tools_service.dart';
import 'package:peipal/data/services/media/wav_encoder.dart';

class _Binding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  _Binding();
  late Directory temp;
  late HttpServer server;
  late String base;
  late List<({String path, String body, String? auth})> requests;
  late dynamic responseBody;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('deepseek_tools_test_');
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://${server.address.address}:${server.port}';
    requests = [];
    responseBody = {'text': '识别结果'};
    server.listen((request) async {
      requests.add((
        path: request.uri.path,
        body: await const Utf8Decoder(
          allowMalformed: true,
        ).bind(request).join(),
        auth: request.headers.value('authorization'),
      ));
      request.response.headers.contentType = ContentType.json;
      request.response.write('\n\n${jsonEncode(responseBody)}');
      await request.response.close();
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => temp.path,
        );
  });

  tearDown(() async {
    await server.close(force: true);
    await temp.delete(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  Future<String> wav(int seconds) async {
    final pcm = File('${temp.path}/speech.pcm');
    await pcm.writeAsBytes(Uint8List(16000 * 2 * seconds));
    return WavEncoder.convertToWav(pcm.path);
  }

  test('normalizes origins, API bases and full tool endpoints', () {
    for (final path in [
      '',
      '/',
      '/v1',
      '/v1/',
      '/v1/tools',
      '/v1/tools/asr/',
      '/v1/tools/ocr',
    ]) {
      expect(DeepSeekToolsService.apiBase('$base$path'), '$base/v1');
      expect(
        DeepSeekToolsService.modelsEndpoint('$base$path'),
        '$base/v1/models',
      );
    }
  });

  test('ASR dispatch uploads only file and parses text', () async {
    final api = ApiService()
      ..updateAsrConfig(
        AsrConfig(
          provider: AsrProvider.deepseek,
          baseUrl: '$base/v1/tools/asr/',
          apiKey: 'test-key',
          model: 'must-not-send',
          language: 'must-not-send',
        ),
      );
    expect(await api.transcribeAudio(await wav(1)), '识别结果');
    expect(requests.single.path, '/v1/tools/asr');
    expect(requests.single.auth, 'Bearer test-key');
    expect(
      requests.single.body,
      contains('name="file"; filename="speech.wav"'),
    );
    expect(
      RegExp(
        r'name="(\w+)"',
      ).allMatches(requests.single.body).map((m) => m[1]).toList(),
      ['file'],
    );
  });

  test(
    'rejects oversized, invalid and overlong recordings before upload',
    () async {
      final service = DeepSeekToolsService();
      Future<String> transcribe(String path) =>
          service.transcribe(baseUrl: base, apiKey: 'test', filePath: path);
      await expectLater(
        transcribe(await wav(121)),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('120 秒'),
          ),
        ),
      );
      final invalid = File('${temp.path}/invalid.wav')
        ..writeAsStringSync('not audio');
      await expectLater(transcribe(invalid.path), throwsFormatException);
      final oversized = File('${temp.path}/large.wav');
      final handle = await oversized.open(mode: FileMode.write);
      await handle.truncate(8 * 1024 * 1024 + 1);
      await handle.close();
      await expectLater(
        transcribe(oversized.path),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('8 MiB'),
          ),
        ),
      );
      expect(requests, isEmpty);
    },
  );

  test(
    'OCR uploads purpose and file, cleans coordinates and reports truncation',
    () async {
      responseBody = {
        'pages': [
          {
            'index': 0,
            'text': '<｜ref｜>血红蛋白 120 g/L<｜/ref｜><｜box｜>[[1,2,3,4]]<｜/box｜>',
            'finish_reason': 'stop',
          },
          {
            'index': 1,
            'text': '| 检查 | 结果 |\n| 钠 | 140 |',
            'finish_reason': 'length',
          },
        ],
      };
      final image = File('${temp.path}/page.png')..writeAsStringSync('image');
      final api = ApiService()
        ..updateOcrConfig(
          OcrConfig(
            provider: OcrProvider.deepseek,
            baseUrl: base,
            apiKey: 'test-key',
            model: 'unused',
          ),
        );
      final text = await api.extractTextFromImages([image.path]);
      expect(text, contains('血红蛋白 120 g/L'));
      expect(text, contains('| 钠 | 140 |'));
      expect(text, contains('第 2 页识别结果不完整'));
      expect(text, isNot(contains('<｜')));
      expect(text, isNot(contains('[[1,2,3,4]]')));
      expect(requests.single.path, '/v1/tools/ocr');
      expect(requests.single.auth, 'Bearer test-key');
      expect(requests.single.body, contains('text_recognition'));
      expect(
        RegExp(
          r'name="(\w+)"',
        ).allMatches(requests.single.body).map((m) => m[1]).toSet(),
        {'file', 'purpose'},
      );
      expect(await image.exists(), isTrue);
    },
  );

  test(
    'HTTP 200 errors and malformed results do not become OCR text',
    () async {
      final file = File('${temp.path}/image.png')..writeAsStringSync('image');
      final service = DeepSeekToolsService();
      responseBody = {
        'error': {'message': 'OCR did not finish in time'},
      };
      await expectLater(
        service.recognize(baseUrl: base, apiKey: 'test', filePath: file.path),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('OCR did not finish'),
          ),
        ),
      );
      responseBody = {'pages': []};
      await expectLater(
        service.recognize(baseUrl: base, apiKey: 'test', filePath: file.path),
        throwsFormatException,
      );
      responseBody = {'request_id': 'missing-text'};
      await expectLater(
        service.transcribe(
          baseUrl: base,
          apiKey: 'test',
          filePath: await wav(1),
        ),
        throwsFormatException,
      );
    },
  );
}
