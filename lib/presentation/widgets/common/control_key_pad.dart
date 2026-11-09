import 'package:flutter/material.dart';

/// 常用控制与编辑键
const _commonControlKeys = [
  ('TAB', 'Tab ⇥'),
  ('ENTER', 'Enter ↵'),
  ('SPACE', 'Space ␣'),
  ('ESC', 'Esc'),
  ('BS', '退格 ⌫'),
  ('DEL', '删除 Del'),
  ('INSERT', 'Ins'),
  ('WIN', 'Win ❖'),
];

/// 光标导航键
const _navigationKeys = [
  ('UP', '↑ 上'),
  ('DOWN', '↓ 下'),
  ('LEFT', '← 左'),
  ('RIGHT', '→ 右'),
  ('HOME', 'Home'),
  ('END', 'End'),
  ('PGUP', 'PgUp'),
  ('PGDN', 'PgDn'),
];

/// QWERTY 全键盘行定义
const _numberRow = ['1', '2', '3', '4', '5', '6', '7', '8', '9', '0'];
const _qwertyRow1 = ['Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P'];
const _qwertyRow2 = ['A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L'];
const _qwertyRow3 = ['Z', 'X', 'C', 'V', 'B', 'N', 'M'];

/// 功能键 F1 - F12
const _fnRow1 = ['F1', 'F2', 'F3', 'F4', 'F5', 'F6'];
const _fnRow2 = ['F7', 'F8', 'F9', 'F10', 'F11', 'F12'];

/// 高度复用、支持修饰键组合与全尺寸 QWERTY 布局的控制按键面板
class ControlKeyPad extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool? isExpanded;
  final ValueChanged<bool>? onExpansionChanged;
  final bool initiallyExpanded;
  final bool collapsible;
  final bool singleKeyMode;

  const ControlKeyPad({
    super.key,
    required this.controller,
    this.label = '快捷按键与组合键面板',
    this.isExpanded,
    this.onExpansionChanged,
    this.initiallyExpanded = false,
    this.collapsible = true,
    this.singleKeyMode = false,
  });

  @override
  State<ControlKeyPad> createState() => _ControlKeyPadState();
}

class _ControlKeyPadState extends State<ControlKeyPad> {
  late bool _internalExpanded;

  bool get _isExpanded =>
      !widget.collapsible ? true : (widget.isExpanded ?? _internalExpanded);

  // 修饰键状态
  bool _ctrl = false;
  bool _alt = false;
  bool _shift = false;
  bool _win = false;

  @override
  void initState() {
    super.initState();
    _internalExpanded = widget.initiallyExpanded;
  }

  void _toggleExpanded() {
    if (!widget.collapsible) return;
    final next = !_isExpanded;
    if (widget.onExpansionChanged != null) {
      widget.onExpansionChanged!(next);
    } else {
      setState(() => _internalExpanded = next);
    }
  }

  /// 插入单键或组合键
  void _insertKey(String baseKey) {
    final modifiers = <String>[];
    if (_ctrl) modifiers.add('CTRL');
    if (_alt) modifiers.add('ALT');
    if (_shift) modifiers.add('SHIFT');
    if (_win) modifiers.add('WIN');

    String tag;
    if (modifiers.isNotEmpty && !modifiers.contains(baseKey)) {
      tag = '{${[...modifiers, baseKey].join('+')}}';
    } else {
      tag = '{$baseKey}';
    }

    if (widget.singleKeyMode) {
      widget.controller.value = TextEditingValue(
        text: tag,
        selection: TextSelection.collapsed(offset: tag.length),
      );
    } else {
      final text = widget.controller.text;
      final selection = widget.controller.selection;
      final start = selection.isValid ? selection.start : text.length;
      final before = text.substring(0, start);
      final after = text.substring(start);
      final needsComma =
          before.trim().isNotEmpty && !before.trimRight().endsWith(',');
      final prefix = needsComma ? ', ' : '';
      final newText = '$before$prefix$tag$after';

      widget.controller.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
            offset: before.length + prefix.length + tag.length),
      );
    }

    // 敲击组合键后自动释放修饰键，方便继续点选下一个按键
    if (modifiers.isNotEmpty) {
      setState(() {
        _ctrl = false;
        _alt = false;
        _shift = false;
        _win = false;
      });
    }
  }

  /// 删除最后一个按键标签（多键模式下便捷退格）
  void _removeLastTag() {
    final raw = widget.controller.text.trim();
    if (raw.isEmpty) return;
    final parts = raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (parts.isEmpty) {
      widget.controller.clear();
      return;
    }
    parts.removeLast();
    final updated = parts.join(', ');
    widget.controller.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: updated.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasModifiers = _ctrl || _alt || _shift || _win;
    final modPrefix = [
      if (_ctrl) 'Ctrl',
      if (_alt) 'Alt',
      if (_shift) 'Shift',
      if (_win) 'Win',
    ].join(' + ');

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasModifiers
              ? colorScheme.primary.withValues(alpha: 0.5)
              : Theme.of(context).dividerColor.withValues(alpha: 0.25),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.collapsible)
            InkWell(
              onTap: _toggleExpanded,
              borderRadius: BorderRadius.circular(6),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  children: [
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_hide_outlined
                          : Icons.keyboard_alt_outlined,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _isExpanded ? '收起键盘' : '展开软键盘',
                      style: TextStyle(fontSize: 11.5, color: Colors.grey[600]),
                    ),
                    const SizedBox(width: 2),
                    Icon(
                      _isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      size: 18,
                      color: Colors.grey[600],
                    ),
                  ],
                ),
              ),
            ),
          if (_isExpanded) ...[
            if (widget.collapsible) const SizedBox(height: 8),

            // 1. 修饰键锁定栏 + 快捷退格/清空
            Row(
              children: [
                const Text(
                  '修饰键：',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey),
                ),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: _buildModifierButton(
                            'Ctrl', _ctrl, (v) => setState(() => _ctrl = v)),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _buildModifierButton(
                            'Alt', _alt, (v) => setState(() => _alt = v)),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _buildModifierButton(
                            'Shift', _shift, (v) => setState(() => _shift = v)),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: _buildModifierButton(
                            'Win', _win, (v) => setState(() => _win = v)),
                      ),
                    ],
                  ),
                ),
                if (!widget.singleKeyMode) ...[
                  const SizedBox(width: 6),
                  IconButton(
                    icon: const Icon(Icons.backspace_outlined, size: 16),
                    tooltip: '删除上一个按键',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: _removeLastTag,
                  ),
                ],
              ],
            ),

            if (hasModifiers) ...[
              const SizedBox(height: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.bolt_rounded,
                        size: 14, color: colorScheme.primary),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        '组合就绪：$modPrefix + 点击下方任意按键',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() {
                        _ctrl = false;
                        _alt = false;
                        _shift = false;
                        _win = false;
                      }),
                      child: Text(
                        '取消修饰',
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.primary,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 8),

            // 2. 常用编辑与控制键 (4列整齐网格)
            _buildSectionLabel('常用控制与编辑'),
            const SizedBox(height: 4),
            _buildPairGridRow(_commonControlKeys.sublist(0, 4)),
            const SizedBox(height: 4),
            _buildPairGridRow(_commonControlKeys.sublist(4, 8)),

            const SizedBox(height: 8),

            // 3. 标准 QWERTY 全键盘（数字排 + 3排字母）
            _buildSectionLabel('字母与数字键盘 (QWERTY)'),
            const SizedBox(height: 4),
            _buildQwertyRow(_numberRow),
            const SizedBox(height: 4),
            _buildQwertyRow(_qwertyRow1),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: _buildQwertyRow(_qwertyRow2),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: _buildQwertyRow(_qwertyRow3),
            ),

            const SizedBox(height: 8),

            // 4. 光标导航与翻页键 (4列整齐网格)
            _buildSectionLabel('方向与导航'),
            const SizedBox(height: 4),
            _buildPairGridRow(_navigationKeys.sublist(0, 4)),
            const SizedBox(height: 4),
            _buildPairGridRow(_navigationKeys.sublist(4, 8)),

            const SizedBox(height: 8),

            // 5. 功能键 F1 - F12 (6列整齐网格)
            _buildSectionLabel('功能键 (F1 - F12)'),
            const SizedBox(height: 4),
            _buildQwertyRow(_fnRow1),
            const SizedBox(height: 4),
            _buildQwertyRow(_fnRow2),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 10.5,
        color: Colors.grey.shade600,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _buildModifierButton(
    String label,
    bool active,
    ValueChanged<bool> onChanged,
  ) {
    final primary = Theme.of(context).colorScheme.primary;
    return Material(
      color: active ? primary : Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onChanged(!active),
        child: Container(
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: active ? primary : Colors.grey.withValues(alpha: 0.4),
              width: active ? 1.4 : 1.0,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: active ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }

  /// 一排等宽键帽（用于 QWERTY 字母行、数字行、F1-F12 行）
  Widget _buildQwertyRow(List<String> keys) {
    return Row(
      children: [
        for (int i = 0; i < keys.length; i++) ...[
          if (i > 0) const SizedBox(width: 3.5),
          Expanded(
            child: _buildKeyCap(keyTag: keys[i], displayLabel: keys[i]),
          ),
        ],
      ],
    );
  }

  /// 一排带显示别名的等宽键帽（用于控制键与方向键）
  Widget _buildPairGridRow(List<(String, String)> items) {
    return Row(
      children: [
        for (int i = 0; i < items.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: _buildKeyCap(
              keyTag: items[i].$1,
              displayLabel: items[i].$2,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildKeyCap({
    required String keyTag,
    required String displayLabel,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    final hasModifiers = _ctrl || _alt || _shift || _win;
    return Material(
      color: hasModifiers
          ? colorScheme.primary.withValues(alpha: 0.1)
          : colorScheme.surface,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => _insertKey(keyTag),
        child: Container(
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: hasModifiers
                  ? colorScheme.primary.withValues(alpha: 0.65)
                  : Colors.grey.withValues(alpha: 0.35),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                offset: const Offset(0, 1),
                blurRadius: 1,
              ),
            ],
          ),
          child: Text(
            displayLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
              color: hasModifiers ? colorScheme.primary : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
