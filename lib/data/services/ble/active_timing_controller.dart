import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/settings_repository.dart';
import '../../../providers/providers.dart';
import 'ble_service.dart';
import 'timing_params.dart';

/// 描述当前生效的输入速度状态
class ActiveTimingState {
  final Map<String, double> values;
  final TimingPreset? matchedPreset;
  final double estimatedCharsPerSec;
  final bool isSyncing;

  const ActiveTimingState({
    required this.values,
    this.matchedPreset,
    required this.estimatedCharsPerSec,
    this.isSyncing = false,
  });

  ActiveTimingState copyWith({
    Map<String, double>? values,
    TimingPreset? matchedPreset,
    double? estimatedCharsPerSec,
    bool? isSyncing,
    bool clearMatchedPreset = false,
  }) {
    return ActiveTimingState(
      values: values ?? this.values,
      matchedPreset: clearMatchedPreset ? null : (matchedPreset ?? this.matchedPreset),
      estimatedCharsPerSec: estimatedCharsPerSec ?? this.estimatedCharsPerSec,
      isSyncing: isSyncing ?? this.isSyncing,
    );
  }

  /// 计算单个字符耗时与每秒字符速率
  static double calcCharsPerSec(Map<String, double> vals) {
    final hold = vals['alt_hold_ms'] ?? 1.0;
    final dPress = vals['alt_digit_press'] ?? 3.5;
    final dRel = vals['alt_digit_release'] ?? 0.5;
    final altRel = vals['alt_release_ms'] ?? 3.0;
    final gap = vals['cjk_gap_ms'] ?? 2.0;
    final total = hold + (5 * dPress) + (4 * dRel) + altRel + gap;
    if (total <= 0) return 0;
    return 1000.0 / total;
  }

  /// 格式化标签，如 “常规均衡 · 37字/秒” 或 “实时参数 · 42字/秒”
  String get displaySummary {
    final speed = estimatedCharsPerSec.toStringAsFixed(0);
    if (matchedPreset != null) {
      return '${matchedPreset!.name} · $speed字/秒';
    }
    return '实时参数 · $speed字/秒';
  }

  /// 紧凑版标签，适合两行胶囊第二行展示，如 “常规均衡 · 37字/s”
  String get compactSummary {
    final speed = estimatedCharsPerSec.toStringAsFixed(0);
    final name = matchedPreset?.name.split(' ').first ?? '实时';
    return '$name · $speed字/s';
  }
}

/// 输入速度唯一源控制器：
/// 1. 负责管理 App 与固件之间当前生效的时序参数与预设；
/// 2. 监听连接成功、打字完成、急停等时机自动向硬件下发 {CFG?} 回读最新参数；
/// 3. 当用户在悬浮窗、蓝牙胶囊或设置页切速度时，一次调用同步写入 App 与设备 Flash。
class ActiveTimingController extends StateNotifier<ActiveTimingState> {
  final SettingsRepository _settingsRepo;
  final BleService _bleService;
  final Ref _ref;
  StreamSubscription<String>? _bleEventsSub;

  ActiveTimingController(this._settingsRepo, this._bleService, this._ref)
      : super(ActiveTimingState(
          values: defaultTimingValues(),
          matchedPreset: kBuiltInTimingPresets.first,
          estimatedCharsPerSec: ActiveTimingState.calcCharsPerSec(defaultTimingValues()),
        )) {
    _init();
  }

  Future<void> _init() async {
    await _loadFromLocal();
    _listenBleEvents();
  }

  Future<void> _loadFromLocal() async {
    final raw = await _settingsRepo.get('timing_app_defaults');
    Map<String, double> vals = defaultTimingValues();
    if (raw != null) {
      final decoded = decodeTimingJson(raw);
      if (decoded != null) {
        vals = clampTimingValues(decoded);
      }
    }
    _updateInternalState(vals);
  }

  void _listenBleEvents() {
    _bleEventsSub?.cancel();
    _bleEventsSub = _bleService.events.listen((event) async {
      // 仅在急停发生时主动回读硬件参数；连接和正常打字不要自动回读，避免引发死循环发送与抢占
      if (event == 'emergency_stopped') {
        await Future.delayed(const Duration(milliseconds: 200));
        await refreshFromDevice(silent: true);
      }
    });
  }

  /// 与固件通信读取当前参数并校准唯一源
  Future<bool> refreshFromDevice({bool silent = false}) async {
    if (!_bleService.isConnected) return false;
    if (!silent) state = state.copyWith(isSyncing: true);
    try {
      final fetched = await _bleService.fetchTiming();
      if (fetched != null && fetched.isNotEmpty) {
        final clamped = clampTimingValues(fetched);
        _updateInternalState(clamped);
        await _settingsRepo.set('timing_app_defaults', encodeTimingJson(clamped));
        return true;
      }
      return false;
    } finally {
      if (!silent) state = state.copyWith(isSyncing: false);
    }
  }

  /// 一键应用并持久化预设（写入 App 存储 + 写入硬件 Flash + 校验）
  Future<bool> applyPreset(TimingPreset preset) async {
    return applyValues(preset.values, targetPreset: preset);
  }

  /// 应用一组完整参数
  Future<bool> applyValues(
    Map<String, double> rawValues, {
    TimingPreset? targetPreset,
  }) async {
    final clamped = clampTimingValues(rawValues);
    _updateInternalState(clamped, explicitPreset: targetPreset);
    await _settingsRepo.set('timing_app_defaults', encodeTimingJson(clamped));

    if (_bleService.isConnected) {
      state = state.copyWith(isSyncing: true);
      try {
        final cfgCmd = buildTimingCfg(clamped);
        if (cfgCmd.isNotEmpty) {
          await _bleService.sendCommand(cfgCmd);
        }
        await _bleService.sendCommand('{CFGSAVE}');
      } finally {
        state = state.copyWith(isSyncing: false);
      }
    }
    return true;
  }

  void _updateInternalState(
    Map<String, double> values, {
    TimingPreset? explicitPreset,
  }) {
    TimingPreset? matched = explicitPreset;
    if (matched == null) {
      // 遍历所有可用预设，匹配参数完全一致的一项
      final allPresets = _ref.read(timingPresetsProvider);
      matched = allPresets.where((p) => timingValuesEqual(p.values, values)).firstOrNull;
    }
    final charsPerSec = ActiveTimingState.calcCharsPerSec(values);
    state = ActiveTimingState(
      values: values,
      matchedPreset: matched,
      estimatedCharsPerSec: charsPerSec,
      isSyncing: state.isSyncing,
    );
  }

  @override
  void dispose() {
    _bleEventsSub?.cancel();
    super.dispose();
  }
}
