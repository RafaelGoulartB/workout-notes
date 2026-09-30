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
  });

  int get estimatedSleepMinutes => sleepingMinutes + deepSleepMinutes;
}
