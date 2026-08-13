import 'package:sqflite/sqflite.dart';

/// Incremental database upgrades extracted from the legacy schema versions.
abstract final class DatabaseLegacyMigrations {
  static Future<void> upgrade(Database db, int oldVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
          'ALTER TABLE exercise_entries ADD COLUMN rest_time_seconds INTEGER',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE routine_exercises ADD COLUMN rest_time_seconds INTEGER',
        );
      } catch (_) {}
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
          'ALTER TABLE exercise_categories ADD COLUMN energy_system TEXT NOT NULL DEFAULT \'anaerobic\'',
        );
      } catch (_) {}
    }
    if (oldVersion < 4) {
      final defaults = <String, String>{
        'notification_rest_timer_enabled': 'true',
        'notification_rest_timer_sound': 'true',
        'notification_rest_timer_vibration': 'true',
        'notification_workout_timer_enabled': 'true',
        'notification_workout_timer_sound': 'false',
        'notification_workout_timer_vibration': 'false',
      };
      for (final entry in defaults.entries) {
        try {
          await db.insert('app_settings', {
            'key': entry.key,
            'value': entry.value,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        } catch (_) {}
      }
    }
    if (oldVersion < 5) {
      try {
        await db.execute(
          'ALTER TABLE body_measurements ADD COLUMN time_of_day TEXT',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE body_measurements ADD COLUMN is_fasted INTEGER DEFAULT 0',
        );
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE body_measurements ADD COLUMN photos_paths TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE exercises ADD COLUMN locale_key TEXT');
      } catch (_) {}
      try {
        await db.execute(
          'ALTER TABLE exercise_categories ADD COLUMN locale_key TEXT',
        );
      } catch (_) {}
      final seedIds = [
        'bench_press',
        'incl_bench',
        'decl_bench',
        'db_bench',
        'db_incl',
        'cable_fly',
        'pec_deck',
        'pushup',
        'chest_dip',
        'sm_bench',
        'pullup',
        'chinup',
        'lat_pulldown',
        'bent_row',
        'db_row',
        'seated_row',
        'tbar_row',
        'face_pull',
        'deadlift',
        'rdl',
        'hyperextension',
        'ohp',
        'db_ohp',
        'lat_raise',
        'front_raise',
        'rear_delt_fly',
        'upright_row',
        'arnold_press',
        'shrug',
        'bb_curl',
        'db_curl',
        'hammer_curl',
        'preacher_curl',
        'cable_curl',
        'concentration_curl',
        'triceps_pushdown',
        'skull_crusher',
        'close_grip',
        'triceps_extension',
        'bench_dip',
        'kickback',
        'squat',
        'front_squat',
        'leg_press',
        'romanian_dl',
        'leg_curl',
        'leg_ext',
        'bulgarian_split',
        'lunge',
        'calf_raise',
        'goblet_squat',
        'hack_squat',
        'hip_thrust',
        'crunch',
        'leg_raise',
        'plank',
        'russian_twist',
        'cable_crunch',
        'ab_roller',
        'hanging_raise',
        'treadmill',
        'cycling',
        'jump_rope',
        'rowing',
        'swimming',
        'walking',
        'running',
      ];
      for (final id in seedIds) {
        try {
          await db.rawUpdate(
            'UPDATE exercises SET locale_key = ? WHERE id = ?',
            [id, id],
          );
        } catch (_) {}
      }
      final catIds = [
        'chest',
        'back',
        'shoulders',
        'biceps',
        'triceps',
        'legs',
        'core',
        'cardio',
        'fullbody',
      ];
      for (final id in catIds) {
        try {
          await db.rawUpdate(
            'UPDATE exercise_categories SET locale_key = ? WHERE id = ?',
            [id, id],
          );
        } catch (_) {}
      }
    }
    if (oldVersion < 7) {
      try {
        await db.insert('exercises', {
          'id': 'running',
          'name': 'Corrida',
          'locale_key': 'running',
          'category_id': 'cardio',
          'type': 'distanceTime',
          'notes': 'Corrida ao ar livre ou esteira',
          'equipment': 'Bodyweight',
          'is_favorite': 0,
          'default_rest_time': 0,
          'weight_increment': 0,
          'created_at': DateTime.now().toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } catch (_) {}
    }
    if (oldVersion < 8) {
      try {
        await db.execute('ALTER TABLE body_measurements ADD COLUMN side TEXT');
      } catch (_) {}
    }
    if (oldVersion < 9) {
      try {
        await db.execute(
          'ALTER TABLE workouts ADD COLUMN pause_start_time TEXT',
        );
      } catch (_) {}
    }
    if (oldVersion < 10) {
      try {
        await db.execute('ALTER TABLE routine_days ADD COLUMN notes TEXT');
      } catch (_) {}
    }
  }
}
