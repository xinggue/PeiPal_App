import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../data/services/engine_c/config_file_io.dart';
import '../../../data/services/logging/app_log_service.dart';
import '../../../data/services/update/app_update_service.dart';
import '../../../providers/asr_providers_provider.dart';
import '../../../providers/llm_providers_provider.dart';
import '../../../providers/ocr_providers_provider.dart';
import '../../../providers/providers.dart';
import '../../../providers/tutorial_provider.dart';
import '../../widgets/common/app_toast.dart';
import '../../widgets/common/export_action_sheet.dart';
import 'disclaimer_page.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  bool _isCheckingUpdate = false;
  AppUpdateInfo? _updateInfo;
  String? _checkError;
  AppLogStats? _logStats;
  bool _isExportingLogs = false;

  @override
  void initState() {
    super.initState();
    _checkUpdateSilently();
    _loadLogStats();
  }

  Future<void> _loadLogStats() async {
    final stats = await AppLogService.instance.getStats();
    if (mounted) {
      setState(() => _logStats = stats);
    }
  }

  String _formatLogSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _exportDiagnostics() async {
    if (_isExportingLogs) return;
    setState(() => _isExportingLogs = true);
    try {
      final llm = ref.read(llmProvidersProvider).activeProvider;
      final asr = ref.read(asrProvidersProvider).activeProvider;
      final ocr = ref.read(ocrProvidersProvider).activeProvider;
      final summary = <String, String>{
        'LLM': llm == null
            ? '未配置'
            : '${llm.name} (${llm.selectedModel}) key=${llm.apiKey.isNotEmpty ? '已配置' : '空'}',
        'ASR': asr == null
            ? '未配置'
            : '${asr.name} key=${asr.apiKey.isNotEmpty ? '已配置' : '空'}',
        'OCR': ocr == null
            ? '未配置'
            : '${ocr.name} (${ocr.selectedModel}) key=${ocr.apiKey.isNotEmpty ? '已配置' : '空'}',
      };
      final report = await AppLogService.instance.buildDiagnosticReport(
        configSummary: summary,
      );
      if (!mounted) return;
      setState(() => _isExportingLogs = false);

      final fileName = ConfigFileIo.buildFileName('小培诊断日志', extension: 'txt');
      await showExportFileSheet(
        context,
        title: '导出诊断日志',
        summary: '已脱敏处理，不含 API 密钥与任何会话正文',
        savedSuccessPrefix: '已保存诊断日志',
        onShare: () => ConfigFileIo.shareTextFile(
          content: report,
          fileName: fileName,
          mimeType: 'text/plain',
          subject: '小培同学诊断日志',
        ),
        onSave: () => ConfigFileIo.saveConfigTextFile(
          content: report,
          suggestedName: fileName,
          typeLabel: '诊断日志',
          extensions: const ['txt'],
        ),
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isExportingLogs = false);
        showAppToast(context, '导出日志失败：$e');
      }
    }
  }

  Future<void> _clearLogs() async {
    await AppLogService.instance.clearLogs();
    await _loadLogStats();
    if (mounted) {
      showAppToast(context, '已清理本地日志', type: ToastType.success);
    }
  }

  void _showTelemetryFieldsDialog() {
    showTelemetryFieldsDialog(context);
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
    final pkgAsync = ref.watch(appPackageInfoProvider);
    final installedVersion = pkgAsync.valueOrNull?.version ?? _updateInfo?.currentVersion;

    return Scaffold(
      appBar: AppBar(
        title: const Text('关于与帮助'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          const SizedBox(height: 24),

          // 头部：品牌与版本信息
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Column(
                children: [
                  Builder(builder: (context) {
                    final logoSize =
                        (MediaQuery.sizeOf(context).width * 0.45).clamp(140.0, 280.0);
                    return GestureDetector(
                      onTap: () => _showLogoPreview(context),
                      child: Container(
                        width: logoSize,
                        height: logoSize,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer.withValues(alpha: 0.4),
                          borderRadius: BorderRadius.circular(logoSize * 0.22),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Image.asset(
                          'assets/icons/app_icon.png',
                          errorBuilder: (_, _, _) => Icon(
                            Icons.edit_note_rounded,
                            size: logoSize * 0.5,
                            color: colorScheme.primary,
                          ),
                        ),
                      ),
                    );
                  }),
                  const SizedBox(height: 14),
                  const Text(
                    '小培同学 PeiPal',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    installedVersion == null ? 'v—' : 'v$installedVersion',
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
              titleAlignment: ListTileTitleAlignment.center,
              leading: Icon(
                _updateInfo?.hasUpdate == true
                    ? Icons.system_update_rounded
                    : Icons.check_circle_outline_rounded,
                color: colorScheme.primary,
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
                            : '当前版本：v${installedVersion ?? _updateInfo?.currentVersion ?? '—'}')),
                style: const TextStyle(fontSize: 12),
              ),
              trailing: _isCheckingUpdate
                  ? const SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : SizedBox(
                      width: 40,
                      height: 40,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        icon: const Icon(Icons.refresh_rounded),
                        tooltip: '重新检测',
                        onPressed: _checkUpdateSilently,
                      ),
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
              titleAlignment: ListTileTitleAlignment.center,
              leading: Icon(Icons.school_outlined, color: colorScheme.primary),
              title: const Text('重新开启入门操作演练', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('演练会话管理、素材整理与结果生成流程', style: TextStyle(fontSize: 12)),
              trailing: _trailingIcon(Icons.play_circle_outline_rounded),
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
            const Divider(height: 1),
            ListTile(
              titleAlignment: ListTileTitleAlignment.center,
              leading: Icon(Icons.key_rounded, color: colorScheme.primary),
              title: const Text('获取 API Key', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('DeepSeek / 智谱图文教程与一键配置', style: TextStyle(fontSize: 12)),
              trailing: _trailingIcon(Icons.chevron_right),
              onTap: () => context.push('/settings/api-key-guides'),
            ),
          ]),

          const SizedBox(height: 16),

          // 3. 开源仓库与社区
          _buildGroupLabel('开源社区'),
          _buildCard([
            ListTile(
              titleAlignment: ListTileTitleAlignment.center,
              leading: Icon(Icons.code_rounded, color: colorScheme.primary),
              title: const Text('Gitee 开源主页', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('gitee.com/xinggue/peipal_app', style: TextStyle(fontSize: 12)),
              trailing: _trailingIcon(Icons.chevron_right),
              onTap: () => _openUrl('https://gitee.com/xinggue/peipal_app'),
            ),
            const Divider(height: 1),
            ListTile(
              titleAlignment: ListTileTitleAlignment.center,
              leading: Icon(Icons.terminal_rounded, color: colorScheme.primary),
              title: const Text('GitHub 开源主页', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('github.com/xinggue/PeiPal_App', style: TextStyle(fontSize: 12)),
              trailing: _trailingIcon(Icons.chevron_right),
              onTap: () => _openUrl('https://github.com/xinggue/PeiPal_App'),
            ),
          ]),

          const SizedBox(height: 16),

          // 4. 诊断与统计
          _buildGroupLabel('诊断与统计'),
          _buildCard([
            ListTile(
              titleAlignment: ListTileTitleAlignment.center,
              leading: Icon(Icons.bug_report_outlined, color: colorScheme.primary),
              title: const Text('导出诊断日志', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: Text(
                _logStats == null
                    ? '本地运行与异常日志（已脱敏）'
                    : '本地共 ${_formatLogSize(_logStats!.totalBytes)}'
                        '${_logStats!.crashCount > 0 ? ' · ${_logStats!.crashCount} 条异常记录' : ''}',
                style: const TextStyle(fontSize: 12),
              ),
              trailing: _isExportingLogs
                  ? const SizedBox(
                      width: 40,
                      height: 40,
                      child: Center(
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  : _trailingIcon(Icons.share_outlined),
              onTap: _isExportingLogs ? null : _exportDiagnostics,
            ),
            if ((_logStats?.totalBytes ?? 0) > 0) ...[
              const Divider(height: 1),
              ListTile(
                titleAlignment: ListTileTitleAlignment.center,
                leading: Icon(Icons.cleaning_services_outlined, color: colorScheme.onSurfaceVariant),
                title: const Text('清理本地日志', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                subtitle: const Text('释放本地缓存的运行与崩溃日志', style: TextStyle(fontSize: 12)),
                onTap: _clearLogs,
              ),
            ],
            const Divider(height: 1),
            SwitchListTile(
              secondary: Icon(Icons.analytics_outlined, color: colorScheme.primary),
              title: Row(
                children: [
                  const Text('匿名使用统计', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  const SizedBox(width: 4),
                  GestureDetector(
                    onTap: _showTelemetryFieldsDialog,
                    child: Icon(
                      Icons.help_outline_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              subtitle: const Text('仅含版本号与系统类型，不含业务数据', style: TextStyle(fontSize: 12)),
              value: ref.watch(telemetryEnabledProvider),
              onChanged: (v) => ref.read(telemetryEnabledProvider.notifier).setEnabled(v),
            ),
          ]),

          const SizedBox(height: 16),

          _buildGroupLabel('其他'),
          _buildCard([
            ListTile(
              titleAlignment: ListTileTitleAlignment.center,
              leading: Icon(Icons.gavel_rounded, color: colorScheme.primary),
              title: const Text('免责声明与隐私说明', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              subtitle: const Text('软件定位、第三方服务与隐私边界', style: TextStyle(fontSize: 12)),
              trailing: _trailingIcon(Icons.chevron_right),
              onTap: () => context.push('/settings/disclaimer'),
            ),
          ]),
        ],
      ),
    );
  }

  void _showLogoPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(ctx),
        child: InteractiveViewer(
          minScale: 1.0,
          maxScale: 4.0,
          child: Center(
            child: Image.asset(
              'assets/icons/app_icon.png',
              fit: BoxFit.contain,
            ),
          ),
        ),
      ),
    );
  }

  Widget _trailingIcon(IconData icon) {
    return SizedBox(
      width: 40,
      height: 40,
      child: Center(
        child: Icon(
          icon,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
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
