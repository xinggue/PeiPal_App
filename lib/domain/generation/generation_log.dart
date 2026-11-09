import 'dart:convert';
import 'generation_result.dart';

/// 对应 generation_logs 表的持久化实体。
/// 保存每次生成（或重试、部分保存）的完整审计日志，包括各阶段 Prompt 与模型原始返回。
class GenerationLog {
  final String id;
  final String messageId;
  final String patientId;
  final String templateId;
  final String templateName;
  final String? model;
  final String status; // 'success' | 'partial' | 'failed'
  final int totalDurationMs;
  final List<StageLog> stages;
  final List<FieldIssue> issues;
  final String? errorMessage;
  final DateTime createdAt;

  const GenerationLog({
    required this.id,
    required this.messageId,
    required this.patientId,
    required this.templateId,
    required this.templateName,
    this.model,
    required this.status,
    required this.totalDurationMs,
    required this.stages,
    this.issues = const [],
    this.errorMessage,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'message_id': messageId,
        'patient_id': patientId,
        'template_id': templateId,
        'template_name': templateName,
        'model': model ?? '',
        'status': status,
        'total_duration_ms': totalDurationMs,
        'stages_json': jsonEncode(stages.map((s) => s.toJson()).toList()),
        'issues_json': jsonEncode(issues.map((i) => i.toJson()).toList()),
        'error_message': errorMessage,
        'created_at': createdAt.toIso8601String(),
      };

  factory GenerationLog.fromMap(Map<String, dynamic> map) {
    List<StageLog> stagesList = const [];
    try {
      final raw = jsonDecode(map['stages_json'] as String? ?? '[]') as List;
      stagesList = raw.map((e) => StageLog.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {}

    List<FieldIssue> issuesList = const [];
    try {
      final raw = jsonDecode(map['issues_json'] as String? ?? '[]') as List;
      issuesList = raw.map((e) => FieldIssue.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {}

    return GenerationLog(
      id: map['id'] as String,
      messageId: map['message_id'] as String,
      patientId: map['patient_id'] as String,
      templateId: map['template_id'] as String,
      templateName: map['template_name'] as String? ?? '',
      model: (map['model'] as String?)?.isEmpty == true ? null : map['model'] as String?,
      status: map['status'] as String? ?? 'success',
      totalDurationMs: map['total_duration_ms'] as int? ?? 0,
      stages: stagesList,
      issues: issuesList,
      errorMessage: map['error_message'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
