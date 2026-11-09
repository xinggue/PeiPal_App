import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/engine_b/typing_compiler.dart';
import 'package:peipal/data/services/engine_b/typing_text_normalizer.dart';
import 'package:peipal/domain/models/template.dart';
import 'package:peipal/domain/models/typing_action_block.dart';
import 'package:peipal/domain/models/typing_profile.dart';

void main() {
  group('Engine B - TypingTextNormalizer', () {
    test('strips zero-width spaces and normalizes CRLF to LF', () {
      const dirty = '主诉：发热\u200B3天\r\n伴咳嗽\r\n\uFEFF咽痛';
      final clean = TypingTextNormalizer.normalize(dirty);
      expect(clean, '主诉：发热3天\n伴咳嗽\n咽痛');
    });

    test('flattens multiline text to single line with semicolons', () {
      const multi = '高血压2级\n2型糖尿病\n冠心病';
      final single = TypingTextNormalizer.flattenMultilineToSingle(multi);
      expect(single, '高血压2级；2型糖尿病；冠心病');
    });
  });

  group('Engine B - TypingCompiler Modes', () {
    final s1 = const TemplateSlot(
      key: 'chief_complaint',
      label: '主诉',
      type: SlotType.text,
      preKeys: ['{TAB}'],
      postKeys: ['{ENTER}'],
    );
    final s2 = const TemplateSlot(
      key: 'hpi',
      label: '现病史',
      type: SlotType.multiline,
      preKeys: ['{TAB}'],
      postKeys: ['{ENTER}'],
    );
    final s3 = const TemplateSlot(
      key: 'past_history',
      label: '既往史',
      type: SlotType.multiline,
      preKeys: ['{TAB}'],
      postKeys: ['{ENTER}'],
    );

    final template = Template(
      id: 't1',
      name: '标准门诊病历',
      slots: [s1, s2, s3],
    );

    final profile = TypingProfile(
      name: '标准方案',
      postKeySettleMs: 80,
    );

    final recordValues = {
      'chief_complaint': '发热3天',
      'hpi': '', // 未生成/为空
      'past_history': '否认高血压病史',
    };

    test('Mode 1: pipelineKeepFlow performs keep-flow stepping for empty/unselected slots', () {
      final gcode = TypingCompiler.compile(TypingCompileContext(
        template: template,
        profile: profile,
        recordValues: recordValues,
        activeSlotKeys: {'chief_complaint', 'past_history'}, // hpi is skipped
        mode: TypingSendMode.pipelineKeepFlow,
      ));

      // chief_complaint is typed: {TAB}{DELAY:80}发热3天{DELAY:80}{ENTER}
      // followed by {DELAY:80} before hpi's postKey {ENTER},
      // followed by {DELAY:80} before past_history's preKey {TAB}
      expect(
        gcode,
        '{TAB}{DELAY:80}发热3天{DELAY:80}{ENTER}'
        '{DELAY:80}{ENTER}'
        '{DELAY:80}{TAB}{DELAY:80}否认高血压病史{DELAY:80}{ENTER}',
      );
    });

    test('Multiple keys inside preKeys or postKeys have no internal step delay, while inter-step delays are inserted between all blocks', () {
      final multiKeySlot1 = const TemplateSlot(
        key: 'f1',
        label: '字段1',
        type: SlotType.text,
        preKeys: ['{TAB}', '{SPACE}'],
        postKeys: ['{ENTER}', '{TAB}'],
      );
      final multiKeySlot2 = const TemplateSlot(
        key: 'f2',
        label: '字段2',
        type: SlotType.text,
        preKeys: ['{DOWN}'],
        postKeys: ['{ENTER}'],
      );
      final multiTemplate = Template(
        id: 't_multi',
        name: '多键测试',
        slots: [multiKeySlot1, multiKeySlot2],
      );

      final gcode = TypingCompiler.compile(TypingCompileContext(
        template: multiTemplate,
        profile: TypingProfile(name: '测试方案', postKeySettleMs: 100),
        recordValues: {'f1': '内容A', 'f2': '内容B'},
        activeSlotKeys: {'f1', 'f2'},
        mode: TypingSendMode.pipelineKeepFlow,
      ));

      // Within preKeys: {TAB}{SPACE} (no {DELAY:100} between them)
      // Within postKeys: {ENTER}{TAB} (no {DELAY:100} between them)
      // Between preKeys -> 内容A -> postKeys -> next preKeys -> 内容B -> next postKeys: {DELAY:100} everywhere
      expect(
        gcode,
        '{TAB}{SPACE}{DELAY:100}内容A{DELAY:100}{ENTER}{TAB}'
        '{DELAY:100}{DOWN}{DELAY:100}内容B{DELAY:100}{ENTER}',
      );
    });

    test('Inserts step delay between arbitrary blocks (GroupBlock, KeyCombo, LiteralText, FieldInput)', () {
      final blockProfile = TypingProfile(
        name: '积木流方案',
        postKeySettleMs: 60,
        blocks: [
          GroupBlock(
            name: '启动记事本',
            blocks: [
              KeyComboBlock(combo: '{WIN+R}'),
              LiteralTextBlock(text: 'notepad'),
              KeyComboBlock(combo: '{ENTER}'),
            ],
          ),
          FieldInputBlock(
            fieldKey: 'chief_complaint',
            preKeys: const [],
            postKeys: const ['{ENTER}'],
          ),
        ],
      );

      final gcode = TypingCompiler.compile(TypingCompileContext(
        template: template,
        profile: blockProfile,
        recordValues: {'chief_complaint': '发热3天'},
        activeSlotKeys: {'chief_complaint'},
        mode: TypingSendMode.pipelineKeepFlow,
      ));

      expect(
        gcode,
        '{WIN+R}{DELAY:60}notepad{DELAY:60}{ENTER}{DELAY:60}发热3天{DELAY:60}{ENTER}',
      );
    });

    test('Mode 2: plainTextFlatten flattens active fields by lines', () {
      final text = TypingCompiler.compile(TypingCompileContext(
        template: template,
        profile: profile,
        recordValues: recordValues,
        activeSlotKeys: {'chief_complaint', 'past_history'},
        mode: TypingSendMode.plainTextFlatten,
      ));

      expect(text, '【主诉】发热3天\n【既往史】否认高血压病史');
      expect(text.contains('【现病史】'), isFalse);
    });

    test('Mode 3: interactiveDirect only compiles requested target slots', () {
      final gcode = TypingCompiler.compile(TypingCompileContext(
        template: template,
        profile: profile,
        recordValues: recordValues,
        activeSlotKeys: {'chief_complaint', 'past_history'},
        mode: TypingSendMode.interactiveDirect,
        targetSlotKeysForDirect: {'chief_complaint'}, // Only send chief complaint
      ));

      expect(gcode, '{TAB}{DELAY:80}发热3天{DELAY:80}{ENTER}');
      expect(gcode.contains('否认高血压病史'), isFalse);
    });

    test('empty active keys and no input flow still flatten valued fields', () {
      final lone = Template(
        id: 't-lone',
        name: '单字段',
        slots: const [
          TemplateSlot(key: 'note', label: '记录', type: SlotType.multiline),
        ],
      );
      final text = TypingCompiler.compile(TypingCompileContext(
        template: lone,
        profile: TypingProfile(name: '默认方案'),
        recordValues: const {'note': '仅此一段'},
        activeSlotKeys: const {},
        mode: TypingSendMode.pipelineKeepFlow,
      ));
      expect(text, '仅此一段');
    });

    test('partial record with empty active keys still types the filled field', () {
      final text = TypingCompiler.compile(TypingCompileContext(
        template: template,
        profile: profile,
        recordValues: const {'chief_complaint': '头痛1天', 'hpi': '', 'past_history': ''},
        activeSlotKeys: const {},
        mode: TypingSendMode.plainTextFlatten,
      ));
      expect(text, '【主诉】头痛1天');
    });

    test('RhythmActionBlock compiles to {CFG:...}', () {
      final customProfile = TypingProfile(
        name: '调速方案',
        blocks: [
          RhythmActionBlock(
            presetName: '稳妥模式',
            params: {'cjk_gap_ms': 30, 'tap_press_ms': 10},
          ),
          FieldInputBlock(
            fieldKey: 'chief_complaint',
            preKeys: ['{TAB}'],
            postKeys: ['{ENTER}'],
          ),
        ],
      );

      final gcode = TypingCompiler.compile(TypingCompileContext(
        template: template,
        profile: customProfile,
        recordValues: {'chief_complaint': '咳嗽'},
        activeSlotKeys: {'chief_complaint'},
        mode: TypingSendMode.pipelineKeepFlow,
      ));

      expect(gcode, contains('{CFG:cjk_gap_ms=30.0 tap_press_ms=10.0}'));
      expect(gcode, contains('{DELAY:300}'));
      expect(gcode, contains('咳嗽'));
    });
  });
}
