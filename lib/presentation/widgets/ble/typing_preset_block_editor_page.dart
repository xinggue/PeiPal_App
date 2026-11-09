import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/typing_action_block.dart';
import '../../../providers/providers.dart';
import '../common/app_toast.dart';
import '../common/control_key_pad.dart';

/// 完整时间线积木式快捷动作预设编辑器 (纯正输入流程时间线积木体验)
class TypingPresetBlockEditorPage extends ConsumerStatefulWidget {
  final TypingBlockPreset? existing;

  const TypingPresetBlockEditorPage({super.key, this.existing});

  static Future<TypingBlockPreset?> show(
    BuildContext context, {
    TypingBlockPreset? existing,
  }) {
    return Navigator.push<TypingBlockPreset>(
      context,
      MaterialPageRoute(
        builder: (_) => TypingPresetBlockEditorPage(existing: existing),
      ),
    );
  }

  @override
  ConsumerState<TypingPresetBlockEditorPage> createState() =>
      _TypingPresetBlockEditorPageState();
}

class _TypingPresetBlockEditorPageState
    extends ConsumerState<TypingPresetBlockEditorPage> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late List<TypingActionBlock> _blocks;
  String? _selectedBlockId;
  final List<List<TypingActionBlock>> _history = [];

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');
    _blocks = widget.existing != null
        ? widget.existing!.blocks.map((b) => b.duplicate()).toList()
        : <TypingActionBlock>[];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  void _pushHistory() {
    _history.add(_blocks.map((b) => b.duplicate()).toList());
    if (_history.length > 25) _history.removeAt(0);
  }

  void _updateBlocks(List<TypingActionBlock> next, {bool record = true}) {
    if (record) _pushHistory();
    setState(() => _blocks = next);
  }

  void _undo() {
    if (_history.isEmpty) return;
    final prev = _history.removeLast();
    _updateBlocks(prev, record: false);
    showAppToast(context, '已撤销上一步操作');
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      showAppToast(context, '请输入预设名称');
      return;
    }
    if (_blocks.isEmpty) {
      showAppToast(context, '请至少添加一个动作步骤');
      return;
    }

    final preset = TypingBlockPreset(
      id: widget.existing?.id,
      name: name,
      description: _descCtrl.text.trim(),
      isBuiltIn: widget.existing?.isBuiltIn ?? false,
      blocks: _blocks,
    );

    await ref.read(typingBlockPresetsProvider.notifier).savePreset(preset);
    if (mounted) {
      showAppToast(context, '已保存动作预设「${preset.name}」');
      Navigator.pop(context, preset);
    }
  }

  void _insertBlockAt(int insertIndex, TypingActionBlock newBlock) {
    final next = List<TypingActionBlock>.from(_blocks);
    final safeIdx = insertIndex.clamp(0, next.length);
    next.insert(safeIdx, newBlock);
    _updateBlocks(next);
    setState(() => _selectedBlockId = newBlock.id);
  }

  Future<void> _showAddBlockPicker({required int insertIndex}) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '选择动作步骤类型',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.amber,
                child: Icon(Icons.keyboard_rounded, color: Colors.white, size: 20),
              ),
              title: const Text('系统按键 / 快捷键'),
              subtitle: const Text('如 {WIN+R}, {CTRL+C}, {CTRL+V}, {TAB}, {ENTER}'),
              onTap: () => Navigator.pop(ctx, 'key'),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.teal,
                child: Icon(Icons.edit_note_rounded, color: Colors.white, size: 20),
              ),
              title: const Text('固定文本'),
              subtitle: const Text('输出固定文本内容 (如 notepad, cmd)'),
              onTap: () => Navigator.pop(ctx, 'literal'),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.purple,
                child: Icon(Icons.timer_outlined, color: Colors.white, size: 20),
              ),
              title: const Text('等待延时'),
              subtitle: const Text('等待软件界面或焦点响应 (如 300ms)'),
              onTap: () => Navigator.pop(ctx, 'delay'),
            ),
            ListTile(
              leading: const CircleAvatar(
                backgroundColor: Colors.deepOrange,
                child: Icon(Icons.speed_rounded, color: Colors.white, size: 20),
              ),
              title: const Text('切换输入速度 (动态调参)'),
              subtitle: const Text('中途临时改变芯片打字时序'),
              onTap: () => Navigator.pop(ctx, 'rhythm'),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return;

    TypingActionBlock? newBlock;
    if (choice == 'key') {
      newBlock = await _createKeyComboBlock();
    } else if (choice == 'literal') {
      newBlock = await _createLiteralBlock();
    } else if (choice == 'delay') {
      newBlock = await _createDelayBlock();
    } else if (choice == 'rhythm') {
      newBlock = await _createRhythmBlock();
    }

    if (newBlock != null && mounted) {
      _insertBlockAt(insertIndex, newBlock);
    }
  }

  Future<KeyComboBlock?> _createKeyComboBlock({String initialCombo = '{ENTER}'}) async {
    final comboCtrl = TextEditingController(text: initialCombo);
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 14,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.keyboard_rounded, color: Colors.amber, size: 22),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('设置按键或组合快捷键',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 4),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('确定'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: comboCtrl,
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
                decoration: const InputDecoration(
                  labelText: '按键或组合键代码',
                  hintText: '{ENTER}',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 10),
              ControlKeyPad(
                controller: comboCtrl,
                label: '快捷按键与全键盘',
                collapsible: false,
                initiallyExpanded: true,
                singleKeyMode: true,
              ),
            ],
          ),
        ),
      ),
    );

    if (ok == true && comboCtrl.text.trim().isNotEmpty) {
      return KeyComboBlock(combo: comboCtrl.text.trim());
    }
    return null;
  }

  Future<LiteralTextBlock?> _createLiteralBlock({String initialText = 'notepad'}) async {
    final textCtrl = TextEditingController(text: initialText);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置固定文本动作'),
        content: TextField(
          controller: textCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '固定输入内容',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok == true && textCtrl.text.isNotEmpty) {
      return LiteralTextBlock(text: textCtrl.text);
    }
    return null;
  }

  Future<DelayBlock?> _createDelayBlock({int initialMs = 300}) async {
    final msCtrl = TextEditingController(text: initialMs.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置等待延时动作'),
        content: TextField(
          controller: msCtrl,
          keyboardType: TextInputType.number,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '等待时间 (毫秒)',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok == true) {
      return DelayBlock(durationMs: int.tryParse(msCtrl.text.trim()) ?? 300);
    }
    return null;
  }

  Future<RhythmActionBlock?> _createRhythmBlock({RhythmActionBlock? existing}) async {
    final presets = ref.read(timingPresetsProvider);
    String selId = existing != null && presets.any((p) => p.name == existing.presetName)
        ? presets.firstWhere((p) => p.name == existing.presetName).id
        : presets.first.id;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('设置切换节奏动作'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('在执行到此步骤时，向芯片发送动态调参指令：',
                  style: TextStyle(fontSize: 12.5, color: Colors.grey)),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: selId,
                decoration: const InputDecoration(
                  labelText: '选择时序预设',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: presets
                    .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text('${p.name} · ${p.estimatedCharsPerSec.toStringAsFixed(0)}字/s'),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialog(() => selId = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('确定')),
          ],
        ),
      ),
    );

    if (ok == true) {
      final target = presets.firstWhere((p) => p.id == selId);
      return RhythmActionBlock(
        presetName: target.name,
        params: Map.of(target.values),
      );
    }
    return null;
  }

  void _editBlock(int index, TypingActionBlock block) async {
    final next = List<TypingActionBlock>.from(_blocks);

    if (block is KeyComboBlock) {
      final updated = await _createKeyComboBlock(initialCombo: block.combo);
      if (updated != null && mounted) {
        next[index] = updated;
        _updateBlocks(next);
      }
    } else if (block is DelayBlock) {
      final updated = await _createDelayBlock(initialMs: block.durationMs);
      if (updated != null && mounted) {
        next[index] = updated;
        _updateBlocks(next);
      }
    } else if (block is LiteralTextBlock) {
      final updated = await _createLiteralBlock(initialText: block.text);
      if (updated != null && mounted) {
        next[index] = updated;
        _updateBlocks(next);
      }
    } else if (block is RhythmActionBlock) {
      final updated = await _createRhythmBlock(existing: block);
      if (updated != null && mounted) {
        next[index] = updated;
        _updateBlocks(next);
      }
    }
  }

  void _openBlockMenu(int index, TypingActionBlock block) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '第 ${index + 1} 步 · ${_blockTitle(block)}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('修改参数'),
              onTap: () {
                Navigator.pop(ctx);
                _editBlock(index, block);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制并向下插入'),
              onTap: () {
                Navigator.pop(ctx);
                final next = List<TypingActionBlock>.from(_blocks);
                next.insert(index + 1, block.duplicate());
                _updateBlocks(next);
              },
            ),
            if (index > 0)
              ListTile(
                leading: const Icon(Icons.arrow_upward),
                title: const Text('向上移动一步'),
                onTap: () {
                  Navigator.pop(ctx);
                  final next = List<TypingActionBlock>.from(_blocks);
                  final item = next.removeAt(index);
                  next.insert(index - 1, item);
                  _updateBlocks(next);
                },
              ),
            if (index < _blocks.length - 1)
              ListTile(
                leading: const Icon(Icons.arrow_downward),
                title: const Text('向下移动一步'),
                onTap: () {
                  Navigator.pop(ctx);
                  final next = List<TypingActionBlock>.from(_blocks);
                  final item = next.removeAt(index);
                  next.insert(index + 1, item);
                  _updateBlocks(next);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除此步骤', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                final next = List<TypingActionBlock>.from(_blocks)..removeAt(index);
                _updateBlocks(next);
                setState(() => _selectedBlockId = null);
              },
            ),
          ],
        ),
      ),
    );
  }

  String _blockTitle(TypingActionBlock block) {
    if (block is KeyComboBlock) return block.combo;
    if (block is LiteralTextBlock) return '文本: "${block.text}"';
    if (block is DelayBlock) return '等待 ${block.durationMs} ms';
    if (block is RhythmActionBlock) return '切换为 [${block.presetName}] 节奏';
    return block.type.name;
  }

  Widget _buildBrickShape({
    required int index,
    required TypingActionBlock block,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);

    final (Color color, IconData icon, String typeTitle) = switch (block.type) {
      ActionBlockType.keyCombo => (Colors.amber[800]!, Icons.keyboard_rounded, '系统快捷键'),
      ActionBlockType.literalText => (Colors.teal, Icons.edit_note_rounded, '固定文本'),
      ActionBlockType.delay => (Colors.purple, Icons.timer_outlined, '等待延时'),
      ActionBlockType.rhythm => (Colors.deepOrange, Icons.speed_rounded, '切换节奏'),
      _ => (Colors.blueGrey, Icons.widgets_outlined, '自定义动作'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isSelected ? color.withValues(alpha: 0.12) : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? color : color.withValues(alpha: 0.35),
          width: isSelected ? 2.0 : 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: isSelected ? 0.2 : 0.05),
            blurRadius: isSelected ? 6 : 2,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _blockTitle(block),
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                ),
                Text(
                  typeTitle,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ],
            ),
          ),
          if (isSelected)
            IconButton(
              icon: const Icon(Icons.more_horiz),
              tooltip: '步骤菜单',
              onPressed: () => _openBlockMenu(index, block),
            ),
        ],
      ),
    );
  }

  Widget _buildInsertPlusButton({
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Center(
        child: SizedBox(
          width: 28,
          height: 28,
          child: IconButton.filled(
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.add, size: 16),
            tooltip: tooltip,
            onPressed: onPressed,
          ),
        ),
      ),
    );
  }

  Widget _buildTimelineItem({
    required int index,
    required int totalCount,
    required TypingActionBlock block,
  }) {
    final isSelected = _selectedBlockId == block.id;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 32,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 2.5,
                    color: Colors.blueGrey.withValues(alpha: 0.25),
                  ),
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.blueGrey[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (isSelected)
                        _buildInsertPlusButton(
                          tooltip: '在此步骤之前插入动作',
                          onPressed: () => _showAddBlockPicker(insertIndex: index),
                        ),
                      GestureDetector(
                        onTap: () {
                          setState(() {
                            _selectedBlockId = isSelected ? null : block.id;
                          });
                        },
                        child: _buildBrickShape(
                          index: index,
                          block: block,
                          isSelected: isSelected,
                        ),
                      ),
                      if (isSelected)
                        _buildInsertPlusButton(
                          tooltip: '在此步骤之后插入动作',
                          onPressed: () => _showAddBlockPicker(insertIndex: index + 1),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? '新建快捷动作' : '编辑快捷动作'),
        actions: [
          IconButton(
            icon: const Icon(Icons.undo),
            tooltip: '撤销',
            onPressed: _history.isNotEmpty ? _undo : null,
          ),
          IconButton(
            icon: const Icon(Icons.check),
            tooltip: '保存',
            onPressed: _save,
          ),
        ],
      ),
      body: Column(
        children: [
          // 顶部名称与说明配置卡片
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Card(
              margin: EdgeInsets.zero,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameCtrl,
                      decoration: const InputDecoration(
                        labelText: '动作名称',
                        hintText: '如：打开记事本缓冲、清空当前框',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _descCtrl,
                      decoration: const InputDecoration(
                        labelText: '动作说明 (选填)',
                        hintText: '简短描述该动作的作用',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                const Icon(Icons.timeline_rounded, size: 18, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Text(
                  '动作步骤序列 (${_blocks.length} 步)',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加动作', style: TextStyle(fontSize: 12)),
                  onPressed: () => _showAddBlockPicker(insertIndex: _blocks.length),
                ),
              ],
            ),
          ),

          // 核心时间线动作列表 (与输入流程完全相同的动作质感与交互)
          Expanded(
            child: _blocks.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.view_in_ar_outlined, size: 56, color: Colors.grey),
                        const SizedBox(height: 12),
                        const Text('暂无动作步骤', style: TextStyle(color: Colors.grey)),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('添加第一个动作'),
                          onPressed: () => _showAddBlockPicker(insertIndex: 0),
                        ),
                      ],
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 80),
                    itemCount: _blocks.length,
                    buildDefaultDragHandles: false,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex--;
                        final item = _blocks.removeAt(oldIndex);
                        _blocks.insert(newIndex, item);
                        _updateBlocks(_blocks);
                      });
                    },
                    itemBuilder: (context, index) {
                      final block = _blocks[index];
                      return ReorderableDelayedDragStartListener(
                        key: ValueKey(block.id),
                        index: index,
                        child: _buildTimelineItem(
                          index: index,
                          totalCount: _blocks.length,
                          block: block,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
