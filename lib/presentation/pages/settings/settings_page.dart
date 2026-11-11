import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/ble/character_sanitizer.dart';
import '../../../data/services/qr/qr_pack_service.dart';
import '../../../providers/asr_providers_provider.dart';
import '../../../providers/llm_providers_provider.dart';
import '../../../providers/ocr_providers_provider.dart';
import '../../../providers/providers.dart';

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  static const _title = TextStyle(fontWeight: FontWeight.w600);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontScale = ref.watch(appFontScaleProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
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
          _groupLabel(context, '人工智能'),
          _groupCard(context, [
            ListTile(
              leading: const Icon(Icons.psychology_outlined),
              title: const Text('大语言模型', style: _title),
              subtitle: Consumer(
                builder: (ctx, ref, _) {
                  final model = ref.watch(llmProvidersProvider).activeProvider?.selectedModel ?? '';
                  return Text(model.isEmpty ? '未设定模型' : model);
                },
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/llm-providers'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.notes_outlined),
              title: const Text('提示词', style: _title),
              subtitle: const Text('系统提示词与阶段生成编排'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/prompts'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.image_search),
              title: const Text('图像识别', style: _title),
              subtitle: Consumer(
                builder: (ctx, ref, _) {
                  final active =
                      ref.watch(ocrProvidersProvider).activeProvider;
                  if (active == null || !active.isConfigured) {
                    return const Text('未配置');
                  }
                  return Text('${active.name} (${active.selectedModel})');
                },
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/ocr'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.mic),
              title: const Text('语音识别', style: _title),
              subtitle: Consumer(
                builder: (ctx, ref, _) {
                  final active =
                      ref.watch(asrProvidersProvider).activeProvider;
                  if (active == null || !active.isConfigured) {
                    return const Text('未配置');
                  }
                  return Text('${active.name} (${active.selectedModel})');
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
                  return Text(
                    ble.isConnected ? '已连接: ${ble.connectedName ?? "键盘"}' : '未连接',
                    style: TextStyle(
                      color: ble.isConnected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
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
              subtitle: const Text('打字节奏、按键延迟与时序预设'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/timing'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.qr_code_2),
              title: const Text('二维码', style: _title),
              subtitle: Consumer(
                builder: (ctx, ref, _) {
                  final qr = ref.watch(qrConfigProvider);
                  return Text('单包限额 ${qr.chunkSize} 字符');
                },
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/qr'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.spellcheck),
              title: const Text('字符替换', style: _title),
              subtitle: Consumer(
                builder: (ctx, ref, _) {
                  final rules = ref.watch(charReplacementRulesProvider);
                  return Text(rules.isEmpty ? '默认转义规则' : '${rules.length} 条替换规则');
                },
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/char-replacement'),
            ),
          ]),
          _groupLabel(context, '数据'),
          _groupCard(context, [
            ListTile(
              leading: const Icon(Icons.import_export),
              title: const Text('导入与导出', style: _title),
              subtitle: const Text('数据备份、模板导入与导出'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/backup'),
            ),
          ]),
          _groupLabel(context, '关于'),
          _groupCard(context, [
            ListTile(
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('关于与帮助', style: _title),
              subtitle: const Text('版本检测、新手教程与开源社区'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/about'),
            ),
          ]),
        ],
      ),
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
