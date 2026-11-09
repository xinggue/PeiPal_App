import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:go_router/go_router.dart';

import '../../../domain/models/patient.dart';
import '../../../domain/models/message.dart';
import '../../../data/services/media/media_storage.dart';
import '../../../data/services/task/task_center.dart';
import '../../../providers/providers.dart';
import '../../widgets/ble/ble_connect_manual_sheet.dart';

enum PatientFilter { all, active, discharged }

enum PatientSortField {
  recentActivity,
  createdAt,
  name,
}

extension PatientSortFieldExt on PatientSortField {
  String get label => switch (this) {
        PatientSortField.recentActivity => '活跃时间',
        PatientSortField.createdAt => '创建时间',
        PatientSortField.name => '会话名称',
      };

  IconData get icon => switch (this) {
        PatientSortField.recentActivity => Icons.access_time_rounded,
        PatientSortField.createdAt => Icons.calendar_today_rounded,
        PatientSortField.name => Icons.sort_by_alpha_rounded,
      };
}

class PatientListPage extends ConsumerStatefulWidget {
  const PatientListPage({super.key});

  @override
  ConsumerState<PatientListPage> createState() => _PatientListPageState();
}

class _PatientListPageState extends ConsumerState<PatientListPage> {
  PatientFilter _filter = PatientFilter.active;
  PatientSortField _sortField = PatientSortField.recentActivity;
  bool _sortAscending = false; // 默认 false: 降序 (最新优先)
  final Set<SlidableController> _openSlidables = {};

  void _closeAllOpenSlidables() {
    if (_openSlidables.isEmpty) return;
    for (final c in _openSlidables.toList()) {
      try {
        c.close();
      } catch (_) {}
    }
    _openSlidables.clear();
  }

  @override
  Widget build(BuildContext context) {
    final patients = ref.watch(patientsProvider);

    final activeTaskCount =
        ref.watch(taskCenterProvider.select((tc) => tc.activeTasks.length));

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: Badge(
            isLabelVisible: activeTaskCount > 0,
            label: Text('$activeTaskCount'),
            child: const Icon(Icons.auto_awesome_motion_rounded, size: 22),
          ),
          tooltip: '后台任务中心',
          onPressed: () => context.push('/tasks'),
        ),
        title: Consumer(
          builder: (context, ref, _) {
            final list = patients.valueOrNull ?? const [];
            final activeCount =
                list.where((p) => p.status == PatientStatus.active).length;
            final dischargedCount =
                list.where((p) => p.status == PatientStatus.discharged).length;
            final totalCount = list.length;

            return PopupMenuButton<PatientFilter>(
              useRootNavigator: true,
              initialValue: _filter,
              onSelected: (f) => setState(() => _filter = f),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              itemBuilder: (ctx) => [
                PopupMenuItem(
                  value: PatientFilter.active,
                  child: Row(
                    children: [
                      const Icon(Icons.play_circle_outline, size: 18),
                      const SizedBox(width: 8),
                      Text('进行中会话 ($activeCount)'),
                      if (_filter == PatientFilter.active) ...[
                        const Spacer(),
                        Icon(Icons.check,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary),
                      ],
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: PatientFilter.discharged,
                  child: Row(
                    children: [
                      const Icon(Icons.inventory_2_outlined, size: 18),
                      const SizedBox(width: 8),
                      Text('已归档会话 ($dischargedCount)'),
                      if (_filter == PatientFilter.discharged) ...[
                        const Spacer(),
                        Icon(Icons.check,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary),
                      ],
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: PatientFilter.all,
                  child: Row(
                    children: [
                      const Icon(Icons.workspaces_outline, size: 18),
                      const SizedBox(width: 8),
                      Text('全部会话 ($totalCount)'),
                      if (_filter == PatientFilter.all) ...[
                        const Spacer(),
                        Icon(Icons.check,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary),
                      ],
                    ],
                  ),
                ),
              ],
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _filter == PatientFilter.all
                        ? '全部会话'
                        : (_filter == PatientFilter.active
                            ? '进行中会话'
                            : '已归档会话'),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                  const SizedBox(width: 2),
                  const Icon(Icons.arrow_drop_down_rounded, size: 22),
                ],
              ),
            );
          },
        ),
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final ble = ref.watch(bleServiceProvider);
              final isConnected = ble.isConnected;
              final rssi = ble.connectedRssi;
              final rssiText = rssi != 0 ? '$rssi dBm' : '';

              return Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        _showBluetoothQuickSheet(context, ref);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isConnected
                              ? Colors.green.shade50
                              : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isConnected
                                ? Colors.green.shade300
                                : Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                              size: 15,
                              color: isConnected ? Colors.green.shade700 : Colors.grey.shade600,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isConnected ? '已连接' : '未连接',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: isConnected ? Colors.green.shade800 : Colors.grey.shade700,
                              ),
                            ),
                            if (isConnected && rssiText.isNotEmpty) ...[
                              const SizedBox(width: 4),
                              Text(
                                rssiText,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green.shade700,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(patientsProvider);
        },
        child: patients.when(
          data: (list) => _buildPatientList(context, ref, list),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('加载失败: $e')),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/patients/new'),
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('新建会话'),
      ),
    );
  }

  Widget _buildPatientList(
      BuildContext context, WidgetRef ref, List<Patient> patients) {
    final activePatients =
        patients.where((p) => p.status == PatientStatus.active).toList();
    final dischargedPatients =
        patients.where((p) => p.status == PatientStatus.discharged).toList();

    final filtered = switch (_filter) {
      PatientFilter.active => activePatients,
      PatientFilter.discharged => dischargedPatients,
      PatientFilter.all => patients,
    };

    final sorted = List<Patient>.from(filtered);
    sorted.sort((a, b) {
      int cmp;
      switch (_sortField) {
        case PatientSortField.recentActivity:
          cmp = a.updatedAt.compareTo(b.updatedAt);
          break;
        case PatientSortField.createdAt:
          cmp = a.createdAt.compareTo(b.createdAt);
          break;
        case PatientSortField.name:
          cmp = a.name.compareTo(b.name);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });

    return SlidableAutoCloseBehavior(
      closeWhenOpened: true,
      closeWhenTapped: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _closeAllOpenSlidables,
        child: ListView.builder(
          padding: const EdgeInsets.only(bottom: 24),
          itemCount: 1 + (sorted.isEmpty ? 1 : sorted.length),
          itemBuilder: (context, index) {
            if (index == 0) {
              return _buildSortHeader(context);
            }
            if (sorted.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 80),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.forum_outlined, size: 56, color: Colors.grey),
                      const SizedBox(height: 12),
                      Text(
                        _filter == PatientFilter.active
                            ? '暂无进行中会话'
                            : _filter == PatientFilter.discharged
                                ? '暂无已归档会话'
                                : '暂无会话',
                        style: const TextStyle(color: Colors.grey, fontSize: 15),
                      ),
                      const SizedBox(height: 6),
                      const Text('点击右下角按钮新建会话',
                          style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                ),
              );
            }
            final p = sorted[index - 1];
            return _PatientCardItem(
              key: ValueKey(p.id),
              patient: p,
              onEdit: () => _editPatient(context, p),
              onToggleStatus: () => _toggleStatus(ref, p),
              onDelete: () => _deletePatient(context, ref, p),
              onLongPress: () => _showPatientActionsSheet(context, ref, p),
              onSlidableOpened: (controller) => _openSlidables.add(controller),
              onSlidableClosed: (controller) => _openSlidables.remove(controller),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSortHeader(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Row(
        children: [
          // 左侧：排序菜单 (字段维度与升降序独立拆开，并使用 useRootNavigator: true)
          Container(
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 字段选择下拉菜单
                PopupMenuButton<PatientSortField>(
                  useRootNavigator: true,
                  initialValue: _sortField,
                  onSelected: (field) => setState(() => _sortField = field),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  itemBuilder: (ctx) => [
                    for (final field in PatientSortField.values)
                      PopupMenuItem(
                        value: field,
                        child: Row(
                          children: [
                            Icon(field.icon,
                                size: 17, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Text(field.label,
                                style: const TextStyle(fontSize: 13)),
                            if (_sortField == field) ...[
                              const Spacer(),
                              Icon(Icons.check,
                                  size: 16, color: colorScheme.primary),
                            ],
                          ],
                        ),
                      ),
                  ],
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _sortField.icon,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _sortField.label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 2),
                        Icon(
                          Icons.arrow_drop_down_rounded,
                          color: colorScheme.onSurfaceVariant,
                          size: 18,
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 0.8,
                  height: 16,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
                // 2. 升序/降序一键切换开关按钮
                InkWell(
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(8),
                    bottomRight: Radius.circular(8),
                  ),
                  onTap: () {
                    setState(() => _sortAscending = !_sortAscending);
                  },
                  child: Tooltip(
                    message: _sortAscending ? '当前升序，点击切换为降序' : '当前降序，点击切换为升序',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 5),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _sortAscending
                                ? Icons.arrow_upward_rounded
                                : Icons.arrow_downward_rounded,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            _sortAscending ? '升序' : '降序',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }

  void _showPatientActionsSheet(
      BuildContext context, WidgetRef ref, Patient patient) {
    final isActive = patient.status == PatientStatus.active;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                patient.name,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑会话信息'),
              onTap: () {
                Navigator.pop(ctx);
                _editPatient(context, patient);
              },
            ),
            ListTile(
              leading: Icon(isActive ? Icons.archive_outlined : Icons.unarchive_outlined),
              title: Text(isActive ? '标记为已归档' : '恢复为进行中'),
              onTap: () {
                Navigator.pop(ctx);
                _toggleStatus(ref, patient);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除会话', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                _deletePatient(context, ref, patient);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showBluetoothQuickSheet(BuildContext context, WidgetRef ref) async {
    final ble = ref.read(bleServiceProvider);
    if (!ble.isConnected) {
      await BleConnectManualSheet.show(context);
      return;
    }

    if (!context.mounted) return;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => Consumer(
        builder: (ctx, sheetRef, _) {
          final currentBle = sheetRef.watch(bleServiceProvider);
          final activeTiming = sheetRef.watch(activeTimingControllerProvider);
          final presets = sheetRef.watch(timingPresetsProvider);
          final isOverlayEnabled = sheetRef.watch(floatingOverlayEnabledProvider);

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. 设备与信号状态卡片
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(Icons.bluetooth_connected,
                              color: Colors.green.shade700, size: 24),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                currentBle.connectedName ?? '蓝牙键盘',
                                style: const TextStyle(
                                    fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${currentBle.connectedRemoteId ?? ""} · 信号: ${currentBle.connectedRssi} dBm',
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: BorderSide(color: Colors.red.shade300),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () async {
                            Navigator.pop(ctx);
                            await currentBle.disconnect();
                          },
                          child: const Text('断开'),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // 2. 悬浮窗快捷开关
                  SwitchListTile(
                    secondary: const Icon(Icons.picture_in_picture_alt_outlined),
                    title: const Text('常驻键盘悬浮窗',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                    subtitle: const Text('在任意界面快速贴入文字与执行快捷动作',
                        style: TextStyle(fontSize: 12)),
                    value: isOverlayEnabled,
                    onChanged: (v) async {
                      await sheetRef
                          .read(floatingOverlayEnabledProvider.notifier)
                          .toggle(v);
                    },
                  ),
                  const Divider(height: 1),

                  // 3. 输入速度快捷切换
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.speed, size: 16, color: Colors.blueGrey),
                            const SizedBox(width: 6),
                            Text(
                              '当前速度：${activeTiming.displaySummary}',
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.blueGrey),
                            ),
                            const Spacer(),
                            InkWell(
                              onTap: () {
                                Navigator.pop(ctx);
                                context.push('/settings/timing');
                              },
                              child: const Text(
                                '详细调参 >',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.blue,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: presets.map((p) {
                            final isSel = activeTiming.matchedPreset?.id == p.id;
                            return ChoiceChip(
                              label: Text(
                                '${p.name.split(" ").first} (${p.estimatedCharsPerSec.toStringAsFixed(0)}字/s)',
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight:
                                      isSel ? FontWeight.bold : FontWeight.normal,
                                ),
                              ),
                              selected: isSel,
                              visualDensity: VisualDensity.compact,
                              onSelected: (val) async {
                                if (val) {
                                  await sheetRef
                                      .read(activeTimingControllerProvider.notifier)
                                      .applyPreset(p);
                                }
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  ListTile(
                    leading: const Icon(Icons.refresh_rounded),
                    title: const Text('切换或连接新设备'),
                    onTap: () {
                      Navigator.pop(ctx);
                      BleConnectManualSheet.show(context);
                    },
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _editPatient(BuildContext context, Patient patient) {
    context.push('/patients/${patient.id}/edit');
  }

  Future<void> _toggleStatus(WidgetRef ref, Patient patient) async {
    final newStatus = patient.status == PatientStatus.active
        ? PatientStatus.discharged
        : PatientStatus.active;
    await ref
        .read(patientRepositoryProvider)
        .update(patient.copyWith(status: newStatus));
    ref.invalidate(patientsProvider);
    ref.invalidate(patientProvider(patient.id));
  }

  Future<void> _deletePatient(
      BuildContext context, WidgetRef ref, Patient patient) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除会话「${patient.name}」吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消')),
          TextButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除',
                  style: TextStyle(color: Colors.red))),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(patientRepositoryProvider).delete(patient.id);
      try {
        await MediaStorage.deletePatientMedia(patient.id);
      } catch (_) {}
      ref.invalidate(patientsProvider);
      ref.invalidate(patientProvider(patient.id));
      ref.invalidate(lastMessageProvider(patient.id));
      ref.invalidate(messagesProvider(patient.id));
    }
  }
}

class _LastMessagePreview extends ConsumerWidget {
  final String patientId;
  const _LastMessagePreview({required this.patientId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lastMsg = ref.watch(lastMessageProvider(patientId));
    return lastMsg.when(
      data: (msg) {
        if (msg == null) return const SizedBox.shrink();
        return Text(
          _previewMessage(msg),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 13, color: Colors.grey[600]),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (err, stack) => const SizedBox.shrink(),
    );
  }

  static String _previewMessage(Message msg) {
    switch (msg.type) {
      case MessageType.text:
        return msg.content ?? '';
      case MessageType.voice:
        return '[语音 ${(msg.durationMs ?? 0) ~/ 1000}s]';
      case MessageType.photo:
        return '[图片 ${msg.pageCount}页]';
      case MessageType.document:
        return '[文件] ${msg.content ?? ""}';
      case MessageType.generatedRecord:
        final title = msg.recordMeta?.templateName ?? '生成文书';
        return '[$title]';
      default:
        return msg.content ?? '';
    }
  }
}

class _PatientCardItem extends StatefulWidget {
  final Patient patient;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;
  final VoidCallback onLongPress;
  final ValueChanged<SlidableController> onSlidableOpened;
  final ValueChanged<SlidableController> onSlidableClosed;

  const _PatientCardItem({
    super.key,
    required this.patient,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onDelete,
    required this.onLongPress,
    required this.onSlidableOpened,
    required this.onSlidableClosed,
  });

  @override
  State<_PatientCardItem> createState() => _PatientCardItemState();
}

class _PatientCardItemState extends State<_PatientCardItem> {
  SlidableController? _controller;
  bool _isOpened = false;

  void _onAnimationChanged() {
    if (_controller == null) return;
    final val = _controller!.animation.value;
    if (val > 0.05 && !_isOpened) {
      _isOpened = true;
      widget.onSlidableOpened(_controller!);
    } else if (val <= 0.05 && _isOpened) {
      _isOpened = false;
      widget.onSlidableClosed(_controller!);
    }
  }

  @override
  void dispose() {
    _controller?.animation.removeListener(_onAnimationChanged);
    if (_isOpened && _controller != null) {
      widget.onSlidableClosed(_controller!);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final patient = widget.patient;

    return Slidable(
      key: ValueKey(patient.id),
      endActionPane: ActionPane(
        motion: const BehindMotion(),
        children: [
          SlidableAction(
            onPressed: (_) => widget.onEdit(),
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            icon: Icons.edit,
            label: '编辑',
          ),
          SlidableAction(
            onPressed: (_) => widget.onToggleStatus(),
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            icon: patient.status == PatientStatus.active
                ? Icons.archive_outlined
                : Icons.unarchive_outlined,
            label: patient.status == PatientStatus.active ? '归档' : '激活',
          ),
          SlidableAction(
            onPressed: (_) => widget.onDelete(),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
            icon: Icons.delete,
            label: '删除',
          ),
        ],
      ),
      child: Builder(
        builder: (ctx) {
          final ctrl = Slidable.of(ctx);
          if (ctrl != null && ctrl != _controller) {
            _controller?.animation.removeListener(_onAnimationChanged);
            _controller = ctrl;
            _controller!.animation.addListener(_onAnimationChanged);
          }
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: patient.status == PatientStatus.active
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Colors.grey[200],
                child: Text(
                  patient.name.isNotEmpty ? patient.name[0] : '?',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: patient.status == PatientStatus.active
                        ? Theme.of(context).colorScheme.onPrimaryContainer
                        : Colors.grey[600],
                  ),
                ),
              ),
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      patient.name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (patient.status == PatientStatus.discharged)
                    Container(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Text('已归档',
                          style: TextStyle(fontSize: 10, color: Colors.grey)),
                    ),
                ],
              ),
              subtitle: _LastMessagePreview(patientId: patient.id),
              trailing: patient.displayMeta.isEmpty
                  ? null
                  : Text(
                      patient.displayMeta,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: Colors.grey[500]),
                    ),
              onTap: () => context.push('/patients/${patient.id}/chat'),
              onLongPress: widget.onLongPress,
            ),
          );
        },
      ),
    );
  }
}
