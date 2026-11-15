import 'dart:convert';
import 'dart:io';

import 'package:file_selector_platform_interface/file_selector_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peipal/data/services/engine_c/config_file_io.dart';

// Enforce the same filter requirement as file_selector_ios before returning
// the sandbox copy created by its document picker.
class _IosFileSelector extends FileSelectorPlatform {
  XFile? selection;

  @override
  Future<XFile?> openFile({
    List<XTypeGroup>? acceptedTypeGroups,
    String? initialDirectory,
    String? confirmButtonText,
  }) async {
    for (final group in acceptedTypeGroups ?? <XTypeGroup>[]) {
      if (!group.allowsAny &&
          (group.uniformTypeIdentifiers?.isEmpty ?? true)) {
        throw ArgumentError('iOS requires uniformTypeIdentifiers');
      }
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        expect(group.uniformTypeIdentifiers, contains('public.data'));
      }
    }
    return selection;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FileSelectorPlatform original;
  late _IosFileSelector selector;
  late Directory temp;

  setUp(() async {
    original = FileSelectorPlatform.instance;
    selector = _IosFileSelector();
    FileSelectorPlatform.instance = selector;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    temp = await Directory.systemTemp.createTemp('peipal_config_import_');
  });

  tearDown(() async {
    FileSelectorPlatform.instance = original;
    debugDefaultTargetPlatformOverride = null;
    await temp.delete(recursive: true);
  });

  for (final extension in ['txt', 'json', 'cfg', 'csv']) {
    test('imports UTF-8 configuration from iOS selection (.$extension)', () async {
      final content = jsonEncode({
        'engine': 'medhistory_engine_c',
        'diagnosis_tags': ['心内科'],
      });
      final file = File('${temp.path}/配置 文件.$extension');
      await file.writeAsString(content, encoding: utf8);
      selector.selection = XFile(file.path);

      expect(await ConfigFileIo.pickAndReadConfigFile(), content);
    });
  }

  test('cancelling the iOS picker returns null', () async {
    expect(await ConfigFileIo.pickAndReadConfigFile(), isNull);
  });
}
