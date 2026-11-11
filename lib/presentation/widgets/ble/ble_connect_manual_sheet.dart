import 'dart:async';

import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/ble/ble_service.dart';
import '../../../providers/providers.dart';

/// 蓝牙发送前的手动连接弹窗：列出上次连接记录与周围扫描结果，供用户手动自主连接，杜绝隐式自动乱连
class BleConnectManualSheet extends ConsumerStatefulWidget {
  /// 非空时以回调方式关闭（用于顶层 Overlay 模式，而非 Navigator 路由）。
  final ValueChanged<bool>? onResult;

  const BleConnectManualSheet({super.key, this.onResult});

  static Future<bool> show(BuildContext context) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => const BleConnectManualSheet(),
    );
    return result ?? false;
  }

  /// 挂在最顶层 [Overlay] 上弹出，层级高于全局悬浮窗。
  static Future<bool> showAboveOverlay(BuildContext context) {
    final overlay = Overlay.of(context, rootOverlay: true);
    final completer = Completer<bool>();
    late OverlayEntry entry;
    var closed = false;

    void close(bool ok) {
      if (closed) return;
      closed = true;
      if (!completer.isCompleted) completer.complete(ok);
      entry.remove();
    }

    entry = OverlayEntry(
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final size = MediaQuery.of(ctx).size;
        return Stack(
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => close(false),
                child: Container(color: Colors.black.withValues(alpha: 0.35)),
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Material(
                color: theme.colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                clipBehavior: Clip.antiAlias,
                child: SafeArea(
                  top: false,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: size.height * 0.62),
                    child: BleConnectManualSheet(onResult: close),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    overlay.insert(entry);
    return completer.future;
  }

  @override
  ConsumerState<BleConnectManualSheet> createState() => _BleConnectManualSheetState();
}

class _BleConnectManualSheetState extends ConsumerState<BleConnectManualSheet> {
  bool _scanning = false;

  void _finish(bool result) {
    if (widget.onResult != null) {
      widget.onResult!(result);
    } else {
      Navigator.pop(context, result);
    }
  }
  List<BleDeviceInfo> _devices = [];
  String? _connectingId;

  @override
  void initState() {
    super.initState();
    Future.microtask(_startScan);
  }

  Future<void> _startScan() async {
    final ble = ref.read(bleServiceProvider);
    if (_scanning) return;
    setState(() => _scanning = true);

    final on = await ble.ensureAdapterOn();
    if (!on && mounted) {
      setState(() => _scanning = false);
      showAppToast(context, '请先打开手机蓝牙开关并授予权限');
      return;
    }

    final results = await ble.scan(
      onDiscovered: (list) {
        if (mounted) setState(() => _devices = list);
      },
    );
    if (!mounted) return;
    setState(() {
      _scanning = false;
      _devices = results;
    });
  }

  Future<void> _connect(BleDeviceInfo info) async {
    if (_scanning) {
      setState(() => _scanning = false);
    }
    setState(() => _connectingId = info.remoteId);
    final ble = ref.read(bleServiceProvider);
    final ok = await ble.connectTo(info);
    if (!mounted) return;
    setState(() => _connectingId = null);

    if (ok) {
      await ref.read(bleConfigProvider.notifier).saveLastDevice(info.remoteId, info.name);
      if (mounted) {
        _finish(true);
      }
    } else {
      if (mounted) {
        showAppToast(context, '连接失败：${info.name}');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = ref.watch(bleServiceProvider);
    final lastId = ble.lastRemoteId;
    final lastName = ble.lastName;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.bluetooth_searching, color: Colors.teal),
              const SizedBox(width: 8),
              const Text(
                '选择并连接蓝牙键盘',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (_scanning)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('重新扫描', style: TextStyle(fontSize: 12.5)),
                  onPressed: _startScan,
                ),
              if (widget.onResult != null)
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  tooltip: '关闭',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _finish(false),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '当前尚未连接键盘。请在下方选择你的 ESP32 小培键盘完成连接。',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600, height: 1.35),
          ),
          const Divider(height: 20),

          // 上次配对的硬件（作为快捷项展示，用户点击才连接）
          if (lastId != null && lastName != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.history, size: 20, color: Colors.teal),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('上次连接设备: $lastName',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                        Text(lastId, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: _connectingId != null
                        ? null
                        : () => _connect(BleDeviceInfo(remoteId: lastId, name: lastName, rssi: 0)),
                    child: _connectingId == lastId
                        ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('连接'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          const Text('周围扫描到的蓝牙设备：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.blueGrey)),
          const SizedBox(height: 6),
          if (_scanning) ...[
            const LinearProgressIndicator(minHeight: 2),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(strokeWidth: 1.5),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '正在搜索周围设备… 已发现 ${_devices.length} 个',
                    style: TextStyle(fontSize: 11, color: Colors.teal.shade800),
                  ),
                ],
              ),
            ),
          ],

          Expanded(
            child: _devices.isEmpty
                ? Center(
                    child: _scanning
                        ? const Text('正在扫描周围蓝牙设备...', style: TextStyle(color: Colors.grey, fontSize: 13))
                        : const Text('未发现蓝牙设备，请确认键盘设备电源已打开', style: TextStyle(color: Colors.grey, fontSize: 13)),
                  )
                : ListView.separated(
                    itemCount: _devices.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final dev = _devices[i];
                      final isConnecting = _connectingId == dev.remoteId;

                      return ListTile(
                        dense: true,
                        enabled: _connectingId == null,
                        leading: const Icon(Icons.keyboard, color: Colors.teal),
                        title: Text(dev.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${dev.remoteId} · 信号: ${dev.rssi} dBm', style: const TextStyle(fontSize: 11)),
                        trailing: FilledButton.tonal(
                          style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                          onPressed: _connectingId != null ? null : () => _connect(dev),
                          child: isConnecting
                              ? const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('连接'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
