import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class TutorialSpotlightOverlay extends StatefulWidget {
  final GlobalKey? targetKey;
  final String stepTag;
  final String title;
  final String description;
  final String nextButtonLabel;
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final VoidCallback? onTargetTap;
  final double targetPadding;
  final double borderRadius;
  final Widget? customAction;
  final Widget? extraContent;
  /// 为 true 时不再依赖 targetKey，而是高亮整个屏幕下半部分。
  final bool highlightLowerHalf;
  /// 为 true 时引导卡片固定在顶部，不随高亮目标移动。
  final bool pinTooltip;

  const TutorialSpotlightOverlay({
    super.key,
    this.targetKey,
    required this.stepTag,
    required this.title,
    required this.description,
    this.nextButtonLabel = '下一步',
    required this.onNext,
    required this.onSkip,
    this.onTargetTap,
    this.targetPadding = 6.0,
    this.borderRadius = 14.0,
    this.customAction,
    this.extraContent,
    this.highlightLowerHalf = false,
    this.pinTooltip = false,
  });

  @override
  State<TutorialSpotlightOverlay> createState() =>
      _TutorialSpotlightOverlayState();
}

class _TutorialSpotlightOverlayState extends State<TutorialSpotlightOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final Animation<double> _pulseAnimation;
  Rect? _targetRect;
  final GlobalKey _overlayKey = GlobalKey();
  Timer? _resolveTimer;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _pulseAnimation = CurvedAnimation(
      parent: _pulseController,
      curve: Curves.easeInOut,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) => _startResolveLoop());
  }

  @override
  void didUpdateWidget(covariant TutorialSpotlightOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetKey != widget.targetKey ||
        oldWidget.highlightLowerHalf != widget.highlightLowerHalf) {
      _startResolveLoop();
    }
  }

  @override
  void dispose() {
    _resolveTimer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  /// 页面刚推入时会有转场动画/布局抖动，目标位置会持续变化，
  /// 因此在最初约 1.2 秒内反复校准，避免第一次进入时高光偏移。
  void _startResolveLoop() {
    _resolveTimer?.cancel();
    _resolveTarget();
    var ticks = 0;
    _resolveTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      _resolveTarget();
      ticks++;
      if (ticks >= 24) timer.cancel();
    });
  }

  void _resolveTarget() {
    if (!mounted) return;

    final overlayBox =
        _overlayKey.currentContext?.findRenderObject() as RenderBox?;
    final overlayOrigin =
        overlayBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    Rect? newRect;

    if (widget.highlightLowerHalf) {
      final screenSize = MediaQuery.sizeOf(context);
      newRect = Rect.fromLTWH(
        0,
        screenSize.height * 0.5,
        screenSize.width,
        screenSize.height * 0.5,
      );
    } else {
      final targetContext = widget.targetKey?.currentContext;
      if (targetContext == null) return;
      final renderBox = targetContext.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final offset = renderBox.localToGlobal(Offset.zero);
        final size = renderBox.size;
        newRect = (offset & size)
            .inflate(widget.targetPadding)
            .shift(-overlayOrigin);
      }
    }

    if (newRect != null && _targetRect != newRect) {
      setState(() => _targetRect = newRect);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final safePadding = MediaQuery.of(context).padding;
    final target = _targetRect ??
        Rect.fromCenter(
          center: Offset(screenSize.width / 2, screenSize.height / 2),
          width: 80,
          height: 80,
        );

    final isUpperHalf = target.center.dy < screenSize.height * 0.55;

    final double? tooltipTop;
    final double? tooltipBottom;
    if (widget.pinTooltip) {
      tooltipTop = safePadding.top + kToolbarHeight + 12;
      tooltipBottom = null;
    } else if (isUpperHalf) {
      tooltipTop =
          (target.bottom + 14).clamp(safePadding.top + 10, screenSize.height - 240);
      tooltipBottom = null;
    } else {
      tooltipTop = null;
      tooltipBottom = (screenSize.height - target.top + 14)
          .clamp(safePadding.bottom + 10, screenSize.height - 240);
    }

    return Stack(
      key: _overlayKey,
      children: [
        // 1. 半透明挖孔高亮遮罩与呼吸脉冲光晕
        AnimatedBuilder(
          animation: _pulseAnimation,
          builder: (context, _) {
            return CustomPaint(
              size: screenSize,
              painter: _SpotlightPainter(
                targetRect: target,
                borderRadius: widget.borderRadius,
                pulseValue: _pulseAnimation.value,
              ),
            );
          },
        ),

        // 2. 目标高亮可触控区域
        if (widget.onTargetTap != null)
          Positioned.fromRect(
            rect: target,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTargetTap,
              child: const SizedBox.expand(),
            ),
          ),

        // 3. 引导提示气泡卡片
        Positioned(
          left: 20,
          right: 20,
          top: tooltipTop,
          bottom: tooltipBottom,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
                border: Border.all(
                  color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: 0.4),
                  width: 0.8,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          widget.stepTag,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: widget.onSkip,
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: Text(
                          '跳过',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    widget.title,
                    style: const TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.description,
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.48,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  if (widget.extraContent != null) ...[
                    const SizedBox(height: 10),
                    widget.extraContent!,
                  ],
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (widget.customAction != null) ...[
                        widget.customAction!,
                        const SizedBox(width: 10),
                      ],
                      FilledButton(
                        onPressed: widget.onNext,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          widget.nextButtonLabel,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect targetRect;
  final double borderRadius;
  final double pulseValue;

  _SpotlightPainter({
    required this.targetRect,
    required this.borderRadius,
    required this.pulseValue,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final screenRect = Rect.fromLTWH(0, 0, size.width, size.height);
    final rrect = RRect.fromRectAndRadius(
      targetRect,
      Radius.circular(borderRadius),
    );

    // 1. 绘制暗色蒙版挖孔
    final path = Path()
      ..addRect(screenRect)
      ..addRRect(rrect)
      ..fillType = PathFillType.evenOdd;

    final maskPaint = Paint()..color = Colors.black.withValues(alpha: 0.72);
    canvas.drawPath(path, maskPaint);

    // pulseValue 从 0 → 1：白框由外向内收缩，最终贴合高亮区（无缝隙）。
    final contract = 1.0 - pulseValue;
    final borderInflate = contract * 9.0;

    // 2. 白色柔和外发光（随收缩逐渐消散）
    final haloRRect = RRect.fromRectAndRadius(
      targetRect.inflate(borderInflate + 4),
      Radius.circular(borderRadius + borderInflate + 4),
    );
    final haloPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 8
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, 5)
      ..color = Colors.white.withValues(alpha: 0.08 + contract * 0.22);
    canvas.drawRRect(haloRRect, haloPaint);

    // 3. 清晰醒目的白色描边（最内圈正好压在高亮区边缘，无缝隙）
    final borderRRect = RRect.fromRectAndRadius(
      targetRect.inflate(borderInflate),
      Radius.circular(borderRadius + borderInflate),
    );
    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..color = Colors.white.withValues(alpha: 0.55 + (1 - contract) * 0.45);
    canvas.drawRRect(borderRRect, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) {
    return oldDelegate.targetRect != targetRect ||
        oldDelegate.borderRadius != borderRadius ||
        oldDelegate.pulseValue != pulseValue;
  }
}
