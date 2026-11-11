import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/update/app_update_service.dart';

void main() {
  group('AppUpdateService.isVersionNewer', () {
    test('detects newer minor and patch versions correctly', () {
      expect(AppUpdateService.isVersionNewer('v0.1.2', '0.1.1'), isTrue);
      expect(AppUpdateService.isVersionNewer('v0.2.0', '0.1.1'), isTrue);
      expect(AppUpdateService.isVersionNewer('v1.0.0', '0.1.1'), isTrue);
      expect(AppUpdateService.isVersionNewer('0.1.2+12', '0.1.1+10'), isTrue);
    });

    test('returns false when latest is equal or older', () {
      expect(AppUpdateService.isVersionNewer('v0.1.1', '0.1.1'), isFalse);
      expect(AppUpdateService.isVersionNewer('v0.1.0', '0.1.1'), isFalse);
      expect(AppUpdateService.isVersionNewer('0.1.1+10', '0.1.1+10'), isFalse);
      expect(AppUpdateService.isVersionNewer('', '0.1.1'), isFalse);
    });
  });
}
