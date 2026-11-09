import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:record/record.dart';

import 'package:peipal/presentation/widgets/common/app_toast.dart';
import '../../../domain/models/message.dart';
import '../../../domain/models/template.dart';
import '../../../domain/models/content_template.dart';
import '../../../data/repositories/message_repository.dart';
import '../../../data/services/media/media_storage.dart';
import '../../../providers/providers.dart';
import '../../../domain/models/patient.dart';
import '../../../data/services/media/document_parser_service.dart';
import '../../widgets/chat/message_bubble.dart';
import '../../widgets/chat/input_bar.dart';
import '../../widgets/chat/recording_overlay.dart';
import '../../widgets/chat/generation_pending_bubble.dart';
import '../../widgets/chat/manual_prompt_preview_dialog.dart';
import '../../widgets/chat/record_generation_wizard_sheet.dart';
import '../../widgets/chat/session_info_quick_sheet.dart';
import 'llm_dry_run_preview_page.dart';
import 'generation_run_page.dart';
import '../../../data/services/task/task_center.dart';
import '../../../domain/generation/generation_plan.dart';
import '../../../providers/tutorial_provider.dart';
import '../../widgets/tutorial/tutorial_spotlight_overlay.dart';

class ChatPage extends ConsumerStatefulWidget {
  final String patientId;
  final String? highlightMessageId;

  const ChatPage({
    super.key,
    required this.patientId,
    this.highlightMessageId,
  });

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _scrollController = ScrollController();
  MessageRepository get _msgRepo => ref.read(messageRepositoryProvider);
  final _inputKey = GlobalKey<ChatInputBarState>();
  final _generateBtnKey = GlobalKey();

  RecordingPhase _recPhase = RecordingPhase.holding;
  TouchTarget _touchTarget = TouchTarget.normal;
  Stream<Amplitude>? _amplitudeStream;
  bool _showOverlay = false;
  bool _hasScrolledToHighlight = false;
  Timer? _recordTimer;
  int _recordDurationMs = 0;
  String? _previewWavPath;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _recordTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _onSendText(String text) async {
    final msg = Message.text(patientId: widget.patientId, content: text);
    await _msgRepo.insert(msg);
    _notifyDataChanged();
  }

  Future<void> _onSendPhotos({
    required List<String> filePaths,
    required List<int> fileSizes,
  }) async {
    final draft = Message.photo(
      patientId: widget.patientId,
      filePaths: filePaths,
      fileSizes: fileSizes,
    );
    List<String> finalPaths = filePaths;
    try {
      finalPaths = await MediaStorage.savePhotos(
        widget.patientId,
        draft.id,
        filePaths,
      );
    } catch (e) {
      debugPrint('保存照片到永久目录失败: $e');
    }

    final msg = draft.copyWith(filePaths: finalPaths);
    await _msgRepo.insert(msg);
    if (mounted) _notifyDataChanged();

    // 绑定至该图片文书本身进行 OCR，绝不产生多余错位的孤立占位消息
    ref.read(processingServiceProvider.notifier)
        .processOcr(widget.patientId, finalPaths, targetPhotoMsgId: msg.id);
  }

  /// 接收文书装订工作台交付的多份文书批量投递
  Future<void> _onSendDocuments(List<List<String>> documentPhotoBatches) async {
    for (final paths in documentPhotoBatches) {
      final sizes = paths.map((p) => File(p).lengthSync()).toList();
      await _onSendPhotos(filePaths: paths, fileSizes: sizes);
    }
  }

  Future<void> _onSendVoice({
    required String filePath,
    required int fileSize,
    required int durationMs,
  }) async {
    final draft = Message.voice(
      patientId: widget.patientId,
      filePath: filePath,
      fileSize: fileSize,
      durationMs: durationMs,
    );
    String finalPath = filePath;
    try {
      finalPath = await MediaStorage.saveAudio(
        widget.patientId,
        draft.id,
        filePath,
      );
    } catch (e) {
      debugPrint('保存语音到永久目录失败: $e');
    }

    final msg = draft.copyWith(filePaths: [finalPath]);
    await _msgRepo.insert(msg);
    if (mounted) _notifyDataChanged();

    // Hand off to ProcessingService for async ASR
    ref.read(processingServiceProvider.notifier)
        .processAsr(widget.patientId, finalPath);
  }

  /// 发送并解析常见文件 (PDF, Word docx, TXT等)
  Future<void> _onSendFile(String filePath) async {
    final file = File(filePath);
    if (!await file.exists()) return;

    final fileName = file.uri.pathSegments.last;
    final fileSize = await file.length();

    // 1. 先插入占位文档消息
    final msg = Message.document(
      patientId: widget.patientId,
      filePath: filePath,
      fileSize: fileSize,
      fileName: fileName,
    );
    await _msgRepo.insert(msg);
    _notifyDataChanged();

    // 2. 后台拷贝到应用永久持久化目录并本地提取文本
    try {
      final savedPath = await MediaStorage.saveDocument(widget.patientId, msg.id, filePath);
      String? extracted;
      try {
        extracted = await DocumentParserService.parseFileText(savedPath);
      } catch (e) {
        extracted = '文件提取失败: $e';
      }

      final isPdf = savedPath.toLowerCase().endsWith('.pdf');
      // 如果是 PDF 且提取出来的文字非常少（说明是纯扫描图或图文混排扫描版）
      if (isPdf && DocumentParserService.isPdfTextSparse(extracted)) {
        final hint = extracted.isNotEmpty
            ? '$extracted\n\n⚠️【提示】该 PDF 文字较少或为扫描图片，建议长按此消息选择「转为图片并重新 OCR」'
            : '⚠️【提示】未能从该 PDF 提取到文字层，可能为纯扫描图片，建议长按此消息选择「转为图片并重新 OCR」';
        extracted = hint;
      }

      await _msgRepo.update(msg.copyWith(
        filePaths: [savedPath],
        extractedText: extracted,
      ));
      if (mounted) _notifyDataChanged();
    } catch (e) {
      debugPrint('处理并解析文件失败: $e');
    }
  }

  void _notifyDataChanged() {
    ref.invalidate(messagesProvider(widget.patientId));
    ref.invalidate(lastMessageProvider(widget.patientId));
    ref.invalidate(patientsProvider);
  }

  Future<void> _openSessionInfoQuickSheet(
    Patient? p, {
    bool autoExtract = false,
  }) async {
    if (p == null) return;
    final msgs = await _msgRepo.getByPatient(widget.patientId, limit: 200);
    if (!mounted) return;
    await SessionInfoQuickSheet.show(
      context,
      patient: p,
      messages: msgs,
      autoExtractOnOpen: autoExtract,
    );
  }

  /// 统一收集病历生成规划（通过一体化 1-2-3-4 步骤向导收集模板、内容模板、素材范围、字段与要求）
  Future<({Template template, ContentTemplate? contentTemplate, GenerationPlan plan})?>
      _collectGenerationInputs({required bool isDryRun}) async {
    final templates = await ref.read(templateRepositoryProvider).getAll();
    if (!mounted) return null;

    if (templates.isEmpty) {
      showWarningToast(context, '暂无文书类型，请先在菜单中创建文书类型');
      return null;
    }

    // 弹出单一一体化病历生成向导（画面中央弹窗，整合 1.选结构模板 -> 2.选内容模板 -> 3.选素材范围 -> 4.选字段与要求）
    final wizardResult = await showDialog<GenerationWizardResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => RecordGenerationWizardSheet(
        patientId: widget.patientId,
        isDryRun: isDryRun,
      ),
    );

    if (wizardResult == null || !mounted) return null;

    final messages = await _msgRepo.getAllChronological(widget.patientId);
    final patient =
        await ref.read(patientRepositoryProvider).getById(widget.patientId);
    if (patient == null || !mounted) return null;

    final engine = ref.read(generationEngineProvider);
    final favDiags =
        await ref.read(favoriteDiagnosisRepositoryProvider).getAll();
    if (!mounted) return null;

    await ref.read(llmPromptConfigProvider.notifier).ready;
    if (!mounted) return null;

    final catalogList = await ref.read(catalogsProvider.future);
    if (!mounted) return null;
    final catalogsById = {for (final c in catalogList) c.id: c};

    final plan = engine.buildPlan(
      template: wizardResult.template,
      contentTemplate: wizardResult.contentTemplate,
      patient: patient,
      chatMessages: messages,
      favoriteDiagnoses: favDiags,
      catalogs: catalogsById,
      promptConfig: ref.read(llmPromptConfigProvider),
      allMaterials: wizardResult.allMaterials,
      selectedSlotKeys: wizardResult.selectedSlotKeys,
      extraInstructions: wizardResult.extraInstructions,
    );

    return (
      template: wizardResult.template,
      contentTemplate: wizardResult.contentTemplate,
      plan: plan,
    );
  }

  Future<void> _onGenerateRecord({bool forceManual = false}) async {
    final inputs = await _collectGenerationInputs(isDryRun: false);
    if (inputs == null || !mounted) return;

    bool useManual = forceManual;
    final llmConfig = ref.read(llmConfigProvider);

    // 教程最后一步、或未配置密钥时，在「确认开始生成」弹出方式选择。
    final tutorial = ref.read(tutorialProvider);
    final isTutorialConfirm = tutorial.isActive &&
        tutorial.activeTutorial == TutorialType.basicFlow &&
        tutorial.currentStep == 4;

    final needChoice =
        !useManual && (!llmConfig.isConfigured || isTutorialConfirm);

    if (needChoice) {
      if (isTutorialConfirm) {
        ref.read(tutorialProvider.notifier).goToStep(5);
      }
      if (!mounted) return;
      final choice = await _showGenerationModeDialog(
        isTutorial: isTutorialConfirm,
        aiConfigured: llmConfig.isConfigured,
      );
      if (choice == null) {
        if (isTutorialConfirm) {
          ref.read(tutorialProvider.notifier).goToStep(4);
        }
        return;
      }
      if (choice == 'manual') {
        useManual = true;
      } else if (choice == 'ai') {
        if (!llmConfig.isConfigured) {
          if (isTutorialConfirm) {
            await ref.read(tutorialProvider.notifier).completeTutorial();
          }
          if (mounted) {
            context.push('/settings/llm-providers');
            showAppToast(context, '填入 API Key 后即可自动生成');
          }
          return;
        }
        // 已配置 AI：选择后继续正常生成
      }
      if (isTutorialConfirm) {
        await ref.read(tutorialProvider.notifier).completeTutorial();
      }
    } else if (isTutorialConfirm) {
      await ref.read(tutorialProvider.notifier).completeTutorial();
    }

    if (useManual) {
      final taskId = ref.read(taskCenterProvider).startManualGenerationTask(
        plan: inputs.plan,
        patientId: widget.patientId,
        patientName: inputs.plan.patient.name,
      );
      final task = ref.read(taskCenterProvider).getTask(taskId);
      if (task?.manualPrompt != null) {
        Clipboard.setData(ClipboardData(text: task!.manualPrompt!));
      }

      if (mounted && task?.manualPrompt != null) {
        showManualPromptPreviewDialog(
          context: context,
          title: '已整理对话内容 · ${inputs.plan.template.name}',
          promptText: task!.manualPrompt!,
        );
      }
      return;
    }

    // 打开全屏等待与故障恢复界面
    if (!mounted) return;
    final savedMsgId = await Navigator.push<String?>(
      context,
      MaterialPageRoute(
        builder: (_) => GenerationRunPage(
          plan: inputs.plan,
          patientId: widget.patientId,
        ),
      ),
    );

    _notifyDataChanged();

    // 生成全量成功或部分保存成功后，直接打开审核页
    if (savedMsgId != null && mounted) {
      context.push('/patients/${widget.patientId}/records/$savedMsgId/review');
    }
  }

  Future<String?> _showGenerationModeDialog({
    required bool isTutorial,
    required bool aiConfigured,
  }) async {
    return showDialog<String>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isTutorial)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '新手指引 · 5/5',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              const Row(
                children: [
                  Icon(Icons.play_circle_outline_rounded, color: Colors.amber, size: 22),
                  SizedBox(width: 8),
                  Text(
                    '最后一步：确认开始生成',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                aiConfigured
                    ? '选择本次的生成方式：'
                    : '还没有配置 AI 密钥，请选择生成方式：',
                style: TextStyle(fontSize: 13.5, color: Colors.grey.shade700, height: 1.4),
              ),
              const SizedBox(height: 16),
              // 选项 A：应用内 AI 生成（未配置时引导去配置）
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(ctx, 'ai'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: scheme.primary.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        aiConfigured ? Icons.auto_awesome : Icons.key_rounded,
                        color: scheme.primary,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  aiConfigured ? '使用 AI 直接生成' : '配置 AI，直接生成',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: scheme.primary,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('推荐',
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              aiConfigured
                                  ? '在应用内自动整理并生成结果。'
                                  : '填写一次 API Key，之后都能在应用内自动生成。',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              // 选项 B：复制到外部 AI 手动生成
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => Navigator.pop(ctx, 'manual'),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.shade400),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.copy_all_rounded, color: Colors.amber.shade900, size: 24),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text('复制到外部 AI 生成',
                                    style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 14,
                                        color: Colors.amber.shade900)),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade800,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text('免配置',
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '自动整理好内容并复制，粘贴到任意 AI 生成后再贴回。',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.chevron_right, size: 20, color: Colors.grey),
                    ],
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _onDryRunTest() async {
    final inputs = await _collectGenerationInputs(isDryRun: true);
    if (inputs == null || !mounted) return;

    final engine = ref.read(generationEngineProvider);
    final stages = engine.dryRun(inputs.plan);

    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LlmDryRunPreviewPage(
            templateName: inputs.template.name,
            stages: stages,
          ),
        ),
      );
    }
  }

  void _showMessageActions(Message msg, Message? subMsg) {
    final canDelete = msg.sender == MessageSender.user ||
        msg.type == MessageType.asrResult ||
        msg.type == MessageType.ocrResult ||
        msg.type == MessageType.generatedRecord;

    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  msg.type == MessageType.generatedRecord ? '删除此文书记录' : '删除',
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('确认删除'),
                      content: Text(msg.type == MessageType.generatedRecord
                          ? '确定要删除这份已生成的文书记录吗？\n删除后不可恢复。'
                          : '确定要删除这条消息吗？'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('取消')),
                        TextButton(
                            onPressed: () => Navigator.pop(c, true),
                            child: const Text('删除',
                                style: TextStyle(color: Colors.red))),
                      ],
                    ),
                  );
                  if (confirm == true) {
                    await _msgRepo.delete(msg.id);
                    if (subMsg != null) await _msgRepo.delete(subMsg.id);
                    try {
                      if (msg.type == MessageType.voice) {
                        for (final f in msg.filePaths) {
                          await MediaStorage.deleteAudio(f);
                        }
                      } else if (msg.type == MessageType.photo) {
                        await MediaStorage.deletePhotos(
                            widget.patientId, msg.id);
                      }
                    } catch (_) {}
                    _notifyDataChanged();
                  }
                },
              ),
            if (msg.type == MessageType.voice &&
                msg.filePaths.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('重新识别 (ASR)'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(processingServiceProvider.notifier).processAsr(
                    widget.patientId,
                    msg.filePaths.first,
                    existingMsgId: subMsg?.id,
                  );
                },
              ),
            if (msg.type == MessageType.photo &&
                msg.filePaths.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.refresh),
                title: const Text('重新识别 (OCR)'),
                onTap: () {
                  Navigator.pop(ctx);
                  ref.read(processingServiceProvider.notifier).processOcr(
                    widget.patientId,
                    msg.filePaths,
                    targetPhotoMsgId: msg.id,
                  );
                },
              ),
            if (msg.type == MessageType.document &&
                msg.filePaths.isNotEmpty &&
                msg.filePaths.first.toLowerCase().endsWith('.pdf'))
              ListTile(
                leading: const Icon(Icons.image_search_outlined, color: Colors.blue),
                title: const Text('转为图片并重新 OCR'),
                subtitle: const Text('将 PDF 页面拆解为图片消息并深度提取图文'),
                onTap: () async {
                  Navigator.pop(ctx);
                  final pdfPath = msg.filePaths.first;
                  showInfoToast(context, '正在拆解 PDF 为图片，请稍候...');

                  // 拆解页面到独立文件夹
                  final tempOutputDir = '${Directory.systemTemp.path}/pdf_${DateTime.now().millisecondsSinceEpoch}';
                  final renderedImages = await DocumentParserService.renderPdfPagesToImages(
                    pdfPath: pdfPath,
                    outputDir: tempOutputDir,
                  );

                  if (renderedImages.isNotEmpty && mounted) {
                    final sizes = renderedImages.map((p) => File(p).lengthSync()).toList();
                    await _onSendPhotos(filePaths: renderedImages, fileSizes: sizes);
                  } else if (mounted) {
                    showErrorToast(context, '未能从该 PDF 拆解出图片页面');
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final patient = ref.watch(patientProvider(widget.patientId));
    final messages = ref.watch(messagesProvider(widget.patientId));

    // Listen for ProcessingService ticks → refresh messages from DB
    ref.listen<int>(processingServiceProvider, (previous, next) {
      _notifyDataChanged();
    });

    final runningTask = ref.watch(
      taskCenterProvider.select((tc) => tc.getRunningGenerationForPatient(widget.patientId)),
    );

    return patient.when(
      data: (p) => Stack(
        children: [
          Scaffold(
        appBar: AppBar(
          title: InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: () => _openSessionInfoQuickSheet(p),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      p?.name ?? '会话',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.arrow_drop_down_rounded, size: 20),
                ],
              ),
            ),
          ),
          actions: [
            TextButton.icon(
              icon: const Icon(Icons.assignment_outlined, size: 20),
              label: const Text('已生成文书', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () =>
                  context.push('/patients/${widget.patientId}/records'),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              tooltip: '会话选项',
              onSelected: (val) async {
                if (p == null) return;
                switch (val) {
                  case 'edit':
                    context.push('/patients/${p.id}/edit');
                    break;
                  case 'toggle_status':
                    final newStatus = p.status == PatientStatus.active
                        ? PatientStatus.discharged
                        : PatientStatus.active;
                    final updatedPatient = p.copyWith(
                      status: newStatus,
                    );
                    await ref.read(patientRepositoryProvider).update(updatedPatient);
                    ref.invalidate(patientProvider(p.id));
                    ref.invalidate(patientsProvider);
                    if (context.mounted) {
                      showSuccessToast(
                        context,
                        newStatus == PatientStatus.discharged ? '已标记为归档' : '已恢复为进行中',
                      );
                    }
                    break;
                  case 'delete':
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('删除会话'),
                        content: Text('确定要删除会话「${p.name}」吗？\n所有相关消息、材料与生成的文书都将被永久删除。'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx, false),
                            child: const Text('取消'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(backgroundColor: Colors.red),
                            onPressed: () => Navigator.pop(ctx, true),
                            child: const Text('删除'),
                          ),
                        ],
                      ),
                    );
                    if (confirm == true) {
                      await ref.read(patientRepositoryProvider).delete(p.id);
                      await MediaStorage.deletePatientMedia(p.id);
                      ref.invalidate(patientsProvider);
                      if (context.mounted) {
                        context.pop();
                      }
                    }
                    break;
                }
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'edit',
                  child: Row(
                    children: [
                      Icon(Icons.edit_outlined, size: 18),
                      SizedBox(width: 8),
                      Text('编辑会话信息'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'toggle_status',
                  child: Row(
                    children: [
                      Icon(
                        p?.status == PatientStatus.active ? Icons.archive_outlined : Icons.unarchive_outlined,
                        size: 18,
                        color: Colors.orange,
                      ),
                      const SizedBox(width: 8),
                      Text(p?.status == PatientStatus.active ? '标记归档' : '恢复进行中'),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      Icon(Icons.delete_outline, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('删除此会话', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        body: Stack(
          children: [
            Column(
          children: [
            // 后台生成任务常驻提示胶囊（可点击直接切回全屏监控）
            if (runningTask != null)
              InkWell(
                onTap: () {
                  if (runningTask.generationPlan != null) {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => GenerationRunPage(
                          plan: runningTask.generationPlan!,
                          patientId: widget.patientId,
                          existingTaskId: runningTask.id,
                        ),
                      ),
                    );
                  }
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  color: Colors.blue.withValues(alpha: 0.12),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '后台生成中: ${runningTask.stageDescription}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Text(
                        '点击查看 ➔',
                        style: TextStyle(fontSize: 11, color: Colors.blue),
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: messages.when(
                data: (list) {
                  
                  if (list.isEmpty) {
                    return const Center(
                        child: Text('开始采集信息',
                            style: TextStyle(color: Colors.grey)));
                  }

                  final List<BackgroundTask> runningGenTasks =
                      runningTask != null ? [runningTask] : const <BackgroundTask>[];
                  final int pendingTasksCount = runningGenTasks.length;

                  // 如果有外部传递的 highlightMessageId，且尚未执行滚动，计算目标索引并自动滚动
                  if (widget.highlightMessageId != null && !_hasScrolledToHighlight) {
                    final targetIndex = list.indexWhere((m) =>
                        m.id == widget.highlightMessageId ||
                        (m.recordMeta != null && m.id == widget.highlightMessageId));
                    if (targetIndex >= 0) {
                      _hasScrolledToHighlight = true;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (_scrollController.hasClients) {
                          // reverse: true 下，每个消息大概 100~150px 高度
                          final targetOffset =
                              ((targetIndex + pendingTasksCount) * 110.0).clamp(
                            0.0,
                            _scrollController.position.maxScrollExtent,
                          );
                          _scrollController.animateTo(
                            targetOffset,
                            duration: const Duration(milliseconds: 350),
                            curve: Curves.easeOutCubic,
                          );
                        }
                      });
                    }
                  }

                  return ListView.builder(
                        controller: _scrollController,
                        reverse: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 12),
                        itemCount: list.length + pendingTasksCount,
                        itemBuilder: (_, i) {
                          // 优先在最底端（最新位置）展示正在生成中或等待贴回的手动挡卡片
                          if (i < pendingTasksCount) {
                            return GenerationPendingBubble(
                              task: runningGenTasks[i],
                            );
                          }

                            final int msgIndex = i - pendingTasksCount;
                            final msg = list[msgIndex];
                          Message? subMsg;
                          // With reverse:true, newer messages have lower index.
                          // A voice's asrResult is at i-1 (created after the voice).
                          if (msgIndex > 0) {
                            final newer = list[msgIndex - 1];
                            if ((msg.type == MessageType.voice &&
                                    newer.type == MessageType.asrResult) ||
                                (msg.type == MessageType.photo &&
                                    newer.type == MessageType.ocrResult)) {
                              subMsg = newer;
                            }
                          }
                          // Skip sub-messages when they're already shown as paired
                          if (msgIndex + 1 < list.length) {
                            final older = list[msgIndex + 1];
                            if ((older.type == MessageType.voice &&
                                    msg.type == MessageType.asrResult) ||
                                (older.type == MessageType.photo &&
                                    msg.type == MessageType.ocrResult)) {
                              return const SizedBox.shrink();
                            }
                          }
                          // Detect pending processing from DB placeholder state
                          final isPlaceholder = subMsg != null &&
                              ((subMsg.type == MessageType.asrResult &&
                                      (subMsg.transcribedText?.isEmpty ?? true)) ||
                                  (subMsg.type == MessageType.ocrResult &&
                                      (subMsg.extractedText?.isEmpty ?? true)));
                          final ageSeconds = DateTime.now().difference(msg.createdAt).inSeconds;
                          final showPending = isPlaceholder && ageSeconds < 120;
                          final isHighlighted = widget.highlightMessageId != null &&
                              (msg.id == widget.highlightMessageId ||
                                  subMsg?.id == widget.highlightMessageId);

                          return Container(
                            decoration: isHighlighted
                                ? BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(color: Colors.amber.shade400, width: 1.5),
                                  )
                                : null,
                            margin: isHighlighted
                                ? const EdgeInsets.symmetric(vertical: 4, horizontal: 2)
                                : EdgeInsets.zero,
                            child: GestureDetector(
                              onLongPress: () => _showMessageActions(msg, subMsg),
                              child: MessageBubble(
                                message: msg,
                                subMessage: subMsg,
                                showProcessing: showPending,
                                ref: ref,
                              ),
                            ),
                          );
                        },
                      );
                  },
                  loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('加载失败: $e')),
              ),
            ),
            if (ref.watch(llmDryRunEnabledProvider))
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                color: Colors.amber.withValues(alpha: 0.15),
                child: Row(
                  children: [
                    const Icon(Icons.bug_report_outlined,
                        size: 14, color: Colors.brown),
                    const SizedBox(width: 6),
                    const Text('LLM 提示词监视模式开启中',
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.brown,
                            fontWeight: FontWeight.bold)),
                    const Spacer(),
                    InkWell(
                      borderRadius: BorderRadius.circular(4),
                      onTap: _onDryRunTest,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.amber[800],
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.visibility,
                                size: 12, color: Colors.white),
                            SizedBox(width: 4),
                            Text('测试 Prompt (试跑)',
                                style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ChatInputBar(
              key: _inputKey,
              generateButtonKey: _generateBtnKey,
              onSendText: _onSendText,
              onSendPhotos: _onSendPhotos,
              onSendDocuments: _onSendDocuments,
              onSendVoice: _onSendVoice,
              onSendFile: _onSendFile,
              onRecordingHoldingStarted: (stream) {
                _recordTimer?.cancel();
                _recordDurationMs = 0;
                _previewWavPath = null;
                _recordTimer = Timer.periodic(const Duration(milliseconds: 200), (t) {
                  if (mounted && _showOverlay) {
                    setState(() {
                      _recordDurationMs =
                          _inputKey.currentState?.currentDurationMs ?? (t.tick * 200);
                    });
                  }
                });
                setState(() {
                  _amplitudeStream = stream;
                  _recPhase = RecordingPhase.holding;
                  _touchTarget = TouchTarget.normal;
                  _showOverlay = true;
                });
              },
              onTouchTargetChanged: (target) {
                if (mounted) setState(() => _touchTarget = target);
              },
              onHoldingFinished: (lockToWorkbench, cancel) async {
                if (cancel) {
                  _recordTimer?.cancel();
                  if (mounted) setState(() => _showOverlay = false);
                } else if (lockToWorkbench) {
                  // 进入锁定的录音工作台模式（继续录音）
                  if (mounted) {
                    setState(() {
                      _recPhase = RecordingPhase.lockedRecording;
                    });
                  }
                } else {
                  // 正常长按松手后直接发送完成
                  _recordTimer?.cancel();
                  if (mounted) setState(() => _showOverlay = false);
                }
              },
              onGenerateRecord: _onGenerateRecord,
              onManualGenerateRecord: () => _onGenerateRecord(forceManual: true),
              onAutofillSessionInfo: () => _openSessionInfoQuickSheet(p, autoExtract: true),
              isDryRunEnabled: ref.watch(llmDryRunEnabledProvider),
              onDryRunTest: _onDryRunTest,
            ),
          ],
        ),
        if (_showOverlay && _amplitudeStream != null)
          RecordingOverlay(
            phase: _recPhase,
            currentTouchTarget: _touchTarget,
            amplitudeStream: _amplitudeStream!,
            durationMs: _recordDurationMs,
            audioPath: _previewWavPath,
            onDirectTapCancel: () async {
              _recordTimer?.cancel();
              await _inputKey.currentState?.cancelRecording();
              if (mounted) setState(() => _showOverlay = false);
            },
            onDirectTapLock: () {
              if (mounted) {
                setState(() {
                  _recPhase = RecordingPhase.lockedRecording;
                });
              }
            },
            onStopRecording: () async {
              _recordTimer?.cancel();
              final wav = await _inputKey.currentState?.stopAndPrepareWav();
              if (mounted) {
                setState(() {
                  _previewWavPath = wav;
                  _recPhase = RecordingPhase.stoppedReview;
                });
              }
            },
            onSend: () async {
              _recordTimer?.cancel();
              await _inputKey.currentState?.confirmSendCachedVoice();
              if (mounted) setState(() => _showOverlay = false);
            },
            onCancel: () async {
              _recordTimer?.cancel();
              await _inputKey.currentState?.cancelRecording();
              if (mounted) setState(() => _showOverlay = false);
            },
          ),
      ],
    ),
  ),
        Consumer(
          builder: (context, ref, _) {
            final tutorialState = ref.watch(tutorialProvider);
            if (!tutorialState.isActive ||
                tutorialState.activeTutorial != TutorialType.basicFlow ||
                (tutorialState.currentStep != 3 &&
                    tutorialState.currentStep != 4)) {
              return const SizedBox.shrink();
            }
            if (tutorialState.currentStep == 3) {
              return TutorialSpotlightOverlay(
                highlightLowerHalf: true,
                lowerHalfStart: 0.3,
                pinTooltip: true,
                borderRadius: 18,
                stepTag: '新手指引 · 3/5',
                title: '像微信一样录入材料',
                description: '上方是聊天记录，下方输入框可以打字、按住说话；点「+」展开后还能拍照或发送图片文件。\n语音和图片会自动转成文字。',
                nextButtonLabel: '下一步',
                onNext: () => ref.read(tutorialProvider.notifier).nextStep(),
                onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
              );
            } else {
              return TutorialSpotlightOverlay(
                targetKey: _generateBtnKey,
                targetPadding: 16,
                pinTooltip: true,
                stepTag: '新手指引 · 4/5',
                title: '最后一步：整理生成',
                description: '点击这个按钮会打开文书生成指引，一步步选择：文书类型 → 内容模板 → 素材范围 → 字段与要求，最后确认开始生成。',
                nextButtonLabel: '开始生成',
                onNext: () => _onGenerateRecord(),
                onSkip: () => ref.read(tutorialProvider.notifier).skipTutorial(),
              );
            }
          },
        ),
      ],
    ),
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('加载失败: $e')),
      ),
    );
  }
}
