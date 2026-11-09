import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:peipal/presentation/widgets/common/app_toast.dart';

import '../../../data/services/api/extractor_config.dart';
import '../../../providers/providers.dart';

class ExtractorSettingsPage extends ConsumerStatefulWidget {
  const ExtractorSettingsPage({super.key});

  @override
  ConsumerState<ExtractorSettingsPage> createState() =>
      _ExtractorSettingsPageState();
}

class _ExtractorSettingsPageState extends ConsumerState<ExtractorSettingsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;
  late final TextEditingController _refineCtrl;
  late final TextEditingController _migrateCtrl;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _refineCtrl = TextEditingController();
    _migrateCtrl = TextEditingController();
    _load();
  }

  Future<void> _load() async {
    await ref.read(extractorConfigProvider.notifier).ready;
    if (!mounted) return;
    final cfg = ref.read(extractorConfigProvider);
    _refineCtrl.text = cfg.refinePromptTemplate;
    _migrateCtrl.text = cfg.migratePromptTemplate;
    setState(() => _isLoading = false);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _refineCtrl.dispose();
    _migrateCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cfg = ExtractorConfig(
      refinePromptTemplate: _refineCtrl.text,
      migratePromptTemplate: _migrateCtrl.text,
    );
    await ref.read(extractorConfigProvider.notifier).save(cfg);
    if (mounted) {
      showAppToast(context, '已保存提示词设置');
    }
  }

  Future<void> _reset() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('恢复默认提示词'),
        content: const Text('确定将「补充与细化」及「跨文书迁移」提示词恢复为默认模板吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('恢复默认'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    await ref.read(extractorConfigProvider.notifier).reset();
    await _load();
    if (mounted) {
      showAppToast(context, '已恢复默认设置');
    }
  }

  void _insertPlaceholder(TextEditingController ctrl, String token) {
    final text = ctrl.text;
    final selection = ctrl.selection;
    final newText = selection.isValid
        ? text.replaceRange(selection.start, selection.end, token)
        : '$text$token';
    ctrl.text = newText;
    ctrl.selection = TextSelection.collapsed(
      offset:
          (selection.isValid ? selection.start : text.length) + token.length,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('内容模板补充与迁移')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('内容模板补充与迁移'),
        actions: [
          TextButton(
            onPressed: _reset,
            child: const Text('恢复默认'),
          ),
          FilledButton(
            onPressed: _save,
            child: const Text('保存'),
          ),
          const SizedBox(width: 8),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(text: '补充与细化（含范文拆分）'),
            Tab(text: '跨文书迁移'),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              children: [
                _buildPromptTab(
                  controller: _refineCtrl,
                  description:
                      '用于从零拆分示范文书，或在已有内容模板基础上结合新范文/指令做增量细化。',
                  placeholders: const [
                    ('{target_doc_name}', '目标文书名称'),
                    ('{field_list}', '目标字段列表'),
                    ('{output_scope_rule}', '示范文本/撰写要求生成范围说明'),
                  ],
                ),
                _buildPromptTab(
                  controller: _migrateCtrl,
                  description:
                      '用于将一份已有内容模板经语义重组与文体改写后，迁移适配到另一文书结构。',
                  placeholders: const [
                    ('{source_doc_name}', '源文书名称'),
                    ('{target_doc_name}', '目标文书名称'),
                    ('{field_list}', '目标字段列表'),
                    ('{output_scope_rule}', '示范文本/撰写要求生成范围说明'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromptTab({
    required TextEditingController controller,
    required String description,
    required List<(String, String)> placeholders,
  }) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          description,
          style: const TextStyle(fontSize: 12.5, color: Colors.blueGrey),
        ),
        const SizedBox(height: 10),
        const Text(
          '点击插入可用占位符：',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            for (final p in placeholders)
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.add, size: 14),
                label: Text('${p.$1} ${p.$2}',
                    style: const TextStyle(fontSize: 12)),
                onPressed: () => _insertPlaceholder(controller, p.$1),
              ),
          ],
        ),
        const SizedBox(height: 10),
        TextField(
          controller: controller,
          maxLines: 20,
          minLines: 12,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          style: const TextStyle(fontSize: 13, height: 1.4),
        ),
      ],
    );
  }
}
