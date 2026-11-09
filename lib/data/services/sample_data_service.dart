import 'package:flutter/foundation.dart';
import '../../domain/models/content_template.dart';
import '../../domain/models/message.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/template.dart';
import '../repositories/content_template_repository.dart';
import '../repositories/message_repository.dart';
import '../repositories/patient_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/template_repository.dart';

class SampleDataService {
  static const String samplePatientId = 'sample_patient_demo';
  static const String sampleTemplateId = 'tpl_sample_generic';
  static const String sampleContentTemplateId = 'ctpl_sample_generic';
  // 早期版本使用过的医疗化示例 ID，升级时一并清理。
  static const List<String> _legacyTemplateIds = [
    'tpl_sample_admission',
  ];
  static const List<String> _legacyContentTemplateIds = [
    'ctpl_sample_admission',
  ];
  static const String keySampleSeeded = 'sample_patient_seeded';
  static const String keySampleVersion = 'sample_data_version';
  static const String currentSampleVersion = '2';

  final PatientRepository patientRepo;
  final MessageRepository messageRepo;
  final TemplateRepository templateRepo;
  final ContentTemplateRepository contentTemplateRepo;
  final SettingsRepository settingsRepo;

  SampleDataService({
    required this.patientRepo,
    required this.messageRepo,
    required this.templateRepo,
    required this.contentTemplateRepo,
    required this.settingsRepo,
  });

  /// 检查并在首次运行时注入示例模板、示例会话与示例消息。
  ///
  /// 示例内容刻意保持通用（仅涉及信息、对话与材料），不绑定具体行业。
  Future<void> ensureSampleData({bool force = false}) async {
    try {
      final version = await settingsRepo.get(keySampleVersion);
      final seeded = await settingsRepo.get(keySampleSeeded);
      if (version == currentSampleVersion && seeded == 'true' && !force) {
        return;
      }

      // 旧版本示例或手动重走教程时，先清理旧的示例数据，避免残留。
      if (version != currentSampleVersion || force) {
        await _cleanupSampleData();
      }

      await _seedSampleTemplateIfNeeded();
      await _seedSamplePatientAndMessages();

      await settingsRepo.set(keySampleSeeded, 'true');
      await settingsRepo.set(keySampleVersion, currentSampleVersion);
    } catch (e, st) {
      debugPrint('初始化示例数据失败: $e\n$st');
    }
  }

  Future<void> _cleanupSampleData() async {
    try {
      await patientRepo.delete(samplePatientId);
    } catch (_) {}
    try {
      await contentTemplateRepo.delete(sampleContentTemplateId);
    } catch (_) {}
    try {
      await templateRepo.delete(sampleTemplateId);
    } catch (_) {}
    for (final id in _legacyContentTemplateIds) {
      try {
        await contentTemplateRepo.delete(id);
      } catch (_) {}
    }
    for (final id in _legacyTemplateIds) {
      try {
        await templateRepo.delete(id);
      } catch (_) {}
    }
  }

  Future<void> _seedSampleTemplateIfNeeded() async {
    final existing = await templateRepo.getById(sampleTemplateId);
    if (existing != null) return;

    final templates = await templateRepo.getAll();
    if (templates.isNotEmpty) {
      // 用户已有自己的模板，就不再注入默认示例模板，但仍会创建示例会话。
      return;
    }

    final sampleTemplate = Template(
      id: sampleTemplateId,
      name: '信息整理记录',
      version: '1.0.0',
      slots: const [
        TemplateSlot(
          key: 'topic',
          label: '主题',
          type: SlotType.text,
          required: true,
          order: 0,
        ),
        TemplateSlot(
          key: 'key_points',
          label: '关键信息',
          type: SlotType.multiline,
          required: true,
          order: 1,
        ),
        TemplateSlot(
          key: 'todos',
          label: '待办事项',
          type: SlotType.multiline,
          order: 2,
        ),
        TemplateSlot(
          key: 'summary',
          label: '结论',
          type: SlotType.multiline,
          order: 3,
        ),
      ],
    );

    await templateRepo.insert(sampleTemplate);

    final sampleCt = ContentTemplate(
      id: sampleContentTemplateId,
      structureTemplateId: sampleTemplateId,
      name: '标准信息整理',
      globalGuidance: '请从对话与材料中提炼关键信息，语言简洁、条理清晰。',
      fullExample: '',
    );
    await contentTemplateRepo.insert(sampleCt);
  }

  Future<void> _seedSamplePatientAndMessages() async {
    final existing = await patientRepo.getById(samplePatientId);
    if (existing != null) {
      return;
    }

    final now = DateTime.now();
    final patient = Patient(
      id: samplePatientId,
      name: '示例会话',
      notes: '用于演示信息与对话整理的新手示例',
      status: PatientStatus.active,
      createdAt: now.subtract(const Duration(minutes: 30)),
      updatedAt: now,
    );
    await patientRepo.insert(patient);

    // 1. 文字信息
    final m1 = Message(
      patientId: samplePatientId,
      sender: MessageSender.user,
      type: MessageType.text,
      content:
          '这是一段示例文字信息：项目已于本周二正式启动，负责人是李工，计划下个月交付初稿。',
      createdAt: now.subtract(const Duration(minutes: 25)),
    );

    // 2. 语音转写信息
    final m2 = Message(
      patientId: samplePatientId,
      sender: MessageSender.user,
      type: MessageType.voice,
      content: '示例录音',
      durationMs: 12000,
      transcribedText:
          '再补充一点：客户希望重点突出安全性和稳定性，预算控制在五十万以内。',
      createdAt: now.subtract(const Duration(minutes: 18)),
    );

    // 3. 图片识别材料
    final m3 = Message(
      patientId: samplePatientId,
      sender: MessageSender.user,
      type: MessageType.photo,
      content: '示例图片材料',
      extractedText:
          '会议纪要：\n1. 明确交付时间；\n2. 确认预算范围；\n3. 下周同步最新进展。',
      createdAt: now.subtract(const Duration(minutes: 10)),
    );

    await messageRepo.insert(m1);
    await messageRepo.insert(m2);
    await messageRepo.insert(m3);
  }
}
