import 'package:workout_notes/repositories/base_repository.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Estimated one-rep max (Epley). Sets above [maxReps] reps are too far from
/// a single to predict it reliably and return null.
double? strengthE1rm(double weight, int reps, {int maxReps = 12}) {
  if (weight <= 0 || reps <= 0 || reps > maxReps) return null;
  if (reps == 1) return weight;
  return weight * (1 + reps / 30);
}

/// One completed working set of a finished workout, the unit every strength
/// statistic is built from.
class StrengthSetSample {
  final String workoutId;
  final DateTime date;
  final String exerciseId;
  final String exerciseName;
  final String? exerciseLocaleKey;
  final String categoryId;
  final double weight;
  final int reps;

  const StrengthSetSample({
    required this.workoutId,
    required this.date,
    required this.exerciseId,
    required this.exerciseName,
    required this.exerciseLocaleKey,
    required this.categoryId,
    required this.weight,
    required this.reps,
  });

  double? get e1rm => strengthE1rm(weight, reps);

  double get volume => weight * reps;

  /// Row shaped like an `exercises` query, for `ExerciseLocaleHelper`.
  Map<String, dynamic> get exerciseRow => {
    'name': exerciseName,
    'locale_key': exerciseLocaleKey,
    'category_id': categoryId,
  };
}

/// A finished workout that had strength work.
class StrengthWorkoutInfo {
  final String id;
  final DateTime date;
  final int? durationSeconds;
  final int? feeling;

  /// Whether [date] carries a real start time (older workouts only have a day).
  final bool hasTime;

  const StrengthWorkoutInfo({
    required this.id,
    required this.date,
    required this.durationSeconds,
    required this.feeling,
    this.hasTime = true,
  });
}

/// Best marks of one exercise.
class StrengthRecord {
  final String exerciseId;
  final String exerciseName;
  final String? exerciseLocaleKey;
  final String categoryId;

  /// Best estimated 1RM and the set that produced it.
  final double? bestE1rm;
  final double? bestE1rmWeight;
  final int? bestE1rmReps;
  final DateTime? bestE1rmDate;
  final String? bestE1rmWorkoutId;

  /// Heaviest weight lifted (any reps) and when.
  final double maxWeight;
  final int maxWeightReps;
  final DateTime maxWeightDate;
  final String maxWeightWorkoutId;

  /// Biggest single-session volume (kg) for this exercise.
  final double bestSessionVolume;
  final DateTime bestSessionVolumeDate;

  final int sessionCount;
  final DateTime lastDate;

  const StrengthRecord({
    required this.exerciseId,
    required this.exerciseName,
    required this.exerciseLocaleKey,
    required this.categoryId,
    required this.bestE1rm,
    required this.bestE1rmWeight,
    required this.bestE1rmReps,
    required this.bestE1rmDate,
    required this.bestE1rmWorkoutId,
    required this.maxWeight,
    required this.maxWeightReps,
    required this.maxWeightDate,
    required this.maxWeightWorkoutId,
    required this.bestSessionVolume,
    required this.bestSessionVolumeDate,
    required this.sessionCount,
    required this.lastDate,
  });

  Map<String, dynamic> get exerciseRow => {
    'name': exerciseName,
    'locale_key': exerciseLocaleKey,
    'category_id': categoryId,
  };
}

enum StrengthRecordKind { e1rm, weight }

/// A moment an exercise beat its own previous best.
class StrengthRecordEvent {
  final String exerciseId;
  final String exerciseName;
  final String? exerciseLocaleKey;
  final String categoryId;
  final StrengthRecordKind kind;
  final DateTime date;
  final String workoutId;
  final double weight;
  final int reps;

  /// New best (kg of e1RM or of load) and the one it beat (null = first).
  final double value;
  final double? previous;

  const StrengthRecordEvent({
    required this.exerciseId,
    required this.exerciseName,
    required this.exerciseLocaleKey,
    required this.categoryId,
    required this.kind,
    required this.date,
    required this.workoutId,
    required this.weight,
    required this.reps,
    required this.value,
    required this.previous,
  });

  double? get improvement => previous == null ? null : value - previous!;

  Map<String, dynamic> get exerciseRow => {
    'name': exerciseName,
    'locale_key': exerciseLocaleKey,
    'category_id': categoryId,
  };
}

/// Strength records computed from completed, non-warm-up, weighted sets of
/// finished workouts only (planned or abandoned sessions never count).
class StrengthRecordsRepository extends BaseRepository {
  /// All qualifying sets, oldest first. [from]/[to] bound the workout date
  /// (inclusive, `yyyy-MM-dd`). With [includeUnweighted] bodyweight and timed
  /// sets (no load) are returned too, for set counts and frequency; records
  /// leave them out.
  Future<List<StrengthSetSample>> loadSets({
    DateTime? from,
    DateTime? to,
    String? exerciseId,
    bool includeUnweighted = false,
  }) async {
    final database = await db;
    final rows = await database.rawQuery(
      '''
      SELECT w.id AS workout_id, w.date AS date, w.start_time AS start_time,
        e.id AS exercise_id, e.name AS exercise_name,
        e.locale_key AS locale_key, e.category_id AS category_id,
        s.weight AS weight, s.reps AS reps
      FROM sets s
      JOIN exercise_entries ee ON ee.id = s.exercise_entry_id
      JOIN workouts w ON w.id = ee.workout_id
      JOIN exercises e ON e.id = ee.exercise_id
      LEFT JOIN exercise_categories c ON c.id = e.category_id
      WHERE s.is_complete = 1
        AND IFNULL(s.is_warmup, 0) = 0
        AND ${includeUnweighted ? '(s.reps > 0 OR s.time_seconds > 0)' : 's.weight > 0 AND s.reps > 0'}
        AND w.end_time IS NOT NULL
        AND IFNULL(c.energy_system, 'anaerobic') = 'anaerobic'
        ${from == null ? '' : 'AND w.date >= ?'}
        ${to == null ? '' : 'AND w.date <= ?'}
        ${exerciseId == null ? '' : 'AND e.id = ?'}
      ORDER BY w.date ASC, w.start_time ASC, ee.order_index ASC, s.order_index ASC
      ''',
      [if (from != null) dateKey(from), if (to != null) dateKey(to), ?exerciseId],
    );
    return [
      for (final r in rows)
        StrengthSetSample(
          workoutId: r['workout_id'] as String,
          date:
              DateTime.tryParse(r['start_time'] as String? ?? '') ??
              DateTime.parse(r['date'] as String),
          exerciseId: r['exercise_id'] as String,
          exerciseName: r['exercise_name'] as String? ?? '',
          exerciseLocaleKey: r['locale_key'] as String?,
          categoryId: r['category_id'] as String? ?? '',
          weight: (r['weight'] as num?)?.toDouble() ?? 0,
          reps: (r['reps'] as num?)?.toInt() ?? 0,
        ),
    ];
  }

  /// Finished workouts with at least one strength working set, oldest first.
  Future<List<StrengthWorkoutInfo>> loadWorkouts({
    DateTime? from,
    DateTime? to,
  }) async {
    final database = await db;
    final rows = await database.rawQuery(
      '''
      SELECT w.id AS id, w.date AS date, w.start_time AS start_time,
        w.duration_seconds AS duration_seconds,
        w.feeling_rating AS feeling_rating
      FROM workouts w
      WHERE w.end_time IS NOT NULL
        ${from == null ? '' : 'AND w.date >= ?'}
        ${to == null ? '' : 'AND w.date <= ?'}
        AND EXISTS (
          SELECT 1 FROM exercise_entries ee
          JOIN exercises e ON e.id = ee.exercise_id
          LEFT JOIN exercise_categories c ON c.id = e.category_id
          JOIN sets s ON s.exercise_entry_id = ee.id
          WHERE ee.workout_id = w.id
            AND s.is_complete = 1 AND IFNULL(s.is_warmup, 0) = 0
            AND IFNULL(c.energy_system, 'anaerobic') = 'anaerobic')
      ORDER BY w.date ASC, w.start_time ASC
      ''',
      [if (from != null) dateKey(from), if (to != null) dateKey(to)],
    );
    return [
      for (final r in rows)
        StrengthWorkoutInfo(
          id: r['id'] as String,
          date:
              DateTime.tryParse(r['start_time'] as String? ?? '') ??
              DateTime.parse(r['date'] as String),
          durationSeconds: (r['duration_seconds'] as num?)?.toInt(),
          feeling: (r['feeling_rating'] as num?)?.toInt(),
          hasTime: DateTime.tryParse(r['start_time'] as String? ?? '') != null,
        ),
    ];
  }

  /// Best marks per exercise, sorted by best e1RM (then max weight).
  Future<List<StrengthRecord>> listRecords() async {
    return StrengthRecordsCalculator.records(await loadSets());
  }

  /// Personal bests in chronological order, newest first.
  Future<List<StrengthRecordEvent>> recentRecords({
    int limit = 10,
    DateTime? since,
  }) async {
    final events = StrengthRecordsCalculator.events(await loadSets());
    final filtered = since == null
        ? events
        : events.where((e) => !e.date.isBefore(since)).toList();
    return filtered.reversed.take(limit).toList();
  }

  /// Records set in a given workout (used by workout detail badges).
  Future<List<StrengthRecordEvent>> recordsInWorkout(String workoutId) async {
    final events = StrengthRecordsCalculator.events(await loadSets());
    return events.where((e) => e.workoutId == workoutId).toList();
  }
}

/// Pure calculations over [StrengthSetSample]s, unit-tested separately.
abstract final class StrengthRecordsCalculator {
  static List<StrengthRecord> records(List<StrengthSetSample> sets) {
    final byExercise = <String, List<StrengthSetSample>>{};
    for (final s in sets) {
      byExercise.putIfAbsent(s.exerciseId, () => []).add(s);
    }
    final result = <StrengthRecord>[];
    byExercise.forEach((id, list) {
      StrengthSetSample? bestE1rmSet;
      var bestE1rm = 0.0;
      var heaviest = list.first;
      final volumeBySession = <String, double>{};
      final dateBySession = <String, DateTime>{};
      for (final s in list) {
        final e = s.e1rm;
        if (e != null && e > bestE1rm) {
          bestE1rm = e;
          bestE1rmSet = s;
        }
        if (s.weight > heaviest.weight ||
            (s.weight == heaviest.weight && s.reps > heaviest.reps)) {
          heaviest = s;
        }
        volumeBySession[s.workoutId] =
            (volumeBySession[s.workoutId] ?? 0) + s.volume;
        dateBySession[s.workoutId] = s.date;
      }
      var bestVolumeSession = volumeBySession.keys.first;
      volumeBySession.forEach((w, v) {
        if (v > volumeBySession[bestVolumeSession]!) bestVolumeSession = w;
      });
      final first = list.first;
      result.add(
        StrengthRecord(
          exerciseId: id,
          exerciseName: first.exerciseName,
          exerciseLocaleKey: first.exerciseLocaleKey,
          categoryId: first.categoryId,
          bestE1rm: bestE1rmSet == null ? null : bestE1rm,
          bestE1rmWeight: bestE1rmSet?.weight,
          bestE1rmReps: bestE1rmSet?.reps,
          bestE1rmDate: bestE1rmSet?.date,
          bestE1rmWorkoutId: bestE1rmSet?.workoutId,
          maxWeight: heaviest.weight,
          maxWeightReps: heaviest.reps,
          maxWeightDate: heaviest.date,
          maxWeightWorkoutId: heaviest.workoutId,
          bestSessionVolume: volumeBySession[bestVolumeSession]!,
          bestSessionVolumeDate: dateBySession[bestVolumeSession]!,
          sessionCount: volumeBySession.length,
          lastDate: list.last.date,
        ),
      );
    });
    result.sort((a, b) {
      final e = (b.bestE1rm ?? 0).compareTo(a.bestE1rm ?? 0);
      return e != 0 ? e : b.maxWeight.compareTo(a.maxWeight);
    });
    return result;
  }

  /// Every time an exercise beat its previous best e1RM or heaviest weight,
  /// oldest first. The first session of an exercise sets a baseline and is
  /// not reported, so a brand-new exercise doesn't flood the list. Only the
  /// best set of a session per kind counts.
  static List<StrengthRecordEvent> events(List<StrengthSetSample> sets) {
    final bestE1rm = <String, double>{};
    final bestWeight = <String, double>{};
    final seenSessions = <String, Set<String>>{};
    final events = <StrengthRecordEvent>[];

    // Group per (workout, exercise) so one session yields at most one event
    // per kind, with its best set.
    final sessions = <String, List<StrengthSetSample>>{};
    final order = <String>[];
    for (final s in sets) {
      final key = '${s.workoutId}|${s.exerciseId}';
      if (!sessions.containsKey(key)) order.add(key);
      sessions.putIfAbsent(key, () => []).add(s);
    }

    for (final key in order) {
      final list = sessions[key]!;
      final first = list.first;
      final id = first.exerciseId;
      final isBaseline = (seenSessions[id] ?? const {}).isEmpty;
      seenSessions.putIfAbsent(id, () => {}).add(first.workoutId);

      StrengthSetSample? topE1rm;
      var topE1rmValue = 0.0;
      var topWeight = list.first;
      for (final s in list) {
        final e = s.e1rm;
        if (e != null && e > topE1rmValue) {
          topE1rmValue = e;
          topE1rm = s;
        }
        if (s.weight > topWeight.weight) topWeight = s;
      }

      StrengthRecordEvent event(
        StrengthRecordKind kind,
        StrengthSetSample s,
        double value,
        double? previous,
      ) => StrengthRecordEvent(
        exerciseId: id,
        exerciseName: s.exerciseName,
        exerciseLocaleKey: s.exerciseLocaleKey,
        categoryId: s.categoryId,
        kind: kind,
        date: s.date,
        workoutId: s.workoutId,
        weight: s.weight,
        reps: s.reps,
        value: value,
        previous: previous,
      );

      final prevE1rm = bestE1rm[id];
      if (topE1rm != null &&
          (prevE1rm == null || topE1rmValue > prevE1rm + 0.01)) {
        if (!isBaseline) {
          events.add(
            event(StrengthRecordKind.e1rm, topE1rm, topE1rmValue, prevE1rm),
          );
        }
        bestE1rm[id] = topE1rmValue;
      }
      final prevWeight = bestWeight[id];
      if (prevWeight == null || topWeight.weight > prevWeight + 0.01) {
        if (!isBaseline) {
          events.add(
            event(
              StrengthRecordKind.weight,
              topWeight,
              topWeight.weight,
              prevWeight,
            ),
          );
        }
        bestWeight[id] = topWeight.weight;
      }
    }
    return events;
  }
}
