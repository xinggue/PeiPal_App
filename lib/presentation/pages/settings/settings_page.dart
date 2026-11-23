import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/asr_providers_provider.dart';
import '../../../providers/document_parser_provider.dart';
import '../../../providers/llm_providers_provider.dart';
import '../../../providers/ocr_providers_provider.dart';
import '../../../providers/providers.dart';
import '../../../providers/storefront_compliance_provider.dart';
import '../../../providers/tutorial_provider.dart';
import '../../widgets/tutorial/tutorial_spotlight_overlay.dart';

final _llmSettingsTileKey = GlobalKey();

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const _title = TextStyle(fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontScale = ref.watch(appFontScaleProvider);
    final isAiRestricted = ref.watch(isChinaAiRestrictedProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tutorial = ref.watch(tutorialProvider);
    final guideLlm = !isAiRestricted &&
        tutorial.isActive &&
        tutorial.activeTutorial == TutorialType.aiConfig &&
        tutorial.currentStep == 2;

    void openLlm() {
      if (guideLlm) {
        ref.read(tutorialProvider.notifier).completeTutorial();
      }
      context.push('/settings/llm-providers');
    }

    final scaffold = Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _groupLabel(context, '通用'),
          _groupCard(context, [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(
                children: [
                  const Icon(Icons.format_size_rounded, size: 20),
                  const SizedBox(width: 8),
                  const Text('字号', style: _title),
                  const Spacer(),
                  Text(
                    '${(fontScale * 100).round()}%',
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final preset in const [
                    ('紧凑', 0.90),
                    ('标准', 1.00),
                    ('舒适', 1.12),
                    ('大字', 1.25),
                    ('特大', 1.40),
                  ])
                    ChoiceChip(
                      label: Text(preset.$1, style: const TextStyle(fontSize: 12)),
                      selected: (fontScale - preset.$2).abs() < 0.03,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) {
                        ref.read(appFontScaleProvider.notifier).setScale(preset.$2);
                      },
                    ),
                ],
              ),
            ),
            Slider(
              value: fontScale.clamp(0.85, 1.45),
              min: 0.85,
              max: 1.45,
              divisions: 12,
              label: '${(fontScale * 100).round()}%',
              onChanged: (v) {
                ref.read(appFontScaleProvider.notifier).setScale(v, persist: false);
              },
              onChangeEnd: (v) {
                ref.read(appFontScaleProvider.notifier).setScale(v, persist: true);
              },
            ),
          ]),
          _groupLabel(context, isAiRestricted ? '识别与提示词' : '人工智能'),
          _groupCard(context, [
            if (!isAiRestricted) ...[
              ListTile(
                key: _llmSettingsTileKey,
                leading: const Icon(Icons.psychology_outlined),
                title: const Text('大语言模型', style: _title),
                subtitle: Consumer(
                  builder: (ctx, ref, _) {
                    final active = ref.watch(llmProvidersProvider).activeProvider;
                    if (active == null || !active.isConfigured) {
                      return const _InlineCodeRow(
                        badges: [_InlineCodeSpec('未配置 Key', muted: true)],
                      );
                    }
                    final model = active.selectedModel.trim();
                    return _InlineCodeRow(
                      badges: [
                        _InlineCodeSpec(active.name),
                        if (model.isNotEmpty)
                          _InlineCodeSpec(model, mono: true, highlighted: true)
                        else
                          const _InlineCodeSpec('未设定模型', muted: true),
                      ],
                    );
                  },
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: openLlm,
              ),
              const Divider(height: 1),
            ],
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('提示词', style: _title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/prompts'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.image_search),
              title: const Text('图像识别', style: _title),
              subtitle: Consumer(
                builder: (ctx, ref, _) {
                  final active = ref.watch(ocrProvidersProvider).activeProvider;
                  if (active == null || !active.isConfigured) {
                    return const _InlineCodeRow(
                      badges: [_InlineCodeSpec('未配置', muted: true)],
                    );
                  }
                  final model = active.selectedModel.trim();
                  return _InlineCodeRow(
                    badges: [
                      _InlineCodeSpec(
                        active.name,
                        highlighted: model.isEmpty || model == active.name,
                      ),
                      if (model.isNotEmpty && model != active.name)
                        _InlineCodeSpec(model, mono: true, highlighted: true),
                    ],
                  );
                },
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/ocr'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('文件解析', style: _title),
              subtitle: Consumer(
                builder: (ctx, ref, _) {
                  final active =
                      ref.watch(documentParserProvider).valueOrNull?.activeProvider;
                  if (active == null || !active.isConfigured) {
                    return const _InlineCodeRow(
                      badges: [_InlineCodeSpec('未配置', muted: true)],
                    );
                  }
                  return _InlineCodeRow(
                    badges: [_InlineCodeSpec(active.name, highlighted: true)],
                  );
                },
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/document-parser'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.mic),
              title: const Text('语音识别', style: _title),
              subtitle: Consumer(
                builder: (ctx, ref, _) {
                  final active = ref.watch(asrProvidersProvider).activeProvider;
                  if (active == null || !active.isConfigured) {
                    return const _InlineCodeRow(
                      badges: [_InlineCodeSpec('未配置', muted: true)],
                    );
                  }
                  final model = active.selectedModel.trim();
                  return _InlineCodeRow(
                    badges: [
                      _InlineCodeSpec(
                        active.name,
                        highlighted: active.isLocal || model.isEmpty,
                      ),
                      if (!active.isLocal &&
                          model.isNotEmpty &&
                          model != active.name)
                        _InlineCodeSpec(model, mono: true, highlighted: true),
                    ],
                  );
                },
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/asr'),
            ),
          ]),
          _groupLabel(context, '输入与输出'),
          _groupCard(context, [
            ListTile(
              leading: const Icon(Icons.bluetooth),
              title: const Text('蓝牙与键盘', style: _title),
              subtitle: Consumer(
                builder: (ctx, ref, _) {
                  final ble = ref.watch(bleServiceProvider);
                  if (!ble.isConnected) {
                    return const _InlineCodeRow(
                      badges: [_InlineCodeSpec('未连接', muted: true)],
                    );
                  }
                  final name = (ble.connectedName ?? '').trim();
                  return _InlineCodeRow(
                    badges: [
                      const _InlineCodeSpec('已连接', highlighted: true),
                      if (name.isNotEmpty) _InlineCodeSpec(name, mono: true),
                    ],
                  );
                },
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/ble'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.speed),
              title: const Text('键盘参数与输入速度', style: _title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/timing'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('二维码', style: _title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/qr'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.spellcheck),
              title: const Text('特殊字符替换', style: _title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/char-replacement'),
            ),
          ]),
          _groupLabel(context, '数据'),
          _groupCard(context, [
            ListTile(
              leading: const Icon(Icons.forum_outlined),
              title: const Text('会话数据备份与恢复', style: _title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/session-backup'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.tune_outlined),
              title: const Text('模板与配置导入导出', style: _title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/backup'),
            ),
          ]),
          _groupLabel(context, '关于'),
          _groupCard(context, [
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('关于与帮助', style: _title),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/about'),
            ),
          ]),
        ],
      ),
    );

    if (!guideLlm) return scaffold;

    return Stack(
      children: [
        scaffold,
        const _RevealLlmTile(),
        TutorialSpotlightOverlay(
          targetKey: _llmSettingsTileKey,
          stepTag: '配置指引 · 2/2',
          title: '大语言模型',
          description: '点这里进入。',
          nextButtonLabel: '进入',
          onNext: openLlm,
          onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
          onTargetTap: openLlm,
        ),
      ],
    );
  }

  Widget _groupLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 14, 4, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _groupCard(BuildContext context, List<Widget> children) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
      ),
      child: Column(children: children),
    );
  }
}

class _InlineCodeSpec {
  final String text;
  final bool mono;
  final bool highlighted;
  final bool muted;

  const _InlineCodeSpec(
    this.text, {
    this.mono = false,
    this.highlighted = false,
    this.muted = false,
  });
}

class _InlineCodeRow extends StatelessWidget {
  final List<_InlineCodeSpec> badges;

  const _InlineCodeRow({required this.badges});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        children: [
          for (final b in badges) _InlineCodePill(spec: b),
        ],
      ),
    );
  }
}

class _InlineCodePill extends StatelessWidget {
  final _InlineCodeSpec spec;

  const _InlineCodePill({required this.spec});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color bg;
    final Color border;
    final Color fg;

    if (spec.highlighted) {
      bg = scheme.primary.withValues(alpha: 0.10);
      border = scheme.primary.withValues(alpha: 0.25);
      fg = scheme.primary;
    } else if (spec.muted) {
      bg = scheme.surfaceContainerHighest.withValues(alpha: 0.45);
      border = scheme.outlineVariant.withValues(alpha: 0.45);
      fg = scheme.onSurfaceVariant.withValues(alpha: 0.8);
    } else {
      bg = scheme.surfaceContainerHighest.withValues(alpha: 0.65);
      border = scheme.outlineVariant.withValues(alpha: 0.6);
      fg = scheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Text(
        spec.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11.5,
          height: 1.25,
          fontFamily: spec.mono ? 'monospace' : null,
          fontWeight: spec.highlighted ? FontWeight.w600 : FontWeight.w500,
          color: fg,
        ),
      ),
    );
  }
}

class _RevealLlmTile extends StatefulWidget {
  const _RevealLlmTile();

  @override
  State<_RevealLlmTile> createState() => _RevealLlmTileState();
}

class _RevealLlmTileState extends State<_RevealLlmTile> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _llmSettingsTileKey.currentContext;
      if (ctx != null && ctx.mounted) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.25,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
