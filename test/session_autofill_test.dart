import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/media/session_autofill_service.dart';

void main() {
  group('SessionAutofillService Local Heuristic Extraction Tests', () {
    test('Extracts labeled medical wristband / admission sheet accurately', () {
      const text = '''
结果来自 PaddleOCR 本地

第一人民医院住院腕带
姓名：张建军  性别：男  年龄：54岁
科室：心血管内科  床号：12床
住院号：ZY20260918
入院诊断：冠心病、高血压3级
''';

      final res = SessionAutofillService.extractLocally(text);
      expect(res.name, '张建军');
      expect(res.gender, 'male');
      expect(res.age, 54);
      expect(res.medicalRecordNumber, 'ZY20260918');
      expect(res.extraData['科室'], '心血管内科');
      expect(res.extraData['床号'], '12床');
      expect(res.notes, '冠心病、高血压3级');
    });

    test('Extracts compact unlabeled wristband text via surname & context heuristics', () {
      const text = '李淑芬 女 62岁 骨科 08床 8902341 13812345678 左股骨颈骨折';

      final res = SessionAutofillService.extractLocally(text);
      expect(res.name, '李淑芬');
      expect(res.gender, 'female');
      expect(res.age, 62);
      expect(res.medicalRecordNumber, '8902341');
      expect(res.extraData['科室'], '骨科');
      expect(res.extraData['床号'], '08床');
      expect(res.extraData['电话'], '13812345678');
    });

    test('Extracts spoken ASR sentence with Chinese numerals and residual notes', () {
      const text = '新收王大锤，男，六十八岁，住院号是330192，呼吸内科15床，反复咳嗽咳痰伴气促三天';

      final res = SessionAutofillService.extractLocally(text);
      expect(res.name, '王大锤');
      expect(res.gender, 'male');
      expect(res.age, 68);
      expect(res.medicalRecordNumber, '330192');
      expect(res.extraData['科室'], '呼吸内科');
      expect(res.extraData['床号'], '15床');
      expect(res.notes, contains('反复咳嗽咳痰伴气促三天'));
    });

    test('Chinese numeral parser handles single, tens, and compound numbers', () {
      expect(SessionAutofillService.parseChineseNumber('五'), 5);
      expect(SessionAutofillService.parseChineseNumber('十'), 10);
      expect(SessionAutofillService.parseChineseNumber('十五'), 15);
      expect(SessionAutofillService.parseChineseNumber('二十'), 20);
      expect(SessionAutofillService.parseChineseNumber('三十八'), 38);
      expect(SessionAutofillService.parseChineseNumber('九十九'), 99);
      expect(SessionAutofillService.parseChineseNumber('一百零二'), 102);
    });
  });
}
