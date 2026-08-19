import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/utils/run_formatters.dart';

/// Per-km splits with relative pace bars (longer = faster).
class RunSplitsList extends StatelessWidget {
  final List<RunSplit> splits;

  const RunSplitsList({super.key, required this.splits});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    if (splits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text(
          loc.runDetailSplitsEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    double? slowest;
    double? fastest;
    for (final s in splits) {
      final p = s.paceSecPerKm;
      if (p == null || !p.isFinite || p <= 0) continue;
      if (slowest == null || p > slowest) slowest = p;
      if (fastest == null || p < fastest) fastest = p;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  loc.runDetailSplitKm,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  loc.runDetailSplitPace,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  loc.runRecordSplitTime,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < splits.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
            ),
          _SplitRow(
            split: splits[i],
            fastest: fastest,
            slowest: slowest,
          ),
        ],
      ],
    );
  }
}

class _SplitRow extends StatelessWidget {
  final RunSplit split;
  final double? fastest;
  final double? slowest;

  const _SplitRow({
    required this.split,
    required this.fastest,
    required this.slowest,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final label = split.isPartial
        ? loc.runDetailSplitPartial(
            RunFormatters.distanceKm(split.distanceMeters),
          )
        : loc.runRecordSplitKm(split.km);
    final pace = split.paceSecPerKm;
    final barFraction = _barFraction(pace);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              SizedBox(
                width: 64,
                child: Text(
                  label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight:
                        split.isPartial ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              SizedBox(
                width: 56,
                child: Text(
                  RunFormatters.pace(pace),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  RunFormatters.duration(split.durationSeconds),
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Container(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.7),
                  ),
                  FractionallySizedBox(
                    widthFactor: barFraction,
                    child: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(
                          alpha: split.isPartial ? 0.55 : 0.9,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Longer bar = faster pace. Partial / missing pace → short stub.
  double _barFraction(double? pace) {
    if (pace == null || !pace.isFinite || pace <= 0) return 0.15;
    final fast = fastest;
    final slow = slowest;
    if (fast == null || slow == null) return 0.7;
    if ((slow - fast).abs() < 1) return 1.0;
    final t = ((slow - pace) / (slow - fast)).clamp(0.0, 1.0);
    return 0.28 + 0.72 * t;
  }
}
