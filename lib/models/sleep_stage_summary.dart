class SleepStageSummary {
  final DateTime? sleepOnsetAt;
  final DateTime? finalWakeAt;
  final int awakeMinutes;
  final int sleepingMinutes;
  final int deepSleepMinutes;
  final int unknownMinutes;
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
    required this.sleepLatencyMinutes,
    required this.awakeningCount,
    required this.sleepEfficiency,
    required this.stageConfidence,
    required this.algorithmVersion,
  });

  int get estimatedSleepMinutes => sleepingMinutes + deepSleepMinutes;
}
