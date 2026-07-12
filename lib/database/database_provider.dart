import 'package:sqflite/sqflite.dart';

/// Contract used by repositories to obtain the SQLite connection.
abstract interface class DatabaseProvider {
  Future<Database> get database;
}

/// Explicitly configured fallback for legacy construction sites while the UI is
/// migrated to [AppDependenciesScope]. Repositories never import the concrete
/// database implementation.
abstract final class DatabaseProviderRegistry {
  static DatabaseProvider? _current;

  static DatabaseProvider get current {
    final provider = _current;
    if (provider == null) {
      throw StateError('DatabaseProviderRegistry has not been configured.');
    }
    return provider;
  }

  static void configure(DatabaseProvider provider) {
    _current = provider;
  }
}
