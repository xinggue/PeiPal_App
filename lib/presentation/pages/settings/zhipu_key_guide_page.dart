import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/services/sample_data_service.dart';
import '../../../domain/models/asr_provider.dart';
import '../../../domain/models/llm_provider.dart';
import '../../../domain/models/ocr_provider.dart';
import '../../../providers/asr_providers_provider.dart';
import '../../../providers/llm_providers_provider.dart';
import '../../../providers/ocr_providers_provider.dart';
import '../../../providers/providers.dart';
import '../../../providers/tutorial_provider.dart';
import '../../widgets/common/app_toast.dart';

class _GuideStep {
  final int number;
  final String title;
  final String description;
  final String assetPath;

  const _GuideStep({
    required this.number,
    required this.title,
    required this.description,
    required this.assetPath,
  });
}

class ZhipuKeyGuidePage extends ConsumerStatefulWidget {
  const ZhipuKeyGuidePage({super.key});

  @override
  ConsumerState<ZhipuKeyGuidePage> createState() => _ZhipuKeyGuidePageState();
}

class _ZhipuKeyGuidePageState extends ConsumerState<ZhipuKeyGuidePage> {
  static const String _bigModelUrl = 'https://bigmodel.cn';
  static const String _zhipuBaseUrl = 'https://open.bigmodel.cn/api/paas/v4';
  static const String _defaultLlmModel = 'glm-5.3-flash';
  static const String _defaultOcrModel = 'glm-ocr';
  static const String _defaultAsrModel = 'glm-asr-2512';

  static const List<_GuideStep> _steps = [
    _GuideStep(
      number: 1,
      title: '用电脑打开智谱官网',
      description: '在电脑浏览器打开 https://bigmodel.cn，点击右上角黑色「登录 / 注册」按钮。',
      assetPath: 'assets/tutorial/zhipu_key/01_home.png',
    ),
    _GuideStep(
      number: 2,
      title: '注册账号并领免费额度',
      description:
          '务必在电脑上完成注册：用手机号验证码或微信扫码登录（未注册会自动建号），新用户会赠送免费 Tokens 体验包。',
      assetPath: 'assets/tutorial/zhipu_key/02_register.png',
    ),
    _GuideStep(
      number: 3,
      title: '进入控制台',
      description: '登录完成后回到首页，点击右上角的「控制台」。',
      assetPath: 'assets/tutorial/zhipu_key/03_login.png',
    ),
    _GuideStep(
      number: 4,
      title: '打开左侧「API Key」',
      description: '在控制台左侧菜单栏里找到并点击「API Key」。',
      assetPath: 'assets/tutorial/zhipu_key/04_console.png',
    ),
    _GuideStep(
      number: 5,
      title: '新建 API Key',
      description: '点击右上角蓝色「+ 新建API Key」按钮。',
      assetPath: 'assets/tutorial/zhipu_key/05_new_key.png',
    ),
    _GuideStep(
      number: 6,
      title: '给 Key 起个名字',
      description: '在弹出的输入框里填写「小培同学」（方便以后辨认），然后点「确定」。',
      assetPath: 'assets/tutorial/zhipu_key/06_name_key.png',
    ),
    _GuideStep(
      number: 7,
      title: '复制并妥善保存 Key',
      description: 'Key 只在这里显示这一次！点「复制」（建议先发到电脑微信「文件传输助手」），再点「我已妥善保存」。',
      assetPath: 'assets/tutorial/zhipu_key/07_copy_key.png',
    ),
    _GuideStep(
      number: 8,
      title: '确认列表中已有刚建的 Key',
      description:
          '表格中出现「小培同学」即创建成功。核对 Key 的「前 4 位」与「末 4 位」（如 13ee…qbkg），确认复制完整、没有漏字符。',
      assetPath: 'assets/tutorial/zhipu_key/08_check_key.png',
    ),
    _GuideStep(
      number: 9,
      title: '打开「账号设置」准备实名',
      description: '重要：智谱账号必须实名认证后才能调用 API。点击右上角头像，进入「账号设置」。',
      assetPath: 'assets/tutorial/zhipu_key/09_account_settings.png',
    ),
    _GuideStep(
      number: 10,
      title: '完成个人实名认证',
      description: '在左侧点击「实名认证」→「开始个人认证」，按提示刷脸/填身份证即可（完成还能解锁更多免费额度）。',
      assetPath: 'assets/tutorial/zhipu_key/10_realname_auth.png',
    ),
    _GuideStep(
      number: 11,
      title: '按需充值（可选）',
      description: '前期用免费额度即可。如果后面额度用完或需要调用收费模型，点右上角「财务 → 去充值」充几块钱就能用很久。',
      assetPath: 'assets/tutorial/zhipu_key/11_recharge.png',
    ),
  ];

  final TextEditingController _keyController = TextEditingController();
  bool _obscureKey = true;
  bool _isVerifying = false;
  bool _verified = false;
  String? _verifyError;

  void _goToGeneration() {
    context.go('/patients');
    context.push('/patients/${SampleDataService.samplePatientId}/chat');
  }

  /// First 4 + last 4 characters, e.g. "13ee…qbkg". Empty if too short.
  String get _keyPreview {
    final k = _keyController.text.trim();
    if (k.length < 8) return '';
    return '${k.substring(0, 4)}…${k.substring(k.length - 4)}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final existing = ref
          .read(llmProvidersProvider)
          .providers
          .where((p) => p.id == 'zhipu')
          .firstOrNull;
      if (existing != null &&
          existing.apiKey.trim().isNotEmpty &&
          _keyController.text.isEmpty) {
        _keyController.text = existing.apiKey.trim();
      }
    });
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _copyWebsite() async {
    await Clipboard.setData(const ClipboardData(text: _bigModelUrl));
    if (mounted) {
      showAppToast(context, '已复制 https://bigmodel.cn，请发到电脑浏览器打开');
    }
  }

  Future<void> _pasteKey() async {
    final clip = await Clipboard.getData('text/plain');
    final text = clip?.text?.trim() ?? '';
    if (text.isEmpty) {
      if (mounted) showAppToast(context, '剪贴板里没有内容');
      return;
    }
    setState(() {
      _keyController.text = text;
      _verifyError = null;
    });
  }

  void _openImagePreview(_GuideStep step) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (ctx) => Stack(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.pop(ctx),
            child: InteractiveViewer(
              minScale: 1.0,
              maxScale: 5.0,
              child: Center(
                child: Image.asset(
                  step.assetPath,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          Positioned(
            top: MediaQuery.paddingOf(ctx).top + 12,
            right: 16,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ),
          Positioned(
            bottom: MediaQuery.paddingOf(ctx).bottom + 20,
            left: 20,
            right: 20,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(
                    '第 ${step.number} 步 · 双指缩放，轻触关闭',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _verifyAndSaveAll() async {
    final apiKey = _keyController.text.trim();
    if (apiKey.isEmpty) {
      setState(() => _verifyError = '请先粘贴或输入智谱 API Key');
      return;
    }

    setState(() {
      _isVerifying = true;
      _verifyError = null;
    });

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
      ));

      final resp = await dio.post(
        '$_zhipuBaseUrl/chat/completions',
        data: {
          'model': _defaultLlmModel,
          'messages': [
            {'role': 'user', 'content': 'hi'},
          ],
          'max_tokens': 1,
        },
        options: Options(
          headers: {
            'Authorization': 'Bearer $apiKey',
            'Content-Type': 'application/json',
          },
          validateStatus: (_) => true,
        ),
      );

      final ok = resp.statusCode == 200;
      if (!ok) {
        String detail = '验证未通过 (HTTP ${resp.statusCode})';
        final data = resp.data;
        if (data is Map && data['error'] is Map) {
          final err = data['error'] as Map;
          final msg = err['message']?.toString() ?? '';
          final code = err['code']?.toString() ?? '';
          if (resp.statusCode == 401) {
            detail = 'API Key 无效或未复制完整 (401)';
          } else if (code == '1113' || msg.contains('余额') || msg.contains('欠费')) {
            detail = '账号余额或免费额度不足，请先确认是否已完成第 10 步实名认证或第 11 步充值（$msg）';
          } else if (msg.isNotEmpty) {
            detail = '$msg${code.isNotEmpty ? " ($code)" : ""}';
          }
        } else if (resp.statusCode == 401) {
          detail = 'API Key 无效或未复制完整 (401)';
        }
        if (mounted) {
          setState(() {
            _isVerifying = false;
            _verifyError = detail;
          });
        }
        return;
      }

      // 1. 写入并激活 LLM（智谱 glm-5.3-flash）
      final llmNotifier = ref.read(llmProvidersProvider.notifier);
      final existingLlm = ref
          .read(llmProvidersProvider)
          .providers
          .where((p) => p.id == 'zhipu')
          .firstOrNull;
      final baseLlm = existingLlm ??
          LlmProviderPresets.builtIn.firstWhere((p) => p.id == 'zhipu');
      await llmNotifier.updateProvider(
        baseLlm.copyWith(
          baseUrl: _zhipuBaseUrl,
          apiKey: apiKey,
          selectedModel: _defaultLlmModel,
        ),
      );
      await llmNotifier.setActiveProvider('zhipu', model: _defaultLlmModel);

      // 2. 写入并激活 OCR（智谱 glm-ocr）
      final ocrNotifier = ref.read(ocrProvidersProvider.notifier);
      final existingOcr = ref
          .read(ocrProvidersProvider)
          .providers
          .where((p) => p.id == 'zhipu')
          .firstOrNull;
      final baseOcr = existingOcr ??
          OcrProviderPresets.builtIn.firstWhere((p) => p.id == 'zhipu');
      await ocrNotifier.updateProvider(
        baseOcr.copyWith(
          baseUrl: _zhipuBaseUrl,
          apiKey: apiKey,
          selectedModel: _defaultOcrModel,
        ),
      );
      await ocrNotifier.setActiveProvider('zhipu', model: _defaultOcrModel);

      // 3. 写入并激活 ASR（智谱 glm-asr-2512）
      final asrNotifier = ref.read(asrProvidersProvider.notifier);
      final existingAsr = ref
          .read(asrProvidersProvider)
          .providers
          .where((p) => p.id == 'zhipu')
          .firstOrNull;
      final baseAsr = existingAsr ??
          AsrProviderPresets.builtIn.firstWhere((p) => p.id == 'zhipu');
      await asrNotifier.updateProvider(
        baseAsr.copyWith(
          baseUrl: _zhipuBaseUrl,
          apiKey: apiKey,
          selectedModel: _defaultAsrModel,
        ),
      );
      await asrNotifier.setActiveProvider('zhipu', model: _defaultAsrModel);

      // 4. 确保示例会话存在，并从第 4 步（文书生成按钮）重开生成教程
      await ref.read(sampleDataServiceProvider).ensureSampleData();
      ref.invalidate(patientsProvider);
      await ref
          .read(tutorialProvider.notifier)
          .resetTutorial(TutorialType.basicFlow, step: 4);

      if (mounted) {
        setState(() {
          _isVerifying = false;
          _verified = true;
        });
        showAppToast(context, '验证通过，文本 / 识图 / 语音已全部配置好');
      }
    } on DioException catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _verifyError = '网络请求失败，请检查网络连接 (${e.message ?? e.type.name})';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifying = false;
          _verifyError = '验证出错: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('获取智谱 API Key'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
        children: [
          // 顶部醒目提醒：手机看教程、电脑操作
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.shade400, width: 1.4),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.devices_rounded, color: Colors.amber.shade900, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '请用手机看教程，用电脑开网页操作',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.bold,
                          color: Colors.amber.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  '智谱开放平台同时提供大语言模型、图片 OCR 识别和语音转文字，新用户有免费额度。\n用电脑浏览器打开下方网址注册、建 Key、做实名认证最省事，手机只负责对照往下滑看步骤即可。',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: Colors.grey.shade800,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _copyWebsite,
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.amber.shade800,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('复制网址 https://bigmodel.cn（发到电脑打开）'),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 开头简介：API Key 是什么、智谱是谁、整体流程
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: theme.dividerColor.withValues(alpha: 0.25),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '开始前，先花 1 分钟了解',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                _buildIntroLine(
                  'API Key 是什么',
                  '一串只属于你的访问密钥。本应用用它代表你调用智谱的 AI（文本 / 识图 / 语音）。按用量计费，新用户有免费额度。',
                ),
                _buildIntroLine(
                  '智谱是谁',
                  '智谱（BigModel）源自清华大学技术团队，是国内头部大模型公司，GLM 系列模型在国际评测中位居前列。',
                ),
                _buildIntroLine(
                  '总共要做的事',
                  '用电脑打开官网 → 注册登录 → 创建并复制 Key → 实名认证 → 回到本页粘贴验证。',
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 11 步图文流程
          ..._steps.map((step) => _buildStepCard(theme, step)),

          const SizedBox(height: 8),

          // 教程末尾：一站式填入 Key 并验证
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colorScheme.primary.withValues(alpha: 0.45),
                width: 1.4,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(Icons.key_rounded, color: colorScheme.primary, size: 22),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        '最后一步：贴入智谱 API Key',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_verified) ...[
                  _buildSuccessPanel(colorScheme),
                ] else ...[
                  Text(
                    '只需填入这 1 个 Key，系统会自动帮你同时配好以下三项并设为默认可用：',
                    style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: const [
                      _ModelBadge(label: '大语言模型', model: _defaultLlmModel),
                      _ModelBadge(label: '图像识别', model: _defaultOcrModel),
                      _ModelBadge(label: '语音识别', model: _defaultAsrModel),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _keyController,
                    obscureText: _obscureKey,
                    onChanged: (_) => setState(() => _verifyError = null),
                    decoration: InputDecoration(
                      labelText: '智谱 API Key',
                      hintText: '粘贴第 7 步复制的 Key',
                      filled: true,
                      fillColor: colorScheme.surface,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _obscureKey ? Icons.visibility_off : Icons.visibility,
                              size: 19,
                            ),
                            tooltip: _obscureKey ? '显示' : '隐藏',
                            onPressed: () => setState(() => _obscureKey = !_obscureKey),
                          ),
                          IconButton(
                            icon: const Icon(Icons.paste_rounded, size: 19),
                            tooltip: '从剪贴板粘贴',
                            onPressed: _pasteKey,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_keyPreview.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      '已输入：$_keyPreview（前 4 位 … 末 4 位），请与第 8 步列表里的 Key 核对一致',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (_verifyError != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.error_outline, color: Colors.red.shade700, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _verifyError!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.red.shade800,
                                height: 1.4,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  SizedBox(
                    height: 50,
                    child: FilledButton.icon(
                      onPressed: _isVerifying ? null : _verifyAndSaveAll,
                      icon: _isVerifying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.verified_rounded, size: 18),
                      label: Text(
                        _isVerifying ? '正在验证 Key 是否可用…' : '验证并一键配置',
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessPanel(ColorScheme colorScheme) {
    final green = Colors.green;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: green.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: green.shade300, width: 1.2),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.check_circle_rounded, color: green.shade700, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '验证成功，AI 已全部配置好',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: green.shade800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '文本、识图、语音三项都已就绪，可以开始生成文书了。',
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.45,
                        color: green.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 50,
          child: FilledButton.icon(
            onPressed: _goToGeneration,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: const Text(
              '回到文书生成页面',
              style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.teal,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildIntroLine(String title, String desc) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            desc,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCard(ThemeData theme, _GuideStep step) {
    final colorScheme = theme.colorScheme;
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.dividerColor.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '第 ${step.number} 步',
                    style: TextStyle(
                      color: colorScheme.onPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    step.title,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              step.description,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.48,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => _openImagePreview(step),
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: theme.dividerColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Image.asset(
                        step.assetPath,
                        fit: BoxFit.fitWidth,
                        width: double.infinity,
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.58),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.zoom_in_rounded, color: Colors.white, size: 14),
                          SizedBox(width: 3),
                          Text(
                            '点图放大',
                            style: TextStyle(color: Colors.white, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelBadge extends StatelessWidget {
  final String label;
  final String model;

  const _ModelBadge({
    required this.label,
    required this.model,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
      ),
      child: Text(
        '$label: $model',
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w600,
          color: colorScheme.primary,
        ),
      ),
    );
  }
}
