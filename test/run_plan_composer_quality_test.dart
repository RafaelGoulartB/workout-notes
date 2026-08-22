import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_pace_calculator.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_plan_templates.dart';

/// Training-quality invariants for generated plans.
///
/// Every test here pins a rule that a coach would apply, and each one exists
/// because the composer once broke it.

bool _isQuality(RunWorkoutKind kind) =>
    kind == RunWorkoutKind.interval ||
    kind == RunWorkoutKind.tempo ||
    kind == RunWorkoutKind.fartlek ||
    kind == RunWorkoutKind.hills ||
    kind == RunWorkoutKind.progression;

bool _isHard(RunWorkoutKind kind) =>
    kind == RunWorkoutKind.tempo ||
    kind == RunWorkoutKind.fartlek ||
    kind == RunWorkoutKind.hills ||
    kind == RunWorkoutKind.progression;

/// Every session reports its total planned distance, so weekly volume is just a
/// sum. Quality sessions include warm-up, jog recoveries and cool-down.
double _km(RunPlanTemplateWorkout s) => (s.targetDistanceMeters ?? 0) / 1000;

double _weekKm(List<RunPlanTemplateWorkout> week) =>
    week.fold<double>(0, (a, s) => a + _km(s));

RunPlanTemplateWorkout _longest(List<RunPlanTemplateWorkout> week) =>
    week.reduce((a, b) => _km(a) >= _km(b) ? a : b);

const _calibration = RunPlanPaceCalibration(
  distanceMeters: 5000,
  timeSeconds: 25 * 60,
);

RunPlanBuildConfig _config({
  int sessions = 4,
  List<int> days = const [2, 4, 5, 7],
  RunPlanIntent intent = RunPlanIntent.pb,
  bool calibrated = true,
  double? currentWeeklyKm,
}) => RunPlanBuildConfig(
  sessionsPerWeek: sessions,
  availableDays: days,
  intent: intent,
  calibration: calibrated ? _calibration : null,
  currentWeeklyKm: currentWeeklyKm,
);

void main() {
  group('scheduling integrity', () {
    test('never schedules two sessions on the same weekday', () {
      // The old slot map handed one weekday to two quality kinds whenever the
      // rotation put e.g. fartlek and tempo in the same week, silently dropping
      // a training day and doubling up another.
      for (final template in RunPlanTemplates.all) {
        for (final days in const [
          [2, 4, 7],
          [1, 3, 5, 7],
          [1, 2, 3, 5, 7],
          [3, 5, 6],
        ]) {
          if (!template.allowedSessionsPerWeek.contains(days.length)) continue;
          for (final intent in RunPlanIntent.values) {
            final schedule = RunPlanComposer.compose(
              template,
              _config(sessions: days.length, days: days, intent: intent),
            );
            for (final week in schedule) {
              final used = week.map((s) => s.dayOfWeek).toList();
              expect(
                used.toSet(),
                hasLength(used.length),
                reason: '${template.key} on $days repeated a weekday: $used',
              );
            }
          }
        }
      }
    });

    test('pace ranges always put the faster bound first', () {
      // Pace is seconds per km, so the faster bound is the smaller number. A
      // step with min > max renders as "5:16-4:50".
      for (final template in RunPlanTemplates.all) {
        for (final session
            in RunPlanComposer.compose(
              template,
              _config(),
            ).expand((w) => w)) {
          for (final step in session.steps) {
            final min = step.targetPaceMinSecPerKm;
            final max = step.targetPaceMaxSecPerKm;
            if (min == null || max == null) continue;
            expect(
              min,
              lessThanOrEqualTo(max),
              reason: '${template.key} / ${session.name} / ${step.role.name}',
            );
          }
        }
      }
    });
  });

  group('volume progression', () {
    test('the long run is the longest session of its week', () {
      for (final template in RunPlanTemplates.all) {
        for (final sessions in template.allowedSessionsPerWeek) {
          final schedule = RunPlanComposer.compose(
            template,
            _config(
              sessions: sessions,
              days: const [1, 3, 4, 5, 7].sublist(0, sessions),
            ),
          );
          for (final week in schedule) {
            expect(
              _longest(week).kind,
              isIn({
                RunWorkoutKind.long,
                RunWorkoutKind.race,
                RunWorkoutKind.progression,
                RunWorkoutKind.easy, // run/walk plans have no long run
              }),
              reason:
                  '${template.key}/$sessions: "${_longest(week).name}" '
                  'outran the long run',
            );
          }
        }
      }
    });

    test('long run stays a bounded share of the week', () {
      // A 32 km long run inside a 46 km week is how the old composer built
      // marathon plans nobody could absorb.
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.marathon,
        _config(),
      );
      for (var i = 0; i < schedule.length - 1; i++) {
        expect(
          _km(_longest(schedule[i])) / _weekKm(schedule[i]),
          lessThanOrEqualTo(0.5),
          reason: 'week ${i + 1} long-run share',
        );
      }
    });

    test('weekly volume grows at most ~10% outside recovery rebounds', () {
      final volumes = RunPlanComposer.compose(
        RunPlanTemplates.marathon,
        _config(),
      ).map(_weekKm).toList();
      // The final week carries the race itself, which is not a training ramp.
      // Every other rise is either a build step or a rebound from a deliberate
      // down week back onto the build line.
      for (var i = 2; i < volumes.length - 1; i++) {
        if (volumes[i - 1] < volumes[i - 2]) continue;
        expect(
          volumes[i] / volumes[i - 1],
          lessThanOrEqualTo(1.12),
          reason:
              'week ${i + 1} jumped from ${volumes[i - 1].toStringAsFixed(1)} '
              'to ${volumes[i].toStringAsFixed(1)} km',
        );
      }
    });

    test('current weekly volume anchors week 1', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.firstFiveK,
        _config(
          sessions: 3,
          days: const [2, 4, 7],
          calibrated: false,
          currentWeeklyKm: 12,
        ),
      );
      expect(_weekKm(schedule.first), closeTo(12, 1.5));
    });
  });

  group('race week and taper', () {
    test('race week carries only a sharpener, easy days and the race', () {
      for (final template in [
        RunPlanTemplates.marathon,
        RunPlanTemplates.half,
        RunPlanTemplates.tenK,
        RunPlanTemplates.firstFiveK,
      ]) {
        final schedule = RunPlanComposer.compose(template, _config());
        final raceWeek = schedule.last;
        expect(
          raceWeek.where((s) => s.kind == RunWorkoutKind.race),
          hasLength(1),
          reason: '${template.key} race week',
        );
        expect(
          raceWeek.any((s) => _isHard(s.kind)),
          isFalse,
          reason: '${template.key} race week still holds a hard session',
        );
        final peak = schedule
            .take(schedule.length - 1)
            .map(_weekKm)
            .reduce((a, b) => a > b ? a : b);
        final support =
            _weekKm(raceWeek) -
            _km(raceWeek.firstWhere((s) => s.kind == RunWorkoutKind.race));
        // Taper magnitude scales with race duration: a marathon week has to be
        // stripped down, a 5K week only needs to be light.
        final ceiling =
            template.goalKind == RunPlanGoalKind.marathon ||
                template.goalKind == RunPlanGoalKind.half
            ? 0.30
            : 0.65;
        expect(support, lessThan(peak * ceiling), reason: template.key);
      }
    });

    test('race-week sharpener sits at least two days before the race', () {
      final raceWeek = RunPlanComposer.compose(
        RunPlanTemplates.marathon,
        _config(),
      ).last;
      final race = raceWeek.firstWhere((s) => s.kind == RunWorkoutKind.race);
      final sharpen = raceWeek.firstWhere(
        (s) => s.kind == RunWorkoutKind.interval,
      );
      expect((race.dayOfWeek - sharpen.dayOfWeek + 7) % 7, greaterThan(1));
    });

    test('taper cuts volume but keeps a quality session', () {
      // Mujika & Padilla: cut volume 40-60%, maintain intensity. The old
      // composer did the opposite — it softened the effort and kept the volume.
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.marathon,
        _config(),
      );
      final peak = schedule
          .take(schedule.length - 3)
          .map(_weekKm)
          .reduce((a, b) => a > b ? a : b);
      final lastTaper = schedule[schedule.length - 2];
      expect(_weekKm(lastTaper), lessThan(peak * 0.7));
      expect(lastTaper.any((s) => _isQuality(s.kind)), isTrue);
    });
  });

  group('session physiology', () {
    test('VO2 work stays near 8% of weekly volume', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.marathon,
        _config(),
      );
      for (final week in schedule) {
        final weekKm = _weekKm(week);
        for (final session in week) {
          if (session.kind != RunWorkoutKind.interval) continue;
          final workKm = session.steps
              .where(
                (s) =>
                    s.role == RunStepRole.work &&
                    s.metric == RunIntervalMetric.distance,
              )
              .fold<double>(0, (a, s) => a + s.value * s.repeatCount / 1000);
          expect(workKm, lessThanOrEqualTo(weekKm * 0.085 + 0.1));
        }
      }
    });

    test('interval recovery scales with rep duration', () {
      // 120 s after a 1000 m rep is barely a third of the rep, so every rep
      // after the first degrades. Daniels jogs roughly the rep duration.
      final paces = _calibration.paces;
      for (final session
          in RunPlanComposer.compose(
            RunPlanTemplates.half,
            _config(),
          ).expand((w) => w)) {
        if (session.kind != RunWorkoutKind.interval) continue;
        final work = session.steps.firstWhere((s) => s.role == RunStepRole.work);
        final rest = session.steps.firstWhere(
          (s) => s.role == RunStepRole.recovery,
        );
        if (work.metric != RunIntervalMetric.distance) continue;
        if (rest.metric != RunIntervalMetric.time) continue;
        expect(
          rest.value,
          greaterThanOrEqualTo(
            work.value / 1000 * paces.intervalSecPerKm * 0.7,
          ),
          reason: session.name,
        );
      }
    });

    test('hill reps are prescribed by effort, never by flat-ground pace', () {
      // The same effort uphill is 30-60 s/km slower, so a track pace here is
      // either impossible or a licence to overreach.
      for (final session
          in RunPlanComposer.compose(
            RunPlanTemplates.tenK,
            _config(),
          ).expand((w) => w)) {
        if (session.kind != RunWorkoutKind.hills) continue;
        expect(session.targetPaceSecPerKm, isNull);
        for (final step in session.steps) {
          expect(step.targetPaceMinSecPerKm, isNull, reason: session.name);
          expect(step.targetPaceMaxSecPerKm, isNull, reason: session.name);
        }
      }
    });

    test('race pace comes from the goal distance, not the calibration', () {
      // A 25:00 5K runner is not a 5:00/km marathoner.
      final race = RunPlanComposer.compose(
        RunPlanTemplates.marathon,
        _config(),
      ).last.firstWhere((s) => s.kind == RunWorkoutKind.race);
      final paces = _calibration.paces;
      expect(
        race.targetPaceSecPerKm,
        closeTo(paces.racePaceFor(RunPaceCalculator.marathonMeters), 1),
      );
      expect(
        race.targetPaceSecPerKm!,
        greaterThan(paces.raceSecPerKm + 20),
        reason: 'marathon pace must be well slower than 5K pace',
      );
    });

    test('endurance plans include goal-pace specific work', () {
      for (final template in [
        RunPlanTemplates.marathon,
        RunPlanTemplates.half,
      ]) {
        final racePace = _calibration.paces.racePaceFor(
          template.goalKind == RunPlanGoalKind.marathon
              ? RunPaceCalculator.marathonMeters
              : RunPaceCalculator.halfMeters,
        );
        final hasRacePaceWork = RunPlanComposer.compose(template, _config())
            .take(RunPlanComposer.compose(template, _config()).length - 1)
            .expand((w) => w)
            .any(
              (s) => s.steps.any(
                (step) =>
                    step.role == RunStepRole.work &&
                    step.targetPaceMinSecPerKm != null &&
                    (step.targetPaceMinSecPerKm! - racePace).abs() <
                        racePace * 0.06,
              ),
            );
        expect(hasRacePaceWork, isTrue, reason: template.key);
      }
    });

    test('build weeks add strides to an easy run', () {
      final hasStrides = RunPlanComposer.compose(
        RunPlanTemplates.tenK,
        _config(),
      ).expand((w) => w).any(
        (s) => s.kind == RunWorkoutKind.easy && s.steps.isNotEmpty,
      );
      expect(hasStrides, isTrue);
    });

    test('easy runs advertise a pace window, not a single number', () {
      // Running the easy days too fast is the most common amateur error, and a
      // single precise number invites it.
      final easy = RunPlanComposer.compose(
        RunPlanTemplates.tenK,
        _config(),
      ).first.firstWhere((s) => s.kind == RunWorkoutKind.easy);
      expect(easy.notes, contains('/km'));
    });
  });
}
