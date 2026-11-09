import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/ble/character_sanitizer.dart';
import '../../../data/services/engine_c/config_file_io.dart';
import '../../../data/services/engine_c/engine_c_models.dart';
import '../../../data/services/engine_c/template_bundle_engine.dart';
import '../../../domain/models/catalog_definition.dart';
import '../../../domain/models/content_template.dart';
import '../../../domain/models/template.dart';
import '../../pages/hub/hub_publish_wizard_page.dart';
import '../../../providers/asr_providers_provider.dart';
import '../../../providers/llm_providers_provider.dart';
import '../../../providers/ocr_providers_provider.dart';
import '../../../providers/providers.dart';

class EngineCExportSheet extends ConsumerStatefulWidget {
  final Template? focusTemplate;
  final ContentTemplate? focusContentTemplate;
  final bool diagnosisOnlyMode;
  final String catalogType;
  final String? initialSelectedDiagnosisTag;
  final String publishKind;

  const EngineCExportSheet({
    super.key,
    this.focusTemplate,
    this.focusContentTemplate,
    this.diagnosisOnlyMode = false,
    this.catalogType = 'diagnosis',
    this.initialSelectedDiagnosisTag,
    this.publishKind = '',
  });

  static Future<void> showForTemplate(
    BuildContext context,
    Template template, {
    ContentTemplate? focusContentTemplate,
    String publishKind = '',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EngineCExportSheet(
        focusTemplate: template,
        focusContentTemplate: focusContentTemplate,
        publishKind: publishKind,
      ),
    );
  }

  static Future<void> showForDiagnoses(
    BuildContext context, {
    String catalogType = 'diagnosis',
    String? initialTag,
    String publishKind = '',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EngineCExportSheet(
        diagnosisOnlyMode: true,
        catalogType: catalogType,
        initialSelectedDiagnosisTag: initialTag,
        publishKind: publishKind,
      ),
    );
  }

  @override
  ConsumerState<EngineCExportSheet> createState() => _EngineCExportSheetState();
}

class _EngineCExportSheetState extends ConsumerState<EngineCExportSheet> {
  bool _includeStructure = true;
  bool _includePipeline = true;
  final Set<String> _selectedProfileIds = {};
  final Set<String> _selectedCtIds = {};
  bool _ctsDefaultInitialized = false;

  final Set<String> _selectedDiagTags = {};
  bool _diagTagsDefaultInitialized = false;

  @override
  void initState() {
    super.initState();
    final t = widget.focusTemplate;
    if (t != null) {
      if (widget.focusContentTemplate != null) {
        _includeStructure = widget.publishKind.isEmpty;
        _includePipeline = false;
        _selectedCtIds.add(widget.focusContentTemplate!.id);
        _ctsDefaultInitialized = true;
      } else {
        _includeStructure = true;
        _includePipeline = t.pipeline.nodes.isNotEmpty;
        for (final p in t.typingProfiles) {
          _selectedProfileIds.add(p.id);
        }
      }
    }
  }

  EngineCExportRequest _buildRequest(List<String> allLibraryTags) {
    if (widget.diagnosisOnlyMode) {
      final isAll = _selectedDiagTags.length == allLibraryTags.length;
      return EngineCExportRequest(
        includeAllDiagnoses: isAll,
        catalogTypes: {widget.catalogType},
        selectedDiagnosisTags: isAll ? const {} : Set.from(_selectedDiagTags),
      );
    } else {
      final t = widget.focusTemplate!;
      return EngineCExportRequest(
        families: [
          StructureFamilyExportSelection(
            templateId: t.id,
            includePipeline: _includePipeline,
            selectedTypingProfileIds: Set.from(_selectedProfileIds),
            selectedContentTemplateIds: Set.from(_selectedCtIds),
            includeLinkedDiagnoses: false,
          ),
        ],
      );
    }
  }

  String _suggestedFilePrefix() {
    if (widget.diagnosisOnlyMode) {
      final name = ref
              .read(catalogsProvider)
              .valueOrNull
              ?.where((c) => c.id == widget.catalogType)
              .firstOrNull
              ?.name ??
          widget.catalogType;
      const suffix = '词条配置';
      return '$name$suffix';
    }
    if (widget.focusContentTemplate != null) {
      return '内容模板_${widget.focusContentTemplate!.name}';
    }
    return '模板配置_${widget.focusTemplate?.name ?? "导出"}';
  }

  Future<void> _publish(List<String> allLibraryTags) async {
    final t = widget.focusTemplate;
    if (widget.diagnosisOnlyMode) {
      if (_selectedDiagTags.isEmpty && allLibraryTags.isNotEmpty) {
        showAppToast(context, '请至少勾选一个分类标签');
        return;
      }
      Navigator.pop(context);
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => HubBatchPublishPage(
          diagnosisMode: true,
          selectedDiagnosisTags: _selectedDiagTags.toList(),
        ),
      ));
      return;
    }

    if (t == null) return;
    final allCts = (ref.read(contentTemplatesProvider(t.id)).valueOrNull ?? const <ContentTemplate>[]);
    final selectedProfiles = t.typingProfiles.where((p) => _selectedProfileIds.contains(p.id)).toList();
    final selectedCts = allCts.where((c) => _selectedCtIds.contains(c.id)).toList();

    final hasAny = _includeStructure || _includePipeline || selectedProfiles.isNotEmpty || selectedCts.isNotEmpty;
    if (!hasAny) {
      showAppToast(context, '请至少勾选一项要发布的内容');
      return;
    }

    final selection = HubPublishItemSelection(
      template: t,
      publishStructureItself: _includeStructure,
      includePipeline: _includePipeline,
      selectedProfiles: selectedProfiles,
      selectedContents: selectedCts,
      includeLinkedDiagnoses: false,
    );

    Navigator.pop(context);
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HubBatchPublishPage(selection: selection),
    ));
  }

  Future<void> _confirmExport(List<String> allLibraryTags) async {
    final req = _buildRequest(allLibraryTags);
    if (!req.hasAnySelected) {
      showAppToast(context, '请至少勾选一项导出内容');
      return;
    }

    try {
      final engine = ref.read(templateBundleEngineProvider);
      final text = await engine.exportJsonString(req);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ExportPreviewPage(
            text: text,
            suggestedFilePrefix: _suggestedFilePrefix(),
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        showAppToast(context, '导出失败: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogName = ref
            .watch(catalogsProvider)
            .valueOrNull
            ?.where((c) => c.id == widget.catalogType)
            .firstOrNull
            ?.name ??
        widget.catalogType;
    final allLibraryTags =
        ref.watch(catalogTagsProviderFamily(widget.catalogType));
    final t = widget.focusTemplate;
    final cts = t != null
        ? (ref.watch(contentTemplatesProvider(t.id)).valueOrNull ?? const [])
        : const <ContentTemplate>[];

    if (t != null && !_ctsDefaultInitialized && cts.isNotEmpty) {
      _ctsDefaultInitialized = true;
      _selectedCtIds.addAll(cts.map((c) => c.id));
    }

    if (widget.diagnosisOnlyMode && !_diagTagsDefaultInitialized) {
      _diagTagsDefaultInitialized = true;
      if (widget.initialSelectedDiagnosisTag != null) {
        _selectedDiagTags.add(widget.initialSelectedDiagnosisTag!);
      } else {
        _selectedDiagTags.addAll(allLibraryTags);
      }
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶栏：标题 + 全选 / 全不选 + 关闭
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.diagnosisOnlyMode
                        ? '导出词库 · $catalogName'
                        : '导出模板 · ${t?.name ?? ""}',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    setState(() {
                      if (widget.diagnosisOnlyMode) {
                        _selectedDiagTags.addAll(allLibraryTags);
                      } else if (t != null) {
                        if (t.pipeline.nodes.isNotEmpty) {
                          _includePipeline = true;
                        }
                        _selectedProfileIds
                            .addAll(t.typingProfiles.map((p) => p.id));
                        _selectedCtIds.addAll(cts.map((c) => c.id));
                                      }
                    });
                  },
                  child: const Text('全选'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  onPressed: () {
                    setState(() {
                      if (widget.diagnosisOnlyMode) {
                        _selectedDiagTags.clear();
                      } else {
                        _includePipeline = false;
                        _selectedProfileIds.clear();
                        _selectedCtIds.clear();
                      }
                    });
                  },
                  child: const Text('全不选'),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 8),

            // 树状勾选列表
            Flexible(
              child: SingleChildScrollView(
                child: widget.diagnosisOnlyMode
                    ? _buildDiagnosisCheckTree(allLibraryTags)
                    : _buildTemplateCheckTree(t!, cts),
              ),
            ),

            const SizedBox(height: 12),
            if (widget.publishKind.isEmpty)
              FilledButton(
                onPressed: () => _confirmExport(allLibraryTags),
                child: const Text('确认导出'),
              )
            else
              FilledButton(
                onPressed: () => _publish(allLibraryTags),
                child: const Text('下一步'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTemplateCheckTree(Template t, List<ContentTemplate> cts) {
    final hasPipelineNodes = t.pipeline.nodes.isNotEmpty;
    final profiles = t.typingProfiles;

    // 计算「输入方案」父级三态值：true (全选), false (全不选), null (半选)
    final bool? profilesParentState = profiles.isEmpty
        ? false
        : (_selectedProfileIds.length == profiles.length
            ? true
            : (_selectedProfileIds.isEmpty ? false : null));

    // 计算「内容模板」父级三态值：true (全选), false (全不选), null (半选)
    final bool? ctsParentState = cts.isEmpty
        ? false
        : (_selectedCtIds.length == cts.length
            ? true
            : (_selectedCtIds.isEmpty ? false : null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 结构模板（导出时强制勾选，发布到广场时允许取消）
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.trailing,
          value: _includeStructure,
          onChanged: widget.publishKind.isNotEmpty
              ? (v) => setState(() => _includeStructure = v ?? false)
              : (_) {},
          fillColor: _includeStructure
              ? WidgetStatePropertyAll(Theme.of(context).colorScheme.primary)
              : null,
          checkColor: Theme.of(context).colorScheme.onPrimary,
          title: Text(
            '文书类型：${t.name} (${t.slots.length} 个字段)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),

        // 2. 解析流程（上级标题）
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.trailing,
          value: hasPipelineNodes && _includePipeline,
          onChanged: hasPipelineNodes
              ? (v) => setState(() => _includePipeline = v ?? false)
              : null,
          title: Text(
            hasPipelineNodes
                ? '解析流程 (${t.pipeline.nodes.length} 个节点)'
                : '解析流程 (无)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),

        // 3. 输入方案（上级标题，支持全选 / 半选 / 全不选）
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.trailing,
          tristate: true,
          value: profilesParentState,
          onChanged: profiles.isEmpty
              ? null
              : (_) {
                  setState(() {
                    if (profilesParentState == true) {
                      _selectedProfileIds.clear();
                    } else {
                      _selectedProfileIds.addAll(profiles.map((p) => p.id));
                    }
                  });
                },
          title: Text(
            '输入方案 (${_selectedProfileIds.length}/${profiles.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        for (final p in profiles)
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.trailing,
              value: _selectedProfileIds.contains(p.id),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedProfileIds.add(p.id);
                  } else {
                    _selectedProfileIds.remove(p.id);
                  }
                });
              },
              title: Text(p.name, style: const TextStyle(fontSize: 13.5)),
            ),
          ),

        // 4. 内容模板（上级标题，支持全选 / 半选 / 全不选）
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.trailing,
          tristate: true,
          value: ctsParentState,
          onChanged: cts.isEmpty
              ? null
              : (_) {
                  setState(() {
                    if (ctsParentState == true) {
                      _selectedCtIds.clear();
                    } else {
                      _selectedCtIds.addAll(cts.map((c) => c.id));
                    }
                  });
                },
          title: Text(
            '内容模板 (${_selectedCtIds.length}/${cts.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        for (final ct in cts)
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.trailing,
              value: _selectedCtIds.contains(ct.id),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedCtIds.add(ct.id);
                  } else {
                    _selectedCtIds.remove(ct.id);
                  }
                });
              },
              title: Text(ct.name, style: const TextStyle(fontSize: 13.5)),
            ),
          ),
      ],
    );
  }

  Widget _buildDiagnosisCheckTree(List<String> allTags) {
    final favs = ref.watch(favoriteDiagnosesProvider).valueOrNull ?? const [];
    final bool? parentState = allTags.isEmpty
        ? false
        : (_selectedDiagTags.length == allTags.length
            ? true
            : (_selectedDiagTags.isEmpty ? false : null));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CheckboxListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.trailing,
          tristate: true,
          value: parentState,
          onChanged: allTags.isEmpty
              ? null
              : (_) {
                  setState(() {
                    if (parentState == true) {
                      _selectedDiagTags.clear();
                    } else {
                      _selectedDiagTags.addAll(allTags);
                    }
                  });
                },
          title: Text(
            '分类标签 (${_selectedDiagTags.length}/${allTags.length})',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
          ),
        ),
        for (final tag in allTags)
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.trailing,
              value: _selectedDiagTags.contains(tag),
              onChanged: (v) {
                setState(() {
                  if (v == true) {
                    _selectedDiagTags.add(tag);
                  } else {
                    _selectedDiagTags.remove(tag);
                  }
                });
              },
              title: Text(
                '$tag (${favs.where((d) => d.tags.contains(tag)).length})',
                style: const TextStyle(fontSize: 13.5),
              ),
            ),
          ),
      ],
    );
  }
}

class ExportPreviewPage extends StatefulWidget {
  final String text;
  final String suggestedFilePrefix;

  const ExportPreviewPage({
    super.key,
    required this.text,
    required this.suggestedFilePrefix,
  });

  @override
  State<ExportPreviewPage> createState() => _ExportPreviewPageState();
}

class _ExportPreviewPageState extends State<ExportPreviewPage> {
  static const _copyLimit = 1000;
  bool _saving = false;

  bool get _canCopy => widget.text.length <= _copyLimit;

  Future<void> _copy() async {
    if (!_canCopy) return;
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    showAppToast(context, '已复制配置文本');
  }

  Future<void> _saveFile() async {
    setState(() => _saving = true);
    try {
      final fileName = ConfigFileIo.buildFileName(widget.suggestedFilePrefix);
      final savedPath = await ConfigFileIo.saveConfigTextFile(
        content: widget.text,
        suggestedName: fileName,
      );
      if (!mounted) return;
      setState(() => _saving = false);
      if (savedPath != null) {
        showAppToast(context, '已保存配置文件：$savedPath');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showAppToast(context, '导出失败: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.text.length;
    return Scaffold(
      appBar: AppBar(title: const Text('确认导出')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text('共 $count 字',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                if (!_canCopy) ...[
                  const SizedBox(width: 8),
                  Text('超过 $_copyLimit 字，不能复制',
                      style: TextStyle(
                          fontSize: 13,
                          color: Theme.of(context).colorScheme.error)),
                ],
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: SelectableText(
                    widget.text,
                    style: const TextStyle(fontSize: 12, height: 1.4),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('复制配置文本'),
                      onPressed: _canCopy ? _copy : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.save_alt, size: 18),
                      label: const Text('导出为配置文件'),
                      onPressed: _saving ? null : _saveFile,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class EngineCImportSheet extends ConsumerStatefulWidget {
  final String title;
  final String? initialText;
  final String readme;

  const EngineCImportSheet({
    super.key,
    this.title = '导入配置文本',
    this.initialText,
    this.readme = '',
  });

  static Future<void> show(
    BuildContext context, {
    String title = '导入配置文本',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EngineCImportSheet(title: title),
    );
  }

  @override
  ConsumerState<EngineCImportSheet> createState() => _EngineCImportSheetState();
}

class _EngineCImportSheetState extends ConsumerState<EngineCImportSheet> {
  late final TextEditingController _textCtrl;
  EngineCImportPlan? _plan;
  String? _parseError;
  bool _isAnalyzing = false;
  bool _isExecuting = false;

  @override
  void initState() {
    super.initState();
    _textCtrl = TextEditingController(text: widget.initialText ?? '');
    if (_textCtrl.text.trim().isNotEmpty) {
      Future.microtask(() => _analyzeText(_textCtrl.text));
    }
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickConfigFile() async {
    try {
      final content = await ConfigFileIo.pickAndReadConfigFile();
      if (content != null && content.trim().isNotEmpty) {
        _textCtrl.text = content;
        await _analyzeText(content);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '读取文件失败：$e');
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.trim().isNotEmpty) {
      _textCtrl.text = data.text!;
      await _analyzeText(data.text!);
    }
  }

  Future<void> _analyzeText(String rawText) async {
    final trimmed = rawText.trim();
    if (trimmed.isEmpty) {
      setState(() {
        _plan = null;
        _parseError = null;
      });
      return;
    }

    setState(() {
      _isAnalyzing = true;
      _parseError = null;
    });

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        throw const FormatException('内容格式不正确');
      }
      final map = Map<String, dynamic>.from(decoded);
      final plan =
          await ref.read(templateBundleEngineProvider).analyzeImport(map);

      if (mounted) {
        setState(() {
          _plan = plan;
          _isAnalyzing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _plan = null;
          _parseError = '配置文本无法识别：$e';
          _isAnalyzing = false;
        });
      }
    }
  }

  Future<void> _executePlan() async {
    final plan = _plan;
    if (plan == null) return;

    setState(() => _isExecuting = true);
    try {
      final result = await ref
          .read(templateBundleEngineProvider)
          .executeImportPlan(plan);

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
      if (result.importedApiConfigs) {
        ref.invalidate(llmConfigProvider);
        ref.invalidate(llmProvidersProvider);
        ref.invalidate(asrConfigProvider);
        ref.invalidate(asrProvidersProvider);
        ref.invalidate(ocrConfigProvider);
        ref.invalidate(ocrProvidersProvider);
        ref.invalidate(ocrConcurrencyProvider);
      }
      if (result.importedPromptConfigs) {
        ref.invalidate(llmPromptConfigProvider);
        ref.invalidate(extractorConfigProvider);
        ref.invalidate(llmDryRunEnabledProvider);
      }
      if (result.importedDeviceConfigs) {
        ref.invalidate(timingPresetsProvider);
        ref.invalidate(typingBlockPresetsProvider);
        ref.invalidate(charReplacementRulesProvider);
        ref.invalidate(appFontScaleProvider);
        ref.invalidate(floatingOverlayEnabledProvider);
        ref.invalidate(activeTimingControllerProvider);
      }

      if (!mounted) return;
      Navigator.pop(context);
      showAppToast(context, result.summaryText);
    } catch (e) {
      if (mounted) {
        setState(() => _isExecuting = false);
        showAppToast(context, '导入失败：$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  icon: const Icon(Icons.folder_open, size: 16),
                  label: const Text('选择配置文件'),
                  onPressed: _pickConfigFile,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.content_paste, size: 16),
                  label: const Text('粘贴'),
                  onPressed: _pasteFromClipboard,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const Divider(height: 8),
            if (widget.readme.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Text(widget.readme.trim()),
              ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _textCtrl,
                      maxLines: _plan == null ? 5 : 3,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 11.5),
                      decoration: InputDecoration(
                        hintText: '选择上方配置文件，或直接在此粘贴配置文本...',
                        border: const OutlineInputBorder(),
                        suffixIcon: _textCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _textCtrl.clear();
                                  _analyzeText('');
                                },
                              )
                            : null,
                      ),
                      onChanged: _analyzeText,
                    ),
                    const SizedBox(height: 10),
                    if (_isAnalyzing)
                      const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (_parseError != null)
                      Text(
                        _parseError!,
                        style:
                            const TextStyle(color: Colors.red, fontSize: 12.5),
                      ),
                    if (_plan != null)
                      EngineCPlanPreviewWidget(
                        plan: _plan!,
                        onChanged: () => setState(() {}),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: (_plan != null &&
                      _plan!.hasAnyExecutable &&
                      !_isExecuting)
                  ? _executePlan
                  : null,
              child: Text(_isExecuting ? '导入中...' : '确认导入'),
            ),
          ],
        ),
      ),
    );
  }
}

class EngineCPlanPreviewWidget extends ConsumerWidget {
  final EngineCImportPlan plan;
  final VoidCallback onChanged;

  const EngineCPlanPreviewWidget({
    super.key,
    required this.plan,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final unitPlan in plan.unitPlans)
          _buildStructureUnitCard(context, unitPlan),
        if (plan.diagnosisPlan.hasAny) _buildDiagnosisCard(context, ref),
        if (plan.envelope.apiConfigs != null ||
            plan.envelope.promptConfigs != null ||
            plan.envelope.deviceAndOutputConfigs != null)
          _buildSystemConfigsCard(context),
      ],
    );
  }

  Widget _buildStructureUnitCard(
    BuildContext context,
    StructureUnitImportPlan unitPlan,
  ) {
    final struct = unitPlan.unit.structure;
    final hasLocal = unitPlan.matchedLocalStructure != null;
    final slotsMatch = unitPlan.slotsSignatureMatched;

    String statusText;
    if (!hasLocal) {
      statusText = '新建文书类型';
    } else if (slotsMatch) {
      final localName = unitPlan.matchedLocalStructure!.name.trim();
      final incomingName = struct.name.trim();
      statusText = localName == incomingName
          ? '匹配现有模板'
          : '匹配现有模板「$localName」，导入名称为「$incomingName」';
    } else {
      statusText = '字段不同，新建模板副本';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${struct.name} (${struct.slots.length} 个字段)',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                      Text(
                        statusText,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.blueGrey),
                      ),
                    ],
                  ),
                ),
                _buildStructureActionDropdown(unitPlan),
              ],
            ),
            if (unitPlan.structureAction != StructureMatchAction.skip) ...[
              if (unitPlan.unit.hasPipeline ||
                  unitPlan.typingProfilePlans.isNotEmpty ||
                  unitPlan.contentTemplatePlans.isNotEmpty)
                const Divider(height: 12),

              if (unitPlan.unit.hasPipeline)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '解析流程：${_describePipelineAction(unitPlan)}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      if (unitPlan.structureAction ==
                              StructureMatchAction.matchAndReuseLocal &&
                          unitPlan.matchedLocalStructure!.pipeline.nodes
                              .isNotEmpty &&
                          unitPlan.pipelineAction !=
                              PipelineMatchAction.unchanged)
                        TextButton(
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                          onPressed: () {
                            unitPlan.pipelineAction = unitPlan.pipelineAction ==
                                    PipelineMatchAction.replaceLocal
                                ? PipelineMatchAction.keepLocal
                                : PipelineMatchAction.replaceLocal;
                            onChanged();
                          },
                          child: Text(
                            unitPlan.pipelineAction ==
                                    PipelineMatchAction.replaceLocal
                                ? '保留原流程'
                                : '使用导入流程',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ),
                ),

              for (final profPlan in unitPlan.typingProfilePlans)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '输入方案「${profPlan.incoming.name}」：${_describeChildAction(profPlan.action, unitPlan.structureAction)}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      if (unitPlan.structureAction ==
                              StructureMatchAction.matchAndReuseLocal &&
                          profPlan.existingLocal != null &&
                          profPlan.action != ChildItemMatchAction.identicalSkip)
                        _buildChildActionMenu(
                          current: profPlan.action,
                          onSelect: (v) {
                            profPlan.action = v;
                            onChanged();
                          },
                        ),
                    ],
                  ),
                ),

              for (final ctPlan in unitPlan.contentTemplatePlans)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '内容模板「${ctPlan.incoming.name}」：${_describeChildAction(ctPlan.action, unitPlan.structureAction)}',
                          style: const TextStyle(fontSize: 12.5),
                        ),
                      ),
                      if (unitPlan.structureAction ==
                              StructureMatchAction.matchAndReuseLocal &&
                          ctPlan.existingLocal != null &&
                          ctPlan.action != ChildItemMatchAction.identicalSkip)
                        _buildChildActionMenu(
                          current: ctPlan.action,
                          onSelect: (v) {
                            ctPlan.action = v;
                            onChanged();
                          },
                        ),
                    ],
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildStructureActionDropdown(StructureUnitImportPlan unitPlan) {
    final hasLocal = unitPlan.matchedLocalStructure != null;
    if (!hasLocal) {
      return DropdownButton<StructureMatchAction>(
        value: unitPlan.structureAction,
        isDense: true,
        underline: const SizedBox.shrink(),
        style: const TextStyle(fontSize: 12, color: Colors.black87),
        items: const [
          DropdownMenuItem(
            value: StructureMatchAction.createNew,
            child: Text('导入'),
          ),
          DropdownMenuItem(
            value: StructureMatchAction.skip,
            child: Text('跳过'),
          ),
        ],
        onChanged: (v) {
          if (v != null) {
            unitPlan.structureAction = v;
            onChanged();
          }
        },
      );
    }

    return DropdownButton<StructureMatchAction>(
      value: unitPlan.structureAction,
      isDense: true,
      underline: const SizedBox.shrink(),
      style: const TextStyle(fontSize: 12, color: Colors.black87),
      items: [
        if (unitPlan.slotsSignatureMatched)
          const DropdownMenuItem(
            value: StructureMatchAction.matchAndReuseLocal,
            child: Text('合并到现有'),
          ),
        const DropdownMenuItem(
          value: StructureMatchAction.forkAsCopy,
          child: Text('新建副本'),
        ),
        const DropdownMenuItem(
          value: StructureMatchAction.overwriteLocal,
          child: Text('覆盖现有'),
        ),
        const DropdownMenuItem(
          value: StructureMatchAction.skip,
          child: Text('跳过'),
        ),
      ],
      onChanged: (v) {
        if (v != null) {
          unitPlan.structureAction = v;
          onChanged();
        }
      },
    );
  }

  Widget _buildChildActionMenu({
    required ChildItemMatchAction current,
    required ValueChanged<ChildItemMatchAction> onSelect,
  }) {
    return PopupMenuButton<ChildItemMatchAction>(
      initialValue: current,
      onSelected: onSelect,
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: ChildItemMatchAction.forkChildCopy,
          child: Text('新建副本'),
        ),
        PopupMenuItem(
          value: ChildItemMatchAction.overwriteLocalChild,
          child: Text('覆盖同名项'),
        ),
        PopupMenuItem(
          value: ChildItemMatchAction.skip,
          child: Text('跳过'),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          current == ChildItemMatchAction.forkChildCopy
              ? '新建副本 ▾'
              : current == ChildItemMatchAction.overwriteLocalChild
                  ? '覆盖 ▾'
                  : '跳过 ▾',
          style: const TextStyle(fontSize: 12, color: Colors.blue),
        ),
      ),
    );
  }

  String _describePipelineAction(StructureUnitImportPlan unitPlan) {
    if (unitPlan.structureAction == StructureMatchAction.createNew ||
        unitPlan.structureAction == StructureMatchAction.forkAsCopy) {
      return '一并导入';
    }
    switch (unitPlan.pipelineAction) {
      case PipelineMatchAction.unchanged:
        return '无变化';
      case PipelineMatchAction.applyToLocal:
        return '导入流程';
      case PipelineMatchAction.replaceLocal:
        return '更新流程';
      case PipelineMatchAction.keepLocal:
        return '保留原流程';
    }
  }

  String _describeChildAction(
    ChildItemMatchAction action,
    StructureMatchAction parentAction,
  ) {
    if (parentAction == StructureMatchAction.createNew ||
        parentAction == StructureMatchAction.forkAsCopy) {
      return '一并导入';
    }
    switch (action) {
      case ChildItemMatchAction.createNew:
        return '新增';
      case ChildItemMatchAction.identicalSkip:
        return '已存在 (跳过)';
      case ChildItemMatchAction.forkChildCopy:
        return '新建副本';
      case ChildItemMatchAction.overwriteLocalChild:
        return '覆盖';
      case ChildItemMatchAction.skip:
        return '跳过';
    }
  }

  Widget _buildDiagnosisCard(BuildContext context, WidgetRef ref) {
    final dp = plan.diagnosisPlan;
    final catalogNames = {
      for (final c in (ref.watch(catalogsProvider).valueOrNull ??
          const <CatalogDefinition>[]))
        c.id: c.name,
    };

    String labelOf(String id) => catalogNames[id] ?? id;

    final counts = <String, int>{};
    for (final d in dp.newDiagnoses) {
      counts[d.catalogType] = (counts[d.catalogType] ?? 0) + 1;
    }
    for (final d in dp.mergedTagDiagnoses) {
      counts[d.catalogType] = (counts[d.catalogType] ?? 0) + 1;
    }

    final parts = <String>[
      for (final entry in counts.entries)
        if (entry.value > 0) '${labelOf(entry.key)} ${entry.value} 条',
    ];

    final newTagEntries = dp.newTagsByCatalog.entries
        .where((entry) => entry.value.isNotEmpty)
        .toList();
    if (newTagEntries.isNotEmpty) {
      final total =
          newTagEntries.fold<int>(0, (sum, entry) => sum + entry.value.length);
      if (newTagEntries.length == 1) {
        parts.add('新增标签 $total 个');
      } else {
        parts.add(
          '新增标签: ${newTagEntries.map((e) => '${labelOf(e.key)} ${e.value.length}').join('、')}',
        );
      }
    }
    if (plan.envelope.catalogs.isNotEmpty) {
      parts.add('词库定义 ${plan.envelope.catalogs.length} 个');
    }
    if (dp.identicalSkippedCount > 0) {
      parts.add('相同跳过 ${dp.identicalSkippedCount} 条');
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: CheckboxListTile(
        dense: true,
        value: dp.enabled,
        onChanged: (v) {
          dp.enabled = v ?? false;
          onChanged();
        },
        title: const Text('标准词条库',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
        subtitle: Text(
          parts.isEmpty ? '包含标准词条与分类标签' : parts.join(' · '),
          style: const TextStyle(fontSize: 12),
        ),
      ),
    );
  }

  Widget _buildSystemConfigsCard(BuildContext context) {
    final apiSummary = plan.apiConfigsSummary;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          if (plan.envelope.apiConfigs != null)
            CheckboxListTile(
              dense: true,
              value: plan.importApiConfigs,
              onChanged: (v) {
                plan.importApiConfigs = v ?? false;
                onChanged();
              },
              title: const Text('AI 服务商与 API 密钥配置'),
              subtitle: apiSummary != null
                  ? Text(apiSummary, style: const TextStyle(fontSize: 12))
                  : null,
            ),
          if (plan.envelope.promptConfigs != null)
            CheckboxListTile(
              dense: true,
              value: plan.importPromptConfigs,
              onChanged: (v) {
                plan.importPromptConfigs = v ?? false;
                onChanged();
              },
              title: const Text('Prompt 提示词配置'),
              subtitle: const Text('AI 提示词模板与反推提取参数',
                  style: TextStyle(fontSize: 12)),
            ),
          if (plan.envelope.deviceAndOutputConfigs != null)
            CheckboxListTile(
              dense: true,
              value: plan.importDeviceConfigs,
              onChanged: (v) {
                plan.importDeviceConfigs = v ?? false;
                onChanged();
              },
              title: const Text('外设时序与输出设置'),
              subtitle: const Text('时序预设、按键兼容替换、悬浮窗与二维码设置',
                  style: TextStyle(fontSize: 12)),
            ),
        ],
      ),
    );
  }
}
