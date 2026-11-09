import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/services/media/app_image_picker.dart';
import '../../../data/services/media/session_autofill_service.dart';
import '../../../domain/models/message.dart';
import '../../../domain/models/patient.dart';
import '../../../providers/providers.dart';
import '../common/app_sheet.dart';
import '../common/app_toast.dart';
import '../common/voice_autofill_sheet.dart';

/// 会话内快捷查看、编辑与「根据会话内容一键补全」浮窗面板
class SessionInfoQuickSheet extends ConsumerStatefulWidget {
  final Patient patient;
  final List<Message> messages;
  final bool autoExtractOnOpen;

  const SessionInfoQuickSheet({
    super.key,
    required this.patient,
    required this.messages,
    this.autoExtractOnOpen = false,
  });

  static Future<void> show(
    BuildContext context, {
    required Patient patient,
    required List<Message> messages,
    bool autoExtractOnOpen = false,
  }) {
    return showAppSheet<void>(
      context: context,
      builder: (ctx) => SessionInfoQuickSheet(
        patient: patient,
        messages: messages,
        autoExtractOnOpen: autoExtractOnOpen,
      ),
    );
  }

  @override
  ConsumerState<SessionInfoQuickSheet> createState() =>
      _SessionInfoQuickSheetState();
}

class _SessionInfoQuickSheetState extends ConsumerState<SessionInfoQuickSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _ageCtrl;
  late final TextEditingController _mrnCtrl;
  late final TextEditingController _notesCtrl;
  late Gender _gender;
  late Map<String, dynamic> _extraData;
  late String _sessionRawText;

  bool _isExtracting = false;
  bool _isSaving = false;
  String _extractingStatusText = '';

  static const _inputBoldStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 15,
  );

  @override
  void initState() {
    super.initState();
    final p = widget.patient;
    _nameCtrl = TextEditingController(text: p.name);
    _ageCtrl = TextEditingController(text: p.age?.toString() ?? '');
    _mrnCtrl = TextEditingController(text: p.medicalRecordNumber ?? '');
    _notesCtrl = TextEditingController(text: p.notes ?? '');
    _gender = p.gender;
    _extraData = Map<String, dynamic>.from(p.extraData);
    _sessionRawText =
        SessionAutofillService.collectRawTextFromMessages(widget.messages);

    if (widget.autoExtractOnOpen) {
      Future.microtask(_extractFromSessionMessages);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ageCtrl.dispose();
    _mrnCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  void _applyAutofillResult(SessionAutofillResult result) {
    if (result.isEmpty) {
      showAppToast(context, '未提取到有效会话字段，请手动填写');
      return;
    }

    setState(() {
      if (result.name != null && result.name!.isNotEmpty) {
        _nameCtrl.text = result.name!;
      }
      if (result.gender != null) {
        _gender = GenderExt.fromString(result.gender);
      }
      if (result.age != null) {
        _ageCtrl.text = result.age.toString();
      }
      if (result.medicalRecordNumber != null &&
          result.medicalRecordNumber!.isNotEmpty) {
        _mrnCtrl.text = result.medicalRecordNumber!;
      }
      if (result.notes != null && result.notes!.isNotEmpty) {
        if (_notesCtrl.text.trim().isEmpty) {
          _notesCtrl.text = result.notes!;
        } else if (!_notesCtrl.text.contains(result.notes!)) {
          _notesCtrl.text = '${_notesCtrl.text.trim()}\n${result.notes!}';
        }
      }
      if (result.extraData.isNotEmpty) {
        _extraData = {..._extraData, ...result.extraData};
      }
    });

    showAppToast(context, '已自动识别填入信息，请核对保存');
  }

  Future<void> _extractFromSessionMessages() async {
    if (_sessionRawText.trim().isEmpty) {
      if (mounted) {
        showAppToast(context, '当前会话暂无文字内容可供提取');
      }
      return;
    }

    setState(() {
      _isExtracting = true;
      _extractingStatusText = '正在分析会话内容…';
    });
    await Future.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;

    try {
      final result = SessionAutofillService.extractLocally(_sessionRawText);
      _applyAutofillResult(result);
    } finally {
      if (mounted) {
        setState(() => _isExtracting = false);
      }
    }
  }

  Future<void> _startVoiceFill() async {
    final wavPath = await VoiceAutofillSheet.show(context);
    if (wavPath == null || !mounted) return;

    setState(() {
      _isExtracting = true;
      _extractingStatusText = '正在识别语音…';
    });

    try {
      final api = ref.read(apiServiceProvider);
      final transcribed = await api.transcribeAudio(wavPath);
      if (!mounted) return;
      if (transcribed.trim().isEmpty) {
        showAppToast(context, '未能识别到有效语音文字');
        return;
      }

      final result = SessionAutofillService.extractLocally(transcribed);
      _applyAutofillResult(result);
    } catch (e) {
      if (mounted) {
        showAppToast(context, '识别失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExtracting = false);
      }
      try {
        await File(wavPath).delete();
      } catch (_) {}
    }
  }

  Future<void> _startPhotoFill() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt_outlined),
              title: const Text('拍照'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('从相册选择'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source == null || !mounted) return;

    final imagePath = await AppImagePicker.pickSingleImage(source: source);
    if (imagePath == null || !mounted) return;

    setState(() {
      _isExtracting = true;
      _extractingStatusText = '正在本地识别图片…';
    });
    await Future.delayed(const Duration(milliseconds: 40));

    try {
      final ocrText =
          await SessionAutofillService.recognizeImageLocally(imagePath);
      if (!mounted) return;
      if (ocrText.trim().isEmpty) {
        showAppToast(context, '未能从图片中识别出文字');
        return;
      }

      final result = SessionAutofillService.extractLocally(ocrText);
      _applyAutofillResult(result);
    } catch (e) {
      if (mounted) {
        showAppToast(context, '图片识别失败: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isExtracting = false);
      }
    }
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final rawName = _nameCtrl.text.trim();
    final effectiveName = rawName.isEmpty ? widget.patient.name : rawName;
    final parsedAge = int.tryParse(_ageCtrl.text.trim());
    final mrn = _mrnCtrl.text.trim().isEmpty ? null : _mrnCtrl.text.trim();
    final notes =
        _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    final updated = widget.patient.copyWith(
      name: effectiveName,
      gender: _gender,
      age: parsedAge,
      clearAge: parsedAge == null,
      medicalRecordNumber: mrn,
      clearMrn: mrn == null,
      notes: notes,
      clearNotes: notes == null,
      extraData: _extraData,
    );

    await ref.read(patientRepositoryProvider).update(updated);
    ref.invalidate(patientProvider(widget.patient.id));
    ref.invalidate(patientsProvider);

    if (mounted) {
      Navigator.pop(context);
      showSuccessToast(context, '会话信息已更新');
    }
  }

  Widget? _buildExtractingSuffix() {
    if (!_isExtracting) return null;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 5),
          Text(
            '提取中',
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGenderSwitchRow(ColorScheme colorScheme) {
    final disabled = _isExtracting || _isSaving;

    Widget buildToggle(Gender target, String label, IconData icon) {
      final isSelected = _gender == target;
      return Expanded(
        child: Material(
          color: disabled
              ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.25)
              : isSelected
                  ? colorScheme.primaryContainer
                  : colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: disabled
                ? null
                : () {
                    setState(() {
                      _gender = isSelected ? Gender.unspecified : target;
                    });
                  },
            child: Container(
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: disabled
                      ? colorScheme.outlineVariant.withValues(alpha: 0.3)
                      : isSelected
                          ? colorScheme.primary
                          : colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: isSelected ? 1.5 : 1.0,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 17,
                    color: disabled
                        ? colorScheme.onSurfaceVariant.withValues(alpha: 0.38)
                        : isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w500,
                      color: disabled
                          ? colorScheme.onSurfaceVariant.withValues(alpha: 0.38)
                          : isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        buildToggle(Gender.male, '男', Icons.male_rounded),
        const SizedBox(width: 10),
        buildToggle(Gender.female, '女', Icons.female_rounded),
      ],
    );
  }

  Widget _buildSmartAutofillCard(
      ColorScheme colorScheme, bool hasSessionContent) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primaryContainer.withValues(alpha: 0.65),
            colorScheme.primaryContainer.withValues(alpha: 0.25),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.55),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: colorScheme.onPrimary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '智能自动填单',
                style: TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const Spacer(),
              if (_isExtracting)
                Row(
                  children: [
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _extractingStatusText,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _buildAutofillActionButton(
                  colorScheme: colorScheme,
                  icon: Icons.mic_rounded,
                  label: '语音识别',
                  onTap: _isExtracting ? null : _startVoiceFill,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAutofillActionButton(
                  colorScheme: colorScheme,
                  icon: Icons.camera_alt_rounded,
                  label: '图片识别',
                  onTap: _isExtracting ? null : _startPhotoFill,
                ),
              ),
            ],
          ),
          if (hasSessionContent) ...[
            const SizedBox(height: 10),
            _buildAutofillActionButton(
              colorScheme: colorScheme,
              icon: Icons.auto_fix_high_rounded,
              label: '根据会话内容一键补全',
              onTap: _isExtracting ? null : _extractFromSessionMessages,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAutofillActionButton({
    required ColorScheme colorScheme,
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    final disabled = onTap == null;
    return Material(
      color: disabled
          ? colorScheme.surface.withValues(alpha: 0.5)
          : colorScheme.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: disabled ? 0 : 1,
      shadowColor: colorScheme.primary.withValues(alpha: 0.2),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: disabled
                  ? colorScheme.outlineVariant.withValues(alpha: 0.3)
                  : colorScheme.primary.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 20,
                color: disabled
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                    : colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: disabled
                      ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                      : colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fieldsEnabled = !_isExtracting && !_isSaving;
    final hasSessionContent = _sessionRawText.trim().isNotEmpty;
    final hintNormalStyle = TextStyle(
      fontWeight: FontWeight.normal,
      fontSize: 13.5,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.badge_outlined, color: colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              const Text(
                '会话信息',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 22),
                tooltip: '关闭',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _buildSmartAutofillCard(colorScheme, hasSessionContent),
          const SizedBox(height: 14),
          TextField(
            controller: _nameCtrl,
            enabled: fieldsEnabled,
            style: _inputBoldStyle,
            decoration: InputDecoration(
              labelText: '名称 / 姓名',
              hintStyle: hintNormalStyle,
              suffixIcon: _buildExtractingSuffix(),
              suffixIconConstraints:
                  const BoxConstraints(minHeight: 20, minWidth: 20),
            ),
          ),
          const SizedBox(height: 12),
          _buildGenderSwitchRow(colorScheme),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 2,
                child: TextField(
                  controller: _ageCtrl,
                  enabled: fieldsEnabled,
                  style: _inputBoldStyle,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: '年龄',
                    hintStyle: hintNormalStyle,
                    suffixIcon: _buildExtractingSuffix(),
                    suffixIconConstraints:
                        const BoxConstraints(minHeight: 20, minWidth: 20),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _mrnCtrl,
                  enabled: fieldsEnabled,
                  style: _inputBoldStyle,
                  decoration: InputDecoration(
                    labelText: '编号 / 标识号',
                    hintStyle: hintNormalStyle,
                    suffixIcon: _buildExtractingSuffix(),
                    suffixIconConstraints:
                        const BoxConstraints(minHeight: 20, minWidth: 20),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notesCtrl,
            enabled: fieldsEnabled,
            style: _inputBoldStyle,
            maxLines: 2,
            decoration: InputDecoration(
              labelText: '备注',
              hintStyle: hintNormalStyle,
              suffixIcon: _buildExtractingSuffix(),
              suffixIconConstraints:
                  const BoxConstraints(minHeight: 20, minWidth: 20),
            ),
          ),
          if (_extraData.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _extraData.entries.map((e) {
                return Chip(
                  label: Text(
                    '${e.key}: ${e.value}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  visualDensity: VisualDensity.compact,
                  onDeleted: fieldsEnabled
                      ? () {
                          setState(() {
                            _extraData.remove(e.key);
                          });
                        }
                      : null,
                );
              }).toList(),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            height: 46,
            child: FilledButton(
              onPressed: fieldsEnabled ? _save : null,
              child: _isSaving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      '保存',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
