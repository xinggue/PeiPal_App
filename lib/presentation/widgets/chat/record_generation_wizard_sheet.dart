import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/task/task_center.dart';
import '../../../domain/models/content_template.dart';
import '../../../domain/models/message.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import '../../../providers/tutorial_provider.dart';
import 'generation_fields_and_requirements.dart';

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

/// 一体化病历生成向导底栏弹窗：
/// 整合 1.选结构模板 -> 2.选内容模板 -> 3.选素材范围 -> 4.选字段与要求 为单一弹窗
/// 包含步骤指示器、上一步/下一步切换、状态保留及无内容模板时的优雅提示
class RecordGenerationWizardSheet extends ConsumerStatefulWidget {
  final String patientId;
  final bool isDryRun;

  const RecordGenerationWizardSheet({
    super.key,
    required this.patientId,
    this.isDryRun = false,
  });

  @override
  ConsumerState<RecordGenerationWizardSheet> createState() =>
      _RecordGenerationWizardSheetState();
}

class _RecordGenerationWizardSheetState
    extends ConsumerState<RecordGenerationWizardSheet> {
  int _currentStep = 0; // 0: 结构模板, 1: 内容模板, 2: 素材范围, 3: 字段与要求
  bool _isLoading = true;

  // 数据列表缓存
  List<Template> _templates = [];
  final Map<String, List<ContentTemplate>> _contentTemplatesCache = {};
  int _pendingMediaCount = 0;
  bool _hasPastRecords = false;

  // 步骤选择状态
  Template? _selectedTemplate;
  ContentTemplate? _selectedContentTemplate;
  bool _useNoContentTemplate = false;
  bool _allMaterials = true;
  Set<String> _selectedSlotKeys = {};
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

    // 计算是否有未识别完的素材
    final activeTasks = ref.read(taskCenterProvider).activeTasks.where((t) {
      return t.patientId == widget.patientId &&
          (t.type == TaskType.asr || t.type == TaskType.ocr);
    }).toList();

    final placeholderCount = msgs.where((m) {
      final isPlaceholder = (m.type == MessageType.asrResult &&
              (m.transcribedText?.isEmpty ?? true)) ||
          (m.type == MessageType.ocrResult && (m.extractedText?.isEmpty ?? true));
      final isRecent = DateTime.now().difference(m.createdAt).inSeconds < 180;
      return isPlaceholder && isRecent;
    }).length;

    final pendingCount = (activeTasks.length > placeholderCount)
        ? activeTasks.length
        : placeholderCount;

    final hasPast = msgs.any((m) => m.type == MessageType.generatedRecord);

    if (tmpls.isNotEmpty) {
      await _onSelectTemplate(tmpls.first);
    }

    if (mounted) {
      setState(() {
        _templates = tmpls;
        _pendingMediaCount = pendingCount;
        _hasPastRecords = hasPast;
        _allMaterials = true;
        _isLoading = false;
      });
    }
  }

  Future<void> _onSelectTemplate(Template template) async {
    if (mounted) {
      setState(() {
        _selectedTemplate = template;
        _selectedSlotKeys = template.sortedSlots.map((s) => s.key).toSet();
      });
    } else {
      _selectedTemplate = template;
      _selectedSlotKeys = template.sortedSlots.map((s) => s.key).toSet();
    }

    // 加载对应内容模板
    if (!_contentTemplatesCache.containsKey(template.id)) {
      final contentTmpls = await ref
          .read(contentTemplateRepositoryProvider)
          .getByStructure(template.id);
      if (mounted) {
        setState(() {
          _contentTemplatesCache[template.id] = contentTmpls;
          // 默认选中最顶部的第一个内容模板；若无内容模板则选不使用模板
          if (contentTmpls.isNotEmpty) {
            _selectedContentTemplate = contentTmpls.first;
            _useNoContentTemplate = false;
          } else {
            _selectedContentTemplate = null;
            _useNoContentTemplate = true;
          }
        });
      }
    } else {
      final cached = _contentTemplatesCache[template.id] ?? [];
      if (mounted) {
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
    }
  }

  void _nextStep() {
    if (_currentStep == 0 && _selectedTemplate == null) {
      showAppToast(context, '请先选择一个文书类型');
      return;
    }
    if (_currentStep < 3) {
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
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Column(
          children: [
            // 地铁线路图式步骤指示 Header（去向导字样，居中大号步骤数字）
            _buildStepIndicator(theme),

            const Divider(height: 1),

            // 主体内容区（根据当前 step 展示）
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

            // 底部控制按钮栏（上一步 / 下一步）
            _buildBottomBar(theme),
          ],
        ),
      ),
    );
  }

  /// 地铁站点式步骤指示器 (O-O-O-O 线路图)
  Widget _buildStepIndicator(ThemeData theme) {
    const steps = ['文书类型', '内容模板', '素材范围', '字段与要求'];

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
      ),
      child: Column(
        children: [
          // 顶部：右侧有关闭按钮，居中超大字号 "第 n / 4 步"
          Stack(
            alignment: Alignment.center,
            children: [
              Align(
                alignment: Alignment.center,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '第 ${_currentStep + 1} / 4 步',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
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

          // 地铁线路图：O ====== O ====== O ====== O
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(7, (index) {
                // 奇数索引为站点之间的连接轨道
                if (index.isOdd) {
                  final lineIndex = index ~/ 2;
                  final isPassed = lineIndex < _currentStep;
                  return Expanded(
                    child: Container(
                      height: 3.5,
                      margin: const EdgeInsets.only(top: 12),
                      decoration: BoxDecoration(
                        color: isPassed
                            ? Colors.teal
                            : Colors.grey.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }

                // 偶数索引为地铁站点圈圈
                final stepIndex = index ~/ 2;
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
                    child: const Icon(Icons.check, size: 15, color: Colors.white),
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
                          color: theme.colorScheme.primary.withValues(alpha: 0.35),
                          blurRadius: 6,
                          spreadRadius: 2,
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

                return SizedBox(
                  width: 58,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      stationNode,
                      const SizedBox(height: 5),
                      Text(
                        steps[stepIndex],
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isCurrent
                              ? theme.colorScheme.primary
                              : (isDone ? Colors.teal : Colors.grey.shade500),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }

  /// 新手引导期间，在向导内同步提示当前这一步的用途。
  Widget _buildTutorialHint(ThemeData theme) {
    final state = ref.watch(tutorialProvider);
    if (!state.isActive ||
        state.activeTutorial != TutorialType.basicFlow ||
        state.currentStep != 4) {
      return const SizedBox.shrink();
    }
    const hints = [
      '① 文书类型：选择这次要生成的记录/文书类型。',
      '② 内容模板：可选已配置的范文与写作指导，没有也可以直接下一步。',
      '③ 素材范围：使用全部材料，或仅使用上次生成后的新增内容。',
      '④ 字段与要求：勾选要生成的字段，还能补充额外要求。',
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

  /// 动态步骤内容切换
  Widget _buildStepContent(ThemeData theme) {
    switch (_currentStep) {
      case 0:
        return _buildStep1Template(theme);
      case 1:
        return _buildStep2ContentTemplate(theme);
      case 2:
        return _buildStep3Materials(theme);
      case 3:
        return _buildStep4Slots(theme);
      default:
        return const SizedBox.shrink();
    }
  }

  /// 步骤 1: 选病历（结构模板）
  Widget _buildStep1Template(ThemeData theme) {
    if (_templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.assignment_late_outlined, size: 48, color: Colors.grey),
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

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: _templates.length,
      itemBuilder: (ctx, i) {
        final t = _templates[i];
        final isSelected = _selectedTemplate?.id == t.id;

        return Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: isSelected
                  ? theme.colorScheme.primary
                  : Colors.grey.withValues(alpha: 0.2),
              width: isSelected ? 1.8 : 1,
            ),
          ),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
              : theme.colorScheme.surface,
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            leading: Icon(
              Icons.description_outlined,
              color: isSelected ? theme.colorScheme.primary : Colors.grey,
            ),
            title: Text(
              t.name,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              ),
            ),
            subtitle: Text('${t.slots.length} 个字段 · v${t.version}'),
            trailing: isSelected
                ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
            onTap: () {
              _onSelectTemplate(t);
            },
          ),
        );
      },
    );
  }

  /// 步骤 2: 选模板（内容模板，支持显示未配置内容模板）
  Widget _buildStep2ContentTemplate(ThemeData theme) {
    if (_selectedTemplate == null) return const SizedBox.shrink();

    final tmplId = _selectedTemplate!.id;
    final contentTmpls = _contentTemplatesCache[tmplId] ?? [];

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // 选项一：不使用内容模板
        Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: _useNoContentTemplate
                  ? theme.colorScheme.primary
                  : Colors.grey.withValues(alpha: 0.2),
              width: _useNoContentTemplate ? 1.8 : 1,
            ),
          ),
          color: _useNoContentTemplate
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
              : theme.colorScheme.surface,
          child: ListTile(
            dense: true,
            visualDensity: VisualDensity.compact,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
            leading: Icon(
              Icons.not_interested_outlined,
              size: 16,
              color: _useNoContentTemplate
                  ? theme.colorScheme.primary
                  : Colors.grey.shade500,
            ),
            title: Text(
              '不使用模板',
              style: TextStyle(
                fontSize: 11.5,
                color: _useNoContentTemplate
                    ? theme.colorScheme.primary
                    : Colors.grey.shade600,
              ),
            ),
            trailing: _useNoContentTemplate
                ? Icon(Icons.check_circle_rounded,
                    size: 16, color: theme.colorScheme.primary)
                : Icon(Icons.radio_button_unchecked,
                    size: 16, color: Colors.grey.shade500),
            onTap: () {
              setState(() {
                _useNoContentTemplate = true;
                _selectedContentTemplate = null;
              });
            },
          ),
        ),

        // 如果该结构模板未配置内容模板，给出友好卡片提示
        if (contentTmpls.isEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.18)),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.blueGrey, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '当前结构尚未配置内容模板',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '「${_selectedTemplate!.name}」暂无专属 Few-shot 范文，将以标准模式直接进入生成。',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ] else ...[
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 4, bottom: 8),
            child: Text(
              '可选范文内容模板 (${contentTmpls.length})',
              style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ...contentTmpls.map((ct) {
            final isSelected = !_useNoContentTemplate && _selectedContentTemplate?.id == ct.id;

            return Card(
              elevation: 0,
              margin: const EdgeInsets.only(bottom: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.grey.withValues(alpha: 0.2),
                  width: isSelected ? 1.8 : 1,
                ),
              ),
              color: isSelected
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
                  : theme.colorScheme.surface,
              child: ListTile(
                leading: Icon(
                  Icons.folder_copy_outlined,
                  color: isSelected ? theme.colorScheme.primary : Colors.teal,
                ),
                title: Text(
                  ct.name,
                  style: TextStyle(fontWeight: isSelected ? FontWeight.bold : FontWeight.w500),
                ),
                subtitle: Text('${ct.filledSlotCount} 个字段已配置范文/指导要求'),
                trailing: isSelected
                    ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                    : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
                onTap: () {
                  setState(() {
                    _useNoContentTemplate = false;
                    _selectedContentTemplate = ct;
                  });
                },
              ),
            );
          }),
        ],
      ],
    );
  }

  /// 步骤 3: 选素材范围（含未识别素材友好提示）
  Widget _buildStep3Materials(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        // 如果有正在后台识别的素材，顶部展示提醒条
        if (_pendingMediaCount > 0)
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.hourglass_top_rounded, color: Colors.orange, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '提示：当前仍有 $_pendingMediaCount 项语音或文书照片正在后台识别中。若直接生成，未识别完的素材将无法纳入。',
                    style: const TextStyle(fontSize: 12, height: 1.35),
                  ),
                ),
              ],
            ),
          ),

        Card(
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: _allMaterials
                  ? theme.colorScheme.primary
                  : Colors.grey.withValues(alpha: 0.2),
              width: _allMaterials ? 1.8 : 1,
            ),
          ),
          color: _allMaterials
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
              : theme.colorScheme.surface,
          child: ListTile(
            leading: Icon(
              Icons.all_inclusive,
              color: _allMaterials ? theme.colorScheme.primary : Colors.blue,
            ),
            title: const Text('全部会话与材料', style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: const Text('包含建档至今所有文字、语音与材料'),
            trailing: _allMaterials
                ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
            onTap: () {
              setState(() => _allMaterials = true);
            },
          ),
        ),

        if (_hasPastRecords)
          Card(
            elevation: 0,
            margin: const EdgeInsets.only(bottom: 10),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(
                color: !_allMaterials
                    ? theme.colorScheme.primary
                    : Colors.grey.withValues(alpha: 0.2),
                width: !_allMaterials ? 1.8 : 1,
              ),
            ),
            color: !_allMaterials
                ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
                : theme.colorScheme.surface,
            child: ListTile(
              leading: Icon(
                Icons.update,
                color: !_allMaterials ? theme.colorScheme.primary : Colors.teal,
              ),
              title: const Text('自上次生成后的新增内容', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: const Text('仅提取末次文书之后的材料'),
              trailing: !_allMaterials
                  ? Icon(Icons.check_circle_rounded, color: theme.colorScheme.primary)
                  : const Icon(Icons.radio_button_unchecked, color: Colors.grey),
              onTap: () {
                setState(() => _allMaterials = false);
              },
            ),
          ),

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text(
            '注：既往已生成的历史文书卡片将作为基础背景全部完整传入。',
            style: TextStyle(fontSize: 12, color: Colors.blueGrey),
          ),
        ),
      ],
    );
  }

  /// 步骤 4: 选字段与填写补充要求
  Widget _buildStep4Slots(ThemeData theme) {
    if (_selectedTemplate == null) return const SizedBox.shrink();

    return GenerationFieldsAndRequirements(
      slots: _selectedTemplate!.sortedSlots,
      selectedKeys: _selectedSlotKeys,
      instructionsController: _instructionsController,
      onSelectionChanged: (keys) =>
          setState(() => _selectedSlotKeys = keys),
    );
  }

  /// 底部控制按钮栏
  Widget _buildBottomBar(ThemeData theme) {
    final isFirstStep = _currentStep == 0;
    final isLastStep = _currentStep == 3;

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
              icon: Icon(isLastStep ? Icons.auto_awesome : Icons.arrow_forward, size: 18),
              label: Text(
                isLastStep
                    ? '确认所选并开始生成 (${_selectedSlotKeys.length})'
                    : '下一步',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              onPressed: isLastStep && _selectedSlotKeys.isEmpty ? null : _nextStep,
            ),
          ),
        ],
      ),
    );
  }
}
