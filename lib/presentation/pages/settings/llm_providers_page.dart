import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/models/llm_provider.dart';
import '../../../providers/llm_providers_provider.dart';
import '../../../providers/providers.dart';
import '../../../providers/tutorial_provider.dart';
import '../../widgets/tutorial/tutorial_spotlight_overlay.dart';

class LlmProvidersPage extends ConsumerStatefulWidget {
  const LlmProvidersPage({super.key});

  @override
  ConsumerState<LlmProvidersPage> createState() => _LlmProvidersPageState();
}

class _LlmProvidersPageState extends ConsumerState<LlmProvidersPage> {
  String? _expandedProviderId;
  final Map<String, TextEditingController> _urlControllers = {};
  final Map<String, TextEditingController> _keyControllers = {};
  final Map<String, TextEditingController> _modelControllers = {};

  final Set<String> _loadingModels = {};
  bool _isTestingActive = false;
  bool _isCheckingActiveBalance = false;
  String? _activeStatusMessage;

  final GlobalKey _activeBannerKey = GlobalKey();
  final GlobalKey _firstProviderCardKey = GlobalKey();
  final GlobalKey _expandedConfigKey = GlobalKey();

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

  TextEditingController _getUrlCtrl(LlmProviderConfig p) {
    return _urlControllers.putIfAbsent(
        p.id, () => TextEditingController(text: p.baseUrl));
  }

  TextEditingController _getKeyCtrl(LlmProviderConfig p) {
    return _keyControllers.putIfAbsent(
        p.id, () => TextEditingController(text: p.apiKey));
  }

  TextEditingController _getModelCtrl(LlmProviderConfig p) {
    return _modelControllers.putIfAbsent(
        p.id, () => TextEditingController(text: p.selectedModel));
  }

  /// 顺序流畅的一键操作：保存 Key 并立即向云端获取模型列表供用户选择
  Future<void> _onSaveKeyAndFetchModels(LlmProviderConfig p) async {
    final notifier = ref.read(llmProvidersProvider.notifier);
    final key = _getKeyCtrl(p).text.trim();
    final url = _getUrlCtrl(p).text.trim();

    if (key.isEmpty) {
      showAppToast(context, '请先输入该服务商的 API Key');
      return;
    }

    // 先保存输入的 URL 和 Key
    await notifier.updateProvider(p.copyWith(baseUrl: url, apiKey: key));

    setState(() => _loadingModels.add(p.id));
    try {
      final models = await notifier.fetchModelsForProvider(p.id);
      if (mounted) {
        final updatedState = ref.read(llmProvidersProvider);
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

  Future<void> _onSaveProvider(LlmProviderConfig p, {bool setAsActive = false}) async {
    final notifier = ref.read(llmProvidersProvider.notifier);
    final url = _getUrlCtrl(p).text.trim();
    final key = _getKeyCtrl(p).text.trim();
    final model = _getModelCtrl(p).text.trim();

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
      showAppToast(context, setAsActive
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
      final ok = await ref.read(llmConfigProvider.notifier).testConnection();
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

  Future<void> _checkActiveBalance() async {
    final state = ref.read(llmProvidersProvider);
    final active = state.activeProvider;
    if (active == null || !active.isConfigured) {
      showAppToast(context, '当前选用的服务商尚未配置 Key');
      return;
    }

    setState(() {
      _isCheckingActiveBalance = true;
      _activeStatusMessage = null;
    });

    try {
      final res = await ref
          .read(llmProvidersProvider.notifier)
          .fetchBalanceOrPingForProvider(active.id);
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
      if (mounted) setState(() => _isCheckingActiveBalance = false);
    }
  }

  void _showModelPickerSheet(String providerId) {
    final state = ref.read(llmProvidersProvider);
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
                  const Icon(Icons.psychology, color: Colors.teal),
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
                    ? const Center(child: Text('暂无可用模型，请先拉取模型列表'))
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
                                  .read(llmProvidersProvider.notifier)
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

    try {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('添加自定义服务商'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '服务商名称',
                    hintText: '例如: 我的中转站 / 本地Ollama',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: urlCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API Base URL',
                    hintText: 'https://...',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: keyCtrl,
                  decoration: const InputDecoration(
                    labelText: 'API Key',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: modelCtrl,
                  decoration: const InputDecoration(
                    labelText: '模型名称',
                    hintText: '如 gpt-4o, qwen2.5:72b',
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
                final newId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
                final newProvider = LlmProviderConfig(
                  id: newId,
                  name: name,
                  description: '用户自定义端点',
                  defaultBaseUrl: url,
                  baseUrl: url,
                  apiKey: keyCtrl.text.trim(),
                  selectedModel: modelCtrl.text.trim(),
                );
                final nav = Navigator.of(ctx);
                await ref
                    .read(llmProvidersProvider.notifier)
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
    final state = ref.watch(llmProvidersProvider);
    final tutorialState = ref.watch(tutorialProvider);
    final theme = Theme.of(context);
    final active = state.activeProvider;

    final scaffold = Scaffold(
      appBar: AppBar(
        title: const Text('大语言模型'),
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
                // 1. 顶部当前选用模型状态卡片（带测试连接与余额查询）
                _buildActiveStatusBanner(theme, active),
                const SizedBox(height: 18),

                Row(
                  children: [
                    const Icon(Icons.dns_outlined, size: 18, color: Colors.blueGrey),
                    const SizedBox(width: 6),
                    const Text(
                      '服务商列表',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const Spacer(),
                    Text(
                      '已收录 ${state.providers.length} 个服务商',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                const SizedBox(height: 10),

                // 2. 服务商列表
                for (int i = 0; i < state.providers.length; i++)
                  _buildProviderCard(
                    theme,
                    state.providers[i],
                    state.activeProviderId,
                    isFirst: i == 0,
                  ),
              ],
            ),
    );

    if (!tutorialState.isActive ||
        tutorialState.activeTutorial != TutorialType.aiConfig ||
        state.isLoading ||
        state.providers.isEmpty) {
      return scaffold;
    }

    return Stack(
      children: [
        scaffold,
        _buildAiTutorialOverlay(tutorialState, state),
      ],
    );
  }

  Widget _buildAiTutorialOverlay(
      TutorialState tutorialState, LlmProvidersState state) {
    final firstId = state.providers.first.id;

    void expandFirstAndAdvance() {
      setState(() {
        _expandedProviderId ??= firstId;
      });
      ref.read(tutorialProvider.notifier).nextStep();
    }

    if (tutorialState.currentStep == 1) {
      return TutorialSpotlightOverlay(
        targetKey: _firstProviderCardKey,
        stepTag: 'AI 配置指引 · 1/3',
        title: '选择你的大模型服务商',
        description:
            '这里内置了 DeepSeek、硅基流动、智谱、通义千问等主流服务商（右上角 + 也可添加自定义端点）。点击对应卡片即可展开填写。',
        nextButtonLabel: '展开卡片看看',
        onNext: expandFirstAndAdvance,
        onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
        onTargetTap: expandFirstAndAdvance,
      );
    } else if (tutorialState.currentStep == 2) {
      final hasExpanded = _expandedProviderId != null;
      return TutorialSpotlightOverlay(
        targetKey: hasExpanded ? _expandedConfigKey : _firstProviderCardKey,
        stepTag: 'AI 配置指引 · 2/3',
        title: '填入 Key 并选用模型',
        description:
            '粘贴 API Key 后，点「保存 Key 并获取模型列表」挑选模型，再点右下角「确认选用该模型」就会立即生效！',
        nextButtonLabel: '下一步',
        onNext: () => ref.read(tutorialProvider.notifier).nextStep(),
        onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
      );
    } else if (tutorialState.currentStep == 3) {
      return TutorialSpotlightOverlay(
        targetKey: _activeBannerKey,
        stepTag: 'AI 配置指引 · 3/3',
        title: '测试连接，确认可用',
        description:
            '选好之后点这里「测试当前连接」确认接口通畅。\n返回会话页就能直接一键生成了！',
        nextButtonLabel: '完成配置指引',
        onNext: () => ref.read(tutorialProvider.notifier).completeTutorial(),
        onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
      );
    }
    return const SizedBox.shrink();
  }

  /// 顶部当前选用模型 Banner
  Widget _buildActiveStatusBanner(ThemeData theme, LlmProviderConfig? active) {
    final isConfigured = active?.isConfigured ?? false;
    final statusMsg = _activeStatusMessage ?? active?.balance;

    return Container(
      key: _activeBannerKey,
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
                backgroundColor: isConfigured ? Colors.teal : Colors.amber.shade700,
                radius: 14,
                child: const Icon(Icons.bolt_rounded, size: 18, color: Colors.white),
              ),
              const SizedBox(width: 8),
              const Text(
                '当前选用模型',
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
                  isConfigured ? '已就绪' : '未配置 Key',
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
              Text(
                active?.name ?? '未选择',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  active?.selectedModel.isNotEmpty == true ? active!.selectedModel : '未选择模型',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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
                icon: _isCheckingActiveBalance
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.account_balance_wallet_outlined, size: 16),
                label: const Text('查询余额/测速', style: TextStyle(fontSize: 12)),
                onPressed: _isCheckingActiveBalance ? null : _checkActiveBalance,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 单个服务商卡片
  Widget _buildProviderCard(
      ThemeData theme, LlmProviderConfig p, String activeId,
      {bool isFirst = false}) {
    final isActive = p.id == activeId;
    final isExpanded = _expandedProviderId == p.id;
    final isConfigured = p.isConfigured;
    final isLoadingModel = _loadingModels.contains(p.id);

    return Card(
      key: isFirst ? _firstProviderCardKey : null,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isActive
              ? Colors.teal
              : Colors.grey.withValues(alpha: 0.25),
          width: isActive ? 1.8 : 1,
        ),
      ),
      child: Column(
        children: [
          // 卡片头部（点击展开/折叠）
          ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
            leading: CircleAvatar(
              backgroundColor: isActive
                  ? Colors.teal
                  : theme.colorScheme.surfaceContainerHighest,
              foregroundColor: isActive ? Colors.white : theme.colorScheme.primary,
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
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.teal,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '已选用',
                      style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  )
                else if (isConfigured)
                  Container(
                    margin: const EdgeInsets.only(left: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
              key: _expandedConfigKey,
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
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
                      labelText: 'API Key',
                      hintText: 'sk-...',
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
                  FilledButton.tonalIcon(
                    icon: isLoadingModel
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download_outlined, size: 18),
                    label: Text(isLoadingModel ? '正在拉取模型列表...' : '保存 Key 并获取模型列表'),
                    onPressed: isLoadingModel ? null : () => _onSaveKeyAndFetchModels(p),
                  ),
                  const SizedBox(height: 12),

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
                        label: const Text('选择模型', style: TextStyle(fontSize: 12)),
                        onPressed: () => _showModelPickerSheet(p.id),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 5. 底部操作按钮：仅保存 / 确认选用该模型
                  Row(
                    children: [
                      OutlinedButton(
                        onPressed: () => _onSaveProvider(p, setAsActive: false),
                        child: const Text('仅保存'),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: isActive ? Colors.teal : null,
                          ),
                          icon: const Icon(Icons.check_circle_outline, size: 16),
                          label: Text(isActive ? '已选用 (点击更新)' : '确认选用该模型'),
                          onPressed: () => _onSaveProvider(p, setAsActive: true),
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
