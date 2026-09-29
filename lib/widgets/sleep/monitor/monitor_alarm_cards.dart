import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';

class AlarmClockCard extends StatelessWidget {
  final String time;
  final String date;
  final String remaining;
  final String sectionTitle;
  final String changeLabel;
  final VoidCallback onTap;
  final VoidCallback onEarlier;
  final VoidCallback onLater;

  const AlarmClockCard({
    super.key,
    required this.time,
    required this.date,
    required this.remaining,
    required this.sectionTitle,
    required this.changeLabel,
    required this.onTap,
    required this.onEarlier,
    required this.onLater,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        final header = compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.alarm_rounded,
                        size: 20,
                        color: scheme.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          sectionTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: onTap,
                      icon: const Icon(Icons.edit_rounded, size: 16),
                      label: Text(changeLabel),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 36),
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ],
              )
            : Row(
                children: [
                  Icon(Icons.alarm_rounded, size: 20, color: scheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      sectionTitle,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    changeLabel,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.edit_rounded, size: 17, color: scheme.primary),
                ],
              );
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              InkWell(
                onTap: onTap,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    compact ? 14 : 20,
                    compact ? 10 : 16,
                    compact ? 14 : 20,
                    compact ? 10 : 18,
                  ),
                  child: Column(
                    children: [
                      header,
                      SizedBox(height: compact ? 4 : 12),
                      SizedBox(
                        width: double.infinity,
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            time,
                            style:
                                (compact
                                        ? theme.textTheme.displayMedium
                                        : theme.textTheme.displayLarge)
                                    ?.copyWith(
                                      fontWeight: FontWeight.w400,
                                      color: scheme.primary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures(),
                                      ],
                                    ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        date,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 10),
                      Container(
                        padding: EdgeInsets.symmetric(
                          horizontal: compact ? 10 : 12,
                          vertical: compact ? 4 : 6,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          remaining,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: scheme.outlineVariant),
              Padding(
                padding: EdgeInsets.all(compact ? 8 : 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onEarlier,
                        style: compact
                            ? OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                              )
                            : null,
                        child: Text(
                          AppLocalizations.of(context)!.sleepAlarmShiftEarlier,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onLater,
                        style: compact
                            ? OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                              )
                            : null,
                        child: Text(
                          AppLocalizations.of(context)!.sleepAlarmShiftLater,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class MonitoringOnlyCard extends StatelessWidget {
  const MonitoringOnlyCard({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 360;
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: EdgeInsets.all(compact ? 16 : 22),
            child: Column(
              children: [
                Container(
                  width: compact ? 48 : 58,
                  height: compact ? 48 : 58,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: scheme.onPrimaryContainer,
                    size: compact ? 26 : 30,
                  ),
                ),
                SizedBox(height: compact ? 8 : 12),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style:
                      (compact
                              ? theme.textTheme.titleMedium
                              : theme.textTheme.titleLarge)
                          ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  body,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

String formatModeDate(BuildContext context, DateTime date) {
  final locale = Localizations.localeOf(context).toLanguageTag();
  return toBeginningOfSentenceCase(
        DateFormat('EEEE, d MMM', locale).format(date),
      ) ??
      '';
}
