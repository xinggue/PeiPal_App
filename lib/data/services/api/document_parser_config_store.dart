import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../../domain/models/document_parser_provider.dart';

class DocumentParserSettings {
  final List<DocumentParserProviderConfig> providers;
  final String activeProviderId;
  DocumentParserSettings({
    List<DocumentParserProviderConfig>? providers,
    this.activeProviderId = '',
  }) : providers = providers ?? DocumentParserProviderConfig.presets;
  DocumentParserProviderConfig? get activeProvider =>
      providers.where((p) => p.id == activeProviderId).firstOrNull;
  Map<String, dynamic> toJson() => {
    'providers': providers.map((p) => p.toJson()).toList(),
    'activeProviderId': activeProviderId,
  };

  static DocumentParserSettings merge(
    DocumentParserSettings current,
    Map json,
  ) {
    final incoming = json['providers'];
    final byId = {for (final p in current.providers) p.id: p};
    if (incoming is List) {
      for (final raw in incoming.whereType<Map>()) {
        final old = byId[raw['id']];
        if (old == null) continue;
        final merged = {...old.toJson(), ...raw};
        if (raw['apiKey']?.toString().trim().isEmpty ?? true) {
          merged['apiKey'] = old.apiKey;
        }
        final config = DocumentParserProviderConfig.fromJson(merged);
        if (config != null) byId[config.id] = config;
      }
    }
    final selected =
        json['activeProviderId']?.toString() ?? current.activeProviderId;
    return DocumentParserSettings(
      providers: byId.values.toList(),
      activeProviderId: selected.isEmpty || byId.containsKey(selected)
          ? selected
          : current.activeProviderId,
    );
  }
}

class DocumentParserConfigStore {
  static const storageKey = 'document_parser_settings_v1';
  final FlutterSecureStorage storage;
  DocumentParserConfigStore(this.storage);
  Future<DocumentParserSettings> load() async {
    final raw = await storage.read(key: storageKey);
    if (raw == null || raw.isEmpty) return DocumentParserSettings();
    return DocumentParserSettings.merge(
      DocumentParserSettings(),
      jsonDecode(raw) as Map,
    );
  }

  Future<void> save(DocumentParserSettings value) =>
      storage.write(key: storageKey, value: jsonEncode(value.toJson()));
  Future<void> importSettings(Map json) async =>
      save(DocumentParserSettings.merge(await load(), json));
}
