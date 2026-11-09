import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import '../../widgets/engine_c/engine_c_sheets.dart';

class TemplateListPage extends ConsumerWidget {
  const TemplateListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('文书类型'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            tooltip: '导入模板',
            onPressed: () => EngineCImportSheet.show(
              context,
              title: '导入模板',
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新建文书类型'),
        onPressed: () => context.push('/templates/new'),
      ),
      body: templates.when(
        data: (list) => _buildList(context, ref, list),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(child: Text('加载失败: $err')),
      ),
    );
  }

  void _showTemplateActions(BuildContext context, WidgetRef ref, Template t) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(t.name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/templates/${t.id}/edit');
              },
            ),
            ListTile(
              leading: const Icon(Icons.add_box_outlined),
              title: const Text('新建内容模板（基于该结构）'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/templates/${t.id}/content/new');
              },
            ),
            ListTile(
              leading: const Icon(Icons.article_outlined),
              title: const Text('查看其内容模板'),
              onTap: () {
                Navigator.pop(ctx);
                context.push('/content-templates');
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_upload_outlined),
              title: const Text('发布到在线模板广场'),
              onTap: () {
                Navigator.pop(ctx);
                EngineCExportSheet.showForTemplate(
                  context,
                  t,
                  publishKind: 'structure',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share),
              title: const Text('导出模板'),
              onTap: () {
                Navigator.pop(ctx);
                EngineCExportSheet.showForTemplate(context, t);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text('删除文书类型', style: TextStyle(color: Colors.red)),
              onTap: () async {
                Navigator.pop(ctx);
                final cts = await ref
                    .read(contentTemplateRepositoryProvider)
                    .getByStructure(t.id);
                if (!context.mounted) return;

                final warning = cts.isEmpty
                    ? '确定要删除文书类型「${t.name}」吗？'
                    : '确定要删除文书类型「${t.name}」吗？\n\n'
                        '⚠️ 警告：该结构下的 ${cts.length} 个内容模板也将被一并永久删除！';

                final confirm = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('确认删除'),
                    content: Text(warning),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(c, false),
                          child: const Text('取消')),
                      TextButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: const Text('删除',
                            style: TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                );
                if (confirm == true) {
                  await ref.read(templateRepositoryProvider).delete(t.id);
                  ref.invalidate(templatesProvider);
                  ref.invalidate(contentTemplatesProvider(t.id));
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(
      BuildContext context, WidgetRef ref, List<Template> templates) {
    if (templates.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.schema_outlined, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            const Text('暂无文书类型',
                style: TextStyle(color: Colors.grey, fontSize: 16)),
            const SizedBox(height: 8),
            const Text('点击下方按钮创建模板，或点击右上角导入配置文本',
                style: TextStyle(color: Colors.grey, fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('创建文书类型'),
              onPressed: () => context.push('/templates/new'),
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
        final profilesCount = t.typingProfiles.length;
        final slotNames = t.slots.map((s) => s.label).join('、');

        return Card(
          margin: AppTheme.cardListMargin,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
              child: const Icon(Icons.schema_outlined, size: 20),
            ),
            title: Text(t.name,
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 3),
                Text(
                  slotNames.isEmpty ? '暂无字段' : slotNames,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${t.slots.length} 个字段 · $profilesCount 套输入方案',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showTemplateActions(context, ref, t),
            ),
            onTap: () => context.push('/templates/${t.id}/edit'),
          ),
        );
      },
    );
  }
}
