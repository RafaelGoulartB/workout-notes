import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

/// A GitHub-style contribution heatmap showing workout intensity.
///
/// For the current year, weeks stop at today (no empty future columns).
/// The grid scrolls horizontally with the most recent week against the right
/// edge, while the weekday labels stay pinned outside the scroll view and a
/// month ruler runs above the columns.
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
  static const _labelWidth = 24.0;
  static const _monthRowHeight = 14.0;

  double get _columnWidth => _cellSize + _cellGap;

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
    final locale = Localizations.localeOf(context).toString();

    final Map<int, Map<int, int>> grid = {};
    final Map<int, DateTime> weekStarts = {};
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
      weekStarts.putIfAbsent(weekIndex, () => d);
      if (volume > maxVolume) maxVolume = volume;
    }

    // Oldest → newest, so the scroll view can be reversed to open on today.
    final weekIndexes = grid.keys.toList()..sort();
    if (weekIndexes.isEmpty) {
      return _empty(context, theme);
    }

    final loc = AppLocalizations.of(context)!;
    final dayLabels = [
      loc.calendarSun,
      loc.calendarMon,
      loc.calendarTue,
      loc.calendarWed,
      loc.calendarThu,
      loc.calendarFri,
      loc.calendarSat,
    ];
    final monthFormat = DateFormat.MMM(locale);

    return SizedBox(
      height: _monthRowHeight + 7 * _columnWidth + 4,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Pinned weekday ruler: only alternate days are labelled so the
          // 8px text never collides with the 12px cells.
          Padding(
            padding: const EdgeInsets.only(top: _monthRowHeight),
            child: Column(
              children: [
                for (var row = 0; row < 7; row++)
                  SizedBox(
                    width: _labelWidth,
                    height: _columnWidth,
                    child: row.isOdd
                        ? Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              dayLabels[row],
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              style: TextStyle(
                                fontSize: 9,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : null,
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              reverse: true,
              padding: const EdgeInsets.only(left: 2, right: 4),
              itemCount: weekIndexes.length,
              itemBuilder: (context, col) {
                // reverse:true renders index 0 at the right edge.
                final weekIndex = weekIndexes[weekIndexes.length - 1 - col];
                final weekData = grid[weekIndex] ?? {};
                final weekStart = weekStarts[weekIndex]!;
                final previousStart = weekIndex == weekIndexes.first
                    ? null
                    : weekStarts[weekIndex - 1];
                final startsNewMonth = previousStart == null ||
                    previousStart.month != weekStart.month;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: _monthRowHeight,
                      width: _columnWidth,
                      child: startsNewMonth
                          ? OverflowBox(
                              alignment: Alignment.centerLeft,
                              maxWidth: 40,
                              child: Text(
                                monthFormat
                                    .format(weekStart)
                                    .replaceAll('.', ''),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            )
                          : null,
                    ),
                    for (var row = 0; row < 7; row++)
                      Container(
                        width: _cellSize,
                        height: _cellSize,
                        margin: const EdgeInsets.all(_cellGap / 2),
                        decoration: BoxDecoration(
                          color: _cellColor(
                            weekData[row] ?? 0,
                            maxVolume,
                            theme,
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
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
