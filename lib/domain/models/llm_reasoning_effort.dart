/// Only expose effort levels documented for these provider/model pairs.
class LlmReasoningEffort {
  static const labels = {
    '': '服务商默认',
    'none': '关闭',
    'low': '低',
    'high': '高',
    'max': '最高',
  };

  static List<String> options(String providerId, String model) {
    final name = model.trim().toLowerCase();
    if (providerId == 'deepseek' &&
        (name == 'deepseek-flash' || name == 'deepseek-v4-pro')) {
      return const ['', 'none', 'low', 'high', 'max'];
    }
    if (providerId == 'zhipu') {
      if (name == 'glm-5.3' || name.startsWith('glm-5.3-')) {
        return const ['', 'low', 'high', 'max'];
      }
      if (name == 'glm-5.2' || name.startsWith('glm-5.2-')) {
        return const ['', 'none', 'low', 'high', 'max'];
      }
    }
    return const [];
  }

  static String resolve(String providerId, String model, String? value) {
    final supported = options(providerId, model);
    if (value == null) return supported.contains('low') ? 'low' : '';
    return supported.contains(value) ? value : '';
  }
}
