import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/task/task_center.dart';
import '../../../domain/models/content_template.dart';
import '../../../domain/models/message.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import '../../../providers/quick_generation_presets_provider.dart';
import '../../../providers/tutorial_provider.dart';
import '../../pages/settings/quick_generation_settings_page.dart';
import '../common/app_toast.dart';
import 'quick_generation_bar.dart';

/// 一体化病历生成向导返回结果
class GenerationWizardResult {
  final Template template;
  final ContentTemplate? contentTemplate;
  final bool allMaterials;
  final Set<String> selectedSlotKeys;
  final String extraInstructions;

  const GenerationWizardResult({
    required this.template,
    required this.contentTemplate,
    required this.allMaterials,
    required this.selectedSlotKeys,
    required this.extraInstructions,
  });
}

/// 三步病历生成向导弹窗：
/// 1. 类型与字段（顶部含「最近生成」直达第 3 步 + 单选就地展开字段勾选）
/// 2. 内容模板
/// 3. 生成要求（素材范围 + 补充要求 + 生成总览）
class RecordGenerationWizardSheet extends ConsumerStatefulWidget {
  final String patientId;
  final bool isDryRun;
  final QuickGenerationPreset? initialQuickPreset;

  const RecordGenerationWizardSheet({
    super.key,
    required this.patientId,
    this.isDryRun = false,
    this.initialQuickPreset,
  });

  @override
  ConsumerState<RecordGenerationWizardSheet> createState() =>
      _RecordGenerationWizardSheetState();
}

class _RecordGenerationWizardSheetState
    extends ConsumerState<RecordGenerationWizardSheet> {
  int _currentStep = 0; // 0: 类型与字段, 1: 内容模板, 2: 生成要求
  bool _isLoading = true;

  List<Template> _templates = [];
  final Map<String, List<ContentTemplate>> _contentTemplatesCache = {};
  int _pendingMediaCount = 0;
  bool _hasPastRecords = false;

  Template? _selectedTemplate;
  ContentTemplate? _selectedContentTemplate;
  bool _useNoContentTemplate = false;
  bool _allMaterials = true;
  Set<String> _selectedSlotKeys = {};
  String? _activeQuickPresetId;
  final TextEditingController _instructionsController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  @override
  void dispose() {
    _instructionsController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    final templateRepo = ref.read(templateRepositoryProvider);
    final msgRepo = ref.read(messageRepositoryProvider);

    final tmpls = await templateRepo.getAll();
    final msgs = await msgRepo.getAllChronological(widget.patientId);

    final activeTasks = ref.read(taskCenterProvider).activeTasks.where((t) {
      return t.patientId == widget.patientId &&
          (t.type == TaskType.asr ||
              t.type == TaskType.ocr ||
              t.type == TaskType.document);
    }).length;

    final placeholderCount = msgs.where((m) {
      final isPlaceholder = (m.type == MessageType.asrResult &&
              (m.transcribedText?.isEmpty ?? true)) ||
          (m.type == MessageType.ocrResult && (m.extractedText?.isEmpty ?? true));
      final isRecent = DateTime.now().difference(m.createdAt).inSeconds < 180;
      return isPlaceholder && isRecent;
    }).length;

    final pendingCount =
        activeTasks > placeholderCount ? activeTasks : placeholderCount;
    final hasPast = msgs.any((m) => m.type == MessageType.generatedRecord);

    _templates = tmpls;
    _pendingMediaCount = pendingCount;
    _hasPastRecords = hasPast;

    final quick = widget.initialQuickPreset;
    if (quick != null && tmpls.isNotEmpty) {
      final matchedTmpl =
          tmpls.where((t) => t.id == quick.templateId).firstOrNull;
      if (matchedTmpl != null) {
        await _ensureContentTemplatesLoaded(matchedTmpl.id);
        final resolved = quick.resolve(
          templates: tmpls,
          contentTemplatesByStructure: _contentTemplatesCache,
          hasPastRecords: hasPast,
        );
        if (resolved != null && mounted) {
          setState(() {
            _selectedTemplate = resolved.template;
            _selectedContentTemplate = resolved.contentTemplate;
            _useNoContentTemplate = resolved.contentTemplate == null;
            _allMaterials = resolved.allMaterials;
            _selectedSlotKeys = resolved.selectedSlotKeys;
            _activeQuickPresetId = quick.id;
            _currentStep = 2;
            _isLoading = false;
          });
          return;
        }
      }
    }

    if (mounted) {
      setState(() {
        _allMaterials = true;
        _isLoading = false;
      });
    }
  }

  void _deselectTemplate() {
    setState(() {
      _selectedTemplate = null;
      _selectedSlotKeys = {};
      _selectedContentTemplate = null;
      _useNoContentTemplate = false;
      _activeQuickPresetId = null;
    });
  }

  Future<List<ContentTemplate>> _ensureContentTemplatesLoaded(
      String templateId) async {
    if (_contentTemplatesCache.containsKey(templateId)) {
      return _contentTemplatesCache[templateId] ?? const [];
    }
    final contentTmpls = await ref
        .read(contentTemplateRepositoryProvider)
        .getByStructure(templateId);
    _contentTemplatesCache[templateId] = contentTmpls;
    return contentTmpls;
  }

  Future<void> _onSelectTemplate(Template template) async {
    if (mounted) {
      setState(() {
        _selectedTemplate = template;
        _selectedSlotKeys = template.sortedSlots.map((s) => s.key).toSet();
        _activeQuickPresetId = null;
      });
    } else {
      _selectedTemplate = template;
      _selectedSlotKeys = template.sortedSlots.map((s) => s.key).toSet();
    }

    final cached = await _ensureContentTemplatesLoaded(template.id);
    if (!mounted || _selectedTemplate?.id != template.id) return;
    setState(() {
      if (cached.isNotEmpty) {
        _selectedContentTemplate = cached.first;
        _useNoContentTemplate = false;
      } else {
        _selectedContentTemplate = null;
        _useNoContentTemplate = true;
      }
    });
  }

  Future<void> _applyQuickPresetAndJump(QuickGenerationPreset preset) async {
    final targetTmpl =
        _templates.where((t) => t.id == preset.templateId).firstOrNull;
    if (targetTmpl == null) {
      showAppToast(context, '对应文书类型已不存在');
      return;
    }

    await _ensureContentTemplatesLoaded(targetTmpl.id);
    final resolved = preset.resolve(
      templates: _templates,
      contentTemplatesByStructure: _contentTemplatesCache,
      hasPastRecords: _hasPastRecords,
    );
    if (resolved == null || !mounted) return;

    setState(() {
      _selectedTemplate = resolved.template;
      _selectedContentTemplate = resolved.contentTemplate;
      _useNoContentTemplate = resolved.contentTemplate == null;
      _allMaterials = resolved.allMaterials;
      _selectedSlotKeys = resolved.selectedSlotKeys;
      _activeQuickPresetId = preset.id;
      _currentStep = 2;
    });
  }

  Future<void> _openQuickSettings() async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(builder: (_) => const QuickGenerationSettingsPage()),
    );
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_selectedTemplate == null) {
        showAppToast(context, '请先选择一个文书类型');
        return;
      }
      if (_selectedSlotKeys.isEmpty) {
        showAppToast(context, '请至少勾选一个生成字段');
        return;
      }
    }
    if (_currentStep < 2) {
      setState(() => _currentStep++);
    } else {
      _finishWizard();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      setState(() => _currentStep--);
    } else {
      Navigator.pop(context);
    }
  }

  void _finishWizard() {
    if (_selectedTemplate == null) return;
    if (_selectedSlotKeys.isEmpty) {
      showAppToast(context, '请至少勾选一个生成字段');
      return;
    }

    Navigator.pop(
      context,
      GenerationWizardResult(
        template: _selectedTemplate!,
        contentTemplate: _selectedContentTemplate,
        allMaterials: _allMaterials,
        selectedSlotKeys: _selectedSlotKeys,
        extraInstructions: _instructionsController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      clipBehavior: Clip.antiAlias,
      backgroundColor: theme.colorScheme.surface,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 620,
          maxHeight: MediaQuery.of(context).size.height * 0.84,
        ),
        child: Column(
          children: [
            _buildStepIndicator(theme),
            const Divider(height: 1),
            Expanded(
              child: Column(
                children: [
                  _buildTutorialHint(theme),
                  Expanded(
                    child: _isLoading
                        ? const Center(child: CircularProgressIndicator())
                        : _buildStepContent(theme),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            _buildBottomBar(theme),
          ],
        ),
      ),
    );
  }

  /// 三站式地铁线路图（支持点击站点在已选文书时跳转）
  Widget _buildStepIndicator(ThemeData theme) {
    const steps = ['类型与字段', '内容模板', '生成要求'];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      color: theme.colorScheme.surface,
      child: Column(
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '第 ${_currentStep + 1} / 3 步',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        color: theme.colorScheme.primary,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      steps[_currentStep],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Align(
                alignment: Alignment.topRight,
                child: IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  visualDensity: VisualDensity.compact,
                  tooltip: '关闭',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Stack(
            children: [
              Positioned(
                top: 12,
                left: 0,
                right: 0,
                child: Row(
                  children: [
                    const Spacer(flex: 1),
                    for (var lineIndex = 0; lineIndex < 2; lineIndex++)
                      Expanded(
                        flex: 2,
                        child: Container(
                          height: 3.5,
                          decoration: BoxDecoration(
                            color: lineIndex < _currentStep
                                ? Colors.teal
                                : Colors.grey.withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    const Spacer(flex: 1),
                  ],
                ),
              ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: List.generate(3, (stepIndex) {
                  final isDone = stepIndex < _currentStep;
                  final isCurrent = stepIndex == _currentStep;

                  Widget stationNode;
                  if (isDone) {
                    stationNode = Container(
                      width: 26,
                      height: 26,
                      decoration: const BoxDecoration(
                        color: Colors.teal,
                        shape: BoxShape.circle,
                      ),
                      child:
                          const Icon(Icons.check, size: 15, color: Colors.white),
                    );
                  } else if (isCurrent) {
                    stationNode = Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                theme.colorScheme.primary.withValues(alpha: 0.3),
                            blurRadius: 6,
                            spreadRadius: 1.5,
                          ),
                        ],
                      ),
                      child: Center(
                        child: Text(
                          '${stepIndex + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    );
                  } else {
                    stationNode = Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '${stepIndex + 1}',
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  }

                  return Expanded(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () {
                        if (_selectedTemplate == null) return;
                        if (stepIndex > 0 && _selectedSlotKeys.isEmpty) {
                          showAppToast(context, '请至少勾选一个生成字段');
                          return;
                        }
                        setState(() => _currentStep = stepIndex);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              height: 28,
                              child: Center(
                                child: Container(
                                  color: theme.colorScheme.surface,
                                  padding:
                                      const EdgeInsets.symmetric(horizontal: 3),
                                  child: stationNode,
                                ),
                              ),
                            ),
                            const SizedBox(height: 5),
                            FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                steps[stepIndex],
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                softWrap: false,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: isCurrent
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isCurrent
                                      ? theme.colorScheme.primary
                                      : (isDone
                                          ? Colors.teal
                                          : Colors.grey.shade500),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTutorialHint(ThemeData theme) {
    final state = ref.watch(tutorialProvider);
    if (!state.isActive ||
        state.activeTutorial != TutorialType.basicFlow ||
        state.currentStep != 4) {
      return const SizedBox.shrink();
    }
    const hints = [
      '① 类型与字段：选择文书类型并勾选要生成的字段。',
      '② 内容模板：可选已配置的写作范例，没有也可以直接下一步。',
      '③ 生成要求：选择素材范围、填写额外要求并核对总览。',
    ];
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(14, 10, 14, 2),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        hints[_currentStep],
        style: TextStyle(
          fontSize: 12.5,
          height: 1.4,
          color: theme.colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildStepContent(ThemeData theme) {
    switch (_currentStep) {
      case 0:
        return _buildStep1TemplateAndFields(theme);
      case 1:
        return _buildStep2ContentTemplate(theme);
      case 2:
        return _buildStep3RequirementsAndOverview(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  /// 第 1 步：最近生成快捷条 + 单选文书类型并就地展开字段勾选
  Widget _buildStep1TemplateAndFields(ThemeData theme) {
    final scheme = theme.colorScheme;
    if (_templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.assignment_late_outlined,
                size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('暂无文书类型，请先在菜单中创建'),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('返回'),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      children: [
        QuickGenerationBar(
          onSelectPreset: _applyQuickPresetAndJump,
          onOpenSettings: _openQuickSettings,
          selectedPresetId: _activeQuickPresetId,
          showWhenEmpty: true,
          twoRowLayout: true,
          padding: const EdgeInsets.only(bottom: 10),
        ),
        const Divider(height: 1),
        const SizedBox(height: 10),
        for (final t in _templates) _buildTemplateRadioCard(t, scheme),
      ],
    );
  }

  Widget _buildTemplateRadioCard(Template t, ColorScheme scheme) {
    final isSelected = _selectedTemplate?.id == t.id;
    final slots = t.sortedSlots;
    final allKeys = slots.map((s) => s.key).toSet();

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isSelected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.45),
          width: isSelected ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              if (isSelected) {
                _deselectTemplate();
              } else {
                _onSelectTemplate(t);
              }
            },
            child: Container(
              color: isSelected
                  ? scheme.primaryContainer.withValues(alpha: 0.28)
                  : scheme.surface,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Row(
                children: [
                  Icon(
                    Icons.description_outlined,
                    size: 20,
                    color: isSelected ? scheme.primary : scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          t.name,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight:
                                isSelected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          isSelected
                              ? '${slots.length} 个字段（已选 ${_selectedSlotKeys.length}/${slots.length}）'
                              : '${slots.length} 个字段',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isSelected
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked,
                    color: isSelected ? scheme.primary : scheme.outline,
                  ),
                ],
              ),
            ),
          ),
          if (isSelected) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        '生成字段',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () =>
                            setState(() => _selectedSlotKeys = allKeys),
                        child: const Text('全选', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 4),
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () =>
                            setState(() => _selectedSlotKeys = <String>{}),
                        child:
                            const Text('全不选', style: TextStyle(fontSize: 12)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final s in slots)
                        FilterChip(
                          label: Text(
                            s.label.isNotEmpty ? s.label : s.key,
                            style: const TextStyle(fontSize: 12.5),
                          ),
                          selected: _selectedSlotKeys.contains(s.key),
                          visualDensity: VisualDensity.compact,
                          onSelected: (checked) {
                            setState(() {
                              final next = Set<String>.from(_selectedSlotKeys);
                              if (checked) {
                                next.add(s.key);
                              } else {
                                next.remove(s.key);
                              }
                              _selectedSlotKeys = next;
                              _activeQuickPresetId = null;
                            });
                          },
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 第 2 步：选内容模板
  Widget _buildStep2ContentTemplate(ThemeData theme) {
    if (_selectedTemplate == null) return const SizedBox.shrink();

    final tmplId = _selectedTemplate!.id;
    final contentTmpls = _contentTemplatesCache[tmplId] ?? [];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: [
        Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: _useNoContentTemplate
                  ? theme.colorScheme.primary
                  : Colors.grey.withValues(alpha: 0.25),
              width: _useNoContentTemplate ? 1.6 : 1,
            ),
          ),
          color: _useNoContentTemplate
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
              : theme.colorScheme.surface,
          child: ListTile(
            dense: true,
            leading: Icon(
              Icons.not_interested_outlined,
              size: 18,
              color: _useNoContentTemplate
                  ? theme.colorScheme.primary
                  : Colors.grey.shade500,
            ),
            title: Text(
              '不使用内容模板',
              style: TextStyle(
                fontSize: 13.5,
                fontWeight:
                    _useNoContentTemplate ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            trailing: _useNoContentTemplate
                ? Icon(Icons.check_circle_rounded,
                    color: theme.colorScheme.primary)
                : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
            onTap: () {
              setState(() {
                _useNoContentTemplate = true;
                _selectedContentTemplate = null;
                _activeQuickPresetId = null;
              });
            },
          ),
        ),
        if (contentTmpls.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.18)),
            ),
            child: Text(
              '「${_selectedTemplate!.name}」暂无内容模板，可直接下一步。',
              style: const TextStyle(fontSize: 12.5, color: Colors.blueGrey),
            ),
          )
        else
          ...contentTmpls.map((ct) {
            final isSelected =
                !_useNoContentTemplate && _selectedContentTemplate?.id == ct.id;
            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.grey.withValues(alpha: 0.25),
                  width: isSelected ? 1.6 : 1,
                ),
              ),
              color: isSelected
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
                  : theme.colorScheme.surface,
              child: ListTile(
                leading: Icon(
                  Icons.description_outlined,
                  color: isSelected ? theme.colorScheme.primary : Colors.teal,
                ),
                title: Text(
                  ct.name,
                  style: TextStyle(
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                trailing: isSelected
                    ? Icon(Icons.check_circle_rounded,
                        color: theme.colorScheme.primary)
                    : const Icon(Icons.radio_button_unchecked,
                        color: Colors.grey),
                onTap: () {
                  setState(() {
                    _useNoContentTemplate = false;
                    _selectedContentTemplate = ct;
                    _activeQuickPresetId = null;
                  });
                },
              ),
            );
          }),
      ],
    );
  }

  /// 第 3 步：素材范围 + 补充要求 + 生成总览
  Widget _buildStep3RequirementsAndOverview(ThemeData theme) {
    final scheme = theme.colorScheme;
    final tmpl = _selectedTemplate;
    if (tmpl == null) return const SizedBox.shrink();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      children: [
        if (_pendingMediaCount > 0)
          Container(
            padding: const EdgeInsets.all(11),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.hourglass_top_rounded,
                    color: Colors.orange, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '当前仍有 $_pendingMediaCount 项语音或照片正在识别中，未完成前不会纳入本次生成。',
                    style: const TextStyle(fontSize: 12, height: 1.35),
                  ),
                ),
              ],
            ),
          ),

        // 上方：所有材料 vs 新材料 二选一
        Row(
          children: [
            Expanded(
              child: _ScopeChoiceCard(
                title: '全部材料',
                subtitle: '建档至今所有内容',
                selected: _allMaterials,
                enabled: true,
                onTap: () => setState(() => _allMaterials = true),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ScopeChoiceCard(
                title: '仅新增内容',
                subtitle: _hasPastRecords ? '末次生成之后记录' : '暂无既往生成',
                selected: !_allMaterials,
                enabled: _hasPastRecords,
                onTap: _hasPastRecords
                    ? () => setState(() => _allMaterials = false)
                    : null,
              ),
            ),
          ],
        ),

        const SizedBox(height: 12),

        // 中间：额外要求输入框
        TextField(
          controller: _instructionsController,
          maxLines: 3,
          minLines: 2,
          style: const TextStyle(fontSize: 13),
          decoration: InputDecoration(
            hintText: '补充指示 / 额外要求（选填）',
            hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade500),
            prefixIcon: const Icon(Icons.edit_note, size: 20),
            filled: true,
            fillColor: scheme.surfaceContainerLow,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // 最下面：生成总览
        Card(
          elevation: 0,
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '生成总览',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: 8),
                _OverviewRow(
                  label: '生成文书',
                  value:
                      '${tmpl.name}（${_selectedSlotKeys.length}/${tmpl.sortedSlots.length} 个字段）',
                ),
                const SizedBox(height: 5),
                _OverviewRow(
                  label: '内容模板',
                  value: _selectedContentTemplate?.name ?? '不使用内容模板',
                ),
                const SizedBox(height: 5),
                _OverviewRow(
                  label: '素材范围',
                  value: _allMaterials ? '全部会话与材料' : '自上次生成后的新增内容',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBottomBar(ThemeData theme) {
    final isFirstStep = _currentStep == 0;
    final isLastStep = _currentStep == 2;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          OutlinedButton.icon(
            icon: Icon(isFirstStep ? Icons.close : Icons.arrow_back, size: 16),
            label: Text(isFirstStep ? '取消' : '上一步'),
            onPressed: _prevStep,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton.icon(
              icon: Icon(
                isLastStep ? Icons.auto_awesome : Icons.arrow_forward,
                size: 18,
              ),
              label: Text(
                isLastStep
                    ? '开始生成 (${_selectedSlotKeys.length})'
                    : '下一步',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              onPressed: (_selectedTemplate == null ||
                      (_currentStep == 2 && _selectedSlotKeys.isEmpty))
                  ? null
                  : _nextStep,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScopeChoiceCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  const _ScopeChoiceCard({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.enabled,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final borderColor = !enabled
        ? scheme.outlineVariant.withValues(alpha: 0.35)
        : (selected
            ? scheme.primary
            : scheme.outlineVariant.withValues(alpha: 0.55));
    final bgColor = !enabled
        ? scheme.surfaceContainerHighest.withValues(alpha: 0.25)
        : (selected
            ? scheme.primaryContainer.withValues(alpha: 0.28)
            : scheme.surface);

    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(color: borderColor, width: selected && enabled ? 1.5 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? (selected ? scheme.primary : scheme.onSurface)
                            : scheme.onSurfaceVariant.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                  if (selected && enabled)
                    Icon(Icons.check_circle_rounded,
                        size: 16, color: scheme.primary),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 11.5,
                  color: enabled
                      ? scheme.onSurfaceVariant
                      : scheme.onSurfaceVariant.withValues(alpha: 0.45),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OverviewRow extends StatelessWidget {
  final String label;
  final String value;

  const _OverviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
          ),
        ),
      ],
    );
  }
}
