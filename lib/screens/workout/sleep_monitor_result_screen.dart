import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/models/sleep_stage_epoch.dart';
import 'package:workout_notes/repositories/sleep_monitor_repository.dart';
import 'package:workout_notes/widgets/goals/goal_progress_ring.dart';
import 'package:workout_notes/widgets/run/run_ui.dart';
import 'package:workout_notes/widgets/sleep/sleep_stage_card.dart';
import 'package:workout_notes/widgets/sleep/sleep_ui.dart';

/// Detail of one monitored night: headline sleep and efficiency, the night's
/// numbers, the stage timeline and the estimate disclaimer.
class SleepMonitorResultScreen extends StatefulWidget {
  final String sessionId;

  const SleepMonitorResultScreen({super.key, required this.sessionId});

  @override
  State<SleepMonitorResultScreen> createState() =>
      _SleepMonitorResultScreenState();
}

class _SleepMonitorResultScreenState extends State<SleepMonitorResultScreen> {
  final _repository = SleepMonitorRepository();
  SleepMonitorSession? _session;
  SleepEntry? _entry;
  List<SleepStageEpoch> _stages = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await _repository.getSession(widget.sessionId);
    SleepEntry? entry;
    var stages = const <SleepStageEpoch>[];
    if (session != null) {
      // Both are extras: older databases may lack the tables.
      try {
        stages = await _repository.getStageEpochs(session.id);
      } catch (_) {}
      if (session.sleepEntryId != null) {
        try {
          entry = await _repository.getSleepEntry(session.sleepEntryId!);
        } catch (_) {}
      }
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _entry = entry;
      _stages = stages;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final session = _session;
    final date =
        _entry?.date ??
        session?.startedAt.toUtc().add(
          Duration(minutes: session.utcOffsetStartMinutes),
        );
    return Scaffold(
      appBar: AppBar(
        title: Text(
          date == null
              ? loc.sleepMonitorResultTitle
              : loc.sleepNightOf(SleepUi.weekdayDayMonth(date)),
        ),
        actions: [
          if (session != null)
            IconButton(
              onPressed: _deleteSession,
              tooltip: loc.sleepMonitorDeleteSession,
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : session == null
          ? Center(child: Text(loc.sleepMonitorResultMissing))
          : _buildResult(context, loc, session),
    );
  }

  Widget _buildResult(
    BuildContext context,
    AppLocalizations loc,
    SleepMonitorSession session,
  ) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final end = session.endedAt ?? session.startedAt;
    final endOffset =
        session.utcOffsetEndMinutes ?? session.utcOffsetStartMinutes;
    final comment = _entry?.comment;
    final metrics = <Widget>[
      RunMetricBox(
        icon: Icons.hotel_rounded,
        label: loc.sleepMonitorTimeInBed,
        value: SleepUi.duration(loc, session.timeInBedMinutes),
      ),
      RunMetricBox(
        icon: Icons.mic_none_rounded,
        label: loc.sleepMonitorTimeMonitored,
        value: SleepUi.duration(
          loc,
          end.difference(session.startedAt).inMinutes,
        ),
      ),
      if (session.sleepOnsetAt != null)
        RunMetricBox(
          icon: Icons.nightlight_outlined,
          label: loc.sleepOnsetTime,
          value: SleepUi.wallTime(
            session.sleepOnsetAt!,
            session.utcOffsetStartMinutes,
          ),
        ),
      if (session.finalWakeAt != null)
        RunMetricBox(
          icon: Icons.wb_sunny_outlined,
          label: loc.sleepFinalWake,
          value: SleepUi.wallTime(session.finalWakeAt!, endOffset),
        ),
      if (session.sleepLatencyMinutes != null)
        RunMetricBox(
          icon: Icons.hourglass_bottom_rounded,
          label: loc.sleepLatency,
          value: SleepUi.duration(loc, session.sleepLatencyMinutes),
        ),
      if (session.awakeningCount != null)
        RunMetricBox(
          icon: Icons.visibility_outlined,
          label: loc.sleepAwakenings,
          value: '${session.awakeningCount}',
        ),
      RunMetricBox(
        icon: Icons.graphic_eq_rounded,
        label: loc.sleepMonitorNoiseEvents,
        value: '${session.noiseEventCount}',
      ),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          _NightHero(
            session: session,
            window:
                '${SleepUi.wallTime(session.startedAt, session.utcOffsetStartMinutes)}'
                ' → ${SleepUi.wallTime(end, endOffset)}',
          ),
          const SizedBox(height: 12),
          RunMetricGrid(children: metrics),
          const SizedBox(height: 12),
          SleepStageCard(
            session: session,
            stages: _stages,
            showNightMetrics: false,
          ),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            RunSectionCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.notes_rounded,
                    size: 18,
                    color: colors.onSurfaceVariant,
                  ),
                  const SizedBox(width: 10),
                  Expanded(child: Text(comment)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                size: 16,
                color: colors.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  loc.sleepMonitorEstimateWarning,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _deleteSession() async {
    final loc = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(loc.sleepMonitorDeleteSession),
        content: Text(loc.sleepMonitorDeleteSessionBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(loc.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(loc.commonDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _repository.deleteSession(widget.sessionId);
    if (mounted) Navigator.pop(context, true);
  }
}

/// Estimated sleep and efficiency ring for the night, with its time window.
class _NightHero extends StatelessWidget {
  final SleepMonitorSession session;
  final String window;

  const _NightHero({required this.session, required this.window});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final loc = AppLocalizations.of(context)!;
    final efficiency = session.sleepEfficiency;
    final accent = SleepUi.efficiencyColor(colors, efficiency);
    return RunHeroCard(
      child: Row(
        children: [
          GoalProgressRing(
            percent: (efficiency ?? 0) / 100,
            color: accent,
            trackColor: accent.withAlpha(35),
            size: 88,
            strokeWidth: 8,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  efficiency == null ? '--' : '${efficiency.round()}%',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontFeatures: RunUi.tabular,
                  ),
                ),
                Text(
                  loc.sleepEfficiencyShort,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontSize: 10,
                    color: colors.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.sleepEstimatedAsleep,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    SleepUi.duration(loc, session.estimatedSleepMinutes),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                      fontFeatures: RunUi.tabular,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.bedtime_outlined,
                      size: 15,
                      color: colors.onSurfaceVariant,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      window,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontFeatures: RunUi.tabular,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                RunPill(
                  icon: Icons.mic_none_rounded,
                  label: loc.sleepMonitorSource,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
