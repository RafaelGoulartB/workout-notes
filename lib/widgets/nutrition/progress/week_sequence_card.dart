import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/repositories/nutrition_repository.dart';
import 'package:workout_notes/widgets/nutrition/progress/progress_shared.dart';
import 'package:workout_notes/models/nutrition/nutrition_progress.dart';

Color _colorForStatus(BalanceStatus s, ThemeData theme) {
  return switch (s) {
    BalanceStatus.deficit => const Color(0xFF2BB673),
    BalanceStatus.surplus => theme.colorScheme.error,
    BalanceStatus.maintaining => theme.colorScheme.primary,
    BalanceStatus.noGoal => theme.colorScheme.onSurfaceVariant,
  };
}

String _labelForStatus(BalanceStatus s, AppLocalizations loc) {
  return switch (s) {
    BalanceStatus.deficit => loc.nutritionBalanceStatusDeficit,
    BalanceStatus.surplus => loc.nutritionBalanceStatusSurplus,
    BalanceStatus.maintaining => loc.nutritionBalanceStatusMaintaining,
    BalanceStatus.noGoal => loc.nutritionBalanceStatusNoGoal,
  };
}

class WeekSequenceCard extends StatelessWidget {
  final List<DailyCalorieTotal> dailies;
  final double? goal;
  final CalorieBalance? balance;
  final BalancePeriod period;

  const WeekSequenceCard({
    super.key,
    required this.dailies,
    required this.goal,
    required this.balance,
    required this.period,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final hasGoal = goal != null && goal! > 0;
    final status = NutritionProgressCalculator.statusFor(balance, hasGoal);
    final statusColor = _colorForStatus(status, theme);
    final statusLabel = _labelForStatus(status, loc);
    final caloriesValue = balance?.balance;
    final today = DateTime.now();
    final sequenceItems = period == BalancePeriod.month
        ? NutritionProgressCalculator.monthlySequence(
            dailies,
            today,
            loc.nutritionBalanceWeekNumber,
          )
        : NutritionProgressCalculator.dailySequence(dailies, today);
    final bands = NutritionProgressCalculator.bandCounts(sequenceItems, goal);
    final logged = bands.logged;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Ink(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(90),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: statusColor.withAlpha(30),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      period == BalancePeriod.month
                          ? Icons.calendar_view_month_outlined
                          : Icons.view_week_outlined,
                      size: 16,
                      color: statusColor,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      period == BalancePeriod.month
                          ? loc.nutritionBalanceMonthSequence
                          : loc.nutritionBalanceWeekSequence,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      statusLabel.toUpperCase(),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              if (caloriesValue == null)
                Text(
                  loc.nutritionBalanceNoGoal,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      NutritionProgressCalculator.signedKcal(caloriesValue),
                      style: theme.textTheme.headlineLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: statusColor,
                        height: 1,
                      ),
                    ),
                    const SizedBox(width: 5),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        'kcal',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const Spacer(),
                    if (caloriesValue.abs() >= 1)
                      Text(
                        loc.nutritionBalanceFatEquivalent(
                          NutritionProgressCalculator.formatFatKg(
                            caloriesValue.abs(),
                          ),
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: BalanceMetric(
                      label: loc.nutritionBalanceDaysLogged,
                      value: '${balance?.daysLogged ?? 0}/${dailies.length}',
                    ),
                  ),
                  Expanded(
                    child: BalanceMetric(
                      label: loc.nutritionBalanceAverageIntake,
                      value:
                          '${NutritionProgressCalculator.formatKcal(balance?.averageDailyIntake ?? 0)} kcal',
                      sub: hasGoal
                          ? loc.nutritionBalanceGoalKcal(
                              NutritionProgressCalculator.formatKcal(goal!),
                            )
                          : null,
                    ),
                  ),
                  Expanded(
                    child: BalanceMetric(
                      label: loc.nutritionBalanceCurrentStreak,
                      value: balance == null
                          ? '—'
                          : loc.nutritionBalanceStreakDays(
                              balance!.currentStreak,
                            ),
                      valueColor: (balance?.currentStreak ?? 0) > 0
                          ? statusColor
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Divider(color: theme.colorScheme.outlineVariant.withAlpha(90)),
              const SizedBox(height: 10),
              Row(
                children: [
                  for (var index = 0; index < sequenceItems.length; index++)
                    Expanded(
                      child: WeekDayCell(
                        key: period == BalancePeriod.month
                            ? ValueKey('balance-month-week-${index + 1}')
                            : null,
                        date: sequenceItems[index].date,
                        label: sequenceItems[index].label,
                        isHighlighted: sequenceItems[index].isHighlighted,
                        calories: sequenceItems[index].calories,
                        goal: goal,
                        hasGoal: hasGoal,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              if (!hasGoal)
                ProgressEmptyNote(text: loc.nutritionProgressNoGoal)
              else if (logged == 0)
                Text(
                  loc.nutritionBalanceNoDaysLogged,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else
                WeekSequenceSummary(
                  deficit: bands.deficit,
                  onTarget: bands.onTarget,
                  surplus: bands.surplus,
                  logged: bands.logged,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class BalanceMetric extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;

  const BalanceMetric({
    super.key,
    required this.label,
    required this.value,
    this.sub,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: valueColor ?? theme.colorScheme.onSurface,
            height: 1.0,
          ),
        ),
        if (sub != null) ...[
          const SizedBox(height: 3),
          Text(
            sub!,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 10,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

/// Compact summary row for the week sequence. Renders a single line
/// with the deficit / on-target / surplus counts plus the contextual
/// insight. Replaces the former standalone "Day distribution" card,
/// which duplicated the per-cell status the sequence already shows.
class WeekSequenceSummary extends StatelessWidget {
  final int deficit;
  final int onTarget;
  final int surplus;
  final int logged;

  const WeekSequenceSummary({
    super.key,
    required this.deficit,
    required this.onTarget,
    required this.surplus,
    required this.logged,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Row(
      children: [
        CountChip(
          label: loc.nutritionBalanceStatusDeficit,
          count: deficit,
          color: kDeficitColor,
        ),
        const SizedBox(width: 6),
        CountChip(
          label: loc.nutritionBalanceStatusMaintaining,
          count: onTarget,
          color: kOnTargetColor,
        ),
        const SizedBox(width: 6),
        CountChip(
          label: loc.nutritionBalanceStatusSurplus,
          count: surplus,
          color: kSurplusColor,
        ),
      ],
    );
  }
}

class CountChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const CountChip({
    super.key,
    required this.label,
    required this.count,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: color.withAlpha(28),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: theme.textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class WeekDayCell extends StatelessWidget {
  final DateTime date;
  final String? label;
  final bool isHighlighted;
  final double? calories;
  final double? goal;
  final bool hasGoal;

  const WeekDayCell({
    super.key,
    required this.date,
    required this.label,
    required this.isHighlighted,
    required this.calories,
    required this.goal,
    required this.hasGoal,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dow =
        label ?? DateFormat.E(Intl.defaultLocale).format(date).substring(0, 1);
    final (status, color) = _resolveStatus();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        children: [
          Text(
            dow.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: isHighlighted
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 0.72,
            child: Container(
              decoration: BoxDecoration(
                color: _bgColor(color, theme),
                borderRadius: BorderRadius.circular(10),
                border: isHighlighted
                    ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                    : null,
              ),
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (calories == null)
                    Text(
                      '—',
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    )
                  else ...[
                    Text(
                      _formatShort(calories!),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: color,
                        height: 1.0,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'kcal',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: color.withAlpha(180),
                        fontSize: 9,
                        height: 1.0,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (hasGoal && calories != null) ...[
            const SizedBox(height: 5),
            DayDeltaPill(delta: calories! - goal!, color: color),
          ],
        ],
      ),
    );
  }

  String _formatShort(double v) {
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}k';
    return v.round().toString();
  }

  Color _bgColor(Color status, ThemeData theme) {
    if (status == Colors.transparent) {
      return theme.colorScheme.surfaceContainerHighest.withAlpha(120);
    }
    return status.withAlpha(40);
  }

  (DayStatus, Color) _resolveStatus() {
    final status = NutritionProgressCalculator.dayStatus(
      hasGoal ? calories : null,
      goal,
    );
    return (
      status,
      switch (status) {
        DayStatus.onTarget => kOnTargetColor,
        DayStatus.deficit => kDeficitColor,
        DayStatus.surplus => kSurplusColor,
        DayStatus.unknown => Colors.transparent,
      },
    );
  }
}

class DayDeltaPill extends StatelessWidget {
  final double delta;
  final Color color;
  const DayDeltaPill({super.key, required this.delta, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final abs = delta.abs();
    final label = abs >= 1000
        ? '${delta < 0 ? '-' : '+'}${(abs / 1000).toStringAsFixed(1)}k'
        : '${delta < 0 ? '-' : '+'}${abs.round()}';
    return Text(
      label,
      style: theme.textTheme.labelSmall?.copyWith(
        color: color,
        fontWeight: FontWeight.w700,
        fontSize: 10,
        height: 1.0,
      ),
    );
  }
}
