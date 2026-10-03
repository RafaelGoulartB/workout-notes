import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/goal.dart';

/// Wraps [home] in a localized [MaterialApp] (English unless [locale] says
/// otherwise).
Widget goalsApp(Widget home, {Locale locale = const Locale('en')}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );
}

/// Loads the date symbols the screens format with (`pt_BR` is hard-coded in
/// several body/goal widgets).
Future<void> initDateSymbolsForTests() async {
  await initializeDateFormatting('en_US');
  await initializeDateFormatting('pt_BR');
}

/// Lets real async SQLite work finish, then pumps the frames it scheduled.
Future<void> settleDb(WidgetTester tester, {int rounds = 6}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Pumps until [finder] matches (or gives up after a few seconds).
Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 100; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Builds a [Goal] with sensible defaults for UI tests.
Goal sampleGoal({
  String id = 'g1',
  String title = '',
  GoalScope scope = GoalScope.anaerobic,
  GoalMetric metric = GoalMetric.volume,
  GoalPeriod period = GoalPeriod.weekly,
  double target = 1000,
  bool isActive = true,
  int? color,
  DateTime? createdAt,
}) => Goal(
  id: id,
  title: title,
  scope: scope,
  metric: metric,
  period: period,
  targetValue: target,
  createdAt: createdAt ?? DateTime(2026, 1, 1),
  isActive: isActive,
  color: color,
);

/// Inserts the categories/exercises the goal queries join against.
Future<void> seedGoalExercises(Database db) async {
  await db.insert('exercise_categories', {
    'id': 'chest',
    'name': 'Chest',
    'color': 1,
    'energy_system': 'anaerobic',
  });
  await db.insert('exercise_categories', {
    'id': 'cardio',
    'name': 'Cardio',
    'color': 2,
    'energy_system': 'aerobic',
  });
  for (final (id, cat) in [('bench', 'chest'), ('treadmill', 'cardio')]) {
    await db.insert('exercises', {
      'id': id,
      'name': id,
      'category_id': cat,
      'created_at': '2026-01-01T00:00:00.000',
    });
  }
}

var _setSequence = 0;

/// Inserts a finished workout on [date] (`yyyy-MM-dd`) holding one performed
/// set of [exerciseId].
Future<void> seedFinishedWorkout(
  Database db, {
  required String id,
  required String date,
  String exerciseId = 'bench',
  double? weight = 100,
  int? reps = 10,
  double? distance,
  int? seconds,
}) async {
  await db.insert('workouts', {
    'id': id,
    'date': date,
    'start_time': '${date}T08:00:00.000',
    'end_time': '${date}T09:00:00.000',
    'created_at': '${date}T07:00:00.000',
  });
  final entryId = 'entry-$id';
  await db.insert('exercise_entries', {
    'id': entryId,
    'workout_id': id,
    'exercise_id': exerciseId,
    'order_index': 0,
  });
  await db.insert('sets', {
    'id': 'set-${_setSequence++}',
    'exercise_entry_id': entryId,
    'weight': weight,
    'reps': reps,
    'distance': distance,
    'time_seconds': seconds,
    'is_complete': 1,
    'is_warmup': 0,
    'order_index': 0,
  });
}

/// Gives the test view a [size] in logical pixels (device pixel ratio 1) and
/// restores the defaults when the test ends.
void useLogicalViewSize(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
