import 'dart:async';
import 'package:dio/dio.dart';

import '../../../domain/models/llm_provider.dart';

class LlmProviderService {
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

  /// 自动从服务商端点拉取模型列表 (GET /models)
  Future<List<String>> fetchModels(LlmProviderConfig provider) async {
    final baseUrl = _normalizeBaseUrl(provider.baseUrl);
    final apiKey = provider.apiKey.trim();

    if (baseUrl.isEmpty) {
      throw Exception('接口地址不能为空');
    }
    if (apiKey.isEmpty) {
      throw Exception('请先填写该服务商的 API Key');
    }

    final endpoint = '$baseUrl/models';
    final isMimo = provider.id == 'mimo' || baseUrl.contains('xiaomimimo');
    try {
      final response = await _dio.get(
        endpoint,
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
            if (isMimo) 'api-key': apiKey,
          },
        ),
      );

      final data = response.data;
      final rawList = data is Map ? (data['data'] as List?) : (data as List?);
      if (rawList == null || rawList.isEmpty) {
        throw Exception('服务端返回的模型列表为空');
      }

      final models = <String>[];
      for (final item in rawList) {
        if (item is Map && item['id'] != null) {
          models.add(item['id'].toString().trim());
        } else if (item is String) {
          models.add(item.trim());
        }
      }

      // 排序与过滤：将与对话相关的模型排在前面，排除明显的向量/音频模型
      models.sort((a, b) {
        final aLower = a.toLowerCase();
        final bLower = b.toLowerCase();
        final aIsEmbedding = aLower.contains('embed') || aLower.contains('whisper') || aLower.contains('tts');
        final bIsEmbedding = bLower.contains('embed') || bLower.contains('whisper') || bLower.contains('tts');
        if (aIsEmbedding && !bIsEmbedding) return 1;
        if (!aIsEmbedding && bIsEmbedding) return -1;
        return a.compareTo(b);
      });

      return models;
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        throw Exception('API Key 无效或未授权 (401)');
      } else if (e.response?.statusCode == 404) {
        throw Exception('该服务商未开放 /models 端点 (404)');
      }
      throw Exception('拉取模型失败: ${e.message ?? e.toString()}');
    } catch (e) {
      throw Exception('拉取模型失败: $e');
    }
  }

  /// 查询服务商账户余额（如 DeepSeek、SiliconFlow）或进行连通性测速 (Ping)
  Future<String> fetchBalanceOrPing(LlmProviderConfig provider) async {
    final baseUrl = _normalizeBaseUrl(provider.baseUrl);
    final apiKey = provider.apiKey.trim();

    if (apiKey.isEmpty) {
      throw Exception('未填写 API Key');
    }

    final isMimo = provider.id == 'mimo' || baseUrl.contains('xiaomimimo');
    final stopwatch = Stopwatch()..start();

    // 1. DeepSeek 官方余额端点
    if (provider.id == 'deepseek' || baseUrl.contains('api.deepseek.com')) {
      try {
        final resp = await _dio.get(
          'https://api.deepseek.com/user/balance',
          options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
        );
        stopwatch.stop();
        if (resp.statusCode == 200 && resp.data is Map) {
          final isAvailable = resp.data['is_available'] as bool? ?? false;
          final balanceInfos = resp.data['balance_infos'] as List?;
          if (balanceInfos != null && balanceInfos.isNotEmpty) {
            final first = balanceInfos.first as Map;
            final currency = first['currency']?.toString() ?? 'CNY';
            final symbol = currency == 'CNY' ? '￥' : '\$';
            final total = first['total_balance']?.toString() ?? '0.00';
            return '$symbol$total (${isAvailable ? "可用" : "欠费"}) · ${stopwatch.elapsedMilliseconds}ms';
          }
        }
      } catch (_) {
        // 出错回落到连通性测试
      }
    }

    // 2. 硅基流动 SiliconFlow 官方余额端点
    if (provider.id == 'siliconflow' || baseUrl.contains('siliconflow')) {
      try {
        final resp = await _dio.get(
          'https://api.siliconflow.cn/v1/user/info',
          options: Options(headers: {'Authorization': 'Bearer $apiKey'}),
        );
        stopwatch.stop();
        if (resp.statusCode == 200 && resp.data is Map) {
          final data = resp.data['data'];
          if (data is Map && data['totalBalance'] != null) {
            return '￥${data['totalBalance']} · ${stopwatch.elapsedMilliseconds}ms';
          }
        }
      } catch (_) {
        // 出错回落到连通性测试
      }
    }

    // 3. 通用端点：通过 GET /models 测试连通性与 RTT 延迟
    try {
      final resp = await _dio.get(
        '$baseUrl/models',
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
      } else if (resp.statusCode == 401) {
        return 'Key无效 (401)';
      } else if (resp.statusCode == 404) {
        return '端点未找到 (404)';
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
