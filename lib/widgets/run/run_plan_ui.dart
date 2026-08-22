import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_plan.dart';
import 'package:workout_notes/models/run_plan_workout.dart';
import 'package:workout_notes/models/run_voice_settings.dart';
import 'package:workout_notes/models/run_workout_step.dart';
import 'package:workout_notes/models/scheduled_run.dart';

/// Shared labels, colours and formatters for the running-plan screens.
/// Keeping them in one place stops the plan editor, the calendar and the record
/// screen from drifting apart on how a session is described.
abstract final class RunPlanUi {
  static String kindLabel(AppLocalizations loc, RunWorkoutKind kind) =>
      switch (kind) {
        RunWorkoutKind.easy => loc.runWorkoutKindEasy,
        RunWorkoutKind.long => loc.runWorkoutKindLong,
        RunWorkoutKind.tempo => loc.runWorkoutKindTempo,
        RunWorkoutKind.interval => loc.runWorkoutKindInterval,
        RunWorkoutKind.fartlek => loc.runWorkoutKindFartlek,
        RunWorkoutKind.hills => loc.runWorkoutKindHills,
        RunWorkoutKind.progression => loc.runWorkoutKindProgression,
        RunWorkoutKind.recovery => loc.runWorkoutKindRecovery,
        RunWorkoutKind.race => loc.runWorkoutKindRace,
      };

  static IconData kindIcon(RunWorkoutKind kind) => switch (kind) {
    RunWorkoutKind.easy => Icons.directions_run,
    RunWorkoutKind.long => Icons.timeline,
    RunWorkoutKind.tempo => Icons.speed,
    RunWorkoutKind.interval => Icons.repeat,
    RunWorkoutKind.fartlek => Icons.shuffle,
    RunWorkoutKind.hills => Icons.terrain,
    RunWorkoutKind.progression => Icons.trending_up,
    RunWorkoutKind.recovery => Icons.self_improvement,
    RunWorkoutKind.race => Icons.emoji_events,
  };

  static Color kindColor(ColorScheme scheme, RunWorkoutKind kind) =>
      switch (kind) {
        RunWorkoutKind.easy => scheme.primary,
        RunWorkoutKind.recovery => scheme.tertiary,
        RunWorkoutKind.long => scheme.secondary,
        RunWorkoutKind.tempo ||
        RunWorkoutKind.interval ||
        RunWorkoutKind.hills ||
        RunWorkoutKind.fartlek => scheme.error,
        RunWorkoutKind.progression => scheme.secondary,
        RunWorkoutKind.race => scheme.error,
      };

  static String goalLabel(AppLocalizations loc, RunPlanGoalKind goal) =>
      switch (goal) {
        RunPlanGoalKind.base => loc.runPlanGoalBase,
        RunPlanGoalKind.fiveK => loc.runPlanGoal5k,
        RunPlanGoalKind.tenK => loc.runPlanGoal10k,
        RunPlanGoalKind.half => loc.runPlanGoalHalf,
        RunPlanGoalKind.marathon => loc.runPlanGoalMarathon,
        RunPlanGoalKind.maintenance => loc.runPlanGoalMaintenance,
      };

  static String roleLabel(AppLocalizations loc, RunStepRole role) =>
      switch (role) {
        RunStepRole.warmup => loc.runWorkoutStepRoleWarmup,
        RunStepRole.work => loc.runWorkoutStepRoleWork,
        RunStepRole.recovery => loc.runWorkoutStepRoleRecovery,
        RunStepRole.steady => loc.runWorkoutStepRoleSteady,
        RunStepRole.cooldown => loc.runWorkoutStepRoleCooldown,
      };

  static Color roleColor(ColorScheme scheme, RunStepRole role) =>
      switch (role) {
        RunStepRole.work => scheme.error,
        RunStepRole.steady => scheme.secondary,
        RunStepRole.recovery => scheme.tertiary,
        RunStepRole.warmup || RunStepRole.cooldown => scheme.onSurfaceVariant,
      };

  static String statusLabel(AppLocalizations loc, ScheduledRunStatus status) =>
      switch (status) {
        ScheduledRunStatus.planned => loc.runScheduleStatusPlanned,
        ScheduledRunStatus.completed => loc.runScheduleStatusCompleted,
        ScheduledRunStatus.skipped => loc.runScheduleStatusSkipped,
      };

  /// Short weekday name (`Seg`, `Mon`) for an ISO weekday, or "any day".
  static String weekdayLabel(AppLocalizations loc, int? isoWeekday) {
    if (isoWeekday == null) return loc.runWorkoutDayAny;
    // 2024-01-01 was a Monday, so day-of-month maps onto the ISO weekday.
    final date = DateTime(2024, 1, isoWeekday.clamp(1, 7));
    return DateFormat('EEE', Intl.defaultLocale).format(date);
  }

  static String distanceLabel(double meters) {
    if (meters <= 0) return '—';
    if (meters < 1000) return '${meters.round()} m';
    final km = meters / 1000;
    return '${km.toStringAsFixed(km >= 10 ? 0 : 1).replaceAll('.', ',')} km';
  }

  static String durationLabel(int seconds) {
    if (seconds <= 0) return '—';
    final minutes = seconds ~/ 60;
    if (minutes >= 60) {
      final hours = minutes ~/ 60;
      final rest = minutes % 60;
      return rest == 0
          ? '${hours}h'
          : '${hours}h${rest.toString().padLeft(2, '0')}';
    }
    if (minutes == 0) return '${seconds}s';
    final rest = seconds % 60;
    return rest == 0
        ? '$minutes min'
        : '$minutes:${rest.toString().padLeft(2, '0')}';
  }

  /// Rounded duration for estimates — `38 min`, `1h05`. The exact form
  /// (`37:45`) reads like a pace next to `5,7 km`, and an estimate does not
  /// deserve that much precision.
  static String durationRoughLabel(int seconds) {
    if (seconds <= 0) return '—';
    final minutes = (seconds / 60).round();
    if (minutes < 60) return '${minutes < 1 ? 1 : minutes} min';
    final hours = minutes ~/ 60;
    final rest = minutes % 60;
    return rest == 0
        ? '${hours}h'
        : '${hours}h${rest.toString().padLeft(2, '0')}';
  }

  /// `4:35` for 275 s/km.
  static String paceLabel(double? secPerKm) {
    if (secPerKm == null || secPerKm <= 0 || !secPerKm.isFinite) return '—';
    final total = secPerKm.round();
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  /// `4:20–4:35` (or a single value when only one bound is set).
  static String? paceRangeLabel(double? min, double? max) {
    if (min == null && max == null) return null;
    if (min != null && max != null && (max - min).abs() > 1) {
      return '${paceLabel(min)}–${paceLabel(max)}';
    }
    return paceLabel(min ?? max);
  }

  static String stepAmountLabel(RunWorkoutStep step) =>
      step.metric == RunIntervalMetric.time
      ? durationLabel(step.value)
      : distanceLabel(step.value.toDouble());

  /// `8x 400 m` when the session has a repeated effort block. Saying `8x tiros`
  /// next to the kind label ("Tiros") repeated the same word twice and hid the
  /// one number that matters — how long each rep is.
  static String? repsLabel(RunPlanWorkout workout) {
    for (final block in blocks(workout.steps)) {
      if (!block.isRepeat) continue;
      final effort = block.steps.firstWhere(
        (step) => step.role.isEffort,
        orElse: () => block.steps.first,
      );
      return '${block.repeats}x ${stepAmountLabel(effort)}';
    }
    return null;
  }

  /// Rough total duration of a session, from the step estimates or the target.
  static int estimatedTotalSeconds(RunPlanWorkout workout) {
    if (workout.hasSteps) {
      var total = 0;
      for (final item in workout.expandSteps()) {
        total += estimatedSeconds(item.step);
      }
      return total;
    }
    final duration = workout.targetDurationSeconds;
    if (duration != null && duration > 0) return duration;
    final distance = workout.targetDistanceMeters;
    if (distance != null && distance > 0) {
      final pace = workout.targetPaceSecPerKm ?? 330;
      return (distance / 1000 * pace).round();
    }
    return 0;
  }

  /// One-line description of a session, e.g. `8x 400 m · 5,7 km`.
  static String sessionSummary(AppLocalizations loc, RunPlanWorkout workout) {
    final parts = <String>[];
    final reps = repsLabel(workout);
    if (reps != null) {
      parts.add(reps);
    } else if (workout.hasSteps) {
      parts.add(loc.runWorkoutSummarySteps(workout.steps.length));
    }
    final distance = workout.plannedDistanceMeters;
    if (distance > 0) parts.add(distanceLabel(distance));
    final duration = workout.plannedDurationSeconds;
    if (distance <= 0 && duration > 0) parts.add(durationLabel(duration));
    if (workout.targetPaceSecPerKm != null) {
      parts.add('${paceLabel(workout.targetPaceSecPerKm)}/km');
    }
    return parts.join(' · ');
  }

  /// Human-readable expansion of the steps, e.g.
  /// `2 km aquecimento → 6x (800 m + 2 min) → 1 km desaquecimento`.
  static String stepsOutline(AppLocalizations loc, RunPlanWorkout workout) {
    if (!workout.hasSteps) return '';
    final ordered = [...workout.steps]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final chunks = <String>[];
    var index = 0;
    while (index < ordered.length) {
      final group = ordered[index].repeatGroup;
      if (group == null) {
        chunks.add(
          '${stepAmountLabel(ordered[index])} '
          '${roleLabel(loc, ordered[index].role).toLowerCase()}',
        );
        index++;
        continue;
      }
      final block = <RunWorkoutStep>[];
      var cursor = index;
      while (cursor < ordered.length && ordered[cursor].repeatGroup == group) {
        block.add(ordered[cursor]);
        cursor++;
      }
      final repeats = block
          .map((step) => step.repeatCount)
          .reduce((a, b) => a > b ? a : b);
      chunks.add('${repeats}x (${block.map(stepAmountLabel).join(' + ')})');
      index = cursor;
    }
    return chunks.join(' → ');
  }

  /// Parses `4:35` or `4,35` / `4.35` (minutes per km) into seconds per km.
  static double? parsePace(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.contains(':')) {
      final parts = text.split(':');
      final minutes = int.tryParse(parts[0].trim());
      final seconds = parts.length > 1 ? int.tryParse(parts[1].trim()) : 0;
      if (minutes == null || seconds == null) return null;
      final total = minutes * 60 + seconds;
      return total <= 0 ? null : total.toDouble();
    }
    final decimal = double.tryParse(text.replaceAll(',', '.'));
    if (decimal == null || decimal <= 0) return null;
    // 4.5 means 4 min 30 s, not 4.5 s.
    final minutes = decimal.floor();
    final seconds = ((decimal - minutes) * 100).round();
    return (minutes * 60 + seconds).toDouble();
  }

  /// Editable form of a step duration: `45` stays seconds, `150` becomes
  /// `2:30`, so a 20-minute warm-up is not typed as `1200`.
  static String secondsInput(int seconds) {
    if (seconds < 60) return seconds.toString();
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  /// Parses a step duration: `90` (seconds) or `1:30` (minutes and seconds).
  static int? parseSeconds(String raw) {
    final text = raw.trim();
    if (text.isEmpty) return null;
    if (text.contains(':')) {
      final parts = text.split(':');
      final minutes = int.tryParse(parts[0].trim());
      final seconds = parts.length > 1 ? int.tryParse(parts[1].trim()) : 0;
      if (minutes == null || seconds == null) return null;
      final total = minutes * 60 + seconds;
      return total <= 0 ? null : total;
    }
    final value = int.tryParse(text);
    return value == null || value <= 0 ? null : value;
  }

  /// `21,8` — kilometres with the locale decimal separator, for the strings
  /// that already carry their own `km` suffix.
  static String kmValue(double meters) {
    final km = meters / 1000;
    return km.toStringAsFixed(km >= 100 ? 0 : 1).replaceAll('.', ',');
  }

  /// Rough duration of a step, used only to give the profile bar and the
  /// session card a sense of proportion. A distance step is converted with its
  /// own target pace when it has one, otherwise with an easy-run pace.
  static int estimatedSeconds(
    RunWorkoutStep step, {
    double fallbackPaceSecPerKm = 330,
  }) {
    if (step.metric == RunIntervalMetric.time) return step.value;
    final pace =
        step.targetPaceMinSecPerKm ??
        step.targetPaceMaxSecPerKm ??
        fallbackPaceSecPerKm;
    return (step.value / 1000 * pace).round();
  }

  /// Groups the steps the way the editor draws them: consecutive steps sharing
  /// a `repeatGroup` become one repeated block, everything else stands alone.
  /// Mirrors [RunPlanWorkout.expand] so the outline, the profile bar and the
  /// editor never disagree about where a block starts.
  static List<RunStepBlock> blocks(List<RunWorkoutStep> steps) {
    final ordered = [...steps]
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    final result = <RunStepBlock>[];
    var index = 0;
    while (index < ordered.length) {
      final group = ordered[index].repeatGroup;
      if (group == null) {
        result.add(RunStepBlock(steps: [ordered[index]], repeats: 1));
        index++;
        continue;
      }
      final block = <RunWorkoutStep>[];
      while (index < ordered.length && ordered[index].repeatGroup == group) {
        block.add(ordered[index]);
        index++;
      }
      final repeats = block
          .map((step) => step.repeatCount)
          .reduce((a, b) => a > b ? a : b);
      result.add(RunStepBlock(steps: block, repeats: repeats, group: group));
    }
    return result;
  }
}

/// A run of consecutive steps that execute together — either a single step or a
/// repeated interval block.
class RunStepBlock {
  final List<RunWorkoutStep> steps;
  final int repeats;
  final int? group;

  const RunStepBlock({required this.steps, required this.repeats, this.group});

  bool get isRepeat => group != null && repeats > 1;
}

/// Weekly-volume ramp of a plan. A training plan is a progression, and the
/// ramp (plus the taper at the end) is the thing a runner checks first — a list
/// of week chips hides it completely.
class RunPlanVolumeBars extends StatelessWidget {
  final RunPlan plan;
  final int? selectedWeek;
  final ValueChanged<int>? onWeekSelected;
  final double height;

  const RunPlanVolumeBars({
    super.key,
    required this.plan,
    this.selectedWeek,
    this.onWeekSelected,
    this.height = 44,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final volumes = [
      for (var week = 0; week < plan.weeks; week++)
        plan.weeklyDistanceMeters(week),
    ];
    final peak = volumes.fold<double>(
      0,
      (max, value) => value > max ? value : max,
    );

    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var week = 0; week < volumes.length; week++)
            Expanded(
              child: GestureDetector(
                onTap: onWeekSelected == null
                    ? null
                    : () => onWeekSelected!(week),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: DecoratedBox(
                    // A faint track behind every bar: a plan with equal weeks
                    // would otherwise render as one solid rectangle.
                    decoration: BoxDecoration(
                      color: scheme.onSurfaceVariant.withAlpha(28),
                      borderRadius: BorderRadius.circular(3),
                    ),
                    child: Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        height: peak <= 0
                            ? 3
                            : (3 + (height - 3) * (volumes[week] / peak)),
                        decoration: BoxDecoration(
                          color: week == selectedWeek
                              ? scheme.primary
                              : scheme.primary.withAlpha(120),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Horizontal profile of a session: one coloured segment per executed step,
/// sized by its estimated duration. Reading `2 km fácil → 6×(800 m forte + 2
/// min trote) → 1 km fácil` off a sentence takes effort; the shape is instant.
class RunWorkoutProfileBar extends StatelessWidget {
  final RunPlanWorkout workout;
  final double height;

  const RunWorkoutProfileBar({
    super.key,
    required this.workout,
    this.height = 10,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final expanded = workout.expandSteps();

    if (expanded.isEmpty) {
      // A continuous run has no steps — draw it as one flat effort block so the
      // card still reads as a session rather than as missing data.
      return ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Container(
          height: height,
          color: RunPlanUi.kindColor(scheme, workout.kind).withAlpha(70),
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: SizedBox(
        height: height,
        child: Row(
          // Stretch, or the ColoredBox segments collapse to zero height.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final item in expanded)
              Expanded(
                flex: RunPlanUi.estimatedSeconds(item.step).clamp(1, 100000),
                child: Padding(
                  padding: const EdgeInsets.only(right: 1),
                  child: ColoredBox(
                    color: RunPlanUi.roleColor(
                      scheme,
                      item.step.role,
                    ).withAlpha(item.step.role.isEffort ? 235 : 90),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Compact chip describing a step inside the session editor.
class RunStepChip extends StatelessWidget {
  final RunWorkoutStep step;
  final int? repeats;

  const RunStepChip({super.key, required this.step, this.repeats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final color = RunPlanUi.roleColor(theme.colorScheme, step.role);
    final amount = RunPlanUi.stepAmountLabel(step);
    final label = repeats != null && repeats! > 1
        ? '${repeats}x $amount'
        : amount;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        '${RunPlanUi.roleLabel(loc, step.role)} · $label',
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
