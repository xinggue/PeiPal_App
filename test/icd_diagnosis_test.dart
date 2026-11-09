import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/icd_service.dart';
import 'package:peipal/domain/models/favorite_diagnosis.dart';
import 'package:peipal/domain/models/icd_diagnosis.dart';

void main() {
  group('IcdService.cleanQuery', () {
    test('strips symbols, ignores punctuation, lowercases letters, preserves numbers and chinese', () {
      expect(IcdService.cleanQuery('2型糖尿病'), '2型糖尿病');
      expect(IcdService.cleanQuery('COVID-19 感染'), 'covid19感染');
      expect(IcdService.cleanQuery('急性ST段抬高型心肌梗死'), '急性st段抬高型心肌梗死');
      expect(IcdService.cleanQuery('(轻度)I度房室传导阻滞'), '轻度i度房室传导阻滞');
      expect(IcdService.cleanQuery('A18.000x067+M90.0*'), 'a18000x067m900');
      expect(IcdService.cleanQuery('  gxb / tnb  '), 'gxbtnb');
    });
  });

  group('IcdDiagnosis Model', () {
    test('parses version list cleanly', () {
      const diag = IcdDiagnosis(
        id: 1,
        code: 'I25.101',
        cleanCode: 'i25101',
        name: '冠状动脉粥样硬化性心脏病',
        cleanName: '冠状动脉粥样硬化性心脏病',
        mixedPy: 'gzayrhxxzb',
        purePy: 'gzayrhxxzb',
        version: '国临2.0 / 医保2.0 / 医保1.0',
      );

      expect(diag.versionList, ['国临2.0', '医保2.0', '医保1.0']);
      expect(diag.purePy, 'gzayrhxxzb');
    });
  });

  group('FavoriteDiagnosis Model', () {
    test('serializes and deserializes cleanly with copyWith for editing', () {
      final fav = FavoriteDiagnosis(
        code: 'I25.101',
        name: '冠心病 (心内科主治版)',
        version: '医保2.0',
        note: '出院首选',
        tags: ['心血管', '门诊常用'],
        order: 1,
      );

      final map = fav.toMap();
      final revived = FavoriteDiagnosis.fromMap(map);

      expect(revived.id, fav.id);
      expect(revived.code, 'I25.101');
      expect(revived.name, '冠心病 (心内科主治版)');
      expect(revived.version, '医保2.0');
      expect(revived.note, '出院首选');
      expect(revived.tags, ['心血管', '门诊常用']);
      expect(revived.order, 1);

      final edited = revived.copyWith(
        name: '冠心病 (新版本)',
        tags: ['慢病'],
      );
      expect(edited.name, '冠心病 (新版本)');
      expect(edited.tags, ['慢病']);
      expect(edited.id, fav.id);
    });
  });
}
