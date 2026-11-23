import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/engine_c/engine_c_sheets.dart';

/// 弹出文书类型卡片的三点操作菜单（复用于文书一览卡片与「文书类型」列表页）。
void showTemplateActionsSheet(
  BuildContext context,
  WidgetRef ref,
  Template template,
) {
  showModalBottomSheet(
    context: context,
    builder: (ctx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              template.name,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('编辑'),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/templates/${template.id}/edit');
            },
          ),
          ListTile(
            leading: const Icon(Icons.add_box_outlined),
            title: const Text('新建内容模板（基于该结构）'),
            onTap: () {
              Navigator.pop(ctx);
              context.push('/templates/${template.id}/content/new');
            },
          ),
          ListTile(
            leading: const Icon(Icons.copy_all_outlined),
            title: const Text('另存副本'),
            onTap: () {
              Navigator.pop(ctx);
              duplicateStructureTemplate(context, ref, template);
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
                template,
                publishKind: 'structure',
              );
            },
          ),
          ListTile(
            leading: const Icon(Icons.ios_share),
            title: const Text('导出模板'),
            onTap: () {
              Navigator.pop(ctx);
              EngineCExportSheet.showForTemplate(context, template);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('删除文书类型', style: TextStyle(color: Colors.red)),
            onTap: () async {
              Navigator.pop(ctx);
              final cts = await ref
                  .read(contentTemplateRepositoryProvider)
                  .getByStructure(template.id);
              if (!context.mounted) return;

              final warning = cts.isEmpty
                  ? '确定要删除文书类型「${template.name}」吗？'
                  : '确定要删除文书类型「${template.name}」吗？\n\n'
                      '⚠️ 警告：该结构下的 ${cts.length} 个内容模板也将被一并永久删除！';

              final confirm = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('确认删除'),
                  content: Text(warning),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('取消'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(c, true),
                      child:
                          const Text('删除', style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              );
              if (confirm == true) {
                await ref.read(templateRepositoryProvider).delete(template.id);
                ref.invalidate(templatesProvider);
                ref.invalidate(contentTemplatesProvider(template.id));
              }
            },
          ),
        ],
      ),
    ),
  );
}

/// 将指定文书类型深拷贝并另存为一个新的独立文书类型。
Future<void> duplicateStructureTemplate(
  BuildContext context,
  WidgetRef ref,
  Template template,
) async {
  final nameCtrl = TextEditingController(text: '${template.name}（副本）');
  final newName = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('另存为新文书类型'),
      content: TextField(
        controller: nameCtrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '新文书类型名称',
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
  WidgetsBinding.instance.addPostFrameCallback((_) => nameCtrl.dispose());

  if (newName == null || newName.isEmpty) return;

  final cloned = Template.fromMap(template.toMap());
  final copy = Template(
    name: newName,
    version: cloned.version,
    slots: cloned.slots,
    pipeline: cloned.pipeline,
    typingProfiles: cloned.typingProfiles,
  );
  await ref.read(templateRepositoryProvider).insert(copy);
  ref.invalidate(templatesProvider);
  if (context.mounted) {
    showAppToast(context, '已另存为「$newName」');
  }
}
