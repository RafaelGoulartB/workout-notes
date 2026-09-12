import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/repositories/sleep_monitor_repository.dart';
import 'package:workout_notes/widgets/sleep/sleep_stage_card.dart';

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
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await _repository.getSession(widget.sessionId);
    if (!mounted) return;
    setState(() {
      _session = session;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final loc = AppLocalizations.of(context)!;
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        title: Text(loc.sleepMonitorResultTitle),
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
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _SessionSummaryCard(session: session, loc: loc),
          const SizedBox(height: 12),
          SleepStageCard(session: session, stages: const []),
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(loc.sleepMonitorEstimateWarning),
            ),
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

class _SessionSummaryCard extends StatelessWidget {
  final SleepMonitorSession session;
  final AppLocalizations loc;

  const _SessionSummaryCard({required this.session, required this.loc});

  @override
  Widget build(BuildContext context) {
    final end = session.endedAt ?? session.startedAt;
    final values = [
      (
        loc.sleepMonitorTimeMonitored,
        _duration(end.difference(session.startedAt).inSeconds),
      ),
      (loc.sleepMonitorTimeInBed, _minutes(session.timeInBedMinutes)),
      (
        loc.sleepInferenceEstimatedSleep,
        _minutes(session.estimatedSleepMinutes),
      ),
      (loc.sleepEfficiency, _percentage(session.sleepEfficiency)),
      (loc.sleepAwakenings, session.awakeningCount?.toString() ?? '—'),
      (loc.sleepMonitorNoiseEvents, '${session.noiseEventCount}'),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SourceBadge(label: loc.sleepMonitorSource),
            const SizedBox(height: 14),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: values
                  .map(
                    (value) => SizedBox(
                      width: 142,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            value.$1,
                            style: Theme.of(context).textTheme.labelMedium,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            value.$2,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  static String _percentage(double? value) =>
      value == null ? '—' : '${value.round()}%';

  static String _minutes(int? value) {
    if (value == null) return '—';
    final safe = value.clamp(0, 16 * 60);
    final hours = safe ~/ 60;
    final minutes = safe % 60;
    return hours == 0
        ? '$minutes min'
        : '${hours}h ${minutes.toString().padLeft(2, '0')}min';
  }

  static String _duration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours == 0) return '$minutes min';
    return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
  }
}

class _SourceBadge extends StatelessWidget {
  final String label;

  const _SourceBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      avatar: const Icon(Icons.mic_none, size: 18),
      label: Text(label),
    );
  }
}
