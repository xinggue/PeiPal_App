import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/content_template.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import '../../../providers/quick_generation_presets_provider.dart';
import '../../widgets/common/app_toast.dart';

/// 文书快捷生成管理页面 (/settings/quick-generation)
class QuickGenerationSettingsPage extends ConsumerWidget {
  const QuickGenerationSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final enabled = ref.watch(chatQuickPresetsEnabledProvider);
    final presets = ref.watch(quickGenerationPresetsProvider);
    final templates = ref.watch(templatesProvider).valueOrNull ?? const <Template>[];
    final templatesById = {for (final t in templates) t.id: t};
    final scheme = Theme.of(context).colorScheme;

    final pinned = presets.where((p) => p.isPinned).toList();
    final recent = presets.where((p) => !p.isPinned).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('文书快捷生成管理')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Card(
            elevation: 0,
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
            ),
            child: SwitchListTile(
              secondary: Icon(Icons.playlist_add_check_rounded, color: scheme.primary),
              title: const Text(
                '输入框上方显示最近生成',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
              ),
              value: enabled,
              onChanged: (v) =>
                  ref.read(chatQuickPresetsEnabledProvider.notifier).toggle(v),
            ),
          ),

          const SizedBox(height: 18),

          Row(
            children: [
              Text(
                '置顶管理',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: templates.isEmpty
                    ? () => showAppToast(context, '暂无可用文书类型')
                    : () => _showAddPinnedDialog(context, ref, templates),
                icon: const Icon(Icons.add, size: 17),
                label: const Text('添加置顶'),
              ),
            ],
          ),
          const SizedBox(height: 8),

          if (pinned.isEmpty)
            const _EmptyBox(text: '暂无置顶')
          else
            _PinnedGroupCard(
              items: pinned,
              templatesById: templatesById,
              onTapRow: (p) => _showRenameDialog(context, ref, p),
            ),

          const SizedBox(height: 18),

          Row(
            children: [
              Text(
                '最近生成',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
              const Spacer(),
              if (recent.isNotEmpty)
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () async {
                    await ref
                        .read(quickGenerationPresetsProvider.notifier)
                        .clearRecent();
                    if (context.mounted) {
                      showAppToast(context, '已清空最近生成记录');
                    }
                  },
                  child: const Text('清空记录'),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (recent.isEmpty)
            const _EmptyBox(text: '暂无最近生成记录')
          else
            _RecentGroupCard(
              items: recent,
              pinned: pinned,
              templatesById: templatesById,
            ),
        ],
      ),
    );
  }

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    QuickGenerationPreset preset,
  ) async {
    final ctrl = TextEditingController(text: preset.customTitle ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义名称'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: InputDecoration(
            labelText: '显示名称（留空恢复默认）',
            hintText: '${preset.templateName} · ${preset.contentTemplateName ?? "无模板"}',
            border: const OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    if (result == null) return;
    await ref
        .read(quickGenerationPresetsProvider.notifier)
        .renamePreset(preset.id, result);
  }

  Future<void> _showAddPinnedDialog(
    BuildContext context,
    WidgetRef ref,
    List<Template> templates,
  ) async {
    var selectedTemplate = templates.first;
    ContentTemplate? selectedCt;
    var allMaterials = true;
    final aliasCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final ctsAsync =
              ref.watch(contentTemplatesProvider(selectedTemplate.id));
          final cts = ctsAsync.valueOrNull ?? const <ContentTemplate>[];
          if (selectedCt != null && !cts.any((c) => c.id == selectedCt!.id)) {
            selectedCt = null;
          }

          return AlertDialog(
            title: const Text('添加置顶'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedTemplate.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '文书类型',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final t in templates)
                        DropdownMenuItem(value: t.id, child: Text(t.name)),
                    ],
                    onChanged: (id) {
                      if (id == null) return;
                      final next = templates.firstWhere((t) => t.id == id);
                      setDialog(() {
                        selectedTemplate = next;
                        selectedCt = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedCt?.id,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: '内容模板',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('不使用内容模板'),
                      ),
                      for (final c in cts)
                        DropdownMenuItem<String?>(
                          value: c.id,
                          child: Text(c.name),
                        ),
                    ],
                    onChanged: (id) {
                      setDialog(() {
                        selectedCt = id == null
                            ? null
                            : cts.where((c) => c.id == id).firstOrNull;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(value: true, label: Text('全部材料')),
                      ButtonSegment(value: false, label: Text('仅新增内容')),
                    ],
                    selected: {allMaterials},
                    onSelectionChanged: (s) =>
                        setDialog(() => allMaterials = s.first),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: aliasCtrl,
                    decoration: const InputDecoration(
                      labelText: '简称（选填）',
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
                child: const Text('保存并置顶'),
              ),
            ],
          );
        },
      ),
    );

    final alias = aliasCtrl.text.trim();
    WidgetsBinding.instance.addPostFrameCallback((_) => aliasCtrl.dispose());
    if (ok != true) return;

    await ref.read(quickGenerationPresetsProvider.notifier).addPinnedPreset(
          template: selectedTemplate,
          contentTemplate: selectedCt,
          allMaterials: allMaterials,
          customTitle: alias,
        );
    if (context.mounted) {
      showAppToast(context, '已添加置顶');
    }
  }
}

class _EmptyBox extends StatelessWidget {
  final String text;

  const _EmptyBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }
}

class _PinnedGroupCard extends ConsumerWidget {
  final List<QuickGenerationPreset> items;
  final Map<String, Template> templatesById;
  final ValueChanged<QuickGenerationPreset> onTapRow;

  const _PinnedGroupCard({
    required this.items,
    required this.templatesById,
    required this.onTapRow,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _PinnedRow(
              preset: items[i],
              liveTemplate: templatesById[items[i].templateId],
              canMoveUp: i > 0,
              canMoveDown: i < items.length - 1,
              onTap: () => onTapRow(items[i]),
              onMoveUp: () => ref
                  .read(quickGenerationPresetsProvider.notifier)
                  .movePinned(i, -1),
              onMoveDown: () => ref
                  .read(quickGenerationPresetsProvider.notifier)
                  .movePinned(i, 1),
              onDelete: () => ref
                  .read(quickGenerationPresetsProvider.notifier)
                  .deletePreset(items[i].id),
            ),
          ],
        ],
      ),
    );
  }
}

class _RecentGroupCard extends ConsumerWidget {
  final List<QuickGenerationPreset> items;
  final List<QuickGenerationPreset> pinned;
  final Map<String, Template> templatesById;

  const _RecentGroupCard({
    required this.items,
    required this.pinned,
    required this.templatesById,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            _RecentRow(
              preset: items[i],
              liveTemplate: templatesById[items[i].templateId],
              alreadyPinned: pinned.any((p) => p.matchesPreset(items[i])),
              onPin: () async {
                final added = await ref
                    .read(quickGenerationPresetsProvider.notifier)
                    .pinFromRecent(items[i].id);
                if (!context.mounted) return;
                showAppToast(context, added ? '已添加到置顶管理' : '已在置顶管理中');
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _PinnedRow extends ConsumerWidget {
  final QuickGenerationPreset preset;
  final Template? liveTemplate;
  final bool canMoveUp;
  final bool canMoveDown;
  final VoidCallback onTap;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onDelete;

  const _PinnedRow({
    required this.preset,
    required this.liveTemplate,
    required this.canMoveUp,
    required this.canMoveDown,
    required this.onTap,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final liveCt = _watchLiveContentTemplate(ref, preset);
    final title = preset.displayTitle(
      liveTemplate: liveTemplate,
      liveContentTemplate: liveCt,
    );
    final isStale = liveTemplate == null;
    final scopeLabel = preset.allMaterials ? '全部材料' : '仅新增内容';
    final fieldsLabel = preset.fieldCountSummary(liveTemplate: liveTemplate);

    return InkWell(
      onTap: isStale ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: isStale ? scheme.error : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isStale ? '原文书类型已删除' : '$fieldsLabel · $scopeLabel',
                    style: TextStyle(
                      fontSize: 12,
                      color: isStale ? scheme.error : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_up, size: 20),
              visualDensity: VisualDensity.compact,
              tooltip: '上移',
              onPressed: canMoveUp ? onMoveUp : null,
            ),
            IconButton(
              icon: const Icon(Icons.keyboard_arrow_down, size: 20),
              visualDensity: VisualDensity.compact,
              tooltip: '下移',
              onPressed: canMoveDown ? onMoveDown : null,
            ),
            IconButton(
              icon: Icon(Icons.delete_outline, size: 19, color: scheme.error),
              visualDensity: VisualDensity.compact,
              tooltip: '删除',
              onPressed: onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecentRow extends ConsumerWidget {
  final QuickGenerationPreset preset;
  final Template? liveTemplate;
  final bool alreadyPinned;
  final VoidCallback onPin;

  const _RecentRow({
    required this.preset,
    required this.liveTemplate,
    required this.alreadyPinned,
    required this.onPin,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final liveCt = _watchLiveContentTemplate(ref, preset);
    final title = preset.displayTitle(
      liveTemplate: liveTemplate,
      liveContentTemplate: liveCt,
    );
    final isStale = liveTemplate == null;
    final scopeLabel = preset.allMaterials ? '全部材料' : '仅新增内容';
    final fieldsLabel = preset.fieldCountSummary(liveTemplate: liveTemplate);

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                    color: isStale ? scheme.error : scheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isStale ? '原文书类型已删除' : '$fieldsLabel · $scopeLabel',
                  style: TextStyle(
                    fontSize: 12,
                    color: isStale ? scheme.error : scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              alreadyPinned ? Icons.push_pin : Icons.push_pin_outlined,
              size: 19,
              color: alreadyPinned ? scheme.primary : scheme.onSurfaceVariant,
            ),
            visualDensity: VisualDensity.compact,
            tooltip: alreadyPinned ? '已置顶' : '收藏并置顶',
            onPressed: onPin,
          ),
        ],
      ),
    );
  }
}

ContentTemplate? _watchLiveContentTemplate(
  WidgetRef ref,
  QuickGenerationPreset preset,
) {
  if (preset.contentTemplateId == null) return null;
  final cts = ref
          .watch(contentTemplatesProvider(preset.templateId))
          .valueOrNull ??
      const <ContentTemplate>[];
  return cts.where((c) => c.id == preset.contentTemplateId).firstOrNull;
}
