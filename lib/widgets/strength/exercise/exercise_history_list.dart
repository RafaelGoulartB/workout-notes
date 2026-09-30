import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/strength_insights_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// One workout of the exercise, from `AnalyticsRepository.getExerciseHistory`.
class ExerciseSession {
  final String workoutId;
  final DateTime date;
  final List<({double weight, int reps, double? e1rm})> sets;
  final double maxWeight;
  final double volume;
  final int totalReps;
  final double? e1rm;
  final double bestSetWeight;
  final int bestSetReps;

  const ExerciseSession({
    required this.workoutId,
    required this.date,
    required this.sets,
    required this.maxWeight,
    required this.volume,
    required this.totalReps,
    required this.e1rm,
    required this.bestSetWeight,
    required this.bestSetReps,
  });

  factory ExerciseSession.fromRow(Map<String, dynamic> row) {
    final best = (row['best_set'] as Map?) ?? const {};
    return ExerciseSession(
      workoutId: row['workout_id'] as String,
      date: DateTime.parse(row['date'] as String),
      sets: [
        for (final s in (row['sets'] as List? ?? const []))
          (
            weight: ((s as Map)['weight'] as num?)?.toDouble() ?? 0,
            reps: (s['reps'] as num?)?.toInt() ?? 0,
            e1rm: (s['e1rm'] as num?)?.toDouble(),
          ),
      ],
      maxWeight: (row['max_weight'] as num?)?.toDouble() ?? 0,
      volume: (row['total_volume'] as num?)?.toDouble() ?? 0,
      totalReps: (row['total_reps'] as num?)?.toInt() ?? 0,
      e1rm: (row['estimated_1rm'] as num?)?.toDouble(),
      bestSetWeight: (best['weight'] as num?)?.toDouble() ?? 0,
      bestSetReps: (best['reps'] as num?)?.toInt() ?? 0,
    );
  }

  /// `80 kg × 8`, or just `12 reps` for a bodyweight set.
  static String setLabel(AppLocalizations loc, double weight, int reps) =>
      weight > 0
      ? '${StrengthFormat.weight(weight)} kg × $reps'
      : '$reps ${loc.exerciseDetailMetricReps.toLowerCase()}';
}

/// Sessions newest first, each with its sets and a record badge when it set a
/// personal best.
class ExerciseHistoryList extends StatelessWidget {
  final List<ExerciseSession> sessions;
  final Set<String> recordWorkoutIds;
  final void Function(ExerciseSession session) onOpen;

  const ExerciseHistoryList({
    super.key,
    required this.sessions,
    required this.recordWorkoutIds,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toString();
    final currentYear = DateTime.now().year;
    final ordered = sessions.reversed.toList();

    return Column(
      children: [
        for (final (i, s) in ordered.indexed) ...[
          if (i > 0) const SizedBox(height: 10),
          _SessionCard(
            session: s,
            isRecord: recordWorkoutIds.contains(s.workoutId),
            dateLabel:
                (s.date.year == currentYear
                        ? DateFormat.MMMEd(locale)
                        : DateFormat.yMMMEd(locale))
                    .format(s.date),
            onTap: () => onOpen(s),
          ),
        ],
      ],
    );
  }
}

class _SessionCard extends StatelessWidget {
  final ExerciseSession session;
  final bool isRecord;
  final String dateLabel;
  final VoidCallback onTap;

  const _SessionCard({
    required this.session,
    required this.isRecord,
    required this.dateLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final s = session;

    return AppSectionCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  dateLabel,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isRecord) ...[
                AppPill(
                  label: loc.exerciseDetailRecordBadge,
                  icon: Icons.emoji_events_rounded,
                  color: colors.tertiary,
                ),
                const SizedBox(width: 4),
              ],
              Icon(Icons.chevron_right_rounded, color: colors.onSurfaceVariant),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            [
              loc.exerciseDetailSessionSets(s.sets.length),
              if (s.volume > 0)
                '${loc.commonVolume} ${StrengthFormat.volumeWithUnit(s.volume)}',
              if (s.e1rm != null)
                '${loc.exerciseDetailBestE1rm} ${RunFormatters.decimal(s.e1rm!, 0)} kg',
            ].join(' · '),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final set in s.sets)
                _SetChip(
                  label: ExerciseSession.setLabel(loc, set.weight, set.reps),
                  best:
                      set.weight == s.bestSetWeight &&
                      set.reps == s.bestSetReps,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SetChip extends StatelessWidget {
  final String label;
  final bool best;

  const _SetChip({required this.label, required this.best});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: best
            ? colors.primary.withAlpha(36)
            : colors.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: best ? FontWeight.w700 : FontWeight.w500,
          color: best ? colors.primary : colors.onSurface,
          fontFeatures: AppUi.tabular,
        ),
      ),
    );
  }
}
