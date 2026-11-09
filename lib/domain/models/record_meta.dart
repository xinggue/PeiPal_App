import 'template.dart';

/// 随 Message 一同存储的轻量级病历生成元数据。
///
/// 解决了两个关键隐患：
/// 1. 模板被修改/删除后，可依靠 [slotSnapshots] 依然完整渲染带中文 Label 的字段卡片。
/// 2. 区分全量成功与部分生成 ([isPartial])，记录缺失的字段列表。
class RecordMeta {
  final String? templateName;
  final String? templateVersion;
  final String? contentTemplateId;
  final String? contentTemplateName;
  final String? model;
  final bool allMaterials;
  final bool isPartial;
  final List<String> missingSlotKeys;
  final DateTime generatedAt;
  final int totalDurationMs;

  /// 模板槽位快照（key/label/type/options 等），模板被删后的自愈基石。
  final List<Map<String, dynamic>> slotSnapshots;

  /// AI 原始生成的键值（用户在审阅页修改后，保留对比与一键还原 AI 原文的能力）。
  final Map<String, String> aiOriginalValues;

  /// 明确被生成或有效填入的字段集合（用于后续过滤未填写的空/默认槽位，以及子集生成字段辨识）。
  final List<String> activeSlotKeys;

  const RecordMeta({
    this.templateName,
    this.templateVersion,
    this.contentTemplateId,
    this.contentTemplateName,
    this.model,
    this.allMaterials = true,
    this.isPartial = false,
    this.missingSlotKeys = const [],
    required this.generatedAt,
    this.totalDurationMs = 0,
    this.slotSnapshots = const [],
    this.aiOriginalValues = const {},
    this.activeSlotKeys = const [],
  });

  Map<String, dynamic> toJson() => {
        if (templateName != null) 'template_name': templateName,
        if (templateVersion != null) 'template_version': templateVersion,
        if (contentTemplateId != null) 'content_template_id': contentTemplateId,
        if (contentTemplateName != null)
          'content_template_name': contentTemplateName,
        if (model != null) 'model': model,
        'all_materials': allMaterials,
        'is_partial': isPartial,
        if (missingSlotKeys.isNotEmpty) 'missing_slot_keys': missingSlotKeys,
        'generated_at': generatedAt.toIso8601String(),
        'total_duration_ms': totalDurationMs,
        if (slotSnapshots.isNotEmpty) 'slot_snapshots': slotSnapshots,
        if (aiOriginalValues.isNotEmpty)
          'ai_original_values': aiOriginalValues,
        if (activeSlotKeys.isNotEmpty) 'active_slot_keys': activeSlotKeys,
      };

  factory RecordMeta.fromJson(Map<String, dynamic> j) => RecordMeta(
        templateName: j['template_name'] as String?,
        templateVersion: j['template_version'] as String?,
        contentTemplateId: j['content_template_id'] as String?,
        contentTemplateName: j['content_template_name'] as String?,
        model: j['model'] as String?,
        allMaterials: j['all_materials'] as bool? ?? true,
        isPartial: j['is_partial'] as bool? ?? false,
        missingSlotKeys: (j['missing_slot_keys'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        generatedAt: j['generated_at'] != null
            ? DateTime.tryParse(j['generated_at'].toString()) ?? DateTime.now()
            : DateTime.now(),
        totalDurationMs: j['total_duration_ms'] as int? ?? 0,
        slotSnapshots: (j['slot_snapshots'] as List?)
                ?.whereType<Map>()
                .map((e) => e.cast<String, dynamic>())
                .toList() ??
            const [],
        aiOriginalValues: (j['ai_original_values'] as Map?)
                ?.map((k, v) => MapEntry(k.toString(), v?.toString() ?? '')) ??
            const {},
        activeSlotKeys: (j['active_slot_keys'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
      );

  RecordMeta copyWith({
    String? templateName,
    String? templateVersion,
    String? contentTemplateId,
    String? contentTemplateName,
    String? model,
    bool? allMaterials,
    bool? isPartial,
    List<String>? missingSlotKeys,
    DateTime? generatedAt,
    int? totalDurationMs,
    List<Map<String, dynamic>>? slotSnapshots,
    Map<String, String>? aiOriginalValues,
    List<String>? activeSlotKeys,
  }) {
    return RecordMeta(
      templateName: templateName ?? this.templateName,
      templateVersion: templateVersion ?? this.templateVersion,
      contentTemplateId: contentTemplateId ?? this.contentTemplateId,
      contentTemplateName: contentTemplateName ?? this.contentTemplateName,
      model: model ?? this.model,
      allMaterials: allMaterials ?? this.allMaterials,
      isPartial: isPartial ?? this.isPartial,
      missingSlotKeys: missingSlotKeys ?? this.missingSlotKeys,
      generatedAt: generatedAt ?? this.generatedAt,
      totalDurationMs: totalDurationMs ?? this.totalDurationMs,
      slotSnapshots: slotSnapshots ?? this.slotSnapshots,
      aiOriginalValues: aiOriginalValues ?? this.aiOriginalValues,
      activeSlotKeys: activeSlotKeys ?? this.activeSlotKeys,
    );
  }

  /// 根据模板槽位构造快照。
  static List<Map<String, dynamic>> snapshotSlots(List<TemplateSlot> slots) =>
      slots.map((s) => s.toJson()).toList();
}
