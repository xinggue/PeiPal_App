import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/ble/timing_params.dart';
import '../../../providers/providers.dart';
import '../../widgets/ble/ble_connect_manual_sheet.dart';
import '../../widgets/ble/piano_roll_timing_editor.dart';
import '../../widgets/ble/typing_test_panel.dart';

/// 独立的输入节奏与参数设置页面 (/settings/timing)
class TimingSettingsPage extends ConsumerStatefulWidget {
  const TimingSettingsPage({super.key});

  @override
  ConsumerState<TimingSettingsPage> createState() => _TimingSettingsPageState();
}

class _TimingSettingsPageState extends ConsumerState<TimingSettingsPage> {
  Map<String, double> _timingValues = defaultTimingValues();
  String _selectedPresetId = 'preset_standard';
  bool _isBusy = false;

  @override
  void initState() {
    super.initState();
    _loadAppDefaults();
  }

  Future<void> _loadAppDefaults() async {
    final active = ref.read(activeTimingControllerProvider);
    setState(() {
      _timingValues = clampTimingValues(active.values);
      if (active.matchedPreset != null) {
        _selectedPresetId = active.matchedPreset!.id;
      }
    });
  }

  Future<bool> _ensureConnected() async {
    final ble = ref.read(bleServiceProvider);
    if (ble.isConnected) return true;
    if (!mounted) return false;
    return BleConnectManualSheet.show(context);
  }

  void _showSnack(String msg) {
    if (mounted) {
      showAppToast(context, msg);
    }
  }

  Future<bool> _saveScheme(TimingPreset cur, {bool quiet = false}) async {
    final values = clampTimingValues(_timingValues);
    await ref.read(timingPresetsProvider.notifier).savePreset(cur.copyWith(values: values));
    await ref.read(activeTimingControllerProvider.notifier).applyValues(values, targetPreset: cur);
    if (!mounted) return true;
    setState(() => _timingValues = values);
    if (!quiet) _showSnack('已保存方案「${cur.name}」');
    return true;
  }

  Future<void> _saveAndSend(TimingPreset cur) async {
    final connected = await _ensureConnected();
    if (!mounted) return;
    if (!connected) {
      _showSnack('未连接设备，未发送');
      return;
    }
    setState(() => _isBusy = true);
    await _saveScheme(cur, quiet: true);
    await ref.read(activeTimingControllerProvider.notifier).applyValues(
      _timingValues,
      targetPreset: cur,
    );
    if (!mounted) return;
    setState(() => _isBusy = false);
    _showSnack('已保存并同步发送到设备');
  }

  Future<void> _readFromDevice() async {
    final connected = await _ensureConnected();
    if (!mounted) return;
    if (!connected) {
      _showSnack('未连接设备，未读取');
      return;
    }
    setState(() => _isBusy = true);
    final ok = await ref.read(activeTimingControllerProvider.notifier).refreshFromDevice();
    if (!mounted) return;
    setState(() => _isBusy = false);
    if (!ok) {
      _showSnack('未读到设备参数，请确认固件在线');
      return;
    }
    final active = ref.read(activeTimingControllerProvider);
    setState(() {
      _timingValues = Map<String, double>.from(active.values);
      if (active.matchedPreset != null) {
        _selectedPresetId = active.matchedPreset!.id;
      }
    });
    _showSnack('已读取设备当前参数');
  }

  /// 另存为新的独立预设
  Future<void> _saveAsNewPresetDialog() async {
    final nameCtrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('另存为新输入预设'),
        content: TextField(
          controller: nameCtrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '预设名称',
            hintText: '如：稳妥专用、极速流',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, nameCtrl.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    final newPreset = TimingPreset(
      name: name,
      values: Map<String, double>.from(_timingValues),
    );
    await ref.read(timingPresetsProvider.notifier).savePreset(newPreset);
    setState(() => _selectedPresetId = newPreset.id);
    _showSnack('已保存新预设「$name」');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final presets = ref.watch(timingPresetsProvider);
    final activeTiming = ref.watch(activeTimingControllerProvider);
    final currentPreset =
        presets.where((p) => p.id == _selectedPresetId).firstOrNull ?? presets.first;
    final isMatched = activeTiming.matchedPreset?.id == currentPreset.id;
    final ble = ref.watch(bleServiceProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('键盘参数与输入速度'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 1. 醒目的预设选择与管理卡片
          Card(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isMatched
                  ? BorderSide(color: colorScheme.primary, width: 1.8)
                  : BorderSide.none,
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Icon(Icons.bookmarks_rounded, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      const Text(
                        '时序预设管理',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      if (isMatched) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '当前硬件生效中',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.add, size: 16),
                        label: const Text('新建预设'),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: _saveAsNewPresetDialog,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 大号显眼的预设下拉选择框
                  DropdownButtonFormField<String>(
                    initialValue: currentPreset.id,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: '当前选中的输入节奏预设',
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      suffixIcon: !currentPreset.isBuiltIn
                          ? IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red),
                              tooltip: '删除此自定义预设',
                              onPressed: () async {
                                await ref.read(timingPresetsProvider.notifier).deletePreset(currentPreset.id);
                                setState(() => _selectedPresetId = 'preset_standard');
                              },
                            )
                          : null,
                    ),
                    items: presets.map((p) {
                      final isCurrentMatched = activeTiming.matchedPreset?.id == p.id;
                      return DropdownMenuItem(
                        value: p.id,
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${p.name} · ${p.estimatedCharsPerSec.toStringAsFixed(0)} 字/秒',
                                style: TextStyle(
                                  fontWeight: isCurrentMatched
                                      ? FontWeight.bold
                                      : FontWeight.w600,
                                  fontSize: 14,
                                  color: isCurrentMatched
                                      ? colorScheme.primary
                                      : null,
                                ),
                              ),
                            ),
                            if (isCurrentMatched)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 1),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary
                                      .withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  '生效中',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }).toList(),
                    onChanged: (id) {
                      if (id == null) return;
                      final target = presets.firstWhere((p) => p.id == id);
                      setState(() {
                        _selectedPresetId = id;
                        _timingValues = Map<String, double>.from(target.values);
                      });
                    },
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      TextButton.icon(
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('重置为方案原值'),
                        onPressed: () {
                          setState(() {
                            _timingValues = clampTimingValues(currentPreset.values);
                          });
                        },
                      ),
                      const Spacer(),
                      TextButton.icon(
                        icon: const Icon(Icons.download_rounded, size: 16),
                        label: const Text('读取设备参数'),
                        onPressed: _isBusy ? null : _readFromDevice,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 2. 钢琴卷帘微观时序视图与调节
          PianoRollTimingEditor(
            values: _timingValues,
            onChanged: (next) => setState(() => _timingValues = clampTimingValues(next)),
          ),
          const SizedBox(height: 12),
          Text(
            ble.isConnected ? '已连接 ${ble.connectedName ?? "键盘"}' : '未连接键盘。发送或读取时会先要求连接。',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isBusy ? null : () => _saveScheme(currentPreset),
                  icon: const Icon(Icons.save_outlined, size: 16),
                  label: const Text('保存参数方案'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _isBusy ? null : _saveAsNewPresetDialog,
                  icon: const Icon(Icons.file_copy_outlined, size: 16),
                  label: const Text('另存为新方案'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _isBusy ? null : () => _saveAndSend(currentPreset),
                  icon: _isBusy
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.upload_rounded, size: 16),
                  label: const Text('保存并发送到设备'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _isBusy ? null : _readFromDevice,
                  icon: const Icon(Icons.download_rounded, size: 16),
                  label: const Text('读取设备参数'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const TypingTestPanel(),
          const SizedBox(height: 16),

          // 常规数字与字母 Alt 码开关
          Card(
            margin: EdgeInsets.zero,
            child: SwitchListTile(
              secondary: Icon(Icons.spellcheck, color: colorScheme.primary),
              title: const Text('常规数字与字母走 Alt 码输入', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text(
                (_timingValues['alt_ascii'] ?? 1.0) >= 0.5
                    ? '已开启：数字和字母均走 Alt 小键盘码，避开中文输入法候选框'
                    : '已关闭：作为普通键盘按键直接敲出，可能被中文输入法拦截',
                style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
              ),
              value: (_timingValues['alt_ascii'] ?? 1.0) >= 0.5,
              onChanged: (v) {
                setState(() => _timingValues['alt_ascii'] = v ? 1.0 : 0.0);
              },
            ),
          ),
          const SizedBox(height: 16),

          _buildHealthCheckCard(colorScheme, currentPreset),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildHealthCheckCard(ColorScheme colorScheme, TimingPreset currentPreset) {
    final fenceOn = (_timingValues['fence_auto'] ?? 1.0) >= 0.5;
    final shakeOn = (_timingValues['shake_auto'] ?? 0.0) >= 0.5;
    final altAsciiOn = (_timingValues['alt_ascii'] ?? 1.0) >= 0.5;
    final interval = (_timingValues['check_interval'] ?? 15.0).round();

    return Card(
      child: ExpansionTile(
        initiallyExpanded: false, // 默认收起折叠
        leading: Icon(Icons.tune, color: colorScheme.primary),
        title: const Text(
          '高级设置',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
        ),
        subtitle: Text(
          '${altAsciiOn ? "英文走 Alt 码" : "英文直接打"} · ${fenceOn ? "每 $interval 字自愈" : "未开启自愈"}',
          style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          const Text(
            '针对长文本输入期间偶发的 Alt 键粘滞、NumLock 意外熄灭或乱码，在字符输出间隙自动执行安全自愈。',
            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.35),
          ),
          const SizedBox(height: 12),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('英文字母和符号走 Alt 码', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: const Text('开启后绕过中文输入法。关闭则英文直接敲键，输入法开着时可能进候选框'),
            value: altAsciiOn,
            onChanged: (v) {
              setState(() => _timingValues['alt_ascii'] = v ? 1.0 : 0.0);
            },
          ),
          const Divider(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('长文本防粘滞硬重置 (推荐开启)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: const Text('输入间歇向系统发送全按键释放帧，彻底清除因按键过急导致的 Alt 键假死粘滞'),
            value: fenceOn,
            onChanged: (v) {
              setState(() => _timingValues['fence_auto'] = v ? 1.0 : 0.0);
            },
          ),
          const Divider(height: 8),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('闭环握手翻转自检 (可选)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            subtitle: const Text('通过 CapsLock 敲击与回读翻转闭环测试通信链路活性，遇严重卡顿系统时可选'),
            value: shakeOn,
            onChanged: (v) {
              setState(() => _timingValues['shake_auto'] = v ? 1.0 : 0.0);
            },
          ),
          const Divider(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                const Text('自检触发周期：', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                const Spacer(),
                IconButton.outlined(
                  icon: const Icon(Icons.remove, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: interval > 5
                      ? () => setState(() => _timingValues['check_interval'] = (interval - 1).toDouble())
                      : null,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '每 $interval 字',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, fontFamily: 'monospace'),
                  ),
                ),
                IconButton.outlined(
                  icon: const Icon(Icons.add, size: 16),
                  visualDensity: VisualDensity.compact,
                  onPressed: interval < 50
                      ? () => setState(() => _timingValues['check_interval'] = (interval + 1).toDouble())
                      : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: _isBusy ? null : () => _saveAndSend(currentPreset),
              icon: const Icon(Icons.upload_rounded, size: 16),
              label: const Text('发送到设备'),
            ),
          ),
        ],
      ),
    );
  }
}
