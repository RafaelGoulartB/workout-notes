import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Year calendar of the working sets done each day (see [ActivityHeatmap]).
class StrengthHeatmap extends StatelessWidget {
  final int year;

  /// Working sets per local calendar day.
  final Map<DateTime, double> daily;
  final DateTime today;

  const StrengthHeatmap({
    super.key,
    required this.year,
    required this.daily,
    required this.today,
  });

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return ActivityHeatmap(
      year: year,
      daily: daily,
      today: today,
      dayLabel: (date, sets) => loc.strengthInsightsHeatDay(
        date,
        loc.strengthInsightsSetsCount(sets.round()),
      ),
      restLabel: loc.strengthInsightsHeatRest,
      activeDaysLabel: loc.strengthInsightsActiveDays,
    );
  }
}
