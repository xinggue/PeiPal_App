import 'package:flutter/material.dart';

class DisclaimerPage extends StatelessWidget {
  const DisclaimerPage({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('免责声明'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
        children: [
          Text(
            '小培同学仅提供语音识别、图像识别与文本输入等调用能力，不提供任何文书内容的生成能力。',
            style: TextStyle(fontSize: 14, height: 1.6, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 16),
          Text(
            '文书内容由你自行选择并配置的第三方 AI 服务生成，其准确性、合规性与完整性由你自行核对并负责。',
            style: TextStyle(fontSize: 14, height: 1.6, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 16),
          Text(
            '所有数据按你的配置发送至相应第三方服务，隐私与数据安全风险由你自行承担。',
            style: TextStyle(fontSize: 14, height: 1.6, color: theme.colorScheme.onSurface),
          ),
        ],
      ),
    );
  }
}
