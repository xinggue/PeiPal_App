import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/content_template.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import '../../../providers/quick_generation_presets_provider.dart';

/// 横向可滚动的「最近生成 / 置顶复用」快捷复用条。
///
/// 在聊天输入框上方使用单行布局并传入 [onClose] 展示 `✕` 关闭按钮；
/// 在生成向导首页传入 [twoRowLayout]: `true` 与 [onOpenSettings]，上方展示标题与设置，下方胶囊占满整行宽度。
class QuickGenerationBar extends ConsumerWidget {
  final ValueChanged<QuickGenerationPreset> onSelectPreset;
  final VoidCallback? onClose;
  final VoidCallback? onOpenSettings;
  final String? selectedPresetId;
  final bool showWhenEmpty;
  final bool twoRowLayout;
  final EdgeInsetsGeometry padding;
  final bool showTopBorder;

  const QuickGenerationBar({
    super.key,
    required this.onSelectPreset,
    this.onClose,
    this.onOpenSettings,
    this.selectedPresetId,
    this.showWhenEmpty = false,
    this.twoRowLayout = false,
    this.padding = const EdgeInsets.fromLTRB(12, 7, 6, 7),
    this.showTopBorder = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rawPresets = ref.watch(quickGenerationPresetsProvider);
    final templates =
        ref.watch(templatesProvider).valueOrNull ?? const <Template>[];
    final templatesById = {for (final t in templates) t.id: t};

    final resolved = <({
      QuickGenerationPreset preset,
      String title,
      String subtitle,
    })>[];

    if (templatesById.isNotEmpty) {
      final pinnedItems = rawPresets.where((p) => p.isPinned).toList();
      final recentItems = rawPresets
          .where((p) => !p.isPinned && !pinnedItems.any((pin) => pin.matchesPreset(p)))
          .toList();

      for (final preset in [...pinnedItems, ...recentItems]) {
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
          title: preset.capsuleTitle(liveTemplate: tmpl),
          subtitle: preset.capsuleSubtitle(
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
      child: twoRowLayout
          ? _buildTwoRowContent(resolved, scheme)
          : _buildSingleRowContent(resolved, scheme),
    );
  }

  Widget _buildSingleRowContent(
    List<({QuickGenerationPreset preset, String title, String subtitle})> resolved,
    ColorScheme scheme,
  ) {
    return Row(
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
              : _buildCapsulesScroller(resolved),
        ),
        if (onOpenSettings != null) ...[
          const SizedBox(width: 4),
          _buildSettingsButton(),
        ],
        if (onClose != null) ...[
          const SizedBox(width: 2),
          _buildCloseButton(scheme),
        ],
      ],
    );
  }

  Widget _buildTwoRowContent(
    List<({QuickGenerationPreset preset, String title, String subtitle})> resolved,
    ColorScheme scheme,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Text(
              '最近生成',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            if (onOpenSettings != null) _buildSettingsButton(),
            if (onClose != null) ...[
              const SizedBox(width: 2),
              _buildCloseButton(scheme),
            ],
          ],
        ),
        if (resolved.isNotEmpty) ...[
          const SizedBox(height: 7),
          SizedBox(
            width: double.infinity,
            child: _buildCapsulesScroller(resolved),
          ),
        ],
      ],
    );
  }

  Widget _buildCapsulesScroller(
    List<({QuickGenerationPreset preset, String title, String subtitle})> resolved,
  ) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < resolved.length; i++) ...[
            if (i > 0) const SizedBox(width: 7),
            _QuickPresetPill(
              title: resolved[i].title,
              subtitle: resolved[i].subtitle,
              isSelected: selectedPresetId == resolved[i].preset.id,
              onTap: () => onSelectPreset(resolved[i].preset),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSettingsButton() {
    return TextButton.icon(
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      onPressed: onOpenSettings,
      icon: const Icon(Icons.settings_outlined, size: 15),
      label: const Text('设置', style: TextStyle(fontSize: 12)),
    );
  }

  Widget _buildCloseButton(ColorScheme scheme) {
    return IconButton(
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
    );
  }
}

class _QuickPresetPill extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickPresetPill({
    required this.title,
    required this.subtitle,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: isSelected
          ? scheme.primary.withValues(alpha: 0.11)
          : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(11),
        side: BorderSide(
          color: isSelected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.55),
          width: isSelected ? 1.2 : 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5.5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? scheme.primary : scheme.onSurface,
                ),
              ),
              const SizedBox(height: 1.5),
              Text(
                subtitle,
                maxLines: 1,
                softWrap: false,
                style: TextStyle(
                  fontSize: 10,
                  height: 1.2,
                  fontWeight: FontWeight.w400,
                  color: isSelected
                      ? scheme.primary.withValues(alpha: 0.85)
                      : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
