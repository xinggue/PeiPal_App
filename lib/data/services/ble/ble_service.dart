import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

import '../logging/app_log_service.dart';
import 'timing_params.dart';

class BleDeviceConfig {
  final String deviceNamePattern;
  final String serviceUuid;
  final String txCharacteristicUuid;
  final String rxCharacteristicUuid;
  final int mtu;

  const BleDeviceConfig({
    this.deviceNamePattern = '键盘',
    this.serviceUuid = '6E400001-B5A3-F393-E0A9-E50E24DCCA9E',
    this.txCharacteristicUuid = '6E400002-B5A3-F393-E0A9-E50E24DCCA9E',
    this.rxCharacteristicUuid = '6E400003-B5A3-F393-E0A9-E50E24DCCA9E',
    this.mtu = 512,
  });

  BleDeviceConfig copyWith({
    String? deviceNamePattern,
    String? serviceUuid,
    String? txCharacteristicUuid,
    String? rxCharacteristicUuid,
    int? mtu,
  }) =>
      BleDeviceConfig(
        deviceNamePattern: deviceNamePattern ?? this.deviceNamePattern,
        serviceUuid: serviceUuid ?? this.serviceUuid,
        txCharacteristicUuid:
            txCharacteristicUuid ?? this.txCharacteristicUuid,
        rxCharacteristicUuid:
            rxCharacteristicUuid ?? this.rxCharacteristicUuid,
        mtu: mtu ?? this.mtu,
      );
}

enum BleConnectionStatus { disconnected, scanning, connecting, connected, sending }

class BleDeviceInfo {
  final String remoteId;
  final String name;
  final int rssi;

  const BleDeviceInfo({
    required this.remoteId,
    required this.name,
    required this.rssi,
  });

  factory BleDeviceInfo.fromScan(ScanResult r) {
    var name = r.advertisementData.advName.trim();
    if (name.isEmpty) name = r.device.platformName.trim();
    return BleDeviceInfo(
      remoteId: r.device.remoteId.str,
      name: name,
      rssi: r.rssi,
    );
  }

  bool matches(String pattern) => name.contains(pattern);
}

/// 内部链路抽象，便于连接状态机与断连回归测试脱离平台通道运行。
@visibleForTesting
abstract interface class BleLink {
  String get remoteId;
  bool get isConnected;
  Stream<BluetoothConnectionState> get connectionState;
  Future<int> mtuCap();
  Future<void> write(List<int> bytes);
  Future<int> readRssi({Duration timeout});
  Future<void> disconnect();
  Future<void> dispose();
}

@visibleForTesting
abstract interface class BleTransport {
  Stream<BluetoothAdapterState> get adapterState;
  bool get isAdapterOn;
  Future<bool> ensureAdapterOn();
  Future<List<BleDeviceInfo>> scan({
    required Duration timeout,
    required String deviceNamePattern,
    void Function(List<BleDeviceInfo> currentList)? onDiscovered,
  });
  Future<void> stopScan();
  Future<BleLink?> connect(
    BleDeviceInfo info,
    BleDeviceConfig config, {
    required void Function(List<int> bytes) onValue,
  });
}

class _FbpLink implements BleLink {
  final BluetoothDevice _device;
  final BluetoothCharacteristic _tx;
  final StreamSubscription<List<int>>? _rxSub;

  _FbpLink(this._device, this._tx, this._rxSub);

  @override
  String get remoteId => _device.remoteId.str;

  @override
  bool get isConnected => _device.isConnected;

  @override
  Stream<BluetoothConnectionState> get connectionState => _device.connectionState;

  @override
  Future<int> mtuCap() async {
    try {
      final mtuNow =
          await _device.mtu.first.timeout(const Duration(milliseconds: 400));
      return (mtuNow - 3).clamp(20, 509);
    } catch (_) {
      return 20;
    }
  }

  @override
  Future<void> write(List<int> bytes) =>
      _tx.write(bytes, withoutResponse: false);

  @override
  Future<int> readRssi({Duration timeout = const Duration(seconds: 4)}) =>
      _device.readRssi(timeout: timeout.inSeconds.clamp(1, 30));

  @override
  Future<void> disconnect() => _device.disconnect();

  @override
  Future<void> dispose() async {
    await _rxSub?.cancel();
  }
}

class _FbpTransport implements BleTransport {
  @override
  Stream<BluetoothAdapterState> get adapterState => FlutterBluePlus.adapterState;

  @override
  bool get isAdapterOn =>
      FlutterBluePlus.adapterStateNow == BluetoothAdapterState.on;

  @override
  Future<bool> ensureAdapterOn() async {
    try {
      await FlutterBluePlus.adapterState
          .where((s) => s == BluetoothAdapterState.on)
          .first
          .timeout(const Duration(seconds: 3));
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> stopScan() => FlutterBluePlus.stopScan();

  @override
  Future<List<BleDeviceInfo>> scan({
    required Duration timeout,
    required String deviceNamePattern,
    void Function(List<BleDeviceInfo> currentList)? onDiscovered,
  }) async {
    await FlutterBluePlus.stopScan();

    final found = <String, ScanResult>{};
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        found[r.device.remoteId.str] = r; // 同名去重，保留后到的
      }
      if (onDiscovered != null) {
        onDiscovered(
          BleService.sortScannedDevices(found.values, deviceNamePattern),
        );
      }
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: timeout,
        androidUsesFineLocation: true,
      );
      await FlutterBluePlus.isScanning
          .where((v) => v == false)
          .first
          .timeout(timeout + const Duration(seconds: 2));
    } catch (_) {
      // 扫描被中断/失败：用已收集到的结果
    } finally {
      await sub.cancel();
    }

    return BleService.sortScannedDevices(found.values, deviceNamePattern);
  }

  @override
  Future<BleLink?> connect(
    BleDeviceInfo info,
    BleDeviceConfig config, {
    required void Function(List<int> bytes) onValue,
  }) async {
    final device = BluetoothDevice.fromId(info.remoteId);
    StreamSubscription<List<int>>? rxSub;
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      await device.discoverServices();

      BluetoothCharacteristic? tx;
      BluetoothCharacteristic? rx;
      for (final service in device.servicesList) {
        if (service.uuid.toString().toUpperCase() !=
            config.serviceUuid.toUpperCase()) {
          continue;
        }
        for (final char in service.characteristics) {
          final uuid = char.uuid.toString().toUpperCase();
          if (uuid == config.txCharacteristicUuid.toUpperCase()) {
            tx = char;
          } else if (uuid == config.rxCharacteristicUuid.toUpperCase()) {
            rx = char;
          }
        }
      }

      if (tx == null) {
        AppLogService.instance.warn('BLE', '未找到串口写入特征值，断开连接');
        await device.disconnect();
        return null;
      }

      // 订阅固件的回执/状态（{DONE} 完成回执依赖它）
      if (rx != null) {
        try {
          await rx.setNotifyValue(true);
          rxSub = rx.onValueReceived.listen(onValue);
        } catch (_) {
          rxSub = null;
        }
      }

      // 尽量协商更快的 MTU（失败不影响连接）
      try {
        await device.requestMtu(config.mtu);
      } catch (_) {}

      return _FbpLink(device, tx, rxSub);
    } catch (e) {
      AppLogService.instance.warn('BLE', '连接设备失败: $e');
      await rxSub?.cancel();
      try {
        await device.disconnect();
      } catch (_) {}
      return null;
    }
  }
}

/// 有状态的 BLE 连接中心：扫描 / 连接指定设备 / 记住上次设备 / 断线感知 / 发送。
/// 用 ChangeNotifierProvider 暴露，UI watch 即可响应状态变化。
class BleService extends ChangeNotifier {
  final BleTransport _transport;
  final Duration _rssiPollInterval;

  BleService([
    BleTransport? transport,
    Duration rssiPollInterval = const Duration(seconds: 8),
  ])  : _transport = transport ?? _FbpTransport(),
        _rssiPollInterval = rssiPollInterval;

  BleDeviceConfig _config = const BleDeviceConfig();
  BleConnectionStatus _status = BleConnectionStatus.disconnected;

  BleLink? _link;
  StreamSubscription<BluetoothConnectionState>? _watchSub;
  StreamSubscription<BluetoothAdapterState>? _adapterSub;

  // 设备→手机 的回执/状态行（按换行切分，trim 后抛出）
  final StreamController<String> _incoming = StreamController.broadcast();
  String _rxBuffer = '';

  String? _connectedName;
  String? _connectedRemoteId;
  int _connectedRssi = 0;
  Timer? _rssiTimer;
  int _rssiFailCount = 0;

  // 固件状态变化钩子（连接成功、断连、队列打字结束、急停完成）
  final StreamController<String> _eventController = StreamController.broadcast();
  Stream<String> get events => _eventController.stream;

  // 上次成功连接的设备（用于“一键连上次”）
  String? _lastRemoteId;
  String? _lastName;

  bool _disconnecting = false;
  int _connectEpoch = 0;

  // 先进先出发送队列：支持随时追加发送，写入仍串行、完成回执按唯一 ID 区分
  int _doneSeq = DateTime.now().millisecondsSinceEpoch % 100000;
  final List<_QueuedSend> _queue = [];
  _QueuedSend? _currentSending;
  void Function(bool)? _activeWaiterFinish;
  int _pushGen = 0;
  bool _workerRunning = false;

  BleDeviceConfig get config => _config;
  BleConnectionStatus get status => _status;
  bool get isConnected =>
      (_status == BleConnectionStatus.connected ||
          _status == BleConnectionStatus.sending) &&
      _link != null &&
      _link!.isConnected;
  bool get hasPendingSends => _queue.isNotEmpty;
  String? get connectedName => _connectedName;
  String? get connectedRemoteId => _connectedRemoteId;
  int get connectedRssi => _connectedRssi;
  String? get lastRemoteId => _lastRemoteId;
  String? get lastName => _lastName;
  Stream<String> get incoming => _incoming.stream;

  void updateConfig(BleDeviceConfig config) {
    _config = config;
    notifyListeners();
  }

  void setLastDevice(String? remoteId, String? name) {
    _lastRemoteId = remoteId;
    _lastName = name;
    notifyListeners();
  }

  void _setStatus(BleConnectionStatus s) {
    if (_status != s) {
      _status = s;
      notifyListeners();
    }
  }

  Future<bool> ensureAdapterOn() => _transport.ensureAdapterOn();

  /// 扫描一段时间的可见设备，按 RSSI 从强到弱去重排序。
  @visibleForTesting
  static List<BleDeviceInfo> sortScannedDevices(
    Iterable<ScanResult> results,
    String pattern,
  ) {
    final list = results.map(BleDeviceInfo.fromScan).toList();

    list.sort((a, b) {
      final aKey = a.name.contains('键盘') ||
          a.name.toLowerCase().contains('keyboard') ||
          a.matches(pattern);
      final bKey = b.name.contains('键盘') ||
          b.name.toLowerCase().contains('keyboard') ||
          b.matches(pattern);
      if (aKey && !bKey) return -1;
      if (!aKey && bKey) return 1;
      return b.rssi.compareTo(a.rssi);
    });
    return list;
  }

  Future<List<BleDeviceInfo>> scan({
    Duration timeout = const Duration(seconds: 8),
    void Function(List<BleDeviceInfo> currentList)? onDiscovered,
  }) async {
    if (!await ensureAdapterOn()) return const [];
    return _transport.scan(
      timeout: timeout,
      deviceNamePattern: _config.deviceNamePattern,
      onDiscovered: onDiscovered,
    );
  }

  Future<void> _cancelWatch() async {
    final sub = _watchSub;
    _watchSub = null;
    await sub?.cancel();
  }

  Future<void> _cancelAdapterWatch() async {
    final sub = _adapterSub;
    _adapterSub = null;
    await sub?.cancel();
  }

  void _watchAdapterState() {
    if (_adapterSub != null) return;
    try {
      _adapterSub = _transport.adapterState.listen(
        (state) {
          if (state == BluetoothAdapterState.off ||
              state == BluetoothAdapterState.turningOff ||
              state == BluetoothAdapterState.unavailable ||
              state == BluetoothAdapterState.unauthorized) {
            _connectEpoch++;
            if (_link != null ||
                _status == BleConnectionStatus.connected ||
                _status == BleConnectionStatus.sending ||
                _status == BleConnectionStatus.connecting) {
              _handleDisconnected(reason: '系统蓝牙已关闭');
            }
          }
        },
        onError: (_) {},
      );
    } catch (_) {
      _adapterSub = null;
    }
  }

  /// 连接指定设备（含发现服务、定位 TX 特征、请求 MTU）。
  Future<bool> connectTo(BleDeviceInfo info) async {
    if (isConnected && _link != null && _link!.remoteId == info.remoteId) {
      return true;
    }
    if (!await ensureAdapterOn()) {
      _setStatus(BleConnectionStatus.disconnected);
      return false;
    }

    final epoch = ++_connectEpoch;
    _disconnecting = false;
    _setStatus(BleConnectionStatus.connecting);
    _watchAdapterState();

    // 连接开始前立即中止后台扫描，避免扫描射频占用造成握手延迟或超时
    try {
      await _transport.stopScan();
    } catch (_) {}

    // 清理旧连接与未完成的队列
    await _teardownLink(
      reason: '切换设备',
      disconnectDevice: true,
      updateStatusToDisconnected: false,
    );

    if (epoch != _connectEpoch || _disconnecting) {
      return false;
    }

    final link = await _transport.connect(
      info,
      _config,
      onValue: _onDeviceValue,
    );

    if (epoch != _connectEpoch || _disconnecting || link == null) {
      if (link != null) {
        try {
          await link.disconnect();
        } catch (_) {}
        await link.dispose();
      }
      if (epoch == _connectEpoch && !_disconnecting) {
        _setStatus(BleConnectionStatus.disconnected);
      }
      return false;
    }

    if (!link.isConnected) {
      try {
        await link.disconnect();
      } catch (_) {}
      await link.dispose();
      _setStatus(BleConnectionStatus.disconnected);
      return false;
    }

    _link = link;
    _connectedName = info.name;
    _connectedRemoteId = info.remoteId;
    _connectedRssi = info.rssi;
    _rssiFailCount = 0;
    _lastRemoteId = info.remoteId;
    _lastName = info.name;

    _watchDevice(link);

    // 防止在挂监听瞬间已经断开
    if (!link.isConnected) {
      _handleDisconnected(reason: '连接已断开', expectedLink: link);
      return false;
    }

    _startRssiPolling(link);
    _setStatus(BleConnectionStatus.connected);
    if (!_eventController.isClosed) {
      _eventController.add('connected');
    }
    AppLogService.instance.info('BLE', '已连接设备 name=${info.name}');
    return true;
  }

  void _onDeviceValue(List<int> bytes) {
    try {
      _rxBuffer += utf8.decode(bytes);
    } catch (_) {
      _rxBuffer += String.fromCharCodes(bytes);
    }
    while (true) {
      final idx = _rxBuffer.indexOf('\n');
      if (idx < 0) break;
      final line = _rxBuffer.substring(0, idx).trim();
      _rxBuffer = _rxBuffer.substring(idx + 1);
      if (line.isNotEmpty && !_incoming.isClosed) {
        _incoming.add(line);
      }
    }
  }

  /// 扫描并按名称匹配自动连接（找不到就连接扫描到的最强设备名匹配）。
  Future<bool> connectAuto() async {
    final results = await scan();
    if (results.isEmpty) return false;

    final pattern = _config.deviceNamePattern;
    BleDeviceInfo? target;
    for (final d in results) {
      if (d.matches(pattern)) {
        target = d;
        break;
      }
    }
    target ??= results.first;
    return connectTo(target);
  }

  /// 尝试连接上次设备；失败则退回 connectAuto。
  Future<bool> connectLast() async {
    try {
      await _transport.stopScan();
    } catch (_) {}
    if (_lastRemoteId != null) {
      final ok = await connectTo(BleDeviceInfo(
        remoteId: _lastRemoteId!,
        name: _lastName ?? _config.deviceNamePattern,
        rssi: 0,
      ));
      if (ok) return true;
    }
    return connectAuto();
  }

  void _startRssiPolling(BleLink link) {
    _rssiTimer?.cancel();
    _rssiFailCount = 0;
    _rssiTimer = Timer.periodic(_rssiPollInterval, (_) async {
      if (_link != link) return;
      // 正在发送时避开全局 BLE 互斥锁竞争
      if (_status == BleConnectionStatus.sending) return;

      if (!link.isConnected || !_transport.isAdapterOn) {
        _handleDisconnected(reason: '连接已断开', expectedLink: link);
        return;
      }

      try {
        final rssi = await link.readRssi(timeout: const Duration(seconds: 4));
        if (_link != link) return;
        _rssiFailCount = 0;
        if (_connectedRssi != rssi) {
          _connectedRssi = rssi;
          notifyListeners();
        }
      } catch (_) {
        if (_link != link) return;
        if (!link.isConnected || !_transport.isAdapterOn) {
          _handleDisconnected(reason: '心跳检测断连', expectedLink: link);
          return;
        }
        _rssiFailCount++;
        if (_rssiFailCount >= 2) {
          AppLogService.instance.warn('BLE', '连续 RSSI 心跳失败，判定链路已失效并断开');
          unawaited(link.disconnect().catchError((_) {}));
          _handleDisconnected(reason: '链路无响应', expectedLink: link);
        }
      }
    });
  }

  void _stopRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = null;
    _rssiFailCount = 0;
  }

  void _watchDevice(BleLink link) {
    final prev = _watchSub;
    _watchSub = null;
    if (prev != null) unawaited(prev.cancel());

    _watchSub = link.connectionState.listen(
      (state) {
        if (_link != link) return;
        if (state == BluetoothConnectionState.disconnected) {
          _handleDisconnected(reason: '断连', expectedLink: link);
        }
      },
      onError: (_) {
        if (_link == link) {
          _handleDisconnected(reason: '连接监听异常', expectedLink: link);
        }
      },
    );
  }

  Future<void> _verifyLinkOrDisconnect(
    BleLink link, {
    required String reason,
  }) async {
    if (_link != link) return;
    if (!link.isConnected || !_transport.isAdapterOn) {
      _handleDisconnected(reason: reason, expectedLink: link);
      return;
    }
    try {
      await link.readRssi(timeout: const Duration(seconds: 2));
    } catch (_) {
      if (_link == link) {
        unawaited(link.disconnect().catchError((_) {}));
        _handleDisconnected(reason: reason, expectedLink: link);
      }
    }
  }

  void _handleDisconnected({
    required String reason,
    BleLink? expectedLink,
  }) {
    if (expectedLink != null && _link != expectedLink) return;
    if (_link == null && _status == BleConnectionStatus.disconnected) return;

    final wasActive = _status == BleConnectionStatus.connected ||
        _status == BleConnectionStatus.sending ||
        _status == BleConnectionStatus.connecting;

    _stopRssiPolling();
    final watchSub = _watchSub;
    _watchSub = null;
    if (watchSub != null) unawaited(watchSub.cancel());

    final oldLink = _link;
    _link = null;
    _rxBuffer = '';
    if (oldLink != null) {
      unawaited(oldLink.dispose().catchError((_) {}));
    }

    _connectedName = null;
    _connectedRemoteId = null;
    _connectedRssi = 0;

    _abortInFlightSends(reason);

    if (!_disconnecting) {
      _setStatus(BleConnectionStatus.disconnected);
      if (wasActive && !_eventController.isClosed) {
        _eventController.add('disconnected');
      }
      AppLogService.instance.warn('BLE', '设备已断开 ($reason)');
    }
  }

  Future<void> _teardownLink({
    required String reason,
    required bool disconnectDevice,
    required bool updateStatusToDisconnected,
  }) async {
    _stopRssiPolling();
    await _cancelWatch();

    final oldLink = _link;
    _link = null;
    _rxBuffer = '';
    _connectedName = null;
    _connectedRemoteId = null;
    _connectedRssi = 0;

    _abortInFlightSends(reason);

    if (oldLink != null) {
      if (disconnectDevice) {
        try {
          await oldLink.disconnect();
        } catch (_) {}
      }
      await oldLink.dispose();
    }

    if (updateStatusToDisconnected) {
      _setStatus(BleConnectionStatus.disconnected);
    }
  }

  void _abortInFlightSends(String reason) {
    _pushGen++;
    final finish = _activeWaiterFinish;
    _activeWaiterFinish = null;
    finish?.call(false);

    final cur = _currentSending;
    _currentSending = null;
    if (cur != null && !cur.completer.isCompleted) {
      cur.completer.complete(false);
    }
    _failQueue(reason);
  }

  Future<void> disconnect() async {
    _disconnecting = true;
    _connectEpoch++;
    await _cancelAdapterWatch();
    await _teardownLink(
      reason: '手动断开',
      disconnectDevice: true,
      updateStatusToDisconnected: false,
    );
    _disconnecting = false;
    _setStatus(BleConnectionStatus.disconnected);
  }

  /// UTF-8 编码并按多字节字符边界分包；分包上限 = MTU-3。
  List<List<int>> _chunkUtf8(String text, int cap) {
    final bytes = utf8.encode(text);
    final chunks = <List<int>>[];
    var i = 0;
    while (i < bytes.length) {
      var end = i;
      var size = 0;
      while (end < bytes.length) {
        final len = _utf8SeqLen(bytes[end]);
        if (size > 0 && size + len > cap) break;
        size += len;
        end += len;
      }
      if (end == i) end = i + 1; // 极端保护
      chunks.add(bytes.sublist(i, end));
      i = end;
    }
    return chunks;
  }

  Future<void> _pushText(String text) async {
    final link = _link;
    if (link == null || !isConnected) {
      throw StateError('disconnected');
    }
    final pushGen = _pushGen;
    final chunks = _chunkUtf8(text, await link.mtuCap());
    for (final chunk in chunks) {
      if (pushGen != _pushGen || _link != link || !isConnected) {
        throw StateError('aborted');
      }
      try {
        await link.write(chunk);
      } catch (_) {
        if (pushGen == _pushGen && _link == link) {
          await _verifyLinkOrDisconnect(link, reason: '写入失败，连接已断开');
        }
        rethrow;
      }
      if (pushGen != _pushGen || _link != link) {
        throw StateError('aborted');
      }
      await Future.delayed(const Duration(milliseconds: 12));
    }
  }

  /// 普通发送：把内容全部写入 BLE（不等固件打完）。返回写完了没有。
  Future<bool> sendText(String text) async {
    if (!isConnected) return false;
    if (utf8.encode(text).isEmpty) return true;

    _setStatus(BleConnectionStatus.sending);
    try {
      await _pushText(text);
      if (isConnected) {
        _setStatus(BleConnectionStatus.connected);
      }
      return true;
    } catch (_) {
      if (isConnected) {
        _setStatus(BleConnectionStatus.connected);
      } else if (_link != null) {
        _handleDisconnected(reason: '发送失败断连', expectedLink: _link);
      }
      return false;
    }
  }

  /// 发送一条待“打完”回执的文本（含 {KEY}/{CFG} 命令文本均可）。
  ///
  /// 进 FIFO 队列：可随时追加发送（固件本就是连续字节流、边打边收）。
  /// 每条带唯一完成标记 {DONE:ID}，固件打完它后回 DONE:ID，App 只认自己那条，
  /// 因此多条并发/排队互不干扰。返回该条是否在超时内等到了回执。
  Future<bool> sendTextDone(
    String text, {
    Duration timeout = const Duration(minutes: 10),
  }) {
    return _enqueue(text, awaitDone: true, timeout: timeout);
  }

  /// 一段“命令/无回执”文本也走同一队列（保证与长文本不交错写入），
  /// 写完即算成功（固件命令回执另经 incoming 返回，如 CFG? 解析）。
  Future<bool> sendCommand(String command) {
    return _enqueue(command, awaitDone: false, timeout: const Duration(minutes: 1));
  }

  Future<bool> _enqueue(
    String text, {
    required bool awaitDone,
    Duration timeout = const Duration(minutes: 10),
  }) async {
    if (!isConnected) {
      if (_link != null && !_link!.isConnected) {
        _handleDisconnected(reason: '发送前检测到断连', expectedLink: _link);
      }
      return false;
    }
    _doneSeq++;
    final queued = _QueuedSend(
      id: _doneSeq,
      text: text,
      timeout: timeout,
      awaitDone: awaitDone,
      completer: Completer<bool>(),
    );
    _queue.add(queued);
    _startWorker();
    return queued.completer.future;
  }

  void _startWorker() {
    if (_workerRunning) return;
    _workerRunning = true;
    _runWorker();
  }

  Future<void> _runWorker() async {
    try {
      while (_queue.isNotEmpty) {
        if (!isConnected) {
          if (_link != null && !_link!.isConnected) {
            _handleDisconnected(reason: '断连', expectedLink: _link);
          } else {
            _failQueue('断连');
          }
          break;
        }
        final m = _queue.removeAt(0);
        _currentSending = m;
        _setStatus(BleConnectionStatus.sending);
        bool ok;
        try {
          if (m.awaitDone) {
            ok = await _awaitDone(m);
          } else {
            await _pushText(m.text);
            ok = true;
          }
        } catch (_) {
          ok = false;
        } finally {
          if (_currentSending == m) {
            _currentSending = null;
          }
        }
        if (!m.completer.isCompleted) m.completer.complete(ok);

        // 若发送期间已断连，绝不把状态覆盖回 connected
        if (!isConnected) {
          if (_link != null && !_link!.isConnected) {
            _handleDisconnected(reason: '断连', expectedLink: _link);
          }
          break;
        }

        // 连续发送时保持 sending；仅清空后回到 connected
        if (_queue.isNotEmpty) {
          _setStatus(BleConnectionStatus.sending);
        } else {
          _setStatus(BleConnectionStatus.connected);
          if (!_eventController.isClosed) {
            _eventController.add('typing_finished');
          }
        }
      }
    } finally {
      _workerRunning = false;
      _currentSending = null;
    }
  }

  Future<bool> _awaitDone(_QueuedSend m) async {
    final label = 'DONE:${m.id}';
    final completer = Completer<bool>();
    StreamSubscription<String>? sub;
    Timer? timer;
    void finish(bool ok) {
      if (!completer.isCompleted) completer.complete(ok);
      sub?.cancel();
      timer?.cancel();
    }
    _activeWaiterFinish = finish;

    // 先挂监听再写内容，避免漏掉极快回执；同时监听 STOPPED 急停响应
    sub = incoming.listen((l) {
      final trimmed = l.trim();
      if (trimmed == label) {
        finish(true);
      } else if (trimmed == 'STOPPED') {
        finish(false);
      }
    });
    timer = Timer(m.timeout, () => finish(false));

    final link = _link;
    final pushGen = _pushGen;
    try {
      await _pushText(m.text);
      if (pushGen != _pushGen || _link != link || link == null || !isConnected) {
        finish(false);
        return false;
      }
      try {
        await link.write(utf8.encode('{$label}'));
      } catch (_) {
        if (pushGen == _pushGen && _link == link) {
          await _verifyLinkOrDisconnect(link, reason: '写入回执标记失败，连接已断开');
        }
        rethrow;
      }
      final ok = await completer.future;
      return ok;
    } catch (_) {
      finish(false);
      return false;
    } finally {
      if (_activeWaiterFinish == finish) {
        _activeWaiterFinish = null;
      }
      await sub.cancel();
      timer.cancel();
    }
  }

  void _failQueue(String reason) {
    for (final m in _queue) {
      if (!m.completer.isCompleted) m.completer.complete(false);
    }
    _queue.clear();
  }

  /// 紧急停止：立即中断当前正在等待回执的发送，清空队列，复位状态，并向固件下发 {STOP}
  Future<void> emergencyStop() async {
    _abortInFlightSends('用户主动急停');

    final link = _link;
    if (isConnected && link != null) {
      try {
        await link.write(utf8.encode('{STOP}'));
      } catch (_) {
        await _verifyLinkOrDisconnect(link, reason: '急停写入失败，连接已断开');
      }
    }

    if (isConnected) {
      _setStatus(BleConnectionStatus.connected);
    } else if (_link != null) {
      _handleDisconnected(reason: '连接已断开', expectedLink: _link);
    } else {
      _setStatus(BleConnectionStatus.disconnected);
    }
    if (!_eventController.isClosed) {
      _eventController.add('emergency_stopped');
    }
  }

  Future<bool> testSend(String text) async {
    if (!isConnected) return false;
    return sendText(text);
  }

  /// 发 {CFG?} 并解析固件回执，返回当前参数；超时/未连接返回 null。
  Future<Map<String, double>?> fetchTiming() async {
    if (!isConnected) return null;
    final completer = Completer<Map<String, double>?>();
    StreamSubscription<String>? sub;
    Timer? timer;
    void finish(Map<String, double>? m) {
      if (!completer.isCompleted) completer.complete(m);
    }

    sub = incoming.where((l) => parseCfgEcho(l) != null).listen((l) {
      finish(parseCfgEcho(l));
    });
    timer = Timer(const Duration(seconds: 6), () => finish(null));

    try {
      final ok = await sendCommand('{CFG?}'); // 走同一发送队列，避免与长文本交错
      if (!ok) finish(null);
    } catch (_) {
      finish(null);
    }
    final res = await completer.future;
    await sub.cancel();
    timer.cancel();
    return res;
  }

  /// 向固件发送重命名指令，写入 NVS Flash 并持久化
  Future<bool> renameDevice(String newName) async {
    final trimmed = newName.trim();
    if (trimmed.isEmpty || !isConnected) return false;
    final completer = Completer<bool>();
    late final StreamSubscription<String> sub;
    Timer? timer;
    void finish(bool ok) {
      if (!completer.isCompleted) completer.complete(ok);
    }

    sub = incoming
        .where((l) => l.startsWith('NAME:OK:') || l.startsWith('NAME:ERR:'))
        .listen((l) {
      if (l.startsWith('NAME:OK:')) {
        _connectedName = trimmed;
        _lastName = trimmed;
        notifyListeners();
        finish(true);
      } else {
        finish(false);
      }
    });
    timer = Timer(const Duration(seconds: 5), () => finish(false));

    try {
      final ok = await sendCommand('{NAME:$trimmed}');
      if (!ok) finish(false);
    } catch (_) {
      finish(false);
    }
    final res = await completer.future;
    await sub.cancel();
    timer.cancel();
    return res;
  }

  static int _utf8SeqLen(int b) {
    if (b < 0x80) return 1;
    if (b < 0xE0) return 2;
    if (b < 0xF0) return 3;
    return 4;
  }

  @override
  void dispose() {
    _connectEpoch++;
    _stopRssiPolling();
    unawaited(_cancelAdapterWatch());
    unawaited(_cancelWatch());
    final oldLink = _link;
    _link = null;
    if (oldLink != null) {
      unawaited(oldLink.dispose().catchError((_) {}));
    }
    _abortInFlightSends('service disposed');
    _incoming.close();
    _eventController.close();
    super.dispose();
  }
}

/// FIFO 队列里的一条待发送消息。
class _QueuedSend {
  final int id;
  final String text;
  final Duration timeout;
  final bool awaitDone;
  final Completer<bool> completer;

  const _QueuedSend({
    required this.id,
    required this.text,
    required this.timeout,
    required this.awaitDone,
    required this.completer,
  });
}
