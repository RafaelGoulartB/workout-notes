import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_plan_templates.dart';

void main() {
  RunPlanBuildConfig config({
    int sessions = 4,
    List<int> days = const [2, 4, 5, 7],
    RunPlanIntent intent = RunPlanIntent.pb,
    RunPlanIntensity intensity = RunPlanIntensity.standard,
    RunPlanPaceCalibration? calibration,
  }) => RunPlanBuildConfig(
    sessionsPerWeek: sessions,
    availableDays: days,
    intent: intent,
    intensity: intensity,
    calibration: calibration,
  );

  group('RunPlanComposer', () {
    test('maps sessions onto selected weekdays only', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        config(sessions: 3, days: const [1, 3, 6]),
      );
      for (final week in schedule) {
        expect(week, hasLength(3));
        final used = week.map((s) => s.dayOfWeek).toSet();
        expect(used, everyElement(isIn({1, 3, 6})));
        expect(used, hasLength(3));
      }
    });

    test('3-day PB alternates interval and tempo', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        config(sessions: 3, days: const [2, 4, 7], intent: RunPlanIntent.pb),
      );
      expect(
        schedule[0].any((s) => s.kind == RunWorkoutKind.interval),
        isTrue,
      );
      expect(
        schedule[1].any((s) => s.kind == RunWorkoutKind.tempo),
        isTrue,
      );
      expect(
        schedule[0].any((s) => s.kind == RunWorkoutKind.long),
        isTrue,
      );
    });

    test('4-day PB keeps interval and tempo without adjacent quality', () {
      final week = RunPlanComposer.compose(
        RunPlanTemplates.tenK,
        config(sessions: 4, days: const [1, 3, 5, 7], intent: RunPlanIntent.pb),
      ).first;
      final qualityDays = week
          .where(
            (s) =>
                s.kind == RunWorkoutKind.interval ||
                s.kind == RunWorkoutKind.tempo,
          )
          .map((s) => s.dayOfWeek)
          .toList();
      expect(qualityDays, hasLength(2));
      final gap = (qualityDays[0] - qualityDays[1]).abs();
      expect(gap == 1 || gap == 6, isFalse);
    });

    test('finish softens performance plans to a single tempo', () {
      final week = RunPlanComposer.compose(
        RunPlanTemplates.tenK,
        config(
          sessions: 4,
          days: const [2, 4, 5, 7],
          intent: RunPlanIntent.finish,
        ),
      ).first;
      expect(week.where((s) => s.kind == RunWorkoutKind.interval), isEmpty);
      expect(week.where((s) => s.kind == RunWorkoutKind.tempo), hasLength(1));
    });

    test('recovery week has lower easy volume than prior build week', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        config(),
      );
      double weekEasy(List<RunPlanTemplateWorkout> sessions) => sessions
          .where(
            (s) =>
                s.kind == RunWorkoutKind.easy ||
                s.kind == RunWorkoutKind.recovery,
          )
          .fold<double>(0, (sum, s) => sum + (s.targetDistanceMeters ?? 0));

      // Week index 3 is recovery (w > 0 && w % 4 == 3).
      expect(weekEasy(schedule[3]), lessThan(weekEasy(schedule[2])));
    });

    test('taper weeks shrink long-run volume before race', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        config(),
      );
      double longOf(List<RunPlanTemplateWorkout> week) => week
          .firstWhere(
            (s) =>
                s.kind == RunWorkoutKind.long || s.kind == RunWorkoutKind.race,
          )
          .targetDistanceMeters!;
      // Peak build week vs first taper week (last two are taper; last is race).
      final peak = schedule
          .take(schedule.length - 2)
          .map(longOf)
          .reduce((a, b) => a > b ? a : b);
      final taper = longOf(schedule[schedule.length - 2]);
      expect(taper, lessThan(peak));
    });

    test('aggressive intensity increases volume vs conservative', () {
      final soft = RunPlanComposer.compose(
        RunPlanTemplates.base,
        config(
          sessions: 3,
          days: const [2, 5, 7],
          intent: RunPlanIntent.finish,
          intensity: RunPlanIntensity.conservative,
        ),
      ).first;
      final hard = RunPlanComposer.compose(
        RunPlanTemplates.base,
        config(
          sessions: 3,
          days: const [2, 5, 7],
          intent: RunPlanIntent.finish,
          intensity: RunPlanIntensity.aggressive,
        ),
      ).first;
      final softKm = soft.fold<double>(
        0,
        (s, w) => s + (w.targetDistanceMeters ?? 0),
      );
      final hardKm = hard.fold<double>(
        0,
        (s, w) => s + (w.targetDistanceMeters ?? 0),
      );
      expect(hardKm, greaterThan(softKm));
    });

    test('calibration writes paces onto quality steps', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        config(
          calibration: const RunPlanPaceCalibration(
            distanceMeters: 5000,
            timeSeconds: 25 * 60,
          ),
        ),
      );
      final interval = schedule.first.firstWhere(
        (s) => s.kind == RunWorkoutKind.interval,
      );
      expect(interval.targetPaceSecPerKm, isNotNull);
      final work = interval.steps.firstWhere((s) => s.role == RunStepRole.work);
      expect(work.targetPaceMinSecPerKm, isNotNull);
      expect(work.targetPaceMaxSecPerKm, isNotNull);
    });

    test('long prefers Sunday when available', () {
      final week = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        config(sessions: 4, days: const [2, 4, 5, 7]),
      ).first;
      final long = week.firstWhere((s) => s.kind == RunWorkoutKind.long);
      expect(long.dayOfWeek, 7);
    });

    test('run-walk expands to five selected days', () {
      final week = RunPlanComposer.compose(
        RunPlanTemplates.runWalk,
        config(sessions: 5, days: const [1, 2, 3, 4, 5]),
      ).first;
      expect(week, hasLength(5));
      expect(week.every((s) => s.kind == RunWorkoutKind.easy), isTrue);
    });
  });
}
