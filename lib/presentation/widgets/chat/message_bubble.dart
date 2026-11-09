import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:go_router/go_router.dart';

import '../common/full_screen_image_viewer.dart';
import '../../../data/services/processing_service.dart';
import '../../../data/services/ble/character_sanitizer.dart';
import '../../../domain/models/message.dart';
import '../../pages/chat/typing_send_sheet.dart';
import 'ocr_text_details_dialog.dart';

final RegExp _separatorLineRegex = RegExp(r'^[\|\-:\s]+$');
final RegExp _htmlTagRegex = RegExp(r'<[^>]+>');

/// Strips markdown noise from display text: table pipes, separators, html tags.
String _cleanDisplayText(String text) {
  return text
      .split('\n')
      .map((line) {
        final trimmed = line.trim();
        // Skip pure separator lines like |---|---|
        if (_separatorLineRegex.hasMatch(trimmed)) return null;
        // Strip leading/trailing pipes but keep content
        var cleaned = trimmed;
        if (cleaned.startsWith('|')) cleaned = cleaned.substring(1);
        if (cleaned.endsWith('|')) cleaned = cleaned.substring(0, cleaned.length - 1);
        // Replace internal pipes with spaces
        cleaned = cleaned.replaceAll('|', ' ');
        // Strip basic HTML tags
        cleaned = cleaned.replaceAll(_htmlTagRegex, '');
        return cleaned;
      })
      .where((l) => l != null && l.trim().isNotEmpty)
      .join('\n');
}

class MessageBubble extends ConsumerWidget {
  final Message message;
  final Message? subMessage;
  final bool showProcessing;
  final WidgetRef ref;

  const MessageBubble({
    super.key,
    required this.message,
    this.subMessage,
    this.showProcessing = false,
    required this.ref,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUser = message.sender == MessageSender.user;
    final isRecord = message.type == MessageType.generatedRecord;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: isRecord
              ? MediaQuery.of(context).size.width * 0.85
              : MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    switch (message.type) {
      case MessageType.text:
        return Text(message.content ?? '');
      case MessageType.voice:
        return _VoiceBubble(
            message: message, subMessage: subMessage, showPending: showProcessing);
      case MessageType.photo:
        return _PhotoBubble(
            message: message, subMessage: subMessage, showPending: showProcessing);
      case MessageType.document:
        return _DocumentBubble(message: message);
      case MessageType.asrResult:
        return _SystemBubble(message: message);
      case MessageType.ocrResult:
        return _SystemBubble(message: message);
      case MessageType.generatedRecord:
        return _RecordBubble(message: message);
    }
  }
}

class _VoiceBubble extends StatefulWidget {
  final Message message;
  final Message? subMessage;
  final bool showPending;
  const _VoiceBubble(
      {required this.message, this.subMessage, this.showPending = false});

  @override
  State<_VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<_VoiceBubble> {
  final _player = AudioPlayer();
  StreamSubscription<void>? _completeSub;
  bool _isPlaying = false;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _completeSub = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _isPlaying = false);
    });
  }

  @override
  void dispose() {
    _completeSub?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final path = widget.message.filePaths.isNotEmpty
        ? widget.message.filePaths.first
        : null;
    if (path == null) return;

    if (_isPlaying) {
      await _player.pause();
      if (mounted) setState(() => _isPlaying = false);
    } else {
      await _player.play(DeviceFileSource(path));
      if (mounted) setState(() => _isPlaying = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final secs = (widget.message.durationMs ?? 0) ~/ 1000;
    final subText = _cleanDisplayText(widget.subMessage?.transcribedText ?? '');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: Icon(
                  _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
              onPressed: _toggle,
              iconSize: 28,
              visualDensity: VisualDensity.compact,
            ),
            const SizedBox(width: 4),
            Text('${secs}s', style: const TextStyle(fontSize: 14)),
          ],
        ),
        if (widget.showPending) ...[
          const SizedBox(height: 4),
          const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 14, height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 6),
              Text('识别中...',
                  style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ] else if (subText.isNotEmpty) ...[
          const SizedBox(height: 4),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: Colors.grey,
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    _expanded
                        ? subText
                        : '${subText.length > 40 ? subText.substring(0, 40) : subText}...',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                    maxLines: _expanded ? null : 1,
                    overflow: _expanded ? null : TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _PhotoBubble extends StatefulWidget {
  final Message message;
  final Message? subMessage;
  final bool showPending;
  const _PhotoBubble(
      {required this.message, this.subMessage, this.showPending = false});

  @override
  State<_PhotoBubble> createState() => _PhotoBubbleState();
}

class _PhotoBubbleState extends State<_PhotoBubble> {
  void _showFullScreen(int initialPage) {
    final paths = widget.message.filePaths;
    if (paths.isEmpty) return;

    FullScreenImageViewer.show(
      context,
      paths: paths,
      initialPage: initialPage,
    );
  }

  /// 将识别出来的多行文本清洗掉多余空格和换行，产生极致紧凑的高密度单段预览
  String _condenseText(String raw) {
    return raw.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  @override
  Widget build(BuildContext context) {
    final paths = widget.message.filePaths;
    final pageCount = paths.length;

    // 优先读取自身精准绑定的 extractedText，回落兼容可能存在的旧 subMessage
    final ocrText = (widget.message.extractedText != null &&
            widget.message.extractedText!.isNotEmpty)
        ? widget.message.extractedText!
        : (widget.subMessage?.extractedText ?? '');

    final isFailed = ProcessingService.isFailureText(ocrText);
    final isPending = widget.showPending ||
        (ocrText.isEmpty &&
            DateTime.now().difference(widget.message.createdAt).inSeconds < 180);

    if (paths.isEmpty) {
      return const Icon(Icons.broken_image, size: 48, color: Colors.grey);
    }

    final condensedOcr = _condenseText(ocrText);

    // ==========================================
    // 场景 A: 识别已完成，且为单图
    // 按照微信发文件/卡片的形式紧凑坍缩：左图右字，极致节省纵向空间
    // ==========================================
    if (pageCount == 1 && !isPending && ocrText.isNotEmpty) {
      return InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => showOcrTextDetailsDialog(
          context: context,
          title: '文书图片识别结果',
          text: ocrText,
        ),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 左侧可点击查看原图的缩略图
              GestureDetector(
                onTap: () => _showFullScreen(0),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: Image.file(
                    File(paths.first),
                    width: 72,
                    height: 72,
                    cacheWidth: 300,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // 右侧紧凑高密度展示文字摘要
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          isFailed ? Icons.error_outline : Icons.document_scanner_outlined,
                          size: 13,
                          color: isFailed ? Colors.red : Colors.teal,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isFailed ? '识别异常' : '识别内容摘要 (${ocrText.length}字)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isFailed ? Colors.red : Colors.teal.shade800,
                          ),
                        ),
                        const Spacer(),
                        const Icon(Icons.open_in_new, size: 12, color: Colors.grey),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      condensedOcr,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: isFailed ? Colors.red.shade800 : Colors.black87,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    // ==========================================
    // 场景 B: 正在识别中（单图/多图均统一为 130px 尺寸），或多图完成
    // ==========================================
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // 图片展示区：单图多图在等待中均统一为 130px 高度的紧凑视觉
        if (pageCount == 1)
          GestureDetector(
            onTap: () => _showFullScreen(0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(paths.first),
                height: 130,
                width: 130,
                cacheWidth: 400,
                fit: BoxFit.cover,
              ),
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.photo_library_outlined, size: 12, color: Colors.blueGrey),
                    const SizedBox(width: 4),
                    Text('文书材料 · 共 $pageCount 页',
                        style: const TextStyle(fontSize: 10, color: Colors.blueGrey, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              SizedBox(
                height: 130,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: pageCount,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (_, i) => GestureDetector(
                    onTap: () => _showFullScreen(i),
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(paths[i]),
                            width: 110,
                            height: 130,
                            cacheWidth: 350,
                            fit: BoxFit.cover,
                            errorBuilder: (_, e, s) => Container(
                              width: 110,
                              height: 130,
                              color: Colors.grey[300],
                              child: const Icon(Icons.image, size: 36),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 4,
                          left: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.65),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '${i + 1}/$pageCount',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

        // 下方识别结果展示
        if (isPending) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 6),
                Text('文书 OCR 识别中...',
                    style: TextStyle(fontSize: 11, color: Colors.blue)),
              ],
            ),
          ),
        ] else if (ocrText.isNotEmpty) ...[
          const SizedBox(height: 6),
          // 多图下方展示高密度纯净内容，点击弹窗查看完整内容
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => showOcrTextDetailsDialog(
              context: context,
              title: '多页文书 ($pageCount页) 识别全文',
              text: ocrText,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isFailed
                    ? Colors.red.withValues(alpha: 0.08)
                    : Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isFailed
                      ? Colors.red.withValues(alpha: 0.3)
                      : Colors.grey.withValues(alpha: 0.2),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isFailed ? Icons.error_outline : Icons.document_scanner_outlined,
                        size: 13,
                        color: isFailed ? Colors.red : Colors.teal,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        isFailed ? '识别异常' : '识别文本 (${ocrText.length}字)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: isFailed ? Colors.red : Colors.teal.shade800,
                        ),
                      ),
                      const Spacer(),
                      const Text('查看全文 ➔', style: TextStyle(fontSize: 10.5, color: Colors.teal, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    condensedOcr,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.35,
                      color: isFailed ? Colors.red.shade800 : Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _DocumentBubble extends StatefulWidget {
  final Message message;
  const _DocumentBubble({required this.message});

  @override
  State<_DocumentBubble> createState() => _DocumentBubbleState();
}

class _DocumentBubbleState extends State<_DocumentBubble> {
  bool _expanded = false;

  IconData _getFileIcon(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'docx':
      case 'doc':
        return Icons.description;
      case 'txt':
      case 'text':
      case 'md':
        return Icons.article;
      default:
        return Icons.insert_drive_file;
    }
  }

  Color _getFileColor(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Colors.red.shade700;
      case 'docx':
      case 'doc':
        return Colors.blue.shade700;
      case 'txt':
      case 'text':
      case 'md':
        return Colors.teal.shade700;
      default:
        return Colors.orange.shade700;
    }
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final fileName = widget.message.content ?? '未命名文件';
    final ext = fileName.split('.').last;
    final fileIcon = _getFileIcon(ext);
    final fileColor = _getFileColor(ext);
    final fileSize = widget.message.fileSizes.isNotEmpty ? widget.message.fileSizes.first : 0;
    final extracted = widget.message.extractedText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 文件头部卡片
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: fileColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(fileIcon, color: fileColor, size: 24),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      fileName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _formatFileSize(fileSize),
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 可折叠的文本提取结果气泡
        if (extracted != null && extracted.isNotEmpty) ...[
          const SizedBox(height: 6),
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(6),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.document_scanner_outlined, size: 13, color: Colors.teal),
                  const SizedBox(width: 4),
                  Text(
                    '已提取 ${extracted.length} 字内容',
                    style: const TextStyle(fontSize: 11, color: Colors.teal, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 16,
                    color: Colors.teal,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const SizedBox(height: 4),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
              ),
              child: SelectableText(
                extracted,
                style: const TextStyle(fontSize: 11.5, height: 1.35),
              ),
            ),
          ],
        ],
      ],
    );
  }
}

class _SystemBubble extends ConsumerWidget {
  final Message message;
  const _SystemBubble({required this.message});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = message.type == MessageType.asrResult
        ? message.transcribedText
        : message.extractedText;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message.content ?? '',
            style: const TextStyle(fontSize: 11, color: Colors.grey)),
        const SizedBox(height: 4),
        Text(text ?? ''),
      ],
    );
  }
}

class _RecordBubble extends ConsumerStatefulWidget {
  final Message message;
  const _RecordBubble({required this.message});

  @override
  ConsumerState<_RecordBubble> createState() => _RecordBubbleState();
}

class _RecordBubbleState extends ConsumerState<_RecordBubble> {
  @override
  Widget build(BuildContext context) {
    Map<String, dynamic> fields = {};
    try {
      if (widget.message.recordJson != null &&
          widget.message.recordJson!.isNotEmpty) {
        fields =
            jsonDecode(widget.message.recordJson!) as Map<String, dynamic>;
      }
    } catch (_) {}

    final title = widget.message.recordMeta?.templateName?.isNotEmpty == true
        ? widget.message.recordMeta!.templateName!
        : '生成文书';
    final unsupported = CharacterSanitizer.findUnsupportedCharacters(
      fields.values.map((v) => v.toString()).join(),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () {
        context.push(
            '/patients/${widget.message.patientId}/records/${widget.message.id}/review');
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(Icons.assignment_outlined, size: 20, color: Colors.teal),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 4),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    TypingSendSheet.show(
                      context: context,
                      message: widget.message,
                      isQrMode: true,
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.all(6),
                    child: Icon(Icons.qr_code_2, size: 22, color: Colors.blue),
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: () {
                    TypingSendSheet.show(
                      context: context,
                      message: widget.message,
                      isQrMode: false,
                    );
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bluetooth, size: 16, color: Colors.blue),
                        SizedBox(width: 2),
                        Text('蓝牙发送', style: TextStyle(fontSize: 12, color: Colors.blue, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (unsupported.isNotEmpty || widget.message.recordMeta?.isPartial == true) ...[
            const SizedBox(height: 4),
            Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                if (unsupported.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.warning_amber_rounded, size: 10, color: Colors.red),
                        SizedBox(width: 2),
                        Text(
                          '含特殊字符',
                          style: TextStyle(
                              fontSize: 9.5,
                              color: Colors.red,
                              fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                if (widget.message.recordMeta?.isPartial == true)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      '部分生成',
                      style: TextStyle(
                          fontSize: 10,
                          color: Colors.deepOrange,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ],
          const Divider(height: 12),

          // Structured field preview lines (up to 4 items)
          if (fields.isEmpty)
            Text(widget.message.recordJson ?? '(空文书)',
                style: const TextStyle(fontSize: 12, color: Colors.grey))
          else
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final e in fields.entries.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: RichText(
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      text: TextSpan(
                        style: DefaultTextStyle.of(context).style.copyWith(fontSize: 12.5),
                        children: [
                          TextSpan(
                            text: '【${e.key}】',
                            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey),
                          ),
                          TextSpan(text: ' ${e.value}'),
                        ],
                      ),
                    ),
                  ),
                if (fields.length > 4)
                  Text(
                    '...等共 ${fields.length} 个字段',
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                  ),
              ],
            ),
          const SizedBox(height: 8),

          // Action entry bar
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Text(
                '点击进入全屏审核修改 ➔',
                style: TextStyle(
                  fontSize: 11,
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
