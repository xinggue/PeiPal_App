import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/ble/character_sanitizer.dart';

/// 非法字符转换确认与实时规则定制弹窗
///
/// 1. 显示当前文本/病历中扫描出的全部不支持字符
/// 2. 显示预设中将要转换成的目标值
/// 3. 若有未在预设中的新特殊字符，自动留空供用户直接手填指定
/// 4. 提供“同时保存到规则库”复选框，作为不断扩充新规则库的最佳时机
class CharReplacementConfirmDialog extends ConsumerStatefulWidget {
  final Set<String> unsupportedChars;

  const CharReplacementConfirmDialog({
    super.key,
    required this.unsupportedChars,
  });

  /// 呼出确认对话框，返回最终确定的替换映射规则字典；如果用户点击取消则返回 null
  static Future<Map<String, String>?> show(
    BuildContext context, {
    required Set<String> unsupportedChars,
  }) {
    return showDialog<Map<String, String>?>(
      context: context,
      builder: (_) => CharReplacementConfirmDialog(
        unsupportedChars: unsupportedChars,
      ),
    );
  }

  @override
  ConsumerState<CharReplacementConfirmDialog> createState() =>
      _CharReplacementConfirmDialogState();
}

class _CharReplacementConfirmDialogState
    extends ConsumerState<CharReplacementConfirmDialog> {
  final Map<String, TextEditingController> _controllers = {};
  bool _saveToLibrary = true;

  @override
  void initState() {
    super.initState();
    final currentRules = ref.read(charReplacementRulesProvider);
    for (final char in widget.unsupportedChars) {
      final defaultTo = currentRules[char] ?? '';
      _controllers[char] = TextEditingController(text: defaultTo);
    }
  }

  @override
  void dispose() {
    for (final ctrl in _controllers.values) {
      ctrl.dispose();
    }
    super.dispose();
  }

  void _onConfirm() {
    final effectiveReplacements = <String, String>{};
    final newRulesToPersist = <String, String>{};

    for (final entry in _controllers.entries) {
      final char = entry.key;
      final target = entry.value.text; // 允许替换为空（即删除该字符）
      effectiveReplacements[char] = target;

      if (_saveToLibrary && target.trim().isNotEmpty) {
        newRulesToPersist[char] = target;
      }
    }

    if (_saveToLibrary && newRulesToPersist.isNotEmpty) {
      ref.read(charReplacementRulesProvider.notifier).saveRules(newRulesToPersist);
    }

    Navigator.pop(context, effectiveReplacements);
  }

  @override
  Widget build(BuildContext context) {
    final currentRules = ref.watch(charReplacementRulesProvider);
    final sortedChars = widget.unsupportedChars.toList()..sort();

    // 响应当前规则变化，保证异步或动态注入的规则能够及时同步到输入框文本中
    for (final char in sortedChars) {
      if (!_controllers.containsKey(char)) {
        _controllers[char] = TextEditingController(text: currentRules[char] ?? '');
      } else {
        // 若当前输入框为空且规则库存在定义，自动回填
        if (_controllers[char]!.text.isEmpty && currentRules.containsKey(char)) {
          _controllers[char]!.text = currentRules[char]!;
        }
      }
    }

    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.spellcheck, color: Colors.deepOrange, size: 24),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              '非法字符转换确认',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前内容包含以下 ${widget.unsupportedChars.length} 个键盘无法打出的字符。请确认或指定转换结果：',
              style: const TextStyle(fontSize: 12.5, color: Colors.black87, height: 1.35),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: sortedChars.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final char = sortedChars[i];
                    final ctrl = _controllers[char]!;
                    final isInLibrary = currentRules.containsKey(char);

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          // 原始非法字符
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.red.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              char,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          const Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.grey),
                          const SizedBox(width: 10),
                          // 替换目标输入框
                          Expanded(
                            child: TextField(
                              controller: ctrl,
                              style: const TextStyle(fontSize: 13.5),
                              decoration: InputDecoration(
                                isDense: true,
                                hintText: '输入替换文本(可留空删除)',
                                hintStyle: TextStyle(fontSize: 11, color: Colors.grey.shade400),
                                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (!isInLibrary)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('新发现', style: TextStyle(fontSize: 9.5, color: Colors.deepOrange, fontWeight: FontWeight.bold)),
                            )
                          else
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text('已在库', style: TextStyle(fontSize: 9.5, color: Colors.teal, fontWeight: FontWeight.bold)),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 10),
            // 保存至规则库复选框
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _saveToLibrary,
              title: const Text('将本次填写的转换映射同步保存至规则库', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600)),
              subtitle: const Text('下次遇到相同字符时将自动沿用此规则', style: TextStyle(fontSize: 11, color: Colors.grey)),
              onChanged: (v) => setState(() => _saveToLibrary = v ?? true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('取消'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check, size: 16),
          label: const Text('确认转换'),
          onPressed: _onConfirm,
        ),
      ],
    );
  }
}
