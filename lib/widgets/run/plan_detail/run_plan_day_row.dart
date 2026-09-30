import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/services/run_plan_week_view.dart';

/// Builds the card of a session; [preview] is the drag feedback (no actions).
typedef RunPlanSessionCardBuilder =
    Widget Function(RunPlanSessionView view, {required bool preview});

/// A weekday (with its real date when the plan is followed) and whatever is
/// planned on it, or an explicit rest marker: a week with four rest days is a
/// light week, which is information too.
class RunPlanDayRow extends StatelessWidget {
  final int? dayOfWeek;
  final String label;

  /// Calendar date of the row; null when the plan is not followed.
  final DateTime? date;
  final bool isToday;
  final List<RunPlanSessionView> sessions;
  final RunPlanSessionCardBuilder cardBuilder;
  final VoidCallback? onAdd;
  final void Function(RunPlanWorkout workout, int dayOfWeek) onMoveToDay;

  /// Runner strength suggested for this day, if any.
  final Widget? strength;

  const RunPlanDayRow({
    super.key,
    required this.dayOfWeek,
    required this.label,
    required this.date,
    required this.isToday,
    required this.sessions,
    required this.cardBuilder,
    required this.onMoveToDay,
    this.onAdd,
    this.strength,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DayLabel(label: label, date: date, isToday: isToday),
          const SizedBox(width: 6),
          Expanded(
            child: DragTarget<RunPlanWorkout>(
              key: dayOfWeek == null
                  ? null
                  : ValueKey('run-plan-day-$dayOfWeek'),
              onWillAcceptWithDetails: (details) =>
                  dayOfWeek != null && details.data.dayOfWeek != dayOfWeek,
              onAcceptWithDetails: (details) {
                final targetDay = dayOfWeek;
                if (targetDay != null) onMoveToDay(details.data, targetDay);
              },
              builder: (context, candidates, rejected) {
                final isTarget = candidates.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: isTarget ? const EdgeInsets.all(3) : EdgeInsets.zero,
                  decoration: BoxDecoration(
                    color: isTarget
                        ? scheme.primaryContainer.withAlpha(90)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: isTarget
                        ? Border.all(color: scheme.primary, width: 1.5)
                        : null,
                  ),
                  child: sessions.isEmpty && strength != null
                      ? strength!
                      : sessions.isEmpty
                      ? _RestRow(onAdd: onAdd)
                      : Column(
                          children: [
                            for (final session in sessions)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: LongPressDraggable<RunPlanWorkout>(
                                  data: session.workout,
                                  hapticFeedbackOnStart: true,
                                  feedback: Material(
                                    color: Colors.transparent,
                                    elevation: 8,
                                    borderRadius: BorderRadius.circular(14),
                                    child: SizedBox(
                                      width:
                                          (MediaQuery.sizeOf(context).width -
                                                  96)
                                              .clamp(220.0, 360.0)
                                              .toDouble(),
                                      child: cardBuilder(
                                        session,
                                        preview: true,
                                      ),
                                    ),
                                  ),
                                  childWhenDragging: Opacity(
                                    opacity: 0.25,
                                    child: cardBuilder(session, preview: false),
                                  ),
                                  child: cardBuilder(session, preview: false),
                                ),
                              ),
                            ?strength,
                          ],
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// `TER` over `30/09`; today's row is highlighted and says so.
class _DayLabel extends StatelessWidget {
  final String label;
  final DateTime? date;
  final bool isToday;

  const _DayLabel({
    required this.label,
    required this.date,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toString();
    final color = isToday ? scheme.primary : scheme.onSurfaceVariant;
    return Container(
      width: 46,
      margin: const EdgeInsets.only(top: 2),
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: isToday ? scheme.primary.withAlpha(28) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          Text(
            label.replaceAll('.', '').toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
          if (date != null)
            Text(
              DateFormat('dd/MM', locale).format(date!),
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          if (isToday)
            Text(
              loc.runPlanDetailToday.toUpperCase(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: scheme.primary,
                letterSpacing: 0.4,
              ),
            ),
        ],
      ),
    );
  }
}

class _RestRow extends StatelessWidget {
  final VoidCallback? onAdd;

  const _RestRow({this.onAdd});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return InkWell(
      onTap: onAdd,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withAlpha(70),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                loc.runPlanRestDay,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                ),
              ),
            ),
            if (onAdd != null)
              Icon(
                Icons.add,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
              ),
          ],
        ),
      ),
    );
  }
}
