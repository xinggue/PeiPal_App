import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/catalog/catalog_source.dart';
import '../../../providers/providers.dart';
import '../../widgets/diagnosis/catalog_entry_detail_dialog.dart';

/// Full-screen Diagnosis Search Page (避免底部弹窗与系统输入法冲突卡顿).
class DiagnosisSearchPage extends ConsumerStatefulWidget {
  final String catalogId;

  const DiagnosisSearchPage({super.key, this.catalogId = 'diagnosis'});

  @override
  ConsumerState<DiagnosisSearchPage> createState() =>
      _DiagnosisSearchPageState();
}

class _DiagnosisSearchPageState extends ConsumerState<DiagnosisSearchPage> {
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  List<CatalogLookupEntry> _searchResults = [];
  bool _isSearching = false;
  Set<String> _favKeys = {};

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    Future.delayed(const Duration(milliseconds: 260), () {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchFocusNode.dispose();
    _searchCtrl.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadFavorites() async {
    final favs = await ref
        .read(favoriteDiagnosisRepositoryProvider)
        .getAll(catalogType: widget.catalogId);
    if (mounted) {
      setState(() {
        _favKeys = favs.map((f) => '${f.code}|${f.name}').toSet();
      });
    }
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() => _isSearching = true);
    _debounceTimer = Timer(const Duration(milliseconds: 100), () async {
      final source =
          await ref.read(catalogSourceProvider(widget.catalogId).future);
      final results = await source.search(query.trim(), limit: 50);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _openItemDetail(CatalogLookupEntry item) async {
    final repo = ref.read(favoriteDiagnosisRepositoryProvider);
    final key = '${item.code}|${item.name}';
    final existingFav = await repo.findByCodeAndName(item.code, item.name,
        catalogType: widget.catalogId);
    final isFav = existingFav != null;

    if (!mounted) return;
    final changed = await CatalogEntryDetailDialog.show(
      context,
      ref,
      catalogType: widget.catalogId,
      code: item.code,
      name: item.name,
      version: existingFav?.version ?? item.version,
      note: existingFav?.note ?? '',
      initialTags: existingFav?.tags ?? const [],
      isFavorite: isFav,
    );

    if (changed != null && mounted) {
      if (changed == true) {
        setState(() => _favKeys.add(key));
      } else if (changed == false) {
        setState(() => _favKeys.remove(key));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogName = ref
            .watch(catalogsProvider)
            .valueOrNull
            ?.where((c) => c.id == widget.catalogId)
            .firstOrNull
            ?.name ??
        '标准词条';
    return Scaffold(
      appBar: AppBar(
        title: Text('检索$catalogName'),
      ),
      body: Column(
        children: [
          // Prompt Banner (人话提示：挑选符合自己医院的版本，可收藏后二次魔改)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            color: Colors.amber.withValues(alpha: 0.12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.info_outline, size: 16, color: Colors.brown),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '请选择符合您所用编码的词条。如果没有完全符合的，可先点击星标收藏，收藏后可自由修改名称与代码，或直接手动新建录入。',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.brown[800],
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Search Input Bar
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: TextField(
              controller: _searchCtrl,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search, size: 20),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          _onQueryChanged('');
                        },
                      )
                    : null,
                hintText: '输入拼音首字母、汉字或编码...',
                border: const OutlineInputBorder(),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: _onQueryChanged,
            ),
          ),

          // Search Results
          Expanded(
            child: _buildResultsView(),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsView() {
    if (_isSearching) {
      return const Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (_searchCtrl.text.trim().isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.manage_search, size: 64, color: Colors.grey),
            const SizedBox(height: 12),
            Text(
              '支持名称、拼音首字母或编码检索',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600], fontSize: 13, height: 1.5),
            ),
          ],
        ),
      );
    }

    if (_searchResults.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('未找到匹配的标准词条',
                style: TextStyle(color: Colors.grey, fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              '如需自编码，可在上一页点击右上角「+」直接手动新建录入',
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        final isFav = _favKeys.contains('${item.code}|${item.name}');

        return ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          leading: Text(
            item.code,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: Colors.blue,
            ),
          ),
          title: Text(
            item.name,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              children: item.versionList.map((ver) {
                final (bgColor, fgColor) = _versionColors(ver);
                return Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: bgColor,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    ver,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w500,
                        color: fgColor),
                  ),
                );
              }).toList(),
            ),
          ),
          trailing: IconButton(
            icon: Icon(
              isFav ? Icons.star : Icons.star_border,
              color: isFav ? Colors.amber : Colors.grey,
              size: 24,
            ),
            tooltip: isFav ? '已收藏 · 点击编辑' : '点击收藏并打标签',
            onPressed: () => _openItemDetail(item),
          ),
          onTap: () => _openItemDetail(item),
        );
      },
    );
  }

  (Color, Color) _versionColors(String version) {
    if (version.contains('国临')) {
      return (Colors.blue.withValues(alpha: 0.12), Colors.blue[800]!);
    }
    if (version.contains('医保2.0')) {
      return (Colors.purple.withValues(alpha: 0.12), Colors.purple[800]!);
    }
    if (version.contains('医保1.0')) {
      return (Colors.orange.withValues(alpha: 0.12), Colors.orange[800]!);
    }
    return (Colors.grey.withValues(alpha: 0.15), Colors.grey[800]!);
  }
}
