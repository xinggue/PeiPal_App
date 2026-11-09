class LlmConfig {
  final String baseUrl;
  final String apiKey;
  final String model;

  const LlmConfig({
    this.baseUrl = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.model = 'gpt-4o',
  });

  bool get isConfigured => apiKey.isNotEmpty;

  LlmConfig copyWith({String? baseUrl, String? apiKey, String? model}) =>
      LlmConfig(
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
      );
}

enum AsrProvider {
  openaiWhisper(
    defaultUrl: 'https://api.openai.com/v1',
    defaultModel: 'whisper-1',
  ),
  mimoV25(
    defaultUrl: 'https://api.xiaomimimo.com/v1',
    defaultModel: 'mimo-v2.5-asr',
  ),
  zhipuAsr(
    defaultUrl: 'https://open.bigmodel.cn/api/paas/v4',
    defaultModel: 'glm-asr-2512',
  );

  final String defaultUrl;
  final String defaultModel;

  const AsrProvider({required this.defaultUrl, required this.defaultModel});
}

class AsrConfig {
  final AsrProvider provider;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String language;

  const AsrConfig({
    this.provider = AsrProvider.openaiWhisper,
    this.baseUrl = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.model = 'whisper-1',
    this.language = 'zh',
  });

  bool get isConfigured => apiKey.isNotEmpty;

  AsrConfig copyWith({
    AsrProvider? provider,
    String? baseUrl,
    String? apiKey,
    String? model,
    String? language,
  }) =>
      AsrConfig(
        provider: provider ?? this.provider,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
        language: language ?? this.language,
      );
}

enum OcrProvider {
  openai,
  paddleOcr,
  mineru,
  appleVision,
  paddleLocal,
  zhipu,
  modelbest,
}

class OcrConfig {
  final OcrProvider provider;
  final String baseUrl;
  final String apiKey;
  final String model;

  const OcrConfig({
    this.provider = OcrProvider.openai,
    this.baseUrl = 'https://api.openai.com/v1',
    this.apiKey = '',
    this.model = 'gpt-4o',
  });

  bool get isConfigured =>
      provider == OcrProvider.mineru ||
      provider == OcrProvider.appleVision ||
      provider == OcrProvider.paddleLocal ||
      apiKey.isNotEmpty;

  bool get needsCloudCredentials =>
      provider != OcrProvider.mineru &&
      provider != OcrProvider.appleVision &&
      provider != OcrProvider.paddleLocal;

  OcrConfig copyWith({
    OcrProvider? provider,
    String? baseUrl,
    String? apiKey,
    String? model,
  }) =>
      OcrConfig(
        provider: provider ?? this.provider,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        model: model ?? this.model,
      );
}
