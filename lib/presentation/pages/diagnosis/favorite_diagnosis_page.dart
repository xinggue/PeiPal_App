import 'dart:async';
import 'dart:convert';
import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/catalog/catalog_source.dart';
import '../../../data/services/engine_c/config_file_io.dart';
import '../../../domain/models/catalog_definition.dart';
import '../../../domain/models/favorite_diagnosis.dart';
import '../../../providers/providers.dart';
import '../../widgets/common/catalog_visuals.dart';
import '../../widgets/diagnosis/catalog_entry_detail_dialog.dart';
import '../../widgets/engine_c/engine_c_sheets.dart';
import 'diagnosis_search_page.dart';

class FavoriteDiagnosisPage extends ConsumerStatefulWidget {
  const FavoriteDiagnosisPage({super.key});

  @override
  ConsumerState<FavoriteDiagnosisPage> createState() =>
      _FavoriteDiagnosisPageState();
}

class _FavoriteDiagnosisPageState extends ConsumerState<FavoriteDiagnosisPage> {
  String _catalogType = 'diagnosis';
  String? _selectedTagFilter; // null means '全量底库', '__favorites__' means '已收藏', other means tag
  bool _isRailExpanded = true;
  final TextEditingController _newTagCtrl = TextEditingController();
  final TextEditingController _rawSearchCtrl = TextEditingController();
  Timer? _rawDebounceTimer;
  List<CatalogLookupEntry> _rawSearchResults = [];
  bool _isRawSearching = false;

  final List<CatalogLookupEntry> _rawItems = [];
  int _rawOffset = 0;
  bool _rawLoading = false;
  bool _rawHasMore = true;
  int _rawTotalCount = 0;
  final ScrollController _rawScrollCtrl = ScrollController();
  Set<String> _favKeys = {};
  bool _initialCatalogLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadRawCount();
    _loadRawBatch();
    _rawScrollCtrl.addListener(_onRawScroll);
  }

  @override
  void dispose() {
    _rawSearchCtrl.dispose();
    _rawDebounceTimer?.cancel();
    _rawScrollCtrl.dispose();
    _newTagCtrl.dispose();
    super.dispose();
  }

  void _onRawSearchChanged(String text) {
    _rawDebounceTimer?.cancel();
    final query = text.trim();
    if (query.isEmpty) {
      setState(() {
        _rawSearchResults = [];
        _isRawSearching = false;
      });
      return;
    }

    setState(() => _isRawSearching = true);
    _rawDebounceTimer = Timer(const Duration(milliseconds: 150), () async {
      try {
        final source =
            await ref.read(catalogSourceProvider(_catalogType).future);
        final results = await source.search(query, limit: 100);
        if (mounted) {
          setState(() {
            _rawSearchResults = results;
            _isRawSearching = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => _isRawSearching = false);
      }
    });
  }

  void _onRawScroll() {
    if (_rawScrollCtrl.position.pixels >= _rawScrollCtrl.position.maxScrollExtent - 300) {
      _loadRawBatch();
    }
  }

  Future<void> _loadRawCount() async {
    try {
      final source =
          await ref.read(catalogSourceProvider(_catalogType).future);
      final cnt = await source.getTotalCount();
      if (mounted) setState(() => _rawTotalCount = cnt);
    } catch (_) {}
  }

  Future<void> _loadRawBatch() async {
    if (_rawLoading || !_rawHasMore) return;
    setState(() => _rawLoading = true);
    try {
      final source =
          await ref.read(catalogSourceProvider(_catalogType).future);
      final batch = await source.getPaged(offset: _rawOffset, limit: 50);
      if (mounted) {
        setState(() {
          _rawItems.addAll(batch);
          _rawOffset += batch.length;
          _rawHasMore = batch.length >= 50;
          _rawLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _rawLoading = false);
    }
  }

  List<CatalogDefinition> get _catalogs =>
      ref.read(catalogsProvider).valueOrNull ?? const <CatalogDefinition>[];

  CatalogDefinition? get _currentCatalog {
    for (final c in _catalogs) {
      if (c.id == _catalogType) return c;
    }
    return _catalogs.isNotEmpty ? _catalogs.first : null;
  }

  bool get _catalogSearchable => _currentCatalog != null;

  String get _catalogLabel => _currentCatalog?.name ?? _catalogType;

  void _selectCatalog(String type) {
    if (_catalogType == type) return;
    setState(() {
      _catalogType = type;
      _selectedTagFilter = null;
      _rawItems.clear();
      _rawOffset = 0;
      _rawHasMore = true;
      _rawTotalCount = 0;
      _rawSearchCtrl.clear();
      _rawSearchResults = [];
    });
    _loadRawCount();
    _loadRawBatch();
  }

  void _invalidateCatalog() {
    ref.invalidate(favoriteDiagnosesProvider);
    ref.invalidate(catalogEntriesProvider(_catalogType));
  }

  void _openSearchPage() async {
    if (!_catalogSearchable) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DiagnosisSearchPage(catalogId: _catalogType),
      ),
    );
    _invalidateCatalog();
  }

  void _openCustomAddDialog([FavoriteDiagnosis? existing]) async {
    final isFav = existing != null;
    final changed = await CatalogEntryDetailDialog.show(
      context,
      ref,
      catalogType: _catalogType,
      code: existing?.code ?? '',
      name: existing?.name ?? '',
      version: existing?.version ?? '自定义',
      note: existing?.note ?? '',
      initialTags: existing?.tags ?? const [],
      isFavorite: isFav,
    );
    if (changed != null && mounted) {
      _invalidateCatalog();
    }
  }

  Future<void> _openRawItemDetail(CatalogLookupEntry item) async {
    final repo = ref.read(favoriteDiagnosisRepositoryProvider);
    final key = '${item.code}|${item.name}';
    final existing = await repo.findByCodeAndName(item.code, item.name, catalogType: _catalogType);
    final isFav = existing != null;

    if (!mounted) return;
    final changed = await CatalogEntryDetailDialog.show(
      context,
      ref,
      catalogType: _catalogType,
      code: item.code,
      name: item.name,
      version: existing?.version ?? item.version,
      note: existing?.note ?? '',
      initialTags: existing?.tags ?? const [],
      isFavorite: isFav,
    );

    if (changed != null && mounted) {
      setState(() {
        if (changed == true) {
          _favKeys.add(key);
        } else if (changed == false) {
          _favKeys.remove(key);
        }
      });
      _invalidateCatalog();
    }
  }

  void _renameTagDialog(String oldTag) async {
    final ctrl = TextEditingController(text: oldTag);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('重命名标签「$oldTag」'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '新标签名',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );

    if (ok == true && ctrl.text.trim().isNotEmpty) {
      final newT = ctrl.text.trim();
      await ref
          .read(catalogTagsProviderFamily(_catalogType).notifier)
          .renameTag(oldTag, newT);
      if (_selectedTagFilter == oldTag) {
        setState(() => _selectedTagFilter = newT);
      }
      _invalidateCatalog();
    }
  }

  void _confirmDeleteTag(String tag) async {
    final count = await ref
        .read(catalogTagsProviderFamily(_catalogType).notifier)
        .getDiagnosisCountForTag(tag);

    if (!mounted) return;

    final warning = count > 0
        ? '⚠️ 标签「$tag」当前关联了 $count 条已收藏词条。\n\n删除该标签后，将同时从这 $count 条词条中解除此标签，确定要删除吗？'
        : '确定要删除标签「$tag」吗？';

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除标签'),
        content: Text(warning),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await ref
          .read(catalogTagsProviderFamily(_catalogType).notifier)
          .deleteTag(tag);
      if (_selectedTagFilter == tag) {
        setState(() => _selectedTagFilter = null);
      }
      _invalidateCatalog();
    }
  }

  Future<void> _importEntries(String catalogType, String catalogName) async {
    final text = await ConfigFileIo.pickAndReadConfigFile();
    if (text == null || text.trim().isEmpty) return;

    final imported = <CatalogEntry>[];
    final tags = <String>{};

    try {
      final trimmed = text.trim();
      if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
        final decoded = jsonDecode(trimmed);
        final list = decoded is List
            ? decoded
            : (decoded is Map && decoded['entries'] is List
                ? decoded['entries'] as List
                : const []);
        for (final item in list) {
          if (item is! Map) continue;
          final name = item['name']?.toString().trim() ?? '';
          if (name.isEmpty) continue;
          final entryTags = (item['tags'] is List)
              ? (item['tags'] as List).map((e) => e.toString()).toList()
              : const <String>[];
          imported.add(CatalogEntry(
            catalogType: catalogType,
            code: item['code']?.toString() ?? '',
            name: name,
            version: item['version']?.toString() ?? '',
            note: item['note']?.toString() ?? '',
            tags: entryTags,
          ));
          tags.addAll(entryTags);
        }
      } else {
        final lines = const LineSplitter().convert(text);
        for (final line in lines) {
          final row = line.trim();
          if (row.isEmpty || row.startsWith('#')) continue;
          final cols = row.split(',');
          if (cols.length < 2) continue;
          final name = cols[1].trim();
          if (name.isEmpty) continue;
          final rawTags = cols.length > 4 ? cols[4].trim() : '';
          final entryTags = rawTags
              .split(RegExp(r'[|;、]'))
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();
          imported.add(CatalogEntry(
            catalogType: catalogType,
            code: cols[0].trim(),
            name: name,
            version: cols.length > 2 ? cols[2].trim() : '',
            note: cols.length > 3 ? cols[3].trim() : '',
            tags: entryTags,
          ));
          tags.addAll(entryTags);
        }
      }
    } catch (e) {
      if (mounted) showAppToast(context, '导入解析失败: $e');
      return;
    }

    if (imported.isEmpty) {
      if (mounted) showAppToast(context, '没有解析到有效词条');
      return;
    }

    final entryRepo = ref.read(catalogEntryRepositoryProvider);
    for (final entry in imported) {
      await entryRepo.insert(entry);
    }
    for (final tag in tags) {
      await ref.read(catalogTagsRepositoryProvider).addTag(catalogType, tag);
    }

    ref.invalidate(catalogEntriesProvider(catalogType));
    ref.invalidate(catalogTagsProviderFamily(catalogType));
    if (catalogType == _catalogType && mounted) {
      setState(() {
        _rawItems.clear();
        _rawOffset = 0;
        _rawHasMore = true;
        _rawTotalCount = 0;
      });
      _loadRawCount();
      _loadRawBatch();
    }
    if (mounted) {
      showAppToast(context, '已导入 ${imported.length} 条词条到「$catalogName」');
    }
  }

  Future<void> _createCatalog() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新建词库'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: '词库名称 *',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: '说明（选填）',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('创建')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;

    final id = 'catalog_${DateTime.now().millisecondsSinceEpoch}';
    final now = DateTime.now();
    await ref.read(catalogRepositoryProvider).insert(CatalogDefinition(
          id: id,
          name: name,
          description: descCtrl.text.trim(),
          sourceKind: CatalogSourceKind.managed,
          searchable: true,
          sortOrder: 100,
          createdAt: now,
          updatedAt: now,
        ));
    ref.invalidate(catalogsProvider);
    if (mounted) {
      setState(() {
        _catalogType = id;
        _selectedTagFilter = null;
        _rawItems.clear();
        _rawOffset = 0;
        _rawHasMore = true;
      });
      _loadRawCount();
      _loadRawBatch();
    }
  }

  Future<void> _editCatalog(CatalogDefinition current) async {
    final nameCtrl = TextEditingController(text: current.name);
    final descCtrl = TextEditingController(text: current.description);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('编辑词库'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: '词库名称',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(
                labelText: '说明',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('保存')),
        ],
      ),
    );
    if (ok != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;
    await ref.read(catalogRepositoryProvider).update(
          current.copyWith(name: name, description: descCtrl.text.trim()),
        );
    ref.invalidate(catalogsProvider);
    if (mounted) setState(() {});
  }

  Future<void> _toggleCatalog(CatalogDefinition current) async {
    await ref.read(catalogRepositoryProvider).update(
          current.copyWith(isEnabled: !current.isEnabled),
        );
    ref.invalidate(catalogsProvider);
    if (mounted) setState(() {});
  }

  Future<void> _deleteCatalog(CatalogDefinition current) async {
    if (current.isSystem) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除词库'),
        content: Text(
            '确定删除词库「${current.name}」及其全部词条与标签吗？模板中的引用将失效。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(catalogEntryRepositoryProvider).deleteByCatalog(current.id);
    await ref.read(catalogTagsRepositoryProvider).deleteByCatalog(current.id);
    await ref.read(catalogRepositoryProvider).delete(current.id);
    ref.invalidate(catalogsProvider);
    ref.invalidate(catalogEntriesProvider(current.id));
    if (mounted) {
      setState(() {
        _catalogType = 'diagnosis';
        _selectedTagFilter = null;
      });
    }
  }

  void _deleteFavorite(FavoriteDiagnosis item) async {
    final repo = ref.read(favoriteDiagnosisRepositoryProvider);
    await repo.delete(item.id);
    _invalidateCatalog();
    if (mounted) {
      showAppToast(context, '已删除标准词条：${item.name}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogsAsync = ref.watch(catalogsProvider);
    if (!_initialCatalogLoaded &&
        catalogsAsync.hasValue &&
        _currentCatalog != null) {
      _initialCatalogLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _loadRawCount();
        _loadRawBatch();
      });
    }
    final favsAsync = ref.watch(catalogEntriesProvider(_catalogType));
    final publishEnabled = _catalogType == 'diagnosis';

    return Scaffold(
      appBar: AppBar(
        title: Text('标准词条库 · $_catalogLabel'),
        actions: [
          if (_catalogSearchable)
            IconButton(
              icon: const Icon(Icons.search),
              tooltip: '检索标准词条',
              onPressed: _openSearchPage,
            ),
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: '手动新建词条',
            onPressed: () => _openCustomAddDialog(),
          ),
          if (publishEnabled)
            IconButton(
              icon: const Icon(Icons.cloud_upload_outlined),
              tooltip: '发布到在线模板广场',
              onPressed: () => EngineCExportSheet.showForDiagnoses(
                context,
                initialTag: _selectedTagFilter,
                publishKind: 'diagnosis',
              ),
            ),
          if (publishEnabled)
            IconButton(
              icon: const Icon(Icons.ios_share),
              tooltip: '导出模板',
              onPressed: () => EngineCExportSheet.showForDiagnoses(
                context,
                catalogType: _catalogType,
                initialTag: _selectedTagFilter,
              ),
            ),
          if (publishEnabled)
            IconButton(
              icon: const Icon(Icons.download),
              tooltip: '导入词条',
              onPressed: () => EngineCImportSheet.show(
                context,
                title: '导入标准词条库',
              ),
            ),
        ],
      ),
      body: Row(
        children: [
          _buildLeftRail(),
          const VerticalDivider(width: 1),
          Expanded(child: _buildEntryList(favsAsync)),
        ],
      ),
    );
  }

  Widget _buildLeftRail() {
    final width = _isRailExpanded ? 168.0 : 52.0;
    final allTags = ref.watch(catalogTagsProviderFamily(_catalogType));
    final favs = ref.watch(catalogEntriesProvider(_catalogType)).valueOrNull;

    return AnimatedSize(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topLeft,
      child: Container(
      width: width,
      color: Theme.of(context).colorScheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _isRailExpanded = !_isRailExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                mainAxisAlignment: _isRailExpanded
                    ? MainAxisAlignment.start
                    : MainAxisAlignment.center,
                children: [
                  Icon(
                    _isRailExpanded
                        ? Icons.chevron_left
                        : Icons.chevron_right,
                    size: 18,
                    color: Colors.grey.shade600,
                  ),
                  if (_isRailExpanded) ...[
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '折叠侧边栏',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          _buildRailHeader(),
          for (final entry in _catalogs)
            _buildCatalogItem(definition: entry),
          const Divider(height: 1),
          if (_isRailExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
              child: Text(
                '标签',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade600,
                ),
              ),
            ),
          Expanded(
            child: _isRailExpanded
                ? _buildTagPane(allTags, favs)
                : const SizedBox.shrink(),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildRailHeader() {
    if (!_isRailExpanded) {
      return Align(
        alignment: Alignment.center,
        child: IconButton(
          icon: const Icon(Icons.settings, size: 18, color: Colors.grey),
          tooltip: '管理词库',
          visualDensity: VisualDensity.compact,
          onPressed: _showCatalogManager,
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 2, 4, 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '词条库',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings, size: 18, color: Colors.grey),
            tooltip: '管理词库',
            visualDensity: VisualDensity.compact,
            onPressed: _showCatalogManager,
          ),
        ],
      ),
    );
  }

  Future<void> _showCatalogManager() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => Consumer(
        builder: (ctx, ref2, _) {
          final catalogs = ref2.watch(catalogsProvider).valueOrNull ??
              const <CatalogDefinition>[];
          return Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              14,
              16,
              MediaQuery.of(ctx).padding.bottom + 14,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.tune, size: 20, color: Colors.teal),
                    const SizedBox(width: 8),
                    const Text('管理词库',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: catalogs.length,
                    itemBuilder: (ctx, i) {
                      final c = catalogs[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          catalogIcon(c.icon.isEmpty ? c.id : c.icon),
                          color: catalogColor(c, Theme.of(ctx)),
                        ),
                        title: Text(c.name),
                        subtitle: Text(
                          c.isSystem
                              ? '系统词库'
                              : (c.isEnabled ? '自定义词库 · 启用中' : '自定义词库 · 已停用'),
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'rename':
                                _editCatalog(c);
                                break;
                              case 'toggle':
                                _toggleCatalog(c);
                                break;
                              case 'import':
                                _importEntries(c.id, c.name);
                                break;
                              case 'delete':
                                _deleteCatalog(c);
                                break;
                            }
                          },
                          itemBuilder: (ctx) => [
                            const PopupMenuItem(
                                value: 'import', child: Text('导入词条')),
                            const PopupMenuItem(
                                value: 'rename', child: Text('重命名')),
                            PopupMenuItem(
                              value: 'toggle',
                              child: Text(c.isEnabled ? '停用' : '启用'),
                            ),
                            if (!c.isSystem)
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('删除',
                                    style: TextStyle(color: Colors.red)),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.library_add_outlined, size: 18),
                    label: const Text('新建词库'),
                    onPressed: () => _createCatalog(),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCatalogItem({required CatalogDefinition definition}) {
    final isSelected = _catalogType == definition.id;
    final primaryColor = Theme.of(context).colorScheme.primary;
    final icon = catalogIcon(
        definition.icon.isEmpty ? definition.id : definition.icon);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Tooltip(
        message: !_isRailExpanded ? definition.name : '',
        child: Material(
          color: isSelected ? primaryColor.withAlpha(25) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _selectCatalog(definition.id),
            child: Padding(
              padding: EdgeInsets.symmetric(
                vertical: 10,
                horizontal: _isRailExpanded ? 8 : 0,
              ),
              child: _isRailExpanded
                  ? Row(
                      children: [
                        Icon(icon,
                            size: 18,
                            color: isSelected
                                ? primaryColor
                                : Colors.grey.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            definition.name,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? primaryColor
                                  : Colors.grey.shade800,
                            ),
                          ),
                        ),
                      ],
                    )
                  : Icon(icon,
                      size: 20,
                      color: isSelected ? primaryColor : Colors.grey.shade700),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTagPane(List<String> allTags, List<FavoriteDiagnosis>? favs) {
    final notifier =
        ref.read(catalogTagsProviderFamily(_catalogType).notifier);

    void addTag() {
      final t = _newTagCtrl.text.trim();
      if (t.isEmpty) return;
      notifier.addTag(t);
      _newTagCtrl.clear();
    }

    int countOf(String? tag) {
      final list = favs ?? const <FavoriteDiagnosis>[];
      if (tag == null) return _catalogSearchable ? _rawTotalCount : list.length;
      if (tag == '__favorites__') return list.length;
      return list.where((f) => f.tags.contains(tag)).length;
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _newTagCtrl,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: '新建标签',
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => addTag(),
                ),
              ),
              const SizedBox(width: 4),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.add, size: 18),
                tooltip: '添加标签',
                onPressed: addTag,
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 8),
            children: [
              _buildTagTile(
                '全部词条',
                null,
                countOf(null),
                icon: Icons.menu_book_rounded,
                manageable: false,
              ),
              _buildTagTile(
                '已收藏',
                '__favorites__',
                countOf('__favorites__'),
                icon: Icons.bookmark_rounded,
                manageable: false,
              ),
              for (final tag in allTags)
                _buildTagTile(
                  tag,
                  tag,
                  countOf(tag),
                  icon: Icons.tag,
                  manageable: true,
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTagTile(
    String label,
    String? tag,
    int count, {
    IconData icon = Icons.tag,
    bool manageable = false,
  }) {
    final selected = _selectedTagFilter == tag;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Material(
      color: selected ? primaryColor.withAlpha(20) : Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _selectedTagFilter = tag),
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: selected
                    ? primaryColor
                    : (tag == '__favorites__' ? Colors.amber.shade700 : Colors.teal),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? primaryColor : null,
                  ),
                ),
              ),
              Text(
                '$count',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
              if (manageable)
                PopupMenuButton<String>(
                  icon: Icon(Icons.more_horiz,
                      size: 16, color: Colors.grey.shade600),
                  padding: EdgeInsets.zero,
                  onSelected: (action) {
                    if (action == 'rename') {
                      _renameTagDialog(tag!);
                    } else if (action == 'delete') {
                      _confirmDeleteTag(tag!);
                    }
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'rename', child: Text('重命名')),
                    PopupMenuItem(value: 'delete', child: Text('删除')),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryList(AsyncValue<List<FavoriteDiagnosis>> favsAsync) {
    return favsAsync.when(
      data: (favs) {
        _favKeys = favs.map((f) => '${f.code}|${f.name}').toSet();

        // 1. 如果选中 null（全部词条），且当前库支持底库检索：展示带置顶检索栏的全量知识库
        if (_selectedTagFilter == null && _catalogSearchable) {
          return _buildRawList();
        }

        // 2. 如果选中 '__favorites__'：展示所有已收藏词条
        // 3. 如果选中具体自定义标签：展示包含该标签的已收藏词条
        final List<FavoriteDiagnosis> listToDisplay;
        if (_selectedTagFilter == null || _selectedTagFilter == '__favorites__') {
          listToDisplay = favs;
        } else {
          listToDisplay = favs.where((f) => f.tags.contains(_selectedTagFilter)).toList();
        }

        if (listToDisplay.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _selectedTagFilter == '__favorites__' ? Icons.bookmark_outline : Icons.star_outline,
                  size: 56,
                  color: Colors.grey,
                ),
                const SizedBox(height: 14),
                Text(
                  _selectedTagFilter == '__favorites__'
                      ? '暂无已收藏词条'
                      : '标签「$_selectedTagFilter」下暂无词条',
                  style: const TextStyle(color: Colors.grey, fontSize: 15),
                ),
                const SizedBox(height: 6),
                Text(
                  '可在左侧切换到「全部词条」浏览并点击收藏打标',
                  style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                ),
              ],
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 80),
          itemCount: listToDisplay.length,
          separatorBuilder: (context, index) => const SizedBox(height: 8),
          itemBuilder: (context, index) => _buildDiagnosisCard(listToDisplay[index]),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(child: Text('加载失败: $err')),
    );
  }

  Widget _buildRawList() {
    final hasSearchQuery = _rawSearchCtrl.text.trim().isNotEmpty;
    final displayList = hasSearchQuery ? _rawSearchResults : _rawItems;

    return Column(
      children: [
        // HIS 风格置顶快速搜索框
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
          child: TextField(
            controller: _rawSearchCtrl,
            decoration: InputDecoration(
              hintText: '输入拼音首字母、汉字或编码模糊检索...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _rawSearchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, size: 18),
                      onPressed: () {
                        _rawSearchCtrl.clear();
                        _onRawSearchChanged('');
                      },
                    )
                  : null,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              isDense: true,
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
            ),
            onChanged: _onRawSearchChanged,
          ),
        ),
        if (_isRawSearching)
          const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: (displayList.isEmpty && (_rawLoading || _isRawSearching))
              ? const Center(child: CircularProgressIndicator())
              : displayList.isEmpty
                  ? Center(
                      child: Text(
                        hasSearchQuery ? '未找到相关词条' : '暂无词条',
                        style: const TextStyle(color: Colors.grey),
                      ),
                    )
                  : ListView.separated(
                      controller: hasSearchQuery ? null : _rawScrollCtrl,
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 80),
                      itemCount: displayList.length + (!hasSearchQuery && _rawHasMore ? 1 : 0),
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        if (index >= displayList.length) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }

                        final item = displayList[index];
                        final isFav = _favKeys.contains('${item.code}|${item.name}');

                        return Card(
                          elevation: 0,
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.35),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Theme.of(context)
                                  .colorScheme
                                  .outline
                                  .withValues(alpha: 0.18),
                            ),
                          ),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _openRawItemDetail(item),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          item.code,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: Colors.blue[800],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          item.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w600,
                                            fontSize: 14.5,
                                          ),
                                        ),
                                        if (item.version.isNotEmpty) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            item.version,
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Colors.grey.shade600,
                                            ),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: Icon(
                                      isFav ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
                                      color: isFav ? Colors.amber.shade700 : Colors.grey,
                                      size: 24,
                                    ),
                                    tooltip: isFav ? '已收藏 · 点击查看' : '收藏并打标签',
                                    onPressed: () => _openRawItemDetail(item),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildDiagnosisCard(FavoriteDiagnosis item) {
    return Card(
      elevation: 0,
      color: Theme.of(context)
          .colorScheme
          .surfaceContainerHighest
          .withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.18),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openCustomAddDialog(item),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center, // 上下绝对垂直居中！
            children: [
              // Left Content: 3-line Layout
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Line 1: Normal-sized ICD Code text (自然无徽章)
                    Text(
                      item.code.isEmpty ? '无编码' : item.code,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color:
                            item.code.isEmpty ? Colors.grey : Colors.blue[800],
                      ),
                    ),
                    const SizedBox(height: 4),

                    // Line 2: Full Diagnosis Name (Bold, 15sp, clean wrap)
                    Text(
                      item.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // Line 3: Version badge + Tags + Note
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        // Version pill
                        if (item.version.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: _versionBgColor(item.version),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              item.version,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: _versionTextColor(item.version),
                              ),
                            ),
                          ),

                        // Tags
                        for (final tag in item.tags)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1.5),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(
                                color: Colors.teal.withValues(alpha: 0.25),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.tag,
                                    size: 10, color: Colors.teal),
                                const SizedBox(width: 1),
                                Text(
                                  tag,
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.teal[800],
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Note
                        if (item.note.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(left: 2),
                            child: Text(
                              '(${item.note})',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // Right: Three-dot menu button, vertically centered!
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_horiz, size: 22),
                padding: EdgeInsets.zero,
                onSelected: (action) {
                  if (action == 'edit') {
                    _openCustomAddDialog(item);
                  } else if (action == 'delete') {
                    _deleteFavorite(item);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 18),
                        SizedBox(width: 8),
                        Text('修改词条与标签'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete_outline,
                            size: 18, color: Colors.red),
                        SizedBox(width: 8),
                        Text('删除此词条', style: TextStyle(color: Colors.red)),
                      ],
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

  Color _versionBgColor(String version) {
    if (version.contains('国临')) return Colors.blue.withValues(alpha: 0.12);
    if (version.contains('医保2.0')) return Colors.purple.withValues(alpha: 0.12);
    if (version.contains('医保1.0')) return Colors.orange.withValues(alpha: 0.12);
    return Colors.grey.withValues(alpha: 0.15);
  }

  Color _versionTextColor(String version) {
    if (version.contains('国临')) return Colors.blue[800]!;
    if (version.contains('医保2.0')) return Colors.purple[800]!;
    if (version.contains('医保1.0')) return Colors.orange[800]!;
    return Colors.grey[800]!;
  }
}
