import 'package:peipal/presentation/widgets/common/app_toast.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/services/engine_c/engine_c_models.dart';
import '../../../data/services/engine_c/template_bundle_engine.dart';
import '../../../data/services/hub/hub_service.dart';
import '../../../domain/models/content_template.dart';
import '../../../domain/models/template.dart';
import '../../../domain/models/typing_profile.dart';
import '../../../providers/providers.dart';

class HubPublishItemSelection {
  final Template template;
  final bool publishStructureItself;
  final bool includePipeline;
  final List<TypingProfile> selectedProfiles;
  final List<ContentTemplate> selectedContents;
  final bool includeLinkedDiagnoses;

  const HubPublishItemSelection({
    required this.template,
    required this.publishStructureItself,
    required this.includePipeline,
    required this.selectedProfiles,
    required this.selectedContents,
    required this.includeLinkedDiagnoses,
  });
}

class HubBatchPublishPage extends ConsumerStatefulWidget {
  final HubPublishItemSelection? selection;
  final bool diagnosisMode;
  final List<String> selectedDiagnosisTags;

  const HubBatchPublishPage({
    super.key,
    this.selection,
    this.diagnosisMode = false,
    this.selectedDiagnosisTags = const [],
  });

  @override
  ConsumerState<HubBatchPublishPage> createState() => _HubBatchPublishPageState();
}

class _HubBatchPublishPageState extends ConsumerState<HubBatchPublishPage> {
  // 结构说明（当用户发布结构本身时必填）
  late final TextEditingController _structureReadmeCtrl;

  // 各个输入方案的说明控制器：profile.id -> TextEditingController（必填）
  final Map<String, TextEditingController> _profileReadmeCtrls = {};

  // 解析流程说明控制器（选填）
  final TextEditingController _pipelineReadmeCtrl = TextEditingController();

  // 各个内容模板说明控制器：ct.id -> TextEditingController（选填）
  final Map<String, TextEditingController> _contentReadmeCtrls = {};

  // 诊断说明控制器（选填）
  final TextEditingController _diagnosisReadmeCtrl = TextEditingController();
  final TextEditingController _diagnosisTitleCtrl = TextEditingController();

  bool _isPublishing = false;

  @override
  void initState() {
    super.initState();
    _structureReadmeCtrl = TextEditingController();

    if (widget.diagnosisMode) {
      _diagnosisTitleCtrl.text = widget.selectedDiagnosisTags.isNotEmpty
          ? '${widget.selectedDiagnosisTags.join("、")} 标准库'
          : '标准词条库';
    }

    final sel = widget.selection;
    if (sel != null) {
      for (final p in sel.selectedProfiles) {
        _profileReadmeCtrls[p.id] = TextEditingController();
      }
      for (final c in sel.selectedContents) {
        _contentReadmeCtrls[c.id] = TextEditingController();
      }
    }
  }

  @override
  void dispose() {
    _structureReadmeCtrl.dispose();
    _pipelineReadmeCtrl.dispose();
    for (final c in _profileReadmeCtrls.values) {
      c.dispose();
    }
    for (final c in _contentReadmeCtrls.values) {
      c.dispose();
    }
    _diagnosisReadmeCtrl.dispose();
    _diagnosisTitleCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    // 1. 必填校验
    final sel = widget.selection;
    if (sel != null) {
      if (sel.publishStructureItself && _structureReadmeCtrl.text.trim().isEmpty) {
        showAppToast(context, '文书类型说明为必填项（请注明与实际系统内文书的对应关系）');
        return;
      }
      for (final p in sel.selectedProfiles) {
        final ctrl = _profileReadmeCtrls[p.id];
        if (ctrl == null || ctrl.text.trim().isEmpty) {
          showAppToast(context, '输入方案「${p.name}」说明为必填项（请注明运行前提与光标初始位置）');
          return;
        }
      }
    }

    setState(() => _isPublishing = true);

    try {
      final engine = ref.read(templateBundleEngineProvider);
      final hub = HubService(ref.read(secureStorageProvider));

      if (widget.diagnosisMode) {
        final req = EngineCExportRequest(
          includeAllDiagnoses: widget.selectedDiagnosisTags.isEmpty,
          selectedDiagnosisTags: Set.of(widget.selectedDiagnosisTags),
        );
        final payloadText = await engine.exportJsonString(req);
        await hub.publish(
          kind: 'diagnosis',
          title: _diagnosisTitleCtrl.text.trim().isEmpty ? '标准词条库' : _diagnosisTitleCtrl.text.trim(),
          readme: _diagnosisReadmeCtrl.text.trim(),
          payload: HubService.publicPayload(payloadText),
        );
      } else if (sel != null) {
        final t = sel.template;

        // A. 如果勾选了“发布结构本身”
        if (sel.publishStructureItself) {
          final req = EngineCExportRequest(
            families: [
              StructureFamilyExportSelection(
                templateId: t.id,
                includePipeline: sel.includePipeline,
                selectedTypingProfileIds: sel.selectedProfiles.map((p) => p.id).toSet(),
                selectedContentTemplateIds: sel.selectedContents.map((c) => c.id).toSet(),
                includeLinkedDiagnoses: sel.includeLinkedDiagnoses,
              ),
            ],
          );
          final text = await engine.exportJsonString(req);
          await hub.publish(
            kind: 'structure',
            title: t.name,
            readme: _structureReadmeCtrl.text.trim(),
            payload: HubService.publicPayload(text),
          );
        }

        // B. 单独为每个勾选的输入方案独立发布一条专属 listing（以便在输入方案栏目下专属陈列并带专属说明）
        for (final p in sel.selectedProfiles) {
          final req = EngineCExportRequest(
            families: [
              StructureFamilyExportSelection(
                templateId: t.id,
                includePipeline: false,
                selectedTypingProfileIds: {p.id},
                selectedContentTemplateIds: const {},
                includeLinkedDiagnoses: false,
              ),
            ],
          );
          final text = await engine.exportJsonString(req);
          await hub.publish(
            kind: 'typing',
            title: p.name,
            readme: _profileReadmeCtrls[p.id]?.text.trim() ?? '',
            payload: HubService.publicPayload(text),
          );
        }

        // C. 单独为每个勾选的内容模板独立发布一条专属 listing（以便在内容模板栏目下专属陈列并带专属说明）
        for (final c in sel.selectedContents) {
          final req = EngineCExportRequest(
            families: [
              StructureFamilyExportSelection(
                templateId: t.id,
                includePipeline: false,
                selectedTypingProfileIds: const {},
                selectedContentTemplateIds: {c.id},
                includeLinkedDiagnoses: sel.includeLinkedDiagnoses,
              ),
            ],
          );
          final text = await engine.exportJsonString(req);
          await hub.publish(
            kind: 'content',
            title: c.name,
            readme: _contentReadmeCtrls[c.id]?.text.trim() ?? '',
            payload: HubService.publicPayload(text),
          );
        }

        // D. 如果勾选了解析流程且没有勾选结构本身，单独发布流程
        if (!sel.publishStructureItself && sel.includePipeline) {
          final req = EngineCExportRequest(
            families: [
              StructureFamilyExportSelection(
                templateId: t.id,
                includePipeline: true,
                selectedTypingProfileIds: const {},
                selectedContentTemplateIds: const {},
                includeLinkedDiagnoses: false,
              ),
            ],
          );
          final text = await engine.exportJsonString(req);
          await hub.publish(
            kind: 'pipeline',
            title: '默认解析流程',
            readme: _pipelineReadmeCtrl.text.trim(),
            payload: HubService.publicPayload(text),
          );
        }
      }

      if (!mounted) return;
      setState(() => _isPublishing = false);
      Navigator.pop(context, true);
      showAppToast(context, '已成功提交发布！管理员审核通过后将在公开模板库展示');
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _isPublishing = false);
      final msg = e.response?.data is Map ? e.response?.data['error']?.toString() : null;
      showAppToast(context, msg ?? '发布失败: $e');
    } catch (e) {
      if (!mounted) return;
      setState(() => _isPublishing = false);
      showAppToast(context, '发布异常: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selection;

    return Scaffold(
      appBar: AppBar(
        title: const Text('填写说明并确认发布'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (widget.diagnosisMode) ...[
            TextField(
              controller: _diagnosisTitleCtrl,
              decoration: const InputDecoration(
                labelText: '词条包标题',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _diagnosisReadmeCtrl,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '使用说明 (选填)',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
                hintText: '选填：说明词条包包含的分类或使用建议...',
              ),
            ),
          ] else if (sel != null) ...[
            // 基底归属信息 (克制、不啰嗦)
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.grey.withAlpha(20),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 16, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Text(
                    '基于文书类型：${sel.template.name}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),

            // 1. 如果勾选了“发布结构本身”
            if (sel.publishStructureItself) ...[
              _buildSectionCard(
                title: '文书类型：${sel.template.name}',
                icon: Icons.schema_outlined,
                badge: '必填说明 *',
                badgeColor: Colors.deepOrange,
                child: TextField(
                  controller: _structureReadmeCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: '文书类型使用说明 (必填 *)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    hintText: '必填：请说明此文书对应的实际文书类型、包含的字段要求及适用场景...',
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 2. 每个选中的输入方案 (必填说明)
            for (final p in sel.selectedProfiles) ...[
              _buildSectionCard(
                title: '输入方案：${p.name}',
                icon: Icons.keyboard_outlined,
                badge: '必填说明 *',
                badgeColor: Colors.blue,
                child: TextField(
                  controller: _profileReadmeCtrls[p.id],
                  minLines: 3,
                  maxLines: 6,
                  decoration: InputDecoration(
                    labelText: '「${p.name}」使用说明 (必填 *)',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                    hintText: '必填：请说明此方案运行的前提要求（如光标必须初始点在哪个输入框、按键流适配哪套系统等）...',
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 3. 解析流程说明 (如有)
            if (sel.includePipeline) ...[
              _buildSectionCard(
                title: '默认解析流程',
                icon: Icons.account_tree_outlined,
                badge: '选填',
                badgeColor: Colors.grey,
                child: TextField(
                  controller: _pipelineReadmeCtrl,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '解析流程说明 (选填)',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    hintText: '选填：说明 AI 拆分各阶段提示词设计意图...',
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],

            // 4. 每个选中的内容模板说明 (选填)
            for (final c in sel.selectedContents) ...[
              _buildSectionCard(
                title: '内容模板：${c.name}',
                icon: Icons.article_outlined,
                badge: '选填',
                badgeColor: Colors.grey,
                child: TextField(
                  controller: _contentReadmeCtrls[c.id],
                  minLines: 2,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: '「${c.name}」使用说明 (选填)',
                    alignLabelWithHint: true,
                    border: const OutlineInputBorder(),
                    hintText: '选填：可说明此示范文书的适用场景或分类...',
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          ],

          const SizedBox(height: 16),

          FilledButton.icon(
            icon: _isPublishing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(_isPublishing ? '发布中…' : '全部确认发布'),
            onPressed: _isPublishing ? null : _submit,
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required String badge,
    required Color badgeColor,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Theme.of(context).dividerColor.withAlpha(60)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: badgeColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: badgeColor.withAlpha(20),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  badge,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: badgeColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}
