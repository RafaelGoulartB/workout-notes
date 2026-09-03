import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/cardio_activity_type.dart';
import 'package:workout_notes/models/run_achievement.dart';
import 'package:workout_notes/models/run_activity.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/scheduled_run.dart';
import 'package:workout_notes/repositories/run_plan_repository.dart';
import 'package:workout_notes/repositories/run_repository.dart';
import 'package:workout_notes/utils/run_achievement_engine.dart';
import 'package:workout_notes/utils/run_progress_analytics.dart';

/// Read-only, AI-facing access to recorded cardio activities and running plans.
///
/// GPS runs and stationary-bike sessions live in `run_activities`, separately
/// from strength `workouts`. Keeping this integration in its own service makes
/// that storage boundary explicit and prevents the coach from confusing an
/// aerobic gym set with a tracked run.
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
       activities = activities ?? RunRepository(),
       plans = plans ?? RunPlanRepository(),
       _now = now ?? DateTime.now;

  Future<Map<String, dynamic>> listActivities({
    String? startDate,
    String? endDate,
    String activityType = 'running',
    int page = 1,
    int pageSize = 20,
  }) async {
    final database = await db.database;
    final where = <String>["status = 'completed'"];
    final args = <Object?>[];
    final type = _activityType(activityType);
    if (type != null) {
      where.add('activity_type = ?');
      args.add(type.databaseValue);
    }
    if (startDate != null) {
      where.add('started_at >= ?');
      args.add('${_date(DateTime.parse(startDate))}T00:00:00');
    }
    if (endDate != null) {
      where.add('started_at < ?');
      args.add(
        '${_date(DateTime.parse(endDate).add(const Duration(days: 1)))}T00:00:00',
      );
    }
    final whereSql = where.join(' AND ');
    final total =
        (await database.rawQuery(
              'SELECT COUNT(*) AS total FROM run_activities WHERE $whereSql',
              args,
            )).first['total']
            as num?;
    final rows = await database.query(
      'run_activities',
      where: whereSql,
      whereArgs: args,
      orderBy: 'started_at DESC',
      limit: pageSize,
      offset: (page - 1) * pageSize,
    );
    return {
      'filters': {
        'startDate': startDate,
        'endDate': endDate,
        'activityType': activityType,
      },
      'pagination': {
        'page': page,
        'pageSize': pageSize,
        'total': total?.toInt() ?? 0,
      },
      'activities': rows
          .map((row) => _activityJson(RunActivity.fromMap(row)))
          .toList(),
    };
  }

  Future<Map<String, dynamic>> activityDetail(String activityId) async {
    final activity = await activities.getActivity(activityId);
    if (activity == null) return {'found': false, 'activityId': activityId};
    final database = await db.database;
    final results = await Future.wait<dynamic>([
      plans.getActivitySteps(activityId),
      activities.getTrackPoints(activityId),
      database.query(
        'scheduled_runs',
        where: 'run_activity_id = ?',
        whereArgs: [activityId],
        orderBy: 'updated_at DESC',
        limit: 1,
      ),
      database.query(
        'run_activities',
        where: 'id = ?',
        whereArgs: [activityId],
        limit: 1,
      ),
    ]);
    final stepResults = results[0] as List<RunActivityStep>;
    final trackPoints = results[1] as List;
    final scheduledRows = results[2] as List<Map<String, Object?>>;
    final activityRows = results[3] as List<Map<String, Object?>>;
    final activityRow = activityRows.isEmpty
        ? const <String, Object?>{}
        : activityRows.first;
    final scheduled = scheduledRows.isEmpty
        ? null
        : ScheduledRun.fromMap(Map<String, dynamic>.from(scheduledRows.first));
    final planWorkoutId =
        scheduled?.runPlanWorkoutId ??
        activityRow['plan_workout_id'] as String?;
    final planWorkout = planWorkoutId == null
        ? null
        : await plans.getWorkout(planWorkoutId);
    final planId = scheduled?.runPlanId ?? planWorkout?.runPlanId;
    final plan = planId == null ? null : await plans.getPlan(planId);

    final altitudes = trackPoints
        .map((point) => (point as dynamic).altitude as double?)
        .whereType<double>()
        .toList();
    var elevationGain = 0.0;
    for (var i = 1; i < altitudes.length; i++) {
      final delta = altitudes[i] - altitudes[i - 1];
      if (delta > 0) elevationGain += delta;
    }

    return {
      'found': true,
      'activity': _activityJson(activity),
      'routeSummary': {
        'trackPointCount':
            (activityRow['raw_point_count'] as num?)?.toInt() ??
            trackPoints.length,
        'storedPointCount':
            (activityRow['stored_point_count'] as num?)?.toInt() ??
            trackPoints.length,
        'routeQuality': activityRow['route_quality'],
        'minimumAltitudeMeters':
            (activityRow['minimum_altitude_meters'] as num?)?.toDouble() ??
            (altitudes.isEmpty
                ? null
                : altitudes.reduce((a, b) => a < b ? a : b)),
        'maximumAltitudeMeters':
            (activityRow['maximum_altitude_meters'] as num?)?.toDouble() ??
            (altitudes.isEmpty
                ? null
                : altitudes.reduce((a, b) => a > b ? a : b)),
        'elevationGainMeters':
            (activityRow['elevation_gain_meters'] as num?)?.toDouble() ??
            elevationGain,
      },
      'plan': plan == null
          ? null
          : {'id': plan.id, 'name': plan.name, 'goal': plan.goalKind.value},
      'scheduledRun': scheduled == null
          ? null
          : {
              'id': scheduled.id,
              'date': _date(scheduled.date),
              'status': scheduled.status.value,
              'notes': scheduled.notes,
            },
      'plannedSession': planWorkout == null ? null : _sessionJson(planWorkout),
      'stepResults': [
        for (final step in stepResults)
          {
            'order': step.orderIndex,
            'role': step.role,
            'rep': step.repIndex,
            'plannedMetric': step.plannedMetric,
            'plannedValue': step.plannedValue,
            'plannedPaceSecPerKm': step.plannedPaceSecPerKm,
            'actualDistanceMeters': step.actualDistanceMeters,
            'actualDurationSeconds': step.actualDurationSeconds,
            'actualPaceSecPerKm': step.actualPaceSecPerKm,
            'paceDeltaSecPerKm': step.paceDeltaSecPerKm,
          },
      ],
    };
  }

  Future<Map<String, dynamic>> cardioSummary({int weeks = 4}) async {
    final end = _now();
    final start = DateTime(
      end.year,
      end.month,
      end.day,
    ).subtract(Duration(days: weeks * 7 - 1));
    final all = await _completedActivities();
    final recent = all.where((activity) {
      final day = DateTime(
        activity.startedAt.year,
        activity.startedAt.month,
        activity.startedAt.day,
      );
      return !day.isBefore(start) && !day.isAfter(end);
    }).toList();
    final byType = <String, List<RunActivity>>{};
    for (final activity in recent) {
      byType
          .putIfAbsent(activity.activityType.databaseValue, () => [])
          .add(activity);
    }
    return {
      'weeksBack': weeks,
      'startDate': _date(start),
      'endDate': _date(end),
      'recordedActivities': recent.length,
      'byActivityType': [
        for (final entry in byType.entries) _aggregate(entry.key, entry.value),
      ],
      'recentActivities': recent
          .take(20)
          .map(_activityJson)
          .toList(growable: false),
    };
  }

  Future<Map<String, dynamic>> progress({String period = '12_weeks'}) async {
    final statsPeriod = switch (period) {
      '4_weeks' => RunStatsPeriod.weeks4,
      'year' => RunStatsPeriod.year,
      'all' => RunStatsPeriod.all,
      _ => RunStatsPeriod.weeks12,
    };
    final all = (await _completedActivities())
        .where((activity) => activity.isRun)
        .toList();
    final stats = RunProgressAnalytics.fromActivities(
      all,
      period: statsPeriod,
      now: _now(),
    );
    return {
      'period': period,
      'periodStart': stats.periodStart == null
          ? null
          : _date(stats.periodStart!),
      'runCount': stats.runCount,
      'totalDistanceMeters': stats.totalDistanceMeters,
      'totalMovingTimeSeconds': stats.totalMovingTimeSeconds,
      'totalCalories': stats.totalCalories,
      'averagePaceSecPerKm': stats.avgPaceSecPerKm,
      'bestAveragePaceSecPerKm': stats.bestPaceSecPerKm,
      'bestKmSplitSecPerKm': stats.bestKmSplitSecPerKm,
      'averageRunsPerWeek': stats.avgRunsPerWeek,
      'weekStreak': stats.weekStreak,
      'thisWeek': {
        'runs': stats.thisWeekRunCount,
        'distanceMeters': stats.thisWeekDistanceMeters,
      },
      'lastWeek': {
        'runs': stats.lastWeekRunCount,
        'distanceMeters': stats.lastWeekDistanceMeters,
      },
      'distanceDeltaVsLastWeekMeters': stats.distanceDeltaVsLastWeek,
      'distanceRatioVsPreviousPeriod': stats.distanceRatioVsPreviousPeriod,
      'paceDeltaVsPreviousPeriodSecPerKm': stats.paceDeltaVsPreviousPeriod,
      'longestRun': stats.longestRun == null
          ? null
          : _activityJson(stats.longestRun!),
      'fastestRun': stats.fastestRun == null
          ? null
          : _activityJson(stats.fastestRun!),
      'weeklyTrend': [
        for (final week in stats.weeklyBuckets)
          {
            'weekStart': _date(week.weekStart),
            'runs': week.runCount,
            'distanceMeters': week.distanceMeters,
            'movingTimeSeconds': week.movingTimeSeconds,
          },
      ],
      'paceTrend': [
        for (final point in stats.paceTrend)
          {
            'date': _date(point.date),
            'paceSecPerKm': point.paceSecPerKm,
            'distanceMeters': point.distanceMeters,
          },
      ],
    };
  }

  Future<Map<String, dynamic>> achievements() async {
    final all = (await _completedActivities())
        .where((activity) => activity.isRun)
        .toList();
    final board = RunAchievementEngine.build(all);
    return {
      'categories': [
        for (final category in board.nonEmptyCategories)
          {
            'kind': category.kind.name,
            'placements': [
              for (final placement in category.placements)
                {
                  'place': placement.tier.place,
                  'activityId': placement.activity.id,
                  'date': _date(placement.activity.startedAt),
                  'value': placement.value,
                  'formattedValue': RunAchievementEngine.formatValue(
                    placement.kind,
                    placement.value,
                  ),
                },
            ],
          },
      ],
    };
  }

  Future<Map<String, dynamic>> listPlans({bool includeArchived = false}) async {
    final listed = await plans.listPlans(
      includeArchived: includeArchived,
      hydrate: true,
    );
    final progress = await Future.wait([
      for (final plan in listed) plans.getPlanProgress(plan.id),
    ]);
    return {
      'includeArchived': includeArchived,
      'plans': [
        for (var i = 0; i < listed.length; i++)
          _planJson(listed[i], progress[i]),
      ],
    };
  }

  Future<Map<String, dynamic>> planDetail(String planId) async {
    final plan = await plans.getPlan(planId);
    if (plan == null) return {'found': false, 'planId': planId};
    final progress = await plans.getPlanProgress(planId);
    final statuses = await plans.getPlanWorkoutStatuses(planId);
    final completedTargetDistance = plan.workouts
        .where(
          (session) => statuses[session.id] == ScheduledRunStatus.completed,
        )
        .fold<double>(0, (sum, session) => sum + session.plannedDistanceMeters);
    final database = await db.database;
    final performedRows = await database.rawQuery(
      '''
      SELECT COALESCE(SUM(distance_meters), 0) AS distance_meters,
        COALESCE(SUM(moving_seconds), 0) AS moving_seconds
      FROM (
        SELECT DISTINCT ra.id, ra.distance_meters,
          CASE WHEN ra.moving_time_seconds > 0 THEN ra.moving_time_seconds
            ELSE ra.duration_seconds END AS moving_seconds
        FROM scheduled_runs sr
        JOIN run_activities ra ON ra.id = sr.run_activity_id
        WHERE sr.run_plan_id = ? AND sr.status = 'completed'
          AND ra.status = 'completed'
      )
      ''',
      [planId],
    );
    final performedDistance =
        (performedRows.first['distance_meters'] as num?)?.toDouble() ?? 0;
    return {
      'found': true,
      ..._planJson(plan, progress),
      'adherence': {
        'completedSessionPlannedDistanceMeters': completedTargetDistance,
        'performedDistanceMeters': performedDistance,
        'performedMovingTimeSeconds':
            (performedRows.first['moving_seconds'] as num?)?.toInt() ?? 0,
        'distanceRatioForCompletedSessions': completedTargetDistance <= 0
            ? null
            : performedDistance / completedTargetDistance,
      },
      'weekPlans': [
        for (var week = 0; week < plan.weeks; week++)
          {
            'week': week + 1,
            'isCurrentWeek': plan.activeWeekIndexOn(_now()) == week,
            'plannedDistanceMeters': plan.weeklyDistanceMeters(week),
            'qualitySessions': plan.qualitySessionsForWeek(week),
            'sessions': [
              for (final session in plan.workoutsForWeek(week))
                _sessionJson(session),
            ],
          },
      ],
    };
  }

  Future<Map<String, dynamic>> schedule({
    String? startDate,
    String? endDate,
  }) async {
    final today = _now();
    final start =
        DateTime.tryParse(startDate ?? '') ??
        DateTime(today.year, today.month, today.day);
    final end =
        DateTime.tryParse(endDate ?? '') ?? start.add(const Duration(days: 27));
    final scheduled = await plans.getScheduledRuns(start, end);
    final planCache = <String, RunPlan?>{};
    final activityCache = <String, RunActivity?>{};
    for (final run in scheduled) {
      final planId = run.runPlanId;
      if (planId != null && !planCache.containsKey(planId)) {
        planCache[planId] = await plans.getPlan(planId);
      }
      final activityId = run.runActivityId;
      if (activityId != null && !activityCache.containsKey(activityId)) {
        activityCache[activityId] = await activities.getActivity(activityId);
      }
    }
    return {
      'startDate': _date(start),
      'endDate': _date(end),
      'scheduledRuns': [
        for (final run in scheduled)
          {
            'id': run.id,
            'date': _date(run.date),
            'status': run.status.value,
            'runPlanId': run.runPlanId,
            'runPlanName': planCache[run.runPlanId]?.name,
            'runActivityId': run.runActivityId,
            'notes': run.notes,
            'session': run.workout == null ? null : _sessionJson(run.workout!),
            'recordedActivity':
                run.runActivityId == null ||
                    activityCache[run.runActivityId] == null
                ? null
                : _activityJson(activityCache[run.runActivityId]!),
          },
      ],
    };
  }

  Future<List<RunActivity>> _completedActivities() async {
    final database = await db.database;
    final rows = await database.query(
      'run_activities',
      where: 'status = ?',
      whereArgs: ['completed'],
      orderBy: 'started_at DESC',
    );
    return rows.map(RunActivity.fromMap).toList();
  }

  static CardioActivityType? _activityType(String raw) => switch (raw) {
    'all' => null,
    'stationary_bike' || 'bike' => CardioActivityType.stationaryBike,
    _ => CardioActivityType.running,
  };

  static Map<String, dynamic> _aggregate(
    String type,
    List<RunActivity> values,
  ) {
    final distance = values.fold<double>(
      0,
      (sum, value) => sum + value.distanceMeters,
    );
    final moving = values.fold<int>(
      0,
      (sum, value) => sum + value.movingTimeSeconds,
    );
    final calories = values.fold<int>(
      0,
      (sum, value) => sum + (value.calories ?? 0),
    );
    final rpes = values.map((value) => value.rpe).whereType<double>().toList();
    return {
      'activityType': type,
      'sessions': values.length,
      'distanceMeters': distance,
      'movingTimeSeconds': moving,
      'calories': calories,
      'averagePaceSecPerKm': type == 'running' && distance > 0 && moving > 0
          ? moving / (distance / 1000)
          : null,
      'averageSpeedKmh': distance > 0 && moving > 0
          ? (distance / 1000) / (moving / 3600)
          : null,
      'averageRpe': rpes.isEmpty
          ? null
          : rpes.reduce((a, b) => a + b) / rpes.length,
    };
  }

  static Map<String, dynamic> _activityJson(RunActivity activity) => {
    'id': activity.id,
    'activityType': activity.activityType.databaseValue,
    'startedAt': activity.startedAt.toIso8601String(),
    'endedAt': activity.endedAt?.toIso8601String(),
    'status': activity.status,
    'title': activity.title,
    'notes': activity.notes,
    'durationSeconds': activity.durationSeconds,
    'movingTimeSeconds': activity.movingTimeSeconds,
    'distanceMeters': activity.distanceMeters,
    'averagePaceSecPerKm': activity.avgPaceSecPerKm,
    'maximumPaceSecPerKm': activity.maxPaceSecPerKm,
    'averageSpeedKmh': activity.averageSpeedKmh,
    'calories': activity.calories,
    'rpe': activity.rpe,
    'feelingRating': activity.feelingRating,
    'bestSplitPaceSecPerKm': activity.bestSplitPaceSecPerKm,
    'bestEffortsSeconds': {
      '1k': activity.bestEffort1kSec,
      '3k': activity.bestEffort3kSec,
      '5k': activity.bestEffort5kSec,
      '10k': activity.bestEffort10kSec,
      'halfMarathon': activity.bestEffortHalfSec,
      'marathon': activity.bestEffortMarathonSec,
    },
    'effortsComputed': activity.effortsComputed,
  };

  Map<String, dynamic> _planJson(RunPlan plan, RunPlanProgress progress) => {
    'id': plan.id,
    'name': plan.name,
    'goal': plan.goalKind.value,
    'weeks': plan.weeks,
    'status': plan.status.value,
    'isActivated': plan.isActivated,
    'activatedAt': plan.activatedAt == null ? null : _date(plan.activatedAt!),
    'currentWeek': plan.activeWeekIndexOn(_now()) == null
        ? null
        : plan.activeWeekIndexOn(_now())! + 1,
    'raceDate': plan.raceDate == null ? null : _date(plan.raceDate!),
    'completionCount': plan.completionCount,
    'progress': {
      'totalSessions': progress.totalSessions,
      'completedSessions': progress.completedSessions,
      'skippedSessions': progress.skippedSessions,
      'plannedSessions': progress.plannedSessions,
      'completionFraction': progress.fraction,
      'isComplete': progress.isComplete,
    },
  };

  static Map<String, dynamic> _sessionJson(RunPlanWorkout session) => {
    'id': session.id,
    'name': session.name,
    'notes': session.notes,
    'kind': session.kind.value,
    'isQuality': session.kind.isQuality,
    'week': session.weekIndex + 1,
    'dayOfWeek': session.dayOfWeek,
    'plannedDistanceMeters': session.plannedDistanceMeters,
    'plannedDurationSeconds': session.plannedDurationSeconds,
    'targetPaceSecPerKm': session.targetPaceSecPerKm,
    'effortZone': session.effortZone,
    'effortReps': session.workRepCount,
    'steps': [
      for (final step in session.steps)
        {
          'role': step.role.value,
          'metric': step.metric.name,
          'value': step.value,
          'repeatGroup': step.repeatGroup,
          'repeatCount': step.repeatCount,
          'targetPaceMinSecPerKm': step.targetPaceMinSecPerKm,
          'targetPaceMaxSecPerKm': step.targetPaceMaxSecPerKm,
          'notes': step.notes,
        },
    ],
  };

  static String _date(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);
}
