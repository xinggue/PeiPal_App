import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../domain/models/document_parse_info.dart';
import '../../domain/models/document_parser_provider.dart';
import '../../domain/models/message.dart';
import '../repositories/message_repository.dart';
import 'api/document_parser_api.dart';
import 'api/document_parser_config_store.dart';
import 'media/document_parser_service.dart';
import 'processing_service.dart';
import 'task/task_center.dart';

class DocumentProcessingService extends StateNotifier<int> {
  final MessageRepository repo;
  final DocumentParserApi api;
  final TaskCenter tasks;
  final Future<DocumentParserSettings> Function() loadSettings;
  final void Function(String patientId) onChanged;
  final _limiter = AsyncLimiter(maxConcurrent: 2);
  final Map<String, Future<void>> _running = {};
  final Map<String, CancelToken> _tokens = {};
  bool _recovering = false;

  DocumentProcessingService({
    required this.repo,
    required this.api,
    required this.tasks,
    required this.loadSettings,
    required this.onChanged,
  }) : super(0);

  static Future<void> validateFile(
    String path,
    DocumentParserProviderConfig? config,
  ) async {
    final ext = DocumentParserProviderConfig.extension(path);
    final local = DocumentParserProviderConfig.isLocalFile(path);
    if (!local &&
        !DocumentParserProviderConfig.officeExtensions.contains(ext)) {
      throw FormatException('暂不支持 .$ext 文件');
    }
    if (!local && (config == null || !config.isConfigured)) {
      throw const FormatException('请先配置文件解析服务');
    }
    if (!local && !config!.supportedExtensions.contains(ext)) {
      throw FormatException('当前文件解析服务不支持 .$ext，请更换服务');
    }
    final file = File(path);
    if (!await file.exists()) throw const FormatException('文件不存在，请重新选择');
    final limit = local
        ? DocumentParserService.maxTextBytes
        : config!.maxBytes(path);
    if (await file.length() > limit) {
      throw FormatException('文件不能超过 ${limit ~/ (1024 * 1024)} MiB，请拆分后发送');
    }
    // Inspect container signatures without decoding or rendering any document.
    if (!local && !const {'html', 'htm', 'wps'}.contains(ext)) {
      final handle = await file.open();
      late List<int> prefix;
      try {
        prefix = await handle.read(1024);
      } finally {
        await handle.close();
      }
      final zip = prefix.length >= 4 && prefix[0] == 0x50 && prefix[1] == 0x4b;
      final ole =
          prefix.length >= 8 &&
          prefix[0] == 0xd0 &&
          prefix[1] == 0xcf &&
          prefix[2] == 0x11 &&
          prefix[3] == 0xe0;
      final valid = ext == 'pdf'
          ? String.fromCharCodes(prefix).contains('%PDF-')
          : const {'docx', 'pptx', 'xlsx'}.contains(ext)
          ? zip
          : ole;
      if (!valid) throw const FormatException('文件内容与后缀不符，请使用原始文件格式');
    }
  }

  void cancel(String messageId) => _tokens[messageId]?.cancel('已取消文件解析');

  Future<void> process(String messageId, {bool recovery = false}) {
    final existing = _running[messageId];
    if (existing != null) return existing;
    final future = _process(messageId, recovery: recovery);
    _running[messageId] = future;
    return future.whenComplete(() {
      _running.remove(messageId);
      _tokens.remove(messageId);
    });
  }

  Future<void> recoverInterrupted() async {
    if (_recovering) return;
    _recovering = true;
    try {
      final documents = await repo.getInterruptedDocuments();
      await Future.wait(
        documents.map((msg) => process(msg.id, recovery: true)),
      );
    } finally {
      _recovering = false;
    }
  }

  void _notify(String patientId) {
    if (!mounted) return;
    state++;
    onChanged(patientId);
  }

  Future<void> _process(String messageId, {required bool recovery}) async {
    final original = await repo.getById(messageId);
    if (original == null ||
        original.type != MessageType.document ||
        original.filePaths.isEmpty) {
      return;
    }
    final path = original.filePaths.first;
    final local = DocumentParserProviderConfig.isLocalFile(path);
    final old = original.documentParse;
    BackgroundTask? task;
    var info = DocumentParseInfo(
      status: DocumentParseStatus.running,
      attemptId: const Uuid().v4(),
      providerId: old?.providerId ?? '',
      baseUrl: old?.baseUrl ?? '',
      toolType: old?.toolType ?? '',
      remoteTaskId: old?.remoteTaskId,
      warnings: old?.warnings ?? const [],
      hasResult: original.usableDocumentText.isNotEmpty,
      pageCount: old?.pageCount,
    );
    final token = CancelToken();
    _tokens[messageId] = token;
    Future<bool> write(DocumentParseInfo value, {String? text}) async {
      final latest = await repo.getById(messageId);
      if (latest == null) return false;
      if (latest.documentParse != null &&
          latest.documentParse!.attemptId != info.attemptId &&
          latest.documentParse!.attemptId != old?.attemptId) {
        return false;
      }
      await repo.update(
        latest.copyWith(documentParse: value, extractedText: text),
      );
      _notify(original.patientId);
      return true;
    }

    try {
      DocumentParserProviderConfig? config;
      String? remoteTaskId;
      if (!local) {
        final settings = await loadSettings();
        final canResume =
            old?.remoteTaskId != null &&
            old?.status != DocumentParseStatus.success &&
            old?.status != DocumentParseStatus.partial;
        if (canResume || recovery) {
          config = settings.providers
              .where((p) => p.id == old?.providerId)
              .firstOrNull;
          if (config == null ||
              !config.isConfigured ||
              config.baseUrl != old?.baseUrl ||
              config.toolType != old?.toolType) {
            throw const FormatException('原文件解析配置已变更，请恢复配置后重试');
          }
          remoteTaskId = old?.remoteTaskId;
        } else {
          config = settings.activeProvider;
        }
        if (recovery && remoteTaskId == null) {
          throw const FormatException('上次解析已中断，未自动重复上传。请确认后重新解析');
        }
        info = DocumentParseInfo(
          status: DocumentParseStatus.running,
          attemptId: info.attemptId,
          providerId: config?.id ?? '',
          baseUrl: config?.baseUrl ?? '',
          toolType: config?.toolType ?? '',
          remoteTaskId: remoteTaskId,
          hasResult: info.hasResult,
          pageCount: info.pageCount,
        );
      }
      await validateFile(path, config);
      if (!await write(info, text: info.hasResult ? original.usableDocumentText : null)) return;
      task = BackgroundTask(
        id: messageId,
        type: TaskType.document,
        patientId: original.patientId,
        patientName: '会话',
        title: original.content ?? '文件解析',
        cancelToken: token,
        stageDescription: local
            ? '正在读取文本'
            : remoteTaskId == null
            ? '正在上传文件'
            : '正在查询解析结果',
      );
      tasks.registerTask(task);
      final result = await _limiter.run(() async {
        if (token.isCancelled) throw token.cancelError!;
        if (local) {
          return DocumentParseResult(
            await DocumentParserService.parseFileText(path),
          );
        }
        return api.parse(
          config!,
          path,
          cancelToken: token,
          remoteTaskId: remoteTaskId,
          onTaskCreated: (id) async {
            info = info.copyWith(remoteTaskId: id);
            if (!await write(info)) token.cancel('文件消息已删除');
            task!.stageDescription = '正在解析文件';
            if (mounted) tasks.notifyTaskUpdated();
          },
        );
      });
      if (token.isCancelled) throw token.cancelError!;
      if (result.text.trim().isEmpty) throw const FormatException('未提取到可用文字');
      info = info.copyWith(
        status: result.isPartial
            ? DocumentParseStatus.partial
            : DocumentParseStatus.success,
        hasResult: true,
        warnings: result.warnings,
        pageCount: result.pageCount,
      );
      if (!await write(info, text: result.text)) return;
      task.status = result.isPartial ? TaskStatus.partial : TaskStatus.success;
      task.stageDescription = result.isPartial ? '部分完成，请检查解析结果' : '解析完成';
      task.progress = 1;
      task.resultMessageId = messageId;
    } catch (e) {
      final cancelled = token.isCancelled;
      final message = _errorMessage(
        e,
        hasRemoteTask: info.remoteTaskId != null,
      );
      info = info.copyWith(
        status: cancelled
            ? DocumentParseStatus.cancelled
            : DocumentParseStatus.failed,
        error: cancelled ? '已取消' : message,
        clearRemoteTaskId:
            e is DocumentRemoteTaskFailed ||
            (e is DioException &&
                const {404, 410}.contains(e.response?.statusCode)),
      );
      await write(info);
      task?.status = cancelled ? TaskStatus.cancelled : TaskStatus.failed;
      task?.error = info.error;
      task?.stageDescription = cancelled ? '已取消' : '解析失败';
      task?.resultMessageId = messageId;
    } finally {
      if (task?.isRunning == true) {
        task!.status = TaskStatus.cancelled;
        task.stageDescription = '文件消息已删除';
      }
      if (mounted) tasks.notifyTaskUpdated();
    }
  }

  @override
  void dispose() {
    for (final token in _tokens.values) {
      token.cancel();
    }
    super.dispose();
  }

  static String _errorMessage(Object error, {required bool hasRemoteTask}) {
    if (error is FormatException) return error.message;
    if (error is DioException) {
      if (const {
        DioExceptionType.sendTimeout,
        DioExceptionType.receiveTimeout,
      }.contains(error.type)) {
        return hasRemoteTask ? '连接超时，可稍后重试查询' : '解析超时，服务商可能仍在处理；重新解析将再次上传';
      }
      final data = error.response?.data;
      final detail = data is Map ? data['error'] : null;
      if (detail is Map && detail['message'] is String) {
        return detail['message'] as String;
      }
      return '文件解析失败（${error.response?.statusCode ?? "网络异常"}）';
    }
    return error.toString();
  }
}
