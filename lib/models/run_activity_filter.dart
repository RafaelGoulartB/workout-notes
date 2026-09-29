import 'package:workout_notes/models/cardio_activity_type.dart';

/// Row-level criteria for querying completed cardio activities in SQL.
class RunActivityFilter {
  final List<CardioActivityType>? types;
  final DateTime? startedFrom;
  final DateTime? startedBefore;
  final double? minDistanceMeters;
  final double? maxDistanceMeters;

  /// Only activities that completed a running-plan session.
  final bool onlyPlanWorkouts;

  /// Free text matched against the title and the notes.
  final String query;

  const RunActivityFilter({
    this.types,
    this.startedFrom,
    this.startedBefore,
    this.minDistanceMeters,
    this.maxDistanceMeters,
    this.onlyPlanWorkouts = false,
    this.query = '',
  });

  static const all = RunActivityFilter();
}

/// Count / distance / moving time of a set of activities.
class RunActivityTotals {
  final int count;
  final double distanceMeters;
  final int movingTimeSeconds;

  const RunActivityTotals({
    this.count = 0,
    this.distanceMeters = 0,
    this.movingTimeSeconds = 0,
  });

  static const empty = RunActivityTotals();
}

/// Presets shown by the history screen's type chips.
enum RunHistoryType {
  all,
  run,
  treadmill,
  bike;

  List<CardioActivityType>? get cardioTypes => switch (this) {
    RunHistoryType.all => null,
    RunHistoryType.run => const [CardioActivityType.running],
    RunHistoryType.treadmill => const [CardioActivityType.treadmill],
    RunHistoryType.bike => const [CardioActivityType.stationaryBike],
  };
}

enum RunHistoryPeriod {
  all,
  last30Days,
  last90Days,
  thisYear;

  DateTime? startFor(DateTime now) => switch (this) {
    RunHistoryPeriod.all => null,
    RunHistoryPeriod.last30Days => DateTime(now.year, now.month, now.day - 29),
    RunHistoryPeriod.last90Days => DateTime(now.year, now.month, now.day - 89),
    RunHistoryPeriod.thisYear => DateTime(now.year, 1, 1),
  };
}

enum RunHistoryDistance {
  any,
  under5,
  from5to10,
  over10;

  double? get minMeters => switch (this) {
    RunHistoryDistance.any || RunHistoryDistance.under5 => null,
    RunHistoryDistance.from5to10 => 5000,
    RunHistoryDistance.over10 => 10000,
  };

  double? get maxMeters => switch (this) {
    RunHistoryDistance.any || RunHistoryDistance.over10 => null,
    RunHistoryDistance.under5 => 5000,
    RunHistoryDistance.from5to10 => 10000,
  };
}

/// User-facing filter state of the history screen.
class RunHistoryFilter {
  final RunHistoryType type;
  final RunHistoryPeriod period;
  final RunHistoryDistance distance;
  final bool onlyPlan;
  final String query;

  const RunHistoryFilter({
    this.type = RunHistoryType.all,
    this.period = RunHistoryPeriod.all,
    this.distance = RunHistoryDistance.any,
    this.onlyPlan = false,
    this.query = '',
  });

  /// True when anything narrows the list (the search text counts).
  bool get isActive =>
      type != RunHistoryType.all ||
      period != RunHistoryPeriod.all ||
      distance != RunHistoryDistance.any ||
      onlyPlan ||
      query.trim().isNotEmpty;

  /// Number of narrowing options excluding the free-text search.
  int get activeOptionCount =>
      (type != RunHistoryType.all ? 1 : 0) +
      (period != RunHistoryPeriod.all ? 1 : 0) +
      (distance != RunHistoryDistance.any ? 1 : 0) +
      (onlyPlan ? 1 : 0);

  RunHistoryFilter copyWith({
    RunHistoryType? type,
    RunHistoryPeriod? period,
    RunHistoryDistance? distance,
    bool? onlyPlan,
    String? query,
  }) => RunHistoryFilter(
    type: type ?? this.type,
    period: period ?? this.period,
    distance: distance ?? this.distance,
    onlyPlan: onlyPlan ?? this.onlyPlan,
    query: query ?? this.query,
  );

  RunActivityFilter toQuery(DateTime now) => RunActivityFilter(
    types: type.cardioTypes,
    startedFrom: period.startFor(now),
    minDistanceMeters: distance.minMeters,
    maxDistanceMeters: distance.maxMeters,
    onlyPlanWorkouts: onlyPlan,
    query: query.trim(),
  );
}
