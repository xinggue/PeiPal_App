import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/catalog/catalog_source.dart';
import '../../../domain/models/catalog_definition.dart';
import '../../../domain/models/catalog_entry.dart';
import '../../../providers/providers.dart';

/// HIS-like Diagnostic Input & Super-Fuzzy Search Picker Component.
class HisDiagnosisPicker extends ConsumerStatefulWidget {
  final String catalogId;
  final ValueChanged<String>? onSelectedText; // 触发选中词条文本
  final void Function(String code, String name, String version)? onSelectedDetail;

  const HisDiagnosisPicker({
    super.key,
    this.catalogId = 'diagnosis',
    this.onSelectedText,
    this.onSelectedDetail,
  });

  @override
  ConsumerState<HisDiagnosisPicker> createState() => _HisDiagnosisPickerState();
}

class _HisDiagnosisPickerState extends ConsumerState<HisDiagnosisPicker> {
  final _searchCtrl = TextEditingController();
  final _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  List<CatalogLookupEntry> _searchResults = [];
  bool _isSearching = false;
  Set<String> _favKeys = {}; // set of "code|name"

  @override
  void initState() {
    super.initState();
    _loadFavorites();
    Future.delayed(const Duration(milliseconds: 180), () {
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
        .read(catalogEntryRepositoryProvider)
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
    _debounceTimer = Timer(const Duration(milliseconds: 150), () async {
      final source =
          await ref.read(catalogSourceProvider(widget.catalogId).future);
      final results = await source.search(query.trim(), limit: 40);
      if (mounted) {
        setState(() {
          _searchResults = results;
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _toggleFavorite(CatalogLookupEntry item) async {
    final repo = ref.read(catalogEntryRepositoryProvider);
    final key = '${item.code}|${item.name}';
    final isFav = _favKeys.contains(key);

    if (isFav) {
      await repo.deleteByCodeAndName(item.code, item.name,
          catalogType: widget.catalogId);
      setState(() => _favKeys.remove(key));
      if (mounted) {
        showAppToast(context, '已从词库移除：${item.name}');
      }
    } else {
      final fav = CatalogEntry(
        catalogType: widget.catalogId,
        code: item.code,
        name: item.name,
        version: item.version,
      );
      await repo.insert(fav);
      setState(() => _favKeys.add(key));
      if (mounted) {
        showAppToast(context, '已加入词库：${item.name}');
      }
    }
    ref.invalidate(catalogEntriesProvider(widget.catalogId));
    ref.invalidate(favoriteDiagnosesProvider);
  }

  void _selectDiagnosis(String code, String name, String version) {
    widget.onSelectedText?.call('$name ($code)');
    widget.onSelectedDetail?.call(code, name, version);
  }

  @override
  Widget build(BuildContext context) {
    final catalogDefinition = ref
            .watch(catalogsProvider)
            .valueOrNull
            ?.where((c) => c.id == widget.catalogId)
            .firstOrNull;
    final canFavorite = catalogDefinition?.sourceKind ==
        CatalogSourceKind.bundledSqlite;
    final favsAsync = ref.watch(catalogEntriesProvider(widget.catalogId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        // HIS Search Input Box
        TextField(
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
            labelText: '检索标准词条',
            hintText: '拼音首字母、汉字或编码...',
            border: const OutlineInputBorder(),
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          ),
          onChanged: _onQueryChanged,
        ),
        const SizedBox(height: 8),

        // Quick Favorites Chip Bar
        favsAsync.when(
          data: (favs) {
            if (favs.isEmpty) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const Icon(Icons.star, size: 15, color: Colors.amber),
                    const SizedBox(width: 4),
                    const Text('常用：',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    for (final f in favs)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ActionChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(f.name, style: const TextStyle(fontSize: 12)),
                          onPressed: () => _selectDiagnosis(f.code, f.name, f.version),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (err, stack) => const SizedBox.shrink(),
        ),

        // Results List
        if (_isSearching)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_searchCtrl.text.trim().isNotEmpty && _searchResults.isEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const Text('未找到匹配的标准词条',
                    style: TextStyle(color: Colors.grey, fontSize: 13)),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: Text('使用自定义词条「${_searchCtrl.text.trim()}」'),
                  onPressed: () => _selectDiagnosis('', _searchCtrl.text.trim(), '自定义'),
                ),
              ],
            ),
          )
        else
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _searchResults.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _searchResults[index];
                final isFav = _favKeys.contains('${item.code}|${item.name}');

                return ListTile(
                  dense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
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
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 14),
                  ),
                  subtitle: Wrap(
                    spacing: 4,
                    runSpacing: 2,
                    children: item.versionList.map((ver) {
                      final (bgColor, fgColor) = _versionColors(ver);
                      return Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
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
                  trailing: !canFavorite
                      ? null
                      : IconButton(
                    icon: Icon(
                      isFav ? Icons.star : Icons.star_border,
                      color: isFav ? Colors.amber : Colors.grey,
                      size: 22,
                    ),
                    tooltip: isFav ? '移出标准词条库' : '加入标准词条库',
                    onPressed: () => _toggleFavorite(item),
                  ),
                  onTap: () =>
                      _selectDiagnosis(item.code, item.name, item.version),
                );
              },
            ),
          ),
      ],
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
