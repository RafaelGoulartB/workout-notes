import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'schema_v37_fixture.dart';

/// Opens an in-memory database shaped exactly like an installed v37 database
/// (see [schemaV37Statements]), with foreign keys on.
///
/// No rows are inserted; callers add the data they want to see preserved.
Future<Database> openV37Database() async {
  final database = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 37,
      singleInstance: false,
      onConfigure: (db) => db.execute('PRAGMA foreign_keys = ON'),
      onCreate: (db, _) async {
        for (final statement in schemaV37Statements) {
          await db.execute(statement);
        }
      },
    ),
  );
  return database;
}

/// Columns, foreign keys and indexes of every user table, normalised so two
/// databases can be compared regardless of column order or auto-index names.
///
/// Keys look like `table:<name>`, `fk:<name>` and `index:<name>`.
Future<Map<String, Object>> schemaSnapshot(Database database) async {
  final snapshot = <String, Object>{};
  final tables = await database.rawQuery(
    "SELECT name FROM sqlite_master WHERE type = 'table' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  for (final row in tables) {
    final table = row['name'] as String;
    final columns = await database.rawQuery('PRAGMA table_info("$table")');
    snapshot['table:$table'] =
        columns
            .map(
              (c) =>
                  '${c['name']} ${c['type']} '
                  'notnull=${c['notnull']} default=${c['dflt_value']} '
                  'pk=${c['pk']}',
            )
            .toList()
          ..sort();
    final fks = await database.rawQuery('PRAGMA foreign_key_list("$table")');
    snapshot['fk:$table'] =
        fks
            .map(
              (f) =>
                  '${f['from']}->${f['table']}.${f['to']} '
                  'delete=${f['on_delete']}',
            )
            .toList()
          ..sort();
  }
  final indexes = await database.rawQuery(
    "SELECT name, tbl_name FROM sqlite_master WHERE type = 'index' "
    "AND name NOT LIKE 'sqlite_%' ORDER BY name",
  );
  for (final row in indexes) {
    final name = row['name'] as String;
    final columns = await database.rawQuery('PRAGMA index_xinfo("$name")');
    final keyColumns = columns
        .where((c) => c['key'] == 1)
        .map((c) => '${c['name']}${c['desc'] == 1 ? ' DESC' : ''}')
        .join(', ');
    final unique = (await database.rawQuery(
      'PRAGMA index_list("${row['tbl_name']}")',
    )).firstWhere((i) => i['name'] == name)['unique'];
    snapshot['index:$name'] = '${row['tbl_name']}($keyColumns) unique=$unique';
  }
  return snapshot;
}

/// Human-readable differences between two [schemaSnapshot]s (empty when equal).
List<String> schemaDifferences(
  Map<String, Object> expected,
  Map<String, Object> actual,
) {
  final differences = <String>[];
  for (final key in {...expected.keys, ...actual.keys}.toList()..sort()) {
    final a = expected[key];
    final b = actual[key];
    if ('$a' != '$b') {
      differences.add('$key\n  expected: $a\n  actual:   $b');
    }
  }
  return differences;
}
