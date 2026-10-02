part of 'periodization_repository.dart';

/// Phase and week metrics plus the weekly check-in log.
extension PeriodizationRepositoryMetrics on PeriodizationRepository {
  Future<List<PeriodizationCheckin>> getCheckins(String phaseId) async {
    final database = await db;
    final rows = await database.query(
      'periodization_checkins',
      where: 'phase_id = ?',
      whereArgs: [phaseId],
      orderBy: 'week_start DESC',
    );
    return rows.map(PeriodizationCheckin.fromMap).toList();
  }

  Future<PeriodizationCheckin?> getCheckin(
    String phaseId,
    DateTime weekStart,
  ) async {
    final database = await db;
    final rows = await database.query(
      'periodization_checkins',
      where: 'phase_id = ? AND week_start = ?',
      whereArgs: [phaseId, dateKey(mondayOf(weekStart))],
      limit: 1,
    );
    return rows.isEmpty ? null : PeriodizationCheckin.fromMap(rows.first);
  }

  Future<void> saveCheckin(PeriodizationCheckin checkin) async {
    if (checkin.energy < 1 ||
        checkin.energy > 5 ||
        checkin.hunger < 1 ||
        checkin.hunger > 5 ||
        checkin.recovery < 1 ||
        checkin.recovery > 5) {
      throw const PeriodizationValidationException('checkin_rating_invalid');
    }
    final phase = await getPhase(checkin.phaseId);
    if (phase == null) {
      throw const PeriodizationValidationException('phase_not_found');
    }
    final normalizedWeek = mondayOf(checkin.weekStart);
    final weekEnd = addDays(normalizedWeek, 6);
    if (weekEnd.isBefore(phase.startDate) ||
        normalizedWeek.isAfter(phase.endDate)) {
      throw const PeriodizationValidationException('checkin_outside_phase');
    }
    final normalized = PeriodizationCheckin(
      id: checkin.id,
      phaseId: checkin.phaseId,
      weekStart: normalizedWeek,
      energy: checkin.energy,
      hunger: checkin.hunger,
      recovery: checkin.recovery,
      performance: checkin.performance,
      decision: checkin.decision,
      notes: checkin.notes,
      metricsSnapshot: checkin.metricsSnapshot,
      targetsSnapshot: checkin.targetsSnapshot,
      createdAt: checkin.createdAt,
    );
    final database = await db;
    await database.transaction((txn) async {
      await txn.delete(
        'periodization_checkins',
        where: 'phase_id = ? AND week_start = ?',
        whereArgs: [checkin.phaseId, dateKey(normalizedWeek)],
      );
      await txn.insert('periodization_checkins', normalized.toMap());
    });
  }

  Future<PeriodizationMetrics> getPhaseMetrics(
    PeriodizationPhase phase, {
    DateTime? rangeStart,
    DateTime? rangeEnd,
  }) async {
    final now = dayOf(DateTime.now());
    final start = dayOf(rangeStart ?? phase.startDate);
    var end = dayOf(rangeEnd ?? phase.endDate);
    if (end.isAfter(now)) end = now;
    if (end.isBefore(start)) {
      return PeriodizationMetrics(
        startDate: start,
        endDate: end,
        elapsedDays: 0,
        workoutCount: 0,
        completedSets: 0,
        volume: 0,
        nutritionDaysLogged: 0,
        sleepDaysLogged: 0,
      );
    }
    final database = await db;
    final startText = dateKey(start);
    final endText = dateKey(end);
    final endAfterText = _dayAfter(end);
    final targetHistory = await getTargetHistory(phase.id);
    final routineIds = <String>{};
    for (var date = start; !date.isAfter(end); date = addDays(date, 1)) {
      routineIds.addAll(
        _targetForDate(targetHistory, date)?.routineIds ?? const [],
      );
    }
    final routineFilter = routineIds.isEmpty
        ? ''
        : ' AND w.routine_id IN (${List.filled(routineIds.length, '?').join(', ')})';
    final routineArgs = routineIds.toList();

    // Weekly running targets are summed per week, not per day: a weekly volume
    // of 40 km must not become 280 km over seven days.
    var plannedRunSessions = 0;
    var plannedRunDistance = 0.0;
    var plannedQualityRuns = 0;
    double? plannedLongRun;
    var hasRunTarget = false;
    for (
      var weekCursor = mondayOf(start);
      !weekCursor.isAfter(end);
      weekCursor = addDays(weekCursor, 7)
    ) {
      // Anchor on a day that belongs to the range so partial first/last weeks
      // resolve the target that actually applies.
      final anchor = weekCursor.isBefore(start) ? start : weekCursor;
      final target = _targetForDate(targetHistory, anchor);
      if (target == null) continue;
      final weekDays = _daysOfWeekInRange(weekCursor, start, end);
      if (weekDays == 0) continue;
      final weight = weekDays / 7;
      if (target.runSessionsPerWeek != null) {
        hasRunTarget = true;
        plannedRunSessions += (target.runSessionsPerWeek! * weight).round();
      }
      if (target.runWeeklyDistanceMeters != null) {
        hasRunTarget = true;
        plannedRunDistance += target.runWeeklyDistanceMeters! * weight;
      }
      if (target.qualitySessionsPerWeek != null) {
        hasRunTarget = true;
        plannedQualityRuns += (target.qualitySessionsPerWeek! * weight).round();
      }
      if (target.longRunDistanceMeters != null) {
        hasRunTarget = true;
        // The long run is a per-week peak, so take the largest one asked for.
        plannedLongRun = plannedLongRun == null
            ? target.longRunDistanceMeters
            : (target.longRunDistanceMeters! > plannedLongRun
                  ? target.longRunDistanceMeters
                  : plannedLongRun);
      }
    }

    final run = (await database.rawQuery(
      '''
      SELECT COUNT(*) AS run_count,
             COALESCE(SUM(distance_meters), 0) AS distance_meters,
             COALESCE(SUM(moving_time_seconds), 0) AS moving_time_seconds,
             COALESCE(MAX(distance_meters), 0) AS longest_run_meters
      FROM run_activities
      WHERE status = 'completed' AND activity_type = 'running'
        AND started_at >= ? AND started_at < ?
      ''',
      [startText, endAfterText],
    )).first;

    // A "quality" run is one linked to a tempo/interval/hills/fartlek/race
    // session of a plan. Ad-hoc runs count as volume, never as quality.
    final qualityRunCount =
        Sqflite.firstIntValue(
          await database.rawQuery(
            '''
            SELECT COUNT(*) FROM run_activities activity
            JOIN run_plan_workouts session
              ON session.id = activity.plan_workout_id
            WHERE activity.status = 'completed'
              AND activity.activity_type = 'running'
              AND activity.started_at >= ? AND activity.started_at < ?
              AND session.kind IN
                  ('tempo', 'interval', 'fartlek', 'hills', 'race')
            ''',
            [startText, endAfterText],
          ),
        ) ??
        0;

    final workoutRows = await database.rawQuery(
      '''
      SELECT COUNT(DISTINCT w.id) AS workout_count,
             COUNT(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0 THEN 1 END) AS set_count,
             SUM(CASE WHEN s.is_complete = 1 AND s.is_warmup = 0
                      THEN COALESCE(s.weight, 0) * COALESCE(s.reps, 0) ELSE 0 END) AS volume
      FROM workouts w
      LEFT JOIN exercise_entries ee ON ee.workout_id = w.id
      LEFT JOIN sets s ON s.exercise_entry_id = ee.id
       WHERE w.date BETWEEN ? AND ? AND w.end_time IS NOT NULL
         $routineFilter
     ''',
      [startText, endText, ...routineArgs],
    );
    final workout = workoutRows.first;

    final nutritionRows = await database.rawQuery(
      '''
      SELECT ml.date,
             SUM(COALESCE(item.calories, 0)) AS calories,
             SUM(COALESCE(item.protein_g, 0)) AS protein_g,
             SUM(COALESCE(item.carbs_g, 0)) AS carbs_g,
             SUM(COALESCE(item.fat_g, 0)) AS fat_g
      FROM meal_logs ml
      JOIN meal_log_items item ON item.meal_log_id = ml.id
      WHERE ml.date BETWEEN ? AND ?
      GROUP BY ml.date
      ORDER BY ml.date ASC
    ''',
      [startText, endText],
    );
    double calorieSum = 0;
    double proteinSum = 0;
    double carbsSum = 0;
    double fatSum = 0;
    final nutritionByDate = <String, Map<String, Object?>>{};
    for (final row in nutritionRows) {
      final calories = (row['calories'] as num?)?.toDouble() ?? 0;
      calorieSum += calories;
      proteinSum += (row['protein_g'] as num?)?.toDouble() ?? 0;
      carbsSum += (row['carbs_g'] as num?)?.toDouble() ?? 0;
      fatSum += (row['fat_g'] as num?)?.toDouble() ?? 0;
      nutritionByDate[row['date'] as String] = row;
    }

    double plannedWorkoutSum = 0;
    double plannedSetsMinimumSum = 0;
    double plannedSetsMaximumSum = 0;
    var hasPlannedWorkouts = false;
    var hasPlannedSetsMinimum = false;
    var hasPlannedSetsMaximum = false;
    var nutritionTargetDays = 0;
    var nutritionTargetDaysLogged = 0;
    double nutritionAdherenceSum = 0;
    var sleepTargetDays = 0;
    final runPlanCache = <String, RunPlan?>{};
    for (var date = start; !date.isAfter(end); date = addDays(date, 1)) {
      final target = _targetForDate(targetHistory, date);
      if (target?.workoutsPerWeek != null) {
        plannedWorkoutSum += target!.workoutsPerWeek! / 7;
        hasPlannedWorkouts = true;
      }
      if (target?.minSetsPerWeek != null) {
        plannedSetsMinimumSum += target!.minSetsPerWeek! / 7;
        hasPlannedSetsMinimum = true;
      }
      if (target?.maxSetsPerWeek != null) {
        plannedSetsMaximumSum += target!.maxSetsPerWeek! / 7;
        hasPlannedSetsMaximum = true;
      }
      // Training and rest days can carry different nutrition targets.
      final trainingDay = target == null || !target.hasRestDayNutrition
          ? true
          : (await dayPlanFor(
                  phase,
                  target,
                  date,
                  runPlanCache: runPlanCache,
                )).trainingDay ??
                true;
      final dayNutrition = target?.nutritionFor(trainingDay: trainingDay);
      final targetValues = [
        dayNutrition?.calories,
        dayNutrition?.proteinG,
        dayNutrition?.carbsG,
        dayNutrition?.fatG,
      ];
      if (targetValues.any((value) => value != null)) {
        nutritionTargetDays++;
        final actual = nutritionByDate[dateKey(date)];
        if (actual != null) nutritionTargetDaysLogged++;
        final actualValues = [
          (actual?['calories'] as num?)?.toDouble(),
          (actual?['protein_g'] as num?)?.toDouble(),
          (actual?['carbs_g'] as num?)?.toDouble(),
          (actual?['fat_g'] as num?)?.toDouble(),
        ];
        var score = 0.0;
        var configured = 0;
        for (var i = 0; i < targetValues.length; i++) {
          final expected = targetValues[i];
          if (expected != null) {
            configured++;
            score += _adherenceScore(actualValues[i], expected);
          }
        }
        nutritionAdherenceSum += configured == 0 ? 0 : score / configured;
      }
      if (target?.sleepHours != null) sleepTargetDays++;
    }

    final weights = await database.query(
      'body_measurements',
      where: "type = 'weight' AND date BETWEEN ? AND ?",
      whereArgs: [startText, endText],
      orderBy: 'date ASC, created_at ASC',
    );
    final normalizedWeights = weights
        .map(_weightKg)
        .whereType<double>()
        .toList();

    final sleepRows = await database.rawQuery(
      '''
      SELECT date,
             COALESCE(actual_sleep_minutes, estimated_sleep_minutes, sleep_minutes) AS minutes
      FROM sleep_entries
      WHERE date BETWEEN ? AND ?
      ORDER BY date ASC
      ''',
      [startText, endText],
    );
    final sleepByDate = <String, double>{};
    for (final row in sleepRows) {
      final minutes = (row['minutes'] as num?)?.toDouble();
      if (minutes != null) sleepByDate[row['date'] as String] = minutes / 60;
    }
    final averageSleepHours = sleepByDate.isEmpty
        ? null
        : sleepByDate.values.fold<double>(0, (sum, value) => sum + value) /
              sleepByDate.length;
    double sleepAdherenceSum = 0;
    var sleepTargetDaysLogged = 0;
    for (var date = start; !date.isAfter(end); date = addDays(date, 1)) {
      final expected = _targetForDate(targetHistory, date)?.sleepHours;
      if (expected == null) continue;
      final actual = sleepByDate[dateKey(date)];
      if (actual != null) sleepTargetDaysLogged++;
      sleepAdherenceSum += _adherenceScore(actual, expected);
    }

    final rpeRows = await database.rawQuery(
      '''
      SELECT w.date, s.rpe
      FROM workouts w
      JOIN exercise_entries ee ON ee.workout_id = w.id
      JOIN sets s ON s.exercise_entry_id = ee.id
       WHERE w.date BETWEEN ? AND ? AND w.end_time IS NOT NULL
         AND s.is_complete = 1 AND s.is_warmup = 0
         $routineFilter
      ''',
      [startText, endText, ...routineArgs],
    );
    var rpeExpectedSets = 0;
    var rpeSetsLogged = 0;
    double rpeSum = 0;
    double rpeAdherenceSum = 0;
    for (final row in rpeRows) {
      final date = DateTime.parse(row['date'] as String);
      final target = _targetForDate(targetHistory, date);
      if (target?.minRpe == null && target?.maxRpe == null) continue;
      rpeExpectedSets++;
      final actual = (row['rpe'] as num?)?.toDouble();
      if (actual == null) continue;
      rpeSetsLogged++;
      rpeSum += actual;
      final minimum = target?.minRpe ?? target?.maxRpe ?? actual;
      final maximum = target?.maxRpe ?? target?.minRpe ?? actual;
      final distance = actual < minimum
          ? minimum - actual
          : actual > maximum
          ? actual - maximum
          : 0.0;
      rpeAdherenceSum += math.max(0, 1 - distance / 10);
    }
    final latestTarget = _targetForDate(targetHistory, end);
    final elapsedDays = daysBetween(start, end) + 1;
    final plannedWorkouts = hasPlannedWorkouts
        ? plannedWorkoutSum.round()
        : null;
    final plannedSetsMinimum = hasPlannedSetsMinimum
        ? plannedSetsMinimumSum.round()
        : null;
    final plannedSetsMaximum = hasPlannedSetsMaximum
        ? plannedSetsMaximumSum.round()
        : null;
    final completedSets = (workout['set_count'] as num?)?.toInt() ?? 0;
    double? setAdherence;
    if (plannedSetsMinimum != null || plannedSetsMaximum != null) {
      if (plannedSetsMinimum != null && completedSets < plannedSetsMinimum) {
        setAdherence = plannedSetsMinimum == 0
            ? 100
            : completedSets / plannedSetsMinimum * 100;
      } else if (plannedSetsMaximum != null &&
          completedSets > plannedSetsMaximum) {
        setAdherence = plannedSetsMaximum == 0
            ? 0
            : plannedSetsMaximum / completedSets * 100;
      } else {
        setAdherence = 100;
      }
    }
    final startingWeight = normalizedWeights.isEmpty
        ? null
        : normalizedWeights.first;
    final endingWeight = normalizedWeights.isEmpty
        ? null
        : normalizedWeights.last;
    final weightChange = normalizedWeights.length < 2
        ? null
        : normalizedWeights.last - normalizedWeights.first;
    final elapsedWeeks = elapsedDays / 7;
    final weeklyWeightChange =
        startingWeight == null ||
            startingWeight == 0 ||
            weightChange == null ||
            elapsedWeeks == 0
        ? null
        : weightChange / startingWeight / elapsedWeeks * 100;
    final expectedWeeklyWeightChange = latestTarget?.weeklyWeightChangePercent;
    final weightAdherence =
        weeklyWeightChange == null || expectedWeeklyWeightChange == null
        ? null
        : _adherenceScore(
                weeklyWeightChange,
                expectedWeeklyWeightChange,
                toleranceFloor: 0.1,
              ) *
              100;
    return PeriodizationMetrics(
      startDate: start,
      endDate: end,
      elapsedDays: elapsedDays,
      workoutCount: (workout['workout_count'] as num?)?.toInt() ?? 0,
      completedSets: completedSets,
      volume: (workout['volume'] as num?)?.toDouble() ?? 0,
      plannedWorkouts: plannedWorkouts,
      plannedSetsMinimum: plannedSetsMinimum,
      plannedSetsMaximum: plannedSetsMaximum,
      setAdherencePercent: setAdherence,
      nutritionDaysLogged: nutritionRows.length,
      nutritionTargetDays: nutritionTargetDays,
      averageCalories: nutritionRows.isEmpty
          ? null
          : calorieSum / nutritionRows.length,
      averageProteinG: nutritionRows.isEmpty
          ? null
          : proteinSum / nutritionRows.length,
      averageCarbsG: nutritionRows.isEmpty
          ? null
          : carbsSum / nutritionRows.length,
      averageFatG: nutritionRows.isEmpty ? null : fatSum / nutritionRows.length,
      nutritionAdherencePercent: nutritionTargetDays == 0
          ? null
          : nutritionAdherenceSum / nutritionTargetDays * 100,
      nutritionCoveragePercent: nutritionTargetDays == 0
          ? null
          : nutritionTargetDaysLogged / nutritionTargetDays * 100,
      startingWeightKg: startingWeight,
      endingWeightKg: endingWeight,
      weightChangeKg: weightChange,
      weeklyWeightChangePercent: weeklyWeightChange,
      weightAdherencePercent: weightAdherence,
      averageSleepHours: averageSleepHours,
      sleepDaysLogged: sleepByDate.length,
      sleepTargetDays: sleepTargetDays,
      sleepAdherencePercent: sleepTargetDays == 0
          ? null
          : sleepAdherenceSum / sleepTargetDays * 100,
      sleepCoveragePercent: sleepTargetDays == 0
          ? null
          : sleepTargetDaysLogged / sleepTargetDays * 100,
      averageRpe: rpeSetsLogged == 0 ? null : rpeSum / rpeSetsLogged,
      rpeSetsLogged: rpeSetsLogged,
      rpeAdherencePercent: rpeExpectedSets == 0
          ? null
          : rpeAdherenceSum / rpeExpectedSets * 100,
      rpeCoveragePercent: rpeExpectedSets == 0
          ? null
          : rpeSetsLogged / rpeExpectedSets * 100,
      runCount: (run['run_count'] as num?)?.toInt() ?? 0,
      runDistanceMeters: (run['distance_meters'] as num?)?.toDouble() ?? 0,
      runMovingTimeSeconds: (run['moving_time_seconds'] as num?)?.toInt() ?? 0,
      longestRunMeters: (run['longest_run_meters'] as num?)?.toDouble() ?? 0,
      qualityRunCount: qualityRunCount,
      plannedRunSessions: hasRunTarget ? plannedRunSessions : null,
      plannedRunDistanceMeters: hasRunTarget ? plannedRunDistance : null,
      plannedLongRunMeters: plannedLongRun,
      plannedQualityRunSessions: hasRunTarget ? plannedQualityRuns : null,
    );
  }

  /// How many days of the week starting at [weekStart] fall inside
  /// [start]..[end]. Used to pro-rate weekly targets over a partial week.
  static int _daysOfWeekInRange(
    DateTime weekStart,
    DateTime start,
    DateTime end,
  ) {
    var count = 0;
    for (var i = 0; i < 7; i++) {
      final day = addDays(weekStart, i);
      if (!day.isBefore(start) && !day.isAfter(end)) count++;
    }
    return count;
  }

  Future<PeriodizationMetrics> getWeekMetrics(
    PeriodizationPhase phase,
    DateTime weekStart,
  ) => getPhaseMetrics(
    phase,
    rangeStart: mondayOf(weekStart).isBefore(phase.startDate)
        ? phase.startDate
        : mondayOf(weekStart),
    rangeEnd: addDays(mondayOf(weekStart), 6).isAfter(phase.endDate)
        ? phase.endDate
        : addDays(mondayOf(weekStart), 6),
  );

  static double _adherenceScore(
    double? actual,
    double expected, {
    double toleranceFloor = 1,
  }) {
    if (actual == null || !actual.isFinite || !expected.isFinite) return 0;
    final denominator = math.max(expected.abs(), toleranceFloor);
    return math.max(0, 1 - (actual - expected).abs() / denominator);
  }

  static double? _weightKg(Map<String, Object?> row) {
    final value = (row['value'] as num?)?.toDouble();
    if (value == null) return null;
    final unit = (row['unit'] as String? ?? 'kg').toLowerCase();
    return unit == 'lb' || unit == 'lbs' ? value * 0.45359237 : value;
  }
}
