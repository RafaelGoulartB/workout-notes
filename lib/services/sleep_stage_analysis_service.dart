import 'package:workout_notes/models/sleep_stage_epoch.dart';
import 'package:workout_notes/models/sleep_stage_summary.dart';
import 'package:workout_notes/models/sleep_stage_type.dart';
import 'package:workout_notes/services/sleep_wake_engine.dart';

/// Consolidates model-labelled epochs into user-facing nightly metrics.
///
/// This service never infers a stage from noise. It only summarizes labels
/// emitted by a separately validated acoustic model.
class SleepStageAnalysisService {
  static const onsetWindowSeconds = 10 * 60;
  static const onsetRequiredSleepSeconds = 8 * 60;
  static const finalWakeSeconds = 5 * 60;
  static const awakeningSeconds = 60;

  /// A sleep window is restless when, within this many seconds on either
  /// side, at least [restlessMovementWindows] windows carry a sound of the
  /// person moving (not ambient sound, not snoring).
  static const restlessNeighbourhoodSeconds = 5 * 60;
  static const restlessMovementWindows = 5;
  static const movementSeconds = 2.0;

  const SleepStageAnalysisService();

  SleepStageSummary? summarize({
    required DateTime sessionStart,
    required DateTime sessionEnd,
    required List<SleepStageEpoch> epochs,
  }) {
    if (epochs.isEmpty || !sessionEnd.isAfter(sessionStart)) return null;
    final ordered = [...epochs]
      ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    final bedside = ordered.every(
      (epoch) => epoch.source == SleepWakeEngine.source,
    );
    if (!bedside &&
        !ordered.any((epoch) => epoch.stage != SleepStageType.unknown)) {
      return null;
    }

    final onset = bedside
        ? ordered.where((epoch) => epoch.isSleep).firstOrNull?.startedAt
        : _findOnset(ordered, sessionEnd);
    final finalWake = _findFinalWake(
      ordered,
      sessionEnd,
      allowSessionEnd: !bedside,
    );
    var awakeSeconds = 0;
    var sleepingSeconds = 0;
    var deepSeconds = 0;
    var unknownSeconds = 0;
    var confidenceSeconds = 0.0;
    var knownSeconds = 0;

    for (final epoch in ordered) {
      final seconds = epoch.durationSeconds.clamp(1, 3600);
      switch (epoch.stage) {
        case SleepStageType.awake:
          awakeSeconds += seconds;
        case SleepStageType.sleeping:
          sleepingSeconds += seconds;
        case SleepStageType.deep:
          deepSeconds += seconds;
        case SleepStageType.unknown:
          unknownSeconds += seconds;
      }
      if (epoch.stage != SleepStageType.unknown) {
        knownSeconds += seconds;
        confidenceSeconds += epoch.confidence.clamp(0.0, 1.0) * seconds;
      }
    }

    final timeInBedSeconds = sessionEnd.difference(sessionStart).inSeconds;
    // Time without a usable estimate is neither sleep nor wake; efficiency is
    // measured over the time that was actually classified.
    final classifiedSeconds = timeInBedSeconds - unknownSeconds;
    final sleepSeconds = sleepingSeconds + deepSeconds;
    final restlessSeconds = _restlessSleepSeconds(ordered);
    final snoreSeconds = ordered
        .where((e) => e.isSleep && e.snoring)
        .fold<int>(0, (sum, e) => sum + e.durationSeconds.clamp(1, 3600));
    final version = ordered
        .firstWhere(
          (epoch) => epoch.algorithmVersion.isNotEmpty,
          orElse: () => ordered.first,
        )
        .algorithmVersion;
    return SleepStageSummary(
      sleepOnsetAt: onset,
      finalWakeAt: finalWake,
      awakeMinutes: _roundMinutes(awakeSeconds),
      sleepingMinutes: _roundMinutes(sleepingSeconds),
      deepSleepMinutes: _roundMinutes(deepSeconds),
      unknownMinutes: _roundMinutes(unknownSeconds),
      restlessSleepMinutes: _roundMinutes(restlessSeconds),
      snoreMinutes: _roundMinutes(snoreSeconds),
      sleepLatencyMinutes: onset == null
          ? 0
          : onset.difference(sessionStart).inMinutes.clamp(0, 16 * 60),
      awakeningCount: onset == null
          ? 0
          : _countAwakenings(ordered, onset, finalWake ?? sessionEnd),
      sleepEfficiency: classifiedSeconds <= 0
          ? 0
          : (sleepSeconds / classifiedSeconds * 100).clamp(0.0, 100.0),
      stageConfidence: knownSeconds == 0 ? 0 : confidenceSeconds / knownSeconds,
      algorithmVersion: version,
    );
  }

  DateTime? _findOnset(List<SleepStageEpoch> epochs, DateTime sessionEnd) {
    for (final epoch in epochs) {
      if (!epoch.isSleep) continue;
      final windowEnd = epoch.startedAt.add(
        const Duration(seconds: onsetWindowSeconds),
      );
      if (windowEnd.isAfter(sessionEnd)) continue;
      var sleepSeconds = 0;
      for (final candidate in epochs) {
        if (!candidate.isSleep) continue;
        sleepSeconds += _overlapSeconds(
          candidate.startedAt,
          candidate.endedAt,
          epoch.startedAt,
          windowEnd,
        );
      }
      if (sleepSeconds >= onsetRequiredSleepSeconds) return epoch.startedAt;
    }
    return null;
  }

  DateTime? _findFinalWake(
    List<SleepStageEpoch> epochs,
    DateTime sessionEnd, {
    bool allowSessionEnd = true,
  }) {
    var runSeconds = 0;
    DateTime? runStart;
    DateTime? expectedEnd = sessionEnd;
    for (final epoch in epochs.reversed) {
      final closeToPrevious =
          expectedEnd == null ||
          expectedEnd.difference(epoch.endedAt).inSeconds.abs() <= 2;
      if (epoch.stage != SleepStageType.awake || !closeToPrevious) break;
      runSeconds += epoch.durationSeconds.clamp(1, 3600);
      runStart = epoch.startedAt;
      expectedEnd = epoch.startedAt;
    }
    return runSeconds >= finalWakeSeconds
        ? runStart
        : (allowSessionEnd ? sessionEnd : null);
  }

  int _countAwakenings(
    List<SleepStageEpoch> epochs,
    DateTime onset,
    DateTime finalWake,
  ) {
    var count = 0;
    var runSeconds = 0;
    for (final epoch in epochs) {
      if (epoch.startedAt.isBefore(onset) ||
          !epoch.startedAt.isBefore(finalWake)) {
        continue;
      }
      if (epoch.stage == SleepStageType.awake) {
        runSeconds += epoch.durationSeconds.clamp(1, 3600);
      } else if (epoch.stage != SleepStageType.unknown) {
        // Unknown time inside a wake neither ends nor extends it, so a short
        // capture glitch does not split one awakening into two.
        if (runSeconds >= awakeningSeconds) count++;
        runSeconds = 0;
      }
    }
    if (runSeconds >= awakeningSeconds) count++;
    return count;
  }

  int _restlessSleepSeconds(List<SleepStageEpoch> epochs) {
    const reach = Duration(seconds: restlessNeighbourhoodSeconds);
    final moving = [
      for (final e in epochs)
        if (e.movementSeconds >= movementSeconds) e.startedAt,
    ];
    var seconds = 0;
    var lo = 0;
    var hi = 0;
    for (final epoch in epochs) {
      final from = epoch.startedAt.subtract(reach);
      final to = epoch.startedAt.add(reach);
      while (lo < moving.length && moving[lo].isBefore(from)) {
        lo++;
      }
      if (hi < lo) hi = lo;
      while (hi < moving.length && !moving[hi].isAfter(to)) {
        hi++;
      }
      if (epoch.isSleep && hi - lo >= restlessMovementWindows) {
        seconds += epoch.durationSeconds.clamp(1, 3600);
      }
    }
    return seconds;
  }

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

  int _roundMinutes(int seconds) => (seconds / 60).round();
}
