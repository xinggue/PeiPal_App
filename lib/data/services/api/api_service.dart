import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import 'api_config.dart';
import 'deepseek_tools_service.dart';
import '../media/apple_vision_ocr.dart';
import '../media/ocr_image_optimizer.dart';
import '../media/paddle_local_ocr.dart';

class ApiService {
  LlmConfig _llmConfig = const LlmConfig();
  AsrConfig _asrConfig = const AsrConfig();
  OcrConfig _ocrConfig = const OcrConfig();

  LlmConfig get llmConfig => _llmConfig;
  AsrConfig get asrConfig => _asrConfig;
  OcrConfig get ocrConfig => _ocrConfig;

  // 记录各模型端点对结构化输出的支持能力缓存，避免每次都试错：
  // 'none' | 'json_object' | 'json_schema'
  final Map<String, String> _formatCapabilityCache = {};

  final Dio _llmDioInstance = Dio();
  final Dio _asrDioInstance = Dio();
  final Dio _ocrDioInstance = Dio();
  final Dio _rawDio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 30),
    receiveTimeout: const Duration(seconds: 60),
  ));

  void _clearCapabilityCache() {
    _formatCapabilityCache.clear();
  }

  void updateLlmConfig(LlmConfig config) {
    if (_llmConfig.baseUrl != config.baseUrl || _llmConfig.model != config.model) {
      _clearCapabilityCache();
    }
    _llmConfig = config;
  }

  void updateAsrConfig(AsrConfig config) {
    _asrConfig = config;
  }

  void updateOcrConfig(OcrConfig config) {
    _ocrConfig = config;
  }

  Dio _llmDio() {
    final isMimo = _llmConfig.baseUrl.contains('xiaomimimo');
    _llmDioInstance.options = BaseOptions(
      baseUrl: _llmConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 180),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${_llmConfig.apiKey}',
        if (isMimo) 'api-key': _llmConfig.apiKey,
      },
    );
    return _llmDioInstance;
  }

  Dio _asrDio() {
    final isMimo = _asrConfig.provider == AsrProvider.mimoV25;
    _asrDioInstance.options = BaseOptions(
      baseUrl: _asrConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: isMimo
          ? {'Content-Type': 'application/json', 'api-key': _asrConfig.apiKey}
          : {'Authorization': 'Bearer ${_asrConfig.apiKey}'},
    );
    return _asrDioInstance;
  }

  Dio _ocrDio() {
    final noAuth = _ocrConfig.provider == OcrProvider.paddleOcr ||
        _ocrConfig.provider == OcrProvider.mineru;
    _ocrDioInstance.options = BaseOptions(
      baseUrl: noAuth ? '' : _ocrConfig.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 60),
      headers: noAuth
          ? {'Content-Type': 'application/json'}
          : {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${_ocrConfig.apiKey}',
            },
    );
    return _ocrDioInstance;
  }

  static final RegExp _thinkTagPattern =
      RegExp(r'<think>[\s\S]*?<\/think>', caseSensitive: false);

  String _cleanContent(String raw) {
    // 过滤部分深度推理模型输出的 <think>...</think> 标签，保留纯 JSON
    return raw.replaceAll(_thinkTagPattern, '').trim();
  }

  String _parseContent(dynamic data) {
    final choices = data['choices'] as List?;
    if (choices == null || choices.isEmpty) {
      throw const FormatException('LLM 响应未包含 choices 字段');
    }
    final msg = choices[0]['message'];
    final content = msg?['content'] as String?;
    if (content == null) {
      throw const FormatException('LLM 响应 content 为空');
    }
    return _cleanContent(content);
  }

  /// 具有自动阶梯降级的对话生成：
  /// 优先使用严格 [jsonSchema]，若接口返回 400 不支持，则自动回落至 [json_object]，再回落至纯文本。
  /// 支持实时流式输出 [onChunk]（增量分片与当前累计文本）。
  Future<String> chatCompletion({
    required String systemPrompt,
    required String userPrompt,
    bool jsonMode = true,
    Map<String, dynamic>? jsonSchema,
    CancelToken? cancelToken,
    void Function(String chunk, String accumulated)? onChunk,
  }) async {
    final cacheKey = '${_llmConfig.baseUrl}::${_llmConfig.model}';
    final knownCap = _formatCapabilityCache[cacheKey];

    // 构建尝试等级列表
    final candidateModes = <String>[];
    if (jsonSchema != null && (knownCap == null || knownCap == 'json_schema')) {
      candidateModes.add('json_schema');
    }
    if (jsonMode && (knownCap == null || knownCap == 'json_schema' || knownCap == 'json_object')) {
      candidateModes.add('json_object');
    }
    candidateModes.add('none');

    DioException? last400Error;

    for (final mode in candidateModes) {
      try {
        final dio = _llmDio();
        final body = <String, dynamic>{
          'model': _llmConfig.model,
          if (_llmConfig.reasoningEffort.isNotEmpty)
            'reasoning_effort': _llmConfig.reasoningEffort,
          'messages': [
            {'role': 'system', 'content': systemPrompt},
            {'role': 'user', 'content': userPrompt},
          ],
        };

        if (mode == 'json_schema' && jsonSchema != null) {
          body['response_format'] = {
            'type': 'json_schema',
            'json_schema': jsonSchema,
          };
        } else if (mode == 'json_object') {
          body['response_format'] = {'type': 'json_object'};
        }

        // 如果调用方监听了 onChunk，且当前不是测试/假端点，优先使用流式 SSE
        if (onChunk != null) {
          body['stream'] = true;
          final response = await dio.post<ResponseBody>(
            '/chat/completions',
            data: body,
            cancelToken: cancelToken,
            options: Options(responseType: ResponseType.stream),
          );

          final stream = response.data?.stream;
          if (stream == null) {
            throw const FormatException('LLM 流式响应 stream 为空');
          }

          // 思考过程与最终正文分开缓冲：展示时合流，解析时只取正文。
          final reasoningBuffer = StringBuffer();
          final contentBuffer = StringBuffer();
          String carry = '';

          await for (final rawBytes in stream) {
            if (cancelToken?.isCancelled == true) {
              throw DioException(
                requestOptions: RequestOptions(path: '/chat/completions'),
                type: DioExceptionType.cancel,
              );
            }

            final textChunk = carry + utf8.decode(rawBytes, allowMalformed: true);
            final lines = textChunk.split('\n');
            carry = lines.removeLast(); // 未闭合的行暂存

            for (final line in lines) {
              final trimmed = line.trim();
              if (trimmed.isEmpty || trimmed == 'data: [DONE]') continue;
              if (trimmed.startsWith('data:')) {
                final jsonStr = trimmed.substring(5).trim();
                try {
                  final decoded = jsonDecode(jsonStr);
                  if (decoded is Map) {
                    final choices = decoded['choices'] as List?;
                    if (choices != null && choices.isNotEmpty) {
                      final delta = choices[0]['delta'] as Map?;
                      // 适配 DeepSeek / Qwen 等思考模型的 reasoning_content 字段与标准 content
                      final reasoningPiece =
                          delta?['reasoning_content'] as String?;
                      final contentPiece = delta?['content'] as String?;

                      final hasReasoning =
                          reasoningPiece != null && reasoningPiece.isNotEmpty;
                      final hasContent =
                          contentPiece != null && contentPiece.isNotEmpty;

                      if (hasReasoning) reasoningBuffer.write(reasoningPiece);
                      if (hasContent) contentBuffer.write(contentPiece);

                      if (hasReasoning || hasContent) {
                        // 展示：思考 + 正文合流，保持实时滚动
                        final displayText =
                            '${reasoningBuffer.toString()}${contentBuffer.toString()}';
                        onChunk(
                          hasContent ? contentPiece : reasoningPiece ?? '',
                          displayText,
                        );
                      }
                    }
                  }
                } catch (_) {
                  // 忽略个别畸形片段
                }
              }
            }
          }

          // 成功！记录该模型端点的支持模式
          _formatCapabilityCache[cacheKey] = mode;
          // 解析只取正文 content；若正文为空（少数非标服务把答案放在 reasoning 里）再兜底。
          final resultText = _cleanContent(
            contentBuffer.isNotEmpty
                ? contentBuffer.toString()
                : reasoningBuffer.toString(),
          );
          if (resultText.isNotEmpty) {
            return resultText;
          }
          // 如果流式没拿到内容（可能某些非标服务忽略了 stream），继续尝试非流式兜底
        }

        // 非流式（或流式未产出文本时的退回）
        body['stream'] = false;
        final response = await dio.post(
          '/chat/completions',
          data: body,
          cancelToken: cancelToken,
        );

        _formatCapabilityCache[cacheKey] = mode;
        final choices = response.data['choices'] as List?;
        if (choices == null || choices.isEmpty) {
          throw const FormatException('LLM 响应未包含 choices 字段');
        }
        final msg = choices[0]['message'];
        final content = msg?['content'] as String?;
        if (content == null) {
          throw const FormatException('LLM 响应 content 为空（可能被模型安全策略过滤）');
        }
        final cleaned = _cleanContent(content);
        onChunk?.call(cleaned, cleaned);
        return cleaned;
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        // 只有 400/422 且还有下一个降级模式时才继续尝试
        if ((status == 400 || status == 422) && mode != candidateModes.last) {
          last400Error = e;
          continue;
        }
        rethrow;
      }
    }

    if (last400Error != null) throw last400Error;
    throw const FormatException('LLM 请求未产生任何响应');
  }

  Future<String> transcribeAudio(String filePath) async {
    if (_asrConfig.provider == AsrProvider.deepseek) {
      return DeepSeekToolsService(dio: _rawDio).transcribe(
        baseUrl: _asrConfig.baseUrl,
        apiKey: _asrConfig.apiKey,
        filePath: filePath,
      );
    }
    if (_asrConfig.provider == AsrProvider.mimoV25) {
      return _transcribeMimo(filePath);
    }
    if (_asrConfig.provider == AsrProvider.zhipuAsr) {
      return _transcribeZhipu(filePath);
    }
    return _transcribeWhisper(filePath);
  }

  Future<String> _transcribeZhipu(String filePath) async {
    var base = _asrConfig.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final endpoint = base.endsWith('/audio/transcriptions')
        ? base
        : '$base/audio/transcriptions';

    final model = _asrConfig.model.trim().isNotEmpty
        ? _asrConfig.model.trim()
        : 'glm-asr-2512';

    final formData = FormData.fromMap({
      'model': model,
      'file': await MultipartFile.fromFile(filePath),
      'stream': false,
    });

    final resp = await _rawDio.post(
      endpoint,
      data: formData,
      options: Options(
        headers: {
          'Authorization': 'Bearer ${_asrConfig.apiKey}',
        },
        contentType: 'multipart/form-data',
      ),
    );

    final data = resp.data;
    if (data is Map && data['text'] != null) {
      return data['text'].toString().trim();
    }
    throw const FormatException('智谱 ASR 响应未包含 text 字段');
  }

  Future<String> _transcribeWhisper(String filePath) async {
    final dio = _asrDio();
    final formData = FormData.fromMap({
      'model': _asrConfig.model,
      'file': await MultipartFile.fromFile(filePath),
      'language': _asrConfig.language,
    });
    final response = await dio.post(
      '/audio/transcriptions',
      data: formData,
      options: Options(contentType: 'multipart/form-data'),
    );
    return response.data['text'] as String;
  }

  Future<String> _transcribeMimo(String filePath) async {
    final dio = _asrDio();
    final file = File(filePath);
    final bytes = await file.readAsBytes();
    final base64 = base64Encode(bytes);

    final ext = filePath.split('.').last.toLowerCase();
    final mimeType = ext == 'mp3' ? 'audio/mpeg' : 'audio/wav';

    final response = await dio.post(
      '/chat/completions',
      data: {
        'model': _asrConfig.model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {
                'type': 'input_audio',
                'input_audio': {
                  'data': 'data:$mimeType;base64,$base64',
                }
              }
            ]
          }
        ],
        'asr_options': {
          'language': _asrConfig.language,
        },
      },
    );
    return _parseContent(response.data);
  }

  /// 全局 OCR 发车速率控制器：保证相邻两个请求发往云端时，至少间隔 2000ms，免疫 1 QPS 限频
  DateTime _lastOcrDispatchTime = DateTime.fromMillisecondsSinceEpoch(0);

  Future<void> _paceOcrDispatch() async {
    final now = DateTime.now();
    final elapsed = now.difference(_lastOcrDispatchTime);
    const minInterval = Duration(milliseconds: 2000);
    if (elapsed < minInterval) {
      await Future.delayed(minInterval - elapsed);
    }
    _lastOcrDispatchTime = DateTime.now();
  }

  /// 统一的单页 OCR 批处理调度器：
  /// - 顺序节流发车（每张图至少间隔 2 秒）
  /// - 单页网络抖动自动指数退避重试 1 次
  /// - 严格按原始顺序重组各页结果
  /// - 若存在不可恢复的失败页面，标记并在顶部透传【部分页面识别失败】
  Future<String> _processMultiPagesWithPacing({
    required List<String> imagePaths,
    required String headerTitle,
    required Future<String> Function(String imagePath, int pageIndex)
        pageWorker,
  }) async {
    final total = imagePaths.length;
    final results = List<String?>.filled(total, null);
    final errors = <int, String>{};

    for (int i = 0; i < total; i++) {
      final path = imagePaths[i];

      // 节流发车：每次请求前保证距离上一次至少 2000ms
      await _paceOcrDispatch();

      // 单页执行与 1 次抖动重试
      String? pageText;
      String? lastError;

      for (int attempt = 0; attempt < 2; attempt++) {
        try {
          if (attempt > 0) {
            // 重试前稍作退避
            await Future.delayed(const Duration(milliseconds: 1500));
            await _paceOcrDispatch();
          }
          final text = await pageWorker(path, i);
          final trimmed = text.trim();
          if (trimmed.isNotEmpty) {
            pageText = trimmed;
            break;
          }
        } on DioException catch (e) {
          final code = e.response?.statusCode;
          if (code == 401 || code == 403) {
            // 鉴权失败不重试，直接抛出
            rethrow;
          }
          lastError = code != null ? 'HTTP $code' : (e.message ?? '网络异常');
        } catch (e) {
          lastError = e.toString();
        }
      }

      if (pageText != null) {
        results[i] = pageText;
      } else {
        errors[i] = lastError ?? '识别无结果';
      }
    }

    // 全部失败
    if (errors.length == total) {
      final firstErr = errors.values.first;
      throw Exception('所有页面均识别失败: $firstErr');
    }

    final buffer = StringBuffer();
    if (errors.isNotEmpty) {
      buffer.writeln('【部分页面识别失败】(成功 ${total - errors.length}/$total 页)');
      buffer.writeln();
    }
    buffer.writeln('结果来自 $headerTitle\n');

    for (int i = 0; i < total; i++) {
      final pageNo = i + 1;
      if (total > 1) {
        buffer.writeln('--- 第 $pageNo 页 ---');
      }
      if (results[i] != null) {
        buffer.writeln(results[i]);
      } else {
        buffer.writeln('【第 $pageNo 页识别失败: ${errors[i]}】');
      }
      if (total > 1) {
        buffer.writeln();
      }
    }

    return buffer.toString().trim();
  }

  Future<String> extractTextFromImages(List<String> imagePaths) async {
    // 后台异步优化：将过大的原图等比压缩至 2048px 高清范围，防超时与 413 超限
    final optimizedPaths = await OcrImageOptimizer.prepareForOcr(imagePaths);

    try {
      if (_ocrConfig.provider == OcrProvider.deepseek) {
        final config = _ocrConfig;
        return await _processMultiPagesWithPacing(
          imagePaths: optimizedPaths,
          headerTitle: 'DeepSeek OCR',
          pageWorker: (path, _) => DeepSeekToolsService(dio: _rawDio).recognize(
            baseUrl: config.baseUrl,
            apiKey: config.apiKey,
            filePath: path,
          ),
        );
      }
      if (_ocrConfig.provider == OcrProvider.paddleOcr) {
        return await _extractPaddleOcr(optimizedPaths);
      }
      if (_ocrConfig.provider == OcrProvider.zhipu) {
        return await _extractZhipuLayout(optimizedPaths);
      }
      if (_ocrConfig.provider == OcrProvider.modelbest) {
        return await _extractModelbestParse(optimizedPaths);
      }
      if (_ocrConfig.provider == OcrProvider.mineru) {
        return await _extractMineru(optimizedPaths);
      }
      if (_ocrConfig.provider == OcrProvider.appleVision) {
        return await _extractAppleVision(optimizedPaths);
      }
      if (_ocrConfig.provider == OcrProvider.paddleLocal) {
        return await _extractPaddleLocal(optimizedPaths);
      }
      return await _extractOpenAi(optimizedPaths);
    } finally {
      // 无论成功还是失败，立即清理本次产生的临时压缩图
      await OcrImageOptimizer.cleanPreparedFiles(optimizedPaths, imagePaths);
    }
  }

  /// 智谱 GLM-OCR 文档解析接口 (/paas/v4/layout_parsing)
  Future<String> _extractZhipuLayout(List<String> imagePaths) async {
    var base = _ocrConfig.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final endpoint = base.endsWith('/layout_parsing')
        ? base
        : '$base/layout_parsing';
    final model = _ocrConfig.model.trim().isNotEmpty
        ? _ocrConfig.model.trim()
        : 'glm-ocr';

    return _processMultiPagesWithPacing(
      imagePaths: imagePaths,
      headerTitle: '智谱 GLM-OCR',
      pageWorker: (path, pageIndex) async {
        final bytes = await File(path).readAsBytes();
        final base64Str = base64Encode(bytes);
        final resp = await _rawDio.post(
          endpoint,
          data: {
            'model': model,
            'file': 'data:image/jpeg;base64,$base64Str',
          },
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${_ocrConfig.apiKey}',
            },
          ),
        );

        final data = resp.data;
        if (data is Map) {
          final mdResults = data['md_results']?.toString().trim() ?? '';
          if (mdResults.isNotEmpty) {
            return mdResults;
          }
          final layoutDetails = data['layout_details'] as List?;
          if (layoutDetails != null) {
            final pageLines = <String>[];
            for (final pageList in layoutDetails) {
              if (pageList is List) {
                for (final item in pageList) {
                  if (item is Map) {
                    final content = item['content']?.toString().trim() ?? '';
                    if (content.isNotEmpty) {
                      pageLines.add(content);
                    }
                  }
                }
              }
            }
            if (pageLines.isNotEmpty) {
              return pageLines.join('\n');
            }
          }
        }
        throw Exception('响应中未解析出文本');
      },
    );
  }

  /// 面壁智能 ModelBest 文档解析接口 (/v1/document-parse)
  Future<String> _extractModelbestParse(List<String> imagePaths) async {
    var base = _ocrConfig.baseUrl.trim();
    while (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    String endpoint = '$base/document-parse';
    if (base.endsWith('/document-parse')) {
      endpoint = base;
    } else if (base.endsWith('/document-parse/jobs')) {
      endpoint = base.substring(0, base.length - '/jobs'.length);
    }
    final model = _ocrConfig.model.trim().isNotEmpty
        ? _ocrConfig.model.trim()
        : 'MiniCPM-OCR-1.0';

    return _processMultiPagesWithPacing(
      imagePaths: imagePaths,
      headerTitle: '面壁智能文档解析',
      pageWorker: (path, pageIndex) async {
        final bytes = await File(path).readAsBytes();
        final base64Str = base64Encode(bytes);
        final resp = await _rawDio.post(
          endpoint,
          data: {
            'model': model,
            'image': 'data:image/jpeg;base64,$base64Str',
            'upright': true,
            'recognize_seal': true,
          },
          options: Options(
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${_ocrConfig.apiKey}',
            },
          ),
        );

        final data = resp.data;
        if (data is Map) {
          String extracted = '';
          final choices = data['choices'] as List?;
          if (choices != null && choices.isNotEmpty) {
            final firstChoice = choices.first;
            if (firstChoice is Map && firstChoice['message'] is Map) {
              extracted =
                  firstChoice['message']['content']?.toString().trim() ?? '';
            }
          }
          if (extracted.isEmpty && data['markdown'] != null) {
            extracted = data['markdown'].toString().trim();
          }
          if (extracted.isEmpty && data['ocr'] is Map) {
            final blocks = (data['ocr'] as Map)['blocks'] as List?;
            if (blocks != null) {
              final blockLines = <String>[];
              for (final b in blocks) {
                if (b is Map) {
                  final c = b['content']?.toString().trim() ?? '';
                  if (c.isNotEmpty) blockLines.add(c);
                }
              }
              extracted = blockLines.join('\n');
            }
          }
          if (extracted.isNotEmpty) {
            return extracted;
          }
        }
        throw Exception('面壁接口未返回可提取文本');
      },
    );
  }

  Future<String> _extractPaddleLocal(List<String> imagePaths) async {
    if (!Platform.isAndroid) {
      throw Exception('当前平台不支持本地 PaddleOCR（仅 Android）');
    }
    final text = await PaddleLocalOcr.recognize(imagePaths);
    final body = text.trim();
    if (body.isEmpty) return '结果来自 PaddleOCR 本地\n\n';
    return '结果来自 PaddleOCR 本地\n\n$body';
  }

  Future<String> _extractAppleVision(List<String> imagePaths) async {
    try {
      final text = await AppleVisionOcr.recognize(imagePaths);
      final body = text.trim();
      if (body.isEmpty) return '结果来自 Apple Vision\n\n';
      return '结果来自 Apple Vision\n\n$body';
    } on MissingPluginException {
      throw Exception('当前平台不支持 Apple Vision（仅 iOS / macOS）');
    }
  }

  Future<String> _extractPaddleOcr(List<String> imagePaths) async {
    final jobUrl = _ocrConfig.baseUrl;

    return _processMultiPagesWithPacing(
      imagePaths: imagePaths,
      headerTitle: 'PaddleOCR-VL',
      pageWorker: (path, pageIndex) async {
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(path, filename: 'page.jpg'),
          'model': _ocrConfig.model,
          'optionalPayload':
              '{"useDocOrientationClassify":false,"useDocUnwarping":false,"useChartRecognition":false}',
        });

        final submitResp = await _rawDio.post(
          jobUrl,
          data: formData,
          options: Options(headers: {
            'Authorization': 'bearer ${_ocrConfig.apiKey}',
          }),
        );

        final jobId = submitResp.data['data']['jobId'] as String;

        // Poll for result (up to 40s)
        String? jsonlUrl;
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(seconds: 2));
          final pollResp = await _rawDio.get(
            '$jobUrl/$jobId',
            options: Options(headers: {
              'Authorization': 'bearer ${_ocrConfig.apiKey}',
            }),
          );
          final state = pollResp.data['data']['state'] as String;
          if (state == 'done') {
            jsonlUrl = pollResp.data['data']['resultUrl']['jsonUrl'] as String;
            break;
          }
          if (state == 'failed') {
            final reason = pollResp.data['data']['error'] ?? 'PaddleOCR任务失败';
            throw Exception(reason.toString());
          }
        }

        if (jsonlUrl == null) {
          throw Exception('PaddleOCR任务轮询超时');
        }

        final jsonlResp = await _rawDio.get(jsonlUrl);
        final lines = (jsonlResp.data as String)
            .split('\n')
            .where((l) => l.trim().isNotEmpty);
        final pageLines = <String>[];
        for (final line in lines) {
          final data = jsonDecode(line) as Map<String, dynamic>;
          final results = data['result']?['layoutParsingResults'] as List?;
          if (results == null || results.isEmpty) continue;
          final parsed =
              results[0]['prunedResult']?['parsing_res_list'] as List?;
          if (parsed == null) continue;
          for (final block in parsed) {
            final content = block['block_content'] as String?;
            if (content != null && content.isNotEmpty) {
              pageLines.add(content);
            }
          }
        }
        if (pageLines.isNotEmpty) {
          return pageLines.join('\n');
        }
        throw Exception('PaddleOCR 未解析出文本');
      },
    );
  }

  Future<String> _extractMineru(List<String> imagePaths) async {
    final dio = _ocrDio();
    const base = 'https://mineru.net/api/v1/agent';

    return _processMultiPagesWithPacing(
      imagePaths: imagePaths,
      headerTitle: 'MinerU',
      pageWorker: (path, pageIndex) async {
        final fileName = path.split('/').last;

        // 1. Get signed upload URL
        final createResp = await dio.post(
          '$base/parse/file',
          data: {
            'file_name': fileName,
            'language': 'ch',
            'enable_table': true,
            'is_ocr': false,
            'enable_formula': true,
          },
        );
        if (createResp.statusCode == 429) {
          throw Exception('MinerU IP 限频 (429)');
        }
        final taskId = createResp.data['data']['task_id'] as String;
        final fileUrl = createResp.data['data']['file_url'] as String;

        // 2. PUT upload file
        final bytes = await File(path).readAsBytes();
        final client = HttpClient();
        final req = await client.putUrl(Uri.parse(fileUrl));
        req.headers.set(HttpHeaders.contentLengthHeader, bytes.length);
        req.add(bytes);
        final uploadResp = await req.close();
        final statusCode = uploadResp.statusCode;
        await uploadResp.drain<void>();
        client.close();
        if (statusCode != 200 && statusCode != 201) {
          throw Exception('MinerU 上传失败 HTTP $statusCode');
        }

        // 3. Poll for result (up to 60s)
        String? mdUrl;
        for (int i = 0; i < 20; i++) {
          await Future.delayed(const Duration(seconds: 3));
          final pollResp = await dio.get('$base/parse/$taskId');
          final state = pollResp.data['data']['state'] as String?;
          if (state == 'done') {
            mdUrl = pollResp.data['data']['markdown_url'] as String?;
            break;
          }
          if (state == 'failed') {
            final err = pollResp.data['data']['err_msg'];
            throw Exception('MinerU 解析失败: $err');
          }
        }

        if (mdUrl == null) {
          throw Exception('MinerU 任务超时');
        }

        final mdResp = await dio.get(mdUrl);
        return mdResp.data.toString();
      },
    );
  }

  Future<String> _extractOpenAi(List<String> imagePaths) async {
    final dio = _ocrDio();
    final content = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text': '请提取并整理以下图片中的所有文字内容，按照从上到下、从左到右的顺序。如果有多页，请合并输出。只输出文字内容，不要添加任何解释。',
      }
    ];
    for (final path in imagePaths) {
      final file = File(path);
      final bytes = await file.readAsBytes();
      final base64 = base64Encode(bytes);
      content.add({
        'type': 'image_url',
        'image_url': {'url': 'data:image/jpeg;base64,$base64'},
      });
    }
    final response = await dio.post(
      '/chat/completions',
      data: {
        'model': _ocrConfig.model,
        'messages': [
          {'role': 'user', 'content': content}
        ],
        'max_tokens': 4096,
      },
    );
    return _parseContent(response.data);
  }

  Future<bool> testLlmConnection() async {
    try {
      final dio = _llmDio();
      final resp = await dio.get('/models');
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<bool> testAsrConnection() async {
    try {
      final dio = _asrDio();
      var base = _asrConfig.baseUrl.trim();
      while (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
      String modelsEndpoint = '$base/models';
      if (_asrConfig.provider == AsrProvider.deepseek) {
        modelsEndpoint = DeepSeekToolsService.modelsEndpoint(base);
      }
      if (base.endsWith('/audio/transcriptions')) {
        modelsEndpoint =
            '${base.substring(0, base.length - '/audio/transcriptions'.length)}/models';
      }

      final resp = await _rawDio.get(
        modelsEndpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer ${_asrConfig.apiKey}',
            if (_asrConfig.provider == AsrProvider.mimoV25)
              'api-key': _asrConfig.apiKey,
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (resp.statusCode == 200) return true;
      if (resp.statusCode == 401 || resp.statusCode == 403) return false;

      // 若 /models 不开放，对 mimo 回落测试
      if (_asrConfig.provider == AsrProvider.mimoV25) {
        final chatResp = await dio.post(
          '/chat/completions',
          data: {
            'model': 'mimo-v2.5',
            'messages': [
              {'role': 'user', 'content': 'hi'}
            ],
            'max_tokens': 1,
          },
        );
        return chatResp.statusCode == 200;
      }
      return resp.statusCode == 200 || resp.statusCode == 404;
    } catch (_) {
      return false;
    }
  }

  Future<bool> testOcrConnection() async {
    try {
      if (_ocrConfig.provider == OcrProvider.appleVision) {
        return AppleVisionOcr.isAvailable();
      }
      if (_ocrConfig.provider == OcrProvider.paddleLocal) {
        return PaddleLocalOcr.isAvailable();
      }
      if (_ocrConfig.provider == OcrProvider.paddleOcr) {
        // PaddleOCR job URL is POST-only; verify auth via a dummy request
        final resp = await _rawDio.post(
          _ocrConfig.baseUrl,
          options: Options(headers: {
            'Authorization': 'bearer ${_ocrConfig.apiKey}',
          }),
        );
        // 405 (Method Not Allowed) or 400 (Bad Request) = endpoint exists + auth OK
        return resp.statusCode != 401 && resp.statusCode != 403;
      }
      if (_ocrConfig.provider == OcrProvider.mineru) {
        // MinerU agent API is no-auth; verify endpoint reachable via empty POST
        final resp = await _rawDio.post(
          'https://mineru.net/api/v1/agent/parse/file',
          options: Options(headers: {'Content-Type': 'application/json'}),
        );
        return resp.statusCode != 429;
      }
      var base = _ocrConfig.baseUrl.trim();
      while (base.endsWith('/')) {
        base = base.substring(0, base.length - 1);
      }
      String modelsUrl = '$base/models';
      if (_ocrConfig.provider == OcrProvider.deepseek) {
        modelsUrl = DeepSeekToolsService.modelsEndpoint(base);
      }
      if (base.endsWith('/layout_parsing')) {
        modelsUrl =
            '${base.substring(0, base.length - '/layout_parsing'.length)}/models';
      } else if (base.endsWith('/document-parse/jobs')) {
        modelsUrl =
            '${base.substring(0, base.length - '/document-parse/jobs'.length)}/models';
      } else if (base.endsWith('/document-parse')) {
        modelsUrl =
            '${base.substring(0, base.length - '/document-parse'.length)}/models';
      }
      final resp = await _rawDio.get(
        modelsUrl,
        options: Options(
          headers: {'Authorization': 'Bearer ${_ocrConfig.apiKey}'},
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    }
  }
}
