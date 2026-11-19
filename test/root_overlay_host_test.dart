import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/presentation/widgets/common/root_overlay_host.dart';

void main() {
  testWidgets(
    'content updates in the current frame without a follow-up frame',
    (tester) async {
      final revision = ValueNotifier(0);
      addTearDown(revision.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: ValueListenableBuilder<int>(
            valueListenable: revision,
            builder: (context, value, child) =>
                RootOverlayHost(child: Text('revision $value')),
          ),
        ),
      );

      for (var i = 1; i <= 20; i++) {
        revision.value = i;
        await tester.pump();
        expect(find.text('revision $i'), findsOneWidget);
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
      }
    },
  );

  testWidgets('overlay remains available to floating text fields', (
    tester,
  ) async {
    final fieldKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RootOverlayHost(
          child: Material(child: TextField(key: fieldKey)),
        ),
      ),
    );
    final overlay = Overlay.of(fieldKey.currentContext!);
    await tester.enterText(find.byType(TextField), '测试输入');
    await tester.pump();
    expect(Overlay.of(fieldKey.currentContext!), same(overlay));
    expect(find.text('测试输入'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });
}
