import 'package:sqflite/sqflite.dart';

import 'seed_data.dart';

/// Seeds stable catalogs and default application settings.
abstract final class DatabaseSeed {
  /// Seeds the four legacy meal types (breakfast → snacks) so upgraded
  /// and fresh databases always have a working catalog. `name` stays
  /// NULL: the UI resolves those keys to localized labels, and the user
  /// can rename them later. Idempotent via `INSERT OR IGNORE` on `key`.
  static Future<void> seedMealTypes(Database db) async {
    final now = DateTime.now().toIso8601String();
    final rows = <Map<String, dynamic>>[
      {'key': 'breakfast', 'order_index': 0},
      {'key': 'lunch', 'order_index': 1},
      {'key': 'dinner', 'order_index': 2},
      {'key': 'snacks', 'order_index': 3},
    ];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      try {
        await db.insert('meal_types', {
          'id': row['key'],
          'key': row['key'],
          'name': null,
          'order_index': row['order_index'],
          'created_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      } catch (_) {}
    }
  }

  static Future<void> seedInitialData(Database db) async {
    final batch = db.batch();

    for (final cat in SeedData.categories) {
      batch.insert('exercise_categories', {
        'id': cat['id'],
        'name': cat['name'],
        'locale_key': cat['locale_key'],
        'color': cat['color'],
        'order_index': cat['order_index'],
        'energy_system': cat['energy_system'],
      });
    }

    for (final ex in SeedData.exercises) {
      batch.insert('exercises', {
        'id': ex['id'],
        'name': ex['name'],
        'locale_key': ex['locale_key'],
        'category_id': ex['category_id'],
        'type': ex['type'],
        'notes': ex['notes'],
        'equipment': ex['equipment'],
        'is_favorite': 0,
        'default_rest_time': ex['default_rest_time'],
        'weight_increment': ex['weight_increment'],
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    batch.insert('app_settings', {'key': 'unit_system', 'value': 'kg'});
    batch.insert('app_settings', {'key': 'theme_mode', 'value': 'system'});
    batch.insert('app_settings', {'key': 'keep_screen_on', 'value': 'false'});
    batch.insert('app_settings', {'key': 'default_rest_time', 'value': '90'});
    batch.insert('app_settings', {
      'key': 'auto_start_rest_timer',
      'value': 'true',
    });
    batch.insert('app_settings', {
      'key': 'auto_start_workout_timer',
      'value': 'false',
    });
    batch.insert('app_settings', {'key': 'sleep_goal_minutes', 'value': '480'});
    batch.insert('app_settings', {
      'key': 'sleep_mission_enabled',
      'value': 'false',
    });
    batch.insert('app_settings', {
      'key': 'sleep_mission_type',
      'value': 'barcode',
    });
    batch.insert('app_settings', {
      'key': 'sleep_mission_barcode_hash',
      'value': '',
    });
    batch.insert('app_settings', {
      'key': 'sleep_mission_barcode_salt',
      'value': '',
    });
    batch.insert('app_settings', {
      'key': 'sleep_mission_barcode_format',
      'value': '',
    });
    batch.insert('app_settings', {
      'key': 'sleep_mission_registered_at',
      'value': '',
    });
    batch.insert('app_settings', {
      'key': 'sleep_monitor_default_mode',
      'value': 'alarm_without_mission',
    });
    batch.insert('app_settings', {
      'key': 'alarm_global_max_snoozes',
      'value': '3',
    });
    batch.insert('app_settings', {
      'key': 'alarm_global_snooze_enabled',
      'value': 'true',
    });
    batch.insert('app_settings', {
      'key': 'notification_rest_timer_enabled',
      'value': 'true',
    });
    batch.insert('app_settings', {
      'key': 'notification_rest_timer_sound',
      'value': 'true',
    });
    batch.insert('app_settings', {
      'key': 'notification_rest_timer_vibration',
      'value': 'true',
    });
    batch.insert('app_settings', {
      'key': 'notification_workout_timer_enabled',
      'value': 'true',
    });
    batch.insert('app_settings', {
      'key': 'notification_workout_timer_sound',
      'value': 'false',
    });
    batch.insert('app_settings', {
      'key': 'notification_workout_timer_vibration',
      'value': 'false',
    });
    await batch.commit(noResult: true);
  }
}
