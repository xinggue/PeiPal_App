import 'dart:io';

/// Restrict existing files as well as new ones. SQLite inherits the database
/// mode when creating journals and WAL/SHM files.
Future<void> restrictMacosDatabaseFiles(String path) async {
  if (!Platform.isMacOS) return;
  final dbFile = File(path);
  await _chmod(dbFile.parent.path, '700');
  if (!await dbFile.exists()) await dbFile.create();
  for (final suffix in ['', '-wal', '-shm', '-journal']) {
    final file = File('$path$suffix');
    if (await file.exists()) await _chmod(file.path, '600');
  }
}

Future<void> _chmod(String path, String mode) async {
  final result = await Process.run('/bin/chmod', [mode, path]);
  if (result.exitCode != 0) {
    throw FileSystemException('无法设置本地数据访问权限', path);
  }
}
