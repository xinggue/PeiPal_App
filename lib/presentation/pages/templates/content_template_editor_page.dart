import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:peipal/presentation/widgets/common/app_toast.dart';

import '../../../data/services/content_template_extractor.dart';
import '../../../data/services/media/app_image_picker.dart';
import '../../../domain/models/catalog_definition.dart';
import '../../../domain/models/catalog_mention.dart';
import '../../../domain/models/content_template.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import '../../widgets/common/catalog_mention_picker_overlay.dart';
import '../../widgets/common/inline_diff_box.dart';
import '../../widgets/common/mention_text_editing_controller.dart';
import '../../widgets/engine_c/engine_c_sheets.dart';

enum _SlotFilterMode {
  all,
  unfilled,
  changes,
}

class ContentTemplateEditorPage extends ConsumerStatefulWidget {
  final String structureTemplateId;
  final String? contentTemplateId;
  final String? initialMigrateFromId;
  final Template? previewStructure;
  final ContentTemplate? previewContentTemplate;

  const ContentTemplateEditorPage({
    super.key,
    required this.structureTemplateId,
    this.contentTemplateId,
    this.initialMigrateFromId,
    this.previewStructure,
    this.previewContentTemplate,
  });

  bool get isReadOnly => previewContentTemplate != null;

  @override
  ConsumerState<ContentTemplateEditorPage> createState() =>
      _ContentTemplateEditorPageState();
}

class _FieldControllers {
  final TextEditingController templateText;
  final MentionTextEditingController guidance;
  bool showGuidance;

  /// Snapshot before AI operation for inline diffing.
  String? beforeTemplateText;
  String? beforeGuidance;

  _FieldControllers({
    required this.templateText,
    required this.guidance,
    this.showGuidance = false,
  });

  bool get isFilled =>
      templateText.text.trim().isNotEmpty || guidance.text.trim().isNotEmpty;

  PendingTextDiff? get textDiff => beforeTemplateText == null
      ? null
      : PendingTextDiff(
          beforeText: beforeTemplateText!,
          afterText: templateText.text,
        );

  PendingTextDiff? get guidanceDiff => beforeGuidance == null
      ? null
      : PendingTextDiff(
          beforeText: beforeGuidance!,
          afterText: guidance.text,
        );

  DiffChangeKind get overallDiffKind {
    final td = textDiff;
    final gd = guidanceDiff;
    if ((td == null || !td.hasChange) && (gd == null || !gd.hasChange)) {
      return DiffChangeKind.none;
    }
    final wasEmpty = (beforeTemplateText?.trim().isEmpty ?? true) &&
        (beforeGuidance?.trim().isEmpty ?? true);
    final nowEmpty = !isFilled;
    if (wasEmpty && !nowEmpty) return DiffChangeKind.added;
    return DiffChangeKind.modified;
  }

  bool get hasPendingDiff => overallDiffKind != DiffChangeKind.none;

  void acceptDiff() {
    beforeTemplateText = null;
    beforeGuidance = null;
  }

  void revertDiff() {
    if (beforeTemplateText != null) {
      templateText.text = beforeTemplateText!;
    }
    if (beforeGuidance != null) {
      guidance.text = beforeGuidance!;
      showGuidance = guidance.text.trim().isNotEmpty;
    }
    beforeTemplateText = null;
    beforeGuidance = null;
  }

  void dispose() {
    templateText.dispose();
    guidance.dispose();
  }
}

class _ContentTemplateEditorPageState
    extends ConsumerState<ContentTemplateEditorPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _globalGuidanceCtrl;
  String? _beforeGlobalGuidance;

  final Map<String, _FieldControllers> _fieldCtrls = {};
  Template? _structure;
  ContentTemplate? _existing;
  bool _isSaving = false;
  bool _isAiBusy = false;
  String _aiBusyLabel = '';

  _SlotFilterMode _filterMode = _SlotFilterMode.all;

  /// Full sample record pasted for AI import; persisted as `fullExample`.
  String? _pastedRecord;

  bool get _isEditing => widget.contentTemplateId != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController();
    _globalGuidanceCtrl = TextEditingController();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    if (widget.isReadOnly) {
      final st = widget.previewStructure!;
      final ct = widget.previewContentTemplate!;
      _nameCtrl.text = ct.name;
      _globalGuidanceCtrl.text = ct.globalGuidance;
      _structure = st;
      _existing = ct;
      _initSlotControllers(st, ct);
      if (mounted) setState(() {});
      return;
    }

    final st = await ref
        .read(templateRepositoryProvider)
        .getById(widget.structureTemplateId);
    ContentTemplate? ct;
    if (_isEditing) {
      ct = await ref
          .read(contentTemplateRepositoryProvider)
          .getById(widget.contentTemplateId!);
      if (ct != null) {
        _nameCtrl.text = ct.name;
        _globalGuidanceCtrl.text = ct.globalGuidance;
      }
    }

    if (st != null && mounted) {
      setState(() {
        _structure = st;
        _existing = ct;
        _initSlotControllers(st, ct);
      });

      if (widget.initialMigrateFromId != null && !_isEditing) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _openMigrateSheet(preselectedId: widget.initialMigrateFromId);
          }
        });
      }
    } else if (mounted) {
      showAppToast(context, '未找到关联的文书类型');
      context.pop();
    }
  }

  void _initSlotControllers(Template st, ContentTemplate? ct) {
    for (final slot in st.sortedSlots) {
      final slotData = ct?.slots[slot.key];
      final text = slotData?.examples.firstOrNull ?? '';
      var guidance = slotData?.guidance ?? '';

      final refs = slotData?.catalogRefs ?? const <CatalogMentionRef>[];
      if (refs.isNotEmpty) {
        final fallbackType = slot.catalogType ?? 'diagnosis';
        for (final ref in refs) {
          final type =
              ref.catalogType.trim().isEmpty ? fallbackType : ref.catalogType;
          final token = '\uFFFC[CATALOG:$type:${ref.tag}]\uFFFC';
          if (!guidance.contains(token)) {
            guidance = guidance.isEmpty ? token : '$guidance $token';
          }
        }
      }

      final ctrl = _FieldControllers(
        templateText: TextEditingController(text: text),
        guidance: MentionTextEditingController(
          text: guidance,
          catalogsGetter: _catalogMap,
        ),
        showGuidance: guidance.trim().isNotEmpty,
      );
      ctrl.templateText.addListener(_onFieldChanged);
      ctrl.guidance.addListener(_onFieldChanged);
      _fieldCtrls[slot.key] = ctrl;
    }
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _globalGuidanceCtrl.dispose();
    for (final c in _fieldCtrls.values) {
      c.templateText.removeListener(_onFieldChanged);
      c.guidance.removeListener(_onFieldChanged);
      c.dispose();
    }
    super.dispose();
  }

  PendingTextDiff? get _globalGuidanceDiff => _beforeGlobalGuidance == null
      ? null
      : PendingTextDiff(
          beforeText: _beforeGlobalGuidance!,
          afterText: _globalGuidanceCtrl.text,
        );

  int get _addedDiffCount {
    var count = 0;
    final gd = _globalGuidanceDiff;
    if (gd != null && gd.kind == DiffChangeKind.added) count++;
    for (final c in _fieldCtrls.values) {
      if (c.overallDiffKind == DiffChangeKind.added) count++;
    }
    return count;
  }

  int get _modifiedDiffCount {
    var count = 0;
    final gd = _globalGuidanceDiff;
    if (gd != null && gd.kind == DiffChangeKind.modified) count++;
    for (final c in _fieldCtrls.values) {
      if (c.overallDiffKind == DiffChangeKind.modified) count++;
    }
    return count;
  }

  int get _totalDiffCount => _addedDiffCount + _modifiedDiffCount;

  int get _filledFieldCount =>
      _fieldCtrls.values.where((c) => c.isFilled).length;

  void _acceptAllDiffs() {
    setState(() {
      _beforeGlobalGuidance = null;
      for (final c in _fieldCtrls.values) {
        c.acceptDiff();
      }
      if (_filterMode == _SlotFilterMode.changes) {
        _filterMode = _SlotFilterMode.all;
      }
    });
    showAppToast(context, '已采纳全部变更');
  }

  void _revertAllDiffs() {
    setState(() {
      if (_beforeGlobalGuidance != null) {
        _globalGuidanceCtrl.text = _beforeGlobalGuidance!;
        _beforeGlobalGuidance = null;
      }
      for (final c in _fieldCtrls.values) {
        c.revertDiff();
      }
      if (_filterMode == _SlotFilterMode.changes) {
        _filterMode = _SlotFilterMode.all;
      }
    });
    showAppToast(context, '已撤回全部变更');
  }

  void _applyAiResult(
    ExtractionResult result, {
    String? sampleRecord,
    String? suggestedName,
  }) {
    var changedCount = 0;
    setState(() {
      if (sampleRecord != null && sampleRecord.trim().isNotEmpty) {
        _pastedRecord = sampleRecord.trim();
      }
      if (suggestedName != null &&
          suggestedName.trim().isNotEmpty &&
          _nameCtrl.text.trim().isEmpty) {
        _nameCtrl.text = suggestedName.trim();
      }

      final newGlobal = result.globalGuidance.trim();
      final oldGlobal = _globalGuidanceCtrl.text;
      if (newGlobal.isNotEmpty && newGlobal != oldGlobal.trim()) {
        _beforeGlobalGuidance ??= oldGlobal;
        _globalGuidanceCtrl.text = newGlobal;
        changedCount++;
      }

      for (final entry in result.fields.entries) {
        final ctrl = _fieldCtrls[entry.key];
        if (ctrl == null) continue;

        final oldT = ctrl.templateText.text;
        final oldG = ctrl.guidance.text;
        final newT = entry.value.text.trim();
        final newG = entry.value.guidance.trim();

        var fieldTouched = false;
        if (newT.isNotEmpty && newT != oldT.trim()) {
          ctrl.beforeTemplateText ??= oldT;
          ctrl.beforeGuidance ??= oldG;
          ctrl.templateText.text = newT;
          fieldTouched = true;
        }
        if (newG.isNotEmpty && newG != oldG.trim()) {
          ctrl.beforeTemplateText ??= oldT;
          ctrl.beforeGuidance ??= oldG;
          ctrl.guidance.text = newG;
          ctrl.showGuidance = true;
          fieldTouched = true;
        }

        if (fieldTouched) changedCount++;
      }
    });

    if (changedCount == 0) {
      showAppToast(context, '未产生新的字段变更');
    } else {
      showAppToast(context, '已生成 $changedCount 处更新，可在卡片上对比或逐项确认');
    }
  }

  Map<String, SlotContent> _buildSlotContentMap() {
    final slots = <String, SlotContent>{};
    for (final entry in _fieldCtrls.entries) {
      final t = entry.value.templateText.text.trim();
      final g = entry.value.guidance.text.trim();
      final mentions = CatalogMentionHelper.parseMentions(g);
      final tags = mentions.map((m) => m.tag).toList();

      if (t.isNotEmpty || g.isNotEmpty) {
        slots[entry.key] = SlotContent(
          examples: t.isNotEmpty ? [t] : const [],
          guidance: g,
          catalogRefs: mentions,
          catalogTags: tags,
        );
      }
    }

    // Preserve any existing stale fields if not explicitly cleaned
    if (_existing != null && _structure != null) {
      final currentKeys = _structure!.slots.map((s) => s.key).toSet();
      for (final e in _existing!.slots.entries) {
        if (!currentKeys.contains(e.key) && !_fieldCtrls.containsKey(e.key)) {
          slots[e.key] = e.value;
        }
      }
    }
    return slots;
  }

  Future<void> _save() async {
    if (_isSaving || _structure == null) return;
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showAppToast(context, '请输入内容模板名称');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final slots = _buildSlotContentMap();

      final ct = ContentTemplate(
        id: _existing?.id,
        structureTemplateId: widget.structureTemplateId,
        name: name,
        globalGuidance: _globalGuidanceCtrl.text.trim(),
        fullExample: _pastedRecord ?? _existing?.fullExample ?? '',
        slots: slots,
        createdAt: _existing?.createdAt,
      );

      final repo = ref.read(contentTemplateRepositoryProvider);
      if (_isEditing) {
        await repo.update(ct);
      } else {
        await repo.insert(ct);
      }

      ref.invalidate(contentTemplatesProvider(widget.structureTemplateId));
      if (mounted) context.pop();
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveAsCopy() async {
    if (_isSaving || _structure == null) return;
    final baseName = _nameCtrl.text.trim();
    final nameCtrl = TextEditingController(
      text: baseName.isEmpty ? '新模板副本' : '$baseName（副本）',
    );

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('另存为新内容模板'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '新模板名称',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = nameCtrl.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('另存'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();

    if (newName == null || newName.isEmpty || !mounted) return;

    setState(() => _isSaving = true);
    try {
      final slots = _buildSlotContentMap();
      final ct = ContentTemplate(
        structureTemplateId: widget.structureTemplateId,
        name: newName,
        globalGuidance: _globalGuidanceCtrl.text.trim(),
        fullExample: _pastedRecord ?? _existing?.fullExample ?? '',
        slots: slots,
      );

      await ref.read(contentTemplateRepositoryProvider).insert(ct);
      ref.invalidate(contentTemplatesProvider(widget.structureTemplateId));
      if (mounted) {
        showAppToast(context, '已另存为「$newName」');
        context.pop();
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  bool get _hasAnyContent =>
      _globalGuidanceCtrl.text.trim().isNotEmpty ||
      _fieldCtrls.values.any((c) => c.isFilled);

  Map<String, ExtractedField> _collectCurrentFields() {
    final map = <String, ExtractedField>{};
    for (final entry in _fieldCtrls.entries) {
      final t = entry.value.templateText.text.trim();
      final g = entry.value.guidance.text.trim();
      if (t.isNotEmpty || g.isNotEmpty) {
        map[entry.key] = ExtractedField(text: t, guidance: g);
      }
    }
    return map;
  }

  Future<void> _openRefineSheet() async {
    if (_structure == null || _isAiBusy) return;

    if (!ref.read(llmConfigProvider).isConfigured) {
      showAppToast(context, '请先在设置中配置 API 密钥');
      return;
    }

    final filledSlotKeys = {
      for (final e in _fieldCtrls.entries)
        if (e.value.isFilled) e.key,
    };

    final req = await showModalBottomSheet<_RefineRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _RefineBottomSheet(
        ref: ref,
        slots: _structure!.sortedSlots,
        filledSlotKeys: filledSlotKeys,
        hasExistingContent: _hasAnyContent,
        initialSample: _pastedRecord ?? _existing?.fullExample ?? '',
      ),
    );

    if (req == null || !mounted) return;

    final targetSlots = _structure!.sortedSlots
        .where((s) => req.selectedSlotKeys.contains(s.key))
        .toList();
    if (targetSlots.isEmpty) return;

    setState(() {
      _isAiBusy = true;
      _aiBusyLabel = _hasAnyContent ? 'AI 正在补充细化…' : 'AI 正在拆分提炼…';
    });

    try {
      await ref.read(extractorConfigProvider.notifier).ready;
      if (!mounted) return;

      final result = await ref.read(contentTemplateExtractorProvider).refine(
            slots: targetSlots,
            targetStructureName: _structure!.name,
            currentGlobalGuidance: _globalGuidanceCtrl.text,
            currentFields: _collectCurrentFields(),
            sampleRecord: req.sampleRecord,
            instruction: req.instruction,
            includeExamples: req.includeExamples,
            includeGuidance: req.includeGuidance,
            config: ref.read(extractorConfigProvider),
          );
      if (!mounted) return;

      if (result.isEmpty) {
        showAppToast(context, '未提炼出有效内容，请检查输入材料或指令');
        return;
      }

      _applyAiResult(
        result,
        sampleRecord: req.sampleRecord,
      );
    } catch (e) {
      if (mounted) {
        showAppToast(context, 'AI 处理失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAiBusy = false;
          _aiBusyLabel = '';
        });
      }
    }
  }

  Future<void> _openMigrateSheet({String? preselectedId}) async {
    if (_structure == null || _isAiBusy) return;

    if (!ref.read(llmConfigProvider).isConfigured) {
      showAppToast(context, '请先在设置中配置 API 密钥');
      return;
    }

    final allStructures =
        await ref.read(templateRepositoryProvider).getAll();
    final allContents =
        await ref.read(contentTemplateRepositoryProvider).getAll();

    if (!mounted) return;

    // Exclude current content template if editing
    final candidates = allContents
        .where((c) => c.id != widget.contentTemplateId)
        .toList();

    if (candidates.isEmpty) {
      showAppToast(context, '暂无其他内容模板可供迁移');
      return;
    }

    final filledSlotKeys = {
      for (final e in _fieldCtrls.entries)
        if (e.value.isFilled) e.key,
    };

    final req = await showModalBottomSheet<_MigrateRequest>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _MigrateBottomSheet(
        targetStructure: _structure!,
        filledTargetSlotKeys: filledSlotKeys,
        structures: allStructures,
        contentTemplates: candidates,
        preselectedContentId: preselectedId,
      ),
    );

    if (req == null || !mounted) return;

    final targetSlots = _structure!.sortedSlots
        .where((s) => req.selectedSlotKeys.contains(s.key))
        .toList();
    if (targetSlots.isEmpty) return;

    setState(() {
      _isAiBusy = true;
      _aiBusyLabel = 'AI 正在从「${req.sourceContent.name}」消化迁移…';
    });

    try {
      await ref.read(extractorConfigProvider.notifier).ready;
      if (!mounted) return;

      final result = await ref.read(contentTemplateExtractorProvider).migrate(
            sourceStructureName: req.sourceStructure.name,
            sourceSlots: req.sourceStructure.sortedSlots,
            sourceContent: req.sourceContent,
            targetStructureName: _structure!.name,
            targetSlots: targetSlots,
            instruction: req.instruction,
            includeExamples: req.includeExamples,
            includeGuidance: req.includeGuidance,
            config: ref.read(extractorConfigProvider),
          );
      if (!mounted) return;

      if (result.isEmpty) {
        showAppToast(context, '迁移未生成匹配字段内容');
        return;
      }

      _applyAiResult(
        result,
        suggestedName: req.sourceContent.name,
      );
    } catch (e) {
      if (mounted) {
        showAppToast(context, 'AI 迁移失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isAiBusy = false;
          _aiBusyLabel = '';
        });
      }
    }
  }

  void _pruneStaleSlots() {
    if (_existing == null || _structure == null) return;
    final validKeys = _structure!.slots.map((s) => s.key).toSet();
    final pruned = Map<String, SlotContent>.from(_existing!.slots)
      ..removeWhere((k, _) => !validKeys.contains(k));
    setState(() {
      _existing = _existing!.copyWith(slots: pruned);
    });
    showAppToast(context, '已清理失效字段，点击右上角保存生效');
  }

  Map<String, CatalogDefinition> _catalogMap() {
    final list =
        ref.read(catalogsProvider).valueOrNull ?? const <CatalogDefinition>[];
    return {for (final c in list) c.id: c};
  }

  @override
  Widget build(BuildContext context) {
    if (_structure == null) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Rebuild chips when catalog metadata finishes loading.
    ref.watch(catalogsProvider);

    final st = _structure!;
    final cs = Theme.of(context).colorScheme;
    final validKeys = st.slots.map((s) => s.key).toSet();
    final staleKeys = _existing?.slots.keys
            .where((k) => !validKeys.contains(k))
            .toList() ??
        const [];

    final titleText = widget.isReadOnly
        ? '预览内容模板 · ${_nameCtrl.text}'
        : (_isEditing ? '编辑内容模板' : '新建内容模板');

    final visibleSlots = st.sortedSlots.where((slot) {
      final ctrl = _fieldCtrls[slot.key];
      if (ctrl == null) return false;
      return switch (_filterMode) {
        _SlotFilterMode.all => true,
        _SlotFilterMode.unfilled => !ctrl.isFilled,
        _SlotFilterMode.changes => ctrl.hasPendingDiff,
      };
    }).toList();

    final globalDiff = _globalGuidanceDiff;

    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        actions: [
          if (!widget.isReadOnly &&
              _isEditing &&
              _structure != null &&
              _existing != null)
            IconButton(
              tooltip: '发布到在线模板广场',
              icon: const Icon(Icons.cloud_upload_outlined),
              onPressed: () {
                EngineCExportSheet.showForTemplate(
                  context,
                  _structure!,
                  focusContentTemplate: _existing,
                  publishKind: 'content',
                );
              },
            ),
          if (!widget.isReadOnly && _isEditing)
            TextButton(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: _isSaving ? null : _saveAsCopy,
              child: const Text('另存为'),
            ),
          if (!widget.isReadOnly)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilledButton.tonal(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('保存',
                        style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 28),
        children: [
          // Overview Card: Document structure badge + Template Name + Global Guidance
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: cs.surfaceContainerLow,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: globalDiff != null && globalDiff.hasChange
                    ? Colors.amber.shade700.withValues(alpha: 0.6)
                    : cs.outlineVariant.withValues(alpha: 0.5),
                width: globalDiff != null && globalDiff.hasChange ? 1.4 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Structure Info bar
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schema_outlined,
                              size: 14, color: cs.primary),
                          const SizedBox(width: 5),
                          Text(
                            st.name,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: cs.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _filledFieldCount == st.slots.length &&
                                st.slots.isNotEmpty
                            ? Colors.green.withValues(alpha: 0.12)
                            : cs.surfaceContainerHighest.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '已填 $_filledFieldCount / ${st.slots.length} 字段',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: _filledFieldCount == st.slots.length &&
                                  st.slots.isNotEmpty
                              ? Colors.green.shade700
                              : cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // Template Name
                Row(
                  children: [
                    Text(
                      '模板名称',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Text(
                      ' *',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.red),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                TextField(
                  controller: _nameCtrl,
                  readOnly: widget.isReadOnly,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600),
                  decoration: InputDecoration(
                    hintText: '例如：冠心病、糖尿病、常规模板…',
                    hintStyle: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.normal,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: cs.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
                const SizedBox(height: 12),

                // Global Guidance
                Row(
                  children: [
                    Icon(Icons.tune_rounded,
                        size: 14, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      '全文撰写要求（可选）',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const Spacer(),
                    if (globalDiff != null && globalDiff.hasChange)
                      DiffActionBadge(
                        kind: globalDiff.kind,
                        onAccept: () => setState(() {
                          _beforeGlobalGuidance = null;
                        }),
                        onRevert: () => setState(() {
                          _globalGuidanceCtrl.text = _beforeGlobalGuidance!;
                          _beforeGlobalGuidance = null;
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 5),
                if (globalDiff != null &&
                    globalDiff.kind == DiffChangeKind.modified)
                  InlineBeforePreviewBox(
                    beforeText: globalDiff.beforeText,
                    label: '原全文要求',
                    onRestoreThis: () => setState(() {
                      _globalGuidanceCtrl.text = _beforeGlobalGuidance!;
                      _beforeGlobalGuidance = null;
                    }),
                  ),
                TextField(
                  controller: _globalGuidanceCtrl,
                  readOnly: widget.isReadOnly,
                  maxLines: 3,
                  minLines: 1,
                  style: const TextStyle(fontSize: 13.5),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: '整体口吻、通用缩写规范、严禁编造事项等…',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: cs.onSurfaceVariant.withValues(alpha: 0.5),
                    ),
                    filled: true,
                    fillColor: cs.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide(
                          color: cs.outlineVariant.withValues(alpha: 0.6)),
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // AI Action Bar (Hidden in preview read-only mode)
          if (!widget.isReadOnly) ...[
            if (_isAiBusy)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                  border:
                      Border.all(color: cs.primary.withValues(alpha: 0.25)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: cs.primary,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _aiBusyLabel,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: cs.primary,
                      ),
                    ),
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: FilledButton.tonalIcon(
                        onPressed: _openRefineSheet,
                        icon: const Icon(Icons.auto_awesome, size: 17),
                        label: Text(
                          _hasAnyContent ? 'AI 补充与细化' : 'AI 范文拆分 / 生成',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 4,
                      child: OutlinedButton.icon(
                        onPressed: () => _openMigrateSheet(),
                        icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                        label: const Text(
                          '从其他模板迁移',
                          style: TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],

          // Pending Diff Summary Banner
          if (_totalDiffCount > 0)
            DiffSummaryBanner(
              addedCount: _addedDiffCount,
              modifiedCount: _modifiedDiffCount,
              onAcceptAll: _acceptAllDiffs,
              onRevertAll: _revertAllDiffs,
              filterChangesOnly: _filterMode == _SlotFilterMode.changes,
              onToggleFilterChanges: (onlyChanges) {
                setState(() {
                  _filterMode = onlyChanges
                      ? _SlotFilterMode.changes
                      : _SlotFilterMode.all;
                });
              },
            ),

          // Stale fields alert (if structure has removed fields)
          if (staleKeys.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '文书类型已删除了 ${staleKeys.length} 个旧字段：${staleKeys.join(", ")}',
                      style: const TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                  TextButton(
                    onPressed: _pruneStaleSlots,
                    child: const Text('一键清理',
                        style: TextStyle(color: Colors.red, fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          ],

          // Field list header & filter chips
          Padding(
            padding: const EdgeInsets.only(left: 2, right: 2, bottom: 8),
            child: Row(
              children: [
                Text(
                  '字段内容配置 (${visibleSlots.length}/${st.slots.length})',
                  style: const TextStyle(
                      fontSize: 14.5, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                _buildFilterChip(
                  label: '全部',
                  selected: _filterMode == _SlotFilterMode.all,
                  onTap: () => setState(() => _filterMode = _SlotFilterMode.all),
                ),
                const SizedBox(width: 6),
                _buildFilterChip(
                  label: '未填 (${st.slots.length - _filledFieldCount})',
                  selected: _filterMode == _SlotFilterMode.unfilled,
                  onTap: () => setState(() {
                    _filterMode = _filterMode == _SlotFilterMode.unfilled
                        ? _SlotFilterMode.all
                        : _SlotFilterMode.unfilled;
                  }),
                ),
                if (_totalDiffCount > 0) ...[
                  const SizedBox(width: 6),
                  _buildFilterChip(
                    label: '变更 ($_totalDiffCount)',
                    selected: _filterMode == _SlotFilterMode.changes,
                    highlightColor: cs.primary,
                    onTap: () => setState(() {
                      _filterMode = _filterMode == _SlotFilterMode.changes
                          ? _SlotFilterMode.all
                          : _SlotFilterMode.changes;
                    }),
                  ),
                ],
              ],
            ),
          ),

          if (visibleSlots.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 32),
              alignment: Alignment.center,
              child: Text(
                _filterMode == _SlotFilterMode.unfilled
                    ? '所有字段均已填写内容'
                    : '当前筛选条件下没有字段',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            )
          else
            for (final slot in visibleSlots) _buildFieldCard(slot),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? highlightColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final activeColor = highlightColor ?? cs.primary;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
        decoration: BoxDecoration(
          color: selected
              ? activeColor.withValues(alpha: 0.14)
              : cs.surfaceContainerHighest.withValues(alpha: 0.45),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? activeColor.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? activeColor : cs.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Widget _buildFieldCard(TemplateSlot slot) {
    final ctrl = _fieldCtrls[slot.key];
    if (ctrl == null) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final diffKind = ctrl.overallDiffKind;
    final textDiff = ctrl.textDiff;
    final guidanceDiff = ctrl.guidanceDiff;

    final isGuidanceVisible = ctrl.showGuidance ||
        ctrl.guidance.text.trim().isNotEmpty ||
        (guidanceDiff != null && guidanceDiff.hasChange);

    final borderColor = switch (diffKind) {
      DiffChangeKind.added => Colors.teal.withValues(alpha: 0.55),
      DiffChangeKind.modified => Colors.amber.shade700.withValues(alpha: 0.65),
      DiffChangeKind.none => cs.outlineVariant.withValues(alpha: 0.45),
    };

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: borderColor,
          width: diffKind == DiffChangeKind.none ? 1 : 1.4,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(13, 11, 13, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: Type Chip, Label, Diff badge or "+ 撰写要求"
            Row(
              children: [
                _fieldTypeChip(slot.type),
                const SizedBox(width: 7),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          slot.label,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (slot.required)
                        const Text(
                          ' *',
                          style: TextStyle(
                              color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
                if (diffKind != DiffChangeKind.none) ...[
                  DiffActionBadge(
                    kind: diffKind,
                    onAccept: () => setState(ctrl.acceptDiff),
                    onRevert: () => setState(ctrl.revertDiff),
                  ),
                ] else if (!isGuidanceVisible && !widget.isReadOnly) ...[
                  InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      setState(() {
                        ctrl.showGuidance = true;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 3),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.add_rounded, size: 14, color: cs.primary),
                          const SizedBox(width: 2),
                          Text(
                            '撰写要求',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: cs.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),

            if (slot.options != null && slot.options!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '可选值：${slot.options!.join(" / ")}',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ),

            const SizedBox(height: 8),

            // Section 1: Sample text
            Row(
              children: [
                Text(
                  '示范文本',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                if (diffKind != DiffChangeKind.none &&
                    !isGuidanceVisible &&
                    !widget.isReadOnly)
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => setState(() => ctrl.showGuidance = true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      child: Text(
                        '+ 撰写要求',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: cs.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (textDiff != null && textDiff.kind == DiffChangeKind.modified)
              InlineBeforePreviewBox(
                beforeText: textDiff.beforeText,
                label: '原范文',
                onRestoreThis: () => setState(() {
                  ctrl.templateText.text = ctrl.beforeTemplateText!;
                  ctrl.beforeTemplateText = null;
                }),
              ),
            TextField(
              controller: ctrl.templateText,
              readOnly: widget.isReadOnly,
              maxLines: null,
              minLines: 1,
              style: const TextStyle(fontSize: 13.5, height: 1.4),
              decoration: InputDecoration(
                hintText: '该字段的标准范文示例…',
                hintStyle: TextStyle(
                  fontSize: 12.5,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                ),
                filled: true,
                fillColor: cs.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide:
                      BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
              ),
            ),

            // Section 2: Field-specific Guidance
            if (isGuidanceVisible) ...[
              const SizedBox(height: 9),
              Row(
                children: [
                  Icon(Icons.rule_rounded,
                      size: 13, color: cs.primary.withValues(alpha: 0.85)),
                  const SizedBox(width: 4),
                  Text(
                    '撰写要求',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: cs.primary.withValues(alpha: 0.9),
                    ),
                  ),
                  const Spacer(),
                  if (!widget.isReadOnly)
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: () {
                        setState(() {
                          ctrl.guidance.clear();
                          ctrl.showGuidance = false;
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 1),
                        child: Text(
                          '移除要求',
                          style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              if (guidanceDiff != null &&
                  guidanceDiff.kind == DiffChangeKind.modified)
                InlineBeforePreviewBox(
                  beforeText: guidanceDiff.beforeText,
                  label: '原要求',
                  onRestoreThis: () => setState(() {
                    ctrl.guidance.text = ctrl.beforeGuidance!;
                    ctrl.beforeGuidance = null;
                  }),
                ),
              Builder(
                builder: (fieldContext) {
                  return TextField(
                    controller: ctrl.guidance,
                    readOnly: widget.isReadOnly,
                    maxLines: null,
                    minLines: 1,
                    style: const TextStyle(fontSize: 13, height: 1.4),
                    decoration: InputDecoration(
                      hintText: '字数、句式、必含要素，输入 @ 可引用标准词条库…',
                      hintStyle: TextStyle(
                        fontSize: 12,
                        color: cs.onSurfaceVariant.withValues(alpha: 0.45),
                      ),
                      filled: true,
                      fillColor: cs.primaryContainer.withValues(alpha: 0.12),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: cs.primary.withValues(alpha: 0.25)),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(
                            color: cs.primary.withValues(alpha: 0.22)),
                      ),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 11, vertical: 8),
                    ),
                    onChanged: (text) {
                      final sel = ctrl.guidance.selection;
                      if (sel.start > 0 &&
                          text.isNotEmpty &&
                          text[sel.start - 1] == '@') {
                        final renderBox = fieldContext.findRenderObject()
                            as RenderBox?;
                        final offset = renderBox != null
                            ? renderBox.localToGlobal(
                                Offset(0, renderBox.size.height + 4))
                            : const Offset(40, 200);
                        CatalogMentionPickerOverlay.show(
                          context: context,
                          ref: ref,
                          position: offset,
                          onSelected: (mentions) {
                            ctrl.guidance.insertMentions(mentions);
                            setState(() {});
                          },
                        );
                      }
                    },
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _fieldTypeChip(SlotType type) {
    final label = {
      SlotType.text: '文本',
      SlotType.multiline: '多行',
      SlotType.dropdown: '下拉',
      SlotType.checkbox: '多选',
      SlotType.typedChoice: '键入',
      SlotType.date: '日期',
    }[type]!;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(
              fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.blue)),
    );
  }
}

// ============================================================================
// Shared UI helper: Output Type Toggle + Target Slot Selector
// ============================================================================

class _GenerationScopeSelector extends StatelessWidget {
  final bool includeExamples;
  final bool includeGuidance;
  final ValueChanged<bool> onExamplesChanged;
  final ValueChanged<bool> onGuidanceChanged;
  final List<TemplateSlot> slots;
  final Set<String> filledSlotKeys;
  final Set<String> selectedSlotKeys;
  final ValueChanged<Set<String>> onSelectedSlotsChanged;

  const _GenerationScopeSelector({
    required this.includeExamples,
    required this.includeGuidance,
    required this.onExamplesChanged,
    required this.onGuidanceChanged,
    required this.slots,
    required this.filledSlotKeys,
    required this.selectedSlotKeys,
    required this.onSelectedSlotsChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final unfilledKeys = slots
        .where((s) => !filledSlotKeys.contains(s.key))
        .map((s) => s.key)
        .toSet();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Output content toggles (示范文本 / 撰写要求)
        Row(
          children: [
            const Text(
              '生成内容：',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 6),
            FilterChip(
              label: const Text('示范文本', style: TextStyle(fontSize: 12.5)),
              selected: includeExamples,
              visualDensity: VisualDensity.compact,
              onSelected: onExamplesChanged,
            ),
            const SizedBox(width: 8),
            FilterChip(
              label: const Text('撰写要求', style: TextStyle(fontSize: 12.5)),
              selected: includeGuidance,
              visualDensity: VisualDensity.compact,
              onSelected: onGuidanceChanged,
            ),
          ],
        ),
        const SizedBox(height: 10),

        // 2. Target fields selector
        Row(
          children: [
            Text(
              '填充字段 (${selectedSlotKeys.length}/${slots.length})',
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            _miniActionBtn(
              context,
              label: '全选',
              onTap: () => onSelectedSlotsChanged(
                  slots.map((s) => s.key).toSet()),
            ),
            if (unfilledKeys.isNotEmpty &&
                unfilledKeys.length < slots.length) ...[
              const SizedBox(width: 6),
              _miniActionBtn(
                context,
                label: '仅空白 (${unfilledKeys.length})',
                onTap: () => onSelectedSlotsChanged(unfilledKeys),
              ),
            ],
            const SizedBox(width: 6),
            _miniActionBtn(
              context,
              label: '全不选',
              onTap: () => onSelectedSlotsChanged(<String>{}),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final s in slots)
                FilterChip(
                  label: Text(
                    s.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: selectedSlotKeys.contains(s.key),
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  onSelected: (v) {
                    final next = Set<String>.from(selectedSlotKeys);
                    if (v) {
                      next.add(s.key);
                    } else {
                      next.remove(s.key);
                    }
                    onSelectedSlotsChanged(next);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniActionBtn(
    BuildContext context, {
    required String label,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: cs.primary,
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// Bottom Sheet 1: AI Supplement & Refinement (补充与细化 / 范文拆分)
// ============================================================================

class _RefineRequest {
  final String sampleRecord;
  final String instruction;
  final bool includeExamples;
  final bool includeGuidance;
  final Set<String> selectedSlotKeys;

  const _RefineRequest({
    required this.sampleRecord,
    required this.instruction,
    required this.includeExamples,
    required this.includeGuidance,
    required this.selectedSlotKeys,
  });
}

class _RefineBottomSheet extends StatefulWidget {
  final WidgetRef ref;
  final List<TemplateSlot> slots;
  final Set<String> filledSlotKeys;
  final bool hasExistingContent;
  final String initialSample;

  const _RefineBottomSheet({
    required this.ref,
    required this.slots,
    required this.filledSlotKeys,
    required this.hasExistingContent,
    required this.initialSample,
  });

  @override
  State<_RefineBottomSheet> createState() => _RefineBottomSheetState();
}

class _RefineBottomSheetState extends State<_RefineBottomSheet> {
  late final TextEditingController _sampleCtrl;
  final _instructionCtrl = TextEditingController();
  bool _includeExamples = true;
  bool _includeGuidance = true;
  late Set<String> _selectedSlotKeys;
  bool _isOcrRunning = false;
  String _ocrStatus = '';

  static const _quickInstructions = [
    '根据参考范本提炼各字段的撰写要求与句式规范',
    '在现有要求基础上细化必填要素与表述要求',
    '精简字数要求，规范专业术语与标点格式',
    '补全尚未填写的空白字段',
  ];

  @override
  void initState() {
    super.initState();
    _sampleCtrl = TextEditingController();
    _selectedSlotKeys = widget.slots.map((s) => s.key).toSet();
  }

  @override
  void dispose() {
    _sampleCtrl.dispose();
    _instructionCtrl.dispose();
    super.dispose();
  }

  Future<void> _ocrFromImages(List<String> paths) async {
    if (paths.isEmpty) return;

    final ocrConfig = widget.ref.read(ocrConfigProvider);
    if (!ocrConfig.isConfigured) {
      if (mounted) {
        showAppToast(context, '请先在「设置」中配置 OCR 接口与 Token');
      }
      return;
    }

    setState(() {
      _isOcrRunning = true;
      _ocrStatus = '正在识别 ${paths.length} 页材料文字...';
    });

    try {
      final text =
          await widget.ref.read(apiServiceProvider).extractTextFromImages(paths);
      if (!mounted) return;

      var clean = text;
      const headers = [
        '结果来自 PaddleOCR-VL\n\n',
        '结果来自 智谱 GLM-OCR\n\n',
        '结果来自 面壁智能文档解析\n\n',
        '结果来自 MinerU\n\n',
        '结果来自 Apple Vision\n\n',
        '结果来自 PaddleOCR 本地\n\n',
      ];
      for (final header in headers) {
        if (clean.startsWith(header)) {
          clean = clean.substring(header.length);
          break;
        }
      }

      final existing = _sampleCtrl.text.trim();
      setState(() {
        _sampleCtrl.text = existing.isEmpty ? clean : '$existing\n\n$clean';
      });
    } catch (e) {
      if (mounted) {
        showAppToast(context, 'OCR 识别失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isOcrRunning = false;
          _ocrStatus = '';
        });
      }
    }
  }

  Future<void> _takePhotos() async {
    final pages = <String>[];
    bool continueShooting = true;

    while (continueShooting) {
      final photoPath =
          await AppImagePicker.pickSingleImage(source: ImageSource.camera);
      if (photoPath == null) break;
      pages.add(photoPath);

      if (!mounted) break;
      continueShooting = await showModalBottomSheet<bool>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('当前材料：第 ${pages.length} 页已拍',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('继续拍下一页'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('完成拍照并识别'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ) ??
          false;
    }

    if (pages.isNotEmpty) {
      await _ocrFromImages(pages);
    }
  }

  Future<void> _pickFromGallery() async {
    final imagePaths = await AppImagePicker.pickMultiImages();
    if (imagePaths.isEmpty) return;
    await _ocrFromImages(imagePaths);
  }

  void _submit() {
    if (!_includeExamples && !_includeGuidance) {
      showAppToast(context, '请至少勾选「示范文本」或「撰写要求」');
      return;
    }
    if (_selectedSlotKeys.isEmpty) {
      showAppToast(context, '请至少选择一个需要填充的字段');
      return;
    }
    final sample = _sampleCtrl.text.trim();
    final inst = _instructionCtrl.text.trim();
    if (sample.isEmpty && inst.isEmpty) {
      showAppToast(context, '请提供参考文书文本或输入细化指令');
      return;
    }
    Navigator.pop(
      context,
      _RefineRequest(
        sampleRecord: sample,
        instruction: inst,
        includeExamples: _includeExamples,
        includeGuidance: _includeGuidance,
        selectedSlotKeys: _selectedSlotKeys,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Row
            Row(
              children: [
                Icon(Icons.auto_awesome, color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Text(
                  widget.hasExistingContent ? 'AI 补充与细化' : 'AI 范文拆分与提炼',
                  style: const TextStyle(
                      fontSize: 16.5, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),

            const SizedBox(height: 8),
            _GenerationScopeSelector(
              includeExamples: _includeExamples,
              includeGuidance: _includeGuidance,
              onExamplesChanged: (v) => setState(() => _includeExamples = v),
              onGuidanceChanged: (v) => setState(() => _includeGuidance = v),
              slots: widget.slots,
              filledSlotKeys: widget.filledSlotKeys,
              selectedSlotKeys: _selectedSlotKeys,
              onSelectedSlotsChanged: (next) =>
                  setState(() => _selectedSlotKeys = next),
            ),

            const SizedBox(height: 14),

            // Section 1: Sample Record Input
            Row(
              children: [
                const Text(
                  '参考文书材料（可选）',
                  style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(width: 8),
                const Text(
                  '请先去除姓名等隐私信息',
                  style: TextStyle(fontSize: 11.5, color: Colors.red),
                ),
                const Spacer(),
                if (widget.initialSample.trim().isNotEmpty &&
                    _sampleCtrl.text.trim().isEmpty)
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                    ),
                    onPressed: () {
                      setState(() {
                        _sampleCtrl.text = widget.initialSample;
                      });
                    },
                    child:
                        const Text('载入上次范文', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                ActionChip(
                  avatar: const Icon(Icons.camera_alt_outlined, size: 14),
                  label:
                      const Text('拍照识别 (OCR)', style: TextStyle(fontSize: 12)),
                  onPressed: _isOcrRunning ? null : _takePhotos,
                ),
                const SizedBox(width: 8),
                ActionChip(
                  avatar: const Icon(Icons.photo_library_outlined, size: 14),
                  label:
                      const Text('相册选图 (OCR)', style: TextStyle(fontSize: 12)),
                  onPressed: _isOcrRunning ? null : _pickFromGallery,
                ),
              ],
            ),
            if (_isOcrRunning) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_ocrStatus,
                        style: const TextStyle(
                            fontSize: 12, color: Colors.blueGrey)),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _sampleCtrl,
              maxLines: 5,
              minLines: 3,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '粘贴完整或局部的示例文本，或用上方 OCR 识别…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                isDense: true,
              ),
            ),

            const SizedBox(height: 12),

            // Section 2: Refinement instruction
            const Text(
              '补充细化指令（可选）',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final chip in _quickInstructions)
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      final cur = _instructionCtrl.text.trim();
                      setState(() {
                        _instructionCtrl.text =
                            cur.isEmpty ? chip : '$cur；$chip';
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 9, vertical: 4),
                      decoration: BoxDecoration(
                        color:
                            cs.surfaceContainerHighest.withValues(alpha: 0.55),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '+ $chip',
                        style: TextStyle(
                            fontSize: 11.5, color: cs.onSurfaceVariant),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _instructionCtrl,
              maxLines: 2,
              minLines: 1,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText: '例如：重点细化现病史和查体的格式要求，补充常见阴性体征…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                isDense: true,
              ),
            ),

            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _isOcrRunning ? null : _submit,
                icon: const Icon(Icons.auto_awesome, size: 17),
                label: Text(
                    widget.hasExistingContent ? '开始补充细化' : '开始拆分生成'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Bottom Sheet 2: Cross-Template Migration (从其他内容模板迁移)
// ============================================================================

class _MigrateRequest {
  final Template sourceStructure;
  final ContentTemplate sourceContent;
  final bool includeExamples;
  final bool includeGuidance;
  final Set<String> selectedSlotKeys;
  final String instruction;

  const _MigrateRequest({
    required this.sourceStructure,
    required this.sourceContent,
    required this.includeExamples,
    required this.includeGuidance,
    required this.selectedSlotKeys,
    required this.instruction,
  });
}

class _MigrateBottomSheet extends StatefulWidget {
  final Template targetStructure;
  final Set<String> filledTargetSlotKeys;
  final List<Template> structures;
  final List<ContentTemplate> contentTemplates;
  final String? preselectedContentId;

  const _MigrateBottomSheet({
    required this.targetStructure,
    required this.filledTargetSlotKeys,
    required this.structures,
    required this.contentTemplates,
    this.preselectedContentId,
  });

  @override
  State<_MigrateBottomSheet> createState() => _MigrateBottomSheetState();
}

class _MigrateBottomSheetState extends State<_MigrateBottomSheet> {
  String? _selectedContentId;
  bool _includeExamples = true;
  bool _includeGuidance = true;
  late Set<String> _selectedSlotKeys;
  final _instructionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedSlotKeys =
        widget.targetStructure.sortedSlots.map((s) => s.key).toSet();
    if (widget.preselectedContentId != null &&
        widget.contentTemplates
            .any((c) => c.id == widget.preselectedContentId)) {
      _selectedContentId = widget.preselectedContentId;
    } else if (widget.contentTemplates.isNotEmpty) {
      _selectedContentId = widget.contentTemplates.first.id;
    }
  }

  @override
  void dispose() {
    _instructionCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    if (_selectedContentId == null) {
      showAppToast(context, '请先选择源内容模板');
      return;
    }
    if (!_includeExamples && !_includeGuidance) {
      showAppToast(context, '请至少勾选「示范文本」或「撰写要求」');
      return;
    }
    if (_selectedSlotKeys.isEmpty) {
      showAppToast(context, '请至少选择一个需要填充的字段');
      return;
    }
    final ct = widget.contentTemplates
        .firstWhere((c) => c.id == _selectedContentId);
    final st = widget.structures.firstWhere(
      (s) => s.id == ct.structureTemplateId,
      orElse: () => widget.targetStructure,
    );

    Navigator.pop(
      context,
      _MigrateRequest(
        sourceStructure: st,
        sourceContent: ct,
        includeExamples: _includeExamples,
        includeGuidance: _includeGuidance,
        selectedSlotKeys: _selectedSlotKeys,
        instruction: _instructionCtrl.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final structureMap = {
      for (final s in widget.structures) s.id: s,
    };

    // Group content templates by structure
    final grouped = <String, List<ContentTemplate>>{};
    for (final ct in widget.contentTemplates) {
      grouped.putIfAbsent(ct.structureTemplateId, () => []).add(ct);
    }

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.swap_horiz_rounded, color: cs.primary, size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '迁移到「${widget.targetStructure.name}」',
                    style: const TextStyle(
                        fontSize: 16.5, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
            const SizedBox(height: 10),

            const Text(
              '选择源内容模板',
              style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 6),

            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(
                      color: cs.outlineVariant.withValues(alpha: 0.6)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final entry in grouped.entries) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        color:
                            cs.surfaceContainerHighest.withValues(alpha: 0.4),
                        child: Text(
                          structureMap[entry.key]?.name ?? '未知文书类型',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: cs.primary,
                          ),
                        ),
                      ),
                      for (final ct in entry.value)
                        ListTile(
                          dense: true,
                          selected: _selectedContentId == ct.id,
                          leading: Icon(
                            _selectedContentId == ct.id
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                            size: 20,
                            color: _selectedContentId == ct.id
                                ? cs.primary
                                : cs.onSurfaceVariant,
                          ),
                          onTap: () =>
                              setState(() => _selectedContentId = ct.id),
                          title: Text(
                            ct.name,
                            style: const TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '已填 ${ct.filledSlotCount} 个字段${ct.globalGuidance.trim().isNotEmpty ? " · 含全文要求" : ""}',
                            style: TextStyle(
                                fontSize: 11.5, color: cs.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 12),

            _GenerationScopeSelector(
              includeExamples: _includeExamples,
              includeGuidance: _includeGuidance,
              onExamplesChanged: (v) => setState(() => _includeExamples = v),
              onGuidanceChanged: (v) => setState(() => _includeGuidance = v),
              slots: widget.targetStructure.sortedSlots,
              filledSlotKeys: widget.filledTargetSlotKeys,
              selectedSlotKeys: _selectedSlotKeys,
              onSelectedSlotsChanged: (next) =>
                  setState(() => _selectedSlotKeys = next),
            ),

            const SizedBox(height: 12),
            TextField(
              controller: _instructionCtrl,
              maxLines: 2,
              minLines: 1,
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                labelText: '附加迁移说明（可选）',
                hintText: '例如：将入院时的待查口吻改为出院小结的总结口吻…',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                isDense: true,
              ),
            ),

            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.swap_horiz_rounded, size: 18),
                label: const Text('开始智能迁移'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
