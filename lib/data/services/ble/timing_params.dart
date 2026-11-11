import 'dart:convert';
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// 统一精简后的核心物理参数定义
class TimingParamSpec {
  final String key;
  final String label;
  final String shortLabel;
  final String description; // 对应参数的通俗物理含义说明
  final String unit;
  final double min;
  final double max;
  final double step;
  final double def;
  final bool flag;

  const TimingParamSpec({
    required this.key,
    required this.label,
    required this.shortLabel,
    required this.description,
    required this.min,
    required this.max,
    required this.step,
    required this.def,
    this.unit = 'ms',
    this.flag = false,
  });
}

/// 核心参数规格表（严格区分汉字合成间隔与普通字符/按键间隔）
const List<TimingParamSpec> timingParamSpecs = [
  // 阵营 A：Alt + 小键盘 5 连击引擎 (中文字符)
  TimingParamSpec(
    key: 'alt_hold_ms',
    label: 'Alt 前置按住',
    shortLabel: 'Alt前置',
    description: 'Alt 键按下后保持多久才开始敲第 1 个小键盘数字，确保系统进入组合状态。',
    min: 1,
    max: 50,
    step: 0.5,
    def: 3.0,
  ),
  TimingParamSpec(
    key: 'alt_digit_press',
    label: '小键盘数字按下',
    shortLabel: '数字按下',
    description: '小键盘数字 0-9 每个单键按下的物理保持时长。',
    min: 1,
    max: 50,
    step: 0.5,
    def: 3.0,
  ),
  TimingParamSpec(
    key: 'alt_digit_release',
    label: '数字之间间隔',
    shortLabel: '数字间隔',
    description: '前 4 个小键盘数字松开后，到下一个数字按下之间的短暂间隙。',
    min: 1,
    max: 50,
    step: 0.5,
    def: 3.0,
  ),
  TimingParamSpec(
    key: 'alt_release_ms',
    label: 'Alt 尾持时长',
    shortLabel: 'Alt尾持',
    description: '第 5 个数字键松开后，Alt 键多按住多久再释放，供 Windows 完成字符合成。',
    min: 1,
    max: 50,
    step: 0.5,
    def: 3.0,
  ),
  TimingParamSpec(
    key: 'cjk_gap_ms',
    label: '汉字合成间隔',
    shortLabel: '汉字间隔',
    description: '上一个汉字合成上屏彻底结束后，至少等待多久才开始下一个汉字输入。',
    min: 1,
    max: 200,
    step: 1.0,
    def: 3.0,
  ),

  // 阵营 B：普通字符 / 功能键 / 组合键控制
  TimingParamSpec(
    key: 'ascii_gap_ms',
    label: '普通字符间隔',
    shortLabel: '单字间隔',
    description: '普通英文字母、数字单键打字结束后的间隙停顿。',
    min: 1,
    max: 100,
    step: 1.0,
    def: 20.0,
  ),
  TimingParamSpec(
    key: 'key_press_ms',
    label: '功能按键按下',
    shortLabel: '按键按下',
    description: 'Tab、Enter、功能键或组合键在物理按下后的保持时长。',
    min: 1,
    max: 200,
    step: 1.0,
    def: 20.0,
  ),
  TimingParamSpec(
    key: 'key_gap_ms',
    label: '功能按键后停顿',
    shortLabel: '按键停顿',
    description: '按下 Tab、Enter 等功能键后等待表单焦点切换、页面响应的安全稳态保护时长。',
    min: 1,
    max: 500,
    step: 5.0,
    def: 20.0,
  ),

  // 阵营 C：全局硬件开关（默认开启自愈，保留英文 Alt 码防输入法开关）
  TimingParamSpec(
    key: 'numlock_auto',
    label: '打字前自愈 NumLock/Caps',
    shortLabel: '自动自愈',
    description: '首字输入前自动检测并点亮 NumLock、关闭 CapsLock，保证小键盘 Alt 码绝对正常。',
    min: 0,
    max: 1,
    step: 1,
    def: 1,
    unit: '',
    flag: true,
  ),
  TimingParamSpec(
    key: 'alt_ascii',
    label: '英文符号走 Alt 码 (防中文输入法)',
    shortLabel: '防输入法',
    description: '开启后英文、数字与符号也通过 Alt 码直接上屏，彻底绕过 Windows 搜狗/微软输入法候选框。',
    min: 0,
    max: 1,
    step: 1,
    def: 1,
    unit: '',
    flag: true,
  ),

  // 阵营 D：长文本自愈与防粘滞保护
  TimingParamSpec(
    key: 'fence_auto',
    label: '长文本防粘滞硬重置',
    shortLabel: '防粘滞重置',
    description: '每输入设定字数后，在物理动作彻底完成的空歇期，向电脑发送全零清空释放帧，根治按键粘滞乱码。',
    min: 0,
    max: 1,
    step: 1,
    def: 1,
    unit: '',
    flag: true,
  ),
  TimingParamSpec(
    key: 'shake_auto',
    label: '闭环握手翻转自检',
    shortLabel: '翻转自检',
    description: '通过敲击 CapsLock 翻转并回读状态，物理闭环验证 USB 通信链路活性（遇严重系统卡顿环境可选用）。',
    min: 0,
    max: 1,
    step: 1,
    def: 0,
    unit: '',
    flag: true,
  ),
  TimingParamSpec(
    key: 'check_interval',
    label: '自检触发周期 (字数)',
    shortLabel: '自检周期',
    description: '每完成多少个物理动作/字符输入后，触发一次安全的硬重置释放与自愈检测。',
    min: 5,
    max: 50,
    step: 1,
    def: 15,
    unit: '字',
  ),
];

/// 一套完整的命名时序预设（可保存到 App，并在输入流程中成套切换）
class TimingPreset {
  final String id;
  final String name;
  final Map<String, double> values;
  final bool isBuiltIn;

  TimingPreset({
    String? id,
    required this.name,
    required Map<String, double> values,
    this.isBuiltIn = false,
  })  : id = id ?? _uuid.v4(),
        values = {
          for (final s in timingParamSpecs) s.key: values[s.key] ?? s.def,
        };

  TimingPreset copyWith({
    String? name,
    Map<String, double>? values,
  }) =>
      TimingPreset(
        id: id,
        name: name ?? this.name,
        values: values ?? Map.of(this.values),
        isBuiltIn: isBuiltIn,
      );

  /// 计算单个中文字符（Alt+5位数字+间隔）的总耗时（毫秒）
  double get singleCharTotalMs {
    final hold = values['alt_hold_ms'] ?? 1.0;
    final dPress = values['alt_digit_press'] ?? 3.5;
    final dRel = values['alt_digit_release'] ?? 0.5;
    final altRel = values['alt_release_ms'] ?? 3.0;
    final gap = values['cjk_gap_ms'] ?? 2.0;
    // 对齐固件：alt_release 共等待两次
    return hold + (5 * dPress) + (4 * dRel) + (2 * altRel) + gap;
  }

  /// 估算每秒打字速度（字/秒）
  double get estimatedCharsPerSec {
    final total = singleCharTotalMs;
    if (total <= 0) return 0;
    return 1000.0 / total;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'values': values,
        'isBuiltIn': isBuiltIn,
      };

  factory TimingPreset.fromJson(Map<String, dynamic> json) {
    final rawMap = json['values'] as Map? ?? {};
    final parsedValues = <String, double>{};
    for (final s in timingParamSpecs) {
      final v = rawMap[s.key];
      if (v is num) {
        parsedValues[s.key] = v.toDouble();
      } else if (v != null) {
        parsedValues[s.key] = double.tryParse(v.toString()) ?? s.def;
      } else {
        parsedValues[s.key] = s.def;
      }
    }
    return TimingPreset(
      id: json['id'] as String?,
      name: json['name'] as String? ?? '未命名预设',
      values: parsedValues,
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
    );
  }
}

/// 经典输入节奏预设体系（按速度梯度覆盖常见场景）
final List<TimingPreset> kBuiltInTimingPresets = [
  TimingPreset(
    id: 'preset_ultra_fast',
    name: '理论最快',
    isBuiltIn: true,
    values: {
      'alt_hold_ms': 1.0,
      'alt_digit_press': 1.0,
      'alt_digit_release': 1.0,
      'alt_release_ms': 1.0,
      'cjk_gap_ms': 1.0,
      'ascii_gap_ms': 20.0,
      'key_press_ms': 20.0,
      'key_gap_ms': 20.0,
      'numlock_auto': 1.0,
      'alt_ascii': 1.0,
      'fence_auto': 1.0,
      'shake_auto': 0.0,
      'check_interval': 15.0,
    },
  ),
  TimingPreset(
    id: 'preset_very_fast',
    name: '极快',
    isBuiltIn: true,
    values: {
      'alt_hold_ms': 1.5,
      'alt_digit_press': 1.5,
      'alt_digit_release': 1.5,
      'alt_release_ms': 1.5,
      'cjk_gap_ms': 1.5,
      'ascii_gap_ms': 20.0,
      'key_press_ms': 20.0,
      'key_gap_ms': 20.0,
      'numlock_auto': 1.0,
      'alt_ascii': 1.0,
      'fence_auto': 1.0,
      'shake_auto': 0.0,
      'check_interval': 15.0,
    },
  ),
  TimingPreset(
    id: 'preset_fast',
    name: '较快',
    isBuiltIn: true,
    values: {
      'alt_hold_ms': 2.0,
      'alt_digit_press': 2.0,
      'alt_digit_release': 2.0,
      'alt_release_ms': 2.0,
      'cjk_gap_ms': 2.0,
      'ascii_gap_ms': 20.0,
      'key_press_ms': 20.0,
      'key_gap_ms': 20.0,
      'numlock_auto': 1.0,
      'alt_ascii': 1.0,
      'fence_auto': 1.0,
      'shake_auto': 0.0,
      'check_interval': 15.0,
    },
  ),
  TimingPreset(
    id: 'preset_standard',
    name: '适中 (默认)',
    isBuiltIn: true,
    values: {
      'alt_hold_ms': 3.0,
      'alt_digit_press': 3.0,
      'alt_digit_release': 3.0,
      'alt_release_ms': 3.0,
      'cjk_gap_ms': 3.0,
      'ascii_gap_ms': 20.0,
      'key_press_ms': 20.0,
      'key_gap_ms': 20.0,
      'numlock_auto': 1.0,
      'alt_ascii': 1.0,
      'fence_auto': 1.0,
      'shake_auto': 0.0,
      'check_interval': 15.0,
    },
  ),
  TimingPreset(
    id: 'preset_steady',
    name: '较慢稳妥',
    isBuiltIn: true,
    values: {
      'alt_hold_ms': 5.0,
      'alt_digit_press': 5.0,
      'alt_digit_release': 5.0,
      'alt_release_ms': 5.0,
      'cjk_gap_ms': 5.0,
      'ascii_gap_ms': 20.0,
      'key_press_ms': 20.0,
      'key_gap_ms': 20.0,
      'numlock_auto': 1.0,
      'alt_ascii': 1.0,
      'fence_auto': 1.0,
      'shake_auto': 0.0,
      'check_interval': 15.0,
    },
  ),
  TimingPreset(
    id: 'preset_manual_pace',
    name: '手打速度',
    isBuiltIn: true,
    values: {
      'alt_hold_ms': 10.0,
      'alt_digit_press': 10.0,
      'alt_digit_release': 10.0,
      'alt_release_ms': 10.0,
      'cjk_gap_ms': 10.0,
      'ascii_gap_ms': 20.0,
      'key_press_ms': 20.0,
      'key_gap_ms': 20.0,
      'numlock_auto': 1.0,
      'alt_ascii': 1.0,
      'fence_auto': 1.0,
      'shake_auto': 0.0,
      'check_interval': 15.0,
    },
  ),
];

Map<String, double> defaultTimingValues() => {
      for (final s in timingParamSpecs) s.key: s.def,
    };

/// 把一组值拼成固件可消费的命令文本：{CFG:key=v key=v ...}
/// 保证 cjk_gap_ms 与 ascii_gap_ms 独立下发，并兼容旧固件映射
String buildTimingCfg(Map<String, double> values, {bool includeLegacyMapping = true}) {
  final clamped = clampTimingValues(values);
  final parts = <String>[];
  for (final s in timingParamSpecs) {
    final v = clamped[s.key];
    if (v == null) continue;
    parts.add('${s.key}=${fmtNumber(v)}');
  }

  // 向下兼容映射：把统一的 key_press_ms 和 key_gap_ms 同步赋值给旧固件字段
  if (includeLegacyMapping) {
    final kp = clamped['key_press_ms'];
    final kg = clamped['key_gap_ms'];
    if (kp != null) {
      parts.add('tap_press_ms=${fmtNumber(kp)}');
      parts.add('shift_press_ms=${fmtNumber(kp)}');
      parts.add('enter_press_ms=${fmtNumber(kp)}');
      parts.add('tab_press_ms=${fmtNumber(kp)}');
    }
    if (kg != null) {
      parts.add('tap_release_ms=${fmtNumber(kg)}');
      parts.add('shift_release_ms=${fmtNumber(kg)}');
      parts.add('enter_release_ms=${fmtNumber(kg)}');
      parts.add('tab_release_ms=${fmtNumber(kg)}');
    }
  }

  return parts.isEmpty ? '' : '{CFG:${parts.join(' ')}}';
}

/// 数字输出：整数不带小数尾（5 → "5"），否则保留一位小数（3.5 → "3.5"）。
String fmtNumber(double v) =>
    v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

/// 解析固件 {CFG?} 回显，自动归纳到统一参数
Map<String, double>? parseCfgEcho(String line) {
  if (!line.startsWith('CFG:')) return null;
  final body = line.substring(4).trim();
  if (body.isEmpty) return null;
  final raw = <String, double>{};
  for (final part in body.split(' ')) {
    final eq = part.indexOf('=');
    if (eq <= 0) continue;
    final k = part.substring(0, eq).trim().toLowerCase();
    final v = double.tryParse(part.substring(eq + 1).trim());
    if (v != null) raw[k] = v;
  }
  if (raw.isEmpty) return null;

  final map = defaultTimingValues();
  for (final s in timingParamSpecs) {
    if (raw.containsKey(s.key)) {
      map[s.key] = raw[s.key]!;
    }
  }
  if (!raw.containsKey('key_press_ms') && raw.containsKey('tap_press_ms')) {
    map['key_press_ms'] = raw['tap_press_ms']!;
  }
  if (!raw.containsKey('key_gap_ms') && raw.containsKey('tap_release_ms')) {
    map['key_gap_ms'] = raw['tap_release_ms']!;
  }
  return clampTimingValues(map);
}

/// 毫秒类参数下限 1ms（USB 帧极限）。开关和自检字数不抬。
Map<String, double> clampTimingValues(Map<String, double> values) {
  final map = Map<String, double>.from(values);
  for (final s in timingParamSpecs) {
    if (s.flag || s.unit != 'ms') continue;
    final v = map[s.key] ?? s.def;
    map[s.key] = v.clamp(s.min, s.max);
  }
  return map;
}

/// 两套参数是否逐项完全一致（先按规格夹紧再比）。
bool timingValuesEqual(Map<String, double> a, Map<String, double> b) {
  final left = clampTimingValues(a);
  final right = clampTimingValues(b);
  for (final s in timingParamSpecs) {
    if ((left[s.key] ?? s.def) != (right[s.key] ?? s.def)) return false;
  }
  return true;
}

String encodeTimingJson(Map<String, double> values) =>
    jsonEncode({for (final s in timingParamSpecs) s.key: (values[s.key] ?? s.def)});

Map<String, double>? decodeTimingJson(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final map = <String, double>{};
    for (final s in timingParamSpecs) {
      final rawVal = decoded[s.key];
      if (rawVal == null) {
        map[s.key] = s.def;
        continue;
      }
      final parsed = rawVal is num
          ? rawVal.toDouble()
          : double.tryParse(rawVal.toString());
      map[s.key] = parsed ?? s.def;
    }
    return map;
  } catch (_) {
    return null;
  }
}

String encodePresetsListJson(List<TimingPreset> presets) =>
    jsonEncode(presets.map((p) => p.toJson()).toList());

List<TimingPreset> decodePresetsListJson(String? raw) {
  if (raw == null || raw.trim().isEmpty) {
    return List<TimingPreset>.from(kBuiltInTimingPresets);
  }
  try {
    final list = jsonDecode(raw) as List;
    final loaded = list
        .whereType<Map>()
        .map((m) => TimingPreset.fromJson(m.cast<String, dynamic>()))
        .toList();
    if (loaded.isEmpty) return List<TimingPreset>.from(kBuiltInTimingPresets);

    // 智能合并机制：保留用户自定义预设的同时，自动合并或更新最新内置预设
    final merged = <TimingPreset>[];
    for (final b in kBuiltInTimingPresets) {
      merged.add(b);
    }
    for (final custom in loaded) {
      if (!custom.isBuiltIn && !merged.any((p) => p.id == custom.id || p.name == custom.name)) {
        merged.add(custom);
      }
    }
    return merged;
  } catch (_) {
    return List<TimingPreset>.from(kBuiltInTimingPresets);
  }
}
