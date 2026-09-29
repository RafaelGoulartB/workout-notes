import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/sleep/sleep_duration_chart.dart';
import 'package:workout_notes/widgets/sleep/sleep_schedule_chart.dart';
import 'package:workout_notes/widgets/sleep/sleep_ui.dart';

enum SleepWeekView { duration, schedule }

/// One card for the selected week: average, regularity, efficiency and
/// nights recorded, then a duration or schedule chart behind a tab switch.
class SleepWeekCard extends StatefulWidget {
  final SleepDashboardStats stats;
  final List<SleepEntry> entries;
  final List<DateTime> days;
  final int goalMinutes;

  const SleepWeekCard({
    super.key,
    required this.stats,
    required this.entries,
    required this.days,
    required this.goalMinutes,
  });

  @override
  State<SleepWeekCard> createState() => _SleepWeekCardState();
}

class _SleepWeekCardState extends State<SleepWeekCard> {
  SleepWeekView _view = SleepWeekView.duration;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final loc = AppLocalizations.of(context)!;
    final stats = widget.stats;
    final first = widget.days.first;
    final last = widget.days.last;
    final inWeek = widget.entries.where((entry) {
      final date = DateTime(entry.date.year, entry.date.month, entry.date.day);
      return !date.isBefore(first) && !date.isAfter(last);
    }).toList();
    final average = inWeek.isEmpty
        ? null
        : (inWeek
                      .map((entry) => entry.effectiveSleepMinutes)
                      .reduce((a, b) => a + b) /
                  inWeek.length)
              .round();

    return RunSectionCard(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          RunStatRow(
            children: [
              RunStatTile(
                label: loc.sleepAverageSleep,
                value: SleepUi.duration(loc, average),
              ),
              Tooltip(
                message: loc.sleepRegularityInfo,
                triggerMode: TooltipTriggerMode.tap,
                showDuration: const Duration(seconds: 5),
                child: RunStatTile(
                  label: loc.sleepRegularity,
                  value: stats.regularity7Days == null
                      ? '--'
                      : '${stats.regularity7Days!.round()}%',
                ),
              ),
              RunStatTile(
                label: loc.sleepEfficiency,
                value: stats.efficiency7Days == null
                    ? '--'
                    : '${stats.efficiency7Days!.round()}%',
                color: SleepUi.efficiencyColor(colors, stats.efficiency7Days),
              ),
              RunStatTile(
                label: loc.sleepNightsShort,
                value: '${stats.recordedDays7Days}/7',
              ),
            ],
          ),
          const SizedBox(height: 16),
          RunSegmentedTabs<SleepWeekView>(
            values: SleepWeekView.values,
            selected: _view,
            labelOf: (view) => switch (view) {
              SleepWeekView.duration => loc.sleepWeekTabDuration,
              SleepWeekView.schedule => loc.sleepWeekTabSchedule,
            },
            onChanged: (view) => setState(() => _view = view),
          ),
          const SizedBox(height: 16),
          switch (_view) {
            SleepWeekView.duration => SleepDurationChart(
              entries: widget.entries,
              days: widget.days,
              goalMinutes: widget.goalMinutes,
            ),
            SleepWeekView.schedule => SleepScheduleChart(
              entries: widget.entries,
              days: widget.days,
            ),
          },
        ],
      ),
    );
  }
}
