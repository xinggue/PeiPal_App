enum DocumentParserKind { deepseek, zhipu }

class DocumentParserProviderConfig {
  final DocumentParserKind kind;
  final String baseUrl;
  final String apiKey;
  final String toolType;
  final bool isEnabled;

  const DocumentParserProviderConfig({
    required this.kind,
    required this.baseUrl,
    this.apiKey = '',
    this.toolType = 'prime-sync',
    this.isEnabled = true,
  });

  String get id => kind.name;
  String get name => kind == DocumentParserKind.deepseek ? 'DeepSeek' : '智谱';
  String get defaultBaseUrl => kind == DocumentParserKind.deepseek
      ? 'https://api.deepseek.com/v1'
      : 'https://open.bigmodel.cn/api/paas/v4';
  String get modeLabel {
    if (kind == DocumentParserKind.deepseek) return 'DeepSeek OCR';
    return switch (toolType) {
      'prime' => 'Prime',
      'expert' => 'Expert',
      'lite' => 'Lite',
      _ => 'Prime-sync',
    };
  }
  bool get isConfigured =>
      isEnabled && apiKey.trim().isNotEmpty && baseUrl.trim().isNotEmpty;

  static const textExtensions = {
    'txt',
    'text',
    'md',
    'markdown',
    'json',
    'csv',
  };
  static const officeExtensions = {
    'pdf',
    'doc',
    'docx',
    'ppt',
    'pptx',
    'xls',
    'xlsx',
    'wps',
    'html',
    'htm',
  };
  static String extension(String path) => path.split('.').last.toLowerCase();
  static bool isLocalFile(String path) =>
      textExtensions.contains(extension(path));

  Set<String> get supportedExtensions {
    if (kind == DocumentParserKind.deepseek) {
      return const {'pdf', 'doc', 'docx', 'ppt', 'pptx'};
    }
    if (toolType == 'expert') return const {'pdf'};
    if (toolType == 'lite') {
      return const {'pdf', 'doc', 'docx', 'ppt', 'pptx', 'xls', 'xlsx'};
    }
    return {...officeExtensions}
      ..removeAll(toolType == 'prime-sync' ? const <String>{} : const {'wps'});
  }

  int maxBytes(String path) {
    if (kind == DocumentParserKind.deepseek) return 100 * 1024 * 1024;
    if (toolType == 'lite') return 50 * 1024 * 1024;
    if (const {'xls', 'xlsx'}.contains(extension(path))) {
      return 10 * 1024 * 1024;
    }
    if (const {'html', 'htm'}.contains(extension(path))) {
      return 20 * 1024 * 1024;
    }
    return 100 * 1024 * 1024;
  }

  DocumentParserProviderConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? toolType,
    bool? isEnabled,
  }) => DocumentParserProviderConfig(
    kind: kind,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    toolType: toolType ?? this.toolType,
    isEnabled: isEnabled ?? this.isEnabled,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'toolType': toolType,
    'isEnabled': isEnabled,
  };

  static List<DocumentParserProviderConfig> get presets => const [
    DocumentParserProviderConfig(
      kind: DocumentParserKind.deepseek,
      baseUrl: 'https://api.deepseek.com/v1',
    ),
    DocumentParserProviderConfig(
      kind: DocumentParserKind.zhipu,
      baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
    ),
  ];

  static DocumentParserProviderConfig? fromJson(Map json) {
    final preset = presets.where((p) => p.id == json['id']).firstOrNull;
    if (preset == null) return null;
    final tool = json['toolType']?.toString() ?? preset.toolType;
    return preset.copyWith(
      baseUrl: json['baseUrl']?.toString(),
      apiKey: json['apiKey']?.toString(),
      toolType: const {'prime-sync', 'prime', 'expert', 'lite'}.contains(tool)
          ? tool
          : 'prime-sync',
      isEnabled: json['isEnabled'] is bool ? json['isEnabled'] as bool : true,
    );
  }
}
