import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/utils/progress_helpers.dart';

/// Monthly summary hero card — same surface/gradient/divider language as
/// the workout home stats card.
class MonthlyReportCard extends StatelessWidget {
  final Map<String, dynamic>? report;
  final Map<String, dynamic>? comparison;

  const MonthlyReportCard({
    super.key,
    required this.report,
    required this.comparison,
  });

  @override
  Widget build(BuildContext context) {
    if (report == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;

    final wc = report!['workout_count'] as int? ?? 0;
    final vol = (report!['total_volume'] as double?) ?? 0;
    final sets = report!['total_sets'] as int? ?? 0;
    final days = report!['days_with_workouts'] as int? ?? 0;
    final avgFeeling = report!['avg_feeling'] as double?;

    final deltaW = comparison?['delta_workouts'] as int? ?? 0;
    final deltaV = (comparison?['delta_volume'] as double?) ?? 0;
    final deltaS = comparison?['delta_sets'] as int? ?? 0;

    final now = DateTime.now();
    final monthName = DateFormat('MMMM', Intl.defaultLocale).format(now);

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.surfaceContainerHighest.withAlpha(200),
            theme.colorScheme.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            loc.progressMonthlyReport(monthName.toUpperCase()),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: loc.progressWorkouts,
                  value: '$wc',
                  icon: Icons.fitness_center,
                  color: theme.colorScheme.primary,
                  delta: deltaW,
                  deltaLabel: _signed(deltaW, '${deltaW.abs()}'),
                ),
              ),
              const _HeroDivider(),
              Expanded(
                child: _HeroStat(
                  label: loc.commonVolume,
                  value: formatVolume(vol),
                  unit: 'kg',
                  icon: Icons.auto_graph,
                  color: theme.colorScheme.secondary,
                  delta: deltaV.round(),
                  // Volume deltas are large; keep the same compact format as
                  // the value itself instead of a raw kilogram count.
                  deltaLabel: _signed(deltaV, '${formatVolume(deltaV.abs())} kg'),
                ),
              ),
              const _HeroDivider(),
              Expanded(
                child: _HeroStat(
                  label: loc.progressSets,
                  value: '$sets',
                  icon: Icons.repeat,
                  color: Colors.teal,
                  delta: deltaS,
                  deltaLabel: _signed(deltaS, '${deltaS.abs()}'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            height: 1,
            color: theme.colorScheme.outlineVariant.withAlpha(80),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 14,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                '$days ${loc.progressDays.toLowerCase()}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (avgFeeling != null) ...[
                const SizedBox(width: 10),
                Container(
                  width: 1,
                  height: 12,
                  color: theme.colorScheme.outlineVariant.withAlpha(80),
                ),
                const SizedBox(width: 10),
                Icon(Icons.star_rounded, size: 14, color: Colors.amber.shade600),
                const SizedBox(width: 4),
                Text(
                  avgFeeling.toStringAsFixed(1),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Prefixes an already formatted magnitude with the sign of [delta].
String _signed(num delta, String magnitude) =>
    '${delta < 0 ? '-' : '+'}$magnitude';

class _HeroDivider extends StatelessWidget {
  const _HeroDivider();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: theme.colorScheme.outlineVariant.withAlpha(80),
    );
  }
}

class _HeroStat extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final IconData icon;
  final Color color;
  final int? delta;
  final String? deltaLabel;

  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    this.unit,
    this.delta,
    this.deltaLabel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                value,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                  height: 1.1,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 2),
              Text(
                unit!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            fontSize: 11,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (delta != null && delta != 0 && deltaLabel != null) ...[
          const SizedBox(height: 4),
          _DeltaPill(label: deltaLabel!, positive: delta! > 0),
        ],
      ],
    );
  }
}

/// Signed month-over-month delta shown under a hero stat.
class _DeltaPill extends StatelessWidget {
  final String label;
  final bool positive;

  const _DeltaPill({required this.label, required this.positive});

  @override
  Widget build(BuildContext context) {
    final color = positive ? Colors.green : Colors.red;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            positive
                ? Icons.trending_up_rounded
                : Icons.trending_down_rounded,
            size: 11,
            color: color,
          ),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
