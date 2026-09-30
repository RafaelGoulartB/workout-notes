import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/periodization_phase.dart';
import 'package:workout_notes/periodization/phase_kind.dart';
import 'package:workout_notes/periodization/phase_week_plan.dart';
import 'package:workout_notes/utils/date_utils.dart';

/// Shared building blocks of the planning screens. They follow the running
/// plan screens: flat tonal cards, uppercase section labels, small pills.

/// Uppercase section label with an optional trailing action.
class PlanningSectionLabel extends StatelessWidget {
  final String text;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  const PlanningSectionLabel(
    this.text, {
    super.key,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: Size.zero,
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Flat tonal card used across the planning screens.
class PlanningCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  const PlanningCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.color,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(16);
    return Material(
      color: color ?? scheme.surfaceContainerLow,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: Container(
          width: double.infinity,
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(
              color: borderColor ?? scheme.outlineVariant.withAlpha(60),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// Rounded square carrying a phase kind's icon in the phase colour.
class PhaseAvatar extends StatelessWidget {
  final Color color;
  final IconData icon;
  final double size;

  const PhaseAvatar({
    super.key,
    required this.color,
    required this.icon,
    this.size = 40,
  });

  factory PhaseAvatar.of(PeriodizationPhase phase, {double size = 40}) =>
      PhaseAvatar(
        color: Color(phase.color),
        icon: PhaseKind.fromKey(phase.templateKey).icon,
        size: size,
      );

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withAlpha(40),
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    child: Icon(icon, color: color, size: size * 0.52),
  );
}

/// Small icon + text pill used for target summaries.
class PlanningPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const PlanningPill({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = color ?? scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: (color ?? scheme.surfaceContainerHighest).withAlpha(
          color == null ? 110 : 36,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: tint),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color ?? scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The plan as a horizontal roadmap: one segment per phase, sized by its
/// length, with the phase names underneath and a marker on today.
class PlanRoadmap extends StatelessWidget {
  final List<PeriodizationPhase> phases;
  final DateTime today;
  final ValueChanged<PeriodizationPhase>? onPhaseTap;

  const PlanRoadmap({
    super.key,
    required this.phases,
    required this.today,
    this.onPhaseTap,
  });

  @override
  Widget build(BuildContext context) {
    if (phases.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final start = phases.first.startDate;
    final end = phases.last.endDate;
    final totalDays = end.difference(start).inDays + 1;
    final day = dayOf(today);
    final inside = !day.isBefore(start) && !day.isAfter(end);
    final todayFraction = inside
        ? (day.difference(start).inDays + 0.5) / totalDays
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 22,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    top: 6,
                    bottom: 4,
                    child: Row(
                      children: [
                        for (var i = 0; i < phases.length; i++) ...[
                          if (i > 0) const SizedBox(width: 3),
                          Expanded(
                            flex: phases[i].totalDays,
                            child: _Segment(
                              phase: phases[i],
                              today: day,
                              onTap: onPhaseTap == null
                                  ? null
                                  : () => onPhaseTap!(phases[i]),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (todayFraction != null)
                    Positioned(
                      left: (width * todayFraction - 1.5).clamp(0, width - 3),
                      top: 0,
                      bottom: 0,
                      child: Container(
                        width: 3,
                        decoration: BoxDecoration(
                          color: scheme.onSurface,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                for (var i = 0; i < phases.length; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    flex: phases[i].totalDays,
                    child: Text(
                      phases[i].name,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      softWrap: false,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: phases[i].contains(day)
                            ? Color(phases[i].color)
                            : scheme.onSurfaceVariant,
                        fontWeight: phases[i].contains(day)
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        );
      },
    );
  }
}

class _Segment extends StatelessWidget {
  final PeriodizationPhase phase;
  final DateTime today;
  final VoidCallback? onTap;

  const _Segment({required this.phase, required this.today, this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = Color(phase.color);
    final progress = phase.progressAt(today);
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ColoredBox(color: color.withAlpha(70)),
            FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: progress.toDouble(),
              child: ColoredBox(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seven columns (Monday → Sunday) showing what each weekday holds: a
/// strength session, a run, both, or rest — plus the day's calories.
class TemplateWeekStrip extends StatelessWidget {
  final List<PlannedWeekday> week;

  /// ISO weekday to highlight (today), if any.
  final int? highlightWeekday;

  /// Weekdays already done (a workout or run logged), shown with a check.
  final Set<int> doneWeekdays;

  /// Routine day names by strength index, to label strength days.
  final List<String> strengthLabels;
  final bool showCalories;
  final Color? accent;

  const TemplateWeekStrip({
    super.key,
    required this.week,
    this.highlightWeekday,
    this.doneWeekdays = const {},
    this.strengthLabels = const [],
    this.showCalories = true,
    this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = accent ?? scheme.primary;
    final restDiffers =
        week.map((day) => day.calories).whereType<double>().toSet().length > 1;
    return Row(
      children: [
        for (final day in week)
          Expanded(
            child: _DayColumn(
              day: day,
              tint: tint,
              highlighted: day.weekday == highlightWeekday,
              done: doneWeekdays.contains(day.weekday),
              label: day.strengthIndex == null || strengthLabels.isEmpty
                  ? null
                  : strengthLabels[day.strengthIndex! % strengthLabels.length],
              showCalories: showCalories,
              emphasizeCalories: restDiffers,
            ),
          ),
      ],
    );
  }
}

class _DayColumn extends StatelessWidget {
  final PlannedWeekday day;
  final Color tint;
  final bool highlighted;
  final bool done;
  final String? label;
  final bool showCalories;
  final bool emphasizeCalories;

  const _DayColumn({
    required this.day,
    required this.tint,
    required this.highlighted,
    required this.done,
    required this.label,
    required this.showCalories,
    required this.emphasizeCalories,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final weekday = DateFormat(
      'EEEEE',
      Intl.defaultLocale,
    ).format(DateTime(2024, 1, day.weekday));
    final training = day.trainingDay;
    final icon = day.strength && day.run
        ? Icons.bolt_rounded
        : day.strength
        ? Icons.fitness_center_rounded
        : day.run
        ? Icons.directions_run_rounded
        : Icons.remove_rounded;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        children: [
          Text(
            weekday.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: highlighted ? tint : scheme.onSurfaceVariant,
              fontWeight: highlighted ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 44, maxHeight: 44),
              decoration: BoxDecoration(
                color: done
                    ? tint
                    : training
                    ? tint.withAlpha(46)
                    : scheme.surfaceContainerHighest.withAlpha(90),
                borderRadius: BorderRadius.circular(12),
                border: highlighted ? Border.all(color: tint, width: 2) : null,
              ),
              child: Icon(
                done ? Icons.check_rounded : icon,
                size: 18,
                color: done
                    ? scheme.onPrimary
                    : training
                    ? tint
                    : scheme.onSurfaceVariant.withAlpha(140),
              ),
            ),
          ),
          if (label != null) ...[
            const SizedBox(height: 4),
            Text(
              label!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ] else if (day.runs.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              _runLabel(day),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (showCalories && day.calories != null) ...[
            const SizedBox(height: 2),
            Text(
              planningKcal(day.calories),
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: emphasizeCalories && !training
                    ? scheme.tertiary
                    : scheme.onSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _runLabel(PlannedWeekday day) {
    final meters = day.runs.fold<double>(
      0,
      (sum, run) => sum + run.plannedDistanceMeters,
    );
    if (meters <= 0) return '';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1).replaceAll('.', ',')}k';
  }
}

/// Seven round toggles for picking weekdays (1 = Monday … 7 = Sunday).
class WeekdayPicker extends StatelessWidget {
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final Color? color;

  /// Weekdays that cannot be toggled (e.g. taken by another activity);
  /// shown dimmed but still selectable.
  final Set<int> hinted;

  const WeekdayPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.color,
    this.hinted = const {},
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = color ?? scheme.primary;
    return Row(
      children: [
        for (var weekday = 1; weekday <= 7; weekday++)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AspectRatio(
                aspectRatio: 1,
                child: Material(
                  color: selected.contains(weekday)
                      ? tint
                      : scheme.surfaceContainerHighest.withAlpha(110),
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      final next = {...selected};
                      if (!next.remove(weekday)) next.add(weekday);
                      onChanged(next);
                    },
                    child: Center(
                      child: Text(
                        DateFormat(
                          'EEEEE',
                          Intl.defaultLocale,
                        ).format(DateTime(2024, 1, weekday)).toUpperCase(),
                        style: theme.textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: selected.contains(weekday)
                              ? scheme.onPrimary
                              : hinted.contains(weekday)
                              ? tint
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Compact "− value +" control.
class PlanningStepper extends StatelessWidget {
  final String value;
  final VoidCallback? onDecrement;
  final VoidCallback? onIncrement;

  const PlanningStepper({
    super.key,
    required this.value,
    this.onDecrement,
    this.onIncrement,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withAlpha(110),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onDecrement == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onDecrement!();
                  },
            icon: const Icon(Icons.remove_rounded, size: 18),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 44),
            child: Text(
              value,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            onPressed: onIncrement == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onIncrement!();
                  },
            icon: const Icon(Icons.add_rounded, size: 18),
          ),
        ],
      ),
    );
  }
}

/// Status line of a phase relative to today: done, now (week X of Y) or
/// starting in N weeks.
String phaseStatusLabel(
  AppLocalizations loc,
  PeriodizationPhase phase,
  DateTime today,
) {
  final day = dayOf(today);
  if (phase.endDate.isBefore(day)) return loc.planningPhaseDone;
  if (phase.contains(day)) {
    return loc.planningWeekOf(phase.weekAt(day), phase.totalWeeks);
  }
  final weeks = (phase.startDate.difference(day).inDays / 7).ceil();
  return loc.planningStartsInWeeks(weeks);
}

/// "24 ago – 15 nov" in the app locale.
String planningDateRange(DateTime start, DateTime end) {
  final format = DateFormat('d MMM', Intl.defaultLocale);
  final sameYear = start.year == end.year;
  final endFormat = sameYear
      ? format
      : DateFormat('d MMM y', Intl.defaultLocale);
  return '${format.format(start)} – ${endFormat.format(end)}';
}

String planningKcal(double? value) => value == null
    ? '—'
    : NumberFormat.decimalPattern(Intl.defaultLocale).format(value.round());

/// Localized message for a [PeriodizationValidationException] code.
String planningErrorMessage(AppLocalizations loc, String code) =>
    switch (code) {
      'name_required' => loc.planningNameRequired,
      'invalid_target' || 'invalid_target_range' => loc.planningInvalidTarget,
      'routine_not_found' => loc.planningRoutineMissing,
      'plan_requires_phase' => loc.planningPlanNeedsPhase,
      _ => loc.planningSaveFailed(code),
    };
