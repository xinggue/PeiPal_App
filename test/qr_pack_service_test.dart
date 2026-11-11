import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/qr/qr_pack_service.dart';

void main() {
  group('QrPackService', () {
    const sampleTextWithKeys = '【主诉】发热3天{DELAY:80}{ENTER}【现病史】咳嗽伴咽痛{ENTER}';

    test('sanitizeForStandardScanner replaces enter with newline and strips delay/cfg', () {
      final sanitized = QrPackService.sanitizeForStandardScanner(sampleTextWithKeys);
      expect(sanitized, '【主诉】发热3天\n【现病史】咳嗽伴咽痛\n');
      expect(sanitized.contains('{DELAY:80}'), isFalse);
      expect(sanitized.contains('{ENTER}'), isFalse);
    });

    test('Dedicated scanner mode embeds <<SEQ:ID:M/N>> header when long text exceeds chunkSize', () {
      final longText = '这是一个超长文本用于测试专用扫码器的分包逻辑。' * 15;
      final packets = QrPackService.splitText(
        longText,
        chunkSize: 100,
        scannerType: QrScannerType.dedicated,
      );

      expect(packets.length, greaterThan(1));
      for (final p in packets) {
        expect(p.isMultiPart, isTrue);
        expect(p.content.startsWith('<<SEQ:'), isTrue);
        expect(p.sessionId.isNotEmpty, isTrue);
      }
    });

    test('Standard scanner mode strips key commands and outputs plain text slices without SEQ header', () {
      final longTextWithKeys = '$sampleTextWithKeys补充说明信息持续跟进中。' * 8;
      final packets = QrPackService.splitText(
        longTextWithKeys,
        chunkSize: 80,
        scannerType: QrScannerType.standard,
      );

      expect(packets.length, greaterThan(1));
      for (final p in packets) {
        expect(p.isMultiPart, isTrue);
        // 不包含任何 <<SEQ: 前缀
        expect(p.content.startsWith('<<SEQ:'), isFalse);
        expect(p.sessionId, isEmpty);
        // 不包含任何按键控制标签
        expect(p.content.contains('{ENTER}'), isFalse);
        expect(p.content.contains('{DELAY'), isFalse);
        expect(p.content, equals(p.payload));
      }
    });

    test('Short text single packet does not have SEQ header in either mode', () {
      const shortText = '短病历主诉：无殊';
      final dedicated = QrPackService.splitText(
        shortText,
        chunkSize: 200,
        scannerType: QrScannerType.dedicated,
      );
      final standard = QrPackService.splitText(
        shortText,
        chunkSize: 200,
        scannerType: QrScannerType.standard,
      );

      expect(dedicated.length, 1);
      expect(dedicated.first.content, shortText);
      expect(dedicated.first.content.startsWith('<<SEQ:'), isFalse);

      expect(standard.length, 1);
      expect(standard.first.content, shortText);
      expect(standard.first.content.startsWith('<<SEQ:'), isFalse);
    });
  });
}
