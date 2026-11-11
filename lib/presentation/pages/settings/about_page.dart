import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/services/update/app_update_service.dart';
import '../../../providers/providers.dart';
import '../../../providers/tutorial_provider.dart';
import '../../widgets/common/app_toast.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  bool _isCheckingUpdate = false;
  AppUpdateInfo? _updateInfo;
  String? _checkError;

  @override
  void initState() {
    super.initState();
    _checkUpdateSilently();
  }

  Future<void> _checkUpdateSilently() async {
    setState(() {
      _isCheckingUpdate = true;
      _checkError = null;
    });
    try {
      final info = await AppUpdateService.checkForUpdate();
      if (mounted) {
        setState(() {
          _updateInfo = info;
          _isCheckingUpdate = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _checkError = '检查更新失败，请稍后重试';
          _isCheckingUpdate = false;
        });
      }
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.tryParse(url);
    bool launched = false;
    if (uri != null) {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (!launched && mounted) {
      await Clipboard.setData(ClipboardData(text: url));
      if (mounted) {
        showAppToast(context, '已复制链接到剪贴板');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('关于与帮助'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // 头部：品牌与版本信息
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: Image.asset(
                      'assets/icons/app_icon.png',
                      errorBuilder: (_, _, _) => Icon(
                        Icons.edit_note_rounded,
                        size: 40,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'PeiPal',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'v${AppUpdateService.currentVersion} (Build ${AppUpdateService.currentBuildNumber})',
                    style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 8),

          // 1. 版本更新检测
          _buildGroupLabel('版本更新'),
          _buildCard([
            ListTile(
              leading: Icon(
                _updateInfo?.hasUpdate == true
                    ? Icons.system_update_rounded
                    : Icons.check_circle_outline_rounded,
                color: _updateInfo?.hasUpdate == true ? Colors.orange : Colors.teal,
              ),
              title: Text(
                _isCheckingUpdate
                    ? '正在检查新版本…'
                    : (_updateInfo?.hasUpdate == true
                        ? '发现新版本 ${_updateInfo!.latestVersion}'
                        : '当前已是最新版本'),
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
              ),
              subtitle: Text(
                _isCheckingUpdate
                    ? '连接更新服务器中'
                    : (_checkError ??
                        (_updateInfo?.hasUpdate == true
                            ? '建议及时更新以获取最新特性与优化'
                            : '当前版本：v${AppUpdateService.currentVersion}')),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: _isCheckingUpdate
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: '重新检测',
                      onPressed: _checkUpdateSilently,
                    ),
            ),
            if (_updateInfo?.hasUpdate == true) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_updateInfo?.releaseNotes != null && _updateInfo!.releaseNotes!.isNotEmpty) ...[
                      Text(
                        _updateInfo!.releaseNotes!,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant, height: 1.4),
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 10),
                    ],
                    Row(
                      children: [
                        if (_updateInfo?.downloadUrl != null) ...[
                          Expanded(
                            child: FilledButton.icon(
                              icon: const Icon(Icons.download_rounded, size: 16),
                              label: const Text('下载安装包'),
                              onPressed: () => _openUrl(_updateInfo!.downloadUrl!),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_browser_rounded, size: 16),
                            label: const Text('查看发行版'),
                            onPressed: () => _openUrl(_updateInfo!.releasePageUrl),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ]),

          const SizedBox(height: 16),

          // 2. 新手教程与演练（仅收录已完成真实功能，杜绝占位）
          _buildGroupLabel('新手教程'),
          _buildCard([
            ListTile(
              leading: const Icon(Icons.school_outlined, color: Colors.indigo),
              title: const Text('重新开启入门操作演练', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('演练会话管理、素材整理与病历生成流程', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.play_circle_outline_rounded),
              onTap: () async {
                final sampleService = ref.read(sampleDataServiceProvider);
                await sampleService.ensureSampleData(force: true);
                ref.invalidate(patientsProvider);
                await ref.read(tutorialProvider.notifier).resetTutorial(TutorialType.basicFlow);
                if (context.mounted) {
                  context.go('/patients');
                  showAppToast(context, '已启动新手入门演练');
                }
              },
            ),
          ]),

          const SizedBox(height: 16),

          // 3. 开源仓库与社区
          _buildGroupLabel('开源社区'),
          _buildCard([
            ListTile(
              leading: const Icon(Icons.code_rounded),
              title: const Text('Gitee 开源主页', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('gitee.com/xinggue/peipal_app', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () => _openUrl('https://gitee.com/xinggue/peipal_app'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.terminal_rounded),
              title: const Text('GitHub 开源主页', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('github.com/xinggue/PeiPal_App', style: TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () => _openUrl('https://github.com/xinggue/PeiPal_App'),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _buildGroupLabel(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.15)),
      ),
      child: Column(children: children),
    );
  }
}
