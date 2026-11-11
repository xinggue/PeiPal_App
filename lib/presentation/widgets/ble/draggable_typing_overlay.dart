import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router.dart';
import '../../../data/services/ble/active_timing_controller.dart';
import '../../../data/services/ble/character_sanitizer.dart';
import '../../../data/services/ble/timing_params.dart';
import '../../../data/services/engine_b/typing_compiler.dart';
import '../../../domain/models/template.dart';
import '../../../domain/models/typing_action_block.dart';
import '../../../domain/models/typing_profile.dart';
import '../../../providers/providers.dart';
import '../common/app_toast.dart';
import 'ble_connect_manual_sheet.dart';
import 'typing_preset_library_sheet.dart';

/// 全局打字状态控制器
final typingProgressControllerProvider =
    ChangeNotifierProvider<TypingProgressController>((ref) {
  return TypingProgressController(ref);
});

class TypingProgressController extends ChangeNotifier {
  final Ref _ref;

  bool _isTyping = false;
  String _title = '';
  int _totalChars = 0;
  DateTime? _startTime;
  int _estimatedDurationMs = 0;
  Timer? _ticker;

  TypingProgressController(this._ref);

  bool get isTyping => _isTyping;
  String get title => _title;
  int get totalChars => _totalChars;
  DateTime? get startTime => _startTime;
  int get estimatedDurationMs => _estimatedDurationMs;

  int get elapsedMs => _startTime == null
      ? 0
      : DateTime.now().difference(_startTime!).inMilliseconds;

  void startTyping({
    required String title,
    required String text,
    int estimatedDurationMs = 0,
  }) {
    _title = title;
    _totalChars = text.length;
    _startTime = DateTime.now();
    _estimatedDurationMs = estimatedDurationMs > 0
        ? estimatedDurationMs
        : (_totalChars * 28).clamp(1000, 180000);
    _isTyping = true;

    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(milliseconds: 300), (_) {
      notifyListeners();
    });
    notifyListeners();
  }

  void finishTyping() {
    _isTyping = false;
    _ticker?.cancel();
    _ticker = null;
    notifyListeners();
  }

  Future<void> emergencyStop() async {
    final ble = _ref.read(bleServiceProvider);
    await ble.emergencyStop();
    finishTyping();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}

/// iOS 风格的非线性弹簧展开曲线 (流畅缓入与微回弹)
class SpringCurve extends Curve {
  final double a;
  final double w;

  const SpringCurve({this.a = 0.12, this.w = 11.0});

  @override
  double transformInternal(double t) {
    return -(math.pow(math.e, -t / a) * math.cos(t * w)) + 1.0;
  }
}

/// 临界阻尼弹簧曲线：起步快、末端缓慢收尾，具有明显的非线性「速度感」，
/// 但全程单调、无过冲回弹，因此不会出现窗口尺寸在末端抖动的观感。
class DampedSpringCurve extends Curve {
  final double stiffness;

  const DampedSpringCurve({this.stiffness = 7.0});

  @override
  double transformInternal(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    final w = stiffness;
    final raw = 1 - (1 + w * t) * math.exp(-w * t);
    final end = 1 - (1 + w) * math.exp(-w);
    return (raw / end).clamp(0.0, 1.0);
  }
}

/// 全局常驻键盘悬浮球与工作控制面板
class DraggableTypingOverlay extends ConsumerStatefulWidget {
  final Widget child;

  const DraggableTypingOverlay({super.key, required this.child});

  @override
  ConsumerState<DraggableTypingOverlay> createState() =>
      _DraggableTypingOverlayState();
}

class _DraggableTypingOverlayState
    extends ConsumerState<DraggableTypingOverlay>
    with SingleTickerProviderStateMixin {
  static const double _ballSize = 56.0;
  static const double _panelWidth = 310.0;
  static const double _panelHeight = 400.0;

  // 悬浮球当前坐标与贴边藏入状态：-1=藏在左边缘, 0=常规悬浮, 1=藏在右边缘
  Offset _ballPosition = const Offset(12, 140);
  int _dockedSide = 1; // 默认贴在右侧边缘
  bool _isPositionInitialized = false;

  void _ensurePositionInitialized(Size screenSize) {
    if (_isPositionInitialized) return;
    if (screenSize.width <= 0 || screenSize.height <= 0) return;
    _isPositionInitialized = true;
    _dockedSide = 1;
    // 默认放在右侧上方三分之一左右位置
    final defaultY = (screenSize.height / 3.0).clamp(36.0, screenSize.height - 100.0);
    _ballPosition = Offset(screenSize.width - _ballSize / 2, defaultY);
    final targetLeft = (screenSize.width - _panelWidth - 10.0).clamp(10.0, double.infinity);
    _panelPosition = Offset(
      targetLeft,
      defaultY.clamp(36.0, (screenSize.height - _panelHeight - 16.0).clamp(36.0, double.infinity)),
    );
  }

  // 展开面板的坐标与窗口形态：false=常规悬浮窗(310x400)，true=大窗(80%宽、2/3高)
  Offset _panelPosition = const Offset(16, 120);
  Offset? _savedFloatingPosition;
  bool _isExpanded = false;
  bool _isMaximized = false;

  // 苹果风格非线性弹性展开/收起动画控制器
  late final AnimationController _animController;
  late final Animation<double> _scaleAnimation;
  late final Animation<double> _fadeAnimation;

  // 下半部功能区 Tab：0 = 快速贴入, 1 = 快捷动作
  int _currentTab = 0;

  // 输入速度方块折叠状态（默认折叠，只显示速度和展开图标）
  bool _isSpeedSquaresExpanded = false;

  // 悬浮窗内部是否正在显示确认关闭对话框（避免全局 Dialog 无法覆盖悬浮窗）
  bool _isConfirmingClose = false;
  bool _confirmCloseDontAsk = false;

  // 快速贴入输入框
  final _quickTextCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      reverseDuration: const Duration(milliseconds: 220),
    );

    // 展开使用有弹性回弹的弹簧曲线，收起使用干脆利落的加速收缩
    final curved = CurvedAnimation(
      parent: _animController,
      curve: const SpringCurve(),
      reverseCurve: Curves.easeInCubic,
    );

    _scaleAnimation = Tween<double>(begin: 0.15, end: 1.0).animate(curved);
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
      parent: _animController,
      curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      reverseCurve: const Interval(0.3, 1.0, curve: Curves.easeIn),
    ));
  }

  @override
  void dispose() {
    _animController.dispose();
    _quickTextCtrl.dispose();
    super.dispose();
  }

  double _effectiveWidth(Size screenSize) =>
      _isMaximized ? (screenSize.width * 0.80).clamp(280.0, 700.0) : _panelWidth;

  double _effectiveHeight(Size screenSize) =>
      _isMaximized ? (screenSize.height * 0.70).clamp(380.0, 840.0) : _panelHeight;

  void _toggleMaximize(Size screenSize) {
    setState(() {
      if (!_isMaximized) {
        _savedFloatingPosition = _panelPosition;
        _isMaximized = true;
        final w = _effectiveWidth(screenSize);
        final h = _effectiveHeight(screenSize);
        _panelPosition = Offset(
          ((screenSize.width - w) / 2).clamp(10.0, double.infinity),
          ((screenSize.height - h) / 2).clamp(36.0, double.infinity),
        );
      } else {
        _isMaximized = false;
        if (_savedFloatingPosition != null) {
          final maxLeft = screenSize.width - _panelWidth - 10.0;
          final maxTop = screenSize.height - _panelHeight - 16.0;
          _panelPosition = Offset(
            _savedFloatingPosition!.dx.clamp(10.0, maxLeft > 10.0 ? maxLeft : 10.0),
            _savedFloatingPosition!.dy.clamp(36.0, maxTop > 36.0 ? maxTop : 36.0),
          );
        }
      }
    });
  }

  Future<void> _closeOverlayPermanently() async {
    final typingCtrl = ref.read(typingProgressControllerProvider);
    if (typingCtrl.isTyping) {
      showAppToast(context, '正在输入中，暂不可关闭悬浮窗');
      return;
    }

    final settingsRepo = ref.read(settingsRepositoryProvider);
    final dontAsk = await settingsRepo.get('floating_close_dont_ask') == 'true';

    if (!dontAsk && mounted) {
      setState(() {
        _isConfirmingClose = true;
        _confirmCloseDontAsk = false;
        _isHandleMenuOpen = false;
      });
      return;
    }

    await _performCloseOverlay();
  }

  Future<void> _performCloseOverlay() async {
    await _animController.reverse();
    if (mounted) {
      setState(() {
        _isExpanded = false;
        _isMaximized = false;
        _isConfirmingClose = false;
        _isHandleMenuOpen = false;
      });
      await ref.read(floatingOverlayEnabledProvider.notifier).toggle(false);
      showAppToast(context, '悬浮窗已关闭，可在设置中重新开启');
    }
  }

  void _expandPanel(Size screenSize) {
    double targetLeft = _ballPosition.dx;
    double targetTop = _ballPosition.dy;

    final curWidth = _effectiveWidth(screenSize);
    final curHeight = _effectiveHeight(screenSize);

    if (targetLeft + curWidth > screenSize.width - 10.0) {
      targetLeft = screenSize.width - curWidth - 10.0;
    }
    if (targetTop + curHeight > screenSize.height - 24.0) {
      targetTop = screenSize.height - curHeight - 24.0;
    }

    targetLeft = targetLeft.clamp(
      10.0,
      (screenSize.width - curWidth - 10.0).clamp(10.0, double.infinity),
    );
    targetTop = targetTop.clamp(
      36.0,
      (screenSize.height - curHeight - 16.0).clamp(36.0, double.infinity),
    );

    setState(() {
      _panelPosition = Offset(targetLeft, targetTop);
      _isExpanded = true;
    });
    _animController.forward(from: 0.0);
  }

  Future<void> _collapsePanel() async {
    await _animController.reverse();
    if (mounted) {
      setState(() {
        _isExpanded = false;
        _isMaximized = false;
        _isHandleMenuOpen = false;
      });
    }
  }

  Widget _buildWindowButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback? onTap,
    required Color color,
  }) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: enabled ? color.withValues(alpha: 0.12) : Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 14,
          color: enabled ? color : Colors.grey.shade400,
        ),
      ),
    );
  }

  Widget _buildHandleActionChip({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    required Color color,
  }) {
    final enabled = onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: enabled ? color : Colors.grey.shade400),
            const SizedBox(width: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: enabled ? color : Colors.grey.shade400,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // 记录点击横条时是否展开气泡菜单
  bool _isHandleMenuOpen = false;

  // 是否正在拖动窗口（拖动时禁用位置补间，保证跟手；否则用于最大化/还原的平滑过渡）
  bool _isDragging = false;

  void _showHandleMenu(Size screenSize) {
    setState(() {
      _isHandleMenuOpen = !_isHandleMenuOpen;
    });
  }

  Future<void> _openConnectSheet() async {
    final navContext = rootNavigatorKey.currentContext ?? context;
    await BleConnectManualSheet.show(navContext);
  }

  Future<void> _openPresetsSheet() async {
    final navContext = rootNavigatorKey.currentContext ?? context;
    await TypingPresetLibrarySheet.show(navContext);
  }

  Future<void> _sendQuickText() async {
    final text = _quickTextCtrl.text;
    if (text.trim().isEmpty) {
      showAppToast(context, '请输入需要贴入的文字');
      return;
    }

    final ble = ref.read(bleServiceProvider);
    if (!ble.isConnected) {
      final navContext = rootNavigatorKey.currentContext ?? context;
      final ok = await BleConnectManualSheet.show(navContext);
      if (!ok || !mounted || !ble.isConnected) return;
    }

    final rules = ref.read(charReplacementRulesProvider);
    final clean = CharacterSanitizer.applyReplacements(text, rules);

    final progress = ref.read(typingProgressControllerProvider);
    progress.startTyping(title: '快速文字贴入', text: clean);

    showAppToast(context, '已加入发送队列');
    final ok = await ble.sendTextDone(clean);
    progress.finishTyping();

    if (mounted) {
      if (ok) {
        showAppToast(context, '文字已输入完成');
        _quickTextCtrl.clear();
      } else {
        showAppToast(context, '输入中断或未完成');
      }
    }
  }

  Future<void> _triggerPresetBlock(TypingBlockPreset preset) async {
    final ble = ref.read(bleServiceProvider);
    if (!ble.isConnected) {
      final navContext = rootNavigatorKey.currentContext ?? context;
      final ok = await BleConnectManualSheet.show(navContext);
      if (!ok || !mounted || !ble.isConnected) return;
    }

    final dummyProfile = TypingProfile(name: preset.name, blocks: preset.blocks);
    final compiled = TypingCompiler.compile(TypingCompileContext(
      template: Template(id: 'preset_run', name: preset.name, slots: const []),
      profile: dummyProfile,
      recordValues: const {},
      activeSlotKeys: const {},
      mode: TypingSendMode.pipelineKeepFlow,
    ));

    if (compiled.isEmpty) return;

    final progress = ref.read(typingProgressControllerProvider);
    progress.startTyping(title: preset.name, text: compiled);

    showAppToast(context, '正在执行动作「${preset.name}」');
    final ok = await ble.sendTextDone(compiled);
    progress.finishTyping();

    if (mounted) {
      if (ok) {
        showAppToast(context, '动作「${preset.name}」执行完成');
      } else {
        showAppToast(context, '动作执行中断');
      }
    }
  }

  /// 计算悬浮球中心相对于面板的归一化锚点 (从 -1 到 1)，实现永远朝向球体展开和吸入
  Alignment _calcPanelPivot(Size screenSize) {
    final ballCenterX = _ballPosition.dx + _ballSize / 2;
    final ballCenterY = _ballPosition.dy + _ballSize / 2;

    final curWidth = _effectiveWidth(screenSize);
    final curHeight = _effectiveHeight(screenSize);

    final normX = ((ballCenterX - _panelPosition.dx) / curWidth) * 2 - 1;
    final normY = ((ballCenterY - _panelPosition.dy) / curHeight) * 2 - 1;

    return Alignment(
      normX.clamp(-1.0, 1.0),
      normY.clamp(-1.0, 1.0),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(floatingOverlayEnabledProvider);
    final typingCtrl = ref.watch(typingProgressControllerProvider);
    final screenSize = MediaQuery.of(context).size;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    _ensurePositionInitialized(screenSize);

    // 当贴边时，若屏幕尺寸变动（如旋转或调整窗口），保持贴边
    if (_dockedSide == 1) {
      _ballPosition = Offset(
        screenSize.width - _ballSize / 2,
        _ballPosition.dy.clamp(36.0, screenSize.height - 100.0),
      );
    } else if (_dockedSide == -1) {
      _ballPosition = Offset(
        -_ballSize / 2,
        _ballPosition.dy.clamp(36.0, screenSize.height - 100.0),
      );
    }

    // 当常驻开关关闭时，仅在真正打字中途临时展示（以保障急停兜底）
    final shouldShow = enabled || typingCtrl.isTyping;

    const bubbleHeight = 36.0;
    final curW = _effectiveWidth(screenSize);
    final curH = _effectiveHeight(screenSize);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        widget.child,
        if (shouldShow)
          _isExpanded
              ? AnimatedPositioned(
                  duration: _isDragging
                      ? Duration.zero
                      : const Duration(milliseconds: 340),
                  curve: const DampedSpringCurve(),
                  left: _panelPosition.dx,
                  top: _panelPosition.dy,
                  width: curW,
                  height: curH,
                  child: Material(
                    color: Colors.transparent,
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: ScaleTransition(
                        scale: _scaleAnimation,
                        alignment: _calcPanelPivot(screenSize),
                        child: _buildExpandedPanel(
                            typingCtrl, colorScheme, screenSize),
                      ),
                    ),
                  ),
                )
              : Positioned(
                  left: _ballPosition.dx,
                  top: _ballPosition.dy,
                  child: Material(
                    color: Colors.transparent,
                    child: _buildFloatingBall(
                        typingCtrl, colorScheme, screenSize),
                  ),
                ),
        // 在横条正上方浮现的气泡弹窗 (最小化 / 最大化 / 关闭)
        if (shouldShow && _isExpanded && _isHandleMenuOpen)
          Positioned(
            left: _panelPosition.dx + (curW - 200) / 2,
            top: (_panelPosition.dy - bubbleHeight - 6).clamp(24.0, double.infinity),
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 200,
                height: bubbleHeight,
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    width: 1.0,
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildHandleActionChip(
                      icon: Icons.remove_rounded,
                      label: '最小化',
                      onTap: () {
                        setState(() => _isHandleMenuOpen = false);
                        _collapsePanel();
                      },
                      color: Colors.blueGrey.shade800,
                    ),
                    Container(
                      width: 1,
                      height: 16,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                    _buildHandleActionChip(
                      icon: _isMaximized
                          ? Icons.fullscreen_exit_rounded
                          : Icons.crop_square_rounded,
                      label: _isMaximized ? '还原' : '最大化',
                      onTap: () {
                        setState(() => _isHandleMenuOpen = false);
                        _toggleMaximize(screenSize);
                      },
                      color: Colors.blueGrey.shade800,
                    ),
                    Container(
                      width: 1,
                      height: 16,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                    _buildHandleActionChip(
                      icon: Icons.close_rounded,
                      label: '关闭',
                      onTap: typingCtrl.isTyping
                          ? null
                          : () {
                              setState(() => _isHandleMenuOpen = false);
                              _closeOverlayPermanently();
                            },
                      color: typingCtrl.isTyping ? Colors.grey.shade400 : Colors.red.shade700,
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// 悬浮球形态（支持拖进左右边缘只露半圆）
  Widget _buildFloatingBall(
    TypingProgressController ctrl,
    ColorScheme colorScheme,
    Size screenSize,
  ) {
    final ble = ref.watch(bleServiceProvider);
    final isConnected = ble.isConnected;
    final isTyping = ctrl.isTyping;
    final isDocked = _dockedSide != 0;

    return MediaQuery.withNoTextScaling(
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            // 允许向左右边缘外侧多滑半个球（-28 到 width - 28），以便滑进边缘变成半圆
            final newX = (_ballPosition.dx + details.delta.dx)
                .clamp(-_ballSize / 2, screenSize.width - _ballSize / 2);
            final newY = (_ballPosition.dy + details.delta.dy)
                .clamp(36.0, screenSize.height - 100.0);
            _ballPosition = Offset(newX, newY);
            if (newX < -4.0) {
              _dockedSide = -1;
            } else if (newX > screenSize.width - _ballSize + 4.0) {
              _dockedSide = 1;
            } else {
              _dockedSide = 0;
            }
          });
        },
        onPanEnd: (_) {
          setState(() {
            // 若用户往边缘里推，则顺势贴入边缘只露半圆；否则停留在边缘内侧
            if (_ballPosition.dx < -4.0) {
              _dockedSide = -1;
              _ballPosition = Offset(-_ballSize / 2, _ballPosition.dy);
            } else if (_ballPosition.dx > screenSize.width - _ballSize + 4.0) {
              _dockedSide = 1;
              _ballPosition = Offset(
                  screenSize.width - _ballSize / 2, _ballPosition.dy);
            } else {
              _dockedSide = 0;
              _ballPosition = Offset(
                _ballPosition.dx.clamp(6.0, screenSize.width - _ballSize - 6.0),
                _ballPosition.dy,
              );
            }
          });
        },
        onTap: () => _expandPanel(screenSize),
        child: Container(
          width: _ballSize,
          height: _ballSize,
          decoration: BoxDecoration(
            color: (isTyping
                    ? colorScheme.primary
                    : (isConnected ? Colors.teal.shade700 : Colors.grey.shade700))
                .withValues(alpha: isDocked ? 0.82 : 1.0),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: (isTyping
                        ? colorScheme.primary
                        : (isConnected ? Colors.teal : Colors.black))
                    .withValues(alpha: 0.32),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: isDocked
              ? Align(
                  alignment: _dockedSide == -1
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: Padding(
                    padding: EdgeInsets.only(
                      right: _dockedSide == -1 ? 6 : 0,
                      left: _dockedSide == 1 ? 6 : 0,
                    ),
                    child: Icon(
                      isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                      color: Colors.white,
                      size: 16,
                    ),
                  ),
                )
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isConnected ? Icons.bluetooth_connected : Icons.bluetooth,
                      color: Colors.white,
                      size: 15,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      isTyping
                          ? '${(ctrl.elapsedMs / 1000).toStringAsFixed(0)}s'
                          : (isConnected ? '已连接' : '未连接'),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  /// 展开的工作面板（支持顶部拖动手柄拖拽位置）
  Widget _buildExpandedPanel(
    TypingProgressController ctrl,
    ColorScheme colorScheme,
    Size screenSize,
  ) {
    final ble = ref.watch(bleServiceProvider);
    final isConnected = ble.isConnected;
    final activeTiming = ref.watch(activeTimingControllerProvider);
    final presets = ref.watch(timingPresetsProvider);

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.65),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 顶部拖拽手柄 + 状态栏（整块顶栏可按住上下左右拖动位置，横条上下留白对称）
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onPanStart: (_) {
              if (!_isDragging) setState(() => _isDragging = true);
            },
            onPanEnd: (_) {
              if (_isDragging) setState(() => _isDragging = false);
            },
            onPanCancel: () {
              if (_isDragging) setState(() => _isDragging = false);
            },
            onPanUpdate: (details) {
              setState(() {
                final curW = _effectiveWidth(screenSize);
                final curH = _effectiveHeight(screenSize);
                final newX = (_panelPosition.dx + details.delta.dx).clamp(
                  6.0,
                  (screenSize.width - curW - 6.0).clamp(6.0, double.infinity),
                );
                final newY = (_panelPosition.dy + details.delta.dy).clamp(
                  32.0,
                  (screenSize.height - curH - 16.0).clamp(32.0, double.infinity),
                );
                _panelPosition = Offset(newX, newY);
                _ballPosition = Offset(
                  newX.clamp(6.0, screenSize.width - _ballSize - 6.0),
                  newY.clamp(36.0, screenSize.height - 100.0),
                );
              });
            },
            child: Column(
              children: [
                // 顶部横条（距离顶缘与底缘留白对称，支持点击呼出上方气泡菜单）
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => _showHandleMenu(screenSize),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(0, 10, 0, 8),
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 10, 8),
                  child: Row(
                    children: [
                      InkWell(
                        borderRadius: BorderRadius.circular(6),
                        onTap: () {
                          if (!isConnected) {
                            _openConnectSheet();
                          }
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              isConnected
                                  ? Icons.bluetooth_connected
                                  : Icons.bluetooth,
                              size: 16,
                              color: isConnected ? Colors.teal : Colors.grey,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isConnected
                                  ? (ble.connectedName ?? '已连键盘')
                                  : '点击连接键盘',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: isConnected
                                    ? Colors.teal.shade800
                                    : Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // 窗口三按钮（顺序：最小化、最大化、关闭，使最边缘角上的关闭最好点击）
                      _buildWindowButton(
                        icon: Icons.remove_rounded,
                        tooltip: '最小化',
                        onTap: _collapsePanel,
                        color: Colors.grey.shade700,
                      ),
                      const SizedBox(width: 4),
                      _buildWindowButton(
                        icon: _isMaximized
                            ? Icons.fullscreen_exit_rounded
                            : Icons.crop_square_rounded,
                        tooltip: _isMaximized ? '还原' : '最大化',
                        onTap: () => _toggleMaximize(screenSize),
                        color: Colors.grey.shade700,
                      ),
                      const SizedBox(width: 4),
                      _buildWindowButton(
                        icon: Icons.close_rounded,
                        tooltip: ctrl.isTyping ? '正在输入，暂不可关闭' : '关闭',
                        onTap: ctrl.isTyping ? null : _closeOverlayPermanently,
                        color: Colors.red.shade700,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // 悬浮窗内部内嵌确认关闭对话框（柔和灰底警告，无刺眼大红和感叹号）
          if (_isConfirmingClose) ...[
            Container(
              padding: const EdgeInsets.all(12),
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    '确认关闭悬浮窗？',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '关闭后悬浮窗将退出。可在「蓝牙与键盘」设置中重新开启。',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 6),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => setState(
                        () => _confirmCloseDontAsk = !_confirmCloseDontAsk),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Checkbox(
                          value: _confirmCloseDontAsk,
                          visualDensity: VisualDensity.compact,
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          onChanged: (v) => setState(
                              () => _confirmCloseDontAsk = v ?? false),
                        ),
                        const SizedBox(width: 4),
                        const Text('下次不再提示', style: TextStyle(fontSize: 11.5)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                        onPressed: () =>
                            setState(() => _isConfirmingClose = false),
                        child: const Text('取消', style: TextStyle(fontSize: 12)),
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red.shade700,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () async {
                          if (_confirmCloseDontAsk) {
                            final settingsRepo =
                                ref.read(settingsRepositoryProvider);
                            await settingsRepo.set(
                                'floating_close_dont_ask', 'true');
                          }
                          await _performCloseOverlay();
                        },
                        child: const Text(
                          '确认关闭',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
          ],

          // 2. 上半部：打字实时仪表盘（空闲时折叠显示简明状态，打字时展开）
          _buildUpperDashboard(ctrl, colorScheme),

          const Divider(height: 1),

          // 3. 中部：输入速度方形阵列快切栏（按速度从低到高排列）
          _buildSpeedSquaresBar(activeTiming, presets, colorScheme),

          const Divider(height: 1),

          // 4. 下半部：功能切换 Tab 与具体工作区 (最大化时可占据剩余高度自适应)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<int>(
                    style: SegmentedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    segments: const [
                      ButtonSegment(
                        value: 0,
                        label: Text('发送文字', style: TextStyle(fontSize: 12)),
                        icon: Icon(Icons.send_rounded, size: 14),
                      ),
                      ButtonSegment(
                        value: 1,
                        label: Text('快捷动作', style: TextStyle(fontSize: 12)),
                        icon: Icon(Icons.auto_fix_high, size: 14),
                      ),
                    ],
                    selected: {_currentTab},
                    onSelectionChanged: (set) {
                      setState(() => _currentTab = set.first);
                    },
                  ),
                ),
              ],
            ),
          ),

          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: _currentTab == 0
                  ? _buildQuickTextTab(colorScheme)
                  : _buildPresetActionsTab(colorScheme),
            ),
          ),
        ],
      ),
    );
  }

  /// 上半部仪表盘：无打字时简单显示，打字时平滑展开详细指标与急停
  Widget _buildUpperDashboard(TypingProgressController ctrl, ColorScheme colorScheme) {
    if (!ctrl.isTyping) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
        child: Row(
          children: [
            Icon(Icons.keyboard_outlined, size: 15, color: colorScheme.primary),
            const SizedBox(width: 6),
            const Text(
              '当前没有输入正在进行',
              style: TextStyle(fontSize: 11.5, color: Colors.blueGrey),
            ),
          ],
        ),
      );
    }

    final elapsed = (ctrl.elapsedMs / 1000).toStringAsFixed(1);
    final remainingMs = math.max(0, ctrl.estimatedDurationMs - ctrl.elapsedMs);
    final est = (remainingMs / 1000).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.all(10),
      color: colorScheme.primary.withValues(alpha: 0.06),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  ctrl.title.isNotEmpty ? ctrl.title : '输入进行中',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${ctrl.totalChars}字 · 已用${elapsed}s · 剩余~${est}s',
                style: TextStyle(
                  fontSize: 10.5,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(vertical: 5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
            icon: const Icon(Icons.stop_circle_outlined, size: 15),
            label: const Text(
              '紧急停止',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
            onPressed: () async {
              await ctrl.emergencyStop();
              if (mounted) {
                showAppToast(context, '已发送急停指令，打字已中断');
              }
            },
          ),
        ],
      ),
    );
  }

  /// 中部：输入速度折叠条（默认仅显示当前速度 + 方案名 + 展开图标；展开后展示自适应方块）
  Widget _buildSpeedSquaresBar(
    ActiveTimingState activeTiming,
    List<TimingPreset> presets,
    ColorScheme colorScheme,
  ) {
    final sorted = List<TimingPreset>.from(presets)
      ..sort((a, b) => a.estimatedCharsPerSec.compareTo(b.estimatedCharsPerSec));

    final selectedSchemeName = activeTiming.matchedPreset?.name ??
        '实时参数 (${activeTiming.estimatedCharsPerSec.toStringAsFixed(0)} 字/秒)';

    return Container(
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _isSpeedSquaresExpanded = !_isSpeedSquaresExpanded;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.speed, size: 15, color: Colors.blueGrey),
                  const SizedBox(width: 5),
                  const Text(
                    '输入速度：',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.blueGrey,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      selectedSchemeName,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _isSpeedSquaresExpanded
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    size: 18,
                    color: Colors.blueGrey,
                  ),
                ],
              ),
            ),
          ),
          if (_isSpeedSquaresExpanded) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final count = sorted.length;
                  if (count == 0) return const SizedBox.shrink();

                  const spacing = 8.0;

                  return Row(
                    children: List.generate(count, (index) {
                      final p = sorted[index];
                      final isSelected = activeTiming.matchedPreset?.id == p.id;
                      final speedVal = p.estimatedCharsPerSec.toStringAsFixed(0);

                      return Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(
                            left: index == 0 ? 0 : spacing / 2,
                            right: index == count - 1 ? 0 : spacing / 2,
                          ),
                          child: AspectRatio(
                            aspectRatio: 1.0,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(8),
                              onTap: () async {
                                final toastCtx = context;
                                await ref
                                    .read(activeTimingControllerProvider.notifier)
                                    .applyPreset(p);
                                if (mounted) {
                                  showAppToast(toastCtx, '已切换速度：${p.name}');
                                }
                              },
                              child: Container(
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? colorScheme.primary
                                      : colorScheme.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.outlineVariant,
                                    width: isSelected ? 1.5 : 1.0,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      speedVal,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        height: 1.1,
                                        color: isSelected
                                            ? colorScheme.onPrimary
                                            : colorScheme.onSurface,
                                      ),
                                    ),
                                    Text(
                                      '字/s',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        height: 1.1,
                                        color: isSelected
                                            ? colorScheme.onPrimary.withValues(alpha: 0.85)
                                            : colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Tab 1：快速文字贴入
  Widget _buildQuickTextTab(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: TextField(
            controller: _quickTextCtrl,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            enableInteractiveSelection: true,
            style: const TextStyle(fontSize: 13, height: 1.35),
            decoration: InputDecoration(
              hintText: '输入需要贴入的文字...',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.all(10),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FilledButton.icon(
          style: FilledButton.styleFrom(
            visualDensity: VisualDensity.compact,
            padding: const EdgeInsets.symmetric(vertical: 9),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
          icon: const Icon(Icons.send_rounded, size: 15),
          label: const Text(
            '发送文字',
            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          ),
          onPressed: _sendQuickText,
        ),
      ],
    );
  }

  /// Tab 2：快捷动作（按键精灵）
  Widget _buildPresetActionsTab(ColorScheme colorScheme) {
    final presets = ref.watch(typingBlockPresetsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: presets.isEmpty
              ? const Center(
                  child: Text(
                    '暂无快捷动作，可前往设置添加',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: presets.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 4),
                  itemBuilder: (ctx, i) {
                    final item = presets[i];
                    return InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _triggerPresetBlock(item),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.play_circle_fill,
                                size: 16, color: Colors.deepOrange),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    item.stepsPreview,
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontFamily: 'monospace',
                                      color: Colors.grey,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right,
                                size: 14, color: Colors.grey),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
        const SizedBox(height: 6),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 6),
            ),
            icon: const Icon(Icons.tune, size: 14),
            label: const Text('管理快捷动作', style: TextStyle(fontSize: 11)),
            onPressed: _openPresetsSheet,
          ),
        ),
      ],
    );
  }
}
