import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/api/document_parser_api.dart';
import '../data/services/document_processing_service.dart';
import '../data/services/task/task_center.dart';
import 'document_parser_provider.dart';
import 'providers.dart';

final documentParserApiProvider = Provider<DocumentParserApi>(
  (ref) => DocumentParserApi(),
);

final documentProcessingProvider =
    StateNotifierProvider<DocumentProcessingService, int>((ref) {
      final service = DocumentProcessingService(
        repo: ref.read(messageRepositoryProvider),
        api: ref.read(documentParserApiProvider),
        tasks: ref.read(taskCenterProvider),
        loadSettings: () async {
          await ref.read(documentParserProvider.notifier).ready;
          return ref.read(documentParserProvider).requireValue;
        },
        onChanged: (id) {
          ref.invalidate(messagesProvider(id));
          ref.invalidate(lastMessageProvider(id));
        },
      );
      unawaited(
        service.recoverInterrupted().catchError((Object e) {
          debugPrint('恢复文件解析失败: $e');
        }),
      );
      return service;
    });
