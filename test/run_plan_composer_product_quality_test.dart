import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_plan_templates.dart';

double _km(RunPlanTemplateWorkout session) =>
    (session.targetDistanceMeters ?? 0) / 1000;

double _weekKm(List<RunPlanTemplateWorkout> week) =>
    week.fold(0, (sum, session) => sum + _km(session));

List<int> _days(int sessions) => switch (sessions) {
  3 => const [2, 5, 7],
  4 => const [1, 3, 5, 7],
  _ => const [1, 2, 4, 6, 7],
};

double _qualityWorkKm(RunPlanTemplateWorkout session) {
  if (!session.kind.isQuality) return 0;
  var total = 0.0;
  for (final step in session.steps) {
    final countsAsWork =
        step.role == RunStepRole.work ||
        (session.kind == RunWorkoutKind.tempo &&
            step.role == RunStepRole.steady);
    if (!countsAsWork) continue;
    if (step.metric == RunIntervalMetric.distance) {
      total += step.value * step.repeatCount / 1000;
    } else {
      final min =
          step.targetPaceMinSecPerKm ?? session.targetPaceSecPerKm ?? 320;
      final max = step.targetPaceMaxSecPerKm ?? min;
      total += step.value * step.repeatCount / ((min + max) / 2);
    }
  }
  return total;
}

void main() {
  test('generated product matrix respects delivered-load invariants', () {
    const calibrations = <RunPlanPaceCalibration?>[
      null,
      RunPlanPaceCalibration(distanceMeters: 5000, timeSeconds: 38 * 60),
      RunPlanPaceCalibration(distanceMeters: 5000, timeSeconds: 25 * 60),
    ];
    var scenarios = 0;

    for (final template in RunPlanTemplates.all) {
      final baselines = <double?>{null, 8, template.prerequisiteWeeklyKm};
      for (final sessions in template.allowedSessionsPerWeek) {
        for (final intent in RunPlanIntent.values) {
          for (final intensity in RunPlanIntensity.values) {
            for (final calibration in calibrations) {
              for (final baseline in baselines) {
                for (final includeHills in [true, false]) {
                  final config = RunPlanBuildConfig(
                    sessionsPerWeek: sessions,
                    availableDays: _days(sessions),
                    intent: intent,
                    intensity: intensity,
                    calibration: calibration,
                    currentWeeklyKm: baseline,
                    includeHills: includeHills,
                  );
                  final schedule = RunPlanComposer.compose(template, config);
                  final readiness = RunPlanComposer.assess(template, config);
                  scenarios++;

                  expect(schedule, hasLength(template.weeks));
                  expect(
                    schedule.every((week) => week.length == sessions),
                    isTrue,
                    reason: '${template.key}/$sessions',
                  );
                  if (template.style == RunPlanTemplateStyle.runWalk) {
                    continue;
                  }

                  expect(
                    readiness.startWeeklyKm,
                    closeTo(_weekKm(schedule.first), 0.001),
                    reason: '${template.key}/$sessions readiness drift',
                  );
                  if (!includeHills) {
                    expect(
                      schedule
                          .expand((week) => week)
                          .any(
                            (session) => session.kind == RunWorkoutKind.hills,
                          ),
                      isFalse,
                      reason: '${template.key}/$sessions retained hills',
                    );
                  }

                  final training = schedule.take(
                    schedule.length -
                        (schedule.last.any(
                              (session) => session.kind == RunWorkoutKind.race,
                            )
                            ? 1
                            : 0),
                  );
                  for (final week in training) {
                    final total = _weekKm(week);
                    expect(total.isFinite && total > 0, isTrue);
                    final longest = week.map(_km).reduce(math.max);
                    for (final session in week) {
                      expect(
                        _km(session).isFinite && _km(session) > 0,
                        isTrue,
                        reason:
                            '${template.key}/$sessions produced a zero-length session',
                      );
                      if (session.kind == RunWorkoutKind.easy ||
                          session.kind == RunWorkoutKind.recovery) {
                        expect(_km(session), lessThanOrEqualTo(longest + 0.01));
                      }
                    }

                    final quality = week.where(
                      (session) => session.kind.isQuality,
                    );
                    expect(
                      quality.length,
                      lessThanOrEqualTo(
                        template.level == RunPlanTemplateLevel.beginner ? 1 : 2,
                      ),
                      reason:
                          '${template.key}/$sessions ${quality.map((s) => s.name)}',
                    );
                    final work = week.fold<double>(
                      0,
                      (sum, session) => sum + _qualityWorkKm(session),
                    );
                    expect(
                      work / total,
                      lessThanOrEqualTo(0.27),
                      reason:
                          '${template.key}/$sessions quality ${work.toStringAsFixed(1)}'
                          '/${total.toStringAsFixed(1)} km',
                    );
                  }

                  var lastBuild = 0.0;
                  final raceWeek =
                      schedule.last.any(
                        (session) => session.kind == RunWorkoutKind.race,
                      )
                      ? schedule.length - 1
                      : -1;
                  final taperCount = raceWeek < 0
                      ? 0
                      : template.goalKind.name == 'marathon'
                      ? 2
                      : 1;
                  for (var w = 0; w < schedule.length; w++) {
                    final recovery = w > 0 && w % 4 == 3;
                    final taper = raceWeek >= 0 && w >= raceWeek - taperCount;
                    if (recovery || taper) continue;
                    final current = _weekKm(schedule[w]);
                    if (lastBuild > 0) {
                      expect(
                        current,
                        lessThanOrEqualTo(lastBuild * 1.11),
                        reason:
                            '${template.key}/$sessions/${intent.name}/'
                            '${intensity.name}/cal=${calibration?.timeSeconds}/'
                            'base=$baseline/hills=$includeHills W$w: '
                            '$lastBuild -> $current',
                      );
                    }
                    lastBuild = current;
                  }
                }
              }
            }
          }
        }
      }
    }
    expect(scenarios, greaterThan(1000));
  });

  test('explicit zero blocks every plan except start-running', () {
    for (final template in RunPlanTemplates.all) {
      final sessions = template.allowedSessionsPerWeek.first;
      final readiness = RunPlanComposer.assess(
        template,
        RunPlanBuildConfig(
          sessionsPerWeek: sessions,
          availableDays: _days(sessions),
          currentWeeklyKm: 0,
        ),
      );
      expect(
        readiness.canCreate,
        template.style == RunPlanTemplateStyle.runWalk,
        reason: template.key,
      );
    }
  });
}
