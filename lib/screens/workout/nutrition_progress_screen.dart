import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/nutrition/nutrition_goal.dart';
import 'package:workout_notes/models/nutrition/nutrition_values.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/widgets/collapsible_section.dart';
import 'package:workout_notes/widgets/nutrition/nutrition_charts.dart';

/// Nutrition progress and history: daily/weekly calorie charts, macro
/// breakdown, micronutrient trends, goal adherence and week-over-week
/// comparison.
class NutritionProgressScreen extends StatefulWidget {
  const NutritionProgressScreen({super.key});

  @override
  State<NutritionProgressScreen> createState() =>
      _NutritionProgressScreenState();
}

/// One logged day from [NutritionRepository.getDailyNutritionHistory].
class _DayPoint {
  final DateTime date;
  final NutritionValues values;

  const _DayPoint({required this.date, required this.values});
}

/// Aggregated ISO week (Monday-anchored) with per-day averages.
class _WeekPoint {
  final DateTime start;
  final int daysLogged;
  final double totalCalories;
  final double totalProtein;
  final double totalCarbs;
  final double totalFat;
  final double totalFiber;
  final double totalSugars;
  final double totalSodium;

  const _WeekPoint({
    required this.start,
    required this.daysLogged,
    required this.totalCalories,
    required this.totalProtein,
    required this.totalCarbs,
    required this.totalFat,
    required this.totalFiber,
    required this.totalSugars,
    required this.totalSodium,
  });

  double get avgCalories => daysLogged == 0 ? 0 : totalCalories / daysLogged;
  double get avgProtein => daysLogged == 0 ? 0 : totalProtein / daysLogged;
  double get avgCarbs => daysLogged == 0 ? 0 : totalCarbs / daysLogged;
  double get avgFat => daysLogged == 0 ? 0 : totalFat / daysLogged;
  double get avgFiber => daysLogged == 0 ? 0 : totalFiber / daysLogged;
  double get avgSugars => daysLogged == 0 ? 0 : totalSugars / daysLogged;
  double get avgSodium => daysLogged == 0 ? 0 : totalSodium / daysLogged;
}

class _NutritionProgressScreenState extends State<NutritionProgressScreen> {
  static const _historyDays = 84;

  final _repository = NutritionRepository();

  List<_DayPoint> _days = const [];
  List<_WeekPoint> _weeks = const [];
  NutritionGoal? _goal;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _repository.getDailyNutritionHistory(days: _historyDays),
        _repository.getActiveGoal(),
      ]);
      if (!mounted) return;
      setState(() {
        _days = (results[0] as List<Map<String, dynamic>>)
            .map(_dayFromRow)
            .toList();
        _weeks = _buildWeeks(_days);
        _goal = results[1] as NutritionGoal?;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  static _DayPoint _dayFromRow(Map<String, dynamic> row) {
    return _DayPoint(
      date: DateTime.parse(row['date'] as String),
      values: NutritionValues(
        calories: (row['calories'] as num?)?.toDouble(),
        proteinG: (row['protein_g'] as num?)?.toDouble(),
        carbsG: (row['carbs_g'] as num?)?.toDouble(),
        fatG: (row['fat_g'] as num?)?.toDouble(),
        fiberG: (row['fiber_g'] as num?)?.toDouble(),
        sugarsG: (row['sugars_g'] as num?)?.toDouble(),
        sodiumMg: (row['sodium_mg'] as num?)?.toDouble(),
      ),
    );
  }

  /// Buckets the last [days] into the last 12 ISO weeks (Monday start),
  /// oldest first. Weeks without logged days keep zero totals so the
  /// charts render a continuous timeline (same as the workout module).
  static List<_WeekPoint> _buildWeeks(List<_DayPoint> days) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final firstMonday = _weekStart(today);
    final weeks = <_WeekPoint>[];
    for (var w = 11; w >= 0; w--) {
      final start = firstMonday.subtract(Duration(days: w * 7));
      final end = start.add(const Duration(days: 6));
      var count = 0;
      var kcal = 0.0;
      var protein = 0.0;
      var carbs = 0.0;
      var fat = 0.0;
      var fiber = 0.0;
      var sugars = 0.0;
      var sodium = 0.0;
      for (final day in days) {
        if (day.date.isBefore(start) || day.date.isAfter(end)) continue;
        count++;
        kcal += day.values.calories ?? 0;
        protein += day.values.proteinG ?? 0;
        carbs += day.values.carbsG ?? 0;
        fat += day.values.fatG ?? 0;
        fiber += day.values.fiberG ?? 0;
        sugars += day.values.sugarsG ?? 0;
        sodium += day.values.sodiumMg ?? 0;
      }
      weeks.add(
        _WeekPoint(
          start: start,
          daysLogged: count,
          totalCalories: kcal,
          totalProtein: protein,
          totalCarbs: carbs,
          totalFat: fat,
          totalFiber: fiber,
          totalSugars: sugars,
          totalSodium: sodium,
        ),
      );
    }
    return weeks;
  }

  static DateTime _weekStart(DateTime date) {
    final d = DateTime(date.year, date.month, date.day);
    return d.subtract(Duration(days: d.weekday - 1));
  }

  // ------------------------------------------------------------------
  // Overview stats
  // ------------------------------------------------------------------

  static double _avg(List<_DayPoint> days, double? Function(_DayPoint) pick) {
    final logged = days.where((d) => pick(d) != null).toList();
    if (logged.isEmpty) return 0;
    return logged.map(pick).whereType<double>().reduce((a, b) => a + b) /
        logged.length;
  }

  double? get _adherencePercent {
    final goal = _goal?.calories;
    if (goal == null) return null;
    final logged = _days
        .where((d) => d.values.calories != null)
        .toList();
    if (logged.isEmpty) return 0;
    var within = 0;
    for (final day in logged) {
      final consumed = day.values.calories!;
      final delta = (consumed - goal).abs() / goal;
      if (delta <= 0.10) within++;
    }
    return within / logged.length * 100;
  }

  List<_DayPoint> get _last30Days =>
      _days.length <= 30 ? _days : _days.sublist(_days.length - 30);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.nutritionProgressTitle),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
                children: [
                  _buildOverviewStats(loc, theme),
                  const SizedBox(height: 8),
                  CollapsibleSection(
                    title: loc.nutritionProgressDaily,
                    icon: Icons.calendar_view_day_outlined,
                    iconColor: theme.colorScheme.primary,
                    initiallyExpanded: true,
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: theme.colorScheme.outlineVariant
                              .withAlpha(80),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                        child: NutritionBarChart(
                          points: _dailyBarPoints(loc),
                          goalValue: _goal?.calories,
                          color: theme.colorScheme.primary,
                          formatValue: (v) => v >= 1000
                              ? '${(v / 1000).toStringAsFixed(1)}k'
                              : v.round().toString(),
                          maxLabels: 10,
                        ),
                      ),
                    ),
                  ).animate().fadeIn(duration: 250.ms),
                  CollapsibleSection(
                    title: loc.nutritionProgressWeekly,
                    icon: Icons.calendar_view_week_outlined,
                    iconColor: theme.colorScheme.secondary,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: theme.colorScheme.outlineVariant
                                  .withAlpha(80),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loc.nutritionProgressWeeklyCalories,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                NutritionBarChart(
                                  points: _weeklyCaloriePoints(loc),
                                  goalValue: _goal?.calories,
                                  color: theme.colorScheme.secondary,
                                  formatValue: (v) => v >= 1000
                                      ? '${(v / 1000).toStringAsFixed(1)}k'
                                      : v.round().toString(),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(
                              color: theme.colorScheme.outlineVariant
                                  .withAlpha(80),
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  loc.nutritionProgressWeeklyMacros,
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                WeeklyMacroBarChart(
                                  points: _weeklyMacroPoints(),
                                  proteinColor: theme.colorScheme.tertiary,
                                  carbsColor: theme.colorScheme.secondary,
                                  fatColor: theme.colorScheme.primary,
                                ),
                                const SizedBox(height: 6),
                                _Legend(
                                  items: [
                                    (
                                      loc.nutritionProgressProtein,
                                      theme.colorScheme.tertiary,
                                    ),
                                    (
                                      loc.nutritionProgressCarbs,
                                      theme.colorScheme.secondary,
                                    ),
                                    (
                                      loc.nutritionProgressFat,
                                      theme.colorScheme.primary,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 250.ms),
                  CollapsibleSection(
                    title: loc.nutritionProgressMicronutrients,
                    icon: Icons.spa_outlined,
                    iconColor: Colors.teal,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _NutrientCard(
                          title: loc.nutritionProgressFiberAndSugars,
                          chart: NutrientTrendChart(
                            series: _micronutrientSeries(loc, 'g'),
                            formatValue: (v) => v.round().toString(),
                          ),
                          legend: _Legend(
                            items: [
                              (
                                loc.nutritionProgressFiber,
                                Colors.teal,
                              ),
                              (
                                loc.nutritionProgressSugars,
                                Colors.amber.shade700,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        _NutrientCard(
                          title: loc.nutritionProgressSodium,
                          chart: NutrientTrendChart(
                            series: [
                              NutrientTrendSeries(
                                label: loc.nutritionProgressSodium,
                                color: Colors.indigo,
                                points: _sodiumPoints(loc),
                              ),
                            ],
                            formatValue: (v) => v >= 1000
                                ? '${(v / 1000).toStringAsFixed(1)}k'
                                : v.round().toString(),
                          ),
                          legend: null,
                        ),
                      ],
                    ),
                  ).animate().fadeIn(duration: 250.ms),
                  CollapsibleSection(
                    title: loc.nutritionProgressAdherence,
                    icon: Icons.flag_outlined,
                    iconColor: theme.colorScheme.error,
                    child: _buildAdherenceSection(loc, theme),
                  ).animate().fadeIn(duration: 250.ms),
                ],
              ),
            ),
    );
  }

  Widget _buildOverviewStats(AppLocalizations loc, ThemeData theme) {
    final loggedDays = _days.where(
      (d) => d.values.calories != null,
    ).length;
    final adherence = _adherencePercent;
    final stats = <(IconData, String, String)>[
      (
        Icons.local_fire_department_outlined,
        loc.nutritionProgressAvgCalories,
        '${_format(_avg(_last30Days, (d) => d.values.calories))} kcal',
      ),
      (
        Icons.fitness_center_outlined,
        loc.nutritionProgressAvgProtein,
        '${_format(_avg(_last30Days, (d) => d.values.proteinG))} g',
      ),
      (
        Icons.event_available_outlined,
        loc.nutritionProgressDaysLogged,
        _format2(loggedDays.toDouble()),
      ),
      (
        Icons.flag_outlined,
        loc.nutritionProgressAdherenceRate,
        adherence == null
            ? '—'
            : '${adherence.round()}%',
      ),
    ];
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 14, 8, 14),
        child: Row(
          children: [
            for (final stat in stats)
              Expanded(
                child: Column(
                  children: [
                    Icon(stat.$1, size: 20, color: theme.colorScheme.primary),
                    const SizedBox(height: 6),
                    Text(
                      stat.$3,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stat.$2,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdherenceSection(AppLocalizations loc, ThemeData theme) {
    final goal = _goal?.calories;
    if (goal == null) {
      return _EmptyNote(text: loc.nutritionProgressNoGoal);
    }
    var below = 0;
    var within = 0;
    var above = 0;
    for (final day in _days) {
      final consumed = day.values.calories;
      if (consumed == null) continue;
      final delta = (consumed - goal).abs() / goal;
      if (delta <= 0.10) {
        within++;
      } else if (consumed < goal) {
        below++;
      } else {
        above++;
      }
    }
    final chips = <(String, int, Color)>[
      (loc.nutritionProgressBelow, below, theme.colorScheme.secondary),
      (loc.nutritionProgressWithin, within, theme.colorScheme.primary),
      (loc.nutritionProgressAbove, above, theme.colorScheme.error),
    ];
    final current = _weeks.isNotEmpty ? _weeks.last : null;
    final previous = _weeks.length >= 2 ? _weeks[_weeks.length - 2] : null;
    final comparison = current != null && previous != null
        ? _WeekComparisonCard(loc: loc, current: current, previous: previous)
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: theme.colorScheme.outlineVariant.withAlpha(80),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                for (final chip in chips)
                  Expanded(
                    child: Column(
                      children: [
                        Text(
                          '${chip.$2}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: chip.$3,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          chip.$1,
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        ?comparison,
      ],
    );
  }

  // ------------------------------------------------------------------
  // Chart data
  // ------------------------------------------------------------------

  List<NutritionBarPoint> _dailyBarPoints(AppLocalizations loc) {
    final fmt = DateFormat('dd/MM', Intl.defaultLocale);
    return [
      for (final day in _last30Days)
        NutritionBarPoint(
          label: fmt.format(day.date),
          value: day.values.calories ?? 0,
          tooltip: DateFormat.yMMMMEEEEd(Intl.defaultLocale).format(day.date),
        ),
    ];
  }

  List<NutritionBarPoint> _weeklyCaloriePoints(AppLocalizations loc) {
    final fmt = DateFormat('dd/MM', Intl.defaultLocale);
    return [
      for (final week in _weeks)
        NutritionBarPoint(
          label: fmt.format(week.start),
          value: week.avgCalories,
          tooltip: '${fmt.format(week.start)} · '
              '${loc.nutritionProgressDaysLabel(week.daysLogged)}',
        ),
    ];
  }

  List<WeeklyMacroPoint> _weeklyMacroPoints() {
    final fmt = DateFormat('dd/MM', Intl.defaultLocale);
    return [
      for (final week in _weeks)
        WeeklyMacroPoint(
          label: fmt.format(week.start),
          protein: week.avgProtein,
          carbs: week.avgCarbs,
          fat: week.avgFat,
        ),
    ];
  }

  /// Fiber + sugars weekly averages as two series.
  List<NutrientTrendSeries> _micronutrientSeries(
    AppLocalizations loc,
    String unit,
  ) {
    final fmt = DateFormat('dd/MM', Intl.defaultLocale);
    return [
      NutrientTrendSeries(
        label: loc.nutritionProgressFiber,
        color: Colors.teal,
        points: [
          for (final week in _weeks)
            NutrientTrendPoint(
              label: fmt.format(week.start),
              value: week.avgFiber,
              tooltip: '${fmt.format(week.start)}\n'
                  '${loc.nutritionProgressFiber}: ${_format(week.avgFiber)} $unit',
            ),
        ],
      ),
      NutrientTrendSeries(
        label: loc.nutritionProgressSugars,
        color: Colors.amber.shade700,
        points: [
          for (final week in _weeks)
            NutrientTrendPoint(
              label: fmt.format(week.start),
              value: week.avgSugars,
              tooltip: '${fmt.format(week.start)}\n'
                  '${loc.nutritionProgressSugars}: ${_format(week.avgSugars)} $unit',
            ),
        ],
      ),
    ];
  }

  /// Sodium weekly averages (mg) as a single series.
  List<NutrientTrendPoint> _sodiumPoints(AppLocalizations loc) {
    final fmt = DateFormat('dd/MM', Intl.defaultLocale);
    return [
      for (final week in _weeks)
        NutrientTrendPoint(
          label: fmt.format(week.start),
          value: week.avgSodium,
          tooltip: '${fmt.format(week.start)}\n'
              '${loc.nutritionProgressSodium}: ${_format(week.avgSodium)} mg',
        ),
    ];
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  static String _format2(double value) => value.round().toString();
}

/// Card wrapper for the micronutrient charts.
class _NutrientCard extends StatelessWidget {
  final String title;
  final Widget chart;
  final Widget? legend;

  const _NutrientCard({
    required this.title,
    required this.chart,
    this.legend,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            chart,
            if (legend != null) const SizedBox(height: 6),
            ?legend,
          ],
        ),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final List<(String, Color)> items;

  const _Legend({required this.items});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        for (final item in items)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: item.$2,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
              Text(
                item.$1,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _EmptyNote extends StatelessWidget {
  final String text;

  const _EmptyNote({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.info_outline, color: theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// This week vs. previous week comparison card.
class _WeekComparisonCard extends StatelessWidget {
  final AppLocalizations loc;
  final _WeekPoint current;
  final _WeekPoint previous;

  const _WeekComparisonCard({
    required this.loc,
    required this.current,
    required this.previous,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = <(String, double, String)>[
      (
        loc.nutritionProgressCalories,
        current.totalCalories - previous.totalCalories,
        'kcal',
      ),
      (
        loc.nutritionProgressProtein,
        current.totalProtein - previous.totalProtein,
        'g',
      ),
      (
        loc.nutritionProgressCarbs,
        current.totalCarbs - previous.totalCarbs,
        'g',
      ),
      (
        loc.nutritionProgressFat,
        current.totalFat - previous.totalFat,
        'g',
      ),
    ];
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: theme.colorScheme.outlineVariant.withAlpha(80)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              loc.nutritionProgressWeekComparison,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            for (final row in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Expanded(child: Text(row.$1)),
                    _DeltaPill(value: row.$2, unit: row.$3),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DeltaPill extends StatelessWidget {
  final double value;
  final String unit;

  const _DeltaPill({required this.value, required this.unit});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final positive = value > 0;
    final label = '${positive ? '+' : ''}${_format(value)} $unit';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: (positive
                ? theme.colorScheme.primary
                : theme.colorScheme.secondary)
            .withAlpha(30),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: positive
              ? theme.colorScheme.primary
              : theme.colorScheme.secondary,
        ),
      ),
    );
  }

  static String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}
