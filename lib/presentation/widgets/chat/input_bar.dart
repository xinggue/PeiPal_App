import 'dart:async';
import 'dart:io';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:record/record.dart';

import '../../../data/services/media/app_image_picker.dart';
import '../../../data/services/media/wav_encoder.dart';
import 'document_collate_sheet.dart';
import 'recording_overlay.dart';
import '../common/app_toast.dart';

class ChatInputBar extends StatefulWidget {
  final void Function(String text) onSendText;
  final void Function({required List<String> filePaths, required List<int> fileSizes}) onSendPhotos;
  final void Function(List<List<String>> documentPhotoBatches)? onSendDocuments;
  final void Function({required String filePath, required int fileSize, required int durationMs}) onSendVoice;
  final void Function(String filePath) onSendFile;
  final void Function(Stream<Amplitude> amplitudeStream) onRecordingHoldingStarted;
  final void Function(TouchTarget target) onTouchTargetChanged;
  final void Function(bool lockToWorkbench, bool cancel) onHoldingFinished;
  final VoidCallback onGenerateRecord;
  final VoidCallback? onManualGenerateRecord;
  final VoidCallback? onAutofillSessionInfo;
  final bool isDryRunEnabled;
  final VoidCallback? onDryRunTest;

  const ChatInputBar({
    super.key,
    required this.onSendText,
    required this.onSendPhotos,
    this.onSendDocuments,
    required this.onSendVoice,
    required this.onSendFile,
    required this.onRecordingHoldingStarted,
    required this.onTouchTargetChanged,
    required this.onHoldingFinished,
    required this.onGenerateRecord,
    this.onManualGenerateRecord,
    this.onAutofillSessionInfo,
    this.isDryRunEnabled = false,
    this.onDryRunTest,
  });

  @override
  State<ChatInputBar> createState() => ChatInputBarState();
}

class ChatInputBarState extends State<ChatInputBar> {
  final _textController = TextEditingController();
  final _recorder = AudioRecorder();
  late final FocusNode _focusNode;

  // 微信式：语音/文字输入模式切换
  bool _isVoiceMode = false;
  bool _isRecording = false;
  int _recordStartMs = 0;
  String? _recordingPcmPath;
  String? _cachedWavPath;
  int? _recordingDurationMs;

  TouchTarget _currentTouchTarget = TouchTarget.normal;
  Offset? _pressStartGlobalPos;
  int? _activePointerId;
  bool _hasMicPermission = false;

  // 微信式底部多功能扩展抽屉
  bool _showAttachmentPanel = false;
  int _attachmentPageIndex = 0;

  bool get _hasText => _textController.text.trim().isNotEmpty;
  bool get isRecording => _isRecording;
  int get currentDurationMs => _recordStartMs > 0
      ? DateTime.now().millisecondsSinceEpoch - _recordStartMs
      : 0;
  String? get currentWavPath => _cachedWavPath;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _showAttachmentPanel) {
        setState(() => _showAttachmentPanel = false);
      }
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _textController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _sendText() {
    final text = _textController.text.trim();
    if (text.isEmpty) return;
    widget.onSendText(text);
    _textController.clear();
    setState(() {});
  }

  Future<void> _captureWithCamera() async {
    final pages = <String>[];
    bool done = false;

    while (!done) {
      final path = await AppImagePicker.pickSingleImage(source: ImageSource.camera);
      if (path == null) break;
      pages.add(path);

      if (!mounted) return;
      done = await showModalBottomSheet<bool>(
            context: context,
            builder: (ctx) => SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('当前材料：第 ${pages.length} 页已拍',
                        style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('继续拍下一页'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('已拍完当前材料'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ) ??
          true;
    }

    if (pages.isNotEmpty) {
      final sizes = pages.map((p) => File(p).lengthSync()).toList();
      widget.onSendPhotos(filePaths: pages, fileSizes: sizes);
    }
  }

  Future<void> _pickFromGallery() async {
    final paths = await AppImagePicker.pickMultiImages();
    if (paths.isEmpty) return;

    if (!mounted) return;

    if (paths.length == 1) {
      final fileSizes = [File(paths.first).lengthSync()];
      widget.onSendPhotos(filePaths: paths, fileSizes: fileSizes);
    } else {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation(Colors.white),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '正在导入 ${paths.length} 张文书照片...',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );

      await Future.delayed(const Duration(milliseconds: 60));
      if (!mounted) return;
      Navigator.pop(context);

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        isDismissible: false,
        enableDrag: false,
        backgroundColor: Colors.transparent,
        builder: (ctx) => DocumentCollateSheet(
          initialImagePaths: paths,
          onConfirm: (documents) {
            if (widget.onSendDocuments != null) {
              final batches = documents.map((doc) => doc.imagePaths).toList();
              widget.onSendDocuments!(batches);
            } else {
              for (final doc in documents) {
                final sizes = doc.imagePaths.map((p) => File(p).lengthSync()).toList();
                widget.onSendPhotos(filePaths: doc.imagePaths, fileSizes: sizes);
              }
            }
          },
        ),
      );
    }
  }

  /// 选择并发送文件 (PDF, Word, TXT等)
  Future<void> _pickDocumentFile() async {
    const typeGroup = XTypeGroup(
      label: '文档',
      extensions: <String>['pdf', 'docx', 'doc', 'txt', 'text', 'md', 'csv', 'json'],
    );
    final file = await openFile(acceptedTypeGroups: <XTypeGroup>[typeGroup]);
    if (file == null) return;
    widget.onSendFile(file.path);
  }

  // ==========================================
  // 微信式 0 延迟即时触控语音录入手势控制 (Listener / Pointer 事件流)
  // 彻底废除 GestureDetector 500ms 长按检测延迟，手指触碰瞬间立刻录音
  // ==========================================

  Future<void> _handlePointerDown(PointerDownEvent event) async {
    if (_isRecording) return;
    _activePointerId = event.pointer;
    _pressStartGlobalPos = event.position;
    _currentTouchTarget = TouchTarget.normal;
    _cachedWavPath = null;

    // 适中干脆的触感震动反馈
    HapticFeedback.mediumImpact();

    if (!_hasMicPermission) {
      _hasMicPermission = await _recorder.hasPermission();
      if (!_hasMicPermission) {
        if (mounted) showAppToast(context, '请允许麦克风权限以录制语音');
        _activePointerId = null;
        return;
      }
    }

    final tempDir = Directory.systemTemp;
    _recordingPcmPath =
        '${tempDir.path}/rec_${DateTime.now().millisecondsSinceEpoch}.pcm';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ),
      path: _recordingPcmPath!,
    );

    _recordStartMs = DateTime.now().millisecondsSinceEpoch;
    if (mounted) {
      setState(() => _isRecording = true);
    }

    final stream =
        _recorder.onAmplitudeChanged(const Duration(milliseconds: 100));
    widget.onRecordingHoldingStarted(stream);
  }

  void _handlePointerMove(PointerMoveEvent event) {
    if (!_isRecording ||
        _pressStartGlobalPos == null ||
        _activePointerId != event.pointer) {
      return;
    }

    final dy = event.position.dy - _pressStartGlobalPos!.dy;
    final dx = event.position.dx - _pressStartGlobalPos!.dx;

    TouchTarget nextTarget = TouchTarget.normal;
    // 只有当手指向上滑动到按钮高度区间（dy 向上超过 50px，且在 220px 范围内），且横向滑入左侧或右侧敏感区时才判定触发
    if (dy < -50 && dy > -220) {
      if (dx < -35) {
        // 滑向左侧取消按钮
        nextTarget = TouchTarget.cancel;
      } else if (dx > 35) {
        // 滑向右侧锁定录音按钮
        nextTarget = TouchTarget.lockRecord;
      }
    }

    if (nextTarget != _currentTouchTarget) {
      _currentTouchTarget = nextTarget;
      HapticFeedback.selectionClick();
      widget.onTouchTargetChanged(nextTarget);
    }
  }

  Future<void> _handlePointerUp(PointerUpEvent event) async {
    if (_activePointerId != event.pointer) return;
    _activePointerId = null;

    if (!_isRecording) return;

    final target = _currentTouchTarget;
    _currentTouchTarget = TouchTarget.normal;
    _pressStartGlobalPos = null;

    if (target == TouchTarget.cancel) {
      await cancelRecording();
      widget.onHoldingFinished(false, true);
    } else if (target == TouchTarget.lockRecord) {
      widget.onHoldingFinished(true, false);
    } else {
      await _finishAndSendDirectly();
      widget.onHoldingFinished(false, false);
    }
  }

  Future<void> _handlePointerCancel(PointerCancelEvent event) async {
    if (_activePointerId != event.pointer) return;
    _activePointerId = null;
    if (!_isRecording) return;
    await cancelRecording();
    widget.onHoldingFinished(false, true);
  }

  /// 停止录音并将 PCM 转换为 WAV 供回放或发送
  Future<String?> stopAndPrepareWav() async {
    if (!_isRecording) return _cachedWavPath;

    final pcmPath = await _recorder.stop();
    _recordingDurationMs =
        DateTime.now().millisecondsSinceEpoch - _recordStartMs;
    setState(() => _isRecording = false);

    if (pcmPath == null || _recordingDurationMs! < 500) {
      if (pcmPath != null) {
        try {
          await File(pcmPath).delete();
        } catch (_) {}
      }
      return null;
    }

    try {
      final wavPath = await WavEncoder.convertToWav(pcmPath);
      _cachedWavPath = wavPath;
      return wavPath;
    } catch (e) {
      return null;
    }
  }

  /// 确认发送当前录制的语音（供工作台“确认发送”调用）
  Future<void> confirmSendCachedVoice() async {
    final wavPath = _cachedWavPath ?? await stopAndPrepareWav();
    if (wavPath == null) {
      if (mounted) showAppToast(context, '说话时间太短');
      return;
    }

    final wavFile = File(wavPath);
    if (!await wavFile.exists()) return;
    final fileSize = await wavFile.length();
    final duration = _recordingDurationMs ?? 1000;

    widget.onSendVoice(
      filePath: wavPath,
      fileSize: fileSize,
      durationMs: duration,
    );

    _cachedWavPath = null;
    _recordingPcmPath = null;
    _recordingDurationMs = null;
  }

  /// 正常长按松手后直接转换并发送
  Future<void> _finishAndSendDirectly() async {
    final wavPath = await stopAndPrepareWav();
    if (wavPath == null) {
      if (mounted) showAppToast(context, '说话时间太短');
      return;
    }
    final wavFile = File(wavPath);
    if (!await wavFile.exists()) return;
    final fileSize = await wavFile.length();

    widget.onSendVoice(
      filePath: wavPath,
      fileSize: fileSize,
      durationMs: _recordingDurationMs ?? 1000,
    );

    _cachedWavPath = null;
    _recordingPcmPath = null;
    _recordingDurationMs = null;
  }

  Future<void> cancelRecording() async {
    if (_isRecording) {
      await _recorder.stop();
      setState(() => _isRecording = false);
    }
    if (_recordingPcmPath != null) {
      try {
        await File(_recordingPcmPath!).delete();
      } catch (_) {}
    }
    if (_cachedWavPath != null) {
      try {
        await File(_cachedWavPath!).delete();
      } catch (_) {}
    }
    _recordingPcmPath = null;
    _cachedWavPath = null;
    _recordingDurationMs = null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: SafeArea(
            top: false,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                // 1. 最左侧：微信式语音/键盘切换图标
                IconButton(
                  icon: Icon(
                    _isVoiceMode ? Icons.keyboard_alt_outlined : Icons.mic_none,
                    size: 26,
                  ),
                  tooltip: _isVoiceMode ? '切换为键盘输入' : '切换为语音输入',
                  onPressed: () async {
                    final next = !_isVoiceMode;
                    setState(() {
                      _isVoiceMode = next;
                      if (next) {
                        _showAttachmentPanel = false;
                        FocusScope.of(context).unfocus();
                      }
                    });
                    if (next) {
                      _hasMicPermission = await _recorder.hasPermission();
                    }
                  },
                ),

                // 2. 中间：语音录入长按按钮 OR 文字输入框
                Expanded(
                  child: _isVoiceMode
                      ? _buildVoiceRecordButton()
                      : _buildTextField(),
                ),

                // 3. 生成文书专属星星按钮
                IconButton(
                  icon: const Icon(Icons.auto_awesome, color: Colors.amber, size: 23),
                  tooltip: '生成文书',
                  onPressed: widget.onGenerateRecord,
                ),

                // 4. 右侧：有文字时显示发送按钮，无文字时显示微信式圆圈加号 (+)
                if (_hasText)
                  FilledButton(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      minimumSize: const Size(40, 38),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(19)),
                    ),
                    onPressed: _sendText,
                    child: const Text('发送', style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                else
                  IconButton(
                    icon: Icon(
                      _showAttachmentPanel ? Icons.highlight_off_rounded : Icons.add_circle_outline,
                      size: 26,
                    ),
                    tooltip: '更多功能',
                    onPressed: () {
                      if (_showAttachmentPanel) {
                        setState(() => _showAttachmentPanel = false);
                        _focusNode.requestFocus();
                      } else {
                        if (_focusNode.hasFocus) {
                          _focusNode.unfocus();
                          Future.delayed(const Duration(milliseconds: 120), () {
                            if (mounted) setState(() => _showAttachmentPanel = true);
                          });
                        } else {
                          setState(() => _showAttachmentPanel = true);
                        }
                      }
                    },
                  ),
              ],
            ),
          ),
        ),

        // 5. 微信式底部多功能扩展面板
        if (_showAttachmentPanel) _buildAttachmentPanel(),
      ],
    );
  }

  Widget _buildTextField() {
    return Container(
      constraints: const BoxConstraints(maxHeight: 100),
      child: TextField(
        controller: _textController,
        focusNode: _focusNode,
        onTap: () {
          if (_showAttachmentPanel) {
            setState(() => _showAttachmentPanel = false);
          }
        },
        decoration: InputDecoration(
          hintText: '输入文字消息...',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(20),
            borderSide: BorderSide.none,
          ),
          filled: true,
          fillColor: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          isDense: true,
        ),
        textInputAction: TextInputAction.send,
        onSubmitted: (_) => _sendText(),
        onChanged: (_) => setState(() {}),
        maxLines: null,
        minLines: 1,
      ),
    );
  }

  Widget _buildVoiceRecordButton() {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerMove: _handlePointerMove,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: _isRecording
              ? Colors.teal.withValues(alpha: 0.18)
              : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _isRecording ? Colors.teal : Colors.transparent,
            width: 1.2,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          _isRecording ? '正在说话 (松开发送 / 滑动选择)' : '按住说话',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
            color: _isRecording ? Colors.teal.shade800 : Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }

  Widget _buildAttachmentPanel() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final items = <Widget>[
      _buildPanelItem(
        icon: Icons.camera_alt_rounded,
        label: '拍摄',
        color: Colors.blue.shade600,
        onTap: () {
          setState(() => _showAttachmentPanel = false);
          _captureWithCamera();
        },
      ),
      _buildPanelItem(
        icon: Icons.photo_library_rounded,
        label: '相册',
        color: Colors.green.shade600,
        onTap: () {
          setState(() => _showAttachmentPanel = false);
          _pickFromGallery();
        },
      ),
      _buildPanelItem(
        icon: Icons.insert_drive_file_rounded,
        label: '发送文件',
        color: Colors.orange.shade700,
        onTap: () {
          setState(() => _showAttachmentPanel = false);
          _pickDocumentFile();
        },
      ),
      _buildPanelItem(
        icon: Icons.auto_awesome_rounded,
        label: '生成文书',
        color: Colors.amber.shade800,
        onTap: () {
          setState(() => _showAttachmentPanel = false);
          widget.onGenerateRecord();
        },
      ),
      if (widget.onAutofillSessionInfo != null)
        _buildPanelItem(
          icon: Icons.badge_outlined,
          label: '补全信息',
          color: Colors.teal.shade600,
          onTap: () {
            setState(() => _showAttachmentPanel = false);
            widget.onAutofillSessionInfo!();
          },
        ),
      if (widget.onManualGenerateRecord != null)
        _buildPanelItem(
          icon: Icons.copy_all_rounded,
          label: '手动复制',
          color: Colors.deepPurple.shade600,
          onTap: () {
            setState(() => _showAttachmentPanel = false);
            widget.onManualGenerateRecord!();
          },
        ),
      _buildPanelItem(
        icon: Icons.draw_rounded,
        label: '手写画板',
        color: Colors.blueGrey,
        onTap: () {
          showAppToast(context, '手写画板功能正在规划中，敬请期待');
        },
      ),
      if (widget.isDryRunEnabled)
        _buildPanelItem(
          icon: Icons.bug_report_outlined,
          label: 'Prompt监视',
          color: Colors.brown,
          onTap: () {
            setState(() => _showAttachmentPanel = false);
            widget.onDryRunTest?.call();
          },
        ),
    ];

    const itemsPerPage = 8;
    final pageCount = (items.length / itemsPerPage).ceil();

    return Container(
      width: double.infinity,
      color: colorScheme.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            const itemWidth = 60.0;
            const columns = 4;
            final availableWidth = constraints.maxWidth;
            // 按钮之间和左右边缘之间严格 5 等分均分，间距完全相等
            final gap = (availableWidth - (columns * itemWidth)) / (columns + 1);

            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. 上间距严格等于左右间距 (gap)
                SizedBox(height: gap),

                // 2. 按钮主体（若 > 8 个自动分页，保持 4x2 微信结构）
                if (pageCount <= 1)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap),
                    child: Wrap(
                      spacing: gap,
                      runSpacing: 18,
                      children: items
                          .map((w) => SizedBox(width: itemWidth, child: w))
                          .toList(),
                    ),
                  )
                else
                  SizedBox(
                    height: 180,
                    child: PageView.builder(
                      itemCount: pageCount,
                      onPageChanged: (i) =>
                          setState(() => _attachmentPageIndex = i),
                      itemBuilder: (ctx, p) {
                        final start = p * itemsPerPage;
                        final end = (start + itemsPerPage < items.length)
                            ? start + itemsPerPage
                            : items.length;
                        final pageItems = items.sublist(start, end);

                        return Padding(
                          padding: EdgeInsets.symmetric(horizontal: gap),
                          child: Wrap(
                            spacing: gap,
                            runSpacing: 18,
                            children: pageItems
                                .map((w) =>
                                    SizedBox(width: itemWidth, child: w))
                                .toList(),
                          ),
                        );
                      },
                    ),
                  ),

                // 3. 按钮到底部圆点的间距严格等于上间距 (gap)
                SizedBox(height: gap),

                // 4. 底部指示器圆点 · (一页显示一个圆点，多页显示对应数量并高亮当前页)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(pageCount, (index) {
                    final isSelected = index == _attachmentPageIndex;
                    return Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.outlineVariant
                                .withValues(alpha: 0.65),
                      ),
                    );
                  }),
                ),

                // 5. 底部边距
                SizedBox(height: gap * 0.7),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildPanelItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.45),
                width: 0.8,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}
