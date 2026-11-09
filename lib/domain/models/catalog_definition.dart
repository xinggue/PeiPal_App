/// How a catalog obtains its entries.
enum CatalogSourceKind {
  /// Entries are user-managed rows in `catalog_entries`.
  managed,

  /// Entries come from a bundled read-only SQLite knowledge base.
  bundledSqlite,
}

/// A standard catalog (词库): diagnosis, procedure, TCM, pathology, legal, etc.
class CatalogDefinition {
  final String id;
  final String name;
  final String description;
  final CatalogSourceKind sourceKind;
  final String sourceAsset;
  final String icon;
  final int color;
  final bool searchable;
  final bool isEnabled;
  final int sortOrder;
  final bool isSystem;
  final DateTime createdAt;
  final DateTime updatedAt;

  const CatalogDefinition({
    required this.id,
    required this.name,
    this.description = '',
    this.sourceKind = CatalogSourceKind.managed,
    this.sourceAsset = '',
    this.icon = '',
    this.color = 0,
    this.searchable = false,
    this.isEnabled = true,
    this.sortOrder = 0,
    this.isSystem = false,
    required this.createdAt,
    required this.updatedAt,
  });

  bool get hasBundledSource =>
      sourceKind == CatalogSourceKind.bundledSqlite && sourceAsset.isNotEmpty;

  CatalogDefinition copyWith({
    String? name,
    String? description,
    CatalogSourceKind? sourceKind,
    String? sourceAsset,
    String? icon,
    int? color,
    bool? searchable,
    bool? isEnabled,
    int? sortOrder,
  }) =>
      CatalogDefinition(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        sourceKind: sourceKind ?? this.sourceKind,
        sourceAsset: sourceAsset ?? this.sourceAsset,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        searchable: searchable ?? this.searchable,
        isEnabled: isEnabled ?? this.isEnabled,
        sortOrder: sortOrder ?? this.sortOrder,
        isSystem: isSystem,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  String get _sourceKindValue => switch (sourceKind) {
        CatalogSourceKind.managed => 'managed',
        CatalogSourceKind.bundledSqlite => 'bundled_sqlite',
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'description': description,
        'source_kind': _sourceKindValue,
        'source_asset': sourceAsset,
        'icon': icon,
        'color': color,
        'searchable': searchable ? 1 : 0,
        'is_enabled': isEnabled ? 1 : 0,
        'sort_order': sortOrder,
        'is_system': isSystem ? 1 : 0,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory CatalogDefinition.fromMap(Map<String, dynamic> map) {
    final rawSource = map['source_kind']?.toString();
    final sourceKind = switch (rawSource) {
      'bundled_sqlite' || 'bundledSqlite' => CatalogSourceKind.bundledSqlite,
      _ => CatalogSourceKind.managed,
    };
    return CatalogDefinition(
      id: map['id'] as String,
      name: map['name'] as String? ?? '',
      description: map['description'] as String? ?? '',
      sourceKind: sourceKind,
      sourceAsset: map['source_asset'] as String? ?? '',
      icon: map['icon'] as String? ?? '',
      color: map['color'] as int? ?? 0,
      searchable: (map['searchable'] as int? ?? 0) != 0,
      isEnabled: (map['is_enabled'] as int? ?? 1) != 0,
      sortOrder: map['sort_order'] as int? ?? 0,
      isSystem: (map['is_system'] as int? ?? 0) != 0,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
