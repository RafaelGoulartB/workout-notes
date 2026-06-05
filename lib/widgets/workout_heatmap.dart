import 'package:flutter/material.dart';

/// A GitHub-style contribution heatmap showing workout intensity.
/// Renders 7 rows (days of week) × ~53 columns (weeks).
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Build a map of (weekIndex, dayOfWeek) -> volume
    // Day of week: 0=Sunday, 1=Monday, ..., 6=Saturday
    final Map<int, Map<int, int>> grid = {};
    int maxVolume = 0;

    final firstDay = DateTime(year, 1, 1);
    final lastDay = DateTime(year, 12, 31);

    for (var d = firstDay; d.isBefore(lastDay) || d == lastDay; d = d.add(const Duration(days: 1))) {
      final dateStr = d.toIso8601String().substring(0, 10);
      final volume = dailyData[dateStr] ?? 0;

      // Calculate week index (ISO week, approximately)
      final dayOfYear = differenceInDays(firstDay, d);
      final weekIndex = dayOfYear ~/ 7;
      final dayOfWeek = d.weekday % 7; // 0=Sunday

      grid.putIfAbsent(weekIndex, () => {});
      grid[weekIndex]![dayOfWeek] = volume;
      if (volume > maxVolume) maxVolume = volume;
    }

    final weeks = grid.keys.length;
    if (weeks == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Text('Nenhum dado para $year',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  )),
        ),
      );
    }

    return SizedBox(
      height: 7 * (_cellSize + _cellGap) + 4,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        itemCount: weeks + 1, // +1 for day labels column
        itemBuilder: (context, col) {
          if (col == 0) {
            // Day labels column
            return Column(
              mainAxisAlignment: MainAxisAlignment.start,
              children: ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'].asMap().entries.map((e) {
                return Container(
                  width: 14,
                  height: _cellSize + _cellGap,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'][e.key],
                    style: TextStyle(fontSize: 8, color: theme.colorScheme.onSurfaceVariant.withAlpha(150)),
                  ),
                );
              }).toList(),
            );
          }

          final weekIndex = col - 1;
          final weekData = grid[weekIndex] ?? {};

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

  int differenceInDays(DateTime a, DateTime b) {
    return b.difference(a).inDays;
  }
}
