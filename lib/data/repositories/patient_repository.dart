import 'package:flutter/foundation.dart';

import '../../domain/models/patient.dart';
import '../database/database_helper.dart';

class PatientRepository {
  List<Patient> _safeMapRows(List<Map<String, dynamic>> rows) {
    final result = <Patient>[];
    for (final row in rows) {
      try {
        result.add(Patient.fromMap(row));
      } catch (e, st) {
        debugPrint('跳过损坏的患者行 (${row['id']}): $e\n$st');
      }
    }
    return result;
  }

  Future<List<Patient>> getAll() async {
    final db = await DatabaseHelper.database;
    final maps = await db.query('patients', orderBy: 'updated_at DESC');
    return _safeMapRows(maps);
  }

  Future<Patient?> getById(String id) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query('patients', where: 'id = ?', whereArgs: [id]);
    if (maps.isEmpty) return null;
    return Patient.fromMap(maps.first);
  }

  Future<List<Patient>> search(String query) async {
    final db = await DatabaseHelper.database;
    final maps = await db.query(
      'patients',
      where: 'name LIKE ? OR medical_record_number LIKE ?',
      whereArgs: ['%$query%', '%$query%'],
      orderBy: 'updated_at DESC',
    );
    return _safeMapRows(maps);
  }

  Future<void> insert(Patient patient) async {
    final db = await DatabaseHelper.database;
    await db.insert('patients', patient.toMap());
  }

  Future<void> update(Patient patient) async {
    final db = await DatabaseHelper.database;
    await db.update(
      'patients',
      patient.toMap(),
      where: 'id = ?',
      whereArgs: [patient.id],
    );
  }

  Future<void> delete(String id) async {
    final db = await DatabaseHelper.database;
    await db.transaction((txn) async {
      await txn.delete('messages', where: 'patient_id = ?', whereArgs: [id]);
      await txn.delete('patients', where: 'id = ?', whereArgs: [id]);
    });
  }
}
