import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../domain/models/icd_diagnosis.dart';

class IcdService {
  static const int _expectedAssetBytes = 8269824;

  Database? _db;
  Future<Database>? _initFuture;

  Future<Database> get _database async {
    if (_db != null) return _db!;
    _initFuture ??= _initDatabase();
    _db = await _initFuture!;
    return _db!;
  }

  Future<Database> _initDatabase() async {
    final dbDir = await getDatabasesPath();
    final dbPath = p.join(dbDir, 'icd_knowledge.db');
    final file = File(dbPath);

    // 仅当本地数据库不存在或大小不一致时才解压读取 8MB Asset，避免每次冷启动重复加载大文件造成掉帧
    if (!file.existsSync() || file.lengthSync() != _expectedAssetBytes) {
      final assetData = await rootBundle.load('assets/data/icd_knowledge.db');
      final assetBytes = assetData.buffer.asUint8List(
        assetData.offsetInBytes,
        assetData.lengthInBytes,
      );
      if (!file.existsSync() || file.lengthSync() != assetBytes.length) {
        await file.writeAsBytes(assetBytes, flush: true);
      }
    }

    return openDatabase(dbPath, readOnly: true);
  }

  /// Cleans a query according to medical search rules:
  /// - Strips all symbols (brackets, dashes, pluses, spaces, slashes, punctuation)
  /// - Lowercases English letters
  /// - Keeps Chinese characters and numbers
  static String cleanQuery(String input) {
    final buffer = StringBuffer();
    for (int i = 0; i < input.length; i++) {
      final code = input.codeUnitAt(i);
      final isChinese = code >= 0x4E00 && code <= 0x9FA5;
      final isDigit = code >= 0x30 && code <= 0x39;
      final isAlpha = (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);

      if (isChinese || isDigit) {
        buffer.writeCharCode(code);
      } else if (isAlpha) {
        buffer.writeCharCode((code >= 0x41 && code <= 0x5A) ? code + 32 : code);
      }
    }
    return buffer.toString().trim();
  }

  /// Super-fuzzy search against 38,500+ ICD records:
  /// Matches cleanCode, mixedPy, cleanName, or purePy (汉字拼音首字母，忽略夹杂在中间的特殊字符/英文/数字).
  Future<List<IcdDiagnosis>> search(String rawQuery, {int limit = 50}) async {
    final clean = cleanQuery(rawQuery);
    if (clean.isEmpty) return [];

    final db = await _database;

    // Generate potential adjacent transposition variation (e.g. xngj <-> xgnj)
    String? swappedVariant;
    if (clean.length >= 3 && clean.length <= 6 && RegExp(r'^[a-z]+$').hasMatch(clean)) {
      // Test swapping adjacent characters (e.g. middle characters)
      for (int i = 0; i < clean.length - 1; i++) {
        final swapped = clean.substring(0, i) +
            clean[i + 1] +
            clean[i] +
            clean.substring(i + 2);
        if (swapped != clean) {
          swappedVariant = swapped;
          break;
        }
      }
    }

    // Ordered ranking:
    // 1. Exact match on code, name, mixed_py or pure_py (score 100)
    // 2. Prefix match on code, mixed_py or pure_py (score 80)
    // 3. Substring match on clean_name (score 60)
    // 4. Substring match on mixed_py or pure_py (score 40)
    // 5. Transposition variant match (score 30)
    final hasVariant = swappedVariant != null;

    final querySql = '''
      SELECT *,
        CASE 
          WHEN clean_code = ? OR clean_name = ? OR mixed_py = ? OR pure_py = ? THEN 100
          WHEN clean_code LIKE ? OR mixed_py LIKE ? OR pure_py LIKE ? THEN 80
          WHEN clean_name LIKE ? THEN 60
          WHEN mixed_py LIKE ? OR pure_py LIKE ? THEN 40
          ${hasVariant ? "WHEN pure_py LIKE ? OR mixed_py LIKE ? THEN 30" : ""}
          ELSE 10
        END AS rank_score
      FROM icd_diagnoses
      WHERE clean_code LIKE ? 
         OR clean_name LIKE ? 
         OR mixed_py LIKE ? 
         OR pure_py LIKE ?
         ${hasVariant ? "OR pure_py LIKE ? OR mixed_py LIKE ?" : ""}
      ORDER BY rank_score DESC, length(name) ASC
      LIMIT ?
    ''';

    final args = <dynamic>[
      // Exact score params
      clean, clean, clean, clean,
      // Prefix score params
      '$clean%', '$clean%', '$clean%',
      // Substring name score params
      '%$clean%',
      // Substring py score params
      '%$clean%', '%$clean%',
    ];

    if (hasVariant) {
      args.add('%$swappedVariant%');
      args.add('%$swappedVariant%');
    }

    // Where clause params
    args.add('$clean%');
    args.add('%$clean%');
    args.add('%$clean%');
    args.add('%$clean%');

    if (hasVariant) {
      args.add('%$swappedVariant%');
      args.add('%$swappedVariant%');
    }

    args.add(limit);

    final results = await db.rawQuery(querySql, args);
    return results.map((m) => IcdDiagnosis.fromMap(m)).toList();
  }

  /// 获取全量 Raw 词条库（分页，按 ICD 编码 clean_code 正序排列）
  Future<List<IcdDiagnosis>> getPaged({int offset = 0, int limit = 50}) async {
    final db = await _database;
    final maps = await db.query(
      'icd_diagnoses',
      orderBy: 'clean_code ASC',
      limit: limit,
      offset: offset,
    );
    return maps.map((m) => IcdDiagnosis.fromMap(m)).toList();
  }

  /// 获取知识库中的词条总条数
  Future<int> getTotalCount() async {
    final db = await _database;
    final res = await db.rawQuery('SELECT COUNT(*) as cnt FROM icd_diagnoses');
    return Sqflite.firstIntValue(res) ?? 0;
  }
}
