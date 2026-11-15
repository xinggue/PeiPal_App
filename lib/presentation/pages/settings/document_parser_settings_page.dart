import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../domain/models/document_parser_provider.dart';
import '../../../providers/document_parser_provider.dart';
import '../../widgets/common/app_toast.dart';

class DocumentParserSettingsPage extends ConsumerStatefulWidget {
  const DocumentParserSettingsPage({super.key});
  @override
  ConsumerState<DocumentParserSettingsPage> createState() =>
      _DocumentParserSettingsPageState();
}

class _DocumentParserSettingsPageState
    extends ConsumerState<DocumentParserSettingsPage> {
  String? _expandedProviderId;
  final _urls = <String, TextEditingController>{};
  final _keys = <String, TextEditingController>{};
  final _tools = <String, String>{};
  final _saving = <String>{};
  bool _isTestingActive = false;
  String? _activeStatusMessage;

  @override
  void dispose() {
    for (final c in [..._urls.values, ..._keys.values]) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _urlCtrl(DocumentParserProviderConfig p) =>
      _urls.putIfAbsent(p.id, () => TextEditingController(text: p.baseUrl));

  TextEditingController _keyCtrl(DocumentParserProviderConfig p) =>
      _keys.putIfAbsent(p.id, () => TextEditingController(text: p.apiKey));

  Future<void> _save(
    DocumentParserProviderConfig p, {
    required bool select,
  }) async {
    final url = _urlCtrl(p).text.trim();
    final uri = Uri.tryParse(url);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      showAppToast(context, '请输入有效的接口地址');
      return;
    }
    final key = _keyCtrl(p).text.trim();
    if (select && key.isEmpty) {
      showAppToast(context, '请先填写 API Key');
      return;
    }
    setState(() => _saving.add(p.id));
    try {
      await ref.read(documentParserProvider.notifier).saveProvider(
        p.copyWith(
          baseUrl: url,
          apiKey: key,
          toolType: _tools[p.id] ?? p.toolType,
          isEnabled: select ? true : p.isEnabled,
        ),
        select: select,
      );
      if (mounted) {
        setState(() => _activeStatusMessage = null);
        showAppToast(context, select ? '已选用 ${p.name}' : '${p.name} 配置已保存');
      }
    } catch (_) {
      if (mounted) showAppToast(context, '保存失败，请重试');
    } finally {
      if (mounted) setState(() => _saving.remove(p.id));
    }
  }

  Future<void> _testActiveConnection(
    DocumentParserProviderConfig? active,
  ) async {
    if (active == null || !active.isConfigured) {
      showAppToast(context, '当前选用的服务商尚未配置 API Key');
      return;
    }
    setState(() {
      _isTestingActive = true;
      _activeStatusMessage = null;
    });
    try {
      final result = await ref
          .read(documentParserApiProvider)
          .testConnection(active);
      if (mounted) {
        setState(() => _activeStatusMessage = result);
        showAppToast(context, '${active.name}: $result');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _activeStatusMessage = '测试失败: $e');
      }
    } finally {
      if (mounted) setState(() => _isTestingActive = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('文件解析')),
      body: ref
          .watch(documentParserProvider)
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (_, _) => const Center(child: Text('配置读取失败，请重新打开')),
            data: (settings) {
              final active = settings.activeProvider;
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildActiveStatusBanner(theme, active),
                  const SizedBox(height: 18),
                  Row(
                    children: [
                      const Icon(
                        Icons.dns_outlined,
                        size: 18,
                        color: Colors.blueGrey,
                      ),
                      const SizedBox(width: 6),
                      const Text(
                        '服务商列表',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '已收录 ${settings.providers.length} 个服务商',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  for (final p in settings.providers)
                    _buildProviderCard(theme, p, settings.activeProviderId),
                ],
              );
            },
          ),
    );
  }

  Widget _buildActiveStatusBanner(
    ThemeData theme,
    DocumentParserProviderConfig? active,
  ) {
    final isConfigured = active?.isConfigured ?? false;
    final statusMsg = _activeStatusMessage;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isConfigured
            ? Colors.teal.withValues(alpha: 0.08)
            : Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isConfigured
              ? Colors.teal.withValues(alpha: 0.3)
              : Colors.amber.withValues(alpha: 0.4),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: isConfigured
                    ? Colors.teal
                    : Colors.amber.shade700,
                radius: 14,
                child: const Icon(
                  Icons.description_rounded,
                  size: 16,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '当前选用解析服务',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isConfigured ? Colors.teal : Colors.amber.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isConfigured ? '已就绪' : '未配置',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Flexible(
                child: Text(
                  active?.name ?? '未选择',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  active?.modeLabel ?? '未选用',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (statusMsg != null && statusMsg.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '状态: $statusMsg',
                style: TextStyle(fontSize: 12, color: Colors.teal.shade900),
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton.icon(
            icon: _isTestingActive
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check, size: 16),
            label: const Text('测试当前连接', style: TextStyle(fontSize: 12)),
            onPressed: _isTestingActive
                ? null
                : () => _testActiveConnection(active),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCard(
    ThemeData theme,
    DocumentParserProviderConfig p,
    String activeId,
  ) {
    final isActive = p.id == activeId;
    final isExpanded = _expandedProviderId == p.id;
    final isConfigured = p.isConfigured;
    final isSaving = _saving.contains(p.id);

    final url = _urlCtrl(p);
    final key = _keyCtrl(p);
    final tool = _tools.putIfAbsent(p.id, () => p.toolType);
    final draft = p.copyWith(toolType: tool);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActive ? Colors.teal : Colors.grey.withValues(alpha: 0.25),
          width: isActive ? 1.8 : 1,
        ),
      ),
      child: Column(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 2,
            ),
            leading: CircleAvatar(
              backgroundColor: isActive
                  ? Colors.teal
                  : theme.colorScheme.surfaceContainerHighest,
              foregroundColor: isActive
                  ? Colors.white
                  : theme.colorScheme.primary,
              child: Text(
                p.name.characters.first,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    style: TextStyle(
                      fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                      fontSize: 14.5,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isActive)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.teal,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '已选用',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else if (isConfigured)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '已配置',
                      style: TextStyle(fontSize: 10, color: Colors.blueGrey),
                    ),
                  ),
              ],
            ),
            subtitle: Text(
              '模式: ${draft.modeLabel} · 支持 ${draft.supportedExtensions.map((e) => e.toUpperCase()).join('/')}',
              style: const TextStyle(fontSize: 12),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: Icon(
              isExpanded ? Icons.expand_less : Icons.expand_more,
              color: Colors.grey,
            ),
            onTap: () {
              setState(() {
                _expandedProviderId = isExpanded ? null : p.id;
              });
            },
          ),
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    key: PageStorageKey('document-url-${p.id}'),
                    controller: url,
                    decoration: InputDecoration(
                      labelText: '接口地址 (Base URL)',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.restore, size: 18),
                        tooltip: '恢复默认地址',
                        onPressed: () {
                          url.text = p.defaultBaseUrl;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: PageStorageKey('document-key-${p.id}'),
                    controller: key,
                    obscureText: true,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'API Key',
                      hintText: '输入该服务商专属密钥',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.paste, size: 18),
                        tooltip: '粘贴剪贴板',
                        onPressed: () async {
                          final clip = await Clipboard.getData('text/plain');
                          if (clip?.text != null) {
                            key.text = clip!.text!.trim();
                          }
                        },
                      ),
                    ),
                  ),
                  if (p.kind == DocumentParserKind.zhipu) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: tool,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '解析服务',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'prime-sync',
                          child: Text('Prime-sync · 按页计费'),
                        ),
                        DropdownMenuItem(
                          value: 'prime',
                          child: Text('Prime · 按页计费'),
                        ),
                        DropdownMenuItem(
                          value: 'expert',
                          child: Text('Expert · 仅 PDF · 按页计费'),
                        ),
                        DropdownMenuItem(
                          value: 'lite',
                          child: Text('Lite · 基础文本提取'),
                        ),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _tools[p.id] = v);
                      },
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '支持格式: ${draft.supportedExtensions.map((e) => e.toUpperCase()).join(' / ')}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        icon: const Icon(Icons.open_in_new, size: 14),
                        label: const Text(
                          '服务文档与价格',
                          style: TextStyle(fontSize: 12),
                        ),
                        onPressed: () => launchUrl(
                          Uri.parse(
                            p.kind == DocumentParserKind.deepseek
                                ? 'https://api-docs.deepseek.com/zh-cn/guides/ocr'
                                : 'https://docs.bigmodel.cn/cn/guide/tools/file-parser-sync',
                          ),
                          mode: LaunchMode.externalApplication,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: isSaving
                            ? null
                            : () => _save(p, select: false),
                        child: const Text('仅保存'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: isActive ? Colors.teal : null,
                          ),
                          icon: const Icon(
                            Icons.check_circle_outline,
                            size: 16,
                          ),
                          label: Text(
                            isActive ? '已选用 (点击更新)' : '确认选用该服务',
                          ),
                          onPressed: isSaving
                              ? null
                              : () => _save(p, select: true),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
