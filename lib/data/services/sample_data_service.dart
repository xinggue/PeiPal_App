import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/content_template.dart';
import '../../domain/models/message.dart';
import '../../domain/models/patient.dart';
import '../../domain/models/template.dart';
import '../repositories/content_template_repository.dart';
import '../repositories/message_repository.dart';
import '../repositories/patient_repository.dart';
import '../repositories/settings_repository.dart';
import '../repositories/template_repository.dart';
import 'media/media_storage.dart';

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
  static const String currentSampleVersion = '7';

  final PatientRepository patientRepo;
  final MessageRepository messageRepo;
  final TemplateRepository templateRepo;
  final ContentTemplateRepository contentTemplateRepo;
  final SettingsRepository settingsRepo;
  final bool seedMedia;

  SampleDataService({
    required this.patientRepo,
    required this.messageRepo,
    required this.templateRepo,
    required this.contentTemplateRepo,
    required this.settingsRepo,
    this.seedMedia = true,
  });

  /// 检查并在首次运行时注入示例模板、示例会话与示例消息。
  ///
  /// 示例内容为一份真实的结肠息肉内镜与病理材料，用于演示完整整理流程。
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
    if (seedMedia) {
      try {
        await MediaStorage.deletePatientMedia(samplePatientId);
      } catch (_) {}
    }
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
    if (existing != null) {
      // 检查已存的内置示例模板是否仍包含旧版 {TAB}，若是则平滑升级为 {ENTER}
      final hasTab = existing.slots.any((s) => s.postKeys.contains('{TAB}'));
      if (hasTab) {
        final updatedSlots = existing.slots.map((s) {
          final updatedPostKeys = s.postKeys.map((k) => k == '{TAB}' ? '{ENTER}' : k).toList();
          return s.copyWith(postKeys: updatedPostKeys);
        }).toList();
        await templateRepo.update(existing.copyWith(slots: updatedSlots));
      }
      return;
    }

    final templates = await templateRepo.getAll();
    if (templates.isNotEmpty) {
      // 用户已有自己的模板，就不再注入默认示例模板，但仍会创建示例会话。
      return;
    }

    final sampleTemplate = Template(
      id: sampleTemplateId,
      name: '示例病史',
      version: '1.0',
      slots: const [
        TemplateSlot(
          key: '主诉',
          label: '主诉',
          type: SlotType.text,
          postKeys: ['{ENTER}'],
          order: 0,
        ),
        TemplateSlot(
          key: '现病史',
          label: '现病史',
          type: SlotType.text,
          postKeys: ['{ENTER}'],
          order: 1,
        ),
        TemplateSlot(
          key: '既往史',
          label: '既往史',
          type: SlotType.text,
          postKeys: ['{ENTER}'],
          order: 2,
        ),
        TemplateSlot(
          key: '辅检',
          label: '辅检',
          type: SlotType.text,
          postKeys: ['{ENTER}'],
          order: 3,
        ),
        TemplateSlot(
          key: '查体',
          label: '专科查体',
          type: SlotType.text,
          postKeys: ['{ENTER}'],
          order: 4,
        ),
        TemplateSlot(
          key: '诊断',
          label: '诊断',
          type: SlotType.text,
          postKeys: ['{ENTER}'],
          order: 5,
          catalogType: 'diagnosis',
        ),
        TemplateSlot(
          key: '诊断依据',
          label: '诊断依据',
          type: SlotType.text,
          postKeys: ['{ENTER}'],
          order: 6,
        ),
        TemplateSlot(
          key: '诊疗计划',
          label: '诊疗计划',
          type: SlotType.text,
          postKeys: ['{ENTER}'],
          order: 7,
        ),
      ],
    );

    await templateRepo.insert(sampleTemplate);

    final sampleCt = ContentTemplate(
      id: sampleContentTemplateId,
      structureTemplateId: sampleTemplateId,
      name: '通用模板',
      globalGuidance: '',
      fullExample: '',
      slots: const {
        '主诉': SlotContent(
          guidance:
              '一句话概括主要症状或体征及持续时间，句末用句号；时间用阿拉伯数字直接加时间单位（如2天、3月、半年余），不写汉字数字加量词再跟时间单位；一般最多体现两个主要矛盾；慢性病控制不佳或急性加重从最初发病时间写起。',
        ),
        '现病史': SlotContent(
          guidance:
              '按时间顺序写明发病时间、诱因、主要症状特点、伴随症状及有鉴别意义的阴性症状；既往诊疗经过只提炼关键检查、处理及反应；写明目前病情变化；结尾写“现为求进一步诊治，收治我科病房”，已有明确诊断可写拟“XX诊断”收治我科病房；按实际病种选择症状和阴性描述。',
        ),
        '既往史': SlotContent(
          guidance:
              '按模板要求合并记录平素健康状况（良好/一般/较差）、既往疾病史（慢性病写明病程、关键病情或最高指标、用药及控制情况；若与现病史为同一疾病则写详见现病史）。',
        ),
        '辅检': SlotContent(
          guidance:
              '按照时间、范围、标题、编号、内容，整理罗列所有的辅助检查内容，包括检验，影像，病理，功能学检查等。日期按报告日期，不要申请日期或送检日期，如果没有确切日期，只提供年或者月也可。编号取影像号或者病理号等最有意义的标识符，不要住院号或者排队号等等，如果没有可以略过。最后按照2026.10.01 北京市第一人民医院 胸部CT 影像号123abc 具体内容 的方式整理好，日期从旧到新，旧的先汇报，新的后汇报。除非特别指明，不需要汇报影像的所见，只汇报诊断或者印象或者结论即可。',
        ),
        '查体': SlotContent(
          examples: [
            '神志清，对答清楚，呼吸平稳，口齿清楚。双侧瞳孔等大等圆，对光反应正常。全身皮肤黏膜无黄染。心率63次/分，律齐，未闻及病理性杂音。双肺呼吸音清，未及啰音。腹软，无压痛、反跳痛，肝脾肋下未及。双下肢不肿，四肢肌力V级，肌张力正常。生理反射存在，病理反射未引出。',
          ],
          guidance:
              '写专科查体，围绕主诉、诊断及鉴别诊断选择相应系统或专科检查内容，记录阳性体征和有鉴别意义的阴性体征；一般情况和生命体征按模板要求记录。',
        ),
        '诊断': SlotContent(
          guidance:
              '分条列出诊断，使用连续编号，用逗号分隔；必须从标准库选择符合的诊断，不在标准库提供的诊断原则上不录入，除非有仍成立的既往出院诊断；按主要诊断、与主诉或主要疾病最相关诊断、其他疾病重要程度排序。',
        ),
        '诊断依据': SlotContent(
          guidance:
              '按诊断逐条对应，使用与诊断字段一致的编号；主要疾病及其并发症或合并症的依据可集中描述，其他疾病依据集中描述；依据包括关键病史、专科查体、辅检阳性结果及有鉴别意义的阴性结果；提炼支撑点，避免整段复制现病史和辅检。',
        ),
        '诊疗计划': SlotContent(
          guidance:
              '根据诊断、病情及合并症制定个体化计划，分条列出：完善必要检查以明确诊断和评估病情及并发症；一般治疗、病因或对症治疗及药物方案（剂量、途径、调整依据）；监测和观察指标；护理、饮食、生活方式及健康教育按病种安排；需会诊、转科、手术或介入等注明。按实际病种调整。',
        ),
      },
    );
    await contentTemplateRepo.insert(sampleCt);
  }

  Future<void> _seedSamplePatientAndMessages() async {
    final existing = await patientRepo.getById(samplePatientId);
    if (existing != null) {
      final msgs = await messageRepo.getAllChronological(samplePatientId);
      if (msgs.length == 4 && msgs.first.type == MessageType.text) {
        final photos = msgs.where((m) => m.type == MessageType.photo).toList();
        final texts = msgs.where((m) => m.type == MessageType.text).toList();
        if (photos.length == 2 && texts.length == 2) {
          final base = existing.createdAt;
          await messageRepo.update(photos[0].copyWith(createdAt: base.add(const Duration(minutes: 5))));
          await messageRepo.update(photos[1].copyWith(createdAt: base.add(const Duration(minutes: 10))));
          await messageRepo.update(texts[0].copyWith(createdAt: base.add(const Duration(minutes: 15))));
          await messageRepo.update(texts[1].copyWith(createdAt: base.add(const Duration(minutes: 20))));
        }
      }
      return;
    }

    final now = DateTime.now();
    final patient = Patient(
      id: samplePatientId,
      name: '示例会话',
      notes: '结肠息肉内镜与病理示例',
      status: PatientStatus.active,
      createdAt: now.subtract(const Duration(minutes: 30)),
      updatedAt: now,
    );
    await patientRepo.insert(patient);

    // 1. 肠镜检查报告（内置真实示例图片，图在前）
    final colonoscopyDraft = Message(
      patientId: samplePatientId,
      sender: MessageSender.user,
      type: MessageType.photo,
      content: '肠镜检查报告',
      extractedText: '主诉:\n'
          '临床诊断:直肠息肉\n'
          '术前用药:\n'
          '镜下所见:\n'
          '进镜情况:肠道准备差.腔内可见较多粪水,影响部分观察.结肠镜顺利插至回肠末\n'
          '端,粘膜绒毛状.回盲瓣呈唇形,阑尾内口光滑.\n'
          '所见结肠及直肠:横结肠可见散在多枚大小约4-5mm广基息肉,表面充血,乙降交\n'
          '界以远直肠可见散在多发3-4mm扁平息肉,余所见黏膜呈桔红色,光滑湿润,有光\n'
          '泽.黏膜血管纹理呈树枝状,清晰可见.\n'
          '内镜诊断：\n'
          '结直肠多发息肉',
      createdAt: now.subtract(const Duration(minutes: 25)),
    );
    final colonoscopy = await _materializeAsset(
      assetPath: 'assets/sample/sample_colonoscopy.jpg',
      resolveDestPath: () async {
        final dir =
            await MediaStorage.photoDir(samplePatientId, colonoscopyDraft.id);
        return p.join(dir, 'page_001.jpg');
      },
    );
    final m1 = colonoscopy == null
        ? colonoscopyDraft
        : colonoscopyDraft.copyWith(
            filePaths: [colonoscopy.path],
            fileSizes: [colonoscopy.size],
          );

    // 2. 病理检查报告（内置真实示例图片，图在前）
    final pathologyDraft = Message(
      patientId: samplePatientId,
      sender: MessageSender.user,
      type: MessageType.photo,
      content: '病理检查报告',
      extractedText: '送检材料：乙状结肠息肉送\n'
          '临床诊断：乙状结肠息肉性质待查\n'
          '镜下所见：\n'
          '病理诊断：\n'
          '(乙状结肠粘膜）腺瘤性息肉，部分腺体呈低级别上皮内瘤变.',
      createdAt: now.subtract(const Duration(minutes: 20)),
    );
    final pathology = await _materializeAsset(
      assetPath: 'assets/sample/sample_pathology.jpg',
      resolveDestPath: () async {
        final dir =
            await MediaStorage.photoDir(samplePatientId, pathologyDraft.id);
        return p.join(dir, 'page_001.jpg');
      },
    );
    final m2 = pathology == null
        ? pathologyDraft
        : pathologyDraft.copyWith(
            filePaths: [pathology.path],
            fileSizes: [pathology.size],
          );

    // 3. 聊天记录：就诊目的（文字在后）
    final m3 = Message(
      patientId: samplePatientId,
      sender: MessageSender.user,
      type: MessageType.text,
      content: '来摘息肉的，没什么不舒服，一个月前做的肠镜和病理，都做好的',
      createdAt: now.subtract(const Duration(minutes: 12)),
    );

    // 4. 聊天记录：既往史与用药（文字在后）
    final m4 = Message(
      patientId: samplePatientId,
      sender: MessageSender.user,
      type: MessageType.text,
      content: '有冠心病，吃阿司匹林和阿托伐，阿司匹林停6天了',
      createdAt: now.subtract(const Duration(minutes: 6)),
    );

    await messageRepo.insert(m1);
    await messageRepo.insert(m2);
    await messageRepo.insert(m3);
    await messageRepo.insert(m4);
  }

  /// 把打包进 assets 的示例媒体复制到应用媒体目录，供语音/图片组件正常打开。
  Future<({String path, int size})?> _materializeAsset({
    required String assetPath,
    required Future<String> Function() resolveDestPath,
  }) async {
    if (!seedMedia) return null;
    try {
      final data = await rootBundle.load(assetPath);
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final path = await resolveDestPath();
      await File(path).writeAsBytes(bytes, flush: true);
      return (path: path, size: bytes.length);
    } catch (e) {
      debugPrint('示例媒体写入失败($assetPath): $e');
      return null;
    }
  }
}
