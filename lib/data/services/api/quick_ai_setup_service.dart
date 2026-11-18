import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/asr_provider.dart';
import '../../../domain/models/document_parser_provider.dart';
import '../../../domain/models/llm_provider.dart';
import '../../../domain/models/ocr_provider.dart';
import '../../../providers/asr_providers_provider.dart';
import '../../../providers/document_parser_provider.dart';
import '../../../providers/llm_providers_provider.dart';
import '../../../providers/ocr_providers_provider.dart';
import '../../../providers/providers.dart';
import '../../../providers/tutorial_provider.dart';

final apiKeyGuideDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
    ),
  );
  ref.onDispose(() => dio.close());
  return dio;
});

enum ApiKeyGuideProvider {
  deepseek,
  zhipu;

  String get label => this == deepseek ? 'DeepSeek' : '智谱';
}

final quickAiSetupServiceProvider = Provider<QuickAiSetupService>((ref) {
  return QuickAiSetupService(ref);
});

/// 复用的快速 AI 密钥验证与写入服务：
/// - DeepSeek / 智谱：一次验证并写入文本、识图、文件解析、语音识别四项配置
/// - 其他大语言模型：仅验证并配置 LLM，不动本地 OCR / ASR
class QuickAiSetupService {
  final Ref _ref;

  QuickAiSetupService(this._ref);

  String _normalizeBaseUrl(String url) {
    var trimmed = url.trim();
    while (trimmed.endsWith('/')) {
      trimmed = trimmed.substring(0, trimmed.length - 1);
    }
    return trimmed;
  }

  String _extractErrorMessage(
    Response<dynamic> resp, {
    required String providerName,
    bool isDeepSeek = false,
    bool fromGuide = false,
  }) {
    String detail = '验证未通过 (HTTP ${resp.statusCode})';
    final data = resp.data;
    if (data is Map && data['error'] is Map) {
      final err = data['error'] as Map;
      final msg = err['message']?.toString() ?? '';
      final code = err['code']?.toString() ?? '';
      if (resp.statusCode == 401) {
        detail = 'API Key 无效或未复制完整 (401)';
      } else if (code == '1113' ||
          msg.contains('余额') ||
          msg.contains('欠费')) {
        if (isDeepSeek) {
          detail = '余额不足，请到 DeepSeek 开放平台确认余额并充值。';
        } else if (fromGuide) {
          detail =
              '账号余额或免费额度不足，请先确认是否已完成第 10 步实名认证或第 11 步充值（$msg）';
        } else {
          detail = '账号余额或免费额度不足，请确认实名认证与账户余额（$msg）';
        }
      } else if (resp.statusCode == 402) {
        detail = '余额不足，请到$providerName开放平台确认余额并充值。';
      } else if (msg.isNotEmpty) {
        detail = '$msg${code.isNotEmpty ? " ($code)" : ""}';
      }
    } else if (resp.statusCode == 401) {
      detail = 'API Key 无效或未复制完整 (401)';
    }
    return detail;
  }

  /// 验证 DeepSeek 或 智谱 Key，成功后一次写入并激活 LLM / OCR / ASR / 文件解析。
  /// 返回 `null` 表示成功，返回非空字符串表示中文错误提示。
  Future<String?> verifyAndConfigureAllInOne({
    required ApiKeyGuideProvider provider,
    required String apiKey,
    bool fromGuide = false,
    bool ensureSampleAndResetTutorial = false,
  }) async {
    final trimmedKey = apiKey.trim();
    final providerName = provider.label;
    if (trimmedKey.isEmpty) {
      return '请先粘贴或输入$providerName API Key';
    }

    final isDeepSeek = provider == ApiKeyGuideProvider.deepseek;
    final providerId = provider.name;
    final llmPreset =
        LlmProviderPresets.builtIn.firstWhere((p) => p.id == providerId);
    final ocrPreset =
        OcrProviderPresets.builtIn.firstWhere((p) => p.id == providerId);
    final asrPreset =
        AsrProviderPresets.builtIn.firstWhere((p) => p.id == providerId);
    final docPreset = DocumentParserProviderConfig.presets
        .firstWhere((p) => p.id == providerId);

    try {
      final dio = _ref.read(apiKeyGuideDioProvider);
      final resp = await dio.post(
        '${llmPreset.baseUrl}/chat/completions',
        data: {
          'model': llmPreset.selectedModel,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
          'max_tokens': isDeepSeek ? 16 : 1,
          if (isDeepSeek) ...{
            'thinking': {'type': 'enabled'},
            'reasoning_effort': 'low',
          },
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $trimmedKey',
            'Content-Type': 'application/json',
          },
          validateStatus: (_) => true,
        ),
      );

      if (resp.statusCode != 200) {
        return _extractErrorMessage(
          resp,
          providerName: providerName,
          isDeepSeek: isDeepSeek,
          fromGuide: fromGuide,
        );
      }

      // 写入并激活所选服务商的文本、识图、语音与文件解析服务。
      final llmNotifier = _ref.read(llmProvidersProvider.notifier);
      await llmNotifier.ready;
      final existingLlm = _ref
          .read(llmProvidersProvider)
          .providers
          .where((p) => p.id == providerId)
          .firstOrNull;
      final baseLlm = existingLlm ?? llmPreset;
      await llmNotifier.updateProvider(
        baseLlm.copyWith(
          baseUrl: llmPreset.baseUrl,
          apiKey: trimmedKey,
          selectedModel: llmPreset.selectedModel,
          isEnabled: true,
          reasoningEfforts: isDeepSeek
              ? {...baseLlm.reasoningEfforts, llmPreset.selectedModel: 'low'}
              : baseLlm.reasoningEfforts,
        ),
      );
      await llmNotifier.setActiveProvider(
        providerId,
        model: llmPreset.selectedModel,
      );

      final ocrNotifier = _ref.read(ocrProvidersProvider.notifier);
      await ocrNotifier.ready;
      final existingOcr = _ref
          .read(ocrProvidersProvider)
          .providers
          .where((p) => p.id == providerId)
          .firstOrNull;
      final baseOcr = existingOcr ?? ocrPreset;
      await ocrNotifier.updateProvider(
        baseOcr.copyWith(
          baseUrl: ocrPreset.baseUrl,
          apiKey: trimmedKey,
          selectedModel: ocrPreset.selectedModel,
          isEnabled: true,
        ),
      );
      await ocrNotifier.setActiveProvider(
        providerId,
        model: ocrPreset.selectedModel,
      );

      final asrNotifier = _ref.read(asrProvidersProvider.notifier);
      await asrNotifier.ready;
      final existingAsr = _ref
          .read(asrProvidersProvider)
          .providers
          .where((p) => p.id == providerId)
          .firstOrNull;
      final baseAsr = existingAsr ?? asrPreset;
      await asrNotifier.updateProvider(
        baseAsr.copyWith(
          baseUrl: asrPreset.baseUrl,
          apiKey: trimmedKey,
          selectedModel: asrPreset.selectedModel,
          isEnabled: true,
        ),
      );
      await asrNotifier.setActiveProvider(
        providerId,
        model: asrPreset.selectedModel,
      );

      final docNotifier = _ref.read(documentParserProvider.notifier);
      await docNotifier.ready;
      final existingDoc = _ref
          .read(documentParserProvider)
          .valueOrNull
          ?.providers
          .where((p) => p.id == providerId)
          .firstOrNull;
      final baseDoc = existingDoc ?? docPreset;
      await docNotifier.saveProvider(
        baseDoc.copyWith(
          baseUrl: docPreset.baseUrl,
          apiKey: trimmedKey,
          toolType: isDeepSeek ? baseDoc.toolType : 'prime-sync',
          isEnabled: true,
        ),
        select: true,
      );

      if (ensureSampleAndResetTutorial) {
        await _ref.read(sampleDataServiceProvider).ensureSampleData();
        _ref.invalidate(patientsProvider);
        await _ref
            .read(tutorialProvider.notifier)
            .resetTutorial(TutorialType.basicFlow, step: 4);
      }

      return null;
    } on DioException catch (e) {
      return '网络请求失败，请检查网络连接 (${e.message ?? e.type.name})';
    } catch (e) {
      return '验证出错: $e';
    }
  }

  /// 验证其他服务商（或自定义 OpenAI 兼容端点），仅写入并激活 LLM。
  /// 返回 `null` 表示成功，返回非空字符串表示中文错误提示。
  Future<String?> verifyAndConfigureLlmOnly({
    required LlmProviderConfig baseProvider,
    required String baseUrl,
    required String apiKey,
    required String model,
  }) async {
    final normalizedUrl = _normalizeBaseUrl(baseUrl);
    final trimmedKey = apiKey.trim();
    final trimmedModel = model.trim();

    if (normalizedUrl.isEmpty) {
      return '请先输入接口地址 (Base URL)';
    }
    if (trimmedKey.isEmpty) {
      return '请先输入 ${baseProvider.name} 的 API Key';
    }
    if (trimmedModel.isEmpty) {
      return '请先填写模型名称';
    }

    final isMimo =
        baseProvider.id == 'mimo' || normalizedUrl.contains('xiaomimimo');

    try {
      final dio = _ref.read(apiKeyGuideDioProvider);
      final resp = await dio.post(
        '$normalizedUrl/chat/completions',
        data: {
          'model': trimmedModel,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
          'max_tokens': 1,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $trimmedKey',
            'Content-Type': 'application/json',
            if (isMimo) 'api-key': trimmedKey,
          },
          validateStatus: (_) => true,
        ),
      );

      if (resp.statusCode != 200) {
        return _extractErrorMessage(
          resp,
          providerName: baseProvider.name,
        );
      }

      final llmNotifier = _ref.read(llmProvidersProvider.notifier);
      await llmNotifier.ready;
      final existingLlm = _ref
          .read(llmProvidersProvider)
          .providers
          .where((p) => p.id == baseProvider.id)
          .firstOrNull;
      final current = existingLlm ?? baseProvider;
      await llmNotifier.updateProvider(
        current.copyWith(
          baseUrl: normalizedUrl,
          apiKey: trimmedKey,
          selectedModel: trimmedModel,
          isEnabled: true,
        ),
      );
      await llmNotifier.setActiveProvider(
        baseProvider.id,
        model: trimmedModel,
      );

      return null;
    } on DioException catch (e) {
      return '网络请求失败，请检查网络连接 (${e.message ?? e.type.name})';
    } catch (e) {
      return '验证出错: $e';
    }
  }
}
