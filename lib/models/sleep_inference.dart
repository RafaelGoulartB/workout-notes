enum SleepInferenceStatus { available, insufficientData }

enum SleepInferenceConfidence { low, medium }

enum SleepInferenceEventType {
  transientActivity,
  prolongedActivity,
  awakening,
  finalActivity,
}

class SleepInferenceEvent {
  final SleepInferenceEventType type;
  final DateTime startedAt;
  final DateTime endedAt;
  final int activeSeconds;
  final double peakNoiseScore;
  final SleepInferenceConfidence confidence;
  final String reason;

  const SleepInferenceEvent({
    required this.type,
    required this.startedAt,
    required this.endedAt,
    required this.activeSeconds,
    required this.peakNoiseScore,
    required this.confidence,
    required this.reason,
  });

  int get durationSeconds =>
      endedAt.difference(startedAt).inSeconds.clamp(0, 16 * 60 * 60);
}

class SleepInferenceResult {
  static const algorithmVersion = 'sleep-inference-v1';

  final SleepInferenceStatus status;
  final SleepInferenceConfidence confidence;
  final DateTime? sleepOnsetAt;
  final DateTime? settlingStartedAt;
  final DateTime? settlingEndedAt;
  final int? estimatedSleepSeconds;
  final List<SleepInferenceEvent> events;
  final List<String> blockers;
  final Map<String, num> parameters;

  const SleepInferenceResult({
    required this.status,
    required this.confidence,
    required this.sleepOnsetAt,
    required this.settlingStartedAt,
    required this.settlingEndedAt,
    required this.estimatedSleepSeconds,
    required this.events,
    required this.blockers,
    required this.parameters,
  });

  bool get isAvailable => status == SleepInferenceStatus.available;

  int? get settlingSeconds {
    final start = settlingStartedAt;
    final end = settlingEndedAt;
    if (start == null || end == null) return null;
    return end.difference(start).inSeconds.clamp(0, 16 * 60 * 60);
  }

  List<SleepInferenceEvent> get awakenings => events
      .where((event) => event.type == SleepInferenceEventType.awakening)
      .toList(growable: false);
}
