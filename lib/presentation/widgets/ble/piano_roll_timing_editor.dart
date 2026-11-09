import 'package:flutter/material.dart';
import '../../../data/services/ble/timing_params.dart';

/// 优雅质感、符合 Flutter Material 3 设计语言的击键时序卷帘视窗
class PianoRollTimingEditor extends StatefulWidget {
  final Map<String, double> values;
  final bool enabled;
  final ValueChanged<Map<String, double>> onChanged;

  const PianoRollTimingEditor({
    super.key,
    required this.values,
    this.enabled = true,
    required this.onChanged,
  });

  @override
  State<PianoRollTimingEditor> createState() => _PianoRollTimingEditorState();
}

class _PianoRollTimingEditorState extends State<PianoRollTimingEditor> {
  String _selectedParamKey = 'cjk_gap_ms';
  late TextEditingController _numInputCtrl;

  @override
  void initState() {
    super.initState();
    _numInputCtrl = TextEditingController(text: fmtNumber(_val(_selectedParamKey)));
  }

  @override
  void didUpdateWidget(covariant PianoRollTimingEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 保持输入框显示同步
    final currentStr = fmtNumber(_val(_selectedParamKey));
    if (_numInputCtrl.text != currentStr && !FocusScope.of(context).hasFocus) {
      _numInputCtrl.text = currentStr;
    }
  }

  @override
  void dispose() {
    _numInputCtrl.dispose();
    super.dispose();
  }

  double _val(String key) {
    final spec = timingParamSpecs.firstWhere((s) => s.key == key);
    return widget.values[key] ?? spec.def;
  }

  void _adjustVal(String key, double delta) {
    if (!widget.enabled) return;
    final spec = timingParamSpecs.firstWhere((s) => s.key == key);
    final cur = _val(key);
    final next = (cur + delta).clamp(spec.min, spec.max);
    final cleanNext = (next * 10).round() / 10.0;
    _setVal(key, cleanNext);
  }

  void _setVal(String key, double value) {
    final spec = timingParamSpecs.firstWhere((s) => s.key == key);
    final clamped = value.clamp(spec.min, spec.max);
    _numInputCtrl.text = fmtNumber(clamped);
    final map = Map<String, double>.from(widget.values)..[key] = clamped;
    widget.onChanged(map);
  }

  void _selectParam(String key) {
    setState(() {
      _selectedParamKey = key;
      _numInputCtrl.text = fmtNumber(_val(key));
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final altHold = _val('alt_hold_ms');
    final digitPress = _val('alt_digit_press');
    final digitRel = _val('alt_digit_release');
    final altRel = _val('alt_release_ms');
    final cjkGap = _val('cjk_gap_ms');
    final asciiGap = _val('ascii_gap_ms');
    final keyPress = _val('key_press_ms');
    final keyGap = _val('key_gap_ms');

    // 汉字单字总耗时与每秒速率
    final singleCharMs = altHold + (5 * digitPress) + (4 * digitRel) + altRel + cjkGap;
    final charsPerSec = singleCharMs > 0 ? (1000.0 / singleCharMs) : 0.0;

    final selectedSpec = timingParamSpecs.firstWhere(
      (s) => s.key == _selectedParamKey,
      orElse: () => timingParamSpecs.first,
    );

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 卷帘主画布（带显式横向滚动条 Scrollbar，底部无多余空隙，提示左右滑动）
          Container(
            height: 176,
            color: colorScheme.surfaceContainerLow.withValues(alpha: 0.35),
            child: Scrollbar(
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
                child: CustomPaint(
                  size: const Size(690, 156),
                  painter: _CleanPianoRollPainter(
                    altHold: altHold,
                    digitPress: digitPress,
                    digitRel: digitRel,
                    altRel: altRel,
                    cjkGap: cjkGap,
                    asciiGap: asciiGap,
                    keyPress: keyPress,
                    keyGap: keyGap,
                    selectedKey: _selectedParamKey,
                    colorScheme: colorScheme,
                  ),
                ),
              ),
            ),
          ),

          const Divider(height: 1),

          // 2. 参数药丸标签栏（名称与卷帘完全一致；选中时用框框明显突出标注）
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
            color: colorScheme.surfaceContainerLowest,
            child: Wrap(
              spacing: 6,
              runSpacing: 8,
              children: timingParamSpecs.where((s) => !s.flag).map((s) {
                final isSel = s.key == _selectedParamKey;
                final v = _val(s.key);
                return InkWell(
                  onTap: () => _selectParam(s.key),
                  borderRadius: BorderRadius.circular(8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: isSel
                          ? colorScheme.primaryContainer
                          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isSel ? colorScheme.primary : colorScheme.outlineVariant.withValues(alpha: 0.5),
                        width: isSel ? 2.0 : 1.0, // 选中加粗外边框
                      ),
                      boxShadow: isSel
                          ? [
                              BoxShadow(
                                color: colorScheme.primary.withValues(alpha: 0.2),
                                blurRadius: 4,
                                spreadRadius: 1,
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          s.label, // 名称完全一致
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: isSel ? FontWeight.bold : FontWeight.w500,
                            color: isSel ? colorScheme.onPrimaryContainer : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${fmtNumber(v)}ms',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                            color: isSel ? colorScheme.primary : colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          const Divider(height: 1),

          // 3. 当前选中参数的精细调节控制台：-1, -0.1, [可直接输入的输入框], +0.1, +1 同在一行
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            color: colorScheme.surface,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 参数名称与动态详细说明解释
                Text(
                  selectedSpec.label,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
                const SizedBox(height: 3),
                Text(
                  selectedSpec.description, // 动态随选中参数展示物理意义
                  style: TextStyle(
                    fontSize: 12,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 12),

                // 核心交互行：[-1.0] [-0.1] [ 直接输入框 ] [+0.1] [+1.0]
                Row(
                  children: [
                    _buildStepButton(
                      label: '-1.0',
                      onPressed: widget.enabled ? () => _adjustVal(selectedSpec.key, -1.0) : null,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(width: 6),
                    _buildStepButton(
                      label: '-0.1',
                      onPressed: widget.enabled ? () => _adjustVal(selectedSpec.key, -0.1) : null,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(width: 8),
                    // 中间可直接键盘输入的数字框
                    SizedBox(
                      width: 96,
                      child: TextField(
                        controller: _numInputCtrl,
                        enabled: widget.enabled,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                          fontFamily: 'monospace',
                          color: colorScheme.primary,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                          suffixText: 'ms',
                          suffixStyle: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                          ),
                          filled: true,
                          fillColor: colorScheme.primary.withValues(alpha: 0.06),
                        ),
                        onSubmitted: (val) {
                          final parsed = double.tryParse(val.trim());
                          if (parsed != null) {
                            _setVal(selectedSpec.key, parsed);
                          } else {
                            _numInputCtrl.text = fmtNumber(_val(selectedSpec.key));
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    _buildStepButton(
                      label: '+0.1',
                      isPositive: true,
                      onPressed: widget.enabled ? () => _adjustVal(selectedSpec.key, 0.1) : null,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(width: 6),
                    _buildStepButton(
                      label: '+1.0',
                      isPositive: true,
                      onPressed: widget.enabled ? () => _adjustVal(selectedSpec.key, 1.0) : null,
                      colorScheme: colorScheme,
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // 4. 底部完整说明文字栏（话说明确完整，不省略）
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.speed_rounded, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '当前参数下：单个汉字输入耗时 ${singleCharMs.toStringAsFixed(1)} ms，每秒约输入 ${charsPerSec.toStringAsFixed(1)} 个汉字',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepButton({
    required String label,
    required VoidCallback? onPressed,
    required ColorScheme colorScheme,
    bool isPositive = false,
  }) {
    return Expanded(
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          minimumSize: const Size(0, 36),
          side: BorderSide(
            color: isPositive
                ? colorScheme.primary.withValues(alpha: 0.6)
                : colorScheme.outlineVariant,
          ),
          backgroundColor: isPositive
              ? colorScheme.primary.withValues(alpha: 0.05)
              : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12.5,
            color: isPositive ? colorScheme.primary : colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// 纯净典雅的卷帘绘制器（画双虚线夹角标尺、高亮边框）
class _CleanPianoRollPainter extends CustomPainter {
  final double altHold;
  final double digitPress;
  final double digitRel;
  final double altRel;
  final double cjkGap;
  final double asciiGap;
  final double keyPress;
  final double keyGap;
  final String selectedKey;
  final ColorScheme colorScheme;

  _CleanPianoRollPainter({
    required this.altHold,
    required this.digitPress,
    required this.digitRel,
    required this.altRel,
    required this.cjkGap,
    required this.asciiGap,
    required this.keyPress,
    required this.keyGap,
    required this.selectedKey,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const double leftHeaderWidth = 80.0;
    const double trackHeight = 28.0;
    const double trackGap = 16.0;

    final double track1Y = 22.0; // ALT 键轨道
    final double track2Y = track1Y + trackHeight + trackGap; // 小键盘数字轨道
    final double track3Y = track2Y + trackHeight + trackGap; // 功能控制键轨道

    // 轨道底色与文字标签
    _drawTrack(canvas, size, leftHeaderWidth, track1Y, trackHeight, 'Alt 键');
    _drawTrack(canvas, size, leftHeaderWidth, track2Y, trackHeight, '小键盘数字');
    _drawTrack(canvas, size, leftHeaderWidth, track3Y, trackHeight, '功能控制键');

    double mapWidth(double ms, {double minPx = 14, double scale = 2.0, double maxPx = 70}) {
      return (minPx + ms * scale).clamp(minPx, maxPx);
    }

    final double wHold = mapWidth(altHold, minPx: 14, scale: 1.8, maxPx: 40);
    final double wDigit = mapWidth(digitPress, minPx: 16, scale: 1.8, maxPx: 34);
    final double wDigitGap = mapWidth(digitRel, minPx: 6, scale: 1.5, maxPx: 20);
    final double wAltRel = mapWidth(altRel, minPx: 14, scale: 1.8, maxPx: 40);
    final double wCjkGap = mapWidth(cjkGap, minPx: 24, scale: 1.0, maxPx: 65);
    final double wKeyPress = mapWidth(keyPress, minPx: 28, scale: 1.0, maxPx: 65);
    final double wKeyGap = mapWidth(keyGap, minPx: 24, scale: 0.8, maxPx: 65);

    final double singleAltBlockWidth = wHold + (5 * wDigit) + (4 * wDigitGap) + wAltRel;

    // 1. 汉字 1 (Alt + 5 连击小键盘)
    final double char1StartX = leftHeaderWidth + 12;
    _drawAltBlockGroup(
      canvas: canvas,
      startX: char1StartX,
      track1Y: track1Y,
      track2Y: track2Y,
      trackHeight: trackHeight,
      wHold: wHold,
      wDigit: wDigit,
      wDigitGap: wDigitGap,
      wAltRel: wAltRel,
      indexTitle: '汉字 1',
      drawDetailLines: true,
    );

    // 2. 两个汉字之间的合成停顿 (cjk_gap_ms 汉字合成间隔，移至与数字按下同一高度，并在右侧展开文字)
    final double gap1StartX = char1StartX + singleAltBlockWidth;
    _drawEngineeringDimension(
      canvas: canvas,
      x1: gap1StartX,
      x2: gap1StartX + wCjkGap,
      y: track2Y + trackHeight + 8,
      label: '汉字合成间隔 ${fmtNumber(cjkGap)}ms',
      isSelected: selectedKey == 'cjk_gap_ms',
      topGuideY: track1Y,
      bottomGuideY: track2Y + trackHeight + 14,
      alignFromRight: true,
    );

    // 3. 汉字 2 (Alt + 5 连击小键盘)
    final double char2StartX = gap1StartX + wCjkGap;
    _drawAltBlockGroup(
      canvas: canvas,
      startX: char2StartX,
      track1Y: track1Y,
      track2Y: track2Y,
      trackHeight: trackHeight,
      wHold: wHold,
      wDigit: wDigit,
      wDigitGap: wDigitGap,
      wAltRel: wAltRel,
      indexTitle: '汉字 2',
      drawDetailLines: false,
    );

    // 4. 汉字与功能键之间的普通间隔 (ascii_gap_ms 普通字符间隔，往上移至与数字间隔同一高度，并在右侧展开文字)
    final double gap2StartX = char2StartX + singleAltBlockWidth;
    _drawEngineeringDimension(
      canvas: canvas,
      x1: gap2StartX,
      x2: gap2StartX + wCjkGap,
      y: track2Y - 8,
      label: '普通字符间隔 ${fmtNumber(asciiGap)}ms',
      isSelected: selectedKey == 'ascii_gap_ms',
      topGuideY: track2Y - 14,
      bottomGuideY: track3Y + trackHeight,
      alignFromRight: true,
    );

    // 5. 独立功能控制键 (key_press_ms 功能按键按下)
    final double keyStartX = gap2StartX + wCjkGap;
    final isKeySel = selectedKey == 'key_press_ms';
    final keyRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(keyStartX, track3Y + 2, wKeyPress, trackHeight - 4),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      keyRect,
      Paint()
        ..color = isKeySel
            ? colorScheme.primary
            : colorScheme.secondary.withValues(alpha: 0.8),
    );
    // 选中时用显眼的框框包住它
    if (isKeySel) {
      canvas.drawRRect(
        keyRect.inflate(2),
        Paint()
          ..color = colorScheme.primary
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.0,
      );
    }

    _drawText(
      canvas,
      'TAB/回车',
      Offset(keyStartX + wKeyPress / 2, track3Y + trackHeight / 2),
      const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
    );
    _drawEngineeringDimension(
      canvas: canvas,
      x1: keyStartX,
      x2: keyStartX + wKeyPress,
      y: track3Y - 8,
      label: '功能按键按下 ${fmtNumber(keyPress)}ms',
      isSelected: isKeySel,
      topGuideY: track3Y - 14,
      bottomGuideY: track3Y + trackHeight,
    );

    // 6. 功能键后稳态保护停顿 (key_gap_ms 功能按键后停顿，文字放在右侧虚线右方对齐)
    final double keyGapStartX = keyStartX + wKeyPress;
    _drawEngineeringDimension(
      canvas: canvas,
      x1: keyGapStartX,
      x2: keyGapStartX + wKeyGap,
      y: track3Y + trackHeight / 2,
      label: '功能按键后停顿 ${fmtNumber(keyGap)}ms',
      isSelected: selectedKey == 'key_gap_ms',
      topGuideY: track3Y,
      bottomGuideY: track3Y + trackHeight,
      alignFromRight: true,
    );
  }

  void _drawTrack(
    Canvas canvas,
    Size size,
    double headerWidth,
    double y,
    double height,
    String title,
  ) {
    final bgRect = Rect.fromLTWH(headerWidth, y, size.width - headerWidth, height);
    canvas.drawRect(
      bgRect,
      Paint()..color = colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
    );
    final borderPaint = Paint()
      ..color = colorScheme.outlineVariant.withValues(alpha: 0.3)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(headerWidth, y), Offset(size.width, y), borderPaint);
    canvas.drawLine(Offset(headerWidth, y + height), Offset(size.width, y + height), borderPaint);

    _drawText(
      canvas,
      title,
      Offset(headerWidth / 2, y + height / 2),
      TextStyle(
        color: colorScheme.onSurfaceVariant,
        fontSize: 11,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  void _drawAltBlockGroup({
    required Canvas canvas,
    required double startX,
    required double track1Y,
    required double track2Y,
    required double trackHeight,
    required double wHold,
    required double wDigit,
    required double wDigitGap,
    required double wAltRel,
    required String indexTitle,
    required bool drawDetailLines,
  }) {
    final totalWidth = wHold + (5 * wDigit) + (4 * wDigitGap) + wAltRel;

    // Alt 长条砖
    final altRect = RRect.fromRectAndRadius(
      Rect.fromLTWH(startX, track1Y + 2, totalWidth, trackHeight - 4),
      const Radius.circular(6),
    );
    canvas.drawRRect(
      altRect,
      Paint()..color = colorScheme.primary.withValues(alpha: 0.85),
    );
    _drawText(
      canvas,
      'Alt 键 ($indexTitle)',
      Offset(startX + totalWidth / 2, track1Y + trackHeight / 2),
      const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
    );

    // 小键盘 5 个数字砖
    double curX = startX + wHold;
    for (int i = 0; i < 5; i++) {
      final isDigitSel = selectedKey == 'alt_digit_press';
      final dRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(curX, track2Y + 3, wDigit, trackHeight - 6),
        const Radius.circular(4),
      );
      canvas.drawRRect(
        dRect,
        Paint()
          ..color = isDigitSel
              ? colorScheme.tertiary
              : colorScheme.tertiary.withValues(alpha: 0.75),
      );
      // 选中时用鲜明的外框框住
      if (isDigitSel) {
        canvas.drawRRect(
          dRect.inflate(1.5),
          Paint()
            ..color = colorScheme.primary
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8,
        );
      }

      _drawText(
        canvas,
        '${i + 1}',
        Offset(curX + wDigit / 2, track2Y + trackHeight / 2),
        const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
      );
      curX += wDigit + (i < 4 ? wDigitGap : 0);
    }

    // 工程标尺线（与按钮名字 100% 一致）
    if (drawDetailLines) {
      // 1. Alt 前置按住
      _drawEngineeringDimension(
        canvas: canvas,
        x1: startX,
        x2: startX + wHold,
        y: track1Y - 8,
        label: 'Alt 前置按住 ${fmtNumber(altHold)}',
        isSelected: selectedKey == 'alt_hold_ms',
        topGuideY: track1Y - 14,
        bottomGuideY: track1Y + trackHeight,
      );

      // 2. 小键盘数字按下（挪到第 2 个数字键，与其它线充分错开）
      final d2Start = startX + wHold + wDigit + wDigitGap;
      _drawEngineeringDimension(
        canvas: canvas,
        x1: d2Start,
        x2: d2Start + wDigit,
        y: track2Y + trackHeight + 8,
        label: '数字按下 ${fmtNumber(digitPress)}',
        isSelected: selectedKey == 'alt_digit_press',
        topGuideY: track2Y,
        bottomGuideY: track2Y + trackHeight + 14,
        alignFromRight: true,
      );

      // 3. 数字之间间隔（挪到第 4 与第 5 个数字键之间，分得开一点）
      final g4Start = startX + wHold + (4 * wDigit) + (3 * wDigitGap);
      _drawEngineeringDimension(
        canvas: canvas,
        x1: g4Start,
        x2: g4Start + wDigitGap,
        y: track2Y - 8,
        label: '数字间隔 ${fmtNumber(digitRel)}',
        isSelected: selectedKey == 'alt_digit_release',
        topGuideY: track2Y - 14,
        bottomGuideY: track2Y + trackHeight,
        alignFromRight: true,
      );

      // 4. Alt 尾持时长
      final altRelStart = startX + totalWidth - wAltRel;
      _drawEngineeringDimension(
        canvas: canvas,
        x1: altRelStart,
        x2: startX + totalWidth,
        y: track1Y - 8,
        label: 'Alt 尾持 ${fmtNumber(altRel)}',
        isSelected: selectedKey == 'alt_release_ms',
        topGuideY: track1Y - 14,
        bottomGuideY: track1Y + trackHeight,
      );
    }
  }

  /// 工程制图级双虚线夹角尺寸线绘制
  void _drawEngineeringDimension({
    required Canvas canvas,
    required double x1,
    required double x2,
    required double y,
    required String label,
    required bool isSelected,
    double? topGuideY,
    double? bottomGuideY,
    bool alignFromRight = false, // 允许文字左对齐但从右侧虚线开始延伸
  }) {
    final activeColor = colorScheme.primary;
    final normalColor = colorScheme.outline;

    final paint = Paint()
      ..color = isSelected ? activeColor : normalColor.withValues(alpha: 0.8)
      ..strokeWidth = isSelected ? 1.8 : 1.0;

    // 两侧垂直虚线引导线
    if (topGuideY != null && bottomGuideY != null) {
      _drawDashedLine(
        canvas,
        Offset(x1, topGuideY),
        Offset(x1, bottomGuideY),
        isSelected ? activeColor : normalColor,
        isSelected: isSelected,
      );
      _drawDashedLine(
        canvas,
        Offset(x2, topGuideY),
        Offset(x2, bottomGuideY),
        isSelected ? activeColor : normalColor,
        isSelected: isSelected,
      );
    }

    // 夹着的水平尺寸线
    canvas.drawLine(Offset(x1, y), Offset(x2, y), paint);
    // 两端箭头/界限短线
    canvas.drawLine(Offset(x1, y - 3), Offset(x1, y + 3), paint);
    canvas.drawLine(Offset(x2, y - 3), Offset(x2, y + 3), paint);

    // 尺寸文字标签
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          color: isSelected ? activeColor : colorScheme.onSurfaceVariant,
          fontSize: 9.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    double textCenterX;
    if (alignFromRight) {
      // 从右侧虚线开始向右延伸展开
      textCenterX = x2 + (tp.width / 2) + 4;
      // 画一小段引出横线连向文字
      canvas.drawLine(Offset(x2, y), Offset(x2 + 4, y), paint);
    } else {
      textCenterX = (x1 + x2) / 2;
    }

    final bgRect = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(textCenterX, y),
        width: tp.width + 6,
        height: tp.height + 2,
      ),
      const Radius.circular(3),
    );
    canvas.drawRRect(bgRect, Paint()..color = colorScheme.surface);
    if (isSelected) {
      canvas.drawRRect(
        bgRect,
        Paint()
          ..color = activeColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2,
      );
    }
    tp.paint(canvas, Offset(textCenterX - tp.width / 2, y - tp.height / 2));
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Color color, {bool isSelected = false}) {
    final paint = Paint()
      ..color = isSelected ? color : color.withValues(alpha: 0.35)
      ..strokeWidth = isSelected ? 1.6 : 0.8;
    const double dashWidth = 3;
    const double dashSpace = 2;
    double startY = p1.dy;
    final endY = p2.dy;
    final x = p1.dx;

    while (startY < endY) {
      final y2 = (startY + dashWidth < endY) ? startY + dashWidth : endY;
      canvas.drawLine(Offset(x, startY), Offset(x, y2), paint);
      startY += dashWidth + dashSpace;
    }
  }

  void _drawText(Canvas canvas, String text, Offset center, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(center.dx - tp.width / 2, center.dy - tp.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CleanPianoRollPainter oldDelegate) {
    return oldDelegate.altHold != altHold ||
        oldDelegate.digitPress != digitPress ||
        oldDelegate.digitRel != digitRel ||
        oldDelegate.altRel != altRel ||
        oldDelegate.cjkGap != cjkGap ||
        oldDelegate.asciiGap != asciiGap ||
        oldDelegate.keyPress != keyPress ||
        oldDelegate.keyGap != keyGap ||
        oldDelegate.selectedKey != selectedKey ||
        oldDelegate.colorScheme != colorScheme;
  }
}
