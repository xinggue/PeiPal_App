import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/domain/models/llm_provider.dart';

void main() {
  group('LlmProviderConfig and Presets', () {
    test('LlmProviderPresets contains major providers including Xiaomi MiMo', () {
      final presets = LlmProviderPresets.builtIn;
      expect(presets.length, greaterThanOrEqualTo(8));

      final deepseek = presets.firstWhere((p) => p.id == 'deepseek');
      expect(deepseek.name, contains('DeepSeek'));
      expect(deepseek.baseUrl, 'https://api.deepseek.com');
      expect(deepseek.selectedModel, 'deepseek-chat');

      final mimo = presets.firstWhere((p) => p.id == 'mimo');
      expect(mimo.name, contains('小米'));
      expect(mimo.baseUrl, contains('xiaomimimo'));

      final silicon = presets.firstWhere((p) => p.id == 'siliconflow');
      expect(silicon.name, contains('硅基流动'));

      final zhipu = presets.firstWhere((p) => p.id == 'zhipu');
      expect(zhipu.name, contains('智谱'));

      // 确保不包含零一万物
      expect(presets.any((p) => p.id == 'yi'), isFalse);
    });

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
