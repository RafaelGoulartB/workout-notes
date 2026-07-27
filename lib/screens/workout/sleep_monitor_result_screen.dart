import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/repositories/sleep_monitor_repository.dart';
import 'package:workout_notes/repositories/sleep_repository.dart';

import 'sleep_entry_sheet.dart';

class SleepMonitorResultScreen extends StatefulWidget {
  final String sessionId;

  const SleepMonitorResultScreen({super.key, required this.sessionId});

  @override
  State<SleepMonitorResultScreen> createState() =>
      _SleepMonitorResultScreenState();
}

class _SleepMonitorResultScreenState extends State<SleepMonitorResultScreen> {
  final _repository = SleepMonitorRepository();
  final _sleepRepository = SleepRepository();
  SleepMonitorSession? _session;
  SleepEntry? _entry;
  List<SleepMonitorSegment> _segments = const [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = await _repository.getSession(widget.sessionId);
    if (session == null) {
      if (mounted) setState(() => _isLoading = false);
      return;
    }
    final segments = await _repository.getSegments(widget.sessionId);
    final entry = session.sleepEntryId == null
        ? null
        : await _sleepRepository.getById(session.sleepEntryId!);
    if (!mounted) return;
    setState(() {
      _session = session;
      _segments = segments;
      _entry = entry;
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
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SourceBadge(label: loc.sleepMonitorSource),
                        const SizedBox(height: 14),
                        Text(
                          _formatDate(session.endedAt ?? session.startedAt),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 16),
                        _MetricGrid(session: session, loc: loc),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          loc.sleepMonitorTimeline,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 12),
                        SleepMonitorTimeline(segments: _segments),
                        const SizedBox(height: 10),
                        _Legend(loc: loc),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(loc.sleepMonitorEstimateWarning),
                  ),
                ),
                const SizedBox(height: 14),
                if (_entry != null)
                  OutlinedButton.icon(
                    onPressed: _editManualEntry,
                    icon: const Icon(Icons.edit_outlined),
                    label: Text(loc.sleepMonitorEditManual),
                  ),
              ],
            ),
    );
  }

  Future<void> _editManualEntry() async {
    final entry = _entry;
    if (entry == null) return;
    await showSleepEntrySheet(
      context,
      repository: _sleepRepository,
      existing: entry,
      onSaved: _load,
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

  static String _formatDate(DateTime value) =>
      '${value.toLocal().day.toString().padLeft(2, '0')}/${value.toLocal().month.toString().padLeft(2, '0')}/${value.toLocal().year}';
}

class SleepMonitorTimeline extends StatelessWidget {
  final List<SleepMonitorSegment> segments;

  const SleepMonitorTimeline({super.key, required this.segments});

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return const SizedBox(height: 32);
    }
    return SizedBox(
      height: 32,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: segments.map((segment) {
            final color = switch (segment.classification) {
              'noise' => Colors.orange,
              'invalid' => Colors.grey,
              _ => Colors.teal,
            };
            return Expanded(
              flex: segment.durationSeconds.clamp(1, 3600),
              child: Tooltip(
                message: segment.classification,
                child: ColoredBox(color: color),
              ),
            );
          }).toList(),
        ),
      ),
    );
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

class _MetricGrid extends StatelessWidget {
  final SleepMonitorSession session;
  final AppLocalizations loc;

  const _MetricGrid({required this.session, required this.loc});

  @override
  Widget build(BuildContext context) {
    final values = [
      (loc.sleepMonitorTimeMonitored, _minutes(session.timeInBedMinutes)),
      (loc.sleepMonitorQuietPeriod, _minutes(session.quietMinutes)),
      (loc.sleepMonitorNoisyPeriod, _minutes(session.noisyMinutes)),
      (loc.sleepMonitorNoiseEvents, '${session.noiseEventCount}'),
      (
        loc.sleepMonitorSignalCoverage,
        session.signalQualityScore == null
            ? '—'
            : '${(session.signalQualityScore! * 100).toStringAsFixed(0)}%',
      ),
    ];
    return Wrap(
      spacing: 14,
      runSpacing: 14,
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
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          )
          .toList(),
    );
  }

  static String _minutes(int? minutes) {
    if (minutes == null) return '—';
    return '$minutes min';
  }
}

class _Legend extends StatelessWidget {
  final AppLocalizations loc;

  const _Legend({required this.loc});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      children: [
        _LegendItem(color: Colors.teal, label: loc.sleepMonitorQuiet),
        _LegendItem(color: Colors.orange, label: loc.sleepMonitorNoise),
        _LegendItem(color: Colors.grey, label: loc.sleepMonitorInvalid),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  final Color color;
  final String label;

  const _LegendItem({required this.color, required this.label});

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
