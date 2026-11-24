import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../data/repositories/settings_repository.dart';
import '../domain/models/content_template.dart';
import '../domain/models/template.dart';
import 'providers.dart';

const _uuid = Uuid();
const String kChatQuickPresetsEnabledKey = 'chat_quick_presets_enabled';
const String kRecentGenerationPresetsKey = 'recent_generation_presets';

/// 一条可持久化的快捷生成套餐（既可作为「最近生成」记录，也可被用户 Pin 置顶）。
class QuickGenerationPreset {
  final String id;
  final String templateId;
  final String templateName;
  final String? contentTemplateId;
  final String? contentTemplateName;
  final bool allMaterials;
  final bool selectAllSlots;
  final List<String> selectedSlotKeys;
  final String? customTitle;
  final bool isPinned;
  final DateTime lastUsedAt;

  const QuickGenerationPreset({
    required this.id,
    required this.templateId,
    required this.templateName,
    this.contentTemplateId,
    this.contentTemplateName,
    this.allMaterials = true,
    this.selectAllSlots = true,
    this.selectedSlotKeys = const [],
    this.customTitle,
    this.isPinned = false,
    required this.lastUsedAt,
  });

  factory QuickGenerationPreset.create({
    required Template template,
    ContentTemplate? contentTemplate,
    required bool allMaterials,
    required bool selectAllSlots,
    required List<String> selectedSlotKeys,
    String? customTitle,
    bool isPinned = false,
    DateTime? lastUsedAt,
  }) {
    return QuickGenerationPreset(
      id: _uuid.v4(),
      templateId: template.id,
      templateName: template.name,
      contentTemplateId: contentTemplate?.id,
      contentTemplateName: contentTemplate?.name,
      allMaterials: allMaterials,
      selectAllSlots: selectAllSlots,
      selectedSlotKeys: List<String>.from(selectedSlotKeys),
      customTitle: customTitle?.trim().isEmpty == true ? null : customTitle?.trim(),
      isPinned: isPinned,
      lastUsedAt: lastUsedAt ?? DateTime.now(),
    );
  }

  QuickGenerationPreset copyWith({
    String? templateName,
    String? contentTemplateId,
    bool clearContentTemplate = false,
    String? contentTemplateName,
    bool? allMaterials,
    bool? selectAllSlots,
    List<String>? selectedSlotKeys,
    String? customTitle,
    bool clearCustomTitle = false,
    bool? isPinned,
    DateTime? lastUsedAt,
  }) {
    return QuickGenerationPreset(
      id: id,
      templateId: templateId,
      templateName: templateName ?? this.templateName,
      contentTemplateId:
          clearContentTemplate ? null : (contentTemplateId ?? this.contentTemplateId),
      contentTemplateName:
          clearContentTemplate ? null : (contentTemplateName ?? this.contentTemplateName),
      allMaterials: allMaterials ?? this.allMaterials,
      selectAllSlots: selectAllSlots ?? this.selectAllSlots,
      selectedSlotKeys: selectedSlotKeys ?? this.selectedSlotKeys,
      customTitle: clearCustomTitle ? null : (customTitle ?? this.customTitle),
      isPinned: isPinned ?? this.isPinned,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  /// 是否与指定的配置组合语义等价（用于去重）。
  bool matchesConfig({
    required String templateId,
    required String? contentTemplateId,
    required bool allMaterials,
    required bool selectAllSlots,
    required List<String> sortedSlotKeys,
  }) {
    if (this.templateId != templateId) return false;
    if ((this.contentTemplateId ?? '') != (contentTemplateId ?? '')) return false;
    if (this.allMaterials != allMaterials) return false;
    if (this.selectAllSlots != selectAllSlots) return false;
    if (!selectAllSlots) {
      if (selectedSlotKeys.length != sortedSlotKeys.length) return false;
      final a = List<String>.from(selectedSlotKeys)..sort();
      final b = List<String>.from(sortedSlotKeys)..sort();
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
    }
    return true;
  }

  String displayTitle({
    Template? liveTemplate,
    ContentTemplate? liveContentTemplate,
  }) {
    final alias = customTitle?.trim();
    if (alias != null && alias.isNotEmpty) return alias;
    final tName = liveTemplate?.name ?? templateName;
    if (contentTemplateId == null) {
      return '$tName · 无模板';
    }
    final ctName = liveContentTemplate?.name ?? contentTemplateName;
    if (ctName == null || ctName.trim().isEmpty) {
      return '$tName · 无模板';
    }
    return '$tName · $ctName';
  }

  /// 将预设解析为当前库里真实存在的实体；若对应文书类型已被删则返回 null。
  ({
    Template template,
    ContentTemplate? contentTemplate,
    bool allMaterials,
    Set<String> selectedSlotKeys,
  })? resolve({
    required List<Template> templates,
    required Map<String, List<ContentTemplate>> contentTemplatesByStructure,
    required bool hasPastRecords,
  }) {
    final tmpl = templates.where((t) => t.id == templateId).firstOrNull;
    if (tmpl == null) return null;

    final cts = contentTemplatesByStructure[tmpl.id] ?? const <ContentTemplate>[];
    final ct = contentTemplateId == null
        ? null
        : cts.where((c) => c.id == contentTemplateId).firstOrNull;

    final allKeys = tmpl.sortedSlots.map((s) => s.key).toSet();
    final Set<String> resolvedKeys;
    if (selectAllSlots) {
      resolvedKeys = allKeys;
    } else {
      final filtered = selectedSlotKeys.where(allKeys.contains).toSet();
      resolvedKeys = filtered.isEmpty ? allKeys : filtered;
    }

    final resolvedAllMaterials = allMaterials || !hasPastRecords;
    return (
      template: tmpl,
      contentTemplate: ct,
      allMaterials: resolvedAllMaterials,
      selectedSlotKeys: resolvedKeys,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'templateId': templateId,
        'templateName': templateName,
        if (contentTemplateId != null) 'contentTemplateId': contentTemplateId,
        if (contentTemplateName != null) 'contentTemplateName': contentTemplateName,
        'allMaterials': allMaterials,
        'selectAllSlots': selectAllSlots,
        'selectedSlotKeys': selectedSlotKeys,
        if (customTitle != null) 'customTitle': customTitle,
        'isPinned': isPinned,
        'lastUsedAt': lastUsedAt.toIso8601String(),
      };

  factory QuickGenerationPreset.fromJson(Map<String, dynamic> json) {
    final rawKeys = json['selectedSlotKeys'];
    final keys = rawKeys is List
        ? rawKeys.map((e) => e.toString()).toList()
        : const <String>[];
    final rawDate = json['lastUsedAt']?.toString();
    return QuickGenerationPreset(
      id: json['id']?.toString() ?? _uuid.v4(),
      templateId: json['templateId']?.toString() ?? '',
      templateName: json['templateName']?.toString() ?? '',
      contentTemplateId: json['contentTemplateId']?.toString(),
      contentTemplateName: json['contentTemplateName']?.toString(),
      allMaterials: json['allMaterials'] as bool? ?? true,
      selectAllSlots: json['selectAllSlots'] as bool? ?? true,
      selectedSlotKeys: keys,
      customTitle: json['customTitle']?.toString(),
      isPinned: json['isPinned'] as bool? ?? false,
      lastUsedAt: rawDate != null ? (DateTime.tryParse(rawDate) ?? DateTime.now()) : DateTime.now(),
    );
  }

  static String encodeList(List<QuickGenerationPreset> items) =>
      jsonEncode(items.map((e) => e.toJson()).toList());

  static List<QuickGenerationPreset> decodeList(String? raw) {
    if (raw == null || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return decoded
          .whereType<Map>()
          .map((m) => QuickGenerationPreset.fromJson(Map<String, dynamic>.from(m)))
          .where((p) => p.templateId.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }
}

/// 控制是否在会话页输入框上方默认显示「最近生成」快捷栏（默认开启）。
final chatQuickPresetsEnabledProvider =
    StateNotifierProvider<ChatQuickPresetsEnabledNotifier, bool>((ref) {
  return ChatQuickPresetsEnabledNotifier(ref.read(settingsRepositoryProvider));
});

class ChatQuickPresetsEnabledNotifier extends StateNotifier<bool> {
  final SettingsRepository _repo;
  late final Future<void> _loadFuture;

  ChatQuickPresetsEnabledNotifier(this._repo) : super(true) {
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final raw = await _repo.get(kChatQuickPresetsEnabledKey);
    if (raw != null) {
      state = raw != 'false';
    }
  }

  Future<bool> ensureLoaded() async {
    await _loadFuture;
    return state;
  }

  Future<void> toggle(bool enabled) async {
    state = enabled;
    await _repo.set(kChatQuickPresetsEnabledKey, enabled ? 'true' : 'false');
  }
}

/// 持久化管理已 Pin 套餐与最近生成记录。
final quickGenerationPresetsProvider =
    StateNotifierProvider<QuickGenerationPresetsNotifier, List<QuickGenerationPreset>>((ref) {
  return QuickGenerationPresetsNotifier(ref.read(settingsRepositoryProvider));
});

class QuickGenerationPresetsNotifier extends StateNotifier<List<QuickGenerationPreset>> {
  static const int maxRecentCount = 5;

  final SettingsRepository _repo;
  late final Future<void> _loadFuture;

  QuickGenerationPresetsNotifier(this._repo) : super(const []) {
    _loadFuture = _load();
  }

  Future<void> _load() async {
    final raw = await _repo.get(kRecentGenerationPresetsKey);
    state = _normalizeOrder(QuickGenerationPreset.decodeList(raw));
  }

  Future<List<QuickGenerationPreset>> ensureLoaded() async {
    await _loadFuture;
    return state;
  }

  List<QuickGenerationPreset> _normalizeOrder(List<QuickGenerationPreset> list) {
    final pinned = list.where((p) => p.isPinned).toList();
    final unpinned = list.where((p) => !p.isPinned).toList()
      ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
    return [
      ...pinned,
      ...unpinned.take(maxRecentCount),
    ];
  }

  Future<void> _save(List<QuickGenerationPreset> next) async {
    final normalized = _normalizeOrder(next);
    state = normalized;
    await _repo.set(kRecentGenerationPresetsKey, QuickGenerationPreset.encodeList(normalized));
  }

  /// 记录一次实际发起的文书生成配置（同组合去重并刷新时间戳，非 Pin 项保留最近 5 条）。
  Future<void> recordUsage({
    required Template template,
    required ContentTemplate? contentTemplate,
    required bool allMaterials,
    required Set<String> selectedSlotKeys,
  }) async {
    await _loadFuture;
    final templateAllKeys = template.sortedSlots.map((s) => s.key).toList();
    final selectAllSlots = templateAllKeys.isNotEmpty &&
        templateAllKeys.every((k) => selectedSlotKeys.contains(k));
    final normalizedKeys = templateAllKeys.where(selectedSlotKeys.contains).toList();
    final now = DateTime.now();

    final idx = state.indexWhere((p) => p.matchesConfig(
          templateId: template.id,
          contentTemplateId: contentTemplate?.id,
          allMaterials: allMaterials,
          selectAllSlots: selectAllSlots,
          sortedSlotKeys: normalizedKeys,
        ));

    if (idx >= 0) {
      final existing = state[idx];
      final updated = existing.copyWith(
        templateName: template.name,
        contentTemplateId: contentTemplate?.id,
        clearContentTemplate: contentTemplate == null,
        contentTemplateName: contentTemplate?.name,
        lastUsedAt: now,
      );
      final next = List<QuickGenerationPreset>.from(state);
      next[idx] = updated;
      await _save(next);
      return;
    }

    final created = QuickGenerationPreset.create(
      template: template,
      contentTemplate: contentTemplate,
      allMaterials: allMaterials,
      selectAllSlots: selectAllSlots,
      selectedSlotKeys: normalizedKeys,
      lastUsedAt: now,
    );
    await _save([created, ...state]);
  }

  /// 在设置页直接添加一个已 Pin 套餐（若已存在同配置则改为 Pin 并更新名称）。
  Future<void> addPinnedPreset({
    required Template template,
    required ContentTemplate? contentTemplate,
    required bool allMaterials,
    String? customTitle,
  }) async {
    await _loadFuture;
    final allKeys = template.sortedSlots.map((s) => s.key).toList();
    final trimmedAlias = customTitle?.trim();
    final alias = (trimmedAlias == null || trimmedAlias.isEmpty) ? null : trimmedAlias;

    final idx = state.indexWhere((p) => p.matchesConfig(
          templateId: template.id,
          contentTemplateId: contentTemplate?.id,
          allMaterials: allMaterials,
          selectAllSlots: true,
          sortedSlotKeys: allKeys,
        ));

    if (idx >= 0) {
      final next = List<QuickGenerationPreset>.from(state);
      next[idx] = next[idx].copyWith(
        isPinned: true,
        customTitle: alias,
        clearCustomTitle: alias == null,
        lastUsedAt: DateTime.now(),
      );
      await _save(next);
      return;
    }

    final created = QuickGenerationPreset.create(
      template: template,
      contentTemplate: contentTemplate,
      allMaterials: allMaterials,
      selectAllSlots: true,
      selectedSlotKeys: allKeys,
      customTitle: alias,
      isPinned: true,
    );
    await _save([created, ...state]);
  }

  Future<void> togglePin(String id) async {
    await _loadFuture;
    final next = [
      for (final p in state)
        if (p.id == id) p.copyWith(isPinned: !p.isPinned) else p,
    ];
    await _save(next);
  }

  Future<void> renamePreset(String id, String? customTitle) async {
    await _loadFuture;
    final trimmed = customTitle?.trim();
    final next = [
      for (final p in state)
        if (p.id == id)
          p.copyWith(
            customTitle: trimmed,
            clearCustomTitle: trimmed == null || trimmed.isEmpty,
          )
        else
          p,
    ];
    await _save(next);
  }

  Future<void> movePinned(int index, int delta) async {
    await _loadFuture;
    final pinned = state.where((p) => p.isPinned).toList();
    final unpinned = state.where((p) => !p.isPinned).toList();
    final target = index + delta;
    if (index < 0 || index >= pinned.length || target < 0 || target >= pinned.length) {
      return;
    }
    final item = pinned.removeAt(index);
    pinned.insert(target, item);
    await _save([...pinned, ...unpinned]);
  }

  Future<void> deletePreset(String id) async {
    await _loadFuture;
    await _save(state.where((p) => p.id != id).toList());
  }

  Future<void> clearUnpinned() async {
    await _loadFuture;
    await _save(state.where((p) => p.isPinned).toList());
  }
}
