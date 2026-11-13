import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:peipal/data/services/hub/hub_payload.dart';
import 'package:peipal/data/services/hub/hub_service.dart';

class _Storage extends FlutterSecureStorage {
  final values = <String, String>{};
  IOSOptions? lastWriteIosOptions;
  MacOsOptions? lastWriteMacOptions;
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
    lastWriteIosOptions = iOptions;
    lastWriteMacOptions = mOptions;
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
      final officialOwner = await hub.ownerKey();
      expect(officialOwner, isNot('legacy-official-owner'));
      expect(await hub.getAdminToken(), 'legacy-official-admin');
      await hub.setBaseUrl('https://other.example/templates');
      expect(await hub.getAdminToken(), isNull);
      final otherOwner = await hub.ownerKey();
      expect(otherOwner, isNot(officialOwner));
      await hub.setAdminToken('other-administrator');
      await hub.setBaseUrl(null);
      expect(await hub.getAdminToken(), 'legacy-official-admin');
      expect(await hub.ownerKey(), officialOwner);
      await hub.setBaseUrl('https://other.example/templates');
      expect(await hub.getAdminToken(), 'other-administrator');
      expect(await hub.ownerKey(), otherOwner);
    },
  );
  test(
    'copied legacy keys never become new device publishing identities',
    () async {
      final deviceA = _Storage();
      final deviceB = _Storage();
      for (final storage in [deviceA, deviceB]) {
        storage.values['hub_owner_key'] = 'copied-legacy-official-owner';
        storage.values['hub_owner_key_aHR0cHM6Ly9vdGhlci5leGFtcGxlL3RlbXBsYXRlcw=='] =
            'copied-legacy-custom-owner';
      }
      final identities = await Future.wait([
        HubService(deviceA).ownerKey(),
        HubService(deviceB).ownerKey(),
      ]);
      expect(identities.toSet(), hasLength(2));
      expect(identities, isNot(contains('copied-legacy-official-owner')));
      expect(await HubService(deviceA).ownerKey(), identities[0]);
      expect(await HubService(deviceB).ownerKey(), identities[1]);
      for (final storage in [deviceA, deviceB]) {
        final hub = HubService(storage);
        await hub.setBaseUrl('https://other.example/templates');
        expect(await hub.ownerKey(), isNot('copied-legacy-custom-owner'));
      }
    },
  );
  test(
    'concurrent service initialization keeps one stable local identity',
    () async {
      final storage = _Storage();
      final keys = await Future.wait(
        List.generate(12, (_) => HubService(storage).ownerKey()),
      );
      expect(keys.toSet(), hasLength(1));
      expect(
        storage.values.keys.where((k) => k.startsWith('hub_publisher_key_v2_')),
        hasLength(1),
      );
      expect(
        storage.lastWriteIosOptions?.toMap(),
        containsPair('accessibility', 'first_unlock_this_device'),
      );
      expect(
        storage.lastWriteIosOptions?.toMap(),
        containsPair('synchronizable', 'false'),
      );
      expect(
        storage.lastWriteMacOptions?.toMap(),
        containsPair('accessibility', 'first_unlock_this_device'),
      );
      expect(
        storage.lastWriteMacOptions?.toMap(),
        containsPair('synchronizable', 'false'),
      );
    },
  );
}
