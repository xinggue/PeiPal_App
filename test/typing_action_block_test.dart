import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/domain/models/template.dart';
import 'package:peipal/domain/models/typing_action_block.dart';
import 'package:peipal/domain/models/typing_profile.dart';

void main() {
  group('TypingActionBlock JSON Serialization', () {
    test('FieldInputBlock serializes and deserializes', () {
      final block = FieldInputBlock(
        fieldKey: 'chief_complaint',
        preKeys: ['{TAB}'],
        postKeys: ['{ENTER}'],
      );
      final json = block.toJson();
      final revived = TypingActionBlock.fromJson(json) as FieldInputBlock;

      expect(revived.fieldKey, 'chief_complaint');
      expect(revived.preKeys, ['{TAB}']);
      expect(revived.postKeys, ['{ENTER}']);
    });

    test('KeyComboBlock serializes and deserializes', () {
      final block = KeyComboBlock(combo: '{WIN+R}');
      final json = block.toJson();
      final revived = TypingActionBlock.fromJson(json) as KeyComboBlock;

      expect(revived.combo, '{WIN+R}');
    });

    test('DelayBlock serializes and deserializes', () {
      final block = DelayBlock(durationMs: 350);
      final json = block.toJson();
      final revived = TypingActionBlock.fromJson(json) as DelayBlock;

      expect(revived.durationMs, 350);
    });

    test('LiteralTextBlock serializes and deserializes', () {
      final block = LiteralTextBlock(text: 'notepad');
      final json = block.toJson();
      final revived = TypingActionBlock.fromJson(json) as LiteralTextBlock;

      expect(revived.text, 'notepad');
    });

    test('GroupBlock with nested blocks serializes and deserializes', () {
      final group = GroupBlock(
        name: '记事本启动流',
        blocks: [
          KeyComboBlock(combo: '{WIN+R}'),
          DelayBlock(durationMs: 200),
          LiteralTextBlock(text: 'notepad'),
          KeyComboBlock(combo: '{ENTER}'),
        ],
      );
      final json = group.toJson();
      final revived = TypingActionBlock.fromJson(json) as GroupBlock;

      expect(revived.name, '记事本启动流');
      expect(revived.blocks.length, 4);
      expect((revived.blocks[0] as KeyComboBlock).combo, '{WIN+R}');
    });

    test('ForEachBlock with nested subBlocks serializes and deserializes', () {
      final forEach = ForEachBlock(
        fieldKey: 'diagnoses',
        separator: r'\n',
        subBlocks: [
          CurrentItemBlock(),
          KeyComboBlock(combo: '{DOWN}'),
          KeyComboBlock(combo: '{ENTER}'),
        ],
      );

      final json = forEach.toJson();
      final revived = TypingActionBlock.fromJson(json) as ForEachBlock;

      expect(revived.fieldKey, 'diagnoses');
      expect(revived.separator, r'\n');
      expect(revived.subBlocks.length, 3);
      expect(revived.subBlocks[0].type, ActionBlockType.currentItem);
      expect((revived.subBlocks[1] as KeyComboBlock).combo, '{DOWN}');
    });
  });

  group('TypingProfile integration with blocks', () {
    test('effectiveBlocks generates sequential FieldInputBlocks when blocks is empty', () {
      final slots = [
        const TemplateSlot(key: 's1', label: '主诉', type: SlotType.text, preKeys: ['{TAB}'], order: 0),
        const TemplateSlot(key: 's2', label: '现病史', type: SlotType.multiline, postKeys: ['{ENTER}'], order: 1),
      ];
      final profile = TypingProfile(name: '默认方案');

      final blocks = profile.effectiveBlocks(slots);
      expect(blocks.length, 2);
      expect(blocks[0].type, ActionBlockType.fieldInput);
      expect((blocks[0] as FieldInputBlock).fieldKey, 's1');
      expect((blocks[0] as FieldInputBlock).preKeys, ['{TAB}']);
      expect((blocks[1] as FieldInputBlock).fieldKey, 's2');
      expect((blocks[1] as FieldInputBlock).postKeys, ['{ENTER}']);
    });

    test('TypingProfile with explicit blocks serializes and duplicates cleanly', () {
      final profile = TypingProfile(
        name: '记事本流',
        blocks: [
          KeyComboBlock(combo: '{WIN+R}'),
          LiteralTextBlock(text: 'notepad'),
          KeyComboBlock(combo: '{ENTER}'),
        ],
      );

      final json = profile.toJson();
      final revived = TypingProfile.fromJson(json);

      expect(revived.name, '记事本流');
      expect(revived.blocks.length, 3);
      expect((revived.blocks[0] as KeyComboBlock).combo, '{WIN+R}');

      final dup = profile.duplicate('记事本流 (副本)');
      expect(dup.name, '记事本流 (副本)');
      expect(dup.blocks.length, 3);
      expect(dup.id != profile.id, isTrue);
    });

    test('TypingBlockPreset serializes, converts to GroupBlock, and encodes/decodes list', () {
      final preset = TypingBlockPreset(
        name: '自定义预设',
        description: '测试预设说明',
        blocks: [
          KeyComboBlock(combo: '{CTRL+A}'),
          LiteralTextBlock(text: 'test'),
        ],
      );

      final group = preset.toGroupBlock();
      expect(group.name, '自定义预设');
      expect(group.blocks.length, 2);
      expect(group.blocks[0].id != preset.blocks[0].id, isTrue);

      final encoded = encodeBlockPresetsListJson([preset]);
      final decoded = decodeBlockPresetsListJson(encoded);
      expect(decoded.length, 1);
      expect(decoded.first.name, '自定义预设');
      expect(decoded.first.description, '测试预设说明');
      expect(decoded.first.stepsPreview, '{CTRL+A} ➔ "test"');
    });
  });
}
