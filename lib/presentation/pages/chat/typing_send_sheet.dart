import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/ble/typing_done_prefs.dart';
import '../../../data/services/ble/character_sanitizer.dart';
import '../../../data/services/qr/qr_pack_service.dart';
import '../../../data/services/engine_b/typing_compiler.dart';
import '../../../data/services/engine_b/typing_text_normalizer.dart';
import '../../../domain/models/message.dart';
import '../../../domain/models/template.dart';
import '../../../domain/models/typing_profile.dart';
import '../../../providers/providers.dart';
import '../../widgets/chat/qr_code_display_sheet.dart';
import '../../widgets/chat/char_replacement_confirm_dialog.dart';
import '../../widgets/common/typing_done_feedback.dart';
import '../../widgets/ble/ble_connect_manual_sheet.dart';
import '../../widgets/ble/draggable_typing_overlay.dart';
import 'gcode_preview_page.dart';

/// 统一发送交互弹窗（Engine B 发送模式选择器）
class TypingSendSheet extends ConsumerStatefulWidget {
  final Message message;
  final bool isQrMode; // true 为扫码发送，false 为蓝牙打字

  const TypingSendSheet({
    super.key,
    required this.message,
    this.isQrMode = false,
  });

  static Future<void> show({
    required BuildContext context,
    required Message message,
    bool isQrMode = false,
  }) async {
    // 1. 蓝牙发送流程：如果未连接蓝牙键盘，先弹连接弹窗，连好后再弹录入选择窗
    if (!isQrMode) {
      final container = ProviderScope.containerOf(context, listen: false);
      final ble = container.read(bleServiceProvider);
      if (!ble.isConnected) {
        final connected = await BleConnectManualSheet.showAboveOverlay(context);
        if (!context.mounted) return;
        if (!connected || !ble.isConnected) {
          showAppToast(context, '未连接蓝牙键盘，无法开始录入');
          return;
        }
      }
    }

    // 2. 提前检查特殊字符：在进入发送方式选择面板前即弹出确认
    final textToCheck = message.recordJson ?? message.content ?? '';
    final canProceed = await _promptUnsupportedChars(context, textToCheck);
    if (!canProceed || !context.mounted) return;

    if (!context.mounted) return;
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => TypingSendSheet(message: message, isQrMode: isQrMode),
    );
  }

  static Future<bool> _promptUnsupportedChars(
    BuildContext context,
    String rawText,
  ) async {
    final unsupported = CharacterSanitizer.findUnsupportedCharacters(rawText);
    if (unsupported.isEmpty) return true;

    final proceed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange),
            SizedBox(width: 8),
            Text('包含特殊字符提示'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '即将发送的内容包含 ${unsupported.length} 种键盘硬件无法打出或控制敏感符号：',
              style: const TextStyle(height: 1.4),
            ),
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                unsupported.join('  '),
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 15),
              ),
            ),
            const SizedBox(height: 10),
            if (unsupported.contains('{') || unsupported.contains('}'))
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.brown),
                    SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '正文中包含英文花括号 { }，在发送时将自动替换为中文全角 ｛ ｝，以防干扰键盘指令。',
                        style: TextStyle(fontSize: 11.5, color: Colors.brown, height: 1.3),
                      ),
                    ),
                  ],
                ),
              ),
            const Text(
              '若直接发送，键盘硬件可能会将无法识别的字符跳过或丢弃；您可以选择先一键转换为标准字符，或仍保持原样忠实发送。',
              style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.35),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('取消'),
          ),
          OutlinedButton(
            onPressed: () => Navigator.pop(ctx, false), // 忠实发送原样
            child: const Text('忠实发送原样'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true), // 一键替换并发送
            child: const Text('一键替换并发送'),
          ),
        ],
      ),
    );

    if (proceed == null || !context.mounted) return false;

    if (proceed == true) {
      final confirmedReplacements = await CharReplacementConfirmDialog.show(
        context,
        unsupportedChars: unsupported,
      );
      if (confirmedReplacements == null || !context.mounted) return false;
    }
    return true;
  }

  @override
  ConsumerState<TypingSendSheet> createState() => _TypingSendSheetState();
}

class _TypingSendSheetState extends ConsumerState<TypingSendSheet> {
  TypingSendMode _selectedMode = TypingSendMode.interactiveDirect;
  bool _noCustomFlow = false;
  late Set<String> _selectedDirectSlots;
  Template? _template;
  TypingProfile? _profile;
  Map<String, dynamic> _values = {};
  Set<String> _activeKeys = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadMetadata();
  }

  Future<void> _loadMetadata() async {
    final tmplRepo = ref.read(templateRepositoryProvider);
    final msg = widget.message;

    if (msg.recordJson != null && msg.recordJson!.isNotEmpty) {
      try {
        _values = jsonDecode(msg.recordJson!) as Map<String, dynamic>;
      } catch (_) {}
    }

    final valuedKeys = _values.entries
        .where((e) => TypingTextNormalizer.normalize(e.value?.toString() ?? '').isNotEmpty)
        .map((e) => e.key)
        .toSet();
    final storedActive = msg.recordMeta?.activeSlotKeys.toSet();
    if (storedActive == null || storedActive.isEmpty) {
      _activeKeys = valuedKeys;
    } else {
      final hit = storedActive.intersection(valuedKeys);
      _activeKeys = hit.isEmpty ? valuedKeys : hit;
    }

    if (msg.templateId != null) {
      _template = await tmplRepo.getById(msg.templateId!);
    }

    // 若无对应模板，构建动态自愈模板
    _template ??= Template(
      id: 'dynamic',
      name: msg.recordMeta?.templateName ?? '文书',
      slots: _values.keys
          .map((k) => TemplateSlot(key: k, label: k, type: SlotType.text))
          .toList(),
    );

    // 默认选取字段录入，且默认全选所有可用字段
    _selectedDirectSlots = Set.from(_template!.sortedSlots.map((s) => s.key));
    if (_selectedDirectSlots.isEmpty) {
      _selectedDirectSlots = Set.from(_activeKeys);
    }

    _noCustomFlow = _template!.typingProfiles.isEmpty;
    _profile = _noCustomFlow
        ? TypingProfile(name: '默认方案')
        : _template!.typingProfiles.first;
    _selectedMode = TypingSendMode.interactiveDirect;

    if (mounted) setState(() => _isLoading = false);
  }

  String _buildPreviewText() {
    if (_template == null || _profile == null) return '';
    final isQrStandard = widget.isQrMode && ref.read(qrConfigProvider).isStandardScanner;
    return TypingCompiler.compile(TypingCompileContext(
      template: _template!,
      profile: _profile!,
      recordValues: _values,
      activeSlotKeys: _activeKeys,
      mode: isQrStandard ? TypingSendMode.interactiveDirect : _selectedMode,
      targetSlotKeysForDirect: _selectedDirectSlots,
    ));
  }

  Future<void> _executeSend() async {
    final text = _buildPreviewText();
    if (text.isEmpty) {
      showAppToast(context, '没有可发送的内容');
      return;
    }

    // 应用已配置的字符替换规则库
    final rules = ref.read(charReplacementRulesProvider);
    final sanitizedText = CharacterSanitizer.applyReplacements(text, rules);
    await _doActualSend(sanitizedText);
  }

  Future<void> _doActualSend(String text) async {
    Navigator.pop(context); // 关掉选择面板

    if (widget.isQrMode) {
      showQrCodeDisplaySheet(context, text: text, title: '扫码发送 · ${_template?.name ?? "文书"}');
      return;
    }

    // 蓝牙发送流程：如果未连接，绝不自动隐式回连，而是弹出直观的手动连接面板让用户安心挑选设备
    final ble = ref.read(bleServiceProvider);
    if (!ble.isConnected) {
      final connected = await BleConnectManualSheet.showAboveOverlay(context);
      if (!connected) return;
      if (!mounted) return;
      if (!ble.isConnected) {
        showAppToast(context, '未连接蓝牙键盘，已取消发送');
        return;
      }
    }

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final rawFeedback = await settingsRepo.get('typing_done_feedback');
    final prefs = TypingDonePrefs.parse(rawFeedback);

    // 唤起全局悬浮球与打字进度监控
    final typingCtrl = ref.read(typingProgressControllerProvider);
    typingCtrl.startTyping(
      title: _template?.name ?? '文书',
      text: text,
    );

    final ok = await ble.sendTextDone(text);
    typingCtrl.finishTyping();

    if (mounted) {
      if (ok) {
        notifyTypingDone(context, prefs);
      }
    }
  }

  void _openGCodePreview() {
    final text = _buildPreviewText();
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GCodePreviewPage(
          title: _template?.name ?? '发送指令',
          gcodeText: text,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const SizedBox(
        height: 200,
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final hasMultipleProfiles = _template != null && _template!.typingProfiles.length > 1;
    final slots = _template!.sortedSlots;
    final qrConfig = ref.watch(qrConfigProvider);
    final isQrStandardScanner = widget.isQrMode && qrConfig.isStandardScanner;
    final activeSelectedMode = isQrStandardScanner
        ? TypingSendMode.interactiveDirect
        : _selectedMode;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  widget.isQrMode ? Icons.qr_code_2 : Icons.bluetooth,
                  color: widget.isQrMode ? Colors.blue : Colors.teal,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isQrMode ? '扫码发送模式' : '蓝牙输入模式',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // 模式 1：按字段平铺展开 (默认且全选)
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: activeSelectedMode == TypingSendMode.interactiveDirect
                    ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25)
                    : null,
              ),
              child: RadioListTile<TypingSendMode>(
                value: TypingSendMode.interactiveDirect,
                groupValue: activeSelectedMode,
                title: const Text('按字段平铺展开 (默认)', style: TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('按「字段名：内容」回车换行录入 (已选 ${_selectedDirectSlots.length} 项)'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => _selectedMode = v!),
              ),
            ),

            // 模式 2：按照输入方案录入（常规扫码枪模式下禁用）
            Opacity(
              opacity: isQrStandardScanner ? 0.45 : 1.0,
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: activeSelectedMode == TypingSendMode.pipelineKeepFlow
                      ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25)
                      : null,
                ),
                child: Column(
                  children: [
                    RadioListTile<TypingSendMode>(
                      value: TypingSendMode.pipelineKeepFlow,
                      groupValue: activeSelectedMode,
                      title: Text(
                        isQrStandardScanner ? '按照输入方案录入 (常规扫码枪不可用)' : '按照输入方案录入',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        isQrStandardScanner
                            ? '常规扫码枪仅支持纯文本，不支持按键动作方案'
                            : (_noCustomFlow
                                ? '此模板未配置输入方案'
                                : '按文书输入方案依次打字，按导航键跨过输入框'),
                      ),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      onChanged: isQrStandardScanner ? null : (v) => setState(() => _selectedMode = v!),
                    ),
                    if (activeSelectedMode == TypingSendMode.pipelineKeepFlow && hasMultipleProfiles)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(36, 0, 16, 10),
                        child: Row(
                          children: [
                            const Icon(Icons.tune, size: 16, color: Colors.blueGrey),
                            const SizedBox(width: 6),
                            const Text('选用方案：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String>(
                                  value: _profile?.id,
                                  isDense: true,
                                  items: _template!.typingProfiles
                                      .map((p) => DropdownMenuItem(
                                            value: p.id,
                                            child: Text(p.name, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                                          ))
                                      .toList(),
                                  onChanged: isQrStandardScanner
                                      ? null
                                      : (pId) {
                                          if (pId == null) return;
                                          final p = _template!.typingProfiles.firstWhere((item) => item.id == pId);
                                          setState(() => _profile = p);
                                        },
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 字段直选大列表：当选择字段平铺模式时，直接铺展在中间充裕的空白区域
            if (activeSelectedMode == TypingSendMode.interactiveDirect) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Text('选择发送字段：', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                      onPressed: () {
                        setState(() {
                          _selectedDirectSlots.addAll(slots.map((s) => s.key));
                        });
                      },
                      child: const Text('全选'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                      onPressed: () {
                        setState(() {
                          _selectedDirectSlots.clear();
                        });
                      },
                      child: const Text('清空'),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: const EdgeInsets.symmetric(horizontal: 6)),
                      onPressed: () {
                        setState(() {
                          final all = slots.map((s) => s.key).toSet();
                          final inverted = all.difference(_selectedDirectSlots);
                          _selectedDirectSlots = inverted;
                        });
                      },
                      child: const Text('反选'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: ListView.separated(
                    itemCount: slots.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final s = slots[i];
                      final isChecked = _selectedDirectSlots.contains(s.key);
                      final hasVal = _values[s.key]?.toString().trim().isNotEmpty ?? false;

                      return CheckboxListTile(
                        value: isChecked,
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                        title: Text(
                          s.label.isNotEmpty ? s.label : s.key,
                          style: TextStyle(fontWeight: hasVal ? FontWeight.bold : FontWeight.normal, fontSize: 13.5),
                        ),
                        subtitle: Text(
                          hasVal ? (_values[s.key].toString().replaceAll('\n', ' ')) : '(无内容)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: hasVal ? Colors.black54 : Colors.grey),
                        ),
                        onChanged: (c) {
                          setState(() {
                            if (c == true) {
                              _selectedDirectSlots.add(s.key);
                            } else {
                              _selectedDirectSlots.remove(s.key);
                            }
                          });
                        },
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ] else
              const Spacer(),

            // 底部操作栏：左侧灰色「预览代码」按钮（常规扫码枪模式下隐藏） + 主发送/扫码按钮
            Row(
              children: [
                if (!isQrStandardScanner) ...[
                  // 1/4 灰色预览代码按钮
                  Expanded(
                    flex: 1,
                    child: FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                        foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      onPressed: _openGCodePreview,
                      child: const Text('预览代码', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                // 主发送按钮
                Expanded(
                  flex: isQrStandardScanner ? 1 : 3,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    icon: Icon(widget.isQrMode ? Icons.qr_code_2 : Icons.send_rounded),
                    label: Text(
                      widget.isQrMode ? '生成二维码并开始扫码' : '立即通过蓝牙键盘发送',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    ),
                    onPressed: _executeSend,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
