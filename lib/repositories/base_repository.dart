import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_provider.dart';

/// Base class for all domain repositories.
/// Provides access to the database connection supplied by the composition root.
abstract class BaseRepository {
  final DatabaseProvider databaseProvider;

  BaseRepository([DatabaseProvider? databaseProvider])
    : databaseProvider = databaseProvider ?? DatabaseProviderRegistry.current;

  Future<Database> get db => databaseProvider.database;
}
