import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/medication.dart';
import 'base_repository.dart';

class MedicationRepository extends BaseRepository {
  static const _uuid = Uuid();

  Future<List<Medication>> getAll() async {
    final rows = await (await db).query(
      'medications',
      orderBy: 'enabled DESC, name COLLATE NOCASE ASC',
    );
    return rows
        .map((row) => Medication.fromMap(Map<String, Object?>.from(row)))
        .toList();
  }

  Future<Medication> insert({
    required String name,
    String? dosage,
    String? notes,
    required List<MedicationTime> times,
    required List<int> weekdays,
    required int escalationMinutes,
  }) async {
    final now = DateTime.now();
    final medication = Medication(
      id: _uuid.v4(),
      name: name.trim(),
      dosage: _blankToNull(dosage),
      notes: _blankToNull(notes),
      times: List<MedicationTime>.from(times)..sort(),
      weekdays: List<int>.from(weekdays)..sort(),
      escalationMinutes: escalationMinutes,
      enabled: true,
      createdAt: now,
      updatedAt: now,
    );
    await (await db).insert('medications', medication.toMap());
    return medication;
  }

  Future<void> update(Medication medication) async {
    await (await db).update(
      'medications',
      medication.toMap(),
      where: 'id = ?',
      whereArgs: [medication.id],
    );
  }

  Future<void> delete(String id) async {
    final database = await db;
    await database.transaction((txn) async {
      // Explicit so the log goes even where foreign keys are not enforced.
      await txn.delete(
        'medication_doses',
        where: 'medication_id = ?',
        whereArgs: [id],
      );
      await txn.delete('medications', where: 'id = ?', whereArgs: [id]);
    });
  }

  /// Doses scheduled in `[from, to)`, oldest first.
  Future<List<MedicationDose>> getDoses({
    required DateTime from,
    required DateTime to,
  }) async {
    final rows = await (await db).query(
      'medication_doses',
      where: 'scheduled_at >= ? AND scheduled_at < ?',
      whereArgs: [from.toIso8601String(), to.toIso8601String()],
      orderBy: 'scheduled_at ASC',
    );
    return rows
        .map((row) => MedicationDose.fromMap(Map<String, Object?>.from(row)))
        .toList();
  }

  /// Records (or replaces) the answer for one dose. Idempotent per
  /// medication and dose key, so a spool entry imported twice is harmless.
  Future<MedicationDose> recordDose({
    required String medicationId,
    required String doseKey,
    required DateTime scheduledAt,
    required MedicationDoseStatus status,
    DateTime? recordedAt,
  }) async {
    final dose = MedicationDose(
      id: _uuid.v4(),
      medicationId: medicationId,
      doseKey: doseKey,
      scheduledAt: scheduledAt,
      status: status,
      recordedAt: recordedAt ?? DateTime.now(),
    );
    await (await db).insert(
      'medication_doses',
      dose.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    return dose;
  }

  Future<void> deleteDose(String medicationId, String doseKey) async {
    await (await db).delete(
      'medication_doses',
      where: 'medication_id = ? AND dose_key = ?',
      whereArgs: [medicationId, doseKey],
    );
  }

  static String? _blankToNull(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
