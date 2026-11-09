import '../../../domain/models/template.dart';

/// 为当前批次要生成的槽位生成严格的 JSON Schema。
///
/// 供 OpenAI 兼容后端的 `response_format: {"type": "json_schema", "json_schema": ...}` 使用。
class OutputSchemaBuilder {
  static Map<String, dynamic> build({
    required String stageTitle,
    required List<TemplateSlot> slots,
  }) {
    final properties = <String, dynamic>{};
    final requiredKeys = <String>[];

    for (final slot in slots) {
      requiredKeys.add(slot.key);
      final desc = '${slot.label} (${_typeDesc(slot.type)})';

      if ((slot.type == SlotType.dropdown || slot.type == SlotType.typedChoice) &&
          slot.options != null &&
          slot.options!.isNotEmpty) {
        final cleanOptions = slot.options!
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet()
            .toList();
        // 允许空字符串（当素材不足或不需要填入时，模型不会被强制幻觉出某个选项）
        final enumList = ['', ...cleanOptions];
        properties[slot.key] = {
          'type': 'string',
          'description': desc,
          'enum': enumList,
        };
      } else {
        properties[slot.key] = {
          'type': 'string',
          'description': desc,
        };
      }
    }

    return {
      'name': 'clinical_record_batch',
      'strict': true,
      'schema': {
        'type': 'object',
        'properties': properties,
        'required': requiredKeys,
        'additionalProperties': false,
      },
    };
  }

  static String _typeDesc(SlotType t) => switch (t) {
        SlotType.text => '单行文本',
        SlotType.multiline => '多行详细文本',
        SlotType.dropdown => '单选',
        SlotType.checkbox => '多选，逗号分隔',
        SlotType.typedChoice => '选项键入',
        SlotType.date => '日期',
      };
}
