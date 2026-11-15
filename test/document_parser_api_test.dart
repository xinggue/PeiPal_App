import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/api/document_parser_api.dart';
import 'package:peipal/domain/models/document_parser_provider.dart';

class Adapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions) respond;
  Adapter(this.respond);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) => respond(options);
  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object value) => ResponseBody.fromString(
  jsonEncode(value),
  200,
  headers: {
    Headers.contentTypeHeader: ['application/json'],
  },
);

void main() {
  late Directory dir;
  late File file;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('document_api_');
    file = File('${dir.path}/test.pdf')..writeAsStringSync('%PDF-1.7');
  });
  tearDown(() => dir.delete(recursive: true));

  test(
    'DeepSeek receives original PDF and returns partial metadata separately',
    () async {
      final dio = Dio()
        ..httpClientAdapter = Adapter((options) async {
          expect(options.uri.path, '/v1/tools/ocr');
          expect(options.headers['Authorization'], 'Bearer key');
          final form = options.data as FormData;
        expect(Map.fromEntries(form.fields)['purpose'], 'text_recognition');
          expect(form.files.single.value.filename, 'test.pdf');
          return jsonResponse({
            'page_count': 2,
            'pages': [
              {
                'text': '<｜ref｜>第一段<｜/ref｜><｜box｜>[[1,2,3,4]]<｜/box｜>',
                'finish_reason': 'stop',
              },
              {'text': '第二段', 'finish_reason': 'length'},
            ],
          });
        });
      final result = await DocumentParserApi(dio: dio).parse(
        DocumentParserProviderConfig.presets.first.copyWith(apiKey: 'key'),
        file.path,
        cancelToken: CancelToken(),
        onTaskCreated: (_) async => fail('DeepSeek has no resumable ID'),
      );
      expect(result.pageCount, 2);
      expect(result.isPartial, isTrue);
      expect(result.text, contains('第一段'));
      expect(result.text, isNot(contains('<｜')));
      expect(result.text, isNot(contains('不完整')));
      expect(result.warnings.single, contains('第 2 页'));
    },
  );

  test(
    'Zhipu sync upload persists task ID before polling without reupload',
    () async {
      final requests = <String>[];
      var persisted = false;
      final dio = Dio()
        ..httpClientAdapter = Adapter((options) async {
          requests.add(options.method);
          if (options.method == 'POST') {
            expect(options.uri.path, '/api/paas/v4/files/parser/sync');
            final form = options.data as FormData;
        expect(Map.fromEntries(form.fields)['tool_type'], 'prime-sync');
        expect(Map.fromEntries(form.fields)['file_type'], 'PDF');
            return jsonResponse({'status': 'processing', 'task_id': 'job-1'});
          }
          expect(persisted, isTrue);
          return jsonResponse({
            'status': 'succeeded',
            'content': '# 标题\n| 钠 | 140 |',
          });
        });
      final config = DocumentParserProviderConfig.presets.last.copyWith(
        apiKey: 'key',
      );
      final result = await DocumentParserApi(dio: dio).parse(
        config,
        file.path,
        cancelToken: CancelToken(),
        onTaskCreated: (id) async {
          expect(id, 'job-1');
          persisted = true;
        },
      );
      expect(result.text, contains('140'));
      expect(requests, ['POST', 'GET']);
      requests.clear();
      await DocumentParserApi(dio: dio).parse(
        config,
        file.path,
        remoteTaskId: 'job-1',
        cancelToken: CancelToken(),
        onTaskCreated: (_) async => fail('Must resume existing task'),
      );
      expect(requests, ['GET']);
    },
  );

  test('downloaded Markdown artifact uses no provider authorization', () async {
    final zip = Archive()
      ..addFile(
        ArchiveFile(
          'result.md',
          utf8.encode('# 完整结果\n正文').length,
          utf8.encode('# 完整结果\n正文'),
        ),
      );
    final dio = Dio()
      ..httpClientAdapter = Adapter((options) async {
        if (options.uri.host == 'storage.example') {
          expect(options.headers['Authorization'], isNull);
          return ResponseBody.fromBytes(ZipEncoder().encode(zip), 200);
        }
        return jsonResponse({
          'status': 'succeeded',
          'task_id': 'job',
          'parsing_result_url': 'https://storage.example/result.zip',
        });
      });
    final result = await DocumentParserApi(dio: dio).parse(
      DocumentParserProviderConfig.presets.last.copyWith(apiKey: 'key'),
      file.path,
      cancelToken: CancelToken(),
      onTaskCreated: (_) async {},
    );
    expect(result.text, contains('完整结果'));
    expect(result.text, isNot(contains('storage.example')));
  });

  test(
    'HTTP 200 errors and terminal task failures do not become document text',
    () async {
      final dio = Dio()
        ..httpClientAdapter = Adapter(
          (_) async => jsonResponse({
            'error': {'message': '余额不足'},
          }),
        );
      final api = DocumentParserApi(dio: dio);
      final config = DocumentParserProviderConfig.presets.last.copyWith(
        apiKey: 'key',
      );
      await expectLater(
        api.parse(
          config,
          file.path,
          cancelToken: CancelToken(),
          onTaskCreated: (_) async {},
        ),
        throwsFormatException,
      );
      dio.httpClientAdapter = Adapter(
        (_) async => jsonResponse({'status': 'failed', 'message': '无法解析'}),
      );
      await expectLater(
        api.parse(
          config,
          file.path,
          remoteTaskId: 'job',
          cancelToken: CancelToken(),
          onTaskCreated: (_) async {},
        ),
        throwsA(isA<DocumentRemoteTaskFailed>()),
      );
    },
  );
}
