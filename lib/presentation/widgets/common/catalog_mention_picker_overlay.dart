import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/catalog_definition.dart';
import '../../../domain/models/catalog_mention.dart';
import '../../../providers/providers.dart';
import 'catalog_visuals.dart';

/// 左右分栏悬浮选择气泡（支持多选）
/// 左栏：标准库类型（诊断库、手术库等）
/// 右栏：当前选中类型下的分类标签（可勾选多个），点击底栏确定按钮一次性插入多个胶囊
class CatalogMentionPickerOverlay {
  static void show({
    required BuildContext context,
    required WidgetRef ref,
    required Offset position,
    required ValueChanged<List<CatalogMentionRef>> onSelected,
  }) {
    late OverlayEntry entry;

    entry = OverlayEntry(
      builder: (ctx) {
        final screenW = MediaQuery.of(ctx).size.width;
        final screenH = MediaQuery.of(ctx).size.height;
        const panelW = 320.0;
        const panelH = 260.0;

        return Stack(
          children: [
            // 全屏透明遮罩，点击外部退出
            GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => entry.remove(),
              child: const SizedBox.expand(),
            ),
            Positioned(
              left: position.dx.clamp(12.0, (screenW - panelW - 12.0).clamp(12.0, screenW)),
              top: position.dy.clamp(50.0, (screenH - panelH - 20.0).clamp(50.0, screenH)),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(10),
                color: Theme.of(ctx).colorScheme.surface,
                child: Container(
                  width: panelW,
                  height: panelH,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Theme.of(ctx).dividerColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: _SplitColumnsPicker(
                    ref: ref,
                    onConfirmed: (mentions) {
                      entry.remove();
                      onSelected(mentions);
                    },
                    onCancel: () => entry.remove(),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );

    Overlay.of(context).insert(entry);
  }
}

class _SplitColumnsPicker extends StatefulWidget {
  final WidgetRef ref;
  final ValueChanged<List<CatalogMentionRef>> onConfirmed;
  final VoidCallback onCancel;

  const _SplitColumnsPicker({
    required this.ref,
    required this.onConfirmed,
    required this.onCancel,
  });

  @override
  State<_SplitColumnsPicker> createState() => _SplitColumnsPickerState();
}

class _SplitColumnsPickerState extends State<_SplitColumnsPicker> {
  String _selectedType = '';
  // 已勾选的项（按 key: "type:tag" 存储）
  final Map<String, CatalogMentionRef> _selectedMentions = {};

  @override
  Widget build(BuildContext context) {
    final catalogs = (widget.ref.watch(catalogsProvider).valueOrNull ??
            const <CatalogDefinition>[])
        .where((c) => c.isEnabled)
        .toList();
    final selectedType = catalogs.any((c) => c.id == _selectedType)
        ? _selectedType
        : (catalogs.isNotEmpty ? catalogs.first.id : '');
    final tags = selectedType.isEmpty
        ? const <String>[]
        : widget.ref.watch(catalogTagsProviderFamily(selectedType));
    final theme = Theme.of(context);
    final selectedCount = _selectedMentions.length;

    return Column(
      children: [
        // 顶栏提示 (彻底去除多余灰字提示)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(9)),
          ),
          child: const Row(
            children: [
              Icon(Icons.alternate_email, size: 13, color: Colors.blueGrey),
              SizedBox(width: 5),
              Text(
                '引用标准词库',
                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // 左右分栏
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 左栏：标准库类型
              Container(
                width: 105,
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                child: ListView(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  children: [
                    if (catalogs.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(10),
                        child: Text(
                          '暂无词库',
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500),
                        ),
                      )
                    else
                      for (final c in catalogs)
                        _buildTypeItem(definition: c),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),

              // 右栏：该类型下的具体标签列表（支持多选勾选）
              Expanded(
                child: tags.isEmpty
                    ? Center(
                        child: Text(
                          '暂无标签',
                          style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        itemCount: tags.length,
                        itemBuilder: (ctx, i) {
                          final tag = tags[i];
                          final key = '$selectedType:$tag';
                          final isChecked = _selectedMentions.containsKey(key);

                          return InkWell(
                            onTap: () {
                              setState(() {
                                if (isChecked) {
                                  _selectedMentions.remove(key);
                                } else {
                                  _selectedMentions[key] = CatalogMentionRef(
                                    catalogType: selectedType,
                                    tag: tag,
                                  );
                                }
                              });
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: Checkbox(
                                      value: isChecked,
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                      onChanged: (val) {
                                        setState(() {
                                          if (val == true) {
                                            _selectedMentions[key] = CatalogMentionRef(
                                              catalogType: selectedType,
                                              tag: tag,
                                            );
                                          } else {
                                            _selectedMentions.remove(key);
                                          }
                                        });
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      tag,
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: isChecked ? FontWeight.w600 : FontWeight.normal,
                                        color: isChecked ? theme.colorScheme.primary : Colors.black87,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
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

        const Divider(height: 1),

        // 底栏：确定多选插入按钮
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            children: [
              Text(
                selectedCount > 0 ? '已选 $selectedCount 个标签' : '请勾选标签',
                style: TextStyle(
                  fontSize: 11,
                  color: selectedCount > 0 ? theme.colorScheme.primary : Colors.grey,
                  fontWeight: selectedCount > 0 ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              const Spacer(),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                ),
                onPressed: widget.onCancel,
                child: const Text('取消', style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(width: 6),
              FilledButton(
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: selectedCount > 0
                    ? () => widget.onConfirmed(_selectedMentions.values.toList())
                    : null,
                child: const Text('插入', style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTypeItem({required CatalogDefinition definition}) {
    final isSelected = _selectedType == definition.id;
    final theme = Theme.of(context);
    final accent = catalogColor(definition, theme);
    final countForType = _selectedMentions.values
        .where((m) => m.catalogType == definition.id)
        .length;

    return InkWell(
      onTap: () {
        if (_selectedType != definition.id) {
          setState(() => _selectedType = definition.id);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        color: isSelected
            ? theme.colorScheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        child: Row(
          children: [
            Icon(
              catalogIcon(definition.icon.isEmpty ? definition.id : definition.icon),
              size: 15,
              color: isSelected ? theme.colorScheme.primary : accent,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                definition.name,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? theme.colorScheme.primary : Colors.black87,
                ),
              ),
            ),
            if (countForType > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$countForType',
                  style: const TextStyle(fontSize: 9.5, color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
