import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_provider.dart';

typedef DatabaseCreate = Future<void> Function(Database database, int version);
typedef DatabaseUpgrade =
    Future<void> Function(Database database, int oldVersion, int newVersion);

/// SQLite connection infrastructure.
///
/// Schema creation, migrations, and seed data are deliberately supplied by
/// collaborators so this class has one responsibility: opening and providing
/// a configured database connection.
class AppDatabase implements DatabaseProvider {
  AppDatabase({
    required this.name,
    required this.version,
    required this.onCreate,
    required this.onUpgrade,
  });

  final String name;
  final int version;
  final DatabaseCreate onCreate;
  final DatabaseUpgrade onUpgrade;

  Database? _database;

  @override
  Future<Database> get database async {
    _database ??= await _open();
    return _database!;
  }

  Future<Database> _open() async {
    final databasePath = await getDatabasesPath();
    return openDatabase(
      path.join(databasePath, name),
      version: version,
      onConfigure: (database) => database.execute('PRAGMA foreign_keys = ON'),
      onCreate: onCreate,
      onUpgrade: onUpgrade,
      singleInstance: true,
    );
  }
}
