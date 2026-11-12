import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/catalog_definition.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';

/// 字段选择 + 补充要求输入。
///
/// 普通文书生成向导的第 4 步与审阅页的「重写」共用此组件，保证交互与样式一致。
class GenerationFieldsAndRequirements extends ConsumerStatefulWidget {
  final List<TemplateSlot> slots;
  final Set<String> selectedKeys;
  final TextEditingController instructionsController;
  final ValueChanged<Set<String>> onSelectionChanged;
  final VoidCallback? onInstructionsChanged;
  final String title;
  final String instructionsHint;

  const GenerationFieldsAndRequirements({
    super.key,
    required this.slots,
    required this.selectedKeys,
    required this.instructionsController,
    required this.onSelectionChanged,
    this.onInstructionsChanged,
    this.title = '生成字段',
    this.instructionsHint = '补充指示 / 额外要求 (选填)',
  });

  @override
  ConsumerState<GenerationFieldsAndRequirements> createState() =>
      _GenerationFieldsAndRequirementsState();
}

class _GenerationFieldsAndRequirementsState
    extends ConsumerState<GenerationFieldsAndRequirements> {
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    final ctrl = _scrollCtrl;
    WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slots = widget.slots;
    final selectedKeys = widget.selectedKeys;
    final title = widget.title;
    final theme = Theme.of(context);
    final catalogDefinitions = {
      for (final c in (ref.watch(catalogsProvider).valueOrNull ??
          const <CatalogDefinition>[]))
        c.id: c,
    };

    return Column(
      children: [
        // 快捷操作栏（全选、全不选、反选）
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
          child: Row(
            children: [
              Text(
                '$title (${selectedKeys.length}/${slots.length})',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              ActionChip(
                label: const Text('全选', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                onPressed: () =>
                    widget.onSelectionChanged(slots.map((s) => s.key).toSet()),
              ),
              const SizedBox(width: 6),
              ActionChip(
                label: const Text('全不选', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                onPressed: () => widget.onSelectionChanged(<String>{}),
              ),
              const SizedBox(width: 6),
              ActionChip(
                label: const Text('反选', style: TextStyle(fontSize: 11)),
                visualDensity: VisualDensity.compact,
                onPressed: () {
                  final all = slots.map((s) => s.key).toSet();
                  widget.onSelectionChanged(all.difference(selectedKeys));
                },
              ),
            ],
          ),
        ),

        const Divider(height: 1),

        // 槽位列表
        Expanded(
          child: Scrollbar(
            controller: _scrollCtrl,
            child: ListView.builder(
              controller: _scrollCtrl,
              primary: false,
              padding: EdgeInsets.zero,
              itemCount: slots.length,
              itemBuilder: (ctx, i) {
                final s = slots[i];
                final isChecked = selectedKeys.contains(s.key);
                final displayName = s.label.isNotEmpty ? s.label : s.key;

                return CheckboxListTile(
                  value: isChecked,
                  dense: true,
                  title: Text(displayName, style: const TextStyle(fontSize: 13.5)),
                  subtitle: s.catalogType == null ||
                          s.catalogType!.trim().isEmpty
                      ? null
                      : Text(
                          '关联 ${catalogDefinitions[s.catalogType]?.name ?? s.catalogType}',
                          style: const TextStyle(
                              fontSize: 11, color: Colors.blue),
                        ),
                  onChanged: (checked) {
                    final next = Set<String>.from(selectedKeys);
                    if (checked == true) {
                      next.add(s.key);
                    } else {
                      next.remove(s.key);
                    }
                    widget.onSelectionChanged(next);
                  },
                );
              },
            ),
          ),
        ),

        // 特别补充要求输入框
        Container(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            border: Border(
              top: BorderSide(color: theme.dividerColor.withValues(alpha: 0.15)),
            ),
          ),
          child: TextField(
            controller: widget.instructionsController,
            maxLines: 2,
            minLines: 1,
            onChanged: widget.onInstructionsChanged == null
                ? null
                : (_) => widget.onInstructionsChanged!(),
            style: const TextStyle(fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: widget.instructionsHint,
              hintStyle: TextStyle(fontSize: 11.5, color: Colors.grey.shade500),
              prefixIcon: const Icon(Icons.edit_note, size: 20, color: Colors.teal),
              filled: true,
              fillColor: Colors.grey.withValues(alpha: 0.08),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: Colors.teal),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
