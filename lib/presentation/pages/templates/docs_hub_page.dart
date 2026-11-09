import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/providers.dart';

class DocsHubPage extends ConsumerWidget {
  const DocsHubPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templates = ref.watch(templatesProvider).valueOrNull ?? [];
    final totalSlots = templates.fold<int>(0, (sum, t) => sum + t.slots.length);
    final favEntries = ref.watch(favoriteDiagnosesProvider).valueOrNull ?? [];
    final blockPresets = ref.watch(typingBlockPresetsProvider);

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文书与模板'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _PortalCard(
            icon: Icons.schema_outlined,
            iconBg: colorScheme.primaryContainer,
            iconColor: colorScheme.onPrimaryContainer,
            title: '文书类型',
            subtitle: '字段定义、解析流程与打字方案',
            badgeText: templates.isEmpty
                ? '暂无类型'
                : '${templates.length} 个类型 · $totalSlots 个字段',
            onTap: () => context.push('/templates'),
          ),
          const SizedBox(height: 12),
          _PortalCard(
            icon: Icons.folder_special_rounded,
            iconBg: Colors.amber.shade100,
            iconColor: Colors.amber.shade900,
            title: '内容模板',
            subtitle: '档案袋式范例库与各字段写作示范',
            badgeText: '查看各类型写作范例',
            onTap: () => context.push('/content-templates'),
          ),
          const SizedBox(height: 12),
          _PortalCard(
            icon: Icons.bookmark_outline_rounded,
            iconBg: Colors.teal.shade100,
            iconColor: Colors.teal.shade900,
            title: '标准词条库',
            subtitle: '检索与维护标准术语、高频词条',
            badgeText: favEntries.isEmpty
                ? '支持拼音首字母检索'
                : '${favEntries.length} 条已收藏常用词条',
            onTap: () => context.push('/diagnoses'),
          ),
          const SizedBox(height: 12),
          _PortalCard(
            icon: Icons.cloud_outlined,
            iconBg: Colors.indigo.shade100,
            iconColor: Colors.indigo.shade900,
            title: '在线模板广场',
            subtitle: '云端共享、发布与一键下载精选模板',
            badgeText: '探索精选文书与输入方案',
            onTap: () => context.push('/hub'),
          ),
          const SizedBox(height: 12),
          _PortalCard(
            icon: Icons.auto_fix_high_rounded,
            iconBg: Colors.deepOrange.shade100,
            iconColor: Colors.deepOrange.shade900,
            title: '快捷动作预设',
            subtitle: '键盘宏、组合键与常用输入序列',
            badgeText: '${blockPresets.length} 套动作 · 可在悬浮窗与方案调用',
            onTap: () => context.push('/typing-presets'),
          ),
          const SizedBox(height: 12),
          _PortalCard(
            icon: Icons.import_export_rounded,
            iconBg: Colors.purple.shade100,
            iconColor: Colors.purple.shade900,
            title: '导入与导出中心',
            subtitle: '全量数据备份、文书模板导入与分享包',
            badgeText: '备份与多端迁移',
            onTap: () => context.push('/settings/backup'),
          ),
        ],
      ),
    );
  }
}

class _PortalCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String subtitle;
  final String badgeText;
  final VoidCallback onTap;

  const _PortalCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.badgeText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1.2,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconColor, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 13,
                        height: 1.25,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        badgeText,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
