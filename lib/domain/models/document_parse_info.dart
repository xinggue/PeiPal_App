enum DocumentParseStatus { running, success, partial, failed, cancelled }

class DocumentParseInfo {
  final DocumentParseStatus status;
  final String attemptId;
  final String providerId;
  final String baseUrl;
  final String toolType;
  final String? remoteTaskId;
  final bool hasResult;
  final String? error;
  final List<String> warnings;
  final int? pageCount;

  const DocumentParseInfo({
    required this.status,
    required this.attemptId,
    this.providerId = '',
    this.baseUrl = '',
    this.toolType = '',
    this.remoteTaskId,
    this.hasResult = false,
    this.error,
    this.warnings = const [],
    this.pageCount,
  });

  DocumentParseInfo copyWith({
    DocumentParseStatus? status,
    String? remoteTaskId,
    bool clearRemoteTaskId = false,
    bool? hasResult,
    String? error,
    List<String>? warnings,
    int? pageCount,
  }) => DocumentParseInfo(
    status: status ?? this.status,
    attemptId: attemptId,
    providerId: providerId,
    baseUrl: baseUrl,
    toolType: toolType,
    remoteTaskId: clearRemoteTaskId ? null : remoteTaskId ?? this.remoteTaskId,
    hasResult: hasResult ?? this.hasResult,
    error: error,
    warnings: warnings ?? this.warnings,
    pageCount: pageCount ?? this.pageCount,
  );

  Map<String, dynamic> toJson() => {
    'status': status.name,
    'attemptId': attemptId,
    'providerId': providerId,
    'baseUrl': baseUrl,
    'toolType': toolType,
    'remoteTaskId': remoteTaskId,
    'hasResult': hasResult,
    'error': error,
    'warnings': warnings,
    'pageCount': pageCount,
  };

  factory DocumentParseInfo.fromJson(Map json) => DocumentParseInfo(
    status:
        DocumentParseStatus.values
            .where((s) => s.name == json['status'])
            .firstOrNull ??
        DocumentParseStatus.failed,
    attemptId: json['attemptId']?.toString() ?? '',
    providerId: json['providerId']?.toString() ?? '',
    baseUrl: json['baseUrl']?.toString() ?? '',
    toolType: json['toolType']?.toString() ?? '',
    remoteTaskId: json['remoteTaskId']?.toString(),
    hasResult: json['hasResult'] == true,
    error: json['error']?.toString(),
    warnings:
        (json['warnings'] as List?)?.map((e) => e.toString()).toList() ??
        const [],
    pageCount: json['pageCount'] is int ? json['pageCount'] as int : null,
  );
}

class DocumentParseResult {
  final String text;
  final List<String> warnings;
  final int? pageCount;
  const DocumentParseResult(
    this.text, {
    this.warnings = const [],
    this.pageCount,
  });
  bool get isPartial => warnings.isNotEmpty;
}
