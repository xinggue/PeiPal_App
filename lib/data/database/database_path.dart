import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

/// Test hook. Desktop FFI's default path is the process working directory.
Future<String> Function()? databasesPathOverride;

/// sqflite_common_ffi's [getDatabasesPath] is `<cwd>/.dart_tool/...`.
/// An installed app's cwd is Program Files, which cannot be written
/// (sqlite error 14). Desktop data lives under Application Support instead.
Future<String> appDatabasesPath() async {
  final override = databasesPathOverride;
  if (override != null) return override();

  if (!kIsWeb &&
      (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'databases'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir.path;
  }

  final path = await getDatabasesPath();
  final dir = Directory(path);
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return path;
}
