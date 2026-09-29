import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/utils/strength_workout_format.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

String strengthRecordKindLabel(AppLocalizations loc, StrengthRecordKind kind) =>
    switch (kind) {
      StrengthRecordKind.e1rm => loc.workoutDetailRecordE1rm,
      StrengthRecordKind.weight => loc.workoutDetailRecordWeight,
    };

/// Personal records set in this workout, one row per exercise and kind.
class StrengthWorkoutRecordsCard extends StatelessWidget {
  final List<StrengthRecordEvent> records;

  const StrengthWorkoutRecordsCard({super.key, required this.records});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final tint = Theme.of(context).colorScheme.tertiary;
    return RunSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: RunDividedList(
        children: [
          for (final record in records)
            RunListRow(
              leading: RunIconBadge(Icons.emoji_events_rounded, color: tint),
              title: ExerciseLocaleHelper.exerciseName(loc, record.exerciseRow),
              subtitle:
                  '${strengthRecordKindLabel(loc, record.kind)} · '
                  '${StrengthWorkoutFormat.setLabel(record.weight, record.reps)}',
              value: StrengthWorkoutFormat.weightKg(record.value),
              valueCaption: record.improvement == null
                  ? null
                  : '+${StrengthWorkoutFormat.weightKg(record.improvement!)}',
            ),
        ],
      ),
    );
  }
}
