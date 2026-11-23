import 'dart:async';
import 'package:dio/dio.dart';

import '../../../domain/models/ocr_provider.dart';
import 'deepseek_tools_service.dart';
import '../media/apple_vision_ocr.dart';
import '../media/paddle_local_ocr.dart';

class OcrProbeResult {
  final bool ok;
  final String message;

  const OcrProbeResult({required this.ok, required this.message});
}

class OcrProviderService {
  final Dio _dio;

  OcrProviderService([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
            ));

  /// 规范化 baseUrl，去除尾部斜杠
  static String normalizeBaseUrl(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  /// 计算 MinerU 代理基址（默认官方地址）
  static String mineruAgentBaseUrl(String rawBaseUrl) {
    var base = normalizeBaseUrl(rawBaseUrl);
    if (base.isEmpty) return 'https://mineru.net/api/v1/agent';
    if (base.endsWith('/parse/file')) {
      base = base.substring(0, base.length - '/parse/file'.length);
    }
    return base.isEmpty ? 'https://mineru.net/api/v1/agent' : base;
  }

  /// 计算 MinerU 文件解析探测端点
  static String mineruParseFileUrl(String rawBaseUrl) {
    return '${mineruAgentBaseUrl(rawBaseUrl)}/parse/file';
  }

  /// 探测百度飞桨星河 PaddleOCR 异步任务端点（以 multipart 缺省 file 请求触发鉴权，避免无 body 导致 500）
  static Future<OcrProbeResult> probePaddleOcr({
    required Dio dio,
    required String baseUrl,
    required String apiKey,
    String model = 'PaddleOCR-VL-1.6',
  }) async {
    final normalizedUrl = normalizeBaseUrl(baseUrl);
    final trimmedKey = apiKey.trim();
    if (normalizedUrl.isEmpty) {
      return const OcrProbeResult(ok: false, message: '接口地址不能为空');
    }
    if (trimmedKey.isEmpty) {
      return const OcrProbeResult(ok: false, message: '未填写 API Key');
    }

    final stopwatch = Stopwatch()..start();
    final formData = FormData.fromMap({
      'model': model.trim().isNotEmpty ? model.trim() : 'PaddleOCR-VL-1.6',
    });
    final resp = await dio.post(
      normalizedUrl,
      data: formData,
      options: Options(
        headers: {'Authorization': 'bearer $trimmedKey'},
        validateStatus: (status) => status != null && status < 600,
      ),
    );
    stopwatch.stop();
    final code = resp.statusCode ?? 0;
    if (code == 401 || code == 403) {
      return OcrProbeResult(ok: false, message: 'Token 无效 ($code)');
    }
    if (code == 404) {
      return const OcrProbeResult(ok: false, message: '接口地址无效 (404)');
    }
    if (code >= 500 || code < 200) {
      return OcrProbeResult(ok: false, message: '服务端异常 ($code)');
    }
    return OcrProbeResult(
      ok: true,
      message: '连通正常 (${stopwatch.elapsedMilliseconds}ms)',
    );
  }

  /// 探测 MinerU 无鉴权云端解析端点（发送空 JSON 触发参数校验 400，确认端点可达且未限频）
  static Future<OcrProbeResult> probeMineru({
    required Dio dio,
    required String baseUrl,
  }) async {
    final stopwatch = Stopwatch()..start();
    final resp = await dio.post(
      mineruParseFileUrl(baseUrl),
      data: const <String, dynamic>{},
      options: Options(
        headers: {'Content-Type': 'application/json'},
        validateStatus: (status) => status != null && status < 600,
      ),
    );
    stopwatch.stop();
    final code = resp.statusCode ?? 0;
    if (code == 429) {
      return const OcrProbeResult(ok: false, message: '公网 IP 触发限频 (429)');
    }
    if (code == 401 || code == 403 || code == 404 || code >= 500 || code < 200) {
      return OcrProbeResult(ok: false, message: '接口异常 ($code)');
    }
    return OcrProbeResult(
      ok: true,
      message: '连通正常 (${stopwatch.elapsedMilliseconds}ms)',
    );
  }

  String _normalizeBaseUrl(String url) => normalizeBaseUrl(url);

  /// 从服务商端点获取可用的 OCR / 视觉模型列表
  Future<List<String>> fetchModels(OcrProviderConfig provider) async {
    if (!provider.requiresModel) return const [];
    if (provider.protocol == OcrProtocol.appleVision) {
      return const ['apple-vision'];
    }
    if (provider.protocol == OcrProtocol.paddleLocal) {
      return const ['ppocr-v5-mobile'];
    }
    if (provider.protocol == OcrProtocol.mineru) {
      return const ['agent'];
    }
    if (provider.protocol == OcrProtocol.paddleOcr) {
      // 百度飞桨星河 OCR jobs 接口不开放标准 /models 端点，返回官方支持的模型列表并校验鉴权
      final apiKey = provider.apiKey.trim();
      if (apiKey.isEmpty) {
        throw Exception('请先填写该服务商的 Token / API Key');
      }
      final baseUrl = _normalizeBaseUrl(provider.baseUrl);
      if (baseUrl.isEmpty) {
        throw Exception('接口地址不能为空');
      }
      final probe = await probePaddleOcr(
        dio: _dio,
        baseUrl: baseUrl,
        apiKey: apiKey,
        model: provider.selectedModel,
      );
      if (!probe.ok) {
        throw Exception(probe.message);
      }
      return const ['PaddleOCR-VL-1.6', 'PaddleOCR-VL-0.9B'];
    }

    final baseUrl = _normalizeBaseUrl(provider.baseUrl);
    final apiKey = provider.apiKey.trim();

    if (baseUrl.isEmpty) {
      throw Exception('接口地址不能为空');
    }
    if (apiKey.isEmpty) {
      throw Exception('请先填写该服务商的 API Key');
    }

    // 处理用户可能直接填入完整路径（如 /paas/v4/layout_parsing 或 /v1/document-parse）的情况
    String modelsEndpoint = '$baseUrl/models';
    if (provider.protocol == OcrProtocol.deepseek) {
      modelsEndpoint = DeepSeekToolsService.modelsEndpoint(baseUrl);
    }
    if (baseUrl.endsWith('/layout_parsing')) {
      modelsEndpoint =
          '${baseUrl.substring(0, baseUrl.length - '/layout_parsing'.length)}/models';
    } else if (baseUrl.endsWith('/document-parse/jobs')) {
      modelsEndpoint =
          '${baseUrl.substring(0, baseUrl.length - '/document-parse/jobs'.length)}/models';
    } else if (baseUrl.endsWith('/document-parse')) {
      modelsEndpoint =
          '${baseUrl.substring(0, baseUrl.length - '/document-parse'.length)}/models';
    }

    try {
      final response = await _dio.get(
        modelsEndpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
        ),
      );

      final data = response.data;
      final rawList = data is Map ? (data['data'] as List?) : (data as List?);
      final models = <String>[];

      if (rawList != null) {
        for (final item in rawList) {
          if (item is Map && item['id'] != null) {
            final idStr = item['id'].toString().trim();
            // 如果面壁智能返回 capabilities，优先筛选支持 document_parse 或 input_image 的模型
            if (provider.protocol == OcrProtocol.modelbestParse &&
                item['capabilities'] is Map) {
              final caps = item['capabilities'] as Map;
              if (caps['document_parse'] == true ||
                  idStr.toLowerCase().contains('ocr')) {
                models.add(idStr);
              }
            } else {
              models.add(idStr);
            }
          } else if (item is String) {
            models.add(item.trim());
          }
        }
      }

      // 针对专门协议补充保底官方模型（如智谱 /paas/v4/models 可能只返回对话模型而不包含 glm-ocr）
      if (provider.protocol == OcrProtocol.zhipuLayout) {
        if (!models.contains('glm-ocr')) {
          models.insert(0, 'glm-ocr');
        }
      } else if (provider.protocol == OcrProtocol.modelbestParse) {
        if (!models.contains('MiniCPM-OCR-1.0')) {
          models.insert(0, 'MiniCPM-OCR-1.0');
        }
      }

      if (models.isEmpty) {
        throw Exception('服务端返回的模型列表为空');
      }

      // 排序：将包含 ocr / vl / vision / parse / 4o / minicpm / pixtral / gemini 的多模态与识别模型排在最前
      int scoreModel(String m) {
        final lower = m.toLowerCase();
        if (lower.contains('ocr') || lower.contains('parse')) return 0;
        if (lower.contains('vl') ||
            lower.contains('vision') ||
            lower.contains('minicpm') ||
            lower.contains('4o') ||
            lower.contains('gemini') ||
            lower.contains('glm-4v') ||
            lower.contains('pixtral')) {
          return 1;
        }
        if (lower.contains('embed') ||
            lower.contains('whisper') ||
            lower.contains('tts') ||
            lower.contains('rerank') ||
            lower.contains('speech')) {
          return 3;
        }
        return 2;
      }

      models.sort((a, b) {
        final sa = scoreModel(a);
        final sb = scoreModel(b);
        if (sa != sb) return sa.compareTo(sb);
        return a.compareTo(b);
      });

      return models;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw Exception('API Key 无效或未授权 (${e.response?.statusCode})');
      } else if (e.response?.statusCode == 404) {
        // 若部分专门接口未开放 /models，但协议已有内置模型，则返回预设模型
        if (provider.protocol == OcrProtocol.zhipuLayout) {
          return const ['glm-ocr'];
        }
        if (provider.protocol == OcrProtocol.modelbestParse) {
          return const ['MiniCPM-OCR-1.0'];
        }
        throw Exception('该服务商未开放 /models 端点 (404)，请直接手动输入模型名称');
      }
      throw Exception('拉取模型失败: ${e.message ?? e.toString()}');
    } catch (e) {
      throw Exception('拉取模型失败: $e');
    }
  }

  /// 查询服务商账户状态/余额或进行连通性测速 (Ping)
  Future<String> fetchStatusOrPing(OcrProviderConfig provider) async {
    final stopwatch = Stopwatch()..start();

    if (provider.protocol == OcrProtocol.appleVision) {
      final ok = await AppleVisionOcr.isAvailable();
      stopwatch.stop();
      return ok ? '本机离线引擎已就绪' : '当前设备不支持 Apple Vision';
    }

    if (provider.protocol == OcrProtocol.paddleLocal) {
      final ok = await PaddleLocalOcr.isAvailable();
      stopwatch.stop();
      return ok ? '本机离线引擎已就绪' : '当前设备不支持本地 PaddleOCR';
    }

    if (provider.protocol == OcrProtocol.mineru) {
      try {
        final probe = await probeMineru(dio: _dio, baseUrl: provider.baseUrl);
        return probe.message;
      } catch (e) {
        return '网络异常: $e';
      }
    }

    final baseUrl = _normalizeBaseUrl(provider.baseUrl);
    final apiKey = provider.apiKey.trim();

    if (apiKey.isEmpty) {
      throw Exception('未填写 API Key');
    }

    // 1. 百度飞桨星河 PaddleOCR
    if (provider.protocol == OcrProtocol.paddleOcr) {
      try {
        final probe = await probePaddleOcr(
          dio: _dio,
          baseUrl: baseUrl,
          apiKey: apiKey,
          model: provider.selectedModel,
        );
        return probe.message;
      } catch (e) {
        return '连接失败: $e';
      }
    }

    // 2. 通用端点：通过 GET /models 测试连通性与 RTT 延迟
    String modelsEndpoint = '$baseUrl/models';
    if (provider.protocol == OcrProtocol.deepseek) {
      modelsEndpoint = DeepSeekToolsService.modelsEndpoint(baseUrl);
    }
    if (baseUrl.endsWith('/layout_parsing')) {
      modelsEndpoint =
          '${baseUrl.substring(0, baseUrl.length - '/layout_parsing'.length)}/models';
    } else if (baseUrl.endsWith('/document-parse/jobs')) {
      modelsEndpoint =
          '${baseUrl.substring(0, baseUrl.length - '/document-parse/jobs'.length)}/models';
    } else if (baseUrl.endsWith('/document-parse')) {
      modelsEndpoint =
          '${baseUrl.substring(0, baseUrl.length - '/document-parse'.length)}/models';
    }

    try {
      final resp = await _dio.get(
        modelsEndpoint,
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
      } else {
        return '响应 HTTP ${resp.statusCode} (${stopwatch.elapsedMilliseconds}ms)';
      }
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
}
