/// Configuration for AI content template refinement (including zero-state
/// extraction) and cross-structure migration.
class ExtractorConfig {
  final String refinePromptTemplate;
  final String migratePromptTemplate;

  /// Legacy getter for backward compatibility if referenced anywhere.
  String get systemPromptTemplate => refinePromptTemplate;

  static const String defaultRefinePromptTemplate = '''
你是临床文书内容模板编排与提炼专家。
用户正在编辑「{target_doc_name}」的内容模板（包含「全文撰写要求 global_guidance」以及各字段的「示范文本 text」和「撰写要求 guidance」）。
请基于【当前已有模板内容】，结合用户提供的【参考文书材料】和/或【补充细化指令】，对指定的目标字段进行补充、细化与提炼。

核心规则：
1. 若【当前已有模板内容】非空，请尊重并保留其中已有的核心约束与有效信息，在此基础上做增量补充、结构细化或按指令修正；若当前为空白模板，则直接从参考材料或指令中提炼生成。
2. 示范文本 (text)：从【参考文书材料】中提取或根据指令编写符合「{target_doc_name}」对应字段体裁的标准范文；若出现人名、住院号、证件号等隐私信息，一律替换为 XXX。若既无对应材料也无法合理编写，则留空字符串。
3. 撰写要求 (guidance)：归纳提炼该字段的具体写作规范（如字数范围、句式结构、必填临床要素、阴性症状/体征要求等）。看不出明确规律且无指令要求时留空字符串，宁缺毋滥。
4. 标准库引用保护：若某字段已有 guidance 中包含类似 `\uFFFC[CATALOG:type:tag]\uFFFC` 的标准库引用标记，必须原样保留在该字段的 guidance 中，严禁删除或篡改。
5. 本次生成范围：{output_scope_rule}
6. 只能输出下方【本次需要生成的目标字段列表】中的 key，不要输出未选中的字段或编造 key。
7. 只输出一个合法的 JSON 对象，不要包含任何解释文字或 Markdown 代码块。格式：
{"fields":{"<key>":{"text":"","guidance":""}},"global_guidance":""}

【本次需要生成的目标字段列表】：
{field_list}''';

  static const String defaultMigratePromptTemplate = '''
你是临床文书模板跨结构迁移与改写专家。
用户的任务是将一份来自「{source_doc_name}」的内容模板，经临床语义消化、重组与文体改写后，迁移适配到目标文书「{target_doc_name}」的指定字段中。

核心规则（严禁机械照搬原文）：
1. 深度消化与文体改写：
   - 严禁把源模板的字段文本原封不动地直接复制粘贴到目标字段！必须根据目标文书「{target_doc_name}」的临床体裁、行文视角、详略程度以及目标字段的定义进行重写与转换（例如：从《入院记录》迁移到《首次病程记录》时，需将分散的病史/查体高度凝练为首程“病例特点”的归纳口吻；迁移到《出院记录》时，需转换为出院总结口吻）。
2. 字段语义重组（多合一 / 一拆多 / 推演）：
   - 当源模板多个字段对应目标模板的一个综合字段时，必须有机融合、去重提炼，绝不能简单拼接。
   - 当源模板综合字段对应目标模板多个细分字段时，请按临床逻辑拆解归位。
   - 若目标字段在源模板中无直接对应项，但可根据源模板的病种与临床背景合理推演其撰写要求或范文，请结合目标字段名称进行适配编写；确实无法推演的留空字符串。
3. 遵循下拉/多选选项约束：若目标字段给定了“选项”，示范文本 text 必须严格取自给定选项。
4. 标准库引用传递：若源字段 guidance 中包含类似 `\uFFFC[CATALOG:type:tag]\uFFFC` 的标准库引用标记，在映射到语义对应的目标字段（如诊断、手术相关字段）时，必须原样保留该标记。
5. 本次生成范围：{output_scope_rule}
6. 只能输出下方【本次需要生成的目标字段列表】中的 key，不要输出其他 key。
7. 只输出一个合法的 JSON 对象，不要包含任何解释文字或 Markdown 代码块。格式：
{"fields":{"<key>":{"text":"","guidance":""}},"global_guidance":""}

【目标文书（{target_doc_name}）本次需要生成的字段列表】：
{field_list}''';

  const ExtractorConfig({
    this.refinePromptTemplate = defaultRefinePromptTemplate,
    this.migratePromptTemplate = defaultMigratePromptTemplate,
  });

  ExtractorConfig copyWith({
    String? refinePromptTemplate,
    String? migratePromptTemplate,
  }) =>
      ExtractorConfig(
        refinePromptTemplate: refinePromptTemplate ?? this.refinePromptTemplate,
        migratePromptTemplate:
            migratePromptTemplate ?? this.migratePromptTemplate,
      );

  Map<String, dynamic> toJson() => {
        'refine_prompt_template': refinePromptTemplate,
        'migrate_prompt_template': migratePromptTemplate,
      };

  factory ExtractorConfig.fromJson(Map<String, dynamic> json) =>
      ExtractorConfig(
        refinePromptTemplate: json['refine_prompt_template'] as String? ??
            defaultRefinePromptTemplate,
        migratePromptTemplate: json['migrate_prompt_template'] as String? ??
            defaultMigratePromptTemplate,
      );
}
