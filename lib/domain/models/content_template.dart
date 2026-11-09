import 'dart:convert';
import 'package:uuid/uuid.dart';

import 'catalog_mention.dart';

const _uuid = Uuid();

/// Content for a single slot of a structure template.
/// - [examples]: few-shot samples ("照着学")
/// - [guidance]: constraints / instructions ("必须遵守")
/// - [catalogRefs]: typed references to catalog tags (catalog id + tag)
/// - [catalogTags]: legacy tag-only list kept for backward compatibility
class SlotContent {
  final List<String> examples;
  final String guidance;
  final List<CatalogMentionRef> catalogRefs;
  final List<String> catalogTags;

  const SlotContent({
    this.examples = const [],
    this.guidance = '',
    this.catalogRefs = const [],
    this.catalogTags = const [],
  });

  bool get isEmpty =>
      guidance.trim().isEmpty &&
      examples.every((e) => e.trim().isEmpty) &&
      catalogRefs.isEmpty &&
      catalogTags.isEmpty;

  SlotContent copyWith({
    List<String>? examples,
    String? guidance,
    List<CatalogMentionRef>? catalogRefs,
    List<String>? catalogTags,
  }) =>
      SlotContent(
        examples: examples ?? this.examples,
        guidance: guidance ?? this.guidance,
        catalogRefs: catalogRefs ?? this.catalogRefs,
        catalogTags: catalogTags ?? this.catalogTags,
      );

  Map<String, dynamic> toJson() => {
        if (examples.isNotEmpty) 'examples': examples,
        if (guidance.isNotEmpty) 'guidance': guidance,
        if (catalogRefs.isNotEmpty)
          'catalog_refs': [
            for (final r in catalogRefs)
              {'type': r.catalogType, 'tag': r.tag},
          ],
        if (catalogTags.isNotEmpty) 'catalog_tags': catalogTags,
      };

  factory SlotContent.fromJson(Map<String, dynamic> json) {
    final legacyTags = (json['catalog_tags'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const <String>[];

    final rawRefs = json['catalog_refs'];
    final refs = <CatalogMentionRef>[];
    if (rawRefs is List) {
      for (final item in rawRefs) {
        if (item is Map) {
          final type = item['type']?.toString().trim() ?? '';
          final tag = item['tag']?.toString().trim() ?? '';
          if (tag.isNotEmpty) {
            refs.add(CatalogMentionRef(catalogType: type, tag: tag));
          }
        }
      }
    }
    if (refs.isEmpty && legacyTags.isNotEmpty) {
      // Type is resolved later by the editor using the slot's catalog binding.
      for (final tag in legacyTags) {
        refs.add(CatalogMentionRef(catalogType: '', tag: tag));
      }
    }

    final tags = legacyTags.isNotEmpty
        ? legacyTags
        : refs.map((r) => r.tag).toList();

    return SlotContent(
      examples: (json['examples'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      guidance: json['guidance'] as String? ?? '',
      catalogRefs: refs,
      catalogTags: tags,
    );
  }
}

/// A content template (内容模板): guidance + examples for one structure template.
class ContentTemplate {
  final String id;
  final String structureTemplateId;
  final String name;

  /// 整体规范: tone, writing rules, "don't fabricate", etc.
  final String globalGuidance;

  /// 整份示范病历: a complete sample record, style reference.
  final String fullExample;

  /// Per-slot content, keyed by slot key.
  final Map<String, SlotContent> slots;
  final DateTime createdAt;
  final DateTime updatedAt;

  ContentTemplate({
    String? id,
    required this.structureTemplateId,
    required this.name,
    this.globalGuidance = '',
    this.fullExample = '',
    Map<String, SlotContent>? slots,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        slots = slots ?? {},
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Number of slots that have any example or guidance filled in.
  int get filledSlotCount => slots.values.where((s) => !s.isEmpty).length;

  ContentTemplate copyWith({
    String? name,
    String? globalGuidance,
    String? fullExample,
    Map<String, SlotContent>? slots,
  }) =>
      ContentTemplate(
        id: id,
        structureTemplateId: structureTemplateId,
        name: name ?? this.name,
        globalGuidance: globalGuidance ?? this.globalGuidance,
        fullExample: fullExample ?? this.fullExample,
        slots: slots ?? this.slots,
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );

  Map<String, dynamic> _slotDataJson() => {
        for (final e in slots.entries)
          if (!e.value.isEmpty) e.key: e.value.toJson(),
      };

  Map<String, dynamic> toMap() => {
        'id': id,
        'structure_template_id': structureTemplateId,
        'name': name,
        'global_guidance': globalGuidance,
        'full_example': fullExample,
        'slot_data': jsonEncode(_slotDataJson()),
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ContentTemplate.fromMap(Map<String, dynamic> map) {
    final raw = jsonDecode(map['slot_data'] as String? ?? '{}')
        as Map<String, dynamic>;
    return ContentTemplate(
      id: map['id'] as String,
      structureTemplateId: map['structure_template_id'] as String,
      name: map['name'] as String,
      globalGuidance: map['global_guidance'] as String? ?? '',
      fullExample: map['full_example'] as String? ?? '',
      slots: {
        for (final e in raw.entries)
          e.key: SlotContent.fromJson(e.value as Map<String, dynamic>),
      },
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }
}
