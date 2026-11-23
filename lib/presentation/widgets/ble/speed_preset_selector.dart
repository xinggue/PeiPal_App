import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/ble/timing_params.dart';
import '../../../providers/providers.dart';
import '../common/app_toast.dart';

/// 速度预设方形快切阵列（复用于大悬浮窗展开态与「蓝牙与键盘」设置页）。
class SpeedPresetSquareGrid extends ConsumerStatefulWidget {
  final bool compact;
  final ScrollController? scrollController;
  final bool showSelectedLabel;

  const SpeedPresetSquareGrid({
    super.key,
    this.compact = false,
    this.scrollController,
    this.showSelectedLabel = true,
  });

  @override
  ConsumerState<SpeedPresetSquareGrid> createState() =>
      _SpeedPresetSquareGridState();
}

class _SpeedPresetSquareGridState extends ConsumerState<SpeedPresetSquareGrid> {
  ScrollController? _ownedScrollCtrl;

  ScrollController get _scrollCtrl =>
      widget.scrollController ?? (_ownedScrollCtrl ??= ScrollController());

  @override
  void dispose() {
    _ownedScrollCtrl?.dispose();
    super.dispose();
  }

  Future<void> _applyPreset(TimingPreset preset) async {
    await ref.read(activeTimingControllerProvider.notifier).applyPreset(preset);
    if (!mounted) return;
    showAppToast(context, '已切换速度：${preset.name}');
  }

  Widget _buildSquareTile({
    required TimingPreset preset,
    required bool isSelected,
    required ColorScheme colorScheme,
    required bool compact,
    double? tileWidth,
  }) {
    final speedVal = preset.estimatedCharsPerSec.toStringAsFixed(0);
    final radius = compact ? 6.0 : 8.0;
    final numSize = compact
        ? 11.5
        : (tileWidth != null ? (tileWidth * 0.30).clamp(10.5, 15.5) : 15.5);
    final unitSize = compact
        ? 9.0
        : (tileWidth != null ? (tileWidth * 0.21).clamp(8.0, 11.0) : 11.0);

    return InkWell(
      borderRadius: BorderRadius.circular(radius),
      onTap: () => _applyPreset(preset),
      child: Container(
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : colorScheme.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: isSelected ? colorScheme.primary : colorScheme.outlineVariant,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              speedVal,
              maxLines: 1,
              style: TextStyle(
                fontSize: numSize,
                fontWeight: FontWeight.bold,
                height: compact ? 1.0 : 1.1,
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface,
              ),
            ),
            Text(
              '字/秒',
              maxLines: 1,
              style: TextStyle(
                fontSize: unitSize,
                height: compact ? 1.0 : 1.1,
                color: isSelected
                    ? colorScheme.onPrimary.withValues(alpha: 0.85)
                    : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeTiming = ref.watch(activeTimingControllerProvider);
    final presets = ref.watch(timingPresetsProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final sorted = List<TimingPreset>.from(presets)
      ..sort((a, b) => a.estimatedCharsPerSec.compareTo(b.estimatedCharsPerSec));
    if (sorted.isEmpty) return const SizedBox.shrink();

    final selectedName = activeTiming.matchedPreset?.name ?? '实时参数';

    if (widget.compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 30,
            child: Scrollbar(
              controller: _scrollCtrl,
              thumbVisibility: true,
              thickness: 3,
              radius: const Radius.circular(2),
              child: ListView.separated(
                controller: _scrollCtrl,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 4),
                itemCount: sorted.length,
                separatorBuilder: (_, _) => const SizedBox(width: 4),
                itemBuilder: (context, index) {
                  final p = sorted[index];
                  final isSelected = activeTiming.matchedPreset?.id == p.id;
                  return SizedBox(
                    width: 46,
                    child: _buildSquareTile(
                      preset: p,
                      isSelected: isSelected,
                      colorScheme: colorScheme,
                      compact: true,
                    ),
                  );
                },
              ),
            ),
          ),
          if (widget.showSelectedLabel) ...[
            const SizedBox(height: 2),
            Text(
              '已选：$selectedName',
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: colorScheme.primary,
              ),
            ),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final count = sorted.length;
        final spacing = count > 6 ? 4.0 : 8.0;
        final totalWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 320.0;
        final tileWidth =
            ((totalWidth - spacing * (count - 1)) / count).clamp(24.0, 80.0);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: List.generate(count, (index) {
                final p = sorted[index];
                final isSelected = activeTiming.matchedPreset?.id == p.id;
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: index == 0 ? 0 : spacing / 2,
                      right: index == count - 1 ? 0 : spacing / 2,
                    ),
                    child: AspectRatio(
                      aspectRatio: 1.0,
                      child: _buildSquareTile(
                        preset: p,
                        isSelected: isSelected,
                        colorScheme: colorScheme,
                        compact: false,
                        tileWidth: tileWidth,
                      ),
                    ),
                  ),
                );
              }),
            ),
            if (widget.showSelectedLabel) ...[
              const SizedBox(height: 6),
              Text(
                '已选：$selectedName',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
