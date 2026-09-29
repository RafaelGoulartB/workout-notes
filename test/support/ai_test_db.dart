import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_db.dart';

/// Installs an empty in-memory database with the real schema (see
/// [installTestDb]) as [DatabaseHelper.overrideDatabase] and returns it.
/// Tests should call [uninstallAiTestDb] in `tearDown`.
///
/// [includeRoutineDayNotes] `false` drops `routine_days.notes` to reproduce
/// the fresh installs that once shipped without it.
Future<Database> installAiTestDb({bool includeRoutineDayNotes = true}) async {
  final db = await installTestDb();
  if (!includeRoutineDayNotes) {
    await db.execute('ALTER TABLE routine_days DROP COLUMN notes');
  }
  return db;
}

Future<void> uninstallAiTestDb() => uninstallTestDb();
