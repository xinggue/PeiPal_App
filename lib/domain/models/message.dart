import 'dart:convert';
import 'package:uuid/uuid.dart';

import 'record_meta.dart';

const _uuid = Uuid();

enum MessageSender { user, system }

enum MessageType {
  text,
  voice,
  photo,
  document,
  asrResult,
  ocrResult,
  generatedRecord,
}

class Message {
  final String id;
  final String patientId;
  final MessageSender sender;
  final MessageType type;
  final String? content;

  final List<String> filePaths;
  final List<int> fileSizes;

  final int? durationMs;
  final int? pageCount;

  final String? transcribedText;
  final String? extractedText;

  final String? recordJson;
  final String? templateId;
  final RecordMeta? recordMeta;

  final DateTime createdAt;

  Message({
    String? id,
    required this.patientId,
    required this.sender,
    required this.type,
    this.content,
    List<String>? filePaths,
    List<int>? fileSizes,
    this.durationMs,
    this.pageCount,
    this.transcribedText,
    this.extractedText,
    this.recordJson,
    this.templateId,
    this.recordMeta,
    DateTime? createdAt,
  })  : id = id ?? _uuid.v4(),
        filePaths = filePaths ?? [],
        fileSizes = fileSizes ?? [],
        createdAt = createdAt ?? DateTime.now();

  factory Message.text({
    required String patientId,
    required String content,
  }) =>
      Message(
        patientId: patientId,
        sender: MessageSender.user,
        type: MessageType.text,
        content: content,
      );

  factory Message.voice({
    required String patientId,
    required String filePath,
    required int fileSize,
    required int durationMs,
  }) =>
      Message(
        patientId: patientId,
        sender: MessageSender.user,
        type: MessageType.voice,
        filePaths: [filePath],
        fileSizes: [fileSize],
        durationMs: durationMs,
      );

  factory Message.photo({
    required String patientId,
    required List<String> filePaths,
    required List<int> fileSizes,
  }) =>
      Message(
        patientId: patientId,
        sender: MessageSender.user,
        type: MessageType.photo,
        filePaths: filePaths,
        fileSizes: fileSizes,
        pageCount: filePaths.length,
      );

  factory Message.document({
    required String patientId,
    required String filePath,
    required int fileSize,
    required String fileName,
    String? extractedText,
  }) =>
      Message(
        patientId: patientId,
        sender: MessageSender.user,
        type: MessageType.document,
        content: fileName,
        filePaths: [filePath],
        fileSizes: [fileSize],
        extractedText: extractedText,
      );

  factory Message.asrResult({
    required String patientId,
    required String transcribedText,
  }) =>
      Message(
        patientId: patientId,
        sender: MessageSender.system,
        type: MessageType.asrResult,
        content: '语音转写结果',
        transcribedText: transcribedText,
      );

  factory Message.ocrResult({
    required String patientId,
    required String extractedText,
  }) =>
      Message(
        patientId: patientId,
        sender: MessageSender.system,
        type: MessageType.ocrResult,
        content: '图片识别结果',
        extractedText: extractedText,
      );

  factory Message.generatedRecord({
    required String patientId,
    required String recordJson,
    required String templateId,
    RecordMeta? recordMeta,
    DateTime? createdAt,
  }) =>
      Message(
        patientId: patientId,
        sender: MessageSender.system,
        type: MessageType.generatedRecord,
        content: '生成文书',
        recordJson: recordJson,
        templateId: templateId,
        recordMeta: recordMeta,
        createdAt: createdAt,
      );

  Message copyWith({
    List<String>? filePaths,
    List<int>? fileSizes,
    String? transcribedText,
    bool clearTranscribedText = false,
    String? extractedText,
    bool clearExtractedText = false,
    String? recordJson,
    bool clearRecordJson = false,
    RecordMeta? recordMeta,
    bool clearRecordMeta = false,
    DateTime? createdAt,
  }) =>
      Message(
        id: id,
        patientId: patientId,
        sender: sender,
        type: type,
        content: content,
        filePaths: filePaths ?? this.filePaths,
        fileSizes: fileSizes ?? this.fileSizes,
        durationMs: durationMs,
        pageCount: pageCount,
        transcribedText: clearTranscribedText
            ? null
            : (transcribedText ?? this.transcribedText),
        extractedText:
            clearExtractedText ? null : (extractedText ?? this.extractedText),
        recordJson: clearRecordJson ? null : (recordJson ?? this.recordJson),
        templateId: templateId,
        recordMeta: clearRecordMeta ? null : (recordMeta ?? this.recordMeta),
        createdAt: createdAt ?? this.createdAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'patient_id': patientId,
        'sender': sender.name,
        'msg_type': type.name,
        'content': content,
        'file_paths': jsonEncode(filePaths),
        'file_sizes': jsonEncode(fileSizes),
        'duration_ms': durationMs,
        'page_count': pageCount,
        'transcribed_text': transcribedText,
        'extracted_text': extractedText,
        'record_json': recordJson,
        'template_id': templateId,
        'record_meta':
            recordMeta != null ? jsonEncode(recordMeta!.toJson()) : null,
        'created_at': createdAt.toIso8601String(),
      };

  factory Message.fromMap(Map<String, dynamic> map) {
    final filePathsRaw = map['file_paths'] as String?;
    final fileSizesRaw = map['file_sizes'] as String?;
    final recordMetaRaw = map['record_meta'] as String?;

    return Message(
      id: map['id'] as String,
      patientId: map['patient_id'] as String,
      sender: MessageSender.values.byName(map['sender'] as String),
      type: MessageType.values.byName(map['msg_type'] as String),
      content: map['content'] as String?,
      filePaths: filePathsRaw != null
          ? List<String>.from(jsonDecode(filePathsRaw))
          : [],
      fileSizes: fileSizesRaw != null
          ? List<int>.from(jsonDecode(fileSizesRaw))
          : [],
      durationMs: map['duration_ms'] as int?,
      pageCount: map['page_count'] as int?,
      transcribedText: map['transcribed_text'] as String?,
      extractedText: map['extracted_text'] as String?,
      recordJson: map['record_json'] as String?,
      templateId: map['template_id'] as String?,
      recordMeta: recordMetaRaw != null && recordMetaRaw.isNotEmpty
          ? RecordMeta.fromJson(
              jsonDecode(recordMetaRaw) as Map<String, dynamic>)
          : null,
      createdAt: DateTime.parse(map['created_at'] as String),
    );
  }
}
