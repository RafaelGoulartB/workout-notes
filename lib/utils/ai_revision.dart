import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Short, stable fingerprint of a JSON-like value (maps are hashed with sorted
/// keys). Read tools return it as `revision`; a proposal made against that
/// revision is refused when the data changed in between, so an edit the user
/// made after the model looked never gets silently reverted.
String aiRevision(Object? value) {
  final canonical = jsonEncode(_canonical(value));
  // FNV-1a 64-bit over the UTF-8 bytes.
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final byte in utf8.encode(canonical)) {
    hash = ((hash ^ BigInt.from(byte)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

Object? _canonical(Object? value) {
  if (value is Map) {
    final keys = value.keys.map((k) => '$k').toList()..sort();
    return {for (final key in keys) key: _canonical(value[key])};
  }
  if (value is List) return value.map(_canonical).toList();
  return value;
}

/// Revision of a routine: every stored field of the routine, its days,
/// exercises and sets, in display order. Null when the routine does not
/// exist. Shared by `get_routine_detail` and the routine proposal handler.
Future<String?> routineRevision(DatabaseExecutor db, String routineId) async {
  final routine = await db.query(
    'routines',
    columns: ['id', 'name', 'notes'],
    where: 'id = ?',
    whereArgs: [routineId],
    limit: 1,
  );
  if (routine.isEmpty) return null;
  final rows = await db.rawQuery(
    '''
    SELECT d.id AS day_id, d.name AS day_name, d.notes AS day_notes,
      d.order_index AS day_order,
      re.id AS re_id, re.exercise_id, re.order_index AS re_order,
      re.superset_group_id, re.rest_time_seconds,
      ps.id AS set_id, ps.weight, ps.reps, ps.distance, ps.time_seconds,
      ps.is_warmup, ps.order_index AS set_order
    FROM routine_days d
    LEFT JOIN routine_exercises re ON re.routine_day_id = d.id
    LEFT JOIN predefined_sets ps ON ps.routine_exercise_id = re.id
    WHERE d.routine_id = ?
    ORDER BY d.order_index, d.id, re.order_index, re.id, ps.order_index, ps.id
    ''',
    [routineId],
  );
  return aiRevision({'routine': routine.first, 'rows': rows});
}
