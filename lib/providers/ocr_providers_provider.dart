import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/services/api/api_config.dart';
import '../data/services/api/ocr_provider_service.dart';
import '../domain/models/ocr_provider.dart';
import 'providers.dart';
import 'storefront_compliance_provider.dart';

class OcrProvidersState {
  final String activeProviderId;
  final List<OcrProviderConfig> providers;
  final bool isLoading;

  const OcrProvidersState({
    this.activeProviderId = 'modelbest',
    this.providers = const [],
    this.isLoading = true,
  });

  OcrProviderConfig? get activeProvider {
    try {
      return providers.firstWhere((p) => p.id == activeProviderId);
    } catch (_) {
      return providers.isNotEmpty ? providers.first : null;
    }
  }

  String get activeModel => activeProvider?.selectedModel ?? 'gpt-4o';

  OcrProvidersState copyWith({
    String? activeProviderId,
    List<OcrProviderConfig>? providers,
    bool? isLoading,
  }) {
    return OcrProvidersState(
      activeProviderId: activeProviderId ?? this.activeProviderId,
      providers: providers ?? this.providers,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class OcrProvidersNotifier extends StateNotifier<OcrProvidersState> {
  final Ref _ref;
  final FlutterSecureStorage _storage;
  final OcrProviderService _service;
  final bool restrictChinaCompliance;

  static const _storageKeyProviders = 'ocr_providers_matrix_v1';
  static const _storageKeyActiveId = 'ocr_active_provider_id_v1';

  late final Future<void> ready;

  OcrProvidersNotifier(
    this._ref,
    this._storage,
    this._service, {
    this.restrictChinaCompliance = false,
  }) : super(const OcrProvidersState()) {
    ready = _load();
  }

  List<OcrProviderConfig> _filterPlatformPresets(List<OcrProviderConfig> list) {
    final platformFiltered = list.where((p) {
      if (p.protocol == OcrProtocol.appleVision) {
        return !kIsWeb && (Platform.isIOS || Platform.isMacOS);
      }
      if (p.protocol == OcrProtocol.paddleLocal) {
        return !kIsWeb && Platform.isAndroid;
      }
      return true;
    }).toList();

    if (!restrictChinaCompliance) return platformFiltered;

    // 中国区合规：移除境外与走通用 LLM chat/completions 端点的 OCR（如 OpenAI Compatible），
    // 保留本机 Apple Vision 与非 LLM 的国内解析/识别接口（含 DeepSeek/面壁/智谱/百度/MinerU 备用）。
    return platformFiltered
        .where(
          (p) => p.protocol != OcrProtocol.openaiVision && p.id != 'openai',
        )
        .toList();
  }

  String _defaultLocalProviderId(List<OcrProviderConfig> loaded) {
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      if (loaded.any((p) => p.id == 'appleVision')) return 'appleVision';
    }
    if (!kIsWeb && Platform.isAndroid) {
      if (loaded.any((p) => p.id == 'paddleLocal')) return 'paddleLocal';
    }
    if (loaded.any((p) => p.id == 'mineru')) return 'mineru';
    return loaded.isNotEmpty ? loaded.first.id : 'modelbest';
  }

  Future<void> _load() async {
    String? activeId;
    List<OcrProviderConfig> loaded = [];

    try {
      final values = await Future.wait([
        _storage.read(key: _storageKeyActiveId),
        _storage.read(key: _storageKeyProviders),
      ]);
      activeId = values[0];
      final rawJson = values[1];

      if (rawJson != null && rawJson.trim().isNotEmpty) {
        try {
          final list = jsonDecode(rawJson) as List;
          final savedList = list
              .map((item) =>
                  OcrProviderConfig.fromJson(item as Map<String, dynamic>))
              .toList();

          // 将内置预设中新增的 provider 与用户已有的合并（保证新版追加的预设不丢失）
          final savedMap = {for (final p in savedList) p.id: p};
          for (final preset in OcrProviderPresets.builtIn) {
            if (!savedMap.containsKey(preset.id)) {
              savedList.add(preset);
            }
          }
          loaded = _filterPlatformPresets(savedList);
        } catch (_) {}
      }
    } catch (_) {
      // 存储读取异常时回退内置预设，保证不会卡在加载态
    } finally {
      if (loaded.isEmpty) {
        loaded = _filterPlatformPresets(List.from(OcrProviderPresets.builtIn));
      }

      String targetActiveId = activeId ?? '';
      if (targetActiveId.isEmpty ||
          !loaded.any((p) => p.id == targetActiveId)) {
        if (loaded.any((p) => p.requiresApiKey && p.isConfigured)) {
          targetActiveId =
              loaded.firstWhere((p) => p.requiresApiKey && p.isConfigured).id;
        } else {
          targetActiveId = _defaultLocalProviderId(loaded);
        }
      }

      if (mounted) {
        state = OcrProvidersState(
          activeProviderId: targetActiveId,
          providers: loaded,
          isLoading: false,
        );
        // 同步激活生效到全局 OcrConfig
        _syncActiveToGlobal();
      }
    }
  }

  OcrProvider _mapProtocol(OcrProtocol protocol) {
    switch (protocol) {
      case OcrProtocol.deepseek:
        return OcrProvider.deepseek;
      case OcrProtocol.openaiVision:
        return OcrProvider.openai;
      case OcrProtocol.paddleOcr:
        return OcrProvider.paddleOcr;
      case OcrProtocol.zhipuLayout:
        return OcrProvider.zhipu;
      case OcrProtocol.modelbestParse:
        return OcrProvider.modelbest;
      case OcrProtocol.mineru:
        return OcrProvider.mineru;
      case OcrProtocol.appleVision:
        return OcrProvider.appleVision;
      case OcrProtocol.paddleLocal:
        return OcrProvider.paddleLocal;
    }
  }

  Future<void> _persist() async {
    final jsonStr =
        jsonEncode(state.providers.map((p) => p.toJson()).toList());
    await _storage.write(key: _storageKeyProviders, value: jsonStr);
    await _storage.write(
        key: _storageKeyActiveId, value: state.activeProviderId);
    _syncActiveToGlobal();
  }

  void _syncActiveToGlobal() {
    final active = state.activeProvider;
    if (active == null) return;
    final config = OcrConfig(
      provider: _mapProtocol(active.protocol),
      baseUrl: active.baseUrl.trim(),
      apiKey: active.apiKey.trim(),
      model: active.selectedModel.trim(),
    );
    _ref.read(ocrConfigProvider.notifier).save(config);
  }

  /// 切换当前生效的活跃服务商
  Future<void> setActiveProvider(String providerId, {String? model}) async {
    await ready;
    final updatedList = List<OcrProviderConfig>.from(state.providers);
    if (model != null) {
      final idx = updatedList.indexWhere((p) => p.id == providerId);
      if (idx >= 0) {
        updatedList[idx] = updatedList[idx].copyWith(selectedModel: model);
      }
    }

    state = state.copyWith(
      activeProviderId: providerId,
      providers: updatedList,
    );
    await _persist();
  }

  /// 切换当前服务商的模型
  Future<void> setActiveModel(String providerId, String model) async {
    await ready;
    final updatedList = List<OcrProviderConfig>.from(state.providers);
    final idx = updatedList.indexWhere((p) => p.id == providerId);
    if (idx >= 0) {
      updatedList[idx] = updatedList[idx].copyWith(selectedModel: model.trim());
      state = state.copyWith(providers: updatedList);
      await _persist();
    }
  }

  /// 更新单个服务商配置（独立保存其 Key、URL、模型等，互不串号）
  Future<void> updateProvider(OcrProviderConfig provider) async {
    await ready;
    final updatedList = List<OcrProviderConfig>.from(state.providers);
    final idx = updatedList.indexWhere((p) => p.id == provider.id);
    if (idx >= 0) {
      updatedList[idx] = provider;
    } else {
      updatedList.add(provider);
    }
    state = state.copyWith(providers: updatedList);
    await _persist();
  }

  /// 自动从云端拉取模型列表并持久化缓存到该服务商
  Future<List<String>> fetchModelsForProvider(String providerId) async {
    final provider = state.providers.firstWhere((p) => p.id == providerId);
    final models = await _service.fetchModels(provider);

    final updated = provider.copyWith(
      customModels: models,
      selectedModel: models.contains(provider.selectedModel)
          ? provider.selectedModel
          : (models.isNotEmpty ? models.first : provider.selectedModel),
    );

    await updateProvider(updated);
    return models;
  }

  /// 刷新该服务商余额或连通性测速
  Future<String> fetchStatusOrPingForProvider(String providerId) async {
    final provider = state.providers.firstWhere((p) => p.id == providerId);
    final statusInfo = await _service.fetchStatusOrPing(provider);

    final updated = provider.copyWith(
      statusInfo: statusInfo,
      statusUpdatedAt: DateTime.now(),
    );

    await updateProvider(updated);
    return statusInfo;
  }
}

final ocrProviderServiceProvider = Provider<OcrProviderService>((ref) {
  return OcrProviderService();
});

final ocrProvidersProvider =
    StateNotifierProvider<OcrProvidersNotifier, OcrProvidersState>((ref) {
  return OcrProvidersNotifier(
    ref,
    ref.read(secureStorageProvider),
    ref.read(ocrProviderServiceProvider),
    restrictChinaCompliance: ref.watch(isChinaAiRestrictedProvider),
  );
});
