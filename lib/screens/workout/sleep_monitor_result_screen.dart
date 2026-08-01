import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import 'package:workout_notes/l10n/app_localizations.dart';
import 'package:workout_notes/models/sleep_entry.dart';
import 'package:workout_notes/models/sleep_inference.dart';
import 'package:workout_notes/models/sleep_monitor_diagnostics.dart';
import 'package:workout_notes/models/sleep_monitor_segment.dart';
import 'package:workout_notes/models/sleep_monitor_session.dart';
import 'package:workout_notes/repositories/sleep_monitor_repository.dart';
import 'package:workout_notes/repositories/sleep_repository.dart';
import 'package:workout_notes/services/sleep_diagnostic_export_service.dart';
import 'package:workout_notes/services/sleep_inference_service.dart';
import 'package:workout_notes/services/sleep_monitor_service.dart';

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
  SleepMonitorDiagnostics? _diagnostics;
  SleepInferenceResult? _inference;
  bool _isLoading = true;
  bool _isExporting = false;

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
    final diagnostics = SleepMonitorDiagnostics.fromSession(session, segments);
    final inference = const SleepInferenceService().analyze(
      session: session,
      segments: segments,
      diagnostics: diagnostics,
    );
    if (!mounted) return;
    setState(() {
      _session = session;
      _segments = segments;
      _entry = entry;
      _diagnostics = diagnostics;
      _inference = inference;
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
    final diagnostics =
        _diagnostics ?? SleepMonitorDiagnostics.fromSession(session, _segments);
    final inference =
        _inference ??
        const SleepInferenceService().analyze(
          session: session,
          segments: _segments,
          diagnostics: diagnostics,
        );
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _SessionSummaryCard(
            session: session,
            diagnostics: diagnostics,
            loc: loc,
          ),
          const SizedBox(height: 12),
          _DataQualityCard(diagnostics: diagnostics, loc: loc),
          const SizedBox(height: 12),
          _InferenceSummaryCard(
            session: session,
            inference: inference,
            loc: loc,
          ),
          const SizedBox(height: 12),
          _ResultCard(
            title: loc.sleepMonitorTimeline,
            icon: Icons.timeline,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SleepMonitorTimeline(
                  segments: _segments,
                  session: session,
                  inference: inference,
                  emptyTitle: loc.sleepMonitorNoSegments,
                  emptyBody: loc.sleepMonitorNoSegmentsBody,
                ),
                if (_segments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _Legend(loc: loc),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${loc.sleepMonitorStartTime}: ${_formatTime(session.startedAt, session.utcOffsetStartMinutes)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        '${loc.sleepMonitorEndTime}: ${_formatTime(session.endedAt ?? session.startedAt, session.utcOffsetEndMinutes ?? session.utcOffsetStartMinutes)}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 12),
          _ResultCard(
            title: loc.sleepMonitorNoiseGraph,
            icon: Icons.show_chart,
            child: SleepNoiseChart(
              segments: _segments,
              session: session,
              inference: inference,
              emptyTitle: loc.sleepMonitorNoSegments,
              noiseScoreLabel: loc.sleepMonitorNoiseScore,
              thresholdLabel: loc.sleepMonitorThreshold,
            ),
          ),
          if (inference.isAvailable &&
              inference.events.any(
                (event) =>
                    event.type != SleepInferenceEventType.transientActivity,
              )) ...[
            const SizedBox(height: 12),
            _InferenceEventsCard(
              session: session,
              inference: inference,
              loc: loc,
            ),
          ],
          const SizedBox(height: 12),
          Card(
            color: Theme.of(context).colorScheme.tertiaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Text(loc.sleepMonitorEstimateWarning),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.tonalIcon(
            onPressed: _isExporting ? null : _exportDiagnostic,
            icon: _isExporting
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.ios_share_outlined),
            label: Text(loc.sleepMonitorExportDiagnostic),
          ),
        ],
      ),
    );
  }

  Future<void> _exportDiagnostic() async {
    final session = _session;
    if (session == null) return;
    final loc = AppLocalizations.of(context)!;
    final scope = await showDialog<_DiagnosticExportScope>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(loc.sleepMonitorExportDiagnosticTitle),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(loc.sleepMonitorExportDiagnosticBody),
              const SizedBox(height: 12),
              _ExportChoiceTile(
                icon: Icons.analytics_outlined,
                title: loc.sleepMonitorExportTechnicalOnly,
                subtitle: loc.sleepMonitorExportTechnicalOnlyBody,
                onTap: () => Navigator.pop(
                  dialogContext,
                  _DiagnosticExportScope.technical,
                ),
              ),
              const SizedBox(height: 8),
              _ExportChoiceTile(
                icon: Icons.person_outline,
                title: loc.sleepMonitorExportWithPersonal,
                subtitle: loc.sleepMonitorExportWithPersonalBody,
                isSensitive: true,
                onTap: () => Navigator.pop(
                  dialogContext,
                  _DiagnosticExportScope.personal,
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(loc.commonCancel),
          ),
        ],
      ),
    );
    if (scope == null || !mounted) return;

    setState(() => _isExporting = true);
    try {
      final diagnostics = SleepMonitorDiagnostics.fromSession(
        session,
        _segments,
      );
      final capabilities = await SleepMonitorService.instance.getCapabilities();
      await SleepDiagnosticExportService().exportAndShare(
        session: session,
        segments: _segments,
        diagnostics: diagnostics,
        inference:
            _inference ??
            const SleepInferenceService().analyze(
              session: session,
              segments: _segments,
              diagnostics: diagnostics,
            ),
        entry: _entry,
        includePersonalData: scope == _DiagnosticExportScope.personal,
        deviceInfo: capabilities,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.sleepMonitorExportSuccess)));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(loc.sleepMonitorExportError)));
      }
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
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

  static String _formatTime(DateTime value, int offsetMinutes) {
    final wallClock = value.toUtc().add(Duration(minutes: offsetMinutes));
    final day = wallClock.day.toString().padLeft(2, '0');
    final month = wallClock.month.toString().padLeft(2, '0');
    final hour = wallClock.hour.toString().padLeft(2, '0');
    final minute = wallClock.minute.toString().padLeft(2, '0');
    return '$day/$month $hour:$minute';
  }
}

enum _DiagnosticExportScope { technical, personal }

class _ExportChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool isSensitive;
  final VoidCallback onTap;

  const _ExportChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.isSensitive = false,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: isSensitive
          ? colorScheme.errorContainer.withAlpha(90)
          : colorScheme.secondaryContainer.withAlpha(100),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionSummaryCard extends StatelessWidget {
  final SleepMonitorSession session;
  final SleepMonitorDiagnostics diagnostics;
  final AppLocalizations loc;

  const _SessionSummaryCard({
    required this.session,
    required this.diagnostics,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    final values = [
      (
        loc.sleepMonitorTimeMonitored,
        _duration(diagnostics.sessionDurationSeconds),
      ),
      (loc.sleepMonitorCapturedSegments, '${diagnostics.segmentCount}'),
      (
        loc.sleepMonitorTimelineCoverage,
        _percentage(diagnostics.timelineCoverage),
      ),
      (loc.sleepMonitorSignalCoverage, _percentage(diagnostics.signalCoverage)),
      (
        loc.sleepMonitorDigitalSilence,
        _percentage(diagnostics.digitalSilenceFraction),
      ),
      (loc.sleepMonitorQuietPeriod, _duration(diagnostics.quietSeconds)),
      (loc.sleepMonitorNoisyPeriod, _duration(diagnostics.noisySeconds)),
      (loc.sleepMonitorNoiseEvents, '${session.noiseEventCount}'),
      (loc.sleepMonitorAverageNoise, _decimal(diagnostics.averageNoiseScore)),
      (loc.sleepMonitorPeakNoise, _decimal(diagnostics.peakNoiseScore)),
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

  static String _percentage(double value) => '${(value * 100).round()}%';

  static String _decimal(double? value) =>
      value == null ? '—' : value.toStringAsFixed(1);

  static String _duration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours == 0) return '$minutes min';
    return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
  }
}

class _DataQualityCard extends StatelessWidget {
  final SleepMonitorDiagnostics diagnostics;
  final AppLocalizations loc;

  const _DataQualityCard({required this.diagnostics, required this.loc});

  @override
  Widget build(BuildContext context) {
    final acceptable = diagnostics.isAcceptableForNextPhase;
    final colorScheme = Theme.of(context).colorScheme;
    final background = acceptable
        ? Colors.green.withAlpha(28)
        : colorScheme.errorContainer;
    final foreground = acceptable
        ? Colors.green.shade800
        : colorScheme.onErrorContainer;
    return Card(
      color: background,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              acceptable ? Icons.verified_outlined : Icons.warning_amber,
              color: foreground,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    loc.sleepMonitorDataQuality,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: foreground),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    acceptable
                        ? loc.sleepMonitorDataAcceptable
                        : loc.sleepMonitorDataInsufficient,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    acceptable
                        ? loc.sleepMonitorDataAcceptableBody
                        : diagnostics.inferenceBlockers
                              .map((blocker) => _blockerText(loc, blocker))
                              .join('\n'),
                    style: TextStyle(color: foreground),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _blockerText(AppLocalizations loc, String blocker) {
    return switch (blocker) {
      'too_short' => loc.sleepInferenceBlockerTooShort,
      'low_timeline_coverage' => loc.sleepInferenceBlockerLowTimelineCoverage,
      'low_signal_coverage' => loc.sleepInferenceBlockerLowSignalCoverage,
      'too_many_invalid_segments' => loc.sleepInferenceBlockerInvalidSegments,
      'digital_silence' => loc.sleepInferenceBlockerDigitalSilence,
      _ => loc.sleepMonitorDataInsufficientBody,
    };
  }
}

class _InferenceSummaryCard extends StatelessWidget {
  final SleepMonitorSession session;
  final SleepInferenceResult inference;
  final AppLocalizations loc;

  const _InferenceSummaryCard({
    required this.session,
    required this.inference,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    if (!inference.isAvailable) {
      return _ResultCard(
        title: loc.sleepInferenceTitle,
        icon: Icons.bedtime_outlined,
        child: Text(loc.sleepInferenceInsufficient),
      );
    }
    final onset = inference.sleepOnsetAt;
    final values = [
      (
        loc.sleepInferenceSleptAt,
        onset == null
            ? loc.sleepInferenceOnsetUnknown
            : _wallTime(onset, session.utcOffsetStartMinutes),
      ),
      (
        loc.sleepInferenceSettling,
        inference.settlingSeconds == null
            ? '—'
            : _duration(inference.settlingSeconds!),
      ),
      (loc.sleepInferenceAwakenings, '${inference.awakenings.length}'),
      (
        loc.sleepInferenceEstimatedSleep,
        inference.estimatedSleepSeconds == null
            ? '—'
            : _duration(inference.estimatedSleepSeconds!),
      ),
    ];
    return _ResultCard(
      title: loc.sleepInferenceTitle,
      icon: Icons.bedtime_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          const SizedBox(height: 14),
          Chip(
            avatar: const Icon(Icons.analytics_outlined, size: 18),
            label: Text(
              '${loc.sleepInferenceConfidence}: '
              '${_confidenceLabel(loc, inference.confidence)}',
            ),
          ),
        ],
      ),
    );
  }
}

class _InferenceEventsCard extends StatelessWidget {
  final SleepMonitorSession session;
  final SleepInferenceResult inference;
  final AppLocalizations loc;

  const _InferenceEventsCard({
    required this.session,
    required this.inference,
    required this.loc,
  });

  @override
  Widget build(BuildContext context) {
    return _ResultCard(
      title: loc.sleepInferenceEventsTitle,
      icon: Icons.notifications_active_outlined,
      child: Column(
        children: inference.events
            .where(
              (event) =>
                  event.type != SleepInferenceEventType.transientActivity,
            )
            .map((event) {
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: _eventColor(event.type).withAlpha(34),
                  child: Icon(
                    _eventIcon(event.type),
                    color: _eventColor(event.type),
                  ),
                ),
                title: Text(_eventLabel(loc, event.type)),
                subtitle: Text(
                  '${_wallTime(event.startedAt, session.utcOffsetStartMinutes)} · '
                  '${_duration(event.durationSeconds)} · '
                  '${loc.sleepInferencePeak}: '
                  '${event.peakNoiseScore.toStringAsFixed(1)}\n'
                  '${_reasonLabel(loc, event.reason)}',
                ),
                trailing: Text(
                  _confidenceLabel(loc, event.confidence),
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              );
            })
            .toList(),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _ResultCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class SleepMonitorTimeline extends StatelessWidget {
  final List<SleepMonitorSegment> segments;
  final SleepMonitorSession session;
  final SleepInferenceResult inference;
  final String? emptyTitle;
  final String? emptyBody;

  const SleepMonitorTimeline({
    super.key,
    required this.segments,
    required this.session,
    required this.inference,
    this.emptyTitle,
    this.emptyBody,
  });

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) {
      return _EmptyData(title: emptyTitle ?? 'No signal data', body: emptyBody);
    }
    return Semantics(
      label: 'Sleep monitoring timeline with ${segments.length} segments',
      child: SizedBox(
        height: 44,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: CustomPaint(
            painter: _SleepTimelinePainter(segments, session, inference),
          ),
        ),
      ),
    );
  }
}

class _SleepTimelinePainter extends CustomPainter {
  final List<SleepMonitorSegment> segments;
  final SleepMonitorSession session;
  final SleepInferenceResult inference;

  const _SleepTimelinePainter(this.segments, this.session, this.inference);

  @override
  void paint(Canvas canvas, Size size) {
    final sessionEnd = session.endedAt ?? segments.last.startedAt;
    final totalSeconds = sessionEnd.difference(session.startedAt).inSeconds;
    if (totalSeconds <= 0) return;
    for (final segment in segments) {
      final duration = segment.durationSeconds.clamp(1, 3600);
      final offset = segment.startedAt
          .difference(session.startedAt)
          .inSeconds
          .clamp(0, totalSeconds);
      final left = size.width * offset / totalSeconds;
      final width = size.width * duration / totalSeconds;
      final color = switch (segment.classification) {
        'noise' => Colors.orange,
        'invalid' => Colors.grey,
        _ => Colors.teal,
      };
      canvas.drawRect(
        Rect.fromLTWH(left, 0, math.max(width, 0.5), size.height),
        Paint()..color = color,
      );
    }

    _drawRange(
      canvas,
      size,
      totalSeconds,
      session.startedAt,
      session.startedAt.add(
        const Duration(seconds: SleepInferenceService.preparationSeconds),
      ),
      Colors.blue.withAlpha(65),
    );
    final settlingStart = inference.settlingStartedAt;
    final settlingEnd = inference.settlingEndedAt;
    if (settlingStart != null && settlingEnd != null) {
      _drawRange(
        canvas,
        size,
        totalSeconds,
        settlingStart,
        settlingEnd,
        Colors.purple.withAlpha(55),
      );
    }
    for (final event in inference.events) {
      if (event.type == SleepInferenceEventType.transientActivity) continue;
      final left = _x(event.startedAt, size, totalSeconds);
      final right = _x(event.endedAt, size, totalSeconds);
      canvas.drawRect(
        Rect.fromLTRB(
          left,
          size.height - 8,
          math.max(left + 2, right),
          size.height,
        ),
        Paint()..color = _eventColor(event.type),
      );
    }
    final onset = inference.sleepOnsetAt;
    if (onset != null) {
      final x = _x(onset, size, totalSeconds);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = Colors.lightBlueAccent
          ..strokeWidth = 3,
      );
    }
  }

  void _drawRange(
    Canvas canvas,
    Size size,
    int totalSeconds,
    DateTime start,
    DateTime end,
    Color color,
  ) {
    final left = _x(start, size, totalSeconds);
    final right = _x(end, size, totalSeconds);
    canvas.drawRect(
      Rect.fromLTRB(left, 0, math.max(left, right), size.height),
      Paint()..color = color,
    );
  }

  double _x(DateTime value, Size size, int totalSeconds) {
    final seconds = value
        .difference(session.startedAt)
        .inSeconds
        .clamp(0, totalSeconds);
    return size.width * seconds / totalSeconds;
  }

  @override
  bool shouldRepaint(_SleepTimelinePainter oldDelegate) =>
      oldDelegate.segments != segments ||
      oldDelegate.session != session ||
      oldDelegate.inference != inference;
}

class SleepNoiseChart extends StatelessWidget {
  final List<SleepMonitorSegment> segments;
  final SleepMonitorSession session;
  final SleepInferenceResult inference;
  final String emptyTitle;
  final String noiseScoreLabel;
  final String thresholdLabel;

  const SleepNoiseChart({
    super.key,
    required this.segments,
    required this.session,
    required this.inference,
    required this.emptyTitle,
    required this.noiseScoreLabel,
    required this.thresholdLabel,
  });

  @override
  Widget build(BuildContext context) {
    final scored = segments
        .where((segment) => segment.noiseScore != null)
        .toList();
    if (scored.isEmpty) return _EmptyData(title: emptyTitle);
    final start = session.startedAt;
    final spots = scored
        .map(
          (segment) => FlSpot(
            segment.startedAt.difference(start).inSeconds / 60.0,
            segment.noiseScore!,
          ),
        )
        .toList();
    final maxX = math.max(1.0, spots.last.x);
    final maxY = math.max(
      12.0,
      spots.map((spot) => spot.y).fold<double>(0, math.max) + 2,
    );
    final color = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(width: 16, height: 3, color: color),
            const SizedBox(width: 6),
            Text(noiseScoreLabel, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(width: 14),
            Container(width: 16, height: 2, color: Colors.orange),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '$thresholdLabel: 10',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 220,
          child: LineChart(
            LineChartData(
              minX: 0,
              maxX: maxX,
              minY: 0,
              maxY: maxY,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(show: true, drawVerticalLine: false),
              lineTouchData: const LineTouchData(enabled: true),
              extraLinesData: ExtraLinesData(
                horizontalLines: [
                  HorizontalLine(
                    y: 10,
                    color: Colors.orange,
                    strokeWidth: 1.5,
                    dashArray: [5, 4],
                  ),
                ],
                verticalLines: [
                  if (inference.sleepOnsetAt != null)
                    VerticalLine(
                      x:
                          inference.sleepOnsetAt!.difference(start).inSeconds /
                          60.0,
                      color: Colors.lightBlue,
                      strokeWidth: 2,
                    ),
                  ...inference.events
                      .where(
                        (event) =>
                            event.type == SleepInferenceEventType.awakening ||
                            event.type == SleepInferenceEventType.finalActivity,
                      )
                      .map(
                        (event) => VerticalLine(
                          x: event.startedAt.difference(start).inSeconds / 60.0,
                          color: _eventColor(event.type),
                          strokeWidth: 1.5,
                          dashArray: [4, 3],
                        ),
                      ),
                ],
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                rightTitles: const AxisTitles(
                  sideTitles: SideTitles(showTitles: false),
                ),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 30,
                    interval: 5,
                    getTitlesWidget: (value, meta) => Text(
                      value.toInt().toString(),
                      style: const TextStyle(fontSize: 10),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: math.max(60.0, maxX / 4),
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(
                        '${(value / 60).toStringAsFixed(value >= 60 ? 0 : 1)}h',
                        style: const TextStyle(fontSize: 10),
                      ),
                    ),
                  ),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: false,
                  color: color,
                  barWidth: 2,
                  dotData: FlDotData(show: spots.length <= 80),
                  belowBarData: BarAreaData(
                    show: true,
                    color: color.withAlpha(24),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _EmptyData extends StatelessWidget {
  final String title;
  final String? body;

  const _EmptyData({required this.title, this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withAlpha(100),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(
            Icons.signal_wifi_bad,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 8),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (body != null) ...[
            const SizedBox(height: 6),
            Text(body!, textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }
}

String _wallTime(DateTime value, int offsetMinutes) {
  final wallClock = value.toUtc().add(Duration(minutes: offsetMinutes));
  final hour = wallClock.hour.toString().padLeft(2, '0');
  final minute = wallClock.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _duration(int seconds) {
  final safeSeconds = seconds.clamp(0, 16 * 60 * 60);
  final hours = safeSeconds ~/ 3600;
  final minutes = (safeSeconds % 3600) ~/ 60;
  if (hours == 0) return '$minutes min';
  return '${hours}h ${minutes.toString().padLeft(2, '0')}min';
}

String _confidenceLabel(
  AppLocalizations loc,
  SleepInferenceConfidence confidence,
) {
  return switch (confidence) {
    SleepInferenceConfidence.low => loc.sleepInferenceConfidenceLow,
    SleepInferenceConfidence.medium => loc.sleepInferenceConfidenceMedium,
  };
}

String _eventLabel(AppLocalizations loc, SleepInferenceEventType type) {
  return switch (type) {
    SleepInferenceEventType.transientActivity =>
      loc.sleepInferenceEventTransient,
    SleepInferenceEventType.prolongedActivity =>
      loc.sleepInferenceEventProlonged,
    SleepInferenceEventType.awakening => loc.sleepInferenceEventAwakening,
    SleepInferenceEventType.finalActivity =>
      loc.sleepInferenceEventFinalActivity,
  };
}

String _reasonLabel(AppLocalizations loc, String reason) {
  return switch (reason) {
    'short_activity' => loc.sleepInferenceReasonShort,
    'sustained_activity' => loc.sleepInferenceReasonSustained,
    'sustained_activity_with_quiet_recovery' =>
      loc.sleepInferenceReasonAwakening,
    'sustained_activity_near_end' => loc.sleepInferenceReasonFinal,
    _ => reason,
  };
}

Color _eventColor(SleepInferenceEventType type) {
  return switch (type) {
    SleepInferenceEventType.transientActivity => Colors.amber,
    SleepInferenceEventType.prolongedActivity => Colors.deepOrange,
    SleepInferenceEventType.awakening => Colors.redAccent,
    SleepInferenceEventType.finalActivity => Colors.purple,
  };
}

IconData _eventIcon(SleepInferenceEventType type) {
  return switch (type) {
    SleepInferenceEventType.transientActivity => Icons.graphic_eq,
    SleepInferenceEventType.prolongedActivity => Icons.waves,
    SleepInferenceEventType.awakening => Icons.visibility_outlined,
    SleepInferenceEventType.finalActivity => Icons.alarm_outlined,
  };
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

class _Legend extends StatelessWidget {
  final AppLocalizations loc;

  const _Legend({required this.loc});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 14,
      runSpacing: 6,
      children: [
        _LegendItem(color: Colors.teal, label: loc.sleepMonitorQuiet),
        _LegendItem(color: Colors.orange, label: loc.sleepMonitorNoise),
        _LegendItem(color: Colors.grey, label: loc.sleepMonitorInvalid),
        _LegendItem(
          color: Colors.blue.withAlpha(150),
          label: loc.sleepInferencePreparation,
        ),
        _LegendItem(
          color: Colors.purple.withAlpha(150),
          label: loc.sleepInferenceSettling,
        ),
        _LegendItem(
          color: Colors.lightBlueAccent,
          label: loc.sleepInferenceSleptAt,
        ),
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
