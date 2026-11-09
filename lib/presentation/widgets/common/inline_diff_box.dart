import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/catalog_definition.dart';
import '../../../domain/models/catalog_mention.dart';
import '../../../providers/providers.dart';

enum DiffChangeKind {
  none,
  added,
  modified,
}

/// Tracks a pending AI change for a single text value.
/// Reusable across ContentTemplateEditorPage and RecordReviewPage.
class PendingTextDiff {
  final String beforeText;
  final String afterText;

  const PendingTextDiff({
    required this.beforeText,
    required this.afterText,
  });

  DiffChangeKind get kind {
    final b = beforeText.trim();
    final a = afterText.trim();
    if (b == a) return DiffChangeKind.none;
    if (b.isEmpty && a.isNotEmpty) return DiffChangeKind.added;
    return DiffChangeKind.modified;
  }

  bool get hasChange => kind != DiffChangeKind.none;
}

/// Top summary bar when there are pending AI changes in the editor.
class DiffSummaryBanner extends StatelessWidget {
  final int addedCount;
  final int modifiedCount;
  final VoidCallback onAcceptAll;
  final VoidCallback onRevertAll;
  final bool filterChangesOnly;
  final ValueChanged<bool>? onToggleFilterChanges;

  const DiffSummaryBanner({
    super.key,
    required this.addedCount,
    required this.modifiedCount,
    required this.onAcceptAll,
    required this.onRevertAll,
    this.filterChangesOnly = false,
    this.onToggleFilterChanges,
  });

  int get totalCount => addedCount + modifiedCount;

  @override
  Widget build(BuildContext context) {
    if (totalCount == 0) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final parts = <String>[];
    if (addedCount > 0) parts.add('新增 $addedCount');
    if (modifiedCount > 0) parts.add('细化 $modifiedCount');
    final detail = parts.join('，');

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.35),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 17, color: cs.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'AI 已更新 $totalCount 个字段（$detail）',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurface,
                  ),
                ),
              ),
              if (onToggleFilterChanges != null)
                InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () => onToggleFilterChanges!(!filterChangesOnly),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: filterChangesOnly
                          ? cs.primary
                          : cs.surface.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: cs.primary.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      filterChangesOnly ? '显示全部' : '仅看变更',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: filterChangesOnly ? cs.onPrimary : cs.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '可直接修改下方内容，或逐项/批量确认',
            style: TextStyle(
              fontSize: 11.5,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              SizedBox(
                width: double.infinity,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        foregroundColor: Colors.red.shade700,
                      ),
                      onPressed: onRevertAll,
                      icon: const Icon(Icons.undo_rounded, size: 15),
                      label:
                          const Text('全部撤回', style: TextStyle(fontSize: 12.5)),
                    ),
                    const SizedBox(width: 6),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      onPressed: onAcceptAll,
                      icon: const Icon(Icons.check_rounded, size: 15),
                      label:
                          const Text('全部采纳', style: TextStyle(fontSize: 12.5)),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Compact badge + accept/revert actions for a single card or section.
class DiffActionBadge extends StatelessWidget {
  final DiffChangeKind kind;
  final VoidCallback onAccept;
  final VoidCallback onRevert;

  const DiffActionBadge({
    super.key,
    required this.kind,
    required this.onAccept,
    required this.onRevert,
  });

  @override
  Widget build(BuildContext context) {
    if (kind == DiffChangeKind.none) return const SizedBox.shrink();

    final isAdded = kind == DiffChangeKind.added;
    final badgeColor = isAdded ? Colors.teal : Colors.amber.shade800;
    final badgeLabel = isAdded ? '新增' : '已细化';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: badgeColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: badgeColor.withValues(alpha: 0.35)),
          ),
          child: Text(
            badgeLabel,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: badgeColor,
            ),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onAccept,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.green.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check, size: 13, color: Colors.green.shade700),
                const SizedBox(width: 2),
                Text(
                  '采纳',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 4),
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: onRevert,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.undo, size: 12, color: Colors.red.shade700),
                const SizedBox(width: 2),
                Text(
                  '撤回',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: Colors.red.shade700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Shows the previous value right above an input field when a value was modified.
class InlineBeforePreviewBox extends ConsumerStatefulWidget {
  final String beforeText;
  final String label;
  final VoidCallback? onRestoreThis;

  const InlineBeforePreviewBox({
    super.key,
    required this.beforeText,
    this.label = '修改前',
    this.onRestoreThis,
  });

  @override
  ConsumerState<InlineBeforePreviewBox> createState() =>
      _InlineBeforePreviewBoxState();
}

class _InlineBeforePreviewBoxState
    extends ConsumerState<InlineBeforePreviewBox> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final catalogNames = {
      for (final c in (ref.watch(catalogsProvider).valueOrNull ??
          const <CatalogDefinition>[]))
        c.id: c.name,
    };
    final displayBefore = CatalogMentionHelper.toDisplayText(
      widget.beforeText.trim(),
      catalogNames: catalogNames,
    );
    if (displayBefore.isEmpty) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.amber.shade700.withValues(alpha: 0.25),
        ),
      ),
      child: InkWell(
        onTap: () => setState(() => _expanded = !_expanded),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                Icons.history_rounded,
                size: 14,
                color: Colors.amber.shade900,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${widget.label}：$displayBefore',
                    maxLines: _expanded ? null : 2,
                    overflow: _expanded
                        ? TextOverflow.visible
                        : TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurfaceVariant,
                      decoration: TextDecoration.lineThrough,
                      decorationColor:
                          cs.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                  ),
                ],
              ),
            ),
            if (widget.onRestoreThis != null) ...[
              const SizedBox(width: 6),
              InkWell(
                onTap: widget.onRestoreThis,
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  child: Text(
                    '还原此项',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
