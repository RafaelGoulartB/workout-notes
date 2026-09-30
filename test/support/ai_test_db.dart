import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'test_db.dart';

/// Installs an empty in-memory database with the real schema (see
/// [installTestDb]) as [DatabaseHelper.overrideDatabase] and returns it.
/// Tests should call [uninstallAiTestDb] in `tearDown`.
Future<Database> installAiTestDb() => installTestDb();

Future<void> uninstallAiTestDb() => uninstallTestDb();
