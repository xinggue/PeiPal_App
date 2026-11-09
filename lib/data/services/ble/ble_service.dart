import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';

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

/// 有状态的 BLE 连接中心：扫描 / 连接指定设备 / 记住上次设备 / 断线感知 / 发送。
/// 用 ChangeNotifierProvider 暴露，UI watch 即可响应状态变化。
class BleService extends ChangeNotifier {
  BleDeviceConfig _config = const BleDeviceConfig();
  BleConnectionStatus _status = BleConnectionStatus.disconnected;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _txCharacteristic;
  StreamSubscription<BluetoothConnectionState>? _watchSub;
  StreamSubscription<List<int>>? _rxSub;

  // 设备→手机 的回执/状态行（按换行切分，trim 后抛出）
  final StreamController<String> _incoming = StreamController.broadcast();
  String _rxBuffer = '';

  String? _connectedName;
  String? _connectedRemoteId;
  int _connectedRssi = 0;
  Timer? _rssiTimer;

  // 固件状态变化钩子（连接成功、队列打字结束、急停完成），供输入速度唯一源自动回读
  final StreamController<String> _eventController = StreamController.broadcast();
  Stream<String> get events => _eventController.stream;

  // 上次成功连接的设备（用于“一键连上次”）
  String? _lastRemoteId;
  String? _lastName;

  bool _disconnecting = false;

  // 先进先出发送队列：支持随时追加发送，写入仍串行、完成回执按唯一 ID 区分
  int _doneSeq = 0;
  final List<_QueuedSend> _queue = [];
  _QueuedSend? _currentSending;
  void Function(bool)? _activeWaiterFinish;
  bool _abortCurrentPush = false;
  bool _workerRunning = false;

  BleDeviceConfig get config => _config;
  BleConnectionStatus get status => _status;
  bool get isConnected =>
      _status == BleConnectionStatus.connected ||
      _status == BleConnectionStatus.sending;
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

  /// 扫描一段时间的可见设备，按 RSSI 从强到弱去重排序。
  List<BleDeviceInfo> _sortScannedDevices(Iterable<ScanResult> results) {
    final pattern = _config.deviceNamePattern;
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
    await FlutterBluePlus.stopScan();

    final found = <String, ScanResult>{};
    final sub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        found[r.device.remoteId.str] = r; // 同名去重，保留后到的
      }
      if (onDiscovered != null) {
        onDiscovered(_sortScannedDevices(found.values));
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
      sub.cancel();
    }

    final list = _sortScannedDevices(found.values);
    return list;
  }

  Future<void> _cancelWatch() async {
    await _watchSub?.cancel();
    _watchSub = null;
  }

  /// 连接指定设备（含发现服务、定位 TX 特征、请求 MTU）。
  Future<bool> connectTo(BleDeviceInfo info) async {
    if (isConnected && _device != null &&
        _device!.remoteId.str == info.remoteId) {
      return true;
    }
    if (!await ensureAdapterOn()) {
      _setStatus(BleConnectionStatus.disconnected);
      return false;
    }

    _setStatus(BleConnectionStatus.connecting);
    _disconnecting = false;

    // 连接开始前立即中止后台扫描，避免扫描射频占用造成握手延迟或超时
    try {
      await FlutterBluePlus.stopScan();
    } catch (_) {}

    // 断开旧设备（如果有）
    if (_device != null) {
      await _cancelWatch();
      await _cancelRx();
      try {
        await _device!.disconnect();
      } catch (_) {}
    }

    final device = BluetoothDevice.fromId(info.remoteId);
    try {
      await device.connect(timeout: const Duration(seconds: 15));
      await device.discoverServices();

      BluetoothCharacteristic? tx;
      BluetoothCharacteristic? rx;
      for (final service in device.servicesList) {
        if (service.uuid.toString().toUpperCase() !=
            _config.serviceUuid.toUpperCase()) {
          continue;
        }
        for (final char in service.characteristics) {
          final uuid = char.uuid.toString().toUpperCase();
          if (uuid == _config.txCharacteristicUuid.toUpperCase()) {
            tx = char;
          } else if (uuid == _config.rxCharacteristicUuid.toUpperCase()) {
            rx = char;
          }
        }
      }

      if (tx == null) {
        await device.disconnect();
        _setStatus(BleConnectionStatus.disconnected);
        return false;
      }

      // 订阅固件的回执/状态（{DONE} 完成回执依赖它）
      if (rx != null) {
        try {
          await rx.setNotifyValue(true);
          _rxSub = rx.onValueReceived.listen(_onDeviceValue);
        } catch (_) {
          _rxSub = null;
        }
      }

      _device = device;
      _txCharacteristic = tx;
      _connectedName = info.name;
      _connectedRemoteId = info.remoteId;
      _connectedRssi = info.rssi;
      _lastRemoteId = info.remoteId;
      _lastName = info.name;

      // 尽量协商更快的 MTU（失败不影响连接）
      try {
        await device.requestMtu(_config.mtu);
      } catch (_) {}

      _watchDevice(device);
      _startRssiPolling(device);
      _setStatus(BleConnectionStatus.connected);
      _eventController.add('connected');
      return true;
    } catch (_) {
      await _cancelWatch();
      await _cancelRx();
      _device = null;
      _txCharacteristic = null;
      _connectedName = null;
      _connectedRemoteId = null;
      _setStatus(BleConnectionStatus.disconnected);
      return false;
    }
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

  Future<void> _cancelRx() async {
    await _rxSub?.cancel();
    _rxSub = null;
    _rxBuffer = '';
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
      await FlutterBluePlus.stopScan();
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

  void _startRssiPolling(BluetoothDevice device) {
    _rssiTimer?.cancel();
    _rssiTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (!isConnected || _device == null) return;
      try {
        final rssi = await device.readRssi();
        if (_connectedRssi != rssi) {
          _connectedRssi = rssi;
          notifyListeners();
        }
      } catch (_) {}
    });
  }

  void _stopRssiPolling() {
    _rssiTimer?.cancel();
    _rssiTimer = null;
  }

  void _watchDevice(BluetoothDevice device) {
    _watchSub = device.connectionState.listen((state) {
      if (state == BluetoothConnectionState.disconnected) {
        final was = _status;
        _stopRssiPolling();
        _device = null;
        _txCharacteristic = null;
        _watchSub = null;
        _cancelRx();
        _failQueue('断连');
        if (was == BleConnectionStatus.connected && !_disconnecting) {
          _setStatus(BleConnectionStatus.disconnected);
        }
      }
    });
  }

  Future<void> disconnect() async {
    _disconnecting = true;
    _stopRssiPolling();
    await _cancelWatch();
    await _cancelRx();
    final dev = _device;
    _device = null;
    _txCharacteristic = null;
    _connectedName = null;
    _connectedRemoteId = null;
    _connectedRssi = 0;
    _failQueue('手动断开');
    if (dev != null) {
      try {
        await dev.disconnect();
      } catch (_) {}
    }
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

  /// 当前可用的单包净荷上限（MTU-3），协商失败退回 20。
  Future<int> _mtuCap() async {
    try {
      final mtuNow = await _device!.mtu.first
          .timeout(const Duration(milliseconds: 400));
      return (mtuNow - 3).clamp(20, 509);
    } catch (_) {
      return 20;
    }
  }

  Future<void> _pushText(String text) async {
    final chunks = _chunkUtf8(text, await _mtuCap());
    for (final chunk in chunks) {
      if (_abortCurrentPush || !isConnected || _txCharacteristic == null) {
        throw StateError('aborted');
      }
      await _txCharacteristic!.write(chunk, withoutResponse: false);
      await Future.delayed(const Duration(milliseconds: 12));
    }
  }

  /// 普通发送：把内容全部写入 BLE（不等固件打完）。返回写完了没有。
  Future<bool> sendText(String text) async {
    if (!isConnected || _txCharacteristic == null) return false;
    if (utf8.encode(text).isEmpty) return true;

    _setStatus(BleConnectionStatus.sending);
    try {
      await _pushText(text);
      _setStatus(BleConnectionStatus.connected);
      return true;
    } catch (_) {
      _setStatus(BleConnectionStatus.connected);
      return false;
    }
  }

  /// 发送一条待“打完”回执的文本（含 {KEY}/{CFG} 命令文本均可）。
  ///
  /// 进 FIFO 队列：可随时追加新发送（固件本就是连续字节流、边打边收）。
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
    if (!isConnected || _txCharacteristic == null) return false;
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
        if (!isConnected || _txCharacteristic == null) {
          _failQueue('断连');
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
          _currentSending = null;
        }
        if (!m.completer.isCompleted) m.completer.complete(ok);
        // 连续发送时保持 sending；仅清空后回到 connected
        if (_queue.isNotEmpty) {
          _setStatus(BleConnectionStatus.sending);
        } else {
          _setStatus(BleConnectionStatus.connected);
          _eventController.add('typing_finished');
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

    try {
      await _pushText(m.text);
      await _txCharacteristic!.write(
        utf8.encode('{$label}'),
        withoutResponse: false,
      );
      final ok = await completer.future;
      return ok;
    } catch (_) {
      finish(false);
      return false;
    } finally {
      if (_activeWaiterFinish == finish) {
        _activeWaiterFinish = null;
      }
      sub.cancel();
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
    _abortCurrentPush = true;
    _activeWaiterFinish?.call(false);
    _activeWaiterFinish = null;

    final cur = _currentSending;
    _currentSending = null;
    if (cur != null && !cur.completer.isCompleted) {
      cur.completer.complete(false);
    }
    _failQueue('用户主动急停');

    if (isConnected && _txCharacteristic != null) {
      try {
        await _txCharacteristic!.write(utf8.encode('{STOP}'), withoutResponse: false);
      } catch (_) {}
    }
    _abortCurrentPush = false;
    _setStatus(isConnected ? BleConnectionStatus.connected : BleConnectionStatus.disconnected);
    _eventController.add('emergency_stopped');
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
      await sendCommand('{CFG?}'); // 走同一发送队列，避免与长文本交错
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
    if (trimmed.isEmpty) return false;
    final completer = Completer<bool>();
    late final StreamSubscription sub;
    Timer? timer;
    void finish(bool ok) {
      if (!completer.isCompleted) completer.complete(ok);
    }

    sub = incoming.where((l) => l.startsWith('NAME:OK:') || l.startsWith('NAME:ERR:')).listen((l) {
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
      await sendCommand('{NAME:$trimmed}');
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
    _stopRssiPolling();
    _cancelWatch();
    _cancelRx();
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
