import 'package:sqflite/sqflite.dart';
import '../database/database_helper.dart';

/// Base class for all domain repositories.
/// Provides access to the database connection from [DatabaseHelper].
abstract class BaseRepository {
  DatabaseHelper get _dbHelper => DatabaseHelper.instance;
  Future<Database> get db => _dbHelper.database;
}
