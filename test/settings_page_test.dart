import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/ble/ble_service.dart';
import 'package:peipal/presentation/pages/settings/settings_page.dart';
import 'package:peipal/providers/providers.dart';

import 'tutorial_test.dart' show MockSettingsRepo;

class _ConnectedBle extends BleService {
  @override
  bool get isConnected => true;

  @override
  String? get connectedName => 'ESP32S3 键盘_01';
}

void main() {
  testWidgets(
    'SettingsPage shows inline-code badges for active status/models, renames 特殊字符替换, and removes gray explanatory subtitles',
    (tester) async {
      tester.view.physicalSize = const Size(412, 915);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FlutterSecureStorage.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(MockSettingsRepo()),
          secureStorageProvider.overrideWithValue(const FlutterSecureStorage()),
          bleServiceProvider.overrideWith((_) => _ConnectedBle()),
        ],
      );
      addTearDown(container.dispose);

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: SettingsPage()),
        ),
      );
      await tester.pumpAndSettle();

      // 1. 保留摘要胶囊并展示蓝牙连接状态与设备名
      expect(find.text('已连接'), findsOneWidget);
      expect(find.text('ESP32S3 键盘_01'), findsOneWidget);

      // 2. 更名为「特殊字符替换」并保留所有核心入口（滑到底部校验下方入口）
      expect(find.text('特殊字符替换'), findsOneWidget);
      expect(find.text('字符替换'), findsNothing);
      expect(find.text('二维码'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pumpAndSettle();
      expect(find.text('会话数据备份与恢复'), findsOneWidget);
      expect(find.text('模板与配置导入导出'), findsOneWidget);
      expect(find.text('关于与帮助'), findsOneWidget);

      // 3. 去掉静态解释性小灰字与冗余副标题
      expect(find.text('系统提示词与阶段生成编排'), findsNothing);
      expect(find.text('打字节奏、按键延迟与时序预设'), findsNothing);
      expect(find.textContaining('单包限额'), findsNothing);
      expect(find.textContaining('条替换规则'), findsNothing);
      expect(find.text('备份或恢复会话、消息、结果与媒体'), findsNothing);
      expect(find.textContaining('AI 密钥与系统参数'), findsNothing);
      expect(find.textContaining('版本检测、新手教程'), findsNothing);
    },
  );
}
