import 'package:sqflite/sqflite.dart';
import '../database/database_provider.dart';
import '../database/database_helper.dart';

/// Base class for all domain repositories.
/// Provides access to the database connection from [DatabaseHelper].
abstract class BaseRepository {
  final DatabaseProvider databaseProvider;

  BaseRepository([DatabaseProvider? databaseProvider])
    : databaseProvider = databaseProvider ?? DatabaseHelper.instance;

  Future<Database> get db => databaseProvider.database;
}
