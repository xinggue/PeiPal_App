import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/services/api/api_config.dart';
import '../data/services/api/llm_provider_service.dart';
import '../domain/models/llm_provider.dart';
import 'providers.dart';

class LlmProvidersState {
  final String activeProviderId;
  final List<LlmProviderConfig> providers;
  final bool isLoading;

  const LlmProvidersState({
    this.activeProviderId = 'deepseek',
    this.providers = const [],
    this.isLoading = true,
  });

  LlmProviderConfig? get activeProvider {
    try {
      return providers.firstWhere((p) => p.id == activeProviderId);
    } catch (_) {
      return providers.isNotEmpty ? providers.first : null;
    }
  }

  String get activeModel => activeProvider?.selectedModel ?? 'gpt-4o';

  LlmProvidersState copyWith({
    String? activeProviderId,
    List<LlmProviderConfig>? providers,
    bool? isLoading,
  }) {
    return LlmProvidersState(
      activeProviderId: activeProviderId ?? this.activeProviderId,
      providers: providers ?? this.providers,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class LlmProvidersNotifier extends StateNotifier<LlmProvidersState> {
  final Ref _ref;
  final FlutterSecureStorage _storage;
  final LlmProviderService _service;

  static const _storageKeyProviders = 'llm_providers_matrix_v1';
  static const _storageKeyActiveId = 'llm_active_provider_id_v1';

  LlmProvidersNotifier(this._ref, this._storage, this._service)
      : super(const LlmProvidersState()) {
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      _storage.read(key: _storageKeyActiveId),
      _storage.read(key: _storageKeyProviders),
    ]);
    final activeId = values[0];
    final rawJson = values[1];

    List<LlmProviderConfig> loaded = [];

    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final list = jsonDecode(rawJson) as List;
        final savedList = list
            .map((item) => LlmProviderConfig.fromJson(item as Map<String, dynamic>))
            .toList();

        // 将内置预设中新增的 provider 与用户已有的合并（保证新版追加的预设不丢失）
        final savedMap = {for (final p in savedList) p.id: p};
        for (final preset in LlmProviderPresets.builtIn) {
          if (!savedMap.containsKey(preset.id)) {
            savedList.add(preset);
          }
        }
        loaded = savedList;
      } catch (_) {}
    }

    // 若无已存列表，初始化内置预设并从旧版平滑迁移数据
    if (loaded.isEmpty) {
      loaded = List.from(LlmProviderPresets.builtIn);

      // 读取旧版 3 个 key 迁移至预设
      final oldUrl = await _storage.read(key: 'llm_base_url');
      final oldKey = await _storage.read(key: 'llm_api_key');
      final oldModel = await _storage.read(key: 'llm_model');
      final oldEffort = await _storage.read(key: 'llm_reasoning_effort');

      if (oldKey != null && oldKey.trim().isNotEmpty) {
        final targetId = _matchProviderIdByUrl(oldUrl ?? '');
        final idx = loaded.indexWhere((p) => p.id == targetId);
        if (idx >= 0) {
          loaded[idx] = loaded[idx].copyWith(
            baseUrl: oldUrl ?? loaded[idx].baseUrl,
            apiKey: oldKey,
            selectedModel: oldModel ?? loaded[idx].selectedModel,
            reasoningEfforts: {
              if (oldModel != null && oldEffort != null)
                oldModel.trim().toLowerCase(): oldEffort,
            },
          );
        } else {
          // 放入自定义端点
          final customIdx = loaded.indexWhere((p) => p.id == 'custom');
          if (customIdx >= 0) {
            loaded[customIdx] = loaded[customIdx].copyWith(
              baseUrl: oldUrl ?? loaded[customIdx].baseUrl,
              apiKey: oldKey,
              selectedModel: oldModel ?? loaded[customIdx].selectedModel,
            );
          }
        }
      }
    }

    final targetActiveId = activeId ??
        (loaded.any((p) => p.isConfigured)
            ? loaded.firstWhere((p) => p.isConfigured).id
            : 'deepseek');

    state = LlmProvidersState(
      activeProviderId: targetActiveId,
      providers: loaded,
      isLoading: false,
    );

    // 同步激活生效到全局 LlmConfig
    _syncActiveToGlobal();
  }

  String _matchProviderIdByUrl(String url) {
    final lower = url.toLowerCase();
    if (lower.contains('deepseek')) return 'deepseek';
    if (lower.contains('siliconflow')) return 'siliconflow';
    if (lower.contains('xiaomimimo') || lower.contains('mimo')) return 'mimo';
    if (lower.contains('bigmodel') || lower.contains('zhipu')) return 'zhipu';
    if (lower.contains('moonshot') || lower.contains('kimi')) return 'moonshot';
    if (lower.contains('aliyuncs') || lower.contains('dashscope')) return 'dashscope';
    if (lower.contains('minimax')) return 'minimax';
    if (lower.contains('api.openai.com')) return 'openai';
    return 'custom';
  }

  Future<void> _persist() async {
    final jsonStr = jsonEncode(state.providers.map((p) => p.toJson()).toList());
    await _storage.write(key: _storageKeyProviders, value: jsonStr);
    await _storage.write(key: _storageKeyActiveId, value: state.activeProviderId);
    _syncActiveToGlobal();
  }

  void _syncActiveToGlobal() {
    final active = state.activeProvider;
    if (active == null) return;
    final config = LlmConfig(
      baseUrl: active.baseUrl.trim(),
      apiKey: active.apiKey.trim(),
      model: active.selectedModel.trim(),
      reasoningEffort: active.reasoningEffort,
    );
    _ref.read(llmConfigProvider.notifier).save(config);
  }

  /// 切换当前生效的活跃服务商
  Future<void> setActiveProvider(String providerId, {String? model}) async {
    final updatedList = List<LlmProviderConfig>.from(state.providers);
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
    final updatedList = List<LlmProviderConfig>.from(state.providers);
    final idx = updatedList.indexWhere((p) => p.id == providerId);
    if (idx >= 0) {
      updatedList[idx] = updatedList[idx].copyWith(selectedModel: model.trim());
      state = state.copyWith(providers: updatedList);
      await _persist();
    }
  }

  /// 更新单个服务商配置（Key、URL、状态等）
  Future<void> updateProvider(LlmProviderConfig provider) async {
    final updatedList = List<LlmProviderConfig>.from(state.providers);
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
      // 若当前选中的模型不在新列表中，自动保持或设为首选
      selectedModel: models.contains(provider.selectedModel)
          ? provider.selectedModel
          : (models.isNotEmpty ? models.first : provider.selectedModel),
    );

    await updateProvider(updated);
    return models;
  }

  /// 刷新该服务商余额或连通性测速
  Future<String> fetchBalanceOrPingForProvider(String providerId) async {
    final provider = state.providers.firstWhere((p) => p.id == providerId);
    final balanceInfo = await _service.fetchBalanceOrPing(provider);

    final updated = provider.copyWith(
      balance: balanceInfo,
      balanceUpdatedAt: DateTime.now(),
    );

    await updateProvider(updated);
    return balanceInfo;
  }
}

final llmProviderServiceProvider = Provider<LlmProviderService>((ref) {
  return LlmProviderService();
});

final llmProvidersProvider =
    StateNotifierProvider<LlmProvidersNotifier, LlmProvidersState>((ref) {
  return LlmProvidersNotifier(
    ref,
    ref.read(secureStorageProvider),
    ref.read(llmProviderServiceProvider),
  );
});
