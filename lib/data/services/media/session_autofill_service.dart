import 'dart:convert';
import 'dart:io';

import '../../../domain/models/message.dart';
import '../api/api_service.dart';
import 'apple_vision_ocr.dart';
import 'ocr_image_optimizer.dart';
import 'paddle_local_ocr.dart';

class SessionAutofillResult {
  final String? name;
  final String? gender;
  final int? age;
  final String? medicalRecordNumber;
  final String? notes;
  final Map<String, dynamic> extraData;
  final String rawText;

  const SessionAutofillResult({
    this.name,
    this.gender,
    this.age,
    this.medicalRecordNumber,
    this.notes,
    this.extraData = const {},
    this.rawText = '',
  });

  bool get isEmpty =>
      (name == null || name!.isEmpty) &&
      (gender == null || gender!.isEmpty) &&
      age == null &&
      (medicalRecordNumber == null || medicalRecordNumber!.isEmpty) &&
      (notes == null || notes!.isEmpty) &&
      extraData.isEmpty;
}

class SessionAutofillService {
  // 常见百家姓（单姓）集合，用于无标签时的姓名启发式识别
  static const Set<String> _commonSurnames = {
    '王', '李', '张', '刘', '陈', '杨', '黄', '赵', '吴', '周',
    '徐', '孙', '马', '朱', '胡', '郭', '何', '高', '林', '罗',
    '郑', '梁', '谢', '宋', '唐', '许', '韩', '冯', '邓', '曹',
    '彭', '曾', '肖', '田', '董', '袁', '潘', '于', '蒋', '蔡',
    '余', '杜', '叶', '程', '苏', '魏', '吕', '丁', '任', '沈',
    '姚', '卢', '姜', '崔', '钟', '谭', '陆', '汪', '范', '金',
    '石', '廖', '贾', '夏', '韦', '付', '方', '白', '邹', '孟',
    '熊', '秦', '邱', '江', '尹', '薛', '闫', '段', '雷', '侯',
    '龙', '史', '陶', '黎', '贺', '顾', '毛', '郝', '龚', '邵',
    '万', '钱', '严', '覃', '武', '戴', '莫', '孔', '向', '汤',
    '庞', '樊', '兰', '殷', '施', '洪', '翟', '安', '颜', '倪',
    '牛', '温', '芦', '季', '俞', '章', '鲁', '葛', '伍', '申',
    '尤', '毕', '聂', '丛', '焦', '柳', '邢', '路', '岳', '齐',
    '沿', '梅', '庄', '辛', '管', '祝', '左', '涂', '谷', '祁',
    '时', '舒', '耿', '牟', '卜', '詹', '关', '苗', '凌', '费',
    '纪', '靳', '盛', '童', '欧', '甄', '项', '曲', '成', '游',
    '阳', '裴', '席', '卫', '查', '屈', '鲍', '位', '霍', '翁',
    '隋', '植', '甘', '景', '薄', '单', '包', '司', '柏', '宁',
    '柯', '阮', '桂', '闵', '解', '强', '柴', '华', '车', '冉',
    '房', '边',
  };

  static const List<String> _compoundSurnames = [
    '欧阳', '太史', '端木', '上官', '司马', '东方', '独孤', '南宫',
    '万俟', '闻人', '夏侯', '诸葛', '尉迟', '公羊', '赫连', '澹台',
    '皇甫', '宗政', '濮阳', '公冶', '太叔', '申屠', '公孙', '慕容',
    '仲孙', '钟离', '长孙', '宇文', '司徒', '鲜于', '司空', '闾丘',
  ];

  // 非人名常见词汇黑名单（防止把医院/科室/症状词误判为人名）
  static const Set<String> _nonNameWords = {
    '姓名', '患者', '病人', '性别', '年龄', '科室', '科别', '病区', '床号', '床位',
    '住院', '门诊', '急诊', '病历', '病案', '编号', '登记', '档案', '卡号', '电话',
    '手机', '联系', '主诉', '诊断', '初步', '入院', '出院', '临床', '病情', '症状',
    '备注', '病史', '医院', '中心', '人民', '第一', '第二', '第三', '第四', '第五',
    '附属', '医科大学', '内科', '外科', '骨科', '儿科', '妇科', '产科', '妇产', '肿瘤',
    '神经', '心内', '呼吸', '消化', '内分泌', '肾内', '血液', '风湿', '免疫', '感染',
    '康复', '重症', '医学', '五官', '眼科', '口腔', '皮肤', '泌尿', '胸外', '神外',
    '普外', '肝胆', '胃肠', '甲乳', '血管', '烧伤', '整形', '麻醉', '急诊科', '检验',
    '放射', '超声', '病理', '药剂', '体检', '护士', '医师', '医生', '主任', '主治',
    '高血', '血压', '糖尿', '尿病', '冠心', '心脏', '脑梗', '肺炎', '支气', '气管',
    '哮喘', '胃炎', '溃疡', '肝炎', '肝硬', '肾炎', '肾衰', '骨折', '外伤', '发热',
    '咳嗽', '胸闷', '气短', '胸痛', '腹痛', '腹泻', '头晕', '头痛', '恶心', '呕吐',
    '乏力', '水肿', '失眠', '纳差', '不适', '入院时', '患者于', '无明显', '诱因',
    '女性', '男性', '男患', '女患', '周岁', '结果', '来自', '本地', '识别', '时间',
    '日期', '记录', '签名', '审核', '打印', '页码', '合计', '金额', '费用', '医保',
    '自费', '居民', '职工', '慢性', '急性', '亚急', '综合征', '综合', '手术', '治疗',
  };

  /// 从会话的消息列表中汇总所有可用的原始文本（文字消息、语音转写、图片OCR、文档文本及已生成文书字段）
  static String collectRawTextFromMessages(List<Message> messages) {
    if (messages.isEmpty) return '';
    final sorted = List<Message>.from(messages)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    final parts = <String>[];
    for (final m in sorted) {
      switch (m.type) {
        case MessageType.text:
          final c = m.content?.trim() ?? '';
          if (c.isNotEmpty) parts.add(c);
          break;
        case MessageType.voice:
        case MessageType.asrResult:
          final t = m.transcribedText?.trim() ?? '';
          if (t.isNotEmpty &&
              !t.startsWith('语音识别失败') &&
              !t.startsWith('识别失败')) {
            parts.add(t);
          }
          break;
        case MessageType.photo:
        case MessageType.ocrResult:
        case MessageType.document:
          final e = m.extractedText?.trim() ?? '';
          if (e.isNotEmpty &&
              !e.startsWith('图片识别失败') &&
              !e.startsWith('文件提取失败')) {
            parts.add(e);
          }
          break;
        case MessageType.generatedRecord:
          final r = m.recordJson?.trim() ?? '';
          if (r.isNotEmpty) {
            try {
              final map = jsonDecode(r);
              if (map is Map) {
                for (final entry in map.entries) {
                  final v = entry.value?.toString().trim() ?? '';
                  if (v.isNotEmpty) {
                    parts.add('${entry.key}: $v');
                  }
                }
              }
            } catch (_) {}
          }
          break;
      }
    }
    return parts.join('\n');
  }

  /// 直接从会话消息列表中提取会话信息
  static SessionAutofillResult extractFromMessages(List<Message> messages) {
    final raw = collectRawTextFromMessages(messages);
    if (raw.isEmpty) return const SessionAutofillResult();
    return extractLocally(raw);
  }

  /// 强制使用本地离线 OCR 识别图片文字（Android 走 PaddleLocalOcr，iOS/macOS 走 AppleVisionOcr）
  static Future<String> recognizeImageLocally(String imagePath) async {
    final optimizedPaths = await OcrImageOptimizer.prepareForOcr([imagePath]);
    try {
      if (Platform.isIOS || Platform.isMacOS) {
        return await AppleVisionOcr.recognize(optimizedPaths);
      }
      return await PaddleLocalOcr.recognize(optimizedPaths);
    } finally {
      await OcrImageOptimizer.cleanPreparedFiles(optimizedPaths, [imagePath]);
    }
  }

  /// 纯本地毫秒级规则+启发式提取（无需联网调 LLM，零延迟）
  static SessionAutofillResult extractLocally(String rawText) {
    var text = _normalizeText(rawText);
    if (text.isEmpty) {
      return const SessionAutofillResult();
    }

    String? gender = _extractGender(text);
    int? age = _extractAge(text);
    String? mrn = _extractMrn(text);
    final extraData = _extractExtraData(text);
    String? name = _extractName(text);
    String? notes = _extractNotes(
      text,
      name: name,
      age: age,
      mrn: mrn,
      extraData: extraData,
    );

    return SessionAutofillResult(
      name: name,
      gender: gender,
      age: age,
      medicalRecordNumber: mrn,
      notes: notes,
      extraData: extraData,
      rawText: text,
    );
  }

  static String _normalizeText(String input) {
    var s = input
        .replaceAll('结果来自 PaddleOCR 本地', '')
        .replaceAll('结果来自 Apple Vision', '')
        .replaceAll('：', ':')
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll('，', ',');

    // 全角数字转半角
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      final code = s.codeUnitAt(i);
      if (code >= 0xFF10 && code <= 0xFF19) {
        buf.writeCharCode(code - 0xFF10 + 0x30);
      } else {
        buf.writeCharCode(code);
      }
    }
    return buf.toString().trim();
  }

  static String? _extractGender(String text) {
    // 1. 显式标签：性别: 男 / 女
    final labelMatch = RegExp(r'性别\s*[:\s]\s*(男|女)').firstMatch(text);
    if (labelMatch != null) {
      return labelMatch.group(1) == '男' ? 'male' : 'female';
    }

    // 2. 明确称谓或词组
    if (RegExp(r'(男性|男患|先生|大爷|老大爷|小伙)').hasMatch(text)) {
      return 'male';
    }
    if (RegExp(r'(女性|女患|女士|阿姨|大妈|老太太|姑娘|孕妇)').hasMatch(text)) {
      return 'female';
    }

    // 3. 独立单字“男”或“女”（前后不连其他易混汉字）
    final standalone = RegExp(
      r'(?<![\u4e00-\u9fa5])(男|女)(?![\u4e00-\u9fa5])',
    ).firstMatch(text);
    if (standalone != null) {
      return standalone.group(1) == '男' ? 'male' : 'female';
    }

    // 4. 常见连写如“男45岁”、“女,60岁”
    final adjacent = RegExp(r'(男|女)\s*[,，/]?\s*\d{1,3}\s*岁').firstMatch(text);
    if (adjacent != null) {
      return adjacent.group(1) == '男' ? 'male' : 'female';
    }

    return null;
  }

  static int? _extractAge(String text) {
    // 1. 显式标签：年龄: 45 / 年龄 45岁
    final labelMatch =
        RegExp(r'年龄\s*[:\s]\s*(\d{1,3})\s*(?:岁|周岁)?').firstMatch(text);
    if (labelMatch != null) {
      final v = int.tryParse(labelMatch.group(1)!);
      if (v != null && v >= 0 && v <= 130) return v;
    }

    // 2. 阿拉伯数字 + 岁 / 周岁
    for (final m in RegExp(r'(?<!\d)(\d{1,3})\s*(?:岁|周岁)').allMatches(text)) {
      final v = int.tryParse(m.group(1)!);
      if (v != null && v >= 1 && v <= 130) return v;
    }

    // 3. 中文数字 + 岁（常用于语音 ASR，如“六十五岁”、“三十八岁”）
    final cnMatch = RegExp(
      r'([一二三四五六七八九十百零两]{1,4})\s*(?:岁|周岁)',
    ).firstMatch(text);
    if (cnMatch != null) {
      final v = parseChineseNumber(cnMatch.group(1)!);
      if (v != null && v >= 1 && v <= 130) return v;
    }

    // 4. 出生年份推算：19xx年出生 / 生于19xx年
    final birthMatch = RegExp(
      r'(?:出生[^\d]{0,3}|生于\s*)(19\d{2}|20[0-2]\d)\s*年',
    ).firstMatch(text);
    if (birthMatch != null) {
      final birthYear = int.tryParse(birthMatch.group(1)!);
      if (birthYear != null) {
        final age = DateTime.now().year - birthYear;
        if (age >= 0 && age <= 130) return age;
      }
    }

    return null;
  }

  static int? parseChineseNumber(String cn) {
    const digits = {
      '零': 0,
      '一': 1,
      '二': 2,
      '两': 2,
      '三': 3,
      '四': 4,
      '五': 5,
      '六': 6,
      '七': 7,
      '八': 8,
      '九': 9,
    };

    if (cn.isEmpty) return null;
    if (digits.containsKey(cn)) return digits[cn];

    int result = 0;
    int temp = 0;
    for (var i = 0; i < cn.length; i++) {
      final ch = cn[i];
      if (digits.containsKey(ch)) {
        temp = digits[ch]!;
      } else if (ch == '十') {
        result += (temp == 0 ? 1 : temp) * 10;
        temp = 0;
      } else if (ch == '百') {
        result += (temp == 0 ? 1 : temp) * 100;
        temp = 0;
      }
    }
    result += temp;
    return result > 0 ? result : null;
  }

  static String? _extractMrn(String text) {
    // 1. 显式标签：住院号 / 病历号 / 门诊号 / 登记号 / 编号 / ID
    final explicit = RegExp(
      r'(?:住院号|病历号|病案号|门诊号|就诊号|登记号|档案号|编号|卡号|ID|No\.?)\s*(?:[:#]|是|为)?\s*([A-Za-z0-9\-_]{3,24})',
      caseSensitive: false,
    ).firstMatch(text);
    if (explicit != null) {
      return explicit.group(1)!.trim();
    }

    // 2. 独立长串数字/字母编号（5~14位，排除 11 位手机号与标准日期）
    for (final m in RegExp(r'(?<![0-9A-Za-z])([A-Za-z]?\d{5,13})(?![0-9A-Za-z])').allMatches(text)) {
      final candidate = m.group(1)!;
      // 排除 11 位常见手机号
      if (candidate.length == 11 && RegExp(r'^1[3-9]\d{9}$').hasMatch(candidate)) {
        continue;
      }
      // 排除 8 位纯年月日 (如 20261108)
      if (candidate.length == 8 && RegExp(r'^(19|20)\d{2}(0[1-9]|1[0-2])(0[1-9]|[12]\d|3[01])$').hasMatch(candidate)) {
        continue;
      }
      return candidate;
    }

    return null;
  }

  static Map<String, dynamic> _extractExtraData(String text) {
    final extra = <String, dynamic>{};

    // 1. 床号
    final bedExplicit = RegExp(
      r'(?:床号|床位)\s*(?:[:]|是|为)?\s*([0-9A-Za-z+\-]{1,6})\s*床?',
    ).firstMatch(text);
    if (bedExplicit != null) {
      final b = bedExplicit.group(1)!.trim();
      extra['床号'] = b.endsWith('床') ? b : '$b床';
    } else {
      final bedInline = RegExp(
        r'(?<![0-9])([加+]?\d{1,3}|[A-Za-z]\d{1,3})\s*床',
      ).firstMatch(text);
      if (bedInline != null) {
        extra['床号'] = '${bedInline.group(1)}床';
      }
    }

    // 2. 科室
    final deptExplicit = RegExp(
      r'(?:科室|科别|病区)\s*(?:[:]|是|为)?\s*([\u4e00-\u9fa5]{2,10}?(?:科|病区|中心|室|ICU))',
    ).firstMatch(text);
    if (deptExplicit != null) {
      extra['科室'] = deptExplicit.group(1)!.trim();
    } else {
      final deptInline = RegExp(
        r'((?:心血管|呼吸|消化|神经|内分泌|肾脏?|血液|风湿免疫|感染|肿瘤|急诊|重症医学|儿|妇产|妇|产|普通外|普外|骨|泌尿外|胸外|心外|神经外|肝胆外|胃肠外|甲乳外|烧伤|整形|眼科|耳鼻咽喉|口腔|皮肤|精神|心理|中医|中西医结合|康复|介入|疼痛|全科|老年)\s*(?:内科|外科|科|病区|中心)|ICU)',
      ).firstMatch(text);
      if (deptInline != null) {
        extra['科室'] = deptInline.group(1)!.replaceAll(RegExp(r'\s+'), '');
      }
    }

    // 3. 手机号
    final phoneMatch = RegExp(r'(?<!\d)(1[3-9]\d{9})(?!\d)').firstMatch(text);
    if (phoneMatch != null) {
      extra['电话'] = phoneMatch.group(1)!;
    }

    return extra;
  }

  static String? _extractName(String text) {
    // 1. 显式标签：姓名: 张三 / 患者: 李四
    final explicit = RegExp(
      r'(?:患者姓名|病人姓名|姓名|患者|病人|名字|称呼)\s*(?:[:]|叫|是|为)\s*([\u4e00-\u9fa5·]{2,5})',
    ).firstMatch(text);
    if (explicit != null) {
      final candidate = _cleanCandidateName(explicit.group(1)!);
      if (_isValidName(candidate)) return candidate;
    }

    // 2. 口语自述或介绍：我叫张三 / 叫李四
    final spoken = RegExp(
      r'(?:我叫|名字叫|名字是|患者叫|病人叫|收一个|新收)\s*([\u4e00-\u9fa5]{2,4})',
    ).firstMatch(text);
    if (spoken != null) {
      final candidate = _cleanCandidateName(spoken.group(1)!);
      if (_isValidName(candidate)) return candidate;
    }

    // 3. 紧邻性别或年龄的前置名字（如“张三 男 45岁”、“张三,女,60岁”）
    final beforeGenderAge = RegExp(
      r'(?<![\u4e00-\u9fa5])([\u4e00-\u9fa5]{2,4})\s*[,，、/\s(（]+\s*(?:性别\s*[:]\s*)?(?:男|女|\d{1,3}\s*岁)',
    ).allMatches(text);
    for (final m in beforeGenderAge) {
      final candidate = _cleanCandidateName(m.group(1)!);
      if (_isValidName(candidate)) return candidate;
    }

    // 4. 扫描分词，寻找以常见百家姓开头的 2~3 字独立词块
    final tokens = text
        .split(RegExp(r'[\s,，。；;、:：()（）【】\[\]/|]+'))
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();

    for (final token in tokens) {
      // 去除末尾可能粘连的“男”、“女”
      var cleaned = token;
      if (cleaned.length >= 3 && (cleaned.endsWith('男') || cleaned.endsWith('女'))) {
        cleaned = cleaned.substring(0, cleaned.length - 1);
      }
      if (_isValidName(cleaned) && _startsWithSurname(cleaned)) {
        return cleaned;
      }
    }

    return null;
  }

  static String _cleanCandidateName(String raw) {
    var s = raw.trim();
    // 截断可能连着被匹配进去的后缀词
    for (final suffix in ['性别', '年龄', '男', '女', '先生', '女士', '同志', '患者', '病人', '住院', '床号', '科室']) {
      if (s.length > 2 && s.endsWith(suffix)) {
        s = s.substring(0, s.length - suffix.length);
      }
    }
    return s;
  }

  static bool _isValidName(String candidate) {
    if (candidate.length < 2 || candidate.length > 4) return false;
    if (!RegExp(r'^[\u4e00-\u9fa5·]+$').hasMatch(candidate)) return false;
    if (_nonNameWords.contains(candidate)) return false;
    for (final bad in _nonNameWords) {
      if (bad.length >= 2 && candidate.contains(bad)) return false;
    }
    // 不能包含科、室、院、部、床、号、岁、病、症、炎、痛、癌、瘤
    if (RegExp(r'[科室院部床号岁病症炎痛癌瘤区男女]').hasMatch(candidate)) {
      return false;
    }
    return true;
  }

  static bool _startsWithSurname(String candidate) {
    if (candidate.length >= 3) {
      final prefix2 = candidate.substring(0, 2);
      if (_compoundSurnames.contains(prefix2)) return true;
    }
    final prefix1 = candidate.substring(0, 1);
    return _commonSurnames.contains(prefix1);
  }

  static String? _extractNotes(
    String text, {
    String? name,
    int? age,
    String? mrn,
    required Map<String, dynamic> extraData,
  }) {
    final notesList = <String>[];

    // 1. 显式标签：主诉 / 诊断 / 备注 / 病史
    final explicitMatches = RegExp(
      r'(?:主诉|入院诊断|初步诊断|临床诊断|诊断|病史|病情|症状|备注)\s*[:]\s*([^\n]+)',
    ).allMatches(text);
    for (final m in explicitMatches) {
      final val = m.group(1)!.trim();
      if (val.isNotEmpty && !notesList.contains(val)) {
        notesList.add(val);
      }
    }
    if (notesList.isNotEmpty) {
      return notesList.join('；');
    }

    // 2. 口语或无标签文本：剥离掉已识别的姓名、性别、年龄、编号、床号、科室子句后，保留剩余描述作为备注
    final segments = text
        .split(RegExp(r'[,，。；;\n]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();

    final remaining = <String>[];
    for (final seg in segments) {
      // 如果该段纯粹是已提取的基本元数据，则跳过
      if (name != null && (seg == name || seg == '姓名:$name' || seg == '患者:$name' || seg == '我叫$name' || seg == '患者叫$name')) {
        continue;
      }
      if (RegExp(r'^(?:性别\s*[:]?\s*)?(?:男|女|男性|女性)$').hasMatch(seg)) {
        continue;
      }
      if (RegExp(r'^(?:年龄\s*[:]?\s*)?(?:\d{1,3}|[一二三四五六七八九十百零两]{1,4})\s*(?:岁|周岁)?$').hasMatch(seg)) {
        continue;
      }
      if (mrn != null && seg.contains(mrn) && seg.length <= mrn.length + 6) {
        continue;
      }
      if (extraData['床号'] != null && seg.contains(extraData['床号'].toString()) && seg.length <= 8) {
        continue;
      }
      if (extraData['科室'] != null && seg == extraData['科室'].toString()) {
        continue;
      }
      if (extraData['电话'] != null && seg.contains(extraData['电话'].toString()) && seg.length <= 15) {
        continue;
      }
      // 过滤医院抬头等无意义短句
      if (RegExp(r'^[\u4e00-\u9fa5]{2,12}(?:医院|卫生院|保健院|诊所|住院部|门诊部|腕带|信息卡)$').hasMatch(seg)) {
        continue;
      }
      if (seg.length >= 3) {
        remaining.add(seg);
      }
    }

    if (remaining.isNotEmpty) {
      return remaining.join('，');
    }
    return null;
  }

  /// 保留原 LLM 提取方法供测试或兼容需要
  static Future<SessionAutofillResult> extractFromText({
    required String text,
    required ApiService apiService,
  }) async {
    return extractLocally(text);
  }

  static Map<String, dynamic>? parseJsonForTest(String text) {
    var raw = text.trim();
    final fenceMatch = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```').firstMatch(raw);
    if (fenceMatch != null) {
      raw = fenceMatch.group(1)?.trim() ?? raw;
    }
    final firstBrace = raw.indexOf('{');
    final lastBrace = raw.lastIndexOf('}');
    if (firstBrace != -1 && lastBrace != -1 && lastBrace > firstBrace) {
      raw = raw.substring(firstBrace, lastBrace + 1);
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    return null;
  }
}
