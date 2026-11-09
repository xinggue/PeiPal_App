import '../models/template.dart';
import 'generation_result.dart';

/// 纯函数校验器：供清洗阶段生成 issues、供审阅页实时驱动标红与选项提示。
class RecordValidator {
  static final RegExp _splitPattern = RegExp(r'[，,、;\n\r|/]+');

  /// 校验单个字段的输入值。
  /// 返回 null 表示通过；返回 [FieldIssue] 表示有问题。
  static FieldIssue? validateField({
    required TemplateSlot slot,
    required String? rawValue,
    Map<String, dynamic> allValues = const {},
  }) {
    // 1. 如果配置了前置条件且不满足，跳过校验
    if (slot.condition != null && !slot.condition!.evaluate(allValues)) {
      return null;
    }

    final val = (rawValue ?? '').trim();

    // 2. 必填空值检查
    if (slot.required && val.isEmpty) {
      return FieldIssue(
        key: slot.key,
        type: FieldIssueType.missingRequired,
        message: '「${slot.label}」为必填字段',
      );
    }

    // 3. 选项匹配检查（值为空时不检查选项，交由必填规则判断）
    final opts = slot.options;
    if (opts == null || opts.isEmpty || val.isEmpty) {
      return null;
    }

    final trimmedOpts = opts.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (trimmedOpts.isEmpty) return null;

    if (slot.type == SlotType.checkbox) {
      // 多选字段：按分隔符切片后，逐个检查是否在可选范围内
      final parts = val
          .split(_splitPattern)
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      final invalid = parts.where((p) => !trimmedOpts.contains(p)).toList();
      if (invalid.isNotEmpty) {
        return FieldIssue(
          key: slot.key,
          type: FieldIssueType.notInOptions,
          message: '包含不在选项中的值：${invalid.join("、")}',
        );
      }
    } else if (slot.type == SlotType.dropdown ||
        slot.type == SlotType.typedChoice) {
      // 单选 / 按选项键入：必须完全等于某一选项
      if (!trimmedOpts.contains(val)) {
        return FieldIssue(
          key: slot.key,
          type: FieldIssueType.notInOptions,
          message: '当前值 "$val" 不在预设选项中',
        );
      }
    }

    return null;
  }

  /// 扫描整份病历的所有字段，返回全部问题。
  static List<FieldIssue> validateAll({
    required List<TemplateSlot> slots,
    required Map<String, String> values,
  }) {
    final list = <FieldIssue>[];
    for (final slot in slots) {
      final issue = validateField(
        slot: slot,
        rawValue: values[slot.key],
        allValues: values,
      );
      if (issue != null) list.add(issue);
    }
    return list;
  }
}
