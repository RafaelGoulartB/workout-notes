// Read-only queries built for the AI Coach may run SQL directly (a documented
// exception to the repository-only rule); writes never happen in this file.
import 'dart:convert';
import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/services/ai_tool_math.dart';
import 'package:workout_notes/services/ai_tool_spec.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';

/// Read-only, AI-facing access to recorded cardio activities and running plans.
///
/// GPS runs, treadmill runs and stationary-bike sessions live in
/// `run_activities`, separately from strength `workouts`. Results are plain
/// `snake_case` maps (the registry shapes them); unknown ids throw
/// [AiToolNotFoundException] and bad arguments [AiToolArgException].
///
/// Timestamps in `run_activities.started_at` are local wall-clock ISO strings
/// without an offset, so day windows are plain string bounds
/// (`>= 'yyyy-MM-ddT00:00:00'` and `< next day`).
class AiRunToolService {
  final DatabaseHelper db;
  final RunRepository activities;
  final RunPlanRepository plans;
  final DateTime Function() _now;

  AiRunToolService({
    DatabaseHelper? db,
    RunRepository? activities,
    RunPlanRepository? plans,
    DateTime Function()? now,
  }) : db = db ?? DatabaseHelper.instance,
       activities = activities ?? DatabaseHelper.instance.runRepo,
       plans = plans ?? DatabaseHelper.instance.runPlanRepo,
       _now = now ?? DateTime.now;

  DateTime get _today => dayOf(_now());

  static const _runTypes = "('running', 'treadmill')";
  static const _maxTrendRows = 26;
  static const _maxPaceTrendPoints = 16;
  static const _maxPlanWeeks = 6;
  static const _inChunk = 400;

  // ---------------------------------------------------------------------------
  // list_run_activities
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> listActivities({
    String? startDate,
    String? endDate,
    String activityType = 'running',
    int limit = 15,
    int page = 1,
  }) async {
    final start = _parseDay('start_date', startDate);
    final end = _parseDay('end_date', endDate);
    _checkRange(start, end);
    final type = switch (activityType) {
      'running' || 'stationary_bike' || 'all' => activityType,
      _ => throw AiToolArgException.invalid(
        'activity_type',
        'running, stationary_bike or all',
        activityType,
      ),
    };
    final where = <String>["status = 'completed'"];
    final args = <Object?>[];
    if (type == 'running') {
      where.add('activity_type IN $_runTypes');
    } else if (type == 'stationary_bike') {
      where.add('activity_type = ?');
      args.add('stationary_bike');
    }
    if (start != null) {
      where.add('started_at >= ?');
      args.add(_dayStart(start));
    }
    if (end != null) {
      where.add('started_at < ?');
      args.add(_dayStart(addDays(end, 1)));
    }
    final whereSql = where.join(' AND ');
    final database = await db.database;
    final total =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM run_activities WHERE $whereSql',
            args,
          ),
        ) ??
        0;
    final offset = (page - 1) * limit;
    final rows = await database.query(
      'run_activities',
      columns: const [
        'id',
        'activity_type',
        'started_at',
        'distance_meters',
        'moving_time_seconds',
        'avg_pace_sec_per_km',
        'calories',
        'rpe',
        'feeling_rating',
        'title',
        'best_split_pace_sec_per_km',
      ],
      where: whereSql,
      whereArgs: args,
      orderBy: 'started_at DESC, id DESC',
      limit: limit,
      offset: offset,
    );
    final hasMore = offset + rows.length < total;
    return {
      'applied': {
        'activity_type': type,
        'start_date': ?(start == null ? null : dateKey(start)),
        'end_date': ?(end == null ? null : dateKey(end)),
      },
      'total': total,
      'page': page,
      'limit': limit,
      'has_more': hasMore,
      if (hasMore) 'next_page': page + 1,
      'activities': [for (final row in rows) _listRow(row)],
    };
  }

  static Map<String, dynamic> _listRow(Map<String, Object?> row) {
    final type = row['activity_type'] as String? ?? 'running';
    final isRunning = type == 'running' || type == 'treadmill';
    final distance = _positive(row['distance_meters']);
    final moving = _positive(row['moving_time_seconds']);
    return {
      'id': row['id'],
      'started_at': row['started_at'],
      'activity_type': type,
      'distance_m': distance,
      'moving_s': moving,
      if (isRunning)
        'pace_s_km': _pace(row['avg_pace_sec_per_km'], distance, moving)
      else
        'speed_kmh': _speed(distance, moving),
      'calories': row['calories'],
      'rpe': row['rpe'],
      'feeling': row['feeling_rating'],
      'title': _text(row['title'] as String?, 60),
      'best_split_pace_s_km': _positive(row['best_split_pace_sec_per_km']),
    };
  }

  // ---------------------------------------------------------------------------
  // get_run_activity_detail
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> activityDetail(String activityId) async {
    final database = await db.database;
    final rows = await database.query(
      'run_activities',
      where: 'id = ?',
      whereArgs: [activityId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw const AiToolNotFoundException(
        'run activity not found',
        hint: 'call list_run_activities to get valid ids',
      );
    }
    final row = rows.first;
    final activity = RunActivity.fromMap(row);
    final isRunning = activity.isRunning;

    final stepResults = await plans.getActivitySteps(activityId);
    final List<RunSplit> splits =
        activity.isRun && activity.distanceMeters >= 1000
        ? await activities.getSplits(activityId)
        : const <RunSplit>[];
    final lapRows = await database.query(
      'run_laps',
      where: 'activity_id = ?',
      whereArgs: [activityId],
      orderBy: 'lap_index ASC',
      limit: 50,
    );
    final scheduledRows = await database.query(
      'scheduled_runs',
      where: 'run_activity_id = ?',
      whereArgs: [activityId],
      orderBy: 'updated_at DESC',
      limit: 1,
    );
    final scheduled = scheduledRows.isEmpty ? null : scheduledRows.first;
    final workoutId =
        scheduled?['run_plan_workout_id'] as String? ?? activity.planWorkoutId;
    final session = workoutId == null
        ? null
        : await plans.getWorkout(workoutId);
    final planId = scheduled?['run_plan_id'] as String? ?? session?.runPlanId;
    final planRows = planId == null
        ? const <Map<String, Object?>>[]
        : await database.query(
            'run_plans',
            columns: const ['id', 'name', 'goal_kind'],
            where: 'id = ?',
            whereArgs: [planId],
            limit: 1,
          );
    final gear = await _gearFor(database, activity.gearId);

    final distance = _positive(activity.distanceMeters);
    final moving = _positive(activity.movingTimeSeconds);
    final labelOffset = splits.any((split) => split.km == 0) ? 1 : 0;
    final lapOffset = lapRows.any((lap) => (lap['lap_index'] as num) == 0)
        ? 1
        : 0;
    return {
      'id': activity.id,
      'activity_type': activity.activityType.databaseValue,
      if (!activity.isCompleted) 'status': activity.status,
      'started_at': row['started_at'],
      'ended_at': row['ended_at'],
      'title': _text(activity.title, 80),
      'notes': _text(activity.notes, 300),
      'distance_m': distance,
      'moving_s': moving,
      'duration_s': _positive(activity.durationSeconds),
      if (isRunning)
        'pace_s_km': _pace(activity.avgPaceSecPerKm, distance, moving)
      else
        'speed_kmh': _speed(distance, moving),
      'best_split_pace_s_km': _positive(activity.bestSplitPaceSecPerKm),
      'calories': activity.calories,
      'rpe': activity.rpe,
      'feeling': activity.feelingRating,
      'elevation_gain_m': activity.elevationGainMeters,
      'elevation_loss_m': activity.elevationLossMeters,
      'min_altitude_m': activity.minimumAltitudeMeters,
      'max_altitude_m': activity.maximumAltitudeMeters,
      if (activity.isRun)
        'route': {
          'quality': activity.routeQuality,
          'gps_accuracy_m': activity.gpsAccuracyMeanMeters,
          'raw_points': row['raw_point_count'],
          'stored_points': row['stored_point_count'],
        },
      if (activity.isRun)
        'best_efforts_s': {
          '1k': activity.bestEffort1kSec,
          '3k': activity.bestEffort3kSec,
          '5k': activity.bestEffort5kSec,
          '10k': activity.bestEffort10kSec,
          'half': activity.bestEffortHalfSec,
          'marathon': activity.bestEffortMarathonSec,
        },
      'gear': gear,
      if (planRows.isNotEmpty)
        'plan': {
          'plan_id': planRows.first['id'],
          'name': planRows.first['name'],
          'goal': planRows.first['goal_kind'],
        },
      if (scheduled != null)
        'scheduled_run': {
          'id': scheduled['id'],
          'date': scheduled['date'],
          'status': scheduled['status'],
        },
      if (session != null)
        'planned_session': {
          'id': session.id,
          'name': session.name,
          'kind': session.kind.value,
          'week': session.weekIndex + 1,
          'distance_m': _positive(session.plannedDistanceMeters),
          'duration_s': _positive(session.plannedDurationSeconds),
          'target_pace_s_km': _positive(session.targetPaceSecPerKm),
          'effort_zone': session.effortZone,
          'steps': _stepsText(session),
        },
      if (stepResults.isNotEmpty)
        'step_results': [
          for (final step in stepResults.take(40))
            {
              'step': step.orderIndex + 1,
              'role': step.role,
              'rep': step.repIndex,
              'planned': _plannedText(step.plannedMetric, step.plannedValue),
              'planned_pace_s_km': _positive(step.plannedPaceSecPerKm),
              'actual_distance_m': _positive(step.actualDistanceMeters),
              'actual_duration_s': _positive(step.actualDurationSeconds),
              'actual_pace_s_km': _positive(step.actualPaceSecPerKm),
              'pace_delta_s_km': step.paceDeltaSecPerKm,
            },
        ],
      if (splits.isNotEmpty)
        'splits': [
          for (final split in splits.take(60))
            {
              'km': split.km + labelOffset,
              'duration_s': split.durationSeconds,
              'pace_s_km': split.paceSecPerKm,
              if (split.isPartial) 'partial': true,
              if (split.isPartial) 'distance_m': split.distanceMeters,
            },
        ],
      if (lapRows.isNotEmpty)
        'laps': [
          for (final lap in lapRows)
            {
              'lap': (lap['lap_index'] as num).toInt() + lapOffset,
              'distance_m': lap['distance_meters'],
              'duration_s': lap['duration_seconds'],
              'pace_s_km': lap['pace_sec_per_km'],
            },
        ],
    };
  }

  Future<Map<String, dynamic>?> _gearFor(
    Database database,
    String? gearId,
  ) async {
    if (gearId == null) return null;
    final rows = await database.rawQuery(
      '''
      SELECT g.name, g.initial_distance_meters AS initial,
        g.retire_distance_meters AS retire, g.retired_at AS retired_at,
        (SELECT COALESCE(SUM(a.distance_meters), 0) FROM run_activities a
          WHERE a.gear_id = g.id AND a.status = 'completed'
            AND a.activity_type IN $_runTypes) AS logged
      FROM run_gear g WHERE g.id = ?
      ''',
      [gearId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final total =
        ((row['initial'] as num?)?.toDouble() ?? 0) +
        ((row['logged'] as num?)?.toDouble() ?? 0);
    final retire = _positive(row['retire']);
    return {
      'name': row['name'],
      'total_km': total / 1000,
      'retire_at_km': retire == null ? null : retire / 1000,
      if (row['retired_at'] != null) 'retired': true,
    };
  }

  // ---------------------------------------------------------------------------
  // get_run_progress
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> progress({String period = '12_weeks'}) async {
    final statsPeriod = switch (period) {
      '4_weeks' => RunStatsPeriod.weeks4,
      '12_weeks' => RunStatsPeriod.weeks12,
      'year' => RunStatsPeriod.year,
      'all' => RunStatsPeriod.all,
      _ => throw AiToolArgException.invalid(
        'period',
        '4_weeks, 12_weeks, year or all',
        period,
      ),
    };
    final today = _today;
    final thisWeek = mondayOf(today);
    final weekCount = statsPeriod.weekCount;
    // Fixed periods need the period plus the previous one of the same length;
    // everything older is never read.
    final from = weekCount == null
        ? null
        : addDays(thisWeek, -7 * (weekCount - 1) - 7 * weekCount);
    final database = await db.database;
    final rows = await database.query(
      'run_activities',
      columns: const [
        'id',
        'activity_type',
        'started_at',
        'ended_at',
        'created_at',
        'updated_at',
        'status',
        'duration_seconds',
        'moving_time_seconds',
        'distance_meters',
        'avg_pace_sec_per_km',
        'calories',
        'elevation_gain_meters',
        'best_split_pace_sec_per_km',
      ],
      where:
          "status = 'completed' AND activity_type IN $_runTypes "
          'AND started_at < ?${from == null ? '' : ' AND started_at >= ?'}',
      whereArgs: [
        _dayStart(addDays(today, 1)),
        ?(from == null ? null : _dayStart(from)),
      ],
      orderBy: 'started_at ASC',
    );
    final stats = RunProgressAnalytics.fromActivities(
      rows.map(RunActivity.fromMap).toList(),
      period: statsPeriod,
      now: _now(),
    );

    final trend = stats.trendBuckets.reversed.toList();
    final shownTrend = trend.take(_maxTrendRows).toList();
    final previous = stats.previousPeriod;
    final distanceRatio = stats.distanceRatioVsPreviousPeriod;
    return {
      'applied': {'period': period},
      'period_start': stats.periodStart == null
          ? null
          : dateKey(stats.periodStart!),
      'run_count': stats.runCount,
      'distance_m': stats.totalDistanceMeters,
      'moving_s': stats.totalMovingTimeSeconds,
      'calories': stats.totalCalories > 0 ? stats.totalCalories : null,
      'elevation_gain_m': stats.totalElevationGainMeters > 0
          ? stats.totalElevationGainMeters
          : null,
      'avg_pace_s_km': stats.avgPaceSecPerKm,
      'best_pace_s_km': stats.bestPaceSecPerKm,
      'best_split_s_km': stats.bestKmSplitSecPerKm,
      'runs_per_week': stats.avgRunsPerWeek,
      'avg_weekly_distance_m': stats.avgWeeklyDistanceMeters,
      'week_streak': await _weekStreak(database, thisWeek),
      'this_week': {
        'runs': stats.thisWeekRunCount,
        'distance_m': stats.thisWeekDistanceMeters,
        'partial': true,
      },
      'last_week': {
        'runs': stats.lastWeekRunCount,
        'distance_m': stats.lastWeekDistanceMeters,
      },
      if (stats.hasPreviousPeriod)
        'vs_previous_period': {
          'run_count': previous.runCount,
          'distance_m': previous.distanceMeters,
          'avg_pace_s_km': previous.avgPaceSecPerKm,
          'distance_change_pct': distanceRatio == null
              ? null
              : distanceRatio * 100,
          'pace_change_s_km': stats.paceDeltaVsPreviousPeriod,
        },
      'pace_trend_s_km_per_30d': stats.paceTrendPerMonthSec,
      'longest_run': _runRef(stats.longestRun),
      'fastest_run': _runRef(stats.fastestRun),
      'best_split_run': stats.bestKmSplitRun == null
          ? null
          : {
              'activity_id': stats.bestKmSplitRun!.id,
              'date': dateKey(stats.bestKmSplitRun!.startedAt),
              'split_pace_s_km': stats.bestKmSplitSecPerKm,
            },
      'trend_unit': stats.trendIsMonthly ? 'month' : 'week',
      if (trend.length > shownTrend.length)
        'older_trend_rows_omitted': trend.length - shownTrend.length,
      'trend': [
        for (final bucket in shownTrend)
          {
            'start': dateKey(bucket.weekStart),
            'runs': bucket.runCount,
            'distance_m': bucket.distanceMeters,
            'moving_s': bucket.movingTimeSeconds,
            if (_isCurrentBucket(bucket, today)) 'partial': true,
          },
      ],
      'pace_trend': [
        for (final point in _downsample(
          stats.paceTrend,
          _maxPaceTrendPoints,
        ).reversed)
          {
            'date': dateKey(point.date),
            'pace_s_km': point.paceSecPerKm,
            'distance_m': point.distanceMeters,
          },
      ],
    };
  }

  /// Consecutive weeks (ending this week, or last week while this one has no
  /// run yet) with at least one completed run. Counted over all history, not
  /// just the loaded period, so a short period never caps it.
  Future<int> _weekStreak(Database database, DateTime thisWeek) async {
    final rows = await database.rawQuery(
      'SELECT DISTINCT substr(started_at, 1, 10) AS day FROM run_activities '
      "WHERE status = 'completed' AND activity_type IN $_runTypes",
    );
    final weeks = <String>{
      for (final row in rows)
        if (DateTime.tryParse((row['day'] as String?) ?? '') case final day?)
          dateKey(mondayOf(day)),
    };
    var cursor = weeks.contains(dateKey(thisWeek))
        ? thisWeek
        : addDays(thisWeek, -7);
    var streak = 0;
    while (weeks.contains(dateKey(cursor))) {
      streak++;
      cursor = addDays(cursor, -7);
    }
    return streak;
  }

  static bool _isCurrentBucket(RunWeekBucket bucket, DateTime today) {
    final start = bucket.weekStart;
    final end = addDays(start, bucket.spanDays);
    return !today.isBefore(start) && today.isBefore(end);
  }

  static List<T> _downsample<T>(List<T> values, int max) {
    if (values.length <= max) return values;
    return [
      for (var i = 0; i < max; i++)
        values[(i * (values.length - 1) / (max - 1)).round()],
    ];
  }

  static Map<String, dynamic>? _runRef(RunActivity? run) {
    if (run == null) return null;
    return {
      'activity_id': run.id,
      'date': dateKey(run.startedAt),
      'distance_m': run.distanceMeters,
      'moving_s': _positive(run.movingTimeSeconds),
      'pace_s_km': run.avgPaceSecPerKm,
    };
  }

  // ---------------------------------------------------------------------------
  // get_cardio_summary
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> cardioSummary({int days = 28}) async {
    final window = AiToolMath.window(
      today: _now(),
      days: days,
      defaultDays: 28,
      maxDays: 366,
    );
    final from = _dayStart(window.start);
    final before = _dayStart(addDays(window.end, 1));
    final database = await db.database;

    final byType = await database.rawQuery(
      '''
      SELECT activity_type, COUNT(*) AS sessions,
        SUM(CASE WHEN distance_meters > 0 THEN distance_meters END) AS distance,
        SUM(CASE WHEN moving_time_seconds > 0 THEN moving_time_seconds END)
          AS moving,
        SUM(CASE WHEN distance_meters > 0 THEN moving_time_seconds END)
          AS moving_with_distance,
        SUM(calories) AS calories, AVG(rpe) AS rpe
      FROM run_activities
      WHERE status = 'completed' AND started_at >= ? AND started_at < ?
      GROUP BY activity_type ORDER BY sessions DESC
      ''',
      [from, before],
    );
    final weeklyRows = await database.rawQuery(
      '''
      SELECT date(substr(started_at, 1, 10),
          '-' || ((CAST(strftime('%w', substr(started_at, 1, 10)) AS INTEGER)
            + 6) % 7) || ' days') AS week_start,
        activity_type, COUNT(*) AS sessions,
        SUM(CASE WHEN distance_meters > 0 THEN distance_meters END) AS distance,
        SUM(moving_time_seconds) AS moving
      FROM run_activities
      WHERE status = 'completed' AND started_at >= ? AND started_at < ?
      GROUP BY week_start, activity_type
      ''',
      [from, before],
    );
    final recent = await database.query(
      'run_activities',
      columns: const ['id'],
      where: "status = 'completed' AND started_at >= ? AND started_at < ?",
      whereArgs: [from, before],
      orderBy: 'started_at DESC, id DESC',
      limit: 10,
    );

    // Calendar weeks fully inside the window; a partial first or current week
    // would read as a drop in volume.
    final weeks = <String, Map<String, dynamic>>{};
    for (final row in weeklyRows) {
      final start = DateTime.tryParse(row['week_start'] as String? ?? '');
      if (start == null ||
          start.isBefore(window.start) ||
          addDays(start, 6).isAfter(window.end)) {
        continue;
      }
      final key = dateKey(start);
      final week = weeks.putIfAbsent(
        key,
        () => {
          'week_start': key,
          'run_sessions': 0,
          'run_distance_m': 0.0,
          'bike_sessions': 0,
          'bike_distance_m': 0.0,
          'moving_s': 0,
        },
      );
      final bike = row['activity_type'] == 'stationary_bike';
      final prefix = bike ? 'bike' : 'run';
      final sessions = (row['sessions'] as num).toInt();
      week['${prefix}_sessions'] =
          (week['${prefix}_sessions'] as int) + sessions;
      week['${prefix}_distance_m'] =
          (week['${prefix}_distance_m'] as double) +
          ((row['distance'] as num?)?.toDouble() ?? 0);
      week['moving_s'] =
          (week['moving_s'] as int) + ((row['moving'] as num?)?.toInt() ?? 0);
    }
    final weekly = weeks.values.toList()
      ..sort(
        (a, b) =>
            (b['week_start'] as String).compareTo(a['week_start'] as String),
      );
    for (final week in weekly) {
      for (final key in ['run_distance_m', 'bike_distance_m']) {
        if ((week[key] as double) <= 0) week[key] = null;
      }
      if ((week['run_sessions'] as int) == 0) week['run_sessions'] = null;
      if ((week['bike_sessions'] as int) == 0) week['bike_sessions'] = null;
    }

    var totalSessions = 0;
    final typeRows = <Map<String, dynamic>>[];
    for (final row in byType) {
      final type = row['activity_type'] as String? ?? 'running';
      final sessions = (row['sessions'] as num).toInt();
      totalSessions += sessions;
      final distance = _positive(row['distance']);
      final movingWith = _positive(row['moving_with_distance']);
      final isRunning = type == 'running' || type == 'treadmill';
      typeRows.add({
        'activity_type': type,
        'sessions': sessions,
        'distance_m': distance,
        'moving_s': _positive(row['moving']),
        if (isRunning)
          'avg_pace_s_km': distance == null || movingWith == null
              ? null
              : movingWith / (distance / 1000)
        else
          'avg_speed_kmh': _speed(distance, movingWith),
        'calories': row['calories'],
        'avg_rpe': row['rpe'],
      });
    }

    return {
      'applied': {...window.toApplied(), 'weekly': 'full_weeks_only'},
      'total_sessions': totalSessions,
      'by_type': typeRows,
      'recent_activity_ids': [for (final row in recent) row['id']],
      'weekly': weekly,
      'gym_cardio': await _gymCardio(database, window),
    };
  }

  /// Aerobic sets logged inside strength workouts (finished workouts only,
  /// no future dates). Their distance is stored in the user's distance unit,
  /// the same convention the goal progress uses (km).
  Future<Map<String, dynamic>?> _gymCardio(
    Database database,
    AiDateWindow window,
  ) async {
    const filter = '''
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN exercises e ON e.id = ee.exercise_id
      JOIN exercise_categories ec ON ec.id = e.category_id
      JOIN workouts w ON w.id = ee.workout_id
      WHERE ec.energy_system = 'aerobic' AND w.end_time IS NOT NULL
        AND w.date >= ? AND w.date <= ?
        AND s.is_complete = 1 AND s.is_warmup = 0
        AND (COALESCE(s.distance, 0) > 0 OR COALESCE(s.time_seconds, 0) > 0)
    ''';
    final args = [window.startKey, window.endKey];
    final modalities = await database.rawQuery('''
      SELECT ec.name AS modality, COUNT(DISTINCT w.id) AS workouts,
        COUNT(*) AS sets, SUM(COALESCE(s.distance, 0)) AS distance,
        SUM(COALESCE(s.time_seconds, 0)) AS time_s
      $filter
      GROUP BY ec.id ORDER BY workouts DESC, ec.name ASC
      ''', args);
    if (modalities.isEmpty) return null;
    final workouts = await database.rawQuery('''
      SELECT w.id AS id, w.date AS date
      $filter
      GROUP BY w.id ORDER BY w.date DESC, w.id DESC LIMIT 10
      ''', args);
    return {
      'by_modality': [
        for (final row in modalities)
          {
            'modality': row['modality'],
            'workouts': row['workouts'],
            'sets': row['sets'],
            'distance_km': _positive(row['distance']),
            'duration_s': _positive(row['time_s']),
          },
      ],
      'workout_ids': [for (final row in workouts) row['id']],
    };
  }

  // ---------------------------------------------------------------------------
  // get_run_achievements
  // ---------------------------------------------------------------------------

  static const _kindNames = {
    RunAchievementKind.longestDistance: ('longest_distance', 'm'),
    RunAchievementKind.longestDuration: ('longest_duration', 's'),
    RunAchievementKind.bestAvgPace: ('best_avg_pace', 's_km'),
    RunAchievementKind.bestKmSplit: ('best_km_split', 's_km'),
    RunAchievementKind.bestEffort1k: ('best_effort_1k', 's'),
    RunAchievementKind.bestEffort3k: ('best_effort_3k', 's'),
    RunAchievementKind.bestEffort5k: ('best_effort_5k', 's'),
    RunAchievementKind.bestEffort10k: ('best_effort_10k', 's'),
    RunAchievementKind.bestEffortHalf: ('best_effort_half', 's'),
    RunAchievementKind.bestEffortMarathon: ('best_effort_marathon', 's'),
  };

  Future<Map<String, dynamic>> achievements() async {
    final board = RunAchievementEngine.build(
      await activities.listActivitiesForRanking(),
    );
    final units = <String, String>{};
    final rows = <Map<String, dynamic>>[];
    for (final category in board.nonEmptyCategories) {
      final (name, unit) = _kindNames[category.kind]!;
      units[name] = unit;
      for (final placement in category.placements) {
        rows.add({
          'kind': name,
          'place': placement.tier.place,
          'activity_id': placement.activity.id,
          'date': dateKey(placement.activity.startedAt),
          'value': placement.value.round(),
        });
      }
    }
    return {'units': units, 'podium': rows};
  }

  // ---------------------------------------------------------------------------
  // get_run_plan (no id: every plan)
  // ---------------------------------------------------------------------------

  /// `get_run_plan`: with [planId] that plan in detail; without it every plan
  /// (progress rows) plus the detail of the plan being followed.
  Future<Map<String, dynamic>> plan({
    String? planId,
    int? fromWeek,
    int weeks = 2,
  }) async {
    if (planId != null) {
      return planDetail(planId, fromWeek: fromWeek, weeks: weeks);
    }
    final listed = await listPlans(includeArchived: true);
    final rows = (listed['plans'] as List).cast<Map<String, dynamic>>();
    if (rows.isEmpty) return {'plans': rows};
    final followed = rows.firstWhere(
      (row) => row['is_activated'] == true && row['status'] == 'active',
      orElse: () => rows.firstWhere(
        (row) => row['status'] == 'active',
        orElse: () => rows.first,
      ),
    );
    final detail = await planDetail(
      followed['id']! as String,
      fromWeek: fromWeek,
      weeks: weeks,
    );
    return {
      'plans': [
        for (final row in rows)
          {
            'id': row['id'],
            'name': row['name'],
            'status': row['status'],
            'goal': row['goal'],
            'current_week': row['current_week'],
          },
      ],
      ...detail,
    };
  }

  Future<Map<String, dynamic>> listPlans({bool includeArchived = false}) async {
    final all = await plans.listPlans(includeArchived: includeArchived);
    final shown = all.take(30).toList();
    final progress = await plans.getPlanProgressBatch([
      for (final plan in shown) plan.id,
    ]);
    final today = _today;
    return {
      'applied': {'include_archived': includeArchived},
      'total': all.length,
      'plans': [
        for (final plan in shown)
          {
            'id': plan.id,
            'name': plan.name,
            'goal': plan.goalKind.value,
            'weeks': plan.weeks,
            'status': plan.status.value,
            'is_activated': plan.isActivated,
            'start_date': plan.activatedAt == null
                ? null
                : dateKey(plan.activatedAt!),
            'current_week': _currentWeek(plan, today),
            if (plan.isFinishedOn(today)) 'finished': true,
            'race_date': plan.raceDate == null ? null : dateKey(plan.raceDate!),
            ..._progressColumns(progress[plan.id]),
          },
      ],
    };
  }

  static int? _currentWeek(RunPlan plan, DateTime today) {
    final index = plan.activeWeekIndexOn(today);
    return index == null ? null : index + 1;
  }

  static Map<String, dynamic> _progressColumns(RunPlanProgress? progress) {
    if (progress == null) return const {};
    return {
      'sessions_completed': progress.completedSessions,
      'sessions_skipped': progress.skippedSessions,
      'sessions_planned': progress.plannedSessions,
      'sessions_total': progress.totalSessions,
      'completion_pct': progress.totalSessions < 1
          ? null
          : progress.completedSessions / progress.totalSessions * 100,
    };
  }

  // ---------------------------------------------------------------------------
  // get_run_plan (one plan in detail)
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> planDetail(
    String planId, {
    int? fromWeek,
    int weeks = 2,
  }) async {
    final plan = await plans.getPlan(planId);
    if (plan == null) {
      throw const AiToolNotFoundException(
        'run plan not found',
        hint: 'call get_run_plan without plan_id to list plans',
      );
    }
    final today = _today;
    final current = _currentWeek(plan, today);
    final first = fromWeek ?? current ?? 1;
    if (first < 1 || first > plan.weeks) {
      throw AiToolArgException.invalid(
        'from_week',
        'a week between 1 and ${plan.weeks}',
        fromWeek,
      );
    }
    final count = weeks.clamp(1, _maxPlanWeeks);
    final last = math.min(plan.weeks, first + count - 1);

    final ledger = await _planLedger(planId);
    var completed = 0;
    var skipped = 0;
    for (final entry in ledger.values) {
      if (entry.status == ScheduledRunStatus.completed) completed++;
      if (entry.status == ScheduledRunStatus.skipped) skipped++;
    }
    final total = plan.workouts.length;
    final planned = math.max(0, total - completed - skipped);

    // Planned versus performed distance, only for sessions that were done and
    // have a recorded run, so both sides cover the same sessions.
    var plannedMeters = 0.0;
    var performedMeters = 0.0;
    for (final session in plan.workouts) {
      final entry = ledger[session.id];
      if (entry == null ||
          entry.status != ScheduledRunStatus.completed ||
          entry.distanceMeters == null) {
        continue;
      }
      final target = session.plannedDistanceMeters;
      if (target <= 0) continue;
      plannedMeters += target;
      performedMeters += entry.distanceMeters!;
    }

    final database = await db.database;
    final adaptationRows = await database.query(
      'run_plan_adaptations',
      where: 'run_plan_id = ?',
      whereArgs: [planId],
      orderBy: 'created_at DESC',
      limit: 6,
    );

    final overview = [
      for (var week = 0; week < plan.weeks && week < 60; week++)
        _weekOverview(plan, week, ledger),
    ];
    final sessions = <Map<String, dynamic>>[];
    for (var week = first - 1; week < last; week++) {
      for (final session in plan.workoutsForWeek(week)) {
        final entry = ledger[session.id];
        sessions.add({
          'week': week + 1,
          'day_of_week': session.dayOfWeek,
          'id': session.id,
          'name': session.name,
          'kind': session.kind.value,
          'distance_m': _positive(session.plannedDistanceMeters),
          'duration_s': _positive(session.plannedDurationSeconds),
          'target_pace_s_km': _positive(session.targetPaceSecPerKm),
          'effort_zone': session.effortZone,
          'status': entry?.status.value,
          'date': entry?.date,
          'activity_id': entry?.activityId,
          'steps': _stepsText(session),
        });
      }
    }
    final hasMore = last < plan.weeks;
    return {
      'applied': {'from_week': first, 'weeks': last - first + 1},
      'plan': {
        'id': plan.id,
        'name': plan.name,
        'goal': plan.goalKind.value,
        'weeks': plan.weeks,
        'status': plan.status.value,
        'is_activated': plan.isActivated,
        'start_date': plan.activatedAt == null
            ? null
            : dateKey(plan.activatedAt!),
        'current_week': current,
        if (plan.isFinishedOn(today)) 'finished': true,
        'race_date': plan.raceDate == null ? null : dateKey(plan.raceDate!),
        'notes': _text(plan.notes, 160),
        'sessions_completed': completed,
        'sessions_skipped': skipped,
        'sessions_planned': planned,
        'sessions_total': total,
        'completion_pct': total < 1 ? null : completed / total * 100,
      },
      'adherence': {
        'planned_distance_m': plannedMeters > 0 ? plannedMeters : null,
        'performed_distance_m': plannedMeters > 0 ? performedMeters : null,
        'distance_adherence_pct': plannedMeters > 0
            ? performedMeters / plannedMeters * 100
            : null,
      },
      'adaptations': [for (final row in adaptationRows) _adaptationRow(row)],
      'week_overview': overview,
      'has_more': hasMore,
      if (hasMore) 'next_from_week': last + 1,
      'sessions': sessions,
    };
  }

  static Map<String, dynamic> _weekOverview(
    RunPlan plan,
    int week,
    Map<String, _LedgerEntry> ledger,
  ) {
    final sessions = plan.workoutsForWeek(week);
    var completed = 0;
    var skipped = 0;
    for (final session in sessions) {
      final status = ledger[session.id]?.status;
      if (status == ScheduledRunStatus.completed) completed++;
      if (status == ScheduledRunStatus.skipped) skipped++;
    }
    return {
      'week': week + 1,
      'sessions': sessions.length,
      'distance_m': _positive(plan.weeklyDistanceMeters(week)),
      'quality': plan.qualitySessionsForWeek(week),
      'completed': completed,
      'skipped': skipped,
    };
  }

  static Map<String, dynamic> _adaptationRow(Map<String, Object?> row) {
    Map<String, dynamic> payload = const {};
    try {
      final decoded = jsonDecode(row['payload_json'] as String? ?? '');
      if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
    } catch (_) {
      // A corrupt payload only loses the numbers; the review row stays.
    }
    num? number(String camel, String snake) {
      final value = payload[camel] ?? payload[snake];
      return value is num ? value : null;
    }

    final fromWeek = number('fromWeek', 'from_week');
    return {
      'week': ((row['week_index'] as num?)?.toInt() ?? 0) + 1,
      'kind': row['kind'],
      'status': row['status'],
      'date': row['created_at'],
      'from_week': fromWeek == null ? null : fromWeek.toInt() + 1,
      'done_km': number('doneKm', 'done_km'),
      'planned_km': number('plannedKm', 'planned_km'),
      'baseline_km': number('baselineKm', 'baseline_km'),
      'missed_weeks': number('missedWeeks', 'missed_weeks'),
    };
  }

  /// Strongest status per plan session (completed > skipped > planned) with
  /// the recorded run. Joins from `run_plan_workouts`, so it never scans
  /// `scheduled_runs` by plan id (there is no index on that column).
  Future<Map<String, _LedgerEntry>> _planLedger(String planId) async {
    final database = await db.database;
    final rows = await database.rawQuery(
      '''
      SELECT sr.run_plan_workout_id AS workout_id, sr.status AS status,
        sr.date AS date, sr.run_activity_id AS activity_id,
        ra.distance_meters AS distance
      FROM run_plan_workouts w
      JOIN scheduled_runs sr ON sr.run_plan_workout_id = w.id
      LEFT JOIN run_activities ra
        ON ra.id = sr.run_activity_id AND ra.status = 'completed'
      WHERE w.run_plan_id = ?
      ORDER BY sr.date ASC
      ''',
      [planId],
    );
    const rank = {
      ScheduledRunStatus.planned: 0,
      ScheduledRunStatus.skipped: 1,
      ScheduledRunStatus.completed: 2,
    };
    final result = <String, _LedgerEntry>{};
    for (final row in rows) {
      final status = ScheduledRunStatus.fromString(row['status'] as String?);
      final id = row['workout_id'] as String;
      final current = result[id];
      final entry = _LedgerEntry(
        status: status,
        date: row['date'] as String?,
        activityId: row['activity_id'] as String?,
        distanceMeters: _positive(row['distance'])?.toDouble(),
      );
      if (current == null ||
          rank[status]! > rank[current.status]! ||
          (rank[status]! == rank[current.status]! &&
              current.activityId == null &&
              entry.activityId != null)) {
        result[id] = entry;
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // get_run_schedule
  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> schedule({
    String? startDate,
    String? endDate,
    int limit = 20,
    int page = 1,
  }) async {
    final parsedEnd = _parseDay('end_date', endDate);
    final start =
        _parseDay('start_date', startDate) ??
        (parsedEnd != null && parsedEnd.isBefore(_today)
            ? addDays(parsedEnd, -27)
            : _today);
    final end = parsedEnd ?? addDays(start, 27);
    _checkRange(start, end);
    final database = await db.database;
    final range = [dateKey(start), dateKey(end)];
    final total =
        Sqflite.firstIntValue(
          await database.rawQuery(
            'SELECT COUNT(*) FROM scheduled_runs WHERE date >= ? AND date <= ?',
            range,
          ),
        ) ??
        0;
    final offset = (page - 1) * limit;
    final rows = await database.rawQuery(
      '''
      SELECT sr.id AS id, sr.date AS date, sr.status AS status,
        sr.run_plan_id AS plan_id, sr.run_plan_workout_id AS workout_id,
        sr.run_activity_id AS activity_id,
        ra.distance_meters AS actual_distance
      FROM scheduled_runs sr
      LEFT JOIN run_activities ra ON ra.id = sr.run_activity_id
      WHERE sr.date >= ? AND sr.date <= ?
      ORDER BY sr.date ASC, sr.created_at ASC, sr.id ASC
      LIMIT ? OFFSET ?
      ''',
      [...range, limit, offset],
    );
    final workouts = await _loadWorkouts(
      database,
      rows.map((row) => row['workout_id']).whereType<String>().toSet(),
    );
    final planIds = rows
        .map((row) => row['plan_id'])
        .whereType<String>()
        .toSet();
    final planNames = <String, String>{};
    for (final chunk in _chunks(planIds.toList())) {
      for (final row in await database.query(
        'run_plans',
        columns: const ['id', 'name'],
        where: 'id IN (${_marks(chunk.length)})',
        whereArgs: chunk,
      )) {
        planNames[row['id'] as String] = row['name'] as String? ?? '';
      }
    }
    final hasMore = offset + rows.length < total;
    return {
      'applied': {
        'start_date': dateKey(start),
        'end_date': dateKey(end),
        'order': 'date_asc',
      },
      'total': total,
      'page': page,
      'limit': limit,
      'has_more': hasMore,
      if (hasMore) 'next_page': page + 1,
      'plans': [
        for (final entry in planNames.entries)
          {'plan_id': entry.key, 'name': entry.value},
      ],
      'runs': [
        for (final row in rows)
          () {
            final session = workouts[row['workout_id']];
            return {
              'date': row['date'],
              'id': row['id'],
              'status': row['status'],
              'plan_id': row['plan_id'],
              'session': session?.name,
              'kind': session?.kind.value,
              'week': session == null ? null : session.weekIndex + 1,
              'distance_m': session == null
                  ? null
                  : _positive(session.plannedDistanceMeters),
              'duration_s': session == null
                  ? null
                  : _positive(session.plannedDurationSeconds),
              'target_pace_s_km': _positive(session?.targetPaceSecPerKm),
              'effort_zone': session?.effortZone,
              'activity_id': row['activity_id'],
              'actual_distance_m': _positive(row['actual_distance']),
            };
          }(),
      ],
    };
  }

  /// Sessions (with their steps) by id, in chunked `IN` queries.
  Future<Map<String, RunPlanWorkout>> _loadWorkouts(
    Database database,
    Set<String> ids,
  ) async {
    final result = <String, RunPlanWorkout>{};
    for (final chunk in _chunks(ids.toList())) {
      final marks = _marks(chunk.length);
      final workoutRows = await database.query(
        'run_plan_workouts',
        where: 'id IN ($marks)',
        whereArgs: chunk,
      );
      final stepRows = await database.query(
        'run_workout_steps',
        where: 'run_plan_workout_id IN ($marks)',
        whereArgs: chunk,
        orderBy: 'order_index ASC',
      );
      final steps = <String, List<RunWorkoutStep>>{};
      for (final row in stepRows) {
        final step = RunWorkoutStep.fromMap(row);
        steps.putIfAbsent(step.runPlanWorkoutId, () => []).add(step);
      }
      for (final row in workoutRows) {
        final id = row['id'] as String;
        result[id] = RunPlanWorkout.fromMap(row, steps: steps[id] ?? const []);
      }
    }
    return result;
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  static DateTime? _parseDay(String param, String? value) {
    if (value == null || value.trim().isEmpty) return null;
    final parsed = DateTime.tryParse(value.trim());
    if (parsed == null || dateKey(parsed) != value.trim()) {
      throw AiToolArgException.invalid(param, 'YYYY-MM-DD', value);
    }
    return parsed;
  }

  static void _checkRange(DateTime? start, DateTime? end) {
    if (start != null && end != null && start.isAfter(end)) {
      throw AiToolArgException.conflict(
        'start_date',
        'must not be after end_date',
      );
    }
  }

  /// Lower string bound of a day for local wall-clock ISO timestamps.
  static String _dayStart(DateTime day) => '${dateKey(day)}T00:00:00';

  static String _marks(int count) => List.filled(count, '?').join(', ');

  static Iterable<List<T>> _chunks<T>(List<T> values) sync* {
    for (var i = 0; i < values.length; i += _inChunk) {
      yield values.sublist(i, math.min(values.length, i + _inChunk));
    }
  }

  /// The number when it is a positive measurement, else null (a zero distance
  /// or duration means "not recorded", never a real zero).
  static num? _positive(Object? value) {
    if (value is! num || !value.isFinite || value <= 0) return null;
    return value;
  }

  static double? _pace(Object? stored, num? distance, num? moving) {
    final value = _positive(stored);
    if (value != null) return value.toDouble();
    if (distance == null || moving == null) return null;
    return RunFormatters.paceOrNull(distance.toDouble(), moving);
  }

  static double? _speed(num? distance, num? moving) {
    if (distance == null || moving == null) return null;
    return (distance / 1000) / (moving / 3600);
  }

  static String? _text(String? value, int maxLength) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;
    return trimmed.length <= maxLength
        ? trimmed
        : '${trimmed.substring(0, maxLength)}...';
  }

  static String? _plannedText(String? metric, int? value) {
    if (value == null || value <= 0) return null;
    return metric == 'time' ? _timeText(value) : '${value}m';
  }

  static String _timeText(int seconds) =>
      seconds % 60 == 0 ? '${seconds ~/ 60}min' : '${seconds}s';

  /// A session's structure on one line, for example
  /// `1200m warmup | 6x(400m work @4:40-5:00, 200m recovery) | 1000m cooldown`.
  /// Null for continuous sessions (their target is in the row itself).
  static String? _stepsText(RunPlanWorkout session) {
    if (session.steps.isEmpty) return null;
    final ordered = [...session.steps]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final parts = <String>[];
    var index = 0;
    while (index < ordered.length) {
      final group = ordered[index].repeatGroup;
      if (group == null) {
        parts.add(_stepText(ordered[index]));
        index++;
        continue;
      }
      final block = <RunWorkoutStep>[];
      while (index < ordered.length && ordered[index].repeatGroup == group) {
        block.add(ordered[index]);
        index++;
      }
      final repeats = block.map((s) => s.repeatCount).reduce(math.max);
      final text = block.map(_stepText).join(', ');
      parts.add(repeats > 1 ? '${repeats}x($text)' : text);
    }
    return parts.join(' | ');
  }

  static String _stepText(RunWorkoutStep step) {
    final amount = step.isDistance ? '${step.value}m' : _timeText(step.value);
    final fast = step.targetPaceMinSecPerKm;
    final slow = step.targetPaceMaxSecPerKm;
    final pace = fast != null && slow != null
        ? ' @${RunFormatters.paceShort(fast)}-${RunFormatters.paceShort(slow)}'
        : fast != null || slow != null
        ? ' @${RunFormatters.paceShort(fast ?? slow)}'
        : '';
    return '$amount ${step.role.value}$pace';
  }
}

class _LedgerEntry {
  final ScheduledRunStatus status;
  final String? date;
  final String? activityId;
  final double? distanceMeters;

  const _LedgerEntry({
    required this.status,
    required this.date,
    required this.activityId,
    required this.distanceMeters,
  });
}
