import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/repositories/sleep_monitor_repository.dart';
import 'package:workout_notes/widgets/ui/ui.dart';
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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await _repository.getSession(widget.sessionId);
    SleepEntry? entry;
    if (session != null && session.sleepEntryId != null) {
      // The entry is an extra: a failed read must not hide the session.
      try {
        entry = await _repository.getSleepEntry(session.sleepEntryId!);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _session = session;
      _entry = entry;
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
      AppMetricBox(
        icon: Icons.hotel_rounded,
        label: loc.sleepMonitorTimeInBed,
        value: SleepUi.duration(loc, session.timeInBedMinutes),
      ),
      AppMetricBox(
        icon: Icons.mic_none_rounded,
        label: loc.sleepMonitorTimeMonitored,
        value: SleepUi.duration(
          loc,
          end.difference(session.startedAt).inMinutes,
        ),
      ),
      if (session.sleepOnsetAt != null)
        AppMetricBox(
          icon: Icons.nightlight_outlined,
          label: loc.sleepOnsetTime,
          value: SleepUi.wallTime(
            session.sleepOnsetAt!,
            session.utcOffsetStartMinutes,
          ),
        ),
      if (session.finalWakeAt != null)
        AppMetricBox(
          icon: Icons.wb_sunny_outlined,
          label: loc.sleepFinalWake,
          value: SleepUi.wallTime(session.finalWakeAt!, endOffset),
        ),
      if (session.sleepLatencyMinutes != null)
        AppMetricBox(
          icon: Icons.hourglass_bottom_rounded,
          label: loc.sleepLatency,
          value: SleepUi.duration(loc, session.sleepLatencyMinutes),
        ),
      if (session.awakeningCount != null)
        AppMetricBox(
          icon: Icons.visibility_outlined,
          label: loc.sleepAwakenings,
          value: '${session.awakeningCount}',
        ),
      AppMetricBox(
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
          AppMetricGrid(children: metrics),
          const SizedBox(height: 12),
          SleepStageCard(session: session, showNightMetrics: false),
          if (comment != null && comment.isNotEmpty) ...[
            const SizedBox(height: 12),
            AppSectionCard(
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
    final confirmed = await showConfirmDialog(
      context,
      title: loc.sleepMonitorDeleteSession,
      message: loc.sleepMonitorDeleteSessionBody,
      confirmLabel: loc.commonDelete,
    );
    if (confirmed != true) return;
    await _repository.deleteSession(widget.sessionId);
    if (mounted) Navigator.pop(context, true);
  }
}

/// Estimated sleep and efficiency for the night, laid out like the nutrition
/// day summary: big duration, efficiency on the right, time window and an
/// efficiency bar.
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
    return AppSoftCard(
      padding: SleepUi.cardPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SleepCardHeader(
            icon: Icons.bedtime_rounded,
            title: loc.sleepEstimatedAsleep,
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: SleepBigDuration(minutes: session.estimatedSleepMinutes),
              ),
              const SizedBox(width: 8),
              SleepHeadlinePercent(
                value: efficiency == null ? '--' : '${efficiency.round()}%',
                caption: loc.sleepEfficiencyShort,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${loc.sleepInBedShort} '
            '${SleepUi.duration(loc, session.timeInBedMinutes)}',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              SleepBadge(icon: Icons.nightlight_round, label: window),
              SleepBadge(
                icon: Icons.mic_none_rounded,
                label: loc.sleepMonitorSource,
                color: colors.secondary,
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ((efficiency ?? 0) / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: colors.surfaceContainerHighest,
              color: colors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
