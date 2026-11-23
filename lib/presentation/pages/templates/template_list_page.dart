import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import '../../widgets/engine_c/engine_c_sheets.dart';
import 'template_actions_sheet.dart';

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
              onPressed: () => showTemplateActionsSheet(context, ref, t),
            ),
            onTap: () => context.push('/templates/${t.id}/edit'),
          ),
        );
      },
    );
  }
}
