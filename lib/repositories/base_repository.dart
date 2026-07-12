import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_provider.dart';

/// Base class for all domain repositories.
/// Provides access to the database connection supplied by the composition root.
abstract class BaseRepository {
  final DatabaseProvider? _databaseProvider;

  BaseRepository([DatabaseProvider? databaseProvider])
    : _databaseProvider = databaseProvider;

  Future<Database> get db =>
      (_databaseProvider ?? DatabaseProviderRegistry.current).database;
}
