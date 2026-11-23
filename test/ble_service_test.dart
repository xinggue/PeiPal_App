import 'dart:async';
import 'dart:convert';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/ble/ble_service.dart';
import 'package:peipal/data/services/ble/timing_params.dart';
import 'package:peipal/providers/providers.dart';

import 'tutorial_test.dart' show MockSettingsRepo;

class _FakeBleLink implements BleLink {
  @override
  final String remoteId;

  @override
  bool isConnected = true;

  final StreamController<BluetoothConnectionState> stateController =
      StreamController<BluetoothConnectionState>.broadcast();

  void Function(List<int> bytes)? onValue;
  Future<void> Function(List<int> bytes)? onWrite;
  Future<int> Function()? onReadRssi;
  int disconnectCalls = 0;
  int disposeCalls = 0;

  _FakeBleLink(this.remoteId);

  @override
  Stream<BluetoothConnectionState> get connectionState => stateController.stream;

  @override
  Future<int> mtuCap() async => 100;

  @override
  Future<void> write(List<int> bytes) async {
    if (onWrite != null) {
      await onWrite!(bytes);
    }
  }

  @override
  Future<int> readRssi({Duration timeout = const Duration(seconds: 4)}) async {
    if (onReadRssi != null) {
      return onReadRssi!();
    }
    return -55;
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
    isConnected = false;
    if (!stateController.isClosed) {
      stateController.add(BluetoothConnectionState.disconnected);
    }
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    await stateController.close();
  }

  void simulateDrop({bool updateCachedFlag = true}) {
    if (updateCachedFlag) {
      isConnected = false;
    }
    if (!stateController.isClosed) {
      stateController.add(BluetoothConnectionState.disconnected);
    }
  }
}

class _FakeBleTransport implements BleTransport {
  final StreamController<BluetoothAdapterState> adapterController =
      StreamController<BluetoothAdapterState>.broadcast();

  @override
  bool isAdapterOn = true;

  Future<_FakeBleLink?> Function(
    BleDeviceInfo info,
    BleDeviceConfig config,
    void Function(List<int> bytes) onValue,
  )? onConnect;

  final List<_FakeBleLink> createdLinks = [];

  @override
  Stream<BluetoothAdapterState> get adapterState => adapterController.stream;

  @override
  Future<bool> ensureAdapterOn() async => isAdapterOn;

  @override
  Future<void> stopScan() async {}

  @override
  Future<List<BleDeviceInfo>> scan({
    required Duration timeout,
    required String deviceNamePattern,
    void Function(List<BleDeviceInfo> currentList)? onDiscovered,
  }) async =>
      const [];

  @override
  Future<BleLink?> connect(
    BleDeviceInfo info,
    BleDeviceConfig config, {
    required void Function(List<int> bytes) onValue,
  }) async {
    if (onConnect != null) {
      final link = await onConnect!(info, config, onValue);
      if (link != null) {
        link.onValue = onValue;
        createdLinks.add(link);
      }
      return link;
    }
    final link = _FakeBleLink(info.remoteId)..onValue = onValue;
    createdLinks.add(link);
    return link;
  }

  Future<void> close() async {
    await adapterController.close();
  }
}

void main() {
  const device = BleDeviceInfo(
    remoteId: 'AA:BB:CC:DD:EE:FF',
    name: 'ESP32S3 键盘_1234',
    rssi: -50,
  );

  test('sending 期间断连应立刻复位为 disconnected 并中止等待回执', () async {
    final transport = _FakeBleTransport();
    final ble = BleService(transport, const Duration(seconds: 60));
    addTearDown(() async {
      ble.dispose();
      await transport.close();
    });

    final events = <String>[];
    final sub = ble.events.listen(events.add);
    addTearDown(sub.cancel);

    expect(await ble.connectTo(device), isTrue);
    expect(ble.status, BleConnectionStatus.connected);
    expect(ble.isConnected, isTrue);

    final link = transport.createdLinks.single;
    final firstSend = ble.sendTextDone('第一段病历', timeout: const Duration(minutes: 10));
    final secondSend = ble.sendTextDone('第二段病历', timeout: const Duration(minutes: 10));

    // 等待写入第一段进入等待 DONE 状态
    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(ble.status, BleConnectionStatus.sending);

    // 模拟在 sending 态下突然断连
    link.simulateDrop();

    expect(await firstSend, isFalse);
    expect(await secondSend, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(ble.status, BleConnectionStatus.disconnected);
    expect(ble.isConnected, isFalse);
    expect(ble.connectedName, isNull);
    expect(ble.connectedRemoteId, isNull);
    expect(events, contains('disconnected'));
    expect(events, isNot(contains('typing_finished')));
  });

  test('底层链路静默失效且写入抛错时，应探测心跳并清理幽灵连接', () async {
    final transport = _FakeBleTransport();
    final ble = BleService(transport, const Duration(seconds: 60));
    addTearDown(() async {
      ble.dispose();
      await transport.close();
    });

    expect(await ble.connectTo(device), isTrue);
    final link = transport.createdLinks.single;

    // 模拟系统尚未发出断连回调（link.isConnected 仍为 true），但写入与 RSSI 探测均已失败
    link.onWrite = (_) async => throw StateError('GATT write failed');
    link.onReadRssi = () async => throw StateError('GATT dead');

    final ok = await ble.sendText('测试幽灵断联');
    expect(ok, isFalse);
    expect(ble.status, BleConnectionStatus.disconnected);
    expect(ble.isConnected, isFalse);
    expect(link.disconnectCalls, greaterThanOrEqualTo(1));
  });

  test('空闲态连续两次 RSSI 心跳失败应自动清理幽灵连接', () async {
    final transport = _FakeBleTransport();
    final ble = BleService(transport, const Duration(milliseconds: 25));
    addTearDown(() async {
      ble.dispose();
      await transport.close();
    });

    expect(await ble.connectTo(device), isTrue);
    final link = transport.createdLinks.single;

    var failRssi = false;
    link.onReadRssi = () async {
      if (failRssi) throw StateError('timeout');
      return -52;
    };

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(ble.isConnected, isTrue);

    failRssi = true;
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(ble.status, BleConnectionStatus.disconnected);
    expect(ble.isConnected, isFalse);
  });

  test('系统蓝牙关闭时应立即断开并清理状态', () async {
    final transport = _FakeBleTransport();
    final ble = BleService(transport, const Duration(seconds: 60));
    addTearDown(() async {
      ble.dispose();
      await transport.close();
    });

    expect(await ble.connectTo(device), isTrue);
    final sendFuture = ble.sendTextDone('长文本');
    await Future<void>.delayed(const Duration(milliseconds: 30));

    transport.isAdapterOn = false;
    transport.adapterController.add(BluetoothAdapterState.off);

    expect(await sendFuture, isFalse);
    expect(ble.status, BleConnectionStatus.disconnected);
    expect(ble.isConnected, isFalse);
  });

  test('断连后再次连接同一设备不得命中假连接短路', () async {
    final transport = _FakeBleTransport();
    final ble = BleService(transport, const Duration(seconds: 60));
    addTearDown(() async {
      ble.dispose();
      await transport.close();
    });

    expect(await ble.connectTo(device), isTrue);
    transport.createdLinks.first.simulateDrop();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(ble.isConnected, isFalse);

    expect(await ble.connectTo(device), isTrue);
    expect(transport.createdLinks.length, 2);
    expect(ble.isConnected, isTrue);
  });

  test('connectTo 进行中被手动 disconnect 中断时不得回写为 connected', () async {
    final transport = _FakeBleTransport();
    final connectGate = Completer<_FakeBleLink?>();
    transport.onConnect = (info, _, _) => connectGate.future;

    final ble = BleService(transport, const Duration(seconds: 60));
    addTearDown(() async {
      ble.dispose();
      await transport.close();
    });

    final connectFuture = ble.connectTo(device);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(ble.status, BleConnectionStatus.connecting);

    await ble.disconnect();
    final lateLink = _FakeBleLink(device.remoteId);
    connectGate.complete(lateLink);

    expect(await connectFuture, isFalse);
    expect(ble.status, BleConnectionStatus.disconnected);
    expect(ble.isConnected, isFalse);
    expect(lateLink.disconnectCalls, 1);
  });

  test('sendCommand({CFG?}) 不触发 typing_finished，sendTextDone 触发且仅回读一次', () async {
    final transport = _FakeBleTransport();
    final ble = BleService(transport, const Duration(seconds: 60));
    addTearDown(() async {
      ble.dispose();
      await transport.close();
    });

    final events = <String>[];
    final sub = ble.events.listen(events.add);
    addTearDown(sub.cancel);

    expect(await ble.connectTo(device), isTrue);
    final link = transport.createdLinks.single;
    var cfgQueryCount = 0;
    link.onWrite = (bytes) async {
      final text = utf8.decode(bytes);
      if (text.contains('{CFG?}')) {
        cfgQueryCount++;
        link.onValue?.call(utf8.encode(
          'CFG:tap_press_ms=20.0 tap_release_ms=20.0 alt_hold_ms=2.0 alt_digit_press=2.0 alt_digit_release=2.0 alt_release_ms=2.0 ascii_gap_ms=20.0 cjk_gap_ms=2.0 numlock_auto=1 alt_ascii=1 fence_auto=1 shake_auto=0 check_interval=15\n',
        ));
      } else {
        final match = RegExp(r'\{(DONE:\d+)\}').firstMatch(text);
        if (match != null) {
          link.onValue?.call(utf8.encode('${match.group(1)}\n'));
        }
      }
    };

    final fetched = await ble.fetchTiming();
    expect(fetched, isNotNull);
    expect(cfgQueryCount, 1);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events, isNot(contains('typing_finished')));

    expect(await ble.sendTextDone('测试'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(events.where((e) => e == 'typing_finished').length, 1);
  });

  test('连接设备后自动读取 {CFG?}：命中本地预设时匹配，未命中时新建“设备参数”且重连不重复创建', () async {
    final transport = _FakeBleTransport();
    final ble = BleService(transport, const Duration(seconds: 60));
    final settings = MockSettingsRepo();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        bleServiceProvider.overrideWith((_) => ble),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await transport.close();
    });

    // 启动控制器，触发 _init()
    container.read(activeTimingControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    // 第 1 次连接：固件返回「较快」(2.0ms) 参数，应命中内置 preset_fast
    var cfgEcho =
        'CFG:tap_press_ms=20.0 tap_release_ms=20.0 alt_hold_ms=2.0 alt_digit_press=2.0 alt_digit_release=2.0 alt_release_ms=2.0 ascii_gap_ms=20.0 cjk_gap_ms=2.0 numlock_auto=1 alt_ascii=1 fence_auto=1 shake_auto=0 check_interval=15\n';
    transport.onConnect = (info, _, onValue) async {
      final link = _FakeBleLink(info.remoteId)..onValue = onValue;
      link.onWrite = (bytes) async {
        final text = utf8.decode(bytes);
        if (text.contains('{CFG?}')) {
          onValue(utf8.encode(cfgEcho));
        }
      };
      return link;
    };

    expect(await ble.connectTo(device), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final fastState = container.read(activeTimingControllerProvider);
    expect(fastState.matchedPreset?.id, 'preset_fast');
    expect(container.read(timingPresetsProvider).length, kBuiltInTimingPresets.length);

    // 断连后切换固件参数为未命中的自定义值 (4.5ms)，再次连接应新建「设备参数」
    await ble.disconnect();
    cfgEcho =
        'CFG:tap_press_ms=20.0 tap_release_ms=20.0 alt_hold_ms=4.5 alt_digit_press=4.5 alt_digit_release=4.5 alt_release_ms=4.5 ascii_gap_ms=20.0 cjk_gap_ms=4.5 numlock_auto=1 alt_ascii=1 fence_auto=1 shake_auto=0 check_interval=15\n';
    expect(await ble.connectTo(device), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final customState = container.read(activeTimingControllerProvider);
    expect(customState.matchedPreset?.name, '设备参数');
    expect(customState.values['alt_hold_ms'], 4.5);
    final presetsAfterCreate = container.read(timingPresetsProvider);
    expect(presetsAfterCreate.length, kBuiltInTimingPresets.length + 1);

    // 相同自定义参数再次重连，必须直接命中刚才新建的「设备参数」，不能重复新建
    await ble.disconnect();
    expect(await ble.connectTo(device), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 250));

    final reconnectState = container.read(activeTimingControllerProvider);
    expect(reconnectState.matchedPreset?.id, customState.matchedPreset?.id);
    expect(container.read(timingPresetsProvider).length, kBuiltInTimingPresets.length + 1);
  });

  test('typing_finished 自动回读硬件最新参数且不新建临时预设、不死循环', () async {
    final transport = _FakeBleTransport();
    final ble = BleService(transport, const Duration(seconds: 60));
    final settings = MockSettingsRepo();
    final container = ProviderContainer(
      overrides: [
        settingsRepositoryProvider.overrideWithValue(settings),
        bleServiceProvider.overrideWith((_) => ble),
      ],
    );
    addTearDown(() async {
      container.dispose();
      await transport.close();
    });

    container.read(activeTimingControllerProvider);
    await Future<void>.delayed(const Duration(milliseconds: 30));

    var currentCfgEcho =
        'CFG:tap_press_ms=20.0 tap_release_ms=20.0 alt_hold_ms=3.0 alt_digit_press=3.0 alt_digit_release=3.0 alt_release_ms=3.0 ascii_gap_ms=20.0 cjk_gap_ms=3.0 numlock_auto=1 alt_ascii=1 fence_auto=1 shake_auto=0 check_interval=15\n';
    var cfgQueries = 0;

    transport.onConnect = (info, _, onValue) async {
      final link = _FakeBleLink(info.remoteId)..onValue = onValue;
      link.onWrite = (bytes) async {
        final text = utf8.decode(bytes);
        if (text.contains('{CFG?}')) {
          cfgQueries++;
          onValue(utf8.encode(currentCfgEcho));
        } else {
          final match = RegExp(r'\{(DONE:\d+)\}').firstMatch(text);
          if (match != null) {
            // 模拟输入过程中通过 {CFG:...} 动态修改了 cjk_gap_ms
            currentCfgEcho =
                'CFG:tap_press_ms=20.0 tap_release_ms=20.0 alt_hold_ms=3.0 alt_digit_press=3.0 alt_digit_release=3.0 alt_release_ms=3.0 ascii_gap_ms=20.0 cjk_gap_ms=30.0 numlock_auto=1 alt_ascii=1 fence_auto=1 shake_auto=0 check_interval=15\n';
            onValue(utf8.encode('${match.group(1)}\n'));
          }
        }
      };
      return link;
    };

    expect(await ble.connectTo(device), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(cfgQueries, 1);

    expect(await ble.sendTextDone('{CFG:cjk_gap_ms=30}测试'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(cfgQueries, 2);
    final updatedState = container.read(activeTimingControllerProvider);
    expect(updatedState.values['cjk_gap_ms'], 30.0);
    expect(updatedState.matchedPreset, isNull);
    expect(container.read(timingPresetsProvider).length, kBuiltInTimingPresets.length);
  });
}
