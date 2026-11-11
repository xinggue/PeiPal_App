import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/ble/timing_params.dart';
import 'package:peipal/data/services/ble/typing_estimate.dart';

void main() {
  group('TypingDurationEstimator', () {
    final timing = defaultTimingValues();

    test('pure CJK text follows Alt-code per-char cost', () {
      // default: hold=3, digit_press=3, digit_release=3, alt_release=3, cjk_gap=3
      // per char = 3 + 15 + 12 + 6 + 3 = 39ms, plus 150ms startup
      final ms = TypingDurationEstimator.estimate('主诉发热三天', timing);
      expect(ms, 150 + 6 * 39);
    });

    test('key tags and DELAY are counted explicitly', () {
      const text = '主诉：无殊{DELAY:80}{ENTER}';
      // 5 CJK/punct chars × 39 + DL80 + ENTER(20+20) + startup 150
      final expected = 150 + 5 * 39 + 80 + 40;
      expect(TypingDurationEstimator.estimate(text, timing), expected);
    });

    test('ASCII string uses ascii gap when alt_ascii enabled', () {
      final ms = TypingDurationEstimator.estimate('ABC', timing);
      // alt_ascii default on: per char = 36 + ascii_gap 20 = 56
      expect(ms, 150 + 3 * 56);
    });

    test('ascii_gap is not applied when alt_ascii disabled', () {
      final noAlt = {...timing, 'alt_ascii': 0.0};
      final ms = TypingDurationEstimator.estimate('ab', noAlt);
      // 2 × (key_press 20 + key_gap 20)
      expect(ms, 150 + 2 * 40);
    });

    test('empty text yields zero', () {
      expect(TypingDurationEstimator.estimate('', timing), 0);
    });
  });
}
