import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/services/engine_c/engine_c_models.dart';
import '../../../data/services/engine_c/template_bundle_engine.dart';
import '../../../data/services/hub/hub_service.dart';
import '../../../domain/models/template.dart';
import '../../../providers/providers.dart';
import '../../widgets/engine_c/engine_c_sheets.dart';
import '../templates/content_template_editor_page.dart';
import '../templates/template_editor_page.dart';

const hubKinds = [
  ('structure', '文书类型', Icons.schema_outlined),
  ('content', '内容模板', Icons.article_outlined),
  ('diagnosis', '标准词条库', Icons.bookmark_outline),
  ('typing', '输入方案', Icons.keyboard_outlined),
  ('pipeline', '解析流程', Icons.account_tree_outlined),
];

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
}

enum HubItemSubtype {
  structure,
  content,
  diagnosis,
  typing,
  pipeline,
}

class TemplateHubPage extends ConsumerStatefulWidget {
  const TemplateHubPage({super.key});

  @override
  ConsumerState<TemplateHubPage> createState() => _TemplateHubPageState();
}

class _TemplateHubPageState extends ConsumerState<TemplateHubPage> {
  String _kind = 'structure';
  final TextEditingController _searchCtrl = TextEditingController();
  bool _mineOnly = false;
  bool _isRailExpanded = true;
  List<HubListing> _rawListings = const [];
  bool _loading = true;
  String? _error;

  HubService get _hub => HubService(ref.read(secureStorageProvider));

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listings = await _hub.list(
        kind: _kind,
        q: _searchCtrl.text.trim(),
        mineOnly: _mineOnly,
      );
      if (!mounted) return;
      setState(() {
        _rawListings = listings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '加载失败: $e';
        _loading = false;
      });
    }
  }

  List<HubCardItem> _flattenItems() {
    final items = <HubCardItem>[];
    for (final listing in _rawListings) {
      final s = listing.summary;
      final structName = s.structure?.name.trim().isNotEmpty == true
          ? s.structure!.name.trim()
          : listing.title.trim();

      switch (_kind) {
        case 'structure':
          final slots = s.structure?.slotLabels ?? [];
          final slotOverview = slots.isNotEmpty
              ? '字段：${slots.join("、")}${s.structure!.slotCount > slots.length ? " 等${s.structure!.slotCount}个字段" : ""}'
              : '无独立字段';
          items.add(HubCardItem(
            listing: listing,
            subtype: HubItemSubtype.structure,
            subId: s.structure?.id ?? '',
            subName: structName,
            structureName: structName,
            formattedTitle: '$structName 文书类型',
            primaryDetail: slotOverview,
            secondaryDetail: listing.readme.trim(),
          ));
          break;

        case 'content':
          if (s.contents.isNotEmpty) {
            for (final ct in s.contents) {
              final snippet = ct.sampleSnippet.isNotEmpty
                  ? '示范：${ct.sampleSnippet}'
                  : (ct.hasGlobalGuidance ? '已配置规范指南' : '示范文书');
              items.add(HubCardItem(
                listing: listing,
                subtype: HubItemSubtype.content,
                subId: ct.id,
                subName: ct.name,
                structureName: structName,
                formattedTitle: '$structName 的 ${ct.name} 内容模板',
                primaryDetail: snippet,
                secondaryDetail: listing.readme.trim(),
              ));
            }
          }
          break;

        case 'diagnosis':
          final d = s.diagnoses;
          final count = d?.count ?? listing.counts['diagnoses'] ?? 0;
          final samples = d?.sampleNames.isNotEmpty == true
              ? '词条包含：${d!.sampleNames.join("、")}'
              : '常用标准词条';
          final tags = d?.tags.isNotEmpty == true ? '标签：${d!.tags.join("、")}' : '';
          items.add(HubCardItem(
            listing: listing,
            subtype: HubItemSubtype.diagnosis,
            subId: 'diagnosis',
            subName: listing.title,
            structureName: '',
            formattedTitle: listing.title.endsWith('标准词条库') ? listing.title : '${listing.title} 标准词条库',
            primaryDetail: '$count 条词条 · $samples',
            secondaryDetail: tags.isNotEmpty ? tags : listing.readme.trim(),
          ));
          break;

        case 'typing':
          if (s.profiles.isNotEmpty) {
            for (final prof in s.profiles) {
              final steps = prof.blockCount > 0
                  ? '${prof.blockCount} 步按键动作流'
                  : '标准按键流';
              items.add(HubCardItem(
                listing: listing,
                subtype: HubItemSubtype.typing,
                subId: prof.id,
                subName: prof.name,
                structureName: structName,
                formattedTitle: '$structName 的 ${prof.name} 输入方案',
                primaryDetail: steps,
                secondaryDetail: listing.readme.trim(),
              ));
            }
          }
          break;

        case 'pipeline':
          final p = s.pipeline;
          final flow = p?.stageLabels.isNotEmpty == true
              ? '阶段推进：${p!.stageLabels.join(" → ")}'
              : '${p?.nodeCount ?? 0} 个阶段节点';
          items.add(HubCardItem(
            listing: listing,
            subtype: HubItemSubtype.pipeline,
            subId: 'pipeline',
            subName: '默认解析流程',
            structureName: structName,
            formattedTitle: '$structName 的默认解析流程',
            primaryDetail: flow,
            secondaryDetail: listing.readme.trim(),
          ));
          break;
      }
    }
    return items;
  }

  Future<void> _openDetail(HubCardItem item) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => HubDetailSheet(item: item),
      ),
    );
    _load();
  }

  Future<void> _remove(HubListing listing) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除发布'),
        content: Text('确定从在线模板广场删除「${listing.title}」？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _hub.delete(listing.id);
      if (!mounted) return;
      showAppToast(context, '已删除发布');
      _load();
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, '删除失败: $e');
    }
  }

  void _showSettingsDialog() async {
    final currentUrl = await _hub.getBaseUrl();
    final currentAdminToken = await _hub.getAdminToken();

    final urlCtrl = TextEditingController(text: currentUrl);
    final adminCtrl = TextEditingController(text: currentAdminToken ?? '');
    String testResult = '';

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('在线模板库设置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: urlCtrl,
                  decoration: InputDecoration(
                    labelText: '服务器接口地址',
                    hintText: HubService.defaultBaseUrl,
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.restore, size: 18),
                      tooltip: '恢复默认官方源',
                      onPressed: () {
                        setDialogState(() {
                          urlCtrl.text = HubService.defaultBaseUrl;
                        });
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton.icon(
                      icon: const Icon(Icons.network_check, size: 16),
                      label: const Text('测试连通性'),
                      onPressed: () async {
                        setDialogState(() => testResult = '测试中...');
                        final ok = await _hub.testConnection(urlCtrl.text.trim());
                        setDialogState(() {
                          testResult = ok ? '✅ 连接成功' : '❌ 无法连接到此服务器';
                        });
                      },
                    ),
                    if (testResult.isNotEmpty)
                      Expanded(
                        child: Text(
                          testResult,
                          style: TextStyle(
                            fontSize: 12,
                            color: testResult.startsWith('✅') ? Colors.green : Colors.red,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
                const Divider(height: 24),
                TextField(
                  controller: adminCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: '管理员密钥 (自建源审核使用)',
                    hintText: '留空表示普通用户身份',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '配置管理员密钥后，可直接在广场查阅与审核他人提交的待审内容。',
                  style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
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
                await _hub.setBaseUrl(urlCtrl.text.trim());
                await _hub.setAdminToken(adminCtrl.text.trim());
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (mounted) {
                  showAppToast(context, '在线模板库设置已保存');
                  _load();
                }
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }

  void _showNewPublishPicker() async {
    final templates = await ref.read(templateRepositoryProvider).getAll();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('发布到在线模板广场',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: const Icon(Icons.schema_outlined, color: Colors.blue),
              title: const Text('发布文书类型及下属模板'),
              subtitle: const Text('选择本地已有的模板打包发布'),
              onTap: () {
                Navigator.pop(ctx);
                _pickTemplateToPublish(templates);
              },
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_outline, color: Colors.teal),
              title: const Text('发布标准词条库'),
              subtitle: const Text('分享收藏的标准词条'),
              onTap: () {
                Navigator.pop(ctx);
                EngineCExportSheet.showForDiagnoses(
                  context,
                  publishKind: 'diagnosis',
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  void _pickTemplateToPublish(List<Template> templates) {
    if (templates.isEmpty) {
      showAppToast(context, '本地暂无文书类型，请先创建');
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text('选择要发布的模板',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
            for (final t in templates)
              ListTile(
                title: Text(t.name),
                subtitle: Text('${t.slots.length} 个字段 · ${t.typingProfiles.length} 个输入方案'),
                onTap: () {
                  Navigator.pop(ctx);
                  EngineCExportSheet.showForTemplate(
                    context,
                    t,
                    publishKind: 'structure',
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _flattenItems();

    return Scaffold(
      appBar: AppBar(
        title: const Text('在线模板广场'),
        actions: [
          IconButton(
            tooltip: _mineOnly ? '查看全部' : '只看我的',
            icon: Icon(
              _mineOnly ? Icons.person : Icons.person_outline,
              color: _mineOnly ? Theme.of(context).colorScheme.primary : null,
            ),
            onPressed: () {
              setState(() => _mineOnly = !_mineOnly);
              _load();
            },
          ),
          IconButton(
            tooltip: '源与审核设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _showSettingsDialog,
          ),
          IconButton(
            tooltip: '发布新内容',
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: _showNewPublishPicker,
          ),
        ],
      ),
      body: Row(
        children: [
          // 1. 左侧竖向分栏 (顺序：结构模板、内容模板、常用诊断、输入方案、解析流程)
          _buildLeftRail(),
          const VerticalDivider(width: 1),

          // 2. 右侧主内容区
          Expanded(
            child: Column(
              children: [
                // 顶部搜索框
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                  child: TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: '搜索文书、内容、方案、词条...',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                _load();
                              },
                            )
                          : null,
                      isDense: true,
                      filled: true,
                      fillColor: Colors.grey.withAlpha(20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                    onSubmitted: (_) => _load(),
                  ),
                ),

                // 主内容列表
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(_error!, style: const TextStyle(color: Colors.red)),
                                  const SizedBox(height: 12),
                                  OutlinedButton(onPressed: _load, child: const Text('重试')),
                                ],
                              ),
                            )
                          : items.isEmpty
                              ? Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
                                      const SizedBox(height: 8),
                                      Text(
                                        _mineOnly ? '你还没有在此分类发布过内容' : '暂无相关内容',
                                        style: const TextStyle(color: Colors.grey),
                                      ),
                                    ],
                                  ),
                                )
                              : RefreshIndicator(
                                  onRefresh: _load,
                                  child: ListView.builder(
                                    padding: const EdgeInsets.all(12),
                                    itemCount: items.length,
                                    itemBuilder: (_, i) => _buildCard(items[i]),
                                  ),
                                ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftRail() {
    final width = _isRailExpanded ? 88.0 : 48.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: width,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        children: [
          // 顶部折叠/展开开关
          InkWell(
            onTap: () => setState(() => _isRailExpanded = !_isRailExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Icon(
                  _isRailExpanded ? Icons.chevron_left : Icons.chevron_right,
                  size: 20,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 4),
          for (final entry in hubKinds)
            _buildRailItem(
              kind: entry.$1,
              label: entry.$2,
              icon: entry.$3,
            ),
        ],
      ),
    );
  }

  Widget _buildRailItem({
    required String kind,
    required String label,
    required IconData icon,
  }) {
    final isSelected = _kind == kind;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Tooltip(
        message: !_isRailExpanded ? label : '',
        child: Material(
          color: isSelected ? primaryColor.withAlpha(25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () {
              if (_kind != kind) {
                setState(() => _kind = kind);
                _load();
              }
            },
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: _isRailExpanded ? 9 : 10,
                horizontal: 2,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: isSelected ? primaryColor : Colors.grey.shade700,
                  ),
                  if (_isRailExpanded) ...[
                    const SizedBox(height: 4),
                    Text(
                      label,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? primaryColor : Colors.grey.shade800,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard(HubCardItem item) {
    final listing = item.listing;
    final isMine = listing.isMine;
    final dateStr = DateFormat('MM-dd').format(listing.updatedAt.toLocal());
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isMine
              ? theme.colorScheme.primary.withAlpha(120)
              : theme.dividerColor.withAlpha(45),
          width: isMine ? 1.4 : 1.0,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _openDetail(item),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 顶行：标题与标签
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      item.formattedTitle,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isMine) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: listing.status == 'pending'
                            ? Colors.orange.withAlpha(40)
                            : theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        listing.status == 'pending' ? '审核中' : '我发布的',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: listing.status == 'pending'
                              ? Colors.deepOrange
                              : theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                  ],
                  if (isMine)
                    PopupMenuButton<String>(
                      icon: Icon(Icons.more_horiz, size: 18, color: Colors.grey.shade600),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      onSelected: (action) {
                        if (action == 'delete') _remove(listing);
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                          value: 'delete',
                          child: Text('删除发布', style: TextStyle(color: Colors.red, fontSize: 13)),
                        ),
                      ],
                    ),
                ],
              ),

              const SizedBox(height: 7),

              // 主细节胶囊卡片（字段清单、示范文本、或按键流）
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withAlpha(35),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.primaryDetail,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blueGrey.shade800,
                    height: 1.35,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

              // 说明文档摘要（如有）
              if (item.secondaryDetail.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  item.secondaryDetail,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: Colors.grey.shade600,
                  ),
                ),
              ],

              const SizedBox(height: 6),

              // 底行：日期小标
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  dateStr,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey.shade500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 模板详情页：查看专属说明、复用已有编辑页预览具体内容、定向导入到本地
class HubDetailSheet extends ConsumerStatefulWidget {
  final HubCardItem item;

  const HubDetailSheet({super.key, required this.item});

  @override
  ConsumerState<HubDetailSheet> createState() => _HubDetailSheetState();
}

class _HubDetailSheetState extends ConsumerState<HubDetailSheet> {
  HubListing? _fullListing;
  EngineCBundleEnvelope? _envelope;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final detail = await HubService(ref.read(secureStorageProvider))
          .get(widget.item.listing.id);
      if (detail.payload != null) {
        final decoded = jsonDecode(detail.payload!);
        final env = await ref
            .read(templateBundleEngineProvider)
            .parseRawJsonToEnvelope(Map<String, dynamic>.from(decoded as Map));
        if (!mounted) return;
        setState(() {
          _fullListing = detail;
          _envelope = env;
          _loading = false;
        });
        return;
      }
      if (!mounted) return;
      setState(() {
        _fullListing = detail;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '读取详情失败: $e';
        _loading = false;
      });
    }
  }

  void _previewStructureOrPipelineOrTyping() {
    final env = _envelope;
    if (env == null || env.units.isEmpty) return;
    final unit = env.units.first;

    int initialTab = 0;
    if (widget.item.subtype == HubItemSubtype.pipeline) initialTab = 1;
    if (widget.item.subtype == HubItemSubtype.typing) initialTab = 2;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TemplateEditorPage(
          previewTemplate: unit.structure,
          initialTabIndex: initialTab,
          initialProfileId: widget.item.subtype == HubItemSubtype.typing
              ? widget.item.subId
              : null,
        ),
      ),
    );
  }

  void _previewContentTemplate() {
    final env = _envelope;
    if (env == null || env.units.isEmpty) return;
    final unit = env.units.first;
    final ct = unit.contentTemplates
            .where((c) => c.id == widget.item.subId || c.name == widget.item.subName)
            .firstOrNull ??
        unit.contentTemplates.firstOrNull;
    if (ct == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContentTemplateEditorPage(
          structureTemplateId: unit.structure.id,
          previewStructure: unit.structure,
          previewContentTemplate: ct,
        ),
      ),
    );
  }

  void _previewDiagnoses() {
    final env = _envelope;
    if (env == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (_, scrollCtrl) => ListView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(16),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text('标准词条库预览',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ],
            ),
            const Divider(),
            for (final d in env.diagnoses)
              ListTile(
                dense: true,
                title: Text('${d.code}  ${d.name}'),
                subtitle: d.tags.isNotEmpty ? Text('标签: ${d.tags.join(", ")}') : null,
              ),
          ],
        ),
      ),
    );
  }

  /// 定向导入：根据当前用户点击的具体子项，构建精准的定向 payload
  Future<void> _startImport() async {
    final env = _envelope;
    final full = _fullListing;
    if (env == null || full?.payload == null) return;

    final targetedPayload = _buildTargetedPayload(env);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => EngineCImportSheet(
        title: '导入 · ${widget.item.formattedTitle}',
        initialText: targetedPayload,
        readme: full?.readme ?? '',
      ),
    );
  }

  String _buildTargetedPayload(EngineCBundleEnvelope original) {
    if (widget.item.subtype == HubItemSubtype.diagnosis) {
      return jsonEncode(original.toJson());
    }
    if (original.units.isEmpty) return _fullListing!.payload!;

    final unit = original.units.first;
    switch (widget.item.subtype) {
      case HubItemSubtype.structure:
        // 导入整套结构
        return jsonEncode(original.toJson());

      case HubItemSubtype.pipeline:
        // 定向只导入此流程（附带结构）
        final singleUnit = StructureGroundedUnit(
          structure: unit.structure,
          hasPipeline: true,
          typingProfiles: const [],
          contentTemplates: const [],
        );
        return jsonEncode(EngineCBundleEnvelope(
          exportedAt: DateTime.now(),
          units: [singleUnit],
        ).toJson());

      case HubItemSubtype.typing:
        // 定向只导入用户点的这个输入方案
        final pickedProfiles = unit.typingProfiles
            .where((p) => p.id == widget.item.subId || p.name == widget.item.subName)
            .toList();
        final singleUnit = StructureGroundedUnit(
          structure: unit.structure,
          hasPipeline: false,
          typingProfiles: pickedProfiles.isNotEmpty ? pickedProfiles : unit.typingProfiles,
          contentTemplates: const [],
        );
        return jsonEncode(EngineCBundleEnvelope(
          exportedAt: DateTime.now(),
          units: [singleUnit],
        ).toJson());

      case HubItemSubtype.content:
        // 定向只导入用户点的这个内容模板
        final pickedCts = unit.contentTemplates
            .where((c) => c.id == widget.item.subId || c.name == widget.item.subName)
            .toList();
        final singleUnit = StructureGroundedUnit(
          structure: unit.structure,
          hasPipeline: false,
          typingProfiles: const [],
          contentTemplates: pickedCts.isNotEmpty ? pickedCts : unit.contentTemplates,
        );
        return jsonEncode(EngineCBundleEnvelope(
          exportedAt: DateTime.now(),
          units: [singleUnit],
        ).toJson());

      case HubItemSubtype.diagnosis:
        return jsonEncode(original.toJson());
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final listing = _fullListing ?? item.listing;

    return Scaffold(
      appBar: AppBar(
        title: Text(item.formattedTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // 头部卡片
                    Card(
                      elevation: 0,
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withAlpha(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    item.formattedTitle,
                                    style: const TextStyle(
                                        fontSize: 17, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                if (listing.isMine)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primaryContainer,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      '我发布的',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            if (item.structureName.isNotEmpty &&
                                item.subtype != HubItemSubtype.structure)
                              Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Text('基于文书类型：${item.structureName}',
                                    style: const TextStyle(
                                        fontSize: 13, color: Colors.blueGrey)),
                              ),
                            const SizedBox(height: 6),
                            Text(
                              '发布时间：${DateFormat("yyyy-MM-dd HH:mm").format(listing.updatedAt.toLocal())}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // 说明文档 (Readme)
                    if (listing.readme.trim().isNotEmpty) ...[
                      const Text('使用说明',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: Theme.of(context).cardColor,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                              color: Theme.of(context).dividerColor.withAlpha(60)),
                        ),
                        child: Text(
                          listing.readme.trim(),
                          style: const TextStyle(fontSize: 13.5, height: 1.5),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // 深度预览卡片入口（复用真实编辑界面）
                    const Text('内容详情预览',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),

                    if (item.subtype == HubItemSubtype.content)
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                              color: Theme.of(context).dividerColor.withAlpha(60)),
                        ),
                        leading: const Icon(Icons.article_outlined, color: Colors.indigo),
                        title: Text('查看内容模板「${item.subName}」完整撰写规范与示例'),
                        subtitle: const Text('进入内容模板排版视图进行深度查看'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _previewContentTemplate,
                      )
                    else if (item.subtype == HubItemSubtype.diagnosis)
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                              color: Theme.of(context).dividerColor.withAlpha(60)),
                        ),
                        leading: const Icon(Icons.bookmark_outline, color: Colors.teal),
                        title: const Text('查看全部标准词条清单'),
                        subtitle: Text(item.primaryDetail),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _previewDiagnoses,
                      )
                    else
                      ListTile(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                          side: BorderSide(
                              color: Theme.of(context).dividerColor.withAlpha(60)),
                        ),
                        leading: const Icon(Icons.schema_outlined, color: Colors.blue),
                        title: Text(
                          item.subtype == HubItemSubtype.pipeline
                              ? '查看完整流程节点与连线'
                              : (item.subtype == HubItemSubtype.typing
                                  ? '查看输入方案「${item.subName}」按键动作序列'
                                  : '查看字段定义与整套结构'),
                        ),
                        subtitle: const Text('进入结构编辑器排版视图进行深度查看'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: _previewStructureOrPipelineOrTyping,
                      ),

                    const SizedBox(height: 32),
                  ],
                ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            icon: const Icon(Icons.download),
            label: Text(_buildImportButtonLabel(item)),
            onPressed: (_loading || _error != null) ? null : _startImport,
          ),
        ),
      ),
    );
  }

  String _buildImportButtonLabel(HubCardItem item) {
    switch (item.subtype) {
      case HubItemSubtype.structure:
        return '导入整套模板到本地';
      case HubItemSubtype.pipeline:
        return '导入此流程到本地';
      case HubItemSubtype.typing:
        return '导入输入方案「${item.subName}」到本地';
      case HubItemSubtype.content:
        return '导入内容模板「${item.subName}」到本地';
      case HubItemSubtype.diagnosis:
        return '导入标准词条库到本地';
    }
  }
}
