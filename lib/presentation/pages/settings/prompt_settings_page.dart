import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../providers/providers.dart';

class PromptSettingsPage extends ConsumerWidget {
  const PromptSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('提示词')),
      body: ListView(
        children: [
          ListTile(
            leading: const Icon(Icons.edit_note_outlined),
            title: const Text('文书生成'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/llm'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.auto_awesome_outlined),
            title: const Text('内容模板补充与迁移'),
            subtitle: const Text('范文拆分、补充细化与跨文书迁移提示词'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push('/settings/extractor'),
          ),
          const Divider(height: 1),
          SwitchListTile(
            secondary: const Icon(Icons.bug_report_outlined),
            title: const Text('提示词监视'),
            value: ref.watch(llmDryRunEnabledProvider),
            onChanged: (v) => ref.read(llmDryRunEnabledProvider.notifier).toggle(v),
          ),
        ],
      ),
    );
  }
}
