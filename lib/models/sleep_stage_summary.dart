import 'package:workout_notes/models/sleep_night_timeline.dart';

class SleepStageSummary {
  final DateTime? sleepOnsetAt;
  final DateTime? finalWakeAt;
  final int awakeMinutes;
  final int sleepingMinutes;
  final int deepSleepMinutes;
  final int unknownMinutes;

  /// Sleep minutes spent in stretches with repeated movement (a subset of
  /// [sleepingMinutes] + [deepSleepMinutes]).
  final int restlessSleepMinutes;
  final int snoreMinutes;
  final int sleepLatencyMinutes;
  final int awakeningCount;
  final double sleepEfficiency;
  final double stageConfidence;
  final String algorithmVersion;

  /// Minute-by-minute night for the chart; null without epochs.
  final SleepNightTimeline? timeline;

  const SleepStageSummary({
    required this.sleepOnsetAt,
    required this.finalWakeAt,
    required this.awakeMinutes,
    required this.sleepingMinutes,
    required this.deepSleepMinutes,
    required this.unknownMinutes,
    this.restlessSleepMinutes = 0,
    this.snoreMinutes = 0,
    required this.sleepLatencyMinutes,
    required this.awakeningCount,
    required this.sleepEfficiency,
    required this.stageConfidence,
    required this.algorithmVersion,
    this.timeline,
  });

  int get estimatedSleepMinutes => sleepingMinutes + deepSleepMinutes;
}
