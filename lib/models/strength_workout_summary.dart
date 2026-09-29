/// A muscle group (exercise category) as needed to label and colour charts.
class StrengthCategoryInfo {
  final String id;
  final String name;
  final String? localeKey;
  final int color;

  const StrengthCategoryInfo({
    required this.id,
    required this.name,
    required this.localeKey,
    required this.color,
  });

  /// Row shaped like a category query, for `ExerciseLocaleHelper`.
  Map<String, dynamic> get row => {
    'name': name,
    'locale_key': localeKey,
    'category_id': id,
  };
}

/// A finished gym workout reduced to what the hub needs. Volume and set
/// counts only include completed, non-warm-up sets of anaerobic exercises.
class StrengthWorkoutSummary {
  final String id;

  /// Local calendar day of the workout (time stripped).
  final DateTime date;
  final DateTime? startTime;
  final DateTime? endTime;
  final int durationSeconds;

  /// 0 when the user never rated the session.
  final int feelingRating;
  final String? routineId;
  final String? routineDayId;
  final String? routineDayName;
  final String? routineName;
  final double volumeKg;
  final int workingSets;
  final int exerciseCount;

  /// Categories trained, the one with the most sets first.
  final List<String> categoryIds;

  const StrengthWorkoutSummary({
    required this.id,
    required this.date,
    this.startTime,
    this.endTime,
    this.durationSeconds = 0,
    this.feelingRating = 0,
    this.routineId,
    this.routineDayId,
    this.routineDayName,
    this.routineName,
    this.volumeKg = 0,
    this.workingSets = 0,
    this.exerciseCount = 0,
    this.categoryIds = const [],
  });

  String? get dominantCategoryId =>
      categoryIds.isEmpty ? null : categoryIds.first;

  /// Routine day name, else the routine name; null for a free workout.
  String? get routineLabel {
    final day = routineDayName?.trim();
    if (day != null && day.isNotEmpty) return day;
    final routine = routineName?.trim();
    if (routine != null && routine.isNotEmpty) return routine;
    return null;
  }
}

/// Working sets and volume of one muscle group over a period.
class StrengthMuscleLoad {
  final StrengthCategoryInfo category;
  final int sets;
  final double volumeKg;

  const StrengthMuscleLoad({
    required this.category,
    required this.sets,
    required this.volumeKg,
  });
}

/// A planned (future-dated, unfinished) workout.
class StrengthUpcomingWorkout {
  final String id;
  final DateTime date;
  final String? routineDayName;
  final String? routineName;
  final int exerciseCount;

  const StrengthUpcomingWorkout({
    required this.id,
    required this.date,
    this.routineDayName,
    this.routineName,
    this.exerciseCount = 0,
  });

  String? get label {
    final day = routineDayName?.trim();
    if (day != null && day.isNotEmpty) return day;
    final routine = routineName?.trim();
    if (routine != null && routine.isNotEmpty) return routine;
    return null;
  }
}

/// A routine day to be trained: what it holds and how long it should take.
class StrengthRoutineDayInfo {
  final String routineId;
  final String routineName;
  final String routineDayId;
  final String dayName;
  final int exerciseCount;

  /// Muscle groups of the day, most exercises first.
  final List<StrengthCategoryInfo> categories;

  /// Estimated duration; 0 when the day has no planned sets.
  final int estimatedSeconds;

  const StrengthRoutineDayInfo({
    required this.routineId,
    required this.routineName,
    required this.routineDayId,
    required this.dayName,
    required this.exerciseCount,
    required this.categories,
    required this.estimatedSeconds,
  });
}

/// A routine day reference (no exercises loaded).
class StrengthRoutineDayRef {
  final String routineId;
  final String routineName;
  final String dayId;
  final String dayName;
  final int orderIndex;

  const StrengthRoutineDayRef({
    required this.routineId,
    required this.routineName,
    required this.dayId,
    required this.dayName,
    required this.orderIndex,
  });
}

/// A finished gym workout reduced to its day and length, for cheap weekly
/// overviews that do not need volume or muscles.
class StrengthWorkoutStamp {
  final DateTime date;
  final int durationSeconds;

  const StrengthWorkoutStamp({
    required this.date,
    required this.durationSeconds,
  });
}
