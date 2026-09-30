import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Year calendar of the distance run each day (see [ActivityHeatmap]).
class RunHeatmap extends StatelessWidget {
  final int year;

  /// Meters per local calendar day.
  final Map<DateTime, double> daily;
  final DateTime today;

  const RunHeatmap({
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
      dayLabel: (date, meters) =>
          loc.runInsightsHeatDay(date, RunFormatters.distanceWithUnit(meters)),
      restLabel: loc.runInsightsHeatRest,
      activeDaysLabel: loc.runInsightsActiveDays,
    );
  }
}
