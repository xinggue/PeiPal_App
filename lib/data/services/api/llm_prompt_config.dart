/// A configurable block in the System Prompt.
class SystemPromptBlock {
  final String id;
  final String label;
  final String description;
  final String templateText;
  final bool isEnabled;

  const SystemPromptBlock({
    required this.id,
    required this.label,
    required this.description,
    required this.templateText,
    this.isEnabled = true,
  });

  SystemPromptBlock copyWith({
    String? templateText,
    bool? isEnabled,
  }) =>
      SystemPromptBlock(
        id: id,
        label: label,
        description: description,
        templateText: templateText ?? this.templateText,
        isEnabled: isEnabled ?? this.isEnabled,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'description': description,
        'templateText': templateText,
        'isEnabled': isEnabled,
      };

  factory SystemPromptBlock.fromJson(Map<String, dynamic> json) =>
      SystemPromptBlock(
        id: json['id'] as String,
        label: json['label'] as String? ?? '',
        description: json['description'] as String? ?? '',
        templateText: json['templateText'] as String? ?? '',
        isEnabled: json['isEnabled'] as bool? ?? true,
      );
}

class LlmPromptConfig {
  final List<SystemPromptBlock> systemBlocks;

  static List<SystemPromptBlock> get defaultSystemBlocks => const [
        SystemPromptBlock(
          id: 'role',
          label: '系统角色与定位',
          description: '定义 AI 的身份与撰写文书的目的',
          templateText:
              '你是最优秀最聪明最努力基本功最扎实的实习新星，现在为你的上级担任严谨、专业的文书助手。你的职责是根据会话中的全部素材，为文书「{document_title}」撰写符合规范的字段内容。我们会尽可能地提供信息，包括先前有哪些文书和字段已经填写完毕，具体内容是什么；本次有哪些需要你填写的字段，它们各自的示范内容、填写要求等。如果偶尔这些信息未被提供，你可以信赖你的背景知识和基本功。\n'
              '你接收到的素材主要来自于与上级的聊天记录，内容种类繁杂，包括但不限于：口语化表达的，长短不一的信息和指令；文书拍照后ocr产生的质量参差不齐的，可能有页面顺序错误以及错别字的大段文字识别内容；中英文混杂的，可能有截断或谐音错字的语音转文字内容。但作为经验老道、年富力强的你，这就是你的工作日常，相信你能够从容应对。',
        ),
        SystemPromptBlock(
          id: 'globalGuidance',
          label: '全文撰写规范 (来自内容模板)',
          description: '注入内容模板中的全篇文书风格约束与注意事项',
          templateText: '【全文撰写规范与要求】：\n{global_guidance}',
        ),
        SystemPromptBlock(
          id: 'stageCustomPrompt',
          label: '流程节点/分组工作指引',
          description: '注入当前阶段在流程图中配置的专属工作指引',
          templateText: '【本阶段专属工作指引 ({stage_title})】：\n{stage_prompt}',
        ),
        SystemPromptBlock(
          id: 'fieldSpecs',
          label: '目标字段规格与要求',
          description: '包含各字段名、类型、必填、选项范围、模板范文及单独要求',
          templateText: '【你当前需要生成的字段规格列表】：\n{field_specs}',
        ),
        SystemPromptBlock(
          id: 'standardCatalogs',
          label: '标准术语库对齐参考',
          description: '当字段关联标准库时，注入对应的标准术语名称及编码参考',
          templateText: '{catalog_specs}',
        ),
        SystemPromptBlock(
          id: 'outputFormat',
          label: '输出格式硬约束 (纯 JSON)',
          description: '强制模型输出合规 JSON 对象，严禁 Markdown 围栏或废话',
          templateText:
              '【输出格式约束】：\n必须输出严格的纯 JSON 对象，格式为：\n{"字段键名": "生成的文书内容", ...}\n要求：\n1. 只填入上方规格列表中的字段键名，严禁新增或幻想未经定义的键名。\n2. 带有可选范围的字段，必须从选项列表中选择或对齐。\n3. 不要在 JSON 外输出任何 markdown 解释、引言或非 JSON字符。',
        ),
      ];

  const LlmPromptConfig({
    this.systemBlocks = const [],
  });

  List<SystemPromptBlock> get effectiveSystemBlocks =>
      systemBlocks.isNotEmpty ? systemBlocks : defaultSystemBlocks;

  Map<String, dynamic> toJson() => {
        'system_blocks': effectiveSystemBlocks.map((b) => b.toJson()).toList(),
      };

  /// 未改过的内置说明和正文跟新默认走；用户改过的块保持原样。
  static List<SystemPromptBlock> _refreshUneditedDefaults(
    List<SystemPromptBlock> blocks,
  ) {
    const legacy = <String, (String, List<String>)>{
      'role': (
        '定义 AI 的临床医生身份与撰写病历的目的',
        [
          '你是一位严谨、专业的临床医生。\n你的职责是根据患者的全部临床素材，为电子病历「{document_title}」撰写符合规范的字段内容。',
          '你是一位严谨、专业的文书助手。\n你的职责是根据会话中的全部素材，为文书「{document_title}」撰写符合规范的字段内容。',
        ],
      ),
      'outputFormat': (
        '强制模型输出合规 JSON 对象，严禁 Markdown 围栏或废话',
        [
          '【输出格式约束】：\n必须输出严格的纯 JSON 对象，格式为：\n{"字段键名": "生成的病历内容", ...}\n要求：\n1. 只填入上方规格列表中的字段键名，严禁新增或幻想未经定义的键名。\n2. 带有可选范围的字段，必须从选项列表中选择或对齐。\n3. 不要在 JSON 外输出任何 markdown 解释、引言或非 JSON字符。',
        ],
      ),
    };
    final defaults = {for (final b in defaultSystemBlocks) b.id: b};

    bool isLegacyText(String id, String text) =>
        (legacy[id]?.$2 ?? const <String>[]).contains(text);

    bool isUnedited(SystemPromptBlock block, SystemPromptBlock def) =>
        block.description == legacy[block.id]?.$1 ||
        isLegacyText(block.id, block.templateText) ||
        block.description == def.description ||
        block.templateText == def.templateText;

    return [
      for (final block in blocks)
        if (defaults[block.id] != null &&
            isUnedited(block, defaults[block.id]!))
          SystemPromptBlock(
            id: block.id,
            label: defaults[block.id]!.label,
            description: block.description == legacy[block.id]?.$1 ||
                    block.description == defaults[block.id]!.description
                ? defaults[block.id]!.description
                : block.description,
            templateText: isLegacyText(block.id, block.templateText) ||
                    block.templateText == defaults[block.id]!.templateText
                ? defaults[block.id]!.templateText
                : block.templateText,
            isEnabled: block.isEnabled,
          )
        else
          block,
    ];
  }

  factory LlmPromptConfig.fromJson(Map<String, dynamic> json) {
    List<SystemPromptBlock> blocks = [];
    final rawBlocks = json['system_blocks'];
    if (rawBlocks is List) {
      blocks = rawBlocks
          .map((b) => SystemPromptBlock.fromJson(b as Map<String, dynamic>))
          .toList();
    }

    return LlmPromptConfig(
      systemBlocks: blocks.isNotEmpty
          ? _refreshUneditedDefaults(blocks)
          : defaultSystemBlocks,
    );
  }
}
