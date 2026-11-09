import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

/// 录音交互阶段
enum RecordingPhase {
  /// 按住说话阶段（手指尚未松开）
  holding,

  /// 锁定的录音工作台界面（松手进入录音模式）
  lockedRecording,

  /// 录音已停止，可试听回放/取消/发送
  stoppedReview,
}

/// 按住说话时手指滑向的区域
enum TouchTarget {
  /// 正常按住说话
  normal,

  /// 滑向取消发送
  cancel,

  /// 滑向保持录音（锁定录音模式）
  lockRecord,
}

class RecordingOverlay extends StatefulWidget {
  final RecordingPhase phase;
  final TouchTarget currentTouchTarget;
  final Stream<Amplitude> amplitudeStream;
  final int durationMs;
  final String? audioPath;
  final VoidCallback onStopRecording;
  final VoidCallback onSend;
  final VoidCallback onCancel;
  final VoidCallback? onDirectTapCancel;
  final VoidCallback? onDirectTapLock;

  const RecordingOverlay({
    super.key,
    required this.phase,
    this.currentTouchTarget = TouchTarget.normal,
    required this.amplitudeStream,
    this.durationMs = 0,
    this.audioPath,
    required this.onStopRecording,
    required this.onSend,
    required this.onCancel,
    this.onDirectTapCancel,
    this.onDirectTapLock,
  });

  @override
  State<RecordingOverlay> createState() => _RecordingOverlayState();
}

class _RecordingOverlayState extends State<RecordingOverlay>
    with TickerProviderStateMixin {
  double _amplitude = 0;
  StreamSubscription<Amplitude>? _ampSub;
  late AnimationController _waveCtrl;
  late AnimationController _baseEntranceCtrl;
  late Animation<double> _baseSlideAnim;

  // 播放器状态（供试听回放使用）
  final AudioPlayer _audioPlayer = AudioPlayer();
  bool _isPlaying = false;
  Duration _playPos = Duration.zero;
  Duration _playTotal = Duration.zero;
  StreamSubscription<void>? _playCompleteSub;
  StreamSubscription<Duration>? _playPosSub;

  @override
  void initState() {
    super.initState();
    _waveCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    // 微信/QQ 风格：底部向上大幅度弹跳上浮入场动画 (260ms)，去除渐入，直接物理位移
    _baseEntranceCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    );
    _baseSlideAnim = Tween<double>(begin: 90.0, end: 0.0).animate(
      CurvedAnimation(parent: _baseEntranceCtrl, curve: Curves.easeOutBack),
    );
    _baseEntranceCtrl.forward();

    _ampSub = widget.amplitudeStream.listen((amp) {
      if (mounted) {
        setState(() {
          _amplitude = ((amp.current + 55).clamp(0, 55) / 55).clamp(0.08, 1.0);
        });
      }
    });

    _playCompleteSub = _audioPlayer.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _playPos = Duration.zero;
        });
      }
    });

    _playPosSub = _audioPlayer.onPositionChanged.listen((pos) {
      if (mounted) {
        setState(() => _playPos = pos);
      }
    });
  }

  @override
  void dispose() {
    _ampSub?.cancel();
    _playCompleteSub?.cancel();
    _playPosSub?.cancel();
    _audioPlayer.dispose();
    _waveCtrl.dispose();
    _baseEntranceCtrl.dispose();
    super.dispose();
  }

  Future<void> _togglePlayPreview() async {
    if (widget.audioPath == null) return;
    if (_isPlaying) {
      await _audioPlayer.pause();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      await _audioPlayer.play(DeviceFileSource(widget.audioPath!));
      final duration = await _audioPlayer.getDuration();
      if (mounted) {
        setState(() {
          _isPlaying = true;
          if (duration != null) _playTotal = duration;
        });
      }
    }
  }

  String _formatDuration(int ms) {
    final totalSec = ms ~/ 1000;
    final min = (totalSec ~/ 60).toString().padLeft(2, '0');
    final sec = (totalSec % 60).toString().padLeft(2, '0');
    return '$min:$sec';
  }

  @override
  Widget build(BuildContext context) {
    final isCancel = widget.currentTouchTarget == TouchTarget.cancel;
    final isHolding = widget.phase == RecordingPhase.holding;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // 统一色调背景：灰度半透明磨砂质感遮罩，取消时也不变全屏红，仅局部按钮和微弱暗红点缀
          Positioned.fill(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              color: isCancel
                  ? const Color(0xC5261C1C) // 极弱微暖深灰，不刺眼不吓人
                  : const Color(0xB81A1C1E),
            ),
          ),

          // 核心动效交互区
          if (isHolding)
            _buildHoldingOverlayContent(isCancel)
          else
            _buildUnifiedWorkbenchContent(),

          // 底部贴合的满屏宽向上微拱弧形底座（按住说话时的专属视觉锚点，带微信式从下往上升起的平滑入场动效）
          if (isHolding)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: AnimatedBuilder(
                animation: _baseEntranceCtrl,
                builder: (_, child) => Transform.translate(
                  offset: Offset(0, _baseSlideAnim.value),
                  child: child,
                ),
                child: _buildHoldingCurvedBase(isCancel),
              ),
            ),
        ],
      ),
    );
  }

  /// 场景 1：按住说话悬浮半透明蒙层
  Widget _buildHoldingOverlayContent(bool isCancel) {
    final isLock = widget.currentTouchTarget == TouchTarget.lockRecord;

    return Stack(
      children: [
        // 居中麦克风波形与计时
        Align(
          alignment: const Alignment(0, -0.18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _waveCtrl,
                builder: (_, child) {
                  final scale = 1.0 + _amplitude * 0.25;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 90,
                      height: 90,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCancel
                            ? Colors.redAccent.withValues(alpha: 0.3)
                            : Colors.teal.withValues(alpha: 0.3),
                        boxShadow: [
                          BoxShadow(
                            color: isCancel
                                ? Colors.redAccent.withValues(alpha: 0.35)
                                : Colors.tealAccent.withValues(alpha: 0.25),
                            blurRadius: 20,
                            spreadRadius: 4 * _amplitude,
                          ),
                        ],
                      ),
                      child: Icon(
                        isCancel ? Icons.delete_outline : Icons.mic_rounded,
                        color: Colors.white,
                        size: 42,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),
              _buildDynamicWaveform(isCancel),
              const SizedBox(height: 14),
              Text(
                _formatDuration(widget.durationMs),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Text(
                  isCancel
                      ? '松开手指，取消发送'
                      : (isLock ? '松开手指，进入录音界面' : '松开发送，滑动可取消或锁定'),
                  style: TextStyle(
                    color: isCancel ? Colors.yellowAccent : Colors.white,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),

        // 底部滑动触碰目标按钮（收拢距离，简洁文案，离大弧底座更近）
        Positioned(
          left: 0,
          right: 0,
          bottom: 125,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildTouchTargetChip(
                label: '取消',
                icon: Icons.close_rounded,
                isTargeted: isCancel,
                activeBgColor: Colors.redAccent,
                onTap: widget.onDirectTapCancel,
              ),
              const SizedBox(width: 140), // 紧凑舒适间距，告别过远割裂感
              _buildTouchTargetChip(
                label: '录音',
                icon: Icons.fiber_manual_record_rounded,
                isTargeted: isLock,
                activeBgColor: Colors.teal,
                onTap: widget.onDirectTapLock,
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 场景 2：独立录音工作台与试听回放界面（色调完全与蒙层一致）
  Widget _buildUnifiedWorkbenchContent() {
    final isRecording = widget.phase == RecordingPhase.lockedRecording;

    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 24),
        padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
        decoration: BoxDecoration(
          color: const Color(0xEB26292E), // 保持统一的灰暗半透明深灰基调
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.15),
            width: 1.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.4),
              blurRadius: 30,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor:
                      isRecording ? Colors.redAccent : Colors.teal,
                  radius: 13,
                  child: Icon(
                    isRecording ? Icons.mic : Icons.audiotrack_rounded,
                    size: 15,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  isRecording ? '录音中' : '录音完成',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const Spacer(),
                Text(
                  _formatDuration(widget.durationMs),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isRecording ? Colors.redAccent : Colors.tealAccent,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (isRecording) ...[
              _buildDynamicWaveform(false),
              const SizedBox(height: 24),
              GestureDetector(
                onTap: () {
                  HapticFeedback.mediumImpact();
                  widget.onStopRecording();
                },
                child: Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.redAccent,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.redAccent.withValues(alpha: 0.4),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Center(
                    child: Icon(Icons.stop_rounded,
                        color: Colors.white, size: 34),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              const Text('点击停止',
                  style: TextStyle(fontSize: 11, color: Colors.white54)),
            ] else ...[
              // 试听回放控制条（统一深灰半透明胶囊）
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: Row(
                  children: [
                    IconButton.filled(
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.teal,
                      ),
                      onPressed: _togglePlayPreview,
                      icon: Icon(
                        _isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isPlaying ? '正在试听回放' : '试听录音',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(
                            value: _playTotal.inMilliseconds > 0
                                ? (_playPos.inMilliseconds /
                                        _playTotal.inMilliseconds)
                                    .clamp(0.0, 1.0)
                                : 0.0,
                            minHeight: 4,
                            backgroundColor: Colors.white12,
                            valueColor: const AlwaysStoppedAnimation(Colors.tealAccent),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 22),

              // 底部操作按钮行：取消 / 确认发送
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: BorderSide(
                            color: Colors.white.withValues(alpha: 0.25)),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.delete_outline, size: 17),
                      label: const Text('取消'),
                      onPressed: () {
                        _audioPlayer.stop();
                        widget.onCancel();
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.teal,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.send_rounded, size: 17),
                      label: const Text('发送'),
                      onPressed: () {
                        _audioPlayer.stop();
                        widget.onSend();
                      },
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 满屏宽向上微凸的弧形大底座（按住说话时的大块实体感）
  Widget _buildHoldingCurvedBase(bool isCancel) {
    return CustomPaint(
      size: const Size(double.infinity, 130),
      painter: _CurvedBasePainter(
        color: isCancel
            ? Colors.redAccent.withValues(alpha: 0.35)
            : Colors.white.withValues(alpha: 0.18),
        borderColor: isCancel
            ? Colors.redAccent.withValues(alpha: 0.5)
            : Colors.white.withValues(alpha: 0.3),
      ),
      child: const SizedBox(
        height: 130,
        child: Align(
          alignment: Alignment(0, 0.25),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.arrow_upward_rounded, size: 15, color: Colors.white60),
              SizedBox(width: 6),
              Text(
                '滑至按钮触发',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                ),
              ),
              SizedBox(width: 6),
              Icon(Icons.arrow_upward_rounded, size: 15, color: Colors.white60),
            ],
          ),
        ),
      ),
    );
  }

  /// 动态波形条组
  Widget _buildDynamicWaveform(bool isDanger) {
    return SizedBox(
      height: 32,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(14, (i) {
          final factor = ((i % 4 + 1) * 0.22 * _amplitude).clamp(0.12, 1.0);
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 2.2),
            width: 3.2,
            height: 32 * factor,
            decoration: BoxDecoration(
              color: isDanger ? Colors.redAccent : Colors.tealAccent,
              borderRadius: BorderRadius.circular(2),
            ),
          );
        }),
      ),
    );
  }

  /// 滑动触碰按钮胶囊（支持多点触控直接点击）
  Widget _buildTouchTargetChip({
    required String label,
    required IconData icon,
    required bool isTargeted,
    required Color activeBgColor,
    VoidCallback? onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) {
        HapticFeedback.mediumImpact();
        onTap?.call();
      },
      child: AnimatedScale(
        duration: const Duration(milliseconds: 160),
        scale: isTargeted ? 1.15 : 1.0,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isTargeted
                    ? activeBgColor
                    : Colors.white.withValues(alpha: 0.16),
                border: Border.all(
                  color: isTargeted
                      ? Colors.white
                      : Colors.white.withValues(alpha: 0.35),
                  width: isTargeted ? 2.5 : 1.5,
                ),
                boxShadow: isTargeted
                    ? [
                        BoxShadow(
                          color: activeBgColor.withValues(alpha: 0.55),
                          blurRadius: 18,
                          spreadRadius: 3,
                        ),
                      ]
                    : null,
              ),
              child: Icon(
                icon,
                color: Colors.white,
                size: 28,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: isTargeted ? Colors.white : Colors.white70,
                fontSize: 11.5,
                fontWeight: isTargeted ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 向上微拱的满屏宽弧形 Painter
class _CurvedBasePainter extends CustomPainter {
  final Color color;
  final Color borderColor;

  _CurvedBasePainter({required this.color, required this.borderColor});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();
    // 从左下角起步，向顶部中点大幅微凸拱起，形成更靠近按钮的大块底座
    path.moveTo(0, size.height);
    path.lineTo(0, 48);
    path.quadraticBezierTo(size.width / 2, 0, size.width, 48);
    path.lineTo(size.width, size.height);
    path.close();

    final fillPaint = Paint()..color = color;
    canvas.drawPath(path, fillPaint);

    final borderPath = Path();
    borderPath.moveTo(0, 48);
    borderPath.quadraticBezierTo(size.width / 2, 0, size.width, 48);

    final borderPaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawPath(borderPath, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _CurvedBasePainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.borderColor != borderColor;
  }
}
