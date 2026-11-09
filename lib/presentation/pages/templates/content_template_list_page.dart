import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/content_template.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import '../../widgets/engine_c/engine_c_sheets.dart';

class ContentTemplateListPage extends ConsumerWidget {
  const ContentTemplateListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(templatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('内容模板'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '导入内容模板',
            onPressed: () => EngineCImportSheet.show(
              context,
              title: '导入内容模板',
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新建内容模板'),
        onPressed: () => _pickStructureAndCreate(context, ref),
      ),
      body: templatesAsync.when(
        data: (templates) {
          if (templates.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.article_outlined,
                      size: 64, color: Colors.grey),
                  const SizedBox(height: 16),
                  const Text('暂无文书类型，请先创建或导入模板',
                      style: TextStyle(color: Colors.grey)),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => context.push('/templates/new'),
                    child: const Text('创建文书类型'),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: templates.length,
            itemBuilder: (context, index) {
              final t = templates[index];
              return _StructureSection(template: t);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('加载失败: $err')),
      ),
    );
  }

  Future<void> _pickStructureAndCreate(
      BuildContext context, WidgetRef ref) async {
    final templates = ref.read(templatesProvider).valueOrNull ?? [];
    if (templates.isEmpty) {
      showAppToast(context, '暂无文书类型，请先创建');
      return;
    }

    final picked = await showModalBottomSheet<Template>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择基于哪个文书类型创建',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in templates)
                    ListTile(
                      leading: const Icon(Icons.schema_outlined),
                      title: Text(t.name),
                      subtitle: Text('${t.slots.length} 个字段'),
                      onTap: () => Navigator.pop(ctx, t),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (picked != null && context.mounted) {
      context.push('/templates/${picked.id}/content/new');
    }
  }
}

class _StructureSection extends ConsumerWidget {
  final Template template;

  const _StructureSection({required this.template});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctsAsync = ref.watch(contentTemplatesProvider(template.id));

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final slotNames = template.slots.map((s) => s.label).join('、');

    return Container(
      margin: AppTheme.cardListMargin,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(8),
          topRight: Radius.circular(18),
          bottomLeft: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: true,
          tilePadding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.folder_rounded,
              color: Colors.amber.shade700,
              size: 26,
            ),
          ),
          title: Text(
            template.name,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15.5),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  slotNames.isEmpty ? '暂无字段' : slotNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                ctsAsync.maybeWhen(
                  data: (cts) => Text(
                    '${template.slots.length} 个字段 · ${cts.length} 个内容模板',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                  ),
                  orElse: () => Text(
                    '${template.slots.length} 个字段',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                  ),
                ),
              ],
            ),
          ),
          trailing: IconButton(
            icon: Icon(Icons.add_circle, color: colorScheme.primary, size: 24),
            tooltip: '为该文书类型新建内容模板',
            onPressed: () => context.push('/templates/${template.id}/content/new'),
          ),
          children: [
            ctsAsync.when(
              data: (cts) {
                if (cts.isEmpty) {
                  return Container(
                    margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      '文件夹为空，点击右上方 ＋ 放入新模板',
                      style: TextStyle(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontSize: 12.5,
                      ),
                    ),
                  );
                }
                return Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  child: Column(
                    children: [
                      for (final ct in cts)
                        Container(
                          margin: const EdgeInsets.only(bottom: 6),
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                              width: 1,
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                            leading: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(
                                Icons.description_outlined,
                                color: colorScheme.primary,
                                size: 18,
                              ),
                            ),
                            title: Text(
                              ct.name,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                            subtitle: Text(
                              '${ct.filledSlotCount}/${template.slots.length} 个字段已填入范例',
                              style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                            trailing: PopupMenuButton<String>(
                              onSelected: (action) {
                                if (action == 'edit') {
                                  context.push(
                                      '/templates/${template.id}/content/${ct.id}/edit');
                                } else if (action == 'duplicate') {
                                  _duplicateTemplate(context, ref, ct);
                                } else if (action == 'migrate') {
                                  _pickTargetStructureAndMigrate(
                                      context, ref, ct);
                                } else if (action == 'publish') {
                                  EngineCExportSheet.showForTemplate(
                                    context,
                                    template,
                                    focusContentTemplate: ct,
                                    publishKind: 'content',
                                  );
                                } else if (action == 'export') {
                                  EngineCExportSheet.showForTemplate(
                                    context,
                                    template,
                                    focusContentTemplate: ct,
                                  );
                                } else if (action == 'delete') {
                                  _confirmDelete(context, ref, ct);
                                }
                              },
                              itemBuilder: (ctx) => const [
                                PopupMenuItem(value: 'edit', child: Text('编辑')),
                                PopupMenuItem(
                                  value: 'duplicate',
                                  child: Text('另存副本…'),
                                ),
                                PopupMenuItem(
                                  value: 'migrate',
                                  child: Text('迁移到其他文书…'),
                                ),
                                PopupMenuItem(
                                  value: 'publish',
                                  child: Text('发布到广场'),
                                ),
                                PopupMenuItem(
                                  value: 'export',
                                  child: Text('导出模板'),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child:
                                      Text('删除', style: TextStyle(color: Colors.red)),
                                ),
                              ],
                            ),
                            onTap: () => context.push(
                                '/templates/${template.id}/content/${ct.id}/edit'),
                          ),
                        ),
                    ],
                  ),
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (err, _) => Padding(
                padding: EdgeInsets.all(16),
                child: Text('加载失败: $err'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, ContentTemplate ct) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确认删除内容模板「${ct.name}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await ref.read(contentTemplateRepositoryProvider).delete(ct.id);
      ref.invalidate(contentTemplatesProvider(template.id));
    }
  }

  Future<void> _duplicateTemplate(
    BuildContext context,
    WidgetRef ref,
    ContentTemplate ct,
  ) async {
    final nameCtrl = TextEditingController(text: '${ct.name}（副本）');
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('另存为新内容模板'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '新模板名称',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              final v = nameCtrl.text.trim();
              if (v.isEmpty) return;
              Navigator.pop(ctx, v);
            },
            child: const Text('另存'),
          ),
        ],
      ),
    );
    nameCtrl.dispose();

    if (newName == null || newName.isEmpty) return;

    final copy = ContentTemplate(
      structureTemplateId: ct.structureTemplateId,
      name: newName,
      globalGuidance: ct.globalGuidance,
      fullExample: ct.fullExample,
      slots: Map<String, SlotContent>.from(ct.slots),
    );
    await ref.read(contentTemplateRepositoryProvider).insert(copy);
    ref.invalidate(contentTemplatesProvider(template.id));
    if (context.mounted) {
      showAppToast(context, '已另存为「$newName」');
    }
  }

  Future<void> _pickTargetStructureAndMigrate(
    BuildContext context,
    WidgetRef ref,
    ContentTemplate sourceCt,
  ) async {
    final allTemplates = ref.read(templatesProvider).valueOrNull ?? [];
    if (allTemplates.isEmpty) return;

    final picked = await showModalBottomSheet<Template>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '将「${sourceCt.name}」迁移到哪个文书类型？',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final t in allTemplates)
                    ListTile(
                      leading: const Icon(Icons.schema_outlined),
                      title: Text(t.name),
                      subtitle: Text(
                        '${t.slots.length} 个字段${t.id == template.id ? "（当前文书类型）" : ""}',
                      ),
                      onTap: () => Navigator.pop(ctx, t),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (picked != null && context.mounted) {
      context.push(
        '/templates/${picked.id}/content/new?migrateFrom=${sourceCt.id}',
      );
    }
  }
}
