import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../pages/settings/api_key_guides_page.dart';

/// 顶部状态卡片在未配置时下方展示的醒目可关闭配置教程引导卡片
class ApiKeyTutorialNoticeBanner extends StatelessWidget {
  final VoidCallback onDismiss;

  const ApiKeyTutorialNoticeBanner({super.key, required this.onDismiss});

  void _openGuides(BuildContext context) {
    final router = GoRouter.maybeOf(context);
    if (router != null) {
      router.push('/settings/api-key-guides');
    } else {
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const ApiKeyGuidesPage()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gradientColors = isDark
        ? const [Color(0xFF1E40AF), Color(0xFF2563EB)]
        : const [Color(0xFF1565C0), Color(0xFF1E88E5)];

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: gradientColors.first.withValues(alpha: isDark ? 0.32 : 0.24),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: () => _openGuides(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 8, 16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.menu_book_rounded,
                          size: 23,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '不知道如何配置？',
                              style: TextStyle(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '点击查看配置教程',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: Colors.white.withValues(alpha: 0.92),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        size: 20,
                        color: Colors.white,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            IconButton(
              icon: Icon(
                Icons.close_rounded,
                size: 20,
                color: Colors.white.withValues(alpha: 0.85),
              ),
              tooltip: '关闭提示',
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}
