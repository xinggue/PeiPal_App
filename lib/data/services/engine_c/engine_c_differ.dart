import 'dart:convert';

import '../../../domain/models/content_template.dart';
import '../../../domain/models/pipeline_graph.dart';
import '../../../domain/models/template.dart';
import '../../../domain/models/typing_profile.dart';

/// 引擎 C 逐层结构与子项等价性判定器（Engine C Structural & Semantic Differ）
///
/// 负责：
/// 1. 判定两个结构模板的字段列表 (`slots`) 签名是否兼容等价；
/// 2. 判定两个解析流程 (`PipelineGraph`) 的拓扑与节点配置是否等价；
/// 3. 判定两个键入方案 (`TypingProfile`) 的动作积木流与参数是否等价；
/// 4. 判定两个内容模板 (`ContentTemplate`) 的整体规范、示范与各槽位内容是否等价；
/// 5. 生成不冲突的副本名称（如 `"心内入院 (副本)"`、`"心内入院 (副本 2)"`）。
class EngineCDiffer {
  /// 比较两个结构模板的字段列表签名是否完全匹配
  ///
  /// 匹配标准：
  /// - 字段数量相同；
  /// - 按 `key` 映射后，每个字段的 `key`、`type`、`catalogType`、`options`（若为下拉/多选）一致。
  static bool areSlotsSignatureEqual(
    List<TemplateSlot> localSlots,
    List<TemplateSlot> incomingSlots,
  ) {
    if (localSlots.length != incomingSlots.length) return false;

    final localByKey = {for (final s in localSlots) s.key: s};
    for (final inc in incomingSlots) {
      final loc = localByKey[inc.key];
      if (loc == null) return false;
      if (loc.type != inc.type) return false;
      if ((loc.catalogType ?? '') != (inc.catalogType ?? '')) return false;
      if (!_stringListEquals(loc.options ?? const [], inc.options ?? const [])) {
        return false;
      }
    }
    return true;
  }

  /// 生成字段差异的人类可读摘要（当字段签名不匹配时，告诉用户具体差在哪里）
  static String? describeSlotDifferences(
    List<TemplateSlot> localSlots,
    List<TemplateSlot> incomingSlots,
  ) {
    if (areSlotsSignatureEqual(localSlots, incomingSlots)) return null;

    final localKeys = localSlots.map((s) => s.key).toSet();
    final incKeys = incomingSlots.map((s) => s.key).toSet();

    final added = incKeys.difference(localKeys);
    final removed = localKeys.difference(incKeys);
    final parts = <String>[];

    if (added.isNotEmpty) {
      parts.add('多出字段: ${added.take(4).join(", ")}${added.length > 4 ? " 等${added.length}个" : ""}');
    }
    if (removed.isNotEmpty) {
      parts.add('缺少本地字段: ${removed.take(4).join(", ")}${removed.length > 4 ? " 等${removed.length}个" : ""}');
    }

    if (parts.isEmpty) {
      parts.add('部分同名字段的类型或候选项定义不一致');
    }
    return parts.join('；');
  }

  /// 比较两个解析流程拓扑图是否语义等价（忽略节点随机 UUID，比较节点坐标、绑定槽位、提示词与连线拓扑）
  static bool arePipelinesEqual(PipelineGraph a, PipelineGraph b) {
    if (a.nodes.isEmpty && b.nodes.isEmpty) return true;
    if (a.nodes.length != b.nodes.length) return false;
    if (a.edges.length != b.edges.length) return false;
    if (a.groupPrompts.length != b.groupPrompts.length) return false;

    for (final entry in a.groupPrompts.entries) {
      if (b.groupPrompts[entry.key] != entry.value) return false;
    }

    // 构建节点位置与槽位签名表
    String nodeSig(PipelineNode n) =>
        '${n.col}:${n.row}:${n.group}:${n.label}:${(List<String>.from(n.slotKeys)..sort()).join(",")}:${n.prompt.trim()}';

    final aNodeMap = {for (final n in a.nodes) n.id: nodeSig(n)};
    final bNodeMap = {for (final n in b.nodes) n.id: nodeSig(n)};

    final aSigs = aNodeMap.values.toList()..sort();
    final bSigs = bNodeMap.values.toList()..sort();
    if (!_stringListEquals(aSigs, bSigs)) return false;

    final aEdgeSigs = a.edges
        .map((e) => '${aNodeMap[e.from] ?? ""}->${aNodeMap[e.to] ?? ""}')
        .toList()
      ..sort();
    final bEdgeSigs = b.edges
        .map((e) => '${bNodeMap[e.from] ?? ""}->${bNodeMap[e.to] ?? ""}')
        .toList()
      ..sort();

    return _stringListEquals(aEdgeSigs, bEdgeSigs);
  }

  /// 比较两个键入方案是否完全等价（忽略方案及积木的随机 id，比较时序参数、overrides 与积木动作流）
  static bool areTypingProfilesEqual(
    TypingProfile a,
    TypingProfile b,
    List<TemplateSlot> slots,
  ) {
    if (a.keyComboHoldMs != b.keyComboHoldMs) return false;
    if (a.postKeySettleMs != b.postKeySettleMs) return false;
    if (!_overridesEqual(a.overrides, b.overrides)) return false;

    final aBlocks = a.effectiveBlocks(slots);
    final bBlocks = b.effectiveBlocks(slots);
    if (aBlocks.length != bBlocks.length) return false;

    for (int i = 0; i < aBlocks.length; i++) {
      final mapA = Map<String, dynamic>.from(aBlocks[i].toJson())..remove('id');
      final mapB = Map<String, dynamic>.from(bBlocks[i].toJson())..remove('id');
      if (jsonEncode(_canonicalizeJson(mapA)) !=
          jsonEncode(_canonicalizeJson(mapB))) {
        return false;
      }
    }
    return true;
  }

  /// 判定键入方案是否仅为空白默认方案（即名为“默认”且未配置自定义积木与覆盖项）
  static bool isTrivialDefaultProfile(TypingProfile p) {
    return p.name == '默认' &&
        p.blocks.isEmpty &&
        p.overrides.values.every((v) => v.isEmpty) &&
        p.keyComboHoldMs == 50 &&
        (p.postKeySettleMs == 300 || p.postKeySettleMs == 80);
  }

  /// 比较两个内容模板的内容是否完全等价（忽略 id、structureTemplateId 与时间戳）
  static bool areContentTemplatesEqual(ContentTemplate a, ContentTemplate b) {
    if (a.globalGuidance.trim() != b.globalGuidance.trim()) return false;
    if (a.fullExample.trim() != b.fullExample.trim()) return false;

    final aNonEmpty = {
      for (final e in a.slots.entries)
        if (!e.value.isEmpty) e.key: e.value,
    };
    final bNonEmpty = {
      for (final e in b.slots.entries)
        if (!e.value.isEmpty) e.key: e.value,
    };

    if (aNonEmpty.length != bNonEmpty.length) return false;

    for (final entry in aNonEmpty.entries) {
      final bSlot = bNonEmpty[entry.key];
      if (bSlot == null) return false;
      if (entry.value.guidance.trim() != bSlot.guidance.trim()) return false;
      if (!_stringListEquals(
        entry.value.examples.map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
        bSlot.examples.map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
      )) {
        return false;
      }
      if (!_stringListEquals(
        List<String>.from(entry.value.catalogTags)..sort(),
        List<String>.from(bSlot.catalogTags)..sort(),
      )) {
        return false;
      }
    }
    return true;
  }

  /// 生成不与现有名称集合冲突的副本名称
  /// 例如：`"入院记录"` -> `"入院记录 (副本)"` -> `"入院记录 (副本 2)"`
  static String allocateForkName(
    String baseName,
    Iterable<String> existingNames, {
    String suffixLabel = '副本',
  }) {
    final nameSet = existingNames.map((e) => e.trim()).toSet();
    final cleanBase = baseName.trim();
    if (!nameSet.contains(cleanBase)) return cleanBase;

    var candidate = '$cleanBase ($suffixLabel)';
    var counter = 2;
    while (nameSet.contains(candidate)) {
      candidate = '$cleanBase ($suffixLabel $counter)';
      counter++;
    }
    return candidate;
  }

  static bool _overridesEqual(
    Map<String, SlotKeyOverride> a,
    Map<String, SlotKeyOverride> b,
  ) {
    final aKeys = a.keys.where((k) => !a[k]!.isEmpty).toSet();
    final bKeys = b.keys.where((k) => !b[k]!.isEmpty).toSet();
    if (aKeys.length != bKeys.length || !aKeys.containsAll(bKeys)) return false;
    for (final key in aKeys) {
      final left = a[key]!;
      final right = b[key]!;
      if (!_stringListEquals(left.pre ?? const [], right.pre ?? const [])) {
        return false;
      }
      if (!_stringListEquals(left.post ?? const [], right.post ?? const [])) {
        return false;
      }
    }
    return true;
  }

  static bool _stringListEquals(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  static dynamic _canonicalizeJson(dynamic value) {
    if (value is Map) {
      final sortedKeys = value.keys.map((k) => k.toString()).toList()..sort();
      return {
        for (final k in sortedKeys)
          if (k != 'id') k: _canonicalizeJson(value[k]),
      };
    } else if (value is List) {
      return value.map(_canonicalizeJson).toList();
    }
    return value;
  }
}
