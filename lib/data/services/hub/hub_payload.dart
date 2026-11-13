import 'dart:convert';

/// Keep portable catalog definitions/references when selecting one contribution.
/// A missing target is an error, never an instruction to import its siblings.
Map<String, dynamic> selectHubPayload(
  Map<String, dynamic> original,
  String kind,
  String targetId,
) {
  final out = Map<String, dynamic>.from(
    jsonDecode(jsonEncode(original)) as Map,
  );
  if (kind == 'diagnosis') {
    out.remove('structure_units');
    return out;
  }
  final units = out['structure_units'] as List? ?? const [];
  if (units.length != 1) {
    throw const FormatException('未找到所属文书类型');
  }
  final unit = Map<String, dynamic>.from(units.single as Map);
  if (kind == 'structure') return out;
  unit['has_pipeline'] = kind == 'pipeline';
  if (kind != 'pipeline') unit.remove('pipeline');
  if (kind == 'pipeline' &&
      original['structure_units'][0]['has_pipeline'] != true) {
    throw const FormatException('所选解析流程已不存在');
  }
  for (final field in ['typing_profiles', 'content_templates']) {
    final selected =
        (kind == 'typing' && field == 'typing_profiles') ||
        (kind == 'content' && field == 'content_templates');
    final values = (unit[field] as List? ?? const []);
    unit[field] = selected
        ? values.where((v) => v is Map && v['id'] == targetId).toList()
        : <dynamic>[];
    if (selected && (unit[field] as List).length != 1) {
      throw const FormatException('所选内容已变更，请刷新后重试');
    }
  }
  out['structure_units'] = [unit];
  return out;
}
