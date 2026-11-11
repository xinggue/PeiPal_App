import '../../../domain/models/template.dart';
import '../../../domain/models/typing_action_block.dart';
import '../../../domain/models/typing_profile.dart';
import 'typing_text_normalizer.dart';

/// 临床发送执行模式
enum TypingSendMode {
  /// 模式 1：流水线占位空跳（严格按照输入方案积木执行；遇到未选/空槽位，不打文字但执行导航键跨过输入框）
  pipelineKeepFlow,

  /// 模式 2：纯文本平铺（大段平铺输入；忽略按键流程，仅按自然段展开，字段间自然换行）
  plainTextFlatten,

  /// 模式 3：交互式点播（仅定向输出勾选的一个或若干个指定字段）
  interactiveDirect,
}

/// 编译生成上下文
class TypingCompileContext {
  final Template template;
  final TypingProfile profile;
  final Map<String, dynamic> recordValues;
  final Set<String> activeSlotKeys;
  final TypingSendMode mode;
  final Set<String>? targetSlotKeysForDirect; // 仅交互式点播模式使用

  const TypingCompileContext({
    required this.template,
    required this.profile,
    required this.recordValues,
    required this.activeSlotKeys,
    required this.mode,
    this.targetSlotKeysForDirect,
  });
}

/// 临床击键编排引擎（Engine B - Execution & Typing Compiler）
///
/// 具备 G 代码级（G-Code）确定性控制：
/// 1. 负责将结构化病历映射、时序参数、按键积木流编译为给 ESP32-C3 键盘芯片/扫码枪执行的物理击键指令流；
/// 2. 注入稳态停顿、组合键时序、动态时序切换（{CFG:...}）；
/// 3. 支持三种临床发送模式（流水线占位空跳、纯文本平铺、交互式单字段点播）；
/// 4. 彻底清洗不可见字符与多余回车。
class TypingCompiler {
  /// 执行全流程编译
  static String compile(TypingCompileContext ctx) {
    switch (ctx.mode) {
      case TypingSendMode.plainTextFlatten:
        return _compilePlainText(ctx);

      case TypingSendMode.interactiveDirect:
        return _compileInteractiveDirect(ctx);

      case TypingSendMode.pipelineKeepFlow:
        return _compilePipelineKeepFlow(ctx);
    }
  }

  /// 本次真正有内容、应当打出的字段。activeSlotKeys 为空时不把全部字段跳过。
  static Set<String> effectiveActiveKeys(TypingCompileContext ctx) {
    final valued = <String>{};
    for (final e in ctx.recordValues.entries) {
      if (TypingTextNormalizer.normalize(e.value?.toString() ?? '').isNotEmpty) {
        valued.add(e.key);
      }
    }
    if (ctx.activeSlotKeys.isEmpty) return valued;
    final hit = ctx.activeSlotKeys.intersection(valued);
    return hit.isEmpty ? valued : hit;
  }

  /// 模式 2：纯文本平铺展开编译
  static String _compilePlainText(TypingCompileContext ctx) {
    final buffer = StringBuffer();
    final active = effectiveActiveKeys(ctx);
    final sortedSlots = ctx.template.sortedSlots;
    final known = sortedSlots.map((s) => s.key).toSet();
    final lines = <String>[];

    for (final slot in sortedSlots) {
      if (!active.contains(slot.key)) continue;
      final cleanVal = TypingTextNormalizer.normalize(
        ctx.recordValues[slot.key]?.toString() ?? '',
      );
      if (cleanVal.isEmpty) continue;
      final label = slot.label.isNotEmpty ? slot.label : slot.key;
      lines.add('【$label】$cleanVal');
    }

    // 模板里没有、但病历里有内容的字段，补到末尾，避免只生成了额外字段时整段为空。
    for (final key in ctx.recordValues.keys) {
      if (known.contains(key) || !active.contains(key)) continue;
      final cleanVal = TypingTextNormalizer.normalize(
        ctx.recordValues[key]?.toString() ?? '',
      );
      if (cleanVal.isEmpty) continue;
      lines.add('【$key】$cleanVal');
    }

    buffer.write(lines.join('\n'));
    return buffer.toString().trim();
  }

  /// 模式 3：交互式单字段点播编译（按字段平铺展开，带字段名与冒号，字段后统一回车换行）
  static String _compileInteractiveDirect(TypingCompileContext ctx) {
    final emitter = _StepEmitter(stepDelayMs: ctx.profile.postKeySettleMs);
    final targets = ctx.targetSlotKeysForDirect ?? ctx.activeSlotKeys;

    for (final slotKey in targets) {
      final rawVal = ctx.recordValues[slotKey]?.toString() ?? '';
      final cleanVal = TypingTextNormalizer.normalize(rawVal);
      if (cleanVal.isEmpty) continue;

      // 查找对应槽位的定义以获取标签名
      final slot = ctx.template.sortedSlots.firstWhere(
        (s) => s.key == slotKey,
        orElse: () => TemplateSlot(key: slotKey, label: slotKey, type: SlotType.text),
      );
      final label = slot.label.isNotEmpty ? slot.label : slot.key;

      // 1. 字段名称：内容
      emitter.emitStep('$label：$cleanVal');

      // 2. 字段输入完成后按回车换行（取代文书结构内的后置动作按键）
      emitter.emitKeyListStep(['{ENTER}']);
    }

    return emitter.buildResult();
  }

  /// 模式 1：流水线输入方案严格编译（含占位空跳）
  /// 未配置积木时 effectiveBlocks 会按字段前置/后置键生成默认流程。
  /// 若结果仍为空，退回字段平铺，避免单字段或漏字段时整段发不出去。
  static String _compilePipelineKeepFlow(TypingCompileContext ctx) {
    final emitter = _StepEmitter(stepDelayMs: ctx.profile.postKeySettleMs);
    final blocks = ctx.profile.effectiveBlocks(ctx.template.slots);

    _compileBlockList(
      blocks: blocks,
      ctx: ctx,
      emitter: emitter,
    );

    final compiled = emitter.buildResult();
    if (compiled.isEmpty) return _compilePlainText(ctx);
    return compiled;
  }

  static void _compileBlockList({
    required List<TypingActionBlock> blocks,
    required TypingCompileContext ctx,
    required _StepEmitter emitter,
    String? currentLoopItemText,
  }) {
    for (final block in blocks) {
      if (block is FieldInputBlock) {
        _compileFieldInput(block, ctx, emitter);
      } else if (block is KeyComboBlock) {
        emitter.emitStep(_normalizeKeyTag(block.combo));
      } else if (block is LiteralTextBlock) {
        emitter.emitStep(TypingTextNormalizer.normalize(block.text));
      } else if (block is DelayBlock) {
        if (block.durationMs > 0) {
          emitter.emitStep('{DELAY:${block.durationMs}}');
        }
      } else if (block is RhythmActionBlock) {
        // 动态调参指令：编译为 {CFG:k=v ...}（并向下兼容映射 key_press_ms 和 key_gap_ms）
        if (block.params.isNotEmpty) {
          final pairs = <String>[];
          for (final e in block.params.entries) {
            pairs.add('${e.key}=${e.value}');
            if (e.key == 'key_press_ms') {
              pairs.add('tap_press_ms=${e.value}');
              pairs.add('shift_press_ms=${e.value}');
              pairs.add('enter_press_ms=${e.value}');
              pairs.add('tab_press_ms=${e.value}');
            } else if (e.key == 'key_gap_ms') {
              pairs.add('tap_release_ms=${e.value}');
              pairs.add('shift_release_ms=${e.value}');
              pairs.add('enter_release_ms=${e.value}');
              pairs.add('tab_release_ms=${e.value}');
            }
          }
          emitter.emitStep('{CFG:${pairs.join(' ')}}');
        }
      } else if (block is GroupBlock) {
        _compileBlockList(
          blocks: block.blocks,
          ctx: ctx,
          emitter: emitter,
          currentLoopItemText: currentLoopItemText,
        );
      } else if (block is ForEachBlock) {
        _compileForEach(block, ctx, emitter);
      } else if (block is CurrentItemBlock) {
        if (currentLoopItemText != null && currentLoopItemText.isNotEmpty) {
          emitter.emitKeyListStep(block.preKeys);
          emitter.emitStep(currentLoopItemText);
          emitter.emitKeyListStep(block.postKeys);
        }
      }
    }
  }

  static void _compileFieldInput(
    FieldInputBlock block,
    TypingCompileContext ctx,
    _StepEmitter emitter,
  ) {
    final rawVal = ctx.recordValues[block.fieldKey]?.toString() ?? '';
    final cleanVal = TypingTextNormalizer.normalize(rawVal);
    final isActive = effectiveActiveKeys(ctx).contains(block.fieldKey);

    // 判断该字段是否被跳过（未在生成子集中，或完全为空）
    final isSkipped = !isActive || cleanVal.isEmpty;

    if (!isSkipped) {
      // 1. 正常字段：执行输入前动作
      emitter.emitKeyListStep(block.preKeys);

      // 2. 敲入具体文本内容
      emitter.emitStep(cleanVal);

      // 3. 执行输入后动作
      emitter.emitKeyListStep(block.postKeys);
    } else {
      // 【流水线占位空跳】：该字段无内容，但为了保证光标从当前输入框准确跳到下一个输入框，
      // 不输入文字，照常执行后置导航键（如 {TAB}），完成跨格占位！
      emitter.emitKeyListStep(block.postKeys);
    }
  }

  static void _compileForEach(
    ForEachBlock block,
    TypingCompileContext ctx,
    _StepEmitter emitter,
  ) {
    final rawVal = ctx.recordValues[block.fieldKey]?.toString() ?? '';
    final cleanVal = TypingTextNormalizer.normalize(rawVal);
    if (cleanVal.isEmpty) return;

    final splitPattern = block.separator == ','
        ? RegExp(r'[\n,，；;]')
        : RegExp(r'[\n；;]');

    final items = cleanVal
        .split(splitPattern)
        .map((s) => s.trim().replaceAll(RegExp(r'^\d+[\.、]\s*'), '')) // 剥离序号
        .where((s) => s.isNotEmpty)
        .toList();

    for (final item in items) {
      _compileBlockList(
        blocks: block.subBlocks,
        ctx: ctx,
        emitter: emitter,
        currentLoopItemText: item,
      );
    }
  }

  static String _normalizeKeyTag(String tag) {
    final trimmed = tag.trim();
    if (trimmed.isEmpty) return '';
    if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
      return trimmed;
    }
    return '{$trimmed}';
  }
}

/// 积木动作步骤发射器：
/// 负责在任意两个相邻动作积木步骤之间（包括输入前动作 -> 具体输入内容 -> 输入后动作 -> 下一个积木）
/// 自动注入输入方案配置的系统反应延时（`{DELAY:ms}`），而单个前置/后置动作内部的多个按键之间不插入此延时。
class _StepEmitter {
  final StringBuffer _buffer = StringBuffer();
  final int stepDelayMs;
  bool _hasEmittedStep = false;

  _StepEmitter({required this.stepDelayMs});

  void emitStep(String stepPayload) {
    if (stepPayload.isEmpty) return;
    if (_hasEmittedStep && stepDelayMs > 0) {
      _buffer.write('{DELAY:$stepDelayMs}');
    }
    _buffer.write(stepPayload);
    _hasEmittedStep = true;
  }

  void emitKeyListStep(List<String> keys) {
    if (keys.isEmpty) return;
    final joined = keys
        .map(TypingCompiler._normalizeKeyTag)
        .where((s) => s.isNotEmpty)
        .join();
    emitStep(joined);
  }

  String buildResult() => _buffer.toString().trim();
}
