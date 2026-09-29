import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/database/database_helper.dart';

import 'test_db.dart';

/// Statements a repository sent to the database, in order.
///
/// Lets tests assert that a call is bounded ("two queries no matter how many
/// meals") instead of N+1. Each entry is the SQL text for raw calls or a short
/// `query <table>` / `insert <table>` style label for helper calls; a batch is
/// recorded as one `batch(<size>)` entry when it commits.
class SqlLog {
  final List<String> statements = [];

  void clear() => statements.clear();

  /// Reads: `SELECT` SQL and `query <table>` helper calls.
  int get reads => statements
      .where(
        (s) => s.toUpperCase().startsWith('SELECT') || s.startsWith('query '),
      )
      .length;

  /// Writes: inserts, updates, deletes and executed DDL (batches count once).
  int get writes => statements.length - reads;

  int get total => statements.length;
}

/// Opens the real-schema test database (see [installTestDb]) and routes every
/// repository call through a counting wrapper.
///
/// Returns the unwrapped database, for seeding and assertions that must not be
/// counted, plus the [SqlLog]. [uninstallTestDb] cleans up.
Future<(Database, SqlLog)> installCountingTestDb({
  bool seedMealTypes = false,
}) async {
  final inner = await installTestDb(seedMealTypes: seedMealTypes);
  final log = SqlLog();
  DatabaseHelper.overrideDatabase = _CountingDatabase(inner, log);
  return (inner, log);
}

mixin _CountingExecutor implements DatabaseExecutor {
  DatabaseExecutor get inner;
  SqlLog get log;

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) {
    log.statements.add(sql);
    return inner.execute(sql, arguments);
  }

  @override
  Future<int> rawInsert(String sql, [List<Object?>? arguments]) {
    log.statements.add(sql);
    return inner.rawInsert(sql, arguments);
  }

  @override
  Future<int> insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    log.statements.add('insert $table');
    return inner.insert(
      table,
      values,
      nullColumnHack: nullColumnHack,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  Future<List<Map<String, Object?>>> query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) {
    log.statements.add('query $table');
    return inner.query(
      table,
      distinct: distinct,
      columns: columns,
      where: where,
      whereArgs: whereArgs,
      groupBy: groupBy,
      having: having,
      orderBy: orderBy,
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<List<Map<String, Object?>>> rawQuery(
    String sql, [
    List<Object?>? arguments,
  ]) {
    log.statements.add(sql.trimLeft());
    return inner.rawQuery(sql, arguments);
  }

  @override
  Future<int> rawUpdate(String sql, [List<Object?>? arguments]) {
    log.statements.add(sql);
    return inner.rawUpdate(sql, arguments);
  }

  @override
  Future<int> update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) {
    log.statements.add('update $table');
    return inner.update(
      table,
      values,
      where: where,
      whereArgs: whereArgs,
      conflictAlgorithm: conflictAlgorithm,
    );
  }

  @override
  Future<int> rawDelete(String sql, [List<Object?>? arguments]) {
    log.statements.add(sql);
    return inner.rawDelete(sql, arguments);
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) {
    log.statements.add('delete $table');
    return inner.delete(table, where: where, whereArgs: whereArgs);
  }

  @override
  Batch batch() => _CountingBatch(inner.batch(), log);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not counted');
}

class _CountingTransaction with _CountingExecutor implements Transaction {
  _CountingTransaction(this.inner, this.log);

  @override
  final Transaction inner;
  @override
  final SqlLog log;
}

class _CountingDatabase with _CountingExecutor implements Database {
  _CountingDatabase(this.inner, this.log);

  @override
  final Database inner;
  @override
  final SqlLog log;

  @override
  Database get database => this;

  @override
  String get path => inner.path;

  @override
  bool get isOpen => inner.isOpen;

  @override
  Future<void> close() => inner.close();

  @override
  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action, {
    bool? exclusive,
  }) => inner.transaction(
    (txn) => action(_CountingTransaction(txn, log)),
    exclusive: exclusive,
  );
}

class _CountingBatch implements Batch {
  _CountingBatch(this.inner, this.log);

  final Batch inner;
  final SqlLog log;

  @override
  int get length => inner.length;

  @override
  Future<List<Object?>> commit({
    bool? exclusive,
    bool? noResult,
    bool? continueOnError,
  }) {
    log.statements.add('batch($length)');
    return inner.commit(
      exclusive: exclusive,
      noResult: noResult,
      continueOnError: continueOnError,
    );
  }

  @override
  Future<List<Object?>> apply({bool? noResult, bool? continueOnError}) {
    log.statements.add('batch($length)');
    return inner.apply(noResult: noResult, continueOnError: continueOnError);
  }

  @override
  void rawInsert(String sql, [List<Object?>? arguments]) =>
      inner.rawInsert(sql, arguments);

  @override
  void insert(
    String table,
    Map<String, Object?> values, {
    String? nullColumnHack,
    ConflictAlgorithm? conflictAlgorithm,
  }) => inner.insert(
    table,
    values,
    nullColumnHack: nullColumnHack,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  void rawUpdate(String sql, [List<Object?>? arguments]) =>
      inner.rawUpdate(sql, arguments);

  @override
  void update(
    String table,
    Map<String, Object?> values, {
    String? where,
    List<Object?>? whereArgs,
    ConflictAlgorithm? conflictAlgorithm,
  }) => inner.update(
    table,
    values,
    where: where,
    whereArgs: whereArgs,
    conflictAlgorithm: conflictAlgorithm,
  );

  @override
  void rawDelete(String sql, [List<Object?>? arguments]) =>
      inner.rawDelete(sql, arguments);

  @override
  void delete(String table, {String? where, List<Object?>? whereArgs}) =>
      inner.delete(table, where: where, whereArgs: whereArgs);

  @override
  void execute(String sql, [List<Object?>? arguments]) =>
      inner.execute(sql, arguments);

  @override
  void query(
    String table, {
    bool? distinct,
    List<String>? columns,
    String? where,
    List<Object?>? whereArgs,
    String? groupBy,
    String? having,
    String? orderBy,
    int? limit,
    int? offset,
  }) => inner.query(
    table,
    distinct: distinct,
    columns: columns,
    where: where,
    whereArgs: whereArgs,
    groupBy: groupBy,
    having: having,
    orderBy: orderBy,
    limit: limit,
    offset: offset,
  );

  @override
  void rawQuery(String sql, [List<Object?>? arguments]) =>
      inner.rawQuery(sql, arguments);
}
