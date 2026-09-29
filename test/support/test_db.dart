import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/database/database_schema.dart';

/// Initializes the sqflite FFI factory once for the current test isolate.
///
/// Safe to call from every `setUpAll`; replaces the `sqfliteFfiInit()` +
/// `databaseFactory = databaseFactoryFfi` boilerplate.
void initSqfliteFfiForTests() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;
}

/// Opens an in-memory database with the REAL current schema
/// ([DatabaseSchema.createSchema], foreign keys on) and no seed rows.
///
/// Pass [seed] to also insert the catalog seed (exercise categories,
/// built-in exercises, meal types) exactly like a fresh install. The caller
/// owns the handle and must close it (or use [installTestDb]).
Future<Database> openTestDb({bool seed = false}) async {
  initSqfliteFfiForTests();
  return databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) =>
          seed ? DatabaseSchema.onCreate(db, 1) : DatabaseSchema.createSchema(db),
    ),
  );
}

Database? _installed;

/// Opens a real-schema in-memory database (see [openTestDb]) and installs it
/// as [DatabaseHelper.overrideDatabase]. Pair with [uninstallTestDb] in
/// `tearDown`. Installing again closes the previously installed database.
Future<Database> installTestDb({bool seed = false}) async {
  await uninstallTestDb();
  final db = await openTestDb(seed: seed);
  _installed = db;
  DatabaseHelper.overrideDatabase = db;
  return db;
}

/// Clears [DatabaseHelper.overrideDatabase] and closes the installed database.
Future<void> uninstallTestDb() async {
  DatabaseHelper.overrideDatabase = null;
  final db = _installed;
  _installed = null;
  if (db != null && db.isOpen) await db.close();
}
