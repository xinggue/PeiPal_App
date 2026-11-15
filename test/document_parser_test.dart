import 'dart:convert';
import 'dart:io';
import 'package:enough_convert/gbk.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/api/document_parser_config_store.dart';
import 'package:peipal/data/services/document_processing_service.dart';
import 'package:peipal/data/services/media/document_parser_service.dart';
import 'package:peipal/domain/models/document_parse_info.dart';
import 'package:peipal/domain/models/document_parser_provider.dart';
import 'package:peipal/domain/models/message.dart';

void main() {
  test(
    'text decoding supports UTF-8, UTF-16 and GBK without binary fallback',
    () {
      const content = '姓名：张三\n血钠,140\n';
      expect(DocumentParserService.decodeText(utf8.encode(content)), content);
      expect(DocumentParserService.decodeText(gbk.encode(content)), content);
      for (final little in [true, false]) {
        final bytes = <int>[
          if (little) ...[0xff, 0xfe] else ...[0xfe, 0xff],
          for (final unit in content.codeUnits)
            if (little) ...[
              unit & 255,
              unit >> 8,
            ] else ...[
              unit >> 8,
              unit & 255,
            ],
        ];
        expect(DocumentParserService.decodeText(bytes), content);
      }
      expect(
        () => DocumentParserService.decodeText([0xff, 0xfe, 0]),
        throwsFormatException,
      );
      expect(
        () => DocumentParserService.decodeText([0x50, 0x4b, 3, 4]),
        throwsFormatException,
      );
      expect(
        () => DocumentParserService.decodeText([0, 1, 2, 3]),
        throwsFormatException,
      );
      expect(
        () => DocumentParserService.decodeText([0x81]),
        throwsFormatException,
      );
    },
  );

  test(
    'settings are independent, never auto-select, and merge old backups',
    () {
      final defaults = DocumentParserSettings();
      expect(defaults.activeProvider, isNull);
      final zhipu = defaults.providers.last;
      expect(zhipu.toolType, 'prime-sync');
      expect(zhipu.supportedExtensions, containsAll(['pdf', 'wps', 'xlsx']));
      expect(
        defaults.providers.first.supportedExtensions,
        isNot(contains('xlsx')),
      );
      final configured = DocumentParserSettings(
        providers: [
          defaults.providers.first.copyWith(apiKey: 'local-key'),
          zhipu,
        ],
        activeProviderId: 'deepseek',
      );
      final restored = DocumentParserSettings.merge(
        DocumentParserSettings(),
        configured.toJson(),
      );
      expect(restored.activeProvider!.apiKey, 'local-key');
      final merged = DocumentParserSettings.merge(restored, {
        'providers': [
          {'id': 'deepseek', 'apiKey': ''},
          {'id': 'zhipu', 'toolType': 'lite', 'apiKey': 'new-key'},
        ],
      });
      expect(merged.activeProvider!.apiKey, 'local-key');
      expect(merged.providers.last.toolType, 'lite');
      expect(merged.providers.last.supportedExtensions, isNot(contains('wps')));
      expect(merged.providers.last.maxBytes('file.pdf'), 50 * 1024 * 1024);
      expect(
        DocumentParserSettings.merge(merged, {}).toJson(),
        merged.toJson(),
      );
    },
  );

  test(
    'PDF and office formats always require a configured supported service',
    () async {
      final dir = await Directory.systemTemp.createTemp('parser_validation_');
      addTearDown(() => dir.delete(recursive: true));
      final pdf = File('${dir.path}/report.pdf')
        ..writeAsStringSync('%PDF-1.7 local text layer');
      final txt = File('${dir.path}/report.txt')..writeAsStringSync('正文');
      final config = DocumentParserProviderConfig.presets.first.copyWith(
        apiKey: 'key',
      );
      await expectLater(
        DocumentProcessingService.validateFile(pdf.path, null),
        throwsFormatException,
      );
      await DocumentProcessingService.validateFile(pdf.path, config);
      await DocumentProcessingService.validateFile(txt.path, null);
      await expectLater(
        DocumentParserService.parseFileText(pdf.path),
        throwsFormatException,
      );
      final excel = File('${dir.path}/test.xlsx')
        ..writeAsBytesSync([0x50, 0x4b, 3, 4]);
      await expectLater(
        DocumentProcessingService.validateFile(excel.path, config),
        throwsFormatException,
      );
      await DocumentProcessingService.validateFile(
        excel.path,
        DocumentParserProviderConfig.presets.last.copyWith(apiKey: 'key'),
      );
      final renamed = File('${dir.path}/fake.pdf')
        ..writeAsStringSync('not PDF');
      await expectLater(
        DocumentProcessingService.validateFile(renamed.path, config),
        throwsFormatException,
      );
    },
  );

  test(
    'message stores state separately and never treats errors as material',
    () {
      final legacy = Message.document(
        patientId: 'p',
        filePath: '/file.pdf',
        fileSize: 3,
        fileName: '文件名.pdf',
        extractedText: '文件提取失败: error',
      );
      expect(legacy.usableDocumentText, isEmpty);
      expect(legacy.documentNeedsAttention, isTrue);
      final good = legacy.copyWith(
        extractedText: '| 项目 | 结果 |\n| 钠 | 140 |',
        documentParse: const DocumentParseInfo(
          status: DocumentParseStatus.success,
          attemptId: 'run',
          hasResult: true,
        ),
      );
      final restored = Message.fromMap(good.toMap());
      expect(restored.usableDocumentText, contains('140'));
      expect(restored.documentNeedsAttention, isFalse);
      final failure = good.copyWith(
        documentParse: good.documentParse!.copyWith(
          status: DocumentParseStatus.failed,
          error: '请求超时',
        ),
      );
      expect(failure.usableDocumentText, good.usableDocumentText);
      expect(failure.documentNeedsAttention, isTrue);
      expect(failure.usableDocumentText, isNot(contains('超时')));
    },
  );
}
