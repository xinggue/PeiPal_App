/// ASR 协议类型
enum AsrProtocol {
  /// OpenAI 兼容语音转文本 (/audio/transcriptions + GET /models)
  openaiWhisper,

  /// 小米 MiMo 多模态语音识别 (/chat/completions input_audio)
  mimoV25,

  /// 智谱 GLM-ASR 语音转文本 (/paas/v4/audio/transcriptions)
  zhipuAsr,

  /// DeepSeek 文件语音识别 (/v1/tools/asr)
  deepseek,
}

/// ASR 服务商配置与预设列表
class AsrProviderConfig {
  final String id;
  final String name;
  final String description;
  final AsrProtocol protocol;
  final String defaultBaseUrl;
  final String baseUrl;
  final String apiKey;
  final String selectedModel;
  final String language;
  final List<String> customModels;
  final bool isEnabled;
  final String? statusInfo;
  final DateTime? statusUpdatedAt;
  final String websiteUrl;

  const AsrProviderConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.protocol,
    required this.defaultBaseUrl,
    required this.baseUrl,
    required this.apiKey,
    required this.selectedModel,
    this.language = 'zh',
    this.customModels = const [],
    this.isEnabled = true,
    this.statusInfo,
    this.statusUpdatedAt,
    this.websiteUrl = '',
  });

  bool get isConfigured => apiKey.trim().isNotEmpty;

  bool get requiresModel => protocol != AsrProtocol.deepseek;

  /// 全部可用模型列表（去重保留顺序）
  List<String> get allModels {
    final set = <String>{};
    if (selectedModel.trim().isNotEmpty) set.add(selectedModel.trim());
    set.addAll(customModels);
    return set.toList();
  }

  AsrProviderConfig copyWith({
    String? id,
    String? name,
    String? description,
    AsrProtocol? protocol,
    String? defaultBaseUrl,
    String? baseUrl,
    String? apiKey,
    String? selectedModel,
    String? language,
    List<String>? customModels,
    bool? isEnabled,
    String? statusInfo,
    DateTime? statusUpdatedAt,
    String? websiteUrl,
  }) {
    return AsrProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      protocol: protocol ?? this.protocol,
      defaultBaseUrl: defaultBaseUrl ?? this.defaultBaseUrl,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      language: language ?? this.language,
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
        'language': language,
        'customModels': customModels,
        'isEnabled': isEnabled,
        if (statusInfo != null) 'statusInfo': statusInfo,
        if (statusUpdatedAt != null)
          'statusUpdatedAt': statusUpdatedAt!.toIso8601String(),
        'websiteUrl': websiteUrl,
      };

  factory AsrProviderConfig.fromJson(Map<String, dynamic> json) {
    final protoStr = json['protocol'] as String? ?? 'openaiWhisper';
    final protocol = AsrProtocol.values
            .where((p) => p.name == protoStr)
            .firstOrNull ??
        AsrProtocol.openaiWhisper;
    return AsrProviderConfig(
      id: json['id'] as String? ?? 'custom',
      name: json['name'] as String? ?? '自定义',
      description: json['description'] as String? ?? '',
      protocol: protocol,
      defaultBaseUrl: json['defaultBaseUrl'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      selectedModel: json['selectedModel'] as String? ?? '',
      language: json['language'] as String? ?? 'zh',
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

/// 内置的 ASR 供应商预设矩阵
class AsrProviderPresets {
  static List<AsrProviderConfig> get builtIn => const [
        AsrProviderConfig(
          id: 'deepseek',
          name: 'DeepSeek 语音识别',
          description: '自动识别语言，单次最长 120 秒、最大 8 MiB',
          protocol: AsrProtocol.deepseek,
          defaultBaseUrl: 'https://api.deepseek.com/v1',
          baseUrl: 'https://api.deepseek.com/v1',
          apiKey: '',
          selectedModel: '',
          websiteUrl: 'https://platform.deepseek.com',
        ),
        AsrProviderConfig(
          id: 'zhipu',
          name: '智谱 AI (GLM-ASR 语音转文本)',
          description: '智谱开放平台 GLM-ASR-2512 模型，专业普通话与多语种高精度语音转写',
          protocol: AsrProtocol.zhipuAsr,
          defaultBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
          baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
          apiKey: '',
          selectedModel: 'glm-asr-2512',
          customModels: ['glm-asr-2512'],
          websiteUrl: 'https://open.bigmodel.cn',
        ),
        AsrProviderConfig(
          id: 'openaiWhisper',
          name: 'OpenAI Whisper (官方 / 兼容端点)',
          description: '国际知名 Whisper-1 语音识别模型，支持任何兼容 Whisper 的中转站',
          protocol: AsrProtocol.openaiWhisper,
          defaultBaseUrl: 'https://api.openai.com/v1',
          baseUrl: 'https://api.openai.com/v1',
          apiKey: '',
          selectedModel: 'whisper-1',
          customModels: ['whisper-1'],
          websiteUrl: 'https://platform.openai.com',
        ),
        AsrProviderConfig(
          id: 'mimoV25',
          name: '小米 MiMo (MiMo-V2.5-ASR)',
          description: '小米端云一体多模态大模型语音识别，高自然度与快速响应',
          protocol: AsrProtocol.mimoV25,
          defaultBaseUrl: 'https://api.xiaomimimo.com/v1',
          baseUrl: 'https://api.xiaomimimo.com/v1',
          apiKey: '',
          selectedModel: 'mimo-v2.5-asr',
          customModels: ['mimo-v2.5-asr'],
          websiteUrl: 'https://api.xiaomimimo.com',
        ),
      ];
}
