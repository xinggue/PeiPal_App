import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/template.dart';
import '../../../domain/models/pipeline_graph.dart';
import '../../../domain/models/typing_profile.dart';
import '../../../providers/providers.dart';
import '../../widgets/templates/pipeline_grid.dart';
import 'slot_editor_sheet.dart';
import 'typing_flow_tab.dart';
import '../../widgets/engine_c/engine_c_sheets.dart';

class TemplateEditorPage extends ConsumerStatefulWidget {
  final String? templateId;
  final Template? previewTemplate;
  final int initialTabIndex;
  final String? initialProfileId;

  const TemplateEditorPage({
    super.key,
    this.templateId,
    this.previewTemplate,
    this.initialTabIndex = 0,
    this.initialProfileId,
  });

  bool get isReadOnly => previewTemplate != null;

  @override
  ConsumerState<TemplateEditorPage> createState() => _TemplateEditorPageState();
}

class _TemplateEditorPageState extends ConsumerState<TemplateEditorPage>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  late TextEditingController _nameCtrl;
  late TextEditingController _versionCtrl;

  List<TemplateSlot> _slots = [];
  PipelineGraph? _pipeline;
  List<TypingProfile> _typingProfiles = [TypingProfile(name: '默认')];
  DateTime? _createdAt;

  final Set<String> _assignedSlots = {};
  bool _isSaving = false;
  bool _isNew = true;
  bool _selectMode = false;
  final Set<int> _selectedSlots = {};
  bool _pipelineInit = false;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTabIndex.clamp(0, 2),
    );
    _tabCtrl.addListener(() {
      if (_tabCtrl.index == 1 && !_pipelineInit) {
        _pipelineInit = true;
        _ensurePipeline();
        setState(() {});
      }
    });

    final preview = widget.previewTemplate;
    if (preview != null) {
      _nameCtrl = TextEditingController(text: preview.name);
      _versionCtrl = TextEditingController(text: preview.version);
      _slots = List.from(preview.slots);
      _pipeline = PipelineGraph.fromJsonString(preview.pipeline.toJsonString());
      _typingProfiles = List.from(preview.typingProfiles);
      _createdAt = preview.createdAt;
      _isNew = false;
      _ensurePipeline();
    } else {
      _nameCtrl = TextEditingController();
      _versionCtrl = TextEditingController(text: '1.0');
      _isNew = widget.templateId == null;
      if (!_isNew) _loadTemplate();
    }
  }

  Future<void> _loadTemplate() async {
    final t =
        await ref.read(templateRepositoryProvider).getById(widget.templateId!);
    if (t != null && mounted) {
      setState(() {
        _nameCtrl.text = t.name;
        _versionCtrl.text = t.version;
        _slots = List.from(t.slots);
        _pipeline = t.pipeline;
        _typingProfiles = List.from(t.typingProfiles);
        _createdAt = t.createdAt;
        _ensurePipeline();
      });
    }
  }

  void _ensurePipeline() {
    _pipeline ??= PipelineGraph();
    if (_pipeline!.nodes.isNotEmpty) {
      _assignedSlots.clear();
      for (final n in _pipeline!.nodes) {
        _assignedSlots.addAll(n.slotKeys);
      }
      return;
    }
    if (widget.isReadOnly) return;
    if (_slots.isEmpty) return;

    _assignedSlots.clear();
    _pipeline!.nodes.add(PipelineNode(
      label: '起点',
      slotKeys: [],
      col: 0,
      row: 0,
    ));
    for (int i = 0; i < _slots.length; i++) {
      final slot = _slots[i];
      _pipeline!.nodes.add(PipelineNode(
        label: slot.label,
        slotKeys: [slot.key],
        col: 1,
        row: i,
      ));
      _assignedSlots.add(slot.key);
    }
  }

  void _pipelineChanged() {
    setState(() {
      _assignedSlots.clear();
      for (final n in _pipeline!.nodes) {
        _assignedSlots.addAll(n.slotKeys);
      }
    });
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _nameCtrl.dispose();
    _versionCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty) {
      showAppToast(context, '请输入模板名称');
      return;
    }
    setState(() => _isSaving = true);

    final template = Template(
      id: _isNew ? null : widget.templateId,
      name: _nameCtrl.text.trim(),
      version: _versionCtrl.text.trim(),
      slots: List.from(_slots),
      pipeline: _pipeline ?? PipelineGraph(),
      typingProfiles: List.from(_typingProfiles),
      createdAt: _createdAt,
    );

    final repo = ref.read(templateRepositoryProvider);
    if (_isNew) {
      await repo.insert(template);
    } else {
      await repo.update(template);
    }

    ref.invalidate(templatesProvider);
    if (mounted) context.pop();
  }

  void _addSlot() {
    SlotEditorSheet.show(
      context: context,
      existingSlots: _slots,
      onSave: (newSlot) {
        setState(() {
          _slots.add(newSlot.copyWith(order: _slots.length));
        });
      },
    );
  }

  void _editSlot(int index) {
    final slot = _slots[index];
    SlotEditorSheet.show(
      context: context,
      initialSlot: slot,
      existingSlots: _slots,
      onSave: (updated) {
        setState(() {
          _slots[index] = updated.copyWith(order: index);
        });
      },
      onDelete: () {
        setState(() {
          _slots.removeAt(index);
          _reindexSlots();
        });
      },
    );
  }

  void _reindexSlots() {
    for (int i = 0; i < _slots.length; i++) {
      _slots[i] = _slots[i].copyWith(order: i);
    }
  }

  String _uniqueKey(String baseKey) {
    var candidate = '${baseKey}_copy';
    int counter = 2;
    final existing = _slots.map((s) => s.key).toSet();
    while (existing.contains(candidate)) {
      candidate = '${baseKey}_copy$counter';
      counter++;
    }
    return candidate;
  }

  @override
  Widget build(BuildContext context) {
    final titleText = widget.isReadOnly
        ? '预览文书类型 · ${_nameCtrl.text}'
        : (_isNew ? '新建文书类型' : '编辑文书类型');

    return Scaffold(
      appBar: AppBar(
        title: Text(titleText),
        actions: [
          if (!widget.isReadOnly && !_isNew)
            IconButton(
              tooltip: '发布到在线模板广场',
              icon: const Icon(Icons.cloud_upload_outlined),
              onPressed: () {
                final currentTemplate = Template(
                  id: widget.templateId,
                  name: _nameCtrl.text.trim().isEmpty ? '未命名' : _nameCtrl.text.trim(),
                  version: _versionCtrl.text.trim(),
                  slots: _slots,
                  pipeline: _pipeline ?? PipelineGraph(),
                  typingProfiles: _typingProfiles,
                  createdAt: _createdAt,
                );
                EngineCExportSheet.showForTemplate(
                  context,
                  currentTemplate,
                  publishKind: 'structure',
                );
              },
            ),
          if (!widget.isReadOnly)
            TextButton(
              onPressed: _isSaving ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: _nameCtrl,
                    readOnly: widget.isReadOnly,
                    decoration: const InputDecoration(
                      labelText: '模板名称',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 1,
                  child: TextField(
                    controller: _versionCtrl,
                    readOnly: widget.isReadOnly,
                    decoration: const InputDecoration(
                      labelText: '版本',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          TabBar(
            controller: _tabCtrl,
            tabs: const [
              Tab(text: '字段定义'),
              Tab(text: '解析流程'),
              Tab(text: '输入流程'),
            ],
          ),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildSlotTab(),
                Builder(builder: (_) {
                  final g = _pipeline ?? PipelineGraph();
                  return PipelineGrid(
                    readOnly: widget.isReadOnly,
                    graph: g,
                    allSlots: _slots,
                    assignedSlots: _assignedSlots,
                    onChanged: _pipelineChanged,
                  );
                }),
                TypingFlowTab(
                  readOnly: widget.isReadOnly,
                  initialProfileId: widget.initialProfileId,
                  slots: _slots,
                  profiles: _typingProfiles,
                  onChanged: (updated) =>
                      setState(() => _typingProfiles = updated),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSlotTab() {
    if (widget.isReadOnly) {
      return ListView(children: [for (final s in _slots)
        ExpansionTile(title: Text(s.label), subtitle: Text(s.type.name), children: [
          ListTile(title: SelectableText([
            '标识：${s.key}',
            if (s.required) '必填',
            if (s.defaultValue != null) '默认值：${s.defaultValue}',
            if (s.options?.isNotEmpty == true) '选项：${s.options!.join('、')}',
            if (s.catalogType != null) '词库：${s.catalogType}',
            if (s.preKeys.isNotEmpty) '输入前：${s.preKeys.join(' ')}',
            if (s.postKeys.isNotEmpty) '输入后：${s.postKeys.join(' ')}',
            if (s.condition != null) '条件：${s.condition!.toJson()}',
          ].join('\n'))),
        ]),
      ]);
    }
    if (_slots.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.drag_indicator, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            const Text('暂无字段', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('添加第一个字段'),
              onPressed: _addSlot,
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _slots.length,
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) {
              setState(() {
                if (newIndex > oldIndex) newIndex--;
                final item = _slots.removeAt(oldIndex);
                _slots.insert(newIndex, item);
                _reindexSlots();
              });
            },
            itemBuilder: (_, index) => _buildSlotCard(index),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: _selectMode
              ? Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.close),
                      label: const Text('取消选择'),
                      onPressed: () => setState(() {
                        _selectMode = false;
                        _selectedSlots.clear();
                      }),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.copy),
                        label: Text('复制选中 (${_selectedSlots.length})'),
                        onPressed: _selectedSlots.isEmpty
                            ? null
                            : () {
                                setState(() {
                                  final copies = <TemplateSlot>[];
                                  final sortedIndices = _selectedSlots.toList()
                                    ..sort();
                                  for (final idx in sortedIndices) {
                                    final src = _slots[idx];
                                    copies.add(src.copyWith(
                                      key: _uniqueKey(src.key),
                                      label: '${src.label} (副本)',
                                      order: _slots.length + copies.length,
                                    ));
                                  }
                                  _slots.addAll(copies);
                                  _selectMode = false;
                                  _selectedSlots.clear();
                                });
                              },
                      ),
                    ),
                  ],
                )
              : SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('添加字段'),
                    onPressed: _addSlot,
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildSlotCard(int index) {
    final slot = _slots[index];
    final hasCond = slot.condition != null;
    final isSelected = _selectedSlots.contains(index);
    final typeLabel = {
      SlotType.text: '文本',
      SlotType.multiline: '多行',
      SlotType.dropdown: '下拉',
      SlotType.checkbox: '多选',
      SlotType.typedChoice: '键入',
      SlotType.date: '日期',
    }[slot.type];

    return Card(
      key: ValueKey(slot.key),
      margin: AppTheme.cardListMargin,
      color: isSelected
          ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3)
          : null,
      child: ListTile(
        leading: _selectMode
            ? Checkbox(
                value: isSelected,
                onChanged: (_) {
                  setState(() {
                    if (isSelected) {
                      _selectedSlots.remove(index);
                    } else {
                      _selectedSlots.add(index);
                    }
                  });
                },
              )
            : CircleAvatar(
                radius: 16,
                backgroundColor:
                    Theme.of(context).colorScheme.secondaryContainer,
                child: Text('${index + 1}',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.bold)),
              ),
        title:
            Text(slot.label, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Row(
          children: [
            _badge(typeLabel ?? '?', Colors.blue),
            if (slot.preKeys.isNotEmpty) ...[
              const SizedBox(width: 4),
              _badge('←${slot.preKeys.length}', Colors.orange),
            ],
            if (slot.postKeys.isNotEmpty) ...[
              const SizedBox(width: 4),
              _badge('${slot.postKeys.length}→', Colors.green),
            ],
            if (hasCond) ...[
              const SizedBox(width: 4),
              _badge('⚙ 条件', Colors.orange),
            ],
          ],
        ),
        onTap: () => _selectMode
            ? setState(() {
                if (isSelected) {
                  _selectedSlots.remove(index);
                } else {
                  _selectedSlots.add(index);
                }
              })
            : _editSlot(index),
        onLongPress: () {
          setState(() {
            _selectMode = true;
            _selectedSlots.add(index);
          });
        },
        trailing: ReorderableDragStartListener(
          index: index,
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.drag_handle, size: 20, color: Colors.grey),
          ),
        ),
      ),
    );
  }

  Widget _badge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(text,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w500)),
    );
  }
}
