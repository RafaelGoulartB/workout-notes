import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';

class SleepLatestCard extends StatelessWidget {
  final SleepEntry entry;
  final VoidCallback onTap;

  const SleepLatestCard({super.key, required this.entry, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final efficiency = entry.efficiency?.clamp(0.0, 100.0).toDouble();

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 310;
              final summary = _LatestSummary(entry: entry);
              final ring = _EfficiencyRing(efficiency: efficiency);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.nights_stay_rounded,
                        color: colors.primary,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          loc.sleepLatest,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 15,
                        color: colors.onSurfaceVariant,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (compact) ...[
                    summary,
                    const SizedBox(height: 16),
                    Align(alignment: Alignment.centerLeft, child: ring),
                  ] else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        ring,
                        const SizedBox(width: 18),
                        Expanded(child: summary),
                      ],
                    ),
                  const SizedBox(height: 16),
                  Divider(height: 1, color: colors.outlineVariant),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _TimeValue(
                          icon: Icons.bedtime_outlined,
                          label: loc.sleepBedtime,
                          value: _formatTime(entry.bedtimeMinutes),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _TimeValue(
                          icon: Icons.wb_sunny_outlined,
                          label: loc.sleepWakeTime,
                          value: _formatTime(entry.wakeTimeMinutes),
                        ),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  static String _formatTime(int? minutes) {
    if (minutes == null) return '--';
    final hour = minutes ~/ 60;
    final minute = minutes % 60;
    return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
  }
}

class _LatestSummary extends StatelessWidget {
  final SleepEntry entry;

  const _LatestSummary({required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          loc.sleepDurationValue(
            entry.sleepMinutes ~/ 60,
            entry.sleepMinutes % 60,
          ),
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w900,
            letterSpacing: -.5,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          DateFormat.yMMMMd(Intl.defaultLocale).format(entry.date),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        if (entry.actualSleepMinutes != null) ...[
          const SizedBox(height: 7),
          Text(
            '${loc.sleepActualDuration}: ${loc.sleepDurationValue(entry.actualSleepMinutes! ~/ 60, entry.actualSleepMinutes! % 60)}',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ],
    );
  }
}

class _EfficiencyRing extends StatelessWidget {
  final double? efficiency;

  const _EfficiencyRing({required this.efficiency});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final valueText = efficiency == null ? '--' : '${efficiency!.round()}%';
    return Semantics(
      label: '${loc.sleepEfficiency}: $valueText',
      child: SizedBox(
        width: 86,
        height: 86,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.expand(
              child: CircularProgressIndicator(
                value: efficiency == null ? 0 : efficiency! / 100,
                strokeWidth: 8,
                strokeCap: StrokeCap.round,
                color: colors.primary,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  valueText,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  loc.sleepEfficiency,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TimeValue extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _TimeValue({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.primary),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                value,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
