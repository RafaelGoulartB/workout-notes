import 'package:sqflite/sqflite.dart';

/// Medication reminders and the dose log (v55). Shared by `onCreate` and the
/// v55 upgrade so both paths build identical tables.
abstract final class DatabaseMedicationSchema {
  static Future<void> create(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medications (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        dosage TEXT,
        notes TEXT,
        times_json TEXT NOT NULL,
        weekdays_json TEXT NOT NULL,
        escalation_minutes INTEGER NOT NULL DEFAULT 30,
        enabled INTEGER NOT NULL DEFAULT 1,
        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS medication_doses (
        id TEXT PRIMARY KEY,
        medication_id TEXT NOT NULL,
        dose_key TEXT NOT NULL,
        scheduled_at TEXT NOT NULL,
        status TEXT NOT NULL,
        recorded_at TEXT NOT NULL,
        UNIQUE (medication_id, dose_key),
        FOREIGN KEY (medication_id) REFERENCES medications(id) ON DELETE CASCADE
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_medication_doses_scheduled ON medication_doses(scheduled_at DESC)',
    );
  }
}
