import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// 当用户尚未配置 ASR API Key 却尝试使用语音转文字时，弹出与 LLM 配置一致的引导弹窗。
Future<void> showAsrKeyPromptDialog(
  BuildContext context, {
  bool voiceSaved = false,
}) async {
  return showDialog<void>(
    context: context,
    builder: (ctx) {
      final scheme = Theme.of(ctx).colorScheme;
      return AlertDialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
        contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.mic_none_rounded, color: Colors.amber, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  '尚未配置语音识别',
                  maxLines: 1,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                voiceSaved
                    ? '语音消息已为你保存。还没有配置语音识别密钥，请选择接下来的方式：'
                    : '还没有配置语音识别密钥，请选择接下来的方式：',
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.grey.shade700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              KeyPromptOptionCard(
                icon: Icons.key_rounded,
                title: '已有 Key，去配置',
                badge: '去配置',
                subtitle: '点开「语音识别」设置页，填入密钥即可使用。',
                bgColor: scheme.primaryContainer.withValues(alpha: 0.35),
                borderColor: scheme.primary.withValues(alpha: 0.4),
                accentColor: scheme.primary,
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/settings/asr');
                },
              ),
              const SizedBox(height: 10),
              KeyPromptOptionCard(
                icon: Icons.menu_book_rounded,
                title: '没有 Key，查看教程',
                badge: '去获取',
                subtitle: '选择 DeepSeek 或智谱，查看获取教程并一键配置。',
                bgColor: Colors.indigo.shade50,
                borderColor: Colors.indigo.shade300,
                accentColor: Colors.indigo.shade700,
                onTap: () {
                  Navigator.pop(ctx);
                  context.push('/settings/api-key-guides');
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(voiceSaved ? '暂不转写' : '取消'),
          ),
        ],
      );
    },
  );
}

class KeyPromptOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? badge;
  final String subtitle;
  final Color bgColor;
  final Color borderColor;
  final Color accentColor;
  final VoidCallback onTap;

  const KeyPromptOptionCard({
    super.key,
    required this.icon,
    required this.title,
    this.badge,
    required this.subtitle,
    required this.bgColor,
    required this.borderColor,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor),
        ),
        child: Row(
          children: [
            Icon(icon, color: accentColor, size: 22),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: Alignment.centerLeft,
                          child: Text(
                            title,
                            maxLines: 1,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: accentColor,
                            ),
                          ),
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 6),
                        Container(
                          height: 18,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: accentColor,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            badge!,
                            maxLines: 1,
                            strutStyle: const StrutStyle(
                              fontSize: 10,
                              height: 1.0,
                              forceStrutHeight: true,
                            ),
                            style: const TextStyle(
                              fontSize: 10,
                              height: 1.0,
                              leadingDistribution: TextLeadingDistribution.even,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.38,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          ],
        ),
      ),
    );
  }
}
