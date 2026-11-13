import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../../domain/models/content_template.dart';
import '../../../domain/models/favorite_diagnosis.dart';
import '../../../domain/models/template.dart';
import '../../repositories/content_template_repository.dart';
import '../../repositories/favorite_diagnosis_repository.dart';
import '../../repositories/settings_repository.dart';
import '../../repositories/template_repository.dart';
import '../../../providers/providers.dart';

/// 导出选项集合
class BackupExportOptions {
  final bool templates; // 结构模板
  final bool contentTemplates; // 内容模板
  final bool favoriteDiagnoses; // 收藏诊断及标签
  final bool apiConfigs; // LLM/ASR/OCR 接口与密钥 (含 API Key)
  final bool promptConfigs; // Prompt 编排与反推参数
  final bool bleAndQrSettings; // 蓝牙时序默认值与二维码参数

  const BackupExportOptions({
    this.templates = true,
    this.contentTemplates = true,
    this.favoriteDiagnoses = true,
    this.apiConfigs = true,
    this.promptConfigs = true,
    this.bleAndQrSettings = true,
  });

  bool get hasAnySelected =>
      templates ||
      contentTemplates ||
      favoriteDiagnoses ||
      apiConfigs ||
      promptConfigs ||
      bleAndQrSettings;
}

/// 导入合并策略
enum ImportConflictStrategy {
  merge, // 保留现有并追加/覆盖匹配项（推荐）
  skipExisting, // 若同 ID/同名已存在则跳过
}

/// 导入结果统计
class ImportResult {
  int importedTemplates = 0;
  int importedContentTemplates = 0;
  int importedDiagnoses = 0;
  int importedDiagnosisTags = 0;
  bool importedApiConfigs = false;
  bool importedPromptConfigs = false;
  bool importedBleAndQrSettings = false;
  final List<String> warnings = [];

  bool get isSuccess => warnings.isEmpty;

  String get summary {
    final parts = <String>[];
    if (importedTemplates > 0) parts.add('$importedTemplates 个文书类型');
    if (importedContentTemplates > 0) parts.add('$importedContentTemplates 个内容模板');
    if (importedDiagnoses > 0) parts.add('$importedDiagnoses 条标准词条库');
    if (importedDiagnosisTags > 0) parts.add('$importedDiagnosisTags 个分类标签');
    if (importedApiConfigs) parts.add('API 配置 (含密钥)');
    if (importedPromptConfigs) parts.add('Prompt 提示词配置');
    if (importedBleAndQrSettings) parts.add('蓝牙与二维码参数');
    if (parts.isEmpty) return '未导入任何有效数据';
    return '成功导入：${parts.join('、')}';
  }
}

/// 数据备份与统一导入导出服务
class BackupService {
  final TemplateRepository templateRepo;
  final ContentTemplateRepository contentTemplateRepo;
  final FavoriteDiagnosisRepository favoriteDiagnosisRepo;
  final SettingsRepository settingsRepo;
  final FlutterSecureStorage secureStorage;

  BackupService({
    required this.templateRepo,
    required this.contentTemplateRepo,
    required this.favoriteDiagnosisRepo,
    required this.settingsRepo,
    required this.secureStorage,
  });

  /// 构建导出 JSON 字典
  Future<Map<String, dynamic>> exportBundle(BackupExportOptions options) async {
    final bundle = <String, dynamic>{
      'version': '1.0',
      'generator': 'medhistory_backup_center',
      'exported_at': DateTime.now().toIso8601String(),
    };

    // 1. 结构模板
    if (options.templates) {
      final templates = await templateRepo.getAll();
      bundle['templates'] = templates.map((t) => t.toMap()).toList();
    }

    // 2. 内容模板
    if (options.contentTemplates) {
      final contentTemplates = await contentTemplateRepo.getAll();
      bundle['content_templates'] =
          contentTemplates.map((ct) => ct.toMap()).toList();
    }

    // 3. 常用词条与标签（诊断与手术等）
    if (options.favoriteDiagnoses) {
      final diags = await favoriteDiagnosisRepo.getAll();
      bundle['favorite_diagnoses'] = diags.map((d) => d.toMap()).toList();

      final rawTags = await settingsRepo.get('diagnosis_tags');
      if (rawTags != null && rawTags.isNotEmpty) {
        try {
          bundle['diagnosis_tags'] = jsonDecode(rawTags);
        } catch (_) {}
      }
      final rawProcTags = await settingsRepo.get('procedure_tags');
      if (rawProcTags != null && rawProcTags.isNotEmpty) {
        try {
          bundle['procedure_tags'] = jsonDecode(rawProcTags);
        } catch (_) {}
      }
    }

    // 4. API 密钥与端点 (LLM / ASR / OCR)
    if (options.apiConfigs) {
      final providersMatrix =
          await secureStorage.read(key: 'llm_providers_matrix_v1');
      final activeProviderId =
          await secureStorage.read(key: 'llm_active_provider_id_v1');
      final asrProvidersMatrix =
          await secureStorage.read(key: 'asr_providers_matrix_v1');
      final asrActiveProviderId =
          await secureStorage.read(key: 'asr_active_provider_id_v1');
      final ocrProvidersMatrix =
          await secureStorage.read(key: 'ocr_providers_matrix_v1');
      final ocrActiveProviderId =
          await secureStorage.read(key: 'ocr_active_provider_id_v1');

      dynamic decodeMatrix(String? raw) {
        if (raw == null || raw.trim().isEmpty) return null;
        try {
          return jsonDecode(raw);
        } catch (_) {
          return null;
        }
      }

      final llmDecoded = decodeMatrix(providersMatrix);
      final asrDecoded = decodeMatrix(asrProvidersMatrix);
      final ocrDecoded = decodeMatrix(ocrProvidersMatrix);

      bundle['api_configs'] = {
        'llm': {
          'baseUrl': await secureStorage.read(key: 'llm_base_url') ?? '',
          'apiKey': await secureStorage.read(key: 'llm_api_key') ?? '',
          'model': await secureStorage.read(key: 'llm_model') ?? '',
          'providers': ?llmDecoded,
          if (providersMatrix != null && providersMatrix.isNotEmpty)
            'providersMatrix': providersMatrix,
          if (activeProviderId != null && activeProviderId.isNotEmpty)
            'activeProviderId': activeProviderId,
        },
        'asr': {
          'provider': await secureStorage.read(key: 'asr_provider') ?? '',
          'baseUrl': await secureStorage.read(key: 'asr_base_url') ?? '',
          'apiKey': await secureStorage.read(key: 'asr_api_key') ?? '',
          'model': await secureStorage.read(key: 'asr_model') ?? '',
          'language': await secureStorage.read(key: 'asr_language') ?? '',
          'providers': ?asrDecoded,
          if (asrProvidersMatrix != null && asrProvidersMatrix.isNotEmpty)
            'providersMatrix': asrProvidersMatrix,
          if (asrActiveProviderId != null && asrActiveProviderId.isNotEmpty)
            'activeProviderId': asrActiveProviderId,
        },
        'ocr': {
          'provider': await secureStorage.read(key: 'ocr_provider') ?? '',
          'baseUrl': await secureStorage.read(key: 'ocr_base_url') ?? '',
          'apiKey': await secureStorage.read(key: 'ocr_api_key') ?? '',
          'model': await secureStorage.read(key: 'ocr_model') ?? '',
          'providers': ?ocrDecoded,
          if (ocrProvidersMatrix != null && ocrProvidersMatrix.isNotEmpty)
            'providersMatrix': ocrProvidersMatrix,
          if (ocrActiveProviderId != null && ocrActiveProviderId.isNotEmpty)
            'activeProviderId': ocrActiveProviderId,
        },
      };
    }

    // 5. Prompt 与反推配置
    if (options.promptConfigs) {
      final promptRaw = await settingsRepo.get('llm_prompt_config');
      final extractorRaw =
          await settingsRepo.get('content_template_extractor_config');
      final dryRunRaw = await settingsRepo.get('llm_dry_run_enabled');

      bundle['prompt_configs'] = {
        if (promptRaw != null) 'llm_prompt_config': jsonDecode(promptRaw),
        if (extractorRaw != null)
          'content_template_extractor_config': jsonDecode(extractorRaw),
        if (dryRunRaw != null) 'llm_dry_run_enabled': dryRunRaw == 'true',
      };
    }

    // 6. 蓝牙时序默认值、多套预设列表与二维码分包设置
    if (options.bleAndQrSettings) {
      final timingAppDefaults =
          await settingsRepo.get('timing_app_defaults');
      final timingPresetsList =
          await settingsRepo.get('timing_presets_list');
      final typingBlockPresetsList =
          await settingsRepo.get('typing_block_presets_list');
      final typingFeedback = await settingsRepo.get('typing_done_feedback');
      final qrMaxChunk = await settingsRepo.get('qr_max_chunk_size');

      final devMap = <String, dynamic>{};
      if (timingAppDefaults != null) devMap['timing_app_defaults'] = timingAppDefaults;
      if (timingPresetsList != null) devMap['timing_presets_list'] = timingPresetsList;
      if (typingBlockPresetsList != null) {
        devMap['typing_block_presets_list'] = typingBlockPresetsList;
      }
      if (typingFeedback != null) devMap['typing_done_feedback'] = typingFeedback;
      if (qrMaxChunk != null) devMap['qr_max_chunk_size'] = qrMaxChunk;
      bundle['device_and_output_configs'] = devMap;
    }

    return bundle;
  }

  /// 导出为格式化 JSON 字符串
  Future<String> exportJsonString(BackupExportOptions options) async {
    final bundle = await exportBundle(options);
    return const JsonEncoder.withIndent('  ').convert(bundle);
  }

  /// 解析并导入备份 JSON
  Future<ImportResult> importBundle(
    Map<String, dynamic> bundle, {
    ImportConflictStrategy strategy = ImportConflictStrategy.merge,
  }) async {
    final result = ImportResult();

    // 1. 导入结构模板
    if (bundle.containsKey('templates') && bundle['templates'] is List) {
      final list = bundle['templates'] as List;
      final existing = await templateRepo.getAll();
      final existingIds = existing.map((e) => e.id).toSet();

      for (final item in list) {
        if (item is Map) {
          try {
            final t = Template.fromMap(Map<String, dynamic>.from(item));
            if (existingIds.contains(t.id)) {
              if (strategy == ImportConflictStrategy.merge) {
                await templateRepo.update(t);
                result.importedTemplates++;
              }
            } else {
              await templateRepo.insert(t);
              result.importedTemplates++;
            }
          } catch (e) {
            result.warnings.add('文书类型导入异常: $e');
          }
        }
      }
    }

    // 2. 导入内容模板
    if (bundle.containsKey('content_templates') &&
        bundle['content_templates'] is List) {
      final list = bundle['content_templates'] as List;
      final existing = await contentTemplateRepo.getAll();
      final existingIds = existing.map((e) => e.id).toSet();

      for (final item in list) {
        if (item is Map) {
          try {
            final ct =
                ContentTemplate.fromMap(Map<String, dynamic>.from(item));
            if (existingIds.contains(ct.id)) {
              if (strategy == ImportConflictStrategy.merge) {
                await contentTemplateRepo.update(ct);
                result.importedContentTemplates++;
              }
            } else {
              await contentTemplateRepo.insert(ct);
              result.importedContentTemplates++;
            }
          } catch (e) {
            result.warnings.add('内容模板导入异常: $e');
          }
        }
      }
    }

    // 3. 常用诊断与标签
    if (bundle.containsKey('favorite_diagnoses') &&
        bundle['favorite_diagnoses'] is List) {
      final list = bundle['favorite_diagnoses'] as List;
      final existing = await favoriteDiagnosisRepo.getAll();
      final existingIds = existing.map((e) => e.id).toSet();

      for (final item in list) {
        if (item is Map) {
          try {
            final d =
                FavoriteDiagnosis.fromMap(Map<String, dynamic>.from(item));
            if (existingIds.contains(d.id)) {
              if (strategy == ImportConflictStrategy.merge) {
                await favoriteDiagnosisRepo.update(d);
                result.importedDiagnoses++;
              }
            } else {
              await favoriteDiagnosisRepo.insert(d);
              result.importedDiagnoses++;
            }
          } catch (e) {
            result.warnings.add('标准词条库导入异常: $e');
          }
        }
      }
    }

    if (bundle.containsKey('diagnosis_tags') &&
        bundle['diagnosis_tags'] is List) {
      try {
        final newTags = (bundle['diagnosis_tags'] as List)
            .map((e) => e.toString().trim())
            .where((t) => t.isNotEmpty)
            .toList();

        final rawExisting = await settingsRepo.get('diagnosis_tags');
        final currentTags = <String>[];
        if (rawExisting != null) {
          try {
            currentTags.addAll(
                (jsonDecode(rawExisting) as List).map((e) => e.toString()));
          } catch (_) {}
        }

        final merged = {...currentTags, ...newTags}.toList();
        await settingsRepo.set('diagnosis_tags', jsonEncode(merged));
        result.importedDiagnosisTags = newTags.length;
      } catch (e) {
        result.warnings.add('分类标签导入异常: $e');
      }
    }

    if (bundle.containsKey('procedure_tags') &&
        bundle['procedure_tags'] is List) {
      try {
        final newTags = (bundle['procedure_tags'] as List)
            .map((e) => e.toString().trim())
            .where((t) => t.isNotEmpty)
            .toList();

        final rawExisting = await settingsRepo.get('procedure_tags');
        final currentTags = <String>[];
        if (rawExisting != null) {
          try {
            currentTags.addAll(
                (jsonDecode(rawExisting) as List).map((e) => e.toString()));
          } catch (_) {}
        }

        final merged = {...currentTags, ...newTags}.toList();
        await settingsRepo.set('procedure_tags', jsonEncode(merged));
      } catch (e) {
        result.warnings.add('手术标签导入异常: $e');
      }
    }

    // 4. API 配置导入
    if (bundle.containsKey('api_configs') && bundle['api_configs'] is Map) {
      try {
        final apis = bundle['api_configs'] as Map;
        String? normalizeMatrix(dynamic raw) {
          if (raw is List) return jsonEncode(raw);
          if (raw is String && raw.trim().isNotEmpty) return raw;
          return null;
        }

        if (apis.containsKey('llm') && apis['llm'] is Map) {
          final llm = apis['llm'] as Map;
          if (llm['baseUrl'] != null) {
            await secureStorage.write(
                key: 'llm_base_url', value: llm['baseUrl'].toString());
          }
          if (llm['apiKey'] != null) {
            await secureStorage.write(
                key: 'llm_api_key', value: llm['apiKey'].toString());
          }
          if (llm['model'] != null) {
            await secureStorage.write(
                key: 'llm_model', value: llm['model'].toString());
          }
          final matrix = normalizeMatrix(llm['providers'] ?? llm['providersMatrix']);
          if (matrix != null) {
            await secureStorage.write(
              key: 'llm_providers_matrix_v1',
              value: matrix,
            );
            if (llm['activeProviderId'] != null) {
              await secureStorage.write(
                key: 'llm_active_provider_id_v1',
                value: llm['activeProviderId'].toString(),
              );
            }
          } else {
            await secureStorage.write(key: 'llm_providers_matrix_v1', value: '');
            await secureStorage.write(key: 'llm_active_provider_id_v1', value: '');
          }
        }
        // Publishing credentials from old backups are intentionally ignored.

        if (apis.containsKey('asr') && apis['asr'] is Map) {
          final asr = apis['asr'] as Map;
          if (asr['provider'] != null) {
            await secureStorage.write(
                key: 'asr_provider', value: asr['provider'].toString());
          }
          if (asr['baseUrl'] != null) {
            await secureStorage.write(
                key: 'asr_base_url', value: asr['baseUrl'].toString());
          }
          if (asr['apiKey'] != null) {
            await secureStorage.write(
                key: 'asr_api_key', value: asr['apiKey'].toString());
          }
          if (asr['model'] != null) {
            await secureStorage.write(
                key: 'asr_model', value: asr['model'].toString());
          }
          if (asr['language'] != null) {
            await secureStorage.write(
                key: 'asr_language', value: asr['language'].toString());
          }
          final asrMatrix = normalizeMatrix(asr['providers'] ?? asr['providersMatrix']);
          if (asrMatrix != null) {
            await secureStorage.write(
              key: 'asr_providers_matrix_v1',
              value: asrMatrix,
            );
            if (asr['activeProviderId'] != null) {
              await secureStorage.write(
                key: 'asr_active_provider_id_v1',
                value: asr['activeProviderId'].toString(),
              );
            }
          } else {
            await secureStorage.write(
                key: 'asr_providers_matrix_v1', value: '');
            await secureStorage.write(
                key: 'asr_active_provider_id_v1', value: '');
          }
        }

        if (apis.containsKey('ocr') && apis['ocr'] is Map) {
          final ocr = apis['ocr'] as Map;
          if (ocr['provider'] != null) {
            await secureStorage.write(
                key: 'ocr_provider', value: ocr['provider'].toString());
          }
          if (ocr['baseUrl'] != null) {
            await secureStorage.write(
                key: 'ocr_base_url', value: ocr['baseUrl'].toString());
          }
          if (ocr['apiKey'] != null) {
            await secureStorage.write(
                key: 'ocr_api_key', value: ocr['apiKey'].toString());
          }
          if (ocr['model'] != null) {
            await secureStorage.write(
                key: 'ocr_model', value: ocr['model'].toString());
          }
          final ocrMatrix = normalizeMatrix(ocr['providers'] ?? ocr['providersMatrix']);
          if (ocrMatrix != null) {
            await secureStorage.write(
              key: 'ocr_providers_matrix_v1',
              value: ocrMatrix,
            );
            if (ocr['activeProviderId'] != null) {
              await secureStorage.write(
                key: 'ocr_active_provider_id_v1',
                value: ocr['activeProviderId'].toString(),
              );
            }
          } else {
            await secureStorage.write(
                key: 'ocr_providers_matrix_v1', value: '');
            await secureStorage.write(
                key: 'ocr_active_provider_id_v1', value: '');
          }
        }
        result.importedApiConfigs = true;
      } catch (e) {
        result.warnings.add('API 配置导入异常: $e');
      }
    }

    // 5. Prompt 与反推配置
    if (bundle.containsKey('prompt_configs') &&
        bundle['prompt_configs'] is Map) {
      try {
        final prompts = bundle['prompt_configs'] as Map;
        if (prompts.containsKey('llm_prompt_config')) {
          await settingsRepo.set('llm_prompt_config',
              jsonEncode(prompts['llm_prompt_config']));
        }
        if (prompts.containsKey('content_template_extractor_config')) {
          await settingsRepo.set('content_template_extractor_config',
              jsonEncode(prompts['content_template_extractor_config']));
        }
        if (prompts.containsKey('llm_dry_run_enabled')) {
          await settingsRepo.set('llm_dry_run_enabled',
              prompts['llm_dry_run_enabled'] == true ? 'true' : 'false');
        }
        result.importedPromptConfigs = true;
      } catch (e) {
        result.warnings.add('Prompt 提示词配置导入异常: $e');
      }
    }

    // 6. 设备与输出参数
    if (bundle.containsKey('device_and_output_configs') &&
        bundle['device_and_output_configs'] is Map) {
      try {
        final devs = bundle['device_and_output_configs'] as Map;
        if (devs.containsKey('timing_app_defaults')) {
          await settingsRepo.set(
              'timing_app_defaults', devs['timing_app_defaults'].toString());
        }
        if (devs.containsKey('timing_presets_list')) {
          await settingsRepo.set(
              'timing_presets_list', devs['timing_presets_list'].toString());
        }
        if (devs.containsKey('typing_block_presets_list')) {
          await settingsRepo.set('typing_block_presets_list',
              devs['typing_block_presets_list'].toString());
        }
        if (devs.containsKey('typing_done_feedback')) {
          await settingsRepo.set(
              'typing_done_feedback', devs['typing_done_feedback'].toString());
        }
        if (devs.containsKey('qr_max_chunk_size')) {
          await settingsRepo.set(
              'qr_max_chunk_size', devs['qr_max_chunk_size'].toString());
        }
        result.importedBleAndQrSettings = true;
      } catch (e) {
        result.warnings.add('外设时序与二维码配置导入异常: $e');
      }
    }

    return result;
  }
}

/// BackupService Provider
final backupServiceProvider = Provider<BackupService>((ref) {
  return BackupService(
    templateRepo: ref.read(templateRepositoryProvider),
    contentTemplateRepo: ref.read(contentTemplateRepositoryProvider),
    favoriteDiagnosisRepo: ref.read(favoriteDiagnosisRepositoryProvider),
    settingsRepo: ref.read(settingsRepositoryProvider),
    secureStorage: ref.read(secureStorageProvider),
  );
});
