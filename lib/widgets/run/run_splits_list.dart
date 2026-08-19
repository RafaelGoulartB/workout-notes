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
      return Text(
        loc.runDetailSplitsEmpty,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
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
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 52,
                child: Text(
                  loc.runDetailSplitKm,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  loc.runDetailSplitPace,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (final split in splits)
          _SplitRow(
            split: split,
            fastest: fastest,
            slowest: slowest,
          ),
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
        ? loc.runDetailSplitPartial(RunFormatters.distanceKm(split.distanceMeters))
        : loc.runRecordSplitKm(split.km);
    final pace = split.paceSecPerKm;
    final barFraction = _barFraction(pace);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 52,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight:
                    split.isPartial ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
          SizedBox(
            width: 52,
            child: Text(
              RunFormatters.pace(pace),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth * barFraction;
                return Align(
                  alignment: Alignment.centerLeft,
                  child: Container(
                    height: 10,
                    width: width.clamp(8.0, constraints.maxWidth),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                );
              },
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
    // Invert: fastest → 1.0, slowest → ~0.28
    final t = ((slow - pace) / (slow - fast)).clamp(0.0, 1.0);
    return 0.28 + 0.72 * t;
  }
}
