import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/typing_action_block.dart';
import '../../../providers/providers.dart';
import '../../widgets/ble/typing_preset_block_editor_page.dart';
import '../../widgets/common/app_toast.dart';

/// 独立的快捷动作预设管理页面 (/typing-presets)
class TypingPresetsPage extends ConsumerStatefulWidget {
  const TypingPresetsPage({super.key});

  @override
  ConsumerState<TypingPresetsPage> createState() => _TypingPresetsPageState();
}

class _TypingPresetsPageState extends ConsumerState<TypingPresetsPage> {
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

  Future<void> _duplicate(TypingBlockPreset preset) async {
    final copy = preset.duplicate();
    await ref.read(typingBlockPresetsProvider.notifier).savePreset(copy);
    if (mounted) {
      showAppToast(context, '已创建副本「${copy.name}」');
    }
  }

  Future<void> _exportPreset(TypingBlockPreset preset) async {
    final jsonStr = const JsonEncoder.withIndent('  ').convert(preset.toJson());
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('导出动作预设 · ${preset.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '已生成该动作预设的配置文本，您可以直接复制分享给他人导入使用：',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  jsonStr,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 11.5),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
          FilledButton.icon(
            icon: const Icon(Icons.copy, size: 16),
            label: const Text('复制配置文本'),
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: jsonStr));
              if (ctx.mounted) {
                Navigator.pop(ctx);
                showAppToast(context, '配置已复制到剪贴板');
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _importPreset() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入快捷动作预设'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              '将他人分享的动作预设 JSON 配置文本粘贴在下方完成导入：',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: ctrl,
              maxLines: 8,
              minLines: 4,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                hintText: '在此粘贴动作预设配置文本...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('导入'),
          ),
        ],
      ),
    );

    if (ok == true && ctrl.text.trim().isNotEmpty && mounted) {
      try {
        final decoded = jsonDecode(ctrl.text.trim());
        if (decoded is Map<String, dynamic>) {
          final preset = TypingBlockPreset.fromJson(decoded);
          await ref.read(typingBlockPresetsProvider.notifier).savePreset(preset);
          if (mounted) {
            showAppToast(context, '已成功导入动作「${preset.name}」');
          }
        } else if (decoded is List) {
          int count = 0;
          for (final item in decoded) {
            if (item is Map) {
              final preset =
                  TypingBlockPreset.fromJson(item.cast<String, dynamic>());
              await ref
                  .read(typingBlockPresetsProvider.notifier)
                  .savePreset(preset);
              count++;
            }
          }
          if (mounted) {
            showAppToast(context, '已批量导入 $count 个动作预设');
          }
        }
      } catch (e) {
        if (mounted) {
          showAppToast(context, '导入失败：配置格式无效');
        }
      }
    }
  }

  void _showPresetActions(TypingBlockPreset preset) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                preset.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑动作'),
              onTap: () {
                Navigator.pop(ctx);
                _openEditor(existing: preset);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('另存为副本'),
              onTap: () {
                Navigator.pop(ctx);
                _duplicate(preset);
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('导出配置'),
              onTap: () {
                Navigator.pop(ctx);
                _exportPreset(preset);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除动作', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (dCtx) => AlertDialog(
                    title: const Text('确认删除'),
                    content: Text('确定删除动作预设「${preset.name}」吗？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(dCtx, false),
                        child: const Text('取消'),
                      ),
                      FilledButton(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.red),
                        onPressed: () => Navigator.pop(dCtx, true),
                        child: const Text('删除'),
                      ),
                    ],
                  ),
                );
                if (confirm == true && mounted) {
                  await ref
                      .read(typingBlockPresetsProvider.notifier)
                      .deletePreset(preset.id);
                  if (mounted) {
                    showAppToast(context, '已删除「${preset.name}」');
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
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

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('快捷动作预设'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '导入预设配置',
            onPressed: _importPreset,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新建动作预设'),
        onPressed: () => _openEditor(),
      ),
      body: Column(
        children: [
          // 顶置搜索栏
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '搜索动作名称、说明或按键...',
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
          ),
          Expanded(
            child: filtered.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.auto_fix_high,
                            size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          query.isEmpty ? '暂无快捷动作预设' : '未找到匹配的动作预设',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          query.isEmpty
                              ? '点击下方按钮新建，或在模板输入方案与悬浮窗中直接使用'
                              : '尝试更换搜索词',
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final p = filtered[index];
                      return Card(
                        margin: AppTheme.cardListMargin,
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                colorScheme.primary.withValues(alpha: 0.12),
                            foregroundColor: colorScheme.primary,
                            child: const Icon(Icons.auto_fix_high, size: 20),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  p.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: colorScheme.primaryContainer
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '${p.blocks.length} 步',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (p.description.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  p.description,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 4),
                              Text(
                                p.stepsPreview,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: Colors.blueGrey,
                                ),
                              ),
                            ],
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.more_vert),
                            onPressed: () => _showPresetActions(p),
                          ),
                          onTap: () => _openEditor(existing: p),
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
