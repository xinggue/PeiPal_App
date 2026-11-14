import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class ApiKeyGuidesPage extends StatelessWidget {
  const ApiKeyGuidesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('获取 API Key')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          _ProviderGuideCard(
            name: 'DeepSeek',
            iconAsset: 'assets/icons/deepseek.png',
            description: '价格亲民，响应快，适合日常使用。',
            accent: const Color(0xFF4D6BFE),
            tint: const Color(0xFFEDF2FF),
            onTap: () => context.push('/settings/deepseek-key-guide'),
          ),
          const SizedBox(height: 16),
          _ProviderGuideCard(
            name: '智谱',
            iconAsset: 'assets/icons/zhipu.png',
            description: '新用户有免费额度，适合先体验。',
            accent: const Color(0xFF67559B),
            tint: const Color(0xFFF3EFFA),
            onTap: () => context.push('/settings/zhipu-key-guide'),
          ),
        ],
      ),
    );
  }
}

class _ProviderGuideCard extends StatelessWidget {
  final String name;
  final String iconAsset;
  final String description;
  final Color accent;
  final Color tint;
  final VoidCallback onTap;

  const _ProviderGuideCard({
    required this.name,
    required this.iconAsset,
    required this.description,
    required this.accent,
    required this.tint,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final radius = BorderRadius.circular(24);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: dark ? 0.05 : 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: scheme.surface,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: accent.withValues(alpha: 0.16)),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                dark
                    ? Color.alphaBlend(
                        accent.withValues(alpha: 0.16),
                        scheme.surface,
                      )
                    : tint,
                scheme.surface,
              ],
            ),
          ),
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: accent.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Image.asset(
                          iconAsset,
                          excludeFromSemantics: true,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          name,
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w600,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    description,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '文本 · 识图 · 语音',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        '查看教程',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: dark ? scheme.onSurface : accent,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward_rounded,
                        size: 17,
                        color: dark ? scheme.onSurface : accent,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
