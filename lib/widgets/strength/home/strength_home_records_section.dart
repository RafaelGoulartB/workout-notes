import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/widgets/ui/ui.dart';
import 'package:workout_notes/widgets/strength/home/strength_home_format.dart';

/// The latest personal records: exercise, new estimated 1RM or load, the
/// improvement over the previous best and the date.
class StrengthRecentRecords extends StatelessWidget {
  final List<StrengthRecordEvent> records;
  final VoidCallback onOpen;

  const StrengthRecentRecords({
    super.key,
    required this.records,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;

    if (records.isEmpty) {
      return AppSectionCard(
        onTap: onOpen,
        child: Row(
          children: [
            AppIconBadge(Icons.emoji_events_outlined, color: colors.tertiary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                loc.strengthHomeRecordsEmpty,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    // One row per exercise and session: a set that beat both the heaviest
    // load and the estimated 1RM shows once, as the load record.
    final rows = <StrengthRecordEvent>[];
    final both = <StrengthRecordEvent>{};
    for (final event in records) {
      final i = rows.indexWhere(
        (r) =>
            r.exerciseId == event.exerciseId && r.workoutId == event.workoutId,
      );
      if (i < 0) {
        rows.add(event);
      } else {
        if (event.kind == StrengthRecordKind.weight) rows[i] = event;
        both.add(rows[i]);
      }
    }

    String kindLabel(StrengthRecordEvent event) => both.contains(event)
        ? loc.strengthHomeRecordBoth
        : event.kind == StrengthRecordKind.e1rm
        ? loc.strengthHomeRecordE1rm
        : loc.strengthHomeRecordWeight;

    return AppSectionCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: AppDividedList(
        children: [
          for (final event in rows.take(4))
            AppListRow(
              leading: AppIconBadge(
                Icons.emoji_events_outlined,
                color: colors.tertiary,
                size: 40,
              ),
              title: ExerciseLocaleHelper.exerciseName(loc, event.exerciseRow),
              subtitle:
                  '${kindLabel(event)}'
                  ' · ${StrengthHomeFormat.shortDate(context, event.date)}',
              value: StrengthHomeFormat.weight(event.value),
              valueCaption: event.improvement == null
                  ? loc.strengthHomeRecordFirst
                  : '+${StrengthHomeFormat.weight(event.improvement!)}',
              onTap: onOpen,
            ),
        ],
      ),
    );
  }
}
