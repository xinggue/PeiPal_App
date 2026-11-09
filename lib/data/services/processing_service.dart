import 'dart:async';
import 'dart:collection';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';

import '../../domain/models/message.dart';
import '../repositories/message_repository.dart';
import 'api/api_service.dart';
import 'task/task_center.dart';

/// 异步并发控制器：限制同时发往云端接口的最大请求数，防止突发多图请求触发第三方限流或封禁
class AsyncLimiter {
  int maxConcurrent;
  int _running = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  AsyncLimiter({this.maxConcurrent = 2});

  int get activeCount => _running;
  int get queuedCount => _waiters.length;

  void updateMaxConcurrent(int newMax) {
    if (newMax < 1) return;
    maxConcurrent = newMax;
    while (_running < maxConcurrent && _waiters.isNotEmpty) {
      final next = _waiters.removeFirst();
      next.complete();
    }
  }

  Future<T> run<T>(Future<T> Function() task) async {
    if (_running >= maxConcurrent) {
      final completer = Completer<void>();
      _waiters.add(completer);
      await completer.future;
    }

    _running++;
    try {
      return await task();
    } finally {
      _running--;
      if (_waiters.isNotEmpty) {
        final next = _waiters.removeFirst();
        next.complete();
      }
    }
  }
}

/// Manages async processing of ASR and OCR with DB-based state machine.
///
/// Flow for every task:
///   1. Insert placeholder message in DB (transcribed/extracted text = '')
///   2. Call the API (throttled through internal AsyncLimiter)
///   3. Update placeholder with result or error
///
/// The [state] counter increments after each DB change. ChatPage listens
/// to this provider and invalidates [messagesProvider] on each tick,
/// causing the UI to re-read from DB and pick up the new placeholder or
/// updated result. This works even if the user navigated away — the DB
/// is always updated, and initState re-fetches when they return.
class ProcessingService extends StateNotifier<int> {
  /// ASR/OCR 失败或部分页面失败时存入转写/识别字段的文本以这些特征开头。
  /// 生成病历时必须识别并排除，防止把错误提示当成临床素材送给 LLM。
  static bool isFailureText(String? text) {
    if (text == null) return false;
    final t = text.trimLeft();
    return t.startsWith('ASR失败') ||
        t.startsWith('ASR超时') ||
        t.startsWith('OCR失败') ||
        t.startsWith('OCR超时') ||
        t.startsWith('【部分页面识别失败】') ||
        t.contains('【第') && t.contains('页识别失败:');
  }

  final MessageRepository _repo;
  final ApiService _api;
  final TaskCenter? _taskCenter;

  /// 内部全局限制器：OCR 限制最多并发（可由设置配置，默认 2），ASR 限制最多 2 个并发
  /// 避免选中数十张图片时 1 秒内发出大量突发请求导致被第三方 API 限流拉黑
  final AsyncLimiter _ocrLimiter;
  final AsyncLimiter _asrLimiter = AsyncLimiter(maxConcurrent: 2);

  ProcessingService(this._repo, this._api, [this._taskCenter, int ocrConcurrency = 2])
      : _ocrLimiter = AsyncLimiter(maxConcurrent: ocrConcurrency.clamp(1, 10)),
        super(0);

  void setOcrConcurrency(int count) {
    _ocrLimiter.updateMaxConcurrent(count.clamp(1, 10));
  }

  Future<void> processAsr(String patientId, String filePath,
      {String? existingMsgId, String patientName = '会话'}) async {
    Message placeholder;
    if (existingMsgId != null) {
      final existing = await _repo.getById(existingMsgId);
      if (existing != null) {
        placeholder = existing.copyWith(transcribedText: '');
        await _repo.update(placeholder);
      } else {
        placeholder =
            Message.asrResult(patientId: patientId, transcribedText: '');
        await _repo.insert(placeholder);
      }
    } else {
      placeholder =
          Message.asrResult(patientId: patientId, transcribedText: '');
      await _repo.insert(placeholder);
    }
    state++;

    // 登记到任务中心
    BackgroundTask? bgTask;
    if (_taskCenter != null) {
      final waitNotice = _asrLimiter.activeCount >= _asrLimiter.maxConcurrent
          ? '正在排队等待发送...'
          : '正在请求语音识别接口...';
      bgTask = BackgroundTask(
        id: placeholder.id,
        type: TaskType.asr,
        patientId: patientId,
        patientName: patientName,
        title: '语音转写',
        stageDescription: waitNotice,
      );
      _taskCenter.registerTask(bgTask);
    }

    final stopwatch = Stopwatch()..start();
    // 排队并限流执行
    final resultText = await _asrLimiter.run(() async {
      if (bgTask != null && _taskCenter != null) {
        bgTask.stageDescription = '正在请求语音识别接口...';
        _taskCenter.notifyTaskUpdated();
      }
      return _callWithErrorHandling(
        () => _api.transcribeAudio(filePath),
        service: 'ASR',
      );
    });
    stopwatch.stop();

    await _repo.update(placeholder.copyWith(transcribedText: resultText));
    state++;

    if (bgTask != null && _taskCenter != null) {
      bgTask.durationMs = stopwatch.elapsedMilliseconds;
      if (isFailureText(resultText)) {
        bgTask.status = TaskStatus.failed;
        bgTask.error = resultText;
        bgTask.stageDescription = '转写失败';
      } else {
        bgTask.status = TaskStatus.success;
        bgTask.progress = 1.0;
        bgTask.stageDescription = '转写完成';
        bgTask.resultMessageId = placeholder.id;
      }
      _taskCenter.notifyTaskUpdated();
    }
  }

  Future<void> processOcr(
    String patientId,
    List<String> filePaths, {
    String? targetPhotoMsgId,
    String patientName = '会话',
  }) async {
    String taskId;

    if (targetPhotoMsgId != null) {
      // 原生内嵌绑定：直接回写图片文书本身
      taskId = targetPhotoMsgId;
      final photoMsg = await _repo.getById(targetPhotoMsgId);
      if (photoMsg != null) {
        // 清空原有识别文本，进入“识别中”状态
        await _repo.update(photoMsg.copyWith(extractedText: ''));
      }
    } else {
      // 兼容兜底：创建独立占位消息
      final placeholder =
          Message.ocrResult(patientId: patientId, extractedText: '');
      await _repo.insert(placeholder);
      taskId = placeholder.id;
    }
    state++;

    BackgroundTask? bgTask;
    if (_taskCenter != null) {
      final waitNotice = _ocrLimiter.activeCount >= _ocrLimiter.maxConcurrent
          ? '在队列中等待识别 (${_ocrLimiter.queuedCount + 1})...'
          : '正在分析图片文本...';
      bgTask = BackgroundTask(
        id: taskId,
        type: TaskType.ocr,
        patientId: patientId,
        patientName: patientName,
        title: '材料OCR识别 (${filePaths.length}页)',
        stageDescription: waitNotice,
      );
      _taskCenter.registerTask(bgTask);
    }

    final stopwatch = Stopwatch()..start();
    // 排队并受控限流执行
    final resultText = await _ocrLimiter.run(() async {
      if (bgTask != null && _taskCenter != null) {
        bgTask.stageDescription = '正在分析图片文本...';
        _taskCenter.notifyTaskUpdated();
      }
      // 在发送前微延迟 120ms，给接口呼吸时间，防止免费端瞬时峰值
      await Future<void>.delayed(const Duration(milliseconds: 120));
      return _callWithErrorHandling(
        () => _api.extractTextFromImages(filePaths),
        service: 'OCR',
      );
    });
    stopwatch.stop();

    if (targetPhotoMsgId != null) {
      final photoMsg = await _repo.getById(targetPhotoMsgId);
      if (photoMsg != null) {
        await _repo.update(photoMsg.copyWith(extractedText: resultText));
      }
    } else {
      final msg = await _repo.getById(taskId);
      if (msg != null) {
        await _repo.update(msg.copyWith(extractedText: resultText));
      }
    }
    state++;

    if (bgTask != null && _taskCenter != null) {
      bgTask.durationMs = stopwatch.elapsedMilliseconds;
      if (isFailureText(resultText)) {
        bgTask.status = TaskStatus.failed;
        bgTask.error = resultText;
        bgTask.stageDescription = resultText.contains('【部分页面识别失败】')
            ? '部分页面异常'
            : 'OCR失败';
      } else {
        bgTask.status = TaskStatus.success;
        bgTask.progress = 1.0;
        bgTask.stageDescription = '识别完成';
        bgTask.resultMessageId = taskId;
      }
      _taskCenter.notifyTaskUpdated();
    }
  }

  Future<String> _callWithErrorHandling(
    Future<String> Function() apiCall, {
    required String service,
  }) async {
    try {
      return await apiCall();
    } on DioException catch (e) {
      final code = e.response?.statusCode;
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return '$service超时\n服务器未在预期时间内响应';
      }
      if (e.type == DioExceptionType.connectionError) {
        return '$service失败\n无法连接到服务器\n请检查网络和接口地址';
      }
      return '$service失败\n${code != null ? "HTTP $code" : "网络错误"}\n${e.message ?? ''}';
    } catch (e) {
      return '$service失败\n$e';
    }
  }
}
