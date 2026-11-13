import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:peipal/data/services/hub/hub_payload.dart';
import 'package:peipal/data/services/hub/hub_service.dart';

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};
  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async => values[key];
  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value != null) values[key] = value;
  }

  @override
  Future<void> delete({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    values.remove(key);
  }
}

Map<String, dynamic> _payload() => {
  'engine': 'medhistory_engine_c',
  'version': '2.0',
  'structure_units': [
    {
      'structure': {'id': 's', 'name': '检查记录', 'slots': []},
      'has_pipeline': true,
      'pipeline': {'nodes': []},
      'typing_profiles': [
        {'id': 'p1'},
        {'id': 'p2'},
      ],
      'content_templates': [
        {
          'id': 'c1',
          'slots': {
            'result': {
              'catalog_refs': [
                {'type': 'inspection', 'tag': '常用'},
              ],
            },
          },
        },
        {'id': 'c2'},
      ],
    },
  ],
  'catalogs': [
    {'id': 'inspection', 'name': '检查标准'},
  ],
  'catalog_entries': [
    {'id': 'e', 'catalog_type': 'inspection', 'name': '正常'},
  ],
  'catalog_tags': {
    'inspection': ['常用'],
  },
};

void main() {
  test(
    'selecting one child retains its structure and portable catalog data',
    () {
      final original = _payload();
      final selected = selectHubPayload(original, 'content', 'c1');
      final unit = (selected['structure_units'] as List).single as Map;
      expect((unit['content_templates'] as List).single['id'], 'c1');
      expect(unit['typing_profiles'], isEmpty);
      expect(unit['has_pipeline'], false);
      expect(selected['catalogs'], original['catalogs']);
      expect(selected['catalog_entries'], original['catalog_entries']);
      expect(selected['catalog_tags'], original['catalog_tags']);
      expect(original['structure_units'][0]['content_templates'], hasLength(2));
    },
  );
  test('missing target never silently imports all siblings', () {
    expect(
      () => selectHubPayload(_payload(), 'content', 'missing'),
      throwsFormatException,
    );
    expect(
      () => selectHubPayload(_payload(), 'typing', 'missing'),
      throwsFormatException,
    );
  });
  test('catalog-only download does not import bundled structures', () {
    final selected = selectHubPayload(_payload(), 'diagnosis', '');
    expect(selected.containsKey('structure_units'), false);
    expect(selected['catalog_entries'], hasLength(1));
  });
  test(
    'administrator and ownership credentials are isolated per server',
    () async {
      final storage = _Storage();
      storage.values['hub_owner_key'] = 'legacy-official-owner';
      storage.values['hub_admin_token'] = 'legacy-official-admin';
      final hub = HubService(storage);
      expect(await hub.ownerKey(), 'legacy-official-owner');
      expect(await hub.getAdminToken(), 'legacy-official-admin');
      await hub.setBaseUrl('https://other.example/templates');
      expect(await hub.getAdminToken(), isNull);
      final otherOwner = await hub.ownerKey();
      expect(otherOwner, isNot('legacy-official-owner'));
      await hub.setAdminToken('other-administrator');
      await hub.setBaseUrl(null);
      expect(await hub.getAdminToken(), 'legacy-official-admin');
      expect(await hub.ownerKey(), 'legacy-official-owner');
      await hub.setBaseUrl('https://other.example/templates');
      expect(await hub.getAdminToken(), 'other-administrator');
      expect(await hub.ownerKey(), otherOwner);
    },
  );
}
