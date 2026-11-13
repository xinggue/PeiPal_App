import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:intl/intl.dart';

import '../../../data/services/engine_c/engine_c_models.dart';
import '../../../data/services/hub/hub_service.dart';
import '../../../domain/models/catalog_mention.dart';
import '../../../domain/models/typing_action_block.dart';

enum HubItemSubtype { structure, content, diagnosis, typing, pipeline }

class HubCardItem {
  final HubListing listing;
  final HubItemSubtype subtype;
  final String subId;
  final String subName;
  final String structureName;
  final String formattedTitle;
  final String primaryDetail;
  final String secondaryDetail;

  const HubCardItem({
    required this.listing,
    required this.subtype,
    required this.subId,
    required this.subName,
    required this.structureName,
    required this.formattedTitle,
    required this.primaryDetail,
    required this.secondaryDetail,
  });

  String get typeLabel => switch (subtype) {
    HubItemSubtype.structure => '文书类型',
    HubItemSubtype.content => '内容模板',
    HubItemSubtype.diagnosis => '标准词条库',
    HubItemSubtype.typing => '输入方案',
    HubItemSubtype.pipeline => '解析流程',
  };
  String get displayName {
    if (subtype == HubItemSubtype.structure) return subName;
    return subName.endsWith(typeLabel) ? subName : '$subName $typeLabel';
  }

  Color get accent => switch (subtype) {
    HubItemSubtype.structure => const Color(0xff4167ad),
    HubItemSubtype.content => const Color(0xff267d77),
    HubItemSubtype.diagnosis => const Color(0xff9c7133),
    HubItemSubtype.typing => const Color(0xff6264a6),
    HubItemSubtype.pipeline => const Color(0xff8a5a87),
  };
}

class HubEntryHeading extends StatelessWidget {
  final HubCardItem item;
  final Widget? trailing;
  final bool large;
  const HubEntryHeading({
    super.key,
    required this.item,
    this.trailing,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (item.listing.institution.isNotEmpty)
          Text(
            '${item.listing.institution}的',
            style: theme.textTheme.bodySmall?.copyWith(
              color: item.accent,
              height: 1.5,
            ),
          ),
        if (item.subtype != HubItemSubtype.structure &&
            item.structureName.isNotEmpty)
          Text(
            '${item.structureName}的',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              height: 1.5,
            ),
          ),
        if (item.listing.institution.isNotEmpty ||
            item.subtype != HubItemSubtype.structure)
          const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(
                item.displayName,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontSize: large ? 21 : 17,
                  fontWeight: FontWeight.w500,
                  height: 1.4,
                ),
                maxLines: large ? null : 3,
                overflow: large ? null : TextOverflow.ellipsis,
              ),
            ),
            ?trailing,
          ],
        ),
      ],
    );
  }
}

class HubListingCard extends StatelessWidget {
  final HubCardItem item;
  final VoidCallback onTap;
  final Widget? trailing;
  const HubListingCard({
    super.key,
    required this.item,
    required this.onTap,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labels =
        item.listing.summary.structure?.slotLabels ?? const <String>[];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: item.accent.withValues(alpha: 0.24)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              HubEntryHeading(item: item, trailing: trailing),
              if (item.primaryDetail.isNotEmpty ||
                  (item.subtype == HubItemSubtype.structure &&
                      labels.isNotEmpty)) ...[
                const SizedBox(height: 12),
                if (item.subtype == HubItemSubtype.structure)
                  Text(
                    '含${item.listing.summary.structure?.slotCount ?? labels.length}个字段：${labels.join('、')}${(item.listing.summary.structure?.slotCount ?? 0) > labels.length ? '……' : ''}',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      height: 1.7,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: item.accent.withValues(alpha: 0.065),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(11),
                      child: Text(
                        item.primaryDetail,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 13,
                          height: 1.6,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
              ],
              if (item.secondaryDetail.trim().isNotEmpty) ...[
                const SizedBox(height: 14),
                Text(
                  '使用说明',
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  item.secondaryDetail.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.65,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (item.listing.isMine ||
                      item.listing.visibility == 'private')
                    Text(
                      item.listing.publicationLabel,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: item.accent,
                      ),
                    ),
                  Text(
                    DateFormat(
                      'yyyy-MM-dd',
                    ).format(item.listing.updatedAt.toLocal()),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class HubPreviewSection extends StatelessWidget {
  final String title;
  final Widget child;
  final Color? accent;
  const HubPreviewSection({
    super.key,
    required this.title,
    required this.child,
    this.accent,
  });

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: accent,
          ),
        ),
        const SizedBox(height: 9),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: (accent ?? Theme.of(context).colorScheme.primary).withValues(
              alpha: 0.045,
            ),
            border: Border.all(
              color: Theme.of(context).dividerColor.withValues(alpha: 0.13),
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: child,
        ),
      ],
    ),
  );
}

class HubContentPreview extends StatelessWidget {
  final EngineCBundleEnvelope envelope;
  final HubItemSubtype subtype;
  final String targetId;
  final int limit;
  const HubContentPreview({
    super.key,
    required this.envelope,
    required this.subtype,
    required this.targetId,
    this.limit = 24,
  });

  Widget _markdown(String text) => MarkdownBody(
    selectable: true,
    data: CatalogMentionHelper.toDisplayText(
      text,
      catalogNames: {for (final c in envelope.catalogs) c.id: c.name},
    ),
  );
  Widget _more(int total) => total > limit
      ? Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('另有 ${total - limit} 项，可查看完整内容。'),
        )
      : const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    if (subtype == HubItemSubtype.diagnosis) {
      return HubPreviewSection(
        title: '标准词条',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in envelope.diagnoses.take(limit))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SelectableText(
                      '${entry.code.isEmpty ? '' : '${entry.code}  '}${entry.name}',
                    ),
                    if (entry.note.isNotEmpty)
                      Text(
                        entry.note,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    if (entry.tags.isNotEmpty)
                      Text(
                        entry.tags.join(' · '),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
            _more(envelope.diagnoses.length),
          ],
        ),
      );
    }
    final unit = envelope.units.firstOrNull;
    if (unit == null) return const Text('暂无可预览内容');
    final structure = unit.structure;
    final labels = {for (final s in structure.slots) s.key: s.label};
    switch (subtype) {
      case HubItemSubtype.structure:
        return HubPreviewSection(
          title: '字段',
          accent: const Color(0xff4167ad),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SelectableText(
                structure.sortedSlots.take(limit).map((s) => s.label).join('、'),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(height: 1.7),
              ),
              _more(structure.slots.length),
            ],
          ),
        );
      case HubItemSubtype.content:
        final content = unit.contentTemplates
            .where((c) => c.id == targetId)
            .firstOrNull;
        if (content == null) return const Text('所选内容已更新，请刷新后重试');
        final slots = content.slots.entries
            .where((e) => !e.value.isEmpty)
            .toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (content.globalGuidance.trim().isNotEmpty)
              HubPreviewSection(
                title: '整体要求',
                accent: const Color(0xff267d77),
                child: _markdown(content.globalGuidance),
              ),
            if (content.fullExample.trim().isNotEmpty)
              HubPreviewSection(
                title: '整份示范',
                child: _markdown(content.fullExample),
              ),
            for (final slot in slots.take(limit))
              HubPreviewSection(
                title: labels[slot.key] ?? slot.key,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final example in slot.value.examples.where(
                      (e) => e.trim().isNotEmpty,
                    )) ...[_markdown(example), const SizedBox(height: 8)],
                    if (slot.value.guidance.trim().isNotEmpty)
                      _markdown(slot.value.guidance),
                    if (slot.value.catalogRefs.isNotEmpty)
                      Text(
                        slot.value.catalogRefs
                            .map(
                              (r) => r.displayChipText(
                                catalogNames: {
                                  for (final c in envelope.catalogs)
                                    c.id: c.name,
                                },
                              ),
                            )
                            .join('、'),
                      ),
                  ],
                ),
              ),
            _more(slots.length),
            if (content.globalGuidance.trim().isEmpty &&
                content.fullExample.trim().isEmpty &&
                slots.isEmpty)
              const Text('暂无撰写内容'),
          ],
        );
      case HubItemSubtype.typing:
        final profile = unit.typingProfiles
            .where((p) => p.id == targetId)
            .firstOrNull;
        if (profile == null) return const Text('所选方案已更新，请刷新后重试');
        final steps = <({String title, String detail, int depth})>[];
        void addSteps(List<TypingActionBlock> blocks, int depth) {
          for (final b in blocks) {
            if (steps.length >= limit) return;
            final title = switch (b) {
              FieldInputBlock() => '录入${labels[b.fieldKey] ?? b.fieldKey}',
              KeyComboBlock() => b.combo,
              LiteralTextBlock() => b.text,
              DelayBlock() => '等待 ${b.durationMs} ms',
              RhythmActionBlock() => '输入节奏：${b.presetName}',
              CurrentItemBlock() => '录入当前条目',
              ForEachBlock() => '逐项录入${labels[b.fieldKey] ?? b.fieldKey}',
              GroupBlock() => b.name,
              _ => '输入步骤',
            };
            final detail = b is FieldInputBlock
                ? [
                    if (b.preKeys.isNotEmpty) '输入前：${b.preKeys.join(' ')}',
                    if (b.postKeys.isNotEmpty) '输入后：${b.postKeys.join(' ')}',
                  ].join('\n')
                : '';
            steps.add((title: title, detail: detail, depth: depth));
            if (b is GroupBlock) addSteps(b.blocks, depth + 1);
            if (b is ForEachBlock) addSteps(b.subBlocks, depth + 1);
          }
        }
        addSteps(profile.effectiveBlocks(structure.slots), 0);
        return HubPreviewSection(
          title: '输入步骤',
          accent: const Color(0xff6264a6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '步骤间隔 ${profile.postKeySettleMs} ms',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              for (int i = 0; i < steps.length; i++)
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    steps[i].depth.clamp(0, 3) * 12,
                    0,
                    0,
                    12,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SelectableText('${i + 1}. ${steps[i].title}'),
                      if (steps[i].detail.isNotEmpty)
                        Text(
                          steps[i].detail,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      case HubItemSubtype.pipeline:
        return HubPreviewSection(
          title: '解析流程',
          accent: const Color(0xff8a5a87),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final n in structure.pipeline.nodes.take(limit))
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        n.label,
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      if (n.slotKeys.isNotEmpty)
                        Text(
                          n.slotKeys.map((k) => labels[k] ?? k).join('、'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      if (n.prompt.trim().isNotEmpty) _markdown(n.prompt),
                    ],
                  ),
                ),
              _more(structure.pipeline.nodes.length),
            ],
          ),
        );
      case HubItemSubtype.diagnosis:
        return const SizedBox.shrink();
    }
  }
}
