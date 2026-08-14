import 'dart:math' as math;

import 'package:sqflite/sqflite.dart';

const devDataPrefix = 'dev-sample:';

/// Shared clock and randomness for one generation run.
///
/// Production code never depends on this class. Tests can inject [now] and
/// [randomSeed], while the debug button gets a fresh scenario on every tap.
class TestDataContext {
  final DatabaseExecutor database;
  final DateTime now;
  final DateTime start;
  final math.Random random;

  TestDataContext({
    required this.database,
    required DateTime now,
    required int historyDays,
    required int randomSeed,
  }) : now = DateTime(now.year, now.month, now.day, now.hour, now.minute),
       start = DateTime(
         now.year,
         now.month,
         now.day,
       ).subtract(Duration(days: historyDays - 1)),
       random = math.Random(randomSeed);

  String id(String domain, Object value) => '$devDataPrefix$domain:$value';

  String date(DateTime value) => DateTime(
    value.year,
    value.month,
    value.day,
  ).toIso8601String().substring(0, 10);

  double jitter(double center, double spread) =>
      center + (random.nextDouble() * 2 - 1) * spread;
}

class TestDataReport {
  final int workouts;
  final int routines;
  final int measurements;
  final int sleepNights;
  final int monitoredNights;
  final int nutritionDays;
  final int meals;
  final int goals;
  final int periodizationPlans;
  final int periodizationPhases;
  final int periodizationCheckins;

  const TestDataReport({
    required this.workouts,
    required this.routines,
    required this.measurements,
    required this.sleepNights,
    required this.monitoredNights,
    required this.nutritionDays,
    required this.meals,
    required this.goals,
    required this.periodizationPlans,
    required this.periodizationPhases,
    required this.periodizationCheckins,
  });
}
