import 'dart:convert';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// Hard-coded placeholder tags seeded by very old versions. They are filtered
/// out so they never show up as real catalog tags.
const kLegacyPlaceholderTags = <String>{
  '通用词条',
  '通用手术',
  '通用常用诊断',
  '常用词条',
  '高频词条',
  '高频手术',
};

bool isLegacyPlaceholderTag(String tag) {
  final t = tag.trim();
  if (t.isEmpty) return true;
  if (kLegacyPlaceholderTags.contains(t)) return true;
  return t.startsWith('分类') || t.startsWith('标签');
}

/// A user-managed entry in a standard catalog (诊断、手术、中医、病理、法律条文等).
///
/// [catalogType] selects which catalog it belongs to (e.g. diagnosis, procedure, tcm).
class CatalogEntry {
  final String id;
  final String catalogType;
  final String code;
  final String name;
  final String version;
  final String note;
  final List<String> tags;
  final int order;
  final DateTime createdAt;
  final DateTime updatedAt;

  CatalogEntry({
    String? id,
    this.catalogType = 'diagnosis',
    required this.code,
    required this.name,
    this.version = '',
    this.note = '',
    List<String>? tags,
    this.order = 0,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        tags = tags ?? const [],
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  CatalogEntry copyWith({
    String? catalogType,
    String? code,
    String? name,
    String? version,
    String? note,
    List<String>? tags,
    int? order,
  }) =>
      CatalogEntry(
        id: id,
        catalogType: catalogType ?? this.catalogType,
        code: code ?? this.code,
        name: name ?? this.name,
        version: version ?? this.version,
        note: note ?? this.note,
        tags: tags ?? this.tags,
        order: order ?? this.order,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'catalog_type': catalogType,
        'code': code,
        'name': name,
        'version': version,
        'note': note,
        'tags': jsonEncode(tags),
        'sort_order': order,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// JSON used in generic backup envelopes.
  Map<String, dynamic> toJson() => toMap();

  factory CatalogEntry.fromMap(Map<String, dynamic> map) {
    List<String> parsedTags = const [];
    final rawTags = map['tags'];
    if (rawTags is String && rawTags.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawTags);
        if (decoded is List) {
          parsedTags = decoded.map((e) => e.toString()).toList();
        }
      } catch (_) {}
    } else if (rawTags is List) {
      parsedTags = rawTags.map((e) => e.toString()).toList();
    }
    parsedTags = parsedTags
        .where((tag) => !isLegacyPlaceholderTag(tag))
        .toList();

    final rawType = map['catalog_type'] ?? map['catalog_id'];
    final catalogType = rawType is String && rawType.trim().isNotEmpty
        ? rawType.trim()
        : 'diagnosis';

    return CatalogEntry(
      id: map['id'] as String,
      catalogType: catalogType,
      code: map['code'] as String? ?? '',
      name: map['name'] as String? ?? '',
      version: map['version'] as String? ?? '',
      note: map['note'] as String? ?? '',
      tags: parsedTags,
      order: map['sort_order'] as int? ?? 0,
      createdAt: DateTime.tryParse(map['created_at']?.toString() ?? '') ??
          DateTime.now(),
      updatedAt: DateTime.tryParse(map['updated_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }

  factory CatalogEntry.fromJson(Map<String, dynamic> json) =>
      CatalogEntry.fromMap(json);
}

/// Backward-compatible alias. New code should use [CatalogEntry].
typedef FavoriteDiagnosis = CatalogEntry;
