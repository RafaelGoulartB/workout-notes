import 'package:flutter_test/flutter_test.dart';
import 'package:workout_notes/models/nutrition/nutrition_progress.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/screens/workout/nutrition_progress_controller.dart';

DailyCalorieTotal _day(DateTime date, double? kcal) =>
    DailyCalorieTotal(date: date, calories: kcal);

void main() {
  group('period windows', () {
    // 2026-03-11 is a Wednesday; weeks run Sunday to Saturday.
    final anchor = DateTime(2026, 3, 11);

    test('week runs Sunday to Saturday', () {
      expect(
        NutritionProgressCalculator.periodStart(BalancePeriod.week, anchor),
        DateTime(2026, 3, 8),
      );
      expect(
        NutritionProgressCalculator.periodEnd(BalancePeriod.week, anchor),
        DateTime(2026, 3, 14),
      );
      expect(
        NutritionProgressCalculator.periodDays(BalancePeriod.week, anchor),
        7,
      );
    });

    test('month covers the full calendar month', () {
      expect(
        NutritionProgressCalculator.periodStart(BalancePeriod.month, anchor),
        DateTime(2026, 3),
      );
      expect(
        NutritionProgressCalculator.periodEnd(BalancePeriod.month, anchor),
        DateTime(2026, 3, 31),
      );
      expect(
        NutritionProgressCalculator.periodDays(BalancePeriod.month, anchor),
        31,
      );
    });

    test('shiftAnchor moves whole weeks or months', () {
      expect(
        NutritionProgressCalculator.shiftAnchor(BalancePeriod.week, anchor, -1),
        DateTime(2026, 3, 4),
      );
      expect(
        NutritionProgressCalculator.shiftAnchor(BalancePeriod.month, anchor, 1),
        DateTime(2026, 4, 1),
      );
    });

    test('cannot page past the current period', () {
      final today = DateTime(2026, 3, 11, 15);
      expect(
        NutritionProgressCalculator.canMoveNext(
          BalancePeriod.week,
          anchor,
          today,
        ),
        isFalse,
      );
      expect(
        NutritionProgressCalculator.canMoveNext(
          BalancePeriod.week,
          DateTime(2026, 3, 4),
          today,
        ),
        isTrue,
      );
      expect(
        NutritionProgressCalculator.isCurrentPeriod(
          BalancePeriod.month,
          anchor,
          today,
        ),
        isTrue,
      );
    });
  });

  group('rolling average', () {
    test('needs three logged days in the window before plotting', () {
      final start = DateTime(2026, 3, 1);
      final dailies = [
        for (var i = 0; i < 10; i++)
          _day(start.add(Duration(days: i)), i < 2 || i == 5 ? null : 2000.0),
      ];
      final spots = NutritionProgressCalculator.rollingSpots(dailies);
      // Index 4 is the first with three logged days (2, 3, 4).
      expect(spots.first.x, 4);
      expect(spots.first.y, 2000);
      expect(spots.length, 6);
      expect(NutritionProgressCalculator.rollingWindow, 7);
    });
  });

  group('day bands', () {
    test('within 10 percent is on target', () {
      expect(
        NutritionProgressCalculator.dayStatus(2100, 2000),
        DayStatus.onTarget,
      );
      expect(
        NutritionProgressCalculator.dayStatus(1700, 2000),
        DayStatus.deficit,
      );
      expect(
        NutritionProgressCalculator.dayStatus(2500, 2000),
        DayStatus.surplus,
      );
      expect(
        NutritionProgressCalculator.dayStatus(2500, null),
        DayStatus.unknown,
      );
      expect(
        NutritionProgressCalculator.dayStatus(null, 2000),
        DayStatus.unknown,
      );
    });

    test('bandCounts ignores unlogged days and needs a goal for bands', () {
      final items = [
        SequenceItem(
          date: DateTime(2026, 3, 8),
          calories: 1500,
          isHighlighted: false,
        ),
        SequenceItem(
          date: DateTime(2026, 3, 9),
          calories: 2000,
          isHighlighted: false,
        ),
        SequenceItem(
          date: DateTime(2026, 3, 10),
          calories: 3000,
          isHighlighted: false,
        ),
        SequenceItem(
          date: DateTime(2026, 3, 11),
          calories: null,
          isHighlighted: true,
        ),
      ];
      final bands = NutritionProgressCalculator.bandCounts(items, 2000);
      expect(
        (bands.deficit, bands.onTarget, bands.surplus, bands.logged),
        (1, 1, 1, 3),
      );

      final noGoal = NutritionProgressCalculator.bandCounts(items, null);
      expect((noGoal.deficit, noGoal.logged), (0, 3));
    });
  });

  group('sequences', () {
    test('monthly sequence averages logged days per calendar week', () {
      final dailies = [
        _day(DateTime(2026, 3, 1), 2000), // Sunday, week 1
        _day(DateTime(2026, 3, 2), 2400),
        _day(DateTime(2026, 3, 3), null),
        _day(DateTime(2026, 3, 8), null), // week 2, nothing logged
      ];
      final items = NutritionProgressCalculator.monthlySequence(
        dailies,
        DateTime(2026, 3, 2),
        (n) => 'W$n',
      );
      expect(items.length, 2);
      expect(items[0].label, 'W1');
      expect(items[0].calories, 2200);
      expect(items[0].isHighlighted, isTrue);
      expect(items[1].label, 'W2');
      expect(items[1].calories, isNull);
      expect(items[1].isHighlighted, isFalse);
    });
  });

  group('status and formatting', () {
    test('statusFor requires a goal and a non-zero balance', () {
      CalorieBalance balance(double? v) => CalorieBalance(
        days: 7,
        totalConsumed: 0,
        totalGoal: null,
        balance: v,
        daysLogged: 3,
        daysInDeficit: 0,
        daysOnTarget: 0,
        daysInSurplus: 0,
        currentStreak: 0,
        averageDailyIntake: 0,
      );
      expect(
        NutritionProgressCalculator.statusFor(balance(-300), false),
        BalanceStatus.noGoal,
      );
      expect(
        NutritionProgressCalculator.statusFor(balance(null), true),
        BalanceStatus.noGoal,
      );
      expect(
        NutritionProgressCalculator.statusFor(balance(0.4), true),
        BalanceStatus.maintaining,
      );
      expect(
        NutritionProgressCalculator.statusFor(balance(-300), true),
        BalanceStatus.deficit,
      );
      expect(
        NutritionProgressCalculator.statusFor(balance(300), true),
        BalanceStatus.surplus,
      );
    });

    test('kcal and fat-equivalent labels', () {
      expect(NutritionProgressCalculator.signedKcal(250.4), '+250');
      // The balance is shown as a magnitude next to the status label.
      expect(NutritionProgressCalculator.signedKcal(-250.4), '250');
      expect(NutritionProgressCalculator.formatFatKg(300), '< 0,1');
      expect(NutritionProgressCalculator.formatFatKg(7700), '1.0');
      expect(NutritionProgressCalculator.formatFatKg(77000), '10');
    });
  });

  group('MacroSummary / NutrientAverages', () {
    test('MacroSummary sums rows and treats nulls as zero', () {
      final summary = MacroSummary.fromRows([
        {'protein_g': 10, 'carbs_g': 20.5, 'fat_g': null, 'calories': 300},
        {'protein_g': 5.5, 'carbs_g': 4, 'fat_g': 2, 'calories': 100},
      ]);
      expect(summary.proteinG, 15.5);
      expect(summary.carbsG, 24.5);
      expect(summary.fatG, 2);
      expect(summary.totalKcal, 400);
    });

    test('NutrientAverages averages over logged days', () {
      expect(NutrientAverages.fromRows(const []).daysLogged, 0);
      final avg = NutrientAverages.fromRows([
        {'fiber_g': 10, 'sodium_mg': 1000},
        {'fiber_g': 20, 'sodium_mg': null},
      ]);
      expect(avg.daysLogged, 2);
      expect(avg.values.fiberG, 15);
      expect(avg.values.sodiumMg, 500);
    });
  });

  group('NutritionProgressController navigation', () {
    test('paging back is always allowed, forward stops at the current one', () {
      final controller = NutritionProgressController(
        now: () => DateTime(2026, 3, 11),
      );
      addTearDown(controller.dispose);
      expect(controller.period, BalancePeriod.week);
      expect(controller.isCurrentPeriod, isTrue);
      expect(controller.canMoveNext, isFalse);
      expect(controller.periodStart, DateTime(2026, 3, 8));
      expect(controller.periodDays, 7);
    });
  });
}
