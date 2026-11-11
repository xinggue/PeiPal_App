import 'timing_params.dart';

/// 逐字符耗时估算器：严格对齐固件实际按键节奏，用于悬浮窗进度与剩余时间预估。
///
/// 固件真实耗时（CH9329 / 原生 HID 两条链路一致）：
/// - Alt 码字符：alt_hold + 5×digit_press + 4×digit_release + 2×alt_release + 字符间隔
/// - 普通 ASCII（alt_ascii 关闭）：key_press + key_gap（大写/符号含 Shift 双倍）
/// - 按键标签 {ENTER}/{TAB}/...：key_press + key_gap
/// - {DELAY:ms}：原样计入
/// - 固件自检栅栏：每 check_interval 个动作额外约 15ms
class TypingDurationEstimator {
  static const double _startupOverheadMs = 150;

  static int estimate(String text, Map<String, double> timingValues) {
    if (text.isEmpty) return 0;
    final v = {...defaultTimingValues(), ...timingValues};

    final altAscii = (v['alt_ascii'] ?? 1) >= 0.5;
    final hold = v['alt_hold_ms'] ?? 3;
    final digitPress = v['alt_digit_press'] ?? 3;
    final digitRelease = v['alt_digit_release'] ?? 3;
    final altRelease = v['alt_release_ms'] ?? 3;
    final cjkGap = v['cjk_gap_ms'] ?? 3;
    final asciiGap = v['ascii_gap_ms'] ?? 20;
    final keyPress = v['key_press_ms'] ?? 20;
    final keyGap = v['key_gap_ms'] ?? 20;
    final fenceAuto = (v['fence_auto'] ?? 1) >= 0.5;
    final checkInterval = v['check_interval'] ?? 15;

    final altCharMs = hold + 5 * digitPress + 4 * digitRelease + 2 * altRelease;
    final keyMs = keyPress + keyGap;

    double total = _startupOverheadMs;
    var actions = 0;
    var i = 0;

    while (i < text.length) {
      final ch = text[i];

      if (ch == '{') {
        final end = text.indexOf('}', i + 1);
        if (end != -1) {
          final token = text.substring(i + 1, end).trim();
          final upper = token.toUpperCase();

          if (upper.startsWith('DELAY:')) {
            final ms = double.tryParse(upper.substring(6).trim());
            if (ms != null && ms > 0) total += ms;
            i = end + 1;
            continue;
          }
          // 纯指令标签不产生击键耗时
          if (upper.startsWith('DONE') ||
              upper.startsWith('CFG') ||
              upper.startsWith('NAME') ||
              upper.startsWith('NUM?') ||
              upper.startsWith('STOP') ||
              upper.startsWith('ABORT')) {
            i = end + 1;
            continue;
          }
          // 其余标签均按一次功能按键处理
          total += keyMs;
          actions++;
          i = end + 1;
          continue;
        }
      }

      if (ch == '\n' || ch == '\r' || ch == '\t') {
        total += keyMs;
        actions++;
        i++;
        continue;
      }

      final code = ch.codeUnitAt(0);
      if (code < 0x80) {
        if (altAscii && code >= 0x20 && code <= 0x7E) {
          total += altCharMs + asciiGap;
        } else {
          total += _asciiNeedsShift(ch) ? keyMs * 2 : keyMs;
        }
      } else {
        total += altCharMs + cjkGap;
      }
      actions++;
      i++;
    }

    if (fenceAuto && checkInterval > 0) {
      total += (actions / checkInterval).floor() * 15.0;
    }

    return total.round().clamp(100, 3600000);
  }

  static bool _asciiNeedsShift(String ch) {
    final code = ch.codeUnitAt(0);
    if (code >= 0x41 && code <= 0x5A) return true; // A-Z
    const symbols = '!@#\$%^&*()_+{}|:"<>?~';
    return symbols.contains(ch);
  }
}
