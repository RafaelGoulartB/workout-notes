import 'package:sqflite/sqflite.dart';

import '../database_periodization_schema.dart';

abstract final class DatabasePeriodizationMigrations {
  static Future<void> upgrade(Database db, int oldVersion) async {
    if (oldVersion < 37) {
      await DatabasePeriodizationSchema.create(db);
    }
  }
}
