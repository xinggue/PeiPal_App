import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/ble/ble_service.dart';
import '../../../data/services/ble/typing_done_prefs.dart';
import '../../../providers/providers.dart';
import '../../widgets/ble/speed_preset_selector.dart';
import '../../widgets/ble/typing_preset_library_sheet.dart';
import '../../widgets/ble/typing_test_panel.dart';
import '../../widgets/common/app_toast.dart';

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
  bool _scanListVisible = false;

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
    setState(() {
      _scanning = true;
      _scanListVisible = true;
    });
    final on = await ble.ensureAdapterOn();
    if (!on) {
      if (!mounted) return;
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
      if (!mounted) return;
      setState(() => _scanListVisible = false);
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
      if (!mounted) return;
      setState(() => _scanListVisible = false);
      _showSnack('已连接 ${ble.connectedName ?? name}');
    } else {
      _showSnack('连接失败，请重新扫描选择设备');
    }
  }

  Future<void> _saveAdvanced() async {
    final config = BleDeviceConfig(
      deviceNamePattern:
          _nameCtrl.text.trim().isEmpty ? '键盘' : _nameCtrl.text.trim(),
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

  Widget _sectionCard(BuildContext context, Widget child) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ble = ref.watch(bleServiceProvider);
    final isOverlayEnabled = ref.watch(floatingOverlayEnabledProvider);
    final scheme = Theme.of(context).colorScheme;
    final showDeviceList =
        _scanning || (_scanListVisible && (_devices.isNotEmpty || !ble.isConnected));

    return Scaffold(
      appBar: AppBar(title: const Text('蓝牙与键盘')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          // 1. 连接与扫描
          _StatusCard(ble: ble, onConnectLast: _connectLast, scanning: _scanning),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
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
          if (showDeviceList) ...[
            const SizedBox(height: 10),
            _DevicePanel(
              scanning: _scanning,
              devices: _devices,
              onConnect: _connect,
              onClose: _scanning
                  ? null
                  : () => setState(() => _scanListVisible = false),
              connectedRemoteId: ble.connectedRemoteId,
              namePattern: ble.config.deviceNamePattern,
            ),
          ],

          const SizedBox(height: 12),

          // 2. 测试输入
          const TypingTestPanel(),

          const SizedBox(height: 12),

          // 3. 键盘参数与输入速度（内嵌大悬浮窗同款方格阵列 + 微调入口）
          _sectionCard(
            context,
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  onTap: () => context.push('/settings/timing'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.speed, size: 20, color: scheme.primary),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            '键盘参数与输入速度',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '微调参数',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.chevron_right,
                          size: 18,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(height: 1),
                const Padding(
                  padding: EdgeInsets.fromLTRB(14, 12, 14, 10),
                  child: SpeedPresetSquareGrid(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 4. 悬浮窗、快捷动作库与提醒
          _sectionCard(
            context,
            Column(
              children: [
                SwitchListTile(
                  secondary: Icon(
                    Icons.picture_in_picture_alt_outlined,
                    color: scheme.primary,
                  ),
                  title: const Text(
                    '全局键盘悬浮窗',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  value: isOverlayEnabled,
                  onChanged: (v) async {
                    await ref
                        .read(floatingOverlayEnabledProvider.notifier)
                        .toggle(v);
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.auto_fix_high, color: scheme.primary),
                  title: const Text(
                    '快捷动作预设库',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => TypingPresetLibrarySheet.show(context),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.spellcheck, color: scheme.primary),
                  title: const Text(
                    '特殊字符替换',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/settings/char-replacement'),
                ),
                const Divider(height: 1),
                const _TypingDoneFeedbackRow(),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // 5. 高级设置
          _sectionCard(
            context,
            _AdvancedSection(
              nameCtrl: _nameCtrl,
              svcCtrl: _svcCtrl,
              txCtrl: _txCtrl,
              rxCtrl: _rxCtrl,
              mtuCtrl: _mtuCtrl,
              onSave: _saveAdvanced,
            ),
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
  final VoidCallback? onClose;
  final String? connectedRemoteId;
  final String namePattern;

  const _DevicePanel({
    required this.scanning,
    required this.devices,
    required this.onConnect,
    required this.onClose,
    required this.connectedRemoteId,
    required this.namePattern,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                Icon(Icons.bluetooth_searching, size: 16, color: scheme.primary),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    scanning
                        ? '正在搜索附近设备… (${devices.length})'
                        : '附近的设备 (${devices.length})',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (onClose != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    visualDensity: VisualDensity.compact,
                    tooltip: '收起',
                    onPressed: onClose,
                  ),
              ],
            ),
          ),
          if (scanning) const LinearProgressIndicator(minHeight: 2),
          const Divider(height: 1),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: devices.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: scanning
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              '未发现可用设备',
                              style: TextStyle(
                                fontSize: 13,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: devices.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) => _deviceTile(
                      context,
                      devices[index],
                      connectedRemoteId,
                      namePattern,
                      onConnect,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _deviceTile(
    BuildContext context,
    BleDeviceInfo d,
    String? currentId,
    String pattern,
    void Function(BleDeviceInfo) onConnect,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final isCurrent = currentId == d.remoteId;
    final matched = d.matches(pattern);

    return ListTile(
      dense: true,
      leading: Icon(
        isCurrent ? Icons.bluetooth_connected : Icons.bluetooth,
        color: isCurrent ? scheme.primary : scheme.onSurfaceVariant,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              d.name.isEmpty ? '(未命名设备)' : d.name,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: matched ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
          if (matched && !isCurrent) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '键盘',
                style: TextStyle(fontSize: 11, color: scheme.primary),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        '${d.remoteId} · ${d.rssi} dBm',
        style: const TextStyle(fontSize: 11.5),
      ),
      trailing: isCurrent
          ? Text('已连接', style: TextStyle(color: scheme.primary, fontSize: 12.5))
          : const Icon(Icons.chevron_right, size: 18),
      onTap: isCurrent ? null : () => onConnect(d),
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
    final scheme = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.bluetooth, color: color, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w600,
                          fontSize: 15.5,
                        ),
                      ),
                      if (ble.isConnected && ble.connectedRssi != 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          '${ble.connectedRssi} dBm',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          ble.connectedName ??
                              (ble.lastName == null
                                  ? '尚未连接过设备'
                                  : '上次设备：${ble.lastName}'),
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (ble.isConnected) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _showRenameDialog(context, ref, ble),
                          child: Icon(
                            Icons.edit_outlined,
                            size: 16,
                            color: scheme.primary,
                          ),
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
    showDialog<void>(
      context: context,
      builder: (_) => _RenameKeyboardDialog(
        initialName: ble.connectedName ?? '小培键盘',
        ble: ble,
        parentContext: context,
        ref: ref,
      ),
    );
  }
}

class _RenameKeyboardDialog extends StatefulWidget {
  final String initialName;
  final BleService ble;
  final BuildContext parentContext;
  final WidgetRef ref;

  const _RenameKeyboardDialog({
    required this.initialName,
    required this.ble,
    required this.parentContext,
    required this.ref,
  });

  @override
  State<_RenameKeyboardDialog> createState() => _RenameKeyboardDialogState();
}

class _RenameKeyboardDialogState extends State<_RenameKeyboardDialog> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
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
            controller: _ctrl,
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
            Navigator.of(context).pop();
            showAppToast(widget.parentContext, '正在恢复出厂默认名称…');
            final ok = await widget.ble.sendCommand('{NAMERESET}');
            if (widget.parentContext.mounted) {
              if (ok) {
                showAppToast(
                  widget.parentContext,
                  '已恢复出厂默认名 (含MAC后缀)，重启或重新连接后生效',
                );
              } else {
                showAppToast(widget.parentContext, '重置指令发送失败');
              }
            }
          },
          child: const Text('恢复默认', style: TextStyle(color: Colors.red)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () async {
            final newName = _ctrl.text.trim();
            if (newName.isEmpty) return;
            Navigator.of(context).pop();
            showAppToast(widget.parentContext, '正在向固件发送改名指令: $newName…');
            final ok = await widget.ble.renameDevice(newName);
            if (widget.parentContext.mounted) {
              if (ok) {
                await widget.ref
                    .read(bleConfigProvider.notifier)
                    .saveLastDevice(widget.ble.connectedRemoteId, newName);
                if (widget.parentContext.mounted) {
                  showAppToast(
                    widget.parentContext,
                    '名称已修改为: $newName (已写入固件 Flash)',
                  );
                }
              } else {
                showAppToast(widget.parentContext, '改名失败或固件无应答');
              }
            }
          },
          child: const Text('保存到设备'),
        ),
      ],
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
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        title: const Text(
          '高级设置',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        leading: Icon(Icons.tune, size: 20, color: scheme.primary),
        tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        childrenPadding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
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
      ),
    );
  }
}

class _TypingDoneFeedbackRow extends ConsumerWidget {
  const _TypingDoneFeedbackRow();

  Future<void> _set(WidgetRef ref, TypingDonePrefs next) async {
    await ref
        .read(settingsRepositoryProvider)
        .set('typing_done_feedback', next.code);
    ref.invalidate(typingDonePrefsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs =
        ref.watch(typingDonePrefsProvider).valueOrNull ?? const TypingDonePrefs();
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.notifications_none, size: 20, color: scheme.primary),
              const SizedBox(width: 14),
              const Text(
                '打字完成提醒',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 34),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                FilterChip(
                  label: const Text('应用内通知'),
                  selected: prefs.inAppNotify,
                  onSelected: (v) => _set(ref, prefs.copyWith(inAppNotify: v)),
                  visualDensity: VisualDensity.compact,
                ),
                FilterChip(
                  label: const Text('震动'),
                  selected: prefs.vibrate,
                  onSelected: (v) => _set(ref, prefs.copyWith(vibrate: v)),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
