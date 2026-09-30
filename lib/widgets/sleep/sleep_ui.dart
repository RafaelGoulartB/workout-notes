import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/utils/duration_format.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Formatting and colours shared by the sleep screens.
abstract final class SleepUi {
  static const Color awake = Colors.orange;
  static const Color sleeping = Colors.lightBlue;
  static const Color deep = Colors.indigo;
  static const Color unknown = Colors.grey;

  /// Inner padding of the sleep cards (an [AppSoftCard]).
  static const EdgeInsets cardPadding = EdgeInsets.fromLTRB(20, 18, 16, 16);

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
    return DurationFormat.hhmm(wrapped);
  }

  /// "23:40 → 07:05" when both ends are known.
  static String? window(int? bedtime, int? wake) {
    if (bedtime == null || wake == null) return null;
    return '${clock(bedtime)} → ${clock(wake)}';
  }

  /// Wall-clock time of a monitored instant, in the offset it was recorded.
  static String wallTime(DateTime value, int offsetMinutes) {
    final wall = value.toUtc().add(Duration(minutes: offsetMinutes));
    return DurationFormat.hhmm(wall.hour * 60 + wall.minute);
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
        borderRadius: BorderRadius.circular(AppUi.tileRadius),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            DateFormat('d').format(date),
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.1,
              fontFeatures: AppUi.tabular,
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

/// Card title row: tinted icon, bold title and an optional trailing widget
/// (a chevron on tappable cards).
class SleepCardHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  const SleepCardHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: colors.primary),
        const SizedBox(width: 8),
        if (subtitle == null) Expanded(child: _title(theme)) else _title(theme),
        if (subtitle != null) ...[
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ],
        ?trailing,
      ],
    );
  }

  Widget _title(ThemeData theme) => Text(
    title,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
  );
}

/// Large duration ("7h 30min") with the unit letters set smaller, like the
/// kcal headline of the nutrition summary.
class SleepBigDuration extends StatelessWidget {
  final int? minutes;

  const SleepBigDuration({super.key, required this.minutes});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final big = theme.textTheme.headlineLarge?.copyWith(
      fontWeight: FontWeight.bold,
      fontSize: 38,
      height: 1.0,
      fontFeatures: AppUi.tabular,
    );
    final unit = theme.textTheme.titleSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );
    final value = minutes;
    final spans = <InlineSpan>[];
    if (value == null) {
      spans.add(TextSpan(text: '--', style: big));
    } else {
      final safe = value < 0 ? 0 : value;
      if (safe >= 60) {
        spans
          ..add(TextSpan(text: '${safe ~/ 60}', style: big))
          ..add(TextSpan(text: '\u2009h\u2002', style: unit));
      }
      spans
        ..add(TextSpan(text: '${safe % 60}', style: big))
        ..add(TextSpan(text: '\u2009min', style: unit));
    }
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: Text.rich(TextSpan(children: spans)),
    );
  }
}

/// Tinted pill used under the sleep headlines (time window, source).
class SleepBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const SleepBadge({
    super.key,
    required this.icon,
    required this.label,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tint = color ?? theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: tint.withAlpha(38),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: tint),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: tint,
                fontWeight: FontWeight.w700,
                fontFeatures: AppUi.tabular,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Right-aligned percentage with a small caption under it, next to the big
/// headline duration.
class SleepHeadlinePercent extends StatelessWidget {
  final String value;
  final String caption;

  const SleepHeadlinePercent({
    super.key,
    required this.value,
    required this.caption,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            color: colors.primary,
            fontWeight: FontWeight.w800,
            height: 1.1,
          ),
        ),
        Text(
          caption,
          style: theme.textTheme.labelSmall?.copyWith(
            color: colors.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}
