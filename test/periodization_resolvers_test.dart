import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:workout_notes/models/periodization_target.dart';
import 'package:workout_notes/periodization/nutrition_target_input.dart';
import 'package:workout_notes/periodization/week_override_resolver.dart';

PeriodizationTarget _target({
  double calories = 2000,
  double proteinG = 160,
  double? validFromOffset,
}) => PeriodizationTarget(
  id: 't',
  phaseId: 'p',
  version: 1,
  validFrom: DateTime(2026, 1, 1).add(
    Duration(days: validFromOffset?.toInt() ?? 0),
  ),
  calories: calories,
  proteinG: proteinG,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  group('WeekOverrideResolver', () {
    final resolver = WeekOverrideResolver();

    test('computeWeekStarts splits the range into 7-day chunks', () {
      final starts = resolver.computeWeekStarts(
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 28),
      );
      expect(starts.length, 4);
      expect(starts[0], DateTime(2026, 1, 1));
      expect(starts[1], DateTime(2026, 1, 8));
      expect(starts.last, DateTime(2026, 1, 22));
    });

    test('weekEnd trims the last week to the phase end', () {
      final starts = resolver.computeWeekStarts(
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 20),
      );
      expect(resolver.weekEnd(starts, 0, DateTime(2026, 1, 20)),
          DateTime(2026, 1, 7));
      expect(resolver.weekEnd(starts, 2, DateTime(2026, 1, 20)),
          DateTime(2026, 1, 20));
    });

    test('effectiveTarget walks back to the nearest override', () {
      final overrides = <PeriodizationTarget?>[null, _target(), null];
      expect(resolver.effectiveTarget(overrides, 0), isNull);
      expect(resolver.effectiveTarget(overrides, 1)?.calories, 2000);
      expect(resolver.effectiveTarget(overrides, 2)?.calories, 2000);
    });

    test('targetForDate picks the newest validFrom at or before date', () {
      final history = [
        _target(calories: 1800, validFromOffset: 0),
        _target(calories: 2200, validFromOffset: 14),
      ];
      expect(resolver.targetForDate(history, DateTime(2026, 1, 10))?.calories,
          1800);
      expect(resolver.targetForDate(history, DateTime(2026, 1, 15))?.calories,
          2200);
      expect(resolver.targetForDate(history, DateTime(2026, 1, 20))?.calories,
          2200);
    });

    test('targetForDate falls back to the oldest target before phase start',
        () {
      final history = [
        _target(calories: 1800, validFromOffset: 0),
        _target(calories: 2200, validFromOffset: 14),
      ];
      expect(resolver.targetForDate(history, DateTime(2025, 12, 1))?.calories,
          1800);
    });

    test('targetsEquivalent treats empties and nulls as equal', () {
      expect(resolver.targetsEquivalent(null, _empty()), isTrue);
      expect(resolver.targetsEquivalent(_empty(), _empty()), isTrue);
      expect(resolver.targetsEquivalent(_target(), _target()), isTrue);
      expect(resolver.targetsEquivalent(_target(calories: 2000),
          _target(calories: 2100)), isFalse);
    });

    test('reconstructOverrides only writes when the target changes', () {
      final starts = resolver.computeWeekStarts(
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 21),
      );
      final history = [
        _target(calories: 2000, validFromOffset: 0),
        _target(calories: 2400, validFromOffset: 14),
      ];
      final overrides = resolver.reconstructOverrides(
        weekStarts: starts,
        history: history,
      );
      expect(overrides[0]?.calories, 2000);
      expect(overrides[1], isNull);
      expect(overrides[2]?.calories, 2400);
    });
  });

  group('NutritionTargetInput', () {
    test('resolve computes the macro split from TDEE + adjustment + ratios', () {
      final controllers = {
        'tdee': TextEditingController(text: '2200'),
        'adjustment': TextEditingController(text: '+200'),
        'proteinPerKg': TextEditingController(text: '2,2'),
        'fatPerKg': TextEditingController(text: '0.8'),
        'refWeight': TextEditingController(text: '75'),
      };
      final input = NutritionTargetInput.fromControllers(controllers);
      expect(input.hasInput, isTrue);
      expect(input.tdee, 2200);
      expect(input.adjustmentKcal, 200);
      final breakdown = input.resolve();
      expect(breakdown, isNotNull);
      expect(breakdown!.calories, 2400);
      expect(breakdown.proteinG, closeTo(165, 0.01));
      expect(breakdown.energyConflict, isFalse);
    });

    test('resolve keeps a deficit (negative adjustment) under TDEE', () {
      final controllers = {
        'tdee': TextEditingController(text: '2200'),
        'adjustment': TextEditingController(text: '-300'),
        'proteinPerKg': TextEditingController(text: '2'),
        'fatPerKg': TextEditingController(text: '1'),
        'refWeight': TextEditingController(text: '78'),
      };
      final breakdown = NutritionTargetInput.fromControllers(
        controllers,
      ).resolve();
      expect(breakdown, isNotNull);
      expect(breakdown!.calories, 1900);
    });

    test('resolve returns null on partial input', () {
      final controllers = {
        'tdee': TextEditingController(text: '2200'),
        'adjustment': TextEditingController(text: '+200'),
        'proteinPerKg': TextEditingController(text: ''),
        'fatPerKg': TextEditingController(text: '0.8'),
        'refWeight': TextEditingController(text: '75'),
      };
      expect(
        NutritionTargetInput.fromControllers(controllers).resolve(),
        isNull,
      );
    });
  });
}

PeriodizationTarget _empty() => PeriodizationTarget(
  id: '',
  phaseId: '',
  version: 0,
  validFrom: DateTime(2026, 1, 1),
  createdAt: DateTime(2026, 1, 1),
);
