import '../../../domain/models/catalog_entry.dart';
import '../../../domain/models/icd_diagnosis.dart';
import '../../repositories/catalog_entry_repository.dart';
import '../icd_service.dart';

/// Generic lookup result from a bundled or managed catalog.
class CatalogLookupEntry {
  final String catalogType;
  final String code;
  final String name;
  final String version;
  final String note;
  final List<String> tags;

  const CatalogLookupEntry({
    required this.catalogType,
    required this.code,
    required this.name,
    this.version = '',
    this.note = '',
    this.tags = const [],
  });

  List<String> get versionList => version
      .split(' / ')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();
}

/// Abstraction over bundled knowledge bases and user-managed entries.
abstract class CatalogSource {
  String get catalogType;
  bool get supportsBrowse;

  Future<List<CatalogLookupEntry>> search(String query, {int limit = 50});
  Future<List<CatalogLookupEntry>> getPaged({int offset = 0, int limit = 50});
  Future<int> getTotalCount();
}

/// ICD-10 bundled SQLite knowledge base (diagnosis).
class IcdCatalogSource implements CatalogSource {
  final IcdService _icd;

  IcdCatalogSource(this._icd);

  @override
  String get catalogType => 'diagnosis';

  @override
  bool get supportsBrowse => true;

  CatalogLookupEntry _map(IcdDiagnosis d) => CatalogLookupEntry(
        catalogType: catalogType,
        code: d.code,
        name: d.name,
        version: d.version,
        tags: const [],
      );

  @override
  Future<List<CatalogLookupEntry>> search(String query, {int limit = 50}) async {
    final results = await _icd.search(query, limit: limit);
    return results.map(_map).toList();
  }

  @override
  Future<List<CatalogLookupEntry>> getPaged(
      {int offset = 0, int limit = 50}) async {
    final results = await _icd.getPaged(offset: offset, limit: limit);
    return results.map(_map).toList();
  }

  @override
  Future<int> getTotalCount() => _icd.getTotalCount();
}

/// User-managed entries stored in `catalog_entries`.
class ManagedCatalogSource implements CatalogSource {
  final CatalogEntryRepository _repo;
  @override
  final String catalogType;

  ManagedCatalogSource(this._repo, this.catalogType);

  @override
  bool get supportsBrowse => true;

  CatalogLookupEntry _map(CatalogEntry e) => CatalogLookupEntry(
        catalogType: catalogType,
        code: e.code,
        name: e.name,
        version: e.version,
        note: e.note,
        tags: e.tags,
      );

  @override
  Future<List<CatalogLookupEntry>> search(String query, {int limit = 50}) async {
    final results = await _repo.search(catalogType, query, limit: limit);
    return results.map(_map).toList();
  }

  @override
  Future<List<CatalogLookupEntry>> getPaged(
      {int offset = 0, int limit = 50}) async {
    final results =
        await _repo.getPaged(catalogType, offset: offset, limit: limit);
    return results.map(_map).toList();
  }

  @override
  Future<int> getTotalCount() => _repo.getTotalCount(catalogType);
}
