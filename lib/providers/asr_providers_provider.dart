import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../data/services/api/api_config.dart';
import '../data/services/api/asr_provider_service.dart';
import '../domain/models/asr_provider.dart';
import 'providers.dart';

class AsrProvidersState {
  final String activeProviderId;
  final List<AsrProviderConfig> providers;
  final bool isLoading;

  const AsrProvidersState({
    this.activeProviderId = 'zhipu',
    this.providers = const [],
    this.isLoading = true,
  });

  AsrProviderConfig? get activeProvider {
    try {
      return providers.firstWhere((p) => p.id == activeProviderId);
    } catch (_) {
      return providers.isNotEmpty ? providers.first : null;
    }
  }

  String get activeModel => activeProvider?.selectedModel ?? 'glm-asr-2512';

  AsrProvidersState copyWith({
    String? activeProviderId,
    List<AsrProviderConfig>? providers,
    bool? isLoading,
  }) {
    return AsrProvidersState(
      activeProviderId: activeProviderId ?? this.activeProviderId,
      providers: providers ?? this.providers,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class AsrProvidersNotifier extends StateNotifier<AsrProvidersState> {
  final Ref _ref;
  final FlutterSecureStorage _storage;
  final AsrProviderService _service;

  static const _storageKeyProviders = 'asr_providers_matrix_v1';
  static const _storageKeyActiveId = 'asr_active_provider_id_v1';

  AsrProvidersNotifier(this._ref, this._storage, this._service)
      : super(const AsrProvidersState()) {
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      _storage.read(key: _storageKeyActiveId),
      _storage.read(key: _storageKeyProviders),
    ]);
    final activeId = values[0];
    final rawJson = values[1];

    List<AsrProviderConfig> loaded = [];

    if (rawJson != null && rawJson.trim().isNotEmpty) {
      try {
        final list = jsonDecode(rawJson) as List;
        final savedList = list
            .map((item) =>
                AsrProviderConfig.fromJson(item as Map<String, dynamic>))
            .toList();

        final savedMap = {for (final p in savedList) p.id: p};
        for (final preset in AsrProviderPresets.builtIn) {
          if (!savedMap.containsKey(preset.id)) {
            savedList.add(preset);
          }
        }
        loaded = savedList;
      } catch (_) {}
    }

    // 若无已存列表，初始化内置预设并从旧版平滑迁移数据
    if (loaded.isEmpty) {
      loaded = List.from(AsrProviderPresets.builtIn);

      final oldProvider = await _storage.read(key: 'asr_provider');
      final oldUrl = await _storage.read(key: 'asr_base_url');
      final oldKey = await _storage.read(key: 'asr_api_key');
      final oldModel = await _storage.read(key: 'asr_model');
      final oldLang = await _storage.read(key: 'asr_language');

      if (oldProvider != null && oldProvider.trim().isNotEmpty) {
        final targetId = _matchProviderId(oldProvider.trim(), oldUrl ?? '');
        final idx = loaded.indexWhere((p) => p.id == targetId);
        if (idx >= 0) {
          loaded[idx] = loaded[idx].copyWith(
            baseUrl: (oldUrl != null && oldUrl.trim().isNotEmpty)
                ? oldUrl.trim()
                : loaded[idx].baseUrl,
            apiKey: oldKey?.trim() ?? loaded[idx].apiKey,
            selectedModel: (oldModel != null && oldModel.trim().isNotEmpty)
                ? oldModel.trim()
                : loaded[idx].selectedModel,
            language: (oldLang != null && oldLang.trim().isNotEmpty)
                ? oldLang.trim()
                : loaded[idx].language,
          );
        }
      }
    }

    String targetActiveId = activeId ?? '';
    if (targetActiveId.isEmpty ||
        !loaded.any((p) => p.id == targetActiveId)) {
      final oldProv = await _storage.read(key: 'asr_provider');
      final oldUrl = await _storage.read(key: 'asr_base_url');
      final matchedOld = oldProv != null && oldProv.isNotEmpty
          ? _matchProviderId(oldProv, oldUrl ?? '')
          : '';
      if (matchedOld.isNotEmpty && loaded.any((p) => p.id == matchedOld)) {
        targetActiveId = matchedOld;
      } else if (loaded.any((p) => p.isConfigured)) {
        targetActiveId = loaded.firstWhere((p) => p.isConfigured).id;
      } else {
        targetActiveId = loaded.any((p) => p.id == 'zhipu')
            ? 'zhipu' : loaded.isNotEmpty ? loaded.first.id : 'zhipu';
      }
    }

    state = AsrProvidersState(
      activeProviderId: targetActiveId,
      providers: loaded,
      isLoading: false,
    );

    _syncActiveToGlobal();
  }

  String _matchProviderId(String oldProviderName, String url) {
    final lowerUrl = url.toLowerCase();
    if (oldProviderName == 'deepseek' || lowerUrl.contains('api.deepseek.com')) {
      return 'deepseek';
    }
    if (oldProviderName == 'zhipuAsr' || lowerUrl.contains('bigmodel.cn')) {
      return 'zhipu';
    }
    if (oldProviderName == 'mimoV25' || lowerUrl.contains('xiaomimimo')) {
      return 'mimoV25';
    }
    return 'openaiWhisper';
  }

  AsrProvider _mapProtocolToLegacyEnum(AsrProtocol protocol) {
    switch (protocol) {
      case AsrProtocol.deepseek:
        return AsrProvider.deepseek;
      case AsrProtocol.zhipuAsr:
        return AsrProvider.zhipuAsr;
      case AsrProtocol.mimoV25:
        return AsrProvider.mimoV25;
      case AsrProtocol.openaiWhisper:
        return AsrProvider.openaiWhisper;
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
    final config = AsrConfig(
      provider: _mapProtocolToLegacyEnum(active.protocol),
      baseUrl: active.baseUrl.trim(),
      apiKey: active.apiKey.trim(),
      model: active.selectedModel.trim(),
      language: active.language.trim(),
    );
    _ref.read(asrConfigProvider.notifier).save(config);
  }

  /// 切换当前生效的活跃服务商
  Future<void> setActiveProvider(String providerId, {String? model}) async {
    final updatedList = List<AsrProviderConfig>.from(state.providers);
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
    final updatedList = List<AsrProviderConfig>.from(state.providers);
    final idx = updatedList.indexWhere((p) => p.id == providerId);
    if (idx >= 0) {
      updatedList[idx] = updatedList[idx].copyWith(selectedModel: model.trim());
      state = state.copyWith(providers: updatedList);
      await _persist();
    }
  }

  /// 更新单个服务商配置（独立保存其 Key、URL、模型、语言等，互不串号）
  Future<void> updateProvider(AsrProviderConfig provider) async {
    final updatedList = List<AsrProviderConfig>.from(state.providers);
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

  /// 刷新该服务商连通性测速
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

final asrProviderServiceProvider = Provider<AsrProviderService>((ref) {
  return AsrProviderService();
});

final asrProvidersProvider =
    StateNotifierProvider<AsrProvidersNotifier, AsrProvidersState>((ref) {
  return AsrProvidersNotifier(
    ref,
    ref.read(secureStorageProvider),
    ref.read(asrProviderServiceProvider),
  );
});
