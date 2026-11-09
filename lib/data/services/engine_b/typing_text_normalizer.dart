/// 临床击键文本清洁与字符规范化器
class TypingTextNormalizer {
  /// 清洗不可打印字符、零宽字符、统一换行符
  static String normalize(String text) {
    if (text.isEmpty) return '';

    var result = text;

    // 1. 过滤 Unicode 零宽字符（常见于大模型 Markdown 围栏或中文排版中的隐藏字符）
    result = result.replaceAll(RegExp(r'[\u200B-\u200D\uFEFF\u00A0]'), '');

    // 2. 统一 Windows (\r\n) 和老 Mac (\r) 为标准的单个 \n
    //    由于固件遇到 \r 或 \n 都会按下 Enter 键，若不统一，\r\n 就会被固件连打两次回车！
    result = result.replaceAll('\r\n', '\n').replaceAll('\r', '\n');

    // 3. 将正文中偶尔出现的英文半角花括号 '{' 和 '}' 转为中文全角 '｛' 和 '｝'
    //    彻底杜绝正文内容与键盘硬件控制标签 ({TAB}, {ENTER}, {DELAY:...}) 冲突
    result = result.replaceAll('{', '｛').replaceAll('}', '｝');

    return result.trim();
  }

  /// 将多行文本转换为单段安全格式（如果 HIS 单行输入框不允许回车跳出）
  static String flattenMultilineToSingle(String text, {String separator = '；'}) {
    final lines = text
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    return lines.join(separator);
  }
}
