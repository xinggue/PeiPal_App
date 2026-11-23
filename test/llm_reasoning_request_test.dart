import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/api/api_config.dart';
import 'package:peipal/data/services/api/api_service.dart';

void main() {
  test(
    'effort is kept across format retries, streaming and non-streaming',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      final requests = <Map<String, dynamic>>[];
      server.listen((request) async {
        final body =
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>;
        requests.add(body);
        if (body['response_format']?['type'] == 'json_schema') {
          request.response.statusCode = 400;
          request.response.write('{}');
        } else if (body['stream'] == true) {
          request.response.headers.contentType = ContentType(
            'text',
            'event-stream',
          );
          request.response.write(
            'data: ${jsonEncode({
              'choices': [
                {
                  'delta': {'content': '{"ok":true}'},
                },
              ],
            })}\n\ndata: [DONE]\n\n',
          );
        } else {
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'choices': [
                {
                  'message': {'content': '{"ok":true}'},
                },
              ],
            }),
          );
        }
        await request.response.close();
      });
      final service = ApiService();
      final config = LlmConfig(
        baseUrl: 'http://${server.address.address}:${server.port}',
        model: 'deepseek-v4-pro',
        reasoningEffort: 'max',
      );
      service.updateLlmConfig(config);
      expect(
        await service.chatCompletion(
          systemPrompt: 'Return JSON',
          userPrompt: 'hello',
          jsonSchema: {
            'name': 'test',
            'schema': {'type': 'object'},
          },
          onChunk: (_, _) {},
        ),
        '{"ok":true}',
      );
      expect(requests, hasLength(2));
      expect(requests.every((r) => r['reasoning_effort'] == 'max'), isTrue);
      service.updateLlmConfig(config.copyWith(reasoningEffort: 'none'));
      await service.chatCompletion(systemPrompt: '', userPrompt: 'hello');
      expect(requests.last['reasoning_effort'], 'none');
      service.updateLlmConfig(config.copyWith(reasoningEffort: ''));
      await service.chatCompletion(systemPrompt: '', userPrompt: 'hello');
      expect(requests.last.containsKey('reasoning_effort'), isFalse);
    },
  );

  test('SSE streaming decodes multi-byte UTF-8 split across chunks without corruption',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));

    final payload =
        'data: ${jsonEncode({'choices': [{'delta': {'content': '{"主诉":"胸闷气短三天"}'}}]})}\n\n'
        'data: [DONE]\n\n';
    final bytes = utf8.encode(payload);
    // 故意在“主”(3 字节 UTF-8) 中间和“闷”中间切开分包
    final zhIndex = payload.indexOf('主');
    final byteOffset = utf8.encode(payload.substring(0, zhIndex)).length + 1;
    final zhIndex2 = payload.indexOf('闷');
    final byteOffset2 = utf8.encode(payload.substring(0, zhIndex2)).length + 2;

    server.listen((request) async {
      request.response.bufferOutput = false;
      request.response.headers.contentType = ContentType('text', 'event-stream');
      request.response.add(bytes.sublist(0, byteOffset));
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      request.response.add(bytes.sublist(byteOffset, byteOffset2));
      await request.response.flush();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      request.response.add(bytes.sublist(byteOffset2));
      await request.response.close();
    });

    final service = ApiService()
      ..updateLlmConfig(LlmConfig(
        baseUrl: 'http://${server.address.address}:${server.port}',
        model: 'deepseek-chat',
      ));

    final chunks = <String>[];
    final result = await service.chatCompletion(
      systemPrompt: 'Return JSON',
      userPrompt: 'hello',
      jsonMode: false,
      onChunk: (piece, _) => chunks.add(piece),
    );
    expect(result, '{"主诉":"胸闷气短三天"}');
    expect(result, isNot(contains('\uFFFD')));
    expect(chunks.join(), '{"主诉":"胸闷气短三天"}');
  });
}
