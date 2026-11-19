import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:peipal/data/services/logging/app_log_service.dart';
import 'package:peipal/data/services/telemetry/telemetry_service.dart';
import 'package:peipal/presentation/pages/onboarding/onboarding_flow.dart';
import 'package:peipal/presentation/pages/settings/about_page.dart';
import 'package:peipal/presentation/pages/settings/disclaimer_page.dart';
import 'package:peipal/providers/providers.dart';

import 'tutorial_test.dart' show MockSettingsRepo;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLogService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('peipal_log_test_');
      AppLogService.resetForTesting();
      AppLogService.directoryOverride = () async => tempDir;
    });

    tearDown(() async {
      AppLogService.directoryOverride = null;
      AppLogService.resetForTesting();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    test('sanitizes secrets and API keys before writing', () async {
      final log = AppLogService.instance;
      log.info(
        'Net',
        'Authorization: Bearer abcdef123456 sk-secretkey998877 apiKey="my-secret-value"',
      );
      await log.flush();

      final content = await File(p.join(tempDir.path, 'app.log')).readAsString();
      expect(content, isNot(contains('abcdef123456')));
      expect(content, isNot(contains('sk-secretkey998877')));
      expect(content, isNot(contains('my-secret-value')));
      expect(content, contains('Bearer ***'));
      expect(content, contains('sk-***'));
    });

    test('rotates runtime logs at 512KB and caps at 5 files', () async {
      final log = AppLogService.instance;
      final bigLine = 'X' * 1900;
      // Write ~3000KB across iterations -> should rotate multiple times and cap at app.log + .1..4
      for (var i = 0; i < 1600; i++) {
        log.info('Rot', '$i $bigLine');
      }
      await log.flush();

      final files = tempDir
          .listSync()
          .whereType<File>()
          .map((f) => p.basename(f.path))
          .toList()
        ..sort();
      expect(files, contains('app.log'));
      expect(files, contains('app.log.1'));
      expect(files, contains('app.log.4'));
      expect(files.contains('app.log.5'), isFalse);

      final stats = await log.getStats();
      expect(stats.fileCount, lessThanOrEqualTo(5));
    });

    test('retains up to 20 crash entries and builds diagnostic report', () async {
      final log = AppLogService.instance;
      for (var i = 1; i <= 25; i++) {
        await log.recordCrash('Zone', StateError('crash-$i'));
      }
      final stats = await log.getStats();
      expect(stats.crashCount, 20);

      final crashContent =
          await File(p.join(tempDir.path, 'crash.log')).readAsString();
      expect(crashContent, isNot(contains('crash-1\n')));
      expect(crashContent, contains('crash-25'));

      final report = await log.buildDiagnosticReport(
        configSummary: {'LLM': 'DeepSeek apiKey=sk-secret999'},
      );
      expect(report, contains('PeiPal 诊断日志'));
      expect(report, contains('crash-25'));
      expect(report, isNot(contains('sk-secret999')));
    });
  });

  group('TelemetryService', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('peipal_telemetry_test_');
    });

    tearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    Dio mockTelemetryDio(List<Map<String, dynamic>> captured) {
      final dio = Dio();
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            captured.add(Map<String, dynamic>.from(options.data as Map));
            handler.resolve(
              Response(
                requestOptions: options,
                statusCode: 200,
                data: {'ok': true},
              ),
            );
          },
        ),
      );
      return dio;
    }

    PackageInfo fakePkg() => PackageInfo(
          appName: '小培同学',
          packageName: 'com.xinggue.docmasterPei',
          version: '0.1.8',
          buildNumber: '26',
        );

    test('does not ping before onboarding completes or when disabled', () async {
      final settings = MockSettingsRepo();
      final sent = <Map<String, dynamic>>[];
      final dio = mockTelemetryDio(sent);
      addTearDown(dio.close);

      final service = TelemetryService(
        settings,
        dio: dio,
        supportDirProvider: () async => tempDir,
        clock: () => DateTime(2026, 11, 18, 10),
        packageInfoProvider: () async => fakePkg(),
      );

      // Not onboarded yet
      expect(await service.pingIfNeeded(), isFalse);
      expect(sent, isEmpty);

      // Onboarded, but user opted out
      await settings.set('onboarding_completed', 'true');
      await service.setEnabled(false);
      expect(await service.pingIfNeeded(), isFalse);
      expect(sent, isEmpty);
    });

    test('pings once per day with only 5 whitelisted fields and reuses anon_id', () async {
      final settings = MockSettingsRepo();
      await settings.set('onboarding_completed', 'true');
      final sent = <Map<String, dynamic>>[];
      final dio = mockTelemetryDio(sent);
      addTearDown(dio.close);

      var now = DateTime(2026, 11, 18, 9);
      final service = TelemetryService(
        settings,
        dio: dio,
        supportDirProvider: () async => tempDir,
        clock: () => now,
        packageInfoProvider: () async => fakePkg(),
      );

      expect(await service.pingIfNeeded(), isTrue);
      expect(sent, hasLength(1));
      expect(
        sent.first.keys.toSet(),
        {'anon_id', 'app_version', 'build_number', 'platform', 'os_version'},
      );
      expect(sent.first['app_version'], '0.1.8');
      expect(sent.first['build_number'], '26');

      // Same day second call -> skipped
      now = DateTime(2026, 11, 18, 22);
      expect(await service.pingIfNeeded(), isFalse);
      expect(sent, hasLength(1));

      // Next day -> sends again with identical anon_id
      now = DateTime(2026, 11, 19, 8);
      expect(await service.pingIfNeeded(), isTrue);
      expect(sent, hasLength(2));
      expect(sent[1]['anon_id'], sent[0]['anon_id']);
    });
  });

  group('Onboarding consent & About diagnostics UI', () {
    testWidgets(
      'Onboarding Page 0 enforces disclaimer acceptance and allows independent telemetry opt-out',
      (tester) async {
        tester.view.physicalSize = const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        FlutterSecureStorage.setMockInitialValues({});
        final settings = MockSettingsRepo();

        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              secureStorageProvider.overrideWithValue(
                const FlutterSecureStorage(),
              ),
              settingsRepositoryProvider.overrideWithValue(settings),
            ],
            child: const MaterialApp(home: OnboardingFlow()),
          ),
        );
        await tester.pumpAndSettle();

        final checkboxes = find.byType(Checkbox);
        expect(checkboxes, findsNWidgets(2));
        expect(tester.widget<Checkbox>(checkboxes.at(0)).value, isFalse);
        expect(tester.widget<Checkbox>(checkboxes.at(1)).value, isTrue);

        // Uncheck telemetry independently -> start button remains disabled until disclaimer is checked
        await tester.tap(checkboxes.at(1));
        await tester.pumpAndSettle();
        expect(tester.widget<Checkbox>(checkboxes.at(1)).value, isFalse);
        expect(
          tester.widget<FilledButton>(find.widgetWithText(FilledButton, '开始')).onPressed,
          isNull,
        );

        // Open disclaimer dialog via tappable link text and accept
        await tester.tapOnText(find.textRange.ofSubstring('《免责声明与隐私说明》'));
        await tester.pumpAndSettle();
        expect(find.text('1. 软件定位与免责声明'), findsOneWidget);
        expect(find.textContaining('结构化文书助手客户端'), findsOneWidget);
        expect(find.textContaining('离线文字识别'), findsOneWidget);
        expect(find.textContaining('医疗、法律等专业场景'), findsOneWidget);
        expect(find.textContaining('患者'), findsNothing);
        expect(find.textContaining('医学诊断建议'), findsNothing);
        await tester.tap(find.text('阅读并同意'));
        await tester.pumpAndSettle();

        // Check telemetry help dialog wording
        await tester.tap(find.byIcon(Icons.help_outline_rounded));
        await tester.pumpAndSettle();
        expect(find.text('匿名使用统计说明'), findsOneWidget);
        expect(find.textContaining('不含任何会话内容、生成结果'), findsOneWidget);
        expect(find.textContaining('患者'), findsNothing);
        await tester.tap(find.text('知道了'));
        await tester.pumpAndSettle();

        expect(tester.widget<Checkbox>(checkboxes.at(0)).value, isTrue);
        await tester.tap(find.text('开始'));
        await tester.pumpAndSettle();

        expect(find.text('开启所需权限'), findsOneWidget);
        expect(settings.data['disclaimer_accepted_version'], kDisclaimerVersion);
        expect(settings.data['telemetry_enabled'], 'false');
      },
    );

    testWidgets('AboutPage renders diagnostics & telemetry toggle', (tester) async {
      FlutterSecureStorage.setMockInitialValues({});
      final settings = MockSettingsRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            secureStorageProvider.overrideWithValue(
              const FlutterSecureStorage(),
            ),
            settingsRepositoryProvider.overrideWithValue(settings),
          ],
          child: const MaterialApp(home: AboutPage()),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      await tester.scrollUntilVisible(
        find.text('免责声明与隐私说明'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('诊断与统计'), findsOneWidget);
      expect(find.text('导出诊断日志'), findsOneWidget);
      expect(find.text('匿名使用统计'), findsOneWidget);
      expect(find.textContaining('病历生成流程'), findsNothing);

      await tester.tap(find.byIcon(Icons.help_outline_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('匿名使用统计说明'), findsOneWidget);
      expect(find.textContaining('不含任何会话内容、生成结果'), findsOneWidget);
      await tester.tap(find.text('知道了'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(settings.data['telemetry_enabled'], 'false');
    });
  });
}
