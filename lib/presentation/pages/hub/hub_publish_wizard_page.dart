import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../data/services/engine_c/engine_c_models.dart';
import '../../../data/services/engine_c/template_bundle_engine.dart';
import '../../../data/services/hub/hub_service.dart';
import '../../../domain/models/content_template.dart';
import '../../../domain/models/template.dart';
import '../../../domain/models/typing_profile.dart';
import '../../../providers/providers.dart';
import '../../widgets/common/app_toast.dart';
import '../templates/content_template_editor_page.dart';
import '../templates/template_editor_page.dart';

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

final hubPublishServiceProvider = Provider<HubService>(
  (ref) => HubService(ref.read(secureStorageProvider)),
);

class HubBatchPublishPage extends ConsumerStatefulWidget {
  final HubPublishItemSelection? selection;
  final bool diagnosisMode;
  final List<String> selectedDiagnosisTags;
  final String catalogType;

  const HubBatchPublishPage({
    super.key,
    this.selection,
    this.diagnosisMode = false,
    this.selectedDiagnosisTags = const [],
    this.catalogType = 'diagnosis',
  });

  @override
  ConsumerState<HubBatchPublishPage> createState() =>
      _HubBatchPublishPageState();
}

class _HubBatchPublishPageState extends ConsumerState<HubBatchPublishPage> {
  final _institution = TextEditingController();
  final _descriptions = <String, TextEditingController>{};
  final _newCopies = <String>{};
  final _editedDescriptions = <String>{};
  Map<String, dynamic>? _analysis;
  Map<String, dynamic>? _payload;
  List<Map<String, dynamic>> _targets = [];
  String _scope = '';
  String _structureId = '';
  String _requestId = const Uuid().v4();
  String? _error;
  bool _busy = true;
  bool _submitting = false;
  bool _institutionChanged = false;
  Timer? _debounce;
  Timer? _clock;
  CancelToken? _matchToken;
  int _matchSequence = 0;
  int _elapsed = 0;
  String _activity = '正在准备发布内容…';

  HubService get _hub => ref.read(hubPublishServiceProvider);
  List<Map<String, dynamic>> get _items =>
      ((_analysis?['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
  List<Map<String, dynamic>> get _candidates =>
      ((_analysis?['candidates'] as List?) ?? const [])
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();

  @override
  void initState() {
    super.initState();
    Future.microtask(_prepare);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _clock?.cancel();
    _matchToken?.cancel();
    _institution.dispose();
    for (final c in _descriptions.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _prepare() async {
    _startClock();
    setState(() {
      _busy = true;
      _activity = '正在准备发布内容…';
    });
    try {
      final sel = widget.selection;
      final request = widget.diagnosisMode
          ? EngineCExportRequest(
              includeAllDiagnoses: widget.selectedDiagnosisTags.isEmpty,
              catalogTypes: {widget.catalogType},
              selectedDiagnosisTags: widget.selectedDiagnosisTags.toSet(),
            )
          : EngineCExportRequest(
              families: [
                StructureFamilyExportSelection(
                  templateId: sel!.template.id,
                  includePipeline: sel.includePipeline,
                  selectedTypingProfileIds: sel.selectedProfiles
                      .map((p) => p.id)
                      .toSet(),
                  selectedContentTemplateIds: sel.selectedContents
                      .map((c) => c.id)
                      .toSet(),
                  includeLinkedDiagnoses: false,
                ),
              ],
            );
      final envelope = await ref
          .read(templateBundleEngineProvider)
          .buildExportEnvelope(request);
      _payload = envelope.toJson();
      if (sel != null) {
        // Preserve the exact editor snapshot instead of silently exporting an
        // older database copy of the structure or input schemes.
        final selected = envelope.units.firstOrNull;
        if (selected == null) throw StateError('未找到所选文书类型');
        _payload!['structure_units'] = [
          StructureGroundedUnit(
            structure: sel.template,
            hasPipeline: sel.includePipeline,
            typingProfiles: sel.selectedProfiles,
            contentTemplates: selected.contentTemplates,
          ).toJson(),
        ];
      }
      if (widget.diagnosisMode) {
        final name =
            ref
                .read(catalogsProvider)
                .valueOrNull
                ?.where((c) => c.id == widget.catalogType)
                .firstOrNull
                ?.name ??
            '标准词条库';
        _targets = [
          {'kind': 'diagnosis', 'source_id': widget.catalogType, 'name': name},
        ];
      } else {
        _targets = [
          if (sel!.publishStructureItself) {'kind': 'structure'},
          for (final c in sel.selectedContents)
            {'kind': 'content', 'source_id': c.id},
          for (final p in sel.selectedProfiles)
            {'kind': 'typing', 'source_id': p.id},
          if (sel.includePipeline) {'kind': 'pipeline'},
        ];
      }
      if (!mounted) return;
      await _match(withAssistance: true);
    } catch (e) {
      if (mounted) {
        _clock?.cancel();
        setState(() {
          _busy = false;
          _error = _message(e);
        });
      }
    }
  }

  Future<void> _match({bool withAssistance = false}) async {
    _startClock();
    _debounce?.cancel();
    _matchToken?.cancel();
    final token = _matchToken = CancelToken();
    final sequence = ++_matchSequence;
    setState(() {
      _busy = true;
      _error = null;
      _elapsed = 0;
      _activity = withAssistance ? '正在匹配文书、整理使用说明…' : '正在更新文书归属…';
    });
    try {
      final result = await _hub.analyzeUpload(
        payload: _payload!,
        targets: _targets,
        scope: _scope,
        institution: _institution.text.trim(),
        skipAssistance: !withAssistance,
        cancelToken: token,
      );
      if (!mounted || sequence != _matchSequence) return;
      _clock?.cancel();
      for (final raw in (result['items'] as List)) {
        final item = Map<String, dynamic>.from(raw as Map);
        final key = item['key'] as String;
        _descriptions.putIfAbsent(
          key,
          () => TextEditingController(text: item['readme'] as String? ?? ''),
        );
        if (!_editedDescriptions.contains(key) &&
            (withAssistance || (_descriptions[key]!.text.trim().isEmpty))) {
          _descriptions[key]!.text = item['readme'] as String? ?? '';
        }
      }
      setState(() {
        _analysis = result;
        _structureId = result['structure_id'] as String? ?? '';
        _scope = result['scope'] as String? ?? '';
        _institution.text = result['institution'] as String? ?? '';
        _busy = false;
        _institutionChanged = false;
        _requestId = const Uuid().v4();
      });
    } catch (e) {
      if (mounted && sequence == _matchSequence && !token.isCancelled) {
        _clock?.cancel();
        setState(() {
          _busy = false;
          _error = _message(e);
        });
      }
    }
  }

  void _chooseStructure(String? id) {
    if (id == null || id.isEmpty) {
      setState(() {
        _structureId = '';
        _scope = '';
        _institution.clear();
        _institutionChanged = true;
      });
      _invalidateMatch();
      return;
    }
    final candidate = _candidates.firstWhere((c) => c['id'] == id);
    _scope = candidate['scope'] as String? ?? '';
    _institution.text = candidate['institution'] as String? ?? '';
    _match();
  }

  void _invalidateMatch() {
    _debounce?.cancel();
    _matchToken?.cancel();
    _matchSequence++;
    _clock?.cancel();
    setState(() {
      _institutionChanged = true;
      _busy = false;
      _error = null;
    });
    if (_scope.isEmpty ||
        (_scope == 'institution' && _institution.text.trim().isEmpty)) {
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 650), () => _match());
  }

  void _startClock() {
    _clock?.cancel();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _busy) setState(() => _elapsed++);
    });
  }

  Widget _progress() => Padding(
    padding: const EdgeInsets.all(20),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(height: 14),
        Text(_activity, textAlign: TextAlign.center),
        if (_elapsed > 0) ...[
          const SizedBox(height: 6),
          Text('已等待 $_elapsed 秒', style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    ),
  );

  String get _matchSummary {
    if (_institutionChanged) return '适用范围已修改，等待更新匹配';
    if (_scope.isEmpty) return '请选择适用范围';
    final owner = _scope == 'general' ? '通用' : _institution.text.trim();
    return '${_structureId.isEmpty ? '将新建' : '将加入'}：$owner · ${widget.selection?.template.name ?? ''}';
  }

  String _message(Object e) {
    if (e is DioException) {
      if (e.response?.statusCode == 404) return '当前模板平台需要升级后才能上传';
      if (e.response?.data is Map) {
        return e.response!.data['error']?.toString() ?? '连接失败';
      }
      return '连接失败，请稍后重试';
    }
    return e.toString();
  }

  Future<void> _submit() async {
    for (final item in _items) {
      if (['structure', 'typing'].contains(item['kind']) &&
          _descriptions[item['key']]!.text.trim().isEmpty) {
        showAppToast(context, '请填写「${item['name']}」的使用说明');
        return;
      }
    }
    if (!widget.diagnosisMode &&
        _structureId.isEmpty &&
        (_scope.isEmpty ||
            (_scope == 'institution' && _institution.text.trim().isEmpty))) {
      showAppToast(context, '请确认适用范围');
      return;
    }
    if (_institutionChanged) {
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await _hub.submitUpload(
        analysisId: _analysis!['analysis_id'] as String,
        requestId: _requestId,
        structureId: _structureId,
        scope: _scope,
        institution: _institution.text.trim(),
        decisions: [
          for (final item in _items)
            {
              'key': item['key'],
              'readme': _descriptions[item['key']]!.text.trim(),
              'new_copy': _newCopies.contains(item['key']),
            },
        ],
      );
      if (!mounted) return;
      final unchanged = (result['items'] as List).every(
        (i) => i['status'] == 'unchanged',
      );
      Navigator.pop(context, true);
      showAppToast(context, unchanged ? '内容没有变化' : '已提交审核');
    } catch (e) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = _message(e);
        });
      }
    }
  }

  void _preview(Map<String, dynamic> item) {
    final sel = widget.selection;
    if (sel == null) return;
    final payload = Map<String, dynamic>.from(item['payload'] as Map);
    final raw = (payload['structure_units'] as List).first as Map;
    final unit = StructureGroundedUnit.fromJson(Map<String, dynamic>.from(raw));
    Widget page;
    if (item['kind'] == 'content') {
      page = ContentTemplateEditorPage(
        structureTemplateId: unit.structure.id,
        previewStructure: unit.structure,
        previewContentTemplate: unit.contentTemplates.single,
      );
    } else {
      page = TemplateEditorPage(
        previewTemplate: unit.structure,
        initialTabIndex: item['kind'] == 'pipeline'
            ? 1
            : item['kind'] == 'typing'
            ? 2
            : 0,
        initialProfileId: item['kind'] == 'typing'
            ? item['source_id'] as String
            : null,
      );
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final sel = widget.selection;
    return Scaffold(
      appBar: AppBar(title: const Text('确认上传')),
      body: _busy && _analysis == null
          ? Center(child: _progress())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (_error != null) ...[
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  TextButton(
                    onPressed: _submitting
                        ? null
                        : _payload == null
                        ? _prepare
                        : _match,
                    child: const Text('重新检查'),
                  ),
                ],
                if (_analysis != null) ...[
                  if (sel != null) ...[
                    Text(
                      sel.template.name,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        '${_analysis!['analysis_id']}:$_structureId',
                      ),
                      initialValue: _structureId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '确认归属',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        for (final c in _candidates.where(
                          (c) => c['exact'] == true,
                        ))
                          DropdownMenuItem(
                            value: c['id'] as String,
                            child: Text(
                              '${(c['institution'] as String).isEmpty ? (c['scope'] == 'general' ? '通用' : '待确认机构') : c['institution']} · ${c['name']}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        const DropdownMenuItem(value: '', child: Text('新建归属')),
                      ],
                      onChanged: _submitting ? null : _chooseStructure,
                    ),
                    if (_structureId.isEmpty) ...[
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'general', label: Text('通用')),
                          ButtonSegment(
                            value: 'institution',
                            label: Text('特定机构'),
                          ),
                        ],
                        selected: {
                          if (['general', 'institution'].contains(_scope))
                            _scope,
                        },
                        emptySelectionAllowed: true,
                        onSelectionChanged: _submitting
                            ? null
                            : (s) {
                                setState(() {
                                  _scope = s.firstOrNull ?? '';
                                  if (_scope == 'general') _institution.clear();
                                });
                                _invalidateMatch();
                              },
                      ),
                      if (_scope == 'institution')
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: TextField(
                            controller: _institution,
                            enabled: !_submitting,
                            maxLength: 120,
                            decoration: const InputDecoration(
                              labelText: '机构名称',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (_) => _invalidateMatch(),
                          ),
                        ),
                    ],
                    if (_busy)
                      _progress()
                    else
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _matchSummary,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    const SizedBox(height: 20),
                  ],
                  for (final item in _items) _itemCard(item),
                  const SizedBox(height: 12),
                ],
              ],
            ),
      bottomNavigationBar: _analysis == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton(
                  onPressed:
                      _submitting ||
                          _busy ||
                          _institutionChanged ||
                          (!widget.diagnosisMode && _scope.isEmpty) ||
                          _error != null
                      ? null
                      : _submit,
                  child: Text(_submitting ? '提交中…' : '提交审核'),
                ),
              ),
            ),
    );
  }

  Widget _itemCard(Map<String, dynamic> item) {
    final kind = item['kind'];
    final key = item['key'] as String;
    final required = kind == 'structure' || kind == 'typing';
    const labels = {
      'structure': '文书类型',
      'content': '内容模板',
      'typing': '输入方案',
      'pipeline': '解析流程',
      'diagnosis': '标准词条库',
    };
    final hint = kind == 'structure'
        ? '说明与实际系统内文书的对应关系'
        : kind == 'typing'
        ? '说明运行前提、光标初始位置'
        : '用途与使用建议';
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item['name']} · ${labels[kind]}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                if (!widget.diagnosisMode)
                  TextButton(
                    onPressed: () => _preview(item),
                    child: const Text('预览'),
                  ),
              ],
            ),
            if ((item['update_id'] as String? ?? '').isNotEmpty) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  const Expanded(child: Text('更新我的发布')),
                  Switch(
                    value: _newCopies.contains(key),
                    onChanged: _submitting
                        ? null
                        : (v) => setState(() {
                            _requestId = const Uuid().v4();
                            if (v) {
                              _newCopies.add(key);
                            } else {
                              _newCopies.remove(key);
                            }
                          }),
                  ),
                  const Text('另建一份'),
                ],
              ),
              if (_candidates.any((c) => c['exact'] != true))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '已有同名文书，但字段定义不同。',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
            const SizedBox(height: 8),
            TextField(
              controller: _descriptions[key],
              onChanged: (_) {
                _editedDescriptions.add(key);
                _requestId = const Uuid().v4();
              },
              enabled: !_submitting,
              minLines: 2,
              maxLines: 8,
              maxLength: 4000,
              decoration: InputDecoration(
                labelText: required ? '使用说明 *' : '使用说明',
                hintText: hint,
                alignLabelWithHint: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
