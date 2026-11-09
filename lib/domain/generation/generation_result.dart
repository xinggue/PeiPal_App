/// 一次阶段调用的可追溯记录（用于排错与审阅）。
class StageLog {
  final int index;
  final String title;
  final List<String> slotKeys;
  final String systemPrompt;
  final String userPrompt;
  final String? rawResponse;
  final int attempts;
  final Duration duration;
  final bool success;
  final String? error;

  const StageLog({
    required this.index,
    required this.title,
    required this.slotKeys,
    required this.systemPrompt,
    required this.userPrompt,
    this.rawResponse,
    this.attempts = 1,
    this.duration = Duration.zero,
    this.success = true,
    this.error,
  });

  Map<String, dynamic> toJson() => {
        'index': index,
        'title': title,
        'slot_keys': slotKeys,
        'system_prompt': systemPrompt,
        'user_prompt': userPrompt,
        if (rawResponse != null) 'raw_response': rawResponse,
        'attempts': attempts,
        'duration_ms': duration.inMilliseconds,
        'success': success,
        if (error != null) 'error': error,
      };

  factory StageLog.fromJson(Map<String, dynamic> j) => StageLog(
        index: j['index'] as int? ?? 0,
        title: j['title'] as String? ?? '',
        slotKeys: (j['slot_keys'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        systemPrompt: j['system_prompt'] as String? ?? '',
        userPrompt: j['user_prompt'] as String? ?? '',
        rawResponse: j['raw_response'] as String?,
        attempts: j['attempts'] as int? ?? 1,
        duration: Duration(milliseconds: j['duration_ms'] as int? ?? 0),
        success: j['success'] as bool? ?? true,
        error: j['error'] as String?,
      );
}

enum FieldIssueType {
  /// 必填字段为空
  missingRequired,

  /// 取值不在模板给定的选项内
  notInOptions,
}

/// 某个字段在清洗/校验时发现的问题；审阅页据此标红。
class FieldIssue {
  final String key;
  final FieldIssueType type;
  final String message;

  const FieldIssue({
    required this.key,
    required this.type,
    required this.message,
  });

  Map<String, dynamic> toJson() =>
      {'key': key, 'type': type.name, 'message': message};

  factory FieldIssue.fromJson(Map<String, dynamic> j) => FieldIssue(
        key: j['key'] as String,
        type: FieldIssueType.values.asNameMap()[j['type']] ??
            FieldIssueType.missingRequired,
        message: j['message'] as String? ?? '',
      );
}

/// 引擎 A 的最终输出。
///
/// 失败时 [fieldValues] 仍保留已成功阶段的结果，[completedStages] / [totalStages]
/// 指示进度，UI 可据此保留部分结果或从失败阶段继续。
class GenerationResult {
  final bool isSuccess;
  final Map<String, String> fieldValues;
  final List<String> executedBatches;
  final List<StageLog> stageLogs;
  final List<FieldIssue> issues;
  final int completedStages;
  final int totalStages;
  final String? errorMessage;
  final Duration duration;

  const GenerationResult({
    required this.isSuccess,
    this.fieldValues = const {},
    this.executedBatches = const [],
    this.stageLogs = const [],
    this.issues = const [],
    this.completedStages = 0,
    this.totalStages = 0,
    this.errorMessage,
    this.duration = Duration.zero,
  });

  bool get isPartial => !isSuccess && fieldValues.isNotEmpty;

  factory GenerationResult.failure(
    String message, {
    Duration? duration,
    Map<String, String> fieldValues = const {},
    List<StageLog> stageLogs = const [],
    List<String> executedBatches = const [],
    int completedStages = 0,
    int totalStages = 0,
  }) =>
      GenerationResult(
        isSuccess: false,
        errorMessage: message,
        duration: duration ?? Duration.zero,
        fieldValues: fieldValues,
        stageLogs: stageLogs,
        executedBatches: executedBatches,
        completedStages: completedStages,
        totalStages: totalStages,
      );
}
