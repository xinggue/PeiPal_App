import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/repositories/message_repository.dart';
import 'package:peipal/data/services/api/document_parser_api.dart';
import 'package:peipal/data/services/api/document_parser_config_store.dart';
import 'package:peipal/data/services/document_processing_service.dart';
import 'package:peipal/data/services/task/task_center.dart';
import 'package:peipal/domain/models/document_parse_info.dart';
import 'package:peipal/domain/models/document_parser_provider.dart';
import 'package:peipal/domain/models/message.dart';

class MemoryMessages extends MessageRepository {
  final data = <String, Message>{};
  @override
  Future<Message?> getById(String id) async => data[id];
  @override
  Future<void> update(Message m) async {
    if (data.containsKey(m.id)) data[m.id] = m;
  }

  @override
  Future<List<Message>> getInterruptedDocuments() async => data.values
      .where((m) => m.documentParse?.status == DocumentParseStatus.running)
      .toList();
}

class Parser extends DocumentParserApi {
  int calls = 0;
  String? resumedId;
  Completer<DocumentParseResult>? pending;
  Object? error;
  @override
  Future<DocumentParseResult> parse(
    DocumentParserProviderConfig config,
    String filePath, {
    required CancelToken cancelToken,
    String? remoteTaskId,
    required Future<void> Function(String id) onTaskCreated,
  }) async {
    calls++;
    resumedId = remoteTaskId;
    await onTaskCreated(remoteTaskId ?? 'remote-1');
    if (error != null) throw error!;
    if (pending != null) {
      return Future.any([
        pending!.future,
        cancelToken.whenCancel.then<DocumentParseResult>((e) => throw e),
      ]);
    }
    return const DocumentParseResult('正文\n| 钠 | 140 |');
  }
}

void main() {
  late Directory dir;
  late File file;
  late MemoryMessages repo;
  late Parser parser;
  late ProviderContainer container;
  late DocumentProcessingService service;
  late DocumentParserProviderConfig config;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('document_processing_');
    file = File('${dir.path}/report.pdf')..writeAsStringSync('%PDF-1.7');
    repo = MemoryMessages();
    parser = Parser();
    container = ProviderContainer();
    config = DocumentParserProviderConfig.presets.last.copyWith(apiKey: 'key');
    service = DocumentProcessingService(
      repo: repo,
      api: parser,
      tasks: container.read(taskCenterProvider),
      loadSettings: () async => DocumentParserSettings(
        providers: [config],
        activeProviderId: config.id,
      ),
      onChanged: (_) {},
    );
  });
  tearDown(() async {
    service.dispose();
    container.dispose();
    await dir.delete(recursive: true);
  });

  Message seed({DocumentParseInfo? info, String? text}) {
    final m = Message.document(
      patientId: 'p',
      filePath: file.path,
      fileSize: 8,
      fileName: 'report.pdf',
      documentParse: info,
      extractedText: text,
    );
    repo.data[m.id] = m;
    return m;
  }

  test(
    'binds success to the original message and preserves it when retry fails',
    () async {
      final m = seed();
      await service.process(m.id);
      expect(repo.data, hasLength(1));
      expect(
        repo.data[m.id]!.documentParse!.status,
        DocumentParseStatus.success,
      );
      expect(repo.data[m.id]!.usableDocumentText, contains('140'));
      parser.error = const FormatException('服务器失败');
      await service.process(m.id);
      expect(
        repo.data[m.id]!.documentParse!.status,
        DocumentParseStatus.failed,
      );
      expect(repo.data[m.id]!.usableDocumentText, contains('140'));
      expect(repo.data[m.id]!.usableDocumentText, isNot(contains('失败')));
      expect(container.read(taskCenterProvider).tasks, hasLength(1));
    },
  );

  test(
    'recovery resumes a saved remote task and never reuploads an unknown task',
    () async {
      final recoverable = seed(
        info: DocumentParseInfo(
          status: DocumentParseStatus.running,
          attemptId: 'old',
          providerId: config.id,
          baseUrl: config.baseUrl,
          toolType: config.toolType,
          remoteTaskId: 'existing-id',
        ),
      );
      final unknown = seed(
        info: DocumentParseInfo(
          status: DocumentParseStatus.running,
          attemptId: 'unknown',
          providerId: config.id,
          baseUrl: config.baseUrl,
          toolType: config.toolType,
        ),
      );
      await service.recoverInterrupted();
      expect(parser.calls, 1);
      expect(parser.resumedId, 'existing-id');
      expect(
        repo.data[recoverable.id]!.documentParse!.status,
        DocumentParseStatus.success,
      );
      expect(
        repo.data[unknown.id]!.documentParse!.status,
        DocumentParseStatus.failed,
      );
      expect(repo.data[unknown.id]!.usableDocumentText, isEmpty);
    },
  );

  test(
    'cancel or deletion cannot resurrect a document or overwrite its result',
    () async {
      final m = seed();
      parser.pending = Completer();
      final future = service.process(m.id);
      while (parser.calls == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      service.cancel(m.id);
      await future;
      expect(
        repo.data[m.id]!.documentParse!.status,
        DocumentParseStatus.cancelled,
      );
      parser.pending = Completer();
      final deleted = seed();
      final running = service.process(deleted.id);
      while (parser.calls < 2) {
        await Future<void>.delayed(Duration.zero);
      }
      repo.data.remove(deleted.id);
      parser.pending!.complete(const DocumentParseResult('不能写回'));
      await running;
      expect(repo.data.containsKey(deleted.id), isFalse);
      expect(
        container.read(taskCenterProvider).getTask(deleted.id)!.status,
        TaskStatus.cancelled,
      );
    },
  );
}
