import 'dart:convert';
import 'package:uuid/uuid.dart';
import 'pipeline_graph.dart';
import 'typing_profile.dart';

const _uuid = Uuid();

enum SlotType { text, dropdown, date, checkbox, multiline, typedChoice }

enum ConditionOperator {
  equals,
  notEquals,
  contains,
  notEmpty,
  isEmpty,
  greaterThan,
  lessThan,
  inList,
}

class Condition {
  final String field;
  final ConditionOperator operator;
  final String? value;
  final List<String>? valueList;

  const Condition({
    required this.field,
    required this.operator,
    this.value,
    this.valueList,
  });

  bool evaluate(Map<String, dynamic> values) {
    final fieldValue = values[field];
    switch (operator) {
      case ConditionOperator.equals:
        return fieldValue?.toString() == value;
      case ConditionOperator.notEquals:
        return fieldValue?.toString() != value;
      case ConditionOperator.contains:
        return fieldValue?.toString().contains(value ?? '') ?? false;
      case ConditionOperator.notEmpty:
        return fieldValue != null && fieldValue.toString().isNotEmpty;
      case ConditionOperator.isEmpty:
        return fieldValue == null || fieldValue.toString().isEmpty;
      case ConditionOperator.greaterThan:
        final numField = num.tryParse(fieldValue?.toString() ?? '');
        final numVal = num.tryParse(value ?? '');
        if (numField != null && numVal != null) return numField > numVal;
        return false;
      case ConditionOperator.lessThan:
        final numField = num.tryParse(fieldValue?.toString() ?? '');
        final numVal = num.tryParse(value ?? '');
        if (numField != null && numVal != null) return numField < numVal;
        return false;
      case ConditionOperator.inList:
        return valueList?.contains(fieldValue?.toString()) ?? false;
    }
  }

  Map<String, dynamic> toJson() => {
        'field': field,
        'operator': operator.name,
        if (value != null) 'value': value,
        if (valueList != null) 'value_list': valueList,
      };

  factory Condition.fromJson(Map<String, dynamic> json) => Condition(
        field: json['field'] as String,
        operator: ConditionOperator.values.byName(json['operator'] as String),
        value: json['value'] as String?,
        valueList: json['value_list'] != null
            ? List<String>.from(json['value_list'])
            : null,
      );
}

class TemplateSlot {
  final String key;
  final String label;
  final SlotType type;
  final bool required;
  final String? defaultValue;
  final List<String>? options;
  final List<String> preKeys;
  final List<String> postKeys;
  final int order;
  final Condition? condition;
  final String? catalogType; // e.g. 'diagnosis', null for plain text

  const TemplateSlot({
    required this.key,
    required this.label,
    required this.type,
    this.required = false,
    this.defaultValue,
    this.options,
    this.preKeys = const [],
    this.postKeys = const [],
    this.order = 0,
    this.condition,
    this.catalogType,
  });

  /// Nullable fields can be reset with the matching `clear*` flag.
  TemplateSlot copyWith({
    String? key,
    String? label,
    SlotType? type,
    bool? required,
    String? defaultValue,
    bool clearDefaultValue = false,
    List<String>? options,
    bool clearOptions = false,
    List<String>? preKeys,
    List<String>? postKeys,
    int? order,
    Condition? condition,
    bool clearCondition = false,
    String? catalogType,
    bool clearCatalogType = false,
  }) =>
      TemplateSlot(
        key: key ?? this.key,
        label: label ?? this.label,
        type: type ?? this.type,
        required: required ?? this.required,
        defaultValue:
            clearDefaultValue ? null : (defaultValue ?? this.defaultValue),
        options: clearOptions ? null : (options ?? this.options),
        preKeys: preKeys ?? this.preKeys,
        postKeys: postKeys ?? this.postKeys,
        order: order ?? this.order,
        condition: clearCondition ? null : (condition ?? this.condition),
        catalogType:
            clearCatalogType ? null : (catalogType ?? this.catalogType),
      );

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'type': type.name,
        'required': required,
        if (defaultValue != null) 'default_value': defaultValue,
        if (options != null) 'options': options,
        if (preKeys.isNotEmpty) 'pre_keys': preKeys,
        if (postKeys.isNotEmpty) 'post_keys': postKeys,
        'order': order,
        if (condition != null) 'condition': condition!.toJson(),
        if (catalogType != null) 'catalog_type': catalogType,
      };

  factory TemplateSlot.fromJson(Map<String, dynamic> json) => TemplateSlot(
        key: json['key'] as String,
        label: json['label'] as String,
        type: SlotType.values.byName(json['type'] as String),
        required: json['required'] as bool? ?? false,
        defaultValue: json['default_value'] as String?,
        options: json['options'] != null
            ? List<String>.from(json['options'])
            : null,
        preKeys: _parseKeys(json, 'pre_keys'),
        postKeys: _parseKeys(json, 'post_keys', oldNavKey: 'nav_after'),
        order: json['order'] as int? ?? 0,
        condition: json['condition'] != null
            ? Condition.fromJson(json['condition'])
            : null,
        catalogType: json['catalog_type'] as String?,
      );

  /// Parses key list from JSON, with backward compatibility for old format.
  static List<String> _parseKeys(Map<String, dynamic> json, String key,
      {String? oldNavKey}) {
    final list = json[key];
    if (list is List) return list.cast<String>();
    if (oldNavKey != null && json.containsKey(oldNavKey)) {
      final nav = json[oldNavKey] as String?;
      if (nav == 'tab') return ['{TAB}'];
      if (nav == 'enter') return ['{ENTER}'];
    }
    return [];
  }
}

class Template {
  final String id;
  final String name;
  final String version;
  final List<TemplateSlot> slots;
  PipelineGraph pipeline;

  /// Typing schemes (输入方案). Always has at least one ("默认").
  final List<TypingProfile> typingProfiles;
  final DateTime createdAt;
  final DateTime updatedAt;

  Template({
    String? id,
    required this.name,
    this.version = '1.0',
    List<TemplateSlot>? slots,
    PipelineGraph? pipeline,
    List<TypingProfile>? typingProfiles,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : id = id ?? _uuid.v4(),
        slots = slots ?? [],
        pipeline = pipeline ?? PipelineGraph(),
        typingProfiles = (typingProfiles == null || typingProfiles.isEmpty)
            ? [TypingProfile(name: '默认')]
            : typingProfiles,
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  List<TemplateSlot> get sortedSlots =>
      List<TemplateSlot>.from(slots)..sort((a, b) => a.order.compareTo(b.order));

  List<TemplateSlot> activeSlots(Map<String, dynamic> values) =>
      sortedSlots.where((s) {
        if (s.condition == null) return true;
        return s.condition!.evaluate(values);
      }).toList();

  String buildBleOutput(Map<String, dynamic> values) {
    final buffer = StringBuffer();
    final active = activeSlots(values);

    for (int i = 0; i < active.length; i++) {
      final slot = active[i];
      final value = values[slot.key]?.toString() ?? slot.defaultValue ?? '';

      // Pre-keys: any control sequence needed to reach this slot
      for (final key in slot.preKeys) {
        buffer.write(key);
      }

      if (slot.type == SlotType.dropdown && slot.options != null) {
        // Dropdown selection via arrow keys + ENTER
        final targetIdx = slot.options!.indexOf(value);
        final defaultIdx = slot.options!.indexOf(slot.defaultValue ?? '');
        final diff = defaultIdx >= 0 && targetIdx >= 0
            ? targetIdx - defaultIdx
            : 0;
        if (diff < 0) {
          for (int j = 0; j < -diff; j++) {
            buffer.write('{UP}');
          }
        } else if (diff > 0) {
          for (int j = 0; j < diff; j++) {
            buffer.write('{DOWN}');
          }
        }
        buffer.write('{ENTER}');
      } else if (slot.type == SlotType.checkbox && slot.options != null) {
        final selectedValues =
            value.split(',').map((s) => s.trim()).toList();
        for (int k = 0; k < slot.options!.length; k++) {
          if (selectedValues.contains(slot.options![k])) {
            buffer.write('{SPACE}');
          }
          if (k < slot.options!.length - 1) buffer.write('{TAB}');
        }
      } else {
        buffer.write(value);
      }

      // Post-keys: any control sequence needed after filling this slot
      for (final key in slot.postKeys) {
        buffer.write(key);
      }
    }

    return buffer.toString();
  }

  String get _slotsJson =>
      jsonEncode(slots.map((s) => s.toJson()).toList());

  String get _profilesJson =>
      jsonEncode(typingProfiles.map((p) => p.toJson()).toList());

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'version': version,
        'slots': _slotsJson,
        // Legacy column (NOT NULL); no longer used.
        'example_values': '{}',
        'pipeline': pipeline.toJsonString(),
        'typing_profiles': _profilesJson,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  /// Export form: slots only (no pipeline, no typing profiles).
  Map<String, dynamic> toMapWithoutPipeline() => {
        'id': id,
        'name': name,
        'version': version,
        'slots': _slotsJson,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory Template.fromMap(Map<String, dynamic> map) {
    final slotsJson = jsonDecode(map['slots'] as String) as List<dynamic>;
    final profilesRaw = map['typing_profiles'] as String?;
    final profiles = (profilesRaw == null || profilesRaw.isEmpty)
        ? <TypingProfile>[]
        : (jsonDecode(profilesRaw) as List<dynamic>)
            .map((p) => TypingProfile.fromJson(p as Map<String, dynamic>))
            .toList();

    return Template(
      id: map['id'] as String,
      name: map['name'] as String,
      version: map['version'] as String? ?? '1.0',
      slots: slotsJson
          .map((s) => TemplateSlot.fromJson(s as Map<String, dynamic>))
          .toList(),
      pipeline: PipelineGraph.fromJsonString(map['pipeline'] as String? ?? ''),
      typingProfiles: profiles,
      createdAt: DateTime.parse(map['created_at'] as String),
      updatedAt: DateTime.parse(map['updated_at'] as String),
    );
  }

  Template copyWith({
    String? name,
    String? version,
    List<TemplateSlot>? slots,
    PipelineGraph? pipeline,
    List<TypingProfile>? typingProfiles,
  }) =>
      Template(
        id: id,
        name: name ?? this.name,
        version: version ?? this.version,
        slots: slots ?? List.from(this.slots),
        pipeline: pipeline ?? this.pipeline,
        typingProfiles: typingProfiles ?? List.from(this.typingProfiles),
        createdAt: createdAt,
        updatedAt: DateTime.now(),
      );
}
