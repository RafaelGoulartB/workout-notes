import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Headline numbers of the records screen: exercises with marks and how many
/// records were broken this month and this year.
class StrengthRecordsHero extends StatelessWidget {
  final int exercises;
  final int thisMonth;
  final int thisYear;

  const StrengthRecordsHero({
    super.key,
    required this.exercises,
    required this.thisMonth,
    required this.thisYear,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final colors = Theme.of(context).colorScheme;
    return AppHeroCard(
      child: Row(
        children: [
          AppIconBadge(
            Icons.emoji_events_rounded,
            color: colors.tertiary,
            size: 44,
            iconSize: 24,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: AppStatRow(
              children: [
                AppStatTile(
                  label: loc.strengthRecordsHeroExercises,
                  value: '$exercises',
                ),
                AppStatTile(
                  label: loc.strengthRecordsHeroThisMonth,
                  value: '$thisMonth',
                  color: colors.tertiary,
                ),
                AppStatTile(
                  label: loc.strengthRecordsHeroThisYear,
                  value: '$thisYear',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
