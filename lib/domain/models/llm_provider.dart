/// LLM 服务商模型定义与预设列表
class LlmProviderConfig {
  final String id;
  final String name;
  final String description;
  final String defaultBaseUrl;
  final String baseUrl;
  final String apiKey;
  final String selectedModel;
  final List<String> customModels;
  final bool isEnabled;
  final String? balance;
  final DateTime? balanceUpdatedAt;
  final String websiteUrl;

  const LlmProviderConfig({
    required this.id,
    required this.name,
    required this.description,
    required this.defaultBaseUrl,
    required this.baseUrl,
    required this.apiKey,
    required this.selectedModel,
    this.customModels = const [],
    this.isEnabled = true,
    this.balance,
    this.balanceUpdatedAt,
    this.websiteUrl = '',
  });

  bool get isConfigured => apiKey.trim().isNotEmpty;

  /// 全部可用模型列表（去重保留顺序）
  List<String> get allModels {
    final set = <String>{};
    if (selectedModel.trim().isNotEmpty) set.add(selectedModel.trim());
    set.addAll(customModels);
    return set.toList();
  }

  LlmProviderConfig copyWith({
    String? id,
    String? name,
    String? description,
    String? defaultBaseUrl,
    String? baseUrl,
    String? apiKey,
    String? selectedModel,
    List<String>? customModels,
    bool? isEnabled,
    String? balance,
    DateTime? balanceUpdatedAt,
    String? websiteUrl,
  }) {
    return LlmProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      defaultBaseUrl: defaultBaseUrl ?? this.defaultBaseUrl,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      selectedModel: selectedModel ?? this.selectedModel,
      customModels: customModels ?? this.customModels,
      isEnabled: isEnabled ?? this.isEnabled,
      balance: balance ?? this.balance,
      balanceUpdatedAt: balanceUpdatedAt ?? this.balanceUpdatedAt,
      websiteUrl: websiteUrl ?? this.websiteUrl,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'defaultBaseUrl': defaultBaseUrl,
        'baseUrl': baseUrl,
        'apiKey': apiKey,
        'selectedModel': selectedModel,
        'customModels': customModels,
        'isEnabled': isEnabled,
        if (balance != null) 'balance': balance,
        if (balanceUpdatedAt != null)
          'balanceUpdatedAt': balanceUpdatedAt!.toIso8601String(),
        'websiteUrl': websiteUrl,
      };

  factory LlmProviderConfig.fromJson(Map<String, dynamic> json) {
    return LlmProviderConfig(
      id: json['id'] as String? ?? 'custom',
      name: json['name'] as String? ?? '自定义',
      description: json['description'] as String? ?? '',
      defaultBaseUrl: json['defaultBaseUrl'] as String? ?? '',
      baseUrl: json['baseUrl'] as String? ?? '',
      apiKey: json['apiKey'] as String? ?? '',
      selectedModel: json['selectedModel'] as String? ?? '',
      customModels: (json['customModels'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          (json['presetModels'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      isEnabled: json['isEnabled'] as bool? ?? true,
      balance: json['balance'] as String?,
      balanceUpdatedAt: json['balanceUpdatedAt'] != null
          ? DateTime.tryParse(json['balanceUpdatedAt'].toString())
          : null,
      websiteUrl: json['websiteUrl'] as String? ?? '',
    );
  }
}

/// 内置的主流 AI 供应商预设
class LlmProviderPresets {
  static List<LlmProviderConfig> get builtIn => const [
        LlmProviderConfig(
          id: 'deepseek',
          name: 'DeepSeek (深度求索)',
          description: '中文推理首选，高性价比，支持余额直查',
          defaultBaseUrl: 'https://api.deepseek.com',
          baseUrl: 'https://api.deepseek.com',
          apiKey: '',
          selectedModel: 'deepseek-chat',
          websiteUrl: 'https://platform.deepseek.com',
        ),
        LlmProviderConfig(
          id: 'siliconflow',
          name: '硅基流动 (SiliconFlow)',
          description: '国内高速大模型托管平台，支持各大开源旗舰，支持余额直查',
          defaultBaseUrl: 'https://api.siliconflow.cn/v1',
          baseUrl: 'https://api.siliconflow.cn/v1',
          apiKey: '',
          selectedModel: 'deepseek-ai/DeepSeek-V3',
          websiteUrl: 'https://cloud.siliconflow.cn',
        ),
        LlmProviderConfig(
          id: 'mimo',
          name: '小米 MiMo (Xiaomi)',
          description: '小米自研大模型，接口响应迅速稳定，支持上下文对话与长文本',
          defaultBaseUrl: 'https://api.xiaomimimo.com/v1',
          baseUrl: 'https://api.xiaomimimo.com/v1',
          apiKey: '',
          selectedModel: 'mimo-v2.5',
          websiteUrl: 'https://api.xiaomimimo.com',
        ),
        LlmProviderConfig(
          id: 'zhipu',
          name: '智谱 AI (GLM)',
          description: '清华系大模型，GLM 系列高效稳定，同时支持对话 / OCR / 语音',
          defaultBaseUrl: 'https://open.bigmodel.cn/api/paas/v4',
          baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
          apiKey: '',
          selectedModel: 'glm-5.3-flash',
          websiteUrl: 'https://open.bigmodel.cn',
        ),
        LlmProviderConfig(
          id: 'moonshot',
          name: '月之暗面 (Kimi / Moonshot)',
          description: '擅长超长上下文和长文档综合整理',
          defaultBaseUrl: 'https://api.moonshot.cn/v1',
          baseUrl: 'https://api.moonshot.cn/v1',
          apiKey: '',
          selectedModel: 'moonshot-v1-8k',
          websiteUrl: 'https://platform.moonshot.cn',
        ),
        LlmProviderConfig(
          id: 'dashscope',
          name: '通义千问 (DashScope 百炼)',
          description: '阿里云百炼兼容模式，通义千问与开源旗舰全覆盖',
          defaultBaseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
          baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1',
          apiKey: '',
          selectedModel: 'qwen-plus',
          websiteUrl: 'https://bailian.console.aliyun.com',
        ),
        LlmProviderConfig(
          id: 'minimax',
          name: 'MiniMax (稀宇科技)',
          description: '国内知名自研大模型，文本理解与角色扮演表现优异',
          defaultBaseUrl: 'https://api.minimax.chat/v1',
          baseUrl: 'https://api.minimax.chat/v1',
          apiKey: '',
          selectedModel: 'MiniMax-Text-01',
          websiteUrl: 'https://platform.minimaxi.com',
        ),
        LlmProviderConfig(
          id: 'openai',
          name: 'OpenAI (官方 / 专线)',
          description: '国际知名基准大语言模型',
          defaultBaseUrl: 'https://api.openai.com/v1',
          baseUrl: 'https://api.openai.com/v1',
          apiKey: '',
          selectedModel: 'gpt-4o',
          websiteUrl: 'https://platform.openai.com',
        ),
        LlmProviderConfig(
          id: 'custom',
          name: '自定义 (OpenAI 兼容端点)',
          description: '支持任何兼容 OpenAI 规范的私有化部署、中转站或本地 Ollama',
          defaultBaseUrl: 'https://api.openai.com/v1',
          baseUrl: 'https://api.openai.com/v1',
          apiKey: '',
          selectedModel: '',
          websiteUrl: '',
        ),
      ];
}
