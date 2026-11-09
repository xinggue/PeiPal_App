import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/ble/ble_service.dart';
import '../../../data/services/ble/typing_done_prefs.dart';
import '../../../providers/providers.dart';
import '../../widgets/ble/typing_preset_library_sheet.dart';
import '../../widgets/ble/typing_test_panel.dart';

class BleConnectPage extends ConsumerStatefulWidget {
  const BleConnectPage({super.key});

  @override
  ConsumerState<BleConnectPage> createState() => _BleConnectPageState();
}

class _BleConnectPageState extends ConsumerState<BleConnectPage> {
  // 高级配置输入框
  final _nameCtrl = TextEditingController();
  final _svcCtrl = TextEditingController();
  final _txCtrl = TextEditingController();
  final _rxCtrl = TextEditingController();
  final _mtuCtrl = TextEditingController();

  List<BleDeviceInfo> _devices = const [];
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final config = ref.read(bleConfigProvider);
      _nameCtrl.text = config.deviceNamePattern;
      _svcCtrl.text = config.serviceUuid;
      _txCtrl.text = config.txCharacteristicUuid;
      _rxCtrl.text = config.rxCharacteristicUuid;
      _mtuCtrl.text = config.mtu.toString();
    });
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _svcCtrl.dispose();
    _txCtrl.dispose();
    _rxCtrl.dispose();
    _mtuCtrl.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final ble = ref.read(bleServiceProvider);
    if (_scanning) return;
    setState(() => _scanning = true);
    final on = await ble.ensureAdapterOn();
    if (!on) {
      setState(() => _scanning = false);
      _showSnack('请先打开手机蓝牙并授予权限');
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
    if (results.isEmpty) _showSnack('未发现设备，请确认键盘设备在开机状态');
  }

  Future<void> _connect(BleDeviceInfo info) async {
    if (_scanning) {
      setState(() => _scanning = false);
    }
    final ble = ref.read(bleServiceProvider);
    _showSnack('正在连接 ${info.name}…');
    final ok = await ble.connectTo(info);
    if (!mounted) return;
    if (ok) {
      await ref
          .read(bleConfigProvider.notifier)
          .saveLastDevice(info.remoteId, info.name);
      _showSnack('已连接 ${info.name}');
    } else {
      _showSnack('连接失败：${info.name}');
    }
  }

  Future<void> _connectLast() async {
    if (_scanning) {
      setState(() => _scanning = false);
    }
    final ble = ref.read(bleServiceProvider);
    final name = ble.lastName ?? '上次设备';
    _showSnack('正在连接 $name…');
    final ok = await ble.connectLast();
    if (!mounted) return;
    if (ok) {
      await ref
          .read(bleConfigProvider.notifier)
          .saveLastDevice(ble.connectedRemoteId, ble.connectedName);
      _showSnack('已连接 ${ble.connectedName ?? name}');
    } else {
      _showSnack('连接失败，请重新扫描选择设备');
    }
  }

  Future<void> _saveAdvanced() async {
    final config = BleDeviceConfig(
      deviceNamePattern: _nameCtrl.text.trim().isEmpty
          ? '键盘'
          : _nameCtrl.text.trim(),
      serviceUuid: _svcCtrl.text.trim(),
      txCharacteristicUuid: _txCtrl.text.trim(),
      rxCharacteristicUuid: _rxCtrl.text.trim(),
      mtu: int.tryParse(_mtuCtrl.text.trim()) ?? 512,
    );
    await ref.read(bleConfigProvider.notifier).save(config);
    if (mounted) _showSnack('高级配置已保存');
  }

  void _showSnack(String msg) {
    if (mounted) {
      showAppToast(context, msg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ble = ref.watch(bleServiceProvider);
    final isOverlayEnabled = ref.watch(floatingOverlayEnabledProvider);
    final activeTiming = ref.watch(activeTimingControllerProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('蓝牙与键盘')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _StatusCard(ble: ble, onConnectLast: _connectLast, scanning: _scanning),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _scanning ? null : _scan,
                  icon: _scanning
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.search),
                  label: Text(_scanning ? '扫描中…' : '扫描设备'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _DevicePanel(
            scanning: _scanning,
            devices: _devices,
            onConnect: _connect,
            connectedRemoteId: ble.connectedRemoteId,
            namePattern: ble.config.deviceNamePattern,
          ),
          const SizedBox(height: 16),

          // 悬浮窗开关与快捷动作配置卡片
          Card(
            margin: EdgeInsets.zero,
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(Icons.picture_in_picture_alt_outlined, color: Theme.of(context).colorScheme.primary),
                  title: const Text('全局键盘悬浮窗', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('在任意界面快速贴入文字、切换速度与执行快捷动作'),
                  value: isOverlayEnabled,
                  onChanged: (v) async {
                    await ref.read(floatingOverlayEnabledProvider.notifier).toggle(v);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.auto_fix_high, color: Theme.of(context).colorScheme.primary),
                  title: const Text('快捷动作预设库', style: TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: const Text('管理可在悬浮窗一键触发的按键与文字序列'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => TypingPresetLibrarySheet.show(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          Card(
            margin: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: activeTiming.matchedPreset != null
                  ? BorderSide(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
                      width: 1.2,
                    )
                  : BorderSide.none,
            ),
            child: ListTile(
              leading: Icon(Icons.speed, color: Theme.of(context).colorScheme.primary),
              title: Row(
                children: [
                  const Text('键盘参数与输入速度', style: TextStyle(fontWeight: FontWeight.bold)),
                  if (activeTiming.matchedPreset != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '已匹配',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Text('当前：${activeTiming.displaySummary}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/timing'),
            ),
          ),
          const SizedBox(height: 12),
          const TypingTestPanel(),
          const SizedBox(height: 12),
          const _TypingDoneFeedbackSection(),
          const SizedBox(height: 16),
          _AdvancedSection(
            nameCtrl: _nameCtrl,
            svcCtrl: _svcCtrl,
            txCtrl: _txCtrl,
            rxCtrl: _rxCtrl,
            mtuCtrl: _mtuCtrl,
            onSave: _saveAdvanced,
          ),
        ],
      ),
    );
  }
}

class _DevicePanel extends StatelessWidget {
  final bool scanning;
  final List<BleDeviceInfo> devices;
  final void Function(BleDeviceInfo) onConnect;
  final String? connectedRemoteId;
  final String namePattern;

  const _DevicePanel({
    required this.scanning,
    required this.devices,
    required this.onConnect,
    required this.connectedRemoteId,
    required this.namePattern,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
            child: Row(
              children: [
                Icon(Icons.bluetooth_searching, size: 16, color: scheme.outline),
                const SizedBox(width: 6),
                Text('附近的设备',
                    style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurfaceVariant)),
              ],
            ),
          ),
          SizedBox(
            height: 300,
            child: (devices.isEmpty && scanning)
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const SizedBox(height: 12),
                        Text('正在搜索周围蓝牙设备…',
                            style: TextStyle(color: Colors.grey[600], fontSize: 13)),
                      ],
                    ),
                  )
                : devices.isEmpty
                    ? Center(
                        child: Text('未发现设备，请点上方“扫描设备”',
                            style: TextStyle(color: Colors.grey[600])),
                      )
                    : Column(
                        children: [
                          if (scanning) ...[
                            const LinearProgressIndicator(minHeight: 2),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              child: Row(
                                children: [
                                  const SizedBox(
                                    width: 12,
                                    height: 12,
                                    child: CircularProgressIndicator(strokeWidth: 1.5),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '正在搜索周围设备… 已发现 ${devices.length} 个',
                                    style: TextStyle(fontSize: 11, color: Colors.blue.shade700),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          Expanded(
                            child: ListView.builder(
                              padding: const EdgeInsets.only(bottom: 6),
                              itemCount: devices.length,
                              itemBuilder: (context, index) => _deviceTile(
                                devices[index],
                                connectedRemoteId,
                                namePattern,
                                onConnect,
                              ),
                            ),
                          ),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _deviceTile(
    BleDeviceInfo d,
    String? currentId,
    String pattern,
    void Function(BleDeviceInfo) onConnect, {
    bool disabled = false,
  }) {
    final isCurrent = currentId == d.remoteId;
    final matched = d.matches(pattern);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ListTile(
        dense: true,
        enabled: !disabled,
        leading: Icon(
          isCurrent ? Icons.bluetooth_connected : Icons.bluetooth_searching,
          color: isCurrent ? Colors.blue : (disabled ? Colors.grey.shade400 : Colors.grey),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                d.name.isEmpty ? '(未命名设备)' : d.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: matched ? FontWeight.bold : FontWeight.normal,
                  color: disabled ? Colors.grey.shade600 : null,
                ),
              ),
            ),
            if (matched && !isCurrent) ...[
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text('键盘',
                    style: TextStyle(fontSize: 11, color: Colors.blue)),
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${d.remoteId}\n信号 ${d.rssi} dBm',
          style: TextStyle(fontSize: 11, color: disabled ? Colors.grey.shade500 : null),
        ),
        trailing: isCurrent
            ? const Text('已连接', style: TextStyle(color: Colors.blue))
            : disabled
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('扫描中', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  )
                : const Icon(Icons.chevron_right, size: 18),
        onTap: (isCurrent || disabled) ? null : () => onConnect(d),
      ),
    );
  }
}

class _StatusCard extends ConsumerWidget {
  final BleService ble;
  final VoidCallback onConnectLast;
  final bool scanning;
  const _StatusCard({
    required this.ble,
    required this.onConnectLast,
    required this.scanning,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ble.status;
    final (label, color) = switch (status) {
      BleConnectionStatus.disconnected => ('未连接', Colors.grey),
      BleConnectionStatus.scanning => ('扫描中', Colors.orange),
      BleConnectionStatus.connecting => ('连接中', Colors.orange),
      BleConnectionStatus.connected => ('已连接', Colors.green),
      BleConnectionStatus.sending => ('正在发送', Colors.blue),
    };
    return Card(
      color: color.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.bluetooth, color: color, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 16)),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          ble.connectedName ??
                              (ble.lastName == null
                                  ? '尚未连接过设备'
                                  : '上次设备：${ble.lastName}'),
                          style: TextStyle(color: Colors.grey[700], fontSize: 13),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (ble.isConnected) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _showRenameDialog(context, ref, ble),
                          child: const Icon(Icons.edit_outlined, size: 16, color: Colors.blue),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (ble.isConnected)
              OutlinedButton(
                onPressed: () => ref.read(bleServiceProvider).disconnect(),
                child: const Text('断开'),
              )
            else if (ble.lastRemoteId != null)
              FilledButton.tonal(
                onPressed: scanning ? null : onConnectLast,
                child: const Text('连接上次'),
              ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BuildContext context, WidgetRef ref, BleService ble) {
    final ctrl = TextEditingController(text: ble.connectedName ?? 'ESP32C3 键盘');
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('修改蓝牙键盘名称'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '名称将直接写入硬件 Flash (NVS 存储)，断电不丢失。改名后下次广播和连接时生效。',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              maxLength: 24,
              decoration: const InputDecoration(
                labelText: '新设备名称',
                hintText: '如：1号诊室键盘',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              showAppToast(context, '正在恢复出厂默认名称…');
              final ok = await ble.sendCommand('{NAMERESET}');
              if (context.mounted) {
                if (ok) {
                  showAppToast(context, '已恢复出厂默认名 (含MAC后缀)，重启或重新连接后生效');
                } else {
                  showAppToast(context, '重置指令发送失败');
                }
              }
            },
            child: const Text('恢复默认', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () async {
              final newName = ctrl.text.trim();
              if (newName.isEmpty) return;
                            Navigator.of(ctx).pop();
              showAppToast(context, '正在向固件发送改名指令: $newName…');
              final ok = await ble.renameDevice(newName);
              if (context.mounted) {
                if (ok) {
                  // 同步更新 App 记忆与匹配规则
                  await ref.read(bleConfigProvider.notifier).saveLastDevice(
                        ble.connectedRemoteId,
                        newName,
                      );
                  if (context.mounted) {
                    showAppToast(context, '名称已修改为: $newName (已写入固件 Flash)');
                  }
                } else {
                  showAppToast(context, '改名失败或固件无应答');
                }
              }
            },
            child: const Text('保存到设备'),
          ),
        ],
      ),
    );
  }
}

class _AdvancedSection extends StatelessWidget {
  final TextEditingController nameCtrl;
  final TextEditingController svcCtrl;
  final TextEditingController txCtrl;
  final TextEditingController rxCtrl;
  final TextEditingController mtuCtrl;
  final VoidCallback onSave;

  const _AdvancedSection({
    required this.nameCtrl,
    required this.svcCtrl,
    required this.txCtrl,
    required this.rxCtrl,
    required this.mtuCtrl,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      title: const Text('高级设置',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      leading: const Icon(Icons.tune, size: 20),
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(bottom: 8),
      children: [
        TextField(
          controller: nameCtrl,
          decoration: const InputDecoration(
            labelText: '设备名称匹配',
            hintText: '键盘',
            border: OutlineInputBorder(),
            isDense: true,
            helperText: '扫描列表里标“键盘”即匹配此名',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: svcCtrl,
          decoration: const InputDecoration(
            labelText: 'Service UUID',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: txCtrl,
          decoration: const InputDecoration(
            labelText: 'TX Characteristic UUID',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: rxCtrl,
          decoration: const InputDecoration(
            labelText: 'RX Characteristic UUID（固件回执）',
            border: OutlineInputBorder(),
            isDense: true,
            helperText: '固件完成/状态回执走的通知特征',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: mtuCtrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '请求 MTU',
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton(onPressed: onSave, child: const Text('保存高级配置')),
        ),
      ],
    );
  }
}

class _TypingDoneFeedbackSection extends ConsumerWidget {
  const _TypingDoneFeedbackSection();

  Future<void> _set(WidgetRef ref, TypingDonePrefs next) async {
    await ref
        .read(settingsRepositoryProvider)
        .set('typing_done_feedback', next.code);
    ref.invalidate(typingDonePrefsProvider);
  }

  Widget _chip({
    required String label,
    required bool selected,
    required bool enabled,
    required ValueChanged<bool>? onSelected,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: enabled ? onSelected : null,
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(typingDonePrefsProvider).valueOrNull ??
        const TypingDonePrefs();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_none, size: 18),
                const SizedBox(width: 6),
                const Text('打字完成提醒',
                    style:
                        TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 4),
            Text('长文本由设备打完后再提醒',
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                _chip(
                  label: '系统横幅通知',
                  selected: prefs.systemBanner,
                  enabled: false,
                  onSelected: null,
                  tooltip: '需后续接入本地通知插件',
                ),
                _chip(
                  label: '应用内通知',
                  selected: prefs.inAppNotify,
                  enabled: true,
                  onSelected: (v) =>
                      _set(ref, prefs.copyWith(inAppNotify: v)),
                ),
                _chip(
                  label: '震动',
                  selected: prefs.vibrate,
                  enabled: true,
                  onSelected: (v) => _set(ref, prefs.copyWith(vibrate: v)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
