import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:peipal/data/services/ble/ble_service.dart';
import 'package:peipal/data/services/ble/timing_params.dart';
import 'package:peipal/presentation/pages/settings/ble_connect_page.dart';
import 'package:peipal/presentation/widgets/ble/speed_preset_selector.dart';
import 'package:peipal/providers/providers.dart';

import 'tutorial_test.dart' show MockSettingsRepo;

class _TestBleService extends BleService {
  bool connected = false;
  String? name;
  String? remoteId;
  final List<BleDeviceInfo> scanList;

  _TestBleService({this.scanList = const []});

  @override
  BleConnectionStatus get status =>
      connected ? BleConnectionStatus.connected : BleConnectionStatus.disconnected;

  @override
  bool get isConnected => connected;

  @override
  String? get connectedName => name;

  @override
  String? get connectedRemoteId => remoteId;

  @override
  Future<bool> ensureAdapterOn() async => true;

  @override
  Future<List<BleDeviceInfo>> scan({
    Duration timeout = const Duration(seconds: 8),
    void Function(List<BleDeviceInfo> currentList)? onDiscovered,
  }) async {
    return scanList;
  }

  @override
  Future<bool> connectTo(BleDeviceInfo info) async {
    connected = true;
    name = info.name;
    remoteId = info.remoteId;
    notifyListeners();
    return true;
  }

  @override
  Future<bool> sendCommand(String command) async => true;
}

void main() {
  testWidgets(
    'BleConnectPage removes redundant copy, embeds speed grid, orders sections, and hides disabled banner chip',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterSecureStorage.setMockInitialValues({});
      final settings = MockSettingsRepo();
      final ble = _TestBleService(
        scanList: const [
          BleDeviceInfo(remoteId: 'AA:BB', name: 'ESP32S3 键盘_01', rssi: -52),
        ],
      );

      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const BleConnectPage(),
          ),
          GoRoute(
            path: '/settings/timing',
            builder: (_, _) => const Scaffold(body: Text('TIMING_FINE_TUNE')),
          ),
          GoRoute(
            path: '/settings/char-replacement',
            builder: (_, _) => const Scaffold(body: Text('CHAR_REPLACEMENT_PAGE')),
          ),
        ],
      );

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          bleServiceProvider.overrideWith((_) => ble),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 冗余说明小字、外部蓝色小字标题与无效开关已移除
      expect(find.text('在任意界面快速贴入文字、切换速度与执行快捷动作'), findsNothing);
      expect(find.text('管理可在悬浮窗一键触发的按键与文字序列'), findsNothing);
      expect(find.text('长文本由设备打完后再提醒'), findsNothing);
      expect(find.text('点击预设载入测试内容，发送过程可通过全局悬浮窗实时监控与紧急停止。'), findsNothing);
      expect(find.text('已匹配'), findsNothing);
      expect(find.text('系统横幅通知'), findsNothing);
      expect(find.text('悬浮窗与提醒'), findsNothing);

      // 2. 初始未扫描时设备列表收起（不占位）
      expect(find.textContaining('未发现设备'), findsNothing);

      // 3. 保留可用提醒芯片，并验证自上而下排列顺序：扫描 -> 测试输入 -> 键盘参数与输入速度 -> 悬浮窗/快捷动作库/特殊字符替换
      expect(find.text('应用内通知'), findsOneWidget);
      expect(find.text('震动'), findsOneWidget);
      expect(find.byType(SpeedPresetSquareGrid), findsOneWidget);
      expect(find.text('测试输入'), findsOneWidget);
      expect(find.text('微调参数'), findsOneWidget);
      expect(find.textContaining('· 微调'), findsNothing);
      expect(find.text('特殊字符替换'), findsOneWidget);

      final scanY = tester.getTopLeft(find.text('扫描设备')).dy;
      final testY = tester.getTopLeft(find.text('测试输入')).dy;
      final speedY = tester.getTopLeft(find.text('键盘参数与输入速度')).dy;
      final overlayY = tester.getTopLeft(find.text('全局键盘悬浮窗')).dy;
      final quickPresetY = tester.getTopLeft(find.text('快捷动作预设库')).dy;
      final charReplaceY = tester.getTopLeft(find.text('特殊字符替换')).dy;
      expect(scanY, lessThan(testY));
      expect(testY, lessThan(speedY));
      expect(speedY, lessThan(overlayY));
      expect(quickPresetY, lessThan(charReplaceY));

      // 4. 点击测试预设按钮后，依然保留说明框
      await tester.ensureVisible(find.text('特殊字符'));
      await tester.tap(find.text('特殊字符'));
      await tester.pumpAndSettle();
      expect(find.text('会打出常用特殊符号示例。'), findsOneWidget);

      // 5. 内嵌方格速度阵列可直接切换预设
      final fastest = kBuiltInTimingPresets.first;
      final fastestSpeed = fastest.estimatedCharsPerSec.toStringAsFixed(0);
      await tester.ensureVisible(find.byType(SpeedPresetSquareGrid));
      await tester.tap(
        find.descendant(
          of: find.byType(SpeedPresetSquareGrid),
          matching: find.text(fastestSpeed),
        ).first,
      );
      await tester.pumpAndSettle();
      expect(find.text('已选：${fastest.name}'), findsOneWidget);

      // 6. 扫描后连接设备，连接成功列表自动收起
      await tester.pump(const Duration(seconds: 4));
      await tester.drag(find.byType(ListView).first, const Offset(0, 800));
      await tester.pumpAndSettle();
      await tester.tap(find.text('扫描设备'));
      await tester.pumpAndSettle();
      expect(find.text('ESP32S3 键盘_01'), findsOneWidget);

      await tester.tap(find.text('ESP32S3 键盘_01'));
      await tester.pumpAndSettle();
      expect(ble.isConnected, isTrue);
      expect(find.text('附近的设备 (1)'), findsNothing);

      // 7. 点击“微调参数”可进入参数微调页
      await tester.ensureVisible(find.text('微调参数'));
      await tester.tap(find.text('微调参数'));
      await tester.pumpAndSettle();
      expect(find.text('TIMING_FINE_TUNE'), findsOneWidget);

      // 返回后点击“特殊字符替换”可进入特殊字符替换页
      router.pop();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('特殊字符替换'));
      await tester.tap(find.text('特殊字符替换'));
      await tester.pumpAndSettle();
      expect(find.text('CHAR_REPLACEMENT_PAGE'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'SpeedPresetSquareGrid fits 8 presets into a single Row without horizontal ListView',
    (tester) async {
      tester.view.physicalSize = const Size(360, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterSecureStorage.setMockInitialValues({});
      final customPresets = [
        ...kBuiltInTimingPresets,
        TimingPreset(
          id: 'custom_1',
          name: '自定义7',
          values: kBuiltInTimingPresets.first.values,
        ),
        TimingPreset(
          id: 'custom_2',
          name: '自定义8',
          values: kBuiltInTimingPresets.last.values,
        ),
      ];
      final settings = MockSettingsRepo()
        ..data['timing_presets_list'] = encodePresetsListJson(customPresets);

      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(settings),
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(
              body: Padding(
                padding: EdgeInsets.all(16),
                child: SpeedPresetSquareGrid(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ListView), findsNothing);
      expect(find.text('字/秒'), findsNWidgets(8));
    },
  );
}
