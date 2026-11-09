import 'dart:async';
import 'package:flutter/material.dart';
import '../../../core/router.dart';

enum ToastType {
  info,
  success,
  warning,
  error,
}

class AppToast {
  static OverlayEntry? _currentEntry;
  static Timer? _timer;

  static void show(
    BuildContext context,
    String message, {
    ToastType type = ToastType.info,
    Duration? duration,
    IconData? icon,
  }) {
    if (!context.mounted) return;

    // 智能推断类型（未显式指定非 info 时）
    var resolvedType = type;
    if (resolvedType == ToastType.info) {
      if (message.contains('失败') ||
          message.contains('错误') ||
          message.contains('未能') ||
          message.contains('异常') ||
          message.contains('中断')) {
        resolvedType = ToastType.error;
      } else if (message.contains('成功') ||
          message.contains('已保存') ||
          message.contains('已添加') ||
          message.contains('已删除') ||
          message.contains('已恢复') ||
          message.contains('已完成') ||
          message.contains('已填入') ||
          message.contains('已复制') ||
          message.contains('文字已打完')) {
        resolvedType = ToastType.success;
      } else if (message.contains('请') ||
          message.contains('不能为空') ||
          message.contains('未找到') ||
          message.contains('至少') ||
          message.contains('没有可发送') ||
          message.contains('尚未配置')) {
        resolvedType = ToastType.warning;
      }
    }

    final effectiveDuration = duration ??
        (resolvedType == ToastType.error
            ? const Duration(milliseconds: 3200)
            : const Duration(milliseconds: 2200));

    // 移除之前的 Toast
    _dismissCurrent();

    final overlay = Overlay.maybeOf(context, rootOverlay: true) ??
        Overlay.maybeOf(context) ??
        rootNavigatorKey.currentState?.overlay;
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _TopToastWidget(
        message: message,
        type: resolvedType,
        icon: icon,
        onDismiss: () {
          if (_currentEntry == entry) {
            _dismissCurrent();
          }
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);

    _timer = Timer(effectiveDuration, () {
      if (_currentEntry == entry) {
        _dismissCurrent();
      }
    });
  }

  static void _dismissCurrent() {
    _timer?.cancel();
    _timer = null;
    _currentEntry?.remove();
    _currentEntry = null;
  }
}

class _TopToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final IconData? icon;
  final VoidCallback onDismiss;

  const _TopToastWidget({
    required this.message,
    required this.type,
    this.icon,
    required this.onDismiss,
  });

  @override
  State<_TopToastWidget> createState() => _TopToastWidgetState();
}

class _TopToastWidgetState extends State<_TopToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    ));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDismiss() async {
    if (!mounted) return;
    await _controller.reverse();
    widget.onDismiss();
  }

  @override
  Widget build(BuildContext context) {
    final topPadding = MediaQuery.paddingOf(context).top;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Color bg;
    Color fg;
    IconData defaultIcon;

    switch (widget.type) {
      case ToastType.success:
        bg = colorScheme.primaryContainer;
        fg = colorScheme.onPrimaryContainer;
        defaultIcon = Icons.check_circle_outline_rounded;
        break;
      case ToastType.warning:
        bg = colorScheme.tertiaryContainer;
        fg = colorScheme.onTertiaryContainer;
        defaultIcon = Icons.warning_amber_rounded;
        break;
      case ToastType.error:
        bg = colorScheme.errorContainer;
        fg = colorScheme.onErrorContainer;
        defaultIcon = Icons.error_outline_rounded;
        break;
      case ToastType.info:
        bg = colorScheme.surfaceContainerHighest;
        fg = colorScheme.onSurfaceVariant;
        defaultIcon = Icons.info_outline_rounded;
        break;
    }

    final displayIcon = widget.icon ?? defaultIcon;

    return Positioned(
      top: topPadding + 12,
      left: 10,
      right: 10,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: GestureDetector(
              onVerticalDragEnd: (details) {
                if (details.primaryVelocity != null &&
                    details.primaryVelocity! < 0) {
                  _handleDismiss();
                }
              },
              onTap: _handleDismiss,
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.20),
                      blurRadius: 22,
                      offset: const Offset(0, 8),
                    ),
                  ],
                  border: Border.all(
                    color: fg.withValues(alpha: 0.22),
                    width: 1.2,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: fg.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(displayIcon, size: 26, color: fg),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        widget.message,
                        style: TextStyle(
                          color: fg,
                          fontSize: 16.5,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 快捷全局调用工具函数
void showAppToast(
  BuildContext context,
  String message, {
  ToastType type = ToastType.info,
  Duration duration = const Duration(milliseconds: 2200),
  IconData? icon,
}) {
  AppToast.show(
    context,
    message,
    type: type,
    duration: duration,
    icon: icon,
  );
}

void showSuccessToast(BuildContext context, String message) {
  AppToast.show(context, message, type: ToastType.success);
}

void showErrorToast(BuildContext context, String message) {
  AppToast.show(
    context,
    message,
    type: ToastType.error,
    duration: const Duration(milliseconds: 3200),
  );
}

void showWarningToast(BuildContext context, String message) {
  AppToast.show(context, message, type: ToastType.warning);
}

void showInfoToast(BuildContext context, String message) {
  AppToast.show(context, message, type: ToastType.info);
}
