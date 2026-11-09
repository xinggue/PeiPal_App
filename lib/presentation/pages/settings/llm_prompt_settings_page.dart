import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/api/llm_prompt_config.dart';
import '../../../providers/providers.dart';

class LlmPromptSettingsPage extends ConsumerStatefulWidget {
  const LlmPromptSettingsPage({super.key});

  @override
  ConsumerState<LlmPromptSettingsPage> createState() =>
      _LlmPromptSettingsPageState();
}

class _LlmPromptSettingsPageState
    extends ConsumerState<LlmPromptSettingsPage> {
  List<SystemPromptBlock> _blocks = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await ref.read(llmPromptConfigProvider.notifier).ready;
    if (!mounted) return;
    final cfg = ref.read(llmPromptConfigProvider);
    setState(() {
      _blocks = List.from(cfg.effectiveSystemBlocks);
      _isLoading = false;
    });
  }

  Future<void> _save() async {
    final cfg = LlmPromptConfig(
      systemBlocks: _blocks,
    );
    await ref.read(llmPromptConfigProvider.notifier).save(cfg);
    if (mounted) {
      showAppToast(context, '已保存提示词编排设置');
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认编排'),
        content: const Text('确定将 System 提示词的规则顺序和每句话的模板措辞恢复为默认吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('恢复默认')),
        ],
      ),
    );

    if (ok == true) {
      await ref.read(llmPromptConfigProvider.notifier).reset();
      await _load();
      if (mounted) {
        showAppToast(context, '已恢复默认设置');
      }
    }
  }

  void _editBlock(int index) async {
    final block = _blocks[index];
    final ctrl = TextEditingController(text: block.templateText);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('编辑模块措辞 · ${block.label}'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                block.description,
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: ctrl,
                maxLines: 8,
                minLines: 4,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
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

    if (ok == true) {
      setState(() {
        _blocks[index] = block.copyWith(templateText: ctrl.text);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('文书生成')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('文书生成'),
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('恢复默认'),
          ),
          FilledButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          // Banner Guide
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: Colors.blue.withValues(alpha: 0.08),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.tune,
                    size: 18, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '长按拖拽可改变各提示词模块在 System Prompt 中的先后排列顺序。\n点击模块可自由编辑措辞语句，右侧开关可控制是否启用。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Reorderable Blocks List
          Expanded(
            child: ReorderableListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _blocks.length,
              onReorder: (oldIndex, newIndex) {
                setState(() {
                  if (newIndex > oldIndex) newIndex--;
                  final item = _blocks.removeAt(oldIndex);
                  _blocks.insert(newIndex, item);
                });
              },
              itemBuilder: (context, index) {
                final block = _blocks[index];
                return Card(
                  key: ValueKey(block.id),
                  margin: const EdgeInsets.only(bottom: 8),
                  elevation: 0,
                  color: block.isEnabled
                      ? Theme.of(context).colorScheme.surface
                      : Colors.grey.withValues(alpha: 0.12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(
                      color: block.isEnabled
                          ? Theme.of(context).colorScheme.outline.withValues(alpha: 0.3)
                          : Colors.grey.withValues(alpha: 0.2),
                      width: 1.2,
                    ),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => _editBlock(index),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          // Index Circle
                          CircleAvatar(
                            radius: 12,
                            backgroundColor: block.isEnabled
                                ? Theme.of(context).colorScheme.primaryContainer
                                : Colors.grey.withValues(alpha: 0.2),
                            child: Text(
                              '${index + 1}',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: block.isEnabled
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),

                          // Titles & Description
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      block.label,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: block.isEnabled ? null : Colors.grey,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    const Icon(Icons.edit_outlined, size: 14, color: Colors.blueGrey),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  block.description,
                                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                                ),
                              ],
                            ),
                          ),

                          // Enable/Disable Switch
                          Switch(
                            value: block.isEnabled,
                            onChanged: (v) {
                              setState(() {
                                _blocks[index] = block.copyWith(isEnabled: v);
                              });
                            },
                          ),

                          // Drag Handle
                          const Padding(
                            padding: EdgeInsets.only(left: 4),
                            child: Icon(Icons.drag_handle, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
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
