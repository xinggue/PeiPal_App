import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/ble/timing_params.dart';
import '../../../domain/models/template.dart';
import '../../../domain/models/typing_action_block.dart';
import '../../../domain/models/typing_profile.dart';
import '../../../providers/providers.dart';
import '../../widgets/ble/typing_preset_library_sheet.dart';
import '../../widgets/common/control_key_pad.dart';

/// Timeline-driven Low-Code Block Editor (按键精灵式时间线积木流).
class TypingFlowTab extends ConsumerStatefulWidget {
  final List<TemplateSlot> slots;
  final List<TypingProfile> profiles;
  final ValueChanged<List<TypingProfile>> onChanged;

  const TypingFlowTab({
    super.key,
    required this.slots,
    required this.profiles,
    required this.onChanged,
  });

  @override
  ConsumerState<TypingFlowTab> createState() => _TypingFlowTabState();
}

class _TypingFlowTabState extends ConsumerState<TypingFlowTab> {
  int _selectedIndex = 0;
  String? _selectedBlockId; // 当前选中的积木ID，选中时在上下显示加号
  final List<List<TypingActionBlock>> _history = []; // 撤销历史栈

  @override
  void initState() {
    super.initState();
    _ensureCurrentBlocksSolidified();
  }

  @override
  void didUpdateWidget(covariant TypingFlowTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _ensureCurrentBlocksSolidified();
  }

  /// 确保当前方案的 blocks 被立即固化保存，避免每次 build 生成不同随机 ID 导致无法点击选中
  void _ensureCurrentBlocksSolidified() {
    if (_current.blocks.isEmpty && widget.slots.isNotEmpty) {
      final defaultBlocks = _current.effectiveBlocks(widget.slots);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _current.blocks.isEmpty) {
          _updateCurrentBlocks(defaultBlocks, recordHistory: false);
        }
      });
    }
  }

  TypingProfile get _current {
    if (_selectedIndex >= widget.profiles.length) {
      return widget.profiles.first;
    }
    return widget.profiles[_selectedIndex];
  }

  void _updateCurrent(TypingProfile updated) {
    final list = List<TypingProfile>.from(widget.profiles);
    list[_selectedIndex] = updated;
    widget.onChanged(list);
  }

  void _pushHistorySnapshot() {
    _history.add(_current
        .effectiveBlocks(widget.slots)
        .map((b) => b.duplicate())
        .toList());
    if (_history.length > 30) _history.removeAt(0);
  }

  void _updateCurrentBlocks(List<TypingActionBlock> newBlocks,
      {bool recordHistory = true}) {
    if (recordHistory) {
      _pushHistorySnapshot();
    }
    _updateCurrent(_current.copyWith(blocks: newBlocks));
  }

  void _undo() {
    if (_history.isEmpty) return;
    final previous = _history.removeLast();
    _updateCurrentBlocks(previous, recordHistory: false);
    setState(() {});
    showAppToast(context, '已撤销上一步操作');
  }

  void _addProfile() async {
    final nameCtrl =
        TextEditingController(text: '方案 ${widget.profiles.length + 1}');
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建输入方案'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '方案名称',
            hintText: '如：记事本缓冲流、条目循环流',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      final newP = TypingProfile(name: name);
      final list = List<TypingProfile>.from(widget.profiles)
        ..add(newP.copyWith(blocks: newP.effectiveBlocks(widget.slots)));
      widget.onChanged(list);
      setState(() => _selectedIndex = list.length - 1);
    }
  }

  void _duplicateCurrent() {
    final cur = _current;
    final copy = cur.duplicate('${cur.name} (副本)');
    final list = List<TypingProfile>.from(widget.profiles)..add(copy);
    widget.onChanged(list);
    setState(() => _selectedIndex = list.length - 1);
  }

  void _renameCurrent() async {
    final cur = _current;
    final nameCtrl = TextEditingController(text: cur.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名方案'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: '方案名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (name != null && name.isNotEmpty) {
      _updateCurrent(cur.copyWith(name: name));
    }
  }

  void _deleteCurrent() async {
    if (widget.profiles.length <= 1) {
      showAppToast(context, '至少保留一套输入方案');
      return;
    }

    final cur = _current;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除方案'),
        content: Text('确认删除输入方案「${cur.name}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (ok == true) {
      final list = List<TypingProfile>.from(widget.profiles)
        ..removeAt(_selectedIndex);
      widget.onChanged(list);
      setState(() {
        if (_selectedIndex >= list.length) {
          _selectedIndex = list.length - 1;
        }
      });
    }
  }

  void _editCurrentProfileTiming() async {
    final cur = _current;
    int delayMs = cur.postKeySettleMs.clamp(300, 2000);
    final holdCtrl = TextEditingController(text: cur.keyComboHoldMs.toString());
    const quickDelays = [300, 500, 800, 1000, 1500, 2000];

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final primary = Theme.of(ctx).colorScheme.primary;
          return AlertDialog(
            title: Text('方案参数 · ${cur.name}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '配置各动作步骤之间（输入前动作、输入内容、输入后动作及相邻积木之间）自动插入的系统反应时间。该间隔独立于键盘打字速度，且不在积木列表中额外显示：',
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                    decoration: BoxDecoration(
                      color: primary.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: primary.withValues(alpha: 0.25)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.timer_outlined, size: 16),
                            const SizedBox(width: 6),
                            const Expanded(
                              child: Text(
                                '步骤间系统反应延时',
                                style: TextStyle(
                                    fontSize: 13, fontWeight: FontWeight.bold),
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: primary,
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(
                                '$delayMs ms',
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: delayMs.toDouble(),
                          min: 300,
                          max: 2000,
                          divisions: 34,
                          label: '$delayMs ms',
                          onChanged: (v) {
                            setDialog(() => delayMs = (v / 50).round() * 50);
                          },
                        ),
                        const Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('300ms (默认)',
                                style:
                                    TextStyle(fontSize: 10.5, color: Colors.grey)),
                            Text('2000ms',
                                style:
                                    TextStyle(fontSize: 10.5, color: Colors.grey)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: quickDelays.map((ms) {
                      final selected = delayMs == ms;
                      return ChoiceChip(
                        label: Text(
                          ms == 300 ? '300ms (默认)' : '${ms}ms',
                          style: const TextStyle(fontSize: 11),
                        ),
                        selected: selected,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) {
                          setDialog(() => delayMs = ms);
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: holdCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: '组合按键按住时长 (毫秒)',
                      hintText: '如 50ms',
                      helperText: 'Ctrl/Alt等修饰键按下后保持的时长',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );

    if (ok == true) {
      final updated = cur.copyWith(
        keyComboHoldMs:
            (int.tryParse(holdCtrl.text.trim()) ?? 50).clamp(0, 5000),
        postKeySettleMs: delayMs.clamp(300, 2000),
      );
      final list = List<TypingProfile>.from(widget.profiles);
      list[_selectedIndex] = updated;
      widget.onChanged(list);
      if (mounted) {
        setState(() {});
        showAppToast(context, '已更新方案参数（步骤间延时 ${updated.postKeySettleMs}ms）');
      }
    }
  }

  void _confirmReset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置输入步骤'),
        content: const Text('确定将当前方案的所有步骤重置为「按字段顺序常规录入」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('重置')),
        ],
      ),
    );
    if (ok == true) _resetToDefaultSequence();
  }

  void _resetToDefaultSequence() {
    final defaultBlocks = widget.slots.map((s) {
      return FieldInputBlock(
        fieldKey: s.key,
        preKeys: s.preKeys,
        postKeys: s.postKeys,
      );
    }).toList();
    _updateCurrentBlocks(defaultBlocks);
    showAppToast(context, '已恢复为所有字段顺序录入');
  }

  /// Show the block creation sheet at a specific index in the block list.
  Future<void> _showAddBlockPicker({required int insertIndex}) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Consumer(
        builder: (ctx, sheetRef, _) {
          final presets = sheetRef.watch(typingBlockPresetsProvider);
          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        '选择要插入的输入动作',
                        style:
                            TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.blue,
                        child: Icon(Icons.text_fields,
                            color: Colors.white, size: 20),
                      ),
                      title: const Text('录入文书字段'),
                      subtitle: const Text('从生成的文书中提取指定字段的值输出'),
                      onTap: () => Navigator.pop(ctx, 'field'),
                    ),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.amber,
                        child:
                            Icon(Icons.keyboard, color: Colors.white, size: 20),
                      ),
                      title: const Text('系统按键 / 快捷键'),
                      subtitle: const Text(
                          '{WIN+R}, {CTRL+C}, {CTRL+V}, {TAB}, {ENTER} 等'),
                      onTap: () => Navigator.pop(ctx, 'key'),
                    ),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.teal,
                        child: Icon(Icons.edit_note,
                            color: Colors.white, size: 20),
                      ),
                      title: const Text('固定文本'),
                      subtitle: const Text('输出写死的文字 (如 notepad)'),
                      onTap: () => Navigator.pop(ctx, 'literal'),
                    ),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.purple,
                        child: Icon(Icons.timer_outlined,
                            color: Colors.white, size: 20),
                      ),
                      title: const Text('等待延时'),
                      subtitle: const Text('暂停片刻给宿主机软件响应时间 (如 300ms)'),
                      onTap: () => Navigator.pop(ctx, 'delay'),
                    ),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.deepOrange,
                        child: Icon(Icons.speed_rounded,
                            color: Colors.white, size: 20),
                      ),
                      title: const Text('切换输入节奏 (动态调速)'),
                      subtitle: const Text('中途注入芯片时序指令，切换为稳妥/极速模式'),
                      onTap: () => Navigator.pop(ctx, 'rhythm'),
                    ),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.green,
                        child:
                            Icon(Icons.repeat, color: Colors.white, size: 20),
                      ),
                      title: const Text('列表循环 (逐条录入)'),
                      subtitle: const Text('逐行拆分条目，循环执行内部按键动作'),
                      onTap: () => Navigator.pop(ctx, 'forEach'),
                    ),
                    ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.indigo,
                        child: Icon(Icons.folder_zip_outlined,
                            color: Colors.white, size: 20),
                      ),
                      title: const Text('新建分组容器'),
                      subtitle: const Text('打包一组操作，支持整体管理与存为预设'),
                      onTap: () => Navigator.pop(ctx, 'group'),
                    ),
                    if (presets.isNotEmpty) ...[
                      const Divider(height: 16),
                      const Padding(
                        padding: EdgeInsets.symmetric(
                            horizontal: 16, vertical: 4),
                        child: Row(
                          children: [
                            Icon(Icons.bookmarks_outlined,
                                size: 16, color: Colors.deepOrange),
                            SizedBox(width: 6),
                            Text(
                              '插入快捷动作预设',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: Colors.deepOrange,
                              ),
                            ),
                          ],
                        ),
                      ),
                      for (final preset in presets)
                        ListTile(
                          leading: const CircleAvatar(
                            backgroundColor: Colors.deepOrange,
                            child: Icon(Icons.auto_fix_high,
                                color: Colors.white, size: 18),
                          ),
                          title: Text(
                            preset.name,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            preset.description.isNotEmpty
                                ? '${preset.description} · ${preset.stepsPreview}'
                                : preset.stepsPreview,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing: const Icon(Icons.add_circle_outline,
                              size: 20, color: Colors.deepOrange),
                          onTap: () =>
                              Navigator.pop(ctx, 'usePreset:${preset.id}'),
                        ),
                      const SizedBox(height: 12),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (choice == null || !mounted) return;

    TypingActionBlock? newBlock;
    if (choice == 'field') {
      newBlock = await _createFieldBlock();
    } else if (choice == 'key') {
      newBlock = await _createKeyComboBlock();
    } else if (choice == 'literal') {
      newBlock = await _createLiteralBlock();
    } else if (choice == 'delay') {
      newBlock = await _createDelayBlock();
    } else if (choice == 'rhythm') {
      newBlock = await _createRhythmBlock();
    } else if (choice == 'forEach') {
      newBlock = await _createForEachBlock();
    } else if (choice == 'group') {
      newBlock = await _createGroupBlock();
    } else if (choice.startsWith('usePreset:')) {
      final presetId = choice.substring('usePreset:'.length);
      final presets = ref.read(typingBlockPresetsProvider);
      final target = presets.where((p) => p.id == presetId).firstOrNull;
      if (target != null) {
        newBlock = target.toGroupBlock();
      }
    }

    if (newBlock != null && mounted) {
      _insertBlockAt(insertIndex, newBlock);
    }
  }

  void _insertBlockAt(int insertIndex, TypingActionBlock newBlock) {
    final blocks =
        List<TypingActionBlock>.from(_current.effectiveBlocks(widget.slots));
    final safeIdx = insertIndex.clamp(0, blocks.length);
    blocks.insert(safeIdx, newBlock);
    _updateCurrentBlocks(blocks);
    setState(() => _selectedBlockId = newBlock.id);
  }

  /// 将积木分组容器直接存为新预设（或覆盖同名预设）
  Future<void> _saveGroupAsPreset(GroupBlock group) async {
    final nameCtrl = TextEditingController(text: group.name);
    final descCtrl = TextEditingController();
    final preview =
        TypingBlockPreset(name: group.name, blocks: group.blocks).stepsPreview;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('存为动作预设'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: '预设名称',
                  hintText: '如：打开记事本缓冲、清空当前框',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(
                  labelText: '预设说明 (选填)',
                  hintText: '简短描述该预设用途',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.indigo.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border:
                      Border.all(color: Colors.indigo.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '包含 ${group.blocks.length} 个动作步骤：',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.indigo,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      preview,
                      style:
                          const TextStyle(fontSize: 11.5, color: Colors.black87),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('保存预设'),
          ),
        ],
      ),
    );

    if (ok != true || !mounted) return;
    final cleanName = nameCtrl.text.trim();
    if (cleanName.isEmpty) {
      showAppToast(context, '预设名称不能为空');
      return;
    }

    final existingList = ref.read(typingBlockPresetsProvider);
    final sameName =
        existingList.where((p) => p.name == cleanName).firstOrNull;

    String? targetId;
    if (sameName != null) {
      final mode = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('存在同名预设'),
          content: Text('预设库中已存在「$cleanName」，请选择保存方式：'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            OutlinedButton(
              onPressed: () => Navigator.pop(ctx, 'new'),
              child: const Text('另存为新预设'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, 'overwrite'),
              child: const Text('覆盖同名预设'),
            ),
          ],
        ),
      );
      if (mode == null || !mounted) return;
      if (mode == 'overwrite') {
        targetId = sameName.id;
      }
    }

    final preset = TypingBlockPreset(
      id: targetId,
      name: cleanName,
      description: descCtrl.text.trim(),
      blocks: group.blocks.map((b) => b.duplicate()).toList(),
    );
    await ref.read(typingBlockPresetsProvider.notifier).savePreset(preset);
    if (mounted) {
      showAppToast(context, '已将分组存为预设「$cleanName」');
    }
  }

  /// 打开预设库管理弹窗（支持搜索、新建、编辑、复制、删除、插入到方案）
  Future<void> _openPresetLibrarySheet({int? insertIndex}) async {
    final chosen = await TypingPresetLibrarySheet.show(
      context,
      selectButtonText: '插入当前方案',
      onSelectPreset: (preset) {
        final targetIdx = insertIndex ??
            _current.effectiveBlocks(widget.slots).length;
        _insertBlockAt(targetIdx, preset.toGroupBlock());
        showAppToast(context, '已插入预设「${preset.name}」');
      },
    );
    if (chosen != null && mounted) {
      final targetIdx = insertIndex ??
          _current.effectiveBlocks(widget.slots).length;
      _insertBlockAt(targetIdx, chosen.toGroupBlock());
      showAppToast(context, '已插入预设「${chosen.name}」');
    }
  }

  /// 选择并创建一个单个子步骤积木（供分组/循环/预设编辑器共用）
  Future<TypingActionBlock?> _pickNewSubBlock({
    bool allowCurrentItem = false,
  }) async {
    final choice = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
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
              subtitle: const Text('如 {ENTER}, {TAB}, {DOWN}, {CTRL+V} 等'),
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
              subtitle: const Text('输出固定字符 (如 notepad)'),
              onTap: () => Navigator.pop(ctx, 'literal'),
            ),
            if (allowCurrentItem)
              ListTile(
                leading: const CircleAvatar(
                    backgroundColor: Colors.lightGreen,
                    child: Icon(Icons.playlist_play,
                        color: Colors.white, size: 20)),
                title: const Text('输出当前循环项文本'),
                subtitle: const Text('输出当前被遍历到的条目内容'),
                onTap: () => Navigator.pop(ctx, 'currentItem'),
              ),
            if (widget.slots.isNotEmpty)
              ListTile(
                leading: const CircleAvatar(
                    backgroundColor: Colors.blue,
                    child: Icon(Icons.text_fields,
                        color: Colors.white, size: 20)),
                title: const Text('录入文书字段'),
                subtitle: const Text('输出指定字段的内容'),
                onTap: () => Navigator.pop(ctx, 'field'),
              ),
            ListTile(
              leading: const CircleAvatar(
                  backgroundColor: Colors.deepOrange,
                  child: Icon(Icons.speed, color: Colors.white, size: 20)),
              title: const Text('切换输入速度节奏'),
              subtitle: const Text('切换整套预设或微调单项时序参数'),
              onTap: () => Navigator.pop(ctx, 'rhythm'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );

    if (choice == null || !mounted) return null;

    if (choice == 'key') {
      return _createKeyComboBlock();
    } else if (choice == 'delay') {
      return _createDelayBlock();
    } else if (choice == 'literal') {
      return _createLiteralBlock();
    } else if (choice == 'currentItem') {
      return CurrentItemBlock();
    } else if (choice == 'field') {
      return _createFieldBlock();
    } else if (choice == 'rhythm') {
      return _showRhythmConfigDialog();
    }
    return null;
  }

  Future<FieldInputBlock?> _createFieldBlock() async {
    return _showFieldBlockEditorSheet();
  }

  Future<FieldInputBlock?> _showFieldBlockEditorSheet({
    FieldInputBlock? existing,
  }) async {
    if (widget.slots.isEmpty) return null;
    String selectedKey = existing != null &&
            widget.slots.any((s) => s.key == existing.fieldKey)
        ? existing.fieldKey
        : widget.slots.first.key;
    final preCtrl = TextEditingController(
      text: existing != null ? existing.preKeys.join(', ') : '',
    );
    final postCtrl = TextEditingController(
      text: existing != null ? existing.postKeys.join(', ') : '{TAB}',
    );
    bool preExpanded = false;
    bool postExpanded = false;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 14,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.88,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.text_fields_rounded,
                          color: Colors.blue, size: 22),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          existing == null ? '新建字段录入操作' : '修改字段录入操作',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('取消'),
                      ),
                      const SizedBox(width: 4),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(existing == null ? '添加' : '保存'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedKey,
                    decoration: const InputDecoration(
                      labelText: '选择文书字段',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: widget.slots
                        .map((s) => DropdownMenuItem(
                              value: s.key,
                              child: Text('${s.label} (${s.key})'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setSheet(() => selectedKey = v);
                    },
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: preCtrl,
                          style: const TextStyle(fontFamily: 'monospace'),
                          decoration: const InputDecoration(
                            labelText: '输入前动作 (逗号分隔)',
                            hintText: '如：{TAB}, {CTRL+A}',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        icon: Icon(preExpanded ? Icons.close : Icons.add,
                            size: 16),
                        label: Text(preExpanded ? '收起' : '添加按键'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                        onPressed: () => setSheet(() {
                          preExpanded = !preExpanded;
                          if (preExpanded) postExpanded = false;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ControlKeyPad(
                    controller: preCtrl,
                    label: '输入前快捷按键与组合键',
                    isExpanded: preExpanded,
                    onExpansionChanged: (v) => setSheet(() {
                      preExpanded = v;
                      if (v) postExpanded = false;
                    }),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: postCtrl,
                          style: const TextStyle(fontFamily: 'monospace'),
                          decoration: const InputDecoration(
                            labelText: '输入后动作 (逗号分隔)',
                            hintText: '如：{ENTER}, {TAB}',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton.tonalIcon(
                        icon: Icon(postExpanded ? Icons.close : Icons.add,
                            size: 16),
                        label: Text(postExpanded ? '收起' : '添加按键'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                        onPressed: () => setSheet(() {
                          postExpanded = !postExpanded;
                          if (postExpanded) preExpanded = false;
                        }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ControlKeyPad(
                    controller: postCtrl,
                    label: '输入后快捷按键与组合键',
                    isExpanded: postExpanded,
                    onExpansionChanged: (v) => setSheet(() {
                      postExpanded = v;
                      if (v) preExpanded = false;
                    }),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (ok == true) {
      final preList = preCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final postList = postCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      if (existing != null) {
        return existing.copyWith(
          fieldKey: selectedKey,
          preKeys: preList,
          postKeys: postList,
        );
      }
      return FieldInputBlock(
        fieldKey: selectedKey,
        preKeys: preList,
        postKeys: postList,
      );
    }
    return null;
  }

  /// 统一的系统按键/组合快捷键配置面板（复用全尺寸 QWERTY 软键盘）
  Future<String?> _showKeyComboPickerSheet({
    required String title,
    String initialCombo = '{ENTER}',
  }) async {
    final comboCtrl = TextEditingController(text: initialCombo);

    return showModalBottomSheet<String>(
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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.88,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const Icon(Icons.keyboard_rounded,
                        color: Colors.amber, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: () {
                        final val = comboCtrl.text.trim();
                        if (val.isNotEmpty) {
                          Navigator.pop(ctx, val);
                        }
                      },
                      child: const Text('确定'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: comboCtrl,
                  builder: (ctx, val, _) => TextField(
                    controller: comboCtrl,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                    decoration: InputDecoration(
                      labelText: '当前选中的按键或组合键',
                      hintText: '如 {WIN+R}, {CTRL+V}, {TAB}',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: val.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              tooltip: '清空',
                              onPressed: comboCtrl.clear,
                            )
                          : null,
                    ),
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
      ),
    );
  }

  Future<KeyComboBlock?> _createKeyComboBlock() async {
    final picked = await _showKeyComboPickerSheet(
      title: '新建系统按键 / 快捷键动作',
      initialCombo: '{ENTER}',
    );
    if (picked != null && picked.isNotEmpty) {
      return KeyComboBlock(combo: picked);
    }
    return null;
  }

  Future<LiteralTextBlock?> _createLiteralBlock() async {
    final textCtrl = TextEditingController(text: 'notepad');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建固定文本动作'),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('添加')),
        ],
      ),
    );

    if (ok == true && textCtrl.text.trim().isNotEmpty) {
      return LiteralTextBlock(text: textCtrl.text.trim());
    }
    return null;
  }

  Future<DelayBlock?> _createDelayBlock() async {
    final msCtrl = TextEditingController(text: '300');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建延时等待动作'),
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
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('添加')),
        ],
      ),
    );

    if (ok == true) {
      return DelayBlock(
          durationMs: int.tryParse(msCtrl.text.trim()) ?? 200);
    }
    return null;
  }

  Future<RhythmActionBlock?> _createRhythmBlock() async {
    return _showRhythmConfigDialog();
  }

  Future<RhythmActionBlock?> _showRhythmConfigDialog({RhythmActionBlock? existing}) async {
    final initialPresets =
        await ref.read(timingPresetsProvider.notifier).ensureLoaded();
    if (!mounted) return null;

    // 模式 0: 成套切换预设；模式 1: 单独微调某个参数
    int mode = 0;
    String selectedPresetId = initialPresets.first.id;
    String selectedSingleKey = 'cjk_gap_ms';
    final singleValCtrl = TextEditingController(text: '20');

    if (existing != null) {
      if (existing.params.length == 1) {
        mode = 1;
        selectedSingleKey = existing.params.keys.first;
        singleValCtrl.text = fmtNumber(existing.params.values.first);
      } else {
        final match = initialPresets
            .where((p) =>
                p.name == existing.presetName ||
                '成套: ${p.name}' == existing.presetName)
            .firstOrNull;
        if (match != null) selectedPresetId = match.id;
      }
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Consumer(
        builder: (ctx, dialogRef, _) {
          final savedPresets = dialogRef.watch(timingPresetsProvider);
          final validSelectedId =
              savedPresets.any((p) => p.id == selectedPresetId)
                  ? selectedPresetId
                  : savedPresets.first.id;

          return StatefulBuilder(
            builder: (ctx, setDialog) => AlertDialog(
              title: Text(existing == null ? '插入节奏切换动作' : '编辑节奏切换动作'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(
                            value: 0,
                            label: Text('成套切换预设'),
                            icon: Icon(Icons.bookmarks_outlined, size: 16)),
                        ButtonSegment(
                            value: 1,
                            label: Text('单独调整某项'),
                            icon: Icon(Icons.tune, size: 16)),
                      ],
                      selected: {mode},
                      onSelectionChanged: (s) =>
                          setDialog(() => mode = s.first),
                    ),
                    const SizedBox(height: 16),
                    if (mode == 0) ...[
                      Text(
                        '选择在「键盘参数与输入速度」中保存的成套预设 (共 ${savedPresets.length} 套)：',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: validSelectedId,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '成套节奏预设',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: savedPresets
                            .map((p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(
                                      '${p.name} (约${p.estimatedCharsPerSec.toStringAsFixed(0)}字/s)'),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            setDialog(() => selectedPresetId = v);
                          }
                        },
                      ),
                    ] else ...[
                      const Text('仅针对后续流程单独改变某一个物理时序参数：',
                          style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedSingleKey,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '选择参数项',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: timingParamSpecs
                            .where((s) => !s.flag)
                            .map((s) => DropdownMenuItem(
                                  value: s.key,
                                  child: Text('${s.label} (${s.shortLabel})'),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) {
                            final spec = timingParamSpecs
                                .firstWhere((s) => s.key == v);
                            setDialog(() {
                              selectedSingleKey = v;
                              singleValCtrl.text = fmtNumber(spec.def);
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: singleValCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: '目标数值 (毫秒 ms)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ],
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
        },
      ),
    );

    if (ok == true) {
      final latestPresets = ref.read(timingPresetsProvider);
      if (mode == 0) {
        final target = latestPresets.firstWhere(
          (p) => p.id == selectedPresetId,
          orElse: () => latestPresets.first,
        );
        return RhythmActionBlock(
          id: existing?.id,
          presetName: '成套: ${target.name}',
          params: Map<String, double>.from(target.values),
        );
      } else {
        final spec =
            timingParamSpecs.firstWhere((s) => s.key == selectedSingleKey);
        final val = double.tryParse(singleValCtrl.text.trim()) ?? spec.def;
        return RhythmActionBlock(
          id: existing?.id,
          presetName: '单项: ${spec.shortLabel}=${fmtNumber(val)}ms',
          params: {selectedSingleKey: val},
        );
      }
    }
    return null;
  }

  Future<ForEachBlock?> _createForEachBlock() async {
    if (widget.slots.isEmpty) return null;
    String selectedKey = widget.slots.first.key;
    String separator = r'\n';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => AlertDialog(
          title: const Text('新建列表循环操作'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: selectedKey,
                decoration: const InputDecoration(
                  labelText: '要循环的文书字段',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: widget.slots
                    .map((s) => DropdownMenuItem(
                          value: s.key,
                          child: Text('${s.label} (${s.key})'),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setDialog(() => selectedKey = v);
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: separator,
                decoration: const InputDecoration(
                  labelText: '拆分规则 (按什么拆分项)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: const [
                  DropdownMenuItem(value: r'\n', child: Text('按换行符拆分 (每行一项)')),
                  DropdownMenuItem(value: ',', child: Text('按逗号拆分 (逗号分隔)')),
                  DropdownMenuItem(value: ';', child: Text('按分号拆分 (分号分隔)')),
                ],
                onChanged: (v) {
                  if (v != null) setDialog(() => separator = v);
                },
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('添加')),
          ],
        ),
      ),
    );

    if (ok == true) {
      return ForEachBlock(
        fieldKey: selectedKey,
        separator: separator,
        subBlocks: [
          CurrentItemBlock(),
          KeyComboBlock(combo: '{DOWN}'),
          KeyComboBlock(combo: '{ENTER}'),
          KeyComboBlock(combo: '{TAB}'),
        ],
      );
    }
    return null;
  }

  Future<GroupBlock?> _createGroupBlock() async {
    final nameCtrl = TextEditingController(text: '快捷操作分组');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建分组容器'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '分组名称',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('创建')),
        ],
      ),
    );

    if (ok == true && nameCtrl.text.trim().isNotEmpty) {
      return GroupBlock(
        name: nameCtrl.text.trim(),
        blocks: [],
      );
    }
    return null;
  }

  /// Unified action menu for any block (修改参数 / 复制 / 成组 / 删除)
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
                '步骤设置 (#${index + 1})',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('修改参数与内容'),
              onTap: () {
                Navigator.pop(ctx);
                _editBlock(index, block);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('复制此步骤'),
              onTap: () {
                Navigator.pop(ctx);
                final blocks = List<TypingActionBlock>.from(
                    _current.effectiveBlocks(widget.slots));
                final copy = block.duplicate();
                blocks.insert(index + 1, copy);
                _updateCurrentBlocks(blocks);
                setState(() => _selectedBlockId = copy.id);
              },
            ),
            if (block is GroupBlock)
              ListTile(
                leading: const Icon(Icons.bookmark_add_outlined,
                    color: Colors.deepOrange),
                title: const Text('将此分组存为预设'),
                subtitle: const Text('保存到动作预设库，方便在其他方案中复用'),
                onTap: () {
                  Navigator.pop(ctx);
                  _saveGroupAsPreset(block);
                },
              )
            else
              ListTile(
                leading: const Icon(Icons.folder_zip_outlined),
                title: const Text('将此步骤打包入新分组'),
                onTap: () {
                  Navigator.pop(ctx);
                  final blocks = List<TypingActionBlock>.from(
                      _current.effectiveBlocks(widget.slots));
                  final group = GroupBlock(
                    name: '新分组',
                    blocks: [block.duplicate()],
                  );
                  blocks[index] = group;
                  _updateCurrentBlocks(blocks);
                  setState(() => _selectedBlockId = group.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除此步骤', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                final blocks = List<TypingActionBlock>.from(
                    _current.effectiveBlocks(widget.slots))
                  ..removeAt(index);
                _updateCurrentBlocks(blocks);
                if (_selectedBlockId == block.id) {
                  setState(() => _selectedBlockId = null);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  void _editBlock(int index, TypingActionBlock block) async {
    final blocks =
        List<TypingActionBlock>.from(_current.effectiveBlocks(widget.slots));

    if (block is KeyComboBlock) {
      final picked = await _showKeyComboPickerSheet(
        title: '修改系统按键 / 快捷键',
        initialCombo: block.combo,
      );
      if (picked != null && picked.isNotEmpty) {
        blocks[index] = block.copyWith(combo: picked);
        _updateCurrentBlocks(blocks);
      }
    } else if (block is DelayBlock) {
      final ctrl = TextEditingController(text: block.durationMs.toString());
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('修改等待延时'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: '毫秒数', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      );
      if (ok == true) {
        blocks[index] = block.copyWith(
            durationMs: int.tryParse(ctrl.text.trim()) ?? 200);
        _updateCurrentBlocks(blocks);
      }
    } else if (block is RhythmActionBlock) {
      final updated = await _showRhythmConfigDialog(existing: block);
      if (updated != null) {
        blocks[index] = updated;
        _updateCurrentBlocks(blocks);
      }
    } else if (block is LiteralTextBlock) {
      final ctrl = TextEditingController(text: block.text);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('修改固定文本'),
          content: TextField(
            controller: ctrl,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      );
      if (ok == true) {
        blocks[index] = block.copyWith(text: ctrl.text.trim());
        _updateCurrentBlocks(blocks);
      }
    } else if (block is FieldInputBlock) {
      final updated = await _showFieldBlockEditorSheet(existing: block);
      if (updated != null) {
        blocks[index] = updated;
        _updateCurrentBlocks(blocks);
      }
    } else if (block is GroupBlock) {
      final nameCtrl = TextEditingController(text: block.name);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重命名分组'),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      );
      if (ok == true) {
        blocks[index] = block.copyWith(name: nameCtrl.text.trim());
        _updateCurrentBlocks(blocks);
      }
    } else if (block is ForEachBlock) {
      String selectedKey = block.fieldKey;
      String separator = block.separator;

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            title: const Text('修改列表循环操作'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedKey,
                  decoration: const InputDecoration(
                    labelText: '循环的文书字段',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: widget.slots
                      .map((s) => DropdownMenuItem(
                            value: s.key,
                            child: Text('${s.label} (${s.key})'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialog(() => selectedKey = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: separator,
                  decoration: const InputDecoration(
                    labelText: '拆分规则 (按什么拆分项)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: r'\n', child: Text('按换行符拆分 (每行一项)')),
                    DropdownMenuItem(value: ',', child: Text('按逗号拆分 (逗号分隔)')),
                    DropdownMenuItem(value: ';', child: Text('按分号拆分 (分号分隔)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialog(() => separator = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('保存')),
            ],
          ),
        ),
      );

      if (ok == true) {
        blocks[index] =
            block.copyWith(fieldKey: selectedKey, separator: separator);
        _updateCurrentBlocks(blocks);
      }
    }
  }

  /// Click an attached sub-block (pre/post key on a field) to edit or remove it
  void _editAttachedKey({
    required int parentBlockIndex,
    required FieldInputBlock fieldBlock,
    required bool isPreKey,
  }) async {
    final curKeys = isPreKey ? fieldBlock.preKeys : fieldBlock.postKeys;
    final ctrl = TextEditingController(text: curKeys.join(', '));

    final action = await showModalBottomSheet<String>(
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
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(ctx).size.height * 0.88,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.attachment_rounded,
                      color: isPreKey ? Colors.orange : Colors.blue,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isPreKey ? '修改「输入前动作」附属块' : '修改「输入后动作」附属块',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(foregroundColor: Colors.red),
                      onPressed: () => Navigator.pop(ctx, 'delete'),
                      child: const Text('删除附属块'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, 'cancel'),
                      child: const Text('取消'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, 'save'),
                      child: const Text('保存'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: ctrl,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                  decoration: InputDecoration(
                    labelText: '按键序列 (逗号分隔)',
                    hintText: '{TAB}, {ENTER}',
                    border: const OutlineInputBorder(),
                    isDense: true,
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      tooltip: '清空',
                      onPressed: ctrl.clear,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                ControlKeyPad(
                  controller: ctrl,
                  label: '快捷按键与全键盘',
                  collapsible: false,
                  initiallyExpanded: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (action == 'save') {
      final newKeys = ctrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final blocks =
          List<TypingActionBlock>.from(_current.effectiveBlocks(widget.slots));
      blocks[parentBlockIndex] = isPreKey
          ? fieldBlock.copyWith(preKeys: newKeys)
          : fieldBlock.copyWith(postKeys: newKeys);
      _updateCurrentBlocks(blocks);
    } else if (action == 'delete') {
      final blocks =
          List<TypingActionBlock>.from(_current.effectiveBlocks(widget.slots));
      blocks[parentBlockIndex] = isPreKey
          ? fieldBlock.copyWith(preKeys: const [])
          : fieldBlock.copyWith(postKeys: const []);
      _updateCurrentBlocks(blocks);
    }
  }

  /// Add a sub-block to a list (either inside a GroupBlock or ForEachBlock)
  Future<void> _addSubBlockToList({
    required List<TypingActionBlock> targetList,
    bool allowCurrentItem = false,
  }) async {
    final newSub = await _pickNewSubBlock(allowCurrentItem: allowCurrentItem);
    if (newSub != null && mounted) {
      setState(() {
        _pushHistorySnapshot();
        targetList.add(newSub);
        _updateCurrent(_current);
      });
    }
  }

  void _showSubBlockMenu({
    required List<TypingActionBlock> parentList,
    required int subIndex,
  }) {
    final sub = parentList[subIndex];
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text('子步骤操作 (#${subIndex + 1})',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('修改参数'),
              onTap: () async {
                Navigator.pop(ctx);
                await _editSingleSubBlock(sub, (updated) {
                  setState(() {
                    _pushHistorySnapshot();
                    parentList[subIndex] = updated;
                    _updateCurrent(_current);
                  });
                });
              },
            ),
            if (subIndex > 0)
              ListTile(
                leading: const Icon(Icons.arrow_upward),
                title: const Text('上移一位'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _pushHistorySnapshot();
                    final item = parentList.removeAt(subIndex);
                    parentList.insert(subIndex - 1, item);
                    _updateCurrent(_current);
                  });
                },
              ),
            if (subIndex < parentList.length - 1)
              ListTile(
                leading: const Icon(Icons.arrow_downward),
                title: const Text('下移一位'),
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() {
                    _pushHistorySnapshot();
                    final item = parentList.removeAt(subIndex);
                    parentList.insert(subIndex + 1, item);
                    _updateCurrent(_current);
                  });
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除此子步骤', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                setState(() {
                  _pushHistorySnapshot();
                  parentList.removeAt(subIndex);
                  _updateCurrent(_current);
                });
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _editSingleSubBlock(
    TypingActionBlock block,
    ValueChanged<TypingActionBlock> onUpdated,
  ) async {
    if (block is KeyComboBlock) {
      final picked = await _showKeyComboPickerSheet(
        title: '修改系统按键 / 快捷键',
        initialCombo: block.combo,
      );
      if (picked != null && picked.isNotEmpty) {
        onUpdated(block.copyWith(combo: picked));
      }
    } else if (block is DelayBlock) {
      final ctrl = TextEditingController(text: block.durationMs.toString());
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('修改等待延时'),
          content: TextField(
            controller: ctrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
                labelText: '毫秒数', border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      );
      if (ok == true) {
        onUpdated(block.copyWith(
            durationMs: int.tryParse(ctrl.text.trim()) ?? 200));
      }
    } else if (block is LiteralTextBlock) {
      final ctrl = TextEditingController(text: block.text);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('修改固定文本'),
          content: TextField(
              controller: ctrl,
              decoration: const InputDecoration(border: OutlineInputBorder())),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      );
      if (ok == true && ctrl.text.trim().isNotEmpty) {
        onUpdated(block.copyWith(text: ctrl.text.trim()));
      }
    } else if (block is FieldInputBlock) {
      final updated = await _showFieldBlockEditorSheet(existing: block);
      if (updated != null) {
        onUpdated(updated);
      }
    } else if (block is RhythmActionBlock) {
      final updated = await _showRhythmConfigDialog(existing: block);
      if (updated != null) {
        onUpdated(updated);
      }
    } else if (block is GroupBlock) {
      final nameCtrl = TextEditingController(text: block.name);
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('重命名分组'),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(border: OutlineInputBorder()),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('保存')),
          ],
        ),
      );
      if (ok == true && nameCtrl.text.trim().isNotEmpty) {
        onUpdated(block.copyWith(name: nameCtrl.text.trim()));
      }
    } else if (block is ForEachBlock) {
      String selectedKey = block.fieldKey;
      String separator = block.separator;

      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialog) => AlertDialog(
            title: const Text('修改列表循环操作'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedKey,
                  decoration: const InputDecoration(
                    labelText: '循环的文书字段',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: widget.slots
                      .map((s) => DropdownMenuItem(
                            value: s.key,
                            child: Text('${s.label} (${s.key})'),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setDialog(() => selectedKey = v);
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: separator,
                  decoration: const InputDecoration(
                    labelText: '拆分规则 (按什么拆分项)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: r'\n', child: Text('按换行符拆分 (每行一项)')),
                    DropdownMenuItem(value: ',', child: Text('按逗号拆分 (逗号分隔)')),
                    DropdownMenuItem(value: ';', child: Text('按分号拆分 (分号分隔)')),
                  ],
                  onChanged: (v) {
                    if (v != null) setDialog(() => separator = v);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('取消')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('保存')),
            ],
          ),
        ),
      );
      if (ok == true) {
        onUpdated(block.copyWith(fieldKey: selectedKey, separator: separator));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // 预热输入节奏预设与动作积木预设，避免首次弹窗异步读取未完成
    ref.watch(timingPresetsProvider);
    ref.watch(typingBlockPresetsProvider);

    final cur = _current;
    final blocks = cur.effectiveBlocks(widget.slots);

    return Column(
      children: [
        // Merged compact header: Scheme Dropdown (Hamburger Menu) + Undo + Reset
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: Theme.of(context)
              .colorScheme
              .surfaceContainerHighest
              .withValues(alpha: 0.25),
          child: Row(
            children: [
              // Scheme Dropdown with Hamburger Icon
              PopupMenuButton<String>(
                tooltip: '切换或管理输入方案',
                onSelected: (val) {
                  if (val.startsWith('select:')) {
                    final idx = int.parse(val.substring('select:'.length));
                    setState(() {
                      _selectedIndex = idx;
                      _selectedBlockId = null;
                    });
                    _ensureCurrentBlocksSolidified();
                  } else if (val == 'timing') {
                    _editCurrentProfileTiming();
                  } else if (val == 'presets') {
                    _openPresetLibrarySheet();
                  } else if (val == 'new') {
                    _addProfile();
                  } else if (val == 'rename') {
                    _renameCurrent();
                  } else if (val == 'duplicate') {
                    _duplicateCurrent();
                  } else if (val == 'delete') {
                    _deleteCurrent();
                  }
                },
                itemBuilder: (ctx) => [
                  // 1. All profiles list
                  for (int i = 0; i < widget.profiles.length; i++)
                    PopupMenuItem<String>(
                      value: 'select:$i',
                      child: Row(
                        children: [
                          Icon(
                            _selectedIndex == i
                                ? Icons.radio_button_checked
                                : Icons.radio_button_unchecked,
                            size: 16,
                            color: _selectedIndex == i
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.profiles[i].name,
                              style: TextStyle(
                                fontWeight: _selectedIndex == i
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'timing',
                    child: Row(
                      children: [
                        Icon(Icons.tune, size: 18, color: Colors.blue),
                        SizedBox(width: 8),
                        Text('方案参数 (步骤间延时)'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'presets',
                    child: Row(
                      children: [
                        Icon(Icons.bookmarks_outlined,
                            size: 18, color: Colors.deepOrange),
                        SizedBox(width: 8),
                        Text('动作预设管理'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'new',
                    child: Row(
                      children: [
                        Icon(Icons.add, size: 18),
                        SizedBox(width: 8),
                        Text('新建输入方案'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'rename',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('重命名当前方案'),
                      ],
                    ),
                  ),
                  const PopupMenuItem<String>(
                    value: 'duplicate',
                    child: Row(
                      children: [
                        Icon(Icons.copy_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('复制当前方案'),
                      ],
                    ),
                  ),
                  if (widget.profiles.length > 1)
                    const PopupMenuItem<String>(
                      value: 'delete',
                      child: Row(
                        children: [
                          Icon(Icons.delete_outline,
                              size: 18, color: Colors.red),
                          SizedBox(width: 8),
                          Text('删除当前方案', style: TextStyle(color: Colors.red)),
                        ],
                      ),
                    ),
                ],
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.menu, size: 18),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 160),
                        child: Text(
                          cur.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(Icons.arrow_drop_down, size: 18),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              // Undo
              // Undo
              IconButton(
                icon: const Icon(Icons.undo, size: 20),
                tooltip: '撤销',
                visualDensity: VisualDensity.compact,
                onPressed: _history.isNotEmpty ? _undo : null,
              ),
              // Reset
              TextButton.icon(
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('重置', style: TextStyle(fontSize: 12)),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _confirmReset,
              ),
            ],
          ),
        ),

        // Timeline Blocks Reorderable List
        Expanded(
          child: blocks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.view_in_ar_outlined,
                          size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      const Text('当前方案暂无输入步骤',
                          style: TextStyle(color: Colors.grey)),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        icon: const Icon(Icons.add),
                        label: const Text('添加第一个步骤'),
                        onPressed: () => _showAddBlockPicker(insertIndex: 0),
                      ),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 6, 12, 80),
                  itemCount: blocks.length,
                  buildDefaultDragHandles: false,
                  onReorder: (oldIndex, newIndex) {
                    setState(() {
                      if (newIndex > oldIndex) newIndex--;
                      final item = blocks.removeAt(oldIndex);
                      blocks.insert(newIndex, item);
                      _updateCurrentBlocks(blocks);
                    });
                  },
                  itemBuilder: (context, index) {
                    final block = blocks[index];
                    return ReorderableDelayedDragStartListener(
                      key: ValueKey(block.id),
                      index: index,
                      child: _buildTimelineItem(
                        index: index,
                        totalCount: blocks.length,
                        block: block,
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  /// Builds a timeline node containing the block and optional top/bottom insertion '+' buttons
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
            // Left Timeline Line & Node Dot
            SizedBox(
              width: 32,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Continuous vertical line
                  Container(
                    width: 2.5,
                    color: Colors.blueGrey.withValues(alpha: 0.25),
                  ),
                  // Dot Node with step number
                  CircleAvatar(
                    radius: 11,
                    backgroundColor: isSelected
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest,
                    child: Text(
                      '${index + 1}',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: isSelected
                            ? Colors.white
                            : Colors.blueGrey[800],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            // Brick Block + Center-aligned Top/Bottom '+' buttons
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 310),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Insert '+' button BEFORE this block (only visible when selected)
                      if (isSelected)
                        _buildInsertPlusButton(
                          tooltip: '在此步骤之前插入操作',
                          onPressed: () =>
                              _showAddBlockPicker(insertIndex: index),
                        ),

                      // Main Brick Block
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

                      // Insert '+' button AFTER this block (only visible when selected)
                      if (isSelected)
                        _buildInsertPlusButton(
                          tooltip: '在此步骤之后插入操作',
                          onPressed: () =>
                              _showAddBlockPicker(insertIndex: index + 1),
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

  /// Builds the brick block shape (靠近方块，精致的低代码积木手感)
  Widget _buildBrickShape({
    required int index,
    required TypingActionBlock block,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);

    // Color definitions for brick types
    final (Color color, IconData icon, String typeTitle) = switch (block.type) {
      ActionBlockType.fieldInput => (
          Colors.blue,
          Icons.text_fields_rounded,
          '字段录入'
        ),
      ActionBlockType.keyCombo => (
          Colors.amber[800]!,
          Icons.keyboard_rounded,
          '系统快捷键'
        ),
      ActionBlockType.literalText => (
          Colors.teal,
          Icons.edit_note_rounded,
          '固定文本'
        ),
      ActionBlockType.delay => (
          Colors.purple,
          Icons.timer_outlined,
          '等待延时'
        ),
      ActionBlockType.rhythm => (
          Colors.deepOrange,
          Icons.speed_rounded,
          '切换节奏'
        ),
      ActionBlockType.forEach => (
          Colors.green[700]!,
          Icons.repeat_rounded,
          '列表循环'
        ),
      ActionBlockType.currentItem => (
          Colors.lightGreen[800]!,
          Icons.playlist_play_rounded,
          '当前项'
        ),
      ActionBlockType.group => (
          Colors.indigo,
          Icons.folder_zip_outlined,
          '操作分组'
        ),
    };

    // If it's a FieldInputBlock, we render attached mini-bricks for pre/post keys!
    if (block is FieldInputBlock) {
      final slot =
          widget.slots.where((s) => s.key == block.fieldKey).firstOrNull;
      final label = slot?.label ?? block.fieldKey;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Attached Pre-key mini block (if any)
          if (block.preKeys.isNotEmpty)
            _buildAttachedKeyChip(
              label: '前置按键: ${block.preKeys.join("+")}',
              color: Colors.orange,
              isSelected: isSelected,
              onTap: () => _editAttachedKey(
                parentBlockIndex: index,
                fieldBlock: block,
                isPreKey: true,
              ),
            ),

          // Main Field Block Brick (方块造型)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected
                  ? color.withValues(alpha: 0.12)
                  : theme.colorScheme.surface,
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
                        label,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        '字段键名: ${block.fieldKey}',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  IconButton(
                    icon: const Icon(Icons.more_horiz),
                    tooltip: '操作选项',
                    onPressed: () => _openBlockMenu(index, block),
                  ),
              ],
            ),
          ),

          // Attached Post-key mini block (if any)
          if (block.postKeys.isNotEmpty)
            _buildAttachedKeyChip(
              label: '后置按键: ${block.postKeys.join("+")}',
              color: Colors.blue,
              isSelected: isSelected,
              onTap: () => _editAttachedKey(
                parentBlockIndex: index,
                fieldBlock: block,
                isPreKey: false,
              ),
            ),
        ],
      );
    }

    // If it's a GroupBlock, render container shape
    if (block is GroupBlock) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.4),
            width: isSelected ? 2.0 : 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.folder_open_rounded, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          block.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: color,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${block.blocks.length} 步)',
                        style:
                            const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  IconButton(
                    icon: const Icon(Icons.more_horiz),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    tooltip: '分组菜单',
                    onPressed: () => _openBlockMenu(index, block),
                  ),
              ],
            ),
            const Divider(height: 12),
            if (block.blocks.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                child: Text('分组内暂无步骤，点击下方按钮添加',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
              )
            else
              for (int sub = 0; sub < block.blocks.length; sub++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () => _showSubBlockMenu(
                      parentList: block.blocks,
                      subIndex: sub,
                    ),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: color.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          Text('${sub + 1}. ',
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: color)),
                          Expanded(
                            child: Text(
                              _subBlockDescription(block.blocks[sub]),
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                          const Icon(Icons.more_horiz,
                              size: 16, color: Colors.grey),
                        ],
                      ),
                    ),
                  ),
                ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 15),
                label: const Text('添加子步骤', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  side: BorderSide(color: color.withValues(alpha: 0.35)),
                  foregroundColor: color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => _addSubBlockToList(
                  targetList: block.blocks,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // If it's ForEachBlock, render loop container shape
    if (block is ForEachBlock) {
      final slot =
          widget.slots.where((s) => s.key == block.fieldKey).firstOrNull;
      final label = slot?.label ?? block.fieldKey;

      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? color : color.withValues(alpha: 0.4),
            width: isSelected ? 2.0 : 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.loop_rounded, size: 18, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '循环录入: $label',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: color,
                    ),
                  ),
                ),
                if (isSelected)
                  IconButton(
                    icon: const Icon(Icons.more_horiz),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(4),
                    tooltip: '循环菜单',
                    onPressed: () => _openBlockMenu(index, block),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '拆分规则: ${block.separator == r'\n' ? '换行符 (每行一项)' : block.separator}  (点击子步骤可修改/排序)',
              style: const TextStyle(fontSize: 11, color: Colors.blueGrey),
            ),
            const Divider(height: 12),
            for (int sub = 0; sub < block.subBlocks.length; sub++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => _showSubBlockMenu(
                    parentList: block.subBlocks,
                    subIndex: sub,
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: color.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Text('${sub + 1}. ',
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: color)),
                        Expanded(
                          child: Text(
                            _subBlockDescription(block.subBlocks[sub]),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        const Icon(Icons.more_horiz,
                            size: 16, color: Colors.grey),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 4),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.add, size: 15),
                label: const Text('添加子步骤', style: TextStyle(fontSize: 12)),
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  side: BorderSide(color: color.withValues(alpha: 0.35)),
                  foregroundColor: color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: () => _addSubBlockToList(
                  targetList: block.subBlocks,
                  allowCurrentItem: true,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Other standard brick blocks: KeyComboBlock, DelayBlock, LiteralTextBlock
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isSelected
            ? color.withValues(alpha: 0.12)
            : theme.colorScheme.surface,
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
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.bold),
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
              tooltip: '操作选项',
              onPressed: () => _openBlockMenu(index, block),
            ),
        ],
      ),
    );
  }

  /// Attached mini block for pre/post keys (视觉相连的附属小块，跟随主积木一起高亮)
  Widget _buildAttachedKeyChip({
    required String label,
    required Color color,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
          decoration: BoxDecoration(
            color: isSelected
                ? color.withValues(alpha: 0.22)
                : color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? color : color.withValues(alpha: 0.4),
              width: isSelected ? 1.8 : 1.0,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    )
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.attachment_rounded, size: 12, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                  color: color,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.edit, size: 10, color: color),
            ],
          ),
        ),
      ),
    );
  }

  String _blockTitle(TypingActionBlock block) {
    if (block is KeyComboBlock) return block.combo;
    if (block is LiteralTextBlock) return '文本: "${block.text}"';
    if (block is DelayBlock) return '等待 ${block.durationMs} ms';
    if (block is RhythmActionBlock) return '切换为 [${block.presetName}] 节奏';
    if (block is CurrentItemBlock) return '输入当前循环项文字';
    return '';
  }

  String _subBlockDescription(TypingActionBlock b) {
    if (b is KeyComboBlock) return '快捷键 ${b.combo}';
    if (b is DelayBlock) return '延时 ${b.durationMs}ms';
    if (b is RhythmActionBlock) return '调速 [${b.presetName}]';
    if (b is LiteralTextBlock) return '文本 "${b.text}"';
    if (b is CurrentItemBlock) return '输出当前循环条目';
    if (b is FieldInputBlock) return '录入字段 ${b.fieldKey}';
    if (b is GroupBlock) return '分组 [${b.name}] (${b.blocks.length}步)';
    if (b is ForEachBlock) return '循环录入 ${b.fieldKey}';
    return b.type.name;
  }
}
