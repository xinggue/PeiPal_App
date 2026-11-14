import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/api/api_config.dart';
import 'package:peipal/domain/models/asr_provider.dart';
import 'package:peipal/domain/models/ocr_provider.dart';
import 'package:peipal/presentation/pages/settings/asr_settings_page.dart';
import 'package:peipal/presentation/pages/settings/ocr_settings_page.dart';
import 'package:peipal/providers/providers.dart';

void main() {
  for (final audio in [true, false]) {
    testWidgets(
      'DeepSeek ${audio ? "ASR" : "OCR"} settings save without a model',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 1800);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final preset = audio
            ? AsrProviderPresets.builtIn
                  .firstWhere((p) => p.id == 'deepseek')
                  .toJson()
            : OcrProviderPresets.builtIn
                  .firstWhere((p) => p.id == 'deepseek')
                  .toJson();
        final prefix = audio ? 'asr' : 'ocr';
        FlutterSecureStorage.setMockInitialValues({
          '${prefix}_providers_matrix_v1': jsonEncode([preset]),
          '${prefix}_active_provider_id_v1': 'deepseek',
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: audio ? const AsrSettingsPage() : const OcrSettingsPage(),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text(preset['name'] as String).last);
        await tester.pumpAndSettle();
        expect(find.text('选用模型名称'), findsNothing);
        expect(find.text('选择模型'), findsNothing);
        expect(find.text('保存 Key 并获取模型列表'), findsNothing);
        expect(find.text('识别语言 (Language)'), findsNothing);
        expect(find.text('未选择模型'), findsNothing);
        final keyField = find.byWidgetPredicate(
          (w) =>
              w is TextField &&
              w.decoration?.labelText ==
                  (audio ? 'API Key' : 'Token / API Key'),
        );
        await tester.enterText(keyField, 'test-deepseek-key');
        await tester.tap(find.text('仅保存'));
        await tester.pumpAndSettle();
        if (audio) {
          expect(
            container.read(asrConfigProvider).provider,
            AsrProvider.deepseek,
          );
          expect(container.read(asrConfigProvider).apiKey, 'test-deepseek-key');
        } else {
          expect(
            container.read(ocrConfigProvider).provider,
            OcrProvider.deepseek,
          );
          expect(container.read(ocrConfigProvider).apiKey, 'test-deepseek-key');
        }
        final raw = await const FlutterSecureStorage().read(
          key: '${prefix}_providers_matrix_v1',
        );
        final saved = (jsonDecode(raw!) as List).firstWhere(
          (p) => p['id'] == 'deepseek',
        );
        expect(saved['protocol'], 'deepseek');
        expect(saved['selectedModel'], '');
        expect(saved['apiKey'], 'test-deepseek-key');

        // Load the global config as on app restart, before the settings page opens.
        final reloaded = ProviderContainer();
        addTearDown(reloaded.dispose);
        if (audio) {
          reloaded.read(asrConfigProvider);
        } else {
          reloaded.read(ocrConfigProvider);
        }
        await tester.pumpAndSettle();
        if (audio) {
          expect(
            reloaded.read(asrConfigProvider).provider,
            AsrProvider.deepseek,
          );
        } else {
          expect(
            reloaded.read(ocrConfigProvider).provider,
            OcrProvider.deepseek,
          );
        }
        await tester.pump(const Duration(seconds: 3));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}
