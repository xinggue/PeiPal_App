import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:peipal/presentation/widgets/common/app_sheet.dart';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/generation/generation_log.dart';
import '../../../domain/generation/generation_result.dart';
import '../../../domain/generation/record_validator.dart';
import '../../../data/services/ble/character_sanitizer.dart';
import '../../../domain/models/favorite_diagnosis.dart';
import '../../../domain/models/message.dart';
import '../../../domain/models/patient.dart';
import '../../../domain/models/pipeline_graph.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import '../../widgets/diagnosis/his_diagnosis_picker.dart';
import '../../widgets/chat/char_replacement_confirm_dialog.dart';
import '../../widgets/chat/generation_fields_and_requirements.dart';
import 'typing_send_sheet.dart';
import 'generation_log_page.dart';
import 'generation_run_page.dart';

class RecordReviewPage extends ConsumerStatefulWidget {
  final String patientId;
  final String messageId;

  const RecordReviewPage({
    super.key,
    required this.patientId,
    required this.messageId,
  });

  @override
  ConsumerState<RecordReviewPage> createState() => _RecordReviewPageState();
}

class _RecordReviewPageState extends ConsumerState<RecordReviewPage> {
  final Map<String, TextEditingController> _controllers = {};
  Map<String, dynamic> _originalRawJson = {};
  List<TemplateSlot> _effectiveSlots = [];
  Set<String> _effectiveSlotKeySet = {};
  String _effectiveTemplateName = '';
  bool _isTemplateMissing = false;

  // 缓存的校验与特殊字符扫描结果，避免每次 build（如软键盘动画帧）重复全量计算
  Map<String, FieldIssue> _cachedIssueBySlot = {};
  Map<String, Set<String>> _cachedUnsupportedBySlot = {};
  Set<String> _cachedAllUnsupported = {};
  int _cachedNotInOptionsCount = 0;

  Message? _message;
  Patient? _patient;
  Template? _template;
  GenerationLog? _genLog;

  bool _isLoading = true;
  bool _isSaving = false;
  Timer? _debounceTimer;

  void _recomputeValidationCache() {
    final values = _collectValues();
    final issues = RecordValidator.validateAll(
      slots: _effectiveSlots,
      values: values,
    );
    final issueMap = <String, FieldIssue>{
      for (final issue in issues) issue.key: issue,
    };
    final unsupportedBySlot = <String, Set<String>>{};
    final allUnsupported = <String>{};
    for (final entry in values.entries) {
      final chars = CharacterSanitizer.findUnsupportedCharacters(entry.value);
      if (chars.isNotEmpty) {
        unsupportedBySlot[entry.key] = chars;
        allUnsupported.addAll(chars);
      }
    }

    _cachedIssueBySlot = issueMap;
    _cachedUnsupportedBySlot = unsupportedBySlot;
    _cachedAllUnsupported = allUnsupported;
    _cachedNotInOptionsCount =
        issues.where((i) => i.type == FieldIssueType.notInOptions).length;
  }

  void _onFieldChanged() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) {
        setState(_recomputeValidationCache);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final msgRepo = ref.read(messageRepositoryProvider);
    final tmplRepo = ref.read(templateRepositoryProvider);
    final patientRepo = ref.read(patientRepositoryProvider);
    final logRepo = ref.read(generationLogRepositoryProvider);

    final msg = await msgRepo.getById(widget.messageId);
    final patient = await patientRepo.getById(widget.patientId);
    final log = await logRepo.getByMessageId(widget.messageId);
    Template? template;

    if (msg != null && msg.templateId != null) {
      template = await tmplRepo.getById(msg.templateId!);
    }

    if (msg != null && mounted) {
      Map<String, dynamic> rawJson = {};
      try {
        if (msg.recordJson != null && msg.recordJson!.isNotEmpty) {
          rawJson = jsonDecode(msg.recordJson!) as Map<String, dynamic>;
        }
      } catch (_) {}
      _originalRawJson = Map.from(rawJson);

      List<TemplateSlot> slots = [];
      String tmplName = '';

      if (template != null) {
        slots = template.sortedSlots;
        tmplName = template.name;
        _isTemplateMissing = false;
      } else if (msg.recordMeta != null && msg.recordMeta!.slotSnapshots.isNotEmpty) {
        // 模板被删自愈：利用快照重建槽位
        slots = msg.recordMeta!.slotSnapshots
            .map((s) => TemplateSlot.fromJson(s))
            .toList();
        tmplName = msg.recordMeta!.templateName ?? '历史文书';
        _isTemplateMissing = true;
      } else {
        // 兜底：从现有 JSON 键名反推槽位
        slots = rawJson.keys
            .map((k) => TemplateSlot(key: k, label: k, type: SlotType.multiline))
            .toList();
        tmplName = '自定义文书';
        _isTemplateMissing = true;
      }

      _effectiveSlots = slots;
      _effectiveSlotKeySet = slots.map((s) => s.key).toSet();
      _effectiveTemplateName = tmplName;

      for (final slot in slots) {
        final val = rawJson[slot.key]?.toString() ?? slot.defaultValue ?? '';
        final ctrl = TextEditingController(text: val);
        ctrl.addListener(_onFieldChanged); // 驱动实时校验与标红（带180ms防抖）
        _controllers[slot.key] = ctrl;
      }

      // 处理不在模板槽位里的孤儿 key（保留在界面可编辑，绝不静默丢失）
      for (final k in rawJson.keys) {
        if (!_controllers.containsKey(k)) {
          final ctrl = TextEditingController(text: rawJson[k]?.toString() ?? '');
          ctrl.addListener(_onFieldChanged);
          _controllers[k] = ctrl;
        }
      }

      _recomputeValidationCache();

      _template = template;

      setState(() {
        _message = msg;
        _patient = patient;
        _genLog = log;
        _isLoading = false;
      });
    } else if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, String> _collectValues() {
    // 优先合并原有字段，再用输入框覆写，确保非模板字段 100% 被保留
    final map = <String, String>{};
    for (final e in _originalRawJson.entries) {
      map[e.key] = e.value?.toString() ?? '';
    }
    for (final e in _controllers.entries) {
      map[e.key] = e.value.text.trim();
    }
    return map;
  }

  Future<void> _save({bool showFeedback = true}) async {
    if (_message == null || _isSaving) return;
    setState(() => _isSaving = true);

    try {
      final updatedMap = _collectValues();
      final updatedJson = jsonEncode(updatedMap);

      // 同步更新 activeSlotKeys，将手工填写了内容的槽位也标为激活
      final currentActives = _message!.recordMeta?.activeSlotKeys.toSet() ?? <String>{};
      for (final e in updatedMap.entries) {
        if (e.value.trim().isNotEmpty) {
          currentActives.add(e.key);
        }
      }
      final updatedMeta = _message!.recordMeta?.copyWith(
        activeSlotKeys: currentActives.toList(),
      );

      final updatedMsg = _message!.copyWith(
        recordJson: updatedJson,
        recordMeta: updatedMeta,
      );

      await ref.read(messageRepositoryProvider).update(updatedMsg);
      ref.invalidate(messagesProvider(widget.patientId));
      ref.invalidate(lastMessageProvider(widget.patientId));

      if (mounted) {
        setState(() {
          _message = updatedMsg;
          _originalRawJson = Map.from(updatedMap);
          _recomputeValidationCache();
        });
      }

      if (showFeedback && mounted) {
        showAppToast(context, '已保存修改');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveAndOpenSendSheet({required bool isQrMode}) async {
    if (_message == null || _isSaving) return;
    await _save(showFeedback: false);
    if (!mounted || _message == null) return;
    TypingSendSheet.show(
      context: context,
      message: _message!,
      isQrMode: isQrMode,
    );
  }

  Future<void> _openRewriteSheet() async {
    if (_message == null || _patient == null || _isSaving) return;
    if (_effectiveSlots.isEmpty) {
      _snack('当前文书没有可重写的字段');
      return;
    }

    final instructionsCtrl = TextEditingController();
    final selectedKeys = <String>{..._effectiveSlots.map((s) => s.key)};

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final canStart = selectedKeys.isNotEmpty &&
              instructionsCtrl.text.trim().isNotEmpty;

          return Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            clipBehavior: Clip.antiAlias,
            backgroundColor: Theme.of(ctx).colorScheme.surface,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: 620,
                maxHeight: MediaQuery.of(ctx).size.height * 0.82,
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 8, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.auto_fix_high,
                            size: 20, color: Colors.teal),
                        const SizedBox(width: 8),
                        const Text('重写文书',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close, size: 20),
                          visualDensity: VisualDensity.compact,
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '在原文书基础上修改润色，未勾选的字段将保持原样。重写结果会保存为一份新文书，原稿保留。',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            height: 1.35),
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: GenerationFieldsAndRequirements(
                      title: '重写字段',
                      instructionsHint: '重写要求，例如：更简洁、突出过敏史、按时间顺序润色现病史…',
                      slots: _effectiveSlots,
                      selectedKeys: selectedKeys,
                      instructionsController: instructionsCtrl,
                      onSelectionChanged: (keys) => setSheetState(() {
                        selectedKeys
                          ..clear()
                          ..addAll(keys);
                      }),
                      onInstructionsChanged: () => setSheetState(() {}),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        icon: const Icon(Icons.auto_awesome, size: 18),
                        label: const Text('开始重写',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed:
                            canStart ? () => Navigator.pop(ctx, true) : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    final instruction = instructionsCtrl.text.trim();
    instructionsCtrl.dispose();
    if (confirmed == true && mounted) {
      await _runRewrite(selectedKeys, instruction);
    }
  }

  Future<void> _runRewrite(Set<String> selectedKeys, String instruction) async {
    if (_patient == null || instruction.isEmpty) return;

    if (!ref.read(llmConfigProvider).isConfigured) {
      _snack('请先在设置中配置大模型接口');
      return;
    }

    final messages =
        await ref.read(messageRepositoryProvider).getAllChronological(widget.patientId);
    if (!mounted) return;

    final materials =
        messages.where((m) => m.id != widget.messageId).toList();
    final favs =
        await ref.read(favoriteDiagnosisRepositoryProvider).getAll();
    if (!mounted) return;

    final ctId = _message?.recordMeta?.contentTemplateId;
    final contentTemplate = (ctId == null || ctId.isEmpty)
        ? null
        : await ref.read(contentTemplateRepositoryProvider).getById(ctId);
    if (!mounted) return;

    // 空管线的临时模板会让普通生成回落为单批次，从而只发起一次 LLM 调用。
    final rewriteTemplate = Template(
      id: _template?.id ?? _message?.templateId,
      name: _effectiveTemplateName,
      version: _template?.version ?? '1.0',
      slots: _effectiveSlots,
      pipeline: PipelineGraph(),
      typingProfiles: _template?.typingProfiles,
      createdAt: _template?.createdAt,
      updatedAt: _template?.updatedAt,
    );

    final currentValues = _collectValues();
    final currentDoc = const JsonEncoder.withIndent('  ').convert({
      for (final slot in _effectiveSlots)
        slot.key: currentValues[slot.key] ?? '',
    });

    final selectedLabels = _effectiveSlots
        .where((s) => selectedKeys.contains(s.key))
        .map((s) => '- ${s.key}（${s.label}）')
        .join('\n');

    final extraInstructions =
        '【当前待重写文书（完整原文，作为改写基础）】：\n$currentDoc\n\n'
        '【本次需要重写/润色的字段】：\n$selectedLabels\n\n'
        '【重写要求（最高优先级）】：\n$instruction\n\n'
        '除上述指定字段外，其余字段必须原样照抄，不得改动。';

    await ref.read(llmPromptConfigProvider.notifier).ready;
    if (!mounted) return;

    final catalogList = await ref.read(catalogsProvider.future);
    if (!mounted) return;
    final catalogsById = {for (final c in catalogList) c.id: c};

    final plan = ref.read(generationEngineProvider).buildPlan(
          template: rewriteTemplate,
          contentTemplate: contentTemplate,
          patient: _patient!,
          chatMessages: materials,
          favoriteDiagnoses: favs,
          catalogs: catalogsById,
          promptConfig: ref.read(llmPromptConfigProvider),
          allMaterials: _message?.recordMeta?.allMaterials ?? true,
          extraInstructions: extraInstructions,
        );

    final newMsgId = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => GenerationRunPage(
          plan: plan,
          patientId: widget.patientId,
        ),
      ),
    );

    if (newMsgId != null && mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => RecordReviewPage(
            patientId: widget.patientId,
            messageId: newMsgId,
          ),
        ),
      );
    }
  }

  void _snack(String msg) {
    if (mounted) {
      showAppToast(context, msg);
    }
  }

  void _openLog() {
    if (_genLog == null) {
      _snack('暂无此份文书的生成日志');
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => GenerationLogPage(log: _genLog!)),
    );
  }

  /// 构建 Markdown 行内代码块风格 (Code Badge) 的字符微卡片
  Widget _buildCodeChip(String char, {bool isLarge = false}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: isLarge ? 6 : 4, vertical: isLarge ? 2 : 1),
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9), // 优雅的 slate-100 代码块浅灰底纹
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: const Color(0xFFCBD5E1), width: 0.8), // slate-300 细线边框
      ),
      child: Text(
        char,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: isLarge ? 13 : 11,
          fontWeight: FontWeight.bold,
          color: const Color(0xFFB91C1C), // 醒目的暗红/深色代码字符
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_message == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('审阅文书')),
        body: const Center(child: Text('未能加载文书数据')),
      );
    }

    final favs = ref.watch(favoriteDiagnosesProvider).valueOrNull ?? [];
    final notInOptionsCount = _cachedNotInOptionsCount;
    final allUnsupportedChars = _cachedAllUnsupported;

    return Scaffold(
      appBar: AppBar(
        title: Text('审阅文书 · $_effectiveTemplateName'),
        actions: [
          if (_genLog != null)
            TextButton.icon(
              icon: const Icon(Icons.receipt_long_outlined, size: 18),
              label: const Text('生成日志'),
              onPressed: _openLog,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 80),
        children: [
          // Template missing banner
          if (_isTemplateMissing)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.healing_outlined, size: 18, color: Colors.brown),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '原模板已变更，当前按历史字段显示。',
                      style: TextStyle(fontSize: 12, color: Colors.brown),
                    ),
                  ),
                ],
              ),
            ),

          // Partial generation warning banner
          if (_message?.recordMeta?.isPartial == true)
            Container(
              padding: const EdgeInsets.all(10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded,
                      size: 18, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '此文书为部分生成保存。\n未完成字段: ${_message!.recordMeta!.missingSlotKeys.join("、")}',
                      style: const TextStyle(fontSize: 12, color: Colors.deepOrange),
                    ),
                  ),
                ],
              ),
            ),

          // Option Mismatch Summary Warning
          if (notInOptionsCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, size: 16, color: Colors.red),
                  const SizedBox(width: 6),
                  Text(
                    '共有 $notInOptionsCount 个字段内容与预设选项不符，已标红提醒',
                    style: const TextStyle(
                        fontSize: 12, color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),

          // Unsupported Characters Alert & One-Click Converter Banner
          if (allUnsupportedChars.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.shade600),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(Icons.spellcheck, size: 20, color: Colors.deepOrange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              '检测到包含 ${allUnsupportedChars.length} 种特殊字符：',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: Colors.brown.shade900,
                              ),
                            ),
                            for (final c in allUnsupportedChars) _buildCodeChip(c, isLarge: true),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          allUnsupportedChars.any((c) => c == '{' || c == '}')
                              ? '含英文花括号 { } 或特殊字符，建议先一键转换为中文全角 ｛ ｝ 防键盘指令冲突。'
                              : '键盘硬件可能会将无法识别的字符跳过或丢失，建议先一键转换。',
                          style: TextStyle(fontSize: 11, color: Colors.brown.shade700),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    ),
                    onPressed: () async {
                                            final confirmedReplacements = await CharReplacementConfirmDialog.show(
                        context,
                        unsupportedChars: allUnsupportedChars,
                      );
                      if (confirmedReplacements == null || !mounted) return;

                      for (final ctrl in _controllers.values) {
                        ctrl.text = CharacterSanitizer.applyReplacements(
                          ctrl.text,
                          confirmedReplacements,
                        );
                      }
                      setState(_recomputeValidationCache);
                      if (mounted) {
                        showAppToast(context, '已完成字符转换并更新规则库');
                      }
                    },
                    child: const Text('一键转换', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                  ),
                ],
              ),
            ),

          // Patient info banner
          if (_patient != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .primaryContainer
                    .withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_shared_outlined, size: 18, color: Colors.blue),
                  const SizedBox(width: 6),
                  Text(
                    _patient!.displayMeta.isEmpty
                        ? _patient!.name
                        : '${_patient!.name} (${_patient!.displayMeta})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  if (_patient!.medicalRecordNumber != null) ...[
                    const Spacer(),
                    Text('编号: ${_patient!.medicalRecordNumber}',
                        style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ],
              ),
            ),

          // Template fields list
          for (final slot in _effectiveSlots)
            _buildFieldCard(slot, favs),

          // Extra orphan keys (not in template)
          for (final entry in _controllers.entries)
            if (!_effectiveSlotKeySet.contains(entry.key))
              _buildOrphanFieldCard(entry.key, entry.value),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            border: Border(
              top: BorderSide(
                color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
              ),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('重写'),
                      onPressed: _isSaving ? null : _openRewriteSheet,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save_outlined, size: 18),
                      label: const Text('保存'),
                      onPressed:
                          _isSaving ? null : () => _save(showFeedback: true),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.qr_code_2, size: 18),
                      label: const Text(
                        '保存并二维码发送',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: _isSaving
                          ? null
                          : () => _saveAndOpenSendSheet(isQrMode: true),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      icon: const Icon(Icons.bluetooth, size: 18),
                      label: const Text(
                        '保存并蓝牙发送',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onPressed: _isSaving
                          ? null
                          : () => _saveAndOpenSendSheet(isQrMode: false),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFieldCard(
    TemplateSlot slot,
    List<FavoriteDiagnosis> favs,
  ) {
    final ctrl = _controllers[slot.key];
    if (ctrl == null) return const SizedBox.shrink();

    final catalogId = slot.catalogType?.trim();
    final effectiveCatalogId =
        catalogId != null && catalogId.isNotEmpty
            ? catalogId
            : (slot.label.contains('诊断') ? 'diagnosis' : null);
    final hasCatalogBinding = effectiveCatalogId != null;
    final fieldFavs = hasCatalogBinding
        ? favs.where((f) => f.catalogType == effectiveCatalogId).toList()
        : const <FavoriteDiagnosis>[];
    final issue = _cachedIssueBySlot[slot.key];

    final isOptionMismatch = issue?.type == FieldIssueType.notInOptions;
    final isMissingRequired = issue?.type == FieldIssueType.missingRequired;
    final unsupportedInSlot = _cachedUnsupportedBySlot[slot.key] ?? const <String>{};

    // AI 原始值与当前值对比
    final aiOrig = _message?.recordMeta?.aiOriginalValues[slot.key];
    final isModifiedFromAi =
        aiOrig != null && aiOrig.trim() != ctrl.text.trim();
    final isActive = _message?.recordMeta?.activeSlotKeys.contains(slot.key) ?? true;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: isOptionMismatch
          ? Colors.red.withValues(alpha: 0.04)
          : (unsupportedInSlot.isNotEmpty
              ? Colors.amber.withValues(alpha: 0.04)
              : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isOptionMismatch
              ? Colors.red.withValues(alpha: 0.6)
              : (unsupportedInSlot.isNotEmpty
                  ? Colors.amber.shade700
                  : (isMissingRequired
                      ? Colors.orange.withValues(alpha: 0.5)
                      : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2))),
          width: (isOptionMismatch || unsupportedInSlot.isNotEmpty) ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  slot.label,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isOptionMismatch ? Colors.red : null,
                  ),
                ),
                if (slot.required)
                  const Text(' *',
                      style: TextStyle(
                          color: Colors.red, fontWeight: FontWeight.bold)),
                const SizedBox(width: 6),
                Text(slot.key,
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                if (isModifiedFromAi) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text('已编辑',
                        style: TextStyle(fontSize: 9, color: Colors.blue)),
                  ),
                ],
                if (!isActive) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: const Text('未选/未生成',
                        style: TextStyle(fontSize: 9, color: Colors.grey)),
                  ),
                ],
                const Spacer(),
                // 右上角呈现该字段所含的特殊字符行内代码块标签
                if (unsupportedInSlot.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          '含特殊字符：',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.deepOrange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        for (final c in unsupportedInSlot) _buildCodeChip(c),
                      ],
                    ),
                  ),
                if (isModifiedFromAi)
                  IconButton(
                    icon: const Icon(Icons.restore, size: 16, color: Colors.blueGrey),
                    tooltip: '还原 AI 原始生成内容',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      ctrl.text = aiOrig;
                      setState(_recomputeValidationCache);
                    },
                  ),
                if (hasCatalogBinding)
                  IconButton(
                    icon: const Icon(Icons.search, size: 18, color: Colors.blue),
                    tooltip: '检索词库追加',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _openCatalogSearchSheet(
                        ctrl, effectiveCatalogId),
                  ),
              ],
            ),

            // 标红或必填告警提示
            if (issue != null)
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 6),
                child: Row(
                  children: [
                    Icon(
                      isOptionMismatch
                          ? Icons.warning_amber_rounded
                          : Icons.info_outline,
                      size: 13,
                      color: isOptionMismatch ? Colors.red : Colors.orange,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        issue.message,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isOptionMismatch ? Colors.red : Colors.orange[800],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // 预设选项快捷修正 Chips（当有选项且不符合时，供医生一键选入合规值）
            if (slot.options != null && slot.options!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2, bottom: 8),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final opt in slot.options!)
                      ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(opt, style: const TextStyle(fontSize: 11)),
                        onPressed: () {
                          if (slot.type == SlotType.checkbox) {
                            final cur = ctrl.text.trim();
                            if (cur.isEmpty) {
                              ctrl.text = opt;
                            } else if (!cur.contains(opt)) {
                              ctrl.text = '$cur，$opt';
                            }
                          } else {
                            ctrl.text = opt;
                          }
                          setState(_recomputeValidationCache);
                        },
                      ),
                  ],
                ),
              ),

            // 常用词条 Chips
            if (hasCatalogBinding && fieldFavs.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      const Icon(Icons.star, size: 13, color: Colors.amber),
                      const SizedBox(width: 4),
                      const Text('常用：',
                          style: TextStyle(fontSize: 11, color: Colors.blueGrey)),
                      for (final f in favs)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            visualDensity: VisualDensity.compact,
                            label: Text(f.name, style: const TextStyle(fontSize: 11)),
                            onPressed: () {
                              final text = ctrl.text.trim();
                              final addition = f.code.isNotEmpty
                                  ? '${f.name} (${f.code})'
                                  : f.name;
                              if (text.isEmpty) {
                                ctrl.text = addition;
                              } else {
                                ctrl.text = '$text\n$addition';
                              }
                              setState(_recomputeValidationCache);
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // Field text input
            TextField(
              controller: ctrl,
              maxLines: null,
              minLines: slot.type == SlotType.multiline ? 3 : 1,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderSide: isOptionMismatch
                      ? const BorderSide(color: Colors.red, width: 1.5)
                      : const BorderSide(),
                ),
                isDense: true,
                hintText: '输入${slot.label}...',
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrphanFieldCard(String key, TextEditingController ctrl) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: Colors.grey.withValues(alpha: 0.1),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: Colors.grey.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  key,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(width: 6),
                const Text('(其他字段)',
                    style: TextStyle(fontSize: 10, color: Colors.blueGrey)),
              ],
            ),
            const SizedBox(height: 6),
            TextField(
              controller: ctrl,
              maxLines: null,
              minLines: 1,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openCatalogSearchSheet(
      TextEditingController targetCtrl, String catalogId) {
    showAppSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          height: MediaQuery.of(ctx).size.height * 0.75,
          child: Column(
            children: [
              Row(
                children: [
                  const Icon(Icons.search, size: 20),
                  const SizedBox(width: 8),
                  const Text('选择标准词条追加到文书',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Expanded(
                child: HisDiagnosisPicker(
                  catalogId: catalogId,
                  onSelectedText: (chosenText) {
                    Navigator.pop(ctx);
                    final cur = targetCtrl.text.trim();
                    if (cur.isEmpty) {
                      targetCtrl.text = chosenText;
                    } else {
                      targetCtrl.text = '$cur\n$chosenText';
                    }
                    setState(_recomputeValidationCache);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
