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
}
