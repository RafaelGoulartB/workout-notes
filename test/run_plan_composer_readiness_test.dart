import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/services/run_plan_composer.dart';
import 'package:workout_notes/services/run_plan_templates.dart';

/// Guards for the coaching rules added after the plan-quality review:
/// race readiness, anchoring without inflating volume, easy runs that stay
/// easy, quality sessions that stay meaningful, and a beginner trail without
/// VO2 work.
double _km(RunPlanTemplateWorkout s) => (s.targetDistanceMeters ?? 0) / 1000;
double _weekKm(List<RunPlanTemplateWorkout> w) =>
    w.fold(0.0, (a, s) => a + _km(s));
RunPlanTemplateWorkout _longest(List<RunPlanTemplateWorkout> w) =>
    w.reduce((a, b) => _km(a) >= _km(b) ? a : b);

const _slow = RunPlanPaceCalibration(distanceMeters: 5000, timeSeconds: 2280);
const _mid = RunPlanPaceCalibration(distanceMeters: 5000, timeSeconds: 1500);

RunPlanBuildConfig _config({
  int sessions = 4,
  List<int> days = const [2, 4, 5, 7],
  RunPlanIntent intent = RunPlanIntent.finish,
  RunPlanIntensity intensity = RunPlanIntensity.standard,
  RunPlanPaceCalibration? calibration,
  double? currentWeeklyKm,
  bool includeHills = true,
}) => RunPlanBuildConfig(
  sessionsPerWeek: sessions,
  availableDays: days,
  intent: intent,
  intensity: intensity,
  calibration: calibration,
  currentWeeklyKm: currentWeeklyKm,
  includeHills: includeHills,
);

void main() {
  group('race readiness', () {
    test('a plan that cannot reach the race distance says so', () {
      // Before: 8 km/week anchored the whole ladder, so a half-marathon plan
      // peaked at a 10 km long run, then sent the athlete to run 21.1 km with
      // no warning. Growing ≤10%/week from 8 km still cannot get there in 14
      // weeks — so the plan stays honest about its ladder and flags it.
      final half = RunPlanComposer.assess(
        RunPlanTemplates.half,
        _config(
          sessions: 3,
          days: const [2, 4, 7],
          intensity: RunPlanIntensity.conservative,
          calibration: _slow,
          currentWeeklyKm: 8,
        ),
      );
      expect(half.startWeeklyKm, lessThan(12));
      expect(half.longRunShort, isTrue);
      expect(half.ok, isFalse);
    });

    test('a 20-week marathon ladder from a modest base reaches the floor', () {
      // Twenty weeks is enough for the 10% cap to close the gap from 8 km:
      // the peak long run must be a real marathon long run again (was 13.6).
      final marathon = RunPlanComposer.assess(
        RunPlanTemplates.marathon,
        _config(sessions: 3, days: const [2, 4, 7], currentWeeklyKm: 8),
      );
      expect(marathon.peakLongKm, greaterThanOrEqualTo(24));
    });

    test('the wizard is told when week 1 jumps far above today', () {
      final ready = RunPlanComposer.assess(
        RunPlanTemplates.marathon,
        _config(currentWeeklyKm: 35),
      );
      expect(ready.volumeGap, isFalse);
      expect(ready.ok, isTrue);

      final gap = RunPlanComposer.assess(
        RunPlanTemplates.marathon,
        _config(currentWeeklyKm: 8),
      );
      // Anchoring is clamped, so an 8 km runner still gets a week 1 well above
      // 8 km — and must be warned about it instead of finding out in week 1.
      expect(gap.volumeGap, isTrue);
      expect(gap.startWeeklyKm, greaterThan(8 * 1.25));
    });

    test('time-on-feet cap does not hide a marathon preparation gap', () {
      // Keeping a slow runner under three hours is sensible. Calling an
      // 18.5 km peak sufficient preparation for 42.2 km is not.
      final ready = RunPlanComposer.assess(
        RunPlanTemplates.marathon,
        _config(calibration: _slow, currentWeeklyKm: 35),
      );
      expect(ready.longRunCapKm, lessThan(25));
      expect(ready.requiredLongKm, greaterThan(27));
      expect(ready.timeCapDistanceGap, isTrue);
      expect(ready.longRunShort, isTrue);
      expect(ready.canCreate, isFalse);
    });

    test('zero is a real baseline and blocks non-run-walk plans', () {
      final marathon = RunPlanComposer.assess(
        RunPlanTemplates.marathon,
        _config(currentWeeklyKm: 0),
      );
      expect(marathon.baselineZero, isTrue);
      expect(marathon.canCreate, isFalse);

      final runWalk = RunPlanComposer.assess(
        RunPlanTemplates.runWalk,
        _config(sessions: 3, days: const [2, 4, 7], currentWeeklyKm: 0),
      );
      expect(runWalk.baselineZero, isFalse);
      expect(runWalk.canCreate, isTrue);
    });

    test('readiness reports the materialised first week exactly', () {
      final config = _config(
        sessions: 4,
        days: const [1, 3, 5, 7],
        intensity: RunPlanIntensity.conservative,
        calibration: _slow,
        currentWeeklyKm: 8,
      );
      final schedule = RunPlanComposer.compose(RunPlanTemplates.fiveK, config);
      final readiness = RunPlanComposer.assess(RunPlanTemplates.fiveK, config);
      expect(readiness.startWeeklyKm, closeTo(_weekKm(schedule.first), 0.001));
    });

    test('three consecutive days are flagged only on 3–4 day weeks', () {
      expect(
        RunPlanComposer.assess(
          RunPlanTemplates.tenK,
          _config(sessions: 3, days: const [5, 6, 7]),
        ).consecutiveDays,
        isTrue,
      );
      expect(
        RunPlanComposer.assess(
          RunPlanTemplates.tenK,
          _config(sessions: 3, days: const [2, 4, 7]),
        ).consecutiveDays,
        isFalse,
      );
      expect(
        RunPlanComposer.assess(
          RunPlanTemplates.tenK,
          _config(sessions: 5, days: const [1, 2, 3, 5, 7]),
        ).consecutiveDays,
        isFalse,
      );
    });
  });

  group('volume anchoring', () {
    test('week 1 opens near the template prerequisite, not far above it', () {
      // "Faster 5K" assumes 15 km/week; on four days it used to open at 22 km.
      for (final (template, prerequisite) in [
        (RunPlanTemplates.fiveK, 15.0),
        (RunPlanTemplates.tenK, 25.0),
        (RunPlanTemplates.marathon, 35.0),
      ]) {
        for (final sessions in [3, 4, 5]) {
          final schedule = RunPlanComposer.compose(
            template,
            _config(
              sessions: sessions,
              days: const [1, 2, 4, 6, 7].sublist(0, sessions),
            ),
          );
          expect(
            _weekKm(schedule.first),
            lessThanOrEqualTo(prerequisite * 1.3),
            reason: '${template.key} on $sessions days',
          );
        }
      }
    });

    test('peak volume is not inflated far beyond the template ladder', () {
      // First marathon on five days used to peak at 76 km/week (template: 42).
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.marathon,
        _config(sessions: 5, days: const [1, 2, 4, 6, 7]),
      );
      final peak = schedule
          .take(schedule.length - 1)
          .map(_weekKm)
          .reduce((a, b) => a > b ? a : b);
      expect(peak, lessThanOrEqualTo(70));
      expect(peak, greaterThanOrEqualTo(55));
    });

    test('a measured baseline is honoured even when it is high', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.fiveK,
        _config(sessions: 4, currentWeeklyKm: 30),
      );
      expect(_weekKm(schedule.first), closeTo(30, 3.5));
    });
  });

  group('easy runs stay easy', () {
    test('no easy run approaches the long run on a 3-day marathon plan', () {
      // Before: a 20.9 km "Rodagem leve" on Tuesday.
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.marathon,
        _config(sessions: 3, days: const [2, 4, 7]),
      );
      for (final week in schedule) {
        final long = _km(_longest(week));
        for (final s in week) {
          if (s.kind != RunWorkoutKind.easy &&
              s.kind != RunWorkoutKind.recovery) {
            continue;
          }
          expect(
            _km(s),
            lessThanOrEqualTo(long * 0.45 + 2.0 + 0.01),
            reason: '${s.name} ${_km(s)} km beside a $long km long run',
          );
          expect(_km(s), lessThanOrEqualTo(_weekKm(week) * 0.3 + 0.01));
        }
      }
    });
  });

  group('quality stays meaningful', () {
    test('hill and fartlek sessions carry at least four reps', () {
      for (final template in [RunPlanTemplates.tenK, RunPlanTemplates.half]) {
        final schedule = RunPlanComposer.compose(
          template,
          _config(sessions: 3, days: const [2, 4, 7]),
        );
        for (final week in schedule) {
          for (final s in week) {
            if (s.kind != RunWorkoutKind.hills &&
                s.kind != RunWorkoutKind.fartlek) {
              continue;
            }
            final work = s.steps.firstWhere((st) => st.repeatCount > 1);
            expect(work.repeatCount, greaterThanOrEqualTo(4), reason: s.name);
            expect(work.value, greaterThanOrEqualTo(45), reason: s.name);
          }
        }
      }
    });

    test('threshold sessions never drop below a 10-minute stimulus', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.marathon,
        _config(sessions: 3, days: const [2, 4, 7]),
      );
      for (final week in schedule) {
        for (final s in week) {
          if (s.kind != RunWorkoutKind.tempo) continue;
          if (s.name.startsWith('Ritmo de prova')) continue;
          final seconds = s.steps
              .where(
                (st) => st.metric.name == 'time' && st.role.name != 'recovery',
              )
              .fold<int>(0, (a, st) => a + st.value * st.repeatCount);
          expect(seconds, greaterThanOrEqualTo(600), reason: s.name);
        }
      }
    });

    test('taper quality is race-pace work, not hills', () {
      for (final template in [
        RunPlanTemplates.fiveK,
        RunPlanTemplates.tenK,
        RunPlanTemplates.half,
      ]) {
        final schedule = RunPlanComposer.compose(
          template,
          _config(calibration: _mid),
        );
        final taper = schedule[schedule.length - 2];
        expect(
          taper.any((s) => s.name.startsWith('Ritmo de prova')),
          isTrue,
          reason: '${template.key} taper: ${taper.map((s) => s.name)}',
        );
        expect(taper.any((s) => s.kind == RunWorkoutKind.hills), isFalse);
      }
    });
  });

  group('whole-plan load', () {
    test('no training week contains more than two load-bearing sessions', () {
      for (final template in [
        RunPlanTemplates.half,
        RunPlanTemplates.halfPerformance,
        RunPlanTemplates.marathon,
      ]) {
        for (final intent in RunPlanIntent.values) {
          final schedule = RunPlanComposer.compose(
            template,
            _config(
              sessions: 5,
              days: const [1, 2, 4, 6, 7],
              intent: intent,
              calibration: _mid,
              currentWeeklyKm: template.prerequisiteWeeklyKm,
            ),
          );
          for (final week in schedule.take(schedule.length - 1)) {
            final loadBearing = week.where((session) => session.kind.isQuality);
            expect(
              loadBearing.length,
              lessThanOrEqualTo(2),
              reason:
                  '${template.key}/${intent.name}: '
                  '${loadBearing.map((s) => s.name).join(', ')}',
            );
          }
        }
      }
    });

    test('beginner plans carry at most one structured quality session', () {
      for (final template in [
        RunPlanTemplates.returnToRunning,
        RunPlanTemplates.firstFiveK,
        RunPlanTemplates.firstTenK,
      ]) {
        for (final sessions in template.allowedSessionsPerWeek) {
          final schedule = RunPlanComposer.compose(
            template,
            _config(
              sessions: sessions,
              days: const [1, 2, 4, 6, 7].sublist(0, sessions),
            ),
          );
          for (final week in schedule.take(schedule.length - 1)) {
            expect(
              week.where((session) => session.kind.isQuality).length,
              lessThanOrEqualTo(1),
              reason: '${template.key}/$sessions',
            );
          }
        }
      }
    });

    test('actual build-line growth stays near ten percent at low volume', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.half,
        _config(
          sessions: 4,
          days: const [1, 3, 5, 7],
          intensity: RunPlanIntensity.conservative,
          calibration: _slow,
          currentWeeklyKm: 8,
        ),
      );
      var lastBuild = 0.0;
      for (var i = 0; i < schedule.length - 1; i++) {
        final recovery = i > 0 && i % 4 == 3;
        final taper = i >= schedule.length - 2;
        if (recovery || taper) continue;
        final current = _weekKm(schedule[i]);
        if (lastBuild > 0) {
          expect(
            current,
            lessThanOrEqualTo(lastBuild * 1.11),
            reason: 'week ${i + 1}: $lastBuild -> $current',
          );
        }
        lastBuild = current;
      }
    });

    test('disabling hills replaces every hill session with flat work', () {
      for (final template in [
        RunPlanTemplates.fiveK,
        RunPlanTemplates.tenK,
        RunPlanTemplates.half,
        RunPlanTemplates.marathon,
      ]) {
        final schedule = RunPlanComposer.compose(
          template,
          _config(
            intent: RunPlanIntent.pb,
            includeHills: false,
            currentWeeklyKm: template.prerequisiteWeeklyKm,
          ),
        );
        expect(
          schedule
              .expand((week) => week)
              .any((session) => session.kind == RunWorkoutKind.hills),
          isFalse,
          reason: template.key,
        );
        expect(
          schedule
              .expand((week) => week)
              .any((session) => session.kind == RunWorkoutKind.fartlek),
          isTrue,
          reason: '${template.key} lost the replacement stimulus',
        );
      }
    });

    test('aerobic-base plan stays easy apart from strides', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.base,
        _config(currentWeeklyKm: 12),
      );
      expect(
        schedule
            .expand((week) => week)
            .any((session) => session.kind.isQuality),
        isFalse,
      );
    });
  });

  group('beginner trail', () {
    test('first-5K and return plans never prescribe VO2 repeats or hills', () {
      for (final template in [
        RunPlanTemplates.firstFiveK,
        RunPlanTemplates.returnToRunning,
        RunPlanTemplates.firstTenK,
      ]) {
        for (final sessions in [3, 4, 5]) {
          final schedule = RunPlanComposer.compose(
            template,
            _config(
              sessions: sessions,
              days: const [1, 2, 4, 6, 7].sublist(0, sessions),
            ),
          );
          for (final week in schedule.take(schedule.length - 1)) {
            for (final s in week) {
              expect(
                s.kind,
                isNot(isIn({RunWorkoutKind.interval, RunWorkoutKind.hills})),
                reason: '${template.key} $sessions days: ${s.name}',
              );
            }
          }
        }
      }
    });

    test('beginners still get pace-change work after the intro weeks', () {
      final schedule = RunPlanComposer.compose(
        RunPlanTemplates.firstFiveK,
        _config(sessions: 3, days: const [2, 4, 7]),
      );
      expect(
        schedule.any(
          (w) => w.any(
            (s) =>
                s.kind == RunWorkoutKind.fartlek ||
                s.kind == RunWorkoutKind.progression,
          ),
        ),
        isTrue,
      );
    });
  });

  test('the long run is still the longest session everywhere', () {
    for (final template in RunPlanTemplates.all) {
      if (template.style == RunPlanTemplateStyle.runWalk) continue;
      for (final sessions in template.allowedSessionsPerWeek) {
        for (final calibration in [null, _slow, _mid]) {
          final schedule = RunPlanComposer.compose(
            template,
            _config(
              sessions: sessions,
              days: const [1, 3, 4, 5, 7].sublist(0, sessions),
              calibration: calibration,
              currentWeeklyKm: 8,
            ),
          );
          for (final week in schedule) {
            expect(
              _longest(week).kind,
              isIn({
                RunWorkoutKind.long,
                RunWorkoutKind.race,
                RunWorkoutKind.progression,
              }),
              reason: '${template.key} $sessions days',
            );
          }
        }
      }
    }
  });
}
