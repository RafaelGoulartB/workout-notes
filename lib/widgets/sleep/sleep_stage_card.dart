import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';
import 'package:workout_notes/widgets/sleep/sleep_night_chart.dart';
import 'package:workout_notes/widgets/sleep/sleep_ui.dart';
import 'package:workout_notes/widgets/ui/ui.dart';

class SleepStageCard extends StatelessWidget {
  final SleepMonitorSession session;

  /// Onset, final wake, latency and awakenings under the breakdown. Hosts
  /// that already show those numbers turn it off.
  final bool showNightMetrics;

  const SleepStageCard({
    super.key,
    required this.session,
    this.showNightMetrics = true,
  });

  /// The persisted per-night stage aggregates are the only stage data: raw
  /// epochs are never stored.
  bool get _hasStageAggregates =>
      session.analysisStatus == SleepMonitorSession.analysisAvailable &&
      (session.awakeMinutes != null ||
          session.sleepingMinutes != null ||
          session.deepSleepMinutes != null);

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final timeline = SleepWakeEngine.supports(session) ? session.timeline : null;
    return AppSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const AppIconBadge(Icons.bedtime_rounded),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  SleepWakeEngine.supports(session)
                      ? loc.sleepWakeEstimateTitle
                      : loc.sleepStagesTitle,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!SleepWakeEngine.supports(session) &&
                  _hasStageAggregates &&
                  session.stageConfidence != null)
                Tooltip(
                  message: loc.sleepInferenceConfidence,
                  child: AppPill(
                    icon: Icons.verified_outlined,
                    label: '${(session.stageConfidence! * 100).round()}%',
                  ),
                ),
            ],
          ),
          const SizedBox(height: 14),
          if (!_hasStageAggregates)
            _UnavailableState(session: session)
          else ...[
            if (timeline != null) ...[
              SleepNightChart(
                timeline: timeline,
                startedAt: session.startedAt,
                utcOffsetMinutes: session.utcOffsetStartMinutes,
              ),
              const SizedBox(height: 16),
            ],
            _Breakdown(session: session),
            if (SleepWakeEngine.supports(session) &&
                (session.restlessSleepMinutes != null ||
                    session.snoreMinutes != null)) ...[
              const SizedBox(height: 12),
              _SleepQuality(session: session),
            ],
            if (SleepWakeEngine.supports(session)) ...[
              const SizedBox(height: 12),
              Text(
                loc.sleepBedsideEstimateBody,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (showNightMetrics) ...[
              const SizedBox(height: 14),
              Divider(color: theme.colorScheme.outlineVariant),
              const SizedBox(height: 10),
              _NightMetrics(session: session),
            ],
          ],
        ],
      ),
    );
  }
}

class _UnavailableState extends StatelessWidget {
  final SleepMonitorSession session;

  const _UnavailableState({required this.session});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.info_outline_rounded,
          size: 18,
          color: colors.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                loc.sleepStageUnavailable,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                SleepWakeEngine.supports(session) &&
                        session.analysisStatus !=
                            SleepMonitorSession.analysisInsufficient
                    ? loc.sleepStageUnavailableBedsideBody
                    : _unavailableBody(loc, session.analysisStatus),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
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

/// Bedside nights only: how much of the sleep was restless, and snoring.
class _SleepQuality extends StatelessWidget {
  final SleepMonitorSession session;

  const _SleepQuality({required this.session});

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(
          child: _StageValue(
            color: SleepUi.restless,
            label: loc.sleepStageRestless,
            minutes: session.restlessSleepMinutes ?? 0,
          ),
        ),
        Expanded(
          child: _StageValue(
            color: SleepUi.snoring,
            label: loc.sleepSnoring,
            minutes: session.snoreMinutes ?? 0,
          ),
        ),
        const Spacer(),
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
            : SleepUi.wallTime(
                session.sleepOnsetAt!,
                session.utcOffsetStartMinutes,
              ),
      ),
      (
        loc.sleepFinalWake,
        session.finalWakeAt == null
            ? '--'
            : SleepUi.wallTime(
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

String _minutes(int? value) {
  if (value == null) return '--';
  final safe = value.clamp(0, 16 * 60);
  final hours = safe ~/ 60;
  final minutes = safe % 60;
  return hours == 0 ? '$minutes min' : '${hours}h ${minutes}min';
}
