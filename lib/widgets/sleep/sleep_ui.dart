import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';

/// Formatting and colours shared by the sleep screens.
abstract final class SleepUi {
  static const Color awake = Colors.orange;
  static const Color sleeping = Colors.lightBlue;
  static const Color deep = Colors.indigo;
  static const Color unknown = Colors.grey;

  static Color stageColor(SleepStageType stage) => switch (stage) {
    SleepStageType.awake => awake,
    SleepStageType.sleeping => sleeping,
    SleepStageType.deep => deep,
    SleepStageType.unknown => unknown,
  };

  /// "7h 30min", "25min" under an hour, or "--" when unknown.
  static String duration(AppLocalizations loc, int? minutes) {
    if (minutes == null) return '--';
    final safe = minutes < 0 ? 0 : minutes;
    if (safe < 60) return '${safe}min';
    return loc.sleepDurationValue(safe ~/ 60, safe % 60);
  }

  /// Minutes after midnight as "HH:mm" (or "--").
  static String clock(int? minutes) {
    if (minutes == null) return '--';
    final wrapped = minutes % 1440;
    return '${(wrapped ~/ 60).toString().padLeft(2, '0')}:'
        '${(wrapped % 60).toString().padLeft(2, '0')}';
  }

  /// "23:40 → 07:05" when both ends are known.
  static String? window(int? bedtime, int? wake) {
    if (bedtime == null || wake == null) return null;
    return '${clock(bedtime)} → ${clock(wake)}';
  }

  /// Wall-clock time of a monitored instant, in the offset it was recorded.
  static String wallTime(DateTime value, int offsetMinutes) {
    final wall = value.toUtc().add(Duration(minutes: offsetMinutes));
    return '${wall.hour.toString().padLeft(2, '0')}:'
        '${wall.minute.toString().padLeft(2, '0')}';
  }

  static String dayMonth(DateTime date) =>
      DateFormat.MMMd(Intl.defaultLocale).format(date);

  static String weekdayDayMonth(DateTime date) =>
      DateFormat.MMMEd(Intl.defaultLocale).format(date);

  /// Colour for an efficiency percentage: good, fair or low.
  static Color efficiencyColor(ColorScheme colors, double? value) {
    if (value == null) return colors.onSurfaceVariant;
    if (value >= 85) return colors.primary;
    if (value >= 70) return colors.secondary;
    return colors.tertiary;
  }
}

/// Thin horizontal bar with the awake / sleeping / deep split of a night.
class SleepStageBar extends StatelessWidget {
  final SleepMonitorSession session;
  final double height;

  const SleepStageBar({super.key, required this.session, this.height = 6});

  @override
  Widget build(BuildContext context) {
    final parts = [
      (session.awakeMinutes ?? 0, SleepUi.awake),
      (session.sleepingMinutes ?? 0, SleepUi.sleeping),
      (session.deepSleepMinutes ?? 0, SleepUi.deep),
      (session.unknownMinutes ?? 0, SleepUi.unknown),
    ].where((part) => part.$1 > 0).toList();
    if (parts.isEmpty) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(99),
      child: SizedBox(
        height: height,
        child: Row(
          children: [
            for (final part in parts)
              Expanded(
                flex: part.$1,
                child: Container(color: part.$2),
              ),
          ],
        ),
      ),
    );
  }
}

/// Square date badge (day number over short weekday) for history rows.
class SleepDateBadge extends StatelessWidget {
  final DateTime date;

  const SleepDateBadge({super.key, required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.primary.withAlpha(24),
        borderRadius: BorderRadius.circular(RunUi.tileRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('d').format(date),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.1,
              fontFeatures: RunUi.tabular,
            ),
          ),
          Text(
            DateFormat(
              'EEE',
              Intl.defaultLocale,
            ).format(date).replaceAll('.', '').toLowerCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 10,
              color: colors.onSurfaceVariant,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
  }
}
