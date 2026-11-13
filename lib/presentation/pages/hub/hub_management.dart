import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../data/services/hub/hub_service.dart';
import '../../widgets/common/app_toast.dart';

enum HubManagementResult { cancelled, requested, deleted }

Future<HubManagementResult> manageHubPublication(
  BuildContext context,
  HubService service,
  HubListing listing,
) async {
  if (!listing.isMine) return HubManagementResult.cancelled;
  try {
    if (listing.kind == 'structure' && listing.visibility != 'private') {
      if (listing.withdrawalPending) return HubManagementResult.cancelled;
      final reason = await showDialog<String>(
        context: context,
        builder: (_) => _WithdrawalDialog(name: listing.title),
      );
      if (reason == null || !context.mounted) {
        return HubManagementResult.cancelled;
      }
      await service.requestStructureWithdrawal(listing.structureId, reason);
      if (context.mounted) showAppToast(context, '下架申请已提交');
      return HubManagementResult.requested;
    }
    final includeOwn = await showDialog<bool>(
      context: context,
      builder: (_) => HubDeletePublicationDialog(
        name: listing.title,
        allowOwnChildren: listing.kind == 'structure',
      ),
    );
    if (includeOwn == null || !context.mounted) {
      return HubManagementResult.cancelled;
    }
    final count = await service.delete(
      listing.id,
      includeOwnChildren: includeOwn,
    );
    if (context.mounted) showAppToast(context, '已删除 $count 项发布');
    return HubManagementResult.deleted;
  } on DioException catch (e) {
    final message = e.response?.data is Map
        ? e.response!.data['error']?.toString()
        : null;
    if (context.mounted) showAppToast(context, message ?? '操作失败，请稍后重试');
  } catch (_) {
    if (context.mounted) showAppToast(context, '操作失败，请稍后重试');
  }
  return HubManagementResult.cancelled;
}

class HubPublicationMenu extends StatelessWidget {
  final HubListing listing;
  final VoidCallback onManage;
  const HubPublicationMenu({
    super.key,
    required this.listing,
    required this.onManage,
  });

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
    tooltip: '管理发布',
    icon: const Icon(Icons.more_horiz, size: 20),
    onSelected: (_) => onManage(),
    itemBuilder: (_) => [
      if (listing.kind == 'structure' && listing.visibility != 'private')
        PopupMenuItem(
          value: 'withdraw',
          enabled: !listing.withdrawalPending,
          child: Text(listing.withdrawalPending ? '下架审核中' : '申请下架'),
        )
      else
        PopupMenuItem(
          value: 'delete',
          child: Text(
            '删除我的发布',
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}

class HubDeletePublicationDialog extends StatefulWidget {
  final String name;
  final bool allowOwnChildren;
  const HubDeletePublicationDialog({
    super.key,
    required this.name,
    required this.allowOwnChildren,
  });
  @override
  State<HubDeletePublicationDialog> createState() =>
      _HubDeletePublicationDialogState();
}

class _HubDeletePublicationDialogState
    extends State<HubDeletePublicationDialog> {
  bool _includeOwn = false;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('删除我的发布'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.name),
          if (widget.allowOwnChildren) ...[
            const SizedBox(height: 12),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('同时删除我在此文书下的其他发布'),
              value: _includeOwn,
              onChanged: (v) => setState(() => _includeOwn = v ?? false),
            ),
            const Text('其他人的贡献与设备本地模板不受影响。'),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () => Navigator.pop(context, _includeOwn),
        style: FilledButton.styleFrom(
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
        child: const Text('删除'),
      ),
    ],
  );
}

class _WithdrawalDialog extends StatefulWidget {
  final String name;
  const _WithdrawalDialog({required this.name});
  @override
  State<_WithdrawalDialog> createState() => _WithdrawalDialogState();
}

class _WithdrawalDialogState extends State<_WithdrawalDialog> {
  final _reason = TextEditingController();
  final _form = GlobalKey<FormState>();
  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('申请下架文书类型'),
    content: SingleChildScrollView(
      child: Form(
        key: _form,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(widget.name),
            const SizedBox(height: 8),
            const Text('审核通过后，该文书类型及全部关联内容仅各自发布者与管理员可见。'),
            const SizedBox(height: 16),
            TextFormField(
              controller: _reason,
              minLines: 2,
              maxLines: 5,
              maxLength: 1000,
              decoration: const InputDecoration(
                labelText: '下架原因',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  v == null || v.trim().isEmpty ? '请填写下架原因' : null,
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: () {
          if (_form.currentState!.validate()) {
            Navigator.pop(context, _reason.text.trim());
          }
        },
        child: const Text('提交申请'),
      ),
    ],
  );
}
