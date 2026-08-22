import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/periodization/run_plan_week_resolver.dart';

void main() {
  const resolver = RunPlanWeekResolver();

  group('phase week', () {
    test('counts calendar weeks from the phase start week', () {
      final start = DateTime(2026, 8, 19); // Wednesday
      expect(resolver.phaseWeekOf(phaseStart: start, date: start), 0);
      // Still the same Monday-anchored week.
      expect(
        resolver.phaseWeekOf(phaseStart: start, date: DateTime(2026, 8, 23)),
        0,
      );
      expect(
        resolver.phaseWeekOf(phaseStart: start, date: DateTime(2026, 8, 24)),
        1,
      );
      // Monday the 17th is the same week as Wednesday the 19th.
      expect(
        resolver.phaseWeekOf(phaseStart: start, date: DateTime(2026, 8, 17)),
        0,
      );
      expect(
        resolver.phaseWeekOf(phaseStart: start, date: DateTime(2026, 8, 16)),
        -1,
      );
    });
  });

  group('plan week mapping', () {
    test('offset 0 keeps the historic behaviour', () {
      for (var week = 0; week < 14; week++) {
        expect(
          resolver.planWeekFor(phaseWeek: week, planWeeks: 12),
          week % 12,
        );
      }
    });

    test('offset shifts the phase onto a plan already in progress', () {
      // Phase week 1 starts on plan week 5 (index 4).
      expect(
        resolver.planWeekFor(phaseWeek: 0, planWeeks: 12, startWeek: 4),
        4,
      );
      expect(
        resolver.planWeekFor(phaseWeek: 7, planWeeks: 12, startWeek: 4),
        11,
      );
      // Past the end it wraps back to the start of the plan.
      expect(
        resolver.planWeekFor(phaseWeek: 8, planWeeks: 12, startWeek: 4),
        0,
      );
    });

    test('a one-week plan applies to every phase week', () {
      for (var week = 0; week < 5; week++) {
        expect(resolver.planWeekFor(phaseWeek: week, planWeeks: 1), 0);
      }
    });

    test('returns null for a plan with no weeks', () {
      expect(resolver.planWeekFor(phaseWeek: 0, planWeeks: 0), isNull);
    });
  });

  group('alignment helpers', () {
    test('startWeekForFinish lands the plan final week on the phase end', () {
      // 16-week plan on a 12-week phase: start on plan week 5 (index 4) so the
      // phase's last week is the plan's last week.
      final start = resolver.startWeekForFinish(phaseWeeks: 12, planWeeks: 16);
      expect(start, 4);
      expect(
        resolver.planWeekFor(phaseWeek: 11, planWeeks: 16, startWeek: start),
        15,
      );
    });

    test('startWeekForFinish is 0 when the plan matches the phase', () {
      expect(resolver.startWeekForFinish(phaseWeeks: 12, planWeeks: 12), 0);
    });

    test('coverage classifies the fit', () {
      expect(
        resolver.coverage(phaseWeeks: 12, planWeeks: 12),
        RunPlanCoverage.exact,
      );
      expect(
        resolver.coverage(phaseWeeks: 12, planWeeks: 16),
        RunPlanCoverage.planLonger,
      );
      expect(
        resolver.coverage(phaseWeeks: 12, planWeeks: 4),
        RunPlanCoverage.planRepeats,
      );
      // An offset can turn a longer plan into an exact fit.
      expect(
        resolver.coverage(phaseWeeks: 12, planWeeks: 16, startWeek: 4),
        RunPlanCoverage.exact,
      );
      expect(
        resolver.coverage(phaseWeeks: 0, planWeeks: 4),
        RunPlanCoverage.empty,
      );
    });

    test('leftoverPlanWeeks counts the tail the phase never reaches', () {
      expect(resolver.leftoverPlanWeeks(phaseWeeks: 12, planWeeks: 16), 4);
      expect(
        resolver.leftoverPlanWeeks(phaseWeeks: 12, planWeeks: 16, startWeek: 4),
        0,
      );
      expect(resolver.leftoverPlanWeeks(phaseWeeks: 12, planWeeks: 4), 0);
    });

    test('repeatsWithin counts how often a short plan restarts', () {
      expect(resolver.repeatsWithin(phaseWeeks: 12, planWeeks: 4), 2);
      expect(resolver.repeatsWithin(phaseWeeks: 12, planWeeks: 12), 0);
      expect(resolver.repeatsWithin(phaseWeeks: 4, planWeeks: 12), 0);
      expect(
        resolver.repeatsWithin(phaseWeeks: 12, planWeeks: 12, startWeek: 6),
        1,
      );
    });
  });
}
