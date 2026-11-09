import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/ble/character_sanitizer.dart';
import '../../../data/services/engine_c/config_file_io.dart';
import '../../../data/services/engine_c/engine_c_models.dart';
import '../../../data/services/engine_c/template_bundle_engine.dart';
import '../../../providers/asr_providers_provider.dart';
import '../../../providers/llm_providers_provider.dart';
import '../../../providers/ocr_providers_provider.dart';
import '../../../providers/providers.dart';
import '../../widgets/engine_c/engine_c_sheets.dart';

class BackupCenterPage extends ConsumerStatefulWidget {
  const BackupCenterPage({super.key});

  @override
  ConsumerState<BackupCenterPage> createState() => _BackupCenterPageState();
}

class _BackupCenterPageState extends ConsumerState<BackupCenterPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // 导出选项
  bool _expTemplates = true;
  bool _expContentTemplates = true;
  bool _expFavoriteDiagnoses = true;
  bool _expApiConfigs = true;
  bool _expPromptConfigs = true;
  bool _expBleAndQr = true;

  // 导入状态
  final TextEditingController _importInputCtrl = TextEditingController();
  bool _isImporting = false;
  EngineCImportPlan? _importPlan;
  String? _importParseError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _importInputCtrl.dispose();
    super.dispose();
  }

  Future<String?> _generateExportText() async {
    final hasAny = _expTemplates ||
        _expContentTemplates ||
        _expFavoriteDiagnoses ||
        _expApiConfigs ||
        _expPromptConfigs ||
        _expBleAndQr;

    if (!hasAny) {
      showAppToast(context, '请至少勾选一项要导出的内容');
      return null;
    }

    final allTemplates = await ref.read(templateRepositoryProvider).getAll();
    final families = <StructureFamilyExportSelection>[];

    if (_expTemplates || _expContentTemplates) {
      for (final t in allTemplates) {
        families.add(StructureFamilyExportSelection(
          templateId: t.id,
          includePipeline: _expTemplates,
          selectedTypingProfileIds: _expTemplates ? null : const <String>{},
          selectedContentTemplateIds:
              _expContentTemplates ? null : const <String>{},
          includeLinkedDiagnoses: _expFavoriteDiagnoses,
        ));
      }
    }

    final req = EngineCExportRequest(
      families: families,
      includeAllDiagnoses: _expFavoriteDiagnoses,
      includeApiConfigs: _expApiConfigs,
      includePromptConfigs: _expPromptConfigs,
      includeDeviceAndOutputConfigs: _expBleAndQr,
    );

    return ref.read(templateBundleEngineProvider).exportJsonString(req);
  }

  Future<void> _handleConfirmExport() async {
    try {
      final text = await _generateExportText();
      if (text == null || !mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExportPreviewPage(
            text: text,
            suggestedFilePrefix: '文书助手导出',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '导出失败: $e');
    }
  }

  Future<void> _pickImportFile() async {
    try {
      final content = await ConfigFileIo.pickAndReadConfigFile();
      if (content != null && content.trim().isNotEmpty) {
        setState(() {
          _importInputCtrl.text = content;
        });
        await _analyzeImport();
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '读取文件失败：$e');
      }
    }
  }

  Future<void> _analyzeImport() async {
    final raw = _importInputCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _importPlan = null;
        _importParseError = null;
      });
      return;
    }

    Map<String, dynamic> bundle;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('配置文本格式不正确');
      }
      bundle = Map<String, dynamic>.from(decoded);
    } catch (e) {
      setState(() {
        _importPlan = null;
        _importParseError = '配置文本解析失败：$e';
      });
      return;
    }

    setState(() => _isImporting = true);
    try {
      final plan =
          await ref.read(templateBundleEngineProvider).analyzeImport(bundle);
      if (!mounted) return;
      setState(() {
        _importPlan = plan;
        _importParseError = null;
        _isImporting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importPlan = null;
        _importParseError = '配置文本无法识别：$e';
        _isImporting = false;
      });
    }
  }

  Future<void> _handleImport() async {
    final plan = _importPlan;
    if (plan == null || !plan.hasAnyExecutable) return;

    setState(() => _isImporting = true);
    try {
      final result =
          await ref.read(templateBundleEngineProvider).executeImportPlan(plan);

      ref.invalidate(templatesProvider);
      for (final u in plan.unitPlans) {
        ref.invalidate(contentTemplatesProvider(u.unit.structure.id));
        if (u.matchedLocalStructure != null) {
          ref.invalidate(
              contentTemplatesProvider(u.matchedLocalStructure!.id));
        }
      }
      ref.invalidate(favoriteDiagnosesProvider);
      ref.invalidate(diagnosisTagsProvider);
      ref.invalidate(catalogTagsProviderFamily('diagnosis'));
      ref.invalidate(catalogTagsProviderFamily('procedure'));
      ref.invalidate(catalogEntriesProvider('diagnosis'));
      ref.invalidate(catalogEntriesProvider('procedure'));
      ref.invalidate(llmConfigProvider);
      ref.invalidate(llmProvidersProvider);
      ref.invalidate(asrConfigProvider);
      ref.invalidate(asrProvidersProvider);
      ref.invalidate(ocrConfigProvider);
      ref.invalidate(ocrProvidersProvider);
      ref.invalidate(ocrConcurrencyProvider);
      ref.invalidate(llmPromptConfigProvider);
      ref.invalidate(extractorConfigProvider);
      ref.invalidate(llmDryRunEnabledProvider);
      ref.invalidate(timingPresetsProvider);
      ref.invalidate(typingBlockPresetsProvider);
      ref.invalidate(charReplacementRulesProvider);
      ref.invalidate(appFontScaleProvider);
      ref.invalidate(floatingOverlayEnabledProvider);
      ref.invalidate(activeTimingControllerProvider);

      setState(() => _isImporting = false);

      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(
                result.isSuccess ? Icons.check_circle : Icons.warning_amber,
                color: result.isSuccess ? Colors.green : Colors.orange,
              ),
              const SizedBox(width: 8),
              const Text('导入完成'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(result.summaryText),
              if (result.warnings.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Text('提示信息：', style: TextStyle(color: Colors.red)),
                ...result.warnings.map(
                  (w) => Text(' • $w',
                      style: const TextStyle(fontSize: 12, color: Colors.red)),
                ),
              ],
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _importInputCtrl.clear();
                  _importPlan = null;
                  _importParseError = null;
                });
              },
              child: const Text('确定'),
            ),
          ],
        ),
      );
    } catch (e) {
      setState(() => _isImporting = false);
      if (!mounted) return;
      showAppToast(context, '导入失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导入与导出'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(icon: Icon(Icons.upload_file), text: '导出'),
            Tab(icon: Icon(Icons.download_for_offline), text: '导入'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildExportTab(),
          _buildImportTab(),
        ],
      ),
    );
  }

  Widget _buildExportTab() {
    final templates = ref.watch(templatesProvider).valueOrNull ?? [];
    final catalogs = ref.watch(catalogsProvider).valueOrNull ?? const [];
    var catalogEntryCount = 0;
    var catalogTagCount = 0;
    for (final c in catalogs) {
      catalogEntryCount +=
          (ref.watch(catalogEntriesProvider(c.id)).valueOrNull ?? const [])
              .length;
      catalogTagCount += ref.watch(catalogTagsProviderFamily(c.id)).length;
    }
    final llmState = ref.watch(llmProvidersProvider);
    final asrState = ref.watch(asrProvidersProvider);
    final ocrState = ref.watch(ocrProvidersProvider);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined, color: Colors.blue),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '勾选需要导出的内容',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _expTemplates = true;
                        _expContentTemplates = true;
                        _expFavoriteDiagnoses = true;
                        _expApiConfigs = true;
                        _expPromptConfigs = true;
                        _expBleAndQr = true;
                      }),
                      child: const Text('全选'),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _expTemplates = false;
                        _expContentTemplates = false;
                        _expFavoriteDiagnoses = false;
                        _expApiConfigs = false;
                        _expPromptConfigs = false;
                        _expBleAndQr = false;
                      }),
                      child: const Text('全不选'),
                    ),
                  ],
                ),
                const Divider(height: 16),
                CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.trailing,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('文书类型'),
                  subtitle: Text(templates.isNotEmpty
                      ? '${templates.length} 份文书类型，含输入方案与解析流程'
                      : '字段定义、解析流程及输入方案'),
                  value: _expTemplates,
                  onChanged: (v) => setState(() => _expTemplates = v ?? true),
                ),
                CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.trailing,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('内容模板'),
                  subtitle: const Text('整体规范、整份示范文书及字段示例'),
                  value: _expContentTemplates,
                  onChanged: (v) =>
                      setState(() => _expContentTemplates = v ?? true),
                ),
                CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.trailing,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('标准词条库及分类标签'),
                  subtitle: Text(
                      '${catalogs.length} 个词库 · $catalogEntryCount 条词条 · $catalogTagCount 个标签'),
                  value: _expFavoriteDiagnoses,
                  onChanged: (v) =>
                      setState(() => _expFavoriteDiagnoses = v ?? true),
                ),
                CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.trailing,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('AI 服务商与 API 密钥'),
                  subtitle: Text(
                      '大模型 (${llmState.providers.length} 家) · 语音识别 (${asrState.providers.length} 家) · 文档识图 (${ocrState.providers.length} 家)'),
                  value: _expApiConfigs,
                  onChanged: (v) => setState(() => _expApiConfigs = v ?? true),
                ),
                CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.trailing,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Prompt 提示词设置'),
                  subtitle: const Text('提示词模板与 AI 反推提取参数'),
                  value: _expPromptConfigs,
                  onChanged: (v) =>
                      setState(() => _expPromptConfigs = v ?? true),
                ),
                CheckboxListTile(
                  controlAffinity: ListTileControlAffinity.trailing,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('外设时序与输出设置'),
                  subtitle: const Text('打字时序预设、按键兼容替换、悬浮窗与二维码设置'),
                  value: _expBleAndQr,
                  onChanged: (v) => setState(() => _expBleAndQr = v ?? true),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _handleConfirmExport,
                  child: const Text('确认导出'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImportOverview(EngineCImportPlan plan) {
    final lines = <String>[];
    if (plan.unitPlans.isNotEmpty) {
      final n = plan.unitPlans
          .where((u) => u.structureAction != StructureMatchAction.skip)
          .length;
      lines.add('文书类型 $n 份');
    }
    if (plan.diagnosisPlan.enabled && plan.diagnosisPlan.hasAny) {
      final d = plan.diagnosisPlan;
      final entryCount = d.newDiagnoses.length + d.mergedTagDiagnoses.length;
      final tagCount = d.newTagsByCatalog.values
          .fold<int>(0, (sum, tags) => sum + tags.length);
      final parts = <String>[];
      if (entryCount > 0) parts.add('标准词条 $entryCount 条');
      if (tagCount > 0) parts.add('标签 $tagCount 个');
      if (d.identicalSkippedCount > 0) {
        parts.add('相同跳过 ${d.identicalSkippedCount} 条');
      }
      if (parts.isNotEmpty) lines.add(parts.join(' · '));
    }
    if (plan.importApiConfigs) {
      lines.add(plan.apiConfigsSummary != null
          ? 'AI 服务商与密钥 (${plan.apiConfigsSummary})'
          : 'AI 服务商与接口密钥');
    }
    if (plan.importPromptConfigs) lines.add('提示词设置');
    if (plan.importDeviceConfigs) lines.add('外设与输出设置');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          lines.isEmpty ? '没有将导入的内容' : '将导入：${lines.join('、')}',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('查看具体内容', style: TextStyle(fontSize: 14)),
          children: [
            EngineCPlanPreviewWidget(
              plan: plan,
              onChanged: () => setState(() {}),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildImportTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.file_download_outlined,
                        color: Colors.teal),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '导入配置文本',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.folder_open, size: 16),
                      label: const Text('选择配置文件'),
                      onPressed: _pickImportFile,
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.paste, size: 16),
                      label: const Text('粘贴'),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          setState(() {
                            _importInputCtrl.text = data!.text!;
                          });
                          await _analyzeImport();
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                  TextField(
                  controller: _importInputCtrl,
                  maxLines: _importPlan == null ? 8 : 4,
                  decoration: InputDecoration(
                    hintText: '选择上方配置文件，或在此粘贴导出的配置文本...',
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.grey.withAlpha(15),
                    suffixIcon: _importInputCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              setState(() {
                                _importInputCtrl.clear();
                                _importPlan = null;
                                _importParseError = null;
                              });
                            },
                          )
                        : null,
                  ),
                  onChanged: (_) => _analyzeImport(),
                ),
                if (_importParseError != null) ...[
                  const SizedBox(height: 8),
                  Text(_importParseError!,
                      style: const TextStyle(color: Colors.red, fontSize: 12.5)),
                ],
                if (_importPlan != null) ...[
                  const SizedBox(height: 12),
                  _buildImportOverview(_importPlan!),
                ],
                const SizedBox(height: 16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    icon: _isImporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.check),
                    label: Text(_isImporting ? '处理中…' : '确认导入'),
                    onPressed: (_isImporting ||
                            _importPlan == null ||
                            !_importPlan!.hasAnyExecutable)
                        ? null
                        : _handleImport,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
