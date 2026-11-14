import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../data/database/database_helper.dart';
import '../data/repositories/patient_repository.dart';
import '../data/repositories/message_repository.dart';
import '../data/repositories/template_repository.dart';
import '../data/repositories/content_template_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/catalog_repository.dart';
import '../data/repositories/catalog_tags_repository.dart';
import '../data/repositories/generation_log_repository.dart';
import '../data/repositories/favorite_diagnosis_repository.dart';
import '../data/services/catalog/catalog_source.dart';
import '../data/services/icd_service.dart';
import '../data/services/api/api_service.dart';
import '../data/services/api/api_config.dart';
import '../data/services/api/extractor_config.dart';
import '../data/services/api/llm_prompt_config.dart';
import '../data/services/ble/active_timing_controller.dart';
import '../data/services/ble/ble_service.dart';
import '../data/services/ble/timing_params.dart';
import '../data/services/ble/typing_done_prefs.dart';
import '../data/services/task/task_center.dart';
import '../data/services/processing_service.dart';
import '../data/services/generation_engine.dart';
import '../data/services/content_template_extractor.dart';
import '../data/services/sample_data_service.dart';
import '../domain/models/patient.dart';
import '../domain/models/message.dart';
import '../domain/models/template.dart';
import '../domain/models/typing_action_block.dart';
import '../domain/models/content_template.dart';
import '../domain/models/catalog_definition.dart';
import '../domain/models/catalog_entry.dart';
import '../domain/models/favorite_diagnosis.dart';

final secureStorageProvider = Provider<FlutterSecureStorage>((ref) {
  return const FlutterSecureStorage(
    mOptions: MacOsOptions(
      accessibility: KeychainAccessibility.first_unlock,
      useDataProtectionKeyChain: false,
    ),
  );
});

final databaseProvider = Provider<DatabaseHelper>((ref) {
  return DatabaseHelper();
});

// ---- Repositories ----

final patientRepositoryProvider = Provider<PatientRepository>((ref) {
  return PatientRepository();
});

final messageRepositoryProvider = Provider<MessageRepository>((ref) {
  return MessageRepository();
});

final templateRepositoryProvider = Provider<TemplateRepository>((ref) {
  return TemplateRepository();
});

final contentTemplateRepositoryProvider =
    Provider<ContentTemplateRepository>((ref) {
  return ContentTemplateRepository();
});

final catalogEntryRepositoryProvider = Provider<CatalogEntryRepository>((ref) {
  return CatalogEntryRepository();
});

final generationLogRepositoryProvider =
    Provider<GenerationLogRepository>((ref) {
  return GenerationLogRepository();
});

final favoriteDiagnosisRepositoryProvider =
    Provider<FavoriteDiagnosisRepository>((ref) {
  return FavoriteDiagnosisRepository();
});

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  return CatalogRepository();
});

final catalogTagsRepositoryProvider = Provider<CatalogTagsRepository>((ref) {
  return CatalogTagsRepository();
});

final catalogsProvider = FutureProvider<List<CatalogDefinition>>((ref) async {
  final repo = ref.watch(catalogRepositoryProvider);
  return repo.getAll();
});

final catalogSourceProvider =
    FutureProvider.family<CatalogSource, String>((ref, catalogId) async {
  final definitions = await ref.watch(catalogsProvider.future);
  final definition = definitions
      .where((c) => c.id == catalogId)
      .firstOrNull;
  if (definition != null &&
      definition.sourceKind == CatalogSourceKind.bundledSqlite &&
      definition.sourceAsset.contains('icd_knowledge.db')) {
    return IcdCatalogSource(ref.read(icdServiceProvider));
  }
  // Other bundled sources can register their own adapter here later.
  return ManagedCatalogSource(
    ref.read(catalogEntryRepositoryProvider),
    catalogId,
  );
});

const kDefaultDiagnosisTags = <String>[];
const kDefaultProcedureTags = <String>[];

List<String> defaultTagsForCatalog(String catalogType) => switch (catalogType) {
      'procedure' => kDefaultProcedureTags,
      _ => kDefaultDiagnosisTags,
    };

/// Legacy settings key. New code stores tags in the `catalog_tags` table.
String catalogTagsSettingsKey(String catalogType) =>
    catalogType == 'diagnosis' ? 'diagnosis_tags' : '${catalogType}_tags';

final catalogTagsProviderFamily = StateNotifierProvider.family<
    CatalogTagsNotifier, List<String>, String>((ref, catalogType) {
  return CatalogTagsNotifier(
    ref.read(catalogTagsRepositoryProvider),
    ref.read(catalogEntryRepositoryProvider),
    catalogType,
  );
});

final diagnosisTagsProvider = catalogTagsProviderFamily('diagnosis');

class CatalogTagsNotifier extends StateNotifier<List<String>> {
  final CatalogTagsRepository _tagsRepo;
  final CatalogEntryRepository _entryRepo;
  final String catalogType;

  CatalogTagsNotifier(this._tagsRepo, this._entryRepo, this.catalogType)
      : super(defaultTagsForCatalog(catalogType)) {
    _load();
  }

  Future<void> _load() async {
    try {
      state = await _tagsRepo.getAll(catalogType);
    } catch (_) {
      state = defaultTagsForCatalog(catalogType);
    }
  }

  Future<void> addTag(String tag) async {
    final t = tag.trim();
    if (t.isEmpty || state.contains(t)) return;
    await _tagsRepo.addTag(catalogType, t);
    state = await _tagsRepo.getAll(catalogType);
  }

  Future<void> renameTag(String oldTag, String newTag) async {
    final oldT = oldTag.trim();
    final newT = newTag.trim();
    if (oldT.isEmpty || newT.isEmpty || oldT == newT) return;

    await _tagsRepo.renameTag(catalogType, oldT, newT);
    state = await _tagsRepo.getAll(catalogType);

    final allEntries = await _entryRepo.getAll(catalogType: catalogType);
    for (final entry in allEntries) {
      if (entry.tags.contains(oldT)) {
        final newTags =
            entry.tags.map((t) => t == oldT ? newT : t).toSet().toList();
        await _entryRepo.update(entry.copyWith(tags: newTags));
      }
    }
  }

  Future<int> getDiagnosisCountForTag(String tag) async =>
      getEntryCountForTag(tag);

  Future<int> getEntryCountForTag(String tag) async =>
      _entryRepo.countByTag(catalogType, tag);

  Future<void> deleteTag(String tag) async {
    await _tagsRepo.deleteTag(catalogType, tag);
    state = await _tagsRepo.getAll(catalogType);

    final allEntries = await _entryRepo.getAll(catalogType: catalogType);
    for (final entry in allEntries) {
      if (entry.tags.contains(tag)) {
        final newTags = entry.tags.where((t) => t != tag).toList();
        await _entryRepo.update(entry.copyWith(tags: newTags));
      }
    }
  }
}

/// Backward-compatible alias.
typedef DiagnosisTagsNotifier = CatalogTagsNotifier;

final favoriteDiagnosesProvider =
    FutureProvider<List<CatalogEntry>>((ref) async {
  final repo = ref.watch(catalogEntryRepositoryProvider);
  return repo.getAll();
});

final catalogEntriesProvider =
    FutureProvider.family<List<CatalogEntry>, String>((ref, catalogType) async {
  final repo = ref.watch(catalogEntryRepositoryProvider);
  return repo.getAll(catalogType: catalogType);
});

final icdServiceProvider = Provider<IcdService>((ref) {
  return IcdService();
});

// ---- Services ----

final bleServiceProvider = ChangeNotifierProvider<BleService>((ref) {
  return BleService();
});

final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService();
});

// ---- LLM Config ----

class LlmConfigNotifier extends StateNotifier<LlmConfig> {
  final ApiService _apiService;
  final FlutterSecureStorage _storage;

  LlmConfigNotifier(this._apiService, this._storage)
      : super(const LlmConfig()) {
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      _storage.read(key: 'llm_base_url'),
      _storage.read(key: 'llm_api_key'),
      _storage.read(key: 'llm_model'),
      _storage.read(key: 'llm_reasoning_effort'),
    ]);
    state = LlmConfig(
      baseUrl: values[0] ?? 'https://api.openai.com/v1',
      apiKey: values[1] ?? '',
      model: values[2] ?? 'gpt-4o',
      reasoningEffort: values[3] ?? '',
    );
    _apiService.updateLlmConfig(state);
  }

  Future<void> save(LlmConfig config) async {
    await _storage.write(key: 'llm_base_url', value: config.baseUrl);
    await _storage.write(key: 'llm_api_key', value: config.apiKey);
    await _storage.write(key: 'llm_model', value: config.model);
    await _storage.write(key: 'llm_reasoning_effort', value: config.reasoningEffort);
    state = config;
    _apiService.updateLlmConfig(config);
  }

  Future<bool> testConnection() => _apiService.testLlmConnection();
}

final llmConfigProvider =
    StateNotifierProvider<LlmConfigNotifier, LlmConfig>((ref) {
  return LlmConfigNotifier(
    ref.read(apiServiceProvider),
    ref.read(secureStorageProvider),
  );
});

// ---- ASR Config ----

class AsrConfigNotifier extends StateNotifier<AsrConfig> {
  final ApiService _apiService;
  final FlutterSecureStorage _storage;

  AsrConfigNotifier(this._apiService, this._storage)
      : super(const AsrConfig()) {
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      _storage.read(key: 'asr_provider'),
      _storage.read(key: 'asr_base_url'),
      _storage.read(key: 'asr_api_key'),
      _storage.read(key: 'asr_model'),
      _storage.read(key: 'asr_language'),
    ]);
    final providerStr = values[0];
    final provider = AsrProvider.values
        .where((p) => p.name == providerStr).firstOrNull ??
        (providerStr == 'zhipu' ? AsrProvider.zhipuAsr : AsrProvider.openaiWhisper);
    final url = values[1];
    final key = values[2];
    final model = values[3];
    final lang = values[4];
    state = AsrConfig(
      provider: provider,
      baseUrl: url ?? provider.defaultUrl,
      apiKey: key ?? '',
      model: model ?? provider.defaultModel,
      language: lang ?? 'zh',
    );
    _apiService.updateAsrConfig(state);
  }

  Future<void> save(AsrConfig config) async {
    await _storage.write(key: 'asr_provider', value: config.provider.name);
    await _storage.write(key: 'asr_base_url', value: config.baseUrl);
    await _storage.write(key: 'asr_api_key', value: config.apiKey);
    await _storage.write(key: 'asr_model', value: config.model);
    await _storage.write(key: 'asr_language', value: config.language);
    state = config;
    _apiService.updateAsrConfig(config);
  }

  Future<bool> testConnection() => _apiService.testAsrConnection();
}

final asrConfigProvider =
    StateNotifierProvider<AsrConfigNotifier, AsrConfig>((ref) {
  return AsrConfigNotifier(
    ref.read(apiServiceProvider),
    ref.read(secureStorageProvider),
  );
});

// ---- OCR Config ----

class OcrConfigNotifier extends StateNotifier<OcrConfig> {
  final ApiService _apiService;
  final FlutterSecureStorage _storage;

  OcrConfigNotifier(this._apiService, this._storage)
      : super(const OcrConfig()) {
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      _storage.read(key: 'ocr_provider'),
      _storage.read(key: 'ocr_base_url'),
      _storage.read(key: 'ocr_api_key'),
      _storage.read(key: 'ocr_model'),
    ]);
    final provider = values[0];
    final url = values[1];
    final key = values[2];
    final model = values[3];
    final resolved = OcrProvider.values.where((p) => p.name == provider);
    final OcrProvider defaultOcrProvider;
    if (!kIsWeb && (Platform.isIOS || Platform.isMacOS)) {
      defaultOcrProvider = OcrProvider.appleVision;
    } else if (!kIsWeb && Platform.isAndroid) {
      defaultOcrProvider = OcrProvider.paddleLocal;
    } else {
      defaultOcrProvider = OcrProvider.mineru;
    }
    final ocrProvider =
        resolved.isEmpty ? defaultOcrProvider : resolved.first;
    state = OcrConfig(
      provider: ocrProvider,
      baseUrl: url ??
          (ocrProvider == OcrProvider.deepseek ? 'https://api.deepseek.com/v1' : null) ??
          (ocrProvider == OcrProvider.paddleOcr
              ? 'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs'
              : ocrProvider == OcrProvider.mineru
                  ? 'https://mineru.net/api/v1/agent'
                  : ocrProvider == OcrProvider.zhipu
                      ? 'https://open.bigmodel.cn/api/paas/v4'
                      : ocrProvider == OcrProvider.modelbest
                          ? 'https://api.modelbest.cn/v1'
                          : ocrProvider == OcrProvider.appleVision
                              ? 'local://apple-vision'
                              : ocrProvider == OcrProvider.paddleLocal
                                  ? 'local://paddle-ocr'
                                  : 'https://api.openai.com/v1'),
      apiKey: key ?? '',
      model: model ??
          (ocrProvider == OcrProvider.deepseek ? '' : null) ??
          (ocrProvider == OcrProvider.paddleOcr
              ? 'PaddleOCR-VL-1.6'
              : ocrProvider == OcrProvider.mineru
                  ? 'agent'
                  : ocrProvider == OcrProvider.zhipu
                      ? 'glm-ocr'
                      : ocrProvider == OcrProvider.modelbest
                          ? 'MiniCPM-OCR-1.0'
                          : ocrProvider == OcrProvider.appleVision
                              ? 'apple-vision'
                              : ocrProvider == OcrProvider.paddleLocal
                                  ? 'ppocr-v5-mobile'
                                  : 'gpt-4o'),
    );
    _apiService.updateOcrConfig(state);
  }

  Future<void> save(OcrConfig config) async {
    await _storage.write(key: 'ocr_provider', value: config.provider.name);
    await _storage.write(key: 'ocr_base_url', value: config.baseUrl);
    await _storage.write(key: 'ocr_api_key', value: config.apiKey);
    await _storage.write(key: 'ocr_model', value: config.model);
    state = config;
    _apiService.updateOcrConfig(config);
  }

  Future<bool> testConnection() => _apiService.testOcrConnection();
}

final ocrConfigProvider =
    StateNotifierProvider<OcrConfigNotifier, OcrConfig>((ref) {
  return OcrConfigNotifier(
    ref.read(apiServiceProvider),
    ref.read(secureStorageProvider),
  );
});

// ---- BLE Config State ----

class BleConfigNotifier extends StateNotifier<BleDeviceConfig> {
  final BleService _bleService;
  final FlutterSecureStorage _storage;

  BleConfigNotifier(this._bleService, this._storage)
      : super(const BleDeviceConfig()) {
    _load();
  }

  Future<void> _load() async {
    final values = await Future.wait([
      _storage.read(key: 'ble_device_name'),
      _storage.read(key: 'ble_service_uuid'),
      _storage.read(key: 'ble_tx_uuid'),
      _storage.read(key: 'ble_rx_uuid'),
      _storage.read(key: 'ble_mtu'),
      _storage.read(key: 'ble_last_id'),
      _storage.read(key: 'ble_last_name'),
    ]);
    final name = values[0];
    final svc = values[1];
    final tx = values[2];
    final rx = values[3];
    final mtu = values[4];
    final lastId = values[5];
    final lastName = values[6];

    final config = BleDeviceConfig(
      deviceNamePattern: name ?? '键盘',
      serviceUuid: svc ?? '6E400001-B5A3-F393-E0A9-E50E24DCCA9E',
      txCharacteristicUuid:
          tx ?? '6E400002-B5A3-F393-E0A9-E50E24DCCA9E',
      rxCharacteristicUuid:
          rx ?? '6E400003-B5A3-F393-E0A9-E50E24DCCA9E',
      mtu: int.tryParse(mtu ?? '') ?? 512,
    );
    state = config;
    _bleService.updateConfig(config);

    // 上次成功连接的设备（供“连接上次设备”）
    if (lastId != null) {
      _bleService.setLastDevice(lastId, lastName);
    }
  }

  Future<void> save(BleDeviceConfig config) async {
    await _storage.write(key: 'ble_device_name', value: config.deviceNamePattern);
    await _storage.write(key: 'ble_service_uuid', value: config.serviceUuid);
    await _storage.write(key: 'ble_tx_uuid', value: config.txCharacteristicUuid);
    await _storage.write(key: 'ble_rx_uuid', value: config.rxCharacteristicUuid);
    await _storage.write(key: 'ble_mtu', value: config.mtu.toString());
    state = config;
    _bleService.updateConfig(config);
  }

  /// 记住上次成功连接的设备；传 null 则清除。
  Future<void> saveLastDevice(String? remoteId, String? name) async {
    if (remoteId == null) {
      await _storage.delete(key: 'ble_last_id');
      await _storage.delete(key: 'ble_last_name');
    } else {
      await _storage.write(key: 'ble_last_id', value: remoteId);
      await _storage.write(key: 'ble_last_name', value: name ?? '');
    }
    _bleService.setLastDevice(remoteId, name);
  }
}

final bleConfigProvider =
    StateNotifierProvider<BleConfigNotifier, BleDeviceConfig>((ref) {
  return BleConfigNotifier(
    ref.read(bleServiceProvider),
    ref.read(secureStorageProvider),
  );
});

// ---- Sample Data ----

final sampleDataServiceProvider = Provider<SampleDataService>((ref) {
  return SampleDataService(
    patientRepo: ref.read(patientRepositoryProvider),
    messageRepo: ref.read(messageRepositoryProvider),
    templateRepo: ref.read(templateRepositoryProvider),
    contentTemplateRepo: ref.read(contentTemplateRepositoryProvider),
    settingsRepo: ref.read(settingsRepositoryProvider),
  );
});

// ---- Patients ----

final patientsProvider = StreamProvider<List<Patient>>((ref) async* {
  final sampleService = ref.read(sampleDataServiceProvider);
  await sampleService.ensureSampleData();
  final repo = ref.read(patientRepositoryProvider);
  yield await repo.getAll();
});

final patientProvider =
    FutureProvider.family<Patient?, String>((ref, id) async {
  final repo = ref.read(patientRepositoryProvider);
  return repo.getById(id);
});

// ---- Messages ----

final messagesProvider =
    StreamProvider.autoDispose.family<List<Message>, String>((ref, patientId) async* {
  final repo = ref.read(messageRepositoryProvider);
  yield await repo.getByPatient(patientId);
});

final lastMessageProvider =
    FutureProvider.family<Message?, String>((ref, patientId) async {
  final repo = ref.read(messageRepositoryProvider);
  return repo.getLastByPatient(patientId);
});

// ---- Templates ----

final templatesProvider = StreamProvider<List<Template>>((ref) async* {
  final repo = ref.read(templateRepositoryProvider);
  yield await repo.getAll();
});

final templateProvider =
    FutureProvider.family<Template?, String>((ref, id) async {
  final repo = ref.read(templateRepositoryProvider);
  return repo.getById(id);
});

final contentTemplatesProvider = StreamProvider.autoDispose
    .family<List<ContentTemplate>, String>((ref, structureTemplateId) async* {
  final repo = ref.read(contentTemplateRepositoryProvider);
  yield await repo.getByStructure(structureTemplateId);
});

// ---- Processing Service ----

final processingServiceProvider =
    StateNotifierProvider<ProcessingService, int>((ref) {
  return ProcessingService(
    ref.read(messageRepositoryProvider),
    ref.read(apiServiceProvider),
    ref.read(taskCenterProvider),
  );
});

final generationEngineProvider = Provider<GenerationEngine>((ref) {
  return GenerationEngine(ref.read(apiServiceProvider));
});

final contentTemplateExtractorProvider =
    Provider<ContentTemplateExtractor>((ref) {
  return ContentTemplateExtractor(ref.read(apiServiceProvider));
});

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  return SettingsRepository();
});

/// “打字完成提醒”偏好（系统横幅/应用内通知/震动），存 settings 表。
final typingDonePrefsProvider = FutureProvider<TypingDonePrefs>((ref) async {
  final repo = ref.read(settingsRepositoryProvider);
  final raw = await repo.get('typing_done_feedback');
  return TypingDonePrefs.parse(raw);
});

final llmPromptConfigProvider =
    StateNotifierProvider<LlmPromptConfigNotifier, LlmPromptConfig>((ref) {
  return LlmPromptConfigNotifier(ref.read(settingsRepositoryProvider));
});

class LlmPromptConfigNotifier extends StateNotifier<LlmPromptConfig> {
  final SettingsRepository _repo;

  /// 首次从数据库读取完成。调用方在读取配置前应先 await，避免把默认值误当成用户配置。
  late final Future<void> ready;

  LlmPromptConfigNotifier(this._repo) : super(const LlmPromptConfig()) {
    ready = _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _repo.get('llm_prompt_config');
      if (raw == null) return;
      state = LlmPromptConfig.fromJson(jsonDecode(raw));
    } catch (_) {
      // keep default on parse / database error
    }
  }

  Future<void> save(LlmPromptConfig config) async {
    state = config;
    await _repo.set('llm_prompt_config', jsonEncode(config.toJson()));
  }

  Future<void> reset() async {
    state = const LlmPromptConfig();
    await _repo.delete('llm_prompt_config');
  }
}

final extractorConfigProvider =
    StateNotifierProvider<ExtractorConfigNotifier, ExtractorConfig>((ref) {
  return ExtractorConfigNotifier(ref.read(settingsRepositoryProvider));
});

class ExtractorConfigNotifier extends StateNotifier<ExtractorConfig> {
  final SettingsRepository _repo;

  /// 首次从数据库读取完成。调用方在读取配置前应先 await。
  late final Future<void> ready;

  ExtractorConfigNotifier(this._repo) : super(const ExtractorConfig()) {
    ready = _load();
  }

  Future<void> _load() async {
    try {
      final raw = await _repo.get('content_template_extractor_config');
      if (raw == null) return;
      state = ExtractorConfig.fromJson(jsonDecode(raw));
    } catch (_) {
      // keep default on parse / database error
    }
  }

  Future<void> save(ExtractorConfig config) async {
    state = config;
    await _repo.set(
        'content_template_extractor_config', jsonEncode(config.toJson()));
  }

  Future<void> reset() async {
    state = const ExtractorConfig();
    await _repo.delete('content_template_extractor_config');
  }
}

final llmDryRunEnabledProvider =
    StateNotifierProvider<LlmDryRunNotifier, bool>((ref) {
  return LlmDryRunNotifier(ref.read(settingsRepositoryProvider));
});

class LlmDryRunNotifier extends StateNotifier<bool> {
  final SettingsRepository _repo;

  LlmDryRunNotifier(this._repo) : super(false) {
    _load();
  }

  Future<void> _load() async {
    final raw = await _repo.get('llm_dry_run_enabled');
    state = raw == 'true';
  }

  Future<void> toggle(bool enabled) async {
    state = enabled;
    await _repo.set('llm_dry_run_enabled', enabled ? 'true' : 'false');
  }
}

// ---- Timing Presets Management (多套输入节奏预设) ----

final timingPresetsProvider =
    StateNotifierProvider<TimingPresetsNotifier, List<TimingPreset>>((ref) {
  return TimingPresetsNotifier(ref.read(settingsRepositoryProvider));
});

class TimingPresetsNotifier extends StateNotifier<List<TimingPreset>> {
  final SettingsRepository _repo;
  late final Future<void> _loadFuture;

  TimingPresetsNotifier(this._repo) : super(kBuiltInTimingPresets) {
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final raw = await _repo.get('timing_presets_list');
    state = decodePresetsListJson(raw);
  }

  Future<List<TimingPreset>> ensureLoaded() async {
    await _loadFuture;
    return state;
  }

  Future<void> savePreset(TimingPreset preset) async {
    final idx = state.indexWhere((p) => p.id == preset.id || p.name == preset.name);
    List<TimingPreset> updated;
    if (idx >= 0) {
      updated = List.from(state)..[idx] = preset;
    } else {
      updated = [...state, preset];
    }
    state = updated;
    await _repo.set('timing_presets_list', encodePresetsListJson(updated));
  }

  Future<void> deletePreset(String id) async {
    final updated = state.where((p) => p.id != id).toList();
    state = updated.isEmpty ? List.from(kBuiltInTimingPresets) : updated;
    await _repo.set('timing_presets_list', encodePresetsListJson(state));
  }

  Future<void> resetToBuiltIns() async {
    state = List.from(kBuiltInTimingPresets);
    await _repo.set('timing_presets_list', encodePresetsListJson(state));
  }
}

// ---- Typing Block Presets Management (输入方案积木动作预设库) ----

final typingBlockPresetsProvider = StateNotifierProvider<
    TypingBlockPresetsNotifier, List<TypingBlockPreset>>((ref) {
  return TypingBlockPresetsNotifier(ref.read(settingsRepositoryProvider));
});

class TypingBlockPresetsNotifier
    extends StateNotifier<List<TypingBlockPreset>> {
  final SettingsRepository _repo;
  late final Future<void> _loadFuture;

  TypingBlockPresetsNotifier(this._repo) : super(createBuiltInBlockPresets()) {
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final raw = await _repo.get('typing_block_presets_list');
    state = decodeBlockPresetsListJson(raw);
  }

  Future<List<TypingBlockPreset>> ensureLoaded() async {
    await _loadFuture;
    return state;
  }

  Future<void> savePreset(TypingBlockPreset preset) async {
    final idx = state.indexWhere((p) => p.id == preset.id);
    List<TypingBlockPreset> updated;
    if (idx >= 0) {
      updated = List.from(state)..[idx] = preset;
    } else {
      updated = [...state, preset];
    }
    state = updated;
    await _repo.set(
        'typing_block_presets_list', encodeBlockPresetsListJson(updated));
  }

  Future<void> deletePreset(String id) async {
    final updated = state.where((p) => p.id != id).toList();
    state = updated;
    await _repo.set(
        'typing_block_presets_list', encodeBlockPresetsListJson(state));
  }

  Future<void> reorderPresets(int oldIndex, int newIndex) async {
    final updated = List<TypingBlockPreset>.from(state);
    if (newIndex > oldIndex) newIndex--;
    final item = updated.removeAt(oldIndex);
    updated.insert(newIndex, item);
    state = updated;
    await _repo.set(
        'typing_block_presets_list', encodeBlockPresetsListJson(state));
  }

  Future<void> restoreBuiltIns() async {
    final builtIns = createBuiltInBlockPresets();
    final updated = List<TypingBlockPreset>.from(state);
    for (final b in builtIns) {
      final idx = updated.indexWhere((p) => p.id == b.id || p.name == b.name);
      if (idx >= 0) {
        updated[idx] = b;
      } else {
        updated.insert(0, b);
      }
    }
    state = updated;
    await _repo.set(
        'typing_block_presets_list', encodeBlockPresetsListJson(state));
  }
}

// ---- OCR 并发限制配置 ----

final ocrConcurrencyProvider =
    StateNotifierProvider<OcrConcurrencyNotifier, int>((ref) {
  return OcrConcurrencyNotifier(ref.read(settingsRepositoryProvider), ref);
});

class OcrConcurrencyNotifier extends StateNotifier<int> {
  final SettingsRepository _repo;
  final Ref _ref;

  OcrConcurrencyNotifier(this._repo, this._ref) : super(2) {
    _load();
  }

  Future<void> _load() async {
    final raw = await _repo.get('ocr_concurrency');
    final val = int.tryParse(raw ?? '') ?? 2;
    state = val.clamp(1, 8);
    _ref.read(processingServiceProvider.notifier).setOcrConcurrency(state);
  }

  Future<void> setConcurrency(int val) async {
    final clean = val.clamp(1, 8);
    state = clean;
    await _repo.set('ocr_concurrency', clean.toString());
    _ref.read(processingServiceProvider.notifier).setOcrConcurrency(clean);
  }
}

// ---- 全局界面字号缩放倍率 (照顾不同视力/老花眼需求) ----

final appFontScaleProvider =
    StateNotifierProvider<AppFontScaleNotifier, double>((ref) {
  return AppFontScaleNotifier(ref.read(settingsRepositoryProvider));
});

class AppFontScaleNotifier extends StateNotifier<double> {
  final SettingsRepository _repo;

  AppFontScaleNotifier(this._repo) : super(1.0) {
    _load();
  }

  Future<void> _load() async {
    final raw = await _repo.get('app_font_scale');
    final val = double.tryParse(raw ?? '');
    if (val != null) {
      state = val.clamp(0.85, 1.45);
    }
  }

  Future<void> setScale(double scale, {bool persist = true}) async {
    final clean = (scale.clamp(0.85, 1.45) * 100).round() / 100.0;
    state = clean;
    if (persist) {
      await _repo.set('app_font_scale', clean.toStringAsFixed(2));
    }
  }
}

// ---- 全局常驻键盘悬浮窗开关 (默认开启) ----

final floatingOverlayEnabledProvider =
    StateNotifierProvider<FloatingOverlayEnabledNotifier, bool>((ref) {
  return FloatingOverlayEnabledNotifier(ref.read(settingsRepositoryProvider));
});

class FloatingOverlayEnabledNotifier extends StateNotifier<bool> {
  final SettingsRepository _repo;

  FloatingOverlayEnabledNotifier(this._repo) : super(true) {
    _load();
  }

  Future<void> _load() async {
    final raw = await _repo.get('floating_overlay_enabled');
    if (raw == null) {
      state = true; // 默认开启
    } else {
      state = raw == 'true';
    }
  }

  Future<void> toggle(bool enabled) async {
    state = enabled;
    await _repo.set('floating_overlay_enabled', enabled ? 'true' : 'false');
  }
}

// ---- 输入速度唯一数据源控制器 ----

final activeTimingControllerProvider =
    StateNotifierProvider<ActiveTimingController, ActiveTimingState>((ref) {
  return ActiveTimingController(
    ref.read(settingsRepositoryProvider),
    ref.read(bleServiceProvider),
    ref,
  );
});

// ---- 安装包版本信息（真实读取 APK/安装包元数据） ----

final appPackageInfoProvider = FutureProvider<PackageInfo>((ref) {
  return PackageInfo.fromPlatform();
});
