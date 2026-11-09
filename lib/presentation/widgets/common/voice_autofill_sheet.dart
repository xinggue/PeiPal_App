import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';

import '../../../data/services/media/wav_encoder.dart';
import 'app_toast.dart';

/// 专用于智能填单的语音录制弹窗
class VoiceAutofillSheet extends StatefulWidget {
  const VoiceAutofillSheet({super.key});

  static Future<String?> show(BuildContext context) {
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => const VoiceAutofillSheet(),
    );
  }

  @override
  State<VoiceAutofillSheet> createState() => _VoiceAutofillSheetState();
}

class _VoiceAutofillSheetState extends State<VoiceAutofillSheet>
    with SingleTickerProviderStateMixin {
  final _recorder = AudioRecorder();
  late final AnimationController _pulseController;
  Timer? _timer;

  bool _isRecording = false;
  int _seconds = 0;
  String? _recordingPcmPath;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _startRecording() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      if (mounted) showAppToast(context, '请允许麦克风权限以录制语音');
      return;
    }

    HapticFeedback.mediumImpact();

    final tempDir = Directory.systemTemp;
    _recordingPcmPath =
        '${tempDir.path}/autofill_${DateTime.now().millisecondsSinceEpoch}.pcm';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _recordingPcmPath!,
    );

    _seconds = 0;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _seconds++);
      }
    });

    setState(() => _isRecording = true);
  }

  Future<void> _stopAndConfirm() async {
    HapticFeedback.mediumImpact();
    _timer?.cancel();

    final pcmPath = await _recorder.stop();
    setState(() => _isRecording = false);

    if (pcmPath == null || _seconds < 1) {
      if (pcmPath != null) {
        try {
          await File(pcmPath).delete();
        } catch (_) {}
      }
      if (mounted) {
        showAppToast(context, '说话时间太短，请重试');
        Navigator.pop(context, null);
      }
      return;
    }

    try {
      final wavPath = await WavEncoder.convertToWav(pcmPath);
      if (mounted) {
        Navigator.pop(context, wavPath);
      }
    } catch (e) {
      if (mounted) {
        showAppToast(context, '语音编码失败: $e');
        Navigator.pop(context, null);
      }
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    if (_isRecording) {
      try {
        final p = await _recorder.stop();
        if (p != null) {
          await File(p).delete();
        }
      } catch (_) {}
    }
    if (mounted) {
      Navigator.pop(context, null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mins = (_seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (_seconds % 60).toString().padLeft(2, '0');

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(Icons.mic_none_rounded, color: colorScheme.primary, size: 22),
                const SizedBox(width: 8),
                const Text(
                  '语音智能填单',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 20),
                  onPressed: _cancel,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              _isRecording
                  ? '正在倾听，请清晰说出会话名称、性别、年龄、编号及备注…'
                  : '点击下方麦克风开始说话，录毕点击停止即可自动填单',
              style: TextStyle(fontSize: 12.5, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // 计时器或提示
            Text(
              _isRecording ? '$mins:$secs' : '准备就绪',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: _isRecording ? Colors.red.shade700 : colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 20),

            // 麦克风主按钮
            AnimatedBuilder(
              animation: _pulseController,
              builder: (context, child) {
                final scale = _isRecording ? 1.0 + (_pulseController.value * 0.12) : 1.0;
                return Transform.scale(
                  scale: scale,
                  child: GestureDetector(
                    onTap: _isRecording ? _stopAndConfirm : _startRecording,
                    child: Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(
                        color: _isRecording ? Colors.red.shade600 : colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? Colors.red : colorScheme.primary)
                                .withValues(alpha: 0.35),
                            blurRadius: 18,
                            spreadRadius: _isRecording ? 4 : 0,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop_rounded : Icons.mic_rounded,
                        color: Colors.white,
                        size: 38,
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            Text(
              _isRecording ? '点击红色按钮完成录音并识别' : '点击开始录音',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: _isRecording ? Colors.red.shade700 : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
