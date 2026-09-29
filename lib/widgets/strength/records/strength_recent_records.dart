import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/l10n/exercise_locale_helper.dart';
import 'package:workout_notes/repositories/strength_records_repository.dart';
import 'package:workout_notes/utils/strength_insights_format.dart';
import 'package:workout_notes/widgets/run/insights/run_insight_card.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Timeline of the latest personal bests, newest first.
class StrengthRecentRecords extends StatefulWidget {
  final List<StrengthRecordEvent> events;
  final void Function(StrengthRecordEvent event) onOpen;

  const StrengthRecentRecords({
    super.key,
    required this.events,
    required this.onOpen,
  });

  @override
  State<StrengthRecentRecords> createState() => _StrengthRecentRecordsState();
}

class _StrengthRecentRecordsState extends State<StrengthRecentRecords> {
  static const _page = 8;
  int _shown = _page;

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final now = DateTime.now();

    if (widget.events.isEmpty) {
      return RunSectionCard(
        child: RunInsightsNote(loc.strengthRecordsRecentEmpty),
      );
    }

    final visible = widget.events.take(_shown).toList();
    return RunSectionCard(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RunDividedList(
            children: [
              for (final e in visible)
                RunListRow(
                  leading: RunIconBadge(
                    e.kind == StrengthRecordKind.e1rm
                        ? Icons.emoji_events_rounded
                        : Icons.fitness_center_rounded,
                    color: e.kind == StrengthRecordKind.e1rm
                        ? colors.tertiary
                        : colors.primary,
                  ),
                  title: ExerciseLocaleHelper.exerciseName(loc, e.exerciseRow),
                  subtitle:
                      '${e.kind == StrengthRecordKind.e1rm ? loc.strengthRecordsKindE1rm : loc.strengthRecordsKindWeight}'
                      ' · ${StrengthFormat.weight(e.weight)} × ${e.reps}'
                      ' · ${(e.date.year == now.year ? DateFormat.MMMd(locale) : DateFormat.yMMMd(locale)).format(e.date)}',
                  value: '${StrengthFormat.weight(e.value)} kg',
                  valueCaption: e.improvement == null
                      ? null
                      : loc.strengthRecordsImprovement(
                          StrengthFormat.weight(e.improvement!),
                        ),
                  onTap: () => widget.onOpen(e),
                ),
            ],
          ),
          if (widget.events.length > visible.length)
            TextButton(
              onPressed: () => setState(() => _shown += _page),
              child: Text(loc.strengthInsightsShowMore),
            ),
        ],
      ),
    );
  }
}
