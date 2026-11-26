import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/external_ai_launcher.dart';
import '../../../providers/storefront_compliance_provider.dart';

/// 仅中国大陆 iOS 受限模式可见的「复制并打开外部 AI」组合按钮：
/// 主体点击直接复制提示词并拉起上次选中的 AI，右侧小箭头可切换常用 AI。
class CopyAndLaunchAiButton extends ConsumerWidget {
  final String promptText;
  final bool compact;
  final bool fullWidth;

  const CopyAndLaunchAiButton({
    super.key,
    required this.promptText,
    this.compact = false,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(isChinaAiRestrictedProvider)) {
      return const SizedBox.shrink();
    }

    final activeApp = ref.watch(preferredExternalAiProvider);
    final bgColor = Colors.amber.shade800;
    final verticalPad = compact ? 7.0 : 9.0;
    final fontSize = compact ? 11.5 : 13.0;
    final iconSize = compact ? 14.0 : 16.0;

    final mainTap = InkWell(
      onTap: () => copyPromptAndLaunchExternalAi(
        context: context,
        ref: ref,
        promptText: promptText,
        target: activeApp,
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 12,
          vertical: verticalPad,
        ),
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.open_in_new_rounded, size: iconSize, color: Colors.white),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                '复制并打开 ${activeApp.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: fontSize,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final selectorButton = PopupMenuButton<String>(
      tooltip: '切换 AI 应用',
      padding: EdgeInsets.zero,
      onSelected: (id) {
        final picked = findExternalAiApp(id);
        copyPromptAndLaunchExternalAi(
          context: context,
          ref: ref,
          promptText: promptText,
          target: picked,
        );
      },
      itemBuilder: (ctx) => [
        for (final app in kChinaExternalAiApps)
          PopupMenuItem<String>(
            value: app.id,
            height: 40,
            child: Row(
              children: [
                Icon(
                  app.id == activeApp.id
                      ? Icons.check_rounded
                      : Icons.open_in_new_rounded,
                  size: 16,
                  color: app.id == activeApp.id
                      ? Theme.of(ctx).colorScheme.primary
                      : Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(app.name, style: const TextStyle(fontSize: 13.5)),
              ],
            ),
          ),
      ],
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 7 : 8,
          vertical: verticalPad,
        ),
        child: Icon(
          Icons.arrow_drop_down_rounded,
          size: iconSize + 3,
          color: Colors.white,
        ),
      ),
    );

    return Material(
      color: bgColor,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (fullWidth) Expanded(child: mainTap) else mainTap,
            const VerticalDivider(
              width: 1,
              thickness: 1,
              indent: 6,
              endIndent: 6,
              color: Colors.white24,
            ),
            selectorButton,
          ],
        ),
      ),
    );
  }
}
