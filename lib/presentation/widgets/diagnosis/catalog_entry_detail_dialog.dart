import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/favorite_diagnosis.dart';
import '../../../providers/providers.dart';
import '../common/app_toast.dart';

/// 标准词条详情与收藏/标签管理弹窗
class CatalogEntryDetailDialog {
  static Future<bool?> show(
    BuildContext context,
    WidgetRef ref, {
    required String catalogType,
    required String code,
    required String name,
    String version = '',
    String note = '',
    List<String> initialTags = const [],
    bool isFavorite = false,
  }) async {
    final codeCtrl = TextEditingController(text: code);
    final nameCtrl = TextEditingController(text: name);
    final versionCtrl = TextEditingController(text: version);
    final noteCtrl = TextEditingController(text: note);
    final newTagCtrl = TextEditingController();

    final currentTags = List<String>.from(initialTags);

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final allLibraryTags = ref.watch(catalogTagsProviderFamily(catalogType));

          void toggleTag(String tag) {
            setDialogState(() {
              if (currentTags.contains(tag)) {
                currentTags.remove(tag);
              } else {
                currentTags.add(tag);
              }
            });
          }

          void addNewTag() {
            final t = newTagCtrl.text.trim();
            if (t.isNotEmpty) {
              ref.read(catalogTagsProviderFamily(catalogType).notifier).addTag(t);
              setDialogState(() {
                if (!currentTags.contains(t)) currentTags.add(t);
                newTagCtrl.clear();
              });
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(
                  isFavorite ? Icons.bookmark_rounded : Icons.bookmark_add_outlined,
                  color: isFavorite ? Colors.amber.shade700 : Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(isFavorite ? '编辑词条与标签' : '收藏标准词条'),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '词条名称 *',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    decoration: const InputDecoration(
                      labelText: '标准编码',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: versionCtrl,
                    decoration: const InputDecoration(
                      labelText: '来源版本 / 说明',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: noteCtrl,
                    decoration: const InputDecoration(
                      labelText: '备注 / 自定义说明',
                      hintText: '可选',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Tag Selection
                  const Text(
                    '打上分类标签：',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  if (allLibraryTags.isEmpty && currentTags.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '暂无标签，可在下方输入新标签后点击 ＋ 添加',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    )
                  else
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: {
                        ...allLibraryTags,
                        ...currentTags,
                      }.map((tag) {
                        final isSelected = currentTags.contains(tag);
                        return FilterChip(
                          label: Text(tag, style: const TextStyle(fontSize: 12)),
                          selected: isSelected,
                          visualDensity: VisualDensity.compact,
                          onSelected: (_) => toggleTag(tag),
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 8),

                  // Add new tag row
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: newTagCtrl,
                          style: const TextStyle(fontSize: 12),
                          decoration: const InputDecoration(
                            hintText: '新建标签名称',
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => addNewTag(),
                        ),
                      ),
                      const SizedBox(width: 6),
                      IconButton.filledTonal(
                        icon: const Icon(Icons.add, size: 18),
                        tooltip: '添加标签',
                        onPressed: addNewTag,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              if (isFavorite)
                TextButton(
                  onPressed: () => Navigator.pop(ctx, false), // false means delete/unfavorite
                  child: const Text('取消收藏', style: TextStyle(color: Colors.red)),
                ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: const Text('关闭'),
              ),
              FilledButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isEmpty) {
                    showAppToast(context, '词条名称不能为空');
                    return;
                  }
                  Navigator.pop(ctx, true); // true means save/favorite
                },
                child: Text(isFavorite ? '保存修改' : '确认收藏'),
              ),
            ],
          );
        },
      ),
    );

    if (result == true) {
      final repo = ref.read(favoriteDiagnosisRepositoryProvider);
      final finalName = nameCtrl.text.trim();
      final finalCode = codeCtrl.text.trim();
      final finalVersion = versionCtrl.text.trim();
      final finalNote = noteCtrl.text.trim();

      // Check if existing record by code+name exists
      final existing = await repo.findByCodeAndName(finalCode, finalName, catalogType: catalogType);
      if (existing != null) {
        final updated = existing.copyWith(
          name: finalName,
          code: finalCode,
          version: finalVersion,
          note: finalNote,
          tags: currentTags,
        );
        await repo.update(updated);
      } else {
        final newEntry = FavoriteDiagnosis(
          catalogType: catalogType,
          code: finalCode,
          name: finalName,
          version: finalVersion,
          note: finalNote,
          tags: currentTags,
        );
        await repo.insert(newEntry);
      }

      ref.invalidate(favoriteDiagnosesProvider);
      ref.invalidate(catalogEntriesProvider(catalogType));
      if (context.mounted) {
        showSuccessToast(context, isFavorite ? '已更新词条与标签' : '已收藏并添加标签');
      }
      return true;
    } else if (result == false) {
      // Unfavorite
      final repo = ref.read(favoriteDiagnosisRepositoryProvider);
      await repo.deleteByCodeAndName(code, name, catalogType: catalogType);
      ref.invalidate(favoriteDiagnosesProvider);
      ref.invalidate(catalogEntriesProvider(catalogType));
      if (context.mounted) {
        showAppToast(context, '已取消收藏');
      }
      return false;
    }

    return null;
  }
}
