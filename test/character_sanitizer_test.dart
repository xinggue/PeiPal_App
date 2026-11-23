import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/ble/character_sanitizer.dart';
import 'package:peipal/providers/providers.dart';

import 'tutorial_test.dart' show MockSettingsRepo;

void main() {
  test('固件已支持的引号和医疗符号不再被默认替换或报不支持', () {
    const nativeChars = ['‘', '’', '“', '”', '◎', '♀', '♂', '℃', '±', '≤', '≥'];
    for (final ch in nativeChars) {
      expect(
        CharacterSanitizer.isSupportedByFirmware(ch.runes.single),
        isTrue,
        reason: '$ch 应被固件白名单直接支持',
      );
      expect(kDefaultReplacementRules.containsKey(ch), isFalse);
    }

    const sample = '患者主诉：“偶发胸闷”，体征：♀ ◎ 37.2℃，±0.5';
    expect(CharacterSanitizer.findUnsupportedCharacters(sample), isEmpty);
    expect(
      CharacterSanitizer.applyReplacements(sample, kDefaultReplacementRules),
      sample,
    );
  });

  test('敏感花括号与上标降级规则保持有效', () {
    const raw = '面积 12m²，体积 5cm³，注意 {非标签} 与 {TAB}';
    expect(CharacterSanitizer.findUnsupportedCharacters('12m² 5cm³'), isEmpty);
    expect(CharacterSanitizer.hasBracesInText(raw), isTrue);
    expect(
      CharacterSanitizer.applyReplacements(raw, kDefaultReplacementRules),
      '面积 12m^2，体积 5cm^3，注意 ｛非标签｝ 与 {TAB}',
    );
  });

  test('加载旧版已持久化规则时清理固件已支持符号并补全默认规则', () async {
    final settings = MockSettingsRepo();
    // 模拟旧版规则里保存了 4 个弯引号且缺少了 '{', '}', '℉', '•'（总长度与迁移后不一致或一致均需写回）
    settings.data['char_replacement_rules'] = json.encode({
      '‘': '\'',
      '’': '\'',
      '“': '"',
      '”': '"',
      '™': '(TM)',
      '★': '*',
    });

    final container = ProviderContainer(
      overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
    );
    addTearDown(container.dispose);

    container.read(charReplacementRulesProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    final rules = container.read(charReplacementRulesProvider);
    expect(rules.containsKey('‘'), isFalse);
    expect(rules.containsKey('’'), isFalse);
    expect(rules.containsKey('“'), isFalse);
    expect(rules.containsKey('”'), isFalse);
    expect(rules.containsKey('★'), isFalse);
    expect(rules['{'], '｛');
    expect(rules['²'], '^2');

    final persisted =
        json.decode(settings.data['char_replacement_rules']!) as Map<String, dynamic>;
    expect(persisted.containsKey('“'), isFalse);
    expect(persisted['{'], '｛');
  });
}
