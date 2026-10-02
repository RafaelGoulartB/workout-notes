import 'package:fl_chart/fl_chart.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/utils/app_number_format.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Calendar window analysed by the nutrition progress screen.
enum BalancePeriod { week, month }

/// Overall energy-balance verdict for a period.
enum BalanceStatus { deficit, surplus, maintaining, noGoal }

/// How a single day (or month week) compares with the calorie goal.
enum DayStatus { onTarget, deficit, surplus, unknown }

/// Total macros logged in a period.
class MacroSummary {
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double totalKcal;

  const MacroSummary({
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.totalKcal,
  });

  factory MacroSummary.fromRows(List<Map<String, dynamic>> rows) {
    double protein = 0, carbs = 0, fat = 0, calories = 0;
    for (final row in rows) {
      protein += (row['protein_g'] as num?)?.toDouble() ?? 0;
      carbs += (row['carbs_g'] as num?)?.toDouble() ?? 0;
      fat += (row['fat_g'] as num?)?.toDouble() ?? 0;
      calories += (row['calories'] as num?)?.toDouble() ?? 0;
    }
    return MacroSummary(
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      totalKcal: calories,
    );
  }
}

/// Per-day averages of the secondary nutrients over the logged days.
class NutrientAverages {
  final int daysLogged;
  final NutritionValues values;

  const NutrientAverages({required this.daysLogged, required this.values});

  factory NutrientAverages.fromRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const NutrientAverages(
        daysLogged: 0,
        values: NutritionValues.empty,
      );
    }
    double average(String key) =>
        rows.fold<double>(0, (sum, row) {
          return sum + ((row[key] as num?)?.toDouble() ?? 0);
        }) /
        rows.length;
    return NutrientAverages(
      daysLogged: rows.length,
      values: NutritionValues(
        fiberG: average('fiber_g'),
        sugarsG: average('sugars_g'),
        sodiumMg: average('sodium_mg'),
        saturatedFatG: average('saturated_fat_g'),
        monounsaturatedFatG: average('monounsaturated_fat_g'),
        polyunsaturatedFatG: average('polyunsaturated_fat_g'),
        transFatG: average('trans_fat_g'),
        potassiumMg: average('potassium_mg'),
        calciumMg: average('calcium_mg'),
        ironMg: average('iron_mg'),
        magnesiumMg: average('magnesium_mg'),
        zincMg: average('zinc_mg'),
        vitaminAUg: average('vitamin_a_ug'),
        vitaminCMg: average('vitamin_c_mg'),
        vitaminDUg: average('vitamin_d_ug'),
        vitaminB12Ug: average('vitamin_b12_ug'),
      ),
    );
  }
}

/// One cell of the week/month sequence strip.
class SequenceItem {
  final DateTime date;
  final String? label;
  final double? calories;
  final bool isHighlighted;

  const SequenceItem({
    required this.date,
    required this.calories,
    required this.isHighlighted,
    this.label,
  });
}

/// Number of sequence cells in each band relative to the calorie goal.
class DayBandCounts {
  final int deficit;
  final int onTarget;
  final int surplus;
  final int logged;

  const DayBandCounts({
    required this.deficit,
    required this.onTarget,
    required this.surplus,
    required this.logged,
  });
}

/// Pure calculations behind the nutrition progress screen.
class NutritionProgressCalculator {
  const NutritionProgressCalculator._();

  static const int rollingWindow = 7;

  /// Roughly 7,700 kcal ≈ 1 kg of body fat. Used only for the
  /// informational "equivalent in fat" label on the hero card.
  static const double kcalPerKgFat = 7700;

  /// A day within this fraction of the goal counts as "on target".
  static const double onTargetTolerance = 0.10;

  static DateTime periodStart(BalancePeriod period, DateTime anchor) =>
      switch (period) {
        BalancePeriod.week => sundayOf(anchor),
        BalancePeriod.month => DateTime(anchor.year, anchor.month),
      };

  static DateTime periodEnd(BalancePeriod period, DateTime anchor) {
    final start = periodStart(period, anchor);
    return switch (period) {
      BalancePeriod.week => addDays(start, 6),
      BalancePeriod.month => DateTime(anchor.year, anchor.month + 1, 0),
    };
  }

  static int periodDays(BalancePeriod period, DateTime anchor) =>
      daysBetween(periodStart(period, anchor), periodEnd(period, anchor)) +
      1;

  /// Anchor [delta] periods away from [anchor].
  static DateTime shiftAnchor(
    BalancePeriod period,
    DateTime anchor,
    int delta,
  ) => switch (period) {
    BalancePeriod.week => addDays(anchor, 7 * delta),
    BalancePeriod.month => DateTime(anchor.year, anchor.month + delta, 1),
  };

  /// Whether the period containing [anchor] ends before the one containing
  /// [today] (so the user may still page forward).
  static bool canMoveNext(
    BalancePeriod period,
    DateTime anchor,
    DateTime today,
  ) {
    final todayDate = dayOf(today);
    final currentStart = switch (period) {
      BalancePeriod.week => sundayOf(todayDate),
      BalancePeriod.month => DateTime(todayDate.year, todayDate.month),
    };
    return periodStart(period, anchor).isBefore(currentStart);
  }

  static bool isCurrentPeriod(
    BalancePeriod period,
    DateTime anchor,
    DateTime today,
  ) {
    final todayDate = dayOf(today);
    return !todayDate.isBefore(periodStart(period, anchor)) &&
        !todayDate.isAfter(periodEnd(period, anchor));
  }

  /// 7-day rolling average series over the selected calendar period. Each
  /// point is the mean of the last [rollingWindow] days ending at that date.
  /// Days without any log pull the mean down; we use a trailing mean of
  /// non-null days within the window so a quiet day doesn't tank the
  /// line (which would suggest a fictitious calorie crash).
  static List<FlSpot> rollingSpots(List<DailyCalorieTotal> dailies) {
    final spots = <FlSpot>[];
    for (var i = 0; i < dailies.length; i++) {
      final start = (i - rollingWindow + 1).clamp(0, dailies.length);
      final window = dailies.sublist(start, i + 1);
      final logged = window.where((d) => d.calories != null).toList();
      if (logged.length < 3) continue;
      final sum = logged.fold<double>(0, (s, d) => s + d.calories!);
      final avg = sum / logged.length;
      spots.add(FlSpot(i.toDouble(), avg));
    }
    return spots;
  }

  static BalanceStatus statusFor(CalorieBalance? balance, bool hasGoal) {
    if (!hasGoal) return BalanceStatus.noGoal;
    final v = balance?.balance;
    if (v == null) return BalanceStatus.noGoal;
    if (v.abs() < 1) return BalanceStatus.maintaining;
    return v < 0 ? BalanceStatus.deficit : BalanceStatus.surplus;
  }

  /// Band of [calories] relative to [goal]; unknown without both.
  static DayStatus dayStatus(double? calories, double? goal) {
    if (goal == null || goal <= 0 || calories == null) return DayStatus.unknown;
    final delta = calories - goal;
    final ratio = delta.abs() / goal;
    if (ratio <= onTargetTolerance) return DayStatus.onTarget;
    return delta < 0 ? DayStatus.deficit : DayStatus.surplus;
  }

  static DayBandCounts bandCounts(List<SequenceItem> items, double? goal) {
    var deficit = 0, onTarget = 0, surplus = 0, logged = 0;
    for (final item in items) {
      if (item.calories == null) continue;
      logged++;
      switch (dayStatus(item.calories, goal)) {
        case DayStatus.onTarget:
          onTarget++;
        case DayStatus.deficit:
          deficit++;
        case DayStatus.surplus:
          surplus++;
        case DayStatus.unknown:
          break;
      }
    }
    return DayBandCounts(
      deficit: deficit,
      onTarget: onTarget,
      surplus: surplus,
      logged: logged,
    );
  }

  static List<SequenceItem> dailySequence(
    List<DailyCalorieTotal> dailies,
    DateTime today,
  ) => [
    for (final day in dailies)
      SequenceItem(
        date: day.date,
        calories: day.calories,
        isHighlighted: isSameDay(day.date, today),
      ),
  ];

  /// One item per calendar week touched by [dailies], holding the mean of its
  /// logged days. [weekLabel] receives the 1-based week number.
  static List<SequenceItem> monthlySequence(
    List<DailyCalorieTotal> dailies,
    DateTime today,
    String Function(int weekNumber) weekLabel,
  ) {
    final groups = <DateTime, List<DailyCalorieTotal>>{};
    for (final day in dailies) {
      groups.putIfAbsent(sundayOf(day.date), () => []).add(day);
    }

    final entries = groups.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (var index = 0; index < entries.length; index++)
        _monthlyWeekItem(entries[index], index, weekLabel, today),
    ];
  }

  static SequenceItem _monthlyWeekItem(
    MapEntry<DateTime, List<DailyCalorieTotal>> entry,
    int index,
    String Function(int weekNumber) weekLabel,
    DateTime today,
  ) {
    final loggedDays = entry.value
        .where((day) => day.calories != null)
        .toList();
    final average = loggedDays.isEmpty
        ? null
        : loggedDays.fold<double>(0, (sum, day) => sum + day.calories!) /
              loggedDays.length;
    return SequenceItem(
      date: entry.key,
      label: weekLabel(index + 1),
      calories: average,
      isHighlighted: entry.value.any((day) => isSameDay(day.date, today)),
    );
  }

  // ---- formatting -------------------------------------------------------

  static String formatKcal(double v) => AppNumberFormat.decimal(v, 0);

  static String signedKcal(double value) {
    final sign = value > 0 ? '+' : '';
    return '$sign${AppNumberFormat.decimal(value.abs(), 0)}';
  }

  static String formatFatKg(double absKcal) {
    final kg = absKcal / kcalPerKgFat;
    if (kg < 0.1) return '< 0,1';
    if (kg >= 10) return AppNumberFormat.decimal(kg, 0);
    return AppNumberFormat.decimal(kg, 1);
  }
}
