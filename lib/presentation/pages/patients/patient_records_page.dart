import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../data/services/ble/record_text.dart';
import '../../../data/services/ble/typing_done_prefs.dart';
import '../../../domain/models/message.dart';
import '../../../providers/providers.dart';
import '../../widgets/common/typing_done_feedback.dart';
import '../../widgets/chat/qr_code_display_sheet.dart';

class PatientRecordsPage extends ConsumerStatefulWidget {
  final String patientId;

  const PatientRecordsPage({super.key, required this.patientId});

  @override
  ConsumerState<PatientRecordsPage> createState() => _PatientRecordsPageState();
}

class _PatientRecordsPageState extends ConsumerState<PatientRecordsPage> {
  static final _dateFormat = DateFormat('yyyy-MM-dd HH:mm');
  int _outstanding = 0;

  Future<void> _deleteRecord(Message record) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除文书记录'),
        content: const Text('确定要删除这份文书记录吗？删除后不可恢复。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await ref.read(messageRepositoryProvider).delete(record.id);
      // 联动删除审计日志
      await ref
          .read(generationLogRepositoryProvider)
          .deleteByMessageId(record.id);
      ref.invalidate(messagesProvider(widget.patientId));
      ref.invalidate(lastMessageProvider(widget.patientId));
      if (mounted) {
        showAppToast(context, '已删除该份文书');
      }
    }
  }

  Future<void> _sendToDevice(Message record) async {
    final text = buildTypingText(record.recordJson);
    if (text.isEmpty) {
      showAppToast(context, '没有可发送的内容');
      return;
    }

    final ble = ref.read(bleServiceProvider);
    if (!ble.isConnected) {
      final ok = await ble.connectAuto();
      if (!ok && mounted) {
        showAppToast(context, '未找到蓝牙键盘，请先在 设置→蓝牙键盘 连接');
        return;
      }
    }
    if (!mounted) return;

    setState(() => _outstanding++);
    showAppToast(context, '已加入发送队列（${text.length} 字符）');

    final ok = await ble.sendTextDone(text);
    if (!mounted) return;
    setState(() => _outstanding--);

    if (ok) {
      if (!mounted) return;
      final prefs = ref.read(typingDonePrefsProvider).valueOrNull ??
          const TypingDonePrefs();
      await notifyTypingDone(context, prefs);
      if (!mounted) return;
      showAppToast(context, '文字已打完');
    } else {
      if (!mounted) return;
      showAppToast(context, '发送失败或超时，请检查连接');
    }
  }

  @override
  Widget build(BuildContext context) {
    final patientAsync = ref.watch(patientProvider(widget.patientId));
    final messagesAsync = ref.watch(messagesProvider(widget.patientId));

    return Scaffold(
      appBar: AppBar(
        title: patientAsync.when(
          data: (p) => Text('文书管理 · ${p?.name ?? "会话"}'),
          loading: () => const Text('文书管理'),
          error: (_, _) => const Text('文书管理'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_outlined),
            tooltip: '返回会话聊天流',
            onPressed: () => context.pop(),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: messagesAsync.when(
        data: (allMessages) {
          final records = allMessages
              .where((m) => m.type == MessageType.generatedRecord)
              .toList();

          if (records.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open_outlined,
                      size: 64, color: Colors.grey.withValues(alpha: 0.5)),
                  const SizedBox(height: 12),
                  const Text('当前会话暂未生成任何文书',
                      style: TextStyle(color: Colors.grey, fontSize: 15)),
                  const SizedBox(height: 6),
                  const Text('在对话页点击「生成文书」开始建立',
                      style: TextStyle(color: Colors.grey, fontSize: 12)),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    icon: const Icon(Icons.arrow_back),
                    label: const Text('返回对话页'),
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            itemCount: records.length,
            itemBuilder: (context, index) {
              final record = records[index];
              return _buildRecordCard(record);
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('加载文书失败: $e')),
      ),
    );
  }

  Widget _buildRecordCard(Message record) {
    Map<String, dynamic> fields = {};
    try {
      if (record.recordJson != null && record.recordJson!.isNotEmpty) {
        fields = jsonDecode(record.recordJson!) as Map<String, dynamic>;
      }
    } catch (_) {}

    final templateName =
        record.recordMeta?.templateName ?? '文书记录';
    final isPartial = record.recordMeta?.isPartial == true;
    final modelName = record.recordMeta?.model ?? '';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isPartial
              ? Colors.orange.withValues(alpha: 0.4)
              : Theme.of(context).colorScheme.outline.withValues(alpha: 0.25),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          context.push(
              '/patients/${widget.patientId}/records/${record.id}/review');
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.description,
                        size: 18, color: Colors.teal),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              templateName,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            if (isPartial) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('部分生成',
                                    style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.deepOrange,
                                        fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ],
                        ),
                        Text(
                          '${_dateFormat.format(record.createdAt)}${modelName.isNotEmpty ? " · $modelName" : ""}',
                          style:
                              const TextStyle(fontSize: 11, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.qr_code_2, size: 20, color: Colors.blue),
                    tooltip: '扫码发送',
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      final text = buildTypingText(record.recordJson);
                      if (text.isEmpty) {
                        showAppToast(context, '没有可发送的内容');
                        return;
                      }
                      showQrCodeDisplaySheet(context, text: text, title: '扫码发送文书');
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.bluetooth, size: 20, color: Colors.blue),
                    tooltip: '蓝牙发送到电脑',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _sendToDevice(record),
                  ),
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, size: 20, color: Colors.grey),
                    tooltip: '更多操作',
                    onSelected: (val) {
                      if (val == 'delete') {
                        _deleteRecord(record);
                      }
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, size: 18, color: Colors.red),
                            SizedBox(width: 8),
                            Text('删除文书', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(height: 18),

              // Key field snippets (take up to 3 fields)
              if (fields.isEmpty)
                const Text('(空文书内容)',
                    style: TextStyle(fontSize: 12, color: Colors.grey))
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in fields.entries.take(3))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: RichText(
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          text: TextSpan(
                            style: DefaultTextStyle.of(context)
                                .style
                                .copyWith(fontSize: 12),
                            children: [
                              TextSpan(
                                text: '【${e.key}】',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.blueGrey),
                              ),
                              TextSpan(
                                  text: ' ${e.value.toString().replaceAll('\n', ' ')}'),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),

              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    '包含 ${fields.length} 个字段',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  const Spacer(),
                  Text(
                    '点击审阅修改 ➔',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
