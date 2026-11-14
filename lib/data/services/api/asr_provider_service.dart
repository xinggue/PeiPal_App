import 'dart:async';
import 'package:dio/dio.dart';

import '../../../domain/models/asr_provider.dart';
import 'deepseek_tools_service.dart';

class AsrProviderService {
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 20),
  ));

  /// 规范化 baseUrl，去除尾部斜杠
  String _normalizeBaseUrl(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  /// 从服务商端点获取可用的语音识别模型列表
  Future<List<String>> fetchModels(AsrProviderConfig provider) async {
    if (!provider.requiresModel) return const [];
    if (provider.protocol == AsrProtocol.mimoV25) {
      return const ['mimo-v2.5-asr'];
    }

    final baseUrl = _normalizeBaseUrl(provider.baseUrl);
    final apiKey = provider.apiKey.trim();

    if (baseUrl.isEmpty) {
      throw Exception('接口地址不能为空');
    }
    if (apiKey.isEmpty) {
      throw Exception('请先填写该服务商的 API Key');
    }

    String modelsEndpoint = '$baseUrl/models';
    if (provider.protocol == AsrProtocol.deepseek) {
      modelsEndpoint = DeepSeekToolsService.modelsEndpoint(baseUrl);
    }
    if (baseUrl.endsWith('/audio/transcriptions')) {
      modelsEndpoint =
          '${baseUrl.substring(0, baseUrl.length - '/audio/transcriptions'.length)}/models';
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
            final lower = idStr.toLowerCase();
            // 筛选语音或 ASR 相关模型
            if (lower.contains('asr') ||
                lower.contains('whisper') ||
                lower.contains('audio') ||
                lower.contains('speech')) {
              models.add(idStr);
            }
          } else if (item is String) {
            models.add(item.trim());
          }
        }
      }

      // 针对智谱或官方补充保底模型
      if (provider.protocol == AsrProtocol.zhipuAsr) {
        if (!models.contains('glm-asr-2512')) {
          models.insert(0, 'glm-asr-2512');
        }
      } else if (provider.protocol == AsrProtocol.openaiWhisper) {
        if (!models.contains('whisper-1')) {
          models.insert(0, 'whisper-1');
        }
      }

      if (models.isEmpty) {
        // 如果端点没过滤出特定前缀，返回全部模型
        if (rawList != null) {
          for (final item in rawList) {
            if (item is Map && item['id'] != null) {
              models.add(item['id'].toString().trim());
            }
          }
        }
      }

      if (models.isEmpty) {
        throw Exception('服务端返回的模型列表为空');
      }

      return models;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401 || e.response?.statusCode == 403) {
        throw Exception('API Key 无效或未授权 (${e.response?.statusCode})');
      } else if (e.response?.statusCode == 404) {
        if (provider.protocol == AsrProtocol.zhipuAsr) {
          return const ['glm-asr-2512'];
        }
        if (provider.protocol == AsrProtocol.openaiWhisper) {
          return const ['whisper-1'];
        }
        throw Exception('该服务商未开放 /models 端点 (404)，请直接手动输入模型名称');
      }
      throw Exception('拉取模型失败: ${e.message ?? e.toString()}');
    } catch (e) {
      throw Exception('拉取模型失败: $e');
    }
  }

  /// 查询服务商账户连通性测速 (Ping)
  Future<String> fetchStatusOrPing(AsrProviderConfig provider) async {
    final stopwatch = Stopwatch()..start();
    final baseUrl = _normalizeBaseUrl(provider.baseUrl);
    final apiKey = provider.apiKey.trim();

    if (apiKey.isEmpty) {
      throw Exception('未填写 API Key');
    }

    final isMimo = provider.protocol == AsrProtocol.mimoV25;

    // 通用端点：通过 GET /models 测试连通性与 RTT 延迟
    String modelsEndpoint = '$baseUrl/models';
    if (provider.protocol == AsrProtocol.deepseek) {
      modelsEndpoint = DeepSeekToolsService.modelsEndpoint(baseUrl);
    }
    if (baseUrl.endsWith('/audio/transcriptions')) {
      modelsEndpoint =
          '${baseUrl.substring(0, baseUrl.length - '/audio/transcriptions'.length)}/models';
    }

    try {
      final resp = await _dio.get(
        modelsEndpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            if (isMimo) 'api-key': apiKey,
          },
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
