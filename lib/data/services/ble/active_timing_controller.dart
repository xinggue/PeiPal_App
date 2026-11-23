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
    // 固件 send_alt_code 中 alt_release 实际等待两次（末位数字后 + 函数返回前）
    final total = hold + (5 * dPress) + (4 * dRel) + (2 * altRel) + gap;
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
  Future<bool>? _inFlightRefresh;
  int _mutationEpoch = 0;
  bool _disposed = false;

  ActiveTimingController(this._settingsRepo, this._bleService, this._ref)
      : super(ActiveTimingState(
          values: defaultTimingValues(),
          matchedPreset: kBuiltInTimingPresets.first,
          estimatedCharsPerSec: ActiveTimingState.calcCharsPerSec(defaultTimingValues()),
        )) {
    _listenBleEvents();
    _init();
  }

  Future<void> _init() async {
    await _loadFromLocal();
    if (!_disposed && _bleService.isConnected) {
      await refreshFromDevice(silent: true, createPresetIfUnmatched: true);
    }
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
    await _ref.read(timingPresetsProvider.notifier).ensureLoaded();
    if (_disposed) return;
    _updateInternalState(vals);
  }

  void _listenBleEvents() {
    _bleEventsSub?.cancel();
    _bleEventsSub = _bleService.events.listen((event) {
      if (event == 'connected') {
        _scheduleDeviceRefresh(
          delay: const Duration(milliseconds: 150),
          createPresetIfUnmatched: true,
        );
      } else if (event == 'typing_finished' || event == 'emergency_stopped') {
        _scheduleDeviceRefresh(
          delay: const Duration(milliseconds: 200),
          createPresetIfUnmatched: false,
        );
      }
    });
  }

  void _scheduleDeviceRefresh({
    required Duration delay,
    required bool createPresetIfUnmatched,
  }) {
    Future.delayed(delay, () async {
      if (_disposed || !_bleService.isConnected) return;
      await refreshFromDevice(
        silent: true,
        createPresetIfUnmatched: createPresetIfUnmatched,
      );
    });
  }

  /// 与固件通信读取当前参数并校准唯一源；
  /// [createPresetIfUnmatched] 为 true 时，若设备当前参数未命中本机任何预设，会自动新建一个本地预设并选中。
  Future<bool> refreshFromDevice({
    bool silent = false,
    bool createPresetIfUnmatched = true,
  }) {
    final existing = _inFlightRefresh;
    if (existing != null) return existing;

    final future = _refreshFromDeviceImpl(
      silent: silent,
      createPresetIfUnmatched: createPresetIfUnmatched,
    );
    _inFlightRefresh = future;
    future.whenComplete(() {
      if (identical(_inFlightRefresh, future)) {
        _inFlightRefresh = null;
      }
    });
    return future;
  }

  Future<bool> _refreshFromDeviceImpl({
    required bool silent,
    required bool createPresetIfUnmatched,
  }) async {
    if (_disposed || !_bleService.isConnected) return false;
    final startEpoch = _mutationEpoch;
    if (!silent) state = state.copyWith(isSyncing: true);
    try {
      final fetched = await _bleService.fetchTiming();
      if (_disposed || !_bleService.isConnected || _mutationEpoch != startEpoch) {
        return false;
      }
      if (fetched == null || fetched.isEmpty) return false;

      final clamped = clampTimingValues(fetched);
      await _ref.read(timingPresetsProvider.notifier).ensureLoaded();
      if (_disposed || _mutationEpoch != startEpoch) return false;

      final allPresets = _ref.read(timingPresetsProvider);
      TimingPreset? matched =
          allPresets.where((p) => timingValuesEqual(p.values, clamped)).firstOrNull;

      if (matched == null && createPresetIfUnmatched) {
        final presetName = _nextDevicePresetName(allPresets);
        final created = TimingPreset(name: presetName, values: clamped);
        await _ref.read(timingPresetsProvider.notifier).savePreset(created);
        if (_disposed || _mutationEpoch != startEpoch) return false;
        matched = created;
      }

      _setInternalState(clamped, matchedPreset: matched);
      await _settingsRepo.set('timing_app_defaults', encodeTimingJson(clamped));
      return true;
    } finally {
      if (!silent && !_disposed) {
        state = state.copyWith(isSyncing: false);
      }
    }
  }

  static String _nextDevicePresetName(List<TimingPreset> existing) {
    const base = '设备参数';
    final names = existing.map((p) => p.name).toSet();
    if (!names.contains(base)) return base;
    var index = 2;
    while (names.contains('$base $index')) {
      index++;
    }
    return '$base $index';
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
    _mutationEpoch++;
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
        if (!_disposed) state = state.copyWith(isSyncing: false);
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
    _setInternalState(values, matchedPreset: matched);
  }

  void _setInternalState(
    Map<String, double> values, {
    required TimingPreset? matchedPreset,
  }) {
    final charsPerSec = ActiveTimingState.calcCharsPerSec(values);
    state = ActiveTimingState(
      values: values,
      matchedPreset: matchedPreset,
      estimatedCharsPerSec: charsPerSec,
      isSyncing: state.isSyncing,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _bleEventsSub?.cancel();
    super.dispose();
  }
}
