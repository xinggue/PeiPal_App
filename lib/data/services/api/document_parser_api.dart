import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:dio/dio.dart';
import '../../../domain/models/document_parse_info.dart';
import '../../../domain/models/document_parser_provider.dart';
import 'deepseek_tools_service.dart';

class DocumentRemoteTaskFailed implements Exception {
  final String message;
  const DocumentRemoteTaskFailed(this.message);
  @override
  String toString() => message;
}

class DocumentParserApi {
  final Dio dio;
  final Future<void> Function(Duration) sleep;
  DocumentParserApi({Dio? dio, Future<void> Function(Duration)? sleep})
    : dio =
          dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 30))),
      sleep = sleep ?? Future<void>.delayed;

  static String zhipuBase(String url) => url
      .trim()
      .replaceFirst(RegExp(r'/+$'), '')
      .replaceFirst(RegExp(r'/files/parser(?:/(?:sync|create))?$'), '');

  /// Tests connectivity and API key authorization for the active document parser.
  Future<String> testConnection(DocumentParserProviderConfig config) async {
    final baseUrl = config.baseUrl.trim();
    final apiKey = config.apiKey.trim();
    if (baseUrl.isEmpty) throw Exception('接口地址不能为空');
    if (apiKey.isEmpty) throw Exception('未填写 API Key');

    final endpoint = config.kind == DocumentParserKind.deepseek
        ? DeepSeekToolsService.modelsEndpoint(baseUrl)
        : '${zhipuBase(baseUrl)}/models';
    final stopwatch = Stopwatch()..start();
    try {
      final resp = await dio.get(
        endpoint,
        options: Options(
          headers: {'Authorization': 'Bearer $apiKey'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      stopwatch.stop();
      if (resp.statusCode == 200) {
        return '连通正常 (${stopwatch.elapsedMilliseconds}ms)';
      } else if (resp.statusCode == 401 || resp.statusCode == 403) {
        return 'Key无效 (${resp.statusCode})';
      } else if (resp.statusCode == 404) {
        return '端点已响应 (${stopwatch.elapsedMilliseconds}ms)';
      }
      return '响应 HTTP ${resp.statusCode} (${stopwatch.elapsedMilliseconds}ms)';
    } on DioException catch (e) {
      stopwatch.stop();
      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout) {
        return '连接超时';
      }
      return '网络失败: ${e.response?.statusCode ?? "无法连接"}';
    } catch (e) {
      stopwatch.stop();
      return '测试失败: $e';
    }
  }

  Future<DocumentParseResult> parse(
    DocumentParserProviderConfig config,
    String filePath, {
    required CancelToken cancelToken,
    String? remoteTaskId,
    required Future<void> Function(String id) onTaskCreated,
  }) async {
    if (config.kind == DocumentParserKind.deepseek) {
      return DeepSeekToolsService(dio: dio).recognizeDocument(
        baseUrl: config.baseUrl,
        apiKey: config.apiKey,
        filePath: filePath,
        cancelToken: cancelToken,
      );
    }
    final base = zhipuBase(config.baseUrl);
    final options = Options(
      headers: {'Authorization': 'Bearer ${config.apiKey.trim()}'},
      sendTimeout: const Duration(seconds: 120),
      receiveTimeout: const Duration(seconds: 180),
    );
    Map response;
    String? taskId = remoteTaskId;
    if (taskId == null) {
      final ext = DocumentParserProviderConfig.extension(filePath);
      final upload = await dio.post(
        '$base/files/parser/${config.toolType == 'prime-sync' ? 'sync' : 'create'}',
        data: FormData.fromMap({
          'tool_type': config.toolType,
          'file_type': ext == 'htm' ? 'HTML' : ext.toUpperCase(),
          'file': await MultipartFile.fromFile(filePath),
        }),
        options: options,
        cancelToken: cancelToken,
      );
      response = _object(upload.data);
      if (response['success'] == false || response['status'] == 'failed') {
        throw DocumentRemoteTaskFailed(
          response['message']?.toString() ?? '文件解析失败',
        );
      }
      taskId = response['task_id']?.toString();
      if (taskId != null && taskId.isNotEmpty) await onTaskCreated(taskId);
      if (response['status'] == 'succeeded') {
        return _readResult(
          response,
          options,
          cancelToken,
          base: base,
          taskId: taskId,
        );
      }
      if (taskId == null || taskId.isEmpty) {
        throw const FormatException('服务商未返回解析任务 ID');
      }
    }
    // Once uploaded, retries and app recovery query the same task, without uploading again.
    for (var attempt = 0; attempt < 180; attempt++) {
      if (cancelToken.isCancelled) throw cancelToken.cancelError!;
      final result = await dio.get(
        '$base/files/parser/result/$taskId/text',
        options: options,
        cancelToken: cancelToken,
      );
      response = _object(result.data);
      if (response['status'] == 'succeeded') {
        return _readResult(
          response,
          options,
          cancelToken,
          base: base,
          taskId: taskId,
        );
      }
      if (response['status'] != 'processing') {
        throw DocumentRemoteTaskFailed(
          response['message']?.toString() ?? '文件解析失败',
        );
      }
      // Cancellation also interrupts the delay, rather than waiting for another poll.
      await Future.any([
        sleep(const Duration(seconds: 3)),
        cancelToken.whenCancel.then<void>((e) => throw e),
      ]);
    }
    throw const FormatException('解析仍在进行，可稍后重试查询');
  }

  Map _object(dynamic raw) {
    final data = raw is String ? jsonDecode(raw) : raw;
    if (data is! Map) throw const FormatException('文件解析响应格式不正确');
    if (data['error'] != null) {
      final error = data['error'];
      throw FormatException(
        error is Map
            ? error['message']?.toString() ?? '文件解析失败'
            : error.toString(),
      );
    }
    return data;
  }

  Future<DocumentParseResult> _readResult(
    Map data,
    Options options,
    CancelToken token, {
    required String base,
    String? taskId,
  }) async {
    final content = data['content'];
    var text = content is String ? content.trim() : '';
    // The text-result endpoint has a 1 MiB output limit. Fetch the full artifact at the boundary.
    if (text.isEmpty || utf8.encode(text).length >= 1024 * 1024) {
      var url = data['parsing_result_url']?.toString();
      if ((url == null || url.isEmpty) && taskId != null) {
        final result = await dio.get(
          '$base/files/parser/result/$taskId/download_link',
          options: options,
          cancelToken: token,
        );
        url = _object(result.data)['parsing_result_url']?.toString();
      }
      if (url == null || url.isEmpty) {
        throw const FormatException('服务商未返回完整解析文本');
      }
      final uri = Uri.tryParse(url);
      if (uri == null ||
          !{'http', 'https'}.contains(uri.scheme) ||
          uri.host.isEmpty) {
        throw const FormatException('解析结果下载地址无效');
      }
      // Result URLs can belong to object storage. Never forward the provider API key.
      final result = await dio.get<ResponseBody>(
        url,
        options: Options(
          responseType: ResponseType.stream,
          receiveTimeout: const Duration(seconds: 120),
        ),
        cancelToken: token,
      );
      final builder = BytesBuilder(copy: false);
      await for (final chunk in result.data!.stream) {
        builder.add(chunk);
        if (builder.length > 50 * 1024 * 1024) {
          throw const FormatException('解析结果过大，请拆分文件后重试');
        }
      }
      final bytes = builder.takeBytes();
      if (bytes.length >= 4 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
        final archive = ZipDecoder().decodeBytes(bytes);
        final files =
            archive.files
                .where(
                  (f) =>
                      f.isFile &&
                      RegExp(
                        r'\.(md|txt)$',
                        caseSensitive: false,
                      ).hasMatch(f.name),
                )
                .toList()
              ..sort((a, b) => _naturalOrder(a.name, b.name));
        if (files.fold<int>(0, (sum, f) => sum + f.size) > 50 * 1024 * 1024) {
          throw const FormatException('解析文本过大，请拆分文件后重试');
        }
        text = files
            .map((f) => utf8.decode(f.content as List<int>))
            .join('\n\n')
            .trim();
      } else {
        text = utf8.decode(bytes).trim();
      }
    }
    if (text.isEmpty) throw const FormatException('未取得可用的解析文字');
    final warnings = <String>[
      if (data['truncated'] == true || data['incomplete'] == true)
        '服务商返回的解析结果不完整',
    ];
    return DocumentParseResult(
      text,
      warnings: warnings,
      pageCount: data['page_count'] is int ? data['page_count'] as int : null,
    );
  }

  static int _naturalOrder(String a, String b) {
    final tokens = RegExp(r'\d+|\D+');
    final left = tokens.allMatches(a).map((m) => m.group(0)!).toList();
    final right = tokens.allMatches(b).map((m) => m.group(0)!).toList();
    for (var i = 0; i < left.length && i < right.length; i++) {
      final l = int.tryParse(left[i]);
      final r = int.tryParse(right[i]);
      final result = l != null && r != null ? l.compareTo(r) : left[i].compareTo(right[i]);
      if (result != 0) return result;
    }
    return left.length.compareTo(right.length);
  }
}
