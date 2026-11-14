/// OCR 协议类型（决定底层调用方式与是否支持拉取模型列表）
enum OcrProtocol {
  /// OpenAI 兼容多模态接口 (/chat/completions + GET /models)
  openaiVision,

  /// 百度星河 PaddleOCR VL 异步任务接口 (/api/v2/ocr/jobs)
  paddleOcr,

  /// 智谱 GLM-OCR 文档解析接口 (/paas/v4/layout_parsing + GET /models)
  zhipuLayout,

  /// 面壁智能 ModelBest 文档解析接口 (/v1/document-parse + GET /models)
  modelbestParse,

  /// MinerU 免登录 Agent 接口 (/api/v1/agent/parse/file)
  mineru,

  /// iOS / macOS 系统本地 Vision 离线识别
  appleVision,

  /// Android 本地 PP-OCRv5 离线识别
  paddleLocal,

  /// DeepSeek 文件文字识别 (/v1/tools/ocr)
  deepseek,
}

/// OCR 服务商配置与预设列表
class OcrProviderConfig {
  final String id;
  final String name;
  final String description;
  final OcrProtocol protocol;
  final String defaultBaseUrl;
  final String baseUrl;
  final String apiKey;
  final String selectedModel;
  final List<String> customModels;
  final bool isEnabled;
  final String? statusInfo;
  final DateTime? statusUpdatedAt;
  final String websiteUrl;

  const OcrProviderConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.protocol,
    required this.defaultBaseUrl,
    required this.baseUrl,
    required this.apiKey,
    required this.selectedModel,
    this.customModels = const [],
    this.isEnabled = true,
    this.statusInfo,
    this.statusUpdatedAt,
    this.websiteUrl = '',
  });

  bool get isLocal =>
      protocol == OcrProtocol.appleVision ||
      protocol == OcrProtocol.paddleLocal;

  bool get isNoAuthCloud => protocol == OcrProtocol.mineru;

  bool get requiresApiKey => !isLocal && !isNoAuthCloud;

  bool get isConfigured => !requiresApiKey || apiKey.trim().isNotEmpty;

  bool get requiresModel => protocol != OcrProtocol.deepseek;

  /// 是否支持从服务端 GET /models 获取模型列表或拥有多个可选模型
  bool get supportsModelFetch =>
      protocol == OcrProtocol.openaiVision ||
      protocol == OcrProtocol.zhipuLayout ||
      protocol == OcrProtocol.modelbestParse ||
      protocol == OcrProtocol.paddleOcr;

  /// 全部可用模型列表（去重保留顺序）
  List<String> get allModels {
    final set = <String>{};
    if (selectedModel.trim().isNotEmpty) set.add(selectedModel.trim());
    set.addAll(customModels);
    return set.toList();
  }

  OcrProviderConfig copyWith({
    String? id,
    String? name,
    String? description,
    OcrProtocol? protocol,
    String? defaultBaseUrl,
    String? baseUrl,
    String? apiKey,
    String? selectedModel,
    List<String>? customModels,
    bool? isEnabled,
    String? statusInfo,
    DateTime? statusUpdatedAt,
    String? websiteUrl,
  }) {
    return OcrProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      protocol: protocol ?? this.protocol,
      defaultBaseUrl: defaultBaseUrl ?? this.defaultBaseUrl,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      customModels: customModels ?? this.customModels,
      isEnabled: isEnabled ?? this.isEnabled,
      statusInfo: statusInfo ?? this.statusInfo,
      statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
      websiteUrl: websiteUrl ?? this.websiteUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'protocol': protocol.name,
        'defaultBaseUrl': defaultBaseUrl,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'selectedModel': selectedModel,
        'customModels': customModels,
        'isEnabled': isEnabled,
        if (statusInfo != null) 'statusInfo': statusInfo,
        if (statusUpdatedAt != null)
          'statusUpdatedAt': statusUpdatedAt!.toIso8601String(),
        'websiteUrl': websiteUrl,
      };

  factory OcrProviderConfig.fromJson(Map<String, dynamic> json) {
    final protoStr = json['protocol'] as String? ?? 'openaiVision';
    final protocol = OcrProtocol.values
            .where((p) => p.name == protoStr)
            .firstOrNull ??
        OcrProtocol.openaiVision;
    return OcrProviderConfig(
      id: json['id'] as String? ?? 'custom',
      name: json['name'] as String? ?? '自定义',
      description: json['description'] as String? ?? '',
      protocol: protocol,
      defaultBaseUrl: json['defaultBaseUrl'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      selectedModel: json['selectedModel'] as String? ?? '',
      customModels: (json['customModels'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isEnabled: json['isEnabled'] as bool? ?? true,
      statusInfo: json['statusInfo'] as String?,
      statusUpdatedAt: json['statusUpdatedAt'] != null
          ? DateTime.tryParse(json['statusUpdatedAt'].toString())
          : null,
      websiteUrl: json['websiteUrl'] as String? ?? '',
    );
  }
}

/// 内置的 OCR 供应商预设矩阵
class OcrProviderPresets {
  static List<OcrProviderConfig> get builtIn => const [
        OcrProviderConfig(
          id: 'deepseek',
          name: 'DeepSeek 文字识别',
          description: '按页识别图片文字与表格',
          protocol: OcrProtocol.deepseek,
          defaultBaseUrl: 'https://api.deepseek.com/v1',
          baseUrl: 'https://api.deepseek.com/v1',
          apiKey: '',
          selectedModel: '',
          websiteUrl: 'https://platform.deepseek.com',
        ),
        OcrProviderConfig(
          id: 'modelbest',
          name: '面壁智能 (ModelBest 文档解析)',
          description: 'MiniCPM-OCR 文档解析接口，支持正文、表格、印章与旋转自适应',
          protocol: OcrProtocol.modelbestParse,
          defaultBaseUrl: 'https://api.modelbest.cn/v1',
          baseUrl: 'https://api.modelbest.cn/v1',
          apiKey: '',
          selectedModel: 'MiniCPM-OCR-1.0',
          customModels: ['MiniCPM-OCR-1.0'],
          websiteUrl: 'https://platform.modelbest.cn',
        ),
        OcrProviderConfig(
          id: 'zhipu',
          name: '智谱 AI (GLM-OCR 文档解析)',
          description: '智谱开放平台文档解析 (/paas/v4/layout_parsing)，直接输出结构化 Markdown',
          protocol: OcrProtocol.zhipuLayout,
          defaultBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
          baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
          apiKey: '',
          selectedModel: 'glm-ocr',
          customModels: ['glm-ocr'],
          websiteUrl: 'https://open.bigmodel.cn',
        ),
        OcrProviderConfig(
          id: 'paddleOcr',
          name: '百度飞桨 (PaddleOCR-VL)',
          description: '百度 AI Studio 星河社区文档解析，适合复杂化验单与病历表格',
          protocol: OcrProtocol.paddleOcr,
          defaultBaseUrl: 'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs',
          baseUrl: 'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs',
          apiKey: '',
          selectedModel: 'PaddleOCR-VL-1.6',
          customModels: ['PaddleOCR-VL-1.6', 'PaddleOCR-VL-0.9B'],
          websiteUrl: 'https://aistudio.baidu.com',
        ),
        OcrProviderConfig(
          id: 'openai',
          name: 'OpenAI Vision (兼容多模态端点)',
          description: '支持官方 GPT-4o 或任意兼容 OpenAI Vision 消息格式的服务商',
          protocol: OcrProtocol.openaiVision,
          defaultBaseUrl: 'https://api.openai.com/v1',
          baseUrl: 'https://api.openai.com/v1',
          apiKey: '',
          selectedModel: 'gpt-4o',
          customModels: ['gpt-4o', 'gpt-4o-mini'],
          websiteUrl: 'https://platform.openai.com',
        ),
        OcrProviderConfig(
          id: 'mineru',
          name: 'MinerU (免登录云端解析)',
          description: '免配置 Token 直接调用，支持表格与公式还原（受公网 IP 频率限制）',
          protocol: OcrProtocol.mineru,
          defaultBaseUrl: 'https://mineru.net/api/v1/agent',
          baseUrl: 'https://mineru.net/api/v1/agent',
          apiKey: '',
          selectedModel: 'agent',
          customModels: ['agent'],
          websiteUrl: 'https://mineru.net',
        ),
        OcrProviderConfig(
          id: 'appleVision',
          name: 'Apple 本地识别 (离线 Vision)',
          description: '使用 iOS / macOS 系统内置 Vision 引擎本机离线识别，图片不上传',
          protocol: OcrProtocol.appleVision,
          defaultBaseUrl: 'local://apple-vision',
          baseUrl: 'local://apple-vision',
          apiKey: '',
          selectedModel: 'apple-vision',
          customModels: ['apple-vision'],
        ),
        OcrProviderConfig(
          id: 'paddleLocal',
          name: 'Paddle 本地识别 (离线 PP-OCRv5)',
          description: '使用 Android 内置 PP-OCRv5 引擎本机离线识别，图片不上传',
          protocol: OcrProtocol.paddleLocal,
          defaultBaseUrl: 'local://paddle-ocr',
          baseUrl: 'local://paddle-ocr',
          apiKey: '',
          selectedModel: 'ppocr-v5-mobile',
          customModels: ['ppocr-v5-mobile'],
        ),
      ];
}
