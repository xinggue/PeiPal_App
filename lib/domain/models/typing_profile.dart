import 'package:uuid/uuid.dart';

import 'template.dart';
import 'typing_action_block.dart';

const _uuid = Uuid();

/// Legacy per-slot override inside a [TypingProfile] (kept for compatibility).
class SlotKeyOverride {
  final List<String>? pre;
  final List<String>? post;

  const SlotKeyOverride({this.pre, this.post});

  bool get isEmpty => pre == null && post == null;

  SlotKeyOverride copyWith({
    List<String>? pre,
    List<String>? post,
    bool clearPre = false,
    bool clearPost = false,
  }) =>
      SlotKeyOverride(
        pre: clearPre ? null : (pre ?? this.pre),
        post: clearPost ? null : (post ?? this.post),
      );

  Map<String, dynamic> toJson() => {
        if (pre != null) 'pre': pre,
        if (post != null) 'post': post,
      };

  factory SlotKeyOverride.fromJson(Map<String, dynamic> json) =>
      SlotKeyOverride(
        pre: json['pre'] is List ? List<String>.from(json['pre']) : null,
        post: json['post'] is List ? List<String>.from(json['post']) : null,
      );
}

/// A named typing scheme (输入方案) of a structure template.
/// Can contain an ordered list of [TypingActionBlock]s (类似按键精灵积木流),
/// or fall back to sequential field inputs based on slot defaults and overrides.
class TypingProfile {
  final String id;
  final String name;
  final Map<String, SlotKeyOverride> overrides;
  final List<TypingActionBlock> blocks;

  /// 组合键按住时长 (毫秒，默认 50ms)
  final int keyComboHoldMs;

  /// 动作积木步骤之间的系统反应延时 (毫秒，默认 300ms)。
  /// 在输入前动作、输入内容、输入后动作以及相邻积木之间由引擎自动插入，不显示在积木编辑列表中。
  final int postKeySettleMs;

  /// 步骤间系统反应延时别名
  int get stepDelayMs => postKeySettleMs;

  TypingProfile({
    String? id,
    required this.name,
    Map<String, SlotKeyOverride>? overrides,
    List<TypingActionBlock>? blocks,
    this.keyComboHoldMs = 50,
    this.postKeySettleMs = 300,
  })  : id = id ?? _uuid.v4(),
        overrides = overrides ?? {},
        blocks = blocks ?? [];

  /// Returns [blocks] if non-empty, or generates a default sequential block list
  /// from the provided [slots] and [overrides].
  List<TypingActionBlock> effectiveBlocks(List<TemplateSlot> slots) {
    if (blocks.isNotEmpty) return blocks;

    final sorted = List<TemplateSlot>.from(slots)
      ..sort((a, b) => a.order.compareTo(b.order));

    return sorted.map((s) {
      final ov = overrides[s.key];
      final pre = ov?.pre ?? s.preKeys;
      final post = ov?.post ?? s.postKeys;
      return FieldInputBlock(
        fieldKey: s.key,
        preKeys: pre,
        postKeys: post,
      );
    }).toList();
  }

  TypingProfile copyWith({
    String? name,
    Map<String, SlotKeyOverride>? overrides,
    List<TypingActionBlock>? blocks,
    int? keyComboHoldMs,
    int? postKeySettleMs,
  }) =>
      TypingProfile(
        id: id,
        name: name ?? this.name,
        overrides: overrides ?? Map.of(this.overrides),
        blocks: blocks ?? List.of(this.blocks),
        keyComboHoldMs: keyComboHoldMs ?? this.keyComboHoldMs,
        postKeySettleMs: postKeySettleMs ?? this.postKeySettleMs,
      );

  /// New profile with a fresh id and a deep copy of blocks & overrides.
  TypingProfile duplicate(String newName) => TypingProfile(
        name: newName,
        keyComboHoldMs: keyComboHoldMs,
        postKeySettleMs: postKeySettleMs,
        overrides: {
          for (final e in overrides.entries)
            e.key: SlotKeyOverride(
              pre: e.value.pre == null ? null : List.of(e.value.pre!),
              post: e.value.post == null ? null : List.of(e.value.post!),
            ),
        },
        blocks: blocks.map((b) => b.duplicate()).toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'keyComboHoldMs': keyComboHoldMs,
        'postKeySettleMs': postKeySettleMs,
        if (overrides.isNotEmpty)
          'overrides': {
            for (final e in overrides.entries)
              if (!e.value.isEmpty) e.key: e.value.toJson(),
          },
        if (blocks.isNotEmpty)
          'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory TypingProfile.fromJson(Map<String, dynamic> json) => TypingProfile(
        id: json['id'] as String?,
        name: json['name'] as String? ?? '方案',
        keyComboHoldMs: json['keyComboHoldMs'] as int? ?? 50,
        postKeySettleMs: json['postKeySettleMs'] as int? ?? 300,
        overrides: {
          for (final e
              in ((json['overrides'] as Map<String, dynamic>?) ?? {}).entries)
            e.key: SlotKeyOverride.fromJson(e.value as Map<String, dynamic>),
        },
        blocks: (json['blocks'] as List?)
                ?.map((item) =>
                    TypingActionBlock.fromJson(item as Map<String, dynamic>))
                .toList() ??
            [],
      );
}
