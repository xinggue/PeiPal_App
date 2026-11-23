import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/content_template.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import 'template_actions_sheet.dart';

class DocsHubPage extends ConsumerStatefulWidget {
  const DocsHubPage({super.key});

  @override
  ConsumerState<DocsHubPage> createState() => _DocsHubPageState();
}

class _DocsHubPageState extends ConsumerState<DocsHubPage> {
  final Set<String> _collapsedIds = <String>{};

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(templatesProvider);
    final templates = templatesAsync.valueOrNull ?? const <Template>[];
    final totalSlots = templates.fold<int>(0, (sum, t) => sum + t.slots.length);
    final favEntries = ref.watch(favoriteDiagnosesProvider).valueOrNull ?? [];
    final blockPresets = ref.watch(typingBlockPresetsProvider);

    int? totalContentTemplates;
    if (templates.isNotEmpty) {
      var loadedAll = true;
      var count = 0;
      for (final t in templates) {
        final cts = ref.watch(contentTemplatesProvider(t.id)).valueOrNull;
        if (cts == null) {
          loadedAll = false;
        } else {
          count += cts.length;
        }
      }
      if (loadedAll) {
        totalContentTemplates = count;
      }
    }

    final templateIds = templates.map((t) => t.id).toSet();
    final hasAnyCollapsed =
        templateIds.any((id) => _collapsedIds.contains(id));
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('文书与模板'),
        actions: [
          TextButton(
            onPressed: () => context.push('/templates/new'),
            child: const Text('新建文书'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          // 上半区：文书一览
          Row(
            children: [
              Text(
                '文书一览',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
              const Spacer(),
              if (templates.isNotEmpty)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    setState(() {
                      if (hasAnyCollapsed) {
                        _collapsedIds.clear();
                      } else {
                        _collapsedIds
                          ..clear()
                          ..addAll(templateIds);
                      }
                    });
                  },
                  icon: Icon(
                    hasAnyCollapsed ? Icons.unfold_more : Icons.unfold_less,
                    size: 16,
                  ),
                  label: Text(
                    hasAnyCollapsed ? '全部展开' : '全部折叠',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          if (templatesAsync.isLoading && templates.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (templates.isEmpty)
            _EmptyTemplatesCard(
              onCreate: () => context.push('/templates/new'),
              onExploreHub: () => context.push('/hub'),
            )
          else
            for (final template in templates) ...[
              _ExpandedTemplateCard(
                template: template,
                isExpanded: !_collapsedIds.contains(template.id),
                onToggleExpand: () {
                  setState(() {
                    if (_collapsedIds.contains(template.id)) {
                      _collapsedIds.remove(template.id);
                    } else {
                      _collapsedIds.add(template.id);
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
            ],

          const SizedBox(height: 8),

          // 下半区：文书管理
          Text(
            '文书管理',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 8),
          _PortalCard(
            icon: Icons.schema_outlined,
            iconBg: colorScheme.primaryContainer,
            iconColor: colorScheme.onPrimaryContainer,
            title: '文书类型',
            countText: templates.isEmpty
                ? null
                : '${templates.length} 个类型 · $totalSlots 个字段',
            onTap: () => context.push('/templates'),
          ),
          const SizedBox(height: 12),
          _PortalCard(
            icon: Icons.folder_special_rounded,
            iconBg: Colors.amber.shade100,
            iconColor: Colors.amber.shade900,
            title: '内容模板',
            countText: totalContentTemplates == null
                ? null
                : '$totalContentTemplates 份',
            onTap: () => context.push('/content-templates'),
          ),
          const SizedBox(height: 12),
          _PortalCard(
            icon: Icons.bookmark_outline_rounded,
            iconBg: Colors.teal.shade100,
            iconColor: Colors.teal.shade900,
            title: '标准词条库',
            countText: favEntries.isEmpty ? null : '${favEntries.length} 条收藏',
            onTap: () => context.push('/diagnoses'),
          ),
          const SizedBox(height: 12),
          _PortalCard(
            icon: Icons.cloud_outlined,
            iconBg: Colors.indigo.shade100,
            iconColor: Colors.indigo.shade900,
            title: '在线模板广场',
            onTap: () => context.push('/hub'),
          ),
          const SizedBox(height: 12),
          _PortalCard(
            icon: Icons.auto_fix_high_rounded,
            iconBg: Colors.deepOrange.shade100,
            iconColor: Colors.deepOrange.shade900,
            title: '快捷动作预设',
            countText: '${blockPresets.length} 套',
            onTap: () => context.push('/typing-presets'),
          ),
          const SizedBox(height: 12),
          _PortalCard(
            icon: Icons.import_export_rounded,
            iconBg: Colors.purple.shade100,
            iconColor: Colors.purple.shade900,
            title: '导入与导出中心',
            onTap: () => context.push('/settings/backup'),
          ),
        ],
      ),
    );
  }
}

class _EmptyTemplatesCard extends StatelessWidget {
  final VoidCallback onCreate;
  final VoidCallback onExploreHub;

  const _EmptyTemplatesCard({
    required this.onCreate,
    required this.onExploreHub,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        child: Column(
          children: [
            Text(
              '暂无文书类型',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: onCreate,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新建文书类型'),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: onExploreHub,
                  icon: const Icon(Icons.cloud_outlined, size: 18),
                  label: const Text('模板广场'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExpandedTemplateCard extends ConsumerWidget {
  final Template template;
  final bool isExpanded;
  final VoidCallback onToggleExpand;

  const _ExpandedTemplateCard({
    required this.template,
    required this.isExpanded,
    required this.onToggleExpand,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ctsAsync = ref.watch(contentTemplatesProvider(template.id));
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => context.push('/templates/${template.id}/edit'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
              child: Row(
                children: [
                  Icon(
                    Icons.schema_outlined,
                    size: 20,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          template.name,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 2),
                        InkWell(
                          onTap: onToggleExpand,
                          borderRadius: BorderRadius.circular(4),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${template.slots.length} 个字段',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Icon(
                                isExpanded
                                    ? Icons.keyboard_arrow_up
                                    : Icons.keyboard_arrow_down,
                                size: 15,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints.tightFor(width: 40, height: 40),
                      icon: const Icon(Icons.more_vert),
                      tooltip: '更多操作',
                      onPressed: () =>
                          showTemplateActionsSheet(context, ref, template),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            ctsAsync.when(
              data: (cts) {
                if (cts.isEmpty) {
                  return InkWell(
                    onTap: () =>
                        context.push('/templates/${template.id}/content/new'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.add,
                            size: 16,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '新建内容模板',
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return Column(
                  children: [
                    for (var i = 0; i < cts.length; i++) ...[
                      if (i > 0)
                        Divider(
                          height: 1,
                          indent: 38,
                          color:
                              colorScheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      _ContentTemplateSubRow(
                        template: template,
                        contentTemplate: cts[i],
                      ),
                    ],
                  ],
                );
              },
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: LinearProgressIndicator(minHeight: 2),
              ),
              error: (err, _) => Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Text(
                  '内容模板加载失败: $err',
                  style: TextStyle(fontSize: 12, color: colorScheme.error),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ContentTemplateSubRow extends StatelessWidget {
  final Template template;
  final ContentTemplate contentTemplate;

  const _ContentTemplateSubRow({
    required this.template,
    required this.contentTemplate,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: () => context.push(
        '/templates/${template.id}/content/${contentTemplate.id}/edit',
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        child: Row(
          children: [
            Icon(
              Icons.description_outlined,
              size: 16,
              color: colorScheme.primary.withValues(alpha: 0.85),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '内容模板：${contentTemplate.name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            SizedBox(
              width: 40,
              child: Center(
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PortalCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String? countText;
  final VoidCallback onTap;

  const _PortalCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    this.countText,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.55),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 15.5,
                  ),
                ),
              ),
              if (countText != null) ...[
                Text(
                  countText!,
                  style: TextStyle(
                    fontSize: 12.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 2),
              ],
              SizedBox(
                width: 40,
                child: Center(
                  child: Icon(
                    Icons.chevron_right_rounded,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                    size: 22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
