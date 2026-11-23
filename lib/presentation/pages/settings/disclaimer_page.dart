import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/telemetry/telemetry_service.dart';
import '../../../providers/storefront_compliance_provider.dart';

const String kDisclaimerVersion = '2026-11';

/// 统一的匿名使用统计字段说明弹窗（首次引导页与关于页共用）。
Future<void> showTelemetryFieldsDialog(
  BuildContext context, {
  bool mentionCloseSetting = false,
}) {
  final footer = mentionCloseSetting
      ? '不含任何会话内容、生成结果、API 密钥或账号信息，可随时在「关于与帮助」中关闭。'
      : '不含任何会话内容、生成结果、API 密钥或账号信息。';

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('匿名使用统计说明'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '开启后每日最多静默发送一次，仅包含以下 5 项基础字段：',
              style: TextStyle(fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 10),
            ...TelemetryService.reportedFieldsDescription.map(
              (line) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $line',
                  style: const TextStyle(fontSize: 12.5, height: 1.45),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              footer,
              style: const TextStyle(fontSize: 12.5, height: 1.45),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

/// 可复用的免责声明与隐私说明正文（同时用于设置页与首次启动引导弹窗）。
class DisclaimerPrivacyContent extends ConsumerWidget {
  const DisclaimerPrivacyContent({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isAiRestricted = ref.watch(isChinaAiRestrictedProvider);
    final titleStyle = TextStyle(
      fontSize: 14.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );
    final bodyStyle = TextStyle(
      fontSize: 13.5,
      height: 1.6,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('1. 软件定位与免责声明', style: titleStyle),
        const SizedBox(height: 6),
        Text(
          '「小培同学」是一款本地运行的结构化文书助手客户端，仅提供输入采集、文书排版与输出辅助功能；软件本身不内置大语言模型，不提供云端 AI 推理服务，亦不输出任何医疗、法律等专业判断或决策结论。',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),
        Text('2. 本地识别、第三方服务与核验责任', style: titleStyle),
        const SizedBox(height: 6),
        Text(
          isAiRestricted
              ? '当前地区版本默认提供设备端文字识别（Apple Vision）与系统语音识别，同时支持你自行配置第三方图像识别、语音转文字与文档解析接口，以及本地提示词整理功能；不内置或直连第三方云端生成式大语言模型（LLM）接口。如你将整理后的内容复制至外部工具处理并回填，其准确性、完整性与合规性均由你自行核验并承担最终责任；用于医疗、法律等专业场景时，须由具备相应资质的人员复核后方可使用。'
              : '除部分设备端离线文字识别（如内置或系统级本地 OCR）外，语音识别、云端图像识别、文档解析与文本生成均由你自行配置接口并直连第三方服务商完成。所有识别与生成结果的准确性、完整性与合规性均由你自行核验并承担最终责任；用于医疗、法律等专业场景时，须由具备相应资质的人员复核后方可使用。',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),
        Text('3. 本地数据与隐私边界', style: titleStyle),
        const SizedBox(height: 6),
        Text(
          '会话记录、文书模板、词库与 API 密钥均保存在本地设备。除按你的配置直连第三方接口，或你主动访问模板社区外，上述内容不会上传至开发者服务器。',
          style: bodyStyle,
        ),
        const SizedBox(height: 16),
        Text('4. 匿名统计与本地日志', style: titleStyle),
        const SizedBox(height: 6),
        Text(
          '匿名使用统计（可在「关于与帮助」中随时关闭）仅包含随机匿名标识、应用版本号、构建号、操作系统类型与系统版本 5 项基础信息，不含任何会话内容、生成结果、身份信息或密钥。\n'
          '运行日志与异常崩溃记录仅保存在本地设备且对敏感密钥自动脱敏，仅在你主动点击导出或分享时才会离开设备。',
          style: bodyStyle,
        ),
      ],
    );
  }
}

class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('免责声明与隐私说明'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: const [
          DisclaimerPrivacyContent(),
        ],
      ),
    );
  }
}
