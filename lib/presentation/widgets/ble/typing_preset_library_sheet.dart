import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/typing_action_block.dart';
import '../../../providers/providers.dart';
import '../common/app_toast.dart';
import '../common/control_key_pad.dart';
import 'typing_preset_block_editor_page.dart';

/// 动作预设库（按键精灵）管理与配置弹窗
class TypingPresetLibrarySheet extends ConsumerStatefulWidget {
  final ValueChanged<TypingBlockPreset>? onSelectPreset;
  final String? selectButtonText;

  const TypingPresetLibrarySheet({
    super.key,
    this.onSelectPreset,
    this.selectButtonText,
  });

  static Future<TypingBlockPreset?> show(
    BuildContext context, {
    ValueChanged<TypingBlockPreset>? onSelectPreset,
    String? selectButtonText,
  }) async {
    return showModalBottomSheet<TypingBlockPreset>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TypingPresetLibrarySheet(
        onSelectPreset: onSelectPreset,
        selectButtonText: selectButtonText,
      ),
    );
  }

  @override
  ConsumerState<TypingPresetLibrarySheet> createState() =>
      _TypingPresetLibrarySheetState();
}

class _TypingPresetLibrarySheetState
    extends ConsumerState<TypingPresetLibrarySheet> {
  final _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openEditor({TypingBlockPreset? existing}) async {
    final saved = await TypingPresetBlockEditorPage.show(
      context,
      existing: existing,
    );
    if (saved != null && mounted) {
      await ref.read(typingBlockPresetsProvider.notifier).savePreset(saved);
      if (mounted) {
        showAppToast(context, '已保存预设「${saved.name}」');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allPresets = ref.watch(typingBlockPresetsProvider);
    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? allPresets
        : allPresets.where((p) {
            return p.name.toLowerCase().contains(query) ||
                p.description.toLowerCase().contains(query) ||
                p.stepsPreview.toLowerCase().contains(query);
          }).toList();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.bookmarks_outlined,
                    color: Colors.deepOrange, size: 22),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    '快捷动作管理',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await ref
                        .read(typingBlockPresetsProvider.notifier)
                        .restoreBuiltIns();
                    if (context.mounted) {
                      showAppToast(context, '已恢复默认预设');
                    }
                  },
                  child: const Text('恢复默认', style: TextStyle(fontSize: 12)),
                ),
                const SizedBox(width: 4),
                FilledButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('新建动作', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: () => _openEditor(),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '搜索快捷动作名称、说明或按键...',
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() {});
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.bookmark_border,
                              size: 48, color: Colors.grey),
                          const SizedBox(height: 8),
                          Text(
                            query.isEmpty
                                ? '暂无快捷动作，点击右上角「新建动作」创建'
                                : '未找到匹配的快捷动作',
                            style: const TextStyle(color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (ctx, i) {
                        final preset = filtered[i];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(ctx).colorScheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.deepOrange.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.auto_fix_high,
                                      size: 16, color: Colors.deepOrange),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      preset.name,
                                      style: const TextStyle(
                                        fontSize: 14.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.deepOrange
                                          .withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '${preset.blocks.length} 步',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.deepOrange,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (preset.description.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  preset.description,
                                  style: const TextStyle(
                                      fontSize: 12, color: Colors.black54),
                                ),
                              ],
                              const SizedBox(height: 6),
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.grey.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  preset.stepsPreview,
                                  style: const TextStyle(
                                    fontSize: 11.5,
                                    fontFamily: 'monospace',
                                    color: Colors.blueGrey,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  if (widget.onSelectPreset != null)
                                    FilledButton.tonalIcon(
                                      icon: const Icon(Icons.check, size: 16),
                                      label: Text(
                                        widget.selectButtonText ?? '选用此动作',
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                      style: FilledButton.styleFrom(
                                        visualDensity: VisualDensity.compact,
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                      ),
                                      onPressed: () {
                                        Navigator.pop(ctx, preset);
                                        widget.onSelectPreset!(preset);
                                      },
                                    ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.edit_outlined,
                                        size: 18),
                                    tooltip: '编辑动作',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () =>
                                        _openEditor(existing: preset),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.copy_outlined,
                                        size: 18),
                                    tooltip: '复制动作',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () async {
                                      await ref
                                          .read(typingBlockPresetsProvider
                                              .notifier)
                                          .savePreset(preset.duplicate());
                                      if (ctx.mounted) {
                                        showAppToast(
                                            ctx, '已复制「${preset.name}」');
                                      }
                                    },
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline,
                                        size: 18, color: Colors.red),
                                    tooltip: '删除动作',
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () async {
                                      final confirm = await showDialog<bool>(
                                        context: ctx,
                                        builder: (dCtx) => AlertDialog(
                                          title: const Text('确认删除'),
                                          content:
                                              Text('确定删除快捷动作「${preset.name}」吗？'),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(dCtx, false),
                                              child: const Text('取消'),
                                            ),
                                            FilledButton(
                                              style: FilledButton.styleFrom(
                                                  backgroundColor: Colors.red),
                                              onPressed: () =>
                                                  Navigator.pop(dCtx, true),
                                              child: const Text('删除'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await ref
                                            .read(typingBlockPresetsProvider
                                                .notifier)
                                            .deletePreset(preset.id);
                                        if (ctx.mounted) {
                                          showAppToast(
                                              ctx, '已删除「${preset.name}」');
                                        }
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 动作预设编辑弹窗
class TypingPresetEditorSheet extends StatefulWidget {
  final TypingBlockPreset? existing;

  const TypingPresetEditorSheet({super.key, this.existing});

  static Future<TypingBlockPreset?> show(
    BuildContext context, {
    TypingBlockPreset? existing,
  }) async {
    return showModalBottomSheet<TypingBlockPreset>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TypingPresetEditorSheet(existing: existing),
    );
  }

  @override
  State<TypingPresetEditorSheet> createState() =>
      _TypingPresetEditorSheetState();
}

class _TypingPresetEditorSheetState extends State<TypingPresetEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _descCtrl;
  late final List<TypingActionBlock> _workingBlocks;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _descCtrl = TextEditingController(text: widget.existing?.description ?? '');
    _workingBlocks = widget.existing != null
        ? widget.existing!.blocks.map((b) => b.duplicate()).toList()
        : <TypingActionBlock>[];
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _addStep() async {
    final block = await _pickSubBlock();
    if (block != null && mounted) {
      setState(() => _workingBlocks.add(block));
    }
  }

  Future<TypingActionBlock?> _pickSubBlock() async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('添加动作步骤',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Colors.amber,
                  child: Icon(Icons.keyboard, color: Colors.white, size: 20)),
              title: const Text('系统按键 / 快捷键'),
              subtitle: const Text('如 {ENTER}, {TAB}, {CTRL+V} 等'),
              onTap: () => Navigator.pop(ctx, 'key'),
            ),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Colors.purple,
                  child: Icon(Icons.timer_outlined,
                      color: Colors.white, size: 20)),
              title: const Text('等待延时'),
              subtitle: const Text('等待指定毫秒时间'),
              onTap: () => Navigator.pop(ctx, 'delay'),
            ),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Colors.teal,
                  child: Icon(Icons.edit_note, color: Colors.white, size: 20)),
              title: const Text('固定文本'),
              subtitle: const Text('输入固定文本内容'),
              onTap: () => Navigator.pop(ctx, 'literal'),
            ),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return null;

    if (choice == 'key') {
      final ctrl = TextEditingController(text: '{ENTER}');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('设置按键或组合键'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: '按键代码',
                    hintText: '{ENTER}',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                ControlKeyPad(controller: ctrl, singleKeyMode: true),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确定')),
          ],
        ),
      );
      if (ok == true && ctrl.text.trim().isNotEmpty) {
        return KeyComboBlock(combo: ctrl.text.trim());
      }
    } else if (choice == 'delay') {
      final ctrl = TextEditingController(text: '300');
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('设置等待延时'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '等待时长 (毫秒)',
              hintText: '如 300',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确定')),
          ],
        ),
      );
      if (ok == true) {
        final ms = int.tryParse(ctrl.text.trim()) ?? 300;
        return DelayBlock(durationMs: ms);
      }
    } else if (choice == 'literal') {
      final ctrl = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('输入固定文本'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '文本内容',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确定')),
          ],
        ),
      );
      if (ok == true && ctrl.text.isNotEmpty) {
        return LiteralTextBlock(text: ctrl.text);
      }
    }
    return null;
  }

  String _blockLabel(TypingActionBlock b) {
    if (b is KeyComboBlock) return '按键: ${b.combo}';
    if (b is DelayBlock) return '等待: ${b.durationMs}ms';
    if (b is LiteralTextBlock) return '文本: "${b.text}"';
    if (b is RhythmActionBlock) return '速度: ${b.presetName}';
    return b.type.name;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.88,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_fix_high,
                    color: Colors.deepOrange, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.existing == null ? '新建快捷动作' : '编辑快捷动作',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('取消'),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () {
                    final cleanName = _nameCtrl.text.trim();
                    if (cleanName.isEmpty) {
                      showAppToast(context, '请输入动作名称');
                      return;
                    }
                    if (_workingBlocks.isEmpty) {
                      showAppToast(context, '请至少添加一个动作步骤');
                      return;
                    }
                    final res = TypingBlockPreset(
                      id: widget.existing?.id,
                      name: cleanName,
                      description: _descCtrl.text.trim(),
                      isBuiltIn: widget.existing?.isBuiltIn ?? false,
                      blocks: _workingBlocks,
                    );
                    Navigator.pop(context, res);
                  },
                  child: const Text('保存动作'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '动作名称',
                hintText: '如：打开记事本缓冲、清空当前框',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descCtrl,
              decoration: const InputDecoration(
                labelText: '动作说明 (选填)',
                hintText: '简述该动作的作用',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '动作步骤 (${_workingBlocks.length} 步)',
                  style: const TextStyle(
                      fontSize: 13.5, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                FilledButton.tonalIcon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('添加步骤', style: TextStyle(fontSize: 12)),
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                  ),
                  onPressed: _addStep,
                ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: _workingBlocks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.playlist_add,
                              size: 44, color: Colors.grey),
                          const SizedBox(height: 8),
                          const Text('暂无动作步骤，点击右上角「+ 添加步骤」',
                              style: TextStyle(
                                  fontSize: 12.5, color: Colors.grey)),
                        ],
                      ),
                    )
                  : ReorderableListView.builder(
                      itemCount: _workingBlocks.length,
                      onReorder: (oldIdx, newIdx) {
                        setState(() {
                          if (newIdx > oldIdx) newIdx--;
                          final item = _workingBlocks.removeAt(oldIdx);
                          _workingBlocks.insert(newIdx, item);
                        });
                      },
                      itemBuilder: (ctx, idx) {
                        final b = _workingBlocks[idx];
                        return Card(
                          key: ValueKey(b.id),
                          margin: const EdgeInsets.only(bottom: 6),
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                            side: BorderSide(
                              color: Theme.of(ctx)
                                  .dividerColor
                                  .withValues(alpha: 0.35),
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 2),
                            leading: CircleAvatar(
                              radius: 13,
                              backgroundColor: Colors.deepOrange
                                  .withValues(alpha: 0.14),
                              child: Text(
                                '${idx + 1}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.deepOrange,
                                ),
                              ),
                            ),
                            title: Text(
                              _blockLabel(b),
                              style: const TextStyle(
                                  fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.copy_outlined,
                                      size: 17),
                                  tooltip: '复制步骤',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    setState(() => _workingBlocks.insert(
                                        idx + 1, b.duplicate()));
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      size: 18, color: Colors.red),
                                  tooltip: '删除步骤',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () {
                                    setState(
                                        () => _workingBlocks.removeAt(idx));
                                  },
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
