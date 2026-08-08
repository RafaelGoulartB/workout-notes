import '../models/sleep_inference.dart';
import '../models/sleep_monitor_diagnostics.dart';
import '../models/sleep_monitor_segment.dart';
import '../models/sleep_monitor_session.dart';

class SleepInferenceService {
  static const preparationSeconds = 5 * 60;
  static const activityStartScore = 10.0;
  static const activityHoldScore = 6.0;
  static const eventMergeGapSeconds = 60;
  static const prolongedEnvelopeSeconds = 3 * 60;
  static const prolongedActiveSeconds = 90;
  static const prolongedPeakScore = 15.0;
  static const onsetWindowSeconds = 30 * 60;
  static const recoveryWindowSeconds = 10 * 60;
  static const wakeGuardSeconds = 20 * 60;
  static const finalActivitySeconds = 10 * 60;
  static const minimumWindowValidFraction = 0.80;
  static const onsetBelowStartFraction = 0.90;
  static const onsetBelowHoldFraction = 0.70;
  static const recoveryQuietFraction = 0.80;

  static const parameters = <String, num>{
    'preparation_seconds': preparationSeconds,
    'activity_start_score': activityStartScore,
    'activity_hold_score': activityHoldScore,
    'event_merge_gap_seconds': eventMergeGapSeconds,
    'prolonged_envelope_seconds': prolongedEnvelopeSeconds,
    'prolonged_active_seconds': prolongedActiveSeconds,
    'prolonged_peak_score': prolongedPeakScore,
    'onset_window_seconds': onsetWindowSeconds,
    'recovery_window_seconds': recoveryWindowSeconds,
    'wake_guard_seconds': wakeGuardSeconds,
    'final_activity_seconds': finalActivitySeconds,
    'minimum_window_valid_fraction': minimumWindowValidFraction,
    'onset_below_start_fraction': onsetBelowStartFraction,
    'onset_below_hold_fraction': onsetBelowHoldFraction,
    'recovery_quiet_fraction': recoveryQuietFraction,
  };

  const SleepInferenceService();

  SleepInferenceResult analyze({
    required SleepMonitorSession session,
    required List<SleepMonitorSegment> segments,
    required SleepMonitorDiagnostics diagnostics,
  }) {
    if (!diagnostics.isSuitableForInference) {
      return SleepInferenceResult(
        status: SleepInferenceStatus.insufficientData,
        confidence: SleepInferenceConfidence.low,
        sleepOnsetAt: null,
        settlingStartedAt: null,
        settlingEndedAt: null,
        estimatedSleepSeconds: null,
        events: const [],
        blockers: diagnostics.inferenceBlockers,
        parameters: parameters,
      );
    }

    final ordered = [...segments]
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final rawEvents = _mergeEvents(_extractEvents(ordered), ordered);
    final prolonged = rawEvents.where(_isProlonged).toList(growable: false);
    final onset = _findSleepOnset(session, ordered, prolonged);
    final sessionEnd = session.endedAt ?? session.startedAt;
    final classifiedEvents = _classifyEvents(
      rawEvents,
      ordered,
      onset,
      sessionEnd,
    );
    final confidence = onset == null
        ? SleepInferenceConfidence.low
        : _onsetConfidence(session, ordered, onset);
    final awakeningSeconds = classifiedEvents
        .where((event) => event.type == SleepInferenceEventType.awakening)
        .fold<int>(0, (sum, event) => sum + event.durationSeconds);
    final estimatedSleepSeconds = onset == null
        ? null
        : (sessionEnd.difference(onset).inSeconds - awakeningSeconds).clamp(
            0,
            16 * 60 * 60,
          );
    final settlingStart = session.startedAt.add(
      const Duration(seconds: preparationSeconds),
    );

    return SleepInferenceResult(
      status: SleepInferenceStatus.available,
      confidence: confidence,
      sleepOnsetAt: onset,
      settlingStartedAt: onset == null ? null : settlingStart,
      settlingEndedAt: onset,
      estimatedSleepSeconds: estimatedSleepSeconds,
      events: List.unmodifiable(classifiedEvents),
      blockers: const [],
      parameters: parameters,
    );
  }

  List<_ActivityEnvelope> _extractEvents(List<SleepMonitorSegment> segments) {
    final events = <_ActivityEnvelope>[];
    _ActivityEnvelope? current;
    var consecutiveLow = 0;

    for (final segment in segments) {
      if (current != null &&
          segment.startedAt.difference(current.endedAt).inSeconds >
              eventMergeGapSeconds) {
        events.add(current);
        current = null;
        consecutiveLow = 0;
      }
      if (!_isValid(segment)) {
        if (current != null) {
          consecutiveLow++;
          if (consecutiveLow >= 2) {
            events.add(current);
            current = null;
            consecutiveLow = 0;
          }
        }
        continue;
      }
      final score = segment.noiseScore!;
      final segmentEnd = _segmentEnd(segment);

      if (current == null) {
        if (score >= activityStartScore) {
          current = _ActivityEnvelope(
            startedAt: segment.startedAt,
            endedAt: segmentEnd,
            activeSeconds: segment.durationSeconds,
            peakNoiseScore: score,
          );
        }
        continue;
      }

      if (score >= activityHoldScore) {
        consecutiveLow = 0;
        current = current.copyWith(
          endedAt: segmentEnd,
          activeSeconds:
              current.activeSeconds +
              (score >= activityStartScore ? segment.durationSeconds : 0),
          peakNoiseScore: score > current.peakNoiseScore
              ? score
              : current.peakNoiseScore,
        );
        continue;
      }

      consecutiveLow++;
      if (consecutiveLow >= 2) {
        events.add(current);
        current = null;
        consecutiveLow = 0;
      }
    }
    if (current != null) events.add(current);
    return events;
  }

  List<_ActivityEnvelope> _mergeEvents(
    List<_ActivityEnvelope> source,
    List<SleepMonitorSegment> segments,
  ) {
    if (source.isEmpty) return const [];
    final merged = <_ActivityEnvelope>[source.first];
    for (final event in source.skip(1)) {
      final previous = merged.last;
      final gap = event.startedAt.difference(previous.endedAt).inSeconds;
      final hasInvalidGap = segments.any(
        (segment) =>
            segment.isInvalid &&
            !segment.startedAt.isBefore(previous.endedAt) &&
            segment.startedAt.isBefore(event.startedAt),
      );
      if (gap <= eventMergeGapSeconds && !hasInvalidGap) {
        merged[merged.length - 1] = _ActivityEnvelope(
          startedAt: previous.startedAt,
          endedAt: event.endedAt,
          activeSeconds: previous.activeSeconds + event.activeSeconds,
          peakNoiseScore: event.peakNoiseScore > previous.peakNoiseScore
              ? event.peakNoiseScore
              : previous.peakNoiseScore,
        );
      } else {
        merged.add(event);
      }
    }
    return merged;
  }

  bool _isProlonged(_ActivityEnvelope event) =>
      event.durationSeconds >= prolongedEnvelopeSeconds &&
      event.activeSeconds >= prolongedActiveSeconds &&
      event.peakNoiseScore >= prolongedPeakScore;

  DateTime? _findSleepOnset(
    SleepMonitorSession session,
    List<SleepMonitorSegment> segments,
    List<_ActivityEnvelope> prolonged,
  ) {
    final preparationEnd = session.startedAt.add(
      const Duration(seconds: preparationSeconds),
    );
    final sessionEnd = session.endedAt ?? session.startedAt;

    for (final segment in segments) {
      final candidate = segment.startedAt;
      if (candidate.isBefore(preparationEnd)) continue;
      final windowEnd = candidate.add(
        const Duration(seconds: onsetWindowSeconds),
      );
      if (windowEnd.isAfter(sessionEnd)) break;
      final stats = _windowStats(segments, candidate, windowEnd);
      if (stats.validFraction < minimumWindowValidFraction) continue;
      if (stats.belowStartFraction < onsetBelowStartFraction) continue;
      if (stats.belowHoldFraction < onsetBelowHoldFraction) continue;
      final hasProlonged = prolonged.any(
        (event) =>
            _overlaps(event.startedAt, event.endedAt, candidate, windowEnd),
      );
      if (!hasProlonged) return candidate;
    }
    return null;
  }

  List<SleepInferenceEvent> _classifyEvents(
    List<_ActivityEnvelope> events,
    List<SleepMonitorSegment> segments,
    DateTime? onset,
    DateTime sessionEnd,
  ) {
    return events
        .map((event) {
          final prolonged = _isProlonged(event);
          var type = prolonged
              ? SleepInferenceEventType.prolongedActivity
              : SleepInferenceEventType.transientActivity;
          var reason = prolonged ? 'sustained_activity' : 'short_activity';
          var confidence = prolonged
              ? SleepInferenceConfidence.medium
              : SleepInferenceConfidence.low;

          if (prolonged &&
              !event.startedAt.isBefore(
                sessionEnd.subtract(
                  const Duration(seconds: finalActivitySeconds),
                ),
              )) {
            type = SleepInferenceEventType.finalActivity;
            reason = 'sustained_activity_near_end';
          } else if (prolonged &&
              onset != null &&
              !event.startedAt.isBefore(
                onset.add(const Duration(seconds: wakeGuardSeconds)),
              ) &&
              _hasQuietRecovery(event, segments, sessionEnd)) {
            type = SleepInferenceEventType.awakening;
            reason = 'sustained_activity_with_quiet_recovery';
            confidence = SleepInferenceConfidence.medium;
          }

          return SleepInferenceEvent(
            type: type,
            startedAt: event.startedAt,
            endedAt: event.endedAt,
            activeSeconds: event.activeSeconds,
            peakNoiseScore: event.peakNoiseScore,
            confidence: confidence,
            reason: reason,
          );
        })
        .toList(growable: false);
  }

  bool _hasQuietRecovery(
    _ActivityEnvelope event,
    List<SleepMonitorSegment> segments,
    DateTime sessionEnd,
  ) {
    final recoveryEnd = event.endedAt.add(
      const Duration(seconds: recoveryWindowSeconds),
    );
    if (recoveryEnd.isAfter(sessionEnd)) return false;
    final stats = _windowStats(segments, event.endedAt, recoveryEnd);
    return stats.validFraction >= minimumWindowValidFraction &&
        stats.belowStartFraction >= recoveryQuietFraction;
  }

  SleepInferenceConfidence _onsetConfidence(
    SleepMonitorSession session,
    List<SleepMonitorSegment> segments,
    DateTime onset,
  ) {
    final latency = onset.difference(session.startedAt).inSeconds;
    if (latency <= 10 * 60) return SleepInferenceConfidence.low;
    final preStart = onset.subtract(const Duration(minutes: 10));
    final preSegments = _segmentsInWindow(segments, preStart, onset);
    final activeSeconds = preSegments
        .where(_isValid)
        .where((segment) => segment.noiseScore! >= activityStartScore)
        .fold<int>(0, (sum, segment) => sum + segment.durationSeconds);
    final afterEnd = onset.add(const Duration(minutes: 10));
    final beforeMedian = _median(
      preSegments
          .where(_isValid)
          .map((segment) => segment.noiseScore!)
          .toList(),
    );
    final afterMedian = _median(
      _segmentsInWindow(
        segments,
        onset,
        afterEnd,
      ).where(_isValid).map((segment) => segment.noiseScore!).toList(),
    );
    final clearDrop =
        beforeMedian != null &&
        afterMedian != null &&
        beforeMedian - afterMedian >= 3;
    return activeSeconds >= 90 || clearDrop
        ? SleepInferenceConfidence.medium
        : SleepInferenceConfidence.low;
  }

  _WindowStats _windowStats(
    List<SleepMonitorSegment> segments,
    DateTime start,
    DateTime end,
  ) {
    final expectedSeconds = end.difference(start).inSeconds;
    var validSeconds = 0;
    var belowStartSeconds = 0;
    var belowHoldSeconds = 0;
    for (final segment in _segmentsInWindow(segments, start, end)) {
      if (!_isValid(segment)) continue;
      final overlap = _overlapSeconds(
        segment.startedAt,
        _segmentEnd(segment),
        start,
        end,
      );
      validSeconds += overlap;
      if (segment.noiseScore! < activityStartScore) {
        belowStartSeconds += overlap;
      }
      if (segment.noiseScore! < activityHoldScore) {
        belowHoldSeconds += overlap;
      }
    }
    return _WindowStats(
      validFraction: expectedSeconds <= 0 ? 0 : validSeconds / expectedSeconds,
      belowStartFraction: validSeconds <= 0
          ? 0
          : belowStartSeconds / validSeconds,
      belowHoldFraction: validSeconds <= 0
          ? 0
          : belowHoldSeconds / validSeconds,
    );
  }

  List<SleepMonitorSegment> _segmentsInWindow(
    List<SleepMonitorSegment> segments,
    DateTime start,
    DateTime end,
  ) => segments
      .where(
        (segment) =>
            _segmentEnd(segment).isAfter(start) &&
            segment.startedAt.isBefore(end),
      )
      .toList(growable: false);

  bool _isValid(SleepMonitorSegment segment) =>
      !segment.isInvalid &&
      segment.validFraction >= 0.5 &&
      segment.noiseScore != null;

  DateTime _segmentEnd(SleepMonitorSegment segment) =>
      segment.startedAt.add(Duration(seconds: segment.durationSeconds));

  bool _overlaps(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) => aEnd.isAfter(bStart) && aStart.isBefore(bEnd);

  int _overlapSeconds(
    DateTime aStart,
    DateTime aEnd,
    DateTime bStart,
    DateTime bEnd,
  ) {
    final start = aStart.isAfter(bStart) ? aStart : bStart;
    final end = aEnd.isBefore(bEnd) ? aEnd : bEnd;
    return end.isAfter(start) ? end.difference(start).inSeconds : 0;
  }

  double? _median(List<double> values) {
    if (values.isEmpty) return null;
    values.sort();
    final middle = values.length ~/ 2;
    if (values.length.isOdd) return values[middle];
    return (values[middle - 1] + values[middle]) / 2;
  }
}

class _ActivityEnvelope {
  final DateTime startedAt;
  final DateTime endedAt;
  final int activeSeconds;
  final double peakNoiseScore;

  const _ActivityEnvelope({
    required this.startedAt,
    required this.endedAt,
    required this.activeSeconds,
    required this.peakNoiseScore,
  });

  int get durationSeconds => endedAt.difference(startedAt).inSeconds;

  _ActivityEnvelope copyWith({
    DateTime? endedAt,
    int? activeSeconds,
    double? peakNoiseScore,
  }) {
    return _ActivityEnvelope(
      startedAt: startedAt,
      endedAt: endedAt ?? this.endedAt,
      activeSeconds: activeSeconds ?? this.activeSeconds,
      peakNoiseScore: peakNoiseScore ?? this.peakNoiseScore,
    );
  }
}

class _WindowStats {
  final double validFraction;
  final double belowStartFraction;
  final double belowHoldFraction;

  const _WindowStats({
    required this.validFraction,
    required this.belowStartFraction,
    required this.belowHoldFraction,
  });
}
