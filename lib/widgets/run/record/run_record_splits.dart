import 'package:flutter/material.dart';
import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/run_lap.dart';
import 'package:workout_notes/models/run_split.dart';
import 'package:workout_notes/utils/run_formatters.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

/// Collapsed sheet summary: last and best completed kilometer.
class RunSplitSummary extends StatelessWidget {
  final RunSplit? last;
  final RunSplit? best;
  final bool canExpand;

  const RunSplitSummary({
    super.key,
    required this.last,
    required this.best,
    required this.canExpand,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppSectionCard(
          padding: EdgeInsets.zero,
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.45,
          ),
          child: Column(
            children: [
              _SummaryRow(title: loc.runRecordSplitLast, split: last),
              Divider(
                height: 1,
                indent: 12,
                endIndent: 12,
                color: AppUi.divider(theme.colorScheme),
              ),
              _SummaryRow(
                title: loc.runRecordSplitBest,
                split: best,
                highlight: true,
              ),
            ],
          ),
        ),
        if (canExpand) ...[
          const SizedBox(height: 6),
          Text(
            loc.runRecordSplitsExpandHint,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final String title;
  final RunSplit? split;
  final bool highlight;

  const _SummaryRow({
    required this.title,
    required this.split,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final accent = highlight ? theme.colorScheme.primary : null;
    final split = this.split;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: accent ?? theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (split == null)
            Text('—', style: theme.textTheme.titleSmall)
          else ...[
            Text(
              loc.runRecordSplitKm(split.km),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              RunFormatters.paceWithUnit(split.paceSecPerKm),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: accent,
                fontFeatures: AppUi.tabular,
              ),
            ),
            const SizedBox(width: 10),
            Text(
              RunFormatters.duration(split.durationSeconds),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFeatures: AppUi.tabular,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Expanded sheet: every kilometer split so far (the last one in progress).
class RunSplitsTable extends StatelessWidget {
  final List<RunSplit> splits;

  const RunSplitsTable({super.key, required this.splits});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    if (splits.isEmpty) {
      return Text(
        loc.runRecordSplitsEmpty,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    final header = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              const Expanded(flex: 2, child: SizedBox.shrink()),
              Expanded(
                child: Text(
                  loc.runRecordSplitTime,
                  textAlign: TextAlign.end,
                  style: header,
                ),
              ),
              Expanded(
                child: Text(
                  loc.runRecordSplitPace,
                  textAlign: TextAlign.end,
                  style: header,
                ),
              ),
            ],
          ),
        ),
        for (final split in splits)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Text(
                    split.isPartial
                        ? loc.runRecordSplitPartial(split.km)
                        : loc.runRecordSplitKm(split.km),
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: split.isPartial
                          ? FontWeight.w600
                          : FontWeight.w500,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    RunFormatters.duration(split.durationSeconds),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontFeatures: AppUi.tabular,
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    RunFormatters.pace(split.paceSecPerKm),
                    textAlign: TextAlign.end,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
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
}

/// Expanded sheet: manual laps, with the lap in progress at the bottom.
class RunLapsTable extends StatelessWidget {
  final List<RunLap> laps;
  final RunLap? currentLap;

  const RunLapsTable({super.key, required this.laps, required this.currentLap});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loc = AppLocalizations.of(context)!;
    final header = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    if (laps.isEmpty) {
      return Text(
        loc.runLapsEmpty,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }
    Widget row(RunLap lap, {required bool current}) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(
              current ? loc.runLapCurrent : loc.runLapNumber(lap.index),
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: current ? FontWeight.w600 : FontWeight.w500,
                color: current ? theme.colorScheme.primary : null,
              ),
            ),
          ),
          Expanded(
            child: Text(
              RunFormatters.distanceKm(lap.distanceMeters),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFeatures: AppUi.tabular,
              ),
            ),
          ),
          Expanded(
            child: Text(
              RunFormatters.duration(lap.durationSeconds),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontFeatures: AppUi.tabular,
              ),
            ),
          ),
          Expanded(
            child: Text(
              RunFormatters.pace(lap.paceSecPerKm),
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: AppUi.tabular,
              ),
            ),
          ),
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            children: [
              const Expanded(flex: 2, child: SizedBox.shrink()),
              Expanded(
                child: Text(
                  loc.runLapColumnDistance,
                  textAlign: TextAlign.end,
                  style: header,
                ),
              ),
              Expanded(
                child: Text(
                  loc.runRecordSplitTime,
                  textAlign: TextAlign.end,
                  style: header,
                ),
              ),
              Expanded(
                child: Text(
                  loc.runRecordSplitPace,
                  textAlign: TextAlign.end,
                  style: header,
                ),
              ),
            ],
          ),
        ),
        for (final lap in laps) row(lap, current: false),
        if (currentLap != null) row(currentLap!, current: true),
      ],
    );
  }
}
