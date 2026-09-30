import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_lap.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/utils/run_split_analytics.dart';
import 'package:workout_notes/widgets/run/run_theme_colors.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Per-km splits: a bar per kilometre (longer = faster) coloured by how it
/// compares with the run average, the delta vs average, the climb of that km
/// and a badge on the fastest one.
class RunSplitsList extends StatelessWidget {
  final List<RunSplit> splits;

  /// Run average pace; when null the mean of the completed splits is used.
  final double? averagePaceSecPerKm;

  /// Climb per kilometre keyed by split number; the column is hidden when empty.
  final Map<int, double> elevationGainByKm;

  const RunSplitsList({
    super.key,
    required this.splits,
    this.averagePaceSecPerKm,
    this.elevationGainByKm = const {},
  });

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

    final rows = RunSplitAnalytics.build(
      splits,
      averagePaceSecPerKm: averagePaceSecPerKm,
      elevationGainByKm: elevationGainByKm,
    );
    final showElevation = elevationGainByKm.isNotEmpty;
    final header = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              SizedBox(
                width: _kmWidth,
                child: Text(loc.runDetailSplitKm, style: header),
              ),
              const Spacer(),
              SizedBox(
                width: _paceWidth,
                child: Text(
                  loc.runDetailSplitPace,
                  textAlign: TextAlign.end,
                  style: header,
                ),
              ),
              SizedBox(
                width: _deltaWidth,
                child: Text(
                  loc.runSplitsDelta,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: header,
                ),
              ),
              if (showElevation)
                SizedBox(
                  width: _climbWidth,
                  child: Text(
                    loc.runSplitsClimb,
                    textAlign: TextAlign.end,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: header,
                  ),
                ),
            ],
          ),
        ),
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0)
            Divider(height: 1, color: AppUi.divider(theme.colorScheme)),
          _SplitRow(row: rows[i], showElevation: showElevation),
        ],
      ],
    );
  }

  static const double _kmWidth = 60;
  static const double _paceWidth = 48;
  static const double _deltaWidth = 52;
  static const double _climbWidth = 46;
}

class _SplitRow extends StatelessWidget {
  final RunSplitRow row;
  final bool showElevation;

  const _SplitRow({required this.row, required this.showElevation});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final split = row.split;
    final label = split.isPartial
        ? loc.runDetailSplitPartial(
            RunFormatters.distanceKm(split.distanceMeters),
          )
        : loc.runRecordSplitKm(split.km);
    final toneColor = switch (row.tone) {
      RunSplitTone.faster => colors.primary,
      RunSplitTone.slower => RunThemeColors.warm(colors),
      _ => colors.onSurfaceVariant,
    };
    final delta = row.deltaSecPerKm;
    final barColor = switch (row.tone) {
      RunSplitTone.faster => colors.primary,
      RunSplitTone.slower => RunThemeColors.warm(colors),
      _ => colors.outline,
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        children: [
          SizedBox(
            width: RunSplitsList._kmWidth,
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: row.isFastest
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (row.isFastest)
                  Semantics(
                    label: loc.runSplitsFastest,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 2),
                      child: Icon(
                        Icons.bolt_rounded,
                        size: 14,
                        color: colors.primary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  height: 10,
                  child: Stack(
                    children: [
                      Container(
                        color: colors.surfaceContainerHighest.withValues(
                          alpha: 0.7,
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: row.barFraction,
                        child: Container(
                          decoration: BoxDecoration(
                            color: barColor.withValues(
                              alpha: split.isPartial ? 0.5 : 0.9,
                            ),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: RunSplitsList._paceWidth,
            child: Text(
              RunFormatters.paceShort(split.paceSecPerKm),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                fontFeatures: AppUi.tabular,
              ),
            ),
          ),
          SizedBox(
            width: RunSplitsList._deltaWidth,
            child: Text(
              delta == null ? '' : RunFormatters.paceDelta(delta),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodySmall?.copyWith(
                color: toneColor,
                fontWeight: FontWeight.w700,
                fontFeatures: AppUi.tabular,
              ),
            ),
          ),
          if (showElevation)
            SizedBox(
              width: RunSplitsList._climbWidth,
              child: Text(
                row.elevationGainMeters == null
                    ? '—'
                    : '+${row.elevationGainMeters!.round()} m',
                textAlign: TextAlign.end,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                  fontFeatures: AppUi.tabular,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Manual laps marked while recording: distance, time and pace per lap.
class RunLapsList extends StatelessWidget {
  final List<RunLap> laps;

  const RunLapsList({super.key, required this.laps});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final fastest = _fastestLap(laps);
    // Laps may be stored 0- or 1-based; always show "Lap 1" first.
    final labelOffset = laps.any((lap) => lap.index == 0) ? 1 : 0;
    return AppDividedList(
      children: [
        for (final lap in laps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          loc.runDetailLapLabel('${lap.index + labelOffset}'),
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (lap == fastest)
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Icon(
                            Icons.bolt_rounded,
                            size: 14,
                            color: colors.primary,
                          ),
                        ),
                    ],
                  ),
                ),
                Text(
                  RunFormatters.distanceWithUnit(lap.distanceMeters),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: AppUi.tabular,
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  RunFormatters.duration(lap.durationSeconds),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                    fontFeatures: AppUi.tabular,
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 44,
                  child: Text(
                    RunFormatters.paceShort(lap.paceSecPerKm),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: AppUi.tabular,
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  static RunLap? _fastestLap(List<RunLap> laps) {
    if (laps.length < 2) return null;
    RunLap? best;
    for (final lap in laps) {
      final pace = lap.paceSecPerKm;
      if (pace == null || !pace.isFinite || pace <= 0) continue;
      if (best == null || pace < best.paceSecPerKm!) best = lap;
    }
    return best;
  }
}
