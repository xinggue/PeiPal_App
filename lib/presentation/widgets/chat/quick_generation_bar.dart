import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/content_template.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import '../../../providers/quick_generation_presets_provider.dart';

/// 横向可滚动的「最近生成 / 已置顶套餐」快捷复用条。
///
/// 在聊天输入框上方传入 [onClose] 展示 `✕` 关闭按钮；
/// 在生成向导首页传入 [onOpenSettings] 展示设置入口（不展示关闭按钮）。
class QuickGenerationBar extends ConsumerWidget {
  final ValueChanged<QuickGenerationPreset> onSelectPreset;
  final VoidCallback? onClose;
  final VoidCallback? onOpenSettings;
  final String? selectedPresetId;
  final bool showWhenEmpty;
  final EdgeInsetsGeometry padding;
  final bool showTopBorder;

  const QuickGenerationBar({
    super.key,
    required this.onSelectPreset,
    this.onClose,
    this.onOpenSettings,
    this.selectedPresetId,
    this.showWhenEmpty = false,
    this.padding = const EdgeInsets.fromLTRB(12, 5, 6, 5),
    this.showTopBorder = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawPresets = ref.watch(quickGenerationPresetsProvider);
    final templates = ref.watch(templatesProvider).valueOrNull ?? const <Template>[];
    final templatesById = {for (final t in templates) t.id: t};

    final resolved = <({
      QuickGenerationPreset preset,
      String label,
    })>[];

    if (templatesById.isNotEmpty) {
      for (final preset in rawPresets) {
        final tmpl = templatesById[preset.templateId];
        if (tmpl == null) continue;
        ContentTemplate? ct;
        if (preset.contentTemplateId != null) {
          final cts = ref
                  .watch(contentTemplatesProvider(preset.templateId))
                  .valueOrNull ??
              const <ContentTemplate>[];
          ct = cts.where((c) => c.id == preset.contentTemplateId).firstOrNull;
        }
        resolved.add((
          preset: preset,
          label: preset.displayTitle(
            liveTemplate: tmpl,
            liveContentTemplate: ct,
          ),
        ));
      }
    }

    if (resolved.isEmpty && !showWhenEmpty) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        border: showTopBorder
            ? Border(
                top: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.45),
                ),
              )
            : null,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            '最近生成',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: resolved.isEmpty
                ? const SizedBox.shrink()
                : SizedBox(
                    height: 30,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: resolved.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 6),
                      itemBuilder: (ctx, i) {
                        final entry = resolved[i];
                        final preset = entry.preset;
                        final isSelected = selectedPresetId == preset.id;

                        return ActionChip(
                          avatar: preset.isPinned
                              ? Icon(
                                  Icons.push_pin,
                                  size: 12.5,
                                  color: isSelected
                                      ? scheme.primary
                                      : scheme.primary.withValues(alpha: 0.8),
                                )
                              : null,
                          label: Text(
                            entry.label,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: isSelected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color:
                                  isSelected ? scheme.primary : scheme.onSurface,
                            ),
                          ),
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          backgroundColor: isSelected
                              ? scheme.primary.withValues(alpha: 0.10)
                              : scheme.surfaceContainerLow,
                          side: BorderSide(
                            color: isSelected
                                ? scheme.primary
                                : scheme.outlineVariant.withValues(alpha: 0.55),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                          onPressed: () => onSelectPreset(preset),
                        );
                      },
                    ),
                  ),
          ),
          if (onOpenSettings != null) ...[
            const SizedBox(width: 4),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: onOpenSettings,
              icon: const Icon(Icons.settings_outlined, size: 15),
              label: const Text('设置', style: TextStyle(fontSize: 12)),
            ),
          ],
          if (onClose != null) ...[
            const SizedBox(width: 2),
            IconButton(
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: Icon(
                Icons.close,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              visualDensity: VisualDensity.compact,
              tooltip: '关闭',
              onPressed: onClose,
            ),
          ],
        ],
      ),
    );
  }
}
