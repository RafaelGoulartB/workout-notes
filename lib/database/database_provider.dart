import 'package:sqflite/sqflite.dart';

/// Contract used by repositories to obtain the SQLite connection.
abstract interface class DatabaseProvider {
  Future<Database> get database;
}
