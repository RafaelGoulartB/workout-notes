import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

/// A GitHub-style contribution heatmap showing workout intensity.
///
/// For the current year, weeks stop at today (no empty future columns).
/// The list is reversed horizontally so the most recent week sits against
/// the right edge of the card.
class WorkoutHeatmap extends StatelessWidget {
  final Map<String, int> dailyData;
  final int year;

  const WorkoutHeatmap({
    super.key,
    required this.dailyData,
    required this.year,
  });

  static const _cellSize = 12.0;
  static const _cellGap = 2.0;
  static const _labelWidth = 14.0;

  DateTime get _rangeEnd {
    final now = DateTime.now();
    final yearEnd = DateTime(year, 12, 31);
    if (year < now.year) return yearEnd;
    if (year > now.year) return DateTime(year, 1, 1);
    return DateTime(now.year, now.month, now.day);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final Map<int, Map<int, int>> grid = {};
    var maxVolume = 0;

    final firstDay = DateTime(year, 1, 1);
    final lastDay = _rangeEnd;

    if (lastDay.isBefore(firstDay)) {
      return _empty(context, theme);
    }

    for (var d = firstDay;
        !d.isAfter(lastDay);
        d = d.add(const Duration(days: 1))) {
      final dateStr = d.toIso8601String().substring(0, 10);
      final volume = dailyData[dateStr] ?? 0;

      final dayOfYear = d.difference(firstDay).inDays;
      final weekIndex = dayOfYear ~/ 7;
      final dayOfWeek = d.weekday % 7; // 0=Sunday

      grid.putIfAbsent(weekIndex, () => {});
      grid[weekIndex]![dayOfWeek] = volume;
      if (volume > maxVolume) maxVolume = volume;
    }

    // Newest week first — with reverse:true this lands on the right edge.
    final weekIndexes = grid.keys.toList()..sort((a, b) => b.compareTo(a));
    if (weekIndexes.isEmpty) {
      return _empty(context, theme);
    }

    final dayLabels = [
      AppLocalizations.of(context)!.calendarSun,
      AppLocalizations.of(context)!.calendarMon,
      AppLocalizations.of(context)!.calendarTue,
      AppLocalizations.of(context)!.calendarWed,
      AppLocalizations.of(context)!.calendarThu,
      AppLocalizations.of(context)!.calendarFri,
      AppLocalizations.of(context)!.calendarSat,
    ];

    return SizedBox(
      height: 7 * (_cellSize + _cellGap) + 4,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        // [newest week … oldest week, day labels]
        // reverse:true → day labels on the left, newest on the right.
        itemCount: weekIndexes.length + 1,
        itemBuilder: (context, col) {
          final isLabelColumn = col == weekIndexes.length;
          if (isLabelColumn) {
            return Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: dayLabels.asMap().entries.map((e) {
                return Container(
                  width: _labelWidth,
                  height: _cellSize + _cellGap,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    dayLabels[e.key].substring(0, 1),
                    style: TextStyle(
                      fontSize: 8,
                      color: theme.colorScheme.onSurfaceVariant.withAlpha(150),
                    ),
                  ),
                );
              }).toList(),
            );
          }

          final weekData = grid[weekIndexes[col]] ?? {};
          return Column(
            mainAxisAlignment: MainAxisAlignment.start,
            children: List.generate(7, (row) {
              final volume = weekData[row] ?? 0;
              return Container(
                width: _cellSize,
                height: _cellSize,
                margin: EdgeInsets.all(_cellGap / 2),
                decoration: BoxDecoration(
                  color: _cellColor(volume, maxVolume, theme),
                  borderRadius: BorderRadius.circular(2),
                ),
              );
            }),
          );
        },
      ),
    );
  }

  Widget _empty(BuildContext context, ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          AppLocalizations.of(context)!.progressHeatmapNoData(year),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  Color _cellColor(int volume, int maxVolume, ThemeData theme) {
    if (volume == 0) {
      return theme.colorScheme.surfaceContainerHighest.withAlpha(80);
    }
    if (maxVolume == 0) return theme.colorScheme.primary.withAlpha(80);

    final ratio = volume / maxVolume;
    if (ratio > 0.75) return Colors.green.shade800;
    if (ratio > 0.5) return Colors.green.shade600;
    if (ratio > 0.25) return Colors.green.shade400;
    return Colors.green.shade200;
  }
}
