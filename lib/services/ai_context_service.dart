// Read-only queries built for the AI Coach may run SQL directly (a documented
// exception to the repository-only rule); writes never happen in this file.
import 'package:flutter/foundation.dart';
import 'package:workout_notes/database/database_helper.dart';
import 'package:workout_notes/models/ai_tool_domain.dart';
import 'package:workout_notes/repositories/periodization_repository.dart';
import 'package:workout_notes/services/effective_nutrition_goal_service.dart';
import 'package:workout_notes/utils/date_utils.dart';
import 'package:workout_notes/utils/duration_format.dart';

/// Builds the compact "today" snapshot injected into the stable part of every
/// request: the facts most questions need (plan of the day, latest activity,
/// weight, goals, last night), so common questions are answered without a
/// tool round.
///
/// Content only changes when the day or the underlying data changes, which
/// keeps the provider's prompt cache warm across turns. Nothing intraday-
/// volatile (food eaten so far, time of day) goes here: the time travels with
/// each user message instead.
class AiContextService {
  final DatabaseHelper db;
  final DateTime Function() _now;

  AiContextService({DatabaseHelper? db, DateTime Function()? now})
    : db = db ?? DatabaseHelper.instance,
      _now = now ?? DateTime.now;

  static const Duration _kTtl = Duration(seconds: 60);

  _Cached? _cache;

  /// Snapshot text (a few short lines) for [domains]; empty sections are
  /// omitted. Cached for a minute per domain set.
  Future<String> buildSnapshot({required Set<AiToolDomain> domains}) async {
    final now = _now();
    final key = (domains.map((d) => d.name).toList()..sort()).join(',');
    final cached = _cache;
    if (cached != null &&
        cached.key == key &&
        now.difference(cached.builtAt) < _kTtl &&
        isSameDay(cached.builtAt, now)) {
      return cached.text;
    }
    final text = await _build(now, domains);
    _cache = _Cached(builtAt: now, key: key, text: text);
    return text;
  }

  void invalidate() => _cache = null;

  Future<String> _build(DateTime now, Set<AiToolDomain> domains) async {
    final today = dayOf(now);
    final lines = <String>[
      'today: ${dateKey(today)} (${_weekday(today.weekday)})',
    ];
    Future<void> section(Future<List<String>> Function() load) async {
      try {
        lines.addAll(await load());
      } catch (error) {
        debugPrint('AI snapshot section failed: $error');
      }
    }

    await section(_units);
    if (domains.contains(AiToolDomain.planning) ||
        domains.contains(AiToolDomain.nutrition)) {
      await section(() => _plan(today, domains));
    }
    if (domains.contains(AiToolDomain.workouts)) {
      await section(() => _workouts(today));
    }
    if (domains.contains(AiToolDomain.running)) {
      await section(() => _running(today));
    }
    if (domains.contains(AiToolDomain.body)) {
      await section(() => _weight(today));
    }
    if (domains.contains(AiToolDomain.goals)) {
      await section(_goals);
    }
    if (domains.contains(AiToolDomain.sleep)) {
      await section(() => _sleep(today));
    }
    return lines.join('\n');
  }

  Future<List<String>> _units() async {
    final km = await db.settingsRepo.getIsDistanceKm();
    return ['units: kg, ${km ? 'km' : 'mi'}'];
  }

  Future<List<String>> _plan(DateTime today, Set<AiToolDomain> domains) async {
    final out = <String>[];
    if (domains.contains(AiToolDomain.planning)) {
      final dayPlan = await db.periodizationRepo.getDayPlan(today);
      if (dayPlan != null) {
        final day = dayPlan.day;
        final parts = <String>[
          if (day.strength) 'strength',
          if (day.run)
            day.runs.isEmpty
                ? 'run'
                : 'run: ${day.runs.map((r) => r.name).join(' + ')}',
        ];
        out.add(
          'plan: phase "${dayPlan.phase.name}"'
          '${dayPlan.phase.templateKey == null ? '' : ' (${dayPlan.phase.templateKey})'}'
          ' week ${dayPlan.weekNumber}/${dayPlan.totalWeeks}; today '
          '${dayPlan.trainingDay == false
              ? 'rest day'
              : parts.isEmpty
              ? 'no session planned'
              : parts.join(', ')}',
        );
      }
    }
    if (domains.contains(AiToolDomain.nutrition)) {
      final effective = await EffectiveNutritionGoalService.resolve(
        date: today,
      );
      final goal = effective.goal;
      if (goal != null && (goal.calories != null || goal.proteinG != null)) {
        out.add(
          'nutrition target today: '
          '${[if (goal.calories != null) '${goal.calories!.round()} kcal', if (goal.proteinG != null) 'protein ${goal.proteinG!.round()} g', if (goal.carbsG != null) 'carbs ${goal.carbsG!.round()} g', if (goal.fatG != null) 'fat ${goal.fatG!.round()} g'].join(', ')}'
          '${effective.fromPlan ? ' (from plan${effective.trainingDay == null
                    ? ''
                    : effective.trainingDay!
                    ? ', training day'
                    : ', rest day'})' : ''}',
        );
      }
    }
    return out;
  }

  Future<List<String>> _workouts(DateTime today) async {
    final raw = await db.database;
    final out = <String>[];
    final last = await raw.rawQuery(
      '''
      SELECT w.date, w.duration_seconds, r.name AS routine, rd.name AS day,
        (SELECT COUNT(*) FROM exercise_entries ee WHERE ee.workout_id = w.id)
          AS exercises
      FROM workouts w
      LEFT JOIN routines r ON r.id = w.routine_id
      LEFT JOIN routine_days rd ON rd.id = w.routine_day_id
      WHERE w.end_time IS NOT NULL AND w.date <= ?
      ORDER BY w.date DESC, w.end_time DESC LIMIT 1
      ''',
      [dateKey(today)],
    );
    if (last.isNotEmpty) {
      final row = last.first;
      final minutes = ((row['duration_seconds'] as num?) ?? 0) ~/ 60;
      final name = [
        row['routine'],
        row['day'],
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' / ');
      out.add(
        'last strength workout: ${row['date']}'
        '${name.isEmpty ? '' : ' "$name"'}, ${row['exercises']} exercises'
        '${minutes > 0 ? ', $minutes min' : ''}',
      );
    }
    final count = await raw.rawQuery(
      'SELECT COUNT(*) AS n FROM workouts WHERE end_time IS NOT NULL '
      'AND date >= ? AND date <= ?',
      [dateKey(addDays(today, -6)), dateKey(today)],
    );
    out.add('strength workouts last 7 days: ${count.first['n']}');
    final planned = await raw.rawQuery(
      '''
      SELECT w.date, r.name AS routine, rd.name AS day FROM workouts w
      LEFT JOIN routines r ON r.id = w.routine_id
      LEFT JOIN routine_days rd ON rd.id = w.routine_day_id
      WHERE w.end_time IS NULL AND w.date >= ? ORDER BY w.date LIMIT 1
      ''',
      [dateKey(today)],
    );
    if (planned.isNotEmpty) {
      final row = planned.first;
      final name = [
        row['routine'],
        row['day'],
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' / ');
      out.add(
        'next planned/in-progress workout: ${row['date']}'
        '${name.isEmpty ? '' : ' "$name"'}',
      );
    }
    return out;
  }

  Future<List<String>> _running(DateTime today) async {
    final raw = await db.database;
    final out = <String>[];
    final last = await raw.rawQuery('''
      SELECT started_at, activity_type, distance_meters, duration_seconds,
        moving_time_seconds
      FROM run_activities WHERE status = 'completed'
      ORDER BY started_at DESC LIMIT 1
      ''');
    if (last.isNotEmpty) {
      final row = last.first;
      final km = ((row['distance_meters'] as num?) ?? 0) / 1000;
      final moving = (row['moving_time_seconds'] as num?)?.toInt() ?? 0;
      final seconds = moving > 0
          ? moving
          : (row['duration_seconds'] as num?)?.toInt() ?? 0;
      out.add(
        'last ${row['activity_type'] == 'stationary_bike' ? 'bike session' : 'run'}: '
        '${(row['started_at'] as String).substring(0, 10)}, '
        '${km.toStringAsFixed(1)} km, ${seconds ~/ 60} min',
      );
    }
    final week = await raw.rawQuery(
      '''
      SELECT COUNT(*) AS n, COALESCE(SUM(distance_meters), 0) AS m
      FROM run_activities WHERE status = 'completed'
        AND activity_type = 'running' AND started_at >= ?
      ''',
      ['${dateKey(addDays(today, -6))}T00:00:00'],
    );
    final row = week.first;
    out.add(
      'runs last 7 days: ${row['n']} '
      '(${(((row['m'] as num?) ?? 0) / 1000).toStringAsFixed(1)} km)',
    );
    final next = await raw.rawQuery(
      '''
      SELECT sr.date, w.name FROM scheduled_runs sr
      LEFT JOIN run_plan_workouts w ON w.id = sr.run_plan_workout_id
      WHERE sr.status = 'planned' AND sr.date >= ? ORDER BY sr.date LIMIT 1
      ''',
      [dateKey(today)],
    );
    if (next.isNotEmpty) {
      out.add(
        'next planned run: ${next.first['date']}'
        '${next.first['name'] == null ? '' : ' "${next.first['name']}"'}',
      );
    }
    return out;
  }

  Future<List<String>> _weight(DateTime today) async {
    final raw = await db.database;
    final rows = await raw.rawQuery(
      '''
      SELECT value, unit, date FROM body_measurements
      WHERE type = 'weight' AND date <= ? ORDER BY date DESC, created_at DESC
      LIMIT 1
      ''',
      [dateKey(today)],
    );
    if (rows.isEmpty) return const [];
    final latest = rows.first;
    final value = (latest['value'] as num).toDouble();
    final before = await raw.rawQuery(
      '''
      SELECT value FROM body_measurements
      WHERE type = 'weight' AND date <= ? ORDER BY date DESC LIMIT 1
      ''',
      [dateKey(addDays(today, -28))],
    );
    final delta = before.isEmpty
        ? null
        : value - (before.first['value'] as num).toDouble();
    return [
      'latest weight: ${value.toStringAsFixed(1)} ${latest['unit'] ?? 'kg'} '
          'on ${latest['date']}'
          '${delta == null ? '' : ' (${delta >= 0 ? '+' : ''}${delta.toStringAsFixed(1)} vs 4 weeks before)'}',
    ];
  }

  Future<List<String>> _goals() async {
    final goals = await db.goalRepo.getAll(activeOnly: true);
    if (goals.isEmpty) return const [];
    final progress = await db.goalRepo.getProgressForGoals(
      goals.take(5).toList(),
    );
    final parts = <String>[];
    for (final goal in goals.take(5)) {
      final p = progress[goal.id];
      parts.add(
        '"${goal.title}" ${goal.period.value} ${goal.metric.value}'
        '${p == null ? '' : ' ${(p.percent * 100).round()}%'}',
      );
    }
    return ['active goals: ${parts.join('; ')}'];
  }

  Future<List<String>> _sleep(DateTime today) async {
    final raw = await db.database;
    final rows = await raw.rawQuery(
      '''
      SELECT date, sleep_minutes, actual_sleep_minutes, estimated_sleep_minutes,
        time_in_bed_minutes
      FROM sleep_entries WHERE date <= ? ORDER BY date DESC LIMIT 1
      ''',
      [dateKey(today)],
    );
    if (rows.isEmpty) return const [];
    final row = rows.first;
    final minutes =
        (row['actual_sleep_minutes'] as num?) ??
        (row['estimated_sleep_minutes'] as num?) ??
        (row['sleep_minutes'] as num?);
    if (minutes == null) return const [];
    final m = minutes.toInt();
    return [
      'last sleep entry: ${row['date']}, ${DurationFormat.hhmm(m)} asleep',
    ];
  }

  static String _weekday(int weekday) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][weekday - 1];
}

class _Cached {
  final DateTime builtAt;
  final String key;
  final String text;
  const _Cached({required this.builtAt, required this.key, required this.text});
}
