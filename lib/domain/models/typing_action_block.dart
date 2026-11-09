import 'dart:convert';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

enum ActionBlockType {
  fieldInput,   // 录入某个字段
  keyCombo,     // 系统按键/快捷键 (Win+R, Ctrl+V, Tab 等)
  literalText,  // 固定文本 (如 notepad)
  delay,        // 等待延时 (毫秒)
  rhythm,       // 动态切换打字节奏 (如常规/稳妥/极速)
  forEach,      // 列表项循环 (如诊断逐条录入)
  currentItem,  // 循环体内的“当前项”录入
  group,        // 积木分组 (如打开记事本流程)
}

/// Base class for all typing action blocks (按键积木块).
abstract class TypingActionBlock {
  final String id;
  final ActionBlockType type;

  const TypingActionBlock({
    required this.id,
    required this.type,
  });

  Map<String, dynamic> toJson();

  TypingActionBlock duplicate();

  static TypingActionBlock fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? '';
    return switch (typeName) {
      'fieldInput' => FieldInputBlock.fromJson(json),
      'keyCombo' => KeyComboBlock.fromJson(json),
      'literalText' => LiteralTextBlock.fromJson(json),
      'delay' => DelayBlock.fromJson(json),
      'rhythm' => RhythmActionBlock.fromJson(json),
      'forEach' => ForEachBlock.fromJson(json),
      'currentItem' => CurrentItemBlock.fromJson(json),
      'group' => GroupBlock.fromJson(json),
      _ => KeyComboBlock(combo: json['combo'] as String? ?? '{TAB}'),
    };
  }
}

/// 录入某个字段内容
class FieldInputBlock extends TypingActionBlock {
  final String fieldKey;
  final List<String> preKeys;
  final List<String> postKeys;

  FieldInputBlock({
    String? id,
    required this.fieldKey,
    this.preKeys = const [],
    this.postKeys = const [],
  }) : super(id: id ?? _uuid.v4(), type: ActionBlockType.fieldInput);

  FieldInputBlock copyWith({
    String? fieldKey,
    List<String>? preKeys,
    List<String>? postKeys,
  }) =>
      FieldInputBlock(
        id: id,
        fieldKey: fieldKey ?? this.fieldKey,
        preKeys: preKeys ?? this.preKeys,
        postKeys: postKeys ?? this.postKeys,
      );

  @override
  FieldInputBlock duplicate() => FieldInputBlock(
        fieldKey: fieldKey,
        preKeys: List.of(preKeys),
        postKeys: List.of(postKeys),
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'fieldInput',
        'fieldKey': fieldKey,
        'preKeys': preKeys,
        'postKeys': postKeys,
      };

  factory FieldInputBlock.fromJson(Map<String, dynamic> json) =>
      FieldInputBlock(
        id: json['id'] as String?,
        fieldKey: json['fieldKey'] as String? ?? '',
        preKeys: (json['preKeys'] as List?)?.cast<String>() ?? const [],
        postKeys: (json['postKeys'] as List?)?.cast<String>() ?? const [],
      );
}

/// 系统按键或组合快捷键 (如 {WIN+R}, {CTRL+C}, {CTRL+V}, {TAB}, {ENTER})
class KeyComboBlock extends TypingActionBlock {
  final String combo;

  KeyComboBlock({
    String? id,
    required this.combo,
  }) : super(id: id ?? _uuid.v4(), type: ActionBlockType.keyCombo);

  KeyComboBlock copyWith({String? combo}) => KeyComboBlock(
        id: id,
        combo: combo ?? this.combo,
      );

  @override
  KeyComboBlock duplicate() => KeyComboBlock(combo: combo);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'keyCombo',
        'combo': combo,
      };

  factory KeyComboBlock.fromJson(Map<String, dynamic> json) => KeyComboBlock(
        id: json['id'] as String?,
        combo: json['combo'] as String? ?? '{TAB}',
      );
}

/// 固定文本 (如 notepad, calc, 命令行等)
class LiteralTextBlock extends TypingActionBlock {
  final String text;

  LiteralTextBlock({
    String? id,
    required this.text,
  }) : super(id: id ?? _uuid.v4(), type: ActionBlockType.literalText);

  LiteralTextBlock copyWith({String? text}) => LiteralTextBlock(
        id: id,
        text: text ?? this.text,
      );

  @override
  LiteralTextBlock duplicate() => LiteralTextBlock(text: text);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'literalText',
        'text': text,
      };

  factory LiteralTextBlock.fromJson(Map<String, dynamic> json) =>
      LiteralTextBlock(
        id: json['id'] as String?,
        text: json['text'] as String? ?? '',
      );
}

/// 延时等待 (毫秒)
class DelayBlock extends TypingActionBlock {
  final int durationMs;

  DelayBlock({
    String? id,
    required this.durationMs,
  }) : super(id: id ?? _uuid.v4(), type: ActionBlockType.delay);

  DelayBlock copyWith({int? durationMs}) => DelayBlock(
        id: id,
        durationMs: durationMs ?? this.durationMs,
      );

  @override
  DelayBlock duplicate() => DelayBlock(durationMs: durationMs);

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'delay',
        'durationMs': durationMs,
      };

  factory DelayBlock.fromJson(Map<String, dynamic> json) => DelayBlock(
        id: json['id'] as String?,
        durationMs: json['durationMs'] as int? ?? 200,
      );
}

/// 动态切换输入节奏积木 (编译为固件 {CFG:...} 即时调速指令)
class RhythmActionBlock extends TypingActionBlock {
  final String presetName; // 预设名称，如 '稳妥模式'、'极速狂飙'、'自定义'
  final Map<String, double> params; // key-value 时序覆盖，如 {'cjk_gap_ms': 30, 'tap_press_ms': 10}

  RhythmActionBlock({
    String? id,
    required this.presetName,
    this.params = const {},
  }) : super(id: id ?? _uuid.v4(), type: ActionBlockType.rhythm);

  RhythmActionBlock copyWith({
    String? presetName,
    Map<String, double>? params,
  }) =>
      RhythmActionBlock(
        id: id,
        presetName: presetName ?? this.presetName,
        params: params ?? Map.of(this.params),
      );

  @override
  RhythmActionBlock duplicate() => RhythmActionBlock(
        presetName: presetName,
        params: Map.of(params),
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'rhythm',
        'presetName': presetName,
        'params': params,
      };

  factory RhythmActionBlock.fromJson(Map<String, dynamic> json) => RhythmActionBlock(
        id: json['id'] as String?,
        presetName: json['presetName'] as String? ?? '常规模式',
        params: (json['params'] as Map?)?.map(
              (k, v) => MapEntry(k.toString(), (v as num).toDouble()),
            ) ??
            const {},
      );
}

/// 循环体内的“当前项”录入
class CurrentItemBlock extends TypingActionBlock {
  final List<String> preKeys;
  final List<String> postKeys;

  CurrentItemBlock({
    String? id,
    this.preKeys = const [],
    this.postKeys = const [],
  }) : super(id: id ?? _uuid.v4(), type: ActionBlockType.currentItem);

  CurrentItemBlock copyWith({
    List<String>? preKeys,
    List<String>? postKeys,
  }) =>
      CurrentItemBlock(
        id: id,
        preKeys: preKeys ?? this.preKeys,
        postKeys: postKeys ?? this.postKeys,
      );

  @override
  CurrentItemBlock duplicate() => CurrentItemBlock(
        preKeys: List.of(preKeys),
        postKeys: List.of(postKeys),
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'currentItem',
        'preKeys': preKeys,
        'postKeys': postKeys,
      };

  factory CurrentItemBlock.fromJson(Map<String, dynamic> json) =>
      CurrentItemBlock(
        id: json['id'] as String?,
        preKeys: (json['preKeys'] as List?)?.cast<String>() ?? const [],
        postKeys: (json['postKeys'] as List?)?.cast<String>() ?? const [],
      );
}

/// 列表循环块 (针对诊断、处置等多项字段逐条录入)
class ForEachBlock extends TypingActionBlock {
  final String fieldKey;
  final String separator; // 拆分分隔符，默认换行 '\n'
  final List<TypingActionBlock> subBlocks;

  ForEachBlock({
    String? id,
    required this.fieldKey,
    this.separator = r'\n',
    List<TypingActionBlock>? subBlocks,
  })  : subBlocks = subBlocks ??
            [
              CurrentItemBlock(),
              KeyComboBlock(combo: '{DOWN}'),
              KeyComboBlock(combo: '{ENTER}'),
            ],
        super(id: id ?? _uuid.v4(), type: ActionBlockType.forEach);

  ForEachBlock copyWith({
    String? fieldKey,
    String? separator,
    List<TypingActionBlock>? subBlocks,
  }) =>
      ForEachBlock(
        id: id,
        fieldKey: fieldKey ?? this.fieldKey,
        separator: separator ?? this.separator,
        subBlocks: subBlocks ?? this.subBlocks,
      );

  @override
  ForEachBlock duplicate() => ForEachBlock(
        fieldKey: fieldKey,
        separator: separator,
        subBlocks: subBlocks.map((b) => b.duplicate()).toList(),
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'forEach',
        'fieldKey': fieldKey,
        'separator': separator,
        'subBlocks': subBlocks.map((b) => b.toJson()).toList(),
      };

  factory ForEachBlock.fromJson(Map<String, dynamic> json) => ForEachBlock(
        id: json['id'] as String?,
        fieldKey: json['fieldKey'] as String? ?? '',
        separator: json['separator'] as String? ?? r'\n',
        subBlocks: (json['subBlocks'] as List?)
                ?.map((item) => TypingActionBlock.fromJson(item as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// 积木成组块 (把多个积木打包成一组，例如“记事本启动流”)
class GroupBlock extends TypingActionBlock {
  final String name;
  final List<TypingActionBlock> blocks;
  final bool isCollapsed;

  GroupBlock({
    String? id,
    required this.name,
    required this.blocks,
    this.isCollapsed = false,
  }) : super(id: id ?? _uuid.v4(), type: ActionBlockType.group);

  GroupBlock copyWith({
    String? name,
    List<TypingActionBlock>? blocks,
    bool? isCollapsed,
  }) =>
      GroupBlock(
        id: id,
        name: name ?? this.name,
        blocks: blocks ?? this.blocks,
        isCollapsed: isCollapsed ?? this.isCollapsed,
      );

  @override
  GroupBlock duplicate() => GroupBlock(
        name: name,
        blocks: blocks.map((b) => b.duplicate()).toList(),
        isCollapsed: isCollapsed,
      );

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'type': 'group',
        'name': name,
        'isCollapsed': isCollapsed,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory GroupBlock.fromJson(Map<String, dynamic> json) => GroupBlock(
        id: json['id'] as String?,
        name: json['name'] as String? ?? '未命名分组',
        isCollapsed: json['isCollapsed'] as bool? ?? false,
        blocks: (json['blocks'] as List?)
                ?.map((item) => TypingActionBlock.fromJson(item as Map<String, dynamic>))
                .toList() ??
            const [],
      );
}

/// 用户可增删查改的积木动作预设（可作为分组容器插入到输入方案中，也可由分组容器直接另存为新预设）
class TypingBlockPreset {
  final String id;
  final String name;
  final String description;
  final List<TypingActionBlock> blocks;
  final bool isBuiltIn;

  TypingBlockPreset({
    String? id,
    required this.name,
    this.description = '',
    required List<TypingActionBlock> blocks,
    this.isBuiltIn = false,
  })  : id = id ?? _uuid.v4(),
        blocks = List.of(blocks);

  TypingBlockPreset copyWith({
    String? name,
    String? description,
    List<TypingActionBlock>? blocks,
    bool? isBuiltIn,
  }) =>
      TypingBlockPreset(
        id: id,
        name: name ?? this.name,
        description: description ?? this.description,
        blocks: blocks ?? this.blocks.map((b) => b.duplicate()).toList(),
        isBuiltIn: isBuiltIn ?? this.isBuiltIn,
      );

  TypingBlockPreset duplicate({String? newName}) => TypingBlockPreset(
        name: newName ?? '$name (副本)',
        description: description,
        blocks: blocks.map((b) => b.duplicate()).toList(),
        isBuiltIn: false,
      );

  /// 将预设转化为一个新的积木分组容器（所有内部积木重新生成独立 ID）
  GroupBlock toGroupBlock() => GroupBlock(
        name: name,
        blocks: blocks.map((b) => b.duplicate()).toList(),
      );

  /// 生成直观的步骤流预览文案
  String get stepsPreview {
    if (blocks.isEmpty) return '暂无步骤';
    return blocks.map(_describeSingleStep).join(' ➔ ');
  }

  static String _describeSingleStep(TypingActionBlock b) {
    if (b is KeyComboBlock) return b.combo;
    if (b is DelayBlock) return '${b.durationMs}ms';
    if (b is LiteralTextBlock) return '"${b.text}"';
    if (b is RhythmActionBlock) return '[${b.presetName}]';
    if (b is FieldInputBlock) return '字段:${b.fieldKey}';
    if (b is CurrentItemBlock) return '当前项';
    if (b is GroupBlock) return '分组:${b.name}';
    if (b is ForEachBlock) return '循环:${b.fieldKey}';
    return b.type.name;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'isBuiltIn': isBuiltIn,
        'blocks': blocks.map((b) => b.toJson()).toList(),
      };

  factory TypingBlockPreset.fromJson(Map<String, dynamic> json) =>
      TypingBlockPreset(
        id: json['id'] as String?,
        name: json['name'] as String? ?? '未命名预设',
        description: json['description'] as String? ?? '',
        isBuiltIn: json['isBuiltIn'] as bool? ?? false,
        blocks: (json['blocks'] as List?)
                ?.whereType<Map>()
                .map((m) =>
                    TypingActionBlock.fromJson(m.cast<String, dynamic>()))
                .toList() ??
            const [],
      );
}

/// 默认内置的常用动作积木预设
List<TypingBlockPreset> createBuiltInBlockPresets() => [
      TypingBlockPreset(
        id: 'builtin_notepad_buffer',
        name: '打开记事本缓冲',
        description: '自动唤起运行窗口启动记事本并等待就绪',
        isBuiltIn: true,
        blocks: [
          KeyComboBlock(combo: '{WIN+R}'),
          DelayBlock(durationMs: 200),
          LiteralTextBlock(text: 'notepad'),
          KeyComboBlock(combo: '{ENTER}'),
          DelayBlock(durationMs: 350),
        ],
      ),
      TypingBlockPreset(
        id: 'builtin_select_all_clear',
        name: '全选并清空当前框',
        description: '选中当前输入框内已有内容并按退格键清除',
        isBuiltIn: true,
        blocks: [
          KeyComboBlock(combo: '{CTRL+A}'),
          KeyComboBlock(combo: '{BS}'),
        ],
      ),
      TypingBlockPreset(
        id: 'builtin_cut_switch_paste',
        name: '全选剪切并切回粘贴',
        description: '适合在缓冲窗口打完字后一键剪切并切回原窗口粘贴',
        isBuiltIn: true,
        blocks: [
          KeyComboBlock(combo: '{CTRL+A}'),
          KeyComboBlock(combo: '{CTRL+X}'),
          KeyComboBlock(combo: '{ALT+TAB}'),
          DelayBlock(durationMs: 250),
          KeyComboBlock(combo: '{CTRL+V}'),
        ],
      ),
    ];

String encodeBlockPresetsListJson(List<TypingBlockPreset> presets) =>
    jsonEncode(presets.map((p) => p.toJson()).toList());

List<TypingBlockPreset> decodeBlockPresetsListJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return createBuiltInBlockPresets();
  }
  try {
    final list = jsonDecode(raw);
    if (list is! List) return createBuiltInBlockPresets();
    return list
        .whereType<Map>()
        .map((m) => TypingBlockPreset.fromJson(m.cast<String, dynamic>()))
        .toList();
  } catch (_) {
    return createBuiltInBlockPresets();
  }
}
