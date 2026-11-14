import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/domain/models/llm_provider.dart';
import 'package:peipal/domain/models/llm_reasoning_effort.dart';

void main() {
  group('LlmProviderConfig and Presets', () {
    test(
      'unset effort defaults low while explicit provider defaults survive',
      () {
        for (final preset in LlmProviderPresets.builtIn.where(
          (p) => p.id == 'deepseek' || p.id == 'zhipu',
        )) {
          expect(preset.reasoningEffort, 'low');
          final explicitDefault = preset.copyWith(
            reasoningEfforts: {preset.selectedModel: ''},
          );
          expect(explicitDefault.reasoningEffort, '');
          expect(
            LlmProviderConfig.fromJson(
              explicitDefault.toJson(),
            ).reasoningEffort,
            '',
          );
        }
        expect(LlmReasoningEffort.resolve('zhipu', 'glm-5.2', null), 'low');
        expect(LlmReasoningEffort.resolve('deepseek', 'unknown', null), '');
        expect(
          LlmReasoningEffort.resolve('custom', 'deepseek-flash', null),
          '',
        );
      },
    );

    test(
      'effort choices follow model capabilities and survive serialization',
      () {
        final deepseek = LlmProviderPresets.builtIn.first.copyWith(
          selectedModel: 'deepseek-v4-pro',
          reasoningEfforts: {
            'deepseek-v4-pro': 'max',
            'deepseek-flash': 'none',
          },
        );
        final restored = LlmProviderConfig.fromJson(deepseek.toJson());
        expect(restored.reasoningEffort, 'max');
        expect(
          restored.copyWith(selectedModel: 'deepseek-flash').reasoningEffort,
          'none',
        );
        expect(
          restored.copyWith(selectedModel: 'deepseek-chat').reasoningEffort,
          '',
        );
        expect(restored.copyWith(id: 'custom').reasoningEffort, '');
        expect(LlmReasoningEffort.options('zhipu', 'GLM-5.3-FlashX'), [
          '',
          'low',
          'high',
          'max',
        ]);
        expect(LlmReasoningEffort.options('zhipu', 'glm-5.2'), [
          '',
          'none',
          'low',
          'high',
          'max',
        ]);
        expect(LlmReasoningEffort.options('zhipu', 'glm-4.7'), isEmpty);
        expect(LlmReasoningEffort.resolve('zhipu', 'glm-5.3', 'none'), '');
        final legacy = Map<String, dynamic>.from(deepseek.toJson())
          ..remove('reasoningEfforts');
        expect(LlmProviderConfig.fromJson(legacy).reasoningEffort, 'low');
      },
    );

    test(
      'LlmProviderPresets contains major providers including Xiaomi MiMo',
      () {
        final presets = LlmProviderPresets.builtIn;
        expect(presets.length, greaterThanOrEqualTo(8));

        final deepseek = presets.firstWhere((p) => p.id == 'deepseek');
        expect(deepseek.name, contains('DeepSeek'));
        expect(deepseek.baseUrl, 'https://api.deepseek.com');
        expect(deepseek.selectedModel, 'deepseek-flash');
        expect(deepseek.reasoningEffort, 'low');

        final mimo = presets.firstWhere((p) => p.id == 'mimo');
        expect(mimo.name, contains('小米'));
        expect(mimo.baseUrl, contains('xiaomimimo'));

        final silicon = presets.firstWhere((p) => p.id == 'siliconflow');
        expect(silicon.name, contains('硅基流动'));

        final zhipu = presets.firstWhere((p) => p.id == 'zhipu');
        expect(zhipu.name, contains('智谱'));
        expect(zhipu.selectedModel, 'glm-5.3-flashx');
        expect(zhipu.reasoningEffort, 'low');

        // 确保不包含零一万物
        expect(presets.any((p) => p.id == 'yi'), isFalse);
      },
    );

    test('LlmProviderConfig JSON round-trip serialization', () {
      const config = LlmProviderConfig(
        id: 'test_provider',
        name: '测试供应商',
        description: '测试描述',
        defaultBaseUrl: 'https://test.api.com/v1',
        baseUrl: 'https://custom.test.api.com/v1',
        apiKey: 'sk-test123456',
        selectedModel: 'test-model-v1',
        customModels: ['cloud-model-1', 'cloud-model-2'],
        isEnabled: true,
        balance: '￥88.50',
      );

      final json = config.toJson();
      final restored = LlmProviderConfig.fromJson(json);

      expect(restored.id, 'test_provider');
      expect(restored.name, '测试供应商');
      expect(restored.baseUrl, 'https://custom.test.api.com/v1');
      expect(restored.apiKey, 'sk-test123456');
      expect(restored.selectedModel, 'test-model-v1');
      expect(restored.allModels, contains('test-model-v1'));
      expect(restored.allModels, contains('cloud-model-1'));
      expect(restored.allModels, contains('cloud-model-2'));
      expect(restored.balance, '￥88.50');
      expect(restored.isConfigured, isTrue);
    });
  });
}
