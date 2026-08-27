import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_plan_templates.dart';

bool _isQuality(RunWorkoutKind kind) =>
    kind == RunWorkoutKind.interval ||
    kind == RunWorkoutKind.tempo ||
    kind == RunWorkoutKind.fartlek ||
    kind == RunWorkoutKind.hills ||
    kind == RunWorkoutKind.progression;

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

    test('3-day weeks include quality plus easy plus long', () {
      final week = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        config(sessions: 3, days: const [2, 4, 7], intent: RunPlanIntent.pb),
      ).first;
      expect(week.any((s) => _isQuality(s.kind)), isTrue);
      expect(week.any((s) => s.kind == RunWorkoutKind.easy), isTrue);
      expect(week.any((s) => s.kind == RunWorkoutKind.long), isTrue);
    });

    test('4-day PB keeps two quality days without adjacency', () {
      final week = RunPlanComposer.compose(
        RunPlanTemplates.tenK,
        config(sessions: 4, days: const [1, 3, 5, 7], intent: RunPlanIntent.pb),
      ).first;
      final qualityDays = week
          .where((s) => _isQuality(s.kind))
          .map((s) => s.dayOfWeek)
          .toSet()
          .toList();
      expect(qualityDays.length, greaterThanOrEqualTo(2));
      final gap = (qualityDays[0] - qualityDays[1]).abs();
      expect(gap == 1 || gap == 6, isFalse);
    });

    test('finish intent still includes VO2 intervals across the plan', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.tenK,
        config(
          sessions: 4,
          days: const [2, 4, 5, 7],
          intent: RunPlanIntent.finish,
        ),
      );
      final hasIntervals = schedule.any(
        (week) => week.any((s) => s.kind == RunWorkoutKind.interval),
      );
      final hasTempo = schedule.any(
        (week) => week.any((s) => s.kind == RunWorkoutKind.tempo),
      );
      expect(hasIntervals, isTrue);
      expect(hasTempo, isTrue);
    });

    test('quality stimuli rotate beyond only easy and long', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        config(),
      );
      final kinds = schedule.expand((w) => w).map((s) => s.kind).toSet();
      expect(kinds.contains(RunWorkoutKind.interval), isTrue);
      expect(kinds.contains(RunWorkoutKind.tempo), isTrue);
      expect(
        kinds.contains(RunWorkoutKind.fartlek) ||
            kinds.contains(RunWorkoutKind.hills) ||
            kinds.contains(RunWorkoutKind.progression),
        isTrue,
      );
    });

    test('continuous race plans get quality after intro weeks', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.firstFiveK,
        config(
          sessions: 3,
          days: const [2, 5, 7],
          intent: RunPlanIntent.finish,
        ),
      );
      // First week is intro (aerobic only).
      expect(schedule.first.every((s) => !_isQuality(s.kind)), isTrue);
      // Later build weeks must include quality — not just easy + long.
      final later = schedule.skip(2).take(4);
      expect(later.any((week) => week.any((s) => _isQuality(s.kind))), isTrue);
    });

    test('recovery week drops to a single soft quality session', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        config(),
      );
      // Week index 3 is recovery (w > 0 && w % 4 == 3).
      expect(schedule[3].where((s) => _isQuality(s.kind)), hasLength(1));
      expect(
        schedule[2].where((s) => _isQuality(s.kind)).length,
        greaterThanOrEqualTo(2),
      );
    });

    test('taper weeks shrink long-run volume before race', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        config(),
      );
      double longOf(List<RunPlanTemplateWorkout> week) => week
          .firstWhere(
            (s) =>
                s.kind == RunWorkoutKind.long ||
                s.kind == RunWorkoutKind.race ||
                s.kind == RunWorkoutKind.progression,
          )
          .targetDistanceMeters!;
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
      final interval = schedule
          .expand((w) => w)
          .firstWhere((s) => s.kind == RunWorkoutKind.interval);
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
      final long = week.firstWhere(
        (s) =>
            s.kind == RunWorkoutKind.long ||
            s.kind == RunWorkoutKind.progression,
      );
      expect(long.dayOfWeek, 7);
    });

    test('run-walk expands to the selected days', () {
      final week = RunPlanComposer.compose(
        RunPlanTemplates.runWalk,
        config(sessions: 4, days: const [1, 2, 4, 6]),
      ).first;
      expect(week, hasLength(4));
      expect(week.every((s) => s.kind == RunWorkoutKind.easy), isTrue);
    });

    test('beginner and return plans are capped at four days a week', () {
      // Bone and tendon adaptation lags the cardiovascular system: a brand-new
      // or returning runner must not be offered a fifth impact day.
      for (final template in [
        RunPlanTemplates.runWalk,
        RunPlanTemplates.returnToRunning,
        RunPlanTemplates.firstFiveK,
      ]) {
        expect(template.allowedSessionsPerWeek, isNot(contains(5)));
      }
    });
  });
}
