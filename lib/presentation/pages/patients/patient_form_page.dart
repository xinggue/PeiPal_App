import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/services/media/app_image_picker.dart';
import '../../../data/services/media/session_autofill_service.dart';
import '../../../domain/models/message.dart';
import '../../../domain/models/patient.dart';
import '../../../providers/providers.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/voice_autofill_sheet.dart';

class PatientFormPage extends ConsumerStatefulWidget {
  final String? patientId;
  final bool autoExtractFromSession;

  const PatientFormPage({
    super.key,
    this.patientId,
    this.autoExtractFromSession = false,
  });

  @override
  ConsumerState<PatientFormPage> createState() => _PatientFormPageState();
}

class _PatientFormPageState extends ConsumerState<PatientFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _ageCtrl = TextEditingController();
  final _mrnCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  Gender _gender = Gender.unspecified;
  PatientStatus _status = PatientStatus.active;
  bool _isLoading = false;
  bool _isEditing = false;
  bool _isExtracting = false;
  String _extractingStatusText = '';
  Map<String, dynamic> _extraData = {};
  String _sessionRawText = '';

  @override
  void initState() {
    super.initState();
    _isEditing = widget.patientId != null;
    if (_isEditing) {
      Future.microtask(_loadPatient);
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

  Future<void> _loadPatient() async {
    if (widget.patientId == null) return;
    final patientFuture =
        ref.read(patientRepositoryProvider).getById(widget.patientId!);
    final messagesFuture = ref
        .read(messageRepositoryProvider)
        .getByPatient(widget.patientId!, limit: 200);
    final results = await Future.wait([patientFuture, messagesFuture]);
    final patient = results[0] as Patient?;
    final messages = results[1] as List<Message>;
    final rawText = SessionAutofillService.collectRawTextFromMessages(messages);

    if (patient != null && mounted) {
      setState(() {
        _nameCtrl.text = patient.name;
        _gender = patient.gender;
        _ageCtrl.text = patient.age?.toString() ?? '';
        _status = patient.status;
        _mrnCtrl.text = patient.medicalRecordNumber ?? '';
        _notesCtrl.text = patient.notes ?? '';
        _extraData = Map<String, dynamic>.from(patient.extraData);
        _sessionRawText = rawText;
      });
      if (widget.autoExtractFromSession && rawText.trim().isNotEmpty) {
        await _startSessionContentFill();
      }
    }
  }

  Future<void> _startSessionContentFill() async {
    if (_sessionRawText.trim().isEmpty) return;
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

  String _generateDefaultSessionName() {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '会话 ${two(now.month)}-${two(now.day)} ${two(now.hour)}:${two(now.minute)}';
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
    // 让出一帧确保输入框变灰与转圈动画立即上屏渲染，再启动原生 OCR 线程
    await Future.delayed(const Duration(milliseconds: 40));

    try {
      final ocrText = await SessionAutofillService.recognizeImageLocally(imagePath);
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
      if (result.medicalRecordNumber != null && result.medicalRecordNumber!.isNotEmpty) {
        _mrnCtrl.text = result.medicalRecordNumber!;
      }
      if (result.notes != null && result.notes!.isNotEmpty) {
        if (_notesCtrl.text.trim().isEmpty) {
          _notesCtrl.text = result.notes!;
        } else {
          _notesCtrl.text = '${_notesCtrl.text.trim()}\n${result.notes!}';
        }
      }
      if (result.extraData.isNotEmpty) {
        _extraData = {..._extraData, ...result.extraData};
      }
    });

    showAppToast(context, '已自动识别填入信息，请核对保存');
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final repo = ref.read(patientRepositoryProvider);
    final rawName = _nameCtrl.text.trim();
    final effectiveName = rawName.isEmpty ? _generateDefaultSessionName() : rawName;
    final parsedAge = int.tryParse(_ageCtrl.text.trim());
    final mrn = _mrnCtrl.text.trim().isEmpty ? null : _mrnCtrl.text.trim();
    final notes = _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

    if (_isEditing && widget.patientId != null) {
      final existing = await repo.getById(widget.patientId!);
      if (existing != null) {
        await repo.update(existing.copyWith(
          name: effectiveName,
          gender: _gender,
          age: parsedAge,
          clearAge: parsedAge == null,
          medicalRecordNumber: mrn,
          clearMrn: mrn == null,
          notes: notes,
          clearNotes: notes == null,
          status: _status,
          extraData: _extraData,
        ));
      }
    } else {
      final newPatient = Patient(
        name: effectiveName,
        gender: _gender,
        age: parsedAge,
        medicalRecordNumber: mrn,
        notes: notes,
        status: _status,
        extraData: _extraData,
      );
      await repo.insert(newPatient);
      ref.invalidate(patientsProvider);
      if (mounted) {
        context.pushReplacement('/patients/${newPatient.id}/chat');
      }
      return;
    }

    ref.invalidate(patientsProvider);
    if (widget.patientId != null) {
      ref.invalidate(patientProvider(widget.patientId!));
      ref.invalidate(lastMessageProvider(widget.patientId!));
      ref.invalidate(messagesProvider(widget.patientId!));
    }
    if (mounted) context.pop();
  }

  static const _inputBoldStyle = TextStyle(
    fontWeight: FontWeight.bold,
    fontSize: 15.5,
  );

  Widget? _buildExtractingSuffix() {
    if (!_isExtracting) return null;
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 6),
          Text(
            '提取中',
            style: TextStyle(
              fontSize: 11.5,
              color: colorScheme.primary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmartAutofillCard(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
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
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '推荐免手填',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
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
          if (_sessionRawText.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            _buildAutofillActionButton(
              colorScheme: colorScheme,
              icon: Icons.auto_fix_high_rounded,
              label: '根据会话内容补全',
              onTap: _isExtracting ? null : _startSessionContentFill,
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

  Widget _buildGenderSwitchRow(ColorScheme colorScheme) {
    final disabled = _isExtracting || _isLoading;

    Widget buildGenderToggle(Gender target, String label, IconData icon) {
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
                      // 点击已选中的按钮则取消选中（恢复为 unspecified），否则选中该项
                      _gender = isSelected ? Gender.unspecified : target;
                    });
                  },
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: disabled
                      ? colorScheme.outlineVariant.withValues(alpha: 0.3)
                      : isSelected
                          ? colorScheme.primary
                          : colorScheme.outlineVariant.withValues(alpha: 0.5),
                  width: isSelected ? 1.6 : 1.0,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 18,
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
                      fontSize: 15,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '性别 (选填)',
              style: TextStyle(
                fontSize: 12.5,
                color: disabled
                    ? colorScheme.onSurfaceVariant.withValues(alpha: 0.4)
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            if (_isExtracting) ...[
              const Spacer(),
              const SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(strokeWidth: 1.8),
              ),
              const SizedBox(width: 6),
              Text(
                '提取中',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            buildGenderToggle(Gender.male, '男', Icons.male_rounded),
            const SizedBox(width: 12),
            buildGenderToggle(Gender.female, '女', Icons.female_rounded),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final fieldsEnabled = !_isExtracting && !_isLoading;
    final hintNormalStyle = TextStyle(
      fontWeight: FontWeight.normal,
      fontSize: 14,
      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '编辑会话信息' : '新建会话'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _buildSmartAutofillCard(colorScheme),
            TextFormField(
              controller: _nameCtrl,
              enabled: fieldsEnabled,
              style: _inputBoldStyle,
              decoration: InputDecoration(
                labelText: '名称 / 姓名 (选填)',
                hintText: '留空将自动按当前时间命名会话',
                hintStyle: hintNormalStyle,
                border: const OutlineInputBorder(),
                suffixIcon: _buildExtractingSuffix(),
                suffixIconConstraints:
                    const BoxConstraints(minHeight: 20, minWidth: 20),
              ),
            ),
            const SizedBox(height: 16),
            _buildGenderSwitchRow(colorScheme),
            const SizedBox(height: 16),
            TextFormField(
              controller: _ageCtrl,
              enabled: fieldsEnabled,
              style: _inputBoldStyle,
              decoration: InputDecoration(
                labelText: '年龄 (选填)',
                hintStyle: hintNormalStyle,
                border: const OutlineInputBorder(),
                suffixIcon: _buildExtractingSuffix(),
                suffixIconConstraints:
                    const BoxConstraints(minHeight: 20, minWidth: 20),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _mrnCtrl,
              enabled: fieldsEnabled,
              style: _inputBoldStyle,
              decoration: InputDecoration(
                labelText: '编号 / 标识号 (选填)',
                hintStyle: hintNormalStyle,
                border: const OutlineInputBorder(),
                suffixIcon: _buildExtractingSuffix(),
                suffixIconConstraints:
                    const BoxConstraints(minHeight: 20, minWidth: 20),
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _notesCtrl,
              enabled: fieldsEnabled,
              style: _inputBoldStyle,
              decoration: InputDecoration(
                labelText: '备注 (选填)',
                hintText: '可填写分类、部门或背景说明等信息',
                hintStyle: hintNormalStyle,
                border: const OutlineInputBorder(),
                suffixIcon: _buildExtractingSuffix(),
                suffixIconConstraints:
                    const BoxConstraints(minHeight: 20, minWidth: 20),
              ),
              maxLines: 3,
            ),
            if (_extraData.isNotEmpty) ...[
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '附加提取信息 (${_extraData.length})：',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(height: 6),
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
            const SizedBox(height: 24),
            SizedBox(
              height: 48,
              child: FilledButton(
                onPressed: fieldsEnabled ? _save : null,
                child: (_isLoading || _isExtracting)
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        _isEditing ? '保存修改' : '创建会话',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15.5,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
