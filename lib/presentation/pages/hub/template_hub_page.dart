import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../data/services/engine_c/engine_c_models.dart';
import '../../../data/services/engine_c/template_bundle_engine.dart';
import '../../../data/services/hub/hub_payload.dart';
import '../../../data/services/hub/hub_service.dart';
import '../../../providers/providers.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/engine_c/engine_c_sheets.dart';
import '../templates/content_template_editor_page.dart';
import '../templates/template_editor_page.dart';
import 'hub_components.dart';
import 'hub_management.dart';

const hubKinds = [
  ('structure', '文书类型', Icons.schema_outlined),
  ('content', '内容模板', Icons.article_outlined),
  ('diagnosis', '标准词条库', Icons.bookmark_outline),
  ('typing', '输入方案', Icons.keyboard_outlined),
  ('pipeline', '解析流程', Icons.account_tree_outlined),
];

List<HubCardItem> _cardItems(List<HubListing> listings, String kind) {
  final items = <HubCardItem>[];
  final seen = <String>{};
  final ordered = kind == 'structure'
      ? [
          ...listings.where((l) => l.isMine),
          ...listings.where((l) => !l.isMine),
        ]
      : listings;
  for (final listing in ordered) {
    final s = listing.summary;
    final structureName = s.structure?.name.isNotEmpty == true
        ? s.structure!.name
        : kind == 'structure'
        ? listing.name
        : '';
    void add(HubItemSubtype type, String id, String name, String preview) {
      items.add(
        HubCardItem(
          listing: listing,
          subtype: type,
          subId: id,
          subName: name,
          structureName: structureName,
          formattedTitle: listing.title,
          primaryDetail: preview,
          secondaryDetail: listing.readme,
        ),
      );
    }

    switch (kind) {
      case 'structure':
        if (listing.structureId.isNotEmpty && !seen.add(listing.structureId)) {
          continue;
        }
        add(
          HubItemSubtype.structure,
          s.structure?.id ?? '',
          structureName.isNotEmpty ? structureName : listing.title,
          s.structure?.slotLabels.join('、') ?? '',
        );
      case 'content':
        for (final c in s.contents) {
          add(
            HubItemSubtype.content,
            c.id,
            c.name,
            c.sampleSnippet.isNotEmpty ? c.sampleSnippet : '',
          );
        }
      case 'typing':
        for (final p in s.profiles) {
          add(
            HubItemSubtype.typing,
            p.id,
            p.name,
            p.blockCount > 0 ? '${p.blockCount} 个输入步骤' : '按字段顺序录入',
          );
        }
      case 'pipeline':
        add(
          HubItemSubtype.pipeline,
          'pipeline',
          '默认解析流程',
          s.pipeline?.stageLabels.join(' → ') ?? '',
        );
      case 'diagnosis':
        add(
          HubItemSubtype.diagnosis,
          'diagnosis',
          listing.name.isEmpty ? listing.title : listing.name,
          s.diagnoses?.sampleNames.join('、') ?? '',
        );
    }
  }
  return items;
}

String _errorText(Object error) {
  if (error is DioException && error.response?.data is Map) {
    return error.response!.data['error']?.toString() ?? '连接失败，请稍后重试';
  }
  return '连接失败，请稍后重试';
}

class TemplateHubPage extends ConsumerStatefulWidget {
  const TemplateHubPage({super.key});
  @override
  ConsumerState<TemplateHubPage> createState() => _TemplateHubPageState();
}

class _TemplateHubPageState extends ConsumerState<TemplateHubPage> {
  String _kind = 'structure';
  final _search = TextEditingController();
  bool _mineOnly = false;
  bool _railExpanded = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _sequence = 0;
  String? _error;
  List<HubListing> _listings = const [];
  HubService get _hub => HubService(ref.read(secureStorageProvider));

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load({bool append = false}) async {
    if (append && _loadingMore) return;
    final sequence = ++_sequence;
    setState(() {
      if (append) {
        _loadingMore = true;
      } else {
        _loading = true;
      }
      _error = null;
    });
    try {
      final listings = await _hub.list(
        kind: _kind,
        q: _search.text,
        mineOnly: _mineOnly,
        offset: append ? _listings.length : 0,
      );
      if (!mounted || sequence != _sequence) return;
      setState(() {
        _listings = append ? [..._listings, ...listings] : listings;
        _hasMore = listings.length == 50;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted && sequence == _sequence) {
        setState(() {
          _error = _errorText(e);
          _loading = false;
          _loadingMore = false;
        });
      }
    }
  }

  Future<void> _manage(HubListing listing) async {
    final result = await manageHubPublication(context, _hub, listing);
    if (mounted && result != HubManagementResult.cancelled) await _load();
  }

  Future<void> _open(HubCardItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HubDetailSheet(item: item)),
    );
    if (mounted) await _load();
  }

  Future<void> _settings() async {
    final hub = _hub;
    final url = await hub.getBaseUrl();
    final token = await hub.getAdminToken();
    if (!mounted) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _HubSettingsDialog(
        service: hub,
        initialUrl: url,
        initialToken: token ?? '',
      ),
    );
    if (saved == true && mounted) await _load();
  }

  Future<void> _publish() async {
    final kind = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.schema_outlined),
            title: const Text('发布文书及模板'),
            onTap: () => Navigator.pop(ctx, 'structure'),
          ),
          ListTile(
            leading: const Icon(Icons.bookmark_outline),
            title: const Text('发布标准词条库'),
            onTap: () => Navigator.pop(ctx, 'diagnosis'),
          ),
        ],
      ),
    );
    if (kind == null || !mounted) return;
    try {
      if (kind == 'diagnosis') {
        final catalogs = await ref.read(catalogsProvider.future);
        if (!mounted) return;
        final id = await showModalBottomSheet<String>(
          context: context,
          useSafeArea: true,
          builder: (ctx) => ListView(
            shrinkWrap: true,
            children: [
              for (final c in catalogs.where((c) => c.isEnabled))
                ListTile(
                  title: Text(c.name),
                  onTap: () => Navigator.pop(ctx, c.id),
                ),
            ],
          ),
        );
        if (id != null && mounted) {
          await EngineCExportSheet.showForDiagnoses(
            context,
            catalogType: id,
            publishKind: 'diagnosis',
          );
        }
      } else {
        final templates = await ref.read(templateRepositoryProvider).getAll();
        if (!mounted) return;
        if (templates.isEmpty) {
          showAppToast(context, '请先创建文书类型');
          return;
        }
        final template = await showModalBottomSheet(
          context: context,
          useSafeArea: true,
          builder: (ctx) => ListView(
            shrinkWrap: true,
            children: [
              for (final t in templates)
                ListTile(
                  title: Text(t.name),
                  onTap: () => Navigator.pop(ctx, t),
                ),
            ],
          ),
        );
        if (template != null && mounted) {
          await EngineCExportSheet.showForTemplate(
            context,
            template,
            publishKind: 'structure',
          );
        }
      }
      if (mounted) await _load();
    } catch (e) {
      if (mounted) showAppToast(context, _errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _cardItems(_listings, _kind);
    return Scaffold(
      appBar: AppBar(
        title: const Text('在线模板广场'),
        actions: [
          IconButton(
            tooltip: _mineOnly ? '查看全部' : '只看我的',
            icon: Icon(_mineOnly ? Icons.person : Icons.person_outline),
            onPressed: () {
              setState(() => _mineOnly = !_mineOnly);
              _load();
            },
          ),
          IconButton(
            tooltip: '模板库设置',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _settings,
          ),
          IconButton(
            tooltip: '发布',
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: _publish,
          ),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _rail(),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _load(),
                    decoration: InputDecoration(
                      hintText: '搜索名称、内容、机构',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 18),
                              onPressed: () {
                                _search.clear();
                                _load();
                              },
                            ),
                      isDense: true,
                      filled: true,
                      fillColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerLow,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(_error!),
                                TextButton(
                                  onPressed: _load,
                                  child: const Text('重试'),
                                ),
                              ],
                            ),
                          ),
                        )
                      : items.isEmpty
                      ? Center(child: Text(_mineOnly ? '暂无自己的发布' : '暂无相关内容'))
                      : RefreshIndicator(
                          onRefresh: _load,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: items.length + (_hasMore ? 1 : 0),
                            itemBuilder: (_, i) {
                              if (i == items.length) {
                                return TextButton(
                                  onPressed: _loadingMore
                                      ? null
                                      : () => _load(append: true),
                                  child: Text(_loadingMore ? '加载中…' : '加载更多'),
                                );
                              }
                              final item = items[i];
                              return HubListingCard(
                                item: item,
                                onTap: () => _open(item),
                                trailing: item.listing.isMine
                                    ? HubPublicationMenu(
                                        listing: item.listing,
                                        onManage: () => _manage(item.listing),
                                      )
                                    : null,
                              );
                            },
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

  Widget _rail() {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: _railExpanded ? 88 : 48,
      color: scheme.surface,
      child: SingleChildScrollView(
        child: Column(
          children: [
            IconButton(
              tooltip: _railExpanded ? '收起分类' : '展开分类',
              onPressed: () => setState(() => _railExpanded = !_railExpanded),
              icon: Icon(
                _railExpanded ? Icons.chevron_left : Icons.chevron_right,
                size: 20,
              ),
            ),
            for (final kind in hubKinds)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: Tooltip(
                  message: kind.$2,
                  child: Material(
                    color: _kind == kind.$1
                        ? scheme.primaryContainer
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(9),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(9),
                      onTap: () {
                        if (_kind != kind.$1) {
                          setState(() => _kind = kind.$1);
                          _load();
                        }
                      },
                      child: SizedBox(
                        width: double.infinity,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            vertical: 11,
                            horizontal: 2,
                          ),
                          child: Column(
                            children: [
                              Icon(
                                kind.$3,
                                size: 20,
                                color: _kind == kind.$1
                                    ? scheme.onPrimaryContainer
                                    : scheme.onSurfaceVariant,
                              ),
                              if (_railExpanded) ...[
                                const SizedBox(height: 5),
                                Text(
                                  kind.$2,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _kind == kind.$1
                                        ? scheme.onPrimaryContainer
                                        : scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class HubDetailSheet extends ConsumerStatefulWidget {
  final HubCardItem item;
  const HubDetailSheet({super.key, required this.item});
  @override
  ConsumerState<HubDetailSheet> createState() => _HubDetailSheetState();
}

class _HubDetailSheetState extends ConsumerState<HubDetailSheet> {
  HubListing? _listing;
  EngineCBundleEnvelope? _envelope;
  List<HubListing> _related = const [];
  bool _loading = true;
  String? _error;
  HubService get _hub => HubService(ref.read(secureStorageProvider));
  HubCardItem get _item {
    if (_listing == null) return widget.item;
    return _cardItems(
          [_listing!],
          widget.item.subtype.name,
        ).where((c) => c.subId == widget.item.subId).firstOrNull ??
        widget.item;
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final listing = await _hub.get(widget.item.listing.id);
      if (listing.payload == null) throw const FormatException('缺少内容');
      final envelope = await ref
          .read(templateBundleEngineProvider)
          .parseRawJsonToEnvelope(
            Map<String, dynamic>.from(jsonDecode(listing.payload!) as Map),
          );
      List<HubListing> related = const [];
      if (listing.structureId.isNotEmpty) {
        try {
          related = await _hub.related(listing.structureId);
        } on DioException {
          /* Older custom sources may not support related entries. */
        }
      }
      if (!mounted) return;
      setState(() {
        _listing = listing;
        _envelope = envelope;
        _related = related;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = _errorText(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _manage() async {
    final result = await manageHubPublication(
      context,
      _hub,
      _listing ?? widget.item.listing,
    );
    if (!mounted) return;
    if (result == HubManagementResult.deleted) {
      Navigator.pop(context);
    } else if (result == HubManagementResult.requested) {
      await _fetch();
    }
  }

  void _preview() {
    final envelope = _envelope;
    if (envelope == null) return;
    if (_item.subtype == HubItemSubtype.diagnosis) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.75,
          builder: (_, scroll) => ListView.builder(
            controller: scroll,
            itemCount: envelope.diagnoses.length,
            itemBuilder: (_, i) {
              final e = envelope.diagnoses[i];
              return ListTile(
                title: Text(e.name),
                subtitle: Text(
                  [
                    e.code,
                    e.note,
                    ...e.tags,
                  ].where((s) => s.isNotEmpty).join(' · '),
                ),
              );
            },
          ),
        ),
      );
      return;
    }
    final unit = envelope.units.firstOrNull;
    if (unit == null) return;
    Widget page;
    if (_item.subtype == HubItemSubtype.content) {
      final content = unit.contentTemplates
          .where((c) => c.id == _item.subId)
          .firstOrNull;
      if (content == null) {
        showAppToast(context, '所选内容已更新，请刷新');
        return;
      }
      page = ContentTemplateEditorPage(
        structureTemplateId: unit.structure.id,
        previewStructure: unit.structure,
        previewContentTemplate: content,
      );
    } else {
      page = TemplateEditorPage(
        previewTemplate: unit.structure,
        initialTabIndex: _item.subtype == HubItemSubtype.pipeline
            ? 1
            : _item.subtype == HubItemSubtype.typing
            ? 2
            : 0,
        initialProfileId: _item.subtype == HubItemSubtype.typing
            ? _item.subId
            : null,
      );
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  Future<void> _import() async {
    final envelope = _envelope;
    if (envelope == null) return;
    try {
      final payload = selectHubPayload(
        envelope.toJson(),
        _item.subtype.name,
        _item.subId,
      );
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => EngineCImportSheet(
          title: '导入 · ${_item.displayName}',
          initialText: jsonEncode(payload),
          readme: _listing?.readme ?? '',
          preview: HubContentPreview(
            envelope: envelope,
            subtype: _item.subtype,
            targetId: _item.subId,
          ),
        ),
      );
    } on FormatException catch (e) {
      if (mounted) showAppToast(context, e.message);
    }
  }

  Future<void> _openRelated(HubCardItem item) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => HubDetailSheet(item: item)),
    );
    if (mounted) await _fetch();
  }

  @override
  Widget build(BuildContext context) {
    final item = _item;
    final listing = _listing ?? item.listing;
    final related = [
      for (final l in _related.where((l) => l.id != listing.id))
        ..._cardItems([l], l.kind),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('模板详情'),
        actions: [
          if (!_loading && _error == null && listing.isMine)
            HubPublicationMenu(listing: listing, onManage: _manage),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_error!),
                  TextButton(onPressed: _fetch, child: const Text('重试')),
                ],
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                HubEntryHeading(item: item, large: true),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (listing.isMine || listing.visibility == 'private')
                      Text(
                        listing.publicationLabel,
                        style: TextStyle(color: item.accent),
                      ),
                    Text(
                      DateFormat(
                        'yyyy-MM-dd HH:mm',
                      ).format(listing.updatedAt.toLocal()),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
                if (listing.visibility == 'private')
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text('仅发布者与管理员可见'),
                  ),
                const SizedBox(height: 22),
                if (_envelope != null)
                  HubContentPreview(
                    envelope: _envelope!,
                    subtype: item.subtype,
                    targetId: item.subId,
                  ),
                FilledButton.tonalIcon(
                  onPressed: _preview,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    backgroundColor: item.accent.withValues(alpha: 0.12),
                    foregroundColor: item.accent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('查看完整内容'),
                ),
                if (listing.readme.trim().isNotEmpty) ...[
                  const SizedBox(height: 18),
                  HubPreviewSection(
                    title: '使用说明',
                    child: SelectableText(
                      listing.readme,
                      style: const TextStyle(height: 1.65),
                    ),
                  ),
                ],
                if (related.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    '同一文书下的内容',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  for (final r in related)
                    HubListingCard(item: r, onTap: () => _openRelated(r)),
                ],
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: FilledButton.icon(
            onPressed: _loading || _error != null ? null : _import,
            icon: const Icon(Icons.download, size: 18),
            label: const Text('导入到本地'),
          ),
        ),
      ),
    );
  }
}

class _HubSettingsDialog extends StatefulWidget {
  final HubService service;
  final String initialUrl;
  final String initialToken;
  const _HubSettingsDialog({
    required this.service,
    required this.initialUrl,
    required this.initialToken,
  });
  @override
  State<_HubSettingsDialog> createState() => _HubSettingsDialogState();
}

class _HubSettingsDialogState extends State<_HubSettingsDialog> {
  late final _url = TextEditingController(text: widget.initialUrl);
  late final _token = TextEditingController(text: widget.initialToken);
  bool _busy = false;
  String? _message;
  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await widget.service.setBaseUrl(_url.text);
      await widget.service.setAdminToken(_token.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _message = e is FormatException ? e.message : '保存失败';
        });
      }
    }
  }

  Future<void> _test() async {
    setState(() => _busy = true);
    final ok = await widget.service.testConnection(_url.text);
    if (mounted) {
      setState(() {
        _busy = false;
        _message = ok ? '连接成功' : '连接失败';
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('模板库设置'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _url,
            enabled: !_busy,
            onChanged: (_) => _token.clear(),
            decoration: InputDecoration(
              labelText: '服务器地址',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: '恢复默认',
                onPressed: _busy
                    ? null
                    : () {
                        _url.text = HubService.defaultBaseUrl;
                        _token.clear();
                      },
                icon: const Icon(Icons.restore),
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _busy ? null : _test,
              child: const Text('测试连接'),
            ),
          ),
          if (_message != null) Text(_message!),
          const SizedBox(height: 12),
          TextField(
            controller: _token,
            enabled: !_busy,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: '管理员密钥（选填）',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: _busy ? null : () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _busy ? null : _save, child: const Text('保存')),
    ],
  );
}
