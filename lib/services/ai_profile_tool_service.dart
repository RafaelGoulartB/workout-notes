// Read-only queries built for the AI Coach may run SQL directly (a documented
// exception to the repository-only rule); writes never happen in this file.
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/services/ai_tool_math.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'package:workout_notes/services/sleep_goal_service.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Read-only profile and body-measurement queries for the AI Coach.
class AiProfileToolService {
  final DatabaseHelper db;
  final NutritionRepository nutritionRepository;
  final PeriodizationRepository periodizationRepository;
  final DateTime Function() _now;

  AiProfileToolService({
    DatabaseHelper? db,
    NutritionRepository? nutritionRepository,
    PeriodizationRepository? periodizationRepository,
    DateTime Function()? now,
  }) : db = db ?? DatabaseHelper.instance,
       nutritionRepository =
           nutritionRepository ??
           (db ?? DatabaseHelper.instance).nutritionRepo,
       periodizationRepository =
           periodizationRepository ??
           (db ?? DatabaseHelper.instance).periodizationRepo,
       _now = now ?? DateTime.now;

  /// Everything the coach needs to personalise advice: body basics, units and
  /// the daily nutrition and sleep goals.
  Future<Map<String, dynamic>> profile() async {
    final database = await db.database;
    final settingRows = await database.query('app_settings');
    final settings = {
      for (final row in settingRows)
        row['key'] as String: row['value'] as String?,
    };
    final weight = await database.query(
      'body_measurements',
      where: 'type = ?',
      whereArgs: ['weight'],
      orderBy: 'date DESC, created_at DESC',
      limit: 1,
    );
    final today = _now();
    final effective = await EffectiveNutritionGoalService.resolve(
      nutritionRepository: nutritionRepository,
      periodizationRepository: periodizationRepository,
      date: today,
    );
    final settingsGoal = await nutritionRepository.getActiveGoal();
    final goal = effective.goal;
    final sleepGoalRaw = int.tryParse(settings['sleep_goal_minutes'] ?? '');
    final mealTypes = await database.query(
      'meal_types',
      orderBy: 'order_index ASC, created_at ASC',
    );
    final counts = await database.rawQuery('''
      SELECT
        (SELECT COUNT(DISTINCT date) FROM meal_logs) AS diary_days,
        (SELECT COUNT(*) FROM foods) AS foods,
        (SELECT COUNT(*) FROM saved_meals) AS saved_meals
    ''');
    double? ratio(String a, String b) =>
        AiToolMath.asDouble(double.tryParse(settings[a] ?? '')) ??
        AiToolMath.asDouble(double.tryParse(settings[b] ?? ''));
    return {
      'sex': settings['nutrition_profile_sex'],
      'age': int.tryParse(settings['nutrition_profile_age'] ?? ''),
      'height_cm': double.tryParse(
        settings['nutrition_profile_height_cm'] ?? '',
      ),
      'profile_weight_kg': double.tryParse(
        settings['nutrition_profile_weight_kg'] ?? '',
      ),
      'activity_level': settings['nutrition_profile_activity'],
      'latest_weight': weight.isEmpty
          ? null
          : {
              'value': weight.first['value'],
              'unit': weight.first['unit'],
              'date': weight.first['date'],
            },
      'units': {
        'weight': settings['unit_system'] ?? 'kg',
        'distance': settings['distance_unit'] ?? 'km',
      },
      'nutrition_goal': goal == null
          ? null
          : {
              'calories': goal.calories,
              'protein_g': goal.proteinG,
              'carbs_g': goal.carbsG,
              'fat_g': goal.fatG,
              'source': effective.fromPlan ? 'plan' : 'settings',
              'phase': effective.phase?.name,
              'day_type': effective.trainingDay == null
                  ? null
                  : (effective.trainingDay! ? 'training' : 'rest'),
              'settings_calories': effective.fromPlan
                  ? settingsGoal?.calories
                  : null,
              'tdee': settingsGoal?.tdee,
              'adjustment': settingsGoal?.adjustmentKind,
              'adjustment_pct': settingsGoal?.adjustmentPercent,
            },
      'macro_g_per_kg': {
        'protein': ratio(
          'nutrition_profile_macro_protein_g_kg',
          'nutrition_profile_macro_maintenance_protein_g_kg',
        ),
        'fat': ratio(
          'nutrition_profile_macro_fat_g_kg',
          'nutrition_profile_macro_maintenance_fat_g_kg',
        ),
      },
      'sleep_goal_min': SleepGoalService.normalize(
        sleepGoalRaw ?? SleepGoalService.defaultGoalMinutes,
      ),
      'sleep_goal_source': sleepGoalRaw == null ? 'default' : 'user',
      'meal_types': [
        for (final row in mealTypes) (row['name'] as String?) ?? row['key'],
      ],
      'counts': {
        'diary_days': counts.first['diary_days'],
        'foods': counts.first['foods'],
        'saved_meals': counts.first['saved_meals'],
      },
    };
  }

  /// Body measurements newest first, or the latest value of each type (and
  /// side) with [latestPerType]. With a single [type] the result adds the
  /// first-to-last change inside the range.
  Future<Map<String, dynamic>> measurements({
    String? type,
    String? startDate,
    String? endDate,
    bool latestPerType = false,
    int limit = 20,
  }) async {
    final database = await db.database;
    final where = <String>[];
    final values = <Object?>[];
    if (type != null) {
      where.add('type = ?');
      values.add(type);
    }
    if (startDate != null) {
      where.add('date >= ?');
      values.add(startDate);
    }
    if (endDate != null) {
      where.add('date <= ?');
      values.add(endDate);
    }
    final whereSql = where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}';
    String filters(String alias) =>
        where.map((clause) => '$alias.$clause').join(' AND ');
    final List<Map<String, Object?>> rows;
    var total = 0;
    if (latestPerType) {
      // No window functions: Android's bundled SQLite may predate them.
      rows = await database.rawQuery(
        '''
        SELECT bm.* FROM body_measurements bm
        WHERE ${where.isEmpty ? '1 = 1' : filters('bm')}
          AND NOT EXISTS (
            SELECT 1 FROM body_measurements n
            WHERE ${where.isEmpty ? '' : '${filters('n')} AND '}
              n.type = bm.type
              AND COALESCE(n.side, '') = COALESCE(bm.side, '')
              AND (n.date > bm.date
                OR (n.date = bm.date AND n.created_at > bm.created_at))
          )
        ORDER BY bm.type ASC, bm.side ASC
        LIMIT ?
        ''',
        [...values, ...values, limit],
      );
      total = rows.length;
    } else {
      total =
          (await database.rawQuery(
                'SELECT COUNT(*) AS total FROM body_measurements $whereSql',
                values,
              )).first['total']
              as int? ??
          0;
      rows = await database.rawQuery(
        '''
        SELECT * FROM body_measurements $whereSql
        ORDER BY date DESC, created_at DESC LIMIT ?
        ''',
        [...values, limit],
      );
    }
    Map<String, dynamic>? change;
    if (type != null && !latestPerType && total >= 2) {
      final first = (await database.rawQuery(
        '''
        SELECT value, date FROM body_measurements $whereSql
        ORDER BY date ASC, created_at ASC LIMIT 1
        ''',
        values,
      )).first;
      final last = rows.first;
      final from = (first['value'] as num).toDouble();
      final to = (last['value'] as num).toDouble();
      change = {
        'from': from,
        'from_date': first['date'],
        'to': to,
        'to_date': last['date'],
        'change': to - from,
        'change_pct': AiToolMath.percentChange(from, to),
      };
    }
    return {
      'applied': {
        'type': type,
        'start_date': startDate,
        'end_date': endDate,
        'latest_per_type': latestPerType ? true : null,
        'limit': limit,
      },
      'total': total,
      'has_more': !latestPerType && total > rows.length,
      'change': change,
      'measurements': [
        for (final row in rows)
          {
            'date': row['date'],
            'type': row['type'],
            'value': row['value'],
            'secondary_value': row['secondary_value'],
            'unit': row['unit'],
            'side': row['side'],
            'is_fasted': (row['is_fasted'] as num?)?.toInt() == 1 ? true : null,
            'time_of_day': row['time_of_day'],
            'comment': _clip(row['comment'] as String?, 100),
          },
      ],
    };
  }

  /// The injected clock, so spec handlers resolve dates like the queries.
  DateTime now() => dayOf(_now());

  static String? _clip(String? text, int max) {
    final trimmed = text?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.length <= max ? trimmed : '${trimmed.substring(0, max)}...';
  }
}
