import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/ble/ble_service.dart';
import 'package:peipal/presentation/widgets/ble/draggable_typing_overlay.dart';
import 'package:peipal/providers/providers.dart';

import 'tutorial_test.dart' show MockSettingsRepo;

class _Keyboard extends BleService {
  final sent = Completer<bool>();
  int stops = 0;

  @override
  bool get isConnected => true;

  @override
  Future<bool> sendTextDone(
    String text, {
    Duration timeout = const Duration(minutes: 10),
  }) => sent.future;

  @override
  Future<void> emergencyStop() async {
    stops++;
  }
}

const _ball = ValueKey('typing-floating-ball');
const _panel = ValueKey('typing-workbench');

Future<ProviderContainer> _mount(
  WidgetTester tester, {
  bool enabled = true,
  bool alreadyTyping = false,
}) async {
  tester.view.physicalSize = const Size(420, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final settings = MockSettingsRepo()
    ..data['floating_overlay_enabled'] = '$enabled';
  final container = ProviderContainer(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(settings),
      bleServiceProvider.overrideWith((ref) => _Keyboard()),
    ],
  );
  if (alreadyTyping) {
    container
        .read(typingProgressControllerProvider)
        .startTyping(title: '测试输入', text: '测试文字');
  }
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: DraggableTypingOverlay(child: Scaffold())),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  addTearDown(() async {
    container.read(typingProgressControllerProvider).finishTyping();
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  });
  return container;
}

void main() {
  testWidgets('live resize does not restart panel position animations', (
    tester,
  ) async {
    await _mount(tester);
    await tester.tapAt(
      Offset(410, tester.getRect(find.byKey(_ball)).center.dy),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_panel), findsOneWidget);

    for (var i = 0; i < 10; i++) {
      tester.view.physicalSize = Size(420 + i * 10, 880 - i * 10);
      await tester.pump();
      final position = tester.widget<AnimatedPositioned>(
        find.ancestor(
          of: find.byKey(_panel),
          matching: find.byType(AnimatedPositioned),
        ),
      );
      expect(position.duration, Duration.zero);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
    'slow horizontal drags escape both edges before pointer release',
    (tester) async {
      await _mount(tester);
      final ball = find.byKey(_ball);
      final rightStart = tester.getRect(ball);
      final gesture = await tester.startGesture(
        Offset(410, rightStart.center.dy),
      );
      for (var i = 0; i < 50; i++) {
        await gesture.moveBy(const Offset(-3, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getRect(ball).left, lessThan(rightStart.left - 100));
      final beforeVertical = tester.getRect(ball);
      await gesture.moveBy(const Offset(0, 40));
      await tester.pump();
      expect(tester.getRect(ball).top, closeTo(beforeVertical.top + 40, 1));
      await gesture.up();
      await tester.pump();

      await tester.drag(ball, const Offset(-400, 0));
      await tester.pump();
      expect(tester.getRect(ball).left, -28);
      final leftGesture = await tester.startGesture(
        Offset(10, tester.getRect(ball).center.dy),
      );
      for (var i = 0; i < 50; i++) {
        await leftGesture.moveBy(const Offset(3, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.getRect(ball).left, greaterThan(80));
      await leftGesture.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  for (final enabled in [true, false]) {
    testWidgets('typing opens a small window when enabled=$enabled', (
      tester,
    ) async {
      final container = await _mount(tester, enabled: enabled);
      final ctrl = container.read(typingProgressControllerProvider);
      expect(find.byKey(_panel), findsNothing);
      ctrl.startTyping(title: '文书', text: '待输入文字');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getSize(find.byKey(_panel)), const Size(216, 345));
      expect(find.textContaining('剩余'), findsNothing);
      expect(find.text('已用0s'), findsOneWidget);
      expect(find.text('紧急停止'), findsNWidgets(2));
      final stops = find.widgetWithText(FilledButton, '紧急停止');
      expect(tester.getSize(stops.at(0)), tester.getSize(stops.at(1)));
      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.byKey(_panel), findsOneWidget);
      ctrl.finishTyping();
      await tester.pump();
      expect(find.byKey(_panel), enabled ? findsOneWidget : findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('mounting during typing also opens the window', (tester) async {
    final container = await _mount(tester, enabled: false, alreadyTyping: true);
    expect(find.byKey(_panel), findsOneWidget);
    container.read(typingProgressControllerProvider).finishTyping();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending inside either window preserves its size and position', (
    tester,
  ) async {
    final container = await _mount(tester);
    await tester.tapAt(
      Offset(410, tester.getRect(find.byKey(_ball)).center.dy),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    final ctrl = container.read(typingProgressControllerProvider);

    for (final maximize in [false, true]) {
      if (maximize) {
        await tester.tap(find.byIcon(Icons.crop_square_rounded));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 500));
      }
      final before = tester.getRect(find.byKey(_panel));
      ctrl.startTyping(title: '文书', text: '外部发送');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      final during = tester.getRect(find.byKey(_panel));
      expect(during.topLeft, before.topLeft);
      expect(during.width, before.width);
      expect(during.height, before.height + (maximize ? 0 : 80));
      final stops = find.widgetWithText(FilledButton, '紧急停止');
      expect(tester.getSize(stops.at(0)), tester.getSize(stops.at(1)));
      ctrl.finishTyping();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(tester.getRect(find.byKey(_panel)), before);
    }

    final beforeSend = tester.getRect(find.byKey(_panel));
    await tester.enterText(find.byType(TextField), '悬浮窗内发送');
    await tester.tap(find.widgetWithText(FilledButton, '发送文字'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(ctrl.isTyping, isTrue);
    expect(tester.getRect(find.byKey(_panel)), beforeSend);
    expect(find.byType(Dialog), findsNothing);
    (container.read(bleServiceProvider) as _Keyboard).sent.complete(true);
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(ctrl.isTyping, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('typing interrupts minimization and keeps stop available', (
    tester,
  ) async {
    final container = await _mount(tester);
    await tester.tapAt(
      Offset(410, tester.getRect(find.byKey(_ball)).center.dy),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byIcon(Icons.remove_rounded));
    await tester.pump(const Duration(milliseconds: 50));
    final ctrl = container.read(typingProgressControllerProvider);
    ctrl.startTyping(title: '文书', text: '输入');
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(_panel), findsOneWidget);
    expect(find.text('紧急停止'), findsNWidgets(2));
    await tester.tap(find.widgetWithText(FilledButton, '紧急停止').first);
    await tester.pump();
    expect(ctrl.isTyping, isFalse);
    expect((container.read(bleServiceProvider) as _Keyboard).stops, 1);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
  });

  testWidgets('small window grows without overflow when speed options are open', (
    tester,
  ) async {
    final container = await _mount(tester);
    await tester.tapAt(
      Offset(410, tester.getRect(find.byKey(_ball)).center.dy),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('当前输入速度：'));
    await tester.pump();
    final before = tester.getRect(find.byKey(_panel));
    expect(find.byType(Scrollbar), findsOneWidget);
    final ctrl = container.read(typingProgressControllerProvider);
    ctrl.startTyping(title: '文书', text: '输入');
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    final during = tester.getRect(find.byKey(_panel));
    expect(during.height, before.height + 80);
    expect(during.width, before.width);
    expect(find.widgetWithText(FilledButton, '紧急停止').hitTestable(), findsNWidgets(2));
    expect(tester.getSize(find.byType(TextField)).height, greaterThan(40));
    ctrl.finishTyping();
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(tester.takeException(), isNull);
    }
    expect(tester.getRect(find.byKey(_panel)), before);
    expect(find.byType(Scrollbar), findsOneWidget);
  });
}
