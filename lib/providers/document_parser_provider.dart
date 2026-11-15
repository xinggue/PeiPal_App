import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/services/api/document_parser_api.dart';
import '../data/services/api/document_parser_config_store.dart';
import '../domain/models/document_parser_provider.dart';
import 'providers.dart';

final documentParserApiProvider = Provider<DocumentParserApi>(
  (ref) => DocumentParserApi(),
);

class DocumentParserNotifier
    extends StateNotifier<AsyncValue<DocumentParserSettings>> {
  final DocumentParserConfigStore store;
  late final Future<void> ready;
  DocumentParserNotifier(this.store) : super(const AsyncLoading()) {
    ready = _load();
  }
  Future<void> _load() async {
    try {
      state = AsyncData(await store.load());
    } catch (e, st) {
      state = AsyncError(e, st);
    }
  }

  Future<void> saveProvider(
    DocumentParserProviderConfig provider, {
    bool select = false,
  }) async {
    await ready;
    final settings = state.requireValue;
    final updated = DocumentParserSettings(
      providers: [
        for (final p in settings.providers) p.id == provider.id ? provider : p,
      ],
      activeProviderId: select ? provider.id : settings.activeProviderId,
    );
    await store.save(updated);
    state = AsyncData(updated);
  }
}

final documentParserProvider =
    StateNotifierProvider<
      DocumentParserNotifier,
      AsyncValue<DocumentParserSettings>
    >(
      (ref) => DocumentParserNotifier(
        DocumentParserConfigStore(ref.read(secureStorageProvider)),
      ),
    );
