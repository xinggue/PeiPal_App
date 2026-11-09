import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/catalog_definition.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import '../../widgets/common/control_key_pad.dart';

/// 全屏 / 大卡片式字段编辑器（对齐内容模板风格，字段名称永久展示，整行自适应延展）
class SlotEditorSheet extends StatefulWidget {
  final TemplateSlot? initialSlot;
  final List<TemplateSlot> existingSlots;
  final ValueChanged<TemplateSlot> onSave;
  final VoidCallback? onDelete;

  const SlotEditorSheet({
    super.key,
    this.initialSlot,
    required this.existingSlots,
    required this.onSave,
    this.onDelete,
  });

  static Future<void> show({
    required BuildContext context,
    TemplateSlot? initialSlot,
    required List<TemplateSlot> existingSlots,
    required ValueChanged<TemplateSlot> onSave,
    VoidCallback? onDelete,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SlotEditorSheet(
        initialSlot: initialSlot,
        existingSlots: existingSlots,
        onSave: onSave,
        onDelete: onDelete,
      ),
    );
  }

  @override
  State<SlotEditorSheet> createState() => _SlotEditorSheetState();
}

class _SlotEditorSheetState extends State<SlotEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _dvCtrl;
  late final TextEditingController _optionsCtrl;
  late final TextEditingController _preCtrl;
  late final TextEditingController _postCtrl;

  late SlotType _type;
  Condition? _cond;
  String? _catalogType;

  bool _preKeyPadExpanded = false;
  bool _postKeyPadExpanded = false;

  bool get _isEditing => widget.initialSlot != null;

  @override
  void initState() {
    super.initState();
    final s = widget.initialSlot;
    // 统一以用户看到的 label 为主要展示名称；若无 label 则 fallback 到 key
    final initialName = (s != null && s.label.isNotEmpty) ? s.label : (s?.key ?? '');
    _nameCtrl = TextEditingController(text: initialName);
    _dvCtrl = TextEditingController(text: s?.defaultValue ?? '');
    _optionsCtrl = TextEditingController(text: s?.options?.join('\n') ?? '');
    _preCtrl = TextEditingController(text: s?.preKeys.join(', ') ?? '');
    _postCtrl = TextEditingController(text: s?.postKeys.join(', ') ?? '');
    _type = s?.type ?? SlotType.text;
    _cond = s?.condition;
    _catalogType = s?.catalogType;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _dvCtrl.dispose();
    _optionsCtrl.dispose();
    _preCtrl.dispose();
    _postCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showAppToast(context, '字段名称不能为空');
      return;
    }

    // 若原有 slot 存在 key 则复用原有 key；若是新增字段，直接以 name 作为 key
    final finalKey = widget.initialSlot?.key.isNotEmpty == true
        ? widget.initialSlot!.key
        : name;

    final preKeys = _preCtrl.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    final postKeys = _postCtrl.text
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final options = (_type == SlotType.dropdown ||
            _type == SlotType.checkbox ||
            _type == SlotType.typedChoice)
        ? _optionsCtrl.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList()
        : null;

    final updated = (widget.initialSlot ??
            TemplateSlot(
              key: finalKey,
              label: name,
              type: _type,
              order: widget.existingSlots.length,
            ))
        .copyWith(
      key: finalKey,
      label: name,
      type: _type,
      defaultValue: _dvCtrl.text.trim().isEmpty ? null : _dvCtrl.text.trim(),
      clearDefaultValue: _dvCtrl.text.trim().isEmpty,
      options: options,
      clearOptions: options == null || options.isEmpty,
      preKeys: preKeys,
      postKeys: postKeys,
      condition: _cond,
      clearCondition: _cond == null,
      catalogType: _catalogType,
      clearCatalogType: _catalogType == null || _catalogType!.isEmpty,
    );

    widget.onSave(updated);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_isEditing ? '配置字段属性' : '添加新字段'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          TextButton(
            onPressed: _submit,
            child: const Text('保存', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          children: [
            // 1. 字段基本信息（整行延展自适应，名称永久置顶）
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(40)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '字段名称',
                      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueGrey),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _nameCtrl,
                      minLines: 1,
                      maxLines: null, // 根据内容自动向下延展
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                      decoration: const InputDecoration(
                        hintText: '如：标题、正文……',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      ),
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<SlotType>(
                      initialValue: _type,
                      decoration: const InputDecoration(
                        labelText: '输入形式',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: SlotType.text, child: Text('单行文本')),
                        DropdownMenuItem(value: SlotType.multiline, child: Text('多行文本')),
                        DropdownMenuItem(value: SlotType.dropdown, child: Text('下拉点选')),
                        DropdownMenuItem(value: SlotType.checkbox, child: Text('复选框组')),
                        DropdownMenuItem(value: SlotType.typedChoice, child: Text('按键选录')),
                        DropdownMenuItem(value: SlotType.date, child: Text('日期字段')),
                      ],
                      onChanged: (v) => setState(() => _type = v ?? SlotType.text),
                    ),
                    if (_type == SlotType.dropdown ||
                        _type == SlotType.checkbox ||
                        _type == SlotType.typedChoice) ...[
                      const SizedBox(height: 16),
                      const Text(
                        '可选列表选项（每行一个）',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.grey),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _optionsCtrl,
                        minLines: 2,
                        maxLines: null,
                        decoration: const InputDecoration(
                          hintText: '如：\n无\n有\n轻度\n重度',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    TextField(
                      controller: _dvCtrl,
                      minLines: 1,
                      maxLines: null,
                      decoration: const InputDecoration(
                        labelText: '默认填充值（可选）',
                        hintText: '未生成时使用的缺省内容',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 1.5 关联标准词库
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                    color: Theme.of(context).dividerColor.withAlpha(40)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Consumer(
                  builder: (context, ref, _) {
                    final catalogs = (ref.watch(catalogsProvider).valueOrNull ??
                            const <CatalogDefinition>[])
                        .where((c) => c.isEnabled)
                        .toList();
                    return DropdownButtonFormField<String?>(
                      initialValue: catalogs.any((c) => c.id == _catalogType)
                          ? _catalogType
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '关联标准词库',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('不关联'),
                        ),
                        for (final c in catalogs)
                          DropdownMenuItem<String?>(
                            value: c.id,
                            child: Text(c.name),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _catalogType = value),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 2. 键盘与输入动作（支持系统组合键与自由组合）
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(40)),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.keyboard_outlined, size: 20, color: Colors.teal),
                        SizedBox(width: 8),
                        Text(
                          '按键输入动作',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _preCtrl,
                            maxLines: 1,
                            decoration: const InputDecoration(
                              labelText: '输入前动作',
                              hintText: '如：{TAB}, {CTRL+A}, {DEL}',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          icon: Icon(_preKeyPadExpanded ? Icons.close : Icons.add, size: 16),
                          label: Text(_preKeyPadExpanded ? '收起' : '添加按键'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          onPressed: () => setState(() => _preKeyPadExpanded = !_preKeyPadExpanded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ControlKeyPad(
                      controller: _preCtrl,
                      label: '快捷按键与系统组合键',
                      isExpanded: _preKeyPadExpanded,
                      onExpansionChanged: (v) => setState(() => _preKeyPadExpanded = v),
                    ),
                    const SizedBox(height: 28),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _postCtrl,
                            maxLines: 1,
                            decoration: const InputDecoration(
                              labelText: '输入后动作',
                              hintText: '如：{ENTER}, {TAB}',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          icon: Icon(_postKeyPadExpanded ? Icons.close : Icons.add, size: 16),
                          label: Text(_postKeyPadExpanded ? '收起' : '添加按键'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                          ),
                          onPressed: () => setState(() => _postKeyPadExpanded = !_postKeyPadExpanded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ControlKeyPad(
                      controller: _postCtrl,
                      label: '快捷按键与系统组合键',
                      isExpanded: _postKeyPadExpanded,
                      onExpansionChanged: (v) => setState(() => _postKeyPadExpanded = v),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // 3. 跳题与显示条件
            Card(
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: Theme.of(context).dividerColor.withAlpha(40)),
              ),
              child: ExpansionTile(
                title: Text(
                  '字段跳题与依赖条件 ${_cond != null ? "⚙ (已生效)" : ""}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: _cond != null ? Colors.blue : null,
                  ),
                ),
                initiallyExpanded: _cond != null,
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  _buildConditionEditor(),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // 底部操作区：大保存按钮与删除按钮
            Row(
              children: [
                if (_isEditing && widget.onDelete != null) ...[
                  OutlinedButton.icon(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: const Text('删除', style: TextStyle(color: Colors.red)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                    ),
                    onPressed: () {
                      widget.onDelete!();
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: FilledButton.icon(
                    icon: const Icon(Icons.check),
                    label: Text(_isEditing ? '保存字段配置' : '确定添加字段',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: _submit,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildConditionEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('启用显示条件', style: TextStyle(fontSize: 13)),
          value: _cond != null,
          onChanged: (v) {
            setState(() {
              _cond = v
                  ? Condition(
                      field: widget.existingSlots.firstOrNull?.key ?? '',
                      operator: ConditionOperator.equals,
                    )
                  : null;
            });
          },
        ),
        if (_cond != null) ...[
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _cond!.field.isEmpty ? null : _cond!.field,
            decoration: const InputDecoration(
              labelText: '控制前置字段',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: widget.existingSlots
                .where((s) => s.key != widget.initialSlot?.key)
                .map((s) => DropdownMenuItem(
                      value: s.key,
                      child: Text(s.label.isNotEmpty ? s.label : s.key),
                    ))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() {
                  _cond = Condition(
                    field: v,
                    operator: _cond!.operator,
                    value: _cond!.value,
                    valueList: _cond!.valueList,
                  );
                });
              }
            },
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<ConditionOperator>(
            initialValue: _cond!.operator,
            decoration: const InputDecoration(
              labelText: '逻辑判断关系',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(value: ConditionOperator.equals, child: Text('等于')),
              DropdownMenuItem(value: ConditionOperator.notEquals, child: Text('不等于')),
              DropdownMenuItem(value: ConditionOperator.contains, child: Text('包含')),
              DropdownMenuItem(value: ConditionOperator.notEmpty, child: Text('非空')),
              DropdownMenuItem(value: ConditionOperator.isEmpty, child: Text('为空')),
              DropdownMenuItem(value: ConditionOperator.greaterThan, child: Text('大于 (数值)')),
              DropdownMenuItem(value: ConditionOperator.lessThan, child: Text('小于 (数值)')),
              DropdownMenuItem(value: ConditionOperator.inList, child: Text('属于列表之一')),
            ],
            onChanged: (op) {
              if (op != null) {
                setState(() {
                  _cond = Condition(
                    field: _cond!.field,
                    operator: op,
                    value: _cond!.value,
                    valueList: _cond!.valueList,
                  );
                });
              }
            },
          ),
          if (_cond!.operator != ConditionOperator.notEmpty &&
              _cond!.operator != ConditionOperator.isEmpty) ...[
            const SizedBox(height: 10),
            TextFormField(
              initialValue: _cond!.value ?? _cond!.valueList?.join(',') ?? '',
              decoration: InputDecoration(
                labelText: _cond!.operator == ConditionOperator.inList
                    ? '比对值列表 (英文逗号分隔)'
                    : '目标比对值',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (val) {
                if (_cond!.operator == ConditionOperator.inList) {
                  _cond = Condition(
                    field: _cond!.field,
                    operator: _cond!.operator,
                    valueList: val.split(',').map((s) => s.trim()).toList(),
                  );
                } else {
                  _cond = Condition(
                    field: _cond!.field,
                    operator: _cond!.operator,
                    value: val,
                  );
                }
              },
            ),
          ],
        ],
      ],
    );
  }
}
