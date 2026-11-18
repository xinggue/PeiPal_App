import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'package:peipal/data/database/database_helper.dart';
import 'package:peipal/data/database/database_path.dart';
import 'package:peipal/data/repositories/generation_log_repository.dart';
import 'package:peipal/data/repositories/message_repository.dart';
import 'package:peipal/data/repositories/patient_repository.dart';
import 'package:peipal/data/repositories/settings_repository.dart';
import 'package:peipal/data/services/ble/record_text.dart';
import 'package:peipal/data/services/ble/typing_done_prefs.dart';
import 'package:peipal/data/services/generation/llm_error_mapper.dart';
import 'package:peipal/data/services/qr/qr_pack_service.dart';
import 'package:peipal/domain/generation/generation_log.dart';
import 'package:peipal/domain/models/message.dart';
import 'package:peipal/domain/models/patient.dart';
import 'package:peipal/domain/models/template.dart';
import 'package:peipal/presentation/pages/chat/record_review_page.dart';
import 'package:peipal/providers/providers.dart';

class _MemPatientRepo extends PatientRepository {
  final Map<String, Patient> _store = {};
  @override
  Future<void> insert(Patient patient) async => _store[patient.id] = patient;
  @override
  Future<Patient?> getById(String id) async => _store[id];
}

class _MemMessageRepo extends MessageRepository {
  final Map<String, Message> _store = {};
  @override
  Future<void> insert(Message message) async => _store[message.id] = message;
  @override
  Future<Message?> getById(String id) async => _store[id];
  @override
  Future<void> update(Message message) async => _store[message.id] = message;
  @override
  Future<List<Message>> getByPatient(String patientId, {int limit = 100, int offset = 0}) async =>
      _store.values.where((m) => m.patientId == patientId).toList();
  @override
  Future<Message?> getLastByPatient(String patientId) async =>
      _store.values.where((m) => m.patientId == patientId).lastOrNull;
}

class _MemLogRepo extends GenerationLogRepository {
  @override
  Future<GenerationLog?> getByMessageId(String messageId) async => null;
}

class _MemSettingsRepo extends SettingsRepository {
  final Map<String, String> _kv = {};
  @override
  Future<String?> get(String key) async => _kv[key];
  @override
  Future<void> set(String key, String value) async => _kv[key] = value;
}

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  group('Record formatting & output defaults', () {
    test('buildTypingText suppresses broken JSON fragments instead of leaking raw braces', () {
      expect(buildTypingText('{"主诉": "发热\t3天'), '');
      expect(buildTypingText('{"主诉": "发热3天"}'), '主诉：发热3天');
      expect(buildTypingText('纯文本内容'), '纯文本内容');
    });

    test('buildReadableRecordText formats ordered slots in plain text and Markdown', () {
      const slots = [
        TemplateSlot(key: 'chief', label: '主诉', type: SlotType.text),
        TemplateSlot(key: 'empty_slot', label: '空项', type: SlotType.text),
        TemplateSlot(key: 'plan', label: '诊疗计划', type: SlotType.multiline),
      ];
      final values = {
        'plan': '1. 补液\n2. 观察',
        'chief': '咳嗽3天',
        'empty_slot': '   ',
        '备注': '加急',
      };

      final plain = buildReadableRecordText(
        values: values,
        orderedSlots: slots,
        title: '门诊病历',
      );
      expect(
        plain,
        '门诊病历\n\n主诉：咳嗽3天\n诊疗计划：1. 补液\n2. 观察\n备注：加急',
      );

      final md = buildReadableRecordText(
        values: values,
        orderedSlots: slots,
        title: '门诊病历',
        markdown: true,
      );
      expect(
        md,
        '# 门诊病历\n\n## 主诉\n咳嗽3天\n\n## 诊疗计划\n1. 补液\n2. 观察\n\n## 备注\n加急',
      );
    });

    test('QrConfig defaults to standard scanner and TypingDonePrefs defaults inAppNotify true', () {
      const qr = QrConfig();
      expect(qr.scannerType, QrScannerType.standard);
      expect(qr.isStandardScanner, isTrue);

      const prefs = TypingDonePrefs();
      expect(prefs.inAppNotify, isTrue);
    });

    test('LlmErrorMapper describes HTTP 402 and classifies config/quota errors', () {
      final err402 = DioException(
        requestOptions: RequestOptions(path: '/chat/completions'),
        response: Response(
          requestOptions: RequestOptions(path: '/chat/completions'),
          statusCode: 402,
        ),
        type: DioExceptionType.badResponse,
      );
      final msg402 = LlmErrorMapper.describe(err402);
      expect(msg402, contains('余额不足'));
      expect(LlmErrorMapper.isConfigOrQuotaErrorText(msg402), isTrue);

      expect(
        LlmErrorMapper.isConfigOrQuotaErrorText('API Key 无效或已过期，请前往「设置」更新'),
        isTrue,
      );
      expect(
        LlmErrorMapper.isConfigOrQuotaErrorText('网络连接失败，请检查手机网络或接口地址设置'),
        isFalse,
      );
    });

    test('JsonEncoder roundtrips tabs, CR, quotes, and backslashes cleanly', () {
      final raw = {'主诉': '咳嗽\t3天\r\n"伴发热"\\持续'};
      final encoded = const JsonEncoder.withIndent('  ').convert(raw);
      final decoded = jsonDecode(encoded) as Map<String, dynamic>;
      expect(decoded['主诉'], raw['主诉']);
    });
  });

  group('MessageRepository partial update & RecordReviewPage guards', () {
    late Directory tempDir;

    setUp(() async {
      await DatabaseHelper.closeDatabase();
      tempDir = await Directory.systemTemp.createTemp('peipal_rec_guard_');
      databasesPathOverride = () async => tempDir.path;
    });

    tearDown(() async {
      await DatabaseHelper.closeDatabase();
      databasesPathOverride = null;
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('updateTextColumns updates only target text column without clobbering concurrent changes', () async {
      await PatientRepository().insert(Patient(id: 'p1', name: '测试'));
      final repo = MessageRepository();
      final msg = Message(
        id: 'v1',
        patientId: 'p1',
        sender: MessageSender.user,
        type: MessageType.voice,
        filePaths: const ['/a/b.wav'],
        fileSizes: const [100],
        durationMs: 1000,
      );
      await repo.insert(msg);

      // Simulate another writer updating filePaths concurrently
      await repo.update(msg.copyWith(filePaths: ['/new/path.wav']));
      // ASR finishes with old placeholder snapshot in memory, calling updateTextColumns
      await repo.updateTextColumns('v1', transcribedText: '主诉咳嗽三天');

      final updated = (await repo.getById('v1'))!;
      expect(updated.transcribedText, '主诉咳嗽三天');
      expect(updated.filePaths, ['/new/path.wav']);
    });

    testWidgets('RecordReviewPage locks save on corrupted JSON and prompts on dirty back navigation', (tester) async {
      final patientRepo = _MemPatientRepo();
      final msgRepo = _MemMessageRepo();
      final logRepo = _MemLogRepo();
      final settingsRepo = _MemSettingsRepo();
      await patientRepo.insert(Patient(id: 'p1', name: '测试患者'));

      final overrides = [
        patientRepositoryProvider.overrideWithValue(patientRepo),
        messageRepositoryProvider.overrideWithValue(msgRepo),
        generationLogRepositoryProvider.overrideWithValue(logRepo),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        favoriteDiagnosesProvider.overrideWith((ref) async => const []),
      ];

      // 1. Corrupted JSON message
      await msgRepo.insert(Message(
        id: 'rec_bad',
        patientId: 'p1',
        sender: MessageSender.system,
        type: MessageType.generatedRecord,
        recordJson: '{"主诉": "含非法未转义\t制表符',
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: const MaterialApp(
            home: RecordReviewPage(patientId: 'p1', messageId: 'rec_bad'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('文书原始内容格式异常'), findsOneWidget);
      final saveBtn = tester.widget<FilledButton>(
        find.ancestor(of: find.text('保存'), matching: find.byType(FilledButton)),
      );
      expect(saveBtn.onPressed, isNull);

      // 2. Valid message: dirty check + save & copy
      String? copiedText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText = (call.arguments as Map)['text'] as String?;
        }
        return null;
      });
      addTearDown(() {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
      });

      await msgRepo.insert(Message(
        id: 'rec_ok',
        patientId: 'p1',
        sender: MessageSender.system,
        type: MessageType.generatedRecord,
        recordJson: jsonEncode({'主诉': '头晕2天'}),
      ));

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp(
            home: Builder(
              builder: (ctx) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      ctx,
                      MaterialPageRoute(
                        builder: (_) => const RecordReviewPage(
                          patientId: 'p1',
                          messageId: 'rec_ok',
                        ),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Edit field -> dirty -> attempt back -> dialog pops up
      await tester.enterText(find.byType(TextField).first, '头晕3天');
      await tester.pump();
      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('有未保存的修改'), findsOneWidget);
      await tester.tap(find.text('继续编辑'));
      await tester.pumpAndSettle();

      // Save & copy whole record
      await tester.tap(find.text('保存并复制全文'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();

      expect(copiedText, contains('头晕3天'));
      final persisted = (await msgRepo.getById('rec_ok'))!;
      expect(jsonDecode(persisted.recordJson!)['主诉'], '头晕3天');
    });
  });
}
