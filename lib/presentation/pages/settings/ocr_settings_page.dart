import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/ocr_provider.dart';
import '../../../providers/ocr_providers_provider.dart';
import '../../../providers/providers.dart';

class OcrSettingsPage extends ConsumerStatefulWidget {
  const OcrSettingsPage({super.key});

  @override
  ConsumerState<OcrSettingsPage> createState() => _OcrSettingsPageState();
}

class _OcrSettingsPageState extends ConsumerState<OcrSettingsPage> {
  String? _expandedProviderId;
  final Map<String, TextEditingController> _urlControllers = {};
  final Map<String, TextEditingController> _keyControllers = {};
  final Map<String, TextEditingController> _modelControllers = {};

  final Set<String> _loadingModels = {};
  bool _isTestingActive = false;
  bool _isCheckingActiveStatus = false;
  String? _activeStatusMessage;

  @override
  void dispose() {
    for (final c in _urlControllers.values) {
      c.dispose();
    }
    for (final c in _keyControllers.values) {
      c.dispose();
    }
    for (final c in _modelControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _getUrlCtrl(OcrProviderConfig p) {
    return _urlControllers.putIfAbsent(
        p.id, () => TextEditingController(text: p.baseUrl));
  }

  TextEditingController _getKeyCtrl(OcrProviderConfig p) {
    return _keyControllers.putIfAbsent(
        p.id, () => TextEditingController(text: p.apiKey));
  }

  TextEditingController _getModelCtrl(OcrProviderConfig p) {
    return _modelControllers.putIfAbsent(
        p.id, () => TextEditingController(text: p.selectedModel));
  }

  /// 一键操作：保存 Key 并向云端获取模型列表供用户选择
  Future<void> _onSaveKeyAndFetchModels(OcrProviderConfig p) async {
    final notifier = ref.read(ocrProvidersProvider.notifier);
    final key = _getKeyCtrl(p).text.trim();
    final url = _getUrlCtrl(p).text.trim();

    if (p.requiresApiKey && key.isEmpty) {
      showAppToast(context, '请先输入该服务商的 API Key');
      return;
    }

    // 先保存输入的 URL 和 Key
    await notifier.updateProvider(p.copyWith(baseUrl: url, apiKey: key));

    setState(() => _loadingModels.add(p.id));
    try {
      final models = await notifier.fetchModelsForProvider(p.id);
      if (mounted) {
        final updatedState = ref.read(ocrProvidersProvider);
        final updatedProvider = updatedState.providers
            .where((item) => item.id == p.id)
            .firstOrNull;
        if (updatedProvider != null) {
          _getModelCtrl(updatedProvider).text = updatedProvider.selectedModel;
        }
        showAppToast(context, 'Key 已保存，成功获取到 ${models.length} 个模型');
        _showModelPickerSheet(p.id);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '拉取模型失败: $e');
      }
    } finally {
      if (mounted) setState(() => _loadingModels.remove(p.id));
    }
  }

  Future<void> _onSaveProvider(OcrProviderConfig p,
      {bool setAsActive = false}) async {
    final notifier = ref.read(ocrProvidersProvider.notifier);
    final url = p.isLocal ? p.baseUrl : _getUrlCtrl(p).text.trim();
    final key = p.requiresApiKey ? _getKeyCtrl(p).text.trim() : '';
    final model = p.isLocal || p.isNoAuthCloud
        ? p.selectedModel
        : _getModelCtrl(p).text.trim();

    final updated = p.copyWith(
      baseUrl: url,
      apiKey: key,
      selectedModel: model,
    );

    await notifier.updateProvider(updated);
    if (setAsActive) {
      await notifier.setActiveProvider(p.id, model: model);
    }

    if (mounted) {
      showAppToast(
          context,
          setAsActive
              ? '已保存，并已选用 ${p.name} ($model)'
              : '${p.name} 配置已保存');
    }
  }

  Future<void> _testActiveConnection() async {
    setState(() {
      _isTestingActive = true;
      _activeStatusMessage = null;
    });

    try {
      final ok = await ref.read(ocrConfigProvider.notifier).testConnection();
      if (mounted) {
        setState(() {
          _activeStatusMessage = ok ? '连通正常' : '连接失败，请检查配置';
        });
        showAppToast(context, _activeStatusMessage!);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _activeStatusMessage = '测试失败: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isTestingActive = false);
    }
  }

  Future<void> _checkActiveStatus() async {
    final state = ref.read(ocrProvidersProvider);
    final active = state.activeProvider;
    if (active == null || !active.isConfigured) {
      showAppToast(context, '当前选用的服务商尚未配置 Key');
      return;
    }

    setState(() {
      _isCheckingActiveStatus = true;
      _activeStatusMessage = null;
    });

    try {
      final res = await ref
          .read(ocrProvidersProvider.notifier)
          .fetchStatusOrPingForProvider(active.id);
      if (mounted) {
        setState(() {
          _activeStatusMessage = res;
        });
        showAppToast(context, '${active.name}: $res');
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _activeStatusMessage = '查询失败: $e';
        });
      }
    } finally {
      if (mounted) setState(() => _isCheckingActiveStatus = false);
    }
  }

  void _showModelPickerSheet(String providerId) {
    final state = ref.read(ocrProvidersProvider);
    final p = state.providers.firstWhere((item) => item.id == providerId);
    final allModels = p.allModels;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) {
        return Container(
          height: MediaQuery.of(ctx).size.height * 0.65,
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.image_search_rounded, color: Colors.teal),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '选择 ${p.name} 的模型 (${allModels.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(height: 16),
              Expanded(
                child: allModels.isEmpty
                    ? const Center(child: Text('暂无可用模型，请先拉取模型列表或手动输入'))
                    : ListView.builder(
                        itemCount: allModels.length,
                        itemBuilder: (ctx, i) {
                          final m = allModels[i];
                          final isCurrent = m == p.selectedModel;

                          return ListTile(
                            dense: true,
                            title: Text(
                              m,
                              style: TextStyle(
                                fontWeight: isCurrent
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: isCurrent ? Colors.teal : null,
                              ),
                            ),
                            trailing: isCurrent
                                ? const Icon(Icons.check, color: Colors.teal)
                                : null,
                            onTap: () {
                              _getModelCtrl(p).text = m;
                              ref
                                  .read(ocrProvidersProvider.notifier)
                                  .setActiveModel(p.id, m);
                              Navigator.pop(ctx);
                              setState(() {});
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddCustomProviderDialog() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController(text: 'https://api.openai.com/v1');
    final keyCtrl = TextEditingController();
    final modelCtrl = TextEditingController();
    OcrProtocol selectedProtocol = OcrProtocol.openaiVision;

    try {
      await showDialog(
        context: context,
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('添加自定义 OCR 服务商'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                      labelText: '服务商名称',
                      hintText: '例如: 我的视觉中转站 / 私有化部署',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<OcrProtocol>(
                    initialValue: selectedProtocol,
                    decoration: const InputDecoration(
                      labelText: '接口协议',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: OcrProtocol.openaiVision,
                        child: Text('OpenAI Vision 兼容 (/chat/completions)'),
                      ),
                      DropdownMenuItem(
                        value: OcrProtocol.modelbestParse,
                        child: Text('面壁文档解析 (/v1/document-parse)'),
                      ),
                      DropdownMenuItem(
                        value: OcrProtocol.zhipuLayout,
                        child: Text('智谱文档解析 (/paas/v4/layout_parsing)'),
                      ),
                      DropdownMenuItem(
                        value: OcrProtocol.paddleOcr,
                        child: Text('百度飞桨异步任务 (/api/v2/ocr/jobs)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val == null) return;
                      setDialogState(() {
                        selectedProtocol = val;
                        if (val == OcrProtocol.modelbestParse) {
                          urlCtrl.text = 'https://api.modelbest.cn/v1';
                          modelCtrl.text = 'MiniCPM-OCR-1.0';
                        } else if (val == OcrProtocol.zhipuLayout) {
                          urlCtrl.text = 'https://open.bigmodel.cn/api/paas/v4';
                          modelCtrl.text = 'glm-ocr';
                        } else if (val == OcrProtocol.paddleOcr) {
                          urlCtrl.text =
                              'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs';
                          modelCtrl.text = 'PaddleOCR-VL-1.6';
                        } else {
                          urlCtrl.text = 'https://api.openai.com/v1';
                          modelCtrl.text = 'gpt-4o';
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: urlCtrl,
                    decoration: const InputDecoration(
                      labelText: '接口地址 (Base URL)',
                      hintText: 'https://...',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: keyCtrl,
                    decoration: const InputDecoration(
                      labelText: 'API Key / Token',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: modelCtrl,
                    decoration: const InputDecoration(
                      labelText: '模型名称',
                      hintText: '如 gpt-4o, qwen-vl-ocr, glm-ocr',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () async {
                  final name = nameCtrl.text.trim();
                  final url = urlCtrl.text.trim();
                  if (name.isEmpty || url.isEmpty) {
                    showAppToast(context, '服务商名称和接口地址不能为空');
                    return;
                  }
                  final newId =
                      'custom_ocr_${DateTime.now().millisecondsSinceEpoch}';
                  final newProvider = OcrProviderConfig(
                    id: newId,
                    name: name,
                    description: '用户自定义 OCR 端点',
                    protocol: selectedProtocol,
                    defaultBaseUrl: url,
                    baseUrl: url,
                    apiKey: keyCtrl.text.trim(),
                    selectedModel: modelCtrl.text.trim(),
                  );
                  final nav = Navigator.of(ctx);
                  await ref
                      .read(ocrProvidersProvider.notifier)
                      .updateProvider(newProvider);
                  if (mounted) {
                    nav.pop();
                    setState(() => _expandedProviderId = newId);
                  }
                },
                child: const Text('添加'),
              ),
            ],
          ),
        ),
      );
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        nameCtrl.dispose();
        urlCtrl.dispose();
        keyCtrl.dispose();
        modelCtrl.dispose();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ocrProvidersProvider);
    final concurrency = ref.watch(ocrConcurrencyProvider);
    final theme = Theme.of(context);
    final active = state.activeProvider;

    return Scaffold(
      appBar: AppBar(
        title: const Text('图像识别'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_rounded),
            tooltip: '添加自定义服务商',
            onPressed: _showAddCustomProviderDialog,
          ),
        ],
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // 1. 顶部当前选用识别引擎状态卡片
                _buildActiveStatusBanner(theme, active),
                const SizedBox(height: 14),

                // 2. 多图并发设置卡片
                _buildConcurrencyCard(theme, concurrency),
                const SizedBox(height: 18),

                Row(
                  children: [
                    const Icon(Icons.dns_outlined,
                        size: 18, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    const Text(
                      '服务商列表',
                      style:
                          TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Spacer(),
                    Text(
                      '已收录 ${state.providers.length} 个服务商',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 3. 服务商列表
                ...state.providers.map((p) =>
                    _buildProviderCard(theme, p, state.activeProviderId)),
              ],
            ),
    );
  }

  /// 顶部当前选用识别引擎 Banner
  Widget _buildActiveStatusBanner(ThemeData theme, OcrProviderConfig? active) {
    final isConfigured = active?.isConfigured ?? false;
    final statusMsg = _activeStatusMessage ?? active?.statusInfo;

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
                backgroundColor:
                    isConfigured ? Colors.teal : Colors.amber.shade700,
                radius: 14,
                child: const Icon(Icons.document_scanner_rounded,
                    size: 16, color: Colors.white),
              ),
              const SizedBox(width: 8),
              const Text(
                '当前选用识别服务',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isConfigured ? Colors.teal : Colors.amber.shade800,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isConfigured
                      ? (active?.isLocal == true
                          ? '本机离线'
                          : active?.isNoAuthCloud == true
                              ? '免密就绪'
                              : '已就绪')
                      : '未配置 Key',
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
                      fontSize: 15, fontWeight: FontWeight.bold),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  active?.selectedModel.isNotEmpty == true
                      ? active!.selectedModel
                      : '未选择模型',
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600),
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
          Row(
            children: [
              OutlinedButton.icon(
                icon: _isTestingActive
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.network_check, size: 16),
                label: const Text('测试当前连接', style: TextStyle(fontSize: 12)),
                onPressed: _isTestingActive ? null : _testActiveConnection,
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                icon: _isCheckingActiveStatus
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.speed_outlined, size: 16),
                label: const Text('查询状态/测速', style: TextStyle(fontSize: 12)),
                onPressed: _isCheckingActiveStatus ? null : _checkActiveStatus,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 多图并发控制卡片
  Widget _buildConcurrencyCard(ThemeData theme, int concurrency) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.layers_outlined,
                  size: 16, color: Colors.blueGrey),
              const SizedBox(width: 6),
              const Text(
                '多图并发请求上限',
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const Spacer(),
              Text(
                '$concurrency 路并发',
                style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                ),
              ),
            ],
          ),
          Slider(
            value: concurrency.toDouble(),
            min: 1,
            max: 6,
            divisions: 5,
            label: '$concurrency',
            onChanged: (val) {
              ref
                  .read(ocrConcurrencyProvider.notifier)
                  .setConcurrency(val.round());
            },
          ),
        ],
      ),
    );
  }

  /// 单个服务商卡片
  Widget _buildProviderCard(
      ThemeData theme, OcrProviderConfig p, String activeId) {
    final isActive = p.id == activeId;
    final isExpanded = _expandedProviderId == p.id;
    final isConfigured = p.isConfigured;
    final isLoadingModel = _loadingModels.contains(p.id);

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
          // 卡片头部（点击展开/折叠）
          ListTile(
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            leading: CircleAvatar(
              backgroundColor: isActive
                  ? Colors.teal
                  : theme.colorScheme.surfaceContainerHighest,
              foregroundColor:
                  isActive ? Colors.white : theme.colorScheme.primary,
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.teal,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '已选用',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.bold),
                    ),
                  )
                else if (p.isLocal)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '离线内置',
                      style: TextStyle(fontSize: 10, color: Colors.blueGrey),
                    ),
                  )
                else if (p.isNoAuthCloud)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '免密可用',
                      style: TextStyle(fontSize: 10, color: Colors.teal),
                    ),
                  )
                else if (isConfigured)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              '当前模型: ${p.selectedModel.isNotEmpty ? p.selectedModel : "未指定 (请获取或输入)"}',
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

          // 展开配置面板
          if (isExpanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (p.description.isNotEmpty) ...[
                    Text(
                      p.description,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (p.isLocal || p.isNoAuthCloud) ...[
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: isActive ? Colors.teal : null,
                      ),
                      icon: const Icon(Icons.check_circle_outline, size: 16),
                      label: Text(isActive ? '当前已选用该服务' : '确认选用该服务'),
                      onPressed: () => _onSaveProvider(p, setAsActive: true),
                    ),
                  ] else ...[
                    // 1. 接口地址 Base URL
                    TextField(
                      controller: _getUrlCtrl(p),
                      decoration: InputDecoration(
                        labelText: '接口地址 (Base URL)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.restore, size: 18),
                          tooltip: '恢复默认地址',
                          onPressed: () {
                            _getUrlCtrl(p).text = p.defaultBaseUrl;
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),

                    // 2. API Key 输入框
                    TextField(
                      controller: _getKeyCtrl(p),
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: 'Token / API Key',
                        hintText: '输入该服务商专属密钥',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.paste, size: 18),
                          tooltip: '粘贴剪贴板',
                          onPressed: () async {
                            final clip = await Clipboard.getData('text/plain');
                            if (clip?.text != null) {
                              _getKeyCtrl(p).text = clip!.text!.trim();
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // 3. 【直达按钮】保存 Key 并获取模型列表
                    if (p.supportsModelFetch) ...[
                      FilledButton.tonalIcon(
                        icon: isLoadingModel
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.cloud_download_outlined,
                                size: 18),
                        label: Text(isLoadingModel
                            ? '正在拉取模型列表...'
                            : '保存 Key 并获取模型列表'),
                        onPressed: isLoadingModel
                            ? null
                            : () => _onSaveKeyAndFetchModels(p),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // 4. 选用模型名称行（输入框 + 从列表选择按钮）
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _getModelCtrl(p),
                            decoration: const InputDecoration(
                              labelText: '选用模型名称',
                              hintText: '点击右侧选择或手动输入',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.list_alt, size: 16),
                          label: const Text('选择模型',
                              style: TextStyle(fontSize: 12)),
                          onPressed: () => _showModelPickerSheet(p.id),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),

                    // 5. 底部操作按钮：仅保存 / 确认选用该模型
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed: () =>
                              _onSaveProvider(p, setAsActive: false),
                          child: const Text('仅保存'),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: isActive ? Colors.teal : null,
                            ),
                            icon: const Icon(Icons.check_circle_outline,
                                size: 16),
                            label:
                                Text(isActive ? '已选用 (点击更新)' : '确认选用该模型'),
                            onPressed: () =>
                                _onSaveProvider(p, setAsActive: true),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
