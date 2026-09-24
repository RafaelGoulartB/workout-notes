import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_epoch.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';

class SleepStageCard extends StatefulWidget {
  final SleepMonitorSession session;
  final List<SleepStageEpoch> stages;
  final bool compact;

  const SleepStageCard({
    super.key,
    required this.session,
    required this.stages,
    this.compact = false,
  });

  @override
  State<SleepStageCard> createState() => _SleepStageCardState();
}

class _SleepStageCardState extends State<SleepStageCard> {
  SleepStageEpoch? _selected;

  bool get _hasStages =>
      widget.stages.any((stage) => stage.stage != SleepStageType.unknown);

  /// The persisted per-night stage aggregates are the only durable stage
  /// data since raw epochs are no longer stored; they are shown instead of
  /// the interactive timeline.
  bool get _hasStageAggregates =>
      widget.session.analysisStatus == SleepMonitorSession.analysisAvailable &&
      (widget.session.awakeMinutes != null ||
          widget.session.sleepingMinutes != null ||
          widget.session.deepSleepMinutes != null);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.bedtime_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    SleepWakeEngine.supports(widget.session)
                        ? loc.sleepWakeEstimateTitle
                        : loc.sleepStagesTitle,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (!SleepWakeEngine.supports(widget.session) &&
                    (_hasStages || _hasStageAggregates) &&
                    widget.session.stageConfidence != null)
                  Chip(
                    visualDensity: VisualDensity.compact,
                    label: Text(
                      '${(widget.session.stageConfidence! * 100).round()}%',
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            if (!_hasStages && !_hasStageAggregates)
              _UnavailableState(session: widget.session)
            else ...[
              if (_hasStages) ...[
                Semantics(
                  label: loc.sleepStageTimelineSemantics,
                  child: LayoutBuilder(
                    builder: (context, constraints) => GestureDetector(
                      onTapDown: (details) =>
                          _selectStage(details, constraints.maxWidth),
                      child: SizedBox(
                        height: widget.compact ? 70 : 112,
                        width: double.infinity,
                        child: CustomPaint(
                          painter: _HypnogramPainter(
                            stages: widget.stages,
                            session: widget.session,
                            selected: _selected,
                            colorScheme: theme.colorScheme,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                _StageLegend(selected: _selected, session: widget.session),
                const SizedBox(height: 14),
              ],
              _Breakdown(session: widget.session),
              if (SleepWakeEngine.supports(widget.session)) ...[
                const SizedBox(height: 12),
                Text(loc.sleepBedsideEstimateBody),
              ],
              if (!widget.compact) ...[
                const SizedBox(height: 14),
                Divider(color: theme.colorScheme.outlineVariant),
                const SizedBox(height: 10),
                _NightMetrics(session: widget.session),
              ],
            ],
          ],
        ),
      ),
    );
  }

  void _selectStage(TapDownDetails details, double width) {
    if (widget.stages.isEmpty || width <= 0 || !width.isFinite) return;
    final end = widget.session.endedAt ?? widget.stages.last.endedAt;
    final total = end.difference(widget.session.startedAt).inMilliseconds;
    if (total <= 0) return;
    final fraction = (details.localPosition.dx / width).clamp(0.0, 1.0);
    final instant = widget.session.startedAt.add(
      Duration(milliseconds: (total * fraction).round()),
    );
    SleepStageEpoch? selected;
    for (final stage in widget.stages) {
      if (!instant.isBefore(stage.startedAt) &&
          instant.isBefore(stage.endedAt)) {
        selected = stage;
        break;
      }
    }
    setState(() => _selected = selected);
  }
}

class _UnavailableState extends StatelessWidget {
  final SleepMonitorSession session;

  const _UnavailableState({required this.session});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.sleepStageUnavailable,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(_unavailableBody(loc, session.analysisStatus)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _unavailableBody(AppLocalizations loc, String? analysisStatus) {
    switch (analysisStatus) {
      case SleepMonitorSession.analysisInsufficient:
        return loc.sleepStageInsufficientBody;
      case SleepMonitorSession.analysisModelUnavailable:
        return loc.sleepStageModelUnavailableBody;
      default:
        return loc.sleepStageUnavailableLegacyBody;
    }
  }
}

class _StageLegend extends StatelessWidget {
  final SleepStageEpoch? selected;
  final SleepMonitorSession session;

  const _StageLegend({required this.selected, required this.session});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    if (selected != null) {
      return Text(
        '${_wallTime(selected!.startedAt, session.utcOffsetStartMinutes)} · '
        '${_stageLabel(loc, selected!.stage)} · '
        '${(selected!.confidence * 100).round()}%',
        style: Theme.of(context).textTheme.labelMedium,
      );
    }
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _LegendDot(color: Colors.orange, label: loc.sleepStageAwake),
        _LegendDot(color: Colors.lightBlue, label: loc.sleepStageSleeping),
        _LegendDot(color: Colors.indigo, label: loc.sleepStageDeepEstimated),
        if ((session.unknownMinutes ?? 0) > 0)
          _LegendDot(color: Colors.grey, label: loc.sleepStageUnknown),
      ],
    );
  }
}

class _Breakdown extends StatelessWidget {
  final SleepMonitorSession session;

  const _Breakdown({required this.session});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: _StageValue(
            color: Colors.orange,
            label: loc.sleepStageAwake,
            minutes: session.awakeMinutes ?? 0,
          ),
        ),
        Expanded(
          child: _StageValue(
            color: Colors.lightBlue,
            label: loc.sleepStageSleeping,
            minutes: session.sleepingMinutes ?? 0,
          ),
        ),
        Expanded(
          child: _StageValue(
            color: SleepWakeEngine.supports(session)
                ? Colors.grey
                : Colors.indigo,
            label: SleepWakeEngine.supports(session)
                ? loc.sleepStageUnknown
                : loc.sleepStageDeepEstimated,
            minutes: SleepWakeEngine.supports(session)
                ? session.unknownMinutes ?? 0
                : session.deepSleepMinutes ?? 0,
          ),
        ),
      ],
    );
  }
}

class _NightMetrics extends StatelessWidget {
  final SleepMonitorSession session;

  const _NightMetrics({required this.session});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final values = [
      (
        loc.sleepOnsetTime,
        session.sleepOnsetAt == null
            ? '--'
            : _wallTime(session.sleepOnsetAt!, session.utcOffsetStartMinutes),
      ),
      (
        loc.sleepFinalWake,
        session.finalWakeAt == null
            ? '--'
            : _wallTime(
                session.finalWakeAt!,
                session.utcOffsetEndMinutes ?? session.utcOffsetStartMinutes,
              ),
      ),
      (loc.sleepLatency, _minutes(session.sleepLatencyMinutes)),
      (loc.sleepAwakenings, '${session.awakeningCount ?? 0}'),
    ];
    return Wrap(
      spacing: 20,
      runSpacing: 12,
      children: values
          .map(
            (value) => SizedBox(
              width: 132,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value.$1, style: Theme.of(context).textTheme.labelSmall),
                  const SizedBox(height: 2),
                  Text(
                    value.$2,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }
}

class _HypnogramPainter extends CustomPainter {
  final List<SleepStageEpoch> stages;
  final SleepMonitorSession session;
  final SleepStageEpoch? selected;
  final ColorScheme colorScheme;

  const _HypnogramPainter({
    required this.stages,
    required this.session,
    required this.selected,
    required this.colorScheme,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final end = session.endedAt ?? stages.last.endedAt;
    final total = end.difference(session.startedAt).inMilliseconds;
    if (total <= 0) return;
    final grid = Paint()
      ..color = colorScheme.outlineVariant.withAlpha(120)
      ..strokeWidth = 1;
    for (var row = 0; row < 3; row++) {
      final y = size.height * (row + .5) / 3;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    for (final stage in stages) {
      final startMs = stage.startedAt
          .difference(session.startedAt)
          .inMilliseconds
          .clamp(0, total);
      final endMs = stage.endedAt
          .difference(session.startedAt)
          .inMilliseconds
          .clamp(0, total);
      final left = size.width * startMs / total;
      final right = size.width * endMs / total;
      final row = switch (stage.stage) {
        SleepStageType.awake => 0,
        SleepStageType.sleeping => 1,
        SleepStageType.deep => 2,
        SleepStageType.unknown => 1,
      };
      final height = size.height / 3 - 4;
      final top = row * size.height / 3 + 2;
      final color = _stageColor(stage.stage);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(left, top, math.max(1, right - left), height),
          const Radius.circular(2),
        ),
        Paint()
          ..color = color.withValues(
            alpha: stage.stage == SleepStageType.unknown ? .35 : .9,
          ),
      );
      if (identical(stage, selected)) {
        canvas.drawRect(
          Rect.fromLTRB(left, 0, math.max(left + 2, right), size.height),
          Paint()
            ..color = colorScheme.onSurface
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_HypnogramPainter oldDelegate) =>
      oldDelegate.stages != stages || oldDelegate.selected != selected;
}

class _StageValue extends StatelessWidget {
  final Color color;
  final String label;
  final int minutes;

  const _StageValue({
    required this.color,
    required this.label,
    required this.minutes,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(width: 24, height: 4, color: color),
        const SizedBox(height: 7),
        Text(label, maxLines: 2, style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 3),
        Text(
          _minutes(minutes),
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircleAvatar(radius: 5, backgroundColor: color),
        const SizedBox(width: 5),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }
}

Color _stageColor(SleepStageType stage) => switch (stage) {
  SleepStageType.awake => Colors.orange,
  SleepStageType.sleeping => Colors.lightBlue,
  SleepStageType.deep => Colors.indigo,
  SleepStageType.unknown => Colors.grey,
};

String _stageLabel(AppLocalizations loc, SleepStageType stage) =>
    switch (stage) {
      SleepStageType.awake => loc.sleepStageAwake,
      SleepStageType.sleeping => loc.sleepStageSleeping,
      SleepStageType.deep => loc.sleepStageDeepEstimated,
      SleepStageType.unknown => loc.sleepStageUnknown,
    };

String _wallTime(DateTime value, int offsetMinutes) {
  final wallClock = value.toUtc().add(Duration(minutes: offsetMinutes));
  return '${wallClock.hour.toString().padLeft(2, '0')}:'
      '${wallClock.minute.toString().padLeft(2, '0')}';
}

String _minutes(int? value) {
  if (value == null) return '--';
  final safe = value.clamp(0, 16 * 60);
  final hours = safe ~/ 60;
  final minutes = safe % 60;
  return hours == 0 ? '$minutes min' : '${hours}h ${minutes}min';
}
